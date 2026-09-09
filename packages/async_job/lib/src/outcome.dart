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

/// An explicit cancellation, queue removal, or duplicate dropped by a policy.
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
  /// Set by the engine when it cascades; optional for domain engines that
  /// have no parent cancellation to attach.
  final Cancelled? cause;

  /// Creates a parent cancellation reason with its optional [cause].
  const ParentCancelReason({this.cause});

  @override
  String get name => 'parent';
}

/// A cancellation forwarded between jobs connected by [Job.then].
final class ChainCancelReason extends CancelReason {
  /// The cancellation of the adjacent job that caused this request.
  final Cancelled cause;

  /// Creates a chain cancellation preserving its [cause].
  const ChainCancelReason({required this.cause});

  @override
  String get name => 'chain';
}

/// The body gave up, directly or by letting a child's cancellation escape.
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
/// — the value, the error, the reason — not the outcome itself.
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

/// The job body threw [error].
///
/// The engine hands it to [JobObserver.onError] first. If nobody then
/// observes the job through [Job.done], [Job.value], [Job.ignore] or failure
/// forwarding by [Job.then], it hands [error] to the job's creation zone
/// through [Zone.handleUncaughtError]. The check runs on the microtask after
/// completion; a continuation attached within that grace period gets a
/// chance to receive the outcome first.
///
/// This is the error that has an outcome of its own. A body that throws
/// after its cancellation ends as [Cancelled] instead, and [Cancelled] is
/// never reported to the zone.
///
/// The errors with no outcome to carry them — a late failure of an action
/// [JobContext.wait] walked away from, a disposer, a callback of
/// [JobContext.onCancel] or [Job.whenCancelled], a failure of work handed
/// over with [JobContext.unattended] — take the other path:
/// [JobObserver.onError], or straight to the zone when there is no observer.
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
/// the job is marked cancelled — the ones that only register a cleanup go
/// on working — and stored in [Job.outcome]. A body may also
/// `throw Cancelled('why')` to cancel itself; the engine records that as
/// [HandlerCancelReason] and cancels the children of that body.
final class Cancelled extends Outcome<Never> implements Exception {
  /// Who cancelled the job.
  final CancelReason reason;

  /// `false` when the job was dropped before its body ran at all.
  final bool started;

  /// Details within [reason]: the text passed by the body, or whatever an
  /// engine of a domain writes there — `'is not Ready'`, `'canStart'`,
  /// `'keepWhile'`, `'duplicate'` in `solo`.
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
  /// A body may throw this to keep a custom [reason] and its data. The
  /// engine records the throw's stack trace and sets [started] to `true`.
  /// Domain engines also use it for their own cancellations, such as rules
  /// and closing in `solo`.
  ///
  /// [started] matters only where the cancellation becomes an outcome as
  /// it is, through `JobBase.finish`: on the way through `cancelWith` the
  /// engine sets it by the status of the job and whatever was passed here
  /// is replaced.
  const Cancelled.by({
    required this.reason,
    required this.started,
    this.description,
    this.stackTrace,
  });

  @override
  String toString() => description == null
      ? 'Cancelled(${reason.name})'
      : 'Cancelled(${reason.name}: $description)';
}
