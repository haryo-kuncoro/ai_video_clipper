import 'package:ai_video_clipper/services/face/face_models.dart';
import 'package:ai_video_clipper/services/face/focus_planner.dart';
import 'package:ai_video_clipper/services/face/native_face_detector.dart';
import 'package:flutter_test/flutter_test.dart';

FaceSample s(int t, [List<FaceBox> faces = const []]) =>
    FaceSample(timeMs: t, faces: faces);
FaceBox f(double x, {double y = 0.4, double size = 0.1}) =>
    FaceBox(x: x, y: y, size: size);

void main() {
  group('sampleTimes', () {
    test('tersebar merata di dalam rentang', () {
      final t = sampleTimes(10000, 40000);
      expect(t.length, 15);
      expect(t.first, greaterThan(10000));
      expect(t.last, lessThan(40000));
      expect([...t]..sort(), t);
    });

    test('clip pendek tetap mendapat minimal 3 sampel', () {
      expect(sampleTimes(0, 3000).length, 3);
    });

    test('batas maksimum dan rentang tidak valid', () {
      expect(sampleTimes(0, 600000).length, 15);
      expect(sampleTimes(5000, 5000), isEmpty);
      expect(sampleTimes(5000, 1000), isEmpty);
    });
  });

  group('planFocus', () {
    test('median tahan terhadap deteksi keliru', () {
      final r = planFocus([
        s(0, [f(0.70)]),
        s(1, [f(0.72)]),
        s(2, [f(0.10)]), // keliru
        s(3, [f(0.71)]),
        s(4, [f(0.69)]),
      ])!;
      expect(r.x, closeTo(0.70, 0.02));
      expect(r.hits, 5);
      expect(r.samples, 5);
    });

    test('memilih wajah terbesar per frame', () {
      final r = planFocus([
        s(0, [f(0.2, size: 0.05), f(0.8, size: 0.2)]),
        s(1, [f(0.2, size: 0.05), f(0.8, size: 0.2)]),
      ])!;
      expect(r.x, 0.8);
    });

    test('wajah terlalu kecil dianggap derau', () {
      expect(planFocus([s(0, [f(0.5, size: 0.01)])]), isNull);
    });

    test('terlalu jarang terdeteksi -> null (fallback center)', () {
      final samples = [
        s(0, [f(0.6)]),
        for (var i = 1; i < 10; i++) s(i),
      ];
      expect(planFocus(samples), isNull); // 1/10 < 30%
      expect(planFocus(samples, minHitRatio: 0.1), isNotNull);
    });

    test('kosong -> null; jumlah genap memakai rata-rata dua tengah', () {
      expect(planFocus(const []), isNull);
      final r = planFocus([s(0, [f(0.4)]), s(1, [f(0.6)])])!;
      expect(r.x, closeTo(0.5, 1e-9));
    });
  });

  group('parseFaceSamples', () {
    test('mengurai balasan native dan melewati entri rusak', () {
      final out = parseFaceSamples([
        {
          'timeMs': 1000,
          'faces': [
            {'x': 0.5, 'y': 0.4, 'size': 0.12},
            {'x': 'rusak'},
            {'x': 1.7, 'y': -0.2, 'size': 0.1},
          ],
        },
        'bukan map',
        {'faces': []},
        {'timeMs': 2000},
      ]);
      expect(out.length, 2);
      expect(out[0].faces.length, 2);
      expect(out[0].faces[1].x, 1.0);
      expect(out[0].faces[1].y, 0.0);
      expect(out[1].faces, isEmpty);
    });
  });
}
