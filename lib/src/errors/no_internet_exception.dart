class NoInternetException implements Exception {
  const NoInternetException({this.message = 'No internet connection'});

  final String message;

  @override
  String toString() => 'NoInternetException: $message';
}
