# jobs

A cancellable `Future`: a job with an outcome, children, cooperative
cancellation and a waiting family. Pure Dart, no dependencies beyond
`meta`.

`Job` is not a `Future`, and nothing awaits it directly: `await job.done`
for the outcome, `await job.value` for the value.

## Why

A `Future` cannot be cancelled. The usual answers — a flag the body
checks, a `CancelableOperation`, a token passed by hand — leave the same
three questions open: what the job ended as, who is waiting for it, and
who hears about a failure nobody looked at.

A job answers all three. It ends with an `Outcome`: `Done`, `Failed` or
`Cancelled` with a reason. It can start children and is not finished
until they are. And a `Failed` outcome nobody observed goes to the zone
that created the job, the way Dart reports an unhandled `Future` error.

`CancelableOperation` ends the waiting the same way. What it does not
have is the outcome to end with, the children to wait for, the
checkpoints inside the body, and the observer that hears the errors with
nowhere else to go.

Cancellation is cooperative, and the body must never await anything by
itself: every call goes through the context, and the member it picks says
what a cancellation does to that call. A direct `await` is not wrong
Dart, it is blind — nothing tells it that the job is over.

There is no state here, no queue, no rules, no retry, no timeout, no
pool. That is `solo`, built on this package and re-exporting it whole: a
package that depends on `solo` never depends on `jobs` as well.

## Install

```sh
dart pub add jobs
```

## Quick start

```dart
import 'package:jobs/jobs.dart';

final job = Job<Database>(
  ifCancelled: (database) => database.close(),
  (ctx) async {
    final database = await ctx.join(
      Database.open,
      ifCancelled: (database) => database.close(),
    );
    await ctx.wait(database.migrate);
    await ctx.uncancellable(database.markReady);

    return database;
  },
);

// Somebody changed their mind while the database was opening.
await Future<void>.delayed(const Duration(milliseconds: 10));
job.cancel().ignore();

final outcome = await job.done;
```

The body starts on the next microtask, not inside the constructor: the
caller gets the handle first and may listen to it, or cancel before the
body ever runs. That is what the wait above is for: a job cancelled on
the same stripe ends as `Cancelled(manual)` with `started: false`, and
none of the body runs at all. `example/example.dart` is this fragment
with a fake `Database` around it.

## Outcomes

`Outcome<T>` is sealed, so a `switch` over its three cases is exhaustive:

```dart
final message = switch (await job.done) {
  Done(:final value) => 'done $value',
  Failed(:final error) => 'failed $error',
  Cancelled(:final reason) => 'cancelled $reason',
};
```

`Cancelled` carries a `reason`, a `started` flag, an optional
`description` and the stack trace of the cancellation itself. The reason
is a `CancelReason` — `manual`, `parent` and `handler` here — and it is
an open class, not an enum: an engine built on this one declares its own,
and reasons are equal by name.

`job.done` completes with the outcome and never throws; `job.value`
completes with the value or throws; `job.whenCancelled` completes on
every `Cancelled` outcome — for a running job the moment it is marked,
before the body finishes, and for a body that cancelled itself only when
the job finishes; `job.cancel()` cancels and waits for the job to
actually finish; `job.ignore()` says that nobody is going to look at the
outcome.

## Cancellation

`cancel()` marks the job; stopping is the body's own business. The mark
reaches the body as a throw: every context member throws `Cancelled` once
the job is marked, and `Cancelled` implements `Exception`. A `catch` wide
enough to hold it swallows the cancellation, and the body walks on:

```dart
try {
  await ctx.wait(database.migrate);
} on Cancelled {
  rethrow; // never swallow this one
} on Exception catch (error) {
  ctx.log('migration failed: $error');
}
```

The outcome is `Cancelled` all the same, and that is what makes a
swallowed cancellation expensive to find: from the outside the job ended
right, while the body went on working. Catch the type you came for, and
let the cancellation through.

The body must never await anything by itself, and the member it picks
says what a cancellation does to that call:

- `ctx.wait(action)` ends the waiting, not the work. The action runs on,
  its result is dropped — or handed to `ifCancelled`, which runs late and
  alone: the job is over by then, and nothing waits for that disposer.
- `ctx.join(action)` waits for all of the action and gives up afterwards:
  a device command already on the wire is not abandoned halfway. Its
  `ifCancelled` is awaited before the `Cancelled` is thrown, so whoever
  waits for the job waits for the disposal too.
- `ctx.each(stream, onData)` follows a stream for as long as the job
  lives. The subscription is cancelled the moment the job is marked,
  before the body learns about it, and nothing is left listening.
- `ctx.uncancellable(action)` refuses the cancellation for the length of
  the call. A refusal is final, not deferred.
- `ctx.onCancel(callback)` fires the moment the job is marked, before the
  body learns about it: this is how a cancellation reaches something that
  can really stop — a cancel token, an abort, a subscription.
- `ctx.check()` gives up where there is no call to wrap.

```dart
final job = Job<void>((ctx) async {
  final token = CancelToken();
  ctx.onCancel(token.cancel);
  await ctx.join(() => device.seek(position, cancelToken: token));
});

final feed = Job<void>((ctx) => ctx.each(socket.messages, handle));
```

A job created as `Job(body, cancellable: false)` refuses every
cancellation it may refuse; its own rules — whatever an engine on top
adds — still apply.

## Children

`ctx.run(child)` starts a child right now, bypassing whatever queue an
engine on top may have. The parent is not finished until its children
are, a cancelled parent cascades onto them, and a child that is not
cancellable refuses the cascade.

```dart
final parent = Job<void>((ctx) async {
  final child = ctx.run(Job.deferred<int>((ctx) => ctx.wait(load)));
  final rows = await child.value;
  ctx.log('$rows rows');
});
```

A child inherits the parent's observer unless it was given one of its
own, and a cancellation of a child that surfaces through `child.value`
marks the parent's outcome as `handler`, naming the child.

`run` refuses as well as starts: a handle that is not a job of this
kernel is an `ArgumentError`, a job already started is a `StateError`,
and a parent that is already cancelled throws its own `Cancelled` with
the child dropped — which is what a body starting children after a long
await eventually meets.

## Late values

Between the `return` of a body and the outcome the job is still alive —
it waits for its children — and a cancellation arriving there wins. The
value the body computed would be dropped, so `ifCancelled` on the job
takes it:

```dart
final job = Job<Database>(
  ifCancelled: (database) => database.close(),
  (ctx) async => Database.open(),
);
```

This body has no context call to be interrupted at: it hands the kernel a
future and the kernel waits for it, so a cancellation arriving meanwhile
is not seen until the value is back. That is the shape `ifCancelled` on
the job is for, and the one place where skipping the context costs
nothing.

The outcome is the cancellation all the same. The disposer runs after the
children and before the outcome, and the engine waits for it. It runs
outside the body — neither `onCancel` nor `uncancellable` reach it — so
keep it short and unconditional.

## Observer

`JobObserver` is the cross-cutting channel of one job: `onStart`,
`onFinish`, `onError`, `onLog`. All four have empty bodies, so a listener
overrides only what it needs; `implements` works as well, for a listener
that already extends something of its own. Pass it at creation; a child
without one inherits the parent's. A hook that throws hands its error to
the current zone and changes nothing else.

```dart
final class Log extends JobObserver {
  @override
  void onFinish(Job<Object?> job) => print('$job: ${job.outcome}');
}

final job = Job<int>(
  key: 'load',
  observer: Log(),
  (ctx) => ctx.wait(load),
); // Job(load): Done(3)
```

A job prints itself as `Job($key)`, so the key is what it is called in a
log — and what an engine on top compares jobs by, as `solo` does in its
queue policies. `describe` adds a line for whoever reads that log.

Errors take two paths, and they are not the same. The body's error goes
to the observer and becomes the `Failed` outcome; it reaches the zone
only if nobody observes that outcome. The three errors that have nowhere
else to go — a late failure of an action `wait` abandoned, a disposer, an
`onCancel` callback — go to the observer, or straight to the zone when
there is none. Silence is the choice of whoever listens.

## Deferred start

`Job.deferred(body)` returns a `DeferredJob<T>`, which adds a public
`start()`. Whoever owns the job starts it: by hand, a queue, or a parent
through `ctx.run(child)`.

```dart
final job = Job.deferred<void>((ctx) => ctx.wait(work));
// ... later, or from a queue of your own
job.start();
```

## Testing

A job starts on one microtask and finishes on another, so a test of a job
is a test about the event loop. `package:fake_async` runs it without a
clock — the suite of this package is built that way:

```dart
test('a cancelled open still closes what it opened', () {
  fakeAsync((async) {
    final job = Job<Database>(
      (ctx) => ctx.join(Database.open, ifCancelled: (db) => db.close()),
    );

    async.elapse(const Duration(milliseconds: 10));
    job.cancel().ignore();
    async.flushTimers();

    expect(job.outcome, isA<Cancelled>());
  });
});
```

`flushMicrotasks()` is enough to get a job started; anything built on
`Future(...)` or `Future.delayed(...)` is a timer, not a microtask, and
needs `flushTimers()` or `elapse(...)`.

## Building on the core

`JobBase<T>` and `JobContextBase` are the two classes an engine of a
domain subclasses. The subclass adds what the kernel does not have — a
state, a queue, rules — and everything the engine needs is protected:
the status, the pending cancellation, the children, the start, the
finish, the cancellation with its rejectable flag, and the two hooks a
job of a domain fills in, `started()` and `finished()`.

```dart
final class MyJob<T> extends JobBase<T> {
  final Future<T> Function(MyContext ctx) _body;

  MyJob(this._body, {super.key, super.observer});

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<T> execute(covariant MyContext ctx) => _body(ctx);

  // `start` is protected: the engine opens its own door to it.
  void launch() => start();
}

final class MyContext extends JobContextBase {
  MyContext(super.owner);
}

final job = MyJob<int>((ctx) => ctx.wait(load))..launch();
```

Two things are worth knowing before you start. `check()` is the
checkpoint every waiting member goes through — `wait`, `join` and
`uncancellable` all begin with it — so a domain that checks more than the
cancellation overrides it there, and gets the whole family for free. And
`@protected` holds inside a subclass only: an engine reaching a job from
the side wants private wrappers on its own subclass, not direct calls —
`launch` above is one.

`solo` is built this way. The protected surface is where half of this
package lives, and it is spelled out in the API reference of
[JobBase](https://pub.dev/documentation/jobs/latest/jobs/JobBase-class.html).

## solo

[solo](https://pub.dev/packages/solo) adds a state, a queue and rules on
top of these jobs: one root job at a time, exclusive state ownership,
declarative rules. If you want a controller rather than a job, start
there — and depend on it alone, since it re-exports this package whole.

Nothing here is Flutter-specific: jobs run wherever Dart runs. The widget
layer of `solo` is [flutter_solo](https://pub.dev/packages/flutter_solo).
