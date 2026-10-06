class ServerException implements Exception {
  const ServerException({
    this.message = 'Server error occurred',
    this.serverMessage,
    this.statusCode,
  });

  final String message;
  final int? statusCode;
  final String? serverMessage;

  @override
  String toString() =>
      'ServerException(${statusCode ?? '-'}): $message'
      '${serverMessage == null ? '' : ' — $serverMessage'}';
}
