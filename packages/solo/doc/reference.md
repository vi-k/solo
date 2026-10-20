# Reference

Every member of `Solo`, of the context its jobs get, of the jobs it returns, of
its queue and of its accumulators, and every parameter of the methods that make
jobs, in one line each, with the section that explains it. What `solo` takes
from the core is listed where it is explained: the rest of `ctx` in
[The context at a glance](https://github.com/vi-k/solo/blob/main/packages/async_job/README.md#the-context-at-a-glance)
of the `async_job` README, and `value`, `done` or `cancel()` of a job in
[Jobs and results](jobs.md#jobs-and-results) on the jobs page.

## Solo

`Solo<S>` is the base class of a controller. Its members fall into four groups
by who uses them: the whole process, a caller, the subclass, and an override in
the subclass.

### Set once for the process

| Member | What it does | Where |
| --- | --- | --- |
| `Solo.observer` | One observer of every controller of the process; it watches and answers for nothing | [Watching every controller](diagnostics.md#watching-every-controller) |
| `Solo.unansweredHandler` | A `SoloUnansweredHandler` that takes the errors nobody answered for, in place of the zone | [Answering for an error](errors.md#answering-for-an-error) |
| `Solo.debug` | A callback that traces the queue, the state and the closing of every controller; the life of each job is on `Job.debug` | [Logs](diagnostics.md#logs) |

### What a caller sees

| Member | What it does | Where |
| --- | --- | --- |
| `currentState` | The state, for a reader outside a job; no checkpoint | [Observing state](state.md#observing-state) |
| `addListener(listener)` | Calls back synchronously inside every change of the state | [Observing state](state.md#observing-state) |
| `removeListener(listener)` | Removes the earliest registration equal to the listener | [Observing state](state.md#observing-state) |
| `isClosed` | Whether `close()` was called | [Three ways to stop](cancellation.md#three-ways-to-stop) |
| `isDraining` | Whether a `close()` that drains is still running the queue | [Three ways to stop](cancellation.md#three-ways-to-stop) |
| `isFinished` | Whether closing has finished and the state can no longer change | [externalSetState](state.md#externalsetstate) |
| `pending` | What is holding the controller right now, or `null` | [What is holding the controller](diagnostics.md#what-is-holding-the-controller) |
| `cancelAll()` | Clears the queue and cancels the running job; the controller stays open | [Three ways to stop](cancellation.md#three-ways-to-stop) |
| `close()` | Stops taking work and closes: cancels what is queued and running, or with `mode: SoloCloseMode.drain` runs the queue first | [Three ways to stop](cancellation.md#three-ways-to-stop) |

### What the subclass uses

A controller builds its own constructor and methods from these, and a caller
sees those. Every member here is protected.

| Member | What it does | Where |
| --- | --- | --- |
| `Solo(initialState)` | The constructor a subclass calls as `super(initialState)`, with the first state | [Quick start](https://github.com/vi-k/solo/blob/main/packages/solo/README.md#quick-start) |
| `run(body)` | Makes a job and queues it: what a method of the controller usually returns | [Creating and scheduling jobs](jobs.md#creating-and-scheduling-jobs) |
| `job(body)` | Makes a job without queueing it, for `add` or for `ctx.run` as a child | [Creating and scheduling jobs](jobs.md#creating-and-scheduling-jobs) |
| `add(job)` | Queues a job made by `job` under a `Policy`, at the tail or, with `first: true`, at the head | [Queue and policies](jobs.md#queue-and-policies) |
| `collect(handler)` | Makes an accumulator that hands one job the list of the events of its group | [One request per log line](accumulation.md#one-request-per-log-line) |
| `accumulate(handler, merge: ...)` | Makes an accumulator that merges the events of a group into one value | [Settings saved on every flip of a switch](accumulation.md#settings-saved-on-every-flip-of-a-switch) |
| `queue` | The jobs waiting to run, a `SoloQueue` | [Working the queue directly](jobs.md#working-the-queue-directly) |
| `lastJobWhere(test)` | The last queued job that passes the test, else the running one if it passes and has not been cancelled, else `null` | [Working the queue directly](jobs.md#working-the-queue-directly) |
| `current` | The running root job, or `null` when the controller is idle | [Working the queue directly](jobs.md#working-the-queue-directly) |
| `hasListeners` | Whether any listener is registered | [Observing state](state.md#observing-state) |
| `externalSetState(state)` | Reflects a state an outside source has already changed | [externalSetState](state.md#externalsetstate) |

### What the subclass overrides

The engine calls these. The hooks do nothing by default, except the two that
hand an error on, and `publish` delivers the state: an override calls
`super.publish` first.

| Member | What it does | Where |
| --- | --- | --- |
| `onStart(job)` | A job body is about to run | [Watching every controller](diagnostics.md#watching-every-controller) |
| `onFinish(job)` | A job has an outcome, a job dropped before its start included | [Watching every controller](diagnostics.md#watching-every-controller) |
| `onError(job, error, stackTrace)` | Hears every error a job runs into; it reports and moves nothing | [Reporting an error](errors.md#reporting-an-error) |
| `onUnanswered(job, error, stackTrace)` | Answers for an error no outcome carries and a `Failed` nobody observes; by default hands it to `Solo.unansweredHandler` or the zone | [Answering for an error](errors.md#answering-for-an-error) |
| `onLog(job, message)` | A job called `ctx.log` | [Logs](diagnostics.md#logs) |
| `onChange(transition)` | The state changed; the `SoloTransition` says which job changed it | [Watching every controller](diagnostics.md#watching-every-controller) |
| `onClose()` | The engine is about to finish closing: the place to release what the controller holds beside its jobs | [externalSetState](state.md#externalsetstate) |
| `onListenerError(error, stackTrace)` | A listener threw; by default the error goes to the zone | [Observing state](state.md#observing-state) |
| `publish(previous, current)` | Calls the listeners; the seam for a delivery of another kind | [A delivery of your own](state.md#a-delivery-of-your-own) |

## Parameters of a job

`run`, `job`, `collect` and `accumulate` take the body first — for an
accumulator, a handler that also gets the events of its group — and these named
parameters after it. The first type argument of each is the working type, in
[State and rules](state.md#state-and-rules) on the state page.

| Parameter | Taken by | What it does | Where |
| --- | --- | --- | --- |
| `key` | `run`, `job`, `collect`, `accumulate` | The key of the job, what a `Policy` matches on; without `describe`, the job prints as `Job(key)` | [Creating and scheduling jobs](jobs.md#creating-and-scheduling-jobs) |
| `describe` | `run`, `job`, `collect`, `accumulate` | The label after the key for logs, observers and `toString()`: `Job(key: label)` | [Creating and scheduling jobs](jobs.md#creating-and-scheduling-jobs) |
| `policy` | `run`, `collect`, `accumulate` | For `run`, a `Policy`: what happens to a job whose key is already queued or running. For an accumulator, an `AccumulationPolicy`: which waiting group an event joins | [Queue and policies](jobs.md#queue-and-policies), [Choosing where events join](accumulation.md#choosing-where-events-join) |
| `timing` | `collect`, `accumulate` | When a group may start, an `AccumulationTiming`: `debounce` or `throttle` | [Choosing when a group is ready](accumulation.md#choosing-when-a-group-is-ready) |
| `merge` | `accumulate` | Merges an incoming event into the value of the group; required, synchronous and pure | [Start, cancellation and errors](accumulation.md#start-cancellation-and-errors) |
| `canStart` | `run`, `job`, `collect`, `accumulate` | Asked once, when the job is about to start; `false` ends it `Cancelled(rules: canStart)` before the body runs | [The rules](state.md#the-rules) |
| `keepWhile` | `run`, `job`, `collect`, `accumulate` | Asked before the start, on state updates while the body runs and at state checkpoints; `false` cancels the job `Cancelled(rules: keepWhile)` | [The rules](state.md#the-rules) |
| `cancellable` | `run`, `job`, `collect`, `accumulate` | `false` turns down manual cancellation, the parent's and closing; waiting in the queue, the job stays through removals and `cancelAll()` without `force: true`, while `close()` takes it out all the same | [A whole job](cancellation.md#a-whole-job) |
| `timeout` | `run`, `job`, `collect`, `accumulate` | A deadline counted from the start of the body; when it runs out, the job ends `Cancelled(timeout)` | [A deadline of a job](cancellation.md#a-deadline-of-a-job) |
| `ifFailed` | `run`, `job` | The state to write when the job fails, once the body, its children and cleanup are over | [The handlers](state.md#the-handlers) |
| `ifCancelled` | `run`, `job` | The state to write when the job is cancelled, once the body, its children and cleanup are over | [The handlers](state.md#the-handlers) |

## SoloContext

What a body of `solo` gets as `ctx`: the core's `JobContext` plus the state,
narrowed to the working type `W` of the job. `join`, `abandonable`, `run`,
`onDispose` and the rest of `ctx` are the core's, in
[The context at a glance](https://github.com/vi-k/solo/blob/main/packages/async_job/README.md#the-context-at-a-glance)
of the `async_job` README. Here the checkpoints of the core, `check()` and the
waiting methods, also ask the rules of the job, as `ctx.state` does, and so
does `ctx.each`.

| Member | What it does | Where |
| --- | --- | --- |
| `ctx.state` | The state as `W`; a checkpoint, and a state the rules of the job refuse cancels it | [Reading and updating state](state.md#reading-and-updating-state) |
| `ctx.stateAs<T>()` | The state narrowed further, to `T`; a mismatch cancels the job | [Reading and updating state](state.md#reading-and-updating-state) |
| `ctx.emit(next)` | The body's only way to write the state; synchronous | [Reading and updating state](state.md#reading-and-updating-state) |
| `ctx.each(stream, onData)` | Starts a child that takes the events of a stream one at a time, and `onData` gets the child's `SoloContext`; a checkpoint, and a state the rules of the job refuse cancels the job instead of starting the child | [Processing a stream](streams.md#processing-a-stream) |

## SoloJob

What `run`, `job`, `add` and an accumulator's `add` return: a `Job<T>` of the
core plus the queue. `value`, `done`, `outcome`, `cancel()` and
`ignoreFailure()` are the core's, in the table of
[Jobs and results](jobs.md#jobs-and-results) on the jobs page. A method the
screen calls declares `Job<T>`, and `SoloJob<T>` only for a caller that reads
`isQueued`. A method that makes a child for `ctx.run` declares `SoloJob<T>`:
`ctx.run` takes a `ChildJob<T>`, which `SoloJob<T>` is and `Job<T>` is not.

| Member | What it does | Where |
| --- | --- | --- |
| `job.isQueued` | Whether the job is waiting in the controller's queue | [Creating and scheduling jobs](jobs.md#creating-and-scheduling-jobs) |

## SoloQueue

The type of `queue`. Removal touches waiting jobs only: the running job is not
the queue's. A job made with `cancellable: false` stays unless the call says
`force: true`, and a removed job ends `Cancelled(manual)` or with the `reason:`
the call passes.

| Member | What it does | Where |
| --- | --- | --- |
| `queue.jobs` | The waiting jobs in their order, which is not always the order they start in | [Working the queue directly](jobs.md#working-the-queue-directly) |
| `queue.length` | How many jobs wait | [Working the queue directly](jobs.md#working-the-queue-directly) |
| `queue.isEmpty` | Whether no job waits | [Working the queue directly](jobs.md#working-the-queue-directly) |
| `queue.isNotEmpty` | Whether any job waits | [Working the queue directly](jobs.md#working-the-queue-directly) |
| `queue.remove(job)` | Removes one job; returns whether it did | [Working the queue directly](jobs.md#working-the-queue-directly) |
| `queue.removeWhere(test)` | Removes every job that passes the test; returns how many | [When they are separate jobs after all](accumulation.md#when-they-are-separate-jobs-after-all) |
| `queue.clear()` | Removes every job; returns how many | [Commands that arrive during a shot](camera.md#commands-that-arrive-during-a-shot) |

## SoloAccumulator

The type `collect` and `accumulate` return. Keep one instance in a `late final`
field: events combine only within one accumulator, even under the same key.

| Member | What it does | Where |
| --- | --- | --- |
| `accumulator.add(event)` | Adds the event to a waiting group or starts one, and returns the group's job: everyone who added to it holds the same handle, and each continues it through `shared()`: a plain `then` on it throws | [Start, cancellation and errors](accumulation.md#start-cancellation-and-errors) |

## Other types

| Type | What it is | Where |
| --- | --- | --- |
| `Policy` | What `add` and `run` do with a job whose key is already queued or running: `sequential`, `droppable`, `replace` or `restart`; a job `droppable` may hand back is continued through `shared()` | [Queue and policies](jobs.md#queue-and-policies) |
| `SoloCloseMode` | How `close()` stops: `cancel` or `drain` | [Three ways to stop](cancellation.md#three-ways-to-stop) |
| `SoloObserver` | What `Solo.observer` takes: `onStart`, `onFinish`, `onError`, `onLog`, `onChange` and `onClose` of every controller, plus `onCreate`; `SoloObserver.all` joins several | [Watching every controller](diagnostics.md#watching-every-controller) |
| `SoloTransition` | One change of the state: the states before and after, the job that made it and a revision that grows by one per change | [Watching every controller](diagnostics.md#watching-every-controller) |
| `SoloPending` | What `pending` returns: a `SoloPendingJob` with its `SoloPhase`, a `SoloPendingQueue` or a `SoloPendingStream` | [What is holding the controller](diagnostics.md#what-is-holding-the-controller) |
| `SoloStream` | A mixin that adds a broadcast `stream` of the states | [Observing state](state.md#observing-state) |
| `AccumulationPolicy` | Which waiting group an event joins: `join`, `adjacent` or `replace` | [Choosing where events join](accumulation.md#choosing-where-events-join) |
| `AccumulationTiming` | When a group may start: `debounce` or `throttle` | [Choosing when a group is ready](accumulation.md#choosing-when-a-group-is-ready) |
| `SoloCancelReason` | The base of the reasons `solo` adds to the core's: `RulesCancelReason`, `ClosedCancelReason`, `DuplicateCancelReason` and `ReplacedCancelReason` | [Cancellation details](cancellation.md#cancellation-details) |
