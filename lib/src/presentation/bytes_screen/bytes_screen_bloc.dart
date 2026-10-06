import 'package:chorki_player/src/domain/usecases/bytes_usecase.dart';
import 'package:chorki_player/src/presentation/bytes_screen/byte_screen_event.dart';
import 'package:chorki_player/src/presentation/bytes_screen/byte_screen_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BytesBloc extends Bloc<ByteScreenEvent, ByteScreenState> {
  BytesBloc({required BytesUsecase getByteDataUsecase})
    : _getByteDataUsecase = getByteDataUsecase,
      super(const ByteScreenInitialState()) {
    on<ByteScreenInitialEvent>(_onGetByteData);
  }

  final BytesUsecase _getByteDataUsecase;

  Future<void> _onGetByteData(
    ByteScreenInitialEvent event,
    Emitter<ByteScreenState> emit,
  ) async {
    emit(const ByteScreenLoadingState());

    final response = await _getByteDataUsecase(event.route);

    response.fold(
      (failure) => emit(ByteScreenFailedState(failure.message)),
      (byteData) => emit(ByteScreenLoadedState(byteData)),
    );
  }
}
