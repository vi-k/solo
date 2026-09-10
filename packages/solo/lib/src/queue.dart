part of 'solo_base.dart';

/// The queue of a controller, visible to its subclasses.
///
/// Jobs with `cancellable: false` are skipped silently unless `force` is
/// given. `force` affects only queued jobs: a running job is never touched
/// by the queue.
abstract interface class SoloQueue {
  /// An unmodifiable view of the queued jobs, first to run first.
  Iterable<Job<Object?>> get jobs;

  /// The number of queued jobs.
  int get length;

  /// Whether the queue is empty.
  bool get isEmpty;

  /// Whether the queue has jobs.
  bool get isNotEmpty;

  /// Removes [job] with `Cancelled(manual)`; returns whether it was removed.
  bool remove(Job<Object?> job, {bool force = false});

  /// Removes every job matching [test]; returns the number removed.
  int removeWhere(bool Function(Job<Object?> job) test, {bool force = false});

  /// Removes every job; returns the number removed.
  int clear({bool force = false});

  /// The last queued job matching [test], or `null`.
  Job<Object?>? lastWhere(bool Function(Job<Object?> job) test);
}

final class _SoloQueue<S extends Object> implements SoloQueue {
  final _jobs = <_SoloJob<S, S, Object?>>[];

  @override
  Iterable<Job<Object?>> get jobs => UnmodifiableListView(_jobs);

  @override
  int get length => _jobs.length;

  @override
  bool get isEmpty => _jobs.isEmpty;

  @override
  bool get isNotEmpty => _jobs.isNotEmpty;

  @override
  bool remove(Job<Object?> job, {bool force = false}) {
    if (job is! _SoloJob<S, S, Object?> || !_jobs.contains(job)) {
      return false;
    }
    job._cancelWith(
      Cancelled.by(
        reason: const ManualCancelReason(),
        started: false,
        stackTrace: StackTrace.current,
      ),
      rejectable: !force,
    );
    // The job answers a rejectable cancellation itself, and a job that
    // refused is still here: membership is the answer, not a second check.
    return !_jobs.contains(job);
  }

  @override
  int removeWhere(
    bool Function(Job<Object?> job) test, {
    bool force = false,
  }) {
    var count = 0;
    for (final job in _jobs.where(test).toList()) {
      if (remove(job, force: force)) {
        count++;
      }
    }
    return count;
  }

  @override
  int clear({bool force = false}) => removeWhere((_) => true, force: force);

  @override
  Job<Object?>? lastWhere(bool Function(Job<Object?> job) test) {
    for (final job in _jobs.reversed) {
      if (test(job)) {
        return job;
      }
    }
    return null;
  }

  void _insert(_SoloJob<S, S, Object?> job, {required bool first}) {
    if (first) {
      _jobs.insert(0, job);
    } else {
      _jobs.add(job);
    }
  }

  _SoloJob<S, S, Object?>? _takeFirst() {
    if (_jobs.isEmpty) return null;
    final job = _jobs.removeAt(0);
    job._accumulation?._seal();
    return job;
  }

  List<_SoloJob<S, S, Object?>> _drain() {
    final drained = _jobs.toList();
    _jobs.clear();
    return drained;
  }
}
