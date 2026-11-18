// The built-in implementations pass the same conformance suites that
// package:chorki_player/chorki_player_testing.dart offers to hosts.
import 'dart:typed_data';

import 'package:chorki_player/chorki_player.dart';
import 'package:chorki_player/chorki_player_testing.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/diagnostics.dart';

class _Offline implements MatomoTransport {
  @override
  Future<bool> send(Uri endpoint, List<String> requests) async => false;
}

class _NoNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      throw DioException.connectionError(requestOptions: options, reason: 'x');

  @override
  void close({bool force = false}) {}
}

/// A sink that breaks the contract, to prove the suite notices.
class _Throwing extends ChorkiAnalyticsSink {
  @override
  void onEvent(ChorkiAnalyticsEvent event) => throw StateError('boom');
}

void run(List<ChorkiConformanceCase> cases) {
  for (final c in cases) {
    test(c.name, c.body);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'MemoryAnalyticsSink',
    () => run(analyticsSinkConformance(MemoryAnalyticsSink.new)),
  );
  group('CallbackAnalyticsSink', () {
    run(analyticsSinkConformance(() => CallbackAnalyticsSink((_) {})));
  });
  group('MatomoAnalyticsSink', () {
    run(
      analyticsSinkConformance(
        () => MatomoAnalyticsSink(
          const MatomoConfig(url: 'https://matomo.test', siteId: 1),
          transport: _Offline(),
        ),
      ),
    );
  });
  group('InMemoryAnalyticsStorage', () {
    run(analyticsStorageConformance(InMemoryAnalyticsStorage.new));
  });
  group('DioMatomoTransport', () {
    run(
      matomoTransportConformance(
        () => DioMatomoTransport(dio: Dio()..httpClientAdapter = _NoNetwork()),
      ),
    );
  });
  group('ChorkiFloatingPipDelegate', () {
    // No `floating` plugin in tests: every call reports and reads as
    // unavailable, which is exactly the contract.
    setUp(captureDiagnostics);
    run(pipDelegateConformance(ChorkiFloatingPipDelegate.new));
  });

  test('the suite catches a sink that throws', () async {
    final c = analyticsSinkConformance(_Throwing.new).first;
    await expectLater(c.body(), throwsA(isA<ConformanceFailure>()));
  });

  test('helpers: fake clock, sequential ids, sample events fit the schema', () {
    final clock = ChorkiFakeClock()..advance(const Duration(seconds: 5));
    expect(clock(), DateTime.utc(2026, 1, 1, 12, 0, 5));
    final ids = sequentialIds('v');
    expect([ids(), ids()], ['v1', 'v2']);
    for (final type in ChorkiAnalyticsEventType.values) {
      final e = sampleAnalyticsEvent(type);
      expect(ChorkiAnalyticsSchema.validate(type, e.data), isEmpty);
    }
    expect(const ConformanceFailure('x').toString(), contains('x'));
  });
}
