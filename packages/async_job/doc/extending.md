# Building on the core

If your library needs its own state, queue or scheduling rules, build them on
the core: extend `JobBase<T>` for the job and `JobContextBase` for the context
its body gets. The base classes keep the lifetime the other pages describe —
the start, the [children](children.md), the [cancellation](cancellation.md),
the [cleanup](cleanup.md) and the [outcome](outcomes.md) — while your
subclasses add the library's behavior through their protected API. The third
type, `JobStatus`, says where a job is in its life: `created`, `running` or
`finished`.

The three live in `package:async_job/engine.dart`, not in the main import: an
app that only runs jobs never needs them. An engine imports that library in
place of `async_job.dart`, which it exports too.

The lines under the code are what it prints when it runs. The job's observer
prints what reaches it, `onError:` for an error; `cancel` and `sign out` are
the moments the user does so, and `outcome:` is what `job.done` completes with.
Two parts of the page below open with the version the protected API leads to —
a queue that starts its jobs with `start`, a rule added to `check()` — and show
what that code does. The version that works follows under its own heading.

## A job of your own

A job of your own creates the context its body gets, and the engine that runs
it opens a door of its own to what is protected:

```dart
import 'package:async_job/engine.dart';

final class MyJob<T> extends JobBase<T> {
  MyJob(this._body, {super.key, super.observer});

  final Future<T> Function(MyContext ctx) _body;

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<T> execute(covariant MyContext ctx) => _body(ctx);

  // `start` and `whenDone` are protected: the engine opens doors of its
  // own to them, private to the library it lives in.
  void _launch() => start();

  Future<void> get _whenDone => whenDone;
}

final class MyContext extends JobContextBase {
  MyContext(super.owner);
}
```

`@protected` holds inside a subclass, and an engine reaches a job from the
side: from its queue, from its controller. The wrappers are private, so the
engine lives in the library of `MyJob`, and nobody else who holds the job can
start it behind the engine's back. `whenDone` waits for the job without
observing its outcome, so a failure nobody looked at still reaches the zone;
waiting for `done` would count as looking.

Override `started()` and `finished()` to follow the lifecycle. `started()` runs
as the body is about to start, with the job already running. `finished()` runs
once the job has its outcome — for a job dropped before its body ran too, with
no `started()` before it. An error either of them throws goes to `onError` and
on to the answer of the observer, and the job goes on as it would have; your
own bookkeeping is what is left half-done, so keep both short and
unconditional.

To give an error nobody answered for an answer of your own, put an observer of
your own on every job, make it a `JobAnswerer` and override its
[`onUnanswered`](observing.md#an-observer), the way `solo` does. A child
adopted without an observer takes its parent's, so the answer reaches the
children as well, except a child that came with an observer of its own: that
one answers through its own. A continuation made by `then` is no job of your
engine: it belongs to whoever called `then`, with the observer passed to `then`
and no other. A failure it takes over from your job reaches that observer as
the continuation's own. What goes wrong in the continuation's own code is for
its caller to answer, in the caller's zone, so do not hand it your observer.

When the answer of your engine ends with nobody, `reportToZone` hands the error
to the job's creation zone, and it keeps a cancellation out of the zone the way
the core does. For a context method that must not be called from
[unattended work](observing.md#work-the-job-does-not-wait-for),
`throwIfUnattended` enforces that restriction. The full protected API is in the
reference of
[JobBase](https://pub.dev/documentation/async_job/latest/engine/JobBase-class.html)
and
[JobContextBase](https://pub.dev/documentation/async_job/latest/engine/JobContextBase-class.html).

## A queue of your own

The engine runs its jobs one at a time, in the order they came. A job may be
cancelled while it waits for its turn, and the ones behind it still have to
run.

### The first attempt

The queue keeps the jobs and starts each through the door of `MyJob`:

```dart
final class MyQueue {
  final _waiting = <MyJob<Object?>>[];

  void add(MyJob<Object?> job) => _waiting.add(job);

  Future<void> run() async {
    while (_waiting.isNotEmpty) {
      final job = _waiting.removeAt(0).._launch();
      await job._whenDone;
    }
  }
}
```

The user cancels the second job while the first one runs:

```dart
final second = MyJob<void>(key: 'second', (ctx) => ctx.wait(upload));
final queue = MyQueue()
  ..add(MyJob<void>(key: 'first', (ctx) => ctx.wait(upload)))
  ..add(second);
final running = queue.run();
await second.cancel();
print('second: ${await second.done}');
try {
  await running;
  print('the queue is empty');
} on StateError catch (error) {
  print('the queue stopped: $error');
}
```

```text
second: Cancelled(manual)
the queue stopped: Bad state: Job(second) has already finished
```

A job that has not started is finished on the spot by its cancellation: there
is no body to stop. The queue still held it, and when its turn came, `start`
threw. The queue stopped there, and every job behind the second one waits for
good.

### Leaving the queue on cancellation

Every cancellation asked of a job arrives at `cancelWith`: `cancel()`, the
cascade from a parent, `cancelOwnJob` of its context. A body that gives itself
up does not come through it, and its job has left the queue by then. It is the
one member of the lifecycle a subclass extends rather than replaces, and the
analyzer holds an override to calling `super`. `MyJob` keeps the queue that
holds it and takes itself out of it there:

```dart
  MyQueue? _queue;

  @override
  void cancelWith(Cancelled cancelled, {bool rejectable = true}) {
    _queue?._waiting.remove(this);
    super.cancelWith(cancelled, rejectable: rejectable);
  }
```

The queue tells each job whose it is:

```dart
  void add(MyJob<Object?> job) => _waiting.add(job.._queue = this);
```

```text
second: Cancelled(manual)
the queue is empty
```

The core finishes a job that has not started whatever `cancellable` says: a job
created with `cancellable: false` turns a cancellation down only once it runs.
If a job of your queue may turn one down while it waits, do it in `cancelWith`,
before `super`, as `solo` does.

## A rule of your own

The jobs of the engine may run only while the user is signed in, and
`account.signedIn` says whether they are. A job still running when the user
signs out stops the way a cancelled one does: its `onCancel` callbacks close
what it opened, its children stop, and it ends `Cancelled`.

`check()` is the checkpoint of the context. While the body runs, `wait`, `join`
and `uncancellable` ask it before the action, `join` again after it, `run` once
the child's value has arrived, and `runAll` before it hands the values back. A
rule of the engine goes there. The job downloads rows over a connection and
saves them:

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

```text
sign out
close the connection
outcome: Cancelled(signed out)
```

```text
cancel
close the connection
outcome: Cancelled(manual)
```

A cancellation stops the job at `join` again, and a sign-out ends the job
`Cancelled`. The body lets the rule's `Cancelled` out and gives itself up with
it, and a job whose body gives itself up stops the way a cancelled one does:
its `onCancel` callbacks run and its children stop. The job accepts the rule's
cancellation as the body lets it out, not before: a body that catches it and
goes on is not cancelled. Neither `cancellable: false` nor `ctx.uncancellable`
holds the rule back: they turn down or hold a cancellation asked of the job,
and the rule's comes as a throw from the very step it stops. The rule is asked
where `check()` is asked and nowhere else: a sign-out during the download is
noticed when `join` comes back.

An engine ends a job that is still running by cancelling it: through
`cancelWith`, or through `cancelOwnJob` of its context, a cancellation the job
cannot refuse. `finish` ends a job with the outcome handed in, but it waits for
no children and unwinds no cleanup stack: no `onDispose` and no `discard` runs,
and what the body opened stays open. Only the debug channel says how many
cleanups were left behind. A job that has accepted a cancellation ends with
that cancellation whatever `finish` is handed, and a value handed in goes
nowhere. An engine that finishes a running job by hand anyway releases what the
job holds first.

## Deferred start

A regular `Job` schedules its own start on the next microtask. If the caller
needs to choose when work begins, use `Job.deferred(body)` instead. It returns
a `DeferredJob<T>` with a public `start()` method. You can call it yourself,
let a queue start the job, or pass it to a parent with `ctx.run(child)`, as in
[Children](children.md#children).

```dart
final job = Job.deferred<void>((ctx) => ctx.wait(work));
// ... later, or from a queue of your own
job.start();
```
