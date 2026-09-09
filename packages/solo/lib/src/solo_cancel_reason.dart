import 'package:async_job/async_job.dart';

import 'solo_base.dart';

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

/// [SoloBase.close], or [SoloBase.add] after close.
final class ClosedCancelReason extends SoloCancelReason {
  /// Creates a controller closing reason.
  const ClosedCancelReason();

  @override
  String get name => 'closed';
}
