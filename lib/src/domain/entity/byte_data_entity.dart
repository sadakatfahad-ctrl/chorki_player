import 'package:equatable/equatable.dart';

import 'ad_campaign_entity.dart';

class ByteDataEntity extends Equatable {
  const ByteDataEntity({
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

  @override
  List<Object?> get props => [id, thumbnailUrl, url, adCampaign];
}
