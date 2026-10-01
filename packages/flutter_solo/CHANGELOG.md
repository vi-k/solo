## Unreleased

Moving from `0.2.0`: read "Breaking changes" for what stops compiling or
behaves differently, and "Changes you will see on upgrade" for what a test
shows with no change to the code. This package re-exports `solo` and, through
it, `async_job`, so their breaking changes are its own; the last entry of the
first group names them.

### Breaking changes

- **`SoloListenable` is a mixin on `Solo`,** the way `solo`'s `SoloStream` is:
  `mixin SoloListenable<S extends Object> on Solo<S> implements
  ValueListenable<S>`. It rides on `solo`'s rename — `SoloBase` becomes `Solo`,
  and the stream-carrying `Solo` becomes the mixin `SoloStream`. What the mixin
  opens is a base class of controllers without Flutter, with the mixin on the
  leaf. A class that mixes `SoloListenable` in and overrides `onListenerError`
  keeps its own report; a base without Flutter under a leaf with the mixin
  loses its override to the mixin's, and keeps the report in a method of
  another name for the leaf's override to call. **Migrating.**
  `extends SoloListenable<S>` becomes `extends Solo<S> with SoloListenable`,
  the type argument inferred from the superclass. `SoloListenable<S>(value)` no
  longer compiles — a mixin cannot be instantiated — and a one-line class takes
  its place: `class C<S extends Object> = Solo<S> with SoloListenable;`. In a
  type position the argument is written out, `SoloListenable<S>`: the analyzer
  does not ask for it, and a bare `SoloListenable` there is a
  `SoloListenable<Object>`. See
  [A base class without Flutter](doc/mixins.md#a-base-class-without-flutter).

- **`SoloListenable` no longer carries a stream.** The listeners are its whole
  delivery: a widget rebuilds from `value`, and an operation's result is
  awaited through its `Job`, so the broadcast `StreamController` every
  controller used to carry — created with it, fed on every change and closed
  afterwards — is gone. **Migrating.** A controller whose `stream` somebody
  reads mixes in both, `with SoloStream, SoloListenable`. See
  [A controller with both deliveries](doc/mixins.md#a-controller-with-both-deliveries).

- **The synchronous read is `solo`'s `currentState`, so `SoloListenable.state`
  is gone.** `value` is unchanged and is the same object. **Migrating.** A
  widget that read `controller.state` reads `controller.currentState` or
  `controller.value`.

- **`ValueListenable` is no longer re-exported.**
  `package:flutter/widgets.dart` does not export it either. **Migrating.** A
  file that names the type imports `package:flutter/foundation.dart`; a file
  that only hands a controller to `ValueListenableBuilder` needs nothing new.

- **`SoloListenable.close` takes `solo`'s new `SoloCloseMode` and hands it
  on.** Calls are unchanged. **Migrating.** An override of `close` takes the
  parameter too and passes it to `super.close(mode: mode)`.

- **The listeners are dropped when the engine finishes closing, right after the
  observer's `onClose` and the controller's own.** They used to be dropped a
  few microtasks later, once the stream had closed after the engine, so a
  change made from a microtask scheduled inside the observer's `onClose` still
  reached them. Now it is not a change at all: `solo` freezes the state of a
  closed controller, and `externalSetState` from there throws a `StateError`. A
  change made inside the hook itself still reaches the listeners.
  **Migrating.** Write the last state synchronously, in the controller's
  `onClose`.

- **Inherited from `solo` and `async_job`.** From `solo`: `SoloBase` becomes
  `Solo` and the stream moves to the mixin `SoloStream`; `job`, `add`, `run`,
  `collect` and `accumulate` are protected, so a controller's operations are
  its own methods; the synchronous read is `currentState`; `close` takes a
  `SoloCloseMode`; the change hooks take a `SoloTransition`; the state of a
  closed controller is final, `isFinished` is the guard before an external fact
  and `onClose` is where a controller stops its source; `Solo` carries its own
  listeners; `Solo.onError` is a notice, the new `Solo.onUnanswered` answers
  for an error no outcome carries, and an observer no longer keeps such an
  error out of `Solo.errorHandler` and the zone; `collect` and `accumulate`
  default to `AccumulationPolicy.join`, and `replace` moves the waiting group's
  job instead of cancelling it; `Policy.droppable` compares the result types of
  the two jobs and throws `ArgumentError` when they differ, and the job it
  drops ends with a `DuplicateCancelReason` instead of a `ManualCancelReason`;
  `SoloQueue.lastWhere` is gone; `cancelAll` and the removing methods of
  `SoloQueue` take a `reason`; a subclass member named like a new member of
  `Solo` stops compiling or overrides it, `isFinished` silently. From
  `async_job`, through `solo`: a cancellation inside a `ParallelWaitError` is a
  cancellation again, so the job's `onCancel` handler takes the outcome where
  `onError` used to; a body that throws `Cancelled` runs its `ctx.onCancel`
  callbacks, and `whenCancelled` fires as it throws; `JobContext` gains
  `runAll` and `ctx.run` takes `dispose` and `discard`, so a class that
  implements `JobContext` or `SoloContext` by hand, a test fake for one, needs
  both; `JobObserver.onError` is a notice and the new `JobAnswerer` answers for
  an error no outcome carries; the core's debug switch `JobBase.debug` is
  `Job.debug`; `JobBase`, `JobContextBase` and `JobStatus` move to
  `package:async_job/engine.dart` and are no longer visible through this
  package. **Migrating.** Read the entries of both:
  [the `solo` changelog](https://github.com/vi-k/solo/blob/main/packages/solo/CHANGELOG.md)
  and
  [the `async_job` changelog](https://github.com/vi-k/solo/blob/main/packages/async_job/CHANGELOG.md).

### Changes you will see on upgrade

- A listener that throws is reported through `FlutterError.reportError`, the
  way `ChangeNotifier` reports one, and no longer throws out of the `emit` or
  the `externalSetState` that made the change. The job whose `emit` it was ends
  `Done` where it used to end `Failed`, and a widget test fails on the reported
  error instead.
- Errors that `0.2.0` kept to the hooks reach `Solo.errorHandler` or the zone:
  the first section of
  [the `solo` changelog](https://github.com/vi-k/solo/blob/main/packages/solo/CHANGELOG.md)
  under the same heading.

### Added

- Inherited from `solo` and `async_job`: `SoloObserver.all` and
  `JobObserver.all`, one observer made of several.

- Inherited from `async_job`: `Job.visitErrors`, each failure inside an error
  on its own and the cancellations apart.

- `SoloBuilder`: what `ValueListenableBuilder` is, for a controller that is not
  a `ValueListenable`. It takes any `Solo` — one `with SoloStream` included —
  subscribes in `initState`, reads the controller's state on every build,
  compares controllers by identity when the parent hands over a new one, and
  passes `child` through untouched. See
  [Builders for any controller](README.md#builders-for-any-controller).

- `SoloSelection<S, T>`: a `ValueListenable` of one value picked out of
  another, notifying only when that value changes — by `!=`, or by a `changed`
  of your own answering whether it did. It subscribes to its source only while
  it has listeners and needs no disposal. The source is any `ValueListenable`,
  so a selection picks out of a controller, a `ValueNotifier` or another
  selection alike, and `SoloSelection.from` builds one straight from a
  controller that is not a `ValueListenable`. A listener that throws is
  reported through `FlutterError.reportError` with the selection named, and the
  listeners behind it still hear the change. See
  [Selecting one value](README.md#selecting-one-value).

- `SoloSelector`, the widget that holds a selection for you: a controller, a
  `selector` and a `builder`, and no `State` field to keep the selection in — a
  widget that picks can be a `StatelessWidget`. It takes any `Solo`,
  `SoloListenable` or not, holds its selection across a parent rebuild, and
  picks once per occasion: once on mounting, once when the parent hands over a
  new selector, once per change of the state.

- `select` and `listen` as methods, with `SoloSubscription` and
  `SoloSubscriptions`, in an import of their own,
  `package:flutter_solo/listenable.dart`. Both methods are extensions on the
  framework's own `ValueListenable` and `Listenable`, where another package's
  methods of the same name sit too: two extensions with one member name on one
  type are ambiguous at every call site, so the import is the choice rather
  than something every user of the package is given.
  `SoloSubscriptions.cancel()` never throws, so it is safe in
  `State.dispose()`: a member that refuses to let go is reported through
  `FlutterError.reportError`. See
  [Listening without keeping the callback](README.md#listening-without-keeping-the-callback)
  and [Methods from a second import](README.md#methods-from-a-second-import).

### Fixed

- A listener that throws no longer costs a job its cancellation. Its error left
  `publish` and skipped the engine's re-evaluation of the rules that follows a
  state change, so a job could go on running against a state its `keepWhile`
  forbids. It is reported through `FlutterError.reportError` now, and the
  listeners behind it still hear the change.
- A listener registered after the controller had finished closing was kept in
  memory for good. It was never notified, but it was held; now the registration
  is refused outright and nothing is retained.
- Notifying no longer looks each listener up in the list of all of them, so one
  pass is linear in their number rather than quadratic.

### Documentation

- The README's examples compile, and every Dart block of the page is built and
  run in the repository's CI. It gained the sections on selections, builders
  and `listen`, its `load` falls back to `Empty` when it fails or is cancelled
  instead of leaving a spinner, and the notes at its end became a table of the
  four questions they answer.
- The package has a guide of its own, [Mixins](doc/mixins.md): a controller
  with both `SoloListenable` and `SoloStream`, a screen built on that stream,
  and a base class of controllers without Flutter, with the mixin on the leaf.
- The example no longer sticks on a failed load: the job falls back to `Empty`
  when it fails or is cancelled, the screen offers `Cancel` while a load runs
  and a reload in every state, and the example has widget tests of its own.

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
