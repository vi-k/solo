// ignore_for_file: use_to_and_as_if_applicable

part of 'conveyor.dart';

/// Провайдер, предоставляющий доступ к состонию конвейера изнутри обработчика
/// события.
///
/// Передаётся внутрь обработчика с названием `state`, чтобы убедить
/// разработчика пользоваться именно им, а не использовать напрямую геттер
/// [Conveyor.state].
///
/// ## Потребители
///
/// Провайдер даёт возможность рабоать с состоянием через потребители: [it],
/// [use] и [check]. Их основная задача - проверить состояние на соответствие
/// правилам события и на то, что процесс обработки ещё не отменён извне. Если
/// правила нарушены, процесс отменяется. Если процесс отменён, обработчик
/// вызывает исключение [Cancelled] и прерывает работу. Обработка исключения
/// находится полностью под капотом и наружу не выходит. Результат события
/// [ConveyorEvent.result] оповестит об отмене через флаг
/// [ConveyorResult.isCancelled]. Причина отмены сохранится в параметре
/// [ConveyorResult.cancellationReason], стейктрейс в
/// [ConveyorResult.stackTrace].
///
/// Предполагается, что состояние конвейера может измениться извне через
/// [Conveyor._externalSetState] (см. расширение [ExternalSetState]). В этом
/// случае обработчик события, правила которого не соответствуют изменённому
/// состоянию, будет отменён. Но отмена процесса предполагает только то, что
/// данные, которые yield-ит событие, не будут восприняты. Сам же процесс
/// может прерваться только на ближайшем `yield` (таковы правила работы
/// асинхронных генераторов в дарте). До этого он будет продолжать работать.
/// Что, как минимум, будет излишне занимать ресурсы устройства. А как
/// максимум, может привести к ошибкам работы с тем оборудованием, которое
/// изменяет состояние извне: состояние оборудования изменилось, но обработчик
/// продолжает работать с ним, ничего не зная об этом изменении.
///
/// [it], [use] и [check], с одной стороны, всегда предоставляют актуальное
/// состояние конвейера. А с другой стороны, прерывают процесс изнутри (только
/// изнутри он и может быть прерван), если состояние конвейера не соответсвует
/// правилам события.
///
/// - [it] - прямой доступ к значению состояния.
///
///   ```dart
///   MyEvent<MyWorkingState>(
///     (state) async* {
///       final param = state.it.param;
///       ...
///       yield state.it.copyWith(param: 42);
///     },
///   );
///   ```
///
///   [it] проверит, что тип состояния на соответствие типу `MyWorkingState`.
///   Если тип состояния изменился, обработчик будет прерван. Таким образом, мы
///   гарантировано через [it] получим доступ ко всем свойствам состояния
///   `MyWorkingState`. Нам не нужно будет делать дополнительные проверки и
///   писать условия.
///
/// - [use] - доступ к состоянию с целью его более сложной обработки.
///
///   ```dart
///   MyEvent<MyWorkingState>(
///     (state) async* {
///       final (param1, param2) = state.use((it) => (it.param1, it.param2));
///       ...
///       yield state.use((it) => it.copyWith(param: it.param + 1));
///     },
///   );
///   ```
///
/// - [check] - только проверка состояния. не возвращает значение.
///
///   ```dart
///   MyEvent<MyWorkingState>(
///     (state) async* {
///       await myEquipment.process1();
///       state.check();
///
///       await myEquipment.process2();
///       state.check();
///
///       await myEquipment.process3();
///       state.check();
///     },
///   );
///   ```
///
/// ## Трансформеры
///
/// Провайдеры позволяет создавать цепочку дял проверки и преобразования
/// состояния.
///
/// - [test] - проверка состояния с помощью переданного калбэка.
/// - [isA] - проверка состояния на соответствие типу.
/// - [map] - преобразование состояния.
///
///   ```dart
///   MyEvent<MyState>(
///     (state) async* {
///       yield state
///         .isA<MyWorkingState>()
///         .test((it) => it.param == 42)
///         .map((it) = it.copyWith(param: 43))
///         .it;
///     },
///   );
///   ```
///
///   Обратите внимание, что цепочка провайдеров должна заканчиваться
///   потребителем [it], [use] или [check]. `state.test(...);` и
///   `state.isA...<>();` без потребителя не осуществят проверку. Если вам
///   нужна только проверка без получения значения, добавьте в цепочку [check].
///
/// ## Запуск другого события.
///
/// Провайдер даёт возможность запускать вложенное (дочернее) событие изнутри
/// процесса.
///
///   ```dart
///   MyEvent<MyState>(
///     (state) async* {
///       final childEvent = ...;
///       yield* state.run(childEvent);
///     },
///   );
///   ```
///
///   Только важно не забыть добавить `yield*` для передачи событий из
///   `childEvent`, иначе вы запустите неконтроллируемый процесс, который
///   что-то делает, но никуда не передаёт результаты своей работы.
///
/// Может показаться немного странным использование `state` для запуска
/// событий. Но первоначальная причина этого в том, чтобы дать возможность
/// запускать события только изнутри обработчика события. И чтобы для этого
/// не передавать ещё дополнительные параметры в обработчик наряду со `state`.
/// При таких широких возможностях провайдера, кажется, лучше было бы `state`
/// назвать `context`, как это сделано в других системах. Но, как сказано выше,
/// желание переключить разработчика с прямого доступка к состоянию
/// [Conveyor.state] на [ConveyorStateProvider] оказалось сильнее.
abstract base class ConveyorStateProvider<
    BaseState extends Object,
    Event extends ConveyorEvent<BaseState, Event, BaseState>,
    OutState extends BaseState> {
  Conveyor<BaseState, Event> get _conveyor;

  ConveyorProcess<BaseState, Event> get process;

  /// Значения состояния, пройденное через всю цепочку провайдеров.
  OutState get it;

  /// Доступ к состоянию, пройденному через всю цепочку провайдеров.
  T use<T>(T Function(OutState it) callback) => callback(it);

  /// Проверка состояния через всю цепочку трансформеров.
  void check() {
    it;
  }

  /// Проверяет состояние на заданное условие.
  ConveyorStateProvider<BaseState, Event, OutState> test(
    bool Function(OutState it) test,
  ) =>
      _TestConveyorStateProvider(this, test);

  /// Проверяет тип состояния.
  ConveyorStateProvider<BaseState, Event, CastState> isA<
          CastState extends BaseState>() =>
      _IsAConveyorStateProvider<BaseState, Event, OutState, CastState>(this);

  /// Заменяет состояние новым.
  ConveyorStateProvider<BaseState, Event, CastState>
      map<CastState extends BaseState>(
    CastState Function(OutState it) callback,
  ) =>
          _MapConveyorStateProvider(this, callback);
}

/// Корневой провайдер, напрямую предоставляющий доступ к состоянию конвейера.
final class RootConveyorStateProvider<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>,
        OutState extends BaseState>
    extends ConveyorStateProvider<BaseState, Event, OutState> {
  @override
  final Conveyor<BaseState, Event> _conveyor;

  @override
  final ConveyorProcess<BaseState, Event> process;

  final bool Function(OutState)? _userCheckState;

  RootConveyorStateProvider(
    this._conveyor,
    this.process,
    this._userCheckState,
  );

  ConveyorResult get result => process.event.result;

  OutState _checkState(BaseState state) {
    if (state is! OutState) {
      throw CancelledByEventRules._('is not $OutState');
    }

    final userCheckState = _userCheckState;
    if (userCheckState != null && !userCheckState(state)) {
      throw const CancelledByEventRules._('checkState');
    }

    return state;
  }

  @override
  OutState get it => _checkState(_conveyor.state);

  void log(Object? message) {
    _conveyor.onRawLog(process, message);
  }

  /// Запуск события.
  Stream<OutState> run(Event event) {
    try {
      event.checkStateBeforeProcessing(_conveyor.state);
    } on Cancelled catch (reason, stackTrace) {
      event._result.cancel(reason, stackTrace);
      _conveyor.onRemove(event);

      check();

      return const Stream.empty();
    }

    late final _ConveyorProcess<BaseState, Event> childProcess;
    final streamController = StreamController<OutState>(
      sync: true,
      onCancel: () => childProcess._cancel(
        const CancelledByParent._(),
        StackTrace.current,
      ),
    );

    childProcess = _ConveyorProcess(
      conveyor: _conveyor,
      level: process.level + 1,
      event: event,
      onData: (state) {
        if (state is OutState) {
          debug('$event sent state');
          streamController.add(state);
        } else {
          final reason = CancelledByEventRules._('is not $OutState');
          debug('$event sent $reason');
          streamController.addError(reason, StackTrace.current);
        }
      },
      onFinish: () {
        if (!streamController.isClosed) {
          try {
            check();
          } on Object catch (error, stackTrace) {
            streamController.addError(error, stackTrace);
          }
          streamController.close();
        }

        final currentProcesses = _conveyor._currentProcesses;
        if (currentProcesses != null) {
          currentProcesses.remove(childProcess);
        }
      },
    );

    final currentProcesses = _conveyor._currentProcesses;
    if (currentProcesses != null) {
      currentProcesses.add(childProcess);
    }

    return streamController.stream;
  }
}

/// Основа для трансформеров.
abstract base class _BaseConveyorStateTransformer<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>,
        WorkingState extends BaseState,
        OutState extends BaseState>
    extends ConveyorStateProvider<BaseState, Event, OutState> {
  final ConveyorStateProvider<BaseState, Event, BaseState> _previous;

  @override
  final Conveyor<BaseState, Event> _conveyor;

  @override
  final ConveyorProcess<BaseState, Event> process;

  _BaseConveyorStateTransformer(this._previous)
      : _conveyor = _previous._conveyor,
        process = _previous.process;

  @override
  OutState get it {
    final state = _previous.it;

    return state is OutState
        ? state
        : throw CancelledByCheckState._('is not $OutState');
  }
}

final class _TestConveyorStateProvider<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>,
        WorkingState extends BaseState>
    extends _BaseConveyorStateTransformer<BaseState, Event, WorkingState,
        WorkingState> {
  final bool Function(WorkingState state) _test;

  _TestConveyorStateProvider(super._previous, this._test);

  @override
  WorkingState get it {
    final state = super.it;
    if (!_test(state)) {
      throw const CancelledByCheckState._('test');
    }

    return state;
  }
}

final class _IsAConveyorStateProvider<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>,
        WorkingState extends BaseState,
        OutState extends BaseState>
    extends _BaseConveyorStateTransformer<BaseState, Event, WorkingState,
        OutState> {
  _IsAConveyorStateProvider(super._previous);
}

final class _MapConveyorStateProvider<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>,
        WorkingState extends BaseState,
        OutState extends BaseState>
    extends _BaseConveyorStateTransformer<BaseState, Event, WorkingState,
        OutState> {
  final OutState Function(WorkingState state) _callback;

  _MapConveyorStateProvider(super._previous, this._callback);

  @override
  OutState get it {
    final state = _previous.it;

    return state is WorkingState
        ? _callback(state)
        : throw CancelledByCheckState._('is not $WorkingState');
  }
}
