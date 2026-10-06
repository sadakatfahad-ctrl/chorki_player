abstract class Failure {
  const Failure();

  String get message;
}

class ServerFailure extends Failure {
  const ServerFailure({this.message = 'Server failure'});

  @override
  final String message;
}
