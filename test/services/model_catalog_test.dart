import 'dart:io';

import 'package:ai_video_clipper/core/errors/app_exception.dart';
import 'package:ai_video_clipper/services/models/model_catalog.dart';
import 'package:ai_video_clipper/services/transcription/transcription_models.dart';
import 'package:ai_video_clipper/services/transcription/whisper_model_manager.dart';
import 'package:ai_video_clipper/services/translation/text_translator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Translator implements TextTranslator {
  int ensured = 0;
  bool closed = false;
  Object? failEnsure;

  @override
  Future<void> ensureModels(String source, String target,
      {void Function(String status)? onStatus}) async {
    if (failEnsure != null) throw failEnsure!;
    ensured++;
  }

  final Set<String> downloaded = {};

  @override
  Future<bool> isModelDownloaded(String code) async => downloaded.contains(code);

  @override
  Future<void> downloadModel(String code) async {
    if (failEnsure != null) throw failEnsure!;
    downloaded.add(code);
  }

  @override
  Future<void> deleteModel(String code) async => downloaded.remove(code);

  @override
  Future<String> translate(String source, String target, String text) async =>
      text == 'kosong' ? '' : '[$target] $text';

  @override
  Future<void> close() async => closed = true;
}

void main() {
  late Directory tmp;
  late _Translator tr;
  late ModelCatalog cat;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('avc_cat_');
    tr = _Translator();
    cat = ModelCatalog(
      whisper: WhisperModelManager(Directory(p.join(tmp.path, 'm')),
          validateContent: false),
      translator: tr,
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('sebelum refresh: pesan "memeriksa"', () {
    expect(cat.loaded, isFalse);
    expect(cat.missingMessage(stt: WhisperModels.base), contains('Memeriksa'));
  });

  test('tanpa model: pesan minta unduh di Pengaturan > Model AI', () async {
    await cat.refresh();
    expect(cat.installedWhisper, isEmpty);
    final m = cat.missingMessage(
        stt: WhisperModels.base, sourceLang: 'ko', targetLang: 'id');
    expect(m, contains('model transcript Base'));
    expect(m, contains('terjemahan Korea'));
    expect(m, contains('terjemahan Indonesia'));
    expect(m, contains('Pengaturan > Model AI'));
  });

  test('unduh & hapus model terjemahan memperbarui status', () async {
    await cat.refresh();
    await cat.downloadTranslation('ko');
    expect(cat.translationReady('ko'), isTrue);
    expect(cat.translationReady('id'), isFalse);
    expect(cat.missingMessage(sourceLang: 'ko', targetLang: 'id'),
        isNot(contains('Korea')));
    await cat.downloadTranslation('id');
    expect(cat.missingMessage(sourceLang: 'ko', targetLang: 'id'), isNull);
    await cat.deleteTranslation('ko');
    expect(cat.translationReady('ko'), isFalse);
  });

  test('gagal unduh -> pesan ramah, tidak busy', () async {
    await cat.refresh();
    tr.failEnsure = const AppException('Model terjemahan belum bisa diunduh.');
    await cat.downloadTranslation('ja');
    expect(cat.message, contains('belum bisa diunduh'));
    expect(cat.busy, isFalse);
    expect(cat.translationReady('ja'), isFalse);
  });
}
