import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chorki_player/src/core/diagnostics.dart';
import 'package:chorki_player/src/core/result.dart';
import 'package:chorki_player/src/data/datasources/bytes_data_sources.dart';
import 'package:chorki_player/src/data/model/byte_model.dart';
import 'package:chorki_player/src/data/repositories/byte_repository_impl.dart';
import 'package:chorki_player/src/domain/entity/byte_data_entity.dart';
import 'package:chorki_player/src/errors/chorki_player_error.dart';
import 'package:chorki_player/src/errors/no_internet_exception.dart';
import 'package:chorki_player/src/errors/server_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers each call with the next queued result: a [ByteModel], an
/// exception to throw, or a [Completer] that stays pending.
class _FakeDataSource extends BytesDataSources {
  _FakeDataSource() : super(dio: Dio());

  final List<Object> results = [];
  int calls = 0;

  @override
  Future<ByteModel> getByteData(String route) async {
    calls++;
    final next = results.removeAt(0);
    if (next is Completer<ByteModel>) return next.future;
    if (next is ByteModel) return next;
    if (next is Error) throw next;
    throw next as Exception;
  }
}

ByteModel _model(String url) => ByteModel(id: 1, thumbnailUrl: '', url: url);

/// Replays queued responses; an exception is thrown as the transport error.
class _FakeAdapter implements HttpClientAdapter {
  final List<Object> responses = [];
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    final next = responses.removeAt(0);
    if (next is (int, Object)) {
      return ResponseBody.fromString(
        jsonEncode(next.$2),
        next.$1,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    throw next as Exception;
  }

  @override
  void close({bool force = false}) {}
}

class _TestDataSource extends BytesDataSources {
  _TestDataSource(this.adapter)
    : super(dio: Dio()..httpClientAdapter = adapter);

  final _FakeAdapter adapter;

  @override
  List<Duration> get retryDelays => const [Duration.zero, Duration.zero];
}

const _ok = (
  200,
  {
    'result': {
      'data': {'id': 7, 'url': 'https://test.local/v.mp4'},
    },
  },
);

DioException _transport(DioExceptionType type) => DioException(
  requestOptions: RequestOptions(path: '/r'),
  type: type,
);

void main() {
  group('ByteRepositoryImpl', () {
    late _FakeDataSource source;
    late DateTime now;
    late ByteRepositoryImpl repo;

    setUp(() {
      source = _FakeDataSource();
      now = DateTime(2026);
      repo = ByteRepositoryImpl(byteDataSources: source, clock: () => now);
    });

    String? urlOf(Result<ByteDataEntity> result) =>
        result.fold((_) => null, (data) => data.url);

    test('a revisit within the TTL is served from the cache', () async {
      source.results.addAll([_model('a1'), _model('a2')]);
      expect(urlOf(await repo.getByteData('r')), 'a1');
      expect(urlOf(await repo.getByteData('r')), 'a1');
      expect(source.calls, 1);

      now = now.add(const Duration(minutes: 5));
      expect(urlOf(await repo.getByteData('r')), 'a2', reason: 'expired');
      expect(source.calls, 2);
    });

    test('refresh skips the cache and replaces it', () async {
      source.results.addAll([_model('a1'), _model('a2')]);
      await repo.getByteData('r');
      expect(urlOf(await repo.getByteData('r', refresh: true)), 'a2');
      expect(urlOf(await repo.getByteData('r')), 'a2');
      expect(source.calls, 2);
    });

    test('concurrent requests for one route share a fetch', () async {
      final pending = Completer<ByteModel>();
      source.results.add(pending);
      final first = repo.getByteData('r');
      final second = repo.getByteData('r');
      pending.complete(_model('a'));
      expect(urlOf(await first), 'a');
      expect(urlOf(await second), 'a');
      expect(source.calls, 1);
    });

    test('failures are not cached', () async {
      source.results.addAll([const NoInternetException(), _model('a')]);
      final failed = await repo.getByteData('r');
      expect(failed, isA<Err<ByteDataEntity>>());
      expect(
        failed.fold((e) => e.code, (_) => null),
        ChorkiErrorCode.noInternet,
      );
      expect(urlOf(await repo.getByteData('r')), 'a');
      expect(source.calls, 2);
    });

    test(
      'keeps at most maxCacheEntries, dropping the least recently used',
      () async {
        repo = ByteRepositoryImpl(
          byteDataSources: source,
          maxCacheEntries: 2,
          clock: () => now,
        );
        source.results.addAll([_model('a'), _model('b'), _model('c')]);
        await repo.getByteData('a');
        await repo.getByteData('b');
        await repo.getByteData('a'); // a is now the most recent
        await repo.getByteData('c'); // evicts b
        expect(source.calls, 3);
        source.results.addAll([_model('b2')]);
        expect(urlOf(await repo.getByteData('a')), 'a');
        expect(urlOf(await repo.getByteData('b')), 'b2');
        expect(source.calls, 4);
      },
    );

    test('a server error keeps its status and message as detail', () async {
      source.results.add(
        const ServerException(
          message: 'Server Error',
          serverMessage: 'down',
          statusCode: 503,
        ),
      );
      final result = await repo.getByteData('r');
      expect(
        result.fold((e) => e, (_) => null),
        const ChorkiPlayerError(
          ChorkiErrorCode.server,
          statusCode: 503,
          detail: 'down',
        ),
      );
    });

    test('status codes map to codes; only 5xx is transient', () async {
      for (final (status, code, transient) in const [
        (401, ChorkiErrorCode.unauthorized, false),
        (403, ChorkiErrorCode.forbidden, false),
        (404, ChorkiErrorCode.notFound, false),
        (422, ChorkiErrorCode.badRequest, false),
        (502, ChorkiErrorCode.server, true),
      ]) {
        source.results.add(ServerException(statusCode: status));
        final error = (await repo.getByteData(
          's$status',
        )).fold((e) => e, (_) => null)!;
        expect(error.code, code, reason: '$status');
        expect(error.isTransient, transient, reason: '$status');
      }
    });

    test(
      'a route without a video URL is a permanent noVideoUrl error',
      () async {
        source.results.add(_model(''));
        final result = await repo.getByteData('r');
        expect(
          result.fold((e) => e.code, (_) => null),
          ChorkiErrorCode.noVideoUrl,
        );
      },
    );

    test('a typed error from the data source is passed through', () async {
      source.results.add(
        const ChorkiPlayerError(ChorkiErrorCode.malformedResponse),
      );
      final result = await repo.getByteData('r');
      expect(
        result.fold((e) => e.code, (_) => null),
        ChorkiErrorCode.malformedResponse,
      );
    });

    test('an unexpected exception is reported to diagnostics', () async {
      final reported = <String>[];
      ChorkiDiagnostics.onError = (e, st, context) => reported.add(context);
      addTearDown(() => ChorkiDiagnostics.onError = null);
      source.results.add(StateError('bug'));
      final result = await repo.getByteData('r');
      expect(result.fold((e) => e.code, (_) => null), ChorkiErrorCode.unknown);
      expect(reported, ['repository.getByteData']);
    });
  });

  group('DioApiProvider retries', () {
    late _FakeAdapter adapter;
    late _TestDataSource source;

    setUp(() {
      adapter = _FakeAdapter();
      source = _TestDataSource(adapter);
    });

    test('a dropped connection is retried on a fresh request', () async {
      adapter.responses.addAll([
        _transport(DioExceptionType.unknown),
        _transport(DioExceptionType.connectionError),
        _ok,
      ]);
      final model = await source.getByteData('https://api.test/r');
      expect(model.url, 'https://test.local/v.mp4');
      expect(adapter.requests, 3);
    });

    test('raw transport errors from the HTTP/2 adapter are retried', () async {
      // What a stale connection or GOAWAY looks like before dio wraps it.
      adapter.responses.addAll([
        const HttpException('Connection closed before full header'),
        const SocketException('Connection reset by peer'),
        _ok,
      ]);
      final model = await source.getByteData('https://api.test/r');
      expect(model.url, 'https://test.local/v.mp4');
      expect(adapter.requests, 3);
    });

    test('a timeout is not retried here (the player retries later)', () async {
      adapter.responses.add(_transport(DioExceptionType.connectionTimeout));
      await expectLater(
        source.getByteData('https://api.test/r'),
        throwsA(isA<NoInternetException>()),
      );
      expect(adapter.requests, 1);
    });

    test('gives up after the retries, as no internet', () async {
      adapter.responses.addAll([
        for (var i = 0; i < 3; i++)
          _transport(DioExceptionType.connectionError),
      ]);
      await expectLater(
        source.getByteData('https://api.test/r'),
        throwsA(isA<NoInternetException>()),
      );
      expect(adapter.requests, 3);
    });

    test('a body without result.data is a malformedResponse', () async {
      adapter.responses.add((200, {'result': 'nope'}));
      await expectLater(
        source.getByteData('https://api.test/r'),
        throwsA(
          isA<ChorkiPlayerError>().having(
            (e) => e.code,
            'code',
            ChorkiErrorCode.malformedResponse,
          ),
        ),
      );
    });

    test('a server response is never retried', () async {
      adapter.responses.add((503, {'message': 'maintenance'}));
      await expectLater(
        source.getByteData('https://api.test/r'),
        throwsA(
          isA<ServerException>().having(
            (e) => e.serverMessage,
            'serverMessage',
            'maintenance',
          ),
        ),
      );
      expect(adapter.requests, 1);
    });

    test('a cancelled request is not retried', () async {
      adapter.responses.add(_transport(DioExceptionType.cancel));
      await expectLater(
        source.getByteData('https://api.test/r'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, 1);
    });
  });
}
