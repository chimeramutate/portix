# Flatpak untuk Portix — Panduan Penempatan & Penggunaan

## 1. Struktur file

Letakkan file-file ini di repo `portix` (Flutter app), bukan di `portix-serv`:

```
portix/
├── .github/
│   └── workflows/
│       └── build-desktop.yml          ← ganti workflow lama dengan ini
├── flatpak/
│   ├── com.github.asep.Portix.yml         ← manifest Flatpak
│   ├── com.github.asep.Portix.desktop     ← desktop entry
│   └── com.github.asep.Portix.metainfo.xml ← AppStream metadata
└── assets/
    └── icons/
        └── portix_launcher.png        ← sudah ada, dipakai ulang
```

## 2. Apa yang berubah dari workflow lama

Hanya **menambahkan satu job baru** bernama `flatpak` di akhir file. Job
`build`, `snap`, dan `wait-for-serv-release` **tidak diubah sama sekali**.

Job `flatpak`:
1. `needs: build` — menunggu job `build` (matrix linux) selesai dan artifact
   `portix-linux-<tag>.tar.gz` ter-upload.
2. Download artifact tar.gz itu, extract ke `flatpak/bundle-src`.
3. Jalankan `flatpak-builder` resmi via action
   `flatpak/flatpak-github-actions/flatpak-builder@v6`, yang otomatis
   menyiapkan runtime `org.gnome.Platform//46` di dalam container.
4. Hasil `.flatpak` bundle di-upload sebagai artifact GitHub Actions, dan
   ikut ditempel ke GitHub Release saat push tag.

**Tidak ada double-build** Flutter/Rust — Flatpak murni membungkus ulang
binary yang sudah dihasilkan job `build` linux, sama seperti pola yang sudah
kamu pakai untuk `.deb` dan `.tar.gz`.

## 3. Penyesuaian penting di manifest

- `libsecret-1.so.0` dan `libgcrypt.so.20` **tidak** ikut di-copy ke
  `/app/lib`, karena keduanya sudah disediakan oleh runtime
  `org.gnome.Platform`. Mengikutkan versi sendiri berisiko bentrok dengan
  versi runtime saat sandbox jalan.
- Permission Snap → Flatpak:

  | Snap plug | Flatpak finish-args |
  |---|---|
  | `network`, `network-bind` | `--share=network` |
  | `home` | `--filesystem=home` |
  | `ssh-keys` | `--filesystem=~/.ssh:ro` |
  | `password-manager-service` | `--talk-name=org.freedesktop.secrets` |
  | `wayland`, `x11` | `--socket=wayland`, `--socket=fallback-x11` |
  | `opengl` | `--device=dri` |
  | `desktop`, `desktop-legacy`, `gsettings` | otomatis dari `org.gnome.Platform` |

## 4. Testing lokal sebelum push

```bash
# Install tooling sekali saja
flatpak install flathub org.gnome.Platform//46 org.gnome.Sdk//46
flatpak install flathub org.flatpak.Builder   # untuk linting

# Build manual (simulasi CI) — jalankan dari root repo portix
mkdir -p flatpak/bundle-src
tar -xzf portix-linux-vX.Y.Z.tar.gz -C flatpak/bundle-src --strip-components=1
cp assets/icons/portix_launcher.png flatpak/assets/portix_launcher.png  # sesuaikan path

flatpak-builder --user --install --force-clean build-dir \
  flatpak/com.github.asep.Portix.yml

flatpak run com.github.asep.Portix
```

## 5. Job `publish-flathub` — auto-update versi (setelah app diterima)

Job ini **hanya berguna setelah** app sudah disetujui dan repo
`flathub/com.github.asep.Portix` sudah ada. Cara kerjanya:

1. Jalan setelah job `flatpak` sukses, dan **hanya untuk channel stable**
   (`IS_BETA != 'true'`) — beta release tidak otomatis publish ke Flathub.
2. Checkout repo `flathub/com.github.asep.Portix` terpisah.
3. Hitung ulang `sha256` dari tarball linux yang baru saja dibuild.
4. Update field `url` dan `sha256` di `com.github.asep.Portix.yml` milik
   repo Flathub itu (pakai manifest versi **archive URL**, lihat
   `flatpak/flathub-com.github.asep.Portix.yml` — ini berbeda dari manifest
   testing CI yang pakai `type: dir` lokal).
5. Tambahkan entry `<release>` baru di `metainfo.xml`.
6. Commit & push ke repo Flathub.
7. **Flathub buildbot otomatis** mendeteksi push ini dan menjalankan build +
   publish — bagian ini di luar kendali CI kita, sepenuhnya sisi Flathub.

### Setup yang dibutuhkan sebelum job ini bisa jalan

| Item | Keterangan |
|---|---|
| Secret `FLATHUB_PAT` | Personal Access Token (fine-grained) dengan akses **write** ke repo `flathub/com.github.asep.Portix`. Generate di GitHub → Settings → Developer settings. Tambahkan sebagai repo secret di `portix` (bukan `portix-serv`). |
| Repo `flathub/com.github.asep.Portix` sudah eksis | Hanya terbentuk setelah submission pertama disetujui reviewer Flathub (lihat bagian 6 di bawah). |
| Manifest awal di repo Flathub | Harus berbentuk `type: archive` (bukan `type: dir`) — gunakan isi `flatpak/flathub-com.github.asep.Portix.yml` sebagai starting point saat submission pertama, **bukan** `flatpak/com.github.asep.Portix.yml` (yang itu khusus untuk testing CI lokal/sideload). |

### Kalau token belum di-setup

Job akan gagal di step checkout repo Flathub (`token` tidak valid/repo belum
ada). Ini aman — job lain (`build`, `snap`, `flatpak`) tidak terpengaruh
karena `publish-flathub` berdiri sendiri di akhir pipeline. Bisa dibiarkan
gagal sampai submission pertama selesai, lalu setup `FLATHUB_PAT` baru
job ini mulai berfungsi.

## 6. Submit ke Flathub (langkah manual, terpisah dari CI ini)

CI di atas **hanya menghasilkan bundle `.flatpak` untuk sideload/testing**,
bukan publish otomatis ke Flathub **untuk submission pertama**. Untuk
publish resmi pertama kali:

1. Pastikan `com.github.asep.Portix.metainfo.xml` sudah diisi data asli
   (screenshot URL valid, deskripsi final, lisensi benar — ganti `MIT` jika
   lisensi Portix berbeda).
2. Fork `https://github.com/flathub/flathub`, buat PR baru request repo
   `flathub/com.github.asep.Portix`.
3. Setelah repo dibuat, push isi folder `flatpak/` ke repo tersebut:
   - Pakai **`flathub-com.github.asep.Portix.yml`** (bukan
     `com.github.asep.Portix.yml`) sebagai `com.github.asep.Portix.yml` di
     root repo Flathub — versi ini sudah pakai `type: archive` dengan URL
     GitHub Release, sesuai yang diharapkan reviewer Flathub dan sesuai
     yang akan di-update otomatis oleh job `publish-flathub`.
   - Sertakan juga `.desktop` dan `.metainfo.xml`.
   - Isi `url` dan `sha256` placeholder dengan rilis aktual pertama sebelum
     submit (lihat step "Resolve release version & download URL" di job
     `publish-flathub` untuk cara hitung sha256 manual: `sha256sum <file>`).
4. **Catatan penting**: manifest yang disubmit ke Flathub idealnya
   mem-build dari source asli (vendor Rust crates + Flutter SDK offline),
   bukan fetch pre-built binary dari GitHub Releases milikmu sendiri —
   reviewer Flathub kadang meminta reproducible build dari source. Kalau
   ingin tetap pakai pendekatan pre-built binary, siapkan argumen/justifikasi
   saat review (beberapa app diterima dengan source `type: archive` yang
   checksum-nya tetap terverifikasi, asal source resmi & stabil).
5. Validasi metainfo sebelum submit:
   ```bash
   flatpak run org.freedesktop.appstream-glib validate \
     flatpak/com.github.asep.Portix.metainfo.xml
   ```

## 6. Checklist sebelum tag release pertama kali

- [ ] `flatpak/com.github.asep.Portix.desktop` — sesuaikan `Categories`
      jika perlu (saat ini: `Network;RemoteAccess;System;`)
- [ ] `flatpak/com.github.asep.Portix.metainfo.xml` — isi `<screenshots>`
      dengan URL gambar yang benar-benar ada, atau hapus tag itu sementara
- [ ] Cek `app-id` konsisten di tiga tempat: manifest (`app-id:`),
      desktop file (nama file = app-id), metainfo (`<id>`)
- [ ] Jalankan testing lokal (bagian 4) minimal sekali sebelum andalkan CI
