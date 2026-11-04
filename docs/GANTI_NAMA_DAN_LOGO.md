# Ganti nama aplikasi & logo (AI CLIPPER)

1. Salin isi folder `native/android/res/` ke `android/app/src/main/res/`
   (gabungkan/timpa folder `mipmap-*`; folder `mipmap-anydpi-v26` baru).
   Hapus file lama `ic_launcher.webp` / `ic_launcher.png` bawaan Flutter di
   `mipmap-*` bila masih ada (nama yang sama dengan ekstensi berbeda memicu error
   "Duplicate resources").
2. Di `android/app/src/main/AndroidManifest.xml`, pada tag `<application>`:
   ```xml
   android:label="AI CLIPPER"
   android:icon="@mipmap/ic_launcher"
   android:roundIcon="@mipmap/ic_launcher_round"
   ```
3. `flutter clean` lalu `flutter run`. Bila ikon lama masih tampil, uninstall
   aplikasi dulu (launcher men-cache ikon).

Logo master 1024px: `docs/logo_ai_clipper_1024.png` (ganti dengan logo Anda sendiri
bila ada, lalu saya buatkan ulang semua ukuran).

## Ikon notifikasi (bukan kotak)
Ikon kecil notifikasi harus monokrom. Salin juga `native/android/res/drawable/ic_stat_clipper.xml`
ke `android/app/src/main/res/drawable/` (folder `drawable` dibuat bila belum ada) dan
timpa `KeepAliveService.kt` dengan versi di `native/android/`. Lalu `flutter clean` dan
`flutter run`. Notifikasi lama di status bar hilang setelah proses selesai/dibuka ulang.
