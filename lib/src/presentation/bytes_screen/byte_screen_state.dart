import 'package:equatable/equatable.dart';

import '../../domain/entity/byte_data_entity.dart';
import '../../errors/chorki_player_error.dart';

abstract class ByteScreenState extends Equatable {
  const ByteScreenState({this.byteData});

  final ByteDataEntity? byteData;

  @override
  List<Object?> get props => [byteData];
}

class ByteScreenInitialState extends ByteScreenState {
  const ByteScreenInitialState();
}

class ByteScreenLoadingState extends ByteScreenState {
  const ByteScreenLoadingState();
}

class ByteScreenLoadedState extends ByteScreenState {
  const ByteScreenLoadedState(this.data) : super(byteData: data);

  final ByteDataEntity data;

  @override
  List<Object?> get props => [data];
}

class ByteScreenFailedState extends ByteScreenState {
  const ByteScreenFailedState(this.error);

  final ChorkiPlayerError error;

  @override
  List<Object?> get props => [byteData, error];
}
