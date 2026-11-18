part of '../chorki_analytics_session.dart';

/// Turning video values into playback, QoE and quartile events.
extension _SessionPlayback on ChorkiAnalyticsSession {
  void _handleValue() {
    final video = _video;
    if (video == null || !_active || _disposed || _id == null) return;
    final v = video.value;
    if (!v.isInitialized || v.hasError) return;

    if (!_impressionSent) {
      _impressionSent = true;
      _impressionAt = _clock();
      _emit(ChorkiAnalyticsEventType.impression);
    }

    final now = _clock();
    final pos = v.position;
    final dur = v.duration;
    // Android (ExoPlayer) reports isPlaying false while it rebuffers: the
    // viewer has not paused, so keep a playing view playing until it stops
    // buffering.
    final playing = (v.isPlaying || (v.isBuffering && _wasPlaying)) && !_inAd;

    // A looping video wraps from the end back to the start without ever
    // reporting completion.
    final recentSeek =
        _lastSeekAt != null && now.difference(_lastSeekAt!) < _nearWindow;
    if (_wasPlaying &&
        !recentSeek &&
        dur > _minLoopDuration &&
        _lastPos >= dur - _nearWindow &&
        pos < _nearWindow) {
      _onLooped(pos);
    }

    // Watched time and segments: only real playback between two ticks.
    if (_wasPlaying && playing && !v.isBuffering) {
      final delta = pos - _lastPos;
      final maxTick = _maxTick * max(1.0, v.playbackSpeed);
      if (delta > Duration.zero && delta <= maxTick) {
        _watch.played(_lastPos, pos);
      }
    }
    if (pos > _maxPos) _maxPos = pos;

    // First frame / play / resume.
    if (playing && !_wasPlaying) {
      if (!_playedOnce) {
        _playedOnce = true;
        _timeToPlay = now.difference(_impressionAt ?? now);
        _emit(ChorkiAnalyticsEventType.play, {
          _K.timeToPlayMs: _timeToPlay!.inMilliseconds,
        });
      } else if (_paused) {
        _emit(ChorkiAnalyticsEventType.resume);
      }
      _paused = false;
      _startHeartbeat();
    }
    if (_firstFrameAt == null && v.isPlaying && pos > Duration.zero) {
      _firstFrameAt = now;
      final activated = _activatedAt ?? now;
      final loadStart = _loadStartAt;
      final from = loadStart != null && loadStart.isAfter(activated)
          ? loadStart
          : activated;
      final preloaded = loadStart != null && loadStart.isBefore(activated);
      _emit(ChorkiAnalyticsEventType.firstFrame, {
        _K.startupMs: now.difference(from).inMilliseconds,
        // Load timings belong to the view that waited for them.
        if (!preloaded && loadStart != null && _loadRunningAt != null)
          _K.queueWaitMs: _loadRunningAt!.difference(loadStart).inMilliseconds,
        if (!preloaded && _loadRunningAt != null && _loadedAt != null)
          _K.initMs: _loadedAt!.difference(_loadRunningAt!).inMilliseconds,
        _K.preloaded: preloaded,
      });
    }

    // Pause (an ad pausing the content is not the viewer pausing).
    final atEnd =
        v.isCompleted || (dur > Duration.zero && pos >= dur - _endWindow);
    if (!playing && _wasPlaying) {
      _stopHeartbeat();
      // A scrub pauses while dragging: that is a seek, not a pause.
      if (!_inAd && !atEnd && !_scrubbing) {
        _flush('pause');
        _pauseCount++;
        _paused = true;
        _emit(ChorkiAnalyticsEventType.pause);
      }
    }

    // Rebuffering, after the first frame and outside ads.
    if (v.isBuffering && !_wasBuffering && _firstFrameAt != null && !_inAd) {
      _bufferStartAt = now;
      _rebufferCount++;
      _emit(ChorkiAnalyticsEventType.bufferStart, {_K.afterSeek: recentSeek});
    } else if (!v.isBuffering && _bufferStartAt != null) {
      final took = now.difference(_bufferStartAt!);
      _rebufferTime += took;
      _bufferStartAt = null;
      _emit(ChorkiAnalyticsEventType.bufferEnd, {
        _K.durationMs: took.inMilliseconds,
      });
    }

    // Quartiles and completion.
    if (playing || _wasPlaying) {
      for (final q in _watch.reachedQuartiles(pos, dur)) {
        _emit(ChorkiAnalyticsEventType.quartile, {_K.percent: q});
      }
    }
    if (v.isCompleted && !_completed) {
      _completed = true;
      _onCompleted();
    } else if (_completed && dur > Duration.zero && pos < dur - _oneSecond) {
      _completed = false;
    }

    // Volume / mute.
    final vol = v.volume;
    if (_volume != null && (vol - _volume!).abs() > 0.001) {
      _emit(ChorkiAnalyticsEventType.volumeChange, {
        _K.from: _volume,
        _K.to: vol,
        _K.muted: vol == 0,
      });
    }
    _volume = vol;

    _wasPlaying = playing;
    _wasBuffering = v.isBuffering;
    _lastPos = pos;
  }

  void _onCompleted() {
    _flush('complete');
    if (_watch.reachedEnd()) {
      _emit(ChorkiAnalyticsEventType.quartile, {_K.percent: 100});
    }
    _emit(ChorkiAnalyticsEventType.complete);
  }

  void _onLooped(Duration pos) {
    // The tail between the last tick and the end was played too.
    final dur = _video?.value.duration ?? Duration.zero;
    _watch.played(_lastPos, dur);
    _onCompleted();
    _loopCount++;
    _emit(ChorkiAnalyticsEventType.loop, {_K.loopCount: _loopCount});
    if (_config.newSessionOnLoop) {
      final loops = _loopCount;
      _endSession(ChorkiSessionEndReason.looped);
      _startSession();
      _loopCount = loops;
      _impressionSent = true;
      _impressionAt = _clock();
      // Startup was measured on the first view; a loop starts instantly.
      _firstFrameAt = _impressionAt;
      _emit(ChorkiAnalyticsEventType.impression, {_K.loopCount: loops});
      _playedOnce = true;
      _timeToPlay = Duration.zero;
      _emit(ChorkiAnalyticsEventType.play, {
        _K.timeToPlayMs: 0,
        _K.loopCount: loops,
      });
      _startHeartbeat();
    } else {
      _watch.resetQuartiles();
      _completed = false;
    }
    // The regular tick step counts 0 → pos.
    _lastPos = Duration.zero;
  }
}
