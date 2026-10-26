import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:interactive_media_ads/interactive_media_ads.dart';
import 'package:video_player/video_player.dart';

import 'ad_timeline.dart';
import 'chorki_ad_config.dart';
import 'chorki_ad_state.dart';
import 'vmap.dart';

class ChorkiAdLayer extends StatefulWidget {
  const ChorkiAdLayer({
    super.key,
    required this.controller,
    required this.adTagUrl,
    required this.config,
    required this.autoPlay,
    required this.child,
    this.vmapFetcher = defaultVmapFetcher,
    this.onAdPlayingChanged,
  });

  final VideoPlayerController controller;
  final String adTagUrl;
  final ChorkiAdConfig config;
  final bool autoPlay;
  final Widget child;

  /// Fetches the campaign VMAP for markers/countdown (overridable in tests).
  final VmapFetcher vmapFetcher;

  /// True while an ad has paused the content, false once content resumes.
  final ValueChanged<bool>? onAdPlayingChanged;

  @override
  State<ChorkiAdLayer> createState() => _ChorkiAdLayerState();
}

class _ChorkiAdLayerState extends State<ChorkiAdLayer>
    with WidgetsBindingObserver {
  final ContentProgressProvider _progress = ContentProgressProvider();

  AdsLoader? _loader;
  AdsManager? _manager;
  Timer? _timer;

  bool _showContent = false;
  bool _adActive = false;
  bool _contentCompleteSent = false;
  bool _disposed = false;
  bool _contentStarted = false;
  bool _pauseSeen = false;
  final ChorkiAdState _state = ChorkiAdState();
  AdTimeline _timeline = AdTimeline(const []);
  Timer? _noPreRollFallback;
  Timer? _loadTimeout;
  bool _timedOut = false;
  AppLifecycleState _lastState = AppLifecycleState.resumed;

  late final AdDisplayContainer _container = AdDisplayContainer(
    onContainerAdded: _onContainerAdded,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onControllerValue);
    _state.startNow = _startNow;
    unawaited(_loadBreaks());
    final timeout = widget.config.loadTimeout;
    if (timeout != null) _loadTimeout = Timer(timeout, _onLoadTimeout);
    // Content must not play under the pre-roll.
    unawaited(_safe(widget.controller.pause));
  }

  Future<void> _loadBreaks() async {
    try {
      final raw = await loadVmapBreaks(
        widget.adTagUrl,
        fetcher: widget.vmapFetcher,
      );
      final duration = widget.controller.value.duration;
      if (_disposed || raw.isEmpty || duration <= Duration.zero) return;
      _timeline = AdTimeline(raw.map((b) => b.resolve(duration)).nonNulls);
      _publish(widget.controller.value.position);
    } catch (_) {}
  }

  void _onLoadTimeout() {
    if (_disposed || _pauseSeen || _showContent) return;
    _timedOut = true;
    widget.config.onAdError?.call('Ad load timed out');
    unawaited(_resumeContent());
  }

  void _destroy(AdsManager? manager) {
    if (manager != null) unawaited(_safe(manager.destroy));
  }

  void _publish(Duration position, {bool countdown = true}) {
    if (_disposed) return;
    _state.update(
      markers: _timeline.markers(widget.controller.value.duration),
      countdownSeconds: countdown ? _timeline.countdownSeconds(position) : null,
    );
  }

  /// Tap on the countdown pill: jump to the break so IMA starts it now.
  void _startNow() {
    final c = widget.controller;
    final next = _timeline.upcoming(c.value.position);
    if (next == null || _adActive) return;
    final duration = c.value.duration;
    final target = next.offset >= duration
        ? duration - const Duration(milliseconds: 200)
        : next.offset;
    unawaited(_safe(() => c.seekTo(target)));
    unawaited(
      _safe(() => _progress.setProgress(progress: target, duration: duration)),
    );
  }

  void _onContainerAdded(AdDisplayContainer container) {
    _loader = AdsLoader(
      container: container,
      onAdsLoaded: _onAdsLoaded,
      onAdsLoadError: (data) {
        widget.config.onAdError?.call(data.error.message ?? 'Ad load error');
        _resumeContent();
      },
    );

    _requestAds();
  }

  Future<void> _requestAds() async {
    final loader = _loader;
    if (loader == null || _disposed) return;
    _adActive = true;
    try {
      await loader.requestAds(
        AdsRequest(
          adTagUrl: widget.adTagUrl,
          contentProgressProvider: _progress,
        ),
      );
    } catch (e) {
      widget.config.onAdError?.call(e.toString());
      _resumeContent();
    }
  }

  void _onAdsLoaded(OnAdsLoadedData data) {
    final manager = data.manager;
    // From here the no-pre-roll fallback owns the wait.
    _loadTimeout?.cancel();
    _destroy(_manager);
    _manager = manager;

    manager.setAdsManagerDelegate(
      AdsManagerDelegate(
        onAdEvent: (event) {
          if (_disposed) return;
          widget.config.onAdEvent?.call(event);
          switch (event.type) {
            case AdEventType.loaded:
              unawaited(_safe(manager.start));
            case AdEventType.contentPauseRequested:
              unawaited(_pauseContent());
            case AdEventType.contentResumeRequested:
              unawaited(_resumeContent());
            case AdEventType.allAdsCompleted:
              _destroy(manager);
              _timeline.markAllPlayed();
              _publish(widget.controller.value.position, countdown: false);
              if (identical(_manager, manager)) _manager = null;
              _resumeContent();
            case _:
          }
        },
        onAdErrorEvent: (event) {
          widget.config.onAdError?.call(event.error.message ?? 'Ad error');
          _resumeContent();
        },
      ),
    );

    _pauseSeen = false;
    _noPreRollFallback?.cancel();
    _noPreRollFallback = Timer(const Duration(milliseconds: 1500), () {
      if (_disposed || _pauseSeen) return;
      // Content already revealed by the load timeout: still start the
      // manager, or a late campaign's mid-rolls would never play.
      if (_showContent && !_timedOut) return;
      unawaited(_safe(manager.start));
      if (!_showContent) _resumeContent();
    });
    unawaited(
      _safe(
        () => manager.init(
          settings: AdsRenderingSettings(
            enablePreloading: widget.config.enablePreloading,
          ),
        ),
      ),
    );
  }

  Future<void> _pauseContent() async {
    if (_disposed) return;
    _pauseSeen = true;
    _noPreRollFallback?.cancel();
    _loadTimeout?.cancel();
    _timeline.markPlayedNear(widget.controller.value.position);
    _publish(widget.controller.value.position, countdown: false);
    _stopTimer();
    setState(() {
      _showContent = false;
      _adActive = true;
    });
    widget.onAdPlayingChanged?.call(true);
    await _safe(widget.controller.pause);
  }

  Future<void> _resumeContent() async {
    if (_disposed) return;
    _loadTimeout?.cancel();
    setState(() {
      _showContent = true;
      _adActive = false;
    });
    widget.onAdPlayingChanged?.call(false);
    _startTimer();
    final shouldPlay = _contentStarted || widget.autoPlay;
    _contentStarted = true;
    if (shouldPlay) await _safe(widget.controller.play);
  }

  void _startTimer() {
    _timer ??= Timer.periodic(widget.config.progressInterval, (_) async {
      try {
        final c = widget.controller;
        if (_disposed || !c.value.isInitialized || _adActive) return;
        final position = c.value.position;
        final duration = c.value.duration;
        await _progress.setProgress(progress: position, duration: duration);
        _publish(position);

        final atEnd =
            duration > Duration.zero &&
            position >= duration - const Duration(milliseconds: 300);
        if (atEnd && !_contentCompleteSent && !_adActive) {
          _contentCompleteSent = true;
          await _loader?.contentComplete();
        }
      } catch (_) {}
    });
  }

  void _onControllerValue() {
    final v = widget.controller.value;
    if (_contentCompleteSent &&
        v.isInitialized &&
        !_adActive &&
        v.position < const Duration(seconds: 1)) {
      _contentCompleteSent = false;
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_showContent) {
      _lastState = state;
      return;
    }
    final manager = _manager;
    if (manager != null) {
      if (state == AppLifecycleState.resumed) {
        unawaited(_safe(manager.resume));
      } else if (state == AppLifecycleState.inactive &&
          _lastState == AppLifecycleState.resumed) {
        unawaited(_safe(manager.pause));
      }
    }
    _lastState = state;
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerValue);
    _stopTimer();
    _noPreRollFallback?.cancel();
    _loadTimeout?.cancel();
    _state.dispose();
    _destroy(_manager);
    _manager = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChorkiAdScope(
      state: _state,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _container),
          if (_showContent) Positioned.fill(child: widget.child),
        ],
      ),
    );
  }
}
