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

This page builds the job of an engine:

- [A job of your own](#a-job-of-your-own): the job, its context and the
  protected API the engine reaches them through.
- [Deferred start](#deferred-start): a plain `Job` that starts when the caller
  chooses, with no engine.
- [Finishing a job by hand](#finishing-a-job-by-hand): what `finish` skips that
  a cancellation does.

[An engine of your own](engine.md) builds the rest of the engine on that job: a
queue that runs the jobs one at a time and a rule that stops them at a
sign-out.

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
behind the engine's back. `untilFinished` waits for the job without
[observing](outcomes.md#a-failure-nobody-waits-for) its outcome, so a failure
nobody looked at is still [answered for](errors.md#answering-for-errors);
waiting for `done` would count as looking.

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

Override `started()` and `finished()` to follow the lifecycle:

- `started()` runs as the body is about to start, with the job already running.
- `finished()` runs once the job has its outcome. It runs for a job dropped
  before its body ran too, with no `started()` before it.
- An error `started()` or `finished()` throws goes to `onError` and then to the
  [zone](errors.md#where-errors-go), unless the observer catches it in
  `onUnanswered`. That is the way of an error no outcome carries, as
  [Where each error goes](error-rules.md#where-each-error-goes) on the error
  rules page describes. The job goes on as it would have, and what is left
  half-done is your own bookkeeping, so keep both hooks short and
  unconditional.

`MyJob` drops its body in `finished()`: kept, it would hold everything it
captured for as long as anyone holds the job.

For the engine to answer itself for an error that would otherwise go to the
zone, do what `solo` does. Put an observer of your own on every job, mix
`JobAnswerer` into it and override its `onUnanswered`. Where that answer
reaches and where it does not:

- A child adopted without an observer takes its parent's, so the engine's
  answer reaches the children as well.
- A child that came with an observer of its own answers through its own.
- A continuation made by `then` is no job of your engine. It belongs to whoever
  called `then`, with the observer passed to `then` and no other. A failure the
  continuation takes over from your job reaches that observer as the
  continuation's own.
- What goes wrong in the continuation's own code is for the caller of `then` to
  answer, in the caller's zone, so do not hand the continuation your observer.

When the `onUnanswered` of the engine's observer has nobody to hand an error
to, `super.onUnanswered(job, error, stackTrace)` sends it to the zone the job
was created in and keeps a `Cancelled` out of the zone. It does so whichever
job the error came from: a child adopted without an observer may be no job of
your engine. `reportToZone` does the same for an engine whose answer lives
outside the observer. It is protected, so the engine reaches it through a
wrapper, as it reaches `start`, and only on jobs of its own.

A context method that must not be called from the work of `ctx.unattended`
calls `throwIfUnattended` first. That work is the subject of
[Work the job does not wait for](errors.md#work-the-job-does-not-wait-for) on
the errors page.

The full protected API is in the reference of
[JobBase](https://pub.dev/documentation/async_job/latest/engine/JobBase-class.html)
and
[JobContextBase](https://pub.dev/documentation/async_job/latest/engine/JobContextBase-class.html).

## Deferred start

A plain `Job` starts on the next microtask. If the caller needs to choose when
work begins, use `Job.deferred(body)` instead: it returns a `DeferredJob<T>`
that waits until something starts it. You can call its public `start()`
yourself, let a queue start the job, or pass it to a parent with
`ctx.run(child)`, as in [Running a child](children.md#running-a-child) on the
children page.

```dart
final job = Job.deferred<void>((ctx) => ctx.abandonable(work));
// ... later, or from a queue of your own
job.start();
```

`start()` runs the body in the zone it is called from. A queue that calls it
later, from a zone of its own, should keep the zone the job was made in and
start the job there: `final zone = Zone.current;` next to `Job.deferred`, then
`zone.run(job.start)`. [A job of your own](#a-job-of-your-own) says why.

This recipe is for a `Job.deferred`, not for a job of your engine. The queue
cannot reach the `creationZone` of a `Job.deferred`, since that member is
protected; a job of your engine starts with `creationZone.run(start)`, the way
`_launch` does.

## Finishing a job by hand

`finish` ends a job with the outcome handed in. An engine may reach for it to
drop a running job, but it is no way to do that: it skips what a cancellation
does.

| A cancellation | `finish` |
| --- | --- |
| Waits for the children and stops them | waits for none and stops none |
| Runs the `onCancel` callbacks | runs none |
| Unwinds the cleanup stack, `dispose` and `discard` included | unwinds nothing: what the body opened stays open |

Since `finish` unwinds nothing, an engine that finishes a running job by hand
releases what the job holds first. Only the debug channel, switched on with
`Job.debug = print;`, says how many cleanups `finish` left behind.

A job that has accepted a cancellation ends `Cancelled` whatever `finish` is
handed. A `Done` or a `Failed` gives way to the cancellation the job accepted,
and a value handed in goes nowhere. Only another `Cancelled` handed in stands.

On any job finished by hand, a failure of the body, thrown before `finish` or
after, is in no outcome unless it is the very one handed in. `onError` hears
it, and it goes on to `onUnanswered` or the zone, as the failure of the body of
a cancelled job does. `ignoreFailure()` on the job stops it at `onError`.

Two narrow cases are in the dartdoc of `JobBase.finish`: a `Done` handed to a
branch of `runAll` after its group heard the body fail, and one `Cancelled`
handed to two jobs, through `finish` or `cancelWith`. The second is why
`onSignOut` in
[Not waiting for the checkpoint](engine.md#not-waiting-for-the-checkpoint) on
the engine page builds a `Cancelled` at every call. A `Cancelled` that a body
throws, or a rule from `check()`, may be shared, a `const` one included: the
job ends with one the core builds from it.
