# Multi WhatsApp Web

Aplikasi desktop & mobile untuk mengelola **beberapa akun WhatsApp Web sekaligus**, masing-masing dengan sesi login yang benar-benar terpisah (cookie, localStorage, dan IndexedDB tidak saling bercampur antar akun).

Dibangun dengan Flutter, mengikuti Clean Architecture (domain layer platform-agnostic, terpisah dari implementasi WebView tiap platform).

## Fitur

- **Multi-akun WhatsApp Web** — tambah, hapus, dan ganti-ganti antar akun dari satu aplikasi.
- **Isolasi sesi per akun** — tiap akun punya profil/data browser sendiri, sehingga login satu akun tidak memengaruhi akun lain:
  - **Windows** — WebView2, dengan environment terisolasi per proses OS per akun.
  - **Linux** — WebKitGTK, tiap akun mendapat `WebKitWebsiteDataManager` sendiri.
  - **Android** — WebView native, tiap akun berjalan di proses Android terpisah (`android:process`), embedded langsung ke tampilan aplikasi lewat `SurfaceControlViewHost`.
  - **iOS** — menyusul.
- **Mode desktop** — paksa WhatsApp Web menampilkan tampilan desktop (bukan diarahkan ke halaman "gunakan di ponsel").
- **Manajemen memori** — akun yang tidak aktif otomatis di-nonaktifkan render-nya (dan dilepas sepenuhnya kalau menganggur cukup lama) supaya aplikasi tetap ringan walau banyak akun terbuka.
- **Kunci aplikasi (App Lock)** — lindungi akses ke aplikasi dengan PIN/password, supaya percakapan WhatsApp di semua akun tidak bisa dibuka orang lain yang meminjam/mengambil perangkat kalian.

## Platform yang didukung

| Platform | Status |
|---|---|
| Windows | ✅ Didukung |
| Linux | ✅ Didukung |
| Android | ✅ Didukung |
| macOS | 🚧 Belum diimplementasikan |
| iOS | 🚧 Belum diimplementasikan |

## Cara Menjalankan

```bash
flutter pub get
flutter run -d <windows|linux|android device>
```

Build rilis:

```bash
flutter build windows      # atau linux, apk, dst.
```

## Getting Started (bawaan Flutter)

Proyek ini adalah proyek Flutter standar. Kalau ini pertama kalinya kalian mengembangkan aplikasi Flutter, referensi berikut bisa membantu:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

Dokumentasi lengkap tersedia di [flutter.dev](https://docs.flutter.dev/), termasuk tutorial, contoh, panduan pengembangan mobile, dan referensi API lengkap.
