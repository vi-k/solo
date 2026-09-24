## Unreleased

- **Breaking, inherited from `solo`:** `Solo.onError` is a notice with an empty
  body, and the route for an error nobody answered for moved to the new hook
  `Solo.onUnanswered`. A controller of this package that overrode `onError`
  without calling `super` no longer keeps such an error out of
  `Solo.errorHandler` and the creation zone; move that body to `onUnanswered`.
  Read the `solo` entry before migrating:
  [the `solo` changelog](https://github.com/vi-k/solo/blob/main/packages/solo/CHANGELOG.md).

- **Breaking, inherited from `solo` and `async_job`:** this package re-exports
  both, so their breaking changes are its own. From `solo`: `SoloBase` becomes
  `Solo` and the stream moves to the mixin `SoloStream`; `job`, `add`, `run`,
  `collect` and `accumulate` are protected, so a controller's operations are
  its own methods; the synchronous read is `currentState`; `close` takes a
  `SoloCloseMode`; the change hooks take a `SoloTransition`; the state of a
  closed controller is final, and `isFinished` is the guard before an external
  fact; `Solo` carries its own listeners; an observer no longer answers for an
  error, `Solo.errorHandler` does; `collect` and `accumulate` default to
  `AccumulationPolicy.join`, and `replace` moves the waiting group's job
  instead of cancelling it; `Policy.droppable` compares the result types of the
  two jobs and throws `ArgumentError` when they differ. From `async_job`,
  through `solo`: a cancellation inside a `ParallelWaitError` is a cancellation
  again, so the job's `onCancel` handler takes the outcome where `onError` used
  to; `JobContext` gains `runAll`; `ctx.run` takes `dispose` and `discard`;
  `JobBase`, `JobContextBase` and `JobStatus` move to
  `package:async_job/engine.dart` and are no longer visible through this
  package. Migrate with the entries of both:
  [the `solo` changelog](https://github.com/vi-k/solo/blob/main/packages/solo/CHANGELOG.md)
  and
  [the `async_job` changelog](https://github.com/vi-k/solo/blob/main/packages/async_job/CHANGELOG.md).

- **Breaking:** `SoloListenable` is a mixin now, the way `solo`'s `SoloStream`
  is: `mixin SoloListenable<S extends Object> on Solo<S> implements
  ValueListenable<S>`. `extends SoloListenable<S>` becomes
  `extends Solo<S> with SoloListenable`, the type argument inferred from the
  superclass, and a controller that needs a `stream` too writes
  `with SoloStream, SoloListenable`. `SoloListenable<S>(value)` no longer
  compiles -- mixins can't be instantiated -- and a one-line class takes its
  place: `class C<S extends Object> = Solo<S> with SoloListenable;`. Code that
  calls `run` on it from outside needs a method of its own instead, `run` being
  protected now, as the entry above says. In a type position the argument is
  written out, `SoloListenable<S>`; the analyzer does not ask for it, and a
  bare `SoloListenable` there is a `SoloListenable<Object>`. The migration
  keeps who reports a listener's failure: a base that mixes `SoloListenable` in
  and overrides `onListenerError` still wins. What the mixin opens is a base
  class without Flutter, with the mixin on the leaf, and there the mixin's
  report overrides the base's; a base that wants its own keeps it in a method
  of another name for the leaf's override to call. This rides on `solo`'s
  rename -- `SoloBase` becomes `Solo`, the stream-carrying `Solo` becomes the
  mixin `SoloStream` -- after which nothing else in this package changes shape:
  `SoloBuilder`, `SoloSelection.from` and the rest already took the widest
  engine type, and every mention of `SoloBase` in a signature or a doc comment
  reads `Solo`.

- **Breaking:** `ValueListenable` is no longer re-exported.
  `package:flutter/widgets.dart` does not export it either, so a file that
  names the type imports `package:flutter/foundation.dart`; a file that only
  hands a controller to `ValueListenableBuilder` needs nothing new.

- `SoloBuilder` no longer keeps a copy of the state. It subscribes, and every
  rebuild reads `Solo.currentState`; the field, the two reads that filled it
  and the promise in the dartdoc are gone together. The copy could differ from
  a fresh read in one place only -- a closed controller whose state moved on
  with nobody told -- and `solo` no longer lets the state move there.

- `SoloSelector` keeps the subscription to its selection itself instead of
  wrapping a `ValueListenableBuilder` around it. Behaviour is unchanged -- the
  value is read after subscribing, kept until the next notification, moved
  across when the selection is rebuilt, and let go in `dispose` -- but the
  widget tree is one element shorter under it, and the lifecycle now lives in
  one place rather than in two nested states. A test that looked for a
  `ValueListenableBuilder` under it will no longer find one.
- Add `SoloBuilder`: what `ValueListenableBuilder` is, for a controller that is
  not a `ValueListenable`. It takes any `Solo` -- one `with SoloStream`
  included -- subscribes in `initState`, reads the controller's state on every
  build, compares controllers by identity when the parent hands over a new one,
  and passes `child` through untouched.
- Add `SoloSelection.from`: a selection straight from a controller, for the
  controllers that are not `ValueListenable` -- one built with `SoloStream`,
  and anything else that extends `Solo`. It is a static method rather than a
  constructor because a constructor introduces no type parameters of its own,
  and the class leaves `S` unbounded while `Solo` requires `S extends Object`;
  the existing constructor, nullable sources included, is untouched.
- **Fix:** the first value of a source that publishes while it is being
  subscribed to reaches the widget. The selection used to subscribe before
  registering the incoming listener, so a value arriving in that window updated
  the pick when there was nobody to notify, and `ValueListenableBuilder` --
  which reads the value before subscribing -- stayed on the old one. The
  listener is registered first now, the pick is read again after the
  subscription when the source moved during it, and a change found there is
  announced on a microtask: announcing it synchronously would land in the
  caller's `initState`, where `setState` throws. A subscription that throws
  leaves neither the registration nor the source listener behind.

- **Fix:** a selection counts registrations, not callbacks. The same callback
  registered twice is called twice and removed one registration at a time, and
  a registration cancelled during a notification pass is skipped rather than
  called anyway -- which is what happened before, because the container asked
  whether the callback was still registered and could not tell one registration
  from another. A callback removed and added again during a pass now waits for
  the next change, as the rule says.
- **Fix:** a listener failure is reported through `FlutterError.reportError`,
  and if the report itself throws -- an `onError` of the application's own --
  the pass no longer stops there. The remaining listeners of that selection
  hear the change, and the reporter's error goes to the zone.

- `SoloListenable` keeps only the `ValueListenable` face: the listeners, the
  registration and the pass over them moved into `solo`'s `Solo`, and what
  stays here is `value` and the report of a listener's failure through
  `FlutterError.reportError`. It behaves as it did, with one exception below.
- **Fix:** a listener registered after the engine had finished closing was kept
  in memory for good. It was never notified -- a flag saw to that -- but it was
  held; now the registration is refused outright and nothing is retained.
- **Breaking:** a change delivered from a microtask scheduled inside the
  observer's `onClose` no longer reaches listeners -- and with `solo` freezing
  the state of a closed controller, it is no longer a change at all: the engine
  has finished by then, so `externalSetState` from there throws a `StateError`.
  The list used to be dropped one microtask later, in the continuation of the
  engine's close; the engine now drops it synchronously, right after the hook.
  A change made *inside* the hook still reaches them.

- **Breaking:** `SoloListenable` no longer carries a stream of its own. The
  listeners are its whole delivery: a widget rebuilds from `value`, and an
  operation's result is awaited through its `Job`, so the broadcast
  `StreamController` every controller used to carry — created with it, fed on
  every change and closed afterwards — is gone. Mix in `SoloStream` (above) for
  a controller that needs both.

- **Breaking:** the controller's synchronous read is `solo`'s new
  `currentState`, so `SoloListenable.state` is gone. `value` is unchanged and
  is still the same object; a widget that reads the controller directly reads
  `currentState`.

- The notes at the end of the README became a table of the four questions they
  answer: when listeners run, whether equal states are filtered, how several
  controllers share a screen, and why `value` has no setter.
- **Breaking:** `SoloListenable.close` takes `solo`'s new `SoloCloseMode` and
  hands it on. Calls are unchanged; an override of `close` has to take the
  parameter too.
- **Fix:** a listener that throws is reported through
  `FlutterError.reportError`, the way `ChangeNotifier` reports one, and the
  listeners behind it still hear the change. Its error used to leave `publish`
  and skip the engine's re-evaluation of the rules that follows a state change,
  so a job could go on running against a state its `keepWhile` forbids.
- Notifying no longer looks each listener up in the list of all of them, so one
  pass is linear in their number rather than quadratic.
- Add `SoloSelection<S, T>`: a `ValueListenable` of one value picked out of
  another, notifying only when that value changes — by `!=`, or by a `changed`
  of your own answering whether it did. It subscribes to its source only while
  it has listeners and needs no disposal. The source is any `ValueListenable`,
  so a selection picks out of a controller, a `ValueNotifier` or another
  selection alike.
- Add `SoloSelector`, the widget that holds a selection for you: a controller,
  a `selector` and a `builder`, and no `State` field to keep the selection in —
  a widget that picks can be a `StatelessWidget`. It is to `SoloBuilder` what a
  pick is to the whole state: it takes any `Solo`, `SoloListenable` or not, and
  holds its selection across a parent rebuild, so the value `changed` answers
  from survives one. A `ValueListenable` that is not a controller is picked
  from with a `SoloSelection` and a `ValueListenableBuilder`.
- Add `select` and `listen` as methods, with `SoloSubscription` and
  `SoloSubscriptions`, in an import of their own,
  `package:flutter_solo/listenable.dart`. Both methods are extensions on the
  framework's own `ValueListenable` and `Listenable`, where another package's
  methods of the same name sit too: two extensions with one member name on one
  type are ambiguous at every call site, so the import is the choice rather
  than something every user of the package is given. Without it nothing is lost
  but the shorthand — `SoloSelection(...)` builds the same selection, and
  `SoloSelector` needs no method at all.

- **Fix:** `SoloSubscriptions.cancel()` never throws. A member that refused to
  let go had its error thrown once the pass was over, and the place for this
  call is `State.dispose()`: an exception out of `dispose()` stops the
  framework unmounting the rest of that frame, so the elements queued behind
  this one never get a `dispose()` at all and their listeners stay registered
  -- the very leak this class exists to prevent, one widget further along.
  Every failure goes to `FlutterError.reportError` now, the first one included.
  A caller that wrapped the call in a `try` to keep its frame can drop the
  wrapper.

- **Fix:** `SoloListenable.onListenerError` carries `@protected` again. Dart
  does not inherit the annotation and the override left it off, so a hook of
  the engine was an ordinary public member of every controller with this mixin,
  and would have gone into `dart doc` as one. Taking it back after a release is
  a breaking change; taking it back now is not.

- **Fix:** `SoloSelector` picks once per occasion, which is what its dartdoc
  promised: once on mounting, once when the parent hands over a new selector,
  once per change of the state. It picked four times and twice. The constructor
  of `SoloSelection` made a pick the first subscription always replaced, the
  pick was taken again after subscribing whether or not the source had moved,
  and the widget read `value` back, which picked once more. A subscribed
  selection keeps its last pick together with the source value it came from and
  answers `value` from it while that value stands, so a selector is expected to
  give the same answer for the same value -- which a pick does. A source that
  changes its value in place and says so is still picked afresh on its
  notification, and a selection nobody listens to picks on every read, as
  before. Two things move: a selector that throws does so on the first read or
  subscription rather than in the constructor, and a selector that returns a
  new object every time no longer gets a notification on subscribing to a
  source that did not move.

- The example no longer sticks on a failed load. Its job left the state on
  `Loading` whatever the outcome, so the third load -- the one the fake service
  fails -- left a spinner with nothing to tap, for good. The job falls back to
  `Empty` when it fails or is cancelled, the screen offers `Cancel` while a
  load runs and a reload in every state, and the example has widget tests of
  its own, run in the repository's CI: a load, a failed load and the one after
  it, a cancel, and a tap that `Policy.droppable` hands the running job.

- The README's examples compile, and every Dart block of the page is built and
  run in the repository's CI now. The model under Usage declares the `canSave`
  and the `save` the rest of the page relied on -- `save` works with `Loaded`
  only, so it does not start before there is a profile. Running the page turned
  up one more thing it said wrongly: a second tap is not what a `Cancelled`
  from `load()` means, because `Policy.droppable` hands the second tap the
  first job.

- The README's selection held in a `State` field follows a new controller: the
  recipe builds it again in `didUpdateWidget`. As written it kept picking from
  the controller the `State` was first given, while the button saved to the one
  the parent handed over later. The dartdoc of `SoloSelection` says the same,
  and the section on `listen` says it about subscriptions taken in `initState`.

- The package has a guide of its own, `doc/mixins.md`, with what the README
  leaves out: a controller with both `SoloListenable` and `SoloStream`, a
  screen built on that stream, and a base class of controllers without Flutter,
  with the mixin on the leaf. The page came from `solo`'s documentation, where
  it opened with a tour that repeated this README and advised the other widget;
  the README keeps the tour, and now says what sets `SoloBuilder` apart from
  `ValueListenableBuilder`.

- The README no longer says that a `SoloObserver` takes a failure of work
  handed to `ctx.unattended`. An observer watches; `Solo.errorHandler` or an
  override of `onError` is what answers for such a failure, and without either
  it goes to the zone.

- **Breaking:** `SoloSubscriptions.length` counts the subscriptions the group
  would cancel. A member cancelled on its own leaves the group now, where the
  group used to hold it for good: `length` counted it, and the listener and
  whatever its closure held stayed alive for as long as the group did -- the
  leak the class exists to prevent, one object further along. A group handed a
  subscription that is already cancelled keeps nothing either. Migration: code
  that read `length` as "how many have ever been added" needs a counter of its
  own.

- **Fix:** a listener of a `SoloSelection` that throws is reported with the
  selection named, `SoloSelection<Profile, String>#a1b2c` rather than the bare
  type, the way `SoloListenable` names a controller. If
  `FlutterError.reportError` itself throws, the listener's failure is no longer
  lost with it: both go to the zone, the listener's first.

- The README's `load` falls back to `Empty` when it fails or is cancelled. As
  written it left the state on `Loading` -- a spinner, and nothing on the
  screen to tap -- which is the gap the package's example closed earlier;
  `onError` and `onCancel` are what close it here.

- The listener list behind `SoloSelection` is `solo`'s: this package no longer
  keeps a copy of the mechanics, and takes `Listeners` from
  `package:solo/listeners.dart`. Reporting a listener's failure through
  `FlutterError` stays here, where Flutter is.

- `doc/mixins.md` opens two of its sections with the version the vocabulary of
  the framework and of the engine leads to: a `StreamBuilder` over the
  controller's `stream`, and an override of `onListenerError` in a base class
  without Flutter, which the mixin on the leaf silences. `initialData` stands
  as a second attempt: `StreamBuilder` reads it once, and handed another
  controller it keeps showing the first one's state. The section on both
  deliveries says where a failure of a `stream` subscriber goes and what holds
  `close()`, and the overrides on the page repeat `@protected`, which Dart does
  not inherit.

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
