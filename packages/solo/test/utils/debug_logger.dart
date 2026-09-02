import 'package:conveyor/src/debug_logger.dart';

final class TestConveyorDebugLogger extends ConveyorDebugLogger {
  final String prefix;

  TestConveyorDebugLogger({
    this.prefix = '',
  });

  List<String> _log = [];

  List<String> get log {
    final log = _log;
    _log = [];

    return log;
  }

  @override
  void call(Object? message) {
    final str = messageToString(message);
    _log.add(str);
    print('$prefix$str');
  }
}
