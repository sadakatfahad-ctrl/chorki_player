import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../ads/ad_timeline.dart';
import '../../ads/chorki_ad_state.dart';
import '../../analytics/chorki_analytics_event.dart';
import '../../analytics/chorki_analytics_scope.dart';
import '../../analytics/chorki_analytics_session.dart';
import '../../helpers/time_format.dart';
import '../../theme/chorki_player_theme.dart';
import 'scrub_session.dart';

/// The shorts seek bar: a thin track that grows while dragged, with the
/// buffered range, ad break markers and a time bubble. Tap to seek, drag to
/// scrub; both report to the analytics session in scope.
class ChorkiShortsSeekBar extends StatefulWidget {
  /// A seek bar for [controller].
  const ChorkiShortsSeekBar({
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

  /// The video it shows and seeks.
  final VideoPlayerController controller;

  /// Default colors and height.
  final ChorkiPlayerTheme theme;

  /// May replace the bar or its time bubble.
  final ChorkiPlayerBuilders builders;

  /// Track thickness at rest.
  final double barHeight;

  /// Track thickness while dragging.
  final double expandedBarHeight;

  /// Thumb radius while dragging.
  final double thumbRadius;

  /// Pointer radius at rest.
  final double idlePointerRadius;

  /// Space between the track and the edges.
  final double horizontalPadding;

  /// Touch area height; defaults to [ChorkiPlayerTheme.seekBarHeight].
  final double? height;

  /// Ad break ticks. Defaults to the markers published by the ad layer.
  final List<ChorkiAdMarker>? adMarkers;

  /// A haptic tick each time a drag crosses a multiple of this.
  final Duration hapticTickInterval;

  /// How often the video follows a drag.
  final Duration seekThrottle;

  /// Overrides [ChorkiPlayerTheme.seekBarPlayedColor].
  final Color? playedColor;

  /// Overrides [ChorkiPlayerTheme.seekBarBufferedColor].
  final Color? bufferedColor;

  /// Overrides [ChorkiPlayerTheme.seekBarBaseColor].
  final Color? baseColor;

  /// Overrides [ChorkiPlayerTheme.seekBarThumbColor].
  final Color? thumbColor;

  /// Overrides [ChorkiPlayerTheme.seekBarBubbleColor].
  final Color? bubbleColor;

  /// Overrides [ChorkiPlayerTheme.seekBarBubbleTextStyle].
  final TextStyle? bubbleTextStyle;

  double get _height => height ?? theme.seekBarHeight;
  Color get _playedColor => playedColor ?? theme.seekBarPlayedColor;
  Color get _bufferedColor => bufferedColor ?? theme.seekBarBufferedColor;
  Color get _baseColor => baseColor ?? theme.seekBarBaseColor;
  Color get _thumbColor => thumbColor ?? theme.seekBarThumbColor;
  Color get _bubbleColor => bubbleColor ?? theme.seekBarBubbleColor;
  TextStyle get _bubbleTextStyle =>
      bubbleTextStyle ?? theme.seekBarBubbleTextStyle;

  /// A drag started, at this position.
  final ValueChanged<Duration>? onSeekStarted;

  /// A drag ended; the video seeks here.
  final ValueChanged<Duration>? onSeekEnded;

  @override
  State<ChorkiShortsSeekBar> createState() => _ChorkiShortsSeekBarState();
}

class _ChorkiShortsSeekBarState extends State<ChorkiShortsSeekBar> {
  /// How fast the track and thumb grow when a drag starts.
  static const Duration _grow = Duration(milliseconds: 120);

  late final ScrubSession _scrub = ScrubSession(
    controller: () => widget.controller,
    analytics: () => _analytics,
    source: ChorkiSeekSource.seekBarDrag,
    context: 'seekBar',
    tickInterval: widget.hapticTickInterval,
    throttle: widget.seekThrottle,
    skipSeekToCurrent: true,
  );

  bool get _dragging => _scrub.active;

  VideoPlayerController get _controller => widget.controller;

  ChorkiAnalyticsSession? get _analytics =>
      mounted ? ChorkiAnalyticsScope.maybeOf(context) : null;

  @override
  void didUpdateWidget(covariant ChorkiShortsSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The old video is not resumed: in a feed it belongs to a page that was
    // swiped away.
    if (oldWidget.controller != widget.controller) {
      _scrub.abandon(reportCancel: true);
    }
  }

  @override
  void dispose() {
    _scrub.abandon(reportCancel: true);
    super.dispose();
  }

  void _beginScrub(double fraction) {
    final value = _controller.value;
    if (!value.isInitialized || value.duration == Duration.zero) return;
    setState(() => _scrub.begin(_positionOf(fraction)));
    widget.onSeekStarted?.call(_scrub.target);
  }

  void _updateScrub(double fraction) {
    if (!_dragging) return;
    setState(() => _scrub.update(_positionOf(fraction)));
  }

  void _endScrub() {
    final target = _scrub.finish();
    if (target == null) return;
    widget.onSeekEnded?.call(target);
    setState(() {});
  }

  /// A tap, or a seek from a custom seek bar: clamped to the video.
  void _seekNow(Duration target) {
    _analytics?.recordSeek(
      _controller.value.position,
      _scrub.clamp(target),
      ChorkiSeekSource.seekBarTap,
    );
    unawaited(_scrub.seek(target));
  }

  Duration _positionOf(double fraction) {
    final duration = _controller.value.duration;
    return Duration(
      microseconds: (duration.inMicroseconds * fraction.clamp(0.0, 1.0))
          .round(),
    );
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
            ? _scrub.target.inMilliseconds
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
              adMarkers: _adMarkers,
            ),
            _seekNow,
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
                  unawaited(HapticFeedback.selectionClick());
                  _seekNow(
                    _positionOf(_fractionAt(details.localPosition, width)),
                  );
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

  List<ChorkiAdMarker> get _adMarkers =>
      widget.adMarkers ?? ChorkiAdScope.maybeOf(context)?.markers ?? const [];

  List<Widget> _buildAdMarkers(double trackWidth, double barHeight) {
    final markers = _adMarkers;
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
            duration: _grow,
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
            duration: _grow,
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
              child: _buildTimeBubble(formatClock(_scrub.target)),
            ),
          ),
      ],
    );
  }
}
