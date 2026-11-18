import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../analytics/chorki_analytics_config.dart';
import '../analytics/chorki_analytics_event.dart';
import '../analytics/chorki_analytics_session.dart';
import '../core/diagnostics.dart';
import '../core/guard.dart';
import '../pip/chorki_pip.dart';

/// How the video fills the player box.
enum ChorkiVideoFit {
  /// Letterbox: the whole frame is visible.
  fit,

  /// Crop: the frame covers the whole box.
  fill,
}

/// Public handle for a [ChorkiPlayer] (or a [ChorkiPlayerSurface] in a feed).
///
/// Create it in your widget's state, pass it to the player, and dispose it
/// yourself. All listenables survive video reloads; tracks are refreshed for
/// every new video.
class ChorkiPlayerController {
  /// A controller starting at [initialSpeed] and [initialFit]. [pipDelegate]
  /// defaults to the `floating` plugin; [analytics] applies to players that
  /// have none of their own.
  ChorkiPlayerController({
    double initialSpeed = 1.0,
    ChorkiVideoFit initialFit = ChorkiVideoFit.fit,
    this.seekStep = const Duration(seconds: 10),
    ChorkiPipDelegate? pipDelegate,
    this.analytics,
  }) : _speed = ValueNotifier(initialSpeed),
       _fit = ValueNotifier(initialFit),
       _pip = pipDelegate ?? ChorkiFloatingPipDelegate();

  /// Step used by [seekForward] / [seekBack].
  final Duration seekStep;

  /// Analytics for every [ChorkiPlayer] driven by this controller that has
  /// no `analytics` of its own, e.g. one config for a whole feed.
  final ChorkiAnalyticsConfig? analytics;

  /// Session of the attached player; settings and API actions report to it.
  ChorkiAnalyticsSession? _session;

  final ChorkiPipDelegate _pip;

  final ValueNotifier<VideoPlayerController?> _video = ValueNotifier(null);
  final ValueNotifier<VideoPlayerValue> _value = ValueNotifier(
    const VideoPlayerValue.uninitialized(),
  );
  final ValueNotifier<List<VideoTrack>> _videoTracks = ValueNotifier(const []);
  final ValueNotifier<VideoTrack?> _selectedVideoTrack = ValueNotifier(null);
  final ValueNotifier<List<VideoAudioTrack>> _audioTracks = ValueNotifier(
    const [],
  );
  final ValueNotifier<String?> _selectedAudioTrackId = ValueNotifier(null);
  final ValueNotifier<double> _speed;
  final ValueNotifier<ChorkiVideoFit> _fit;
  final ValueNotifier<ChorkiPipStatus> _pipStatus = ValueNotifier(
    ChorkiPipStatus.unavailable,
  );
  final ValueNotifier<bool> _isAdPlaying = ValueNotifier(false);

  VoidCallback? _onRetry;
  AppLifecycleListener? _lifecycle;
  bool _autoPip = false;
  bool _tracksLoadedFor = false;
  bool _disposed = false;
  int _attachGen = 0;

  /// The attached `video_player` controller, or null while loading.
  ValueListenable<VideoPlayerController?> get videoController => _video;

  /// Mirror of the attached controller's value (position, duration, buffer,
  /// playing, error…). Resets to uninitialized while detached.
  ValueListenable<VideoPlayerValue> get value => _value;

  /// Available qualities (HLS/DASH renditions). Empty if unsupported.
  ValueListenable<List<VideoTrack>> get videoTracks => _videoTracks;

  /// The quality picked by the user; null means Auto (adaptive).
  ValueListenable<VideoTrack?> get selectedVideoTrack => _selectedVideoTrack;

  /// Available audio tracks (languages). Empty if unsupported.
  ValueListenable<List<VideoAudioTrack>> get audioTracks => _audioTracks;

  /// Id of the playing audio track, if known.
  ValueListenable<String?> get selectedAudioTrackId => _selectedAudioTrackId;

  /// Playback speed chosen by the user (long-press boost is not reflected).
  ValueListenable<double> get speed => _speed;

  /// How the video fills the player.
  ValueListenable<ChorkiVideoFit> get fit => _fit;

  /// Picture-in-picture state, refreshed when the app resumes.
  ValueListenable<ChorkiPipStatus> get pipStatus => _pipStatus;

  /// True while an IMA ad has paused the attached video. Resets when a
  /// different video is attached or the video is detached.
  ValueListenable<bool> get isAdPlaying => _isAdPlaying;

  /// Whether a video is attached.
  bool get isAttached => _video.value != null;

  /// Whether the device supports picture-in-picture.
  bool get isPipAvailable => _pipStatus.value != ChorkiPipStatus.unavailable;

  /// Whether leaving the app enters picture-in-picture ([setAutoPip]).
  bool get isAutoPipEnabled => _autoPip;

  // ---------------------------------------------------------------------------
  // Wiring (called by ChorkiPlayer; call it yourself when using
  // ChorkiPlayerSurface directly).
  // ---------------------------------------------------------------------------

  /// Binds [controller]. Re-applies the chosen speed and refreshes tracks.
  /// [onRetry] backs [retry].
  ///
  /// [analytics] is the attached player's session: settings changes and
  /// commands sent through this controller are reported to it.
  void attach(
    VideoPlayerController controller, {
    VoidCallback? onRetry,
    ChorkiAnalyticsSession? analytics,
  }) {
    if (_disposed) return;
    if (identical(_video.value, controller)) {
      _onRetry = onRetry ?? _onRetry;
      _session = analytics ?? _session;
      return;
    }
    _detachListener();
    _attachGen++;
    _onRetry = onRetry;
    _session = analytics;
    _tracksLoadedFor = false;
    _videoTracks.value = const [];
    _selectedVideoTrack.value = null;
    _audioTracks.value = const [];
    _selectedAudioTrackId.value = null;
    _isAdPlaying.value = false;
    _video.value = controller;
    controller.addListener(_onVideoValue);
    _onVideoValue();
    _ensureLifecycle();
    unawaited(refreshPipStatus());
  }

  /// Unbinds [controller] if it is the attached one (or any, when null).
  void detach([VideoPlayerController? controller]) {
    if (controller != null && !identical(controller, _video.value)) return;
    _detachListener();
    _attachGen++;
    _onRetry = null;
    _session = null;
    _video.value = null;
    _value.value = const VideoPlayerValue.uninitialized();
    _videoTracks.value = const [];
    _selectedVideoTrack.value = null;
    _audioTracks.value = const [];
    _selectedAudioTrackId.value = null;
    _isAdPlaying.value = false;
  }

  /// Reported by the ad layer. Internal: only the player calls it.
  @internal
  void setAdPlaying(bool playing) {
    if (!_disposed) _isAdPlaying.value = playing;
  }

  void _detachListener() {
    _video.value?.removeListener(_onVideoValue);
  }

  void _onVideoValue() {
    final c = _video.value;
    if (c == null || _disposed) return;
    final v = c.value;
    _value.value = v;
    if (v.isInitialized && !_tracksLoadedFor) {
      _tracksLoadedFor = true;
      if (_speed.value != 1.0) {
        fireAndReport(
          () => c.setPlaybackSpeed(_speed.value),
          'controller.restoreSpeed',
        );
      }
      unawaited(refreshTracks());
      if (_autoPip) {
        fireAndReport(
          () => _pip.setAuto(true, _aspectRatio),
          'controller.setAutoPip',
        );
      }
    }
  }

  double get _aspectRatio {
    final v = _video.value?.value;
    if (v == null || !v.isInitialized) return 16 / 9;
    return v.aspectRatio;
  }

  // ---------------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------------

  /// Plays the attached video.
  Future<void> play() async => _withVideo((c) => c.play());

  /// Pauses the attached video.
  Future<void> pause() async => _withVideo((c) => c.pause());

  /// Pauses when playing, plays when paused.
  Future<void> togglePlayPause() async =>
      _withVideo((c) => c.value.isPlaying ? c.pause() : c.play());

  /// Jumps to [position] (reported as an API seek).
  Future<void> seekTo(Duration position) async =>
      _withVideo((c) => _seek(c, position));

  /// Jumps ahead by [step] (default [seekStep]).
  Future<void> seekForward([Duration? step]) async =>
      _withVideo((c) => _seek(c, c.value.position + (step ?? seekStep)));

  /// Jumps back by [step] (default [seekStep]).
  Future<void> seekBack([Duration? step]) async =>
      _withVideo((c) => _seek(c, c.value.position - (step ?? seekStep)));

  Future<void> _seek(VideoPlayerController c, Duration target) {
    final to = _clamp(c, target);
    _session?.recordSeek(c.value.position, to, ChorkiSeekSource.api);
    return c.seekTo(to);
  }

  Duration _clamp(VideoPlayerController c, Duration d) {
    if (d < Duration.zero) return Duration.zero;
    final duration = c.value.duration;
    if (duration > Duration.zero && d > duration) return duration;
    return d;
  }

  /// Sets the playback speed; kept across video reloads.
  Future<void> setSpeed(double speed) async {
    assert(speed > 0);
    if (_disposed) return;
    _session?.recordSpeedChange(_speed.value, speed);
    _speed.value = speed;
    await _withVideo((c) => c.setPlaybackSpeed(speed));
  }

  /// Sets how the video fills the player (reported as a `fitChange`).
  void setFit(ChorkiVideoFit fit) {
    if (_disposed || _fit.value == fit) return;
    _fit.value = fit;
    _session?.recordFitChange(fit.name);
  }

  /// Switches between fit and fill.
  void toggleFit() => setFit(
    _fit.value == ChorkiVideoFit.fit ? ChorkiVideoFit.fill : ChorkiVideoFit.fit,
  );

  /// Asks the host [ChorkiPlayer] to reload the route.
  void retry() => _onRetry?.call();

  // ---------------------------------------------------------------------------
  // Tracks
  // ---------------------------------------------------------------------------

  /// Re-reads video and audio tracks from the platform.
  Future<void> refreshTracks() async {
    final c = _video.value;
    if (c == null || !c.value.isInitialized) return;
    final gen = _attachGen;

    if (c.isVideoTrackSupportAvailable()) {
      try {
        final tracks = await c.getVideoTracks();
        if (gen == _attachGen && !_disposed) _videoTracks.value = tracks;
      } catch (e, st) {
        ChorkiDiagnostics.report(e, st, 'controller.getVideoTracks');
      }
    }
    if (c.isAudioTrackSupportAvailable()) {
      try {
        final tracks = await c.getAudioTracks();
        if (gen != _attachGen || _disposed) return;
        _audioTracks.value = tracks;
        _selectedAudioTrackId.value ??= tracks
            .where((t) => t.isSelected)
            .firstOrNull
            ?.id;
      } catch (e, st) {
        ChorkiDiagnostics.report(e, st, 'controller.getAudioTracks');
      }
    }
  }

  /// Locks playback to [track]; pass null to return to Auto.
  Future<void> selectQuality(VideoTrack? track) async {
    final c = _video.value;
    if (c == null || !c.value.isInitialized || _disposed) return;
    try {
      await c.selectVideoTrack(track);
      if (identical(c, _video.value)) {
        final from = _selectedVideoTrack.value;
        _selectedVideoTrack.value = track;
        _session?.recordQualityChange(
          fromHeight: from?.height,
          toHeight: track?.height,
          bitrate: track?.bitrate,
          label: track?.label,
        );
      }
    } catch (e, st) {
      ChorkiDiagnostics.report(e, st, 'controller.selectQuality');
    }
  }

  /// Switches the audio to the track with [trackId] (from [audioTracks]).
  Future<void> selectAudioTrack(String trackId) async {
    final c = _video.value;
    if (c == null || !c.value.isInitialized || _disposed) return;
    try {
      await c.selectAudioTrack(trackId);
      if (identical(c, _video.value)) {
        _session?.recordAudioTrackChange(_selectedAudioTrackId.value, trackId);
        _selectedAudioTrackId.value = trackId;
      }
    } catch (e, st) {
      ChorkiDiagnostics.report(e, st, 'controller.selectAudioTrack');
    }
  }

  // ---------------------------------------------------------------------------
  // Picture-in-picture (Android)
  // ---------------------------------------------------------------------------

  /// Shrinks the app into a PiP window sized to the video. Android only.
  ///
  /// The whole Flutter UI is shown in the window, so hide everything except
  /// the player while [pipStatus] is [ChorkiPipStatus.enabled].
  Future<void> enterPip() async {
    if (_disposed) return;
    _ensureLifecycle();
    try {
      final status = await _pip.enter(_aspectRatio);
      _setPipStatus(status);
    } catch (e, st) {
      ChorkiDiagnostics.report(e, st, 'controller.enterPip');
    }
    _schedulePipProbes();
  }

  /// Enter PiP automatically when the user leaves the app. Android only.
  Future<void> setAutoPip(bool enabled) async {
    if (_disposed) return;
    _autoPip = enabled;
    _ensureLifecycle();
    await guardAsync(
      () => _pip.setAuto(enabled, _aspectRatio),
      'controller.setAutoPip',
    );
    await refreshPipStatus();
  }

  /// Re-reads the PiP status from the platform.
  Future<void> refreshPipStatus() async {
    if (_disposed) return;
    try {
      final status = await _pip.status();
      _setPipStatus(status);
    } catch (e, st) {
      ChorkiDiagnostics.report(e, st, 'controller.pipStatus');
    }
  }

  void _setPipStatus(ChorkiPipStatus status) {
    if (_disposed || _pipStatus.value == status) return;
    final wasKnown = _pipStatus.value != ChorkiPipStatus.unavailable;
    _pipStatus.value = status;
    // Availability being discovered is not a viewer action.
    if (wasKnown || status == ChorkiPipStatus.enabled) {
      _session?.recordPipChange(status.name);
    }
  }

  void _ensureLifecycle() {
    if (_lifecycle != null || _disposed) return;
    try {
      _lifecycle = AppLifecycleListener(
        onStateChange: (_) => _schedulePipProbes(),
      );
    } on FlutterError {
      // No binding yet; retried on the next attach.
    }
  }

  /// PiP transitions surface as lifecycle changes, but the platform reports
  /// the new mode a little later — probe a few times instead of polling.
  void _schedulePipProbes() {
    for (final t in _pipProbes) {
      t.cancel();
    }
    _pipProbes = [
      for (final delay in _pipProbeDelays)
        Timer(delay, () => unawaited(refreshPipStatus())),
    ];
  }

  static const List<Duration> _pipProbeDelays = [
    Duration.zero,
    Duration(milliseconds: 150),
    Duration(milliseconds: 500),
    Duration(milliseconds: 1200),
  ];
  List<Timer> _pipProbes = const [];

  // ---------------------------------------------------------------------------

  Future<void> _withVideo(
    Future<void> Function(VideoPlayerController c) action,
  ) async {
    final c = _video.value;
    if (c == null || !c.value.isInitialized || _disposed) return;
    await guardAsync(() => action(c), 'controller.video');
  }

  /// Releases the controller. The player does not call this: you do.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _session = null;
    _detachListener();
    _lifecycle?.dispose();
    _lifecycle = null;
    for (final t in _pipProbes) {
      t.cancel();
    }
    _pipProbes = const [];
    if (_autoPip) {
      fireAndReport(() => _pip.setAuto(false, 1), 'controller.disableAutoPip');
    }
    for (final n in <ChangeNotifier>[
      _video,
      _value,
      _videoTracks,
      _selectedVideoTrack,
      _audioTracks,
      _selectedAudioTrackId,
      _speed,
      _fit,
      _pipStatus,
      _isAdPlaying,
    ]) {
      n.dispose();
    }
  }
}
