import 'dart:async';
import 'dart:collection';

import '../../core/clock.dart';
import '../../core/diagnostics.dart';
import '../../core/result.dart';
import '../../domain/entity/byte_data_entity.dart';
import '../../domain/repositories/bytes_repository.dart';
import '../../errors/chorki_player_error.dart';
import '../../errors/no_internet_exception.dart';
import '../../errors/server_exception.dart';
import '../datasources/bytes_data_sources.dart';

/// Fetches routes and keeps the results for a while: a feed rebuilds a page
/// whenever it scrolls back into view, and the revisit should not wait for
/// the network again.
class ByteRepositoryImpl extends ByteRepository {
  /// Fetches through [byteDataSources].
  ByteRepositoryImpl({
    required this._byteDataSources,
    this.cacheTtl = const Duration(minutes: 5),
    this.maxCacheEntries = 50,
    this._clock = systemClock,
  });

  final BytesDataSources _byteDataSources;

  /// How long a resolved route is reused. Keep it below the lifetime of any
  /// signed video URL the API returns.
  final Duration cacheTtl;

  /// Most routes kept; the least recently used goes first.
  final int maxCacheEntries;

  final ChorkiClock _clock;

  // Insertion order is recency order: a hit is removed and re-added.
  final LinkedHashMap<String, (DateTime, ByteDataEntity)> _cache =
      LinkedHashMap();
  final Map<String, Future<Result<ByteDataEntity>>> _inFlight = {};

  @override
  Future<Result<ByteDataEntity>> getByteData(
    String url, {
    bool refresh = false,
  }) {
    final hit = _cache.remove(url);
    if (!refresh && hit != null && _clock().isBefore(hit.$1)) {
      _cache[url] = hit;
      return Future.value(Ok(hit.$2));
    }
    // A page and its neighbour asking for the same route share one request.
    return _inFlight[url] ??= _fetch(url).then((result) {
      unawaited(_inFlight.remove(url));
      if (result case Ok(:final value)) _remember(url, value);
      return result;
    });
  }

  void _remember(String url, ByteDataEntity data) {
    if (maxCacheEntries <= 0) return;
    _cache.remove(url);
    _cache[url] = (_clock().add(cacheTtl), data);
    while (_cache.length > maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<Result<ByteDataEntity>> _fetch(String url) async {
    try {
      final byteModel = await _byteDataSources.getByteData(url);
      final entity = byteModel.toEntity();
      if (entity.url.isEmpty) {
        return const Err(ChorkiPlayerError(ChorkiErrorCode.noVideoUrl));
      }
      return Ok(entity);
    } on ChorkiPlayerError catch (error) {
      return Err(error);
    } on NoInternetException catch (error) {
      return Err(ChorkiPlayerError.from(error));
    } on ServerException catch (error) {
      return Err(ChorkiPlayerError.from(error));
    } catch (error, stack) {
      // Not a network or server error: a bug or an unexpected payload.
      ChorkiDiagnostics.report(error, stack, 'repository.getByteData');
      return Err(ChorkiPlayerError.from(error));
    }
  }
}
