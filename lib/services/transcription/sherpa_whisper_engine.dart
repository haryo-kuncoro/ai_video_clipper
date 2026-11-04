import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import 'transcription_engine.dart';
import 'transcription_models.dart';
import 'wav_reader.dart';

/// Satu-satunya file yang memakai paket `sherpa_onnx`.
///
/// Cara kerja (semua offline di perangkat):
/// 1. Audio WAV dibaca BERTAHAP (1 detik per potongan) - tidak pernah
///    dimuat utuh ke RAM, sehingga aman untuk video berjam-jam.
/// 2. Silero VAD memotong audio per ucapan (maks. 25 dtk, di bawah batas
///    jendela 30 dtk Whisper) sekaligus memberi waktu mulai tiap segmen.
/// 3. Whisper (ONNX int8) mengenali tiap ucapan satu per satu.
/// Seluruh proses berjalan di isolate terpisah agar UI tidak macet.
class SherpaWhisperEngine implements TranscriptionEngine {
  const SherpaWhisperEngine();

  @override
  String get name => 'whisper-onnx';

  @override
  Future<List<RawSegment>> transcribe({
    required String wavPath,
    required WhisperModelFiles files,
    required String language,
    int threads = 2,
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) throw const TranscriptionCancelled();

    final results = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final completer = Completer<List<RawSegment>>();
    SendPort? workerCancel;

    void fail(Object e) {
      if (!completer.isCompleted) completer.completeError(e);
    }

    results.listen((Object? m) {
      if (m is! List || m.isEmpty) return;
      switch (m[0]) {
        case 'ready':
          workerCancel = m[1] as SendPort;
          if (cancel?.isCancelled ?? false) workerCancel?.send(true);
        case 'progress':
          onProgress?.call((m[1] as num).toDouble());
        case 'done':
          if (!completer.isCompleted) {
            completer.complete([
              for (final r in m[1] as List)
                RawSegment(
                  startMs: (r as List)[0] as int,
                  endMs: r[1] as int,
                  text: r[2] as String,
                ),
            ]);
          }
        case 'cancelled':
          fail(const TranscriptionCancelled());
        case 'error':
          AppLogger.e('Engine STT gagal: ${m[2]}');
          fail(AppException(m[1] as String, code: 'stt_failed'));
      }
    });
    errors.listen((Object? e) {
      AppLogger.e('Isolate STT error: $e');
      fail(const AppException(
        'Mesin transkripsi berhenti tak terduga. Coba model yang lebih kecil.',
        code: 'stt_crash',
      ));
    });
    exits.listen((Object? _) {
      fail(const AppException(
        'Proses transkripsi berhenti sebelum selesai.',
        code: 'stt_exit',
      ));
    });

    final Isolate isolate;
    try {
      isolate = await Isolate.spawn<_Job>(
        _worker,
        _Job(
          port: results.sendPort,
          wavPath: wavPath,
          encoder: files.encoder,
          decoder: files.decoder,
          tokens: files.tokens,
          vad: files.vad,
          language: language,
          threads: threads,
        ),
        onError: errors.sendPort,
        onExit: exits.sendPort,
        errorsAreFatal: true,
      );
    } catch (e, st) {
      AppLogger.e('Gagal memulai isolate STT', e, st);
      results.close();
      errors.close();
      exits.close();
      throw const AppException('Transkripsi tidak dapat dimulai.',
          code: 'stt_spawn');
    }

    Timer? killTimer;
    final unlisten = cancel?.onCancel(() {
      workerCancel?.send(true);
      // Cadangan: bila worker macet di dalam satu proses native yang panjang.
      killTimer = Timer(const Duration(seconds: 20), () {
        isolate.kill(priority: Isolate.immediate);
        fail(const TranscriptionCancelled());
      });
    });

    try {
      return await completer.future;
    } finally {
      killTimer?.cancel();
      unlisten?.call();
      results.close();
      errors.close();
      exits.close();
    }
  }
}

class _Job {
  const _Job({
    required this.port,
    required this.wavPath,
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.vad,
    required this.language,
    required this.threads,
  });

  final SendPort port;
  final String wavPath;
  final String encoder;
  final String decoder;
  final String tokens;
  final String vad;
  final String language;
  final int threads;
}

class _Cancelled implements Exception {
  const _Cancelled();
}

const _sampleRate = 16000;
const _chunkSeconds = 1;

final _hasLetterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

Future<void> _worker(_Job job) async {
  final out = job.port;
  final cancelPort = ReceivePort();
  var cancelled = false;
  cancelPort.listen((Object? _) => cancelled = true);
  out.send(['ready', cancelPort.sendPort]);

  sherpa.OfflineRecognizer? recognizer;
  sherpa.VoiceActivityDetector? vad;
  RandomAccessFile? raf;

  try {
    sherpa.initBindings();

    final rec = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: job.encoder,
            decoder: job.decoder,
            language: job.language,
            task: 'transcribe',
          ),
          tokens: job.tokens,
          numThreads: job.threads,
          debug: false,
          modelType: 'whisper',
        ),
      ),
    );
    recognizer = rec;

    final det = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: job.vad,
          threshold: 0.5,
          minSilenceDuration: 0.5,
          minSpeechDuration: 0.25,
          maxSpeechDuration: 25.0,
        ),
        sampleRate: _sampleRate,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 60,
    );
    vad = det;

    raf = await File(job.wavPath).open();
    final info = await readWavInfo(raf);
    if (info.sampleRate != _sampleRate) {
      throw const WavFormatException('sample rate harus 16 kHz');
    }
    await raf.setPosition(info.dataOffset);

    final segments = <List<Object>>[];
    final totalBytes = info.dataLength;
    var remaining = totalBytes;
    const chunkBytes = _sampleRate * _chunkSeconds * 2;

    Future<void> drain() async {
      while (!det.isEmpty()) {
        final seg = det.front();
        det.pop();

        final stream = rec.createStream();
        String text;
        try {
          stream.acceptWaveform(samples: seg.samples, sampleRate: _sampleRate);
          rec.decode(stream);
          text = rec.getResult(stream).text.trim();
        } finally {
          stream.free();
        }

        final startMs = (seg.start * 1000 / _sampleRate).round();
        final endMs = startMs + (seg.samples.length * 1000 / _sampleRate).round();
        // Whisper kadang "berhalusinasi" simbol saat hening; buang yang
        // tidak berisi huruf/angka.
        if (text.isNotEmpty && _hasLetterOrDigit.hasMatch(text)) {
          segments.add([startMs, endMs, text]);
        }

        // Beri kesempatan menerima pesan batal.
        await Future<void>.delayed(Duration.zero);
        if (cancelled) throw const _Cancelled();
      }
    }

    while (remaining > 0) {
      if (cancelled) throw const _Cancelled();
      final bytes = await raf.read(math.min(chunkBytes, remaining));
      if (bytes.isEmpty) break;
      remaining -= bytes.length;

      det.acceptWaveform(pcm16ToFloat32(bytes));
      await drain();

      out.send(['progress', 1 - remaining / totalBytes]);
      await Future<void>.delayed(Duration.zero);
    }

    det.flush();
    await drain();
    out.send(['done', segments]);
  } on _Cancelled {
    out.send(['cancelled']);
  } on WavFormatException catch (e) {
    out.send([
      'error',
      'Format audio tidak didukung. Coba ulangi proses.',
      e.toString(),
    ]);
  } on FileSystemException catch (e) {
    out.send([
      'error',
      'File audio atau model tidak dapat dibaca. Pastikan model sudah diunduh lengkap.',
      e.toString(),
    ]);
  } catch (e, st) {
    out.send([
      'error',
      'Mesin transkripsi gagal berjalan. Coba unduh ulang model atau pilih model lebih kecil.',
      '$e\n$st',
    ]);
  } finally {
    try {
      await raf?.close();
    } catch (_) {}
    vad?.free();
    recognizer?.free();
    cancelPort.close();
  }
}
