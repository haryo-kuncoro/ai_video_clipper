import 'dart:io';
import 'dart:typed_data';

class WavFormatException implements Exception {
  const WavFormatException(this.message);

  final String message;

  @override
  String toString() => 'WavFormatException: $message';
}

class WavInfo {
  const WavInfo({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int dataOffset;
  final int dataLength;

  int get sampleCount => dataLength ~/ (channels * (bitsPerSample ~/ 8));
  double get durationSeconds => sampleCount / sampleRate;
}

/// Membaca header WAV tanpa memuat seluruh file ke memori.
/// Hanya menerima PCM 16-bit mono (format keluaran STEP 6: 16 kHz).
Future<WavInfo> readWavInfo(RandomAccessFile raf) async {
  final length = await raf.length();
  await raf.setPosition(0);
  final head = await raf.read(12);
  if (head.length < 12 ||
      String.fromCharCodes(head.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(head.sublist(8, 12)) != 'WAVE') {
    throw const WavFormatException('bukan file WAV');
  }

  var pos = 12;
  int? sampleRate;
  int? channels;
  int? bits;
  while (pos + 8 <= length) {
    await raf.setPosition(pos);
    final h = await raf.read(8);
    if (h.length < 8) break;
    final id = String.fromCharCodes(h.sublist(0, 4));
    final size = ByteData.sublistView(h).getUint32(4, Endian.little);

    if (id == 'fmt ') {
      if (size < 16) throw const WavFormatException('chunk fmt rusak');
      final f = await raf.read(16);
      if (f.length < 16) throw const WavFormatException('chunk fmt rusak');
      final bd = ByteData.sublistView(f);
      final tag = bd.getUint16(0, Endian.little);
      if (tag != 1 && tag != 0xFFFE) {
        throw const WavFormatException('bukan PCM');
      }
      channels = bd.getUint16(2, Endian.little);
      sampleRate = bd.getUint32(4, Endian.little);
      bits = bd.getUint16(14, Endian.little);
    } else if (id == 'data') {
      if (sampleRate == null || channels == null || bits == null) {
        throw const WavFormatException('chunk fmt tidak ada');
      }
      if (channels != 1 || bits != 16) {
        throw const WavFormatException('harus PCM 16-bit mono');
      }
      final available = length - (pos + 8);
      var dataLength = size;
      // Header dari proses streaming bisa berisi ukuran 0 / 0xFFFFFFFF.
      if (dataLength == 0 || dataLength == 0xFFFFFFFF || dataLength > available) {
        dataLength = available;
      }
      return WavInfo(
        sampleRate: sampleRate,
        channels: channels,
        bitsPerSample: bits,
        dataOffset: pos + 8,
        dataLength: dataLength,
      );
    }
    pos += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw const WavFormatException('chunk data tidak ditemukan');
}

/// PCM 16-bit little-endian -> float -1..1. Byte ganjil di akhir diabaikan.
Float32List pcm16ToFloat32(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final bd = ByteData.sublistView(bytes);
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}
