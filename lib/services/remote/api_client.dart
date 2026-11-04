import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/errors/app_exception.dart';

class ApiResponse {
  const ApiResponse({required this.statusCode, this.json, this.etag});

  final int statusCode;

  /// Isi JSON (Map) bila ada dan valid.
  final Map<String, dynamic>? json;
  final String? etag;

  bool get notModified => statusCode == 304;
}

/// Gagal menghubungi server. Pesan selalu ramah pengguna.
class ApiException extends AppException {
  const ApiException(super.message, {super.code, super.cause, this.statusCode});

  /// Status HTTP bila gagal dari sisi server (null untuk masalah jaringan).
  final int? statusCode;

  /// Ditolak server karena kredensial/sesi (401/403).
  bool get isAuthRejection => statusCode == 401 || statusCode == 403;

  /// Masalah jaringan (tanpa balasan server): sesi lokal sebaiknya tetap dipertahankan.
  bool get isNetwork =>
      code == 'offline' || code == 'timeout' || code == 'tls_failed' || code == 'http_error';
}

/// Klien HTTP minimal. Diabstraksikan agar mudah di-fake saat testing.
abstract class ApiClient {
  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    String? ifNoneMatch,
    String? bearer,
  });

  /// POST dengan body JSON. Hanya untuk endpoint akun (STEP 19); tidak pernah
  /// dipakai untuk mengirim video, project, atau transcript.
  Future<ApiResponse> post(
    String path, {
    Map<String, Object?> body = const {},
    String? bearer,
  });
}

/// Implementasi dart:io (tanpa dependency tambahan). Hanya GET ke endpoint
/// konfigurasi; tidak pernah mengirim video, project, atau transcript.
class HttpApiClient implements ApiClient {
  HttpApiClient({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 8),
    HttpClient Function()? clientFactory,
  }) : _factory = clientFactory ?? HttpClient.new;

  final String baseUrl;
  final Duration timeout;
  final HttpClient Function() _factory;

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    String? ifNoneMatch,
    String? bearer,
  }) =>
      _send('GET', path, query: query, ifNoneMatch: ifNoneMatch, bearer: bearer);

  @override
  Future<ApiResponse> post(
    String path, {
    Map<String, Object?> body = const {},
    String? bearer,
  }) =>
      _send('POST', path, body: body, bearer: bearer);

  Future<ApiResponse> _send(
    String method,
    String path, {
    Map<String, String>? query,
    String? ifNoneMatch,
    String? bearer,
    Map<String, Object?>? body,
  }) async {
    final base = Uri.tryParse(baseUrl);
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      throw const ApiException('Alamat server belum diatur dengan benar.',
          code: 'bad_base_url');
    }
    final uri = base.replace(
      path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );

    final client = _factory()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.userAgentHeader, 'AIVideoClipper');
      if (ifNoneMatch != null) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, ifNoneMatch);
      }
      if (bearer != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        request.headers.contentType = ContentType.json;
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(timeout);
      final etag = response.headers.value(HttpHeaders.etagHeader);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);

      if (response.statusCode == 304) {
        return ApiResponse(statusCode: 304, etag: etag ?? ifNoneMatch);
      }
      Map<String, dynamic>? parsed;
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) parsed = decoded;
      } on FormatException {
        parsed = null;
      }
      if (response.statusCode >= 500) {
        throw ApiException('Server sedang bermasalah. Coba lagi nanti.',
            code: 'server_error', statusCode: response.statusCode);
      }
      if (response.statusCode >= 400) {
        throw ApiException(
          _errorMessage(parsed) ?? 'Permintaan ditolak server.',
          code: _errorCode(parsed) ?? 'request_rejected',
          statusCode: response.statusCode,
        );
      }
      if (parsed == null) {
        throw const ApiException('Balasan server tidak dikenali.',
            code: 'bad_response');
      }
      return ApiResponse(statusCode: response.statusCode, json: parsed, etag: etag);
    } on TimeoutException catch (e) {
      throw ApiException('Server tidak merespons. Periksa koneksi internet.',
          code: 'timeout', cause: e);
    } on SocketException catch (e) {
      throw ApiException('Tidak dapat terhubung ke server. Periksa koneksi internet.',
          code: 'offline', cause: e);
    } on HandshakeException catch (e) {
      throw ApiException('Koneksi aman ke server gagal.',
          code: 'tls_failed', cause: e);
    } on HttpException catch (e) {
      throw ApiException('Koneksi ke server terputus.',
          code: 'http_error', cause: e);
    } finally {
      client.close(force: true);
    }
  }

  static String? _errorCode(Map<String, dynamic>? json) {
    final err = json?['error'];
    if (err is Map && err['code'] is String) return err['code'] as String;
    return null;
  }

  static String? _errorMessage(Map<String, dynamic>? json) {
    final err = json?['error'];
    if (err is Map && err['message'] is String) return err['message'] as String;
    return null;
  }
}
