import 'package:equatable/equatable.dart';

import 'ad_campaign_entity.dart';

/// A resolved byte: what to play, its poster and its ads.
class ByteDataEntity extends Equatable {
  /// Byte [id] playing [url].
  const ByteDataEntity({
    required this.id,
    required this.thumbnailUrl,
    required this.url,
    this.adCampaign,
  });

  /// The byte's id (0 for a direct URL).
  final int id;

  /// Poster shown while the video loads.
  final String thumbnailUrl;

  /// The video URL.
  final String url;

  /// The ad campaign, if the byte has ads.
  final AdCampaignEntity? adCampaign;

  /// The campaign's ad tag, or empty.
  String get adTagUrl => adCampaign?.url ?? '';

  @override
  List<Object?> get props => [id, thumbnailUrl, url, adCampaign];
}
