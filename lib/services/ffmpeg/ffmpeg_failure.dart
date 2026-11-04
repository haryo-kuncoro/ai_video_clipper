/// Mengubah log FFmpeg menjadi pesan yang mudah dipahami pengguna.
/// Urutan pengecekan penting: penyebab paling spesifik lebih dulu.
String mapFFmpegFailure(String logs) {
  final l = logs.toLowerCase();

  if (l.contains('no space left')) {
    return 'Storage tidak cukup untuk memproses video.';
  }
  if (l.contains('does not contain any stream')) {
    return 'Video tidak memiliki audio atau stream yang dibutuhkan.';
  }
  if (l.contains('moov atom not found')) {
    return 'File video rusak atau tidak lengkap.';
  }
  if (l.contains('permission denied')) {
    return 'Tidak dapat mengakses file video.';
  }
  if (l.contains('no such file')) {
    return 'File video tidak ditemukan.';
  }
  if (l.contains('unsupported') ||
      l.contains('invalid data found') ||
      l.contains('unknown decoder') ||
      l.contains('decoder not found')) {
    return 'Format atau codec video tidak didukung.';
  }
  return 'Proses video gagal. Silakan coba lagi.';
}
