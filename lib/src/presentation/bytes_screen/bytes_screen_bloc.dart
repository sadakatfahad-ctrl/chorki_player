import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/usecases/bytes_usecase.dart';
import 'byte_screen_event.dart';
import 'byte_screen_state.dart';

/// Resolves a byte route (or takes a direct source) into a
/// [ByteScreenState].
class BytesBloc extends Bloc<ByteScreenEvent, ByteScreenState> {
  /// A bloc that resolves routes with the given use case.
  BytesBloc({required this._getByteDataUsecase})
    : super(const ByteScreenInitialState()) {
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

    final response = await _getByteDataUsecase(
      event.route,
      refresh: event.refresh,
    );
    if (id != _requestId) return;

    response.fold(
      (error) => emit(ByteScreenFailedState(error)),
      (byteData) => emit(ByteScreenLoadedState(byteData)),
    );
  }
}
