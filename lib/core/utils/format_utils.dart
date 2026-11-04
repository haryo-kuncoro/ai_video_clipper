/// Durasi video sumber untuk kartu project, mis. "23 menit".
String formatSourceDuration(int? ms) {
  if (ms == null || ms <= 0) return 'Belum ada video';
  final totalSeconds = ms ~/ 1000;
  if (totalSeconds < 60) return '$totalSeconds detik';
  final totalMinutes = totalSeconds ~/ 60;
  if (totalMinutes < 60) return '$totalMinutes menit';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return minutes == 0 ? '$hours jam' : '$hours jam $minutes menit';
}

/// Durasi jam digital: "23:05" atau "1:02:03".
String formatClockDuration(int ms) {
  final total = ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Ukuran file: "512 B", "1.5 MB", "2.0 GB".
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[i]}';
}

/// Tanggal relatif: "Hari ini", "Kemarin", "3 hari lalu", atau dd/MM/yyyy.
String formatRelativeDate(DateTime date, {DateTime? now}) {
  final n = now ?? DateTime.now();
  // Pakai UTC agar selisih hari tidak terpengaruh perubahan jam (DST).
  final today = DateTime.utc(n.year, n.month, n.day);
  final day = DateTime.utc(date.year, date.month, date.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Hari ini';
  if (diff == 1) return 'Kemarin';
  if (diff < 7) return '$diff hari lalu';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(day.day)}/${two(day.month)}/${day.year}';
}
