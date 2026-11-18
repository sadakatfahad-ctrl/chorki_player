import 'package:dio/dio.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';

import 'chorki_network_config.dart';

/// Builds the [Dio] client the player uses for its own requests.
class ApiClient {
  /// Creates a client for [config]. The [Dio] is built on first use.
  ApiClient([this.config = const ChorkiNetworkConfig()]);

  /// The settings this client was built with.
  final ChorkiNetworkConfig config;

  static const Duration _sendTimeout = Duration(seconds: 15);
  static const Duration _poolIdleTimeout = Duration(seconds: 10);

  Dio? _dio;

  /// The shared client.
  Dio get dio => _dio ??= _build();

  Dio _build() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: config.connectTimeout,
        receiveTimeout: config.receiveTimeout,
        sendTimeout: _sendTimeout,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          ...config.headers,
        },
      ),
    );
    if (config.useHttp2) {
      dio.httpClientAdapter = Http2Adapter(
        ConnectionManager(idleTimeout: _poolIdleTimeout),
      );
    }
    final provider = config.headersProvider;
    if (provider != null) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            try {
              options.headers.addAll(await provider());
              handler.next(options);
            } catch (e, st) {
              // guardrail:allow swallowed_error - forwarded to dio, the request fails with it.
              handler.reject(
                DioException(requestOptions: options, error: e, stackTrace: st),
              );
            }
          },
        ),
      );
    }
    return dio;
  }

  /// Closes the client's connections.
  void close() => _dio?.close(force: true);
}
