# Portix Packaging

Dokumentasi untuk membuat paket instalasi Portix untuk semua platform.

## 🚀 Quick Start

Package instalasi dibangun otomatis oleh GitHub Actions di `.github/workflows/portix.yml`.

Untuk build lokal:

### Build macOS DMG

```bash
# Full build (Rust + Flutter + DMG)
./packaging/dmg/build_dmg.sh 1.0.0 1

# atau Flutter app saja (lebih cepat)
./packaging/dmg/build_flutter_app.sh 1.0.0
```

### Build Windows

```bash
# Full build (Rust + Flutter + ZIP)
./packaging/windows/build_windows.bat 1.0.0 1

# atau Flutter app saja (lebih cepat)
./packaging/windows/build_flutter_app.bat 1.0.0
```

---

## 📁 Directory Structure

```
packaging/
├── dmg/                      # macOS DMG packaging
│   ├── build_dmg.sh          # Full macOS DMG build script
│   ├── build_flutter_app.sh  # Flutter app only build
│   ├── build_dmg_simple.sh   # Simple DMG build
│   ├── README.md             # Documentation
│   └── .background/          # DMG background image
│       └── .gitkeep          # Keep directory
│
├── windows/                  # Windows packaging
│   ├── build_windows.sh      # Linux/macOS build script
│   ├── build_windows.bat     # Windows batch script
│   ├── build_flutter_app.bat # Flutter app only build
│   ├── portix-installer.nsi  # NSIS installer script
│   ├── README.md             # Documentation
│   ├── LICENSE               # License for installer
│   └── resources/            # Installer resources
│       └── installer-icons/
│
└── icons/                    # Generated icons
    └── README.md             # Icon creation guide
```

---

## 📋 Prerequisites

| Platform | Required Tools |
|----------|---------------|
| **macOS** | Flutter, Xcode, Rust (for full build) |
| **Windows** | Flutter, Visual Studio, Rust (for full build) |
| **Linux** | Flutter, Rust (for full build) |

---

## 📦 Build Options

### Full Build (Rust + Flutter)

Membangun semua komponen dari awal:

```bash
# macOS
./packaging/dmg/build_dmg.sh 1.0.0 1

# Windows
./packaging/windows/build_windows.bat 1.0.0 1
```

### Flutter App Only (Faster)

Jika Rust library sudah ada (biasanya dari CI):

```bash
# macOS
./packaging/dmg/build_flutter_app.sh 1.0.0

# Windows
./packaging/windows/build_flutter_app.bat 1.0.0
```

---

## 🖼️ Creating Icons

```bash
./packaging/create_icons.sh
```

Output:
- `packaging/icons/portix.ico` - Windows icon
- `packaging/icons/portix.icns` - macOS icon

---

## 🛠️ Creating a Windows Installer (NSIS)

Untuk membuat EXE installer dengan UI profesional:

1. Install [NSIS](https://nsis.sourceforge.io/Download) di Windows
2. Buka folder hasil build di `dist/windows/Release/`
3. Compile: `makensis portix-installer.nsi`

---

## 🔄 CI/CD Integration

Workflow utama **`.github/workflows/portix.yml`** sudah mengatur build otomatis:

- **Trigger**: Push tag versi (`v*`), atau manual workflow dispatch
- **Hasil**: ZIP file + checksum, di-upload ke GitHub Releases

Workflow menghasilkan:
- macOS: ZIP file (bisa dibuat DMG manual jika diperlukan)
- Windows: ZIP file
- Linux: ZIP file / Snap package
- Rust libraries: Artifacts terpisah untuk download

---

## 📋 Release Checklist

- [ ] Semua tests lulus (`flutter test`, `cargo test`)
- [ ] Rust library sudah dibuild (`cargo build --release`)
- [ ] Icon sudah dikonversi
- [ ] Build DMG di macOS (`build_flutter_app.sh`)
- [ ] Build Windows (`build_flutter_app.bat`)
- [ ] Checksum dibuat (`.sha256`)
- [ ] Release notes ditulis
- [ ] Verifikasi instalasi
## macOS updates (Sparkle 2)

Portix on macOS updates itself through [Sparkle 2](https://sparkle-project.org). Users can wait for the scheduled check or choose **Portix → Check for Updates…**.

### How it works

- **Update feed.** `SUFeedURL` in `portix_app/macos/Runner/Info.plist` points at `https://github.com/chimeramutate/portix/releases/latest/download/appcast.xml`.
  - GitHub serves that URL from the newest release that is not a prerelease.
  - So only stable releases are offered as updates.
- **Signing in CI.** For a stable tag, `.github/workflows/portix.yml` does three things:
  1. It signs `portix-macos-<tag>.zip` with Sparkle's `sign_update`.
  2. It writes `appcast.xml`.
  3. It attaches `appcast.xml` to the release.
- **Verification.** The app checks every update against `SUPublicEDKey`, which comes from `SPARKLE_PUBLIC_ED_KEY`.
  - While that key is empty, the updater stays off. This covers local, debug and beta builds.
  - In those builds, **Check for Updates…** explains why it is off.
- **Version comparison.** Sparkle compares `CFBundleVersion`, which is the `+build` number in `pubspec.yaml`. Raise the build number with every release, for example `1.0.9+9` then `1.0.10+10`.

### One-time key setup

1. Download Sparkle 2.9.6 from <https://github.com/sparkle-project/Sparkle/releases>. Keep it at the same version as `Sparkle` in `portix_app/macos/Podfile.lock`.
2. Generate the key pair:

   ```bash
   ./bin/generate_keys
   ```

   This stores the private key in your login Keychain and prints the public key.
3. Export the private key:

   ```bash
   ./bin/generate_keys -x sparkle_private_key
   ```

4. Add these to the repository settings:

   | Name | Kind | Value |
   | --- | --- | --- |
   | `SPARKLE_ED_PRIVATE_KEY` | Actions **secret** | Contents of `sparkle_private_key` |
   | `SPARKLE_PUBLIC_ED_KEY` | Actions **variable** | The printed public key |

5. Delete the exported `sparkle_private_key` file.
   - Keep the key in your Keychain, or in a password manager.
   - **If the private key is lost, installed copies can never be updated again.** They only trust that one key.
