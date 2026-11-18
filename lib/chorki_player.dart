library;

export 'package:video_player/video_player.dart'
    show
        VideoAudioTrack,
        VideoPlayerController,
        VideoPlayerValue,
        VideoTrack,
        VideoViewType;

export 'src/ads/ad_timeline.dart' show ChorkiAdMarker;
export 'src/ads/chorki_ad_config.dart';
export 'src/analytics/chorki_analytics_config.dart';
export 'src/analytics/chorki_analytics_event.dart';
export 'src/analytics/chorki_analytics_schema.dart';
export 'src/analytics/chorki_analytics_session.dart';
export 'src/analytics/chorki_analytics_sink.dart';
export 'src/analytics/chorki_media_metadata.dart';
export 'src/analytics/matomo/analytics_storage.dart';
export 'src/analytics/matomo/matomo_config.dart';
export 'src/analytics/matomo/matomo_naming.dart';
export 'src/analytics/matomo/matomo_request_builder.dart';
export 'src/analytics/matomo/matomo_sink.dart';
export 'src/controllers/chorki_player_controller.dart';
export 'src/controllers/video_load_scheduler.dart';
export 'src/controllers/video_preloader.dart';
export 'src/core/clock.dart' show ChorkiClock;
export 'src/core/diagnostics.dart';
export 'src/core/ids.dart' show ChorkiIdGenerator;
export 'src/errors/chorki_player_error.dart';
export 'src/helpers/time_format.dart' show formatClock, formatDelta;
export 'src/injection_container.dart' show getIt, initChorkiPlayer;
export 'src/legacy_names.dart';
export 'src/media/chorki_media_options.dart';
export 'src/network/chorki_network_config.dart';
export 'src/pip/chorki_pip.dart';
export 'src/presentation/chorki_player_widget.dart';
export 'src/presentation/widgets/chorki_player_surface.dart';
export 'src/presentation/widgets/chorki_settings_sheet.dart';
export 'src/presentation/widgets/gesture_overlay.dart';
export 'src/presentation/widgets/shorts_seek_bar.dart';
export 'src/theme/chorki_player_theme.dart';
