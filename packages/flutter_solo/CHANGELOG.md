## Unreleased

- `SoloBuilder` no longer keeps a copy of the state. It subscribes, and every
  rebuild reads `SoloBase.currentState`; the field, the two reads that filled
  it and the promise in the dartdoc are gone together. The copy could differ
  from a fresh read in one place only -- a closed controller whose state moved
  on with nobody told -- and `solo` no longer lets the state move there.

- `SoloSelector` and `SoloSelectBuilder` keep the subscription to their
  selection themselves instead of wrapping a `ValueListenableBuilder` around
  it. Behaviour is unchanged -- the value is read after subscribing, kept until
  the next notification, moved across when the selection is rebuilt, and let go
  in `dispose` -- but the widget tree is one element shorter under each of
  them, and the lifecycle now lives in one place rather than in two nested
  states. A test that looked for a `ValueListenableBuilder` under them will no
  longer find one.
- Add `SoloBuilder` and `SoloSelectBuilder`: what `ValueListenableBuilder` and
  `SoloSelector` are, for a controller that is not a `ValueListenable`. Both
  take any `SoloBase` -- a plain `Solo` included -- read the state after
  subscribing and cache it, compare controllers by identity when the parent
  hands over a new one, and pass `child` through untouched. `SoloSelectBuilder`
  holds its selection across a parent rebuild, so the baseline `compare`
  answers from survives one; it carries no `buildWhen`, because picking a value
  is what it does.
- Add `SoloSelection.of`: a selection straight from a controller, for the
  controllers that are not `ValueListenable` -- `Solo` and anything else built
  on `SoloBase`. It is a static method rather than a constructor because a
  constructor introduces no type parameters of its own, and the class leaves
  `S` unbounded while `SoloBase` requires `S extends Object`; the existing
  constructor, nullable sources included, is untouched.
- **Fix:** the first value of a source that publishes while it is being
  subscribed to reaches the widget. The selection used to subscribe before
  registering the incoming listener, so a value arriving in that window updated
  the pick when there was nobody to notify, and `ValueListenableBuilder` --
  which reads the value before subscribing -- stayed on the old one. The
  listener is registered first now, the pick is read again after the
  subscription, and a change found there is announced on a microtask:
  announcing it synchronously would land in the caller's `initState`, where
  `setState` throws. A subscription that throws leaves neither the registration
  nor the source listener behind.

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
  registration and the pass over them moved into `solo`'s `SoloBase`, and what
  stays here is `value` and the report of a listener's failure through
  `FlutterError.reportError`. The class behaves as it did, with one exception
  below.
- **Fix:** a listener registered after `close` had finished was kept in memory
  for good. It was never notified -- a flag saw to that -- but it was held; now
  the registration is refused outright and nothing is retained.
- A change delivered from a microtask scheduled inside the observer's `onClose`
  no longer reaches listeners -- and with `solo` freezing the state of a closed
  controller, it is no longer a change at all: the engine has finished by then,
  so `externalSetState` from there throws a `StateError`. The list used to be
  dropped one microtask later, in the continuation of the engine's close; the
  engine now drops it synchronously, right after the hook. A change made
  *inside* the hook still reaches them.

- **Breaking:** `SoloListenable` is built on `SoloBase`, not on `Solo`, and has
  no `stream`. The listeners are its whole delivery: a widget rebuilds from
  `value`, and an operation's result is awaited through its `Job`, so the
  broadcast `StreamController` every controller used to carry — created with
  it, fed on every change and closed afterwards — is gone. A controller no
  longer fits where a `Solo<S>` is expected; `SoloBase<S>` is the type that
  covers both.

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
  another, notifying only when that value changes — by `!=`, or by a `compare`
  of your own answering whether it did. It subscribes to its source only while
  it has listeners and needs no disposal. The source is any `ValueListenable`,
  so a selection picks out of a controller, a `ValueNotifier` or another
  selection alike.
- Add `SoloSelector`, the widget that holds a selection for you: a
  `listenable`, a `selector` and a `builder`, and no `State` field to keep the
  selection in — a widget that picks can be a `StatelessWidget`.
- Add `select` and `listen` as methods, with `SoloSubscription` and
  `SoloSubscriptions`, in an import of their own,
  `package:flutter_solo/listenable.dart`. Both methods are extensions on the
  framework's own `ValueListenable` and `Listenable`, where another package's
  methods of the same name sit too: two extensions with one member name on one
  type are ambiguous at every call site, so the import is the choice rather
  than something every user of the package is given. Without it nothing is lost
  but the shorthand — `SoloSelection(...)` builds the same selection, and
  `SoloSelector` needs no method at all.

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
