import 'package:chorki_player/src/domain/usecases/bytes_usecase.dart';
import 'package:chorki_player/src/presentation/bytes_screen/byte_screen_event.dart';
import 'package:chorki_player/src/presentation/bytes_screen/byte_screen_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BytesBloc extends Bloc<ByteScreenEvent, ByteScreenState> {
  BytesBloc({required BytesUsecase getByteDataUsecase})
    : _getByteDataUsecase = getByteDataUsecase,
      super(const ByteScreenInitialState()) {
    on<ByteScreenInitialEvent>(_onGetByteData);
    on<ByteScreenSourceEvent>(_onSource);
  }

  final BytesUsecase _getByteDataUsecase;
  int _requestId = 0;

  void _onSource(ByteScreenSourceEvent event, Emitter<ByteScreenState> emit) {
    // Also cancels an in-flight route fetch.
    _requestId++;
    // Loading first: re-emitting an equal Loaded state (retry) is a no-op.
    emit(const ByteScreenLoadingState());
    emit(ByteScreenLoadedState(event.data));
  }

  Future<void> _onGetByteData(
    ByteScreenInitialEvent event,
    Emitter<ByteScreenState> emit,
  ) async {
    // Events run concurrently: only the latest request may emit, otherwise a
    // slow response for an old route would replace the current one.
    final id = ++_requestId;
    emit(const ByteScreenLoadingState());

    final response = await _getByteDataUsecase(event.route);
    if (id != _requestId) return;

    response.fold(
      (failure) => emit(ByteScreenFailedState(failure.message)),
      (byteData) => emit(ByteScreenLoadedState(byteData)),
    );
  }
}
