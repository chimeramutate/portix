# Portix Windows Build

Build script untuk membuat paket executable untuk Portix pada Windows.

## Build Options

Ada dua cara untuk build Windows:

### Option 1: Full Build (Build Rust + Flutter + ZIP)
Jika Anda ingin build dari awal termasuk Rust library:

```cmd
cd packaging\windows
build_windows.bat 1.0.0 1
```

### Option 2: Flutter App Only (Faster)
Jika Rust library sudah ada (sudah dibuild atau di-download):

```cmd
# Rust libraries harus ada di:
# portix_app\artifacts\portix_serv.dll
# portix_app\artifacts\portix_rdp.dll

cd packaging\windows
build_flutter_app.bat 1.0.0
```

---

## Prerequisites

Pastikan Anda memiliki:

1. **Windows 10/11**
2. **Flutter SDK** - [Instalasi Flutter](https://docs.flutter.dev/get-started/install/windows)
3. **Visual Studio 2022** dengan workloads:
   - Desktop development with C++
   - Windows 10/11 SDK
4. **Rust** - [Instalasi Rust](https://www.rust-lang.org/tools/install)

Untuk **Option 2 (Flutter-only)**, Rust libraries harus sudah ada di:
```
portix_app\artifacts\
├── portix_serv.dll
└── portix_rdp.dll
```

---

## Build Commands

### From Windows (Command Prompt)

```cmd
# Full build
build_windows.bat 1.0.0 1

# Flutter app only
build_flutter_app.bat 1.0.0
```

### From Linux/macOS (requires Windows toolchain)

```bash
cd packaging/windows
./build_windows.sh 1.0.0 1
```

---

## Output

Setelah build selesai, Anda akan menemukan:

- `dist/windows/portix-VERSION-win-x64.zip` - File ZIP executable
- `dist/windows/portix-VERSION-win-x64.zip.sha256` - Checksum SHA256

---

## Creating an Installer (Optional - NSIS)

Jika Anda ingin membuat EXE installer dengan UI profesional:

1. Install [NSIS](https://nsis.sourceforge.io/Download) di Windows
2. Buka folder hasil build
3. Compile: `makensis portix-installer.nsi`

File `portix-installer.nsi` berada di `packaging/windows/`.

---

## Windows Features

- ✅ 64-bit Windows support
- ✅ Self-contained executable
- ✅ Rust SSH & RDP libraries
- ✅ SHA256 checksum

---

## Troubleshooting

### Error: "Visual Studio not found"

Pastikan Visual Studio dengan C++ tools terinstal:
```cmd
winget install Microsoft.VisualStudio.2022.Community
```

### Error: "Rust libraries not found"

Build Rust library terlebih dahulu:
```cmd
cd portix_serv
cargo build --release
copy target\release\portix_serv.dll ..\portix_app\artifacts\
```

---

## CI/CD Integration

Workflow utama `.github/workflows/portix.yml` sudah mengatur build Windows secara otomatis saat:
- Push tag versi (misal: `v1.0.0`)
- Manual workflow dispatch

Hasilnya berupa ZIP file yang dapat diunduh dari GitHub Releases.