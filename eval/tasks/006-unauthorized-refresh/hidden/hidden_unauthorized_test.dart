import 'dart:typed_data';

import 'package:chorki_player/chorki_player.dart';
import 'package:chorki_player/src/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.statuses);
  final List<int> statuses;
  final List<String?> auth = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    auth.add(options.headers['Authorization'] as String?);
    return ResponseBody.fromString('{}', statuses.removeAt(0));
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('a 401 refreshes the token once and retries', () async {
    var token = 'old';
    var refreshes = 0;
    final client = ApiClient(
      ChorkiNetworkConfig(
        useHttp2: false,
        headersProvider: () async => {'Authorization': token},
        onUnauthorized: () async {
          refreshes++;
          token = 'new';
          return true;
        },
      ),
    );
    final adapter = _Adapter([401, 200]);
    client.dio.httpClientAdapter = adapter;
    final r = await client.dio.get<dynamic>(
      'https://api.test/r',
      options: Options(validateStatus: (s) => s == 200),
    );
    expect(r.statusCode, 200);
    expect(refreshes, 1);
    expect(adapter.auth, ['old', 'new']);
  });

  test('a refusal or a second 401 fails as before', () async {
    final client = ApiClient(
      ChorkiNetworkConfig(useHttp2: false, onUnauthorized: () async => true),
    );
    final adapter = _Adapter([401, 401]);
    client.dio.httpClientAdapter = adapter;
    await expectLater(
      client.dio.get<dynamic>(
        'https://api.test/r',
        options: Options(validateStatus: (s) => s == 200),
      ),
      throwsA(isA<DioException>()),
    );
    expect(adapter.auth, hasLength(2), reason: 'retried once only');
  });
}
