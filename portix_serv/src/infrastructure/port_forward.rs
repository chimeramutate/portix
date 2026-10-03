//! Port forwarding over SSH: local forwards (`ssh -L`) and a SOCKS5 proxy
//! (`ssh -D`). Each one owns a dedicated SSH connection, so it keeps running
//! when the terminal tab is closed.

use std::collections::HashMap;
use std::net::{Ipv4Addr, Ipv6Addr, SocketAddr};
use std::sync::{Arc, LazyLock, Mutex};
use std::time::Duration;

use russh::client;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::{AbortHandle, JoinSet};
use uuid::Uuid;

use crate::domain::errors::{PortixError, Result};
use crate::domain::profile::SshProfile;
use crate::infrastructure::ssh_client::{Client, connect_and_authenticate_profile};

/// An active tunnel listening on `127.0.0.1:local_port`: either to
/// `remote_host:remote_port`, or, when [socks] is set, a SOCKS5 proxy whose
/// clients pick the destination (remote_host is empty, remote_port 0).
#[derive(Clone, Debug)]
pub struct LocalForward {
    pub id: String,
    pub profile_id: String,
    pub local_port: u16,
    pub remote_host: String,
    pub remote_port: u16,
    pub socks: bool,
}

/// Where a tunnel's connections go.
#[derive(Clone, Debug)]
pub(crate) enum Destination {
    Fixed { host: String, port: u16 },
    Socks,
}

static ACTIVE: LazyLock<Mutex<HashMap<String, (LocalForward, AbortHandle)>>> =
    LazyLock::new(Default::default);

/// How often an idle tunnel checks that its SSH connection is still alive.
const LIVENESS_INTERVAL: Duration = Duration::from_secs(5);

/// Binds 127.0.0.1:`local_port` (0 = any free port), connects to `profile`,
/// and forwards to `remote_host:remote_port` until [`stop_local_forward`]
/// or the SSH connection drops. Returns once the tunnel is ready.
pub async fn start_local_forward(
    profile: SshProfile,
    local_port: u16,
    remote_host: String,
    remote_port: u16,
) -> Result<LocalForward> {
    start(
        profile,
        local_port,
        Destination::Fixed {
            host: remote_host,
            port: remote_port,
        },
    )
    .await
}

/// Like [`start_local_forward`], but serves a SOCKS5 proxy: each client
/// connection says where it wants to go, and the server connects there.
pub async fn start_socks_proxy(profile: SshProfile, local_port: u16) -> Result<LocalForward> {
    start(profile, local_port, Destination::Socks).await
}

async fn start(
    profile: SshProfile,
    local_port: u16,
    destination: Destination,
) -> Result<LocalForward> {
    // Bind first: a busy port should fail before spending an SSH handshake.
    let listener = TcpListener::bind(("127.0.0.1", local_port))
        .await
        .map_err(|e| PortixError::InvalidRequest(format!("cannot listen on port {local_port}: {e}")))?;
    let local_port = listener.local_addr()?.port();
    let handle = Arc::new(connect_and_authenticate_profile(&profile).await?);

    let (remote_host, remote_port) = match &destination {
        Destination::Fixed { host, port } => (host.clone(), *port),
        Destination::Socks => (String::new(), 0),
    };
    let forward = LocalForward {
        id: Uuid::new_v4().to_string(),
        profile_id: profile.id.clone(),
        local_port,
        remote_host,
        remote_port,
        socks: matches!(destination, Destination::Socks),
    };
    let id = forward.id.clone();
    // Hold the lock across spawn so the task can't remove itself before it
    // is registered.
    let mut active = ACTIVE.lock().unwrap();
    let task = tokio::spawn(async move {
        serve(listener, handle, destination).await;
        ACTIVE.lock().unwrap().remove(&id);
    });
    active.insert(forward.id.clone(), (forward.clone(), task.abort_handle()));
    Ok(forward)
}

/// Accepts connections until the SSH connection closes. Dropping the
/// returned future (task abort) closes every open connection too.
pub(crate) async fn serve(
    listener: TcpListener,
    handle: Arc<client::Handle<Client>>,
    destination: Destination,
) {
    let mut connections = JoinSet::new();
    let mut liveness = tokio::time::interval(LIVENESS_INTERVAL);
    loop {
        tokio::select! {
            accepted = listener.accept() => {
                let Ok((socket, peer)) = accepted else { continue };
                connections.spawn(forward_connection(socket, peer, handle.clone(), destination.clone()));
            }
            _ = liveness.tick() => {
                if handle.is_closed() { return; }
            }
            // Reap finished connections so the set doesn't grow forever.
            Some(_) = connections.join_next(), if !connections.is_empty() => {}
        }
    }
}

async fn forward_connection(
    mut socket: TcpStream,
    peer: SocketAddr,
    handle: Arc<client::Handle<Client>>,
    destination: Destination,
) {
    let socks = matches!(destination, Destination::Socks);
    let (host, port) = match destination {
        Destination::Fixed { host, port } => (host, port),
        Destination::Socks => match socks5_request(&mut socket).await {
            Ok(target) => target,
            Err(_) => return,
        },
    };
    let opened = handle
        .channel_open_direct_tcpip(host, port.into(), peer.ip().to_string(), peer.port().into())
        .await;
    let channel = match opened {
        Ok(channel) => channel,
        Err(_) => {
            if socks {
                let _ = socks5_reply(&mut socket, SOCKS_CONNECTION_REFUSED).await;
            }
            return;
        }
    };
    if socks && socks5_reply(&mut socket, SOCKS_SUCCEEDED).await.is_err() {
        return;
    }
    let mut stream = channel.into_stream();
    let _ = tokio::io::copy_bidirectional(&mut socket, &mut stream).await;
}

const SOCKS_SUCCEEDED: u8 = 0;
const SOCKS_CONNECTION_REFUSED: u8 = 5;
const SOCKS_COMMAND_NOT_SUPPORTED: u8 = 7;
const SOCKS_ADDRESS_NOT_SUPPORTED: u8 = 8;

fn socks_error(message: &str) -> std::io::Error {
    std::io::Error::new(std::io::ErrorKind::InvalidData, message.to_owned())
}

/// Reads a SOCKS5 greeting and CONNECT request (RFC 1928, no
/// authentication) and returns the requested host and port. Domain names
/// are passed through unresolved, so the server resolves them (like
/// `ssh -D` with `socks5h://`).
///
/// ponytail: SOCKS4, username/password auth, BIND and UDP are not
/// supported; clients that need them get a protocol error reply.
async fn socks5_request<S: AsyncRead + AsyncWrite + Unpin>(
    socket: &mut S,
) -> std::io::Result<(String, u16)> {
    let mut greeting = [0u8; 2];
    socket.read_exact(&mut greeting).await?;
    if greeting[0] != 5 {
        return Err(socks_error("not a SOCKS5 client"));
    }
    let mut methods = vec![0u8; greeting[1].into()];
    socket.read_exact(&mut methods).await?;
    if !methods.contains(&0) {
        socket.write_all(&[5, 0xFF]).await?;
        return Err(socks_error("client requires authentication"));
    }
    socket.write_all(&[5, 0]).await?;

    // VER CMD RSV ATYP
    let mut request = [0u8; 4];
    socket.read_exact(&mut request).await?;
    if request[1] != 1 {
        socks5_reply(socket, SOCKS_COMMAND_NOT_SUPPORTED).await?;
        return Err(socks_error("only CONNECT is supported"));
    }
    let host = match request[3] {
        1 => {
            let mut ip = [0u8; 4];
            socket.read_exact(&mut ip).await?;
            Ipv4Addr::from(ip).to_string()
        }
        3 => {
            let mut len = [0u8; 1];
            socket.read_exact(&mut len).await?;
            let mut name = vec![0u8; len[0].into()];
            socket.read_exact(&mut name).await?;
            String::from_utf8(name).map_err(|_| socks_error("invalid domain name"))?
        }
        4 => {
            let mut ip = [0u8; 16];
            socket.read_exact(&mut ip).await?;
            Ipv6Addr::from(ip).to_string()
        }
        _ => {
            socks5_reply(socket, SOCKS_ADDRESS_NOT_SUPPORTED).await?;
            return Err(socks_error("unknown address type"));
        }
    };
    let mut port = [0u8; 2];
    socket.read_exact(&mut port).await?;
    Ok((host, u16::from_be_bytes(port)))
}

/// A reply with the bound address left as 0.0.0.0:0, which clients ignore.
async fn socks5_reply<S: AsyncWrite + Unpin>(socket: &mut S, code: u8) -> std::io::Result<()> {
    socket.write_all(&[5, code, 0, 1, 0, 0, 0, 0, 0, 0]).await
}

/// Stops a tunnel and closes its listener and connections. Unknown ids are
/// ignored (the tunnel may already have ended on its own).
pub fn stop_local_forward(id: &str) {
    if let Some((_, task)) = ACTIVE.lock().unwrap().remove(id) {
        task.abort();
    }
}

/// Tunnels that are still running.
pub fn active_local_forwards() -> Vec<LocalForward> {
    ACTIVE
        .lock()
        .unwrap()
        .values()
        .map(|(forward, _)| forward.clone())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn profile() -> SshProfile {
        SshProfile {
            id: "p".into(),
            name: "p".into(),
            // Never reached: the bind must fail first.
            host: "203.0.113.1".into(),
            port: 22,
            username: "u".into(),
            password: Some("x".into()),
            private_key_path: None,
            key_passphrase: None,
            jump_host: None,
        }
    }

    #[tokio::test]
    async fn busy_local_port_fails_before_connecting() {
        let taken = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let port = taken.local_addr().unwrap().port();
        let err = start_local_forward(profile(), port, "db".into(), 5432)
            .await
            .unwrap_err();
        assert!(err.to_string().contains(&format!("port {port}")), "{err}");
        assert!(active_local_forwards().is_empty());
    }

    #[test]
    fn stopping_an_unknown_tunnel_is_a_no_op() {
        stop_local_forward("missing");
    }

    /// Runs [socks5_request] against [client_bytes]; returns its result and
    /// what the proxy wrote back.
    async fn socks(client_bytes: &[u8]) -> (std::io::Result<(String, u16)>, Vec<u8>) {
        let (mut client, mut proxy) = tokio::io::duplex(1024);
        client.write_all(client_bytes).await.unwrap();
        let result = socks5_request(&mut proxy).await;
        drop(proxy);
        let mut written = Vec::new();
        client.read_to_end(&mut written).await.unwrap();
        (result, written)
    }

    #[tokio::test]
    async fn socks5_connect_requests_for_every_address_type() {
        let mut domain = vec![5, 1, 0, 5, 1, 0, 3, 11];
        domain.extend_from_slice(b"example.com");
        domain.extend_from_slice(&443u16.to_be_bytes());
        let (target, reply) = socks(&domain).await;
        assert_eq!(target.unwrap(), ("example.com".into(), 443));
        assert_eq!(reply, [5, 0], "accepted with no authentication");

        let ipv4 = [5, 1, 0, 5, 1, 0, 1, 10, 0, 0, 5, 0x15, 0x38];
        assert_eq!(socks(&ipv4).await.0.unwrap(), ("10.0.0.5".into(), 5432));

        let mut ipv6 = vec![5, 1, 0, 5, 1, 0, 4];
        ipv6.extend_from_slice(&Ipv6Addr::LOCALHOST.octets());
        ipv6.extend_from_slice(&22u16.to_be_bytes());
        assert_eq!(socks(&ipv6).await.0.unwrap(), ("::1".into(), 22));
    }

    #[tokio::test]
    async fn socks5_refuses_what_it_does_not_support() {
        // Username/password authentication only.
        let (result, reply) = socks(&[5, 1, 2]).await;
        assert!(result.is_err());
        assert_eq!(reply, [5, 0xFF]);

        // BIND instead of CONNECT.
        let (result, reply) = socks(&[5, 1, 0, 5, 2, 0, 1, 1, 2, 3, 4, 0, 80]).await;
        assert!(result.is_err());
        assert_eq!(reply[2..4], [5, SOCKS_COMMAND_NOT_SUPPORTED]);

        // SOCKS4.
        assert!(socks(&[4, 1, 0, 80]).await.0.is_err());
    }
}
