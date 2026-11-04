import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';

/// Tujuan ekspor: galeri video (Movies) atau Downloads.
enum ExportTarget { video, download }

class ExportedFile {
  const ExportedFile({required this.uri, required this.displayName});

  final String uri;
  final String displayName;
}

/// Menyalin file ke penyimpanan publik tanpa mengubah file asli.
/// Diabstraksikan agar bisa di-fake saat testing.
abstract class GalleryExporter {
  Future<ExportedFile> exportFile({
    required String sourcePath,
    required String displayName,
    required String mimeType,
    required ExportTarget target,
  });

  Future<void> share({required String uri, required String mimeType});
}

/// Implementasi Android (MediaStore) lewat MethodChannel.
/// Kodenya ada di `native/android/MainActivity.kt`.
class NativeGalleryExporter implements GalleryExporter {
  static const _channel = MethodChannel('com.haryo.ai_video_clipper/media');

  @override
  Future<ExportedFile> exportFile({
    required String sourcePath,
    required String displayName,
    required String mimeType,
    required ExportTarget target,
  }) async {
    try {
      final uri = await _channel.invokeMethod<String>('exportFile', {
        'source': sourcePath,
        'displayName': displayName,
        'mimeType': mimeType,
        'target': target.name,
      });
      if (uri == null || uri.isEmpty) throw _failed;
      return ExportedFile(uri: uri, displayName: displayName);
    } on MissingPluginException {
      throw const AppException(
        'Komponen native belum terpasang. Salin MainActivity.kt sesuai README.',
        code: 'native_missing',
      );
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'file_missing':
          throw const AppException(
            'File clip tidak ditemukan. Render ulang clip terlebih dahulu.',
            code: 'file_missing',
          );
        case 'permission_denied':
          throw const AppException(
            'Izin penyimpanan ditolak. Izinkan agar clip dapat disimpan ke galeri.',
            code: 'permission_denied',
          );
        default:
          throw _failed;
      }
    }
  }

  @override
  Future<void> share({required String uri, required String mimeType}) async {
    try {
      await _channel
          .invokeMethod<bool>('shareUri', {'uri': uri, 'mimeType': mimeType});
    } on MissingPluginException {
      throw const AppException(
        'Komponen native belum terpasang. Salin MainActivity.kt sesuai README.',
        code: 'native_missing',
      );
    } on PlatformException {
      throw const AppException(
        'Clip tidak dapat dibagikan. Simpan ke galeri lalu bagikan dari sana.',
        code: 'share_failed',
      );
    }
  }

  static const _failed = AppException(
    'Clip gagal disimpan ke galeri. Periksa ruang penyimpanan lalu coba lagi.',
    code: 'export_failed',
  );
}
