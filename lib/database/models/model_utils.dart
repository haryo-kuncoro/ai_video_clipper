/// Mencari enum berdasarkan nama; memakai [fallback] bila tidak dikenal
/// (aman terhadap data lama / versi aplikasi berbeda).
T enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

DateTime fromEpochMs(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

int toEpochMs(DateTime d) => d.millisecondsSinceEpoch;
