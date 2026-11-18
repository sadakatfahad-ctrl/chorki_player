import 'package:flutter/foundation.dart';

import '../data/datasources/bytes_data_sources.dart';
import '../data/repositories/byte_repository_impl.dart';
import '../domain/repositories/bytes_repository.dart';
import '../domain/usecases/bytes_usecase.dart';
import '../network/api_client.dart';
import '../network/chorki_network_config.dart';

/// The player's own object graph: the HTTP client and the route repository
/// (with its cache), shared by every [ChorkiPlayer].
///
/// It deliberately does not use the app's service locator: an app resetting
/// or scoping its own `GetIt.instance` must not affect the player.
class ChorkiServices {
  ChorkiServices._(this.network);

  static ChorkiServices? _instance;

  /// The shared instance, created on first use.
  static ChorkiServices get instance =>
      _instance ??= ChorkiServices._(const ChorkiNetworkConfig());

  /// Replaces the shared instance with one using [network]. Cached routes
  /// are dropped. Players created before keep their repository.
  static void configure({required ChorkiNetworkConfig network}) {
    if (_instance?.network == network) return;
    // The old client is not closed: players built before keep using it.
    _instance = ChorkiServices._(network);
  }

  /// Replaces the route repository (tests).
  @visibleForTesting
  static void overrideForTesting({required ByteRepository repository}) {
    instance._repository = repository;
  }

  /// Back to a fresh default instance (tests).
  @visibleForTesting
  static void resetForTesting() {
    _instance?.apiClient.close();
    _instance = null;
  }

  /// The network settings in use.
  final ChorkiNetworkConfig network;

  /// The HTTP client for route requests.
  late final ApiClient apiClient = ApiClient(network);

  ByteRepository? _repository;

  /// The route repository, with its cache.
  ByteRepository get repository => _repository ??= ByteRepositoryImpl(
    byteDataSources: BytesDataSources(dio: apiClient.dio),
  );

  /// The route lookup use case.
  BytesUsecase get bytesUsecase => BytesUsecase(repository);
}
