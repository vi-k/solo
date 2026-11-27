part of 'solo.dart';

/// What a [SoloJob] says of the lane it runs in.
///
/// Two lanes differ by identity, not by name: the name is what the lane was
/// declared with, for logs, and [toString] gives it. Only a lane makes one,
/// so a fake cannot pass for a lane.
///
/// See [Declaring lanes](https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#declaring-lanes)
/// on the lanes page.
final class SoloLaneId {
  /// The name the lane was declared with.
  final String name;

  SoloLaneId._(this.name);

  @override
  String toString() => name;
}

/// What a lane and a pool of a [SoloLanes] have in common: a queue of root
/// jobs and the members that make jobs and queue them.
///
/// Code that reads neither [SoloLane.current] nor [SoloPool.running] takes
/// this type and accepts both. Whoever holds the lane or pool queues jobs in
/// it, so a controller keeps them in private fields. A job runs in the lane
/// or pool that queued it; one made by another lane or pool, or by another
/// controller, is refused.
///
/// See [Declaring lanes](https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#declaring-lanes)
/// on the lanes page.
abstract interface class SoloQueueOwner<S extends Object> {
  /// The name the lane or pool was declared with in [SoloLanes.lane] or
  /// [SoloLanes.pool].
  String get name;

  /// What a job of this lane or pool says in [SoloJob.lane].
  SoloLaneId get id;

  /// Creates a job of this lane or pool without queueing it, as [Solo.job]
  /// does.
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

  /// Queues [job] in this lane or pool, as [Solo.enqueueJob] queues it in a
  /// [Solo].
  ///
  /// Throws what [Solo.enqueueJob] throws, and [ArgumentError] for a job
  /// made by another lane or pool, or by another controller. A [Policy]
  /// looks for its key in this lane or pool only.
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

  /// Creates an accumulator whose groups go into this lane or pool, as
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
  /// lane or pool, as [Solo.accumulate].
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

  /// The jobs waiting in this lane or pool.
  SoloQueue get queue;

  /// The last job of this lane or pool matching [test], as
  /// [Solo.lastJobWhere].
  SoloJob<Object?>? lastJobWhere(bool Function(SoloJob<Object?> job) test);

  /// What is holding this lane or pool right now, or `null`: a lane says it
  /// as [SoloController.pending] does for a [Solo], a pool as a
  /// [SoloPendingLanes] of its own entries however many jobs run in it, one
  /// for each running job and one for its queue when the queue holds it.
  SoloPending? get pending;
}

/// A lane of a [SoloLanes]: its own queue of root jobs, run one at a time.
///
/// The members are those of the queue of a [Solo], and they are public:
/// whoever holds the lane queues jobs in it, so a controller keeps its lanes
/// in private fields. A job runs in the lane that queued it; one made by
/// another lane or another controller is refused. A lane has no `close` or
/// `cancelAll`: [queue] and [current] give both for one lane.
///
/// See [Two queues over one state](https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#two-queues-over-one-state)
/// on the lanes page.
abstract interface class SoloLane<S extends Object>
    implements SoloQueueOwner<S> {
  /// The name the lane was declared with in [SoloLanes.lane].
  @override
  String get name;

  /// What a job of this lane says in [SoloJob.lane].
  @override
  SoloLaneId get id;

  /// Creates a job of this lane without queueing it, as [Solo.job] does.
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
  });

  /// Queues [job] in this lane, as [Solo.enqueueJob] queues it in a [Solo].
  ///
  /// Throws what [Solo.enqueueJob] throws, and [ArgumentError] for a job
  /// made by another lane or another controller. A [Policy] looks for its
  /// key in this lane only.
  @override
  SoloJob<T> enqueueJob<T>(
    Job<T> job, {
    bool first = false,
    Policy policy = Policy.sequential,
  });

  /// `enqueueJob(job(...), policy: policy)` in one call, as [Solo.enqueue].
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
  });

  /// Creates an accumulator whose groups go into this lane, as
  /// [Solo.collect].
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
  });

  /// Creates an accumulator of one merged value whose groups go into this
  /// lane, as [Solo.accumulate].
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
  });

  /// The jobs waiting in this lane.
  @override
  SoloQueue get queue;

  /// The running root job of this lane, or `null` when it is idle.
  SoloJob<Object?>? get current;

  /// The last job of this lane matching [test], as [Solo.lastJobWhere].
  @override
  SoloJob<Object?>? lastJobWhere(bool Function(SoloJob<Object?> job) test);

  /// What is holding this lane right now, as [SoloController.pending] says
  /// it for a [Solo], or `null`.
  @override
  SoloPending? get pending;
}

/// A pool of a [SoloLanes]: one queue of root jobs, up to [concurrency] of
/// them running at once.
///
/// The members of the queue are those of a lane, and [running] takes the
/// place of [SoloLane.current]. A key keeps the order of its jobs here even
/// under [Policy.sequential]: two jobs of one key never run at once, and
/// the later waits for the earlier to end. A child of a running job takes
/// no place; [concurrency] counts the root jobs.
///
/// See [Declaring lanes](https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#declaring-lanes)
/// on the lanes page.
abstract interface class SoloPool<S extends Object>
    implements SoloQueueOwner<S> {
  /// How many root jobs of this pool run at once at most, as declared in
  /// [SoloLanes.pool].
  int get concurrency;

  /// The running root jobs of this pool in the order they started, an
  /// unmodifiable snapshot taken at the read; empty when the pool is idle.
  List<SoloJob<Object?>> get running;
}

/// What a lane and a pool share: every member of [SoloQueueOwner], over the
/// one core each of them is.
abstract class _SoloQueueFace<S extends Object> implements SoloQueueOwner<S> {
  final SoloLanes<S> _controller;
  final _SoloLaneCore<S> _core;

  _SoloQueueFace(this._controller, this._core) {
    _core.lane = this;
  }

  /// What [enqueueJob] says of a job another lane or pool, or another
  /// controller, made, the fix included.
  String get _notCreatedByThis;

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
    // Whatever comes of the call, a refusal included: from the first
    // `enqueueJob` call on, the set of lanes is what the pump walks.
    _controller._sealed ??= _Sealed.enqueue;
    if (job is! _SoloJob<S, S, T> || !identical(job._destination, _core)) {
      throw ArgumentError.value('$job', 'job', _notCreatedByThis);
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
  SoloJob<Object?>? lastJobWhere(bool Function(SoloJob<Object?> job) test) =>
      _controller._lastJobWhereIn(_core, test);

  @override
  SoloPending? get pending => _controller._pendingOf(_core);
}

final class _SoloLane<S extends Object> extends _SoloQueueFace<S>
    implements SoloLane<S> {
  _SoloLane(SoloLanes<S> controller, String name)
    : super(controller, _SoloLaneCore<S>(controller, name: name));

  @override
  String get _notCreatedByThis => _notCreatedByLane;

  @override
  SoloJob<Object?>? get current => _core.current;

  @override
  String toString() => 'SoloLane($name)';
}

final class _SoloPool<S extends Object> extends _SoloQueueFace<S>
    implements SoloPool<S> {
  final _SoloPoolCore<S> _pool;

  _SoloPool(SoloLanes<S> controller, String name, {required int concurrency})
    : this._(
        controller,
        _SoloPoolCore<S>(controller, name: name, concurrency: concurrency),
      );

  _SoloPool._(SoloLanes<S> controller, this._pool) : super(controller, _pool);

  @override
  String get _notCreatedByThis => _notCreatedByPool;

  @override
  int get concurrency => _pool.concurrency;

  @override
  List<SoloJob<Object?>> get running =>
      List<SoloJob<Object?>>.unmodifiable(_pool.running);

  // The entries of this pool as the controller lists them: one running job
  // is a `SoloPendingLanes` as several are, so the shape does not depend on
  // how many jobs run.
  @override
  SoloPending? get pending {
    final entries = _controller._pendingEntriesOf(_pool);
    return entries.isEmpty
        ? null
        : SoloPendingLanes(List<SoloPendingLane>.unmodifiable(entries));
  }

  @override
  String toString() => 'SoloPool($name)';
}

/// What a controller keeps once for every line of its root jobs: the queue,
/// the running root job and the job whose start rules are being asked.
///
/// A [Solo] has exactly one, and a [SoloLanes] one for each lane and each
/// pool. Everything else — the state, the pump, the listeners, the timers
/// and closing — belongs to the [controller] and is shared by its cores.
final class _SoloLaneCore<S extends Object> {
  /// The controller whose pump steps this core.
  final SoloController<S> controller;

  /// The lane or pool this core is, for one of a [SoloLanes]; `null` for
  /// the core of a [Solo].
  final SoloLaneId? id;

  /// The face a lane or a pool of a [SoloLanes] shows; `null` for the core
  /// of a [Solo].
  _SoloQueueFace<S>? lane;

  /// The root jobs waiting for this core.
  late final _SoloQueue<S> queue = makeQueue();

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

  /// Whether the pump has said that a group of this lane is waiting for its
  /// window, so the passes driven by other lanes do not say it again.
  bool saidWaiting = false;

  /// The revision of the last write of the state made by a job running in
  /// this core, `0` before the first; what tells a debug line that a job
  /// writes over the work of another lane or pool.
  int lastWrite = 0;

  _SoloLaneCore(this.controller, {required String? name})
    : id = name == null ? null : SoloLaneId._(name);

  /// The queue [queue] holds, made on its first read: a method rather than
  /// the field itself, so a pool gives its own kind without overriding a
  /// field.
  // Makes a queue for this core; it does not turn the core into one.
  // ignore: use_to_and_as_if_applicable
  _SoloQueue<S> makeQueue() => _SoloQueue<S>(this);

  /// The running root jobs of this core, taken now: [current] of a lane or
  /// of a [Solo], every running job of a pool.
  List<_SoloJob<S, S, Object?>> get runningJobs => [?current];

  /// Takes note of a write of the state at [revision] by a job running in
  /// this core, [writer] being the number of its root in a pool.
  void wrote(int revision, int writer) => lastWrite = revision;

  /// What the debug lines call this core; `null` for the core of a [Solo].
  String? get name => id?.name;

  /// [line] as [Solo.debug] prints it for this core: a lane puts its name in
  /// front, the one core of a [Solo] says it as it is.
  String said(String line) {
    final name = this.name;
    return name == null ? line : '$name: $line';
  }
}

/// The core of a pool: one queue and one window of start rules, as a lane
/// has, and up to [concurrency] running root jobs in place of [current],
/// which a pool leaves `null`.
final class _SoloPoolCore<S extends Object> extends _SoloLaneCore<S> {
  /// How many root jobs run in this pool at once at most.
  final int concurrency;

  /// The running root jobs of this pool, in the order they started.
  final running = <_SoloJob<S, S, Object?>>[];

  /// The queue of this pool, the one [queue] holds, by its own type.
  late final _SoloPoolQueue<S> poolQueue = _SoloPoolQueue<S>(this);

  /// The number given to the last root job queued in this pool; each one
  /// gets the next.
  int _writers = 0;

  /// The number of the root whose job made the last write, `0` before the
  /// first.
  int lastWriter = 0;

  /// The revision of the last write made by a root other than
  /// [lastWriter], `0` before the first.
  int otherWrite = 0;

  _SoloPoolCore(
    super.controller, {
    required super.name,
    required this.concurrency,
  });

  /// Whether every place of this pool is taken.
  bool get isFull => running.length >= concurrency;

  @override
  _SoloQueue<S> makeQueue() => poolQueue;

  @override
  List<_SoloJob<S, S, Object?>> get runningJobs => [...running];

  @override
  void wrote(int revision, int writer) {
    if (writer != lastWriter) {
      otherWrite = lastWrite;
      lastWriter = writer;
    }
    lastWrite = revision;
  }

  /// The last write made by a root of this pool other than [writer]: a job
  /// of the pool writes over that one, and over none of its own root.
  int writeOtherThan(int writer) =>
      writer == lastWriter ? otherWrite : lastWrite;
}
