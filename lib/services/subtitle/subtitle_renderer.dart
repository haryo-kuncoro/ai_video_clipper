import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ffmpeg/subtitle_overlay.dart';
import 'subtitle_cue.dart';
import 'subtitle_style.dart';

/// Merender cue menjadi gambar PNG transparan memakai mesin teks Flutter.
///
/// Keuntungan dibanding subtitle berbasis font/libass: tampilan sama persis di
/// semua perangkat, mendukung outline, bayangan, kotak latar, dan semua
/// karakter yang didukung font sistem Android.
class SubtitleRenderer {
  /// Menulis satu PNG per cue ke [outDir] dan mengembalikan daftar overlay.
  ///
  /// PNG selebar [outWidth] (pita horizontal setinggi teks); ukuran font
  /// diskalakan dari acuan lebar 1080 px.
  Future<List<SubtitleOverlay>> render({
    required List<SubtitleCue> cues,
    required SubtitleStyle style,
    required int outWidth,
    required int outHeight,
    required Directory outDir,
  }) async {
    final s = style.normalized();
    await outDir.create(recursive: true);

    final overlays = <SubtitleOverlay>[];
    for (var i = 0; i < cues.length; i++) {
      final cue = cues[i];
      final rendered = await _renderCue(cue, s, outWidth);
      final file =
          File('${outDir.path}/cue_${i.toString().padLeft(4, '0')}.png');
      await file.writeAsBytes(rendered.bytes, flush: true);

      overlays.add(SubtitleOverlay(
        imagePath: file.path,
        startMs: cue.startMs,
        endMs: cue.endMs,
        y: subtitleY(
          position: s.position,
          outHeight: outHeight,
          bandHeight: rendered.height,
        ),
      ));
    }
    return overlays;
  }

  Future<({List<int> bytes, int height})> _renderCue(
    SubtitleCue cue,
    SubtitleStyle s,
    int outWidth,
  ) async {
    final scale = outWidth / 1080.0;
    final fontSize = s.fontSize * scale;
    final outline = s.outlineWidth * scale;
    final text = s.uppercase ? cue.text.toUpperCase() : cue.text;

    final base = TextStyle(
      fontFamily: s.fontFamily,
      fontSize: fontSize,
      fontWeight: s.bold ? FontWeight.w800 : FontWeight.w500,
      height: 1.2,
    );

    final fillStyle = base.copyWith(
      color: Color(s.textColor),
      shadows: s.shadow
          ? [
              Shadow(
                color: const Color(0xCC000000),
                offset: Offset(0, 3 * scale),
                blurRadius: 6 * scale,
              ),
            ]
          : null,
    );

    final maxTextWidth = outWidth * 0.9;

    TextPainter layoutPainter(TextStyle style) {
      return TextPainter(
        text: TextSpan(text: text, style: style),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxTextWidth);
    }

    final fill = layoutPainter(fillStyle);
    final stroke = outline > 0
        ? layoutPainter(base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = outline * 2
              ..strokeJoin = StrokeJoin.round
              ..color = Color(s.outlineColor),
          ))
        : null;

    final padX = s.background ? fontSize * 0.5 : 0.0;
    final padY = s.background ? fontSize * 0.3 : 0.0;
    // Ruang ekstra untuk outline dan bayangan agar tidak terpotong.
    final extra = outline + (s.shadow ? 8 * scale : 0) + 4;

    final textW = fill.width;
    final textH = fill.height;
    final bandW = outWidth;
    final bandH = (textH + 2 * padY + 2 * extra).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      Rect.fromLTWH(0, 0, bandW.toDouble(), bandH.toDouble()),
    );

    final textLeft = (bandW - textW) / 2;

    if (s.background) {
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(textLeft - padX, extra, textW + 2 * padX, textH + 2 * padY),
        Radius.circular(fontSize * 0.3),
      );
      canvas.drawRRect(box, Paint()..color = const Color(0x99000000));
    }

    final offset = Offset(textLeft, extra + padY);
    stroke?.paint(canvas, offset);
    fill.paint(canvas, offset);

    final picture = recorder.endRecording();
    final image = await picture.toImage(bandW, math.max(1, bandH));
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    fill.dispose();
    stroke?.dispose();

    if (data == null) {
      throw StateError('Gagal membuat gambar subtitle');
    }
    return (
      bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      height: math.max(1, bandH),
    );
  }
}
