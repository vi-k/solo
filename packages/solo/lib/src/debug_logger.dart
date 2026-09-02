ConveyorDebugLogger debug = const NothingConveyorDebugLogger();

// ignore: one_member_abstracts
abstract base class ConveyorDebugLogger {
  const ConveyorDebugLogger();

  String messageToString(Object? message) =>
      (message is Object? Function() ? message() : message).toString();

  void call(Object? message);
}

final class NothingConveyorDebugLogger extends ConveyorDebugLogger {
  const NothingConveyorDebugLogger();

  @override
  void call(Object? message) {}
}

final class PrintConveyorDebugLogger extends ConveyorDebugLogger {
  final String prefix;

  const PrintConveyorDebugLogger({
    this.prefix = '',
  });

  @override
  void call(Object? message) {
    final str = messageToString(message);
    print('$prefix$str');
  }
}
