import 'package:chorki_player/src/domain/entity/ad_campaign_entity.dart';
import 'package:chorki_player/src/domain/entity/byte_data_entity.dart';
import 'package:chorki_player/src/helpers/json_helper.dart';

class ByteModel {
  const ByteModel({
    required this.id,
    required this.thumbnailUrl,
    required this.url,
    this.adCampaign,
  });

  final int id;
  final String thumbnailUrl;
  final String url;
  final AdCampaignEntity? adCampaign;

  String get adTagUrl => adCampaign?.url ?? '';

  static ByteModel fromJson(dynamic json) {
    final data = json is Map ? json['data'] : null;
    final helper = JsonHelper(json: data);
    final campaign = data is Map ? data['ad_campaign'] : null;
    final campaignHelper = JsonHelper(json: campaign);
    final campaignUrl = campaignHelper.getJsonString('url');

    return ByteModel(
      id: helper.getJsonInt('id'),
      thumbnailUrl: helper.getJsonString('poster_background'),
      url: helper.getJsonString('url'),
      adCampaign: campaignUrl.isEmpty
          ? null
          : AdCampaignEntity(
              id: campaignHelper.getJsonString('id'),
              title: campaignHelper.getJsonString('title'),
              url: campaignUrl,
            ),
    );
  }

  ByteDataEntity toEntity() => ByteDataEntity(
    id: id,
    thumbnailUrl: thumbnailUrl,
    url: url,
    adCampaign: adCampaign,
  );
}
