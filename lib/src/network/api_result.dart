import 'dart:convert';
import 'package:chorki_player/src/errors/server_exception.dart';
import 'package:dio/dio.dart';

class ApiResult {
  const ApiResult({
    required this.data,
    required this.statusCode,
    required this.message,
  });

  final dynamic data;
  final int statusCode;
  final String message;

  factory ApiResult.fromResponse(Response<dynamic> response) {
    final statusCode = response.statusCode ?? 0;

    if (statusCode == 200 || statusCode == 201) {
      return ApiResult(
        data: _decodeBody(response.data),
        statusCode: statusCode,
        message: 'Success',
      );
    }

    if (statusCode == 204) {
      return ApiResult(data: null, statusCode: statusCode, message: 'Success');
    }

    throw ServerException(
      message: _fallbackMessage(statusCode),
      statusCode: statusCode,
      serverMessage: _serverMessage(_decodeBody(response.data)),
    );
  }

  static String _fallbackMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Bad Request';
      case 401:
        return 'Unauthorized';
      case 403:
        return 'Forbidden';
      case 404:
        return 'Not Found';
      case 422:
        return 'Validation Error';
    }
    if (statusCode >= 500) return 'Server Error';
    return 'Error';
  }

  static dynamic _decodeBody(dynamic data) {
    if (data is String && data.isNotEmpty) {
      try {
        return jsonDecode(data);
      } on FormatException {
        return data;
      }
    }
    return data;
  }

  static String? _serverMessage(dynamic body) {
    if (body is! Map) return null;

    final message = body['message'];
    if (message is! String) return null;

    final trimmed = message.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
