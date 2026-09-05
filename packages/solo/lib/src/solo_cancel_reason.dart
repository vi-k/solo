import 'package:jobs/jobs.dart';

import 'solo_base.dart';

/// The reasons `solo` adds to the core ones.
final class SoloCancelReason {
  /// `canStart`, `state is! W`, `keepWhile`, or [SoloContext.stateAs].
  static const rules = CancelReason('rules');

  /// [SoloBase.close], or [SoloBase.add] after close.
  static const closed = CancelReason('closed');

  const SoloCancelReason._();
}
