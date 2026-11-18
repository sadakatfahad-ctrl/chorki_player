import 'dart:io';

import 'package:dio/dio.dart';

import '../errors/error.dart';
import '../errors/no_internet_exception.dart';
import 'api_result.dart';

/// Base for API data sources: sends requests with retries of transient
/// connection failures and turns responses into [ApiResult]s.
abstract class DioApiProvider {
  /// The client requests go through.
  Dio get dioClient;

  /// Waits before each retry of an idempotent request that failed without a
  /// response. One entry per retry.
  List<Duration> get retryDelays => defaultRetryDelays;

  /// The default [retryDelays].
  static const List<Duration> defaultRetryDelays = [
    Duration(milliseconds: 300),
    Duration(milliseconds: 900),
  ];

  Future<ApiResult> _send(
    Future<Response<dynamic>> Function() request, {
    bool idempotent = false,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await request();
        return ApiResult.fromResponse(response);
      } on Object catch (error) {
        if (error is DioException && error.response != null) {
          return ApiResult.fromResponse(error.response!);
        }
        if (error is! DioException && error is! SocketException) rethrow;
        // A dropped or stale (HTTP/2 GOAWAY) connection usually succeeds on
        // a fresh one.
        final delays = retryDelays;
        if (idempotent &&
            attempt < delays.length &&
            isTransientFailure(error)) {
          await Future<void>.delayed(delays[attempt]);
          continue;
        }
        if (isConnectionFailure(error)) throw const NoInternetException();
        rethrow;
      }
    }
  }

  /// GETs [url] (retried on a dropped connection).
  Future<ApiResult> get(String url) =>
      _send(() => dioClient.get<dynamic>(url), idempotent: true);
}
