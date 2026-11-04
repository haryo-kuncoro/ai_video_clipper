/// Kata kunci untuk penilaian rule-based (Indonesia + Inggris, huruf kecil).
/// Sengaja berupa data terpisah agar mudah disesuaikan tanpa mengubah logika.
abstract final class ClipKeywords {
  /// Kata tanya: pembuka berupa pertanyaan menarik perhatian.
  static const questionWords = {
    'apa', 'apakah', 'kenapa', 'mengapa', 'bagaimana', 'gimana', 'siapa',
    'kapan', 'dimana', 'berapa', 'why', 'how', 'what', 'who', 'when',
  };

  /// Kata pemancing perhatian / nilai informasi.
  static const attention = {
    'rahasia', 'ternyata', 'kesalahan', 'jangan', 'penting', 'tips', 'cara',
    'kunci', 'faktanya', 'fakta', 'sebenarnya', 'harus', 'wajib', 'pelajaran',
    'masalah', 'solusi', 'strategi', 'pertama', 'terakhir', 'alasan',
    'secret', 'mistake', 'never', 'actually', 'important', 'truth', 'lesson',
    'problem', 'solution', 'always', 'must',
  };

  /// Kata beremosi / penekanan kuat.
  static const emotion = {
    'gila', 'parah', 'bahaya', 'takut', 'bangga', 'sukses',
    'gagal', 'hancur', 'bohong', 'sakit', 'kaget', 'mustahil', 'keren',
    'amazing', 'crazy', 'insane', 'worst', 'best', 'shocking', 'fail',
  };

  /// Kata pembuka kosong yang dibuang saat membuat judul.
  static const leadingFillers = {
    'jadi', 'nah', 'oke', 'ok', 'ya', 'dan', 'terus', 'kemudian', 'lalu',
    'so', 'and', 'well', 'okay', 'yeah', 'um', 'eh', 'hmm',
  };
}
