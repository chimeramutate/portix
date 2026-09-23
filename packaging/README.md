# Portix Packaging

Dokumentasi untuk membuat paket instalasi Portix untuk semua platform.

## Quick Start

### Build All Platforms

```bash
# From project root

# Build macOS DMG
./packaging/dmg/build_dmg.sh 1.0.0 1

# Build Windows EXE
./packaging/windows/build_windows.sh 1.0.0 1
```

## Directory Structure

```
packaging/
├── dmg/                    # macOS DMG packaging
│   ├── build_dmg.sh        # DMG build script
│   ├── README.md           # Documentation
│   └── .background/        # DMG background image
│       └── .gitkeep        # Keep directory
│
├── windows/                # Windows packaging
│   ├── build_windows.sh    # Linux/macOS build script
│   ├── build_windows.bat   # Windows batch script
│   ├── portix-installer.nsi # NSIS installer script
│   ├── README.md           # Documentation
│   └── resources/          # Installer resources
│       └── installer-icons/
│
└── icons/                  # Generated icons
    ├── portix.ico          # Windows icon
    └── Portix.iconset/     # macOS iconset
```

## Prerequisites

| Platform | Required Tools |
|----------|---------------|
| **macOS** | Flutter, Xcode, Rust, OpenSSL |
| **Windows** | Flutter, Visual Studio, Rust |
| **Linux** | Flutter, Rust, ImageMagick |

## Build Commands

### macOS DMG

```bash
cd packaging/dmg

# Build with default version
./build_dmg.sh

# Build with specific version
./build_dmg.sh 1.2.0 5
```

Output di `dist/Portix-VERSION.dmg`

### Windows EXE

**Dari Windows (Command Prompt):**
```cmd
cd packaging\windows
build_windows.bat 1.0.0 1
```

**Dari Linux/macOS:**
```bash
cd packaging/windows
./build_windows.sh 1.0.0 1
```

Output di `dist/windows/portix-VERSION-win-x64.zip`

## Membuat Icon

```bash
# Dari root proyek
./packaging/create_icons.sh
```

## Creating an Executable Installer (Windows)

1. Install NSIS di Windows
2. Buka hasil build di `dist/windows/Release/`
3. Copy `portix-installer.nsi` ke folder tersebut
4. Jalankan: `makensis portix-installer.nsi`

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build and Release

on:
  release:
    types: [created]

jobs:
  build:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [macos-latest, windows-latest]
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Flutter
      uses: subosito/flutter-action@v2
      
    - name: Build DMG (macOS)
      if: matrix.os == 'macos-latest'
      run: |
        ./packaging/dmg/build_dmg.sh ${{ github.event.release.tag_name }}
        
    - name: Build Windows (Windows)
      if: matrix.os == 'windows-latest'
      run: |
        ./packaging/windows/build_windows.bat ${{ github.event.release.tag_name }}
```

## Release Checklist

- [ ] Semua tests lulus
- [ ] Rust library sudah dibuild
- [ ] Icon sudah dikonversi
- [ ] DMG dibuild di macOS
- [ ] EXE dibuild di Windows
- [ ] Checksum dibuat
- [ ] Release notes ditulis
- [ ] Verifikasi instalasi