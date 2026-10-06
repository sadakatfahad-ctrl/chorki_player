import 'package:chorki_player/src/domain/entity/byte_data_entity.dart';
import 'package:chorki_player/src/helpers/json_helper.dart';

class ByteModel {
  const ByteModel({
    required this.id,
    required this.thumbnailUrl,
    required this.url,
  });

  final int id;
  final String thumbnailUrl;
  final String url;

  static ByteModel fromJson(dynamic json) {
    final helper = JsonHelper(json: json is Map ? json['data'] : null);

    return ByteModel(
      id: helper.getJsonInt('id'),
      thumbnailUrl: helper.getJsonString('poster_background'),
      url: helper.getJsonString('url'),
    );
  }

  ByteDataEntity toEntity() =>
      ByteDataEntity(id: id, thumbnailUrl: thumbnailUrl, url: url);
}
