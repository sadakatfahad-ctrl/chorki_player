import 'package:chorki_player/src/data/model/byte_model.dart';
import 'package:chorki_player/src/errors/server_exception.dart';
import 'package:chorki_player/src/network/dio_api_provider.dart';

class BytesDataSources extends DioApiProvider {
  Future<ByteModel> getByteData(String route) async {
    final response = await get(route);

    final data = response.data;
    if (data is Map) {
      return ByteModel.fromJson(data['result']);
    }
    throw const ServerException(message: 'Malformed response data');
  }
}
