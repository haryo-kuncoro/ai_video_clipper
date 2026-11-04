import 'dart:math' as math;

import '../../database/models/model_utils.dart';

enum SubtitlePosition {
  top,
  center,

  /// Sepertiga bawah (di atas area UI Reels/TikTok).
  lower,
  bottom;

  String get label {
    switch (this) {
      case SubtitlePosition.top:
        return 'Atas';
      case SubtitlePosition.center:
        return 'Tengah';
      case SubtitlePosition.lower:
        return 'Bawah 1/3';
      case SubtitlePosition.bottom:
        return 'Bawah';
    }
  }
}

enum SubtitlePreset {
  classic,
  bold,
  minimal,
  social,
  custom;

  String get label {
    switch (this) {
      case SubtitlePreset.classic:
        return 'Classic';
      case SubtitlePreset.bold:
        return 'Bold';
      case SubtitlePreset.minimal:
        return 'Minimal';
      case SubtitlePreset.social:
        return 'Social';
      case SubtitlePreset.custom:
        return 'Custom';
    }
  }
}

/// Font yang dijamin ada di Android (alias sistem).
const List<String> subtitleFontFamilies = [
  'sans-serif',
  'sans-serif-condensed',
  'serif',
  'monospace',
];

/// Gaya subtitle. Ukuran font dinyatakan untuk lebar output 1080 px dan
/// otomatis diskalakan untuk resolusi lain (mis. 720).
class SubtitleStyle {
  const SubtitleStyle({
    this.preset = SubtitlePreset.classic,
    this.fontFamily = 'sans-serif',
    this.fontSize = 52,
    this.position = SubtitlePosition.bottom,
    this.outlineWidth = 3,
    this.shadow = false,
    this.background = false,
    this.maxCharsPerLine = 28,
    this.enabled = true,
    this.bold = false,
    this.uppercase = false,
    this.textColor = 0xFFFFFFFF,
    this.outlineColor = 0xFF000000,
  });

  final SubtitlePreset preset;
  final String fontFamily;
  final int fontSize;
  final SubtitlePosition position;
  final double outlineWidth;
  final bool shadow;
  final bool background;
  final int maxCharsPerLine;
  final bool enabled;
  final bool bold;
  final bool uppercase;

  /// ARGB, mis. 0xFFFFFFFF = putih.
  final int textColor;
  final int outlineColor;

  SubtitleStyle copyWith({
    SubtitlePreset? preset,
    String? fontFamily,
    int? fontSize,
    SubtitlePosition? position,
    double? outlineWidth,
    bool? shadow,
    bool? background,
    int? maxCharsPerLine,
    bool? enabled,
    bool? bold,
    bool? uppercase,
    int? textColor,
    int? outlineColor,
  }) {
    return SubtitleStyle(
      preset: preset ?? this.preset,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      position: position ?? this.position,
      outlineWidth: outlineWidth ?? this.outlineWidth,
      shadow: shadow ?? this.shadow,
      background: background ?? this.background,
      maxCharsPerLine: maxCharsPerLine ?? this.maxCharsPerLine,
      enabled: enabled ?? this.enabled,
      bold: bold ?? this.bold,
      uppercase: uppercase ?? this.uppercase,
      textColor: textColor ?? this.textColor,
      outlineColor: outlineColor ?? this.outlineColor,
    );
  }

  /// Salinan dengan nilai dibatasi ke rentang aman.
  SubtitleStyle normalized() {
    return copyWith(
      fontSize: fontSize.clamp(20, 140).toInt(),
      outlineWidth: outlineWidth.clamp(0.0, 12.0).toDouble(),
      maxCharsPerLine: maxCharsPerLine.clamp(8, 60).toInt(),
      fontFamily:
          subtitleFontFamilies.contains(fontFamily) ? fontFamily : 'sans-serif',
    );
  }

  Map<String, Object?> toMap() {
    final s = normalized();
    return {
      'preset': s.preset.name,
      'font_family': s.fontFamily,
      'font_size': s.fontSize,
      'position': s.position.name,
      'outline_width': s.outlineWidth,
      'shadow': s.shadow ? 1 : 0,
      'background': s.background ? 1 : 0,
      'max_chars_per_line': s.maxCharsPerLine,
      'enabled': s.enabled ? 1 : 0,
      'bold': s.bold ? 1 : 0,
      'uppercase': s.uppercase ? 1 : 0,
      'text_color': s.textColor,
      'outline_color': s.outlineColor,
    };
  }

  factory SubtitleStyle.fromMap(Map<String, Object?> m) {
    return SubtitleStyle(
      preset: enumByName(
          SubtitlePreset.values, m['preset'] as String?, SubtitlePreset.classic),
      fontFamily: (m['font_family'] as String?) ?? 'sans-serif',
      fontSize: (m['font_size'] as num?)?.toInt() ?? 52,
      position: enumByName(SubtitlePosition.values, m['position'] as String?,
          SubtitlePosition.bottom),
      outlineWidth: (m['outline_width'] as num?)?.toDouble() ?? 3,
      shadow: (m['shadow'] as num?) == 1,
      background: (m['background'] as num?) == 1,
      maxCharsPerLine: (m['max_chars_per_line'] as num?)?.toInt() ?? 28,
      enabled: (m['enabled'] as num?) != 0,
      bold: (m['bold'] as num?) == 1,
      uppercase: (m['uppercase'] as num?) == 1,
      textColor: (m['text_color'] as num?)?.toInt() ?? 0xFFFFFFFF,
      outlineColor: (m['outline_color'] as num?)?.toInt() ?? 0xFF000000,
    ).normalized();
  }
}

/// Preset bawaan.
class SubtitlePresets {
  SubtitlePresets._();

  static const List<SubtitlePreset> selectable = [
    SubtitlePreset.classic,
    SubtitlePreset.bold,
    SubtitlePreset.minimal,
    SubtitlePreset.social,
  ];

  static SubtitleStyle style(SubtitlePreset preset) {
    switch (preset) {
      case SubtitlePreset.classic:
      case SubtitlePreset.custom:
        return const SubtitleStyle(
          preset: SubtitlePreset.classic,
          fontSize: 52,
          outlineWidth: 3,
          maxCharsPerLine: 28,
        );
      case SubtitlePreset.bold:
        return const SubtitleStyle(
          preset: SubtitlePreset.bold,
          fontSize: 60,
          bold: true,
          outlineWidth: 5,
          shadow: true,
          maxCharsPerLine: 24,
        );
      case SubtitlePreset.minimal:
        return const SubtitleStyle(
          preset: SubtitlePreset.minimal,
          fontSize: 44,
          outlineWidth: 0,
          shadow: true,
          maxCharsPerLine: 32,
        );
      case SubtitlePreset.social:
        return const SubtitleStyle(
          preset: SubtitlePreset.social,
          fontSize: 68,
          bold: true,
          uppercase: true,
          textColor: 0xFFFFE600,
          outlineWidth: 7,
          shadow: true,
          position: SubtitlePosition.lower,
          maxCharsPerLine: 18,
        );
    }
  }
}

/// Posisi vertikal (piksel dari atas) untuk pita subtitle setinggi
/// [bandHeight] pada frame setinggi [outHeight]. Posisi bawah sengaja
/// dinaikkan agar tidak tertutup UI Reels/TikTok/Shorts.
int subtitleY({
  required SubtitlePosition position,
  required int outHeight,
  required int bandHeight,
}) {
  final double y = switch (position) {
    SubtitlePosition.top => outHeight * 0.10,
    SubtitlePosition.center => (outHeight - bandHeight) / 2,
    SubtitlePosition.lower => outHeight * 0.74 - bandHeight,
    SubtitlePosition.bottom => outHeight * 0.86 - bandHeight,
  };
  final maxY = math.max(0, outHeight - bandHeight);
  return y.round().clamp(0, maxY).toInt();
}
