part of 'solo_base.dart';

/// Chooses which waiting group receives an event and where it runs.
enum AccumulationPolicy {
  /// Joins only the queue's tail, preserving intervening jobs as boundaries.
  adjacent,

  /// Transfers the last matching group's data to a new job at the tail.
  /// The old handle finishes cancelled, including with `cancellable: false`.
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
  /// Adjacent and joined events share a handle and outcome; replacement
  /// creates a new handle and cancels the previous one before start.
  /// After controller closure, returns a new `Cancelled(closed)` job
  /// without retaining the event or calling the merge function.
  ///
  /// A merge error escapes synchronously without accepting the event.
  /// Throws [StateError] on recursive addition from this accumulator's
  /// merge, or if the merge invalidates its candidate or closes the
  /// controller. Merge functions must be synchronous and pure.
  SoloJob<T> add(E event);
}

final class _SoloAccumulator<S extends Object, W extends S, E, V, T>
    implements SoloAccumulator<E, T>, _AccumulationOwner {
  final SoloBase<S> _solo;
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
      final group = _AccumulationGroup(this, _seed(event), _snapshot);
      final job = _solo.add(_job(group));
      if (job.isQueued && group._open) group._accepted();
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
    if (_policy != AccumulationPolicy.replace) {
      group
        .._value = next
        .._accepted();
      return previous;
    }
    final nextGroup = _AccumulationGroup(this, next, _snapshot);
    final replacement = _job(nextGroup);
    // Transfer ownership and publish the new queue state before cancellation
    // hooks can add, clear, cancel or close reentrantly. A collect buffer is
    // transferred as-is; releasing the old group must not clear its list.
    group._release();
    _solo._queue._jobs.remove(previous);
    replacement._added = true;
    _solo._queue._insert(replacement, first: false);
    nextGroup._accepted();
    _solo._schedulePump();
    previous._drop(
      Cancelled.by(
        reason: const ManualCancelReason(),
        started: false,
        description: 'replaced by accumulated group',
        stackTrace: StackTrace.current,
      ),
    );
    return replacement;
  }

  @override
  bool get _throttleReady => _throttleTimer?.isActive != true;

  bool get _hasQueuedGroup => _solo._queue._jobs.any(
        (job) => identical(job._accumulation?._owner, this),
      );

  @override
  Timer _startTimer(Duration duration, void Function(Timer) callback) =>
      _solo._startTimer(duration, callback);

  @override
  void _cancelTimer(Timer timer) => _solo._cancelTimer(timer);

  @override
  void _schedulePump() => _solo._schedulePump();

  @override
  void _started() {
    final timing = _timing;
    if (timing == null ||
        timing._kind != _AccumulationTimingKind.throttle ||
        timing.duration == Duration.zero) {
      return;
    }
    late final Timer timer;
    timer = _startTimer(timing.duration, (elapsed) {
      if (!identical(_throttleTimer, elapsed)) return;
      _throttleTimer = null;
      if (_solo._current == null && _hasQueuedGroup) _schedulePump();
    });
    _throttleTimer = timer;
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
