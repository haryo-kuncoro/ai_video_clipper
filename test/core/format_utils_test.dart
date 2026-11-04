import 'package:ai_video_clipper/core/utils/format_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatSourceDuration', () {
    test('tanpa video', () {
      expect(formatSourceDuration(null), 'Belum ada video');
      expect(formatSourceDuration(0), 'Belum ada video');
    });

    test('detik, menit, jam', () {
      expect(formatSourceDuration(45000), '45 detik');
      expect(formatSourceDuration(23 * 60 * 1000), '23 menit');
      expect(formatSourceDuration(2 * 3600 * 1000), '2 jam');
      expect(formatSourceDuration((3600 + 5 * 60) * 1000), '1 jam 5 menit');
    });
  });

  test('formatClockDuration', () {
    expect(formatClockDuration(5000), '0:05');
    expect(formatClockDuration((23 * 60 + 5) * 1000), '23:05');
    expect(formatClockDuration((3600 + 2 * 60 + 3) * 1000), '1:02:03');
  });

  test('formatFileSize', () {
    expect(formatFileSize(500), '500 B');
    expect(formatFileSize(1536 * 1024), '1.5 MB');
    expect(formatFileSize(150 * 1024 * 1024), '150 MB');
    expect(formatFileSize(2 * 1024 * 1024 * 1024), '2.0 GB');
  });

  group('formatRelativeDate', () {
    final now = DateTime(2026, 10, 21, 10);

    test('hari ini dan kemarin', () {
      expect(formatRelativeDate(DateTime(2026, 10, 21, 1), now: now),
          'Hari ini');
      expect(formatRelativeDate(DateTime(2026, 10, 20, 23), now: now),
          'Kemarin');
    });

    test('beberapa hari lalu dan tanggal', () {
      expect(formatRelativeDate(DateTime(2026, 10, 18), now: now),
          '3 hari lalu');
      expect(formatRelativeDate(DateTime(2026, 9, 5), now: now),
          '05/09/2026');
    });
  });
}
