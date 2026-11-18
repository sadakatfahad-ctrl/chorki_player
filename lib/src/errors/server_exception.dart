/// The server answered with an error status.
class ServerException implements Exception {
  /// An error for [statusCode] with [message].
  const ServerException({
    this.message = 'Server error occurred',
    this.serverMessage,
    this.statusCode,
  });

  /// A generic description of the status (e.g. `Not Found`).
  final String message;

  /// The HTTP status, if there was a response.
  final int? statusCode;

  /// The `message` field of the response body, if any (never shown to
  /// viewers).
  final String? serverMessage;

  @override
  String toString() =>
      'ServerException(${statusCode ?? '-'}): $message'
      '${serverMessage == null ? '' : ' — $serverMessage'}';
}
