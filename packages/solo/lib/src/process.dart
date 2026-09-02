part of 'conveyor.dart';

abstract interface class ConveyorProcess<BaseState extends Object,
    Event extends ConveyorEvent<BaseState, Event, BaseState>> {
  /// Уровень процесса.
  ///
  /// 0 - корневой, запускается напрямую из конвейера.
  /// 1-n - процессы, запускаемые из других процессов.
  int get level;

  /// Корневой процесс.
  bool get isRoot;

  /// Процесс-потомок.
  bool get isChild;

  /// Обрабатываемое событие.
  Event get event;

  /// Запущен ли процесс.
  bool get inProgress;

  /// Возможность дождаться окончания процесса.
  ConveyorResult get result;

  /// Отмена процесса.
  ///
  /// Дожидается его реального завершения.
  Future<void> cancel();

  /// Проверка события, обрабатываемого процессом.
  ///
  /// Возвращает событие, если проверка прошла успешно, и `null`, если [test]
  /// вернул `false`.
  Event? checkEvent(bool Function(Event event) test);
}

class _ConveyorProcess<BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>>
    implements ConveyorProcess<BaseState, Event> {
  final Conveyor<BaseState, Event> conveyor;

  @override
  final int level;

  @override
  final Event event;

  final void Function(BaseState state) onData;

  final void Function() onFinish;

  late final RootConveyorStateProvider<BaseState, Event, BaseState>
      _stateProvider;
  StreamSubscription<BaseState>? _subscription;
  Future<void>? _cancelFuture;

  _ConveyorProcess({
    required this.conveyor,
    required this.event,
    required this.onData,
    required this.onFinish,
    this.level = 0,
  }) {
    _start();
  }

  @override
  bool get isRoot => level == 0;

  @override
  bool get isChild => level != 0;

  @override
  bool get inProgress => _subscription != null;

  @override
  ConveyorResult get result => event.result;

  void _start() {
    conveyor.onStart(this);
    debug('$event started');

    final (stateProvider, stream) = event._run(conveyor, this);
    _stateProvider = stateProvider;

    _subscription = stream.listen(
      (state) {
        try {
          debug(() => '$event yield: check current state');
          _stateProvider.check();
        } on Cancelled catch (reason, stackTrace) {
          _cancel(reason, stackTrace);
          return;
        }

        try {
          debug(() => '$event yield: check new state');
          stateProvider._checkState(state);
        } on Cancelled catch (reason, stackTrace) {
          _cancel(reason, stackTrace);
          return;
        }

        onData(state);
      },
      // ignore: avoid_types_on_closure_parameters
      onError: (Object error, StackTrace stackTrace) async {
        await _subscription?.cancel();
        _subscription = null;
        if (error is Cancelled) {
          event._result.cancel(error, stackTrace);
          debug('$event cancelled: $error');
          conveyor.onCancel(this);
        } else {
          event._result.completeError(error, stackTrace);
          debug('$event failed: $error');
          conveyor.onError(this, error, stackTrace);
        }
        onFinish();
      },
      onDone: () {
        _subscription = null;
        event._result.complete();
        debug('$event done');
        conveyor.onDone(this);
        onFinish();
      },
      cancelOnError: true,
    );
  }

  @override
  Future<void> cancel() async {
    await _cancel(
      const CancelledManually._(),
      StackTrace.current,
    );
  }

  @override
  Event? checkEvent(bool Function(Event event) test) =>
      test(event) ? event : null;

  Future<void> _cancel(Cancelled reason, StackTrace stackTrace) async {
    if (event.uncancellable) {
      debug("$event can't be cancelled");
      return;
    }

    final cancelFuture = _cancelFuture;
    if (cancelFuture != null) {
      await cancelFuture;
      return;
    }

    final subscription = _subscription;
    if (subscription == null) {
      return;
    }

    debug('$event start cancellation: $reason');

    // Начинаем отмену: срабатывает [ConveyorResult.onCancelled].
    event._result.cancelStart(reason, stackTrace);

    final future = subscription.cancel().onError<Object>(
      (error, stackTrace) {
        if (error is! Cancelled) {
          conveyor.onError(this, error, stackTrace);
        }
      },
    );
    _cancelFuture = future;

    await future;
    _cancelFuture = null;

    // Завершаем выполнение: срабатывает [ConveyorResult.done].
    _subscription = null;
    event._result.cancelFinish();
    onFinish();
    conveyor.onCancel(this);
    debug('$event finish cancellation');
  }
}
