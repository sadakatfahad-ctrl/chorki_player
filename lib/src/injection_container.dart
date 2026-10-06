import 'package:chorki_player/src/data/datasources/bytes_data_sources.dart';
import 'package:chorki_player/src/data/repositories/byte_repository_impl.dart';
import 'package:chorki_player/src/domain/repositories/bytes_repository.dart';
import 'package:chorki_player/src/domain/usecases/bytes_usecase.dart';
import 'package:get_it/get_it.dart';

final getIt = GetIt.instance;

void initChorkiPlayer() {
  if (!getIt.isRegistered<BytesDataSources>()) {
    getIt.registerLazySingleton<BytesDataSources>(BytesDataSources.new);
  }
  if (!getIt.isRegistered<ByteRepository>()) {
    getIt.registerLazySingleton<ByteRepository>(
      () => ByteRepositoryImpl(byteDataSources: getIt()),
    );
  }
  if (!getIt.isRegistered<BytesUsecase>()) {
    getIt.registerLazySingleton<BytesUsecase>(() => BytesUsecase(getIt()));
  }
}
