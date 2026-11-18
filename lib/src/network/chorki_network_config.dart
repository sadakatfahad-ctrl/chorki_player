import 'package:flutter/foundation.dart';

/// HTTP settings for the player's byte route lookups.
///
/// Video requests use [ChorkiMediaOptions.httpHeaders]. VMAP ad schedules
/// use their own client: these headers (often auth tokens) are never sent
/// to ad servers.
///
/// Set it once at startup with `ChorkiPlayer.configure(network: ...)`.
@immutable
class ChorkiNetworkConfig {
  /// Creates a network configuration.
  const ChorkiNetworkConfig({
    this.headers = const {},
    this.headersProvider,
    this.connectTimeout = const Duration(seconds: 8),
    this.receiveTimeout = const Duration(seconds: 15),
    this.useHttp2 = true,
  });

  /// Sent with every request, e.g. `{'X-App-Version': '5.2.0'}`.
  final Map<String, String> headers;

  /// Called before every request; its headers are added to [headers]. Use it
  /// for values that change, like an auth token.
  final Future<Map<String, String>> Function()? headersProvider;

  /// Longest wait for a connection.
  final Duration connectTimeout;

  /// Longest wait for a response.
  final Duration receiveTimeout;

  /// Use one shared HTTP/2 connection (the default). Turn it off for servers
  /// or proxies that only speak HTTP/1.1.
  final bool useHttp2;

  @override
  bool operator ==(Object other) =>
      other is ChorkiNetworkConfig &&
      mapEquals(other.headers, headers) &&
      other.headersProvider == headersProvider &&
      other.connectTimeout == connectTimeout &&
      other.receiveTimeout == receiveTimeout &&
      other.useHttp2 == useHttp2;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      headers.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    headersProvider,
    connectTimeout,
    receiveTimeout,
    useHttp2,
  );
}
