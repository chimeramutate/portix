//! End-to-end checks against an in-process russh server: jump hosts,
//! ssh-agent authentication and SFTP (served by the system's OpenSSH
//! `sftp-server`) over real SSH handshakes on loopback.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};

use russh::keys::{Algorithm, PrivateKey};
use russh::server::{self, Auth, Msg, Session};
use russh::{Channel, ChannelId};
use tokio::net::{TcpListener, TcpStream, UnixListener};

use super::*;

struct TestServer {
    forwards: Arc<AtomicUsize>,
    /// Folder the `sftp` subsystem starts in; None refuses the subsystem.
    sftp_root: Option<PathBuf>,
    channels: HashMap<ChannelId, Channel<Msg>>,
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
        channel: Channel<Msg>,
        _: &mut Session,
    ) -> std::result::Result<bool, Self::Error> {
        self.channels.insert(channel.id(), channel);
        Ok(true)
    }

    async fn subsystem_request(
        &mut self,
        id: ChannelId,
        name: &str,
        session: &mut Session,
    ) -> std::result::Result<(), Self::Error> {
        let (Some(root), Some(channel), "sftp") =
            (self.sftp_root.clone(), self.channels.remove(&id), name)
        else {
            return Ok(session.channel_failure(id)?);
        };
        let mut server = tokio::process::Command::new(SFTP_SERVER)
            .current_dir(root)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .kill_on_drop(true)
            .spawn()?;
        session.channel_success(id)?;
        tokio::spawn(async move {
            let (mut from_client, mut to_client) = tokio::io::split(channel.into_stream());
            let mut stdin = server.stdin.take().unwrap();
            let mut stdout = server.stdout.take().unwrap();
            tokio::select! {
                _ = tokio::io::copy(&mut from_client, &mut stdin) => {}
                _ = tokio::io::copy(&mut stdout, &mut to_client) => {}
            }
            let _ = server.kill().await;
        });
        Ok(())
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

const SFTP_SERVER: &str = "/usr/libexec/sftp-server";

/// Starts a server on 127.0.0.1 and returns its port and host key.
async fn start_server(forwards: Arc<AtomicUsize>) -> (u16, PrivateKey) {
    start_server_with(forwards, None).await
}

async fn start_server_with(
    forwards: Arc<AtomicUsize>,
    sftp_root: Option<PathBuf>,
) -> (u16, PrivateKey) {
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
                sftp_root: sftp_root.clone(),
                channels: HashMap::new(),
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

mod sftp {
    use std::os::unix::fs::PermissionsExt;

    use super::*;
    use crate::domain::sftp::TransferProgress;
    use crate::infrastructure::sftp_client::{PART_SUFFIX, SftpConnection};

    /// An SFTP connection whose login folder is [root].
    async fn open(root: &Path, known_hosts: &Path) -> SftpConnection {
        let (port, key) = start_server_with(Arc::default(), Some(root.to_path_buf())).await;
        trust(known_hosts, port, &key);
        let ssh = connect_with_known_hosts(&profile(port), known_hosts)
            .await
            .unwrap();
        SftpConnection::over(ssh).await.unwrap()
    }

    fn data(len: usize) -> Vec<u8> {
        (0..len).map(|i| (i % 251) as u8).collect()
    }

    #[tokio::test]
    async fn file_operations_round_trip() {
        if !Path::new(SFTP_SERVER).exists() {
            return eprintln!("skipped: no {SFTP_SERVER}");
        }
        let root = tempfile::tempdir().unwrap();
        let root_path = root.path().canonicalize().unwrap();
        let sftp = open(&root_path, &root.path().join("known_hosts")).await;

        assert_eq!(
            sftp.resolve("~").await.unwrap(),
            root_path.to_string_lossy()
        );
        sftp.create_dir("~/docs").await.unwrap();
        sftp.write("docs/a.txt", b"hello").await.unwrap();
        sftp.create_file("~/empty").await.unwrap();
        assert!(sftp.create_file("~/empty").await.is_err(), "never clobbers");
        sftp.chmod("docs/a.txt", 0o750).await.unwrap();
        sftp.copy("docs", "docs-copy").await.unwrap();
        sftp.rename("docs-copy/a.txt", "docs-copy/b.txt")
            .await
            .unwrap();

        let names: Vec<_> = sftp
            .list("~")
            .await
            .unwrap()
            .into_iter()
            .map(|e| (e.name, e.is_directory))
            .collect();
        assert_eq!(
            names,
            [
                ("docs".into(), true),
                ("docs-copy".into(), true),
                ("empty".into(), false),
                ("known_hosts".into(), false)
            ]
        );
        let copied = &sftp.list("docs-copy").await.unwrap()[0];
        assert_eq!(
            (copied.name.as_str(), copied.size_bytes, copied.mode),
            ("b.txt", 5, 0o750)
        );
        assert_eq!(sftp.read("~/docs-copy/b.txt").await.unwrap(), b"hello");

        sftp.remove("docs-copy").await.unwrap();
        assert!(!root_path.join("docs-copy").exists());
        assert!(sftp.remove("/").await.is_err());
    }

    #[tokio::test]
    async fn interrupted_download_resumes_from_the_part_file() {
        if !Path::new(SFTP_SERVER).exists() {
            return eprintln!("skipped: no {SFTP_SERVER}");
        }
        let root = tempfile::tempdir().unwrap();
        let content = data(1_000_000);
        std::fs::write(root.path().join("big.bin"), &content).unwrap();
        let sftp = open(root.path(), &root.path().join("known_hosts")).await;
        let local = root.path().join("local.bin");
        let part = root.path().join(format!("local.bin{PART_SUFFIX}"));

        // Cancel after the first chunk: the part file stays behind.
        let mut chunks = 0;
        let cancelled = sftp
            .download("big.bin", &local, |_| {
                chunks += 1;
                chunks < 3
            })
            .await;
        assert!(matches!(cancelled, Err(PortixError::TransferCancelled)));
        let kept = std::fs::metadata(&part).unwrap().len();
        assert!(kept > 0 && kept < content.len() as u64);

        let mut first = None;
        sftp.download("big.bin", &local, |p| {
            first.get_or_insert(p);
            true
        })
        .await
        .unwrap();
        assert_eq!(
            first,
            Some(TransferProgress {
                done: kept,
                total: content.len() as u64
            })
        );
        assert_eq!(std::fs::read(&local).unwrap(), content);
        assert!(!part.exists());
    }

    #[tokio::test]
    async fn interrupted_upload_resumes_and_keeps_the_replaced_files_mode() {
        if !Path::new(SFTP_SERVER).exists() {
            return eprintln!("skipped: no {SFTP_SERVER}");
        }
        let root = tempfile::tempdir().unwrap();
        let remote_dir = root.path().join("remote");
        std::fs::create_dir(&remote_dir).unwrap();
        let target = remote_dir.join("run.sh");
        std::fs::write(&target, b"old").unwrap();
        std::fs::set_permissions(&target, std::fs::Permissions::from_mode(0o755)).unwrap();
        let content = data(700_000);
        let local = root.path().join("run.sh");
        std::fs::write(&local, &content).unwrap();
        let sftp = open(&remote_dir, &root.path().join("known_hosts")).await;

        let mut chunks = 0;
        let cancelled = sftp
            .upload(&local, "~/run.sh", |_| {
                chunks += 1;
                chunks < 2
            })
            .await;
        assert!(matches!(cancelled, Err(PortixError::TransferCancelled)));
        assert_eq!(
            std::fs::read(&target).unwrap(),
            b"old",
            "untouched until complete"
        );
        let kept = std::fs::metadata(remote_dir.join(format!("run.sh{PART_SUFFIX}")))
            .unwrap()
            .len();

        let mut first = None;
        sftp.upload(&local, "~/run.sh", |p| {
            first.get_or_insert(p);
            true
        })
        .await
        .unwrap();
        assert_eq!(first.unwrap().done, kept);
        assert_eq!(std::fs::read(&target).unwrap(), content);
        let mode = std::fs::metadata(&target).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o755);
        assert!(!remote_dir.join(format!("run.sh{PART_SUFFIX}")).exists());
    }
}
