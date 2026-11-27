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

  /// The first queued job that shares [by], or `null` when none does.
  _SoloJob<S, S, Object?>? _firstOf(Object by) {
    final list = _lists[by];
    return list == null || list.isEmpty ? null : list.first.job;
  }

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
    // The key first: its `==` and `hashCode` are the caller's code, and one
    // that throws leaves the job in no list rather than in the queue alone.
    // A key not equal to itself, such as `double.nan`, is not indexed: no
    // job shares it, and the index would keep a key no removal finds.
    if (job.key case final key? when key == key) {
      job._keyEntry = _byKey._insert(job, key, first: first);
    }
    if (job._accumulation?._owner case final owner?) {
      job._ownerEntry = _byOwner._insert(job, owner, first: first);
    }
    final entry = _QueueEntry<S>(job);
    job._queueEntry = entry;
    if (first) {
      _entries.addFirst(entry);
    } else {
      _entries.add(entry);
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

/// The queue of a pool: the queue of a lane, plus the jobs the pump may
/// take next, by their place in the order of the queue, and the keys held
/// by the jobs of the pool.
///
/// A job's place is a number given at its insertion: below every other
/// with `first: true`, above every other without. The pump takes the
/// first candidate that is ready, so the order of the queue holds without
/// a walk of the queue.
///
/// A job with a key equal to itself holds the key from the moment the pump
/// takes it to its end, and two jobs of one key never run together. The
/// candidates are the jobs without such a key and the head of every key
/// that no job holds; the others of a key wait out of the candidates and
/// cost nothing to the jobs of other keys. The head holds its key even as
/// a group waiting for its window: the jobs of its key stay behind it.
final class _SoloPoolQueue<S extends Object> extends _SoloQueue<S> {
  /// The place the last job inserted with `first: true` got.
  var _first = 0;

  /// The place the last job inserted at the tail got.
  var _last = 0;

  /// The jobs the pump may take next, by their place.
  final _ready = SplayTreeMap<int, _SoloJob<S, S, Object?>>();

  /// The job that holds each key, by the key, compared with `==` as the
  /// keys of jobs are: one that runs in the pool, or whose start rules are
  /// asked in its window.
  final _holders = <Object, _SoloJob<S, S, Object?>>{};

  /// Whether the pump is in the step of this pool: a candidate that comes
  /// in there is taken by the same step, and one that comes in elsewhere
  /// has to bring the pump back.
  var _stepping = false;

  _SoloPoolQueue(super._core);

  /// The job that holds [key], or `null` when none does.
  _SoloJob<S, S, Object?>? _holderOf(Object key) => _holders[key];

  @override
  void _insert(_SoloJob<S, S, Object?> job, {required bool first}) {
    // The holders are asked before anything is inserted: the key's `==` and
    // `hashCode` are the caller's code, and one that throws here or in the
    // queue leaves the job in no list. Past the queue only places are
    // compared. A key not equal to itself is held by no job.
    final key = job.key;
    final held = key != null && _holders.containsKey(key);
    super._insert(job, first: first);
    final seq = job._seq = first ? --_first : ++_last;
    // The index holds only a key equal to itself, so a job with no entry
    // there goes as a job without a key.
    final entry = job._keyEntry;
    if (entry == null) {
      _ready[seq] = job;
      return;
    }
    // A job of a key is a candidate only as the head of a free key, and the
    // head it takes over from is a candidate no longer.
    if (entry.previous != null || held) return;
    if (entry.next case final behind?) _ready.remove(behind.job._seq);
    _ready[seq] = job;
  }

  @override
  void _unlink(_SoloJob<S, S, Object?> job) {
    // Read before the job leaves the index: the one after it there is the
    // next head of its key. The holders are asked here too, before the
    // queue changes, and only for a candidate, the one job whose leaving
    // can make another a candidate: a key whose `==` or `hashCode` throws
    // in that lookup leaves the job where it was, in the queue and among
    // the candidates.
    final entry = job._keyEntry;
    final next = entry?.next?.job;
    final candidate = _ready.containsKey(job._seq);
    final held = candidate && next != null && _holders.containsKey(entry!.by);
    super._unlink(job);
    _ready.remove(job._seq);
    // A job of a key is a candidate only as the head of a free key, so the
    // next one heads a free key as well, unless the pump has just taken
    // this one and holds the key for it.
    if (!candidate || next == null || held) return;
    _ready[next._seq] = next;
    // A removal or a move made by the caller's code ends no running job,
    // so nothing else brings the pump back for this one. In the step of
    // the pool its loop takes the job anyway.
    if (!_stepping) _core.controller._schedulePump();
  }

  @override
  List<_SoloJob<S, S, Object?>> _drain() {
    _ready.clear();
    return super._drain();
  }

  /// Takes the first candidate that is ready out of the queue: a group
  /// waiting for its window is stepped over, as [_takeFirst] steps over it.
  ///
  /// The job holds its key from here: it is put among the holders before
  /// it leaves the queue, so the next job of its key does not become a
  /// candidate.
  _SoloJob<S, S, Object?>? _takeNext() {
    for (final job in _ready.values) {
      if (!(job._accumulation?._ready ?? true)) continue;
      if (job._keyEntry case final entry?) _holders[entry.by] = job;
      // The walk ends here, so taking the job out of the map it walks is
      // safe.
      _unlink(job);
      job._accumulation?._seal();
      return job;
    }
    return null;
  }

  /// Lets the key of [job] go if [job] holds it, and makes the head of the
  /// key a candidate: for every job of the pool that ends, a running one or
  /// one ended in the window of its start rules.
  void _release(_SoloJob<S, S, Object?> job) {
    final key = job.key;
    if (key == null || !identical(_holders[key], job)) return;
    _holders.remove(key);
    if (_byKey._firstOf(key) case final head?) _ready[head._seq] = head;
  }
}
