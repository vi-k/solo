# Building on the core

An engine, on this page, is a library with its own state, queue or scheduling
rules. Build yours on the core: extend `JobBase<T>` for the job and
`JobContextBase` for the context its body gets. The base classes keep the
lifetime the other pages describe — the start, the [children](children.md), the
[cancellation](cancellation.md), the [cleanup](cleanup.md) and the
[outcome](outcomes.md) — while your subclasses add the engine's behavior
through their protected API. The third type, `JobStatus`, says where a job is
in its life: `created`, `running` or `finished`.

The three live in `package:async_job/engine.dart`, not in the main import: an
app that only runs jobs never needs them. An engine imports that file in place
of `async_job.dart`: `engine.dart` exports everything `async_job.dart` does.

The lines under the code are what it prints when it runs. The job's observer
prints what reaches it, `onError:` for an error; `cancel` and `sign out` are
the moments the user cancels the job or signs out, and `outcome:` is what
`job.done` completes with. Two parts of the page below open with the version
habit leads to — a queue that counts on `cancellable: false` to protect a job
while it waits, a rule written into `check()` — and show what that code does.
The version that works follows under its own heading.

## A job of your own

A job of your own creates the context its body gets and runs the body with it.
Two private wrappers let the rest of the engine start the job and wait for it:

```dart
import 'package:async_job/engine.dart';

final class MyJob<T> extends JobBase<T> {
  final Future<T> Function(MyContext ctx) _body;

  MyJob(this._body, {super.key, super.observer, super.cancellable});

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<T> execute(covariant MyContext ctx) => _body(ctx);

  // `start` and `whenDone` are protected: the rest of the engine calls
  // them through these wrappers, private to its library.
  void _launch() => start();

  Future<void> get _whenDone => whenDone;
}

final class MyContext extends JobContextBase {
  MyContext(super.owner);
}
```

A `@protected` member is for the subclass alone, and an engine reaches a job
from the side, from its queue. The wrappers are private, so the engine lives in
the Dart library of `MyJob`, and nobody else who holds the job can start it
behind the engine's back. `whenDone` waits for the job without observing its
outcome, so a failure nobody looked at still reaches the zone; waiting for
`done` would count as looking.

Override `started()` and `finished()` to follow the lifecycle. `started()` runs
as the body is about to start, with the job already running. `finished()` runs
once the job has its outcome — for a job dropped before its body ran too, with
no `started()` before it. An error either of them throws goes to `onError` and
on to the answer of the observer, as [An observer](observing.md#an-observer) on
the observing page describes for an error no outcome carries, and the job goes
on as it would have. Your own bookkeeping is what is left half-done, so keep
both short and unconditional.

For the engine to answer for such errors itself, put an observer of your own on
every job, mix `JobAnswerer` into it and override its `onUnanswered`, the way
`solo` does. A child adopted without an observer takes its parent's, so the
answer reaches the children as well, except a child that came with an observer
of its own: that one answers through its own. A continuation made by `then` is
no job of your engine: it belongs to whoever called `then`, with the observer
passed to `then` and no other. A failure it takes over from your job reaches
that observer as the continuation's own. What goes wrong in the continuation's
own code is for its caller to answer, in the caller's zone, so do not hand it
your observer.

When that `onUnanswered` has nobody to hand an error to,
`super.onUnanswered(job, error, stackTrace)` sends it to the zone the job was
created in and keeps a `Cancelled` out of the zone. It does so whichever job
the error came from: a child adopted without an observer may be no job of your
engine. `reportToZone` does the same for an engine whose answer lives outside
the observer. It is protected, so the engine reaches it through a wrapper, as
it reaches `start`, and only on jobs of its own. A context method that must not
be called from the work of `ctx.unattended` calls `throwIfUnattended` first;
that work is the subject of
[Work the job does not wait for](observing.md#work-the-job-does-not-wait-for)
on the observing page.

The full protected API is in the reference of
[JobBase](https://pub.dev/documentation/async_job/latest/engine/JobBase-class.html)
and
[JobContextBase](https://pub.dev/documentation/async_job/latest/engine/JobContextBase-class.html).

## A queue of your own

The engine runs its jobs one at a time, in the order they came. A job may be
cancelled while it waits for its turn, and the ones behind it still have to
run. With `cancellable: false` a job is not to be cancelled while it waits
either: it runs when its turn comes, whatever was asked of it meanwhile.

### The first attempt

The queue keeps the jobs, starts each with `_launch` and skips a job cancelled
while it waited:

```dart
final class MyQueue {
  final _waiting = <MyJob<Object?>>[];

  void add(MyJob<Object?> job) => _waiting.add(job);

  Future<void> run() async {
    while (_waiting.isNotEmpty) {
      final job = _waiting.removeAt(0);
      if (job.isFinished) continue;
      job._launch();
      await job._whenDone;
    }
  }
}
```

The second job is created with `cancellable: false`, and the user cancels it
while the first one runs:

```dart
final first = MyJob<void>(key: 'first', (ctx) => ctx.wait(upload));
final second = MyJob<void>(
  key: 'second',
  cancellable: false,
  (_) async => print('second runs'),
);
final third = MyJob<void>(key: 'third', (_) async => print('third runs'));
final queue = MyQueue()
  ..add(first)
  ..add(second)
  ..add(third);
final running = queue.run();
await second.cancel();
await running;
print('second: ${await second.done}');
```

```text
third runs
second: Cancelled(manual)
```

The queue skipped the second job and went on to the third, as it should with a
job the user may cancel. But this one was not to be cancelled. The core
finishes a job that has not started on the spot, whatever `cancellable` says.
`cancellable: false` keeps a body that has begun from being cut short, and
before the start there is nothing to cut. Nor can the core tell whether such a
job will ever be started: one that refused and was never started would never
finish. The queue does know: it gives every job its turn.

### Refusing while the job waits

Every cancellation asked of a job arrives at `cancelWith`, among them
`cancel()`, the cascade from a parent and the one the engine asks for itself
through `cancelOwnJob` of the context. An override passes a cancellation on to
`super` to let it through, and the analyzer requires that call to be there. To
refuse one, the override returns before the call. `MyJob` keeps the queue it
was added to. While it waits there, it refuses what it would refuse while it
runs, and a cancellation it lets through takes it out of the queue:

```dart
  MyQueue? _queue;

  @override
  void cancelWith(Cancelled cancelled, {bool rejectable = true}) {
    final waits = _queue?._waiting.contains(this) ?? false;
    if (waits && !cancellable && rejectable) return;
    _queue?._waiting.remove(this);
    super.cancelWith(cancelled, rejectable: rejectable);
  }
```

The queue tells each job whose it is:

```dart
  void add(MyJob<Object?> job) => _waiting.add(job.._queue = this);
```

The check in the loop stays for a job cancelled before it was added to the
queue. Only a job that waits in the queue refuses. A `MyJob` nobody queued is
left to the core, such as one a cancelled parent turns away from its `ctx.run`:
refused there, it would never start and never finish. Once the queue has taken
the job out to start it, the core refuses for it. `rejectable` is `false` for a
cancellation no job may refuse, such as one the engine sends through a wrapper
around `cancelWith` to drop a job whatever `cancellable` says, and that one
goes on to `super`. The same run now gives the second job its turn:

```text
second runs
third runs
second: Done(null)
```

`cancel()` returns a future that waits for the job to be over, refused or not,
so here it completes once the second job has run.

## A rule of your own

The jobs of the engine may run only while the user is signed in, and
`account.signedIn` says whether the user is. A job still running when the user
signs out stops the way a cancelled one does: its `onCancel` callbacks close
what it opened, its children stop, and it ends `Cancelled`.

`check()` is the checkpoint of the context. While the body runs, `wait`, `join`
and `uncancellable` ask it before the action, `join` again after it, `run` once
the child's value has arrived, and `runAll` before it hands the values back. A
rule of the engine goes there. A job of the engine downloads rows over a
connection and saves them:

```dart
final job = MyJob<void>(observer: printer, (ctx) async {
  ctx.onCancel(() => print('close the connection'));
  final rows = await ctx.join(download);
  print('downloaded $rows rows');
  await ctx.join(() => save(rows));
  print('saved');
})
  .._launch();
```

### The first attempt

`MyContext` overrides `check()` with the rule:

```dart
  @override
  void check() {
    if (!account.signedIn) throw const SignedOut();
  }
```

The user cancels while the download runs:

```text
cancel
close the connection
downloaded 42 rows
saved
outcome: Cancelled(manual)
```

The user signs out while the download runs:

```text
sign out
onError: SignedOut
outcome: Failed(SignedOut)
```

The analyzer points at this override, and both runs show why. It replaced the
checkpoint of the core rather than adding to it: after `cancel`, `check()` no
longer asks for the cancellation, so `join` handed the rows to a cancelled job
and the body saved them, and `ctx.uncancellable` would begin its step on one.
`wait` and `run` still throw the cancellation: they read it themselves. And a
rule that no longer holds is not a failure. The job ends `Failed` with an error
of the engine's own, nobody closes the connection, and a child of the job would
run on to its end.

### A cancellation of the engine's own

The override asks `super.check()` first, and the rule throws a `Cancelled` with
a reason of the engine's own:

```dart
final class SignedOutReason extends CancelReason {
  const SignedOutReason();

  @override
  String get name => 'signed out';
}
```

```dart
  @override
  void check() {
    super.check();
    if (!account.signedIn) {
      throw Cancelled.by(
        reason: const SignedOutReason(),
        started: true,
        stackTrace: StackTrace.current,
      );
    }
  }
```

The user cancels while the download runs:

```text
cancel
close the connection
outcome: Cancelled(manual)
```

The user signs out while the download runs:

```text
sign out
close the connection
outcome: Cancelled(signed out)
```

A cancellation stops the job at `join` again, and a sign-out ends the job
`Cancelled`. The body lets the rule's `Cancelled` out and gives itself up with
it, and a job whose body gives itself up stops the way a cancelled one does:
its `onCancel` callbacks run and its children stop. The job accepts the rule's
cancellation as the body lets it out, not before: a body that catches it and
goes on is not cancelled. Nobody asked the job for this cancellation, so it
does not come through `cancelWith`. Neither `cancellable: false` nor
`ctx.uncancellable` stands in the rule's way: they refuse or hold a
cancellation asked of the job, and the rule's comes as a throw from the very
step it stops. The rule is asked where `check()` is asked and nowhere else: a
sign-out during the download is noticed when `join` comes back, and one during
a `wait` only at the next call that asks.

An engine that cannot wait for the next checkpoint, or has to stop a job
whatever its body catches, cancels the job itself when the user signs out, with
the `Cancelled` its rule throws. It does so through wrappers of its own, as
with `start`: around `cancelWith` with `rejectable: false`, or around
`cancelOwnJob` of the context, which passes `false`. The job cannot refuse that
cancellation, and no `ctx.uncancellable` holds it. `finish` ends a job with the
outcome handed in, and it is no way to stop a running one: it waits for no
children and stops none, runs no `onCancel` callback and unwinds no cleanup
stack, so no `dispose` and no `discard` runs, and what the body opened stays
open. Only the debug channel, switched on with `Job.debug = print;`, says how
many cleanups were left behind. A job that has accepted a cancellation ends
`Cancelled` whatever `finish` is handed: a `Done` or a `Failed` gives way to
the cancellation the job accepted, a value handed in goes nowhere, and only
another `Cancelled` handed in stands. An engine that finishes a running job by
hand anyway releases what the job holds first.

## Deferred start

A regular `Job` schedules its own start on the next microtask. If the caller
needs to choose when work begins, use `Job.deferred(body)` instead. It returns
a `DeferredJob<T>` with a public `start()` method. You can call it yourself,
let a queue start the job, or pass it to a parent with `ctx.run(child)`, as in
[Children](children.md#children) on the children page.

```dart
final job = Job.deferred<void>((ctx) => ctx.wait(work));
// ... later, or from a queue of your own
job.start();
```
