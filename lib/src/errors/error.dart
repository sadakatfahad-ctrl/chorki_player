import 'dart:io';

import 'package:dio/dio.dart';

bool isConnectionFailure(Object? error) {
  if (error is SocketException) return true;
  if (error is! DioException) return false;
  if (error.response != null) return false;
  if (error.error is SocketException) return true;
  return error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout;
}

/// A failure worth retrying at once: the request never got a response
/// because the connection was refused or dropped, or an HTTP/2 connection
/// closed or sent GOAWAY mid-request. Those usually succeed on a fresh
/// connection. Timeouts are not included: retrying them here would multiply
/// the wait on a dead network (the player retries later anyway). A server
/// response, even 5xx, is not transient.
bool isTransientFailure(Object? error) {
  if (error is SocketException || error is HttpException) return true;
  if (error is! DioException) return false;
  if (error.response != null) return false;
  switch (error.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.unknown:
      return true;
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.cancel:
    case DioExceptionType.transformTimeout:
    case DioExceptionType.badResponse:
    case DioExceptionType.badCertificate:
      return false;
  }
}
