import 'dart:ui' show Size;

import '../chorki_analytics_event.dart';
import '../chorki_analytics_schema.dart';
import 'matomo_config.dart';
import 'matomo_naming.dart';

typedef _K = ChorkiAnalyticsKeys;

/// Turns [ChorkiAnalyticsEvent]s into Matomo Tracking API parameter maps.
///
/// Pure (no I/O), so the exact requests can be unit tested. The visitor id
/// (`_id`) is added at send time by [MatomoAnalyticsSink].
class MatomoRequestBuilder {
  /// Builds requests for [config].
  const MatomoRequestBuilder(this.config);

  /// Site, dimensions and naming.
  final MatomoConfig config;

  /// The Matomo requests for [event]: none, one or two (a media request and
  /// an event request).
  List<Map<String, String>> build(
    ChorkiAnalyticsEvent event, {
    String? userId,
    Map<String, String> userProperties = const {},
    String? resolution,
    String? language,
    Size? viewport,
  }) {
    final requests = <Map<String, String>>[];
    final base = _base(
      event,
      userId: userId,
      userProperties: userProperties,
      resolution: resolution,
      language: language,
    );

    final type = event.type;
    final isMedia =
        type == ChorkiAnalyticsEventType.impression ||
        type == ChorkiAnalyticsEventType.heartbeat;

    if (config.mediaAnalytics && isMedia) {
      requests.add({...base, ..._media(event, viewport)});
    }
    if (config.eventTracking && !config.excludedEvents.contains(type)) {
      // With Media Analytics on, impressions are already media requests.
      final duplicate =
          config.mediaAnalytics && type == ChorkiAnalyticsEventType.impression;
      if (!duplicate) requests.add({...base, ..._event(event)});
    }
    return requests;
  }

  Map<String, String> _base(
    ChorkiAnalyticsEvent event, {
    String? userId,
    required Map<String, String> userProperties,
    String? resolution,
    String? language,
  }) {
    final meta = event.metadata.toMap();
    final contentId = meta['contentId'] ?? event.sessionId;
    final values = <String, String>{
      ...meta,
      ...userProperties,
      'sessionId': event.sessionId,
      'playerName': config.playerName,
      'eventType': event.type.name,
      if (event.data[_K.adCampaignId] case final Object id)
        _K.adCampaignId: '$id',
      if (event.data[_K.adCampaignTitle] case final Object t)
        _K.adCampaignTitle: '$t',
      if (event.videoSize.height > 0)
        'qualityHeight': '${event.videoSize.height.round()}',
    };
    return {
      'idsite': '${config.siteId}',
      'rec': '1',
      'apiv': '1',
      // Not a page view: never counted as one, even if a plugin is missing.
      'ca': '1',
      'url':
          meta['pageUrl'] ??
          '${config.appUrl}/video/${Uri.encodeComponent(contentId)}',
      'urlref': ?meta['referrerUrl'],
      'cdt': '${event.timestamp.toUtc().millisecondsSinceEpoch ~/ 1000}',
      if (userId != null && userId.isNotEmpty) 'uid': userId,
      'ua': ?config.userAgent,
      'res': ?resolution,
      'lang': ?language,
      for (final entry in config.dimensionIds.entries)
        if (values[entry.key] case final String v when v.isNotEmpty)
          'dimension${entry.value}': _clip(v, 255),
    };
  }

  Map<String, String> _media(ChorkiAnalyticsEvent event, Size? viewport) {
    final meta = event.metadata;
    final title = meta.title ?? meta.contentId ?? '';
    final segments = event.data[_K.newSegments];
    final size =
        config.mediaSize == MatomoMediaSize.viewport && viewport != null
        ? viewport
        : event.videoSize;
    final w = size.width.round();
    final h = size.height.round();
    final impression = event.type == ChorkiAnalyticsEventType.impression;
    return {
      'ma_id': event.sessionId,
      if (title.isNotEmpty) 'ma_ti': _clip(title, 255),
      'ma_re': meta.mediaUrl ?? '',
      'ma_mt': 'video',
      'ma_pn': config.playerName,
      // An impression has not been played yet (except a loop's impression,
      // which starts at zero too).
      'ma_st': impression ? '0' : '${event.watchedTime.inSeconds}',
      'ma_ps': '${event.position.inSeconds}',
      if (event.duration > Duration.zero)
        'ma_le': '${event.duration.inSeconds}',
      if (!impression && event.timeToPlay != null)
        'ma_ttp': '${event.timeToPlay!.inSeconds}',
      if (w > 0) 'ma_w': '$w',
      if (h > 0) 'ma_h': '$h',
      if (config.fullscreen != null) 'ma_fs': config.fullscreen! ? '1' : '0',
      if (segments is List && segments.isNotEmpty) 'ma_se': segments.join(','),
    };
  }

  Map<String, String> _event(ChorkiAnalyticsEvent event) {
    final (category, action, name, value) = describe(event, config.naming);
    return {
      'e_c': category,
      'e_a': action,
      if (name.isNotEmpty) 'e_n': _clip(name, 255),
      if (value != null) 'e_v': _number(value),
    };
  }

  /// Category, action, name and value of the Matomo Event for [event].
  static (String, String, String, num?) describe(
    ChorkiAnalyticsEvent event, [
    MatomoNaming naming = MatomoNaming.standard,
  ]) {
    final (action, name, value) = _describe(event);
    return (
      naming.categoryOf(event.category),
      naming.actions[event.type] ?? action,
      name,
      naming.positionValue.contains(event.type)
          ? event.position.inSeconds
          : value,
    );
  }

  static (String, String, num?) _describe(ChorkiAnalyticsEvent event) {
    final d = event.data;
    final meta = event.metadata;
    final title = meta.title ?? meta.contentId ?? meta.mediaUrl ?? '';
    // Values are read defensively: a custom sink chain may hand in anything.
    num? n(String key) => switch (d[key]) {
      final num v => v,
      final String v => num.tryParse(v),
      _ => null,
    };
    num? secs(String key) => n(key) == null ? null : n(key)! / 1000;
    String s(String key) => '${d[key] ?? ''}';
    String ad() => '${d[_K.adTitle] ?? d[_K.adId] ?? ''}';
    String campaign() =>
        '${d[_K.adCampaignTitle] ?? d[_K.adCampaignId] ?? title}';

    final (String action, String name, num? value) = switch (event.type) {
      ChorkiAnalyticsEventType.impression => ('impression', title, null),
      ChorkiAnalyticsEventType.play => ('play', title, secs(_K.timeToPlayMs)),
      ChorkiAnalyticsEventType.pause => (
        'pause',
        title,
        event.position.inSeconds,
      ),
      ChorkiAnalyticsEventType.resume => ('resume', title, null),
      ChorkiAnalyticsEventType.seek => (
        'seek (${s(_K.source)})',
        title,
        ((n(_K.toMs) ?? 0) - (n(_K.fromMs) ?? 0)) / 1000,
      ),
      ChorkiAnalyticsEventType.heartbeat => (
        'heartbeat',
        title,
        event.watchedTime.inSeconds,
      ),
      ChorkiAnalyticsEventType.quartile => (
        'progress ${s(_K.percent)}%',
        title,
        n(_K.percent),
      ),
      ChorkiAnalyticsEventType.complete => ('complete', title, null),
      ChorkiAnalyticsEventType.loop => ('loop', title, n(_K.loopCount)),
      ChorkiAnalyticsEventType.sessionEnd => (
        'session end (${s(_K.reason)})',
        title,
        event.watchedTime.inSeconds,
      ),
      ChorkiAnalyticsEventType.loadStart => ('load start', title, null),
      ChorkiAnalyticsEventType.firstFrame => (
        'startup time',
        title,
        secs(_K.startupMs),
      ),
      ChorkiAnalyticsEventType.bufferStart => ('rebuffer start', title, null),
      ChorkiAnalyticsEventType.bufferEnd => (
        'rebuffer',
        title,
        secs(_K.durationMs),
      ),
      ChorkiAnalyticsEventType.error => (
        'error (${s(_K.stage)})',
        s(_K.code),
        null,
      ),
      ChorkiAnalyticsEventType.retry => (
        d[_K.auto] == true ? 'auto retry' : 'manual retry',
        title,
        n(_K.attempt),
      ),
      ChorkiAnalyticsEventType.qualityChange => (
        'quality ${d[_K.toHeight] == null ? 'auto' : '${d[_K.toHeight]}p'}',
        title,
        n(_K.toHeight),
      ),
      ChorkiAnalyticsEventType.abandon => (
        'exit before start (${s(_K.abandonStage)})',
        title,
        secs(_K.waitedMs),
      ),
      ChorkiAnalyticsEventType.adBreakStart => (
        'break start (${s(_K.breakKind)})',
        campaign(),
        n(_K.breakIndex),
      ),
      ChorkiAnalyticsEventType.adBreakEnd => (
        'break end',
        campaign(),
        secs(_K.durationMs),
      ),
      ChorkiAnalyticsEventType.adStart => (
        'ad start',
        ad(),
        secs(_K.adDurationMs),
      ),
      ChorkiAnalyticsEventType.adQuartile => (
        'ad ${s(_K.percent)}%',
        ad(),
        n(_K.percent),
      ),
      ChorkiAnalyticsEventType.adComplete => ('ad complete', ad(), null),
      ChorkiAnalyticsEventType.adSkip => ('ad skip', ad(), null),
      ChorkiAnalyticsEventType.adClick => ('ad click', ad(), null),
      ChorkiAnalyticsEventType.adPause => ('ad pause', '', null),
      ChorkiAnalyticsEventType.adResume => ('ad resume', '', null),
      ChorkiAnalyticsEventType.adError => ('ad error', s(_K.message), null),
      ChorkiAnalyticsEventType.speedChange => (
        'speed ${s(_K.to)}x',
        title,
        n(_K.to),
      ),
      ChorkiAnalyticsEventType.speedBoostStart => (
        'speed boost',
        title,
        n(_K.speed),
      ),
      ChorkiAnalyticsEventType.speedBoostEnd => (
        'speed boost end',
        title,
        secs(_K.durationMs),
      ),
      ChorkiAnalyticsEventType.audioTrackChange => (
        'audio track',
        s(_K.toTrack),
        null,
      ),
      ChorkiAnalyticsEventType.fitChange => ('fit ${s(_K.fit)}', title, null),
      ChorkiAnalyticsEventType.pipChange => (
        'pip ${s(_K.status)}',
        title,
        null,
      ),
      ChorkiAnalyticsEventType.volumeChange => (
        d[_K.muted] == true ? 'mute' : 'volume',
        title,
        n(_K.to),
      ),
      ChorkiAnalyticsEventType.settingsOpen => ('settings open', title, null),
    };
    return (action, name, value);
  }

  static String _number(num v) {
    if (v is int || v == v.roundToDouble()) return '${v.round()}';
    return v.toStringAsFixed(3);
  }

  static String _clip(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);
}
