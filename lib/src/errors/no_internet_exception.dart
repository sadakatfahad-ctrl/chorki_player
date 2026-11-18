/// The device could not reach the server.
class NoInternetException implements Exception {
  /// An exception with [message].
  const NoInternetException({this.message = 'No internet connection'});

  /// Developer-facing description (never shown to viewers).
  final String message;

  @override
  String toString() => 'NoInternetException: $message';
}
