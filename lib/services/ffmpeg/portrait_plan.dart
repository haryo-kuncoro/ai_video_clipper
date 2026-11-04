/// Perencanaan crop portrait 9:16 (fungsi murni, mudah dites).
///
/// Prinsip: video TIDAK PERNAH di-stretch. Area 9:16 dipotong (crop) dari
/// frame sumber, baru kemudian diskalakan ke resolusi output.

enum PortraitCropMode {
  /// Potong di tengah. Default dan fallback bila mode lain gagal.
  centerCrop,

  /// Area crop mengikuti titik fokus (wajah) dari face detection lokal.
  /// Detektornya dibuat di STEP 14; tanpa titik fokus memakai center crop.
  faceAwareCrop,

  /// Pengguna menentukan posisi dan zoom.
  manualCrop,
}

enum PortraitResolution {
  /// 1080x1920 bila sumber cukup tajam, selain itu 720x1280.
  auto,
  p1080,
  p720;

  String get label {
    switch (this) {
      case PortraitResolution.auto:
        return 'Otomatis';
      case PortraitResolution.p1080:
        return '1080x1920';
      case PortraitResolution.p720:
        return '720x1280';
    }
  }
}

class CropRect {
  const CropRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is CropRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'CropRect($x,$y ${width}x$height)';
}

class PortraitPlan {
  const PortraitPlan({
    required this.mode,
    required this.crop,
    required this.outputWidth,
    required this.outputHeight,
    required this.sourceWidth,
    required this.sourceHeight,
    this.usedFallback = false,
  });

  final PortraitCropMode mode;
  final CropRect crop;
  final int outputWidth;
  final int outputHeight;
  final int sourceWidth;
  final int sourceHeight;

  /// True bila mode face-aware diminta tetapi tidak ada titik fokus,
  /// sehingga dipakai center crop.
  final bool usedFallback;

  /// >1 berarti hasil diperbesar (upscale) dari area crop.
  double get upscaleFactor => outputWidth / crop.width;
}

int _even(int v) => v - (v % 2);

/// Menghitung area crop 9:16 dan ukuran output.
///
/// [focusX]/[focusY] (0.0-1.0) adalah titik tengah area crop relatif terhadap
/// frame sumber. [zoom] (1.0-4.0) memperkecil area crop (hanya mode manual).
/// Semua ukuran dan posisi dibuat genap (syarat encoder H.264 yuv420p).
PortraitPlan planPortrait({
  required int sourceWidth,
  required int sourceHeight,
  PortraitCropMode mode = PortraitCropMode.centerCrop,
  double? focusX,
  double? focusY,
  double zoom = 1.0,
  PortraitResolution resolution = PortraitResolution.auto,
}) {
  if (sourceWidth < 16 || sourceHeight < 16) {
    throw ArgumentError('Resolusi sumber terlalu kecil: '
        '${sourceWidth}x$sourceHeight');
  }

  var fx = 0.5;
  var fy = 0.5;
  var z = 1.0;
  var fallback = false;

  switch (mode) {
    case PortraitCropMode.centerCrop:
      break;
    case PortraitCropMode.faceAwareCrop:
      if (focusX == null) {
        fallback = true;
      } else {
        fx = focusX.clamp(0.0, 1.0).toDouble();
        fy = (focusY ?? 0.5).clamp(0.0, 1.0).toDouble();
      }
    case PortraitCropMode.manualCrop:
      fx = (focusX ?? 0.5).clamp(0.0, 1.0).toDouble();
      fy = (focusY ?? 0.5).clamp(0.0, 1.0).toDouble();
      z = zoom.clamp(1.0, 4.0).toDouble();
  }

  // Area 9:16 terbesar yang muat di dalam frame sumber.
  final double baseHeight;
  if (sourceWidth * 16 >= sourceHeight * 9) {
    baseHeight = sourceHeight.toDouble(); // sumber lebih lebar dari 9:16
  } else {
    baseHeight = sourceWidth * 16 / 9; // sumber lebih sempit dari 9:16
  }

  var cropH = _even((baseHeight / z).floor());
  var cropW = _even((cropH * 9 / 16).floor());
  if (cropW > sourceWidth) cropW = _even(sourceWidth);
  if (cropH > sourceHeight) cropH = _even(sourceHeight);

  final x = _even((fx * sourceWidth - cropW / 2)
      .round()
      .clamp(0, sourceWidth - cropW)
      .toInt());
  final y = _even((fy * sourceHeight - cropH / 2)
      .round()
      .clamp(0, sourceHeight - cropH)
      .toInt());

  final use1080 = switch (resolution) {
    PortraitResolution.p1080 => true,
    PortraitResolution.p720 => false,
    // Hindari upscale besar: 1080 hanya bila lebar crop sudah >= 1080.
    PortraitResolution.auto => cropW >= 1080,
  };

  return PortraitPlan(
    mode: mode,
    crop: CropRect(x: x, y: y, width: cropW, height: cropH),
    outputWidth: use1080 ? 1080 : 720,
    outputHeight: use1080 ? 1920 : 1280,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    usedFallback: fallback,
  );
}
