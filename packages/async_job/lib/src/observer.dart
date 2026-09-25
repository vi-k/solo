part of 'job_base.dart';

/// Cross-cutting hooks of a single job: analytics, error reporting, a log.
///
/// Given to a job by whoever runs it — in `solo`, by the controller. A hook
/// that throws hands its error to the current zone and changes nothing
/// else: not the job's outcome, not the hook standing next to it.
///
/// Two hooks see errors, and they do different work. [onError] is told
/// about every error of the job and answers for none. [onUnanswered] is
/// asked about the errors no outcome carries, and its default body sends
/// them to the zone the job was created in — the same place they go when
/// the job has no observer at all. An observer written to watch changes
/// nowhere an error goes.
///
/// A class that already extends another one mixes this in, `with
/// JobObserver`, and keeps the default bodies.
abstract mixin class JobObserver {
  /// A job body is about to run.
  void onStart(Job<Object?> job) {}

  /// A job has an outcome, including jobs dropped before start.
  void onFinish(Job<Object?> job) {}

  /// Something the job did threw.
  ///
  /// The body's failure, or one of the errors with no outcome to carry
  /// them: an action abandoned by [JobContext.wait] failing later, a
  /// disposer, a cancellation callback, work handed over with
  /// [JobContext.unattended], or a failure while formatting a child's
  /// cancellation description. Each is told here once.
  ///
  /// Notification only: overriding it changes nothing about where the
  /// error goes. The errors with no outcome go on to [onUnanswered], and so
  /// do two failures of the body that a parent cannot pass on: that of a
  /// branch of [JobContext.runAll] the group did not throw, and one a
  /// cancellation covered in a child of [JobContext.run] or a branch. Any
  /// other failure of the body is carried by the outcome, and one nobody
  /// observes reaches the zone — all but a failure thrown after the job
  /// accepted a cancellation: an operation stopping at the job's token
  /// looks like that, and this hook is the only one to hear it.
  ///
  /// A [Cancelled] reaches this hook whenever one is thrown where there is
  /// no outcome to carry it — never the job giving up, which is not an
  /// error and never comes here. A disposer or a callback of
  /// [JobContext.onCancel] or [Job.whenCancelled] that throws one;
  /// `throw Cancelled(...)` inside unattended work, where there is nobody
  /// left to cancel and the object is new; a fresh `Cancelled` built by
  /// the rules of a domain for a context that outlived its job; a child's
  /// cancellation taken through `child.value` from one of those places
  /// rather than from the body, where it becomes the outcome instead and
  /// never comes here.
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {}

  /// Nobody answered for this error, and this observer is the last one
  /// holding it.
  ///
  /// The errors no outcome carries: an action abandoned by
  /// [JobContext.wait] failing later, a disposer, a callback of
  /// [JobContext.onCancel] or [Job.whenCancelled], work handed over with
  /// [JobContext.unattended], a failure while formatting a child's
  /// cancellation description, the failure of a branch of
  /// [JobContext.runAll] that the group did not throw, and a failure of the
  /// body that a cancellation covered afterwards in a child of
  /// [JobContext.run] or a branch — the parent took the outcome, and the
  /// outcome carries the cancellation. Any other failure of a body does not
  /// come here: it has an outcome, and one nobody observes reaches the zone
  /// by itself. Every error that comes here has been through [onError]
  /// already.
  ///
  /// **What the default body does.** It hands the error to the zone the
  /// job was created in — where the error goes when the job has no
  /// observer. A cancellation is the exception and goes nowhere: a
  /// [Cancelled], and a `ParallelWaitError` carrying nothing but
  /// cancellations. A cancellation is a decision somebody made, not a
  /// failure.
  ///
  /// **Override it to answer here instead** — an observer that reports to
  /// its own system and stops there. An override that says nothing keeps
  /// these errors out of the zone. Call
  /// `super.onUnanswered(job, error, stackTrace)` to keep the zone as well,
  /// and hand it whatever the override cannot tell apart: it knows the
  /// cancellations to drop.
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    if (job is JobBase<Object?>) {
      job._toZone(error, stackTrace);
    } else if (!JobBase._isCancellation(error)) {
      // Called by hand with a job of another kind: the core always passes
      // its own, so the zone it was created in is not known here.
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  /// A job called [JobContext.log], with what it passed.
  ///
  /// [message] arrives as the body gave it, untouched: making a line out
  /// of it is this listener's business, and a `toString` that throws while
  /// it does is a hook that throws — the error goes to the current zone
  /// and nothing else changes.
  void onLog(Job<Object?> job, Object? message) {}
}
