import 'package:ai_video_clipper/database/models/clip_edit.dart';
import 'package:ai_video_clipper/services/subtitle/subtitle_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toMap/fromMap menjaga semua field termasuk gaya subtitle', () {
    final edit = ClipEdit(
      clipId: 7,
      cropMode: EditCropMode.manual,
      focusX: 0.25,
      focusY: 0.75,
      zoom: 2.5,
      burnSubtitles: false,
      style: SubtitlePresets.style(SubtitlePreset.bold),
    );
    final back = ClipEdit.fromMap(edit.toMap());
    expect(back.clipId, 7);
    expect(back.cropMode, EditCropMode.manual);
    expect(back.focusX, 0.25);
    expect(back.focusY, 0.75);
    expect(back.zoom, 2.5);
    expect(back.burnSubtitles, isFalse);
    expect(back.style?.preset, SubtitlePreset.bold);
    expect(back.style?.bold, isTrue);
  });

  test('tanpa gaya khusus -> style null; copyWith clearStyle', () {
    final map = const ClipEdit(clipId: 1).toMap();
    expect(map['style_json'], isNull);
    expect(ClipEdit.fromMap(map).style, isNull);

    final withStyle =
        ClipEdit(clipId: 1, style: SubtitlePresets.style(SubtitlePreset.minimal));
    expect(withStyle.copyWith(clearStyle: true).style, isNull);
  });

  test('JSON gaya rusak tidak membuat crash', () {
    final map = const ClipEdit(clipId: 1).toMap()..['style_json'] = '{rusak';
    expect(ClipEdit.fromMap(map).style, isNull);
  });

  test('nilai enum tak dikenal kembali ke default', () {
    final map = const ClipEdit(clipId: 1).toMap()..['crop_mode'] = 'aneh';
    expect(ClipEdit.fromMap(map).cropMode, EditCropMode.face);
  });
}
