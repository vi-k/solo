## Unreleased

- **Fix:** a listener that throws is reported through
  `FlutterError.reportError`, the way `ChangeNotifier` reports one, and the
  listeners behind it still hear the change. Its error used to leave
  `publish` and skip the engine's re-evaluation of the rules that follows a
  state change, so a job could go on running against a state its
  `keepWhile` forbids.
- Notifying no longer looks each listener up in the list of all of them, so
  one pass is linear in their number rather than quadratic.

## 0.2.0

The first published release. 0.1.0 never left the tree.

- `SoloListenable<S>`: a `Solo<S>` that is also a `ValueListenable<S>`,
  for `ValueListenableBuilder`, `ListenableBuilder`, `AnimatedBuilder`
  and `Listenable.merge`. Listeners are called synchronously, in
  subscription order, on every state change; the `stream` of `Solo`
  still works and arrives a microtask later.
- Read-only on purpose: `value` and `state` are the same object, and
  there is no setter — the state belongs to the jobs.
- `close()` cancels what is running, drops every listener and stops
  notifying for good; nothing else closes the controller for you.
- Re-exports `package:solo/solo.dart`, which re-exports
  `package:async_job/async_job.dart`, so `flutter_solo` is the only dependency
  an app adds and the only import it writes.
- Floor: `solo: ^0.2.0`, whose job kernel is `async_job: ^0.2.0`
  with synchronous `job.whenCancelled(callback)` registration.

## 0.1.0

Never published.
