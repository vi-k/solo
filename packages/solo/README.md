# solo

State management for controllers with a lifecycle: one job at a time,
exclusive state ownership, declarative rules and cooperative cancellation.
Pure Dart, no Flutter dependency;
[`flutter_solo`](https://pub.dev/packages/flutter_solo) adds the
`ValueListenable` face.

## Why

`solo` is a controller: it owns one state, runs jobs over that state one
at a time, and cancels them by rules you declare instead of flags you
remember to check. It is for what has a lifecycle — a screen, a device, a
session — where the state decides what may run and work has to be dropped
the moment it stops matching. Where a value merely changes, a
`ValueNotifier` is enough; where work has no state to guard,
[async_job](https://pub.dev/packages/async_job) alone will do.

The list below is about bloc because that is where the package grew from,
and because bloc is where these problems have names:

1. the event queue cannot be managed;
2. when every event is `sequential`, a single one of them cannot be made
   `restartable` without moving it to a separate queue;
3. events running in parallel write to one and the same state;
4. after cancellation the handler keeps running until it checks
   `emit.isDone` itself;
5. you cannot await your own event: the `stream` tells you the state
   changed, not who changed it;
6. from the outside you want to call a method, not build an event and
   `add` it.

[solo and bloc, side by side](https://github.com/vi-k/solo/blob/main/packages/solo/doc/vs-bloc.md)
takes ten scenarios from different domains, solves each one in bloc
first — the workaround an experienced team would actually write — and then
in `solo`.

What is not here, so that the minute you spend deciding is honest: no
parallel root jobs — one at a time is the subject of the package, not a
limit of its engine — no retry, no timeout, no pool, no dependency
injection, no persistence, and no equality check between states.

The job itself — its lifecycle, its context, the outcomes and the
observer — lives in [async_job](https://pub.dev/packages/async_job), and `solo` adds
the state, the queue and the rules on top. The package re-exports it
whole, so `package:solo/solo.dart` is the only import you need. Its types
come with it and show up in autocomplete: `JobObserver` is the one you may
want, while `JobContext`, `JobBase`, `JobContextBase`, `DeferredJob` and
`JobStatus` are there for an engine of your own and are explained in the
`async_job` README, not here.

## Install

```sh
dart pub add solo
```

For Flutter, take `flutter_solo` instead — it re-exports all of `solo`:

```sh
flutter pub add flutter_solo
```

## Quick start

The state is one immutable object. A single class is enough to start
with; a sealed hierarchy comes later, when the states differ in what they
allow:

```dart
final class Profile {
  final String name;
  final bool loading;

  const Profile({this.name = '', this.loading = false});

  Profile copyWith({String? name, bool? loading}) =>
      Profile(name: name ?? this.name, loading: loading ?? this.loading);

  @override
  String toString() => 'Profile("$name", loading: $loading)';
}
```

The controller is a plain class with plain methods. Each method builds a
job and hands it to the queue; the handle it returns is not a `Future`, so
calling the method without `await` is legal and raises no lint:

```dart
final class ProfileController extends Solo<Profile> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Profile());

  Job<String> load() => run<Profile, String>(
        key: 'load',
        policy: Policy.droppable,
        (ctx) async {
          ctx.emit(ctx.state.copyWith(loading: true));
          final name = await ctx.wait(api.fetchName);
          ctx.emit(Profile(name: name));
          return name;
        },
      );

  // A flag the body raised has to come off whatever the outcome, and the
  // body is not the place for that: a failure skips the lines below it,
  // and a cancellation makes `emit` throw. The hook runs on every outcome.
  @override
  void onFinish(Job<Object?> job) {
    if (job.key == 'load' && state.loading) {
      externalSetState(state.copyWith(loading: false));
    }
  }
}
```

From the outside:

```dart
final profile = ProfileController(ProfileApi());
final subscription = profile.stream.listen(print);

final job = profile.load();
profile.load(); // droppable: the same job, not a second one

print(await job.value); // Ada Lovelace; a failure is rethrown here
print(profile.state.name); // the same name, straight from the state

await subscription.cancel();
await profile.close();
```

Cancelling is the caller's side of the same handle:

```dart
final job = profile.load();

await job.cancel(); // returns when the job has actually stopped
print(job.outcome); // Cancelled(manual)
```

`cancelAll()` does that to the queue and the running job at once, and
`close()` does it once and for good.

`run<Profile, String>` says that the job works with `Profile` states and
returns a `String`. Inside the body `ctx.emit` is the only way to write
the state, and `ctx.wait` awaits a future the way `await` does, except
that it gives up the moment the job is cancelled. `Policy.droppable` with
`key: 'load'` means that a second `load()` while the first one is still
queued or running returns that first job instead of starting a second.

Reading is free: `profile.state` is the current state, synchronously, for
anyone; `profile.stream` is a broadcast stream of every change, delivered
one microtask later. Only jobs write, one root job at a time, in queue
order. Two writers inside one controller happen on purpose and only on
purpose: a child started by `ctx.run` writes beside its parent, and
`externalSetState` writes from outside any job at all.

`close()` shuts the controller down for good: queued jobs end with
`Cancelled(closed)`, the running one is cancelled, and later calls return
jobs that are already `Cancelled(closed)` instead of throwing. It does not
close the door on `externalSetState`, though: the state still changes
after `close()` and the rules are still re-evaluated, while the stream,
already closed, drops the event and nobody hears it. Stop the source of
external states — the hardware listener, the socket — before closing the
controller.

## Concepts

**State.** One immutable object of type `S`, usually a sealed hierarchy
with union interfaces (`NotDisposed`, `Initialized`) so that jobs can
declare a working type wider than a single class. `solo.state` is readable
by anyone at any time; only jobs write.

**Controller.** The owner of the state and of the queue. The hierarchy is
linear: `SoloBase<S>` is the engine and `state`; `Solo<S>` adds a broadcast
`stream`; `SoloListenable<S>` in `flutter_solo` adds `ValueListenable`.
They differ only in how a change is delivered.

**Job.** A unit of work: an `async` body `Future<T> Function(SoloContext)`,
an optional `key`, rules, and a handle `Job<T>`. `job(...)` builds one
without queueing it, `add(job, policy: ...)` queues it, `run(...)` does both
in one call; all three return a `SoloJob<T>`, which is `Job<T>` plus
`isQueued` — the queue belongs to the controller, so that member is not on
the handle every job has. `describe: () => 'zoom: $zoom'` labels the job for
logs, the observer and `toString`, which prints `Job(key: label)` instead of
`Job(key)`. At most one root job runs at a time, and while it runs no other
**root** job of this controller writes the state.

**Working type `W`.** The subtype of `S` a job agrees to work with. The
body sees `ctx.state` already narrowed to `W`. The type is checked before
the job starts, on every state change while the body runs, and on every
read through the context. Once the body has ended — while the children
finish and the cleanup runs — the rules let the job go: there is no body
left for them to guard, and the value it returned is on its way out.

**Rules.** `canStart` is checked once, when the job is taken from the
queue; failing it drops the job with `Cancelled(rules: canStart)` and
`started: false`. `keepWhile` is checked continuously — and also before the
start, together with `canStart`: a job whose invariant is already broken
never starts, instead of starting and dying on its first read.

```dart
Job<void> record() => run<Ready, void>(
      key: 'record',
      canStart: (state) => state.free > 0,
      keepWhile: (state) => !state.paused,
      (ctx) => ctx.each(
        camera.frames,
        (child, frame) => child.join(() => store(frame)),
      ).value,
    );
```

The recording stops itself the moment somebody pauses: nothing in the body
checks `paused`, and there is no `if` left to forget.

**Cancellation.** Cooperative: Dart cannot interrupt somebody else's
`await`. A cancelled job learns about it the next time it touches the
context — the members that wait or start something throw the job's
`Cancelled` once the job is marked, while `log`, `job`, the three that
register a cleanup (`onDispose`, `onDiscard`, `disown`) and
`ctx.unattended` go on working. So a body does not `await` on its own:
every call goes through the context, and the member you pick says what a
cancellation does to that call. `ctx.wait(() => ...)` returns as soon as
either the action or the cancellation arrives. `ctx.join(() => ...)` waits
for all of the action and gives up afterwards. `ctx.uncancellable(() => ...)`
holds the cancellation for the length of the call and gives up once it is
over. `ctx.unattended(() => ...)` does not wait at all: it hands the work
to the engine and comes back, and whatever that work throws — now or long
after the job is over — reaches `onError` instead of the process. Where
there is no
call to wrap — a loop over work of your own — `ctx.check()` is the same
check on its own. A bare `await` is right in one place only: a call with
no body code after it — the last cleanup of a job, the way the example
closes its camera, or the `finally` of a job already cancelled, where
every member would throw at entry anyway. A bare `unawaited(...)` stands
in the same place as a bare `await`: outside the family, with its failure
going to the zone; `ctx.unattended` is what to write instead.

**The action is not stopped.** The wait ends, the work does not. The action
runs to its end and its result is dropped on the floor, which is fine for a
read you can abandon and wrong for anything that must actually stop, or
that must not be started twice at once. Hand the cancellation to the work
itself with `ctx.onCancel(callback)`, which fires the moment the job is
marked, and wait for the work with `ctx.join` rather than walking away
from it:

```dart
Job<void> seek(Duration position) => run<Ready, void>(
      key: 'seek',
      policy: Policy.restart,
      (ctx) async {
        final token = CancelToken();
        ctx.onCancel(token.cancel);
        // The device stops on its own, and `join` waits for it, so the
        // next seek never overlaps this one and the job gives up only
        // once the device has come back.
        await ctx.join(() => _player.seek(position, cancelToken: token));
        ctx.emit(ctx.state.copyWith(position: position));
      },
    );
```

**Taking ownership.** What the body opens it registers where it opens it,
and the engine releases it after the children and before the outcome —
`close()` waits for that release as well:

```dart
Job<void> load() => run<Idle, void>(
      key: 'load',
      (ctx) async {
        final db = await ctx.join(
          Database.open,
          dispose: (db) => db.close(),
        );

        final rows = await ctx.join(db.readAll);
        ctx.emit(Loaded(rows));
      },
    );
```

One line covers the whole life of that database: the value that never
reached the body — a cancellation throws inside the context call, so
`join` would otherwise drop it and `wait` never had it at all — and
everything after it, an error, a cancellation between two steps, a
cancellation landing after the `return`. **One value, one registration:**
a `ctx.onDispose(db.close)` next to it would be a second one, and the
database would be closed twice.

`dispose` here and not `discard` because this body keeps the database to
itself: it reads the rows, emits them and closes on the way out, whatever
the outcome. `discard` is for a value the body returns or hands outside —
on the successful path it does nothing, and that leak is the one mistake
the engine cannot catch.

An ordinary `try`/`finally` still works, but it is no longer the main
form; the stack scales to several resources, unwinds in reverse, runs
after the children rather than before them, and reaches past the `return`.
In reverse while the outcome holds: a `discard` skipped because the body
had returned is taken up in a second pass if a cancellation lands during
the unwinding, and then it runs after disposers registered below it.

**Handing a resource over.** When the body gives the resource to someone
else — to the state, most often — the registration has to go before the
hand-over can throw. `check`, `disown` and `emit` are all synchronous, so
nothing can slip between them:

```dart
ctx
  ..check()
  ..disown(db)
  ..emit(Ready(db));
```

If `check` throws, the database is still on the stack and the cleanup
closes it — the state never got it. If `emit` throws after writing (a hook
that sets the state reentrantly can do that), the state holds the database
and the registration is already gone. For an asynchronous hand-over the
pair goes into one `ctx.uncancellable(...)`, and inside the section the
step goes with a bare `await`: `ctx.join` there would throw after the step
on a cancellation by the rules, and the `disown` would never happen.

**The state on the way out.** A disposer cannot `emit` — the outcome is
decided by the time it runs, and every read and write of the context
throws a `StateError` there. Write the last state in the body: on the
successful path before the `return`, on an error in a `try`/`catch` with a
`rethrow`. On a cancellation there is no path at all — `emit` throws for a
cancelled job — so a state that has to be set even then belongs in
`onFinish` of the controller, through `externalSetState`.

**Errors of a disposer.** They go to `onError` and to `SoloBase.observer`.
With neither of the two set, nobody is listening, and the error goes to the
zone the job was created in — not the controller's — the way the core
reports one that has nowhere else to go — so a disposer that touches the
context and stops on its first line is heard rather than lost. A `Cancelled`
is the one thing that never travels that road. Install an observer at
startup, as the [Errors](#errors) section says, and it becomes yours to
route.

Note also that a disposer must not wait for its own job, nor for a job of
the same queue: `job.done`, `job.value`, `job.cancel()` and the next job
of the queue all wait for the cleanup that would be waiting for them.

**Following a stream.** `ctx.each` starts and returns a child `Job<void>`
that owns the subscription. Its callback receives a `SoloContext<S, W>`
for that child, so state reads, writes and cancellation checks belong to
the child:

```dart
Job<void> track() => run<Ready, void>(
      key: 'track',
      (ctx) => ctx.each(
        hw.positions,
        (child, p) => child.emit(child.state.copyWith(position: p)),
      ).value,
    );
```

The example returns the child's `.value` so a stream or callback error
reaches the parent body; cancellation is thrown as `Cancelled`. To inspect
the outcome instead, await `.done`. To stop this subscription separately,
keep the returned job as `subscription` and await its `cancel()`. Child
cancellation does not itself mark the parent cancelled, but an uncaught
`Cancelled` from `.value` cancels the parent under the usual child rules.

The parent waits for this child even if its body returns without awaiting
it. A quiet, open stream therefore keeps the parent alive. Accepted parent
cancellation cascades to the child, including during `close()`. The child
is cancellable even if the parent is not. It retains the parent's working
type `W` and `keepWhile`, so rules still protect state access after the
parent body returns. It does not inherit `canStart`: that condition has
already allowed the parent to start. Observers see the child separately.

Events keep their order: an asynchronous callback is awaited before the
next event is delivered, and the first stream or callback error stops
processing. When the child accepts cancellation, it immediately removes
the subscription and stops delivery, then waits for the current callback
before completing and releasing resources. Parent cleanup also waits.
Use the child's `wait`, `join` or other checkpoints inside the callback;
a plain `await` cannot be interrupted and can delay cancellation and
`close()` forever. Do not await this child's own completion or `cancel()`
from its callback: the child is already waiting for that callback.

The future returned by the underlying subscription's `cancel()` is not
awaited. Await asynchronous source cleanup separately when needed. Normal
stream completion still depends on the source sending `onDone`. `each`
is a context method with the same lifecycle restrictions as `run`: it
cannot start a child after the parent body ends or from `unattended`
or cleanup.

**Children.** `ctx.run(child)` starts a job right now, bypassing the queue,
as a child of the current one. The parent finishes only after all of its
children. A cancelled parent cancels them, and so does a body that gives
itself up with `throw Cancelled(...)` — including one that let a child's
`Cancelled` through from `await child.value`; a body that *fails* leaves
them to finish and waits. A child writes the state beside its parent —
neither waits for the other, and their writes interleave — which is the one
way to have two writers inside a controller deliberately.
`ctx.run(child).done` gives the outcome and never throws;
`ctx.run(child).value` gives the value and throws the child's `Cancelled` or
error into the parent's body.

**External state.** `externalSetState(next)` sets the state from outside
any job: a hardware listener, a forced transition. Every job whose body is
still running, except the one that emitted, is re-evaluated against the
new state immediately; the emitting job is checked lazily, on its next
read, and a job whose body has ended is not checked at all.

**Outcomes.** `Outcome<T>` is sealed, so a `switch` over its three cases is
exhaustive: `Done` carries the returned `value`, `Failed` carries `error`
and `stackTrace`, `Cancelled` carries a `reason`, a `started` flag, an
optional `description` and the stack trace of the cancellation itself. The
reason extends `CancelReason`: `ManualCancelReason`, `ParentCancelReason`
and `HandlerCancelReason` from the core, `RulesCancelReason` and
`ClosedCancelReason` from `solo`. Check the type, not the display `name`;
there is no equality by name. Extend `CancelReason` to carry data of your
own and pass it through `job.cancel(reason: reason)` or throw
`Cancelled.by(reason: reason, started: true)` from the body. Parent and
child propagation retain the original cancellation in the reason's
`cause`. `job.done` completes with the outcome and never throws;
`job.value` completes with the value or throws; `job.whenCancelled(callback)`
registers a synchronous listener and returns an unregister function. The
listener receives `Cancelled` with its reason and details: on accepted
cancellation for a running job, on dropping a job before start, or after
the body and its children end and before cleanup if the body cancelled
itself. Late registration calls it immediately. Jobs that end `Done` or
`Failed` without cancellation release their listeners without calling them.
Listener errors follow the `ctx.onCancel` route; `async` callbacks are not
awaited. `job.cancel()` cancels and waits for the job to actually finish;
`job.ignore()` says that nobody is going to look at the outcome.

**Queue and policies.** `queue` is a first-class object visible to
subclasses: `jobs`, `remove`, `removeWhere`, `clear`, `lastWhere`. The
three removing methods skip `cancellable: false` jobs unless given `force:
true`, and none of them touches the running job. Policies are sugar over
the common case of one key: `sequential` appends; `droppable` returns the
queued or running job with the same key and drops the new one; `replace`
removes queued jobs with the same key; `restart` additionally cancels the
running one without waiting for it. `add(job, first: true)` puts a job at
the head. A key stands for the result type as well: the job a key finds is
cast to the result type of the new one, so a `load()` returning `String`
and a `refresh()` returning `void` must not share a key. Nothing checks
that for you — the cast fails at run time, as a `TypeError` out of `add`.
An enum of keys, as in `example/`, is how you keep them apart by hand: one
constant per method, and the rule is that a result type gets a key of its
own. `job`, `add` and `run` are public because the controller's own methods
call them; the API a caller is meant to use is those methods.

**Stream.** `Solo.stream` is a broadcast stream of every state change, in
order, delivered on the next microtask — the stream is asynchronous. The
source of truth is `state`: by the time an event arrives, `state` may
already be newer. Equality is not checked; each change is one event. In
`flutter_solo`, `SoloListenable` listeners are called synchronously,
in subscription order, while the stream event is still on its way.

## Rules that are not visible in signatures

`cancellable: false` protects a job from actors: a manual `cancel`, a
`clear` without `force`, the cancellation of its parent, and `close` once
the job is running — `close` still drops it while it waits in the queue,
because there is no body there to protect. It does
not protect it from reality: if the state stopped matching `W` or
`keepWhile`, the job is cancelled anyway, because there is nothing left for
it to read. A non-cancellable job that must survive any state needs the
base type `S` and no `keepWhile`.

`ctx.uncancellable(action)` protects one step of the body rather than the
whole job, and it is the third answer a call can get: `wait` ends the
waiting and not the work, `join` waits for the work and gives up after it,
this one is not cancelled at all while `action` runs. Use it for a step
that cannot be taken back — a payment on its way to the server, a write
already on the wire. A `cancel` or a `close` arriving then is held, not
refused: the job is not marked while the step runs, so nothing reaches into
it — not an `onCancel` callback, not the cascade onto children — and
`close` waits for the body. When the section closes the cancellation lands,
and the next member of the context throws it, so a tail that has to happen
anyway belongs inside the same section. The rules are not covered by any of
this: a job whose state left its working type is cancelled regardless.
Sections nest and only the outermost lets a held cancellation through; a
job created with `cancellable: false` refuses it outright instead, and that
refusal is what a section leaves alone.

`emit` is trusted, reads are checked. The emitted state is not verified
against the rules of the job that emitted it — otherwise a `close` job
declared as `run<NotClosed, void>` would cancel itself the moment it
emitted `Closed()`. The next read is checked as usual, though, so a job
that emits itself out of `W` must not touch `ctx` again: emit that state
as the last statement of the body, or the job ends with
`Cancelled(rules: is not W)` on its next read.

That check is about the job's own rules. A cancellation that arrives from
inside the write itself — a hook or a listener setting the state again, a
parent going down and taking this job with it — is thrown by `emit` on the
way out, so the body never walks past it.

`ctx.run(child)` returns a handle, not a value. `await ctx.run(child).value`
throws into the parent; `switch (await ctx.run(child).done)` does not. A
forgotten `await` breaks nothing: the parent waits for its children in any
case.

A job handed to `ctx.run` becomes a child even if it is dropped before it
starts: it gets its parent, its level and its observer before the rules are
asked, so a parent always accounts for every job it tried to run. Only the
waiting is different — a job the rules turn away never joins the list the
parent waits for, and a rule that throws instead of refusing ends the child
with that error rather than leaving it behind.

A rule that throws is caught wherever it is asked, and what happens next
depends on where that was. In the queue the job ends `Failed` and the queue
goes on: the error reaches `onError` and, if nobody looks at the outcome,
the zone as well. At the job's next read of the state it is thrown into the
body like any other error, and takes the body's own path from there. In a
reevaluation after a state change it goes to `onError` and stops — the job
runs on, because a rule that threw says nothing about whether it may.
`onError` is the end of the line when there is one: a controller that
overrides it, or a `SoloObserver` set on `SoloBase.observer`. With neither,
the same error goes to the zone the controller was made in, and in the root
zone that is the process. Rules are ordinary code
of yours: they are not expected to throw, and the engine does not pretend
they cannot.

`add` on a closed controller does not throw. It returns a job that is
already finished with `Cancelled(closed)`, so call sites need no
`isClosed` check.

Any policy other than `sequential` with `key == null` throws
`ArgumentError`, not an `assert`: in release mode `null == null` is true
and `replace` would wipe every keyless job in the queue.

`ctx.emit`, `ctx.run`, `ctx.wait`, `ctx.join` and `ctx.uncancellable` after
the job has finished throw `StateError`. A context that leaked out of its
job — captured by a closure nobody awaited — must not write the state
outside the critical section, and must not start work either: an action
begun by a job that is over runs beside the job running now, counted by
neither the queue nor `close()`. Reads (`state`, `stateAs`, `check`) after
a job that finished normally are allowed; after a cancelled one they still
throw its `Cancelled`. `log` never throws.

`close()` awaited from inside the current job's body never completes: it
waits for that very body. The same holds for `cancelAll()`. Cancel from the
inside by returning or by throwing `Cancelled('why')`.

From inside a job body the whole surface of the `Solo` subclass is visible,
so there is no `ctx.solo`.

## Errors

A job that throws does not break the controller and does not stop the
queue: the error becomes the job's outcome and the next job runs.
`Outcome<T>` is sealed, so one `switch` covers everything that can happen
to a job:

```dart
switch (await profile.load().done) {
  case Done(:final value):
    print('loaded $value');
  case Failed(:final error):
    print('not loaded: $error');
  case Cancelled(:final reason):
    print('gave up: $reason');
}
```

`job.done` never throws. `job.value` gives the value instead, and rethrows
the body's error with its original stack trace, or throws the job's
`Cancelled`. `Cancelled` is not a failure: a job dropped as a duplicate,
cut short by `close`, or one whose state stopped matching its rules ends
that way, and that is normal traffic, not something to report. It is an
`Exception` and not an `Error`: a job that did not happen is an ordinary
outcome, not a broken program. That is what makes `throw Cancelled('why')`
from a body an ordinary throw.

Being an `Exception` cuts both ways: a wide `catch` in a body catches the
job's own `Cancelled` too. The outcome is safe — a job that is marked ends
with its cancellation whatever the body does next — but everything the
catch does on the way is work a cancelled job should not be doing: a
compensation, a retry, a failure written into the state. Let it through
first, the way the camera example does:

```dart
try {
  await ctx.join(hw.open);
  await ctx.join(() => hw.setZoom(zoom));
} on Cancelled {
  rethrow;
} on Object catch (error) {
  ctx.emit(Broken(error));
  rethrow;
}
```

Every failure also reaches the hooks, before the outcome is delivered to
whoever waits for it: `onError` on the controller itself, and
`SoloObserver.onError` for the whole process. Install an observer at
startup and every failure of every controller is reported once, in one
place.

A job nobody looks at is not silent. When a job ends with `Failed` and
nothing observed it — no `job.done`, no `job.value`, no `job.ignore()` —
the engine hands the error to the zone the job was created in, through
`Zone.handleUncaughtError`, exactly as Dart does with an unhandled
`Future` error. A fire-and-forget `profile.load();` on its own line still
reports what went wrong.

Neither is an error a job left behind. Work a body hands to
`ctx.unattended` keeps its own error zone, and a failure of it — now, or
long after the job is over — arrives at `onError` like any other. With
neither the hook overridden nor an observer installed, nobody is
listening, and it goes to the zone the job was created in rather than
stopping in an empty hook; a cancellation is the one thing that never
goes there.

When the failure is genuinely handled elsewhere — by `onError`, by the
observer — say so:

```dart
profile.load().ignore(); // the counterpart of Future.ignore
```

`ignore()` marks the job as observed without waiting for it.

`Cancelled` never goes to the zone. An error that arrives after the job was
cancelled — an action that `wait` stopped waiting for and that fails later
— is reported to `onError` and stops there **if anybody is listening**:
without an observer and without an overridden hook it takes the same road
to the zone as any error with nowhere else to go.

## Testing

There is no `bloc_test` here and no need for one: the job handle is the
synchronization point. Start a job, await its outcome, then look at the
state.

```dart
test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  final outcome = await profile.load().done;

  expect(outcome, isA<Done<String>>());
  expect(profile.state.name, 'Ada Lovelace');

  await profile.close();
});
```

Use `job.value` instead of `job.done` when the test is about the returned
value, and `await expectLater(profile.load().value, throwsA(...))` when it
is about a failure.

When timing matters — a debounce, a timeout, two jobs racing — wrap the
test in `fakeAsync` and move time by hand. An observer that collects one
ordered journal turns a whole episode into a single `expect`, and that
catches ordering mistakes no final-state check can see:

```dart
final class Journal extends SoloObserver {
  final lines = <String>[];

  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} started');

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} ${job.outcome}');

  @override
  void onChange(SoloBase<Object> solo, Object previous, Object current) =>
      lines.add('state: $current');
}

test('a second load while the first one runs is dropped', () {
  fakeAsync((async) {
    final journal = Journal();
    SoloBase.observer = journal;
    addTearDown(() => SoloBase.observer = null);
    final profile = ProfileController(FakeProfileApi());

    final first = profile.load();
    final second = profile.load();
    expect(identical(first, second), isTrue);

    async.elapse(const Duration(milliseconds: 20));
    expect(journal.lines, [
      'load Cancelled(manual: duplicate)',
      'load started',
      'state: Profile("", loading: true)',
      'state: Profile("Ada Lovelace", loading: false)',
      'load Done(Ada Lovelace)',
    ]);

    profile.close();
    async.flushTimers();
  });
});
```

`SoloBase.observer` is a global, so it is set once and undone by
`addTearDown` — a failing expectation throws, and a line at the end of the
test would never run, leaving the journal of this test to collect the
lines of the next one. `stream` works with
`expectLater(..., emitsInOrder([...]))` too, but it is asynchronous —
after `await job.done` the state is already the final one, so reading
`state` is usually enough.

Cancelling in a test is the same two lines as anywhere: `job.cancel()`
returns a future nothing inside `fakeAsync` can await, so
`job.cancel().ignore()` and then `async.flushTimers()` before the
expectation. And a fake API built on `Future(...)` or `Future.delayed(...)`
schedules a timer, not a microtask: `flushMicrotasks()` will not run it,
`flushTimers()` and `elapse(...)` will.

## Recipes

**Timeout.** The engine knows nothing about timeouts, and `Future.timeout`
by itself is not one: it ends the waiting, not the work. The source future
is never cancelled, so `hw.open().timeout(...)` fails the job while the
device is still opening, and the next job starts against it. Give the timer
something that really stops — the same cancel token the job hands to
`onCancel` — and wait for the device with `join`. It comes back with an
error of its own, and the job ends `Failed`:

```dart
Job<void> connect() => run<Idle, void>(
      key: 'connect',
      (ctx) async {
        final token = CancelToken();
        final timer = Timer(const Duration(seconds: 5), token.cancel);
        ctx.onCancel(token.cancel);
        try {
          await ctx.join(() => hw.open(cancelToken: token));
        } finally {
          timer.cancel();
        }
        ctx.emit(const Connected());
      },
    );
```

Where the call has nothing to leave behind — a read, a request whose answer
you can drop — the short form is honest: `ctx.wait(() => api.fetch()
.timeout(...))`, and the abandoned request finishes on its own.

**Debounce.** Also outside the engine: hold a `Timer` in the controller and
start the job when it fires. Combine it with `Policy.restart`, so that a job
still running for the previous input is cancelled rather than awaited.
Nothing awaits this job, so a failure of `api.search` goes to the zone; see
[Errors](#errors) for the ways out:

```dart
import 'dart:async';

final class Search extends Solo<SearchState> {
  final SearchApi api;

  Timer? _debounce;

  Search(this.api) : super(const SearchState.idle());

  void query(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      run<SearchState, void>(
        key: 'query',
        policy: Policy.restart,
        describe: () => text,
        (ctx) async {
          final results = await ctx.wait(() => api.search(text));
          ctx.emit(SearchState.results(results));
        },
      );
    });
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
```

**Following another controller.** The answer to `BlocListener` for a
controller rather than a screen: a long-lived job over the other one's
stream. The subscription lives exactly as long as the job, `close()` takes
it down with everything else, and the writes it makes go through the queue
like any other job's.

Two things this recipe asks of you. A stream carries what happens next and
not what has already happened, so the job starts by taking the state it
follows — `session.state` — and only then listens; without that first line
a screen follows a session it never read. And the job holds the queue for
as long as it follows, so it belongs to a controller whose work is the
following: a controller that has jobs of its own wants a job per event
instead, queued from the callback.

```dart
final class ScreenController extends Solo<Screen> {
  final Solo<Session> session;

  ScreenController(this.session) : super(const Screen());

  Job<void> follow() => run<Screen, void>(
        key: 'follow',
        (ctx) async {
          void take(SoloContext<Screen, Screen> target, Session next) =>
              target.emit(target.state.copyWith(signedIn: next.signedIn));

          take(ctx, session.state); // what has already happened
          await ctx.each(session.stream, take).value; // what happens next
        },
      );
}
```

**Hooks.** A controller can override `onStart`, `onFinish`, `onError`,
`onLog` and `onChange` to react to its own jobs:

```dart
final class ProfileController extends Solo<Profile> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Profile());

  // ...the jobs above...

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    reportCrash(error, stackTrace);
  }
}
```

**Observer.** `SoloObserver` is the cross-cutting version of the same five
hooks plus `onCreate` and `onClose`: analytics, error reporting, one log for
every controller in the process. The engine calls the observer before the
controller's own hook, and independently of it — a subclass that forgets
`super` does not switch the observer off:

```dart
final class LoggingObserver extends SoloObserver {
  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) =>
      print('$job started');

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) =>
      print('$job finished ${job.outcome}');

  @override
  void onChange(SoloBase<Object> solo, Object previous, Object current) =>
      print('state: $current');
}

void main() {
  SoloBase.observer = LoggingObserver();
}
```

Hooks are a channel, not a link in the chain: an error thrown by any of
them — a controller's or an observer's — goes to the current zone, the way
Dart reports an unhandled `Future` error, and changes nothing else. The job
ends with the outcome it had, the queue goes on, `close` still completes,
and the hook standing next to the throwing one is still called.

To trace the engine itself rather than the jobs, set
`SoloBase.debug = print`.

## Flutter

`flutter_solo` adds `SoloListenable<S> extends Solo<S> implements
ValueListenable<S>`, and re-exports all of `solo`. The only change to the
controller is its base class — the jobs stay exactly as they are:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

final class ProfileController extends SoloListenable<Profile> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Profile());

  // ...the jobs above...
}
```

There is no `SoloProvider`, and nothing closes the controller for you. A
controller that belongs to one screen is created in `initState` and closed
in `dispose`; a controller shared by several screens goes into whatever
you already use for that — `provider`, `get_it`, an `InheritedWidget` —
and is closed there.

A side effect is not a state: awaiting the job is the whole mechanism.
Check `mounted` after the await, as after any `await` in a `State`, and
then decide what to do with the outcome:

```dart
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileController profile;

  @override
  void initState() {
    super.initState();
    profile = ProfileController(ProfileApi());
  }

  @override
  void dispose() {
    unawaited(profile.close());
    super.dispose();
  }

  Future<void> _open() async {
    final outcome = await profile.load().done;
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case Done():
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
        );
      case Failed(:final error):
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      case Cancelled():
        break;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ValueListenableBuilder<Profile>(
            valueListenable: profile,
            builder: (context, state, _) => state.loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _open,
                    child: const Text('Open profile'),
                  ),
          ),
        ),
      );
}
```

`ListenableBuilder` and `AnimatedBuilder` take the controller too — it is a
`Listenable` — when the builder does not need the value itself. `value` and
`state` are the same object. There is no setter on purpose: a
`ValueNotifier` face would be a hole in the ownership guarantee.

## Coming from bloc

| bloc | solo |
| --- | --- |
| `Bloc<E, S>`, `Cubit<S>` | `Solo<S>`, `SoloListenable<S>` |
| an event class, `on<E>`, `add(E())` | a method returning `Job<T>` |
| an `EventTransformer` | a `Policy` on the job |
| `emit(next)` | `ctx.emit(next)` |
| `if (emit.isDone) return;` | `ctx.wait(...)`, `ctx.join(...)`, `ctx.check()` |
| `emit.onEach`, `emit.forEach` | `ctx.each(stream, onData)` |
| `state`, `stream` | `state`, `stream` |
| `BlocObserver` | `SoloObserver` |
| `BlocBuilder`, `BlocSelector` | `ValueListenableBuilder` |
| `BlocListener` | `await job.done` at the call site |
| `BlocProvider` | `initState` plus `dispose` |
| `close()` | `close()` |
| `blocTest` | `test` plus `await job.done` |

The transformers map by name: `sequential()` is `Policy.sequential`,
`droppable()` is `Policy.droppable`, `restartable()` is `Policy.restart`.
`Policy.replace` — drop what is queued, leave what is running — has no
transformer of its own, and a policy is chosen per call rather than per
event type.

Three things have no counterpart on purpose. There is no `concurrent`
transformer: root jobs of one controller never overlap, and work that really
is parallel goes inside one job, which awaits it itself. There is nothing
like an `emit` after `close` to guard against: `add` on a closed controller
returns a job that is already `Cancelled(closed)`, so call sites need no
`isClosed` check. And an event is not a value you can hold on to — a method
call gives you the `Job<T>` instead, so the caller can await exactly the
work it started.

## Example

The camera below is the shape of a real controller: several jobs with
different policies, a job that must not be cancelled, and a teardown that
clears the queue before it runs. The state is a sealed hierarchy, and
`NotDisposed` is a union interface that jobs can declare as their working
type:

```dart
sealed class CameraState {
  const CameraState();
}

sealed class NotDisposed extends CameraState {
  const NotDisposed();
}

final class Initial extends NotDisposed {
  const Initial();
}

final class Preparing extends NotDisposed {
  const Preparing();
}

final class Ready extends NotDisposed {
  final double zoom;
  final bool paused;

  const Ready({this.zoom = 1, this.paused = false});

  Ready copyWith({double? zoom, bool? paused}) =>
      Ready(zoom: zoom ?? this.zoom, paused: paused ?? this.paused);
}

final class Disposed extends CameraState {
  const Disposed();
}
```

```dart
enum CameraKey { init, closeCamera, setZoom, takePhoto, dispose }

final class CameraController extends Solo<CameraState> {
  final FakeCameraHardware hw;

  CameraController(this.hw) : super(const Initial());

  Job<void> init() => run<NotDisposed, void>(
        key: CameraKey.init,
        policy: Policy.droppable,
        canStart: (state) => state is Initial,
        (ctx) async {
          ctx.emit(const Preparing());
          await ctx.join(hw.open);
          ctx.emit(const Ready());
        },
      );

  Job<void> setZoom(double zoom) => run<Ready, void>(
        key: CameraKey.setZoom,
        policy: Policy.replace,
        describe: () => 'zoom: $zoom',
        canStart: (state) => !state.paused,
        (ctx) async {
          await ctx.join(() => hw.setZoom(zoom));
          ctx.emit(ctx.state.copyWith(zoom: zoom));
        },
      );

  Job<Photo> takePhoto() => run<Ready, Photo>(
        key: CameraKey.takePhoto,
        policy: Policy.droppable,
        canStart: (state) => !state.paused,
        (ctx) async {
          final photo = await ctx.join(hw.capture);
          queue.clear();
          ctx.log('captured $photo');
          return photo;
        },
      );

  Job<void> _closeCameraJob() => job<NotDisposed, void>(
        key: CameraKey.closeCamera,
        cancellable: false,
        (ctx) async => hw.close(),
      );

  Job<void> dispose() {
    queue.clear(force: true);
    current?.cancel();
    return run<CameraState, void>(
      key: CameraKey.dispose,
      policy: Policy.droppable,
      cancellable: false,
      (ctx) async {
        if (ctx.state is Disposed) {
          return;
        }
        if (ctx.state is! Initial) {
          await ctx.run(_closeCameraJob()).value;
        }
        ctx.emit(const Disposed());
      },
    );
  }
}
```

From the outside:

```dart
final camera = CameraController(FakeCameraHardware());
await camera.init().done;

camera.setZoom(2); // no await needed, and no lint about it

final photo = await camera.takePhoto().value;

switch (await camera.dispose().done) {
  case Done():
    print('disposed');
  case Cancelled(:final reason):
    print('cancelled: $reason');
  case Failed(:final error):
    print('failed: $error');
}

await camera.close();
```

Four things in that controller are worth a sentence each.

**The working type is wider than the start condition.** `init` starts only
from `Initial`, but it is declared `run<NotDisposed, void>`, because its
first line emits `Preparing` and the body keeps reading the context
afterwards. The start condition lives in `canStart`; `W` covers every state
the body walks through.

**`takePhoto` clears the queue.** The commands that piled up while the
shutter was open were aimed at the frame that has just been taken. Once
the capture succeeds they are stale, so the shot throws them away instead
of applying them to the next frame. `queue.clear()` without
`force` leaves `cancellable: false` jobs alone and never touches the
running job — the shot itself.

**`dispose()` is a job; `close()` is the end of the controller.**
`dispose()` puts the hardware back and can be queued, dropped as a
duplicate, and awaited like any other job. `close()` drops the queue,
cancels the running job and refuses everything after it. One does not
imply the other: `close()` alone leaves the camera open. Await the teardown
first, then close.

**A queued `setZoom` is replaced, a running one is not.** `Policy.replace`
removes queued jobs with the same key; the job already running is left to
finish. `Policy.restart` would cancel it as well, and `Policy.droppable` —
what `takePhoto` uses — keeps the running job and drops the newcomer.

[`example/`](example) is a runnable package with this controller extended:
a fake camera whose hardware answers late and may break on its own, a
`Broken` state, `reopen`, `pause`, `resume` and focus jobs, seven tests
over an ordered journal, and `bin/main.dart` that prints the same journal in
real time.

```sh
cd example
dart pub get
dart run bin/main.dart
dart test
```
