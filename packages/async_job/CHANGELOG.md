## Unreleased

Moving from `0.2.0`: read "Breaking changes" for what stops compiling or
behaves differently, and "Changes you will see on upgrade" for the errors that
now reach the zone, and fail a test there.

### Breaking changes

- **`ctx.wait` is renamed to `ctx.abandonable`.** The behaviour and the
  parameters are the same: a cancellation arriving during the call throws
  `Cancelled` at once and lets go of the action, which runs on. The old name
  said nothing of that: `Future.wait` and `.wait` on a list or a record wait to
  the end, and letting go of the action is what sets this call apart from
  `ctx.join`. The new name pairs with `ctx.uncancellable`, and both say what a
  cancellation does to the action. `wait` stays on `JobContext` and
  `JobContextBase` as a deprecated alias until the next breaking release: it
  does what `abandonable` does, and only the `StateError` of a call on a job
  that has finished still says `cannot wait`; the new name says
  `cannot run an abandonable action`. **Migrating.** Replace `ctx.wait` with
  `ctx.abandonable`. Code that keeps the old name compiles and runs as before,
  and the analyzer marks every call with a `deprecated_member_use` info, so
  analysis that treats infos as fatal — `flutter analyze` by default,
  `dart analyze --fatal-infos` — fails until the calls are replaced. A class
  that implements `JobContext` by hand, a test fake for one, implements
  `abandonable` as well; an engine that extends `JobContextBase` gets both.

- **`Job.ignore()` is renamed to `Job.ignoreFailure()`.** The behaviour is the
  same: the call marks the outcome observed, and a failure of the job that
  nobody reads stays out of the zone. The old name was the name of
  `Future.ignore()`, and the two stood side by side on one line —
  `child.ignore()` and `ctx.run(child).ignore()` — while doing different
  things: the first is about the report of the job's failure, the second about
  the error of one future. There is no deprecated alias: the old name is gone.
  **Migrating.** Replace `ignore()` with `ignoreFailure()` where the receiver
  is a `Job`; the analyzer names every such call with `undefined_method`.
  `ignore()` on a future — of `ctx.run`, of `cancel()`, of `value` or `done` —
  is `Future.ignore()` and stays as it is.

- **`JobObserver.onError` is a notice, and the new `JobAnswerer` answers for an
  error no outcome carries.** Such an error — a late failure of an action
  `ctx.abandonable` walked away from, a disposer, a callback of `ctx.onCancel`
  or `job.whenCancelled`, work handed to `ctx.unattended` — used to stop at
  whatever observer the job had, so an observer written for a log, overriding
  `onFinish` alone, kept every one of them out of the zone without a word. Now
  `onError` hears it, and an observer that mixes in `JobAnswerer` answers for
  it in `onUnanswered`; without one the error goes to the zone the job was
  created in, where it goes without an observer too, and a cancellation is
  dropped. The default body of `onUnanswered` does the same. `JobAnswerer` is a
  mixin on `JobObserver`, and `JobObserver` is a mixin class now: a class that
  extends another one mixes it in with `with JobObserver`, or
  `with JobObserver, JobAnswerer`, and keeps the default bodies. **Migrating.**
  An observer from `0.2.0` compiles unchanged, and the errors it used to
  swallow reach the zone; one that mixes in `JobAnswerer` and overrides
  `onUnanswered` with an empty body keeps the old behaviour. An `onUnanswered`
  written on an observer without `JobAnswerer` is never called: the analyzer
  says so where it carries `@override`, and nowhere else. An engine built on
  the core answers for these errors through the observer it puts on its jobs,
  the way `solo` does. See
  [Answering for errors](doc/observing.md#answering-for-errors).

- **`JobBase`, `JobContextBase` and `JobStatus` moved to
  `package:async_job/engine.dart`.** They are the protocol for building an
  engine on the core, and the main import handed them to every file that merely
  runs a job — and, through `solo` and `flutter_solo`, to every file of an app.
  **Migrating.** `engine.dart` exports the rest of the package as well, so an
  engine swaps one import for the other:
  `import 'package:async_job/engine.dart';` in place of `async_job.dart`. Code
  that only runs jobs is untouched but for the debug switch: `JobBase.debug` is
  `Job.debug` now, so the channel stays in the main import, and an app on
  `solo` sets it next to `Solo.debug`. See
  [Building on the core](doc/extending.md).

- **`JobContextBase.check` is marked `@mustCallSuper`.** The checkpoint is
  where the cancellation of the job is asked: while the body runs,
  `ctx.abandonable`, `ctx.join` and `ctx.uncancellable` ask it before the
  action, `ctx.join` again after it, `ctx.run` once the child's value has
  arrived and `ctx.runAll` before it hands the values back. An engine that
  overrode it for a rule of its own without calling `super` stopped asking:
  `ctx.join` handed a value to a job already cancelled, and `ctx.uncancellable`
  began its step on one. The analyzer now warns about such an override, and
  `dart analyze` fails on the warning. **Migrating.** Call `super.check()`
  first; a rule that no longer holds throws a `Cancelled` with a reason of the
  engine's own. See [A rule of your own](doc/extending.md#a-rule-of-your-own).

- **`JobBase.finish` and `JobContextBase.startChild` are marked
  `@mustCallSuper`, and the hooks an engine overrides are marked
  `@visibleForOverriding`:** `started`, `finished`, `adoptedBy`,
  `createContext`, `execute`, `createEachJob` and `beforeChildStart`. An
  override of `startChild` without `super` left `ctx.run` waiting for a child
  nobody started, and one of `finish` left the job without an outcome. The
  analyzer now warns about such an override and about a hook called other than
  through `super`, and `dart analyze` fails on the warning. **Migrating.** Call
  `super` in both overrides, and call a hook only from its own override.

- **`JobBase.cascadeToChildren` and the `JobBase.level` setter are no longer
  part of the protected surface.** Neither had a use outside the core: the
  cascade runs inside `cancelWith`, after the job is marked, and the level is
  set by `startChild` when a child is adopted. An engine that ran the cascade
  itself cancelled the children of a job it had not marked, and one that set
  the level changed what the public `isChild` answers. **Migrating.** Cancel a
  job through `cancelWith` or `cancelOwnJob`, and adopt a child through
  `startChild`; the `level` getter stays.

- **The core announces a `Failed` an engine hands to `finish`.** An engine that
  ended a job by hand with a failure its body never threw — a rule of its own
  that threw, say — left `onError` silent unless it told the observer itself,
  and a child that `beforeChildStart` or its own context turned away with a
  throw ended `Failed` with no `onError` at all. Now `finish` tells the
  observer of every `Failed` it ends a job with, once, before `finished()` and
  `onFinish`; the error of a turned-away child still goes to the parent's body
  as well. A `Failed` handed to a job that is already over used to vanish:
  `finish` did nothing. The outcome still stays, and the error goes to
  `onError` and `onUnanswered` — by default the zone — as any error with no
  outcome does; `ignoreFailure` keeps it to `onError`. One error object is
  announced once, however many routes bring it: a body that throws what the
  engine has already ended the job with is not heard twice. **Migrating.** An
  engine that called `notifyObserver` before `finish` drops that call, or the
  observer hears the error twice; `solo` has dropped its own. The call is safe
  to drop on a job that may be over as well: `finish` announces there too.

- **`ctx.run` takes `dispose` and `discard`,** the way `ctx.abandonable` does,
  and makes the registration the moment the child's value comes back. `run`
  checks the parent once the value is in hand — for its own cancellation, and
  for the rules of an engine — and a checkpoint that throws there takes the
  value with it: the child ended `Done`, so its own conditional registration
  went with the value, and the line that would have made the next one is never
  reached. New named parameters on a member of an `abstract interface class`,
  so an implementation of `JobContext` written by hand no longer compiles;
  `JobContextBase` gets them once and every engine built on it, `solo`
  included, gets them for nothing. **Migrating.** Nothing breaks at a call
  site: `ctx.run(child)` is unchanged, and
  `ctx.abandonable(() => ctx.run(child), discard: ...)` still closes what it
  took on every path it ever did. It does not close this one, and it never
  could: at this checkpoint `run` throws instead of returning the value its
  registration is made against. That wrapper and a registration written on the
  line after `await ctx.run(child)` are both the ones to move into the call. A
  subclass of `JobContextBase` that overrides `run` takes `dispose` and
  `discard` and passes them to `super.run`. See
  [Registering on arrival](doc/cleanup.md#registering-on-arrival).

- **`JobContext` gains `runAll`,** which runs children side by side and asks
  the rest to stop as soon as one of them goes wrong, a branch that throws
  before its first `await` included. It brings a fifth built-in reason,
  `SiblingCancelReason`, which is what the group gives the branches it asks to
  stop; its `cause` is what went wrong. The contract of `discard` is untouched:
  it still runs only when the job ends without handing its value over, and in a
  branch of a group the group is what says whether it did. A branch must not
  wait for what another branch releases in its cleanup: a branch unwinds only
  once every branch has ended its body or one of them has ended in anything but
  a value, so a lock two branches share through `dispose` can hang the group.
  New on an `abstract interface class`, so an implementation of `JobContext`
  written by hand no longer compiles; `JobContextBase` gets it once and every
  engine built on it, `solo` included, gets it for nothing. A failure of a
  branch that the group did not throw goes to `onError` and `onUnanswered` of
  the branch. **Migrating.** The member shadows an extension named `runAll` on
  `JobContext` without a warning: a call that fits the member's signature
  reaches the group, with its sibling stop, and one that does not stops
  compiling with an error about the member. Rename the extension. A subclass of
  `JobContextBase` with a `runAll` of its own either stops compiling or
  overrides the group. See
  [When one failure makes the rest pointless](doc/children.md#when-one-failure-makes-the-rest-pointless).

- **A cancellation that travels inside a `ParallelWaitError` is a cancellation
  again.** `[...].wait` wraps every branch error in that envelope, and the core
  read a caught error by type, so a child cancelled under
  `[ctx.run(a), ctx.run(b)].wait` ended the parent `Failed`, where the same
  code written as `await ctx.run(child)` ends it `Cancelled`. An envelope
  carrying cancellations and successful branches now decides the outcome the
  way the cancellation it carries would, with the stack trace of that branch;
  the children the body started but did not put under `[...].wait` are
  cancelled too, and an unobserved outcome no longer sends the envelope to the
  zone. An envelope carrying a real failure is untouched: the outcome stays
  `Failed` with the same object, its `errors` and `values` intact, because a
  failure must not hide behind a cancellation. What changes for a caller:
  `job.value` throws the `Cancelled` instead of the envelope, a
  `catch (ParallelWaitError)` around it no longer runs, `whenCancelled` fires,
  and in `solo` the job's `onCancel` hook takes the outcome where `onError`
  used to. **Migrating.** A resource opened in a successful branch and closed
  from that outer `catch` should be taken through
  `ctx.abandonable(() => open(), dispose: (value) => value.close())`: the core
  then closes it whatever the outcome, and nothing is needed at the call site.
  For a branch that cannot go through `ctx.abandonable`, catch the envelope
  inside the body, where it still arrives as it did. An envelope built by hand
  is read by the same rule — it cannot be told apart from the one the language
  builds — so code that deliberately throws an aggregate with a cancellation
  inside should wrap it in an error of its own. `Future.wait` is unchanged and
  cannot be changed: it reports the first error to reach it and discards the
  rest before anything else can see them. See
  [Registered on arrival, waited for in one envelope](doc/children.md#registered-on-arrival-waited-for-in-one-envelope).

- **A body that gives itself up is cancelled the way a cancelled job is.** A
  body that throws `Cancelled`, or lets out the cancellation of a child,
  accepted the cancellation as it threw, but its `ctx.onCancel` callbacks never
  ran, and `whenCancelled` fired only once its children had ended, right before
  the cleanup. Now the throw goes the way of a cancellation from outside, as
  the body ends: the children are asked to stop, then the `ctx.onCancel`
  callbacks run and `whenCancelled` fires. A token or a connection handed to
  `ctx.onCancel` is closed when the body gives up, and a listener that times a
  cancellation counts the children in. A `ctx.uncancellable` section the body
  walked away from does not hold this cancellation: `ctx.abandonable` inside it
  throws. **Migrating.** A callback that must not run when the body gives
  itself up is unregistered before the throw, with the function `ctx.onCancel`
  returns. See [Cancellation](doc/cancellation.md).

- **`JobBase` gains the protected `inUncancellableSection` and `heldCancel`,**
  for an engine that waits for a job and wants to say why. The first says a
  section of `ctx.uncancellable` is open; the second is the cancellation such a
  section holds back, which the job does not accept until the section closes
  and so shows nowhere else. An open section alone does not mean anybody asked.
  Adding a member to a class meant to be extended is breaking on its own: a
  subclass with a member of that name stops compiling.

- **`JobContext` gains `pause`.** A context built on `JobContextBase` gets the
  member with it. A class that implements `JobContext` by hand — a fake in a
  test — stops compiling until it has one. **Migrating.** Add
  `Future<void> pause([Duration duration = Duration.zero])` to the fake; one
  that only has to let the body go on returns `Future<void>.value()`.

### Changes you will see on upgrade

Errors that `0.2.0` lost, or told only to the observer, now reach the zone the
job was created in. In a test that zone is the test's, and the test fails:

- the failure of a body when a cancellation reaches the job afterwards, while
  the job waits for children of its own or runs its cleanup. Whoever reads the
  outcome gets the cancellation. In `0.2.0` reading it kept the failure out of
  the zone, and the failure of a child still cleaning up on its way out of
  `ctx.run` reached no zone at all. Reading the outcome no longer keeps the
  failure out;
- the failure of a step of `ctx.uncancellable` while the section held a
  cancellation back, the same way;
- the late failure of an action `ctx.abandonable` walked away from, through
  `.timeout` or `Future.any`, arriving once the job is over: `0.2.0` told
  nobody at all;
- an error no outcome carries, of a job that has an observer: `0.2.0` stopped
  it there, see the first of the breaking changes;
- the failure of a source's own cleanup, the future of the subscription's
  `cancel()`, when `ctx.each` lets go of a stream: `0.2.0` dropped it. It
  reaches `onError` and `onUnanswered` of the `each` child.

To keep such an error out of the zone, find which of the two it is. A failure
of the job's own body or step that a cancellation covered, and the failure of a
branch of `ctx.runAll` that the group did not throw, are silenced by
`job.ignoreFailure()` on that job, called before the job ends — or at the
latest from `onFinish` or a callback of `whenCancelled` registered before it
ends; on a child of `ctx.run` as well. `onError` still hears it. The rest
belongs to no outcome, and `ignoreFailure` does not reach it: an observer that
mixes in `JobAnswerer` and overrides `onUnanswered` answers for it in place of
the zone. See [Where errors go](doc/observing.md#where-errors-go).

One report is gone: a job that gives up inside a call it walked away from — a
helper that takes the context and calls `ctx.check()` after `ctx.abandonable`
let go of it — no longer reaches `onError` as a failure. `onError` promises
never to report the job giving up.

A test that matches error messages by text needs the new wording. A job
cleaning up after its body says `is cleaning up after its body` where it said
`is disposing`; `ctx.runAll` and `ctx.each` refused after the body has ended or
from `ctx.unattended` name their own call, `cannot run a group of children` and
`cannot follow a stream`; a continuation refused as a child says
`is a continuation, which starts itself once its source finishes` where it said
`A continuation starts itself after its source finishes`; a refused handle is
named as `Job(key)`, not by its class.

### Added

- **`started` of `Cancelled.by` is optional and defaults to `true`.** A body
  that throws `Cancelled.by(reason: reason)` ends with `started: true` whatever
  it passes, so the argument said nothing there; an engine that drops a job
  before its body runs still passes `started: false`. Calls that pass
  `started: true` keep compiling, and `avoid_redundant_argument_values` names
  them.

- **`timeout` gives a job a deadline of its own.** `Job(...)` and
  `Job.deferred(...)` take it, and so does the constructor of `JobBase`, for an
  engine to pass on. The deadline is counted from the start of the body, not
  from the creation or a queue, and bounds the body and the children the job
  waits for after it, not the cleanup stack. When it runs out, the job is
  cancelled with the new `TimeoutCancelReason` and ends `Cancelled(timeout)`: a
  cancellation like that of `cancel()`, which a section of `ctx.uncancellable`
  holds, and drops with the timer when the body and the children are over
  first, and which a job cancelled already turns away, and not the
  `TimeoutException` of `Future.timeout`. The core cancels the timer however
  the job ends, observing nothing; `Timer(limit, job.cancel)` lived until the
  limit, and cancelling it at the end took `job.done`, which observes the
  outcome. A step of a body gets a deadline as a child:
  `await ctx.run(Job.deferred(step, key: 'step', timeout: limit))`. A deadline
  that is zero or negative, or that comes with `cancellable: false`, throws
  `ArgumentError`. `Job.each` and `then` take none. See
  [A deadline](doc/cancellation.md#a-deadline).

- **`Job.each` makes a root job that follows a stream.** A job whose whole work
  was a stream used to take two: a root, and inside it the child of `ctx.each`.
  `Job.each(stream, (ctx, event) { ... })` is that job alone, with `key`,
  `describe`, `cancellable` and `observer` as `Job(...)` has them. It starts
  inside the call rather than on the next microtask, so the subscription is
  there when the call returns and an event a broadcast stream sends right
  afterwards is not lost; `onStart` is heard before the caller has the handle.
  It is a root wherever it is made, and `ctx.run` refuses it: a body follows a
  stream with `ctx.each`. See
  [A job that only follows a stream](doc/streams.md#a-job-that-only-follows-a-stream).

- **`ctx.pause(duration)` is a delay a cancellation ends.** A body that awaits
  a bare `Future.delayed` sits the whole delay out before it notices a
  cancellation. Under `ctx.abandonable` the body leaves at once, but a
  `Future.delayed` cannot be cancelled, and its timer runs to the end with
  nothing waiting for it. `ctx.pause` throws `Cancelled` the moment the job
  accepts a cancellation and cancels its timer; without a duration it comes
  back on the next turn of the event loop. See
  [Letting time pass](doc/cancellation.md#letting-time-pass).

- **`JobObserver.all` makes one observer of several.** Every hook goes to each
  of them in the order of the list, each call on its own, and the one among
  them that is a `JobAnswerer` answers for all of them; with none, an error no
  outcome carries goes to the zone. Two that answer, or the same observer
  twice, throw `ArgumentError`. A class that hands the hooks on to a list by
  hand is no `JobAnswerer`, and the answer of one in its list is never asked.
  `JobObserver` declares its unnamed constructor, so a class that extends it
  compiles as before. See
  [Several observers](doc/observing.md#several-observers).

- **`Job.visitErrors` hands each failure and each cancellation inside an error
  to a callback of its own.** A `ParallelWaitError` that `[a, b].wait` throws
  holds several errors, other such errors too. A check for `error is Cancelled`
  lets a cancellation inside it through, and a report of the whole error names
  none of its failures. `Job.visitErrors(error, stackTrace, onFailure: report)`
  reports each failure and drops each uncaught `Cancelled`. It calls
  `onFailure` not at all exactly when a job drops the error as a cancellation:
  the job decides by the same walk. See
  [Each failure on its own](doc/observing.md#each-failure-on-its-own).

- The debug channel names a job that handed its value over and dropped the
  conditional registrations that went with it:
  `Job(opener) handed its value over: 1 conditional cleanup dropped`. A
  registration made by `discard` or `onDiscard` is settled by the outcome of
  the job that made it and travels with no value, so a receiver that keeps the
  resource has to register it again; forgetting that leaks nothing visible
  until the receiver ends badly. The line names every hand-over, a branch of
  `ctx.runAll` included. See
  [Registering on arrival](doc/cleanup.md#registering-on-arrival).

### Fixed

- A `ParallelWaitError` whose list of errors throws when its length is read is
  a failure like any other. A body that threw it ends `Failed` with it, and
  from `onStart`, `onLog` or work handed to `unattended` it reaches the zone.
  The length was read on every step, outside the guard around the rest of the
  list. A job whose body or `onStart` threw it never finished, one whose
  `onLog` threw it ended `Failed` with the error of the length, and from
  `unattended` the zone got the error of the length instead.
- A `whenCancelled` registered from `onFinish` of a job cancelled before its
  start runs. It was dropped: the job was finished, and its cancellation had
  not reached the listeners yet.
- A cancellation a job cannot refuse, one an engine makes for the rules of its
  domain, drops the cancellation an `uncancellable` section holds, and
  `heldCancel` stops naming it. The job accepted the rule over the held one all
  along, but `heldCancel` kept naming a cancellation that would never land
  until the section closed, and the dartdoc of `cancel` promised that nothing
  replaces a held one. The same goes for a section the body walked away from:
  once the body gives itself up or the job ends, `heldCancel` is `null`.
- A job made by `Job(...)` inside `ctx.unattended`, and a continuation `then`
  made there, runs its body in the zone the work was started from. It ran in
  the zone of the work, and a bare `unawaited` error in it reached the observer
  of the job that started the work. A job started by hand inside the work, a
  `Job.deferred` whose `start` is called there or a job of an engine that
  starts it synchronously, now starts in that zone too, wherever it was made:
  its body, the engine's `started` and the observer's `onStart` run there, past
  any zone the work forked on the way, as for a job made in there. Anywhere
  else a job started by hand starts where `start` is called, as before.
- A `Cancelled` a hook of the observer throws no longer reaches the zone: a
  lazy log message that asks a cancelled job, for one.
- A job an engine ends while `createContext` builds its context keeps that
  outcome. Its body ran anyway, and the job ended twice, with
  `Future already completed` in the zone.
- `ctx.run`, `ctx.runAll` and `ctx.each` refuse, with an `ArgumentError` as
  they promise, a class that implements `JobBase` instead of extending it. It
  threw `NoSuchMethodError`.
- `ctx.runAll` makes every check of the core for every handle before it starts
  any, so a handle the core refuses at the end of the list no longer leaves the
  branches before it running; a refusal of an engine still comes at the
  adoption. Under a parent that is already cancelled, or one a branch cancels
  while the list starts, it turns away every branch not yet started, not the
  next one alone; the rest stayed unstarted for good.
- A `ctx.runAll` the body walked away from no longer throws the parent's
  cancellation into the zone once the branches end. It hands the values over,
  as `ctx.run` does.
- A value that comes to `ctx.abandonable` after the cancellation has already
  ended is released as soon as it arrives, and the job still ends only after
  that release. It was held for the unwinding of the cleanup stack, after the
  children, so a child that kept waiting for the same lock or slot of a pool
  through the cancellation, inside `ctx.uncancellable` for one, waited for it
  for good, and the job or the branch of `ctx.runAll` never ended. A branch
  waiting for its group between the two passes over its cleanup stack releases
  it at once too, so a cleanup of a sibling that wants the same slot no longer
  holds the group for good. A value arriving while the job runs its cleanup
  stack still joins the stack, and a value of a call the body walked away from
  without a cancellation still waits for the unwinding: whoever holds its
  future gets it.
- An error thrown by `JobBase.started` goes to `onError` and `onUnanswered`,
  and the body runs. It left the job running with no body, forever.
- A child leaves its parent's waiting list by identity. With children equal by
  `==`, as in an engine that compares jobs by key, the one that ended stayed on
  the list and a live sibling was dropped from it: the parent waited for a job
  that was over and finished while the sibling still ran.
- Two jobs equal by `==` are no longer taken for one another inside work handed
  to `ctx.unattended`: the inner one, started from inside the other's work,
  refused `uncancellable` and `each` with "cannot ... inside unattended work".
- A body that gives itself up with `throw Cancelled(...)` has accepted that
  cancellation there and then. Until the job had waited for its children it
  answered `isCancelled` with `false`, `ctx.check()` let work through, and a
  `cancel()` arriving in between put its own reason over the one the body
  chose. Now the body's reason stays, and `Job.cancel` on such a job returns
  when the job finishes.
- A `whenCancelled` registered while the cancellation is still reaching the
  children runs after the ones registered earlier, instead of ahead of them.
- A finished job lets go of its body and of its parent. A kept handle held
  everything the body captured — a controller, a connection, a buffer — and a
  child handle held the chain it came out of. What an outcome carries is
  untouched.
- `ctx.run` refuses a continuation, the job `then` returns, with the same
  `ArgumentError` whenever it is called. Once the source had finished it threw
  `StateError: Job(then) is already running`, which did not say that a
  continuation is never a child.
- `ctx.join` releases the value through `dispose` or `discard` when the
  checkpoint after the action throws anything, not only a `Cancelled`: a rule
  of an engine that threw there cost the job the resource it already held.
- `ctx.join` and `ctx.abandonable` called from work handed to `ctx.unattended`
  no longer hand that work a resource they have already closed. A value that
  came back after the body had ended reached the work after `dispose` or
  `discard` had run. The work now gets it on the body's terms: registered as
  the call asked, released with the cancellation thrown on a job that accepted
  one, and released with a `StateError` thrown on a job that is over when there
  is a `dispose` or `discard` to run.
- A value that comes back after the body has ended no longer completes the same
  wait twice: a cancellation arriving at that moment made the core throw
  `Future already completed` and report it to `onError` as an error of the job.
- A job that has accepted a cancellation no longer ends with a value. The
  protected `finish`, which an engine uses to end a job by hand, took whatever
  it was handed: after `cancel()`, `finish(Done(42))` left `isCancelled` true
  and `outcome` a `Done(42)`. A `Done` or `Failed` handed in after the job
  accepted a cancellation now ends it `Cancelled`, and a failure so replaced
  goes where a failure a cancellation covered goes. A `Cancelled` handed in
  still stands.
- A value arriving for a job an engine ended by hand is released instead of
  leaking, and the body hears a `StateError` about the job.
- A cancellation that runs out of stack in a deep tree runs the `onCancel`
  callbacks of the jobs it reached as it unwinds; it used to run none of them.
  The siblings of the child that overflowed are not skipped, and the error
  still reaches whoever cancelled. What lies below the break is still left
  running. How deep a tree may go is in [Children](doc/children.md#children).

- A call of `ctx.abandonable` the body did not await no longer sends the job's
  cancellation to the zone when the job accepts it after the body has ended:
  cancelled while it waits for a child, say. The table of where errors go held
  `abandonable` to the zone only until the body ends, and a late error of the
  same call already went the way of an abandoned action.

### Documentation

- The README is a starting page: what a job is, why a plain `Future` does not
  cover it, `Install`, `Quick start` and a map of the guides. The reference
  moved to seven pages: [Outcomes](doc/outcomes.md),
  [Cancellation](doc/cancellation.md),
  [Children, streams and chains](doc/children.md), [Streams](doc/streams.md),
  [Cleanup](doc/cleanup.md), [Observing and testing](doc/observing.md) and
  [Building on the core](doc/extending.md). Where there is a trap, a section
  opens with the version the vocabulary of the API leads to and shows what it
  does, then the one that holds. One recommendation of the `0.2.0` README is
  replaced: `on Cancelled { rethrow; }` in front of the `catch` logs an
  operation stopped by its token as a failure, because `ctx.join` throws the
  action's own error. [Asking the job](doc/cancellation.md#asking-the-job)
  calls `ctx.check()` in the `catch` instead. The pages also cover what that
  README did not: the failures a cancellation covered, in a table of where each
  error goes, and that a parent waits for its children and not for the
  continuations hanging off them.
- The API reference says where to start and where the guides are. The example
  of `Job.ignore` gives its job an observer, as the text above it asks.
  `ctx.onCancel` promises the order its callbacks run in, `ctx.log` says which
  message costs nothing without an observer, `ctx.disown` covers what `ctx.run`
  registers, and `run`, `runAll`, `each` and the engine protocol name what they
  throw. `Job.isChild` names every way a job is adopted, `Job.deferred` says
  what cancelling it before its start does, and the summaries in the reference
  no longer speak the vocabulary of `solo`. `addCancelCallback` says what an
  error of its callback does.

## 0.2.0

- **Breaking:** `ctx.run(child)` returns `Future<T>` instead of the child's
  handle. Use `await ctx.run(child)` to await its value, children and cleanup;
  successful completion checks the parent's cancellation before continuing.
  Keep the original `child` for cancellation or outcome inspection. Handle the
  returned future's errors, or use `.ignore()` for an intentional concurrent
  start whose result is unused. Start validation still throws synchronously.
  `ctx.each` continues to return its child handle immediately.
- Add protected `JobContextBase.startChild` for domain adoption and start
  checks shared by `run` and `each`, without observing the child's result.

- Add `Job.then` with a separate context per continuation, forward outcome
  propagation and cancellation in both directions. Cancelling the tail waits
  for unfinished predecessors and their cleanup. `ChainCancelReason` retains
  each adjacent cancellation in `cause`. Continuations are core root jobs with
  their own optional observer, independent of domain queues.

- **Breaking:** `ctx.each(stream, (child, event) { ... })` returns a child
  `Job<void>` immediately. Await `.value` for a throwing result, inspect
  `.done` for the outcome, or call `.cancel()` to stop it separately. The
  callback receives the child's context. The parent waits for the child even
  when its body does not await it, and observers see the child.
- Cancelling `each` immediately removes the subscription and stops event
  delivery, then waits for the running callback before child completion and
  cleanup. Use child context checkpoints to respond to cancellation; a plain
  `await` cannot be interrupted. Source cleanup from subscription cancellation
  is still not awaited.
- **Breaking:** `each` is a `JobContext` method; the `JobStream` extension is
  removed. `JobContextBase.createEachJob` is a protected factory for domain
  engines. As with `run`, `each` is rejected from `unattended` and after the
  parent body ends.
- **Breaking:** reasons are extensible classes: `ManualCancelReason`,
  `ParentCancelReason` and `HandlerCancelReason`. Replace named constants with
  constructors and inspect types instead of comparing names. `CancelReason` is
  abstract; subclasses can carry arbitrary data.
- `job.cancel(reason: reason)` accepts a custom reason, preserved by identity
  in callbacks and outcomes. A body throwing `Cancelled.by` now preserves its
  explicit reason as well.
- Parent cancellation and a child's cancellation escaping the body retain the
  source `Cancelled` in `ParentCancelReason.cause` and
  `HandlerCancelReason.cause` respectively.
- **Breaking:** replace the `Job.whenCancelled` future with
  `job.whenCancelled((cancelled) { ... })`. The callback receives the full
  `Cancelled` and runs synchronously; registering after cancellation calls it
  immediately. The returned function unregisters the callback.
- Release unused cancellation listeners when a job finishes without
  cancellation. Registration does not observe a failed outcome.
- Route synchronous listener errors through `onError`, or the creation zone
  without an observer, as for `ctx.onCancel`. Async callbacks are not awaited.

## 0.1.0

Initial release. The job kernel taken out of `solo` before its own first
release.

- `Job<T>`: a cancellable `Future` with an outcome, children and a cooperative
  cancellation. Created by `Job(body)`, which starts on the next microtask, or
  by `Job.deferred(body)`, which waits for `start()`.
- `Outcome<T>`: `Done`, `Failed`, `Cancelled` with an open `CancelReason` and a
  public `Cancelled.by` for engines built on this one.
- A waiting family that says what a cancellation does to a call: `ctx.wait`
  ends the waiting and not the work, `ctx.join` waits for all of the action and
  gives up afterwards, `ctx.uncancellable` holds the cancellation until the
  step is over, `ctx.unattended` does not wait at all and hands the work to the
  engine, `ctx.onCancel` hands the cancellation to whatever can really stop,
  and `ctx.check` gives up where there is no call to wrap. `ctx.each` follows a
  stream for as long as the job lives, waiting for an asynchronous `onData` and
  taking the subscription with it whatever the outcome.
- A cleanup stack: `ctx.onDispose` releases whatever the outcome,
  `ctx.onDiscard` only when the value reaches nobody, and `wait` and `join`
  take the same two as `dispose` and `discard` for the value they hand over.
  The engine unwinds the stack after the children and before the outcome,
  waiting for every disposer; `ctx.disown(value)` takes a registration back
  when the body hands the value over itself.
- Children through `ctx.run`: the parent finishes after them, a cancellation
  cascades, and a child that is not cancellable refuses it.
- `JobObserver` with `onStart`, `onFinish`, `onError` and `onLog`; a child
  inherits the parent's. A `Failed` outcome nobody observed goes to the zone
  that created the job, and so does an error with nowhere else to go when there
  is no observer — but never a `Cancelled`: a cancellation is a decision
  somebody made, not a failure, and the observer is the only place it is heard.
- `ctx.unattended(action)` for work the body starts and does not wait for: it
  runs in an error zone of its own, and whatever it leaves uncaught — now, or
  long after the job is over — reaches `onError` instead of the process.
  `ctx.run` and `ctx.uncancellable` are refused from inside it, and a job
  created in there reports to the zone the body runs in, not to the observer of
  the job that started the work.
- `JobBase<T>` and `JobContextBase` for an engine of a domain to subclass: the
  protected surface, the virtual checkpoint `check()`, and the hooks
  `started()`, `finished()` and `adoptedBy()`. The protected surface also
  carries `reportToZone`, for a domain whose own route for an error with
  nowhere to go ends with nobody — it keeps a `Cancelled` out of the zone
  exactly as the core does, so a domain does not write that rule again — and
  `throwIfUnattended`, for a member of its context that must not be called from
  unattended work.
