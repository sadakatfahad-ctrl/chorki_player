part of '../chorki_analytics_session.dart';

/// Starting and ending a view, and its heartbeats.
extension _SessionView on ChorkiAnalyticsSession {
  void _beginView() {
    _activatedAt = _clock();
    _startSession();
    final v = _video?.value;
    if (v != null) {
      _lastPos = v.position;
      _wasPlaying = false;
      _volume = null;
    }
    _onValue();
  }

  /// Ends the view without reporting it (consent revoked, disabled).
  void _discardSession() {
    _id = null;
    _impressionSent = false;
    _activatedAt = null;
  }

  void _listenToLifecycle() {
    try {
      _lifecycle = AppLifecycleListener(onHide: _onAppHidden);
    } on FlutterError {
      // No binding (pure Dart use): nothing to listen to.
    }
  }

  /// The app went to the background: report progress so far and ask the
  /// sinks to send it, before the OS may kill the app.
  void _onAppHidden() {
    if (!_active || !_impressionSent) return;
    _flush('background');
    for (final sink in _config.sinks) {
      fireAndReport(sink.flush, 'analytics.flush');
    }
  }

  void _startSession() {
    _id = _newId();
    _impressionSent = false;
    _impressionAt = null;
    _timeToPlay = null;
    _watch.reset();
    _maxPos = Duration.zero;
    _playedOnce = false;
    _paused = false;
    _completed = false;
    _bufferStartAt = null;
    _firstFrameAt = null;
    _lastSeekAt = null;
    _loopCount = 0;
    _pauseCount = 0;
    _seekCount = 0;
    _rebufferCount = 0;
    _errorCount = 0;
    _rebufferTime = Duration.zero;
    _adBreakIndex = 0;
    _boostStartAt = null;
    // A break or drag cut off by the previous session must not leak in.
    _inAd = false;
    _adBreakStartAt = null;
    _scrubbing = false;
  }

  void _endSession(ChorkiSessionEndReason reason) {
    _stopHeartbeat();
    if (!_playedOnce && _id != null) {
      // Left before the first frame: exit before video start.
      final now = _clock();
      _emit(ChorkiAnalyticsEventType.abandon, {
        _K.waitedMs: now.difference(_activatedAt ?? now).inMilliseconds,
        _K.reason: reason.name,
        _K.abandonStage: _impressionSent ? 'ready' : 'loading',
        _K.errorCount: _errorCount,
      });
    }
    if (_impressionSent) {
      final now = _clock();
      final buffering = _bufferStartAt;
      if (buffering != null) {
        _rebufferTime += now.difference(buffering);
        _emit(ChorkiAnalyticsEventType.bufferEnd, {
          _K.durationMs: now.difference(buffering).inMilliseconds,
        });
        _bufferStartAt = null;
      }
      if (_boostStartAt != null) recordSpeedBoostEnd();
      // Swiped away mid-break: the ad layer is gone and will not end it.
      if (_inAd) {
        final start = _adBreakStartAt;
        _emit(ChorkiAnalyticsEventType.adBreakEnd, {
          _K.breakIndex: _adBreakIndex,
          _K.durationMs: start == null
              ? 0
              : now.difference(start).inMilliseconds,
          _K.interrupted: true,
          ...adContext,
        });
        _inAd = false;
        _adBreakStartAt = null;
      }
      _flush('end');
      final duration = _video?.value.duration ?? Duration.zero;
      _emit(ChorkiAnalyticsEventType.sessionEnd, {
        _K.reason: reason.name,
        _K.dwellMs: now.difference(_impressionAt ?? now).inMilliseconds,
        _K.watchedPercent: _watch.watchedPercent(duration),
        _K.maxPositionMs: _maxPos.inMilliseconds,
        _K.rebufferCount: _rebufferCount,
        _K.rebufferMs: _rebufferTime.inMilliseconds,
        _K.pauseCount: _pauseCount,
        _K.seekCount: _seekCount,
        _K.loopCount: _loopCount,
        _K.errorCount: _errorCount,
      });
    }
    _id = null;
    _impressionSent = false;
  }

  void _startHeartbeat() {
    if (_heartbeat != null || !_config.isActive) return;
    _heartbeat = Timer.periodic(_config.heartbeatInterval, (_) {
      _flush('interval');
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void _flush(String trigger) {
    if (!_impressionSent || _id == null) return;
    _emit(ChorkiAnalyticsEventType.heartbeat, {
      _K.trigger: trigger,
      _K.newSegments: _watch.takeNewSegments(),
    });
  }
}
