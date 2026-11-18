import '../chorki_analytics_event.dart';
import 'dart:ui' show Size;

import 'matomo_config.dart';
import 'matomo_naming.dart';

/// Turns [ChorkiAnalyticsEvent]s into Matomo Tracking API parameter maps.
///
/// Pure (no I/O), so the exact requests can be unit tested. The visitor id
/// (`_id`) is added at send time by [MatomoAnalyticsSink].
class MatomoRequestBuilder {
  const MatomoRequestBuilder(this.config);

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
      if (event.data['adCampaignId'] case final Object id)
        'adCampaignId': '$id',
      if (event.data['adCampaignTitle'] case final Object t)
        'adCampaignTitle': '$t',
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
    final segments = event.data['newSegments'];
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
    num? ms(String key) => d[key] is num ? d[key] as num : null;
    num? secs(String key) => ms(key) == null ? null : ms(key)! / 1000;

    final (String action, String name, num? value) = switch (event.type) {
      ChorkiAnalyticsEventType.impression => ('impression', title, null),
      ChorkiAnalyticsEventType.play => ('play', title, secs('timeToPlayMs')),
      ChorkiAnalyticsEventType.pause => (
        'pause',
        title,
        event.position.inSeconds,
      ),
      ChorkiAnalyticsEventType.resume => ('resume', title, null),
      ChorkiAnalyticsEventType.seek => (
        'seek (${d['source']})',
        title,
        ((ms('toMs') ?? 0) - (ms('fromMs') ?? 0)) / 1000,
      ),
      ChorkiAnalyticsEventType.heartbeat => (
        'heartbeat',
        title,
        event.watchedTime.inSeconds,
      ),
      ChorkiAnalyticsEventType.quartile => (
        'progress ${d['percent']}%',
        title,
        d['percent'] as num?,
      ),
      ChorkiAnalyticsEventType.complete => ('complete', title, null),
      ChorkiAnalyticsEventType.loop => ('loop', title, ms('loopCount')),
      ChorkiAnalyticsEventType.sessionEnd => (
        'session end (${d['reason']})',
        title,
        event.watchedTime.inSeconds,
      ),
      ChorkiAnalyticsEventType.loadStart => ('load start', title, null),
      ChorkiAnalyticsEventType.firstFrame => (
        'startup time',
        title,
        secs('startupMs'),
      ),
      ChorkiAnalyticsEventType.bufferStart => ('rebuffer start', title, null),
      ChorkiAnalyticsEventType.bufferEnd => (
        'rebuffer',
        title,
        secs('durationMs'),
      ),
      ChorkiAnalyticsEventType.error => (
        'error (${d['stage']})',
        '${d['message'] ?? ''}',
        null,
      ),
      ChorkiAnalyticsEventType.retry => (
        d['auto'] == true ? 'auto retry' : 'manual retry',
        title,
        ms('attempt'),
      ),
      ChorkiAnalyticsEventType.qualityChange => (
        'quality ${d['toHeight'] == null ? 'auto' : '${d['toHeight']}p'}',
        title,
        ms('toHeight'),
      ),
      ChorkiAnalyticsEventType.abandon => (
        'exit before start (${d['stage']})',
        title,
        secs('waitedMs'),
      ),
      ChorkiAnalyticsEventType.adBreakStart => (
        'break start (${d['breakKind']})',
        '${d['adCampaignTitle'] ?? d['adCampaignId'] ?? title}',
        ms('breakIndex'),
      ),
      ChorkiAnalyticsEventType.adBreakEnd => (
        'break end',
        '${d['adCampaignTitle'] ?? d['adCampaignId'] ?? title}',
        secs('durationMs'),
      ),
      ChorkiAnalyticsEventType.adStart => (
        'ad start',
        '${d['adTitle'] ?? d['adId'] ?? ''}',
        secs('adDurationMs'),
      ),
      ChorkiAnalyticsEventType.adQuartile => (
        'ad ${d['percent']}%',
        '${d['adTitle'] ?? d['adId'] ?? ''}',
        d['percent'] as num?,
      ),
      ChorkiAnalyticsEventType.adComplete => (
        'ad complete',
        '${d['adTitle'] ?? d['adId'] ?? ''}',
        null,
      ),
      ChorkiAnalyticsEventType.adSkip => (
        'ad skip',
        '${d['adTitle'] ?? d['adId'] ?? ''}',
        null,
      ),
      ChorkiAnalyticsEventType.adClick => (
        'ad click',
        '${d['adTitle'] ?? d['adId'] ?? ''}',
        null,
      ),
      ChorkiAnalyticsEventType.adPause => ('ad pause', '', null),
      ChorkiAnalyticsEventType.adResume => ('ad resume', '', null),
      ChorkiAnalyticsEventType.adError => (
        'ad error',
        '${d['message'] ?? ''}',
        null,
      ),
      ChorkiAnalyticsEventType.speedChange => (
        'speed ${d['to']}x',
        title,
        d['to'] as num?,
      ),
      ChorkiAnalyticsEventType.speedBoostStart => (
        'speed boost',
        title,
        d['speed'] as num?,
      ),
      ChorkiAnalyticsEventType.speedBoostEnd => (
        'speed boost end',
        title,
        secs('durationMs'),
      ),
      ChorkiAnalyticsEventType.audioTrackChange => (
        'audio track',
        '${d['to']}',
        null,
      ),
      ChorkiAnalyticsEventType.fitChange => ('fit ${d['fit']}', title, null),
      ChorkiAnalyticsEventType.pipChange => ('pip ${d['status']}', title, null),
      ChorkiAnalyticsEventType.volumeChange => (
        d['muted'] == true ? 'mute' : 'volume',
        title,
        d['to'] as num?,
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
