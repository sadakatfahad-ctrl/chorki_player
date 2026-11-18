// Deprecated names kept until 2.0.0. See CHANGELOG "Deprecated".

import 'controllers/video_load_scheduler.dart';
import 'controllers/video_preloader.dart';
import 'domain/entity/ad_campaign_entity.dart' as entity;
import 'domain/entity/byte_data_entity.dart' as entity;
import 'pip/chorki_pip.dart';
import 'presentation/widgets/gesture_overlay.dart';
import 'presentation/widgets/shorts_seek_bar.dart';

/// The old name of [ChorkiGestureOverlay].
@Deprecated('Use ChorkiGestureOverlay. Removed in 2.0.0.')
typedef PlayerGestureOverlay = ChorkiGestureOverlay;

/// The old name of [ChorkiShortsSeekBar].
@Deprecated('Use ChorkiShortsSeekBar. Removed in 2.0.0.')
typedef ShortsSeekBar = ChorkiShortsSeekBar;

/// The old name of [ChorkiVideoPreloader].
@Deprecated('Use ChorkiVideoPreloader. Removed in 2.0.0.')
typedef VideoPreloader = ChorkiVideoPreloader;

/// The old name of [ChorkiVideoLoadScheduler].
@Deprecated('Use ChorkiVideoLoadScheduler. Removed in 2.0.0.')
typedef VideoLoadScheduler = ChorkiVideoLoadScheduler;

/// The old name of [ChorkiFloatingPipDelegate].
@Deprecated('Use ChorkiFloatingPipDelegate. Removed in 2.0.0.')
typedef FloatingPipDelegate = ChorkiFloatingPipDelegate;

/// The player's internal route result. It appears in no public API.
@Deprecated(
  'No longer needed: it appears in no public API (use ChorkiPlayer.url for '
  'a direct URL). Removed in 2.0.0.',
)
typedef ByteDataEntity = entity.ByteDataEntity;

/// The player's internal ad campaign data. It appears in no public API.
@Deprecated(
  'No longer needed: it appears in no public API (use ChorkiPlayer.url '
  'with adTagUrl). Removed in 2.0.0.',
)
typedef AdCampaignEntity = entity.AdCampaignEntity;
