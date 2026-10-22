part of 'job_base.dart';

/// Why a job was cancelled, with any data the reason needs.
///
/// Extend this class to carry domain data such as an error, its stack trace,
/// or an identifier. Inspect reasons by type; [name] is only a display label.
/// There is no equality by name: subclasses inherit identity equality unless
/// they define their own value equality.
@immutable
abstract class CancelReason {
  /// Creates a reason for a subclass.
  const CancelReason();

  /// A short label for journals and diagnostics, not a type identifier.
  String get name;

  @override
  String toString() => name;
}

/// An explicit cancellation: the default reason of [Job.cancel].
///
/// An engine may give it to removals of its own — `solo`, for example, to a job
/// taken out of its queue.
final class ManualCancelReason extends CancelReason {
  /// Creates an explicit cancellation reason.
  const ManualCancelReason();

  @override
  String get name => 'manual';
}

/// A cancellation cascaded from the parent job.
final class ParentCancelReason extends CancelReason {
  /// The parent's cancellation, including its original reason and data.
  ///
  /// Set by the core when it cascades; optional for engines that have no parent
  /// cancellation to attach.
  final Cancelled? cause;

  /// Creates a parent cancellation reason with its optional [cause].
  const ParentCancelReason({this.cause});

  @override
  String get name => 'parent';
}

/// A cancellation forwarded between jobs connected by [Job.then], or from a
/// source to a handle of [Job.shared].
final class ChainCancelReason extends CancelReason {
  /// The cancellation of the adjacent job that caused this request.
  final Cancelled cause;

  /// Creates a chain cancellation preserving its [cause].
  const ChainCancelReason({required this.cause});

  @override
  String get name => 'chain';
}

/// A branch of [JobContext.runAll] was stopped because its group is failing:
/// another branch of the group ended in an error or a cancellation, or the
/// group itself hit an error, such as a job it refused to take as a branch.
///
/// Nobody cancelled this job by hand and no cascade of a parent reached it:
/// the group asked it to stop, so that work whose result the caller will
/// never see does not go on. The stop is a request like any other — a job
/// created with `cancellable: false` refuses it, and an operation that
/// cannot be interrupted plays out.
final class SiblingCancelReason extends CancelReason {
  /// What the group stopped for: the error another branch failed with, the
  /// cancellation that ended it, or an error of the group itself, such as
  /// the [ArgumentError] or [StateError] it refused a job with.
  final Object cause;

  /// Creates a reason for a branch stopped by its group.
  const SiblingCancelReason({required this.cause});

  @override
  String get name => 'sibling';
}

/// The job ran out of the time it was given with `timeout`.
///
/// The core cancels a job with this reason when the deadline set by the
/// `timeout` of [Job.new] or [Job.deferred] runs out before the body and the
/// children it waits for are over. The request is an ordinary rejectable
/// cancellation: an uncancellable section holds it, and a job already cancelled
/// for another reason keeps that one. A held request lands when the section
/// closes, so a body that returns what the section returned still ends with
/// this reason, and the registrations of [JobContext.onDiscard] run. Only a
/// request a section the body did not await still holds when the body and the
/// children are over goes with the timer. Its children hear it as the cause of
/// their [ParentCancelReason].
///
/// Each deadline that runs out makes a reason of its own, so a reason is
/// told apart by identity as well as by type.
final class TimeoutCancelReason extends CancelReason {
  /// The limit that ran out.
  final Duration timeout;

  /// Creates a timeout reason for [timeout].
  const TimeoutCancelReason(this.timeout);

  @override
  String get name => 'timeout';
}

/// The body cancelled itself, directly or by letting a child's cancellation
/// escape.
final class HandlerCancelReason extends CancelReason {
  /// The child's cancellation when it escaped through the parent's body.
  ///
  /// `null` for an ordinary `throw Cancelled(...)` by the body itself.
  final Cancelled? cause;

  /// Creates a body cancellation reason with its optional [cause].
  const HandlerCancelReason({this.cause});

  @override
  String get name => 'handler';
}

/// The result of a job: [Done], [Failed] or [Cancelled].
///
/// [Failed] and [Cancelled] extend `Outcome<Never>`, so a `switch` over
/// `Outcome<T>` with these three cases is exhaustive.
///
/// Outcomes are equal by identity, not by value: two of them stand for two
/// runs, and a [Failed] or a [Cancelled] carries a stack trace that makes
/// value equality a question with no good answer. Compare what is inside
/// — the value, the error, the reason — not the outcome itself. In a test,
/// that means `expect(await job.value, 42)`. Comparing `await job.done` with
/// `Done(42)` fails even when the job returned 42, and the failure prints
/// `Done(42)` on both sides.
sealed class Outcome<T> {
  const Outcome();
}

/// The job body completed and returned [value].
final class Done<T> extends Outcome<T> {
  /// The value returned by the job body.
  final T value;

  /// Creates a successful outcome.
  const Done(this.value);

  @override
  String toString() => 'Done($value)';
}

/// The job body threw [error], or an engine ended the job with it by hand.
///
/// [JobObserver.onError] hears [error] once. If nobody observes the job by
/// the microtask after it ends, through [Job.done], [Job.value],
/// [Job.ignoreFailure] or forwarding by [Job.then] or a handle of
/// [Job.shared], somebody answers for the error: [JobAnswerer.onUnanswered]
/// of an observer that answers, or else the job's creation zone. Reading
/// [Job.outcome] observes nothing. The failure of the body of a job that ends
/// [Cancelled] is no [Failed]: whoever waits for that job gets the
/// cancellation, and the error goes the way of the errors no outcome carries.
///
/// See [A failure nobody waits for](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/outcomes.md#a-failure-nobody-waits-for)
/// on the outcomes page, and [Where errors go](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/errors.md#where-errors-go)
/// for the errors no outcome carries.
final class Failed extends Outcome<Never> {
  /// The thrown error.
  final Object error;

  /// The stack trace of [error].
  final StackTrace stackTrace;

  /// Creates a failed outcome.
  const Failed(this.error, this.stackTrace);

  @override
  String toString() => 'Failed($error)';
}

/// The job was cancelled before or during its run.
///
/// Thrown by the [JobContext] members that wait or start something once
/// the job has accepted a cancellation — the ones that only register a
/// cleanup go on working — and stored in [Job.outcome]. A body may also
/// `throw Cancelled('why')` to cancel itself; the core records that as
/// [HandlerCancelReason] and cancels the children of that body.
///
/// A `catch` in a body takes a cancellation along with the failures:
/// `on Object`, a `catch` with no type and `on Exception` all catch it, and
/// code in the clause then runs on a job that is already cancelled. A clause
/// that handles a failure opens with [JobContext.check], which throws the
/// job's cancellation if it has accepted one. That also covers an error an
/// action throws because the job was cancelled, which no clause for
/// `Cancelled` would let by.
final class Cancelled extends Outcome<Never> implements Exception {
  /// Who cancelled the job.
  final CancelReason reason;

  /// `false` when the job was dropped before its body ran at all.
  final bool started;

  /// Details within [reason]: the text passed by the body, or whatever an
  /// engine writes there — `solo`, for example, writes `'is not Ready'`,
  /// `'canStart'` and `'keepWhile'`.
  final String? description;

  /// Where the cancellation came from, not where the body died.
  final StackTrace? stackTrace;

  /// Cancels the current job from its body: `throw Cancelled('why')`.
  const Cancelled([this.description])
      : reason = const HandlerCancelReason(),
        started = true,
        stackTrace = null;

  /// Creates a cancellation with a reason of your own.
  ///
  /// A body may throw this to keep a custom [reason] and its data. The core
  /// records the throw's stack trace and sets [started] to `true`. Engines also
  /// use it for their own cancellations, such as rules and closing in `solo`.
  ///
  /// The reason is kept whoever built it, and a body that lets another
  /// job's cancellation through — `await other.value` on a job it does not
  /// own — hands that job's reason to its own outcome, where it reads as
  /// though somebody cancelled this one. Only a child of this job is
  /// wrapped in a [HandlerCancelReason] naming its cause; for anything
  /// else, wrap it by hand or catch it.
  ///
  /// [started] matters only where the cancellation becomes an outcome as
  /// it is, through `JobBase.finish`: an engine passes `false` there for a
  /// job it drops before the body runs. On the way through `cancelWith` the
  /// core sets it by the status of the job and whatever was passed here
  /// is replaced.
  const Cancelled.by({
    required this.reason,
    this.started = true,
    this.description,
    this.stackTrace,
  });

  @override
  String toString() => description == null
      ? 'Cancelled(${reason.name})'
      : 'Cancelled(${reason.name}: $description)';
}
