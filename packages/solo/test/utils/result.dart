import 'package:conveyor/conveyor.dart';

extension ConveyorResultExt on ConveyorResult {
  void saveToResults(
    String name,
    List<(String, ConveyorResult)> results,
  ) {
    results.add((name, this));
  }
}

extension ConveyorEventExt on ConveyorEvent {
  void saveToResults(
    List<(String, ConveyorResult)> results, [
    String postfix = '',
  ]) {
    results.add(('$this$postfix', result));
  }
}
