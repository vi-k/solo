part of 'solo_base.dart';

// `SoloBase.job` and `SoloBase.run` are added in Task 4; until then these
// forward references do not resolve.
// ignore: comment_references
/// A handle to a job created by [SoloBase.job] or [SoloBase.run].
///
/// Not a [Future]: calling a controller method without `await` is legal.
/// Await [done], [value] or [whenCancelled] where you need to.
abstract interface class Job<T> {
  /// The key given at creation; compared with `==` by policies and queue
  /// searches.
  Object? get key;

  /// The description given at creation, or an empty string.
  String describe();

  /// Nesting depth: 0 for a root job, `parent.level + 1` for a child.
  int get level;

  /// Whether this job was started by [JobContext.run].
  bool get isChild;

  /// Whether the job waits in the queue.
  bool get isQueued;

  /// Whether the body is running or its children are still finishing.
  bool get isRunning;

  /// Whether [outcome] is set.
  bool get isFinished;

  /// Whether the job is marked cancelled, even if the body still runs.
  bool get isCancelled;

  /// The outcome, or `null` until the job is finished.
  Outcome<T>? get outcome;

  /// Completes with the outcome; never throws.
  Future<Outcome<T>> get done;

  /// Completes with the returned value, or throws [Cancelled] with the
  /// cancellation stack trace, or throws the body's error.
  Future<T> get value;

  /// Completes when the job is marked cancelled, before the body finishes.
  /// Never completes for a job that finishes without cancellation.
  Future<void> get whenCancelled;

  /// Cancels the job and waits for it to actually finish.
  ///
  /// A running job with `cancellable: false` is not cancelled; the
  /// returned future still waits for it to finish.
  Future<void> cancel();
}
