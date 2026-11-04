import 'package:ai_video_clipper/database/models/video_record.dart';
import 'package:ai_video_clipper/features/video/player/player_math.dart';
import 'package:ai_video_clipper/features/video/player/video_player_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('player_math', () {
    test('clampSeekMs membatasi ke rentang durasi', () {
      expect(clampSeekMs(-500, 60000), 0);
      expect(clampSeekMs(30000, 60000), 30000);
      expect(clampSeekMs(90000, 60000), 60000);
      expect(clampSeekMs(100, 0), 0);
    });

    test('skipMs maju/mundur dan tidak keluar rentang', () {
      expect(skipMs(30000, 10000, 60000), 40000);
      expect(skipMs(5000, -10000, 60000), 0);
      expect(skipMs(55000, 10000, 60000), 60000);
    });

    test('progressFraction aman untuk durasi 0', () {
      expect(progressFraction(30000, 60000), 0.5);
      expect(progressFraction(10, 0), 0);
      expect(progressFraction(90000, 60000), 1.0);
    });

    test('kecepatan berputar dan label', () {
      expect(nextPlaybackSpeed(1.0), 1.5);
      expect(nextPlaybackSpeed(2.0), 0.5);
      expect(nextPlaybackSpeed(3.0), 1.0);
      expect(speedLabel(1.0), '1x');
      expect(speedLabel(1.5), '1.5x');
    });
  });

  testWidgets('file video hilang: tampil pesan error, tidak crash',
      (tester) async {
    final video = VideoRecord(
      id: 1,
      projectId: 1,
      filePath: '/path/yang/tidak/ada/source.mp4',
      fileName: 'source.mp4',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VideoPlayerPanel(video: video)),
      ),
    );
    await tester.pump();

    expect(find.text('File video tidak ditemukan di perangkat.'),
        findsOneWidget);
  });
}
