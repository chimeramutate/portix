# Portix Icons

Folder ini berisi icon untuk platform berbeda.

## Files

- `portix.ico` - Windows icon (multi-size .ico file)
- `portix.icns` - macOS icon (.icns file)
- `Portix.iconset/` - macOS iconset folder untuk pembuatan .icns

## Membuat Icon Baru

Jalankan script konversi dari assets yang ada:

```bash
# Dari root proyek
./packaging/create_icons.sh
```

Script ini akan:
1. Menggunakan `assets/icons/portix_adaptive_foreground.png` sebagai sumber
2. Membuat `portix.ico` untuk Windows
3. Membuat `portix.icns` untuk macOS

## Requirements

- **ImageMagick** - untuk konversi gambar
- **macOS iconutil** - untuk membuat .icns (hanya di macOS)

### Install ImageMagick

```bash
# macOS
brew install imagemagick

# Ubuntu/Debian
sudo apt install imagemagick

# Windows (Chocolatey)
choco install imagemagick
```

## Manual Icon Setup

Jika Anda memiliki icon kustom:

### Windows (.ico)

1. Buat icon 256x256 atau lebih besar
2. Konversi ke format .ico menggunakan alat seperti:
   - ImageMagick: `convert icon.png icon.ico`
   - Online converter: https://icoconvert.com/

### macOS (.icns)

1. Buat folder `MyIcon.iconset`
2. Letakkan file dengan ukuran berikut:
   - `icon_16x16.png`
   - `icon_16x16@2x.png` (32x32)
   - `icon_32x32.png`
   - `icon_32x32@2x.png` (64x64)
   - `icon_128x128.png`
   - `icon_128x128@2x.png` (256x256)
   - `icon_256x256.png`
   - `icon_256x256@2x.png` (512x512)
   - `icon_512x512.png`
   - `icon_512x512@2x.png` (1024x1024)
3. Buat .icns: `iconutil -c icns MyIcon.iconset`