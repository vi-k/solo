import 'dart:async';

import 'package:meta/meta.dart';

import 'debug_logger.dart';
import 'linked_list/linked_list.dart';

part 'event.dart';
part 'exceptions/cancelled.dart';
part 'external_set_state.dart';
part 'process.dart';
part 'queue.dart';
part 'result.dart';
part 'state_provider.dart';
part 'test_set_state.dart';

abstract class Conveyor<BaseState extends Object,
    Event extends ConveyorEvent<BaseState, Event, BaseState>> {
  late final ConveyorQueue<BaseState, Event> _queue;
  late final StreamController<BaseState> _stateController;

  BaseState _state;
  _ConveyorProcess<BaseState, Event>? _currentProcess;
  List<_ConveyorProcess<BaseState, Event>>? _currentProcesses;
  Completer<void>? _closeCompleter;

  Conveyor(
    BaseState initialState,
  ) : _state = initialState {
    _queue = ConveyorQueue(
      onResume: _startLoop,
      onRemove: onRemove,
    );
    _stateController = StreamController.broadcast(sync: true);
  }

  BaseState get state => _state;

  Stream<BaseState> get stream => _stateController.stream;

  bool get isClosed => _closeCompleter?.isCompleted ?? false;

  @protected
  ConveyorQueue<BaseState, Event> get queue => _queue;

  @protected
  ConveyorProcess<BaseState, Event>? get currentProcess => _currentProcess;

  @protected
  bool get inProgress => _currentProcess != null;

  void _externalSetState(BaseState newState) {
    debug('external setState: $newState');

    _setState(newState);

    final currentProcesses = _currentProcesses;
    if (currentProcesses != null) {
      for (final process in currentProcesses.reversed) {
        debug('${process.event} checkStateOnExternalChange');
        try {
          process.event.checkStateOnExternalChange(newState);
        } on Cancelled catch (reason, stackTrace) {
          debug('${process.event} checkStateOnExternalChange cancel');
          process._cancel(reason, stackTrace);
        }
      }
    }
  }

  void _setState(BaseState newState) {
    debug('state: $newState');

    final previousState = _state;
    _state = newState;
    onChanged(newState, previousState);
    _stateController.add(newState);
  }

  @mustCallSuper
  Future<void> close() async {
    var closeCompleter = _closeCompleter;
    if (closeCompleter != null) {
      return closeCompleter.future;
    }
    closeCompleter = _closeCompleter = Completer();

    debug('close');
    _queue.close();

    // При закрытии дожидаемся окончания текущего рабочего процесса.
    try {
      final currentProcess = _currentProcess;
      if (currentProcess != null) {
        debug('await process {${currentProcess.event}}');
        await currentProcess._cancel(
          const CancelledAsClosed._(),
          StackTrace.current,
        );
      }

      await _stateController.close();
    } finally {
      closeCompleter.complete();
    }
  }

  Future<void> awaitCurrentProccess() async {
    debug('awaitCurrentProccess');

    final currentProcess = _currentProcess;
    if (currentProcess != null) {
      await currentProcess.result.done;
    }
  }

  /// Запуск обработки событий, если обработка была прервана.
  void _startLoop() {
    // При добавлении событий обработка не будет запущена синхронно. Даём
    // возможность коду, добавившему события, завершить свою синхронную часть.
    scheduleMicrotask(() {
      if (_currentProcess != null) {
        return;
      }

      final event = _pull();

      if (event != null) {
        debug('run $event');
        _handle(event);
      } else {
        debug('no events');
      }
    });
  }

  void onStart(ConveyorProcess<BaseState, Event> process) {
    // debug('${process.event}${process.event.debugInfo()} started');
  }

  void onDone(ConveyorProcess<BaseState, Event> process) {
    // debug('${process.event} done');
  }

  /// Если обработка события завершается ошибкой, то [error] и [stackTrace]
  /// будут эквивалентны [ConveyorResult.error] и [ConveyorResult.stackTrace],
  ///
  /// В случае же, если ошибка возникнет в обработчике уже после отмены,
  /// результат сохранит причину отмены [ConveyorResult.isCancelled],
  /// [ConveyorResult.cancellationReason], но не возникшую ошибку. Поэтому
  /// калбэк принимает [error] и [stackTrace], чтобы они могли быть обработаны.
  void onError(
    ConveyorProcess<BaseState, Event> process,
    Object error,
    StackTrace stackTrace,
  ) {
    // debug('${process.event} error $error');
  }

  void onCancel(ConveyorProcess<BaseState, Event> process) {
    // debug(
    //   '${process.event} cancelled'
    //   ' ${process.event.result.cancellationReason}',
    // );
  }

  void onRemove(Event event) {
    // debug('$event removed ${event.result.cancellationReason}');
  }

  void onLog(
    ConveyorProcess<BaseState, Event> process,
    String message,
  ) {
    //
  }

  void onRawLog(
    ConveyorProcess<BaseState, Event> process,
    Object? message,
  ) {
    final str = message is String Function() ? message() : message.toString();
    onLog(process, str);
  }

  void onChanged(BaseState current, BaseState previous) {
    debug('$previous -> $current');
  }

  Event? get lastEvent => queue.lastOrNull ?? currentProcess?.event;

  Event? lastEventWhere(bool Function(Event event) test) =>
      queue.lastWhereOrNull(test) ?? currentProcess?.checkEvent(test);

  MaybeEvent addEventOrDrop<MaybeEvent extends Event?>({
    required bool Function(Event event) check,
    required MaybeEvent Function() create,
    bool returnPreviousIfExists = false,
  }) {
    final lastEvent = lastEventWhere(check);

    if (lastEvent != null && returnPreviousIfExists) {
      return lastEvent as MaybeEvent;
    }

    final event = create();
    if (event != null) {
      queue.add(event);

      if (lastEvent != null && !returnPreviousIfExists) {
        event.unlink();
      }
    }

    return event;
  }

  Event addEventAndRestart({
    required bool Function(Event event) check,
    required Event Function() create,
  }) {
    queue.removeWhere(check);

    final currentProcess = this.currentProcess;
    if (currentProcess != null && check(currentProcess.event)) {
      currentProcess.cancel();
    }

    final event = create();
    queue.add(event);

    return event;
  }

  /// Вынимает из очереди первый элемент, соответствующий текущему состоянию.
  ///
  /// Все элементы в очереди, предшествующие искомому элементу и не
  /// соответствующие текущему состоянию, удаляются с признаком
  /// [RemovedByEventRules].
  Event? _pull() {
    if (_queue.isEmpty) {
      return null;
    }

    var nextEvent = _queue._unsafePull();
    while (nextEvent != null) {
      try {
        return nextEvent..checkStateBeforeProcessing(_state);
      } on Cancelled catch (reason, stackTrace) {
        nextEvent._result.cancel(reason, stackTrace);

        debug('event removed: $nextEvent ${nextEvent.result}');
        onRemove(nextEvent);

        nextEvent = _queue._unsafePull();
      }
    }

    return null;
  }

  void _handle(Event event) {
    late final _ConveyorProcess<BaseState, Event> process;

    process = _ConveyorProcess(
      conveyor: this,
      event: event,
      onData: (state) {
        debug('$event changed state: $state');
        _setState(state);
      },
      onFinish: () {
        _currentProcess = null;

        // После завершения процесса, удаляем все дочерние процессы, созданные
        // им (если те были созданы без использования yield* и зависли
        // в воздухе). Выбрасываем non-fatal, чтобы не прерывать процесс, т.к.
        // в целом это не мешает продолжать работу.
        final currentProcesses = _currentProcesses;
        if (currentProcesses != null) {
          currentProcesses.remove(process);

          if (currentProcesses.isNotEmpty) {
            final error = StateError(
              'Uncompleted child process(es)'
              ' ${currentProcesses.map((e) => e.event)}'
              ' was detected after the root process'
              ' ${process.event} was finished',
            );

            for (final p in currentProcesses) {
              p.cancel();
            }

            Future<void>.error(error);
          }
        }

        _currentProcesses = null;
        _startLoop();
      },
    );

    _currentProcess = process;
    _currentProcesses = [process];
  }
}
