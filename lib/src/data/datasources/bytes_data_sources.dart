import 'package:dio/dio.dart';

import '../../errors/chorki_player_error.dart';
import '../../network/dio_api_provider.dart';
import '../model/byte_model.dart';

/// Fetches a byte route from the Chorki API.
class BytesDataSources extends DioApiProvider {
  /// Uses [dio] for requests.
  BytesDataSources({required this._dio});

  final Dio _dio;

  @override
  Dio get dioClient => _dio;

  /// Resolves [route]. Throws a [ChorkiPlayerError] with
  /// [ChorkiErrorCode.malformedResponse] when the body is not
  /// `{"result": {"data": {...}}}`.
  Future<ByteModel> getByteData(String route) async {
    final response = await get(route);
    final data = response.data;
    final result = data is Map ? data['result'] : null;
    if (result is! Map || result['data'] is! Map) {
      throw const ChorkiPlayerError(
        ChorkiErrorCode.malformedResponse,
        detail: 'expected {"result": {"data": {...}}}',
      );
    }
    return ByteModel.fromJson(result);
  }
}
