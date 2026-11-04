import 'dart:io';

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_video_clipper/app.dart';
import 'package:ai_video_clipper/core/theme/theme_controller.dart';
import 'package:ai_video_clipper/services/storage/app_paths.dart';

void main() {
  late Directory tmp;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('avc_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('AppPaths membuat semua folder lokal', () async {
    final paths = await AppPaths.fromBase(tmp);
    expect(paths.videos.existsSync(), isTrue);
    expect(paths.projects.existsSync(), isTrue);
    expect(paths.clips.existsSync(), isTrue);
    expect(paths.thumbnails.existsSync(), isTrue);
    expect(paths.temp.existsSync(), isTrue);
  });

  testWidgets('Home menampilkan judul dan tombol project baru',
      (tester) async {
    // Layar tinggi agar seluruh isi ListView ikut dibangun.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final paths = await tester.runAsync(() => AppPaths.fromBase(tmp));
    await tester.pumpWidget(
      AiVideoClipperApp(themeController: ThemeController(), paths: paths),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI VIDEO CLIPPER'), findsOneWidget);
    expect(find.text('PROJECT BARU'), findsOneWidget);
    expect(find.text('Folder lokal siap'), findsOneWidget);
  });
}
