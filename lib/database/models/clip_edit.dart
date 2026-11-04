import 'dart:convert';

import '../../services/subtitle/subtitle_style.dart';
import 'model_utils.dart';

enum EditCropMode {
  /// Potong di tengah.
  center,

  /// Mengikuti wajah (deteksi lokal), fallback ke tengah.
  face,

  /// Posisi dan zoom ditentukan pengguna.
  manual;

  String get label {
    switch (this) {
      case EditCropMode.center:
        return 'Tengah';
      case EditCropMode.face:
        return 'Wajah';
      case EditCropMode.manual:
        return 'Manual';
    }
  }
}

/// Pengaturan edit satu clip (disimpan agar dapat diedit ulang).
class ClipEdit {
  const ClipEdit({
    required this.clipId,
    this.cropMode = EditCropMode.face,
    this.focusX,
    this.focusY,
    this.zoom = 1.0,
    this.burnSubtitles = true,
    this.style,
  });

  final int clipId;
  final EditCropMode cropMode;

  /// Titik fokus crop manual, 0.0 - 1.0 (null = tengah).
  final double? focusX;
  final double? focusY;

  /// 1.0 - 4.0, hanya untuk crop manual.
  final double zoom;
  final bool burnSubtitles;

  /// Gaya subtitle khusus clip ini; null = pakai gaya project.
  final SubtitleStyle? style;

  ClipEdit copyWith({
    EditCropMode? cropMode,
    double? focusX,
    double? focusY,
    double? zoom,
    bool? burnSubtitles,
    SubtitleStyle? style,
    bool clearStyle = false,
  }) =>
      ClipEdit(
        clipId: clipId,
        cropMode: cropMode ?? this.cropMode,
        focusX: focusX ?? this.focusX,
        focusY: focusY ?? this.focusY,
        zoom: zoom ?? this.zoom,
        burnSubtitles: burnSubtitles ?? this.burnSubtitles,
        style: clearStyle ? null : (style ?? this.style),
      );

  factory ClipEdit.fromMap(Map<String, Object?> m) {
    SubtitleStyle? style;
    final json = m['style_json'] as String?;
    if (json != null && json.isNotEmpty) {
      try {
        style = SubtitleStyle.fromMap(
            (jsonDecode(json) as Map).cast<String, Object?>());
      } catch (_) {
        style = null; // data rusak: pakai gaya project
      }
    }
    return ClipEdit(
      clipId: m['clip_id'] as int,
      cropMode:
          enumByName(EditCropMode.values, m['crop_mode'] as String?, EditCropMode.face),
      focusX: (m['focus_x'] as num?)?.toDouble(),
      focusY: (m['focus_y'] as num?)?.toDouble(),
      zoom: (m['zoom'] as num?)?.toDouble() ?? 1.0,
      burnSubtitles: (m['burn_subtitles'] as num?) != 0,
      style: style,
    );
  }

  Map<String, Object?> toMap() => {
        'clip_id': clipId,
        'crop_mode': cropMode.name,
        'focus_x': focusX,
        'focus_y': focusY,
        'zoom': zoom,
        'burn_subtitles': burnSubtitles ? 1 : 0,
        'style_json': style == null ? null : jsonEncode(style!.toMap()),
        'updated_at': toEpochMs(DateTime.now()),
      };
}
