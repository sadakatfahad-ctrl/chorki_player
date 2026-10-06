abstract class ByteScreenEvent {
  const ByteScreenEvent();
}

class ByteScreenInitialEvent extends ByteScreenEvent {
  const ByteScreenInitialEvent(this.route);

  final String route;
}
