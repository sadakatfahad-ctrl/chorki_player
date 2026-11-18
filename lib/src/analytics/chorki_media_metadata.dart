import 'package:flutter/foundation.dart';

/// Describes the content a [ChorkiPlayer] plays, for analytics.
///
/// Pass it as `ChorkiPlayer(metadata: ...)`. Every analytics event carries it,
/// and the Matomo sink maps its fields to custom dimensions
/// ([MatomoConfig.dimensionIds]) and to the Media Analytics title / URL.
///
/// When it is not given, the player falls back to the resolved byte (its id
/// and video URL), which gives far less useful reports.
@immutable
class ChorkiMediaMetadata {
  /// Describes the content; every field is optional.
  const ChorkiMediaMetadata({
    this.contentId,
    this.title,
    this.mediaUrl,
    this.seriesId,
    this.seriesTitle,
    this.seasonNumber,
    this.episodeNumber,
    this.category,
    this.contentType,
    this.feedIndex,
    this.pageUrl,
    this.referrerUrl,
    this.extra = const {},
  });

  /// Stable id of the content in your catalog (not the stream URL).
  final String? contentId;

  /// Human readable title, e.g. the episode or byte name.
  final String? title;

  /// URL reported as the media resource. Defaults to the played video URL.
  final String? mediaUrl;

  /// Id of the series or show it belongs to.
  final String? seriesId;

  /// Name of the series or show.
  final String? seriesTitle;

  /// Season number within the series.
  final int? seasonNumber;

  /// Episode number within the season.
  final int? episodeNumber;

  /// Genre / shelf / section, e.g. `drama`, `bytes`.
  final String? category;

  /// e.g. `episode`, `movie`, `trailer`, `byte`.
  final String? contentType;

  /// Position of the item in a feed, when it is shown in one.
  final int? feedIndex;

  /// The app page this view belongs to, sent as Matomo `url` (e.g. the
  /// content's route on your website: `https://www.chorki.com/bytes/abc`).
  /// Prefer an absolute URL. Defaults to `<MatomoConfig.appUrl>/video/<contentId>`.
  final String? pageUrl;

  /// Where the viewer came from, sent as Matomo `urlref`.
  final String? referrerUrl;

  /// Anything else you want to report, keyed by your own names. Keys can be
  /// mapped to Matomo custom dimensions just like the named fields.
  final Map<String, String> extra;

  /// All non-null fields as strings, keyed by their field names (and the
  /// [extra] keys). This is what dimension mapping reads.
  Map<String, String> toMap() => {
    'contentId': ?contentId,
    'title': ?title,
    'mediaUrl': ?mediaUrl,
    'seriesId': ?seriesId,
    'seriesTitle': ?seriesTitle,
    if (seasonNumber != null) 'seasonNumber': '$seasonNumber',
    if (episodeNumber != null) 'episodeNumber': '$episodeNumber',
    'category': ?category,
    'contentType': ?contentType,
    if (feedIndex != null) 'feedIndex': '$feedIndex',
    'pageUrl': ?pageUrl,
    'referrerUrl': ?referrerUrl,
    ...extra,
  };

  /// A copy with the given fields replaced.
  ChorkiMediaMetadata copyWith({
    String? contentId,
    String? title,
    String? mediaUrl,
  }) => ChorkiMediaMetadata(
    contentId: contentId ?? this.contentId,
    title: title ?? this.title,
    mediaUrl: mediaUrl ?? this.mediaUrl,
    seriesId: seriesId,
    seriesTitle: seriesTitle,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    category: category,
    contentType: contentType,
    feedIndex: feedIndex,
    pageUrl: pageUrl,
    referrerUrl: referrerUrl,
    extra: extra,
  );

  @override
  bool operator ==(Object other) =>
      other is ChorkiMediaMetadata && mapEquals(toMap(), other.toMap());

  @override
  int get hashCode => Object.hashAllUnordered(
    toMap().entries.map((e) => Object.hash(e.key, e.value)),
  );

  @override
  String toString() => 'ChorkiMediaMetadata(${toMap()})';
}
