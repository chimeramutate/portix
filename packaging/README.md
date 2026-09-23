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