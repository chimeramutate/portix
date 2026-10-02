use std::collections::HashMap;
use std::sync::Arc;

use tokio::sync::RwLock;
use uuid::Uuid;

use crate::domain::errors::{PortixError, Result};
use crate::domain::profile::SshProfile;
use crate::infrastructure::sftp_client::SftpConnection;

/// Open SFTP connections by id. Each has its own SSH connection, so they
/// live and die independently of terminal sessions.
#[derive(Default)]
pub struct SftpManager {
    connections: RwLock<HashMap<String, Arc<SftpConnection>>>,
}

impl SftpManager {
    pub async fn connect(&self, profile: SshProfile) -> Result<String> {
        profile.validate()?;
        let connection = SftpConnection::open(&profile).await?;
        let id = Uuid::new_v4().to_string();
        self.connections
            .write()
            .await
            .insert(id.clone(), Arc::new(connection));
        Ok(id)
    }

    /// The live connection; a dropped one is forgotten and reported as gone.
    pub async fn get(&self, id: &str) -> Result<Arc<SftpConnection>> {
        let connection = self.connections.read().await.get(id).cloned();
        match connection {
            Some(connection) if !connection.is_closed() => Ok(connection),
            Some(_) => {
                self.connections.write().await.remove(id);
                Err(PortixError::SessionNotFound(format!(
                    "{id} (SFTP connection closed)"
                )))
            }
            None => Err(PortixError::SessionNotFound(id.to_owned())),
        }
    }

    pub async fn is_alive(&self, id: &str) -> bool {
        self.get(id).await.is_ok()
    }

    pub async fn disconnect(&self, id: &str) {
        let connection = self.connections.write().await.remove(id);
        if let Some(connection) = connection {
            connection.close().await;
        }
    }
}
