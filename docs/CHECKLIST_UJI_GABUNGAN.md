# Checklist Uji Gabungan - AI Video Clipper v0.20.0 (STEP 1-20)

Kode Flutter belum pernah dikompilasi oleh pembuatnya. Jalankan urutan A dulu; kirim hasil error bila ada.
Tandai tiap baris: [ ] belum, [x] lolos, [!] gagal (catat pesan).

## A. Persiapan & build
- [ ] `flutter create --org com.haryo --project-name ai_video_clipper --platforms=android .` (jangan timpa lib/, pubspec.yaml, test/)
- [ ] Salin `native/android/MainActivity.kt` dan `KeepAliveService.kt`; samakan `package` dengan applicationId
- [ ] Manifest: izin FOREGROUND_SERVICE, FOREGROUND_SERVICE_DATA_SYNC, POST_NOTIFICATIONS, WRITE_EXTERNAL_STORAGE (maxSdk 28), INTERNET (release), dan `<service .KeepAliveService foregroundServiceType="dataSync">` (lihat README)
- [ ] minSdk 24; `flutter pub get` sukses
- [ ] `flutter analyze` tanpa error
- [ ] `flutter test` hijau (catat tes yang gagal)
- [ ] `flutter run` (tanpa API_BASE_URL) membuka beranda "v0.20.0 - STEP 20 Pengaturan"

## B. Fondasi (STEP 1-3)
- [ ] Tema Sistem/Terang/Gelap berpindah dan bertahan setelah restart
- [ ] Buat project, ubah nama, hapus project (file project terhapus, video asli pengguna tidak)
- [ ] Error ramah (tanpa stack trace) saat input kosong

## C. Video (STEP 4-5)
- [ ] Pilih video lewat picker (tanpa izin storage), metadata/thumbnail muncul
- [ ] Video landscape dan portrait terbaca benar; format tak valid -> pesan ramah
- [ ] Player: play/pause, seek, posisi benar

## D. FFmpeg, portrait, subtitle (STEP 6-8)
- [ ] (Alat uji teknis terlipat di detail project) FFmpeg jalan, batalkan berfungsi
- [ ] Konversi 9:16: blur background, crop tengah, crop manual
- [ ] Subtitle dirender: gaya, posisi, teks Indonesia tampil benar
- [ ] Terjemahan: bahasa Korea + "Terjemahkan ke Indonesia" -> subtitle Indonesia, model terunduh sekali (docs/TERJEMAHAN.md)

## E. STT & transcript (STEP 9-10)
- [ ] Unduh model Whisper (cek URL model valid; jika gagal, catat)
- [ ] Transkripsi video pendek (Indonesia) selesai, progres tampil, bisa dibatalkan
- [ ] Transcript bisa dilihat/diedit/dicari; ekspor SRT/TXT

## F. Deteksi & review clip (STEP 11-12)
- [ ] Deteksi menghasilkan kandidat dengan skor; preset Pendek/Standar/Panjang
- [ ] Terima/tolak/ubah batas waktu kandidat; tersimpan setelah restart

## G. Render & face-aware (STEP 13-14)
- [ ] Render semua kandidat diterima -> clip 9:16 tersimpan, thumbnail ada
- [ ] Face-aware aktif: wajah tetap di frame; matikan -> crop tengah
- [ ] Ruang penyimpanan kurang -> pesan ramah, bukan crash

## H. Editor & ekspor (STEP 15-16)
- [ ] Editor clip: geser waktu mulai/akhir, mode crop/zoom, gaya subtitle; render ulang menggantikan clip
- [ ] Simpan ke galeri: muncul di Movies/AI Video Clipper (Android 10+ dan, bila ada, Android 9-)
- [ ] Ekspor SRT ke Downloads/AI Video Clipper; Bagikan membuka share sheet
- [ ] File asli di folder aplikasi tidak berubah

## I. Latar belakang (STEP 17)
- [ ] Kartu pemrosesan otomatis: transkripsi -> deteksi -> render (-> ekspor opsional)
- [ ] Notifikasi progres muncul; pindah halaman/kunci layar tidak menghentikan
- [ ] Batalkan menghentikan proses; hanya satu proses sekaligus
- [ ] Matikan paksa aplikasi saat proses -> buka lagi: job ditandai gagal, project tidak macet
- [ ] (Xiaomi/Oppo dll) cek apakah proses dimatikan sistem; catat

## J. Backend CI4 (STEP 18)
- [ ] `cd backend && composer install`, salin `env` ke `.env`, set database MySQL
- [ ] `php spark migrate` dan `php spark db:seed DefaultConfigSeeder`
- [ ] `php scripts/smoke.php https://domain-anda` -> semua OK
- [ ] `GET /api/v1/health`, `/app/config`, `/app/version` benar; ETag -> 304
- [ ] Mode produksi: error JSON tanpa jejak file

## K. Autentikasi (STEP 19)
- [ ] `php scripts/auth_flow.php https://domain-anda` -> semua OK
- [ ] Build dengan `--dart-define=API_BASE_URL=https://domain-anda`
- [ ] Daftar, keluar, masuk; sesi bertahan setelah restart
- [ ] Sandi salah 5x -> terkunci, pesan tetap generik
- [ ] Ganti sandi, hapus akun (data lokal aman)
- [ ] Tanpa internet: aplikasi tetap penuh berfungsi, tidak ada error teknis
- [ ] Tanpa API_BASE_URL: tidak ada permintaan jaringan sama sekali

## L. Pengaturan global & penyimpanan (STEP 20)
- [ ] `php spark admin:promote email` lalu login di `/admin`; user biasa ditolak
- [ ] Ubah `max_clip_count` ke 5 -> buka ulang aplikasi/refresh -> slider/pipeline memakai 5
- [ ] Nilai tak masuk akal (mis. 9999) -> aplikasi tetap membatasi ke 20
- [ ] Matikan flag `auto_pipeline` -> kartu pemrosesan otomatis hilang
- [ ] Matikan flag `export_srt` -> menu Ekspor SRT hilang
- [ ] `default_output_width=720` -> clip baru 720x1280
- [ ] Rilis versi baru dengan build lebih tinggi -> kartu update muncul; min_supported > build -> update wajib
- [ ] Mode pemeliharaan menampilkan pesan di aplikasi
- [ ] Log audit mencatat setiap perubahan
- [ ] Pengaturan > Penyimpanan: rincian benar, ruang kosong tampil
- [ ] Bersihkan file sementara berjalan; hapus file yatim meminta konfirmasi; video asli & galeri utuh
- [ ] Saat pemrosesan berjalan, pembersihan ditolak dengan pesan ramah

## M. Keamanan & privasi
- [ ] Lalu lintas jaringan aplikasi hanya ke domain API (tidak ada video/transcript terkirim)
- [ ] Tidak ada stack trace di UI maupun respons API produksi
- [ ] `/admin` dibatasi (IP/basic-auth) di produksi, `cookie.secure=true`
