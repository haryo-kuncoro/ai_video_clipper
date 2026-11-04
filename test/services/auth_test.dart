import 'dart:convert';
import 'dart:io';

import 'package:ai_video_clipper/core/errors/app_exception.dart';
import 'package:ai_video_clipper/services/auth/auth_models.dart';
import 'package:ai_video_clipper/services/auth/auth_service.dart';
import 'package:ai_video_clipper/services/auth/secure_store.dart';
import 'package:ai_video_clipper/services/remote/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> sessionJson({
  String access = 'access-1',
  String refresh = 'refresh-1',
  required DateTime now,
  Duration accessTtl = const Duration(minutes: 30),
  Duration refreshTtl = const Duration(days: 30),
  String email = 'a@example.com',
}) =>
    {
      'access_token': access,
      'access_expires_at': now.add(accessTtl).toUtc().toIso8601String(),
      'refresh_token': refresh,
      'refresh_expires_at': now.add(refreshTtl).toUtc().toIso8601String(),
      'user': {'id': 1, 'email': email, 'name': 'Ani'},
    };

class _Call {
  _Call(this.method, this.path, this.body, this.bearer);

  final String method;
  final String path;
  final Map<String, Object?> body;
  final String? bearer;
}

class _FakeApi implements ApiClient {
  final List<_Call> calls = [];
  final Map<String, ApiResponse Function(_Call)> handlers = {};
  Duration delay = Duration.zero;

  ApiResponse ok(Object data) => ApiResponse(statusCode: 200, json: {'success': true, 'data': data});

  Future<ApiResponse> _handle(String method, String path, Map<String, Object?> body, String? bearer) async {
    final call = _Call(method, path, body, bearer);
    calls.add(call);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final h = handlers[path];
    if (h == null) throw StateError('tidak ada handler untuk $path');
    return h(call);
  }

  @override
  Future<ApiResponse> get(String path,
          {Map<String, String>? query, String? ifNoneMatch, String? bearer}) =>
      _handle('GET', path, const {}, bearer);

  @override
  Future<ApiResponse> post(String path,
          {Map<String, Object?> body = const {}, String? bearer}) =>
      _handle('POST', path, body, bearer);

  int count(String path) => calls.where((c) => c.path == path).length;
}

ApiException rejected(int status, String code, [String message = 'Ditolak.']) =>
    ApiException(message, code: code, statusCode: status);

void main() {
  var now = DateTime.utc(2026, 10, 24, 12);
  late _FakeApi api;
  late MemorySecureStore store;

  AuthService make({ApiClient? client}) => AuthService(
        api: client ?? api,
        store: store,
        clock: () => now,
      );

  setUp(() {
    now = DateTime.utc(2026, 10, 24, 12);
    api = _FakeApi();
    store = MemorySecureStore();
  });

  group('AuthSession', () {
    test('round-trip encode/decode', () {
      final s = AuthSession.fromJson(sessionJson(now: now))!;
      final back = AuthSession.decode(s.encode())!;
      expect(back.accessToken, 'access-1');
      expect(back.refreshToken, 'refresh-1');
      expect(back.user.email, 'a@example.com');
      expect(back.accessExpiresAt, s.accessExpiresAt);
    });

    test('data tidak lengkap atau rusak -> null', () {
      expect(AuthSession.fromJson({'access_token': 'x'}), isNull);
      expect(AuthSession.fromJson('aneh'), isNull);
      expect(AuthSession.decode('{rusak'), isNull);
      expect(AuthSession.decode(null), isNull);
      final bad = sessionJson(now: now)..['access_expires_at'] = 'bukan tanggal';
      expect(AuthSession.fromJson(bad), isNull);
      final noUser = sessionJson(now: now)..['user'] = {'id': 'x'};
      expect(AuthSession.fromJson(noUser), isNull);
    });
  });

  group('login / register', () {
    test('login sukses: sesi tersimpan di secure store, status signedIn', () async {
      api.handlers['api/v1/auth/login'] = (_) => api.ok(sessionJson(now: now));
      final s = make();
      expect(s.status, AuthStatus.unknown);
      await s.login(email: '  a@example.com ', password: 'Rahasia-12345');
      expect(s.isSignedIn, isTrue);
      expect(s.user!.name, 'Ani');
      expect(api.calls.single.body['email'], 'a@example.com');
      expect(api.calls.single.body['device_name'], 'Android');
      expect(store.data[AuthService.sessionKey], contains('access-1'));
      expect(s.busy, isFalse);
    });

    test('register mengirim nama dan sandi', () async {
      api.handlers['api/v1/auth/register'] = (_) => api.ok(sessionJson(now: now));
      final s = make();
      await s.register(email: 'a@example.com', name: ' Ani ', password: 'Rahasia-12345');
      expect(api.calls.single.body['name'], 'Ani');
      expect(s.isSignedIn, isTrue);
    });

    test('validasi lokal: tidak memanggil server', () async {
      final s = make();
      await expectLater(s.login(email: 'bukan-email', password: 'x'),
          throwsA(isA<AppException>().having((e) => e.code, 'code', 'invalid_email')));
      await expectLater(s.login(email: 'a@b.co', password: ''),
          throwsA(isA<AppException>().having((e) => e.code, 'code', 'invalid_password')));
      await expectLater(s.register(email: 'a@b.co', name: ' ', password: 'Rahasia-12345'),
          throwsA(isA<AppException>().having((e) => e.code, 'code', 'invalid_name')));
      await expectLater(s.register(email: 'a@b.co', name: 'A', password: '123'),
          throwsA(isA<AppException>().having((e) => e.code, 'code', 'weak_password')));
      await expectLater(s.register(email: 'a@b.co', name: 'A', password: 'x' * 73),
          throwsA(isA<AppException>().having((e) => e.code, 'code', 'weak_password')));
      expect(api.calls, isEmpty);
    });

    test('kredensial salah: pesan server diteruskan, tidak signedIn', () async {
      api.handlers['api/v1/auth/login'] =
          (_) => throw rejected(401, 'invalid_credentials', 'Email atau kata sandi salah.');
      final s = make();
      await expectLater(s.login(email: 'a@b.co', password: 'salah'),
          throwsA(isA<AppException>().having((e) => e.message, 'm', 'Email atau kata sandi salah.')));
      expect(s.isSignedIn, isFalse);
      expect(store.data, isEmpty);
      expect(s.busy, isFalse);
    });

    test('balasan server tidak lengkap -> error ramah, tidak signedIn', () async {
      api.handlers['api/v1/auth/login'] = (_) => api.ok({'access_token': 'x'});
      final s = make();
      await expectLater(s.login(email: 'a@b.co', password: 'abc'), throwsA(isA<AppException>()));
      expect(s.isSignedIn, isFalse);
    });

    test('error tak terduga -> pesan ramah tanpa detail', () async {
      api.handlers['api/v1/auth/login'] = (_) => throw StateError('rahasia internal');
      final s = make();
      await expectLater(
        s.login(email: 'a@b.co', password: 'abc'),
        throwsA(isA<AppException>().having((e) => e.message, 'm', isNot(contains('rahasia')))),
      );
    });

    test('secure storage gagal menyimpan -> sesi TIDAK dipakai', () async {
      api.handlers['api/v1/auth/login'] = (_) => api.ok(sessionJson(now: now));
      store.failWrites = true;
      final s = make();
      await expectLater(
        s.login(email: 'a@b.co', password: 'abc'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'secure_storage_failed')),
      );
      expect(s.isSignedIn, isFalse);
      expect(store.data, isEmpty);
    });

    test('backend tidak dikonfigurasi', () async {
      final s = AuthService(api: null, store: store, clock: () => now);
      expect(s.available, isFalse);
      await expectLater(s.login(email: 'a@b.co', password: 'abc'),
          throwsA(isA<AppException>().having((e) => e.code, 'code', 'backend_disabled')));
      await s.restore();
      expect(s.status, AuthStatus.signedOut);
    });
  });

  group('restore', () {
    test('tanpa sesi -> signedOut', () async {
      final s = make();
      await s.restore();
      expect(s.status, AuthStatus.signedOut);
    });

    test('sesi tersimpan -> signedIn walau server tidak terjangkau (offline)', () async {
      store.data[AuthService.sessionKey] = AuthSession.fromJson(sessionJson(now: now))!.encode();
      api.handlers['api/v1/auth/me'] = (_) => throw const ApiException('x', code: 'offline');
      final s = make();
      await s.restore();
      await Future<void>.delayed(Duration.zero);
      expect(s.isSignedIn, isTrue);
      expect(store.data[AuthService.sessionKey], isNotNull);
    });

    test('server menolak token (dicabut) -> keluar otomatis', () async {
      store.data[AuthService.sessionKey] = AuthSession.fromJson(sessionJson(now: now))!.encode();
      api.handlers['api/v1/auth/me'] = (_) => throw rejected(401, 'unauthorized');
      final s = make();
      await s.restore();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(s.isSignedIn, isFalse);
      expect(store.data, isEmpty);
    });

    test('server memperbarui data pengguna', () async {
      store.data[AuthService.sessionKey] = AuthSession.fromJson(sessionJson(now: now))!.encode();
      api.handlers['api/v1/auth/me'] = (_) => api.ok({
            'user': {'id': 1, 'email': 'a@example.com', 'name': 'Nama Baru'},
          });
      final s = make();
      await s.restore();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(s.user!.name, 'Nama Baru');
    });

    test('refresh token kedaluwarsa -> dibersihkan', () async {
      store.data[AuthService.sessionKey] = AuthSession.fromJson(
              sessionJson(now: now, refreshTtl: const Duration(days: 1)))!
          .encode();
      now = now.add(const Duration(days: 2));
      final s = make();
      await s.restore();
      expect(s.status, AuthStatus.signedOut);
      expect(store.data, isEmpty);
      expect(api.calls, isEmpty);
    });

    test('data sesi rusak -> signedOut', () async {
      store.data[AuthService.sessionKey] = '{rusak';
      final s = make();
      await s.restore();
      expect(s.status, AuthStatus.signedOut);
    });
  });

  group('accessToken / refresh', () {
    Future<AuthService> signedIn({Duration accessTtl = const Duration(minutes: 30)}) async {
      api.handlers['api/v1/auth/login'] =
          (_) => api.ok(sessionJson(now: now, accessTtl: accessTtl));
      final s = make();
      await s.login(email: 'a@b.co', password: 'abc');
      api.calls.clear();
      return s;
    }

    test('token masih lama -> tanpa refresh', () async {
      final s = await signedIn();
      expect(await s.accessToken(), 'access-1');
      expect(api.calls, isEmpty);
    });

    test('hampir habis -> refresh dan token baru disimpan', () async {
      final s = await signedIn();
      now = now.add(const Duration(minutes: 29, seconds: 30));
      api.handlers['api/v1/auth/refresh'] = (c) {
        expect(c.body['refresh_token'], 'refresh-1');
        return api.ok(sessionJson(now: now, access: 'access-2', refresh: 'refresh-2'));
      };
      expect(await s.accessToken(), 'access-2');
      expect(store.data[AuthService.sessionKey], contains('refresh-2'));
      expect(store.data[AuthService.sessionKey], isNot(contains('refresh-1')));
    });

    test('banyak pemanggil bersamaan hanya memicu satu refresh', () async {
      final s = await signedIn();
      now = now.add(const Duration(minutes: 29, seconds: 30));
      api.delay = const Duration(milliseconds: 30);
      api.handlers['api/v1/auth/refresh'] =
          (_) => api.ok(sessionJson(now: now, access: 'access-2', refresh: 'refresh-2'));
      final tokens = await Future.wait([s.accessToken(), s.accessToken(), s.accessToken()]);
      expect(tokens, ['access-2', 'access-2', 'access-2']);
      expect(api.count('api/v1/auth/refresh'), 1);
    });

    test('refresh ditolak server -> keluar dan pesan sesi berakhir', () async {
      final s = await signedIn();
      now = now.add(const Duration(minutes: 31));
      api.handlers['api/v1/auth/refresh'] = (_) => throw rejected(401, 'token_reused');
      await expectLater(s.accessToken(),
          throwsA(isA<AppException>().having((e) => e.code, 'code', 'session_expired')));
      expect(s.isSignedIn, isFalse);
      expect(store.data, isEmpty);
    });

    test('refresh gagal karena jaringan -> sesi dipertahankan', () async {
      final s = await signedIn();
      now = now.add(const Duration(minutes: 31));
      api.handlers['api/v1/auth/refresh'] =
          (_) => throw const ApiException('offline', code: 'offline');
      await expectLater(s.accessToken(), throwsA(isA<ApiException>()));
      expect(s.isSignedIn, isTrue);
      expect(store.data[AuthService.sessionKey], isNotNull);
    });

    test('refresh token sendiri sudah habis -> keluar tanpa memanggil server', () async {
      final s = await signedIn();
      now = now.add(const Duration(days: 31));
      await expectLater(s.accessToken(),
          throwsA(isA<AppException>().having((e) => e.code, 'code', 'session_expired')));
      expect(api.calls, isEmpty);
      expect(s.isSignedIn, isFalse);
    });

    test('tanpa sesi -> not_signed_in', () async {
      final s = make();
      await expectLater(s.accessToken(),
          throwsA(isA<AppException>().having((e) => e.code, 'code', 'not_signed_in')));
    });
  });

  group('logout / ubah sandi / hapus akun', () {
    Future<AuthService> signedIn() async {
      api.handlers['api/v1/auth/login'] = (_) => api.ok(sessionJson(now: now));
      final s = make();
      await s.login(email: 'a@b.co', password: 'abc');
      api.calls.clear();
      return s;
    }

    test('logout memanggil server dengan bearer lalu membersihkan', () async {
      final s = await signedIn();
      api.handlers['api/v1/auth/logout'] = (_) => api.ok({'logged_out': true});
      await s.logout();
      expect(api.calls.single.bearer, 'access-1');
      expect(s.isSignedIn, isFalse);
      expect(store.data, isEmpty);
    });

    test('logout tetap membersihkan walau server gagal', () async {
      final s = await signedIn();
      api.handlers['api/v1/auth/logout'] =
          (_) => throw const ApiException('x', code: 'offline');
      await s.logout();
      expect(s.isSignedIn, isFalse);
      expect(store.data, isEmpty);
    });

    test('ganti sandi: validasi lokal dan sesi tetap', () async {
      final s = await signedIn();
      await expectLater(s.changePassword(currentPassword: '', newPassword: 'BaruBanget-99'),
          throwsA(isA<AppException>()));
      await expectLater(s.changePassword(currentPassword: 'a', newPassword: '123'),
          throwsA(isA<AppException>().having((e) => e.code, 'code', 'weak_password')));
      expect(api.calls, isEmpty);

      api.handlers['api/v1/auth/change-password'] = (c) {
        expect(c.body['current_password'], 'lama-12345');
        expect(c.bearer, 'access-1');
        return api.ok({'changed': true});
      };
      await s.changePassword(currentPassword: 'lama-12345', newPassword: 'BaruBanget-99');
      expect(s.isSignedIn, isTrue);
    });

    test('ganti sandi salah -> pesan server, tidak keluar', () async {
      final s = await signedIn();
      api.handlers['api/v1/auth/change-password'] =
          (_) => throw rejected(403, 'invalid_credentials', 'Kata sandi salah.');
      await expectLater(s.changePassword(currentPassword: 'x', newPassword: 'BaruBanget-99'),
          throwsA(isA<AppException>().having((e) => e.message, 'm', 'Kata sandi salah.')));
      expect(s.isSignedIn, isTrue);
    });

    test('hapus akun: server lalu bersihkan lokal', () async {
      final s = await signedIn();
      api.handlers['api/v1/auth/delete-account'] = (c) {
        expect(c.body['password'], 'abc-12345');
        return api.ok({'deleted': true});
      };
      await s.deleteAccount(password: 'abc-12345');
      expect(s.isSignedIn, isFalse);
      expect(store.data, isEmpty);
    });

    test('hapus akun gagal (sandi salah) -> tetap masuk', () async {
      final s = await signedIn();
      api.handlers['api/v1/auth/delete-account'] = (_) => throw rejected(403, 'invalid_credentials');
      await expectLater(s.deleteAccount(password: 'salah'), throwsA(isA<AppException>()));
      expect(s.isSignedIn, isTrue);
      expect(store.data[AuthService.sessionKey], isNotNull);
    });
  });

  group('HttpApiClient POST', () {
    late HttpServer server;
    late String base;
    int status = 200;
    String reply = '{"success":true,"data":{}}';
    String lastMethod = '';
    String lastBody = '';
    String lastAuth = '';
    String lastType = '';

    setUpAll(() => HttpOverrides.global = null);

    setUp(() async {
      status = 200;
      reply = '{"success":true,"data":{}}';
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        try {
          lastMethod = req.method;
          lastAuth = req.headers.value('authorization') ?? '';
          lastType = req.headers.contentType?.mimeType ?? '';
          lastBody = await utf8.decoder.bind(req).join();
          req.response.statusCode = status;
          req.response.write(reply);
          await req.response.close();
        } catch (_) {}
      });
    });

    tearDown(() async => server.close(force: true));

    test('mengirim JSON dan bearer', () async {
      await HttpApiClient(baseUrl: base)
          .post('api/v1/auth/login', body: {'email': 'a@b.co', 'password': 'p'}, bearer: 'tok');
      expect(lastMethod, 'POST');
      expect(lastType, 'application/json');
      expect(jsonDecode(lastBody), {'email': 'a@b.co', 'password': 'p'});
      expect(lastAuth, 'Bearer tok');
    });

    test('401 membawa kode dan status dari server', () async {
      status = 401;
      reply = '{"success":false,"error":{"code":"invalid_credentials","message":"Email atau kata sandi salah."}}';
      await expectLater(
        HttpApiClient(baseUrl: base).post('x'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'invalid_credentials')
            .having((e) => e.statusCode, 'status', 401)
            .having((e) => e.isAuthRejection, 'rejection', isTrue)
            .having((e) => e.message, 'message', 'Email atau kata sandi salah.')),
      );
    });

    test('isNetwork benar untuk offline/timeout, salah untuk 401/500', () {
      expect(const ApiException('x', code: 'offline').isNetwork, isTrue);
      expect(const ApiException('x', code: 'timeout').isNetwork, isTrue);
      expect(const ApiException('x', code: 'server_error', statusCode: 500).isNetwork, isFalse);
      expect(const ApiException('x', statusCode: 403).isAuthRejection, isTrue);
    });
  });
}
