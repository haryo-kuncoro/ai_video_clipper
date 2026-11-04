# Terjemahan otomatis (mis. talkshow Korea -> subtitle Indonesia)

Alur di kartu "Proses Otomatis":
1. Pilih **Bahasa** = Korea (atau Jepang/Mandarin/Inggris).
2. Aktifkan **Terjemahkan ke Indonesia**.
3. Mulai. Urutan: transkripsi (Whisper, bahasa asli) -> terjemahan -> deteksi momen -> render.

Catatan:
- Terjemahan memakai ML Kit **on-device**: model bahasa (±30 MB per bahasa) diunduh
  SEKALI, setelah itu offline. Teks/video tidak dikirim ke server.
- Teks asli disimpan di `source_text`; `text` = terjemahan. Subtitle, editor, dan
  deteksi clip otomatis memakai terjemahan (deteksi memakai kata kunci Indonesia,
  jadi hasilnya lebih baik daripada pada teks Korea).
- Untuk bahasa Korea, pakai model Whisper **Small** bila HP kuat (akurasi jauh
  lebih baik daripada Tiny/Base). Unduh dulu di kartu Transkripsi.
- Transcript lama bisa diterjemahkan tanpa transkripsi ulang: biarkan
  "Pakai transcript yang sudah ada" menyala dan pilih bahasa sumber yang benar.
- Kualitas: terjemahan mesin ringan; slang/humor talkshow bisa kurang natural.
  Subtitle bisa dikoreksi di editor clip.

Instalasi: `flutter pub add google_mlkit_translation` (JANGAN timpa pubspec.yang
sudah Anda upgrade; cukup tambah satu baris itu), lalu `flutter pub get`.

## Model AI (v0.22.0)
- Unduh/hapus model dilakukan di **Pengaturan > Model AI** (STT Tiny/Base/Small
  dan model terjemahan per bahasa). Halaman project tidak lagi mengunduh model.
- Tombol "Mulai proses otomatis" dan "Buat transcript" nonaktif + keterangan
  bila model yang dibutuhkan belum ada. Untuk Korea -> Indonesia unduh:
  model STT (disarankan Small), terjemahan Korea, dan terjemahan Indonesia.

## Gaya subtitle default
- Kartu "Proses Otomatis" > **Gaya subtitle**: atur sebelum mulai (berlaku untuk
  project ini), atau tekan **Jadikan default** agar semua render berikutnya
  memakai gaya itu.
- **Alat uji teknis** > Subtitle: atur gaya, **Pratinjau** (15 detik, teks contoh),
  lalu **Simpan sebagai default**. Pratinjau tidak lagi menyimpan gaya per project.
- Bila sebuah project punya gaya sendiri, ada tombol "Pakai gaya default".
