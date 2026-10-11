## Unreleased

This package re-exports `solo` and, through it, `async_job`, so their changes
are its own: see
[the `solo` changelog](https://github.com/vi-k/solo/blob/main/packages/solo/CHANGELOG.md)
and
[the `async_job` changelog](https://github.com/vi-k/solo/blob/main/packages/async_job/CHANGELOG.md).

### Breaking changes

- **`ctx.wait` is renamed to `ctx.abandonable`** in `async_job`.
- **`Job.ignore()` is renamed to `Job.ignoreFailure()`** in `async_job`.
- **The state handlers of `run` and `job` are renamed in `solo`: `onError` to
  `ifFailed`, `onCancel` to `ifCancelled`.**
- **`SoloListenable` is a mixin on `Solo`,** the way `solo`'s `SoloStream` is:
  `extends SoloListenable<S>` becomes `extends Solo<S> with SoloListenable`.
  See
  [The controller as a `ValueListenable`](README.md#the-controller-as-a-valuelistenable).
- **`SoloListenable` no longer carries a stream.** A controller whose `stream`
  somebody reads mixes in both, `with SoloStream, SoloListenable`. See
  [A controller with both deliveries](doc/mixins.md#a-controller-with-both-deliveries).
- **In `solo`, the controller's synchronous read is `currentState`, not
  `state`.**
- **`ValueListenable` is no longer re-exported.** A file that names the type
  imports `package:flutter/foundation.dart`.
- **`close` takes `solo`'s new `SoloCloseMode`.**
- **`publish` is no longer a public member of a controller with
  `SoloListenable`.**
- **The listeners are dropped when the engine finishes closing, right after the
  observer's `onClose` and the controller's own.** Write the last state
  synchronously, in the controller's `onClose`.

### Changes you will see on upgrade

- A listener that throws is reported through `FlutterError.reportError`, the
  way `ChangeNotifier` reports one, and no longer throws out of the `emit` or
  the `externalSetState` that made the change: the job whose `emit` it was ends
  `Done` where it used to end `Failed`.
- Errors that `0.2.0` kept to the hooks reach `Solo.unansweredHandler` or the
  zone: see the same heading of
  [the `solo` changelog](https://github.com/vi-k/solo/blob/main/packages/solo/CHANGELOG.md).

### Added

- `SoloBuilder`: what `ValueListenableBuilder` is, for a controller that is not
  a `ValueListenable`. See [Usage](README.md#usage).
- `SoloSelection<S, T>`: a `ValueListenable` of one value picked out of
  another, notifying only when that value changes. See
  [Selecting one value](README.md#selecting-one-value).
- `SoloSelector`, the widget that picks for you: a controller, a `selector` and
  a `builder`.
- `select` and `listen` as methods, with `SoloSubscription` and
  `SoloSubscriptions`, in an import of their own,
  `package:flutter_solo/listenable.dart`. See
  [Listening without keeping the callback](README.md#listening-without-keeping-the-callback)
  and [Methods from a second import](README.md#methods-from-a-second-import).

### Fixed

- A listener that throws no longer cuts off the listeners behind it, and no
  longer lets a job go on running against a state its `keepWhile` forbids.
- A listener registered after the controller had finished closing is refused;
  it was kept in memory for good.
- One pass of notifying is linear in the number of listeners; it was quadratic.

### Documentation

- The README's examples compile, and the page gained the sections on the
  controller as a `ValueListenable`, on selections and on `listen`.
- The package has a guide of its own, [Mixins](doc/mixins.md).
- The example no longer sticks on a failed load.

## 0.2.0

The first published release. 0.1.0 never left the tree.

- `SoloListenable<S>`: a `Solo<S>` that is also a `ValueListenable<S>`, for
  `ValueListenableBuilder`, `ListenableBuilder`, `AnimatedBuilder` and
  `Listenable.merge`. Listeners are called synchronously, in subscription
  order, on every state change; the `stream` of `Solo` still works and arrives
  a microtask later.
- Read-only on purpose: `value` and `state` are the same object, and there is
  no setter — the state belongs to the jobs.
- `close()` cancels what is running, drops every listener and stops notifying
  for good; nothing else closes the controller for you.
- Re-exports `package:solo/solo.dart`, which re-exports
  `package:async_job/async_job.dart`, so `flutter_solo` is the only dependency
  an app adds and the only import it writes.
- Floor: `solo: ^0.2.0`, whose job kernel is `async_job: ^0.2.0` with
  synchronous `job.whenCancelled(callback)` registration.

## 0.1.0

Never published.
