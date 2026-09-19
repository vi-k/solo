part of 'solo.dart';

/// Chooses which waiting group receives an event and where it runs.
enum AccumulationPolicy {
  /// Joins only the queue's tail, preserving intervening jobs as boundaries.
  adjacent,

  /// Moves the last matching group's job to the tail, keeping its handle.
  /// Nothing is cancelled, so `cancellable: false` has nothing to refuse.
  replace,

  /// Joins the last matching group at its existing position in the queue.
  join,
}

/// A controller-bound factory of queued groups with fixed rules and handler.
///
/// Keep one instance to combine events. Different instances never combine,
/// even with the same job key. Running groups no longer accept events.
// A stable object identifies compatible groups across additions.
// ignore: one_member_abstracts
abstract interface class SoloAccumulator<E, T> {
  /// Adds [event] synchronously and returns the job containing it.
  ///
  /// Every event of one group shares its handle and outcome, whatever the
  /// policy: replacement moves that group's job to the tail and gives back
  /// the same job. After controller closure, returns a new
  /// `Cancelled(closed)` job without retaining the event or calling the
  /// merge function.
  ///
  /// A merge error escapes synchronously without accepting the event.
  /// Throws [StateError] on recursive addition from this accumulator's
  /// merge, or if the merge invalidates its candidate or closes the
  /// controller. Merge functions must be synchronous and pure.
  SoloJob<T> add(E event);
}

final class _SoloAccumulator<S extends Object, W extends S, E, V, T>
    implements SoloAccumulator<E, T>, _AccumulationOwner {
  final Solo<S> _solo;
  final Future<T> Function(SoloContext<S, W>, V) _handler;
  final V Function(E) _seed;
  final V Function(V, E) _merge;
  final V Function(V) _snapshot;
  final Object? _key;
  final AccumulationPolicy _policy;
  @override
  final AccumulationTiming? _timing;
  final bool Function(W)? _canStart;
  final bool Function(W)? _keepWhile;
  final bool _cancellable;
  final String Function()? _describe;
  var _merging = false;
  Timer? _throttleTimer;

  _SoloAccumulator(
    this._solo,
    this._handler, {
    required V Function(E) seed,
    required V Function(V, E) merge,
    required V Function(V) snapshot,
    required Object? key,
    required AccumulationPolicy policy,
    required AccumulationTiming? timing,
    required bool Function(W)? canStart,
    required bool Function(W)? keepWhile,
    required bool cancellable,
    required String Function()? describe,
  })  : _seed = seed,
        _merge = merge,
        _snapshot = snapshot,
        _key = key,
        _policy = policy,
        _timing = timing,
        _canStart = canStart,
        _keepWhile = keepWhile,
        _cancellable = cancellable,
        _describe = describe;

  _SoloJob<S, W, T>? _candidate() {
    final jobs = _solo._queue._jobs;
    final candidates = _policy == AccumulationPolicy.adjacent
        ? <_SoloJob<S, S, Object?>>[if (jobs.isNotEmpty) jobs.last]
        : jobs.reversed;
    for (final job in candidates) {
      final group = job._accumulation;
      if (group != null && group._open && identical(group._owner, this)) {
        return job as _SoloJob<S, W, T>;
      }
    }
    return null;
  }

  _SoloJob<S, W, T> _job(_AccumulationGroup<V>? group) => _SoloJob<S, W, T>(
        _solo,
        (ctx) {
          ctx.check();
          return _handler(ctx, group!._take());
        },
        key: _key,
        canStart: _canStart,
        keepWhile: _keepWhile,
        cancellable: _cancellable,
        describe: _describe,
        observer: _solo._jobObserver,
      ).._accumulation = group;

  @override
  SoloJob<T> add(E event) {
    if (_merging) {
      throw StateError('Cannot add while this accumulator is merging');
    }
    if (_solo.isClosed) return _solo.add(_job(null));
    final previous = _candidate();
    if (previous == null) {
      // Whether this accumulator is idle has to be read before its new job
      // joins the queue. The interval belongs to the accumulator, not to a
      // group, so a group appearing next to one that is already queued or
      // running must not start a second interval under it.
      final idle = _isIdle;
      final group = _AccumulationGroup(this, _seed(event), _snapshot);
      final job = _solo.add(_job(group));
      if (job.isQueued && group._open) {
        group._accepted();
        if (idle) _armCooldown();
      }
      return job;
    }
    final group = previous._accumulation! as _AccumulationGroup<V>;
    final V next;
    _merging = true;
    try {
      next = _merge(group._value as V, event);
    } finally {
      _merging = false;
    }
    if (_solo.isClosed || !identical(_candidate(), previous)) {
      throw StateError('The accumulation group changed during merge');
    }
    group._value = next;
    if (_policy == AccumulationPolicy.replace) {
      // The rule is about position and nothing else: the group keeps its
      // job, its handle and its buffer, and the job moves behind whatever
      // was queued after it. Nothing is cancelled here, so no cancellation
      // hook can re-enter in the middle of the move.
      _solo._queue._jobs.remove(previous);
      _solo._queue._insert(previous, first: false);
      Solo._debug(() => 'move $previous to the tail');
    }
    group._accepted();
    return previous;
  }

  @override
  bool get _throttleReady => _throttleTimer?.isActive != true;

  bool get _hasQueuedGroup => _solo._queue._jobs.any(
        (job) => identical(job._accumulation?._owner, this),
      );

  /// Whether this accumulator has no group of its own queued or running.
  bool get _isIdle =>
      !_hasQueuedGroup &&
      !identical(_solo._current?._accumulation?._owner, this);

  @override
  Timer _startTimer(Duration duration, void Function(Timer) callback) =>
      _solo._startTimer(duration, callback);

  @override
  void _cancelTimer(Timer timer) => _solo._cancelTimer(timer);

  @override
  void _schedulePump() => _solo._schedulePump();

  /// Starts the interval of a throttle that does not start at once, where
  /// a group appears on an idle accumulator and nowhere else.
  ///
  /// Arming it on every accepted event instead would push back a group that
  /// has already waited out its interval and needs only the execution slot,
  /// which is what `An addition does not extend it` promises against. The
  /// same holds for a group appearing beside one that is queued or running:
  /// the caller is told the interval is counted once, and a running one is
  /// never restarted from under a group that is already waiting on it.
  void _armCooldown() {
    final timing = _timing;
    if (timing == null ||
        timing._kind != _AccumulationTimingKind.throttle ||
        timing._startAtOnce) {
      return;
    }
    if (_throttleTimer?.isActive ?? false) return;
    _started();
  }

  @override
  void _started() {
    final timing = _timing;
    if (timing == null ||
        timing._kind != _AccumulationTimingKind.throttle ||
        timing.duration == Duration.zero) {
      return;
    }
    _stopThrottle();
    late final Timer timer;
    timer = _startTimer(timing.duration, (elapsed) {
      if (!identical(_throttleTimer, elapsed)) return;
      _throttleTimer = null;
      if (_solo._current == null && _hasQueuedGroup) _schedulePump();
    });
    _throttleTimer = timer;
  }

  /// Takes the interval timer down, the way `_stopDebounce` takes its own.
  ///
  /// Nothing arms an interval that is already running today: a group is
  /// not ready while one is, and `_armCooldown` turns around at the door.
  /// That is a fact about the callers, though, and the one a replaced
  /// timer would cost is the controller's: an engine timer lives in a list
  /// until it fires or is cancelled, and a replaced one would sit there
  /// holding this accumulator until the controller closed.
  void _stopThrottle() {
    final timer = _throttleTimer;
    if (timer == null) return;
    _throttleTimer = null;
    _cancelTimer(timer);
  }
}

abstract interface class _AccumulationOwner {
  AccumulationTiming? get _timing;

  bool get _throttleReady;

  Timer _startTimer(Duration duration, void Function(Timer) callback);

  void _cancelTimer(Timer timer);

  void _schedulePump();

  void _started();
}

final class _AccumulationGroup<V> {
  final _AccumulationOwner _owner;
  final V Function(V) _snapshot;
  V? _value;
  var _open = true;
  Timer? _debounceTimer;

  _AccumulationGroup(this._owner, this._value, this._snapshot);

  bool get _ready {
    final timing = _owner._timing;
    if (timing == null || timing.duration == Duration.zero) return true;
    return switch (timing._kind) {
      _AccumulationTimingKind.debounce => _debounceTimer == null,
      _AccumulationTimingKind.throttle => _owner._throttleReady,
    };
  }

  void _accepted() {
    final timing = _owner._timing;
    if (timing == null ||
        timing._kind != _AccumulationTimingKind.debounce ||
        timing.duration == Duration.zero) {
      return;
    }
    _stopDebounce();
    late final Timer timer;
    timer = _owner._startTimer(timing.duration, (elapsed) {
      if (!identical(_debounceTimer, elapsed)) return;
      _debounceTimer = null;
      _seal();
      _owner._schedulePump();
    });
    _debounceTimer = timer;
  }

  void _started() => _owner._started();

  void _seal() {
    if (!_open) return;
    _open = false;
    _stopDebounce();
    _value = _snapshot(_value as V);
  }

  V _take() {
    final value = _value as V;
    _release();
    return value;
  }

  void _release() {
    if (!_open && _value == null) return;
    _open = false;
    _stopDebounce();
    _value = null;
  }

  void _stopDebounce() {
    final timer = _debounceTimer;
    if (timer == null) return;
    _debounceTimer = null;
    _owner._cancelTimer(timer);
  }
}
