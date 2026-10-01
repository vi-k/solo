import 'package:async_job/async_job.dart';

import 'solo.dart';

/// The base for reasons added by `solo` and engines built on it.
abstract class SoloCancelReason extends CancelReason {
  /// Creates a reason for a subclass.
  const SoloCancelReason();
}

/// `canStart`, `state is! W`, `keepWhile`, or [SoloContext.stateAs] failed.
final class RulesCancelReason extends SoloCancelReason {
  /// Creates a rule cancellation reason.
  const RulesCancelReason();

  @override
  String get name => 'rules';
}

/// [Solo.close], or [Solo.add] after close.
final class ClosedCancelReason extends SoloCancelReason {
  /// Creates a controller closing reason.
  const ClosedCancelReason();

  @override
  String get name => 'closed';
}

/// [Solo.add] under `Policy.droppable` found a job with the same key,
/// handed that one back and dropped this one before its body ran.
///
/// A reason of its own, apart from [ManualCancelReason]: nobody asked for
/// this job to stop, the controller already had the work it was asking
/// for.
final class DuplicateCancelReason extends SoloCancelReason {
  /// Creates a duplicate reason.
  const DuplicateCancelReason();

  @override
  String get name => 'duplicate';
}
