import 'package:equatable/equatable.dart';

import '../../domain/entity/byte_data_entity.dart';
import '../../errors/chorki_player_error.dart';

/// Output of the [BytesBloc].
abstract class ByteScreenState extends Equatable {
  /// Base constructor.
  const ByteScreenState({this.byteData});

  /// The loaded byte, once there is one.
  final ByteDataEntity? byteData;

  @override
  List<Object?> get props => [byteData];
}

/// Nothing requested yet.
class ByteScreenInitialState extends ByteScreenState {
  /// The initial state.
  const ByteScreenInitialState();
}

/// The route is being resolved.
class ByteScreenLoadingState extends ByteScreenState {
  /// A loading state.
  const ByteScreenLoadingState();
}

/// The byte is known; the video can load.
class ByteScreenLoadedState extends ByteScreenState {
  /// Loaded [data].
  const ByteScreenLoadedState(this.data) : super(byteData: data);

  /// The resolved byte.
  final ByteDataEntity data;

  @override
  List<Object?> get props => [data];
}

/// Resolving the route failed.
class ByteScreenFailedState extends ByteScreenState {
  /// Failed with [error].
  const ByteScreenFailedState(this.error);

  /// Why it failed.
  final ChorkiPlayerError error;

  @override
  List<Object?> get props => [byteData, error];
}
