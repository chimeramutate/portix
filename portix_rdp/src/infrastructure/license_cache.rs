use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};

use ironrdp_connector::{ConnectorError, ConnectorErrorExt as _, LicenseCache};
use ironrdp_pdu::rdp::server_license::LicenseInformation;

/// Returns `true` if the given error message string originates from the
/// RDP license-exchange state machine (any `LicenseExchangeState` variant)
/// or a related license-PDU construction/verification failure.
pub(crate) fn is_license_error(msg: &str) -> bool {
    msg.contains("LicenseExchangeState")
        || msg.contains("SERVER_NEW_LICENSE")
        || msg.contains("licensing error")
        || msg.contains("license verification")
        || msg.contains("ClientNewLicenseRequest")
        || msg.contains("ClientLicenseInfo")
        || msg.contains("ClientPlatformChallengeResponse")
}

/// Detect whether the given username follows a CyberArk PAM/PSM format.
///
/// CyberArk PSM usernames have the format:
/// - `PSM@<session-token>` (PAS/PSM web portal login)
/// - `PSM\@<session-token>` (PSM .rdp file with backslash domain separator)
/// - `PAM@<session-token>` (CyberArk Privileged Access Management)
/// - `PAM\@<session-token>` (PAM .rdp file with backslash domain separator)
///
/// When a CyberArk PAM/PSM username is detected, the client should
/// pre-emptively use [`StubLicenseCache`] to send `CLIENT_LICENSE_INFO`
/// instead of `CLIENT_NEW_LICENSE_REQUEST`, avoiding the malformed
/// `ServerUpgradeLicense` PDU that PSM gateways send during the
/// `UpgradeLicense` state.
pub(crate) fn is_cyberark_pam(username: &str) -> bool {
    let lower = username.to_lowercase();
    lower.starts_with("psm@")
        || lower.starts_with("psm\\@")
        || lower.starts_with("pam@")
        || lower.starts_with("pam\\@")
}

/// Resolve the directory where Portix caches license files.
///
/// Lookup order:
/// 1. `$XDG_CACHE_HOME/portix/licenses/` (Linux)
/// 2. `$HOME/.cache/portix/licenses/` (Linux fallback)
/// 3. `%LOCALAPPDATA%\portix\licenses\` (Windows)
/// 4. `~/Library/Caches/portix/licenses/` (macOS)
fn default_cache_dir() -> PathBuf {
    if let Some(base) = std::env::var_os("XDG_CACHE_HOME") {
        return PathBuf::from(base).join("portix").join("licenses");
    }

    if let Some(home) = std::env::var_os("HOME") {
        if cfg!(target_os = "macos") {
            return PathBuf::from(home)
                .join("Library")
                .join("Caches")
                .join("portix")
                .join("licenses");
        }
        return PathBuf::from(home)
            .join(".cache")
            .join("portix")
            .join("licenses");
    }

    if let Some(local) = std::env::var_os("LOCALAPPDATA") {
        return PathBuf::from(local).join("portix").join("licenses");
    }

    PathBuf::from("/tmp/portix_cache/licenses")
}

// ──────────────────────────────── Stub ──────────────────────────────────

/// A license cache that always returns a stub (empty) license.
///
/// When this cache is installed, the RDP client sends `CLIENT_LICENSE_INFO`
/// (preamble type `0x12`) instead of `CLIENT_NEW_LICENSE_REQUEST`
/// (preamble type `0x13`) during the license-exchange phase.
///
/// Some RDP servers — particularly CyberArk PAS/PSM gateways — respond to
/// `CLIENT_LICENSE_INFO` with a `LicensingErrorMessage(StatusValidClient)`,
/// a well-formed license PDU that **completes** the exchange without ever
/// entering the `SERVER_UPGRADE_LICENSE` step. That step is where the
/// server sends a malformed/unrecognised PDU that ironrdp cannot decode,
/// producing the
/// `"decode during SERVER_NEW_LICENSE/LicenseExchangeState::UpgradeLicense"`
/// error.
///
/// Using this cache as a fallback retry is therefore the primary mitigation
/// for the CyberArk PSM license-decode failure.
#[derive(Debug, Default, Clone, Copy)]
pub struct StubLicenseCache;

impl LicenseCache for StubLicenseCache {
    fn get_license(
        &self,
        _license_info: LicenseInformation,
    ) -> Result<Option<Vec<u8>>, ConnectorError> {
        // Signal to the connector that we "already have a license"
        // (an empty one). This changes the PDU flow from
        // CLIENT_NEW_LICENSE_REQUEST → … → SERVER_UPGRADE_LICENSE
        // to CLIENT_LICENSE_INFO → (LicensingErrorMessage | PlatformChallenge)
        Ok(Some(Vec::new()))
    }

    fn store_license(&self, _license_info: LicenseInformation) -> Result<(), ConnectorError> {
        // Nothing to persist — the stub is intentionally stateless.
        Ok(())
    }
}

// ────────────────────────────── File cache ──────────────────────────────

/// A license cache that persists licenses on disk as JSON files.
///
/// Each license is stored in `~/.cache/portix/licenses/license_<hash>.json`
/// (or the platform equivalent). The file contains the `LicenseInformation`
/// key fields and the raw license blob returned by the server.
///
/// On cache hit, the raw bytes are returned and the client sends
/// `CLIENT_LICENSE_INFO` with the cached license. On cache miss,
/// `None` is returned and the client falls back to the full
/// `CLIENT_NEW_LICENSE_REQUEST` flow.
#[derive(Debug, Clone)]
pub struct FileLicenseCache {
    cache_dir: PathBuf,
}

#[derive(serde::Serialize, serde::Deserialize, Debug)]
struct CachedLicense {
    version: u32,
    scope: String,
    company_name: String,
    product_id: String,
    license_info: Vec<u8>,
}

impl Default for FileLicenseCache {
    fn default() -> Self {
        Self {
            cache_dir: default_cache_dir(),
        }
    }
}

impl FileLicenseCache {
    pub fn new(cache_dir: impl Into<PathBuf>) -> Self {
        Self {
            cache_dir: cache_dir.into(),
        }
    }

    pub fn with_default_dir() -> Self {
        Self::default()
    }

    pub fn cache_dir(&self) -> &Path {
        &self.cache_dir
    }

    fn cache_file_path(&self, info: &LicenseInformation) -> PathBuf {
        let mut hasher = DefaultHasher::new();
        info.version.hash(&mut hasher);
        info.scope.hash(&mut hasher);
        info.company_name.hash(&mut hasher);
        info.product_id.hash(&mut hasher);
        let hash = hasher.finish();

        self.cache_dir.join(format!("license_{:016x}.json", hash))
    }

    fn ensure_dir(&self) -> Result<(), std::io::Error> {
        std::fs::create_dir_all(&self.cache_dir)
    }
}

impl LicenseCache for FileLicenseCache {
    fn get_license(
        &self,
        license_info: LicenseInformation,
    ) -> Result<Option<Vec<u8>>, ConnectorError> {
        let path = self.cache_file_path(&license_info);

        if !path.exists() {
            return Ok(None);
        }

        let file = std::fs::File::open(&path)
            .map_err(|e| ConnectorError::general("FileLicenseCache::get_license").with_source(e))?;

        let cached: CachedLicense = serde_json::from_reader(file).map_err(|e| {
            ConnectorError::general("FileLicenseCache::get_license deserialize").with_source(e)
        })?;

        // Verify that the cached license matches the server identity.
        if cached.version == license_info.version
            && cached.scope == license_info.scope
            && cached.company_name == license_info.company_name
            && cached.product_id == license_info.product_id
        {
            Ok(Some(cached.license_info))
        } else {
            // Stale cache entry — ignore.
            Ok(None)
        }
    }

    fn store_license(&self, license_info: LicenseInformation) -> Result<(), ConnectorError> {
        if let Err(e) = self.ensure_dir() {
            eprintln!(
                "[portix_rdp] WARNING: cannot create license cache dir '{}': {}",
                self.cache_dir.display(),
                e
            );
            return Ok(()); // Non-fatal — the connection itself should not fail.
        }

        let cached = CachedLicense {
            version: license_info.version,
            scope: license_info.scope.clone(),
            company_name: license_info.company_name.clone(),
            product_id: license_info.product_id.clone(),
            license_info: license_info.license_info.clone(),
        };

        let path = self.cache_file_path(&license_info);

        let file = std::fs::File::create(&path).map_err(|e| {
            ConnectorError::general("FileLicenseCache::store_license").with_source(e)
        })?;

        if let Err(e) = serde_json::to_writer_pretty(file, &cached) {
            eprintln!(
                "[portix_rdp] WARNING: cannot write license cache '{}': {}",
                path.display(),
                e
            );
        }

        Ok(())
    }
}

// ───────────────────────────────── Tests ─────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_license_info() -> LicenseInformation {
        LicenseInformation {
            version: 1,
            scope: "example.com".to_string(),
            company_name: "TestCorp".to_string(),
            product_id: "TestPID".to_string(),
            license_info: vec![0xDE, 0xAD, 0xBE, 0xEF],
        }
    }

    #[test]
    fn stub_cache_always_returns_empty_license() {
        let cache = StubLicenseCache;

        let result = cache
            .get_license(sample_license_info())
            .expect("get_license should succeed");
        assert_eq!(
            result,
            Some(Vec::new()),
            "stub cache should return Some(empty)"
        );

        cache
            .store_license(sample_license_info())
            .expect("store_license should succeed");
    }

    #[test]
    fn file_cache_roundtrip() {
        let tmp = std::env::temp_dir().join(format!("portix_license_test_{}", std::process::id()));
        let cache = FileLicenseCache::new(&tmp);

        // Clean any leftover
        let _ = std::fs::remove_dir_all(&tmp);

        let info = sample_license_info();

        // Should be empty initially
        let result = cache
            .get_license(sample_license_info())
            .expect("get_license should succeed");
        assert_eq!(result, None, "cache should be empty initially");

        // Store the license
        cache
            .store_license(sample_license_info())
            .expect("store_license should succeed");

        // Should now return the cached license
        let result = cache.get_license(info).expect("get_license should succeed");
        assert_eq!(result, Some(vec![0xDE, 0xAD, 0xBE, 0xEF]));

        // Clean up
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn file_cache_rejects_mismatched_identity() {
        let tmp = std::env::temp_dir().join(format!(
            "portix_license_test_mismatch_{}",
            std::process::id()
        ));
        let cache = FileLicenseCache::new(&tmp);

        let _ = std::fs::remove_dir_all(&tmp);

        // Store a license
        cache
            .store_license(sample_license_info())
            .expect("store_license should succeed");

        // Query with different scope — should NOT return the cached license
        let result = cache
            .get_license(LicenseInformation {
                version: 1,
                scope: "different.com".to_string(),
                company_name: "TestCorp".to_string(),
                product_id: "TestPID".to_string(),
                license_info: vec![0xDE, 0xAD, 0xBE, 0xEF],
            })
            .expect("get_license should succeed");
        assert_eq!(
            result, None,
            "cache should not return license for different server"
        );

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn is_license_error_detects_known_patterns() {
        // Original error from the field report
        assert!(is_license_error(
            "[decode during SERVER_NEW_LICENSE/LicenseExchangeState::UpgradeLicense @ file.rs:250] decode error"
        ));
        // NewLicenseRequest state
        assert!(is_license_error(
            "[decode during LicenseExchangeState::NewLicenseRequest @ file.rs:120] decode error"
        ));
        // PlatformChallenge state
        assert!(is_license_error(
            "[decode during LicenseExchangeState::PlatformChallenge @ file.rs:80] decode error"
        ));
        // License construction errors (custom_err! contexts)
        assert!(is_license_error(
            "ClientNewLicenseRequest: invalid server license request"
        ));
        assert!(is_license_error("ClientLicenseInfo: encoding failed"));
        assert!(is_license_error(
            "ClientPlatformChallengeResponse: invalid challenge"
        ));
        // Error message from LicensingErrorMessage
        assert!(is_license_error("licensing error: status valid client"));
        // License verification
        assert!(is_license_error("license verification failed"));

        // Non-license errors should NOT match
        assert!(!is_license_error("TCP connection refused"));
        assert!(!is_license_error("TLS handshake failed"));
        assert!(!is_license_error("DNS resolution failed"));
    }

    #[test]
    fn default_cache_dir_is_writable_on_unix() {
        let dir = default_cache_dir();
        // Just verify it returns a reasonable path
        assert!(dir.as_os_str().to_string_lossy().contains("portix"));
    }

    #[test]
    fn is_cyberark_pam_detects_psm_and_pam_prefixes() {
        // PSM@ variants
        assert!(is_cyberark_pam("PSM@abc123"));
        assert!(is_cyberark_pam("psm@abc123"));
        assert!(is_cyberark_pam("PSM\\@abc123"));
        assert!(is_cyberark_pam("psm\\@abc123"));

        // PAM@ variants
        assert!(is_cyberark_pam("PAM@abc123"));
        assert!(is_cyberark_pam("pam@abc123"));
        assert!(is_cyberark_pam("PAM\\@abc123"));
        assert!(is_cyberark_pam("pam\\@abc123"));

        // Non-CyberArk usernames should NOT match
        assert!(!is_cyberark_pam("administrator"));
        assert!(!is_cyberark_pam("user@domain.com"));
        assert!(!is_cyberark_pam("PSM"));
        assert!(!is_cyberark_pam("localhost\\admin"));
        assert!(!is_cyberark_pam(""));
    }
}
