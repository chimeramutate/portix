# Portix Windows Build

Build script untuk membuat paket instalasi Windows untuk Portix.

## Prerequisites

Pastikan Anda memiliki:

1. **Windows 10/11** (build native)
2. **Flutter SDK** - [Instalasi Flutter](https://docs.flutter.dev/get-started/install/windows)
3. **Visual Studio 2022** dengan workloads:
   - Desktop development with C++
   - Windows 10/11 SDK
4. **Rust** - [Instalasi Rust](https://www.rust-lang.org/tools/install)

## Build Instructions

### Quick Build (Native Windows)

```cmd
# Dari root proyek
packaging\windows\build_windows.bat 1.0.0 1
```

### Manual Build (PowerShell)

```powershell
# Masuk ke direktori portix_app
cd portix_app

# Build Rust library untuk Windows
cd ../portix_serv
cargo build --release
cp target\release\portix_serv.dll ..\portix_app\artifacts\

# Kembali ke portix_app dan build Flutter windows
cd ../portix_app
flutter build windows --build-name=1.0.0 --build-number=1

# Buka Solution dan Build
# Atau gunakan build script
```

### Cross-Compile dari macOS/Linux

Jika Anda ingin build Windows dari macOS/Linux:

```bash
# Instal Rust Windows target
rustup target add x86_64-pc-windows-gnu

# Build Rust library
cargo build --release --target x86_64-pc-windows-gnu

# Build Flutter bundle
cd ../portix_app
flutter build bundle

# Hasil: artifacts/portix_serv.dll dan bundled assets
```

## Build Options

```bash
./build_windows.sh [version] [build_number]

# Contoh:
./build_windows.sh 1.2.0 5
```

## Output

Setelah build selesai, Anda akan menemukan:

- `dist/windows/portix-VERSION-win-x64.exe` - Executable langsung
- `dist/windows/portix-VERSION-win-x64.zip` - File zip yang dapat dibagikan
- `dist/windows/installer/` - Folder untuk installer

## Creating an Installer (NSIS)

Untuk membuat EXE installer dengan UI profesional:

### Install NSIS

1. Unduh dari: https://nsis.sourceforge.io/Download
2. Atau instalasi via Chocolatey:
   ```cmd
   choco install nsis
   ```

### Compile Installer

```cmd
# Masuk ke folder Windows build output
cd dist\windows\Release

# Copy NSI script ke sana
copy ..\..\..\..\packaging\windows\portix-installer.nsi .

# Compile dengan NSIS
makensis portix-installer.nsi
```

### Custom Installer Options

Edit file `portix-installer.nsi` untuk:

- Mengubah versi
- Menambahkan tampilan logo
- Mengkonfigurasi shortcut
- Menambah langkah instalasi khusus

## Windows Features

- ✅ 64-bit Windows support
- ✅ Self-contained executable
- ✅ Start Menu shortcut
- ✅ Desktop shortcut (opsional)
- ✅ Uninstaller terintegrasi
- ✅ Registry entries yang benar

## Troubleshooting

### Error: "visual studio not found"

Pastikan Visual Studio dengan C++ tools terinstal:
```cmd
winget install Microsoft.VisualStudio.2022.Community
```

### Error: "Unable to locate Flutter"

Pastikan Flutter berada di PATH:
```cmd
set PATH=%PATH%;C:\src\flutter\bin
```

### Error: "portix_serv.dll not found"

Pastikan Rust library sudah dibangun:
```powershell
cd portix_serv
cargo build --release
copy target\release\portix_serv.dll ..\portix_app\artifacts\
```

## Deployment

### GitHub Releases

Buat release baru di GitHub dan upload:

1. `portix-VERSION-win-x64.exe` - Untuk pengguna langsung
2. `portix-VERSION-win-x64.zip` - Untuk distribusi pribadi

### Auto-update (Menggunakan GitHub Releases)

Flutter tidak memiliki built-in auto-update. Anda dapat menggunakan:

- `url_launcher` untuk mengecek versi terbaru
- `firebase_remote_config` untuk konfigurasi versi

Contoh implementasi:

```dart
import 'package:url_launcher/url_launcher.dart';

Future<void> checkForUpdate() async {
  final currentVersion = '1.0.0';
  final latestVersion = await fetchLatestVersion();
  
  if (latestVersion != currentVersion) {
    final shouldUpdate = await showDialog(...);
    if (shouldUpdate) {
      launch('https://github.com/portix/portix/releases/latest');
    }
  }
}
```

## Code Signing (Opsional untuk Release)

Untuk mengunci executable:

```cmd
# Dapatkan code signing certificate (*.pfx)
# atau gunakan Windows SDK SignTool

signtool sign /f "certificate.pfx" /p password /t http://timestamp.digicert.com dist\windows\Release\portix.exe
```

## Icon Setup

Pastikan icon Windows ada di:
```
packaging/icons/portix.ico
```

Jika belum ada, buat dengan:
```bash
./packaging/create_icons.sh
```