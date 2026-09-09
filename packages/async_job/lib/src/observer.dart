import 'job_base.dart';

/// Cross-cutting hooks of a single job: analytics, error reporting, a log.
///
/// Given to a job by whoever runs it — in `solo`, by the controller. A hook
/// that throws hands its error to the current zone and changes nothing
/// else: not the job's outcome, not the hook standing next to it.
abstract class JobObserver {
  /// A job body is about to run.
  void onStart(Job<Object?> job) {}

  /// A job has an outcome, including jobs dropped before start.
  void onFinish(Job<Object?> job) {}

  /// Something the job did threw.
  ///
  /// The body — that error also becomes the [Failed] outcome — or one of
  /// the errors with no outcome to carry them: an action abandoned by
  /// [JobContext.wait] failing later, a disposer, a cancellation callback,
  /// work handed over with [JobContext.unattended], or a failure while
  /// formatting a child's cancellation description. Without an observer
  /// these go to the job's creation zone — all but a [Cancelled], which the
  /// engine hands to nobody; with an observer they all stop here.
  ///
  /// A [Cancelled] reaches this hook whenever one is thrown where there is
  /// no outcome to carry it — never the job giving up, which is not an
  /// error and never comes here. A disposer or a callback of
  /// [JobContext.onCancel] or [Job.whenCancelled] that throws one;
  /// `throw Cancelled(...)` inside unattended work, where there is nobody
  /// left to cancel and the object is new; a fresh `Cancelled` built by
  /// the rules of a domain for a
  /// context that outlived its job; a child's cancellation taken through
  /// `child.value` from one of those places rather than from the body,
  /// where it becomes the outcome instead and never comes here. This hook
  /// is the only place any of them is heard: a cancellation is a decision
  /// somebody made, not a failure, and none of them reaches the zone.
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {}

  /// A job called [JobContext.log], with what it passed.
  ///
  /// [message] arrives as the body gave it, untouched: making a line out
  /// of it is this listener's business, and a `toString` that throws while
  /// it does is a hook that throws — the error goes to the current zone
  /// and nothing else changes.
  void onLog(Job<Object?> job, Object? message) {}
}
