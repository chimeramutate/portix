//! End-to-end checks against an in-process russh server: jump hosts,
//! ssh-agent authentication and SFTP (served by the system's OpenSSH
//! `sftp-server`) over real SSH handshakes on loopback.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};

use russh::keys::{Algorithm, PrivateKey};
use russh::server::{self, Auth, ChannelOpenHandle, Msg, Session};
use russh::{Channel, ChannelId};
use tokio::net::{TcpListener, TcpStream, UnixListener};

use super::*;

struct TestServer {
    forwards: Arc<AtomicUsize>,
    /// Folder the `sftp` subsystem starts in; None refuses the subsystem.
    sftp_root: Option<PathBuf>,
    channels: HashMap<ChannelId, Channel<Msg>>,
    /// Keyboard-interactive rounds answered so far (password, then OTP).
    kbd_step: u8,
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

    /// PAM-like: "Password:" (kbd-pw), then "Verification code:" (123456).
    async fn auth_keyboard_interactive<'a>(
        &'a mut self,
        _: &str,
        _: &str,
        response: Option<server::Response<'a>>,
    ) -> std::result::Result<Auth, Self::Error> {
        let answer = response.and_then(|mut r| r.next());
        let expected: &[u8] = match self.kbd_step {
            0 => b"",
            1 => b"kbd-pw",
            _ => b"123456",
        };
        if self.kbd_step > 0 && answer.as_deref() != Some(expected) {
            return Ok(Auth::reject());
        }
        self.kbd_step += 1;
        let prompt = match self.kbd_step {
            1 => "Password: ",
            2 => "Verification code: ",
            _ => return Ok(Auth::Accept),
        };
        Ok(Auth::Partial {
            name: "".into(),
            instructions: "".into(),
            prompts: vec![(prompt.into(), false)].into(),
        })
    }

    /// `ssh -A`: open an agent channel back to the client right away and
    /// record how many keys the forwarded agent lists.
    async fn agent_request(
        &mut self,
        _: ChannelId,
        session: &mut Session,
    ) -> std::result::Result<bool, Self::Error> {
        let handle = session.handle();
        tokio::spawn(async move {
            let Ok(channel) = handle.channel_open_agent().await else {
                return;
            };
            let mut agent = AgentClient::connect(channel.into_stream());
            if let Ok(keys) = agent.request_identities().await {
                FORWARDED_AGENT_KEYS.store(keys.len() + 1, Ordering::SeqCst);
            }
        });
        Ok(true)
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
        reply: ChannelOpenHandle,
        _: &mut Session,
    ) -> std::result::Result<(), Self::Error> {
        self.channels.insert(channel.id(), channel);
        reply.accept().await;
        Ok(())
    }

    /// `cat`: echoes stdin back until the client's EOF.
    async fn exec_request(
        &mut self,
        id: ChannelId,
        command: &[u8],
        session: &mut Session,
    ) -> std::result::Result<(), Self::Error> {
        let (Some(channel), b"cat") = (self.channels.remove(&id), command) else {
            return Ok(session.channel_failure(id)?);
        };
        session.channel_success(id)?;
        tokio::spawn(async move {
            use tokio::io::AsyncWriteExt;
            let (mut from_client, mut to_client) = tokio::io::split(channel.into_stream());
            let _ = tokio::io::copy(&mut from_client, &mut to_client).await;
            let _ = to_client.shutdown().await;
        });
        Ok(())
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
        reply: ChannelOpenHandle,
        _: &mut Session,
    ) -> std::result::Result<(), Self::Error> {
        let mut target = TcpStream::connect((host, port as u16)).await?;
        reply.accept().await;
        self.forwards.fetch_add(1, Ordering::SeqCst);
        tokio::spawn(async move {
            let mut stream = channel.into_stream();
            let _ = tokio::io::copy_bidirectional(&mut stream, &mut target).await;
        });
        Ok(())
    }

    /// `ssh -R`: listens on loopback and opens a forwarded-tcpip channel
    /// back to the client for each connection.
    async fn tcpip_forward(
        &mut self,
        address: &str,
        port: &mut u32,
        session: &mut Session,
    ) -> std::result::Result<bool, Self::Error> {
        let listener = TcpListener::bind(("127.0.0.1", *port as u16)).await?;
        let bound = listener.local_addr()?.port();
        *port = bound.into();
        let handle = session.handle();
        let address = address.to_owned();
        tokio::spawn(async move {
            while let Ok((mut socket, peer)) = listener.accept().await {
                let Ok(channel) = handle
                    .channel_open_forwarded_tcpip(
                        address.clone(),
                        bound.into(),
                        peer.ip().to_string(),
                        peer.port().into(),
                    )
                    .await
                else {
                    return;
                };
                tokio::spawn(async move {
                    let mut stream = channel.into_stream();
                    let _ = tokio::io::copy_bidirectional(&mut socket, &mut stream).await;
                });
            }
        });
        Ok(true)
    }
}

/// Keys seen through a forwarded agent, plus one (0 = never reached).
static FORWARDED_AGENT_KEYS: AtomicUsize = AtomicUsize::new(0);

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
                kbd_step: 0,
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
        forward_agent: false,
        command: None,
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
async fn keyboard_interactive_fills_the_password_and_asks_for_the_code() {
    let dir = tempfile::tempdir().unwrap();
    let known_hosts = dir.path().join("known_hosts");
    let (port, key) = start_server(Arc::default()).await;
    trust(&known_hosts, port, &key);
    let mut target = profile(port);
    // Refused by password auth, so the server falls back to its PAM prompts.
    target.password = Some("kbd-pw".to_owned());

    let error = connect_with_known_hosts(&target, &known_hosts)
        .await
        .err()
        .unwrap();
    assert!(matches!(
        error,
        PortixError::KeyboardInteractiveRequired { .. }
    ));
    let pending = keyboard_interactive::pending_prompts("127.0.0.1", port).unwrap();
    assert_eq!(
        pending.prompts,
        vec![("Verification code: ".to_owned(), false)]
    );

    keyboard_interactive::answer_pending("127.0.0.1", port, vec!["000000".to_owned()]);
    let error = connect_with_known_hosts(&target, &known_hosts)
        .await
        .err()
        .unwrap();
    assert!(matches!(error, PortixError::AuthenticationFailed));

    keyboard_interactive::answer_pending("127.0.0.1", port, vec!["123456".to_owned()]);
    connect_with_known_hosts(&target, &known_hosts)
        .await
        .unwrap();
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
        forward_to: None,
        forward_agent: false,
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

#[tokio::test]
async fn forwards_the_local_agent_to_the_server_when_enabled() {
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
    let user_key = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
    AgentClient::connect_uds(&socket)
        .await
        .unwrap()
        .add_identity(&user_key, &[])
        .await
        .unwrap();
    // SAFETY: no other test reads SSH_AUTH_SOCK (their profiles use passwords).
    unsafe { env::set_var("SSH_AUTH_SOCK", &socket) };

    let mut target = profile(port);
    target.forward_agent = true;
    let session = connect_with_known_hosts(&target, &known_hosts)
        .await
        .unwrap();
    let channel = session.channel_open_session().await.unwrap();
    channel.agent_forward(false).await.unwrap();

    for _ in 0..100 {
        if FORWARDED_AGENT_KEYS.load(Ordering::SeqCst) > 0 {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    assert_eq!(FORWARDED_AGENT_KEYS.load(Ordering::SeqCst), 2, "one key");
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

#[tokio::test]
async fn socks_proxy_reaches_a_target_through_the_ssh_server() {
    use crate::infrastructure::port_forward::{Destination, serve};
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    // Target: echoes one message back.
    let target = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let target_port = target.local_addr().unwrap().port();
    tokio::spawn(async move {
        let (mut socket, _) = target.accept().await.unwrap();
        let mut buf = [0u8; 5];
        socket.read_exact(&mut buf).await.unwrap();
        socket.write_all(&buf).await.unwrap();
    });

    let dir = tempfile::tempdir().unwrap();
    let known_hosts = dir.path().join("known_hosts");
    let forwards = Arc::new(AtomicUsize::new(0));
    let (port, key) = start_server(forwards.clone()).await;
    trust(&known_hosts, port, &key);
    let ssh = connect_with_known_hosts(&profile(port), &known_hosts)
        .await
        .unwrap();
    let proxy = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let proxy_port = proxy.local_addr().unwrap().port();
    tokio::spawn(serve(proxy, Arc::new(ssh), Destination::Socks));

    let mut client = TcpStream::connect(("127.0.0.1", proxy_port)).await.unwrap();
    client.write_all(&[5, 1, 0]).await.unwrap();
    let mut choice = [0u8; 2];
    client.read_exact(&mut choice).await.unwrap();
    assert_eq!(choice, [5, 0]);
    let mut request = vec![5, 1, 0, 3, 9];
    request.extend_from_slice(b"127.0.0.1");
    request.extend_from_slice(&target_port.to_be_bytes());
    client.write_all(&request).await.unwrap();
    let mut reply = [0u8; 10];
    client.read_exact(&mut reply).await.unwrap();
    assert_eq!(reply[1], 0, "SOCKS succeeded");

    client.write_all(b"hello").await.unwrap();
    let mut echoed = [0u8; 5];
    client.read_exact(&mut echoed).await.unwrap();
    assert_eq!(&echoed, b"hello");
    assert_eq!(forwards.load(Ordering::SeqCst), 1, "went through SSH");
}

#[tokio::test]
async fn exec_input_reaches_the_command_on_stdin() {
    let dir = tempfile::tempdir().unwrap();
    let known_hosts = dir.path().join("known_hosts");
    let (port, key) = start_server(Arc::new(AtomicUsize::new(0))).await;
    trust(&known_hosts, port, &key);
    let ssh = connect_forwarding_to(&profile(port), &known_hosts, None)
        .await
        .unwrap();

    let manifest = "kind: Secret\ndata:\n  password: \"it's\"\n";
    let output = run_exec(&ssh, "cat".to_owned(), Some(manifest.to_owned()))
        .await
        .unwrap();

    assert_eq!(output, manifest);
}

#[tokio::test]
async fn remote_forward_brings_server_connections_back_to_a_local_port() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    // Local service the server side should reach: echoes one message.
    let local = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let local_port = local.local_addr().unwrap().port();
    tokio::spawn(async move {
        let (mut socket, _) = local.accept().await.unwrap();
        let mut buf = [0u8; 5];
        socket.read_exact(&mut buf).await.unwrap();
        socket.write_all(&buf).await.unwrap();
    });

    let dir = tempfile::tempdir().unwrap();
    let known_hosts = dir.path().join("known_hosts");
    let (port, key) = start_server(Arc::new(AtomicUsize::new(0))).await;
    trust(&known_hosts, port, &key);
    let ssh = connect_forwarding_to(
        &profile(port),
        &known_hosts,
        Some(("127.0.0.1".to_owned(), local_port)),
    )
    .await
    .unwrap();
    let server_port = ssh.tcpip_forward("localhost", 0).await.unwrap();
    assert_ne!(server_port, 0, "server reports the port it picked");

    // A client on the server's side connects to the forwarded port.
    let mut client = TcpStream::connect(("127.0.0.1", server_port as u16))
        .await
        .unwrap();
    client.write_all(b"hello").await.unwrap();
    let mut echoed = [0u8; 5];
    client.read_exact(&mut echoed).await.unwrap();
    assert_eq!(&echoed, b"hello");
}
