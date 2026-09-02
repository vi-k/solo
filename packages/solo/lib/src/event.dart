part of 'conveyor.dart';

/// Событие конвейера.
abstract base class ConveyorEvent<
    BaseState extends Object,
    Event extends ConveyorEvent<BaseState, Event, BaseState>,
    WorkingState extends BaseState> extends LinkedListItem<Event> {
  /// Событие конвейера с переданной функцией его обработки [_process].
  ///
  /// Требуемые типы:
  /// - [BaseState] и [Event] - состояние и события, с которыми работает
  ///   конвейер.
  /// - [WorkingState] - допустимое рабочее состояние (и входящее,
  ///   и промежуточное, и исходящее).
  ///
  /// Пример:
  ///
  /// ```dart
  /// final event = MyEvent<MyState, MyEvent, MyWorkingState>(
  ///   ...
  /// );
  /// ```
  ///
  /// Конвейер работает с состоянием `MyState`, являющейся основой для всех
  /// возможных состояний конвейера, но данное событие работает только
  /// с состоянием `MyWorkingState`.
  ///
  /// Дополнительно могут быть заданы калбэки, проверящие состояние на разных
  /// этапах:
  ///
  /// - [checkStateBeforeProcessing] проверяет состояние перед началом
  ///   обработки. Если подошла очередь выполнения события, а тип текущего
  ///   состояния не соответствует [WorkingState] или проверка
  ///   [checkStateBeforeProcessing] вернула `false`, событие удаляется из
  ///   очереди с признаком [RemovedByEventRules].
  ///
  ///   Пример:
  ///
  ///   ```dart
  ///   final event = MyEvent<MyState, MyEvent, MyWorkingState>(
  ///     checkStateBeforeProcessing: (state) => state.param == 42,
  ///     ...
  ///   );
  ///   ```
  ///
  ///   Событие работает только с состоянием MyWorkingState, параметр `param`
  ///   в котором равен 42.
  ///
  /// - [checkStateOnExternalChange] проверяет состояние при его изменении
  ///   извне (если такое изменение допускается в вашем конвейере). Если
  ///   состояние изменилось и тип состояния не соответствует [WorkingState]
  ///   или проверка [checkStateOnExternalChange] вернула `false`, обработка
  ///   события прерывается с признаком [CancelledByEventRules].
  ///
  ///   Пример 1:
  ///
  ///   ```dart
  ///   final event = MyEvent<MyState, MyEvent, MyWorkingState>(
  ///     checkStateOnExternalChange: (state) => state.param == 42,
  ///     ...
  ///   );
  ///   ```
  ///
  ///   Событие позволяет менять состояние извне, но только при сохранении
  ///   типа `MyWorkingState`, с которым работает событие. Параметр `param`
  ///   в этом состоянии должен быть равен 42.
  ///
  ///   Пример 2:
  ///
  ///   ```dart
  ///   final event = MyEvent<MyState, MyEvent, MyWorkingState>(
  ///     checkStateOnExternalChange: (state) => false,
  ///     ...
  ///   );
  ///   ```
  ///
  ///   Событие не позволяет менять состояние извне ни при каких
  ///   обстоятельствах. При любом изменении обработка события будет
  ///   прервана.
  ///
  /// - [checkState] - общая проверка. Используется во время обработки события
  ///   в провайдере состояния `state`, переданном внутрь обработчика
  ///   [_process], а также вместе с [checkStateBeforeProcessing] и
  ///   [checkStateOnExternalChange].
  ///
  ///   Пример 1:
  ///
  ///   ```dart
  ///   final event = MyEvent<MyState, MyEvent, MyWorkingState>(
  ///     checkState: (state) => state.param == 42,
  ///     (state) async* {
  ///       yield state.it.copyWith(param: 128);
  ///
  ///       await ...
  ///
  ///       state.it;
  ///     }
  ///     ...
  ///   );
  ///   ```
  ///
  ///   Рабочее состояние события: `MyWorkingState`. Тип будет проверяться
  ///   на каждом этапе проверок. Но помимо этого на всех этапах будет
  ///   проверяться и параметр `param` у состояния `MyWorkingState`:
  ///   и перед стартом события, и при внешних изменениях, и после yield,
  ///   и при внутренней проверке с помощью провайдера состояни `state`.
  ///   В данном случае событие установит значение `param` равным 128, но
  ///   сразу после этого прервётся.
  ///
  ///   Пример 2:
  ///
  ///   ```dart
  ///   final event = CameraEvent<CameraState, CameraEvent, CameraReadyState>(
  ///     checkStateBeforeProcessing: (state) => state.focusPointSupported
  ///         && state.exposurePointSupported,
  ///     checkState: (state) => state.param == 42,
  ///     (state) async* {
  ///       try {
  ///         // внешний процесс, меняющий состояние
  ///         await setFocusPoint(point);
  ///         // проверяем, сделал ли он то, что ждём
  ///         state.test((it) => it.focusPoint == point).check();
  ///
  ///         await setExposurePoint(point);
  ///         state.test((it) => it.exposurePoint == point).check();
  ///
  ///         yield ...
  ///       } on Cancelled {
  ///         await setAutoFocus();
  ///         rethrow;
  ///       }
  ///     }
  ///   );
  ///   ```
  ///
  ///   Установка точки в видоискателе камеры, по которой будет настраиваться
  ///   фокус и экспозиция камеры. В начале проверяется готовность камеры
  ///   к работе (состояние `CameraReadyState`) и поддержка камерой установки
  ///   точек экспозиции и фокусировки. В ином случае событие будет удалено
  ///   из очереди, не запустившись. Параметр `param` должен быть равен 42 на
  ///   всех этапах. При любой неудачной проверке работа события будет прервана
  ///   и вызван блок `on Cancelled`.
  ///
  ///   Обратие внимание, [ConveyorStateProvider.test] является участником
  ///   цепочки проверок наряду с [ConveyorStateProvider.isA],
  ///   [ConveyorStateProvider.map], и без конечного потребителя в виде
  ///   [ConveyorStateProvider.check], [ConveyorStateProvider.it] и
  ///   [ConveyorStateProvider.use] работать не будет.
  ConveyorEvent(
    this._process, {
    this.key,
    bool uncancellable = false,
    this.unkilled = false,
    bool Function(WorkingState state)? checkStateBeforeProcessing,
    bool Function(WorkingState state)? checkStateOnExternalChange,
    bool Function(WorkingState state)? checkState,
    String Function()? debugInfo,
  })  : assert(
          !uncancellable || !unkilled,
          'Only `uncancellable` or `unkilled` can be set',
        ),
        uncancellable = uncancellable || unkilled,
        _checkStateBeforeProcessing = checkStateBeforeProcessing,
        _checkStateOnExternalChange = checkStateOnExternalChange,
        _checkState = checkState,
        _debugInfo = debugInfo,
        _result = _ConveyorResult() {
    assert(this is Event, 'The event type must be $Event');

    final classType = '$runtimeType';
    final genericTypeStart = classType.indexOf('<');
    _classType = genericTypeStart == -1
        ? classType
        : classType.substring(0, genericTypeStart);
  }

  final Stream<WorkingState> Function(
    RootConveyorStateProvider<BaseState, Event, WorkingState> state,
  ) _process;

  final Object? key;

  /// Событие нельзя отменить, если оно уже запущено на обработку.
  final bool uncancellable;

  /// Событие нельзя ни удалить из очереди, ни отменить во время обработки.
  ///
  /// Если [unkilled] установлен, [uncancellable] устанавливается автоматически.
  final bool unkilled;

  final bool Function(WorkingState state)? _checkStateBeforeProcessing;

  final bool Function(WorkingState state)? _checkStateOnExternalChange;

  final bool Function(WorkingState state)? _checkState;

  final String Function()? _debugInfo;

  final _ConveyorResult _result;

  late final String _classType;

  ConveyorResult get result => _result;

  /// Проверяет состояние перед запуском обработки события.
  void checkStateBeforeProcessing(BaseState state) {
    if (state is! WorkingState) {
      throw RemovedByEventRules._('is not $WorkingState');
    }

    final checkStateBeforeProcessing = _checkStateBeforeProcessing;
    if (checkStateBeforeProcessing != null &&
        !checkStateBeforeProcessing(state)) {
      throw const RemovedByEventRules._('checkStateBeforeProcessing');
    }

    final checkState = _checkState;
    if (checkState != null && !checkState(state)) {
      throw const RemovedByEventRules._('checkState');
    }
  }

  /// Проверяет состояние при внешнем изменении.
  void checkStateOnExternalChange(BaseState state) {
    if (state is! WorkingState) {
      throw CancelledByEventRules._('is not $WorkingState');
    }

    final checkStateOnExternalChange = _checkStateOnExternalChange;
    if (checkStateOnExternalChange != null &&
        !checkStateOnExternalChange(state)) {
      throw const CancelledByEventRules._('checkStateOnExternalChange');
    }

    final checkState = _checkState;
    if (checkState != null && !checkState(state)) {
      throw const CancelledByEventRules._('checkState');
    }
  }

  /// Запуск обработки события.
  ///
  /// В калбэк обработки события для проверки и возврата состояния передаётся
  /// провайдер состояния [ConveyorStateProvider] для доступа к состоянию
  /// конвейера.
  (RootConveyorStateProvider<BaseState, Event, BaseState>, Stream<WorkingState>)
      _run(
    Conveyor<BaseState, Event> conveyor,
    ConveyorProcess<BaseState, Event> process,
  ) {
    final stateProvider =
        RootConveyorStateProvider<BaseState, Event, WorkingState>(
      conveyor,
      process,
      _checkState,
    );

    return (stateProvider, _process(stateProvider));
  }

  String debugInfo() => _debugInfo?.call() ?? '';

  @override
  String toString() => '$_classType(${key == null ? '' : '$key'})';
}
