# Portix DMG Build

Build script untuk membuat paket instalasi DMG untuk Portix pada macOS.

## Build Options

Ada dua cara untuk build DMG:

### Option 1: Full Build (Build Rust + Flutter + DMG)
Jika Anda ingin build dari awal termasuk Rust library:

```bash
# Dari root proyek
./packaging/dmg/build_dmg.sh 1.0.0 1
```

### Option 2: Flutter App Only (Faster)
Jika Rust library sudah ada (sudah dibuild atau di-download):

```bash
# Rust libraries harus ada di:
# portix_app/artifacts/libportix_serv.dylib
# portix_app/artifacts/libportix_rdp.dylib

./packaging/dmg/build_flutter_app.sh 1.0.0
```

atau untuk simple build:

```bash
./packaging/dmg/build_dmg_simple.sh 1.0.0
```

---

## Prerequisites

Pastikan Anda memiliki:

1. **macOS** (script harus dijalankan di macOS)
2. **Flutter SDK** - [Instalasi Flutter](https://docs.flutter.dev/get-started/install/macos)
3. **Xcode Command Line Tools** - `xcode-select --install`
4. **OpenSSL** (opsional untuk signing)

Untuk **Option 2 (Flutter-only)**, Rust libraries harus sudah ada di:
```
portix_app/artifacts/
├── libportix_serv.dylib
└── libportix_rdp.dylib
```

---

## Build Instructions

### Option 1: Full Build

```bash
cd packaging/dmg
./build_dmg.sh 1.0.0 1
```

Output: `dist/Portix-1.0.0.dmg`

### Option 2: Flutter App Only (Recommended)

Rust library biasanya sudah dibuild di CI. Gunakan script ini untuk build Flutter app saja:

```bash
cd packaging/dmg
./build_flutter_app.sh 1.0.0
```

Output: `dist/Portix-1.0.0.zip` (dan DMG)

---

## Build Commands

```bash
# Build with version
./build_flutter_app.sh 1.2.0

# Build with version (simple DMG)
./build_dmg_simple.sh 1.2.0
```

---

## Output

Setelah build selesai, Anda akan menemukan:

- `dist/Portix-VERSION.dmg` - File DMG instalasinya
- `dist/Portix-VERSION.dmg.sha256` - Checksum SHA256
- `dist/Portix-VERSION.zip` - File ZIP sebagai backup

---

## DMG Features

- ✅ App bundle yang ditas-kan (codesign optional untuk release)
- ✅ Struktur DMG bersih
- ✅ Drag-and-drop instalasi
- ✅ Versi tertentu

---

## Troubleshooting

### Error: "Rust libraries not found"

Build Rust library terlebih dahulu:

```bash
cd portix_serv
cargo build --release
cp target/release/libportix_serv.dylib ../portix_app/artifacts/

cd ../portix_rdp
cargo build --release
cp target/release/libportix_rdp.dylib ../portix_app/artifacts/
```

### Error: "Flutter not found"

Pastikan Flutter berada di PATH:
```bash
export PATH="$PATH:`pwd`/flutter/bin"
```

---

## CI/CD Integration

Workflow utama `.github/workflows/portix.yml` sudah mengatur build DMG secara otomatis saat:
- Push tag versi (misal: `v1.0.0`)
- Manual workflow dispatch