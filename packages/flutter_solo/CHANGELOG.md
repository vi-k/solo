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
- Floor: `solo: ^0.2.0`, whose job kernel lives in `package:async_job`.

## 0.1.0

Never published.
