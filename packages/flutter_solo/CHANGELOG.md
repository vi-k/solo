## Unreleased

- The notes at the end of the README became a table of the four questions
  they answer: when listeners run, whether equal states are filtered, how
  several controllers share a screen, and why `value` has no setter.
- **Breaking:** `SoloListenable.close` takes `solo`'s new `SoloCloseMode`
  and hands it on. Calls are unchanged; an override of `close` has to take
  the parameter too.
- **Fix:** a listener that throws is reported through
  `FlutterError.reportError`, the way `ChangeNotifier` reports one, and the
  listeners behind it still hear the change. Its error used to leave
  `publish` and skip the engine's re-evaluation of the rules that follows a
  state change, so a job could go on running against a state its
  `keepWhile` forbids.
- Notifying no longer looks each listener up in the list of all of them, so
  one pass is linear in their number rather than quadratic.
- Add `SoloSelection<S, T>`: a `ValueListenable` of one value picked out
  of another, notifying only when that value changes — by `!=`, or by a
  `compare` of your own answering whether it did. It subscribes to its
  source only while it has listeners and needs no disposal. The source is
  any `ValueListenable`, so a selection picks out of a controller, a
  `ValueNotifier` or another selection alike.
- Add `SoloSelector`, the widget that holds a selection for you: a
  `listenable`, a `selector` and a `builder`, and no `State` field to keep
  the selection in — a widget that picks can be a `StatelessWidget`.
- Add `select` and `listen` as methods, with `SoloSubscription` and
  `SoloSubscriptions`, in an import of their own,
  `package:flutter_solo/listenable.dart`. Both methods are extensions on
  the framework's own `ValueListenable` and `Listenable`, where another
  package's methods of the same name sit too: two extensions with one
  member name on one type are ambiguous at every call site, so the import
  is the choice rather than something every user of the package is given.
  Without it nothing is lost but the shorthand — `SoloSelection(...)`
  builds the same selection, and `SoloSelector` needs no method at all.

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
