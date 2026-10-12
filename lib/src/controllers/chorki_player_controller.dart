import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

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
  ChorkiPlayerController({
    double initialSpeed = 1.0,
    ChorkiVideoFit initialFit = ChorkiVideoFit.fit,
    this.seekStep = const Duration(seconds: 10),
    ChorkiPipDelegate? pipDelegate,
  }) : _speed = ValueNotifier(initialSpeed),
       _fit = ValueNotifier(initialFit),
       _pip = pipDelegate ?? FloatingPipDelegate();

  /// Step used by [seekForward] / [seekBack].
  final Duration seekStep;

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

  ValueListenable<List<VideoAudioTrack>> get audioTracks => _audioTracks;

  ValueListenable<String?> get selectedAudioTrackId => _selectedAudioTrackId;

  /// Playback speed chosen by the user (long-press boost is not reflected).
  ValueListenable<double> get speed => _speed;

  ValueListenable<ChorkiVideoFit> get fit => _fit;

  ValueListenable<ChorkiPipStatus> get pipStatus => _pipStatus;

  /// True while an IMA ad has paused the content.
  ValueListenable<bool> get isAdPlaying => _isAdPlaying;

  bool get isAttached => _video.value != null;

  bool get isPipAvailable => _pipStatus.value != ChorkiPipStatus.unavailable;

  bool get isAutoPipEnabled => _autoPip;

  // ---------------------------------------------------------------------------
  // Wiring (called by ChorkiPlayer; call it yourself when using
  // ChorkiPlayerSurface directly).
  // ---------------------------------------------------------------------------

  /// Binds [controller]. Re-applies the chosen speed and refreshes tracks.
  /// [onRetry] backs [retry].
  void attach(VideoPlayerController controller, {VoidCallback? onRetry}) {
    if (_disposed) return;
    if (identical(_video.value, controller)) {
      _onRetry = onRetry ?? _onRetry;
      return;
    }
    _detachListener();
    _attachGen++;
    _onRetry = onRetry;
    _tracksLoadedFor = false;
    _videoTracks.value = const [];
    _selectedVideoTrack.value = null;
    _audioTracks.value = const [];
    _selectedAudioTrackId.value = null;
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
    _video.value = null;
    _value.value = const VideoPlayerValue.uninitialized();
    _videoTracks.value = const [];
    _selectedVideoTrack.value = null;
    _audioTracks.value = const [];
    _selectedAudioTrackId.value = null;
  }

  /// Reported by the ad layer.
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
        unawaited(_safe(() => c.setPlaybackSpeed(_speed.value)));
      }
      unawaited(refreshTracks());
      if (_autoPip) unawaited(_pip.setAuto(true, _aspectRatio));
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

  Future<void> play() async => _withVideo((c) => c.play());

  Future<void> pause() async => _withVideo((c) => c.pause());

  Future<void> togglePlayPause() async =>
      _withVideo((c) => c.value.isPlaying ? c.pause() : c.play());

  Future<void> seekTo(Duration position) async =>
      _withVideo((c) => c.seekTo(_clamp(c, position)));

  Future<void> seekForward([Duration? step]) async => _withVideo(
    (c) => c.seekTo(_clamp(c, c.value.position + (step ?? seekStep))),
  );

  Future<void> seekBack([Duration? step]) async => _withVideo(
    (c) => c.seekTo(_clamp(c, c.value.position - (step ?? seekStep))),
  );

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
    _speed.value = speed;
    await _withVideo((c) => c.setPlaybackSpeed(speed));
  }

  void setFit(ChorkiVideoFit fit) {
    if (!_disposed) _fit.value = fit;
  }

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
      } catch (_) {}
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
      } catch (_) {}
    }
  }

  /// Locks playback to [track]; pass null to return to Auto.
  Future<void> selectQuality(VideoTrack? track) async {
    final c = _video.value;
    if (c == null || !c.value.isInitialized || _disposed) return;
    try {
      await c.selectVideoTrack(track);
      if (identical(c, _video.value)) _selectedVideoTrack.value = track;
    } catch (_) {}
  }

  Future<void> selectAudioTrack(String trackId) async {
    final c = _video.value;
    if (c == null || !c.value.isInitialized || _disposed) return;
    try {
      await c.selectAudioTrack(trackId);
      if (identical(c, _video.value)) _selectedAudioTrackId.value = trackId;
    } catch (_) {}
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
    final status = await _pip.enter(_aspectRatio);
    if (!_disposed) _pipStatus.value = status;
    _schedulePipProbes();
  }

  /// Enter PiP automatically when the user leaves the app. Android only.
  Future<void> setAutoPip(bool enabled) async {
    if (_disposed) return;
    _autoPip = enabled;
    _ensureLifecycle();
    await _pip.setAuto(enabled, _aspectRatio);
    await refreshPipStatus();
  }

  Future<void> refreshPipStatus() async {
    if (_disposed) return;
    final status = await _pip.status();
    if (!_disposed) _pipStatus.value = status;
  }

  void _ensureLifecycle() {
    if (_lifecycle != null || _disposed) return;
    try {
      _lifecycle = AppLifecycleListener(
        onStateChange: (_) => _schedulePipProbes(),
      );
    } catch (_) {
      // No binding yet; retried on the next attach.
    }
  }

  /// PiP transitions surface as lifecycle changes, but the platform reports
  /// the new mode a little later — probe a few times instead of polling.
  void _schedulePipProbes() {
    for (final ms in const [0, 150, 500, 1200]) {
      Timer(Duration(milliseconds: ms), () => unawaited(refreshPipStatus()));
    }
  }

  // ---------------------------------------------------------------------------

  Future<void> _withVideo(
    Future<void> Function(VideoPlayerController c) action,
  ) async {
    final c = _video.value;
    if (c == null || !c.value.isInitialized || _disposed) return;
    await _safe(() => action(c));
  }

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _detachListener();
    _lifecycle?.dispose();
    _lifecycle = null;
    if (_autoPip) unawaited(_pip.setAuto(false, 1));
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
