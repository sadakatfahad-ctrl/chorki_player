import 'package:chorki_player/src/domain/entity/byte_data_entity.dart';
import 'package:chorki_player/src/errors/server_failure.dart';
import 'package:dartz/dartz.dart';

abstract class ByteRepository {
  Future<Either<Failure, ByteDataEntity>> getByteData(String url);
}
