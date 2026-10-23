# An engine of your own

This page builds an engine on the job of [Building on the core](extending.md):
`MyJob`, its context `MyContext` and the wrappers `_launch` and
`_untilFinished`, as [A job of your own](extending.md#a-job-of-your-own) shows
them. The engine is a queue of jobs with a rule:

- [A queue of your own](#a-queue-of-your-own): jobs run one at a time, a
  `cancellable: false` job keeps its turn, and
  [The whole engine](#the-whole-engine) says which piece goes where.
- [A rule of your own](#a-rule-of-your-own): the jobs stop at a sign-out.

The lines under the code are what it prints when it runs. The job's observer
prints what reaches it, `onError:` for an error; `cancel` and `sign out` are
the moments the user cancels the job or signs out, and `outcome:` is what
`job.done` completes with.

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
while it waits in the queue:

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

The queue tells each job whose it is, unless the job is over by then:

```dart
  void add(MyJob<Object?> job) {
    if (job._queue != null) throw StateError('$job is in a queue already');
    if (job.isRunning) throw StateError('$job runs already');
    _waiting.add(job);
    if (!job.isFinished) job._queue = this;
  }
```

The job lets go of the queue once it is over, together with its body:

```dart
  @override
  void finished() {
    _body = null;
    _queue = null;
  }
```

A job is held to read its outcome long after it ran, and the queue holds every
job still waiting in it, with everything their bodies captured.

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

### One loop, and no other way to start

```dart
  Future<void>? _running;

  // One loop at a time: a second call gets the future of the loop that
  // runs. Started in a microtask, the loop clears `_running` after it is
  // set, even when there is nothing to run.
  Future<void> run() => _running ??= Future.microtask(_loop);

  Future<void> _loop() async {
    try {
      while (_waiting.isNotEmpty) {
        final job = _waiting.removeAt(0);
        if (job.isFinished) continue;
        job._launch();
        await job._untilFinished;
      }
    } finally {
      _running = null;
    }
  }
```

A second call of `run()` while the loop runs gets the future of that loop. Two
loops would each take the next job from `_waiting`, and two jobs would run at
once. Started at once, a loop with nothing to run would end before `_running`
got its future and leave that finished future to every later call.

`MyJob` is a `ChildJob`, so a body that holds a job of the queue may pass it to
`ctx.run`. The core asks the child in `adoptedBy` before it starts it, and a
job that waits in its queue refuses:

```dart
  @override
  void adoptedBy(JobContextBase parent) {
    if (_queue?._waiting.contains(this) ?? false) {
      throw StateError('$this waits in its queue');
    }
  }
```

The `StateError` comes out of that `ctx.run`, and the job keeps its turn.
Started by a parent, it would be started again by the queue, and the error of
that second start would end the loop and leave the jobs behind it waiting for
good. A second queue would start it again the same way, and so would its own
queue holding it twice: the first line of `add` refuses a job that is in a
queue already. Started by a parent first and added after, it would be started
again by the queue too: the second line of `add` refuses a job that runs.

### The whole engine

The engine is the job of [Building on the core](extending.md) and the code of
the sections above, in one Dart library that imports
`package:async_job/engine.dart`: the job and the queue reach each other's
private members.

| Class | Members | Shown in |
| --- | --- | --- |
| `MyJob` | `_body`, the constructor, `createContext`, `execute`, `_launch`, `_untilFinished` | [A job of your own](extending.md#a-job-of-your-own) |
| `MyJob` | `_queue`, `cancelWith`, `finished()` | [Refusing while the job waits](#refusing-while-the-job-waits) |
| `MyJob` | `adoptedBy` | [One loop, and no other way to start](#one-loop-and-no-other-way-to-start) |
| `MyQueue` | `_waiting` | [The first attempt](#the-first-attempt) |
| `MyQueue` | `add` | [Refusing while the job waits](#refusing-while-the-job-waits) |
| `MyQueue` | `_running`, `run`, `_loop` | [One loop, and no other way to start](#one-loop-and-no-other-way-to-start) |
| `MyContext` | the constructor alone | [A job of your own](extending.md#a-job-of-your-own) |

Where a member is shown twice, the later one stands: the `finished()` that lets
go of the queue replaces the one that drops only the body, and `add` and `run`
replace those of the first attempt.

Two calls of `run()` share one loop, and the jobs run one after the other:

```dart
final queue = MyQueue();
for (final name in ['photo', 'video']) {
  final job = MyJob<void>((ctx) async {
    print('$name starts');
    await ctx.abandonable(upload);
    print('$name ends');
  });
  queue.add(job);
}
await Future.wait([queue.run(), queue.run()]);
```

```text
photo starts
photo ends
video starts
video ends
```

[A rule of your own](#a-rule-of-your-own) gives this `MyContext` a rule.

## A rule of your own

The jobs of the engine may run only while the user is signed in, and
`account.signedIn` says whether the user is. A job still running when the user
signs out stops the way a cancelled one does: its `onCancel` callbacks close
what it opened, its children stop, and it ends `Cancelled`.

`check()` is the checkpoint of the context, and a rule of the engine goes
there. While the body runs, these calls ask it:

| Call | Asks `check()` |
| --- | --- |
| `abandonable`, `pause`, `uncancellable` | before the action |
| `join` | before the action and again after it |
| `run` | once the child's value has arrived |
| `runAll` | before it hands the values back |

A job of the engine downloads rows over a connection and saves them:

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
asked the job for this cancellation, so it does not come through `cancelWith`:
`cancellable: false` does not refuse it, and `ctx.uncancellable` does not hold
it, since `check()` throws inside the call that asked the rule, here `join`.

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

The two ways the engine stops a job at a sign-out:

| | The rule in `check()` | `_stop` from `onSignOut` |
| --- | --- | --- |
| The job accepts the cancellation | when it leaves the body | inside the sign-out |
| `onCancel` callbacks run | when it leaves the body | inside the sign-out, and `abandonable` throws at once |
| A body that catches it and goes on | is not cancelled | ends `Cancelled` all the same |
| `cancellable: false` | does not refuse it | does not refuse it: `rejectable: false` |
| `ctx.uncancellable` | does not hold it | does not hold it |

A wrapper around `cancelOwnJob` of the context stops the job the way `_stop`
does: it passes `rejectable: false` itself.
