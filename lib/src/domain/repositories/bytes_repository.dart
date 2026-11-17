import 'package:chorki_player/src/domain/entity/byte_data_entity.dart';
import 'package:chorki_player/src/errors/server_failure.dart';
import 'package:dartz/dartz.dart';

abstract class ByteRepository {
  /// Resolves the byte at [url]. With [refresh], skips any cached result,
  /// e.g. when the video URL it returned no longer plays.
  Future<Either<Failure, ByteDataEntity>> getByteData(
    String url, {
    bool refresh = false,
  });
}
