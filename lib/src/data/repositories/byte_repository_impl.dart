import 'package:chorki_player/src/data/datasources/bytes_data_sources.dart';
import 'package:chorki_player/src/domain/entity/byte_data_entity.dart';
import 'package:chorki_player/src/domain/repositories/bytes_repository.dart';
import 'package:chorki_player/src/errors/no_internet_exception.dart';
import 'package:chorki_player/src/errors/server_exception.dart';
import 'package:chorki_player/src/errors/server_failure.dart';
import 'package:dartz/dartz.dart';

class ByteRepositoryImpl extends ByteRepository {
  ByteRepositoryImpl({required BytesDataSources byteDataSources})
    : _byteDataSources = byteDataSources;

  final BytesDataSources _byteDataSources;

  @override
  Future<Either<Failure, ByteDataEntity>> getByteData(String url) async {
    try {
      final byteModel = await _byteDataSources.getByteData(url);
      return Right(byteModel.toEntity());
    } on NoInternetException {
      return Left(const ServerFailure(message: 'No internet connection'));
    } on ServerException catch (error) {
      return Left(ServerFailure(message: error.serverMessage ?? error.message));
    } catch (error) {
      return Left(const ServerFailure(message: 'Something went wrong'));
    }
  }
}
