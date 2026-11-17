import 'package:chorki_player/src/domain/entity/byte_data_entity.dart';

abstract class ByteScreenEvent {
  const ByteScreenEvent();
}

class ByteScreenInitialEvent extends ByteScreenEvent {
  const ByteScreenInitialEvent(this.route, {this.refresh = false});

  final String route;

  /// Skip a cached result, e.g. when its video URL failed to play.
  final bool refresh;
}

/// Plays [data] as is, without fetching a route.
class ByteScreenSourceEvent extends ByteScreenEvent {
  const ByteScreenSourceEvent(this.data);

  final ByteDataEntity data;
}
