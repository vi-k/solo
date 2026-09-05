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
  /// the three with no outcome to carry them: an action abandoned by
  /// [JobContext.wait] failing later, a disposer, a callback of
  /// [JobContext.onCancel]. Without an observer those three go to the zone
  /// the job was created in; with one, they stop here.
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {}

  /// A job called [JobContext.log].
  void onLog(Job<Object?> job, String message) {}
}
