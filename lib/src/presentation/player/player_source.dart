import '../../analytics/chorki_analytics_schema.dart';
import '../../analytics/chorki_media_metadata.dart';
import '../../domain/entity/ad_campaign_entity.dart';
import '../../domain/entity/byte_data_entity.dart';
import '../bytes_screen/byte_screen_event.dart';

/// The event that loads a player's source: a route lookup, or a direct URL
/// (`ChorkiPlayer.url`) wrapped as already-resolved byte data.
ByteScreenEvent loadEventFor({
  required String route,
  required String? videoUrl,
  required String posterUrl,
  required String adTagUrl,
  bool refresh = false,
}) {
  final url = videoUrl;
  if (url == null) return ByteScreenInitialEvent(route, refresh: refresh);
  return ByteScreenSourceEvent(
    ByteDataEntity(
      id: 0,
      thumbnailUrl: posterUrl,
      url: url,
      adCampaign: adTagUrl.isEmpty
          ? null
          : AdCampaignEntity(id: '', title: '', url: adTagUrl),
    ),
  );
}

/// [given] metadata completed from the resolved byte: its id and video URL
/// when the app did not set them.
ChorkiMediaMetadata metadataFor(
  ChorkiMediaMetadata? given,
  ByteDataEntity? data,
  String? videoUrl,
) {
  final meta = given ?? const ChorkiMediaMetadata();
  return meta.copyWith(
    contentId:
        meta.contentId ?? (data != null && data.id != 0 ? '${data.id}' : null),
    mediaUrl: meta.mediaUrl ?? data?.url ?? videoUrl,
  );
}

/// The ad campaign of [data] as analytics ad context.
Map<String, Object?> adContextOf(ByteDataEntity? data) {
  final campaign = data?.adCampaign;
  if (campaign == null) return const {};
  return {
    if (campaign.id.isNotEmpty) ChorkiAnalyticsKeys.adCampaignId: campaign.id,
    if (campaign.title.isNotEmpty)
      ChorkiAnalyticsKeys.adCampaignTitle: campaign.title,
  };
}
