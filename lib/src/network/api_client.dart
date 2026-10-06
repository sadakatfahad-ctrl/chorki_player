import 'package:dio/dio.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  Dio? _dio;

  static const Duration connectTimeout = Duration(seconds: 8);
  static const Duration _receiveTimeout = Duration(seconds: 15);
  static const Duration _sendTimeout = Duration(seconds: 15);
  static const Duration _poolIdleTimeout = Duration(seconds: 10);

  Dio get dio => _dio ??= _build();

  Dio _build() {
    final dio =
        Dio(
            BaseOptions(
              connectTimeout: connectTimeout,
              receiveTimeout: _receiveTimeout,
              sendTimeout: _sendTimeout,
              headers: const {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
              },
            ),
          )
          ..httpClientAdapter = Http2Adapter(
            ConnectionManager(idleTimeout: _poolIdleTimeout),
          );
    return dio;
  }
}
