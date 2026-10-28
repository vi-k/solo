part of 'solo.dart';

/// The queue of a controller, visible to its subclasses.
///
/// Jobs with `cancellable: false` are skipped silently unless `force` is
/// given. `force` affects only queued jobs: a running job is never touched
/// by the queue. A removed job ends `Cancelled` with `reason`, a
/// [ManualCancelReason] unless the caller names one of its own — a
/// policy of the domain that clears the queue can say so.
///
/// A job whose start rules are being asked is off the queue and not
/// started yet. [jobs] and [length] leave it out, as its `isQueued` does,
/// and the removals reach it ahead of the rest, the way a [Policy] and
/// [Solo.cancelAll] do: it is queued work until it is launched.
abstract interface class SoloQueue {
  /// An unmodifiable view of queued jobs in their current order.
  ///
  /// A job waiting for an accumulation timing window can be bypassed by a
  /// ready job later in this view.
  Iterable<SoloJob<Object?>> get jobs;

  /// The number of queued jobs.
  int get length;

  /// Whether the queue is empty.
  bool get isEmpty;

  /// Whether the queue has jobs.
  bool get isNotEmpty;

  /// Removes [job] with a cancellation for [reason]; returns whether it was
  /// removed.
  bool remove(
    Job<Object?> job, {
    bool force = false,
    CancelReason reason = const ManualCancelReason(),
  });

  /// Removes every job matching [test]; returns the number removed.
  int removeWhere(
    bool Function(SoloJob<Object?> job) test, {
    bool force = false,
    CancelReason reason = const ManualCancelReason(),
  });

  /// Removes every job; returns the number removed.
  int clear({
    bool force = false,
    CancelReason reason = const ManualCancelReason(),
  });
}

final class _SoloQueue<S extends Object> implements SoloQueue {
  final Solo<S> _solo;
  final _jobs = <_SoloJob<S, S, Object?>>[];

  _SoloQueue(this._solo);

  /// The job the pump holds while its start rules are asked, unless a rule
  /// has already ended it.
  _SoloJob<S, S, Object?>? get _held {
    final job = _solo._inTransition;
    return job != null && !job.isFinished ? job : null;
  }

  @override
  Iterable<SoloJob<Object?>> get jobs => UnmodifiableListView(_jobs);

  @override
  int get length => _jobs.length;

  @override
  bool get isEmpty => _jobs.isEmpty;

  @override
  bool get isNotEmpty => _jobs.isNotEmpty;

  @override
  bool remove(
    Job<Object?> job, {
    bool force = false,
    CancelReason reason = const ManualCancelReason(),
  }) {
    if (job is! _SoloJob<S, S, Object?> ||
        !(_jobs.contains(job) || identical(job, _held))) {
      return false;
    }
    job._cancelWith(
      Cancelled.by(
        reason: reason,
        started: false,
        stackTrace: StackTrace.current,
      ),
      rejectable: !force,
    );
    // The job answers a rejectable cancellation itself, and a job that
    // refused is still here: membership is the answer, not a second check.
    // The held one is in no list, and a cancellation it takes ends it.
    return !_jobs.contains(job) && !identical(job, _held);
  }

  @override
  int removeWhere(
    bool Function(SoloJob<Object?> job) test, {
    bool force = false,
    CancelReason reason = const ManualCancelReason(),
  }) {
    var count = 0;
    // The snapshot is taken before the predicate is asked, not while it is
    // being asked: `test` is the caller's code, and `where` is lazy, so one
    // that touches the queue used to walk into a
    // `ConcurrentModificationError` on the list it had just changed.
    for (final job in [?_held, ..._jobs]) {
      if (!test(job)) {
        continue;
      }
      if (remove(job, force: force, reason: reason)) {
        count++;
      }
    }
    return count;
  }

  @override
  int clear({
    bool force = false,
    CancelReason reason = const ManualCancelReason(),
  }) => removeWhere((_) => true, force: force, reason: reason);

  void _insert(_SoloJob<S, S, Object?> job, {required bool first}) {
    if (first) {
      _jobs.insert(0, job);
    } else {
      _jobs.add(job);
    }
  }

  _SoloJob<S, S, Object?>? _takeFirst() {
    for (var i = 0; i < _jobs.length; i++) {
      final job = _jobs[i];
      if (!(job._accumulation?._ready ?? true)) continue;
      _jobs.removeAt(i);
      job._accumulation?._seal();
      return job;
    }
    return null;
  }

  List<_SoloJob<S, S, Object?>> _drain() {
    final drained = _jobs.toList();
    _jobs.clear();
    return drained;
  }
}
