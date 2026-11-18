import '../../core/result.dart';
import '../entity/byte_data_entity.dart';
import '../repositories/bytes_repository.dart';

/// Looks up a byte route.
class BytesUsecase {
  /// Uses [_byteRepository].
  const BytesUsecase(this._byteRepository);

  final ByteRepository _byteRepository;

  /// Resolves [url]; see [ByteRepository.getByteData].
  Future<Result<ByteDataEntity>> call(String url, {bool refresh = false}) =>
      _byteRepository.getByteData(url, refresh: refresh);
}
