import 'dart:async';

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
/// One rule for the controller and for `SoloObserver.all`, kept here so the two
/// cannot drift apart. Not exported.
void callHook(void Function() hook) {
  try {
    hook();
  } on Object catch (error, stackTrace) {
    Zone.current.handleUncaughtError(error, stackTrace);
  }
}
