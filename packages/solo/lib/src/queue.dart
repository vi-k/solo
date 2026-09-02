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
