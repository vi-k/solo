import 'dart:async';

import 'package:async_job/async_job.dart';

/// Calls [hook] and hands whatever it throws to the current zone, the way
/// Dart reports an unhandled `Future` error.
///
/// Hooks are a cross-cutting channel — analytics, logging, error reporting —
/// called independently of each other and of the job. A failure in one is
/// therefore not allowed to change anything else: not a job's outcome, not the
/// queue, not the closing. Each call is isolated on its own, so a throwing
/// observer does not switch off the instance hook standing next to it, or the
/// observer after it in `SoloObserver.all`.
///
/// A cancellation stays out of the zone, as it does in the core: a
/// [Cancelled], or a `ParallelWaitError` carrying nothing but cancellations.
/// A hook meets one without doing anything wrong — a log message built
/// lazily reads the state of a job cancelled by then — and a cancellation
/// reaching the zone says nothing anybody can act on.
///
/// One rule for the controller and for `SoloObserver.all`, kept here so the two
/// cannot drift apart. Not exported.
void callHook(void Function() hook) {
  try {
    hook();
  } on Object catch (error, stackTrace) {
    reportHookError(error, stackTrace);
  }
}

/// Hands [error], thrown by a hook, to the current zone unless it is a
/// cancellation.
///
/// For the one hook that is not called through [callHook]:
/// `onListenerError`, whose guard has the listener's own error to report
/// first.
void reportHookError(Object error, StackTrace stackTrace) {
  var failed = false;
  Job.visitErrors(
    error,
    stackTrace,
    onFailure: (_, __) => failed = true,
  );
  if (failed) {
    Zone.current.handleUncaughtError(error, stackTrace);
  }
}
