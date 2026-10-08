import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../ads/ad_timeline.dart';
import '../../ads/chorki_ad_state.dart';
import '../../helpers/time_format.dart';
import '../../theme/chorki_player_theme.dart';

class ShortsSeekBar extends StatefulWidget {
  const ShortsSeekBar({
    super.key,
    required this.controller,
    this.theme = const ChorkiPlayerTheme(),
    this.builders = const ChorkiPlayerBuilders(),
    this.barHeight = 3.0,
    this.expandedBarHeight = 6.0,
    this.thumbRadius = 7.0,
    this.idlePointerRadius = 4.5,
    this.horizontalPadding = 8.0,
    this.height,
    this.adMarkers,
    this.playedColor,
    this.bufferedColor,
    this.baseColor,
    this.thumbColor,
    this.bubbleColor,
    this.bubbleTextStyle,
    this.hapticTickInterval = const Duration(seconds: 5),
    this.seekThrottle = const Duration(milliseconds: 150),
    this.onSeekStarted,
    this.onSeekEnded,
  });

  final VideoPlayerController controller;

  final ChorkiPlayerTheme theme;

  final ChorkiPlayerBuilders builders;

  final double barHeight;

  final double expandedBarHeight;

  final double thumbRadius;

  final double idlePointerRadius;

  final double horizontalPadding;

  final double? height;

  /// Ad break ticks. Defaults to the markers published by the ad layer.
  final List<ChorkiAdMarker>? adMarkers;

  final Duration hapticTickInterval;

  final Duration seekThrottle;

  final Color? playedColor;
  final Color? bufferedColor;
  final Color? baseColor;
  final Color? thumbColor;
  final Color? bubbleColor;
  final TextStyle? bubbleTextStyle;

  double get _height => height ?? theme.seekBarHeight;
  Color get _playedColor => playedColor ?? theme.seekBarPlayedColor;
  Color get _bufferedColor => bufferedColor ?? theme.seekBarBufferedColor;
  Color get _baseColor => baseColor ?? theme.seekBarBaseColor;
  Color get _thumbColor => thumbColor ?? theme.seekBarThumbColor;
  Color get _bubbleColor => bubbleColor ?? theme.seekBarBubbleColor;
  TextStyle get _bubbleTextStyle =>
      bubbleTextStyle ?? theme.seekBarBubbleTextStyle;

  final ValueChanged<Duration>? onSeekStarted;

  final ValueChanged<Duration>? onSeekEnded;

  @override
  State<ShortsSeekBar> createState() => _ShortsSeekBarState();
}

class _ShortsSeekBarState extends State<ShortsSeekBar> {
  bool _dragging = false;
  double _dragFraction = 0;
  bool _resumeOnEnd = false;
  int _lastHapticTick = 0;
  Timer? _throttleTimer;

  VideoPlayerController get _controller => widget.controller;

  @override
  void didUpdateWidget(covariant ShortsSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      _throttleTimer?.cancel();
      _dragging = false;
      _resumeOnEnd = false;
    }
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _dragging = false;
    _resumeOnEnd = false;
    super.dispose();
  }

  void _beginScrub(double fraction) {
    final value = _controller.value;
    if (!value.isInitialized || value.duration == Duration.zero) return;

    HapticFeedback.lightImpact();
    setState(() {
      _dragging = true;
      _dragFraction = fraction.clamp(0.0, 1.0);
      _resumeOnEnd = value.isPlaying;
      _lastHapticTick = _tickIndex(_dragFraction);
    });
    widget.onSeekStarted?.call(_positionOf(_dragFraction));

    if (value.isPlaying) {
      _safe(() => _controller.pause());
    }

    _throttleTimer?.cancel();
    _throttleTimer = Timer.periodic(widget.seekThrottle, (_) {
      if (_dragging) _applyDragSeek();
    });
  }

  void _updateScrub(double fraction) {
    if (!_dragging) return;
    final clamped = fraction.clamp(0.0, 1.0);
    setState(() => _dragFraction = clamped);

    final tick = _tickIndex(clamped);
    if (tick != _lastHapticTick) {
      _lastHapticTick = tick;
      HapticFeedback.selectionClick();
    }
  }

  void _endScrub() {
    if (!_dragging) return;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    HapticFeedback.lightImpact();
    _restoreAfterScrub(applySeek: true);
    setState(() => _dragging = false);
  }

  void _restoreAfterScrub({required bool applySeek}) {
    if (applySeek) {
      _applyDragSeek();
      widget.onSeekEnded?.call(_positionOf(_dragFraction));
    }
    if (_resumeOnEnd) {
      _resumeOnEnd = false;
      _safe(() => _controller.play());
    }
  }

  void _safe(Future<void> Function() action) {
    action().catchError((Object _) {});
  }

  void _applyDragSeek() {
    _seekTo(_dragFraction);
  }

  Future<void> _seekTo(double fraction) async {
    final value = _controller.value;
    if (!value.isInitialized) return;
    final target = _positionOf(fraction);
    if (value.position == target) return;
    try {
      await _controller.seekTo(target);
    } catch (_) {}
  }

  Duration _positionOf(double fraction) {
    final duration = _controller.value.duration;
    return Duration(microseconds: (duration.inMicroseconds * fraction).round());
  }

  int _tickIndex(double fraction) {
    final interval = widget.hapticTickInterval.inMilliseconds;
    if (interval <= 0) return 0;
    return _positionOf(fraction).inMilliseconds ~/ interval;
  }

  int _bufferedEndMs(List<DurationRange> ranges, int positionMs) {
    for (final range in ranges) {
      final start = range.start.inMilliseconds;
      final end = range.end.inMilliseconds;
      if (start <= positionMs && positionMs <= end) return end;
    }
    return positionMs;
  }

  double _fractionAt(Offset localPosition, double width) {
    final usable = width - widget.horizontalPadding * 2;
    if (usable <= 0) return 0;
    return ((localPosition.dx - widget.horizontalPadding) / usable).clamp(
      0.0,
      1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        if (!value.isInitialized || value.duration == Duration.zero) {
          return const SizedBox.shrink();
        }

        final durationMs = value.duration.inMilliseconds;
        final positionMs = _dragging
            ? _positionOf(_dragFraction).inMilliseconds
            : value.position.inMilliseconds.clamp(0, durationMs);
        final bufferedMs = _bufferedEndMs(
          value.buffered,
          positionMs,
        ).clamp(0, durationMs);

        final customBuilder = widget.builders.seekBarBuilder;
        if (customBuilder != null) {
          return customBuilder(
            context,
            ChorkiSeekBarState(
              position: Duration(milliseconds: positionMs),
              buffered: Duration(milliseconds: bufferedMs),
              duration: value.duration,
              dragging: _dragging,
            ),
            (target) => _safe(() => _controller.seekTo(target)),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return SizedBox(
              height: widget._height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  HapticFeedback.selectionClick();
                  unawaited(_seekTo(_fractionAt(details.localPosition, width)));
                },
                onHorizontalDragStart: (details) =>
                    _beginScrub(_fractionAt(details.localPosition, width)),
                onHorizontalDragUpdate: (details) =>
                    _updateScrub(_fractionAt(details.localPosition, width)),
                onHorizontalDragEnd: (_) => _endScrub(),
                onHorizontalDragCancel: _endScrub,
                child: _buildTrack(
                  width: width,
                  positionFraction: positionMs / durationMs,
                  bufferedFraction: bufferedMs / durationMs,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTimeBubble(String text) {
    final custom = widget.builders.timeBubbleBuilder;
    if (custom != null) return custom(context, text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: widget._bubbleColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: widget._bubbleTextStyle),
    );
  }

  List<Widget> _buildAdMarkers(double trackWidth, double barHeight) {
    final markers =
        widget.adMarkers ?? ChorkiAdScope.maybeOf(context)?.markers ?? const [];
    if (markers.isEmpty) return const [];
    final theme = widget.theme;
    final markerHeight = theme.adMarkerHeight < barHeight
        ? barHeight
        : theme.adMarkerHeight;
    return [
      for (final m in markers)
        Positioned(
          key: Key('chorki_ad_marker_${m.id}'),
          left:
              widget.horizontalPadding +
              m.fraction.clamp(0.0, 1.0) * trackWidth -
              theme.adMarkerWidth / 2,
          bottom: barHeight / 2 - markerHeight / 2,
          child: IgnorePointer(
            child: Container(
              width: theme.adMarkerWidth,
              height: markerHeight,
              decoration: BoxDecoration(
                color: m.played
                    ? theme.adMarkerPlayedColor
                    : theme.adMarkerColor,
                borderRadius: BorderRadius.circular(theme.adMarkerWidth / 2),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _buildTrack({
    required double width,
    required double positionFraction,
    required double bufferedFraction,
  }) {
    final w = widget;
    final barHeight = _dragging ? w.expandedBarHeight : w.barHeight;
    final pointerRadius = _dragging ? w.thumbRadius : w.idlePointerRadius;
    final trackWidth = width - w.horizontalPadding * 2;

    final thumbCenter =
        w.horizontalPadding + positionFraction.clamp(0.0, 1.0) * trackWidth;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          key: const Key('chorki_seek_bar_track'),
          left: w.horizontalPadding,
          right: w.horizontalPadding,
          bottom: 0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: barHeight,
            decoration: BoxDecoration(
              color: w._baseColor,
              borderRadius: BorderRadius.circular(barHeight / 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: bufferedFraction.clamp(0.0, 1.0),
                    heightFactor: 1.0,
                    child: ColoredBox(
                      key: const Key('chorki_seek_bar_buffered'),
                      color: w._bufferedColor,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: positionFraction.clamp(0.0, 1.0),
                    heightFactor: 1.0,
                    child: ColoredBox(
                      key: const Key('chorki_seek_bar_played'),
                      color: w._playedColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        ..._buildAdMarkers(trackWidth, barHeight),
        Positioned(
          key: const Key('chorki_seek_bar_pointer'),
          left: thumbCenter - pointerRadius,
          bottom: barHeight / 2 - pointerRadius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            width: pointerRadius * 2,
            height: pointerRadius * 2,
            decoration: BoxDecoration(
              color: w._thumbColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),

        if (_dragging)
          Positioned(
            left: thumbCenter,
            bottom: w.thumbRadius * 2 + 14,
            child: FractionalTranslation(
              translation: const Offset(-0.5, 0),
              child: _buildTimeBubble(formatClock(_positionOf(_dragFraction))),
            ),
          ),
      ],
    );
  }
}
