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

Cancellation is cooperative: `cancel()` marks the job, and the body is
what actually stops. That is why every wait in a body goes through the
context — `await ctx.wait(action)`, not `await action()`. A future awaited
directly has nothing to interrupt it: the mark arrives, and the body keeps
waiting for a call that knows nothing about it. The context member you
pick is what says how that call reacts.

There is no state here, no queue, no rules, no retry, no timeout, no
pool. If you want any of those, take `solo`: it is built on this package
and re-exports it whole, so a package that depends on `solo` never depends
on `jobs` as well.

## Install

```sh
dart pub add jobs
```

## Quick start

```dart
import 'package:jobs/jobs.dart';

final job = Job<Database>((ctx) async {
  final database = await ctx.join(
    Database.open,
    discard: (database) => database.close(),
  );

  final stop = CancelToken();
  ctx.onCancel(stop.cancel);

  await ctx.join(() => database.migrate(stop));
  await ctx.uncancellable(() => database.markReady(stop));

  return database;
});

// Somebody changed their mind while the database was opening.
await Future<void>.delayed(const Duration(milliseconds: 10));
await job.cancel();

final outcome = await job.done; // Cancelled(manual)
```

Line by line, because every one of them is a decision:

- **The body starts on the next microtask**, not inside the constructor:
  the caller gets the handle first and may listen to it, or cancel before
  the body ever runs. That is what the delay above is for — a job
  cancelled on the same stripe ends as `Cancelled(manual)` with
  `started: false`, and none of the body runs at all.
- **`ctx.join(Database.open)`** and not `ctx.wait`: an open that is
  already under way is not abandoned halfway, or the database would be
  opened with nobody left holding it.
- **`discard: (database) => database.close()`** covers the whole life of
  that database in one line and once. Not only the value that came back
  after the job had given up — everything after it too: a cancellation
  between two steps, an error inside one, a cancellation landing after the
  `return`. The database is closed unless it reaches the caller. No `try`,
  no `finally`, nothing to remember before the `return`, and nothing to
  register a second time — one value, one registration. See
  [Cleanup](#cleanup).
- **`ctx.onCancel(stop.cancel)`** is how `cancel()` reaches the database
  itself. The callback runs the moment the job is marked, before the body
  learns of it, so whatever the database is doing is told to stop at once.
- **`ctx.join(() => database.migrate(stop))`** for the same reason as the
  open: the migration is told to stop through that token, and `join` waits
  for it to actually stop. `ctx.wait` would end the waiting and leave it
  writing into a database this body is about to close.
- **`ctx.uncancellable(() => database.markReady(stop))`** for the step that
  must not even be told to stop. `join` would not do here, and this is the
  difference between the two: `join` holds the waiting, not the
  cancellation. Under it the callback above has already fired, `stop` is
  already cancelled, and `markReady` gives up halfway — the call is waited
  for, but it is a call that is stopping. `uncancellable` holds the
  cancellation itself. Plainly: while the body is inside the section,
  `onCancel` is not called at all — it is called the moment the section
  ends, and the body learns of the cancellation after that, at its next
  call through the context — see [Cancellation](#cancellation).
- **`await job.cancel()`** returns when the job has actually finished, so
  the outcome below is already there. The `await` is a choice: the
  cancellation goes through either way, and dropping it only means not
  waiting for the end.

`example/example.dart` is this fragment with a fake `Database` around it.

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
neither an enum nor sealed: an engine built on this one declares its own
with `const CancelReason('closed')`, and reasons are equal by name.

`job.done` completes with the outcome and never throws; `job.value`
completes with the value or throws. `job.cancel()` cancels and waits for
the job to actually finish; `job.ignore()` says that nobody is going to
look at the outcome.

`job.whenCancelled` completes on every `Cancelled` outcome — for a
running job the moment it is marked, before the body finishes, and for a
body that cancelled itself once that body has ended and its children are
done, right before the cleanup. It says that the decision has been made,
not that the job is over:

```dart
final job = Job<Report>(build);

// The moment somebody cancels. The children and the cleanup still have
// to play out, and `job.done` waits for them.
unawaited(job.whenCancelled.then((_) => print('cancelling…')));

final outcome = await job.done;
```

It never completes for a job that ends `Done` or `Failed`, so hang work
on it as above, or race it with `job.done`: a bare
`await job.whenCancelled` parks for good on a job that succeeds.

## Cancellation

`cancel()` marks the job; stopping is the body's own business. The mark
reaches the body as a throw: once the job is marked, the members that wait
or start something throw `Cancelled` — `check`, `wait`, `join`,
`uncancellable`, `run` and `each` — and `onCancel` with them, which only
registers, but would be registering a callback that can no longer fire. The
ones that only register go on working, so a body just cancelled can still
put what it holds on the cleanup stack: `onDispose`, `onDiscard`, `disown`
and `unattended`. And `Cancelled` implements `Exception`. A `catch` wide
enough to hold it swallows the cancellation, and the body walks on:

```dart
try {
  await ctx.join(database.migrate);
} on Cancelled {
  rethrow; // never swallow this one
} on Exception catch (error) {
  ctx.log('migration failed: $error');
}
```

or

```dart
try {
  await ctx.join(database.migrate);
} on Object catch (error) {
  if (error is Cancelled) rethrow;
  ctx.log('migration failed: $error');
}
```

The outcome is `Cancelled` all the same, and that is what makes a
swallowed cancellation expensive to find: from the outside the job ended
right, while the body went on working. Catch the type you came for, and
let the cancellation through.

Not every `Cancelled` the body sees is its own: one that came out of
`await child.value` says a child gave up, and catching that one is fair —
an optional step that did not work out. Inside such a `catch`, `ctx.check()`
tells the two apart, because it throws only if this job is cancelled too.

The body must never await anything by itself, and the member it picks
says what a cancellation does to that call:

- `ctx.wait(action)` ends the waiting, not the work: the body goes on
  from that call — with the cancellation in hand — while the action runs
  to its end. Its result is dropped, or handed to the disposer it was
  given. That disposer goes on the cleanup stack while the job is still
  unwinding it, so whoever waits for the job waits for the disposal too,
  the closing of an engine included. If the action finishes after the job
  is already over, the disposer runs on its own, with nobody left to wait
  for it.
- `ctx.join(action)` waits for all of the action and gives up afterwards:
  a device command already on the wire is not abandoned halfway. Its
  disposer is awaited before the `Cancelled` is thrown, so whoever waits
  for the job waits for the disposal too.
- `ctx.each(stream, onData)` follows a stream for as long as the job
  lives, and a body that does nothing else is one expression:
  `Job<void>((ctx) => ctx.each(socket.messages, handle))`. The
  subscription is cancelled the moment the job is marked, before the body
  learns about it, and again when the job ends whatever the outcome, so
  nothing is left listening even behind a body that walked away from the
  call. An `onData` that returns a future is waited for, and delivery is
  held meanwhile: the events keep their order.
- `ctx.uncancellable(action)` holds the cancellation for the length of
  the call: the job is not marked while it runs, so nothing — not an
  `onCancel` callback, not the cascade onto children — reaches into the
  step. It lands the moment the section closes, and the next context call
  throws it. A step whose tail must happen too belongs inside the same
  section; a job that must survive a cancellation altogether is created
  with `cancellable: false`. Always `await` it: the section belongs to the
  job, not to the future, so it opens on the call either way — and a body
  that walked on can end while it is still open, in which case the held
  cancellation lands on a job that is already over and is dropped.
  `cancel()` then returns on a job that ended `Done`, and nothing says
  otherwise.
- `ctx.onCancel(callback)` fires the moment the job is marked, before the
  body learns about it: this is how a cancellation reaches something that
  can really stop — a cancel token, an abort, a subscription. The callback
  is synchronous, and only what it throws synchronously reaches `onError`:
  `void Function()` takes an `async` function without a word from the
  analyser, and the future one of those returns is awaited by nobody — its
  failure goes straight to the zone. A stop that is asynchronous itself is
  handed to the engine — `ctx.onCancel(() => ctx.unattended(device.stop))`.
- `ctx.unattended(action)` is the one that does not wait at all. The work
  is handed to the engine and the body walks on; a cancellation does not
  touch it, and whatever it throws — now or long after the job is over —
  reaches `onError` instead of the process. That is what it has over
  `unawaited(...)`, which only silences the analyser: a future dropped that
  way still belongs to the zone it was made in, and its failure arrives
  there with nothing to say which job started it. Start the work inside and
  take nothing out of it: the boundary of its error zone holds both ways.
- `ctx.check()` gives up where there is no call to wrap.

A job created as `Job(body, cancellable: false)` refuses every
cancellation it may refuse, once it has started: before the body runs
there is nothing to protect, and such a job is dropped like any other.
Its own rules — whatever an engine on top adds — still apply.

## Children

`ctx.run(child)` starts a child right now, bypassing whatever queue an
engine on top may have. The parent is not finished until its children
are, a cancelled parent cascades onto them, and a child that is not
cancellable refuses the cascade. A body that gives itself up with
`throw Cancelled(...)` cancels its children too; a body that *fails*
leaves them to finish, and waits.

```dart
final parent = Job<void>((ctx) async {
  final child = ctx.run(Job.deferred<int>((ctx) => ctx.wait(load)));
  final rows = await child.value;
  ctx.log('$rows rows');
});
```

`Job.deferred` and not `Job`, because the start of a child belongs to its
parent: an auto-starting job that `run` did not reach on the same
synchronous stripe starts itself — as a root job nobody adopted, nobody
cascades onto and nobody waits for — and `run` then refuses it as already
started.

A child inherits the parent's observer unless it was given one of its
own, and a cancellation of a child that surfaces through `child.value`
marks the parent's outcome as `handler`, naming the child.

`run` refuses as well as starts: a handle that is not a job of this
kernel is an `ArgumentError`, a job already started is a `StateError`, a
body that has already ended is a `StateError` too — a child begun then
would be waited for by nobody — and a parent that is already cancelled
throws its own `Cancelled` with the child dropped, which is what a body
starting children after a long await eventually meets.

## Cleanup

What the body opens, it registers — where it opens it, in one line:

```dart
final lock = await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
final database = await ctx.join(
  Database.open,
  discard: (database) => database.close(),
);

await ctx.join(database.migrate);

return database;
```

Two words, and the difference between them carries the whole mechanism:

- **`dispose`** runs whatever the outcome. A lock, a temporary file, a
  counter: released on the successful path too, or it stays taken for
  good.
- **`discard`** runs only when the value reaches nobody — cancelled, or
  failed. The database above goes to the caller on success, and closing it
  then would be a bug; when nobody gets it, the engine closes it.

The rule for choosing is one line, and it is the one mistake the engine
cannot catch: **`discard` is only for what the body returns or hands
outside; everything else takes `dispose`.** A `discard` on a temporary
file the body never returns does nothing on success — a leak on the happy
path that no test on cancellation will ever show.

For a value that did not come out of a call, the two members say the same
thing:

```dart
final buffer = StringBuffer();
ctx.onDispose(() => sink.add(buffer.toString()));
```

Both forms return a function that unregisters; for a value from `wait` or
`join` there is `ctx.disown(value)`, for when the body hands the value
over itself and the cleanup must stop being its business.

**How it runs.** The engine unwinds the stack in one pass, last
registration first, after the children and before the outcome — children
first because they may still be using what the parent opened — and it
waits for every disposer, so `close()` of an engine on top waits for the
release too. A disposer runs outside the body: the context of the body is
closed there, nothing cancels it, and it must not wait for its own job.
Keep it short and unconditional; an error of one goes to the observer and
the rest still run.

**Late values.** Between the `return` of a body and the outcome the job is
still alive — it waits for its children — and a cancellation arriving
there wins. The value is registered by then, so it is released like any
other; a value that comes out of a call the body walked away from is
released too, whatever the outcome, because it reached nobody:

```dart
final job = Job<Database>((ctx) async {
  final database = await Database.open();
  ctx.onDiscard(database.close);

  return database;
});
```

This body has no context call to be interrupted at: it hands the kernel a
future and the kernel waits for it, so a cancellation arriving meanwhile
is not seen until the value is back. Registering right after it is what
covers the gap.

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
only if nobody observes that outcome. The four errors that have nowhere
else to go — a late failure of an action `wait` abandoned, a disposer, an
`onCancel` callback, a failure of work handed to `ctx.unattended` — go to
the observer, or straight to the zone when there is none. Silence is the
choice of whoever listens. A `Cancelled` never takes that second road: a
cancellation is a decision somebody made, not a failure, and the observer
is the only place it is heard.

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
      (ctx) => ctx.join(Database.open, discard: (db) => db.close()),
    );

    async.elapse(const Duration(milliseconds: 10));
    job.cancel().ignore(); // nothing awaits inside `fakeAsync`
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
job of a domain fills in, `started()` and `finished()`. Two more are
there for the error routes: `reportToZone`, for a domain whose own route
for an error with nowhere to go ends with nobody, and
`throwIfUnattended`, for a member of a domain's context that must not be
called from unattended work.

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
