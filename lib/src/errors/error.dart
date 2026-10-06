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
