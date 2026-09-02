import 'package:conveyor/src/conveyor.dart';

import '../../utils/debug_logger.dart';
import 'event.dart';
import 'state.dart';

final class TestConveyor extends Conveyor<TestState, TestEvent>
    with
        ExternalSetState<TestState, TestEvent>,
        TestSetState<TestState, TestEvent> {
  final log = TestConveyorDebugLogger(prefix: '[$TestConveyor] ');

  TestConveyor(super.initialState);

  @override
  void externalSetState(TestState state) {
    log('externalSetState: $state');
    super.externalSetState(state);
  }

  @override
  void testSetState(TestState state) {
    log('testSetState: $state');
    super.testSetState(state);
  }

  String _logIndent(int level) => level == 0 ? '' : '${'>' * level} ';

  @override
  void onStart(ConveyorProcess<TestState, TestEvent> process) {
    log(
      '${_logIndent(process.level)}${process.event} started',
    );
  }

  @override
  void onDone(ConveyorProcess<TestState, TestEvent> process) {
    log('${_logIndent(process.level)}${process.event} done');
  }

  @override
  void onError(
    ConveyorProcess<TestState, TestEvent> process,
    Object error,
    StackTrace stackTrace,
  ) {
    log('${_logIndent(process.level)}${process.event} error $error');
  }

  @override
  void onCancel(ConveyorProcess<TestState, TestEvent> process) {
    log(
      '${_logIndent(process.level)}${process.event} cancelled'
      ' ${process.event.result.cancellationReason}',
    );
  }

  @override
  void onRemove(TestEvent event) {
    log('$event removed ${event.result.cancellationReason}');
  }

  @override
  void onLog(
    ConveyorProcess<TestState, TestEvent<TestState>> process,
    String message,
  ) {
    log('${_logIndent(process.level)}${process.event} $message');
  }

  @override
  ConveyorQueue<TestState, TestEvent> get queue => super.queue;

  @override
  ConveyorProcess<TestState, TestEvent>? get currentProcess =>
      super.currentProcess;
}
