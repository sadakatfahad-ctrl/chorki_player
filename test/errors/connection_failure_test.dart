import 'dart:io';

import 'package:chorki_player/src/errors/error.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final options = RequestOptions(path: '/r');

  test('no connection is a connection failure', () {
    expect(isConnectionFailure(const SocketException('down')), isTrue);
    expect(
      isConnectionFailure(
        DioException.connectionError(
          requestOptions: options,
          reason: 'refused',
        ),
      ),
      isTrue,
    );
    expect(
      isConnectionFailure(
        DioException.connectionTimeout(
          requestOptions: options,
          timeout: const Duration(seconds: 8),
        ),
      ),
      isTrue,
    );
    expect(
      isConnectionFailure(
        DioException(
          requestOptions: options,
          error: const SocketException('reset'),
        ),
      ),
      isTrue,
    );
  });

  test('a response, or anything else, is not', () {
    expect(
      isConnectionFailure(
        DioException(
          requestOptions: options,
          response: Response<dynamic>(requestOptions: options, statusCode: 500),
          type: DioExceptionType.badResponse,
        ),
      ),
      isFalse,
    );
    expect(isConnectionFailure(StateError('x')), isFalse);
    expect(isConnectionFailure(null), isFalse);
  });
}
