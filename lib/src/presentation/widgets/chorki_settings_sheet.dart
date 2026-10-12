import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../controllers/chorki_player_controller.dart';
import '../../theme/chorki_player_theme.dart';

const List<double> defaultChorkiSpeedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// Opens the player settings (quality, audio, speed, video size, PiP) as a
/// modal bottom sheet. Replace its content with
/// [ChorkiPlayerBuilders.settingsSheetBuilder].
Future<void> showChorkiSettings(
  BuildContext context,
  ChorkiPlayerController controller, {
  ChorkiPlayerTheme theme = const ChorkiPlayerTheme(),
  ChorkiPlayerIcons icons = const ChorkiPlayerIcons(),
  ChorkiPlayerStrings strings = const ChorkiPlayerStrings(),
  ChorkiPlayerBuilders builders = const ChorkiPlayerBuilders(),
  List<double> speedOptions = defaultChorkiSpeedOptions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: theme.settingsSheetBackgroundColor,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) =>
        builders.settingsSheetBuilder?.call(ctx, controller) ??
        ChorkiSettingsSheet(
          controller: controller,
          theme: theme,
          icons: icons,
          strings: strings,
          builders: builders,
          speedOptions: speedOptions,
        ),
  );
}

/// Default "Quality: 720p" label; adds the bitrate when heights collide.
String defaultQualityLabel(VideoTrack track, List<VideoTrack> all) {
  final h = track.height;
  if (h == null || h <= 0) {
    return track.label ?? _bitrateLabel(track.bitrate) ?? track.id;
  }
  final tie = all.where((t) => t.height == h).length > 1;
  final rate = _bitrateLabel(track.bitrate);
  return tie && rate != null ? '${h}p · $rate' : '${h}p';
}

String? _bitrateLabel(int? bps) {
  if (bps == null || bps <= 0) return null;
  if (bps >= 1000000) return '${(bps / 1000000).toStringAsFixed(1)} Mbps';
  return '${(bps / 1000).round()} kbps';
}

String _speedLabel(double speed, ChorkiPlayerStrings strings) {
  if (speed == 1.0) return strings.normalSpeed;
  final s = speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();
  return '${s}x';
}

String _audioLabel(VideoAudioTrack t) => t.label ?? t.language ?? t.id;

enum _Page { root, quality, audio, speed }

class ChorkiSettingsSheet extends StatefulWidget {
  const ChorkiSettingsSheet({
    super.key,
    required this.controller,
    this.theme = const ChorkiPlayerTheme(),
    this.icons = const ChorkiPlayerIcons(),
    this.strings = const ChorkiPlayerStrings(),
    this.builders = const ChorkiPlayerBuilders(),
    this.speedOptions = defaultChorkiSpeedOptions,
  });

  final ChorkiPlayerController controller;
  final ChorkiPlayerTheme theme;
  final ChorkiPlayerIcons icons;
  final ChorkiPlayerStrings strings;
  final ChorkiPlayerBuilders builders;
  final List<double> speedOptions;

  @override
  State<ChorkiSettingsSheet> createState() => _ChorkiSettingsSheetState();
}

class _ChorkiSettingsSheetState extends State<ChorkiSettingsSheet> {
  _Page _page = _Page.root;

  ChorkiPlayerController get _c => widget.controller;

  late final Listenable _changes = Listenable.merge([
    _c.videoTracks,
    _c.selectedVideoTrack,
    _c.audioTracks,
    _c.selectedAudioTrackId,
    _c.speed,
    _c.fit,
    _c.pipStatus,
  ]);

  String _qualityLabel(VideoTrack t, List<VideoTrack> all) =>
      widget.builders.qualityLabelBuilder?.call(t) ??
      defaultQualityLabel(t, all);

  List<VideoTrack> get _sortedTracks {
    final tracks = [..._c.videoTracks.value];
    tracks.sort((a, b) {
      final h = (b.height ?? 0).compareTo(a.height ?? 0);
      return h != 0 ? h : (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
    });
    return tracks;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: _changes,
        builder: (context, _) => AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: switch (_page) {
                _Page.root => _root(),
                _Page.quality => _quality(),
                _Page.audio => _audio(),
                _Page.speed => _speed(),
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _root() {
    final s = widget.strings;
    final i = widget.icons;
    final tracks = _c.videoTracks.value;
    final selected = _c.selectedVideoTrack.value;
    final audio = _c.audioTracks.value;
    final audioId = _c.selectedAudioTrackId.value;
    final selectedAudio = audio.where((t) => t.id == audioId).firstOrNull;
    final fill = _c.fit.value == ChorkiVideoFit.fill;

    return [
      if (tracks.length > 1)
        _row(
          key: const Key('chorki_settings_quality'),
          icon: i.quality,
          title: s.quality,
          value: selected == null ? s.auto : _qualityLabel(selected, tracks),
          onTap: () => setState(() => _page = _Page.quality),
        ),
      if (audio.length > 1)
        _row(
          key: const Key('chorki_settings_audio'),
          icon: i.audio,
          title: s.audio,
          value: selectedAudio == null ? null : _audioLabel(selectedAudio),
          onTap: () => setState(() => _page = _Page.audio),
        ),
      _row(
        key: const Key('chorki_settings_speed'),
        icon: i.speed,
        title: s.speed,
        value: _speedLabel(_c.speed.value, s),
        onTap: () => setState(() => _page = _Page.speed),
      ),
      _row(
        key: const Key('chorki_settings_fit'),
        icon: i.fit,
        title: s.videoFit,
        value: fill ? s.fill : s.fit,
        onTap: _c.toggleFit,
      ),
      if (_c.isPipAvailable)
        _row(
          key: const Key('chorki_settings_pip'),
          icon: i.pip,
          title: s.pictureInPicture,
          onTap: () {
            Navigator.of(context).maybePop();
            _c.enterPip();
          },
        ),
    ];
  }

  List<Widget> _quality() {
    final tracks = _sortedTracks;
    final selected = _c.selectedVideoTrack.value;
    return [
      _header(widget.strings.quality),
      _option(
        key: const Key('chorki_quality_auto'),
        label: widget.strings.auto,
        selected: selected == null,
        onTap: () => _pick(() => _c.selectQuality(null)),
      ),
      for (final t in tracks)
        _option(
          key: Key('chorki_quality_${t.id}'),
          label: _qualityLabel(t, tracks),
          selected: selected?.id == t.id,
          onTap: () => _pick(() => _c.selectQuality(t)),
        ),
    ];
  }

  List<Widget> _audio() {
    final id = _c.selectedAudioTrackId.value;
    return [
      _header(widget.strings.audio),
      for (final t in _c.audioTracks.value)
        _option(
          key: Key('chorki_audio_${t.id}'),
          label: _audioLabel(t),
          selected: t.id == id,
          onTap: () => _pick(() => _c.selectAudioTrack(t.id)),
        ),
    ];
  }

  List<Widget> _speed() {
    final current = _c.speed.value;
    return [
      _header(widget.strings.speed),
      for (final v in widget.speedOptions)
        _option(
          key: Key('chorki_speed_$v'),
          label: _speedLabel(v, widget.strings),
          selected: v == current,
          onTap: () => _pick(() => _c.setSpeed(v)),
        ),
    ];
  }

  void _pick(Future<void> Function() action) {
    action();
    setState(() => _page = _Page.root);
  }

  Widget _header(String title) {
    return ListTile(
      leading: IconButton(
        key: const Key('chorki_settings_back'),
        icon: Icon(widget.icons.back, color: widget.theme.settingsButtonColor),
        onPressed: () => setState(() => _page = _Page.root),
      ),
      title: Text(title, style: widget.theme.settingsTextStyle),
    );
  }

  Widget _row({
    required Key key,
    required IconData icon,
    required String title,
    String? value,
    required VoidCallback onTap,
  }) {
    final t = widget.theme;
    return ListTile(
      key: key,
      leading: Icon(icon, color: t.settingsButtonColor),
      title: Text(title, style: t.settingsTextStyle),
      trailing: value == null
          ? null
          : Text(value, style: t.settingsSecondaryTextStyle),
      onTap: onTap,
    );
  }

  Widget _option({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final t = widget.theme;
    return ListTile(
      key: key,
      leading: SizedBox(
        width: 40,
        child: selected
            ? Icon(widget.icons.check, color: t.settingsSelectedColor)
            : null,
      ),
      title: Text(
        label,
        style: selected
            ? t.settingsTextStyle.copyWith(color: t.settingsSelectedColor)
            : t.settingsTextStyle,
      ),
      selected: selected,
      onTap: onTap,
    );
  }
}
