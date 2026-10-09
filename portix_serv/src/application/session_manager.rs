use std::collections::HashMap;
use std::sync::Arc;

use base64::{Engine as _, engine::general_purpose};
use tokio::sync::{RwLock, broadcast, mpsc, oneshot};
use uuid::Uuid;

use crate::domain::errors::{PortixError, Result};
use crate::domain::events::{ConnectionStatusEvent, ErrorEvent, TerminalOutputEvent};
use crate::domain::profile::SshProfile;
use crate::domain::session::{ConnectionStatus, RemoteSystemSnapshot, SessionInfo};
use crate::infrastructure::ssh_client::{SshCommand, SshRuntime};

#[derive(Clone)]
pub struct SessionManager {
    sessions: Arc<RwLock<HashMap<String, ManagedSession>>>,
    output_tx: broadcast::Sender<TerminalOutputEvent>,
    status_tx: broadcast::Sender<ConnectionStatusEvent>,
    error_tx: broadcast::Sender<ErrorEvent>,
}

#[derive(Clone)]
struct ManagedSession {
    command_tx: mpsc::Sender<SshCommand>,
    /// None = not yet detected, Some(platform) = cached
    remote_platform: Arc<RwLock<Option<RemotePlatform>>>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum RemotePlatform {
    Unix,
    WindowsCmd,
    WindowsPowerShell,
}

impl SessionManager {
    pub fn new() -> Self {
        let (output_tx, _) = broadcast::channel(1024);
        let (status_tx, _) = broadcast::channel(256);
        let (error_tx, _) = broadcast::channel(256);
        Self {
            sessions: Arc::new(RwLock::new(HashMap::new())),
            output_tx,
            status_tx,
            error_tx,
        }
    }

    pub fn terminal_output_stream(&self) -> broadcast::Receiver<TerminalOutputEvent> {
        self.output_tx.subscribe()
    }

    pub fn connection_status_stream(&self) -> broadcast::Receiver<ConnectionStatusEvent> {
        self.status_tx.subscribe()
    }

    pub fn error_event_stream(&self) -> broadcast::Receiver<ErrorEvent> {
        self.error_tx.subscribe()
    }

    pub async fn connect(&self, profile: SshProfile, cols: u32, rows: u32) -> Result<SessionInfo> {
        profile.validate()?;

        let session_id = Uuid::new_v4().to_string();
        let (command_tx, command_rx) = mpsc::channel(512);
        let info = SessionInfo {
            id: session_id.clone(),
            profile_id: profile.id.clone(),
            status: ConnectionStatus::Connecting,
        };

        self.sessions.write().await.insert(
            session_id.clone(),
            ManagedSession {
                command_tx,
                remote_platform: Arc::new(RwLock::new(None)),
            },
        );
        self.emit_status(
            &session_id,
            ConnectionStatus::Connecting,
            Some("connecting"),
        );

        let sessions = self.sessions.clone();
        let output_tx = self.output_tx.clone();
        let status_tx = self.status_tx.clone();
        let error_tx = self.error_tx.clone();
        tokio::spawn(async move {
            let mut final_status = ConnectionStatus::Disconnected;
            let mut final_message = None;
            let runtime = SshRuntime::new(
                profile,
                session_id.clone(),
                output_tx,
                status_tx.clone(),
                error_tx.clone(),
            );
            let result = runtime.run(command_rx, cols, rows).await;
            if let Err(error) = result {
                final_status = ConnectionStatus::Error;
                final_message = Some(error.to_string());
                let _ = error_tx.send(ErrorEvent {
                    session_id: Some(session_id.clone()),
                    message: error.to_string(),
                });
            }
            sessions.write().await.remove(&session_id);
            let _ = status_tx.send(ConnectionStatusEvent {
                session_id,
                status: final_status,
                message: final_message,
            });
        });

        Ok(info)
    }

    pub async fn disconnect(&self, session_id: String) -> Result<()> {
        let session = self.session(&session_id).await?;
        session
            .command_tx
            .send(SshCommand::Disconnect)
            .await
            .map_err(|_| PortixError::SessionNotFound(session_id.clone()))?;
        Ok(())
    }

    pub async fn send_terminal_input(&self, session_id: String, data: Vec<u8>) -> Result<()> {
        if data.is_empty() {
            return Ok(());
        }

        let session = self.session(&session_id).await?;
        session
            .command_tx
            .send(SshCommand::Input(data))
            .await
            .map_err(|_| PortixError::SessionNotFound(session_id.clone()))?;
        Ok(())
    }

    pub async fn resize_terminal(&self, session_id: String, cols: u32, rows: u32) -> Result<()> {
        let session = self.session(&session_id).await?;
        session
            .command_tx
            .send(SshCommand::Resize { cols, rows })
            .await
            .map_err(|_| PortixError::SessionNotFound(session_id.clone()))?;
        Ok(())
    }

    pub async fn remote_system_snapshot(&self, session_id: String) -> Result<RemoteSystemSnapshot> {
        let is_windows = self.is_remote_windows(&session_id).await;
        let command = if is_windows {
            remote_system_command_windows()
        } else {
            remote_system_command()
        };
        let output = self.exec(session_id, command).await?;
        Ok(parse_remote_system_snapshot(&output))
    }

    async fn exec(&self, session_id: String, command: String) -> Result<String> {
        let session = self.session(&session_id).await?;
        let (response_tx, response_rx) = oneshot::channel();
        session
            .command_tx
            .send(SshCommand::Exec {
                command,
                response_tx,
            })
            .await
            .map_err(|_| PortixError::SessionNotFound(session_id.clone()))?;
        response_rx
            .await
            .map_err(|_| PortixError::SessionNotFound(session_id))?
    }

    async fn session(&self, session_id: &str) -> Result<ManagedSession> {
        self.sessions
            .read()
            .await
            .get(session_id)
            .cloned()
            .ok_or_else(|| PortixError::SessionNotFound(session_id.to_owned()))
    }

    fn emit_status(&self, session_id: &str, status: ConnectionStatus, message: Option<&str>) {
        let _ = self.status_tx.send(ConnectionStatusEvent {
            session_id: session_id.to_owned(),
            status,
            message: message.map(str::to_owned),
        });
    }

    /// Detect if the remote host is Windows.
    /// Works for both cmd.exe and PowerShell default shells.
    /// Result is cached per session to avoid repeated detection.
    async fn is_remote_windows(&self, session_id: &str) -> bool {
        let platform = self.detect_remote_platform(session_id).await;
        matches!(
            platform,
            RemotePlatform::WindowsCmd | RemotePlatform::WindowsPowerShell
        )
    }

    async fn detect_remote_platform(&self, session_id: &str) -> RemotePlatform {
        // Check cache first
        if let Ok(session) = self.session(session_id).await {
            let cached = session.remote_platform.read().await;
            if let Some(platform) = *cached {
                return platform;
            }
        }

        // Detection strategy:
        // 1. Try `echo $PSVersionTable.PSVersion` — if it returns a version, it's PowerShell
        // 2. Try `echo %OS%` — if it returns Windows_NT, it's cmd.exe
        // 3. Otherwise it's Unix
        let result = self
            .exec(
                session_id.to_owned(),
                "echo PORTIX_DETECT && echo %OS% && echo $env:OS".to_owned(),
            )
            .await;

        let platform = match result {
            Ok(output) => {
                let lines: Vec<&str> = output.lines().map(str::trim).collect();
                // Check if %OS% was expanded (cmd.exe) or $env:OS returned value (PowerShell)
                let has_windows_nt = lines.iter().any(|line| line.contains("Windows_NT"));
                let has_unexpanded_percent = lines.iter().any(|line| *line == "%OS%");
                let _has_unexpanded_env = lines.iter().any(|line| *line == "$env:OS");

                if has_windows_nt && !has_unexpanded_percent {
                    // %OS% expanded to Windows_NT → cmd.exe shell
                    RemotePlatform::WindowsCmd
                } else if has_windows_nt && has_unexpanded_percent {
                    // $env:OS returned Windows_NT but %OS% didn't expand → PowerShell
                    RemotePlatform::WindowsPowerShell
                } else {
                    RemotePlatform::Unix
                }
            }
            Err(_) => RemotePlatform::Unix,
        };

        // Store in cache
        if let Ok(session) = self.session(session_id).await {
            let mut cached = session.remote_platform.write().await;
            *cached = Some(platform);
        }

        platform
    }
}

fn remote_system_command() -> String {
    r#"if [ -r /etc/redhat-release ]; then
  os="$(cat /etc/redhat-release 2>/dev/null)"
else
  os="$(uname -srm 2>/dev/null)"
fi
printf 'OS=%s\n' "$os"
printf 'HOST=%s\n' "$(hostname 2>/dev/null)"
printf 'UPTIME=%s\n' "$(uptime 2>/dev/null)"
if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
  _mem_total=$(sysctl -n hw.memsize 2>/dev/null)
  _page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
  _vm_stat=$(vm_stat 2>/dev/null)
  _pages_free=$(echo "$_vm_stat" | awk '/Pages free:/ {gsub(/\./,"",$3); print $3}')
  _pages_inactive=$(echo "$_vm_stat" | awk '/Pages inactive:/ {gsub(/\./,"",$3); print $3}')
  _pages_purgeable=$(echo "$_vm_stat" | awk '/Pages purgeable:/ {gsub(/\./,"",$3); print $3}')
  _mem_free=$(( (_pages_free + _pages_inactive + _pages_purgeable) * _page_size ))
  _mem_used=$(( _mem_total - _mem_free ))
  if [ "$_mem_used" -lt 0 ] 2>/dev/null; then _mem_used=0; fi
  printf "MEM_USED_BYTES=%s\nMEM_FREE_BYTES=%s\nMEM_TOTAL_BYTES=%s\n" "$_mem_used" "$_mem_free" "$_mem_total"
else
  awk '
    /MemTotal:/ {total=$2 * 1024}
    /MemFree:/ {mem_free=$2 * 1024}
    /Buffers:/ {buffers=$2 * 1024}
    /^Cached:/ {cached=$2 * 1024}
    /MemAvailable:/ {available=$2 * 1024}
    END {
      if (available == 0) available = mem_free + buffers + cached
      used = total - available
      if (used < 0) used = 0
      printf "MEM_USED_BYTES=%.0f\nMEM_FREE_BYTES=%.0f\nMEM_TOTAL_BYTES=%.0f\n", used, available, total
    }
  ' /proc/meminfo 2>/dev/null
fi
df -P -k / 2>/dev/null | awk '
  NR==2 {
    total=$2 * 1024
    used=$3 * 1024
    free=$4 * 1024
    printf "DISK_USED_BYTES=%.0f\nDISK_FREE_BYTES=%.0f\nDISK_TOTAL_BYTES=%.0f\n", used, free, total
  }
'
true
"#
    .to_owned()
}

fn remote_system_command_windows() -> String {
    // Use PowerShell encoded command to avoid quoting issues with cmd.exe wrapping.
    let ps_script = r#"
$os = (Get-CimInstance Win32_OperatingSystem).Caption
$host_ = $env:COMPUTERNAME
$upObj = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$up = (New-TimeSpan -Start $upObj -End (Get-Date))
$upStr = '{0}d {1}h {2}m' -f $up.Days, $up.Hours, $up.Minutes
$mem = Get-CimInstance Win32_OperatingSystem
$memTotal = $mem.TotalVisibleMemorySize * 1024
$memFree = $mem.FreePhysicalMemory * 1024
$memUsed = $memTotal - $memFree
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$diskTotal = $disk.Size
$diskFree = $disk.FreeSpace
$diskUsed = $diskTotal - $diskFree
Write-Output "OS=$os"
Write-Output "HOST=$host_"
Write-Output "UPTIME=$upStr"
Write-Output "MEM_USED_BYTES=$([math]::Max(0, $memUsed))"
Write-Output "MEM_FREE_BYTES=$([math]::Max(0, $memFree))"
Write-Output "MEM_TOTAL_BYTES=$([math]::Max(0, $memTotal))"
Write-Output "DISK_USED_BYTES=$([math]::Max(0, $diskUsed))"
Write-Output "DISK_FREE_BYTES=$([math]::Max(0, $diskFree))"
Write-Output "DISK_TOTAL_BYTES=$([math]::Max(0, $diskTotal))"
"#;
    encode_powershell_command(ps_script)
}

/// Encode a PowerShell script as a base64 UTF-16LE encoded command.
/// This avoids all quoting/escaping issues when launching via cmd.exe or PowerShell.
fn encode_powershell_command(script: &str) -> String {
    let utf16: Vec<u8> = script
        .encode_utf16()
        .flat_map(|c| c.to_le_bytes())
        .collect();
    let encoded = general_purpose::STANDARD.encode(&utf16);
    format!("powershell -NoProfile -EncodedCommand {encoded}")
}

fn parse_remote_system_snapshot(output: &str) -> RemoteSystemSnapshot {
    fn value<'a>(output: &'a str, key: &str) -> &'a str {
        output
            .lines()
            .find_map(|line| line.strip_prefix(key))
            .unwrap_or("")
            .trim()
    }

    RemoteSystemSnapshot {
        os: value(output, "OS=").to_owned(),
        hostname: value(output, "HOST=").to_owned(),
        uptime: value(output, "UPTIME=").to_owned(),
        memory: value(output, "MEM=").to_owned(),
        disk: value(output, "DISK=").to_owned(),
        memory_used_bytes: value(output, "MEM_USED_BYTES=").parse().unwrap_or(0),
        memory_free_bytes: value(output, "MEM_FREE_BYTES=").parse().unwrap_or(0),
        memory_total_bytes: value(output, "MEM_TOTAL_BYTES=").parse().unwrap_or(0),
        disk_used_bytes: value(output, "DISK_USED_BYTES=").parse().unwrap_or(0),
        disk_free_bytes: value(output, "DISK_FREE_BYTES=").parse().unwrap_or(0),
        disk_total_bytes: value(output, "DISK_TOTAL_BYTES=").parse().unwrap_or(0),
    }
}

impl Default for SessionManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── resolve_directory_from_output ────────────────────────────────────────

    #[test]
    fn parse_remote_system_snapshot_extracts_all_fields() {
        let out = "OS=Ubuntu 22.04 LTS\nHOST=prod-01\nUPTIME=5 days\n\
                   MEM_USED_BYTES=4096\nMEM_FREE_BYTES=2048\nMEM_TOTAL_BYTES=8192\n\
                   DISK_USED_BYTES=10000\nDISK_FREE_BYTES=5000\nDISK_TOTAL_BYTES=15000\n";
        let snap = parse_remote_system_snapshot(out);
        assert_eq!(snap.os, "Ubuntu 22.04 LTS");
        assert_eq!(snap.hostname, "prod-01");
        assert_eq!(snap.uptime, "5 days");
        assert_eq!(snap.memory_total_bytes, 8192);
        assert_eq!(snap.disk_total_bytes, 15000);
    }

    #[test]
    fn parse_remote_system_snapshot_defaults_zero_for_missing_fields() {
        let snap = parse_remote_system_snapshot("OS=Linux\n");
        assert_eq!(snap.memory_used_bytes, 0);
        assert_eq!(snap.disk_total_bytes, 0);
    }

    #[test]
    fn parse_remote_system_snapshot_empty_input() {
        let snap = parse_remote_system_snapshot("");
        assert!(snap.os.is_empty());
        assert_eq!(snap.memory_total_bytes, 0);
    }
}
