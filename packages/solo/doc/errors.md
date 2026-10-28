# Errors

A job that fails ends `Failed`. Three parts of the code deal with its error:

- `enqueue(ifFailed: ...)` turns the failure into the state the screen shows;
- `onError`, a hook of the controller, hears the error, to report it;
- whoever observes the outcome answers for the error.

When nobody observes the outcome, `onUnanswered` answers for the error. By
default it sends the error to the creation zone, the zone the job was created
in. There it is an uncaught error, and in the root zone an uncaught error can
end the application. Some errors have no outcome to ride on, and `onUnanswered`
answers for those as well. The first section,
[Where each error goes](#where-each-error-goes), lists every kind.

The sections of the page, by what the application needs:

| The application needs | What gives it | Section |
| --- | --- | --- |
| A report of every error of a job | `onError` of the controller, or of a `SoloObserver` for every controller | [Reporting an error](#reporting-an-error) |
| A failure kept out of the zone | Observing the outcome: `await job.value` where the error is caught, or `job.ignoreFailure()`; for the errors a job expects, `isExpectedError` | [Naming the expected errors](#naming-the-expected-errors) |
| An answer for an error that no outcome carries, or for a `Failed` nobody observes | `onUnanswered`, or `Solo.unansweredHandler` for the whole application | [Answering for an error](#answering-for-an-error) |
| A catch that lets a cancellation through | `ctx.check()` at the top of the catch | [Catching errors inside a body](#catching-errors-inside-a-body) |
| Another attempt after a failure | `ctx.pause` between attempts, or a loop in the caller | [Retrying a failed call](#retrying-a-failed-call) |
| A rule that refuses | A rule that answers `false` instead of throwing | [Errors in state rules](#errors-in-state-rules) |
| Background work whose errors reach the hooks | `ctx.unattended` | [Background work](#background-work) |

The lines under some blocks are what the code prints. `report:` is an error
handed to the crash reporter, and `zone:` is an error that reached the creation
zone uncaught.

## Where each error goes

An error of a job can go two ways at once, and a future the job hands out adds
a third way, Dart's own:

| Route | Who gets the error, in order | Where it ends |
| --- | --- | --- |
| Report | `onError` of a `SoloObserver`, then `onError` of the controller, hear it | It does not end there: the hooks hear it and return, and the error goes on along the answer route |
| Answer | Whoever observes the outcome, then `onUnanswered` of the controller; for an error the job names in `isExpectedError`, only whoever observes the outcome | At whoever observes the outcome; otherwise at an override of `onUnanswered` or at `Solo.unansweredHandler`; with neither, in the creation zone. An error the job names in `isExpectedError` that nobody observes ends nowhere: not at `onUnanswered`, not in the zone |
| Dart's | Whoever holds the future of `job.value` or `ctx.run(child)` | Where that future is handled; unhandled, in the zone, like any future error |

The table below names, for each kind of error, who hears it and who answers for
it. `onError` in it stands for both hooks: the two hear the same errors. An
error that no outcome carries enters the answer route at `onUnanswered` and
goes on from there as the Answer row above says. Taking `job.value` observes
the outcome: when that future goes unhandled, its error takes Dart's route to
the zone, once, and `onUnanswered` never gets it.

The current zone is the zone the hook is called in, the zone of the code that
met the error. The body of a root job, and the hooks it leads to, run in the
zone the job was created in, and the body of a child runs in the zone of the
parent that runs it. A `ctx.onCancel` callback runs in the zone of the call
that cancels the job. A start rule is asked from whatever moves the queue: the
call that queues the job, or the job ahead of it as it ends. A change made by
`externalSetState` runs in the zone of its caller. The answer route keeps to
its own zone: an error nobody answers for goes to the creation zone, wherever
the hooks heard it.

| The error | Who hears it | Who answers for it |
| --- | --- | --- |
| An error of the body, and the job ends `Failed` with it | `onError` | Whoever observes the outcome; if nobody does, `onUnanswered`, unless `isExpectedError` names it |
| An error of a start rule: `canStart` throws instead of answering | `onError` | The same: the job ends `Failed` with it |
| An error of the body, and the job ends `Cancelled` | `onError` | `onUnanswered`, unless `ignoreFailure()` was called on the job or `isExpectedError` names it |
| A late error of an operation `abandonable` stopped waiting for | `onError` | `onUnanswered`, unless `isExpectedError` names it |
| An error of a disposer, a `ctx.onCancel` callback or a state handler of a job | `onError` | `onUnanswered`, unless `isExpectedError` names it |
| An error of a `whenCancelled` or `whenFinished` listener | `onError` | `onUnanswered` |
| A `keepWhile` that throws when a change of state re-checks it | `onError` | `onUnanswered`, unless `isExpectedError` names it |
| An error of work handed to `ctx.unattended` | `onError` | `onUnanswered`, unless `isExpectedError` names it |
| An error of a branch of `ctx.runAll` that the group did not throw | `onError` | `onUnanswered`, unless `ignoreFailure()` was called on the branch or `isExpectedError` names it |
| An error that `Job.isCancellationError` names, on a cancelled job | `onError` | Nobody |
| An error `isExpectedError` names | `onError`, with `never` | Whoever observes an outcome that carries it; nobody else: not `onUnanswered`, not `Solo.unansweredHandler`, not the zone |
| A `Cancelled` from outside the body, such as an abandoned operation that ended in another job's cancellation | `onError` | Nobody |
| A `Cancelled` the body lets out, such as that of a cancelled child | Nobody | Nobody: the job ends `Cancelled` with it |
| The job's own cancellation, thrown back by an abandoned operation | Nobody | Nobody |
| An error of a future the body did not await | Nobody | The zone the body runs in |
| An error a hook throws | Nobody | The current zone |
| An error a listener throws while it is notified | `onListenerError` | `onListenerError`; by default the current zone |

An error can reach both `onError` and the zone. An application that reports in
both places hears it twice.
[Handled and unhandled failures](#handled-and-unhandled-failures) shows how a
caller observes the outcome, and
[Answering for an error](#answering-for-an-error) shows the override, the
handler and `Job.isCancellationError`.

An error that `onUnanswered` takes can come after the job has completed. It
does not replace the outcome the job already has. Every error that reaches
`onUnanswered` has been through `onError` already.

Dart's route in the table above is not the engine's. An unhandled error of
`job.value` or of `ctx.run(child)` is an unhandled future error under the rules
of Dart, even when that error is `Cancelled`. Handle those futures like any
other: `await` them where the error is caught, or give them `onError` or
`Future.ignore()`. `job.ignoreFailure()` does not do it for them. It tells the
job that nobody needs its failure. A future already taken from `job.value`
stays an ordinary future whose error somebody has to handle.

## Reporting an error

The profile controller sends the failures of its jobs to the crash reporter:

```dart
final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  // ...the jobs of the quick start, without its `isExpectedError`...

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => reportCrash(error, stackTrace);
}
```

A controller has a hook for each thing that happens to it and its jobs:
`onStart`, `onFinish`, `onError`, `onUnanswered`, `onLog`, `onChange` and
`onClose`, and `onListenerError` for a listener that throws while it is
notified.

`onError` hears the errors the jobs of the controller run into:

- the failure of a body;
- an error of cleanup, or of an operation that `abandonable` stopped waiting
  for;
- a rule that threw instead of answering.

The hook reports and returns. It answers for nothing, and overriding it moves
no error anywhere. Its `answer` says what the job does about the error next:
with `answered`, `onUnanswered` is asked about it too, unless `ignoreFailure()`
is called before it is. The other values are in
[Where each error goes](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/error-rules.md#where-each-error-goes)
on the error rules page of `async_job`. One case of `never` is `solo`'s own and
is not on that page: an error the job names in `isExpectedError`, as
[Naming the expected errors](#naming-the-expected-errors) shows.

It hears each error once for each job. An error that a child throws and its
parent lets through is a failure of both, so the hook hears it twice. The `job`
it is given tells the two calls apart. A crash reporter fed from here can get
one error three times: from the child, from the parent and, when nobody
observes the parent's outcome, from `onUnanswered`. By default `onUnanswered`
hands it to `Solo.unansweredHandler` or the creation zone.

## Handled and unhandled failures

A screen starts a job of the profile from the quick start, without its
`isExpectedError` and with no reporting hook of its own: `profile.load()`, and
nobody waits for the result. The network is down, and `fetchName` throws an
`ApiException`. The application wants the failure in the crash reporter, and
nothing more.

### The first attempt

A `SoloObserver` hears the hooks of every controller, as
[Watching every controller](diagnostics.md#watching-every-controller) on the
diagnostics page shows. So the application reports from an observer:

```dart
// The first attempt: the failures still go to the zone.
final class Failures extends SoloObserver {
  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => reportCrash(error, stackTrace);
}
```

```text
report: ApiException: no network
zone: ApiException: no network
```

The report goes out, and then the same error reaches the zone. This is what
happens:

1. The load fails, and the job ends `Failed`. `onError` of the observer hears
   the error and reports it.
2. A hook that is told of a failure does not observe the outcome, whichever
   hook it is. Nobody has read the outcome of the load.
3. Nobody answers for that `Failed` either. `onUnanswered` of the controller
   hands it to `Solo.unansweredHandler`, and with no handler set to the
   creation zone through `Zone.handleUncaughtError`. In the root zone that can
   end the application, a moment after the report was sent.

### Observing the outcome

The observer stays, and the screen observes the outcome:

```dart
profile.load().ignoreFailure();
```

```text
report: ApiException: no network
```

Reading `job.done` or `job.value`, or calling `job.ignoreFailure()`, observes
the outcome. Reading `job.outcome` does not. `ignoreFailure()` is for a caller
that needs no result and leaves the reporting to the hooks. A caller that needs
the result takes it with `await job.value` and answers for the error by
catching it.

That caller cannot catch one failure. If the job ends `Cancelled` after the
load failed, `await job.value` throws the `Cancelled`. The failure goes to
`onUnanswered`, as [Answering for an error](#answering-for-an-error) shows.
`ignoreFailure()` drops this failure as well: `onError` still hears it, and it
goes no further.

### Naming the expected errors

The profile knows which of its errors are expected: a network that is down
makes `fetchName` throw an `ApiException`. Its `load()` names that type in
`isExpectedError`:

```dart
Job<String> load() => enqueue<ProfileState, String>(
  key: 'load',
  policy: Policy.droppable,
  ifFailed: (state, error, stackTrace) => Failure(error),
  isExpectedError: (error) => error is ApiException,
  ifCancelled: (state, cancelled) => const Initial(),
  (ctx) async {
    ctx.emit(const Loading());
    final name = await ctx.abandonable(api.fetchName);
    ctx.emit(Loaded(name));
    return name;
  },
);
```

The observer of the first attempt stays, and the screen calls `profile.load()`
with nobody waiting for the result:

```text
report: ApiException: no network
```

`onError` hears the error with `JobErrorAnswer.never`, and nobody is asked to
answer for it: not `onUnanswered`, not `Solo.unansweredHandler`, not the zone.
The outcome is still `Failed`, the screen shows the `Failure` of `ifFailed`,
and `await job.value` still throws the error.

A bug is not an `ApiException`. Say `fetchName` reads the name of the reply
with `!`, and a reply comes without one: the `!` throws a `TypeError`, and that
error goes the way of the first attempt:

```text
report: Null check operator used on a null value
zone: Null check operator used on a null value
```

The predicate is asked about each error of the job on its own, whether
`ifFailed` ran or not: the failure of the body, and the errors that no outcome
carries, listed under [Answering for an error](#answering-for-an-error), all
but those of a listener. A `ParallelWaitError` comes apart first, so
`error is ParallelWaitError` never matches. A cancellation is not asked about:
a `Cancelled`, and an error that `Job.isCancellationError` names, go as before.
A predicate that throws names nothing: the error goes on as it would without
one, and what the predicate threw goes to the zone the job was created in.

A child started in the body takes the predicate of the job that started it,
unless it is made by `job(...)` with one of its own. A broad type such as
`error is Exception` silences the bugs of every child as well, so keep the
predicate a check of the types the API throws.

A continuation answers for the error with its own handle. `load()` is
`droppable`, and a `droppable` job is continued only through `shared()`: a
plain `then` on it throws. The handle that `shared()` returns, and a `then` on
that handle, know nothing of `isExpectedError`: unobserved, they send the
failure to the zone, as
[When a link fails](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/chains.md#when-a-link-fails)
on the chains page of `async_job` says.

## Answering for an error

Most errors ride on an outcome: a failed body becomes `Failed`, and whoever
observes it answers for it. When nobody does, the controller whose job it was
answers in `onUnanswered`. It answers there as well for the errors that have no
outcome to ride on. Here the profile keeps them in a list:

```dart
final class ProfileController extends Solo<ProfileState> {
  // ...the jobs and the reporting hook above...

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      _apiFailures.add(error);
}
```

These are the errors that no outcome carries:

- an operation that `abandonable` stopped waiting for, which fails later;
- what the job calls outside its body: a disposer, a `ctx.onCancel` callback, a
  state handler of a job;
- a `whenCancelled` or `whenFinished` listener, which the caller of the job
  registers;
- a `keepWhile` that throws when a change of state re-checks it;
- work handed to `ctx.unattended`;
- the failure of a branch of `ctx.runAll` that the group did not throw;
- the failure of the body of a job that ends `Cancelled`: whoever reads that
  outcome gets the cancellation.

The override above answers for them and for a `Failed` nobody observes. They
reach nothing else. This controller owns what its jobs failed at and says so.
An error that a job names in `isExpectedError` does not reach the override,
unless a listener threw it: a listener is the caller's code, and the predicate
is not asked about its errors.

A controller without such an override keeps the default body. It hands the
error to `Solo.unansweredHandler`, one handler for the whole application, set
once at startup:

```dart
Solo.unansweredHandler = (solo, job, error, stackTrace) =>
    Sentry.captureException(error, stackTrace: stackTrace);
```

With no handler set, the error goes to the creation zone. An override keeps
that route as well by calling `super.onUnanswered(job, error, stackTrace)`. So
each controller decides whether the handler of the application hears its errors
at all.

A handler or an override can throw, say because the reporter is down. The error
it was asked about is not lost: it goes to the creation zone first. Then what
the hook threw goes to the current zone. A `Cancelled` the hook throws stays
out. The error itself, thrown back by the hook, stays out too, so that error
reaches the zone once. A hook that reported the error before it threw has it
reported twice.

`onUnanswered` and `Solo.unansweredHandler` get one failure at a time. A
`ParallelWaitError` that `[a, b].wait` throws with several errors in it comes
as several calls, each failure with its own stack trace. An uncaught
`Cancelled`, alone or inside one, does not come at all. `onError` hears them
one at a time too, each `Cancelled` included.

The last item of the list comes most often from the cancellation itself. A call
that `ctx.join` is still waiting out stops at a token that `ctx.onCancel`
cancelled, and throws as it stops. The engine cannot tell that error from a
failure of the call. So the application names such errors once, at startup, in
`Job.isCancellationError` of the core. A failure of a cancelled job that it
names reaches `onError` and goes no further: neither `onUnanswered` nor
`Solo.unansweredHandler` hears it.

[The token](cancellation.md#the-token) on the cancellation page names in
`Job.isCancellationError` the error a player throws as it stops.
[Errors of a cancellation](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/errors.md#errors-of-a-cancellation)
on the errors page of `async_job` takes the field apart. A body that catches
such an error asks the job, not the error:
[Letting cancellation through](#letting-cancellation-through) has the `catch`.

Answering for an error is a duty somebody takes on. Switching on a log does not
take it, and neither does setting a `SoloObserver`: watching is not answering.

## Catching errors inside a body

A body drives the camera. On a failure of the device it wants a state of its
own, `Broken`, and a camera left half-open put back the way it was.

### The first attempt

A device can fail anywhere, so the body catches everything:

```dart
// The first attempt: a cancellation resets a working camera.
try {
  await ctx.join(hw.open);
  await ctx.join(() => hw.setZoom(zoom));
} on Object catch (error) {
  await hw.reset();
  ctx.emit(Broken(error));
  rethrow;
}
```

The user cancels this job while `hw.setZoom` is in flight. Nothing failed, and
the camera is reset. This is what happens:

1. `join` waits the call out and then throws `Cancelled` in place of its
   result.
2. `Cancelled` implements `Exception`, so the broad `catch` takes it and reads
   it as a failure of the camera. It resets a camera that opened and took its
   zoom. Whoever cancelled the job waits for the reset as well.
3. `ctx.emit` on a cancelled job throws `Cancelled` in turn. `Broken` never
   reaches the screen, and the `rethrow` under it never runs.
4. The outcome is the same `Cancelled` that `rethrow` would have given.

The job ends exactly as a cancelled job should. Neither the hooks nor the zone
mention anything, and the only trace is on the device.

### Letting cancellation through

```dart
try {
  await ctx.join(hw.open);
  await ctx.join(() => hw.setZoom(zoom));
} on Object catch (error) {
  ctx.check();
  await hw.reset();
  ctx.emit(Broken(error));
  rethrow;
}
```

`ctx.check()` asks the job, not the error. It throws the job's `Cancelled` if
the job has accepted one, whatever the catch took. What follows it handles the
failures of a job that nobody cancelled.

A clause for the error does less. Take `on Cancelled { rethrow; }` in front of
the broad clause, or `if (error is Cancelled) rethrow;` as its first line. It
holds while every call in the `try` runs to its end, as these two do.
[The token](cancellation.md#the-token) on the cancellation page wires a token
that `ctx.onCancel` cancels. A call told to stop through such a token may stop
by throwing. Then the catch gets an error of the call in place of the
`Cancelled`, because `join` throws an error of its call as it is. The clause
lets that error by, and the camera is reset for a cancellation again.
[Catching errors of the operation](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cancellation.md#catching-errors-of-the-operation)
on the cancellation page of `async_job` takes that clause apart.

Asking the job has its other side. A camera that fails on its own after the job
accepted a cancellation is not reset by this catch either, and no hook hears of
the failure. On a cancelled job the catch only lets the cancellation out.

Once a job has accepted a cancellation, its outcome stays `Cancelled` even if
the body catches it. For a final failure state, use the `ifFailed` parameter of
`enqueue` rather than a broad catch.

## Retrying a failed call

The network drops a request now and then. The profile tries three times before
it gives up, and waits a little longer after each failure.

### The first attempt

A loop catches the failure and waits before the next attempt:

```dart
// The first attempt: a cancellation sits out the delays.
ctx.emit(const Loading());
for (var attempt = 1; ; attempt++) {
  final String name;
  try {
    name = await ctx.abandonable(api.fetchName);
  } on Object {
    if (attempt == 3) rethrow;
    await Future<void>.delayed(Duration(seconds: attempt));
    continue;
  }
  ctx.emit(Loaded(name));
  return name;
}
```

The catch is there for the network, and it takes a cancellation along. The user
cancels the job while the first call is in flight, and the job ends three
seconds later. This is what happens:

1. `abandonable` throws `Cancelled`. The catch counts it as a failed attempt
   and waits a second.
2. A plain `Future.delayed` is no checkpoint, so the job sits that second out.
3. The next `abandonable` throws at once, without calling `fetchName`, and the
   catch waits two seconds more.
4. Only the third throw goes out. The job ends `Cancelled` three seconds after
   it was cancelled.

All that time the job holds the queue. The next job waits for a body that has
nothing left to do, and so does `close()`.

### A pause between attempts

```dart
ctx.emit(const Loading());
for (var attempt = 1; ; attempt++) {
  final String name;
  try {
    name = await ctx.abandonable(api.fetchName);
  } on Object {
    if (attempt == 3) rethrow;
    await ctx.pause(Duration(seconds: attempt));
    continue;
  }
  ctx.emit(Loaded(name));
  return name;
}
```

`ctx.pause` is a delay that is a checkpoint. If the catch has taken a
cancellation, the pause throws it again before it waits. A cancellation that
comes during a pause ends the pause there and cancels its timer. Either way the
job ends `Cancelled` at once. Like `ctx.check()` in
[Letting cancellation through](#letting-cancellation-through), the pause asks
the job, not the error, so the catch needs no clause for the cancellation.

After the third failure of the network, `rethrow` lets it out, and the job ends
`Failed` with that error. `on Object` repeats every failure of the call, a bug
in reading the answer among them. A clause for the failures worth repeating,
such as `on ApiException`, lets a bug end the job at once. It still needs
nothing for the cancellation.

### Retrying from the caller

A pause in the body still belongs to the job. Root jobs run one at a time, so
the next job of the profile waits through every attempt and every pause between
them. Where other jobs should run between the attempts, the caller retries
instead of the body. The job is `load()` of the quick start, without its
`isExpectedError`, on the profile of [Reporting an error](#reporting-an-error),
and it tries once.

```dart
Future<Outcome<String>> loadWithRetries(ProfileController profile) async {
  for (var attempt = 1; ; attempt++) {
    final outcome = await profile.load().done;
    if (outcome is! Failed || attempt == 3) return outcome;
    await Future<void>.delayed(Duration(seconds: attempt));
  }
}
```

Here `Future.delayed` is in its place: it belongs to no job, so it holds
nothing. The jobs sent in between run in the gap, and `close()` does not wait
for it. How the loop ends:

- A `Cancelled` ends the loop as a `Done` does.
- `cancelAll()` while an attempt runs cancels it, and the loop returns that
  `Cancelled`.
- `cancelAll()` in the gap finds no job to cancel, and the next attempt starts
  after it all the same.
- Close the profile, and the next attempt is refused: the loop returns its
  `Cancelled(closed)` at the end of the gap.

Each attempt is a job of its own, and the profile shows how each one ended.
Between the attempts the state is the `Failure` of `ifFailed`, and the screen
shows the error until the next attempt emits `Loading`. With the loop in the
body, the state stays `Loading` throughout.

Every failed attempt reaches `onError` too, so the crash reporter hears each
one. The loop in the body let it hear only the failure that ended the job.
`done` observes each outcome, so no failure of an attempt goes on to the zone.

The gap itself is the caller's to stop. Until it does, the timer outlives a
closed profile: a widget test that closes the profile in the gap fails on it,
where the loop in the body passes. Nor does the loop know of a load sent in the
gap: if that load succeeds, the next attempt still loads again. A wait the
controller itself stops is the countdown of
[A delayed start](jobs.md#a-delayed-start).

## Errors in state rules

A job that needs a free slot asks for one in its start rule.

### The first attempt

A rule that cannot go on throws, the way a function does:

```dart
// The first attempt: a throw in canStart is a failure.
canStart: (state) {
  if (state.free == 0) throw StateError('no free slot');

  return true;
},
```

A throw reads like a refusal, and it is a failure. This is what happens:

1. The error goes to `onError`: a crash report for an ordinary "not now".
2. The job ends `Failed`, and `onUnanswered` answers for that outcome unless
   somebody observes it.
3. The state handler passed as `ifFailed` to that same `enqueue` is not called.
   A state handler computes the state after a job that ran, and this one never
   started.
4. The queue goes on to the next job.

### A rule answers

```dart
// A rule answers; it does not throw to refuse.
canStart: (state) => state.free > 0,
```

A rule that answers `false` is not an error: it cancels the job. The trace of
that `Cancelled` is taken where the rule said no. A `keepWhile` re-checked on a
change says no from inside that change, so the trace leads to the `emit` or the
`externalSetState` whose state broke the rule.

Where a rule says no away from the change, the trace names the place that
noticed. `canStart` is asked once, as the job leaves the queue, and names the
queue. A job that breaks its own rule is not re-checked on its own `emit`. It
finds out at its next checkpoint, such as `ctx.state`, `ctx.check()`, a waiting
method or `ctx.each`, and the trace names that checkpoint.

Where a rule throws anyway decides what becomes of the error:

| Where it throws | What happens |
| --- | --- |
| A start rule | The job fails and the queue continues. |
| A rule at a context checkpoint | The body receives the error. |
| Re-evaluation after a state update | Reported; it does not itself cancel the running body. |
| The same re-evaluation, on a job with a state handler | Reported, and the handler is disabled. |

A job with a state handler is re-evaluated after its body has ended as well.
[Handler eligibility and errors](state.md#handler-eligibility-and-errors) on
the state page is about that. An error of a re-evaluation takes the way the
table of [Where each error goes](#where-each-error-goes) gives a `keepWhile`:
`onError`, then `onUnanswered`, and the creation zone when nobody answers.

## Background work

A body sends an analytics event. The job has nothing to wait for and nothing to
cancel: the event goes out or it does not.

### The first attempt

`unawaited` says that the caller does not wait:

```dart
// The first attempt: the error belongs to nobody in the job.
unawaited(analytics.send('zoom'));
```

That is all it says. The error of the future belongs to nobody in the job. The
hooks never see it, and `Solo.unansweredHandler` is never asked. It surfaces as
an unhandled error in the zone the body runs in, which for a job from the queue
is the zone the job was created in. Nothing there names the job it came from.

### Work with a life of its own

```dart
// Work with a life of its own: the job neither waits for it nor cancels
// it, and its errors still reach the job's hooks.
ctx.unattended(() => analytics.send('zoom'));
```

`ctx.unattended(action)` starts work that the job neither waits for nor
cancels. Its errors stay with the job, even after the job finishes. `onError`
hears them, and `onUnanswered` answers for them; with no override and no
handler, they end in the creation zone. Use it for work with a lifetime of its
own.

Start that work inside the callback. A future made before the call and only
awaited inside fails past the hooks, into the zone it was made in.
[Work handed to the job](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/errors.md#work-handed-to-the-job)
on the errors page of `async_job` draws that boundary both ways.

Unattended work is not the job, and the context refuses there whatever acts on
the job. `ctx.run`, `ctx.runAll`, `ctx.each` and `ctx.uncancellable` all throw
a `StateError` that names the call: `cannot run a child inside unattended work`
for `ctx.run`. That throw is an error of the work it happened in, so it takes
the way above, to the hooks. The job itself still ends `Done`.

A captured context still belongs to the original job. `emit` works while that
job is active and is rejected after a cancellation or after the job completes.
The background work does not extend the life of the context.
