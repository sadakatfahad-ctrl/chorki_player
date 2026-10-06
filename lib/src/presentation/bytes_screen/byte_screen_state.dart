import 'package:chorki_player/src/domain/entity/byte_data_entity.dart';
import 'package:equatable/equatable.dart';

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
  const ByteScreenFailedState(this.message);

  final String message;

  @override
  List<Object?> get props => [byteData, message];
}
