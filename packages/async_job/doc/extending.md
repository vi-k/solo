# Building on the core

An engine, on this page, is a library with its own state, queue or scheduling
rules. Build yours on the core: extend `JobBase<T>` for the job and
`JobContextBase` for the context its body gets. The base classes keep the
lifetime the other pages describe: the start, the [children](children.md), the
[cancellation](cancellation.md), the [cleanup](cleanup.md) and the
[outcome](outcomes.md). Your subclasses add the engine's behavior through their
protected API. The third type, `JobStatus`, says where a job is in its life:
`created`, `running` or `finished`.

The three live in `package:async_job/engine.dart`, not in the main import: an
app that only runs jobs never needs them. An engine imports that file in place
of `async_job.dart`: `engine.dart` exports everything `async_job.dart` does.

The lines under the code are what it prints when it runs. The job's observer
prints what reaches it, `onError:` for an error; `cancel` and `sign out` are
the moments the user cancels the job or signs out, and `outcome:` is what
`job.done` completes with.

## A job of your own

A job of your own creates the context its body gets and runs the body with it.
Two private wrappers let the rest of the engine start the job and wait for it:

```dart
import 'package:async_job/engine.dart';

final class MyJob<T> extends JobBase<T> implements ChildJob<T> {
  // Dropped once the job is over, as the core drops its own: the body
  // holds everything it captured, and a job is held to read its outcome
  // long after.
  Future<T> Function(MyContext ctx)? _body;

  MyJob(
    Future<T> Function(MyContext ctx) body, {
    super.key,
    super.observer,
    super.cancellable,
  }) : _body = body;

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<T> execute(covariant MyContext ctx) => _body!(ctx);

  @override
  void finished() => _body = null;

  // `start` and `untilFinished` are protected: the rest of the engine calls
  // them through these wrappers, private to its library. The queue starts
  // a job later, from a zone of its own, so `_launch` starts it in the zone
  // it was created in.
  void _launch() => creationZone.run(start);

  Future<void> get _untilFinished => untilFinished;
}

final class MyContext extends JobContextBase {
  MyContext(super.owner);
}
```

A `@protected` member is for the subclass alone, and an engine reaches a job
from the side, from its queue. The wrappers are private, so the engine lives in
the Dart library of `MyJob`, and nobody else who holds the job can start it
behind the engine's back. `untilFinished` waits for the job without observing
its outcome, so a failure nobody looked at still reaches the zone; waiting for
`done` would count as looking.

A body runs a job of your engine as its child with `ctx.run(job)`, and
`ctx.run` takes a `ChildJob`: that is why `MyJob` declares
`implements ChildJob<T>`. A job a body may not run as a child leaves it out.
`ChildJob` adds no member, `start` included: a parent starts the job through
`ctx.run`, your engine through its queue. `DeferredJob` is a `ChildJob` with a
public `start()`, for a job that whoever holds it may start.

`start` runs the body in the zone it is called from, and a queue calls it
later, from wherever the queue runs. `creationZone.run(start)` starts the job
in the zone it was created in: the body gets the timers, the zone values and
the error handler of the code that made the job. A future of that zone that
fails reaches the body there. Started under another `runZonedGuarded`, the body
would never hear of the failure and would wait for good, and the queue with it.
For a job made inside `ctx.unattended`, `creationZone` is the zone that work
was started from, the one `start` itself moves to when called inside the work.

Override `started()` and `finished()` to follow the lifecycle. `started()` runs
as the body is about to start, with the job already running. `finished()` runs
once the job has its outcome. It runs for a job dropped before its body ran
too, with no `started()` before it. An error either of them throws goes to
`onError` and then to the zone, unless the observer catches it in
`onUnanswered`, as [Where each error goes](observing.md#where-each-error-goes)
on the observing page describes for an error no outcome carries, and the job
goes on as it would have. Your own bookkeeping is what is left half-done, so
keep both short and unconditional. `MyJob` drops its body in `finished()`:
kept, it would hold everything it captured for as long as anyone holds the job.

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
// The first attempt: a job that refused cancellation is skipped too.
final class MyQueue {
  final _waiting = <MyJob<Object?>>[];

  void add(MyJob<Object?> job) => _waiting.add(job);

  Future<void> run() async {
    while (_waiting.isNotEmpty) {
      final job = _waiting.removeAt(0);
      if (job.isFinished) continue;
      job._launch();
      await job._untilFinished;
    }
  }
}
```

The second job is created with `cancellable: false`, and the user cancels it
while the first one runs:

```dart
final first = MyJob<void>(key: 'first', (ctx) => ctx.abandonable(upload));
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
job the user may cancel. But this one was not to be cancelled. This is what
happens:

1. The user cancels the second job while it waits. The core finishes a job that
   has not started on the spot, whatever `cancellable` says:
   `cancellable: false` keeps a body that has begun from being cut short, and
   before the start there is nothing to cut.
2. The check in the loop finds the job finished and skips it.

Nor can the core tell whether such a job will ever be started: one that refused
and was never started would never finish. The queue knows what the core does
not: it gives every job its turn.

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

Only a job that waits in the queue refuses. Who answers a cancellation of a
`cancellable: false` job depends on where the job is:

| Where the job is | Who answers the cancellation |
| --- | --- |
| Not added to the queue yet | the core: the job ends `Cancelled`, and the check in the loop skips it |
| Waiting in the queue | `MyJob`, which refuses it |
| Queued by nobody, such as one a cancelled parent turns away from its `ctx.run` | the core: refused there, the job would never start and never finish |
| Taken out of the queue to start | the core, which refuses it |

The check in the loop stays for a job cancelled before it was added to the
queue.


`rejectable` is `false` for a cancellation no job may refuse, such as one the
engine sends through a wrapper around `cancelWith` to drop a job whatever
`cancellable` says, and that one goes on to `super`. The same run now gives the
second job its turn:

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

`check()` is the checkpoint of the context. While the body runs, `abandonable`,
`join`, `pause` and `uncancellable` ask it before the action, `join` again
after it, `run` once the child's value has arrived, and `runAll` before it
hands the values back. A rule of the engine goes there. A job of the engine
downloads rows over a connection and saves them:

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

Cancelled while the download runs, the job closes the connection and ends
`Cancelled`:

```text
cancel
close the connection
outcome: Cancelled(manual)
```

### The first attempt

`MyContext` overrides `check()`. It asks `super.check()` first, the checkpoint
of the core that the analyzer requires an override to call, and then the rule:

```dart
  // The first attempt: a broken rule ends the job Failed.
  @override
  void check() {
    super.check();
    if (!account.signedIn) throw const SignedOut();
  }
```

The user signs out while the download runs:

```text
sign out
onError: SignedOut
outcome: Failed(SignedOut)
```

A rule that no longer holds should not be a failure. This is what happens:

1. `check()` throws `SignedOut` inside `join`, and the body lets it out.
2. The job ends `Failed` with an error of the engine's own, and the observer
   hears an error.
3. Nobody closes the connection: `onCancel` runs only on a cancellation.
4. A child of the job, if it had one, would run on to its end.

### A cancellation of the engine's own

The rule throws a `Cancelled` with a reason of the engine's own:

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
        stackTrace: StackTrace.current,
      );
    }
  }
```

The user signs out while the download runs:

```text
sign out
close the connection
outcome: Cancelled(signed out)
```

A sign-out now ends the job the way a cancellation does: the connection is
closed, and the outcome is `Cancelled`. The body lets the rule's `Cancelled`
out and so cancels itself, and a job whose body cancels itself stops the way a
cancelled one does: its `onCancel` callbacks run and its children stop. Nobody
asked the job for this cancellation, so it does not come through `cancelWith`,
and what holds back a cancellation asked of the job does not hold it:

| What | Against the rule's cancellation |
| --- | --- |
| `cancellable: false` | does not refuse it: it refuses only a cancellation asked of the job |
| `ctx.uncancellable` | does not hold it: the rule's cancellation is an exception `check()` throws inside the call that asked the rule, here `join` |

The job accepts the rule's cancellation as the body lets it out, not before: a
body that catches it in a `try`/`catch` and goes on is not cancelled.


The rule is asked where `check()` is asked and nowhere else: a sign-out during
the download is noticed when `join` comes back, and one during `abandonable`
only at the next call that asks.

### Not waiting for the checkpoint

With `abandonable` in place of the first `join`, the body goes on after the
user signed out:

```dart
  final rows = await ctx.abandonable(download);
```

```text
sign out
downloaded 42 rows
close the connection
outcome: Cancelled(signed out)
```

`abandonable` asks the rule before the download and not after it, so the body
had its rows, and the connection stayed open until `join` asked. An engine that
cannot wait for the next checkpoint, or has to stop a job whatever its body
catches, cancels the job itself when the user signs out, with the `Cancelled`
its rule throws. `MyJob` gets a wrapper around `cancelWith`, as it has one
around `start`:

```dart
  void _stop(Cancelled cancelled) => cancelWith(cancelled, rejectable: false);
```

The engine calls it from `account.onSignOut`, which the account calls when the
user signs out:

```dart
account.onSignOut = () => job._stop(
      Cancelled.by(
        reason: const SignedOutReason(),
        stackTrace: StackTrace.current,
      ),
    );
```

```text
sign out
close the connection
outcome: Cancelled(signed out)
```

The job accepts the cancellation inside the sign-out: its `onCancel` callbacks
run there, and `abandonable` throws at once. With `rejectable: false` the job
cannot refuse that cancellation, and no `ctx.uncancellable` holds it. A wrapper
around `cancelOwnJob` of the context does the same: it passes `false` itself.

## Deferred start

A regular `Job` schedules its own start on the next microtask. If the caller
needs to choose when work begins, use `Job.deferred(body)` instead. It returns
a `DeferredJob<T>` with a public `start()` method. You can call it yourself,
let a queue start the job, or pass it to a parent with `ctx.run(child)`, as in
[Running a child](children.md#running-a-child) on the children page.

```dart
final job = Job.deferred<void>((ctx) => ctx.abandonable(work));
// ... later, or from a queue of your own
job.start();
```

`start()` runs the body in the zone it is called from. A queue that calls it
later, from a zone of its own, should keep the zone the job was made in,
`final zone = Zone.current;` next to `Job.deferred`, and start the job there,
with `zone.run(job.start)`: [A job of your own](#a-job-of-your-own) says why.

## Finishing a job by hand

`finish` ends a job with the outcome handed in. An engine may reach for it to
drop a running job, but it is no way to do that: it skips what a cancellation
does.

| A cancellation | `finish` |
| --- | --- |
| Waits for the children and stops them | waits for none and stops none |
| Runs the `onCancel` callbacks | runs none |
| Unwinds the cleanup stack, `dispose` and `discard` included | unwinds nothing: what the body opened stays open |

Only the debug channel, switched on with `Job.debug = print;`, says how many
cleanups were left behind. A job that has accepted a cancellation ends
`Cancelled` whatever `finish` is handed: a `Done` or a `Failed` gives way to
the cancellation the job accepted, a value handed in goes nowhere, and only
another `Cancelled` handed in stands. An engine that finishes a running job by
hand anyway releases what the job holds first.

When an engine finishes a running job by hand, a failure of the body, thrown
before `finish` or after, is in no outcome unless it is the very one handed in:
`onError` hears it, and it goes on to `onUnanswered` or the zone, as the
failure of the body of a cancelled job does. `ignoreFailure()` on the job stops
it at `onError`.

A `Done` handed to a branch of `runAll` after its group heard that the body
failed comes too late for the group. The group hears of the failure right after
`onError` does, or, for a body that is not `async` and threw while `runAll` was
starting the branches, once all of them have started. The group then goes by
the failure, as if the branch had ended with it, and throws it, or sends it
where any failure of a branch it did not throw goes, which `ignoreFailure()` on
the branch silences. The value stays in the outcome of the branch alone.

A `Cancelled` handed to `cancelWith` or to `finish` belongs to one job, the way
`onSignOut` in
[Not waiting for the checkpoint](#not-waiting-for-the-checkpoint) builds one at
every call. A parent finds the child behind a cancellation by the instance:
with one instance for two of its children, its outcome names the child that
ended last, not the one its body waited for, and a `const` one is one instance
for the whole program. With asserts on, the second child of one parent to end
with the instance sends an `AssertionError` to the zone it was created in, and
ends the way it does without them. A `Cancelled` that a body throws, or a rule
from `check()`, is not bound by this: the job ends with one the core builds
from it.
