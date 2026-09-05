part of 'solo_base.dart';

/// Why a job was cancelled.
///
/// Not an enum: an engine built on the core declares reasons of its own,
/// and an enum cannot be extended from another package. Reasons are equal
/// by [name], so a reason declared elsewhere with the same name is the
/// same reason here — a label for the journal and the observer, never a
/// value the engine branches on.
@immutable
final class CancelReason {
  /// [Job.cancel], [SoloQueue.remove], [SoloQueue.clear], or a duplicate
  /// dropped by [Policy.droppable].
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

/// The reasons `solo` adds to the core ones.
final class SoloCancelReason {
  /// `canStart`, `state is! W`, `keepWhile`, or [JobContext.stateAs].
  static const rules = CancelReason('rules');

  /// [SoloBase.close], or [SoloBase.add] after close.
  static const closed = CancelReason('closed');

  const SoloCancelReason._();
}

/// The result of a job: [Done], [Failed] or [Cancelled].
///
/// [Failed] and [Cancelled] extend `Outcome<Never>`, so a `switch` over
/// `Outcome<T>` with these three cases is exhaustive.
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
/// The engine reports it to [SoloBase.onError] and [SoloObserver.onError]
/// first. If nobody then observes the job — no [Job.done], no [Job.value],
/// no [Job.ignore] — the engine hands [error] to the zone the job was
/// created in, through [Zone.handleUncaughtError], one microtask after the
/// job finished. This is what Dart does with an unhandled [Future] error.
///
/// An error the engine learns about only through those hooks never reaches
/// the zone: a body that throws after cancellation, or an action abandoned
/// by [JobContext.wait] that fails later, both end as [Cancelled], and
/// [Cancelled] is never reported to the zone.
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
/// Thrown by every [JobContext] member once the job is marked cancelled,
/// and stored in [Job.outcome]. A body may also `throw Cancelled('why')`
/// to cancel itself; the engine records that as [CancelReason.handler].
final class Cancelled extends Outcome<Never> implements Exception {
  /// Who cancelled the job.
  final CancelReason reason;

  /// `false` when the job was dropped from the queue before it started.
  final bool started;

  /// Details within [reason]: `'is not Ready'`, `'canStart'`,
  /// `'keepWhile'`, `'duplicate'`, or the text passed by the body.
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
