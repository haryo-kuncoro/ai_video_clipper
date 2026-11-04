import 'dart:convert';
import 'dart:io';

import 'package:ai_video_clipper/database/app_database.dart';
import 'package:ai_video_clipper/database/repositories/app_settings_repository.dart';
import 'package:ai_video_clipper/services/remote/api_client.dart';
import 'package:ai_video_clipper/services/remote/remote_config.dart';
import 'package:ai_video_clipper/services/remote/remote_config_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _data = {
  'settings': {
    'default_clip_duration_seconds': 45,
    'ratio': 1.5,
    'maintenance_mode': false,
    'support_contact': 'a@b.c',
  },
  'features': {'face_aware_crop': true, 'new_ui': false},
  'version': {
    'latest_version': '0.19.0',
    'latest_version_code': 19,
    'min_supported_code': 17,
    'update_available': true,
    'force_update': false,
    'download_url': 'https://x/app.apk',
    'release_notes': 'Baru',
  },
  'maintenance': {'enabled': true, 'message': 'Sebentar'},
};

class _FakeApi implements ApiClient {
  final List<({String path, Map<String, String>? query, String? etag})> calls = [];
  Object? error;
  ApiResponse Function()? respond;

  @override
  Future<ApiResponse> post(String path,
          {Map<String, Object?> body = const {}, String? bearer}) =>
      throw UnimplementedError();

  @override
  Future<ApiResponse> get(String path,
      {Map<String, String>? query, String? ifNoneMatch, String? bearer}) async {
    calls.add((path: path, query: query, etag: ifNoneMatch));
    if (error != null) throw error!;
    return respond!();
  }
}

void main() {
  sqfliteFfiInit();

  group('RemoteConfig', () {
    test('membaca data server dan menyediakan getter bertipe', () {
      final c = RemoteConfig.fromData(_data);
      expect(c.intSetting('default_clip_duration_seconds', 1), 45);
      expect(c.doubleSetting('ratio', 0), 1.5);
      expect(c.intSetting('ratio', 9), 1); // double -> toInt
      expect(c.boolSetting('maintenance_mode', true), isFalse);
      expect(c.stringSetting('support_contact', ''), 'a@b.c');
      expect(c.feature('face_aware_crop', fallback: false), isTrue);
      expect(c.feature('new_ui'), isFalse);
      expect(c.maintenanceEnabled, isTrue);
      expect(c.maintenanceMessage, 'Sebentar');
      expect(c.version!.latestVersionCode, 19);
      expect(c.version!.updateAvailable, isTrue);
    });

    test('fallback bila kunci hilang atau tipe salah', () {
      final c = RemoteConfig.fromData({
        'settings': {'a': 'bukan angka'},
        'features': {'x': 'ya'},
      });
      expect(c.intSetting('a', 7), 7);
      expect(c.intSetting('tidak_ada', 3), 3);
      expect(c.boolSetting('a', true), isTrue);
      expect(c.feature('x'), isTrue); // tidak valid -> fallback default aktif
      expect(c.feature('x', fallback: false), isFalse);
      expect(c.version, isNull);
      expect(c.maintenanceEnabled, isFalse);
    });

    test('data bukan Map -> kosong tanpa crash', () {
      expect(RemoteConfig.fromData('aneh').settings, isEmpty);
      expect(RemoteConfig.fromData(null).features, isEmpty);
      expect(RemoteVersionInfo.fromJson({'latest_version': 1}), isNull);
    });

    test('encode/decode round-trip dan cache rusak -> kosong', () {
      final at = DateTime.fromMillisecondsSinceEpoch(5000);
      final back = RemoteConfig.decode(RemoteConfig.fromData(_data, fetchedAt: at).encode());
      expect(back.intSetting('default_clip_duration_seconds', 0), 45);
      expect(back.version!.downloadUrl, 'https://x/app.apk');
      expect(back.maintenanceMessage, 'Sebentar');
      expect(back.fetchedAt, at);
      expect(RemoteConfig.decode('{rusak').settings, isEmpty);
      expect(RemoteConfig.decode(null).fetchedAt, isNull);
      expect(RemoteConfig.decode('[1,2]').settings, isEmpty);
    });
  });

  group('RemoteConfigService', () {
    late Directory tmp;
    late AppDatabase db;
    late AppSettingsRepository store;
    late _FakeApi api;
    var now = DateTime(2026, 10, 24, 8);

    RemoteConfigService make({ApiClient? client, Duration? minInterval}) =>
        RemoteConfigService(
          api: client,
          store: store,
          appBuild: 18,
          minInterval: minInterval ?? const Duration(minutes: 5),
          clock: () => now,
        );

    setUp(() async {
      now = DateTime(2026, 10, 24, 8);
      tmp = Directory.systemTemp.createTempSync('avc_remote_');
      db = await AppDatabase.openAt(p.join(tmp.path, 't.db'),
          factory: databaseFactoryFfi);
      store = AppSettingsRepository(db.db);
      api = _FakeApi()
        ..respond = () => const ApiResponse(
              statusCode: 200,
              json: {'success': true, 'data': _data},
              etag: '"abc"',
            );
    });

    tearDown(() async {
      await db.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('tanpa API (base URL kosong) -> disabled dan tidak melakukan apa pun', () async {
      final s = make();
      expect(s.status, RemoteStatus.disabled);
      expect(s.enabled, isFalse);
      await s.refresh();
      expect(s.status, RemoteStatus.disabled);
      expect(s.config.settings, isEmpty);
    });

    test('sukses: online, memanggil endpoint dengan version_code, menyimpan cache', () async {
      final s = make(client: api);
      await s.refresh();
      expect(s.status, RemoteStatus.online);
      expect(api.calls.single.path, 'api/v1/app/config');
      expect(api.calls.single.query, {'version_code': '18'});
      expect(api.calls.single.etag, isNull);
      expect(s.config.intSetting('default_clip_duration_seconds', 0), 45);
      expect(await store.get(RemoteConfigService.etagKey), '"abc"');
      expect(await store.get(RemoteConfigService.cacheKey), isNotNull);
    });

    test('peluncuran berikutnya memuat cache lalu mengirim ETag', () async {
      await make(client: api).refresh();

      now = now.add(const Duration(hours: 1));
      api.respond = () => const ApiResponse(statusCode: 304, etag: '"abc"');
      final s2 = make(client: api);
      await s2.refresh();
      expect(api.calls.last.etag, '"abc"');
      expect(s2.status, RemoteStatus.online);
      expect(s2.config.intSetting('default_clip_duration_seconds', 0), 45);
      expect(s2.config.fetchedAt, now);
    });

    test('offline dengan cache -> memakai cache', () async {
      await make(client: api).refresh();
      now = now.add(const Duration(hours: 1));
      api.error = const ApiException('Tidak dapat terhubung ke server.', code: 'offline');
      final s = make(client: api);
      await s.refresh();
      expect(s.status, RemoteStatus.offlineCached);
      expect(s.lastError, contains('terhubung'));
      expect(s.config.intSetting('default_clip_duration_seconds', 0), 45);
    });

    test('offline tanpa cache -> offlineNoData, nilai fallback lokal dipakai', () async {
      api.error = const ApiException('x', code: 'timeout');
      final s = make(client: api);
      await s.refresh();
      expect(s.status, RemoteStatus.offlineNoData);
      expect(s.config.intSetting('default_clip_duration_seconds', 45), 45);
    });

    test('error tak terduga tidak pernah dilempar ke pemanggil', () async {
      api.error = StateError('boom');
      final s = make(client: api);
      await s.refresh();
      expect(s.status, RemoteStatus.offlineNoData);
      expect(s.lastError, isNot(contains('boom')));
    });

    test('balasan tanpa data -> dianggap gagal, cache lama tetap', () async {
      await make(client: api).refresh();
      now = now.add(const Duration(hours: 1));
      api.respond = () => const ApiResponse(statusCode: 200, json: {'success': true});
      final s = make(client: api);
      await s.refresh();
      expect(s.status, RemoteStatus.offlineCached);
      expect(s.config.intSetting('default_clip_duration_seconds', 0), 45);
    });

    test('dibatasi interval: panggilan cepat berikutnya tidak ke server', () async {
      final s = make(client: api);
      await s.refresh();
      await s.refresh();
      expect(api.calls.length, 1);
      await s.refresh(force: true);
      expect(api.calls.length, 2);
      now = now.add(const Duration(minutes: 6));
      await s.refresh();
      expect(api.calls.length, 3);
    });

    test('sesudah gagal, refresh berikutnya langsung mencoba lagi', () async {
      await make(client: api).refresh();
      now = now.add(const Duration(minutes: 10));
      api.error = const ApiException('x', code: 'offline');
      final s = make(client: api);
      await s.refresh();
      expect(s.status, RemoteStatus.offlineCached);
      api.error = null;
      await s.refresh(); // belum melewati interval, tetapi status offline -> coba lagi
      expect(s.status, RemoteStatus.online);
    });

    test('cache rusak di database diabaikan', () async {
      await store.set(RemoteConfigService.cacheKey, '{rusak');
      api.error = const ApiException('x', code: 'offline');
      final s = make(client: api);
      await s.refresh();
      expect(s.status, RemoteStatus.offlineNoData);
    });

    test('refresh bersamaan tidak menggandakan permintaan', () async {
      final s = make(client: api);
      await Future.wait([s.refresh(), s.refresh(force: true)]);
      expect(api.calls.length, 1);
    });
  });

  group('HttpApiClient (server lokal sungguhan)', () {
    late HttpServer server;
    late String base;
    int status = 200;
    String body = '{"success":true,"data":{}}';
    Duration delay = Duration.zero;
    Map<String, String> lastHeaders = {};
    String lastPath = '';
    String lastQuery = '';

    setUpAll(() {
      HttpOverrides.global = null;
    });

    setUp(() async {
      status = 200;
      body = '{"success":true,"data":{}}';
      delay = Duration.zero;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        lastPath = req.uri.path;
        lastQuery = req.uri.query;
        lastHeaders = {
          'if-none-match': req.headers.value('if-none-match') ?? '',
          'accept': req.headers.value('accept') ?? '',
        };
        try {
          if (delay > Duration.zero) await Future<void>.delayed(delay);
          req.response.statusCode = status;
          req.response.headers.set('ETag', '"e1"');
          req.response.write(body);
          await req.response.close();
        } catch (_) {
          // Klien sudah memutus koneksi (mis. tes timeout).
        }
      });
    });

    tearDown(() async => server.close(force: true));

    test('200 JSON: path, query, header, etag', () async {
      final res = await HttpApiClient(baseUrl: base).get(
        'api/v1/app/config',
        query: {'version_code': '18'},
        ifNoneMatch: '"old"',
      );
      expect(res.statusCode, 200);
      expect(res.json!['success'], isTrue);
      expect(res.etag, '"e1"');
      expect(lastPath, '/api/v1/app/config');
      expect(lastQuery, 'version_code=18');
      expect(lastHeaders['if-none-match'], '"old"');
      expect(lastHeaders['accept'], 'application/json');
    });

    test('base URL dengan sub-folder dan garis miring akhir', () async {
      await HttpApiClient(baseUrl: '$base/sub/').get('api/v1/health');
      expect(lastPath, '/sub/api/v1/health');
    });

    test('304 -> notModified dengan etag lama', () async {
      status = 304;
      body = '';
      final res = await HttpApiClient(baseUrl: base)
          .get('x', ifNoneMatch: '"old"');
      expect(res.notModified, isTrue);
    });

    test('500 -> ApiException ramah tanpa isi mentah', () async {
      status = 500;
      body = 'Trace: secret.php line 3';
      await expectLater(
        HttpApiClient(baseUrl: base).get('x'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'server_error')
            .having((e) => e.message, 'message', isNot(contains('secret')))),
      );
    });

    test('400 memakai pesan error dari server', () async {
      status = 400;
      body = '{"success":false,"error":{"code":"x","message":"Parameter salah."}}';
      await expectLater(
        HttpApiClient(baseUrl: base).get('x'),
        throwsA(isA<ApiException>().having((e) => e.message, 'm', 'Parameter salah.')),
      );
    });

    test('balasan bukan JSON -> bad_response', () async {
      body = '<html>bukan json</html>';
      await expectLater(
        HttpApiClient(baseUrl: base).get('x'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'bad_response')),
      );
    });

    test('timeout -> ApiException timeout', () async {
      delay = const Duration(milliseconds: 600);
      await expectLater(
        HttpApiClient(baseUrl: base, timeout: const Duration(milliseconds: 150)).get('x'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'timeout')),
      );
    });

    test('server mati -> offline', () async {
      final port = server.port;
      await server.close(force: true);
      await expectLater(
        HttpApiClient(baseUrl: 'http://127.0.0.1:$port', timeout: const Duration(seconds: 2)).get('x'),
        // Di Windows, koneksi ditolak bisa baru gagal setelah beberapa detik
        // sehingga tampil sebagai timeout; keduanya adalah kegagalan jaringan.
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true)),
      );
    });

    test('base URL tidak valid ditolak', () async {
      await expectLater(
        HttpApiClient(baseUrl: 'bukan url').get('x'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'bad_base_url')),
      );
    });
  });

  test('jsonEncode ke cache tidak kehilangan unicode', () {
    final c = RemoteConfig.fromData({
      'maintenance': {'enabled': true, 'message': 'Pemeliharaan – pukul 02:00 ✓'},
    });
    expect(RemoteConfig.decode(c.encode()).maintenanceMessage, contains('✓'));
    expect(jsonDecode(c.encode()), isA<Map>());
  });
}
