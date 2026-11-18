library;

export 'package:video_player/video_player.dart'
    show VideoTrack, VideoAudioTrack, VideoViewType;

export 'src/presentation/chorki_player_widget.dart';
export 'src/presentation/widgets/chorki_player_surface.dart';
export 'src/presentation/widgets/chorki_settings_sheet.dart';
export 'src/presentation/widgets/gesture_overlay.dart';
export 'src/presentation/widgets/shorts_seek_bar.dart';
export 'src/controllers/chorki_player_controller.dart';
export 'src/controllers/video_load_scheduler.dart';
export 'src/controllers/video_preloader.dart';
export 'src/media/chorki_media_options.dart';
export 'src/pip/chorki_pip.dart';
export 'src/domain/entity/ad_campaign_entity.dart';
export 'src/domain/entity/byte_data_entity.dart';
export 'src/helpers/time_format.dart';
export 'src/theme/chorki_player_theme.dart';
export 'src/ads/ad_timeline.dart' show ChorkiAdMarker;
export 'src/ads/chorki_ad_config.dart';
export 'src/analytics/chorki_analytics_config.dart';
export 'src/analytics/chorki_analytics_event.dart';
export 'src/analytics/chorki_analytics_session.dart';
export 'src/analytics/chorki_analytics_sink.dart';
export 'src/analytics/chorki_media_metadata.dart';
export 'src/analytics/matomo/analytics_storage.dart';
export 'src/analytics/matomo/matomo_config.dart';
export 'src/analytics/matomo/matomo_naming.dart';
export 'src/analytics/matomo/matomo_request_builder.dart';
export 'src/analytics/matomo/matomo_sink.dart';
export 'src/injection_container.dart' show getIt, initChorkiPlayer;
