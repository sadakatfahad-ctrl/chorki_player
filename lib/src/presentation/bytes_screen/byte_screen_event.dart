import '../../domain/entity/byte_data_entity.dart';

/// Input to the [BytesBloc]: what to load.
abstract class ByteScreenEvent {
  /// Base constructor.
  const ByteScreenEvent();
}

/// Load the byte behind a Chorki route.
class ByteScreenInitialEvent extends ByteScreenEvent {
  /// Loads [route]; [refresh] bypasses the route cache.
  const ByteScreenInitialEvent(this.route, {this.refresh = false});

  /// The Chorki API route.
  final String route;

  /// Skip a cached result, e.g. when its video URL failed to play.
  final bool refresh;
}

/// Plays [data] as is, without fetching a route.
class ByteScreenSourceEvent extends ByteScreenEvent {
  /// Plays [data] as is.
  const ByteScreenSourceEvent(this.data);

  /// The byte to play.
  final ByteDataEntity data;
}
