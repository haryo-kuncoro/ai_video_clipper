# AI Video Clipper

Aplikasi pribadi (Android) untuk mengubah video panjang menjadi clip portrait 9:16.
Arsitektur: **local-first**. Video, project, transcript, dan clip tidak pernah diupload ke server.

Status: **STEP 20 - Pengaturan global (panel admin, flag fitur, StorageManager)**

Checklist uji gabungan semua step: [`docs/CHECKLIST_UJI_GABUNGAN.md`](docs/CHECKLIST_UJI_GABUNGAN.md)

## Menjalankan

```bash
# 1. Buat kerangka platform (android/, dll) di folder ini
flutter create --org com.haryo --project-name ai_video_clipper --platforms=android .

# 2. Pasang kode native Android (metadata & thumbnail dari STEP 4)
cp native/android/MainActivity.kt \
   android/app/src/main/kotlin/com/haryo/ai_video_clipper/MainActivity.kt

# 3. WAJIB sejak STEP 6: set minSdk = 24 (lihat di bawah)

# 4. Pasang dependency
flutter pub get

# 5. Analisis dan test
flutter analyze
flutter test

# 6. Jalankan di perangkat Android
flutter run
```

### minSdk 24 (wajib untuk FFmpeg)

Buka `android/app/build.gradle.kts` (atau `build.gradle`) dan set:

```kotlin
defaultConfig {
    minSdk = 24          // Groovy: minSdkVersion 24
}
```

### Izin INTERNET (wajib sejak STEP 9, hanya untuk mengunduh model)

`flutter create` hanya menambah izin INTERNET untuk build debug. Agar build
release dapat mengunduh model Whisper, tambahkan di
`android/app/src/main/AndroidManifest.xml` (di dalam `<manifest>`, sebelum `<application>`):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Internet dipakai HANYA untuk mengunduh file model (sekali). Video, audio, dan
transcript tidak pernah dikirim ke mana pun.

Bila build gagal dengan "2 files found with path lib/.../libc++_shared.so",
tambahkan di `android/app/build.gradle.kts`:

```kotlin
android { packaging { jniLibs { pickFirsts += "**/libc++_shared.so" } } }
```

### Speech-to-text (STEP 9)

Memakai `sherpa_onnx` (Whisper ONNX int8 + Silero VAD), semuanya offline.
Model (Tiny/Base/Small) diunduh dari Hugging Face lewat tombol "Unduh model"
di kartu Transcript, disimpan di `<storage app>/models/`. Seluruh pemakaian
paket ada di satu file: `lib/services/transcription/sherpa_whisper_engine.dart`.

### Deteksi clip (STEP 11)

Offline penuh, tanpa model dan tanpa internet: `RuleBasedClipDetector` menilai
transcript (pertanyaan, kata kunci, angka, kepadatan bicara, durasi) dan
memilih rentang terbaik yang tidak tumpang tindih. Kata kunci ada di
`lib/services/ai/clip_keywords.dart` dan bisa disesuaikan. Detektor berbasis
model lokal dapat ditambahkan lewat interface `ClipDetector`.

### Face-aware crop (STEP 14)

Memakai `android.media.FaceDetector` bawaan Android (open-source AOSP, offline,
tanpa dependency/model unduhan) lewat kode native di `MainActivity.kt`.
**Salin ulang `native/android/MainActivity.kt`** ke project (ada metode baru
`detectFaces`). Hanya ~3-15 frame kecil per clip yang dibaca. Bila wajah tidak
terdeteksi atau komponen native belum terpasang, render otomatis memakai crop
tengah. Detektor dapat diganti lewat interface `VideoFaceDetector`.

### Ekspor ke galeri (STEP 16)

Kartu **Ekspor Clip** menyalin clip ke `Movies/AI Video Clipper` lewat
MediaStore (Android 10+ tanpa izin apa pun). SRT disimpan di
`Downloads/AI Video Clipper`. File asli di folder aplikasi tidak diubah.
**Salin ulang `native/android/MainActivity.kt`** (metode baru `exportFile`
dan `shareUri`).

Hanya untuk Android 9 ke bawah (minSdk 24-28) tambahkan di
`AndroidManifest.xml`, sebelum `<application>`:

```xml
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="28"/>
```

Izin akan diminta saat ekspor pertama. Android 10+ mengabaikan baris ini.

### Proses latar belakang (STEP 17)

Kartu **Proses Otomatis** menjalankan transkripsi, deteksi momen, render
(dan ekspor opsional) berurutan. Agar tetap berjalan saat aplikasi di latar
belakang dipakai foreground service native (tanpa dependency baru).

1. Salin juga `native/android/KeepAliveService.kt` ke folder yang sama dengan
   `MainActivity.kt`, dan **salin ulang `MainActivity.kt`**.
2. Di `android/app/src/main/AndroidManifest.xml`, sebelum `<application>`:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

3. Di dalam `<application>` (sejajar dengan `<activity>`):

```xml
<service
    android:name=".KeepAliveService"
    android:exported="false"
    android:foregroundServiceType="dataSync"/>
```

Tanpa langkah ini pipeline tetap jalan di layar depan, hanya tidak dilindungi
saat aplikasi di latar belakang. Pada Android 13+ izin notifikasi diminta
saat proses pertama; bila ditolak proses tetap berjalan tanpa notifikasi.
Beberapa merek (Xiaomi, Oppo, Vivo, dll.) tetap mematikan aplikasi agresif:
matikan "penghemat baterai" untuk aplikasi ini bila proses sering terhenti.

Bila aplikasi benar-benar tertutup di tengah proses, saat dibuka lagi job
yang terputus ditandai gagal, status project dipulihkan, dan file sementara
dibersihkan. Jalankan ulang dari kartu Proses Otomatis.

### Backend CI4 (STEP 18)

Folder `backend/` berisi API CodeIgniter 4 (lihat `backend/README.md`: instalasi,
deploy shared hosting, endpoint, SQL contoh). Backend HANYA untuk konfigurasi
global, versi, feature flag (dan nanti auth). Video/project/clip/transcript
tidak pernah dikirim ke server.

Di aplikasi, backend bersifat opsional dan offline-first. Aktifkan saat build:

```bash
flutter run --dart-define=API_BASE_URL=https://api.domain-anda.com
flutter build apk --release --dart-define=API_BASE_URL=https://api.domain-anda.com
```

Tanpa `API_BASE_URL` aplikasi 100% lokal seperti sebelumnya. Gunakan **https**
(Android 9+ memblokir http biasa). Izin INTERNET di release manifest sudah
disebut di bagian STEP 9. Konfigurasi di-cache di SQLite (`app_settings`),
memakai ETag, dan kegagalan jaringan tidak pernah menampilkan error teknis.
Kartu status di beranda menampilkan pemeliharaan, update tersedia/wajib, dan
status koneksi.

### Autentikasi (STEP 19)

Akun bersifat **opsional**: Pengaturan > Akun. Semua fitur lokal berjalan tanpa
masuk, dan tidak ada data video/project yang dikirim ke server. Aktif hanya bila
`API_BASE_URL` diisi (lihat STEP 18).

- Token disimpan di Android Keystore lewat `flutter_secure_storage` (^10.3.1,
  minSdk 23, kita memakai 24). Versi 11.x menaikkan `compileSdk` ke 37; naikkan
  hanya bila toolchain Android Anda sudah mendukung.
- Access token otomatis diperbarui lewat refresh token (satu refresh untuk banyak
  pemanggil bersamaan). Bila server menolak sesi, aplikasi keluar otomatis; bila
  hanya offline, sesi dipertahankan.
- Bila penyimpanan aman gagal menulis, sesi tidak dipakai (token tidak pernah
  disimpan di tempat tak aman).
- Keluar selalu menghapus sesi lokal walau server tidak terjangkau. Hapus akun
  menghapus akun di server saja; data lokal tidak disentuh.

### Pengaturan global & penyimpanan (STEP 20)

Admin mengubah konfigurasi lewat panel web backend (`/admin`, lihat `backend/README.md`).
Aplikasi membacanya (offline-first, di-cache) dan **membatasi** nilainya ke rentang aman
(`AppSettings.resolve`), jadi salah ketik di panel tidak merusak aplikasi:

| Kunci server | Efek di aplikasi | Rentang aman |
|---|---|---|
| `default_clip_duration_seconds` | Durasi target deteksi clip (min/maks diturunkan) | 15-180 |
| `max_clip_count` | Jumlah clip maksimal | 1-20 |
| `default_output_width/height` | Lebar <= 720 -> render 720x1280, selain itu otomatis | genap |
| `min_free_storage_mb` | Margin ruang kosong sebelum render + peringatan di halaman Penyimpanan | 100-10000 |
| flag `auto_pipeline` | Menampilkan/menyembunyikan kartu pemrosesan otomatis | - |
| flag `face_aware_crop` | Nilai awal opsi crop wajah | - |
| flag `export_srt` | Menu "Ekspor SRT" | - |

Tanpa server, semua memakai nilai bawaan lokal. Setting hanya berlaku pada proses
berikutnya (tidak mengubah clip yang sudah jadi).

**Penyimpanan** (Pengaturan > Penyimpanan): rincian per kategori, ruang kosong, peringatan
ruang menipis, bersihkan file sementara, dan hapus file yatim (clip/thumbnail buatan aplikasi
yang tidak lagi ada di database). Hanya folder privat aplikasi yang disentuh; video sumber,
video asli pengguna, dan hasil ekspor di galeri/Downloads tidak pernah dihapus. Pembersihan
ditolak saat pemrosesan berjalan.

### Ukuran APK

Library FFmpeg berukuran besar. Untuk APK yang diinstal ke satu perangkat,
bangun per arsitektur:

```bash
flutter build apk --split-per-abi
# pasang yang sesuai ponsel, biasanya app-arm64-v8a-release.apk
```

### Library FFmpeg

Memakai `ffmpeg_kit_flutter_new` (fork komunitas yang masih dipelihara dari
FFmpegKit; paket `ffmpeg_kit_flutter` asli sudah dihentikan). Varian bawaannya
membawa codec GPL (libx264), cukup untuk aplikasi pribadi yang tidak
didistribusikan. Seluruh pemakaian paket ada di satu file:
`lib/services/ffmpeg/ffmpeg_kit_runner.dart`.

Catatan:
- `flutter create .` tidak boleh menimpa `lib/`, `pubspec.yaml`, atau `test/` milik project ini;
  jika tertimpa, salin ulang dari zip.
- Baris `package` di `MainActivity.kt` harus sama dengan `applicationId` di `android/app/build.gradle(.kts)`.
- Pemilih video memakai Storage Access Framework: tidak perlu izin storage di AndroidManifest.

## Struktur

```
lib/
  main.dart
  app.dart
  core/{config,constants,errors,theme,utils}
  database/{migrations,models,repositories}
  features/{home,projects,video,transcription,ai,clips,editor,export,settings}
  services/{ffmpeg,storage,media_store,ai,transcription}
native/android/MainActivity.kt   (kode native: metadata, thumbnail, ruang kosong)
```
