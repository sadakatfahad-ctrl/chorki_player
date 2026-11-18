import '../../core/result.dart';
import '../entity/byte_data_entity.dart';

/// Resolves byte routes.
abstract class ByteRepository {
  /// Resolves the byte at [url]. With [refresh], skips any cached result,
  /// e.g. when the video URL it returned no longer plays.
  Future<Result<ByteDataEntity>> getByteData(
    String url, {
    bool refresh = false,
  });
}
