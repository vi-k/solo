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
  /// the four with no outcome to carry them: an action abandoned by
  /// [JobContext.wait] failing later, a disposer, a callback of
  /// [JobContext.onCancel], and work handed over with
  /// [JobContext.unattended]. Without an observer those four go to the
  /// zone the job was created in — all but a [Cancelled], which the engine
  /// hands to nobody; with an observer they all stop here.
  ///
  /// A [Cancelled] reaches this hook in three cases, and none of them is
  /// the job giving up — that one is not an error and never comes here.
  /// A child's cancellation awaited through `child.value`; a fresh
  /// `Cancelled` built by the rules of a domain for a context that
  /// outlived its job; and `throw Cancelled(...)` inside unattended work,
  /// where there is nobody left to cancel and the object is new. This hook
  /// is the only place any of the three is heard: a cancellation is a
  /// decision somebody made, not a failure, and none of them reaches the
  /// zone.
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {}

  /// A job called [JobContext.log].
  void onLog(Job<Object?> job, String message) {}
}
