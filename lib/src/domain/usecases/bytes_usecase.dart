import 'package:chorki_player/src/domain/entity/byte_data_entity.dart';
import 'package:chorki_player/src/domain/repositories/bytes_repository.dart';
import 'package:chorki_player/src/errors/server_failure.dart';
import 'package:dartz/dartz.dart';

class BytesUsecase {
  const BytesUsecase(this._byteRepository);

  final ByteRepository _byteRepository;

  Future<Either<Failure, ByteDataEntity>> call(String url) =>
      _byteRepository.getByteData(url);
}
