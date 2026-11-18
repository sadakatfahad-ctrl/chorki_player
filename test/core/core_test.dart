import 'dart:async';
import 'dart:typed_data';

import 'package:chorki_player/chorki_player.dart';
import 'package:chorki_player/src/core/guard.dart';
import 'package:chorki_player/src/core/ids.dart';
import 'package:chorki_player/src/core/result.dart';
import 'package:chorki_player/src/core/services.dart';
import 'package:chorki_player/src/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> headers = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    headers.add(Map.of(options.headers));
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late List<String> reported;

  setUp(() {
    reported = [];
    ChorkiDiagnostics.onError = (e, st, context) => reported.add(context);
  });
  tearDown(() => ChorkiDiagnostics.onError = null);

  group('ChorkiDiagnostics', () {
    test('a throwing handler never escapes', () {
      ChorkiDiagnostics.onError = (e, st, c) => throw StateError('handler');
      expect(
        () => ChorkiDiagnostics.report(Exception(), StackTrace.current, 'x'),
        returnsNormally,
      );
    });

    test('no handler: reporting is a no-op', () {
      ChorkiDiagnostics.onError = null;
      ChorkiDiagnostics.report(Exception(), StackTrace.current, 'x');
    });
  });

  group('guard', () {
    test('guardAsync reports and returns false on error', () async {
      expect(await guardAsync(() async => throw StateError('x'), 'a.b'), false);
      expect(await guardAsync(() async {}, 'a.c'), true);
      expect(reported, ['a.b']);
    });

    test('fireAndReport catches synchronous and async errors', () async {
      fireAndReport(() => throw StateError('sync'), 'sync');
      fireAndReport(() async => throw StateError('async'), 'async');
      await pumpEventQueue();
      expect(reported, ['sync', 'async']);
    });

    test('guardSync returns the fallback', () {
      expect(guardSync<int>(() => throw StateError('x'), 's', 7), 7);
      expect(guardSync<int>(() => 1, 's', 7), 1);
      expect(reported, ['s']);
    });
  });

  group('ids', () {
    test('randomId is alphanumeric of the given length', () {
      expect(randomId(), matches(RegExp(r'^[A-Za-z0-9]{12}$')));
      expect(randomId(4), hasLength(4));
    });

    test('secureHex gives 2 hex characters per byte', () {
      expect(secureHex(8), matches(RegExp(r'^[0-9a-f]{16}$')));
    });
  });

  group('Result', () {
    test('fold picks the branch', () {
      const Result<int> ok = Ok(1);
      const Result<int> err = Err(ChorkiPlayerError(ChorkiErrorCode.notFound));
      expect(ok.fold((_) => -1, (v) => v), 1);
      expect(err.fold((e) => e.code, (_) => null), ChorkiErrorCode.notFound);
    });
  });

  group('ChorkiNetworkConfig', () {
    test('static and provided headers are sent; equality by value', () async {
      var token = 'a';
      final config = ChorkiNetworkConfig(
        headers: const {'X-App': '1'},
        headersProvider: () async => {'Authorization': 'Bearer $token'},
        useHttp2: false,
      );
      final client = ApiClient(config);
      final adapter = _RecordingAdapter();
      client.dio.httpClientAdapter = adapter;

      await client.dio.get<dynamic>('https://api.test/r');
      token = 'b';
      await client.dio.get<dynamic>('https://api.test/r');

      expect(adapter.headers.map((h) => h['X-App']), ['1', '1']);
      expect(adapter.headers.map((h) => h['Authorization']), [
        'Bearer a',
        'Bearer b',
      ]);
      expect(
        const ChorkiNetworkConfig(headers: {'a': '1'}),
        const ChorkiNetworkConfig(headers: {'a': '1'}),
      );
    });

    test('a failing headersProvider fails the request, not the app', () async {
      final client = ApiClient(
        ChorkiNetworkConfig(
          headersProvider: () async => throw StateError('no token'),
          useHttp2: false,
        ),
      );
      client.dio.httpClientAdapter = _RecordingAdapter();
      await expectLater(
        client.dio.get<dynamic>('https://api.test/r'),
        throwsA(isA<DioException>()),
      );
    });
  });

  test('configure leaves the client of earlier players working '
      '(bug: it closed the shared Dio under them)', () async {
    ChorkiServices.resetForTesting();
    final before = ChorkiServices.instance.apiClient
      ..dio.httpClientAdapter = _RecordingAdapter();
    ChorkiServices.configure(
      network: const ChorkiNetworkConfig(headers: {'X': '1'}, useHttp2: false),
    );
    expect(ChorkiServices.instance.apiClient, isNot(same(before)));
    final r = await before.dio.get<dynamic>('https://api.test/r');
    expect(r.statusCode, 200);
    ChorkiServices.resetForTesting();
  });

  group('ChorkiPlayerError', () {
    test('maps exceptions to codes', () {
      expect(
        ChorkiPlayerError.from(TimeoutException('t')).code,
        ChorkiErrorCode.timeout,
      );
      expect(
        ChorkiPlayerError.from(const FormatException('f')).code,
        ChorkiErrorCode.malformedResponse,
      );
      expect(
        ChorkiPlayerError.from(StateError('s')).code,
        ChorkiErrorCode.unknown,
      );
    });

    test('every code has a localized message', () {
      const strings = ChorkiPlayerStrings();
      for (final code in ChorkiErrorCode.values) {
        expect(ChorkiPlayerError(code).message(strings), isNotEmpty);
      }
    });
  });
}
