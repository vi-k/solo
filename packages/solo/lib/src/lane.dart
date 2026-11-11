part of 'solo.dart';

/// What a [SoloJob] says of the lane it runs in.
///
/// Two lanes differ by identity, not by name: the name is what the lane was
/// declared with, for logs, and [toString] gives it. Only a lane makes one,
/// so a fake cannot pass for a lane.
final class SoloLaneId {
  /// The name the lane was declared with.
  final String name;

  SoloLaneId._(this.name);

  @override
  String toString() => name;
}

/// A lane of a [SoloLanes]: its own queue of root jobs, run one at a time.
///
/// The members are those of the queue of a [Solo], and they are public:
/// whoever holds the lane queues jobs in it, so a controller keeps its lanes
/// in private fields. A job runs in the lane that queued it; one made by
/// another lane or another controller is refused. A lane has no `close` or
/// `cancelAll`: [queue] and [current] give both for one lane.
abstract interface class SoloLane<S extends Object> {
  /// The name the lane was declared with in [SoloLanes.lane].
  String get name;

  /// What a job of this lane says in [SoloJob.lane].
  SoloLaneId get id;

  /// Creates a job of this lane without queueing it, as [Solo.job] does.
  SoloJob<T> job<W extends S, T>(
    Future<T> Function(SoloContext<S, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    Duration? timeout,
    String Function()? describe,
    S Function(S state, Object error, StackTrace stackTrace)? ifFailed,
    bool Function(Object error)? isExpectedError,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  });

  /// Queues [job] in this lane, as [Solo.enqueueJob] queues it in a [Solo].
  ///
  /// Throws what [Solo.enqueueJob] throws, and [ArgumentError] for a job
  /// made by another lane or another controller. A [Policy] looks for its
  /// key in this lane only.
  SoloJob<T> enqueueJob<T>(
    Job<T> job, {
    bool first = false,
    Policy policy = Policy.sequential,
  });

  /// `enqueueJob(job(...), policy: policy)` in one call, as [Solo.enqueue].
  SoloJob<T> enqueue<W extends S, T>(
    Future<T> Function(SoloContext<S, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    Duration? timeout,
    String Function()? describe,
    Policy policy = Policy.sequential,
    S Function(S state, Object error, StackTrace stackTrace)? ifFailed,
    bool Function(Object error)? isExpectedError,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  });

  /// Creates an accumulator whose groups go into this lane, as
  /// [Solo.collect].
  SoloAccumulator<E, T> collect<W extends S, E, T>(
    Future<T> Function(SoloContext<S, W> ctx, List<E> events) handler, {
    Object? key,
    AccumulationPolicy policy = AccumulationPolicy.join,
    AccumulationTiming? timing,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    Duration? timeout,
    String Function()? describe,
    S Function(S state, Object error, StackTrace stackTrace)? ifFailed,
    bool Function(Object error)? isExpectedError,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  });

  /// Creates an accumulator of one merged value whose groups go into this
  /// lane, as [Solo.accumulate].
  SoloAccumulator<E, T> accumulate<W extends S, E, T>(
    Future<T> Function(SoloContext<S, W> ctx, E value) handler, {
    required E Function(E accumulated, E incoming) merge,
    Object? key,
    AccumulationPolicy policy = AccumulationPolicy.join,
    AccumulationTiming? timing,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    Duration? timeout,
    String Function()? describe,
    S Function(S state, Object error, StackTrace stackTrace)? ifFailed,
    bool Function(Object error)? isExpectedError,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  });

  /// The jobs waiting in this lane.
  SoloQueue get queue;

  /// The running root job of this lane, or `null` when it is idle.
  SoloJob<Object?>? get current;

  /// The last job of this lane matching [test], as [Solo.lastJobWhere].
  SoloJob<Object?>? lastJobWhere(bool Function(SoloJob<Object?> job) test);

  /// What is holding this lane right now, as [SoloController.pending] says
  /// it for a [Solo], or `null`.
  SoloPending? get pending;
}

final class _SoloLane<S extends Object> implements SoloLane<S> {
  final SoloLanes<S> _controller;
  final _SoloLaneCore<S> _core;

  _SoloLane(this._controller, String name)
    : _core = _SoloLaneCore<S>(_controller, name: name) {
    _core.lane = this;
  }

  @override
  String get name => id.name;

  @override
  SoloLaneId get id => _core.id!;

  @override
  SoloJob<T> job<W extends S, T>(
    Future<T> Function(SoloContext<S, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    Duration? timeout,
    String Function()? describe,
    S Function(S state, Object error, StackTrace stackTrace)? ifFailed,
    bool Function(Object error)? isExpectedError,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  }) => _controller._makeJob<W, T>(
    _core,
    body,
    key: key,
    canStart: canStart,
    keepWhile: keepWhile,
    cancellable: cancellable,
    timeout: timeout,
    describe: describe,
    ifFailed: ifFailed,
    isExpectedError: isExpectedError,
    ifCancelled: ifCancelled,
  );

  @override
  SoloJob<T> enqueueJob<T>(
    Job<T> job, {
    bool first = false,
    Policy policy = Policy.sequential,
  }) {
    // Whatever comes of the call, a refusal included: from the first job on,
    // the set of lanes is what the pump walks.
    _controller._sealed ??= _Sealed.enqueue;
    if (job is! _SoloJob<S, S, T> || !identical(job._destination, _core)) {
      throw ArgumentError.value('$job', 'job', _notCreatedByLane);
    }
    return _controller._enqueueIn(_core, job, first: first, policy: policy);
  }

  @override
  SoloJob<T> enqueue<W extends S, T>(
    Future<T> Function(SoloContext<S, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    Duration? timeout,
    String Function()? describe,
    Policy policy = Policy.sequential,
    S Function(S state, Object error, StackTrace stackTrace)? ifFailed,
    bool Function(Object error)? isExpectedError,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  }) => enqueueJob(
    job<W, T>(
      body,
      key: key,
      canStart: canStart,
      keepWhile: keepWhile,
      cancellable: cancellable,
      timeout: timeout,
      describe: describe,
      ifFailed: ifFailed,
      isExpectedError: isExpectedError,
      ifCancelled: ifCancelled,
    ),
    policy: policy,
  );

  @override
  SoloAccumulator<E, T> collect<W extends S, E, T>(
    Future<T> Function(SoloContext<S, W> ctx, List<E> events) handler, {
    Object? key,
    AccumulationPolicy policy = AccumulationPolicy.join,
    AccumulationTiming? timing,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    Duration? timeout,
    String Function()? describe,
    S Function(S state, Object error, StackTrace stackTrace)? ifFailed,
    bool Function(Object error)? isExpectedError,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  }) => _controller._collectIn<W, E, T>(
    _core,
    handler,
    key: key,
    policy: policy,
    timing: timing,
    canStart: canStart,
    keepWhile: keepWhile,
    cancellable: cancellable,
    timeout: timeout,
    describe: describe,
    ifFailed: ifFailed,
    isExpectedError: isExpectedError,
    ifCancelled: ifCancelled,
  );

  @override
  SoloAccumulator<E, T> accumulate<W extends S, E, T>(
    Future<T> Function(SoloContext<S, W> ctx, E value) handler, {
    required E Function(E accumulated, E incoming) merge,
    Object? key,
    AccumulationPolicy policy = AccumulationPolicy.join,
    AccumulationTiming? timing,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    Duration? timeout,
    String Function()? describe,
    S Function(S state, Object error, StackTrace stackTrace)? ifFailed,
    bool Function(Object error)? isExpectedError,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  }) => _controller._accumulateIn<W, E, T>(
    _core,
    handler,
    merge: merge,
    key: key,
    policy: policy,
    timing: timing,
    canStart: canStart,
    keepWhile: keepWhile,
    cancellable: cancellable,
    timeout: timeout,
    describe: describe,
    ifFailed: ifFailed,
    isExpectedError: isExpectedError,
    ifCancelled: ifCancelled,
  );

  @override
  SoloQueue get queue => _core.queue;

  @override
  SoloJob<Object?>? get current => _core.current;

  @override
  SoloJob<Object?>? lastJobWhere(bool Function(SoloJob<Object?> job) test) =>
      _controller._lastJobWhereIn(_core, test);

  @override
  SoloPending? get pending => _controller._pendingOf(_core);

  @override
  String toString() => 'SoloLane($name)';
}

/// What a controller keeps once for every line of its root jobs: the queue,
/// the running root job and the job whose start rules are being asked.
///
/// A [Solo] has exactly one, and a [SoloLanes] one for each lane. Everything
/// else — the state, the pump, the listeners, the timers and closing —
/// belongs to the [controller] and is shared by its cores.
final class _SoloLaneCore<S extends Object> {
  /// The controller whose pump steps this core.
  final SoloController<S> controller;

  /// The lane this core is, for a lane of a [SoloLanes]; `null` for the core
  /// of a [Solo].
  final SoloLaneId? id;

  /// The face a lane of a [SoloLanes] shows; `null` for the core of a
  /// [Solo].
  _SoloLane<S>? lane;

  /// The root jobs waiting for this core.
  late final _SoloQueue<S> queue = _SoloQueue<S>(this);

  /// The running root job of this core.
  _SoloJob<S, S, Object?>? current;

  /// The job the pump holds while it asks its start rules: taken off the
  /// queue, not started, not yet [current].
  ///
  /// The rules are the caller's code and may cancel everything or close
  /// the controller, and in that window neither the queue nor [current]
  /// leads to this job. It is queued work until it is launched, and this
  /// is what says so.
  _SoloJob<S, S, Object?>? inTransition;

  _SoloLaneCore(this.controller, {required String? name})
    : id = name == null ? null : SoloLaneId._(name);

  /// What the debug lines call this core; `null` for the core of a [Solo].
  String? get name => id?.name;

  /// [line] as [Solo.debug] prints it for this core: a lane puts its name in
  /// front, the one core of a [Solo] says it as it is.
  String said(String line) {
    final name = this.name;
    return name == null ? line : '$name: $line';
  }
}
