import 'chorki_analytics_event.dart';

typedef _K = ChorkiAnalyticsKeys;

/// The keys of [ChorkiAnalyticsEvent.data]. Use these instead of string
/// literals when reading events in a sink.
abstract final class ChorkiAnalyticsKeys {
  // Playback.
  /// Milliseconds from the impression to the first played frame.
  static const timeToPlayMs = 'timeToPlayMs';

  /// Loops played so far in this view.
  static const loopCount = 'loopCount';

  /// Seek start, in milliseconds.
  static const fromMs = 'fromMs';

  /// Seek target, in milliseconds.
  static const toMs = 'toMs';

  /// A [ChorkiSeekSource] name.
  static const source = 'source';

  /// What caused a heartbeat: `interval`, `pause`, `seek`, `complete`,
  /// `end`, `ad` or `background`.
  static const trigger = 'trigger';

  /// Segment end offsets in seconds watched since the last heartbeat.
  static const newSegments = 'newSegments';

  /// 25, 50, 75 or 100.
  static const percent = 'percent';

  /// A [ChorkiSessionEndReason] name.
  static const reason = 'reason';

  /// Milliseconds from the impression to the end of the view.
  static const dwellMs = 'dwellMs';

  /// Share of the duration actually played, 0..100.
  static const watchedPercent = 'watchedPercent';

  /// Furthest position reached, in milliseconds.
  static const maxPositionMs = 'maxPositionMs';

  /// Stalls after the first frame.
  static const rebufferCount = 'rebufferCount';

  /// Total stall time, in milliseconds.
  static const rebufferMs = 'rebufferMs';

  /// Viewer pauses.
  static const pauseCount = 'pauseCount';

  /// Seeks.
  static const seekCount = 'seekCount';

  /// Errors during the view.
  static const errorCount = 'errorCount';

  // QoE.
  /// Milliseconds from activation (or load start) to the first frame.
  static const startupMs = 'startupMs';

  /// Milliseconds the load waited for a free slot.
  static const queueWaitMs = 'queueWaitMs';

  /// Milliseconds the video took to initialize.
  static const initMs = 'initMs';

  /// The video was loaded before the item became active.
  static const preloaded = 'preloaded';

  /// The stall started within 1.5 s of a seek.
  static const afterSeek = 'afterSeek';

  /// A duration in milliseconds (stall, boost, ad break).
  static const durationMs = 'durationMs';

  /// A [ChorkiErrorCode] name.
  static const code = 'code';

  /// A [ChorkiErrorStage] name: `route`, `load` or `playback`.
  static const stage = 'stage';

  /// Whether retrying may help.
  static const transient = 'transient';

  /// A silent retry follows.
  static const willRetry = 'willRetry';

  /// HTTP status of a route error.
  static const statusCode = 'statusCode';

  /// Developer-facing error detail.
  static const detail = 'detail';

  /// Retry attempt, from 1.
  static const attempt = 'attempt';

  /// The retry was not the viewer's.
  static const auto = 'auto';

  /// Rendition height before a quality change (null: Auto).
  static const fromHeight = 'fromHeight';

  /// Rendition height after a quality change (null: Auto).
  static const toHeight = 'toHeight';

  /// Bitrate of the chosen rendition.
  static const bitrate = 'bitrate';

  /// Label of the chosen rendition.
  static const label = 'label';

  /// Milliseconds the viewer waited before leaving.
  static const waitedMs = 'waitedMs';

  /// Where an abandoned view was: `loading` (never loaded) or `ready`
  /// (loaded but never played).
  static const abandonStage = 'abandonStage';

  // Ads.
  /// Index of the ad break in this view, from 0.
  static const breakIndex = 'breakIndex';

  /// `preRoll`, `midRoll` or `postRoll`.
  static const breakKind = 'breakKind';

  /// The break was cut off by the end of the view.
  static const interrupted = 'interrupted';

  /// Ad campaign id from the byte route.
  static const adCampaignId = 'adCampaignId';

  /// Ad campaign title from the byte route.
  static const adCampaignTitle = 'adCampaignTitle';

  /// IMA ad id.
  static const adId = 'adId';

  /// IMA ad title.
  static const adTitle = 'adTitle';

  /// IMA ad system.
  static const adSystem = 'adSystem';

  /// IMA advertiser name.
  static const advertiser = 'advertiser';

  /// Ad duration, in milliseconds.
  static const adDurationMs = 'adDurationMs';

  /// The ad can be skipped.
  static const skippable = 'skippable';

  /// Position of the ad in its pod, from 1.
  static const podPosition = 'podPosition';

  /// Ads in the pod.
  static const podTotal = 'podTotal';

  /// Ad error message.
  static const message = 'message';

  // UX.
  /// Value before a change (speed, volume).
  static const from = 'from';

  /// Value after a change (speed, volume).
  static const to = 'to';

  /// Boost speed.
  static const speed = 'speed';

  /// Audio track id before the change.
  static const fromTrack = 'fromTrack';

  /// Audio track id after the change.
  static const toTrack = 'toTrack';

  /// `fit` or `fill`.
  static const fit = 'fit';

  /// A [ChorkiPipStatus] name.
  static const status = 'status';

  /// Volume is zero.
  static const muted = 'muted';
}

/// The type of a value in [ChorkiAnalyticsEvent.data].
enum ChorkiAnalyticsValueType {
  /// An `int`.
  integer,

  /// A `num`.
  number,

  /// A `bool`.
  boolean,

  /// A `String`.
  string,

  /// A `List<int>`.
  integerList;

  /// Whether [value] has this type.
  bool accepts(Object? value) => switch (this) {
    integer => value is int,
    number => value is num,
    boolean => value is bool,
    string => value is String,
    integerList => value is List<int>,
  };
}

/// One key an event carries.
class ChorkiAnalyticsField {
  /// A field; [required] ones are always present.
  const ChorkiAnalyticsField(this.key, this.type, {this.required = true});

  /// An optional field.
  const ChorkiAnalyticsField.optional(this.key, this.type) : required = false;

  /// The [ChorkiAnalyticsEvent.data] key.
  final String key;

  /// Its value type.
  final ChorkiAnalyticsValueType type;

  /// Always present (otherwise only when known).
  final bool required;
}

/// What [ChorkiAnalyticsEvent.data] holds for each event type: the single
/// source of truth that the player, the Matomo sink, the enum docs and the
/// README table are checked against.
abstract final class ChorkiAnalyticsSchema {
  static const _int = ChorkiAnalyticsValueType.integer;
  static const _num = ChorkiAnalyticsValueType.number;
  static const _bool = ChorkiAnalyticsValueType.boolean;
  static const _str = ChorkiAnalyticsValueType.string;
  static const _ints = ChorkiAnalyticsValueType.integerList;

  /// Fields every ad event carries, besides its own.
  static const List<ChorkiAnalyticsField> adCommon = [
    ChorkiAnalyticsField(_K.breakIndex, _int),
    ChorkiAnalyticsField.optional(_K.adCampaignId, _str),
    ChorkiAnalyticsField.optional(_K.adCampaignTitle, _str),
  ];

  /// IMA details of the current ad, when the SDK provides them.
  static const List<ChorkiAnalyticsField> adDetails = [
    ChorkiAnalyticsField.optional(_K.adId, _str),
    ChorkiAnalyticsField.optional(_K.adTitle, _str),
    ChorkiAnalyticsField.optional(_K.adSystem, _str),
    ChorkiAnalyticsField.optional(_K.advertiser, _str),
    ChorkiAnalyticsField.optional(_K.adDurationMs, _int),
    ChorkiAnalyticsField.optional(_K.skippable, _bool),
    ChorkiAnalyticsField.optional(_K.podPosition, _int),
    ChorkiAnalyticsField.optional(_K.podTotal, _int),
  ];

  /// The fields of [type], excluding [adCommon] / [adDetails].
  static List<ChorkiAnalyticsField> own(ChorkiAnalyticsEventType type) =>
      switch (type) {
        ChorkiAnalyticsEventType.impression => const [
          ChorkiAnalyticsField.optional(_K.loopCount, _int),
        ],
        ChorkiAnalyticsEventType.play => const [
          ChorkiAnalyticsField(_K.timeToPlayMs, _int),
          ChorkiAnalyticsField.optional(_K.loopCount, _int),
        ],
        ChorkiAnalyticsEventType.pause ||
        ChorkiAnalyticsEventType.resume ||
        ChorkiAnalyticsEventType.complete ||
        ChorkiAnalyticsEventType.loadStart ||
        ChorkiAnalyticsEventType.settingsOpen => const [],
        ChorkiAnalyticsEventType.seek => const [
          ChorkiAnalyticsField(_K.fromMs, _int),
          ChorkiAnalyticsField(_K.toMs, _int),
          ChorkiAnalyticsField(_K.source, _str),
        ],
        ChorkiAnalyticsEventType.heartbeat => const [
          ChorkiAnalyticsField(_K.trigger, _str),
          ChorkiAnalyticsField(_K.newSegments, _ints),
        ],
        ChorkiAnalyticsEventType.quartile => const [
          ChorkiAnalyticsField(_K.percent, _int),
        ],
        ChorkiAnalyticsEventType.loop => const [
          ChorkiAnalyticsField(_K.loopCount, _int),
        ],
        ChorkiAnalyticsEventType.sessionEnd => const [
          ChorkiAnalyticsField(_K.reason, _str),
          ChorkiAnalyticsField(_K.dwellMs, _int),
          ChorkiAnalyticsField(_K.watchedPercent, _int),
          ChorkiAnalyticsField(_K.maxPositionMs, _int),
          ChorkiAnalyticsField(_K.rebufferCount, _int),
          ChorkiAnalyticsField(_K.rebufferMs, _int),
          ChorkiAnalyticsField(_K.pauseCount, _int),
          ChorkiAnalyticsField(_K.seekCount, _int),
          ChorkiAnalyticsField(_K.loopCount, _int),
          ChorkiAnalyticsField(_K.errorCount, _int),
        ],
        ChorkiAnalyticsEventType.firstFrame => const [
          ChorkiAnalyticsField(_K.startupMs, _int),
          ChorkiAnalyticsField.optional(_K.queueWaitMs, _int),
          ChorkiAnalyticsField.optional(_K.initMs, _int),
          ChorkiAnalyticsField(_K.preloaded, _bool),
        ],
        ChorkiAnalyticsEventType.bufferStart => const [
          ChorkiAnalyticsField(_K.afterSeek, _bool),
        ],
        ChorkiAnalyticsEventType.bufferEnd ||
        ChorkiAnalyticsEventType.speedBoostEnd => const [
          ChorkiAnalyticsField(_K.durationMs, _int),
        ],
        ChorkiAnalyticsEventType.error => const [
          ChorkiAnalyticsField(_K.code, _str),
          ChorkiAnalyticsField(_K.stage, _str),
          ChorkiAnalyticsField(_K.transient, _bool),
          ChorkiAnalyticsField(_K.willRetry, _bool),
          ChorkiAnalyticsField.optional(_K.statusCode, _int),
          ChorkiAnalyticsField.optional(_K.detail, _str),
        ],
        ChorkiAnalyticsEventType.retry => const [
          ChorkiAnalyticsField(_K.attempt, _int),
          ChorkiAnalyticsField(_K.auto, _bool),
        ],
        ChorkiAnalyticsEventType.qualityChange => const [
          ChorkiAnalyticsField.optional(_K.fromHeight, _int),
          ChorkiAnalyticsField.optional(_K.toHeight, _int),
          ChorkiAnalyticsField.optional(_K.bitrate, _int),
          ChorkiAnalyticsField.optional(_K.label, _str),
          ChorkiAnalyticsField(_K.auto, _bool),
        ],
        ChorkiAnalyticsEventType.abandon => const [
          ChorkiAnalyticsField(_K.waitedMs, _int),
          ChorkiAnalyticsField(_K.reason, _str),
          ChorkiAnalyticsField(_K.abandonStage, _str),
          ChorkiAnalyticsField(_K.errorCount, _int),
        ],
        ChorkiAnalyticsEventType.adBreakStart => const [
          ChorkiAnalyticsField(_K.breakKind, _str),
        ],
        ChorkiAnalyticsEventType.adBreakEnd => const [
          ChorkiAnalyticsField(_K.durationMs, _int),
          ChorkiAnalyticsField.optional(_K.interrupted, _bool),
        ],
        ChorkiAnalyticsEventType.adQuartile => const [
          ChorkiAnalyticsField(_K.percent, _int),
        ],
        ChorkiAnalyticsEventType.adError => const [
          ChorkiAnalyticsField(_K.message, _str),
        ],
        ChorkiAnalyticsEventType.adStart ||
        ChorkiAnalyticsEventType.adComplete ||
        ChorkiAnalyticsEventType.adSkip ||
        ChorkiAnalyticsEventType.adClick ||
        ChorkiAnalyticsEventType.adPause ||
        ChorkiAnalyticsEventType.adResume => const [],
        ChorkiAnalyticsEventType.speedChange => const [
          ChorkiAnalyticsField(_K.from, _num),
          ChorkiAnalyticsField(_K.to, _num),
        ],
        ChorkiAnalyticsEventType.speedBoostStart => const [
          ChorkiAnalyticsField(_K.speed, _num),
        ],
        ChorkiAnalyticsEventType.audioTrackChange => const [
          ChorkiAnalyticsField.optional(_K.fromTrack, _str),
          ChorkiAnalyticsField(_K.toTrack, _str),
        ],
        ChorkiAnalyticsEventType.fitChange => const [
          ChorkiAnalyticsField(_K.fit, _str),
        ],
        ChorkiAnalyticsEventType.pipChange => const [
          ChorkiAnalyticsField(_K.status, _str),
        ],
        ChorkiAnalyticsEventType.volumeChange => const [
          ChorkiAnalyticsField(_K.from, _num),
          ChorkiAnalyticsField(_K.to, _num),
          ChorkiAnalyticsField(_K.muted, _bool),
        ],
      };

  /// Every field [type] may carry.
  static List<ChorkiAnalyticsField> of(ChorkiAnalyticsEventType type) => [
    ...own(type),
    if (type.category == ChorkiAnalyticsCategory.ad) ...adCommon,
    if (type.category == ChorkiAnalyticsCategory.ad &&
        type != ChorkiAnalyticsEventType.adBreakStart &&
        type != ChorkiAnalyticsEventType.adBreakEnd)
      ...adDetails,
  ];

  /// Problems with [data] for [type]: unknown keys, missing required keys,
  /// values of the wrong type. Empty when it conforms. The player checks
  /// every event against this in debug builds.
  static List<String> validate(
    ChorkiAnalyticsEventType type,
    Map<String, Object?> data,
  ) {
    final fields = {for (final f in of(type)) f.key: f};
    return [
      for (final key in data.keys)
        if (!fields.containsKey(key)) '${type.name}: unknown key "$key"',
      for (final f in fields.values)
        if (f.required && data[f.key] == null)
          '${type.name}: missing "${f.key}"'
        else if (data[f.key] != null && !f.type.accepts(data[f.key]))
          '${type.name}: "${f.key}" should be ${f.type.name}, '
              'got ${data[f.key].runtimeType}',
    ];
  }
}
