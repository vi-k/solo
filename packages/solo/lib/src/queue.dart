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
/// [SoloController.cancelAll] do: it is queued work until it is launched.
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

/// The place of one job in a queue.
///
/// The job holds its own, so asking whether it is queued and taking it out
/// cost the same however long the queue is: a list asked each of them by a
/// walk, and a long queue paid for that walk once per job.
final class _QueueEntry<S extends Object>
    extends LinkedListEntry<_QueueEntry<S>> {
  final _SoloJob<S, S, Object?> job;

  _QueueEntry(this.job);
}

/// The place of one job among the queued jobs that share something with it:
/// its key, or the accumulator its group belongs to.
final class _IndexEntry<S extends Object>
    extends LinkedListEntry<_IndexEntry<S>> {
  final _SoloJob<S, S, Object?> job;

  /// What the job shares with the others of its list, the key the list is
  /// found by.
  final Object by;

  _IndexEntry(this.job, this.by);
}

/// The queued jobs by what they share, each list in the order of the queue.
///
/// A policy looks for the jobs of a key, and an accumulator for its groups,
/// on every call: a walk of the queue made each of those calls cost the
/// length of the queue, and a long queue paid for it once per call.
final class _QueueIndex<S extends Object> {
  final Map<Object, LinkedList<_IndexEntry<S>>> _lists;

  /// An index whose keys are compared with `==`, as the keys of jobs are.
  _QueueIndex.byEquality() : _lists = {};

  /// An index whose keys are compared by identity, as accumulators are.
  _QueueIndex.byIdentity() : _lists = Map.identity();

  _IndexEntry<S> _insert(
    _SoloJob<S, S, Object?> job,
    Object by, {
    required bool first,
  }) {
    final entry = _IndexEntry<S>(job, by);
    final list = _lists.putIfAbsent(by, LinkedList.new);
    if (first) {
      list.addFirst(entry);
    } else {
      list.add(entry);
    }
    return entry;
  }

  void _unlink(_IndexEntry<S> entry) {
    final list = entry.list!;
    entry.unlink();
    // An empty list goes with its key: the index keeps no key the queue
    // no longer holds.
    if (list.isEmpty) _lists.remove(entry.by);
  }

  /// Whether a queued job shares [by].
  bool _holds(Object by) => _lists.containsKey(by);

  /// The queued jobs that share [by], in the order of the queue, taken now:
  /// the caller asks them questions whose answers may change the queue.
  List<_SoloJob<S, S, Object?>> _of(Object by) => [
    ...?_lists[by]?.map((entry) => entry.job),
  ];

  /// The queued jobs that share [by], from the last to the first, a live
  /// view: for a reader that changes nothing while it walks.
  Iterable<_SoloJob<S, S, Object?>> _reversed(Object by) sync* {
    final list = _lists[by];
    var entry = list == null || list.isEmpty ? null : list.last;
    while (entry != null) {
      yield entry.job;
      entry = entry.previous;
    }
  }

  void _clear() => _lists.clear();
}

/// What [SoloQueue.jobs] hands out: a live view of the queue that prints as
/// the list it used to be.
final class _QueueView<S extends Object>
    extends IterableBase<SoloJob<Object?>> {
  final LinkedList<_QueueEntry<S>> _entries;

  _QueueView(this._entries);

  @override
  Iterator<SoloJob<Object?>> get iterator =>
      _entries.map((entry) => entry.job).iterator;

  @override
  int get length => _entries.length;

  @override
  bool get isEmpty => _entries.isEmpty;

  @override
  String toString() => Iterable.iterableToFullString(this, '[', ']');
}

final class _SoloQueue<S extends Object> implements SoloQueue {
  final _SoloLaneCore<S> _core;
  final _entries = LinkedList<_QueueEntry<S>>();

  /// The queued jobs that have a key, by the key.
  final _byKey = _QueueIndex<S>.byEquality();

  /// The queued jobs of accumulation groups, by the accumulator.
  final _byOwner = _QueueIndex<S>.byIdentity();

  _SoloQueue(this._core);

  /// The queued jobs whose key is [key], in the order of the queue.
  List<_SoloJob<S, S, Object?>> _keyed(Object key) => _byKey._of(key);

  /// The queued jobs of the groups of [owner], from the last to the first,
  /// a live view.
  Iterable<_SoloJob<S, S, Object?>> _ownedReversed(Object owner) =>
      _byOwner._reversed(owner);

  /// Whether a group of [owner] is queued.
  bool _holdsGroupOf(Object owner) => _byOwner._holds(owner);

  /// The queued jobs in their order, a live view.
  Iterable<_SoloJob<S, S, Object?>> get _jobs =>
      _entries.map((entry) => entry.job);

  /// The queued jobs from the last to the first, a live view.
  Iterable<_SoloJob<S, S, Object?>> get _reversed sync* {
    var entry = _entries.isEmpty ? null : _entries.last;
    while (entry != null) {
      yield entry.job;
      entry = entry.previous;
    }
  }

  /// Whether [job] is in this queue.
  bool _has(_SoloJob<S, S, Object?> job) =>
      identical(job._queueEntry?.list, _entries);

  /// The job the pump holds while its start rules are asked, unless a rule
  /// has already ended it.
  _SoloJob<S, S, Object?>? get _held {
    final job = _core.inTransition;
    return job != null && !job.isFinished ? job : null;
  }

  /// What a removal walks: the held job first, then the queue, taken before
  /// any of them is asked or removed.
  List<_SoloJob<S, S, Object?>> get _snapshot => [?_held, ..._jobs];

  @override
  Iterable<SoloJob<Object?>> get jobs => _QueueView(_entries);

  @override
  int get length => _entries.length;

  @override
  bool get isEmpty => _entries.isEmpty;

  @override
  bool get isNotEmpty => _entries.isNotEmpty;

  @override
  bool remove(
    Job<Object?> job, {
    bool force = false,
    CancelReason reason = const ManualCancelReason(),
  }) {
    if (job is! _SoloJob<S, S, Object?> ||
        !(_has(job) || identical(job, _held))) {
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
    return !_has(job) && !identical(job, _held);
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
    for (final job in _snapshot) {
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
  }) => _clear(_snapshot, force: force, reason: reason);

  /// Removes every job of [snapshot] that is still here; returns the number
  /// removed.
  ///
  /// The snapshot may be older than this call: `cancelAll` takes one of
  /// every core before it clears the first, and a job a finish handler puts
  /// in a core cleared later is not in it.
  int _clear(
    List<_SoloJob<S, S, Object?>> snapshot, {
    required bool force,
    required CancelReason reason,
  }) {
    var count = 0;
    for (final job in snapshot) {
      if (remove(job, force: force, reason: reason)) {
        count++;
      }
    }
    return count;
  }

  void _insert(_SoloJob<S, S, Object?> job, {required bool first}) {
    final entry = _QueueEntry<S>(job);
    job._queueEntry = entry;
    if (first) {
      _entries.addFirst(entry);
    } else {
      _entries.add(entry);
    }
    if (job.key case final key?) {
      job._keyEntry = _byKey._insert(job, key, first: first);
    }
    if (job._accumulation?._owner case final owner?) {
      job._ownerEntry = _byOwner._insert(job, owner, first: first);
    }
  }

  /// Takes [job], which is in this queue, out of it.
  void _unlink(_SoloJob<S, S, Object?> job) {
    job._queueEntry!.unlink();
    job._queueEntry = null;
    if (job._keyEntry case final entry?) _byKey._unlink(entry);
    job._keyEntry = null;
    if (job._ownerEntry case final entry?) _byOwner._unlink(entry);
    job._ownerEntry = null;
  }

  /// Moves [job], which is in this queue, behind every other job.
  void _moveToTail(_SoloJob<S, S, Object?> job) {
    _unlink(job);
    _insert(job, first: false);
  }

  _SoloJob<S, S, Object?>? _takeFirst() {
    for (final entry in _entries) {
      final job = entry.job;
      if (!(job._accumulation?._ready ?? true)) continue;
      // The walk ends here, so taking the entry out of the list it walks
      // is safe.
      _unlink(job);
      job._accumulation?._seal();
      return job;
    }
    return null;
  }

  List<_SoloJob<S, S, Object?>> _drain() {
    final drained = _jobs.toList();
    for (final job in drained) {
      job
        .._queueEntry = null
        .._keyEntry = null
        .._ownerEntry = null;
    }
    _entries.clear();
    _byKey._clear();
    _byOwner._clear();
    return drained;
  }
}
