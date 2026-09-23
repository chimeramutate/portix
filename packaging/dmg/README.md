# Portix DMG Build

Build script untuk membuat paket instalasi DMG untuk Portix pada macOS.

## Prerequisites

Pastikan Anda memiliki:

1. **macOS** (script harus dijalankan di macOS)
2. **Flutter SDK** - [Instalasi Flutter](https://docs.flutter.dev/get-started/install/macos)
3. **Xcode Command Line Tools** - `xcode-select --install`
4. **Rust** - [Instalasi Rust](https://www.rust-lang.org/tools/install)
5. **OpenSSL** (untuk signing opsional)

## Build Instructions

### Quick Build

```bash
# Dari root proyek
./packaging/dmg/build_dmg.sh 1.0.0 1
```

### Manual Build

```bash
# Masuk ke direktori portix_app
cd portix_app

# Build Rust library
cd ../portix_serv
cargo build --release
cp target/release/libportix_serv.dylib ../portix_app/artifacts/

# Kembali ke portix_app dan build Flutter macos
cd ../portix_app
flutter build macos --build-name=1.0.0 --build-number=1

# Buat DMG
cd ../packaging/dmg
./build_dmg.sh
```

## Build Options

```bash
./build_dmg.sh [version] [build_number]

# Contoh:
./build_dmg.sh 1.2.0 5
```

## Output

Setelah build selesai, Anda akan menemukan:

- `dist/Portix-VERSION.dmg` - File DMG instalasinya
- `dist/Portix-VERSION.dmg.sha256` - Checksum SHA256
- `dist/Portix-VERSION.zip` - File ZIP sebagai backup

## DMG Features

- ✅ App bundle yang ditas-kan (codesign optional untuk release)
- ✅ Struktur DMG bersih tanpa folder macOS biasa
- ✅readme.txt yang otomatis ditampilkan
- ✅Drag-and-drop instalasi

## Troubleshooting

### Error: "Flutter not found"

Pastikan Flutter berada di PATH:
```bash
export PATH="$PATH:`pwd`/flutter/bin"
```

### Error: "Product bundle not found"

Build Flutter mungkin gagal. Jalankan:
```bash
cd portix_app
flutter build macos
```

### Code Signing (untuk release)

Untuk membuat DMG yang dapat didistribusikan di App Store:

```bash
# Tanda tangani app sebelum membuat DMG
codesign --deep --force --verify --verbose \
    --sign "Developer ID Application: YOUR_NAME (TEAM_ID)" \
    portix_app/build/macos/Build/Products/Release/Portix.app

# Atasi untuk notarization (opsional)
xcrun notarytool submit dist/Portix-VERSION.dmg \
    --keychain-profile "AC_PASSWORD" \
    --wait
```

## Icon Setup

Pastikan icon macOS ada di:
```
packaging/icons/portix.icns
```

Jika belum ada, buat dengan:
```bash
./packaging/create_icons.sh
```