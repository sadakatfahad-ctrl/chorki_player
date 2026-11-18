import 'package:get_it/get_it.dart';

/// The app-wide `GetIt.instance`.
///
/// The player no longer registers anything in it.
@Deprecated(
  'The player no longer uses GetIt; use your own GetIt.instance. '
  'Removed in 2.0.0.',
)
final getIt = GetIt.instance;

/// Did the player's setup in `GetIt.instance`. Now a no-op: the player keeps
/// its own services.
@Deprecated(
  'No longer needed; the player sets itself up. Use ChorkiPlayer.configure '
  'for network settings. Removed in 2.0.0.',
)
void initChorkiPlayer() {}
