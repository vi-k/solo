part of 'job_base.dart';

/// Why a job was cancelled.
///
/// Not an enum: an engine built on the core declares reasons of its own,
/// and an enum cannot be extended from another package. Reasons are equal
/// by [name], so a reason declared elsewhere with the same name is the
/// same reason here — a label for the journal and the observer, never a
/// value the engine branches on.
@immutable
final class CancelReason {
  /// [Job.cancel], or an engine dropping a job of its own accord — a
  /// queue clearing itself, a duplicate a policy turned away.
  static const manual = CancelReason('manual');

  /// Cascade from a cancelled parent job.
  static const parent = CancelReason('parent');

  /// The job body threw `Cancelled` itself.
  static const handler = CancelReason('handler');

  /// The label of this reason.
  final String name;

  /// Creates a reason called [name].
  const CancelReason(this.name);

  @override
  bool operator ==(Object other) => other is CancelReason && name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
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
/// observes the job — no [Job.done], no [Job.value], no [Job.ignore] — it
/// hands [error] to the zone the job was
/// created in, through [Zone.handleUncaughtError], one microtask after the
/// job finished. This is what Dart does with an unhandled [Future] error.
///
/// This is the error that has an outcome of its own. A body that throws
/// after its cancellation ends as [Cancelled] instead, and [Cancelled] is
/// never reported to the zone.
///
/// The errors with no outcome to carry them — a late failure of an action
/// [JobContext.wait] walked away from, a disposer, a callback of
/// [JobContext.onCancel] — take the other path: [JobObserver.onError], or
/// straight to the zone when there is no observer.
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
/// [CancelReason.handler] and cancels the children of that body.
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
      : reason = CancelReason.handler,
        started = true,
        stackTrace = null;

  /// Creates a cancellation with a reason of your own.
  ///
  /// The engine of a domain uses it — `solo` for its rules and its
  /// closing; a body uses the unnamed constructor instead.
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
