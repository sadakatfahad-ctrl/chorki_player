import 'dart:collection';

import 'package:chorki_player/src/data/datasources/bytes_data_sources.dart';
import 'package:chorki_player/src/domain/entity/byte_data_entity.dart';
import 'package:chorki_player/src/domain/repositories/bytes_repository.dart';
import 'package:chorki_player/src/errors/no_internet_exception.dart';
import 'package:chorki_player/src/errors/server_exception.dart';
import 'package:chorki_player/src/errors/server_failure.dart';
import 'package:dartz/dartz.dart';

/// Fetches routes and keeps the results for a while: a feed rebuilds a page
/// whenever it scrolls back into view, and the revisit should not wait for
/// the network again.
class ByteRepositoryImpl extends ByteRepository {
  ByteRepositoryImpl({
    required BytesDataSources byteDataSources,
    this.cacheTtl = const Duration(minutes: 5),
    this.maxCacheEntries = 50,
    DateTime Function()? clock,
  }) : _byteDataSources = byteDataSources,
       _clock = clock ?? DateTime.now;

  final BytesDataSources _byteDataSources;

  /// How long a resolved route is reused. Keep it below the lifetime of any
  /// signed video URL the API returns.
  final Duration cacheTtl;

  /// Most routes kept; the least recently used goes first.
  final int maxCacheEntries;

  final DateTime Function() _clock;

  // Insertion order is recency order: a hit is removed and re-added.
  final LinkedHashMap<String, (DateTime, ByteDataEntity)> _cache =
      LinkedHashMap();
  final Map<String, Future<Either<Failure, ByteDataEntity>>> _inFlight = {};

  @override
  Future<Either<Failure, ByteDataEntity>> getByteData(
    String url, {
    bool refresh = false,
  }) {
    final hit = _cache.remove(url);
    if (!refresh && hit != null && _clock().isBefore(hit.$1)) {
      _cache[url] = hit;
      return Future.value(Right(hit.$2));
    }
    // A page and its neighbour asking for the same route share one request.
    return _inFlight[url] ??= _fetch(url).then((result) {
      _inFlight.remove(url);
      result.fold((_) {}, (data) => _remember(url, data));
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

  Future<Either<Failure, ByteDataEntity>> _fetch(String url) async {
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
