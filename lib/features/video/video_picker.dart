import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';

class PickedVideo {
  const PickedVideo({
    required this.path,
    required this.name,
    required this.sizeBytes,
  });

  /// Path file yang bisa dibaca langsung (di Android: salinan di cache app).
  final String path;
  final String name;
  final int sizeBytes;
}

abstract class VideoPicker {
  /// Mengembalikan null bila pengguna membatalkan.
  Future<PickedVideo?> pick();
}

/// Memakai Storage Access Framework lewat `file_picker`: tidak memerlukan izin
/// storage (kompatibel Scoped Storage) dan tidak memuat video ke RAM.
class FilePickerVideoPicker implements VideoPicker {
  @override
  Future<PickedVideo?> pick() async {
    try {
      // file_picker >= 11: API statis. `dynamic` agar tahan terhadap perbedaan
      // tipe kembalian antar versi (List<PlatformFile> atau null bila batal).
      final dynamic result = await FilePicker.pickFiles(
        type: FileType.video,
      );
      final List<dynamic> files = result == null
          ? const []
          : (result is List ? result : (result.files as List<dynamic>));
      if (files.isEmpty) return null;

      final dynamic file = files.first;
      final String? path = file.path as String?;
      if (path == null) {
        throw const AppException(
          'Video tidak dapat dibaca dari penyimpanan.',
          code: 'pick_no_path',
        );
      }
      // Nama dan ukuran diambil dari path (bukan dari objek picker) agar tidak
      // bergantung pada properti yang berbeda antar versi file_picker.
      return PickedVideo(
        path: path,
        name: p.basename(path),
        sizeBytes: await File(path).length(),
      );
    } on PlatformException catch (e) {
      throw AppException(
        'Tidak dapat mengakses video. Periksa izin akses penyimpanan.',
        code: 'permission_denied',
        cause: e,
      );
    }
  }
}
