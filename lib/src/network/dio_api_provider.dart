import 'dart:io';

import 'package:chorki_player/src/errors/error.dart';
import 'package:chorki_player/src/errors/no_internet_exception.dart';
import 'package:chorki_player/src/network/api_client.dart';
import 'package:chorki_player/src/network/api_result.dart';
import 'package:dio/dio.dart';

abstract class DioApiProvider {
  Dio get dioClient => ApiClient.instance.dio;

  Future<ApiResult> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      return ApiResult.fromResponse(response);
    } on SocketException {
      throw const NoInternetException();
    } on DioException catch (error) {
      final response = error.response;
      if (response != null) return ApiResult.fromResponse(response);
      if (isConnectionFailure(error)) throw const NoInternetException();
      rethrow;
    }
  }

  Future<ApiResult> get(String url) => _send(() => dioClient.get<dynamic>(url));
}
