//! End-to-end checks against an in-process russh server: jump hosts and
//! ssh-agent authentication over real SSH handshakes on loopback.

use std::sync::atomic::{AtomicUsize, Ordering};

use russh::Channel;
use russh::keys::{Algorithm, PrivateKey};
use russh::server::{self, Auth, Msg, Session};
use tokio::net::{TcpListener, TcpStream, UnixListener};

use super::*;

#[derive(Clone)]
struct TestServer {
    forwards: Arc<AtomicUsize>,
}

impl server::Handler for TestServer {
    type Error = russh::Error;

    async fn auth_password(
        &mut self,
        _: &str,
        password: &str,
    ) -> std::result::Result<Auth, Self::Error> {
        Ok(if password == "pw" {
            Auth::Accept
        } else {
            Auth::reject()
        })
    }

    async fn auth_publickey(
        &mut self,
        _: &str,
        _: &russh::keys::ssh_key::PublicKey,
    ) -> std::result::Result<Auth, Self::Error> {
        // Reached only after the client proved it holds the key.
        Ok(Auth::Accept)
    }

    async fn channel_open_session(
        &mut self,
        _: Channel<Msg>,
        _: &mut Session,
    ) -> std::result::Result<bool, Self::Error> {
        Ok(true)
    }

    async fn channel_open_direct_tcpip(
        &mut self,
        channel: Channel<Msg>,
        host: &str,
        port: u32,
        _: &str,
        _: u32,
        _: &mut Session,
    ) -> std::result::Result<bool, Self::Error> {
        let mut target = TcpStream::connect((host, port as u16)).await?;
        self.forwards.fetch_add(1, Ordering::SeqCst);
        tokio::spawn(async move {
            let mut stream = channel.into_stream();
            let _ = tokio::io::copy_bidirectional(&mut stream, &mut target).await;
        });
        Ok(true)
    }
}

/// Starts a server on 127.0.0.1 and returns its port and host key.
async fn start_server(forwards: Arc<AtomicUsize>) -> (u16, PrivateKey) {
    let key = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
    let config = Arc::new(server::Config {
        keys: vec![key.clone()],
        auth_rejection_time: Duration::from_millis(1),
        ..Default::default()
    });
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    tokio::spawn(async move {
        while let Ok((socket, _)) = listener.accept().await {
            let handler = TestServer {
                forwards: forwards.clone(),
            };
            let config = config.clone();
            tokio::spawn(async move {
                if let Ok(session) = server::run_stream(config, socket, handler).await {
                    let _ = session.await;
                }
            });
        }
    });
    (port, key)
}

fn trust(known_hosts: &Path, port: u16, key: &PrivateKey) {
    russh::keys::known_hosts::learn_known_hosts_path(
        "127.0.0.1",
        port,
        key.public_key(),
        known_hosts,
    )
    .unwrap();
}

fn profile(port: u16) -> SshProfile {
    SshProfile {
        id: format!("p{port}"),
        name: format!("p{port}"),
        host: "127.0.0.1".to_owned(),
        port,
        username: "u".to_owned(),
        password: Some("pw".to_owned()),
        private_key_path: None,
        key_passphrase: None,
        jump_host: None,
    }
}

#[tokio::test]
async fn connects_to_the_target_through_the_jump_host() {
    let dir = tempfile::tempdir().unwrap();
    let known_hosts = dir.path().join("known_hosts");
    let jump_forwards = Arc::new(AtomicUsize::new(0));
    let (jump_port, jump_key) = start_server(jump_forwards.clone()).await;
    let (target_port, target_key) = start_server(Arc::default()).await;
    trust(&known_hosts, jump_port, &jump_key);
    trust(&known_hosts, target_port, &target_key);

    let mut target = profile(target_port);
    target.jump_host = Some(Box::new(profile(jump_port)));
    let session = connect_with_known_hosts(&target, &known_hosts)
        .await
        .unwrap();

    assert_eq!(
        jump_forwards.load(Ordering::SeqCst),
        1,
        "went through the jump host"
    );
    let channel = session.channel_open_session().await.unwrap();
    channel.close().await.unwrap();
}

#[tokio::test]
async fn target_host_key_is_still_verified_behind_a_jump_host() {
    let dir = tempfile::tempdir().unwrap();
    let known_hosts = dir.path().join("known_hosts");
    let (jump_port, jump_key) = start_server(Arc::default()).await;
    let (target_port, _) = start_server(Arc::default()).await;
    trust(&known_hosts, jump_port, &jump_key);

    let mut target = profile(target_port);
    target.jump_host = Some(Box::new(profile(jump_port)));
    let error = connect_with_known_hosts(&target, &known_hosts)
        .await
        .err()
        .unwrap();

    assert!(matches!(error, PortixError::HostKeyUnknown { port, .. } if port == target_port));
}

#[tokio::test]
async fn authenticates_with_a_key_held_by_the_agent() {
    let dir = tempfile::tempdir().unwrap();
    let known_hosts = dir.path().join("known_hosts");
    let (port, key) = start_server(Arc::default()).await;
    trust(&known_hosts, port, &key);

    let socket = dir.path().join("agent.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let incoming = futures::stream::unfold(listener, |listener| async {
        Some((listener.accept().await.map(|(stream, _)| stream), listener))
    });
    tokio::spawn(russh::keys::agent::server::serve(Box::pin(incoming), ()));
    let mut agent = AgentClient::connect_uds(&socket).await.unwrap();

    let handler = Client {
        host: "127.0.0.1".to_owned(),
        port,
        known_hosts: known_hosts.clone(),
        _jump: None,
    };
    let mut session = client::connect(Arc::default(), ("127.0.0.1", port), handler)
        .await
        .unwrap();

    let empty = authenticate_with_agent(&mut session, "u", &mut agent).await;
    assert!(
        matches!(empty, Err(PortixError::SshAgent(_))),
        "no keys loaded yet"
    );

    let user_key = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
    agent.add_identity(&user_key, &[]).await.unwrap();
    assert!(
        authenticate_with_agent(&mut session, "u", &mut agent)
            .await
            .unwrap()
    );
}
