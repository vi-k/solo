# Reference

One line for every member of `Solo`, of `SoloLanes` and its lanes, and of their
base `SoloController`, of the context their jobs get, of the jobs they return,
of the queue and of the accumulators, with the section that explains it. One
line, too, for every parameter of the methods that make jobs. What `solo` takes
from the core is listed where it is explained. The rest of `ctx` is in
[The context at a glance](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/reference.md#the-context-at-a-glance)
on the reference page of `async_job`, and `value`, `done` or `cancel()` of a
job are in [Jobs and results](jobs.md#jobs-and-results) on the jobs page.

## SoloController

`SoloController<S>` is the base class of every controller: the state, the
listeners, closing and the hooks. A controller extends `Solo`, which adds the
queue, or `SoloLanes`, which adds lanes; the constructor of `SoloController` is
private. Its members fall into three groups by who uses them: a caller, the
subclass, and an override in the subclass.

### What a caller sees

| Member | What it does | Where |
| --- | --- | --- |
| `currentState` | The state for a reader outside a job, read without a checkpoint | [Observing state](state.md#observing-state) |
| `addListener(listener)` | Calls back synchronously inside every change of the state | [Observing state](state.md#observing-state) |
| `removeListener(listener)` | Removes the earliest registration equal to the listener | [Observing state](state.md#observing-state) |
| `addChangeListener(listener)` | Calls back synchronously with the previous and the current state on every change, after the `addListener` listeners | [Observing state](state.md#observing-state) |
| `removeChangeListener(listener)` | Removes the earliest pair registration equal to the listener | [Observing state](state.md#observing-state) |
| `isClosed` | Whether `close()` was called | [Three ways to stop](cancellation.md#three-ways-to-stop) |
| `isDraining` | Whether a `close()` that drains is still running the queue | [Three ways to stop](cancellation.md#three-ways-to-stop) |
| `isFinished` | Whether closing has finished and the state can no longer change | [externalSetState](state.md#externalsetstate) |
| `pending` | What is holding the controller right now, a running job included, or `null` | [What is holding the controller](diagnostics.md#what-is-holding-the-controller) |
| `cancelAll()` | Clears every queue and cancels every running job, one per lane of a `SoloLanes`; the controller stays open. `force: true` removes queued jobs made with `cancellable: false` too, and `reason:` names the reason every job it ends carries | [Three ways to stop](cancellation.md#three-ways-to-stop) |
| `close()` | Stops taking work and closes, dropping what is queued and asking what runs to cancel or, with `mode: SoloCloseMode.drain`, running the queues first | [Three ways to stop](cancellation.md#three-ways-to-stop) |

### What the subclass uses

Through these a subclass asks about its listeners and reflects a state an
outside source changed. Every member here is protected.

| Member | What it does | Where |
| --- | --- | --- |
| `hasListeners` | Whether any listener is registered | [Observing state](state.md#observing-state) |
| `externalSetState(state)` | Reflects a state an outside source has already changed | [externalSetState](state.md#externalsetstate) |

### What the subclass overrides

The engine calls these. The hooks do nothing by default, except the two that
hand an error on, and `publish` delivers the state: an override calls
`super.publish` first. Every member here is protected too. Dart does not carry
the annotation over to an override, so an override that should stay protected
repeats `@protected`.

| Member | What it does | Where |
| --- | --- | --- |
| `onStart(job)` | A job body is about to run | [Watching every controller](diagnostics.md#watching-every-controller) |
| `onFinish(job)` | A job has an outcome, a job dropped before its start included | [Watching every controller](diagnostics.md#watching-every-controller) |
| `onError(job, error, stackTrace, answer: ...)` | Hears every error a job runs into and reports it, moving nothing | [Reporting an error](errors.md#reporting-an-error) |
| `onUnanswered(job, error, stackTrace)` | Answers for an error no outcome carries and a `Failed` nobody observes, by default through `Solo.unansweredHandler` or the zone | [Answering for an error](errors.md#answering-for-an-error) |
| `onLog(job, message)` | A job called `ctx.log` | [Logs](diagnostics.md#logs) |
| `onChange(transition)` | The state changed, with a `SoloTransition` that says which job changed it | [Watching every controller](diagnostics.md#watching-every-controller) |
| `onClose()` | The engine is about to finish closing, which is the place to release what the controller holds beside its jobs | [externalSetState](state.md#externalsetstate) |
| `onListenerError(error, stackTrace)` | A listener threw an error, which goes to the zone by default | [Observing state](state.md#observing-state) |
| `publish(previous, current)` | Calls the listeners and is the seam for a delivery of another kind | [A delivery of your own](state.md#a-delivery-of-your-own) |

## Solo

`Solo<S>` is the class a controller extends: the controller with one queue. It
declares the members of the queue, and `close` and `cancelAll` once more, with
the contract they have on `SoloController`. The rest of its members come from
`SoloController` and are listed there. The members `Solo` declares fall into
three groups by who uses them: the whole process, a caller and the subclass.

### Set once for the process

| Member | What it does | Where |
| --- | --- | --- |
| `Solo.observer` | One observer of every controller of the process, which watches and answers for nothing | [Watching every controller](diagnostics.md#watching-every-controller) |
| `Solo.unansweredHandler` | A `SoloUnansweredHandler` that takes the errors nobody answered for, in place of the zone | [Answering for an error](errors.md#answering-for-an-error) |
| `Solo.debug` | A callback that traces the queue, the state and the closing of every controller, while the life of each job goes to `Job.debug` | [Logs](diagnostics.md#logs) |

### What a caller sees

| Member | What it does | Where |
| --- | --- | --- |
| `cancelAll()` | `cancelAll()` of `SoloController`, declared again on `Solo` | [Three ways to stop](cancellation.md#three-ways-to-stop) |
| `close()` | `close()` of `SoloController`, declared again on `Solo` | [Three ways to stop](cancellation.md#three-ways-to-stop) |

### What the subclass uses

A controller builds its own constructor and methods from these, and a caller
sees those. Every member here is protected.

| Member | What it does | Where |
| --- | --- | --- |
| `Solo(initialState)` | The constructor a subclass calls as `super(initialState)`, with the first state | [Quick start](https://github.com/vi-k/solo/blob/main/packages/solo/README.md#quick-start) |
| `enqueue(body)` | Makes and queues the job a method of the controller usually returns | [Creating and scheduling jobs](jobs.md#creating-and-scheduling-jobs) |
| `job(body)` | Makes a job without queueing it, for `enqueueJob` or for `ctx.run` as a child | [Creating and scheduling jobs](jobs.md#creating-and-scheduling-jobs) |
| `enqueueJob(job)` | Queues a job made by `job` under a `Policy`, at the tail or, with `first: true`, at the head | [Queue and policies](jobs.md#queue-and-policies) |
| `collect(handler)` | Makes an accumulator that hands one job the list of the events of its group | [One request per log line](accumulation.md#one-request-per-log-line) |
| `accumulate(handler, merge: ...)` | Makes an accumulator that merges the events of a group into one value | [Settings saved on every flip of a switch](accumulation.md#settings-saved-on-every-flip-of-a-switch) |
| `queue` | The jobs waiting to run, a `SoloQueue` | [Working the queue directly](jobs.md#working-the-queue-directly) |
| `lastJobWhere(test)` | The last queued job that passes the test, else the running one if it passes and has not been cancelled, else `null` | [Working the queue directly](jobs.md#working-the-queue-directly) |
| `current` | The running root job, or `null` when the controller is idle | [Working the queue directly](jobs.md#working-the-queue-directly) |

## SoloLanes

`SoloLanes<S>` is the class a controller with lanes extends: its root jobs run
one at a time in each lane, and the lanes run side by side over one state. It
has no queue of its own. It declares its lanes, and the rest of its members
come from `SoloController`.

### What the subclass uses

The lanes are declared in the body of the constructor and kept in private
fields. Every member here is protected.

| Member | What it does | Where |
| --- | --- | --- |
| `SoloLanes(initialState)` | The constructor a subclass calls as `super(initialState)`, with the first state; its body declares the lanes | [Declaring lanes](lanes.md#declaring-lanes) |
| `lane(name)` | Declares a lane and returns it; throws `StateError` for a name declared already, and once any lane's `enqueueJob` has been called (a refused or duplicate call seals too), the controller is closed or a microtask after the constructor has run | [Declaring lanes](lanes.md#declaring-lanes) |
| `lanes` | The lanes in the order they were declared | [Declaring lanes](lanes.md#declaring-lanes) |

## SoloLane

The type `lane` returns: one lane of a `SoloLanes`, with the members of the
queue a `Solo` has. They are public: whoever holds the lane queues jobs in it,
so a controller keeps its lanes in private fields. A job runs in the lane that
queued it, and a `Policy` looks for its key in that lane only. A lane has no
`close` or `cancelAll`: those are the controller's.

| Member | What it does | Where |
| --- | --- | --- |
| `lane.name` | The name the lane was declared with, for logs | [Declaring lanes](lanes.md#declaring-lanes) |
| `lane.id` | The `SoloLaneId` a job of this lane returns from `job.lane` | [Declaring lanes](lanes.md#declaring-lanes) |
| `lane.enqueue(body)` | Makes and queues a job of this lane | [Two queues over one state](lanes.md#two-queues-over-one-state) |
| `lane.job(body)` | Makes a job of this lane without queueing it, for `lane.enqueueJob` or for `ctx.run` as a child | [Creating and scheduling jobs](jobs.md#creating-and-scheduling-jobs) |
| `lane.enqueueJob(job)` | Queues a job this lane made under a `Policy`, at the tail or, with `first: true`, at the head; a job of another lane or another controller is refused with an `ArgumentError` | [Two queues over one state](lanes.md#two-queues-over-one-state) |
| `lane.collect(handler)` | Makes an accumulator whose groups go into this lane, each handing one job the list of its events | [One request per log line](accumulation.md#one-request-per-log-line) |
| `lane.accumulate(handler, merge: ...)` | Makes an accumulator whose groups go into this lane, each merging its events into one value | [Settings saved on every flip of a switch](accumulation.md#settings-saved-on-every-flip-of-a-switch) |
| `lane.queue` | The jobs waiting in this lane, a `SoloQueue` | [Working the queue directly](jobs.md#working-the-queue-directly) |
| `lane.lastJobWhere(test)` | The last queued job of this lane that passes the test, else its running one if it passes and has not been cancelled, else `null` | [Working the queue directly](jobs.md#working-the-queue-directly) |
| `lane.current` | The running root job of this lane, or `null` when the lane is idle | [Working the queue directly](jobs.md#working-the-queue-directly) |
| `lane.pending` | What is holding this lane right now, by the rules `pending` has for a `Solo`, or `null` | [What is holding the controller](diagnostics.md#what-is-holding-the-controller) |

## Parameters of a job

`enqueue`, `job`, `collect` and `accumulate`, of a `Solo` and of a `SoloLane`
alike, take the body first — for an accumulator, a handler that also gets the
events of its group — and these named parameters after it. The first type
argument of each is the working type, in
[State and rules](state.md#state-and-rules) on the state page.

| Parameter | Taken by | What it does | Where |
| --- | --- | --- | --- |
| `key` | `enqueue`, `job`, `collect`, `accumulate` | The key of the job, what a `Policy` matches on and, without `describe`, what the job prints as: `Job(key)` | [Creating and scheduling jobs](jobs.md#creating-and-scheduling-jobs) |
| `describe` | `enqueue`, `job`, `collect`, `accumulate` | The label after the key for logs, observers and `toString()`: `Job(key: label)` | [Creating and scheduling jobs](jobs.md#creating-and-scheduling-jobs) |
| `policy` | `enqueue`, `collect`, `accumulate` | A `Policy` for `enqueue`, deciding what happens to a job whose key is already queued or running, or an `AccumulationPolicy` for an accumulator, deciding which waiting group an event joins | [Queue and policies](jobs.md#queue-and-policies), [Choosing where events join](accumulation-rules.md#choosing-where-events-join) |
| `timing` | `collect`, `accumulate` | When a group may start, an `AccumulationTiming`: `debounce` or `throttle` | [Choosing when a group is ready](accumulation-rules.md#choosing-when-a-group-is-ready) |
| `merge` | `accumulate` | A required, synchronous and pure function that merges an incoming event into the value of the group | [Start, cancellation and errors](accumulation-rules.md#start-cancellation-and-errors) |
| `canStart` | `enqueue`, `job`, `collect`, `accumulate` | Asked once as the job is about to start, ending it `Cancelled(rules: canStart)` on `false` | [The rules](state.md#the-rules) |
| `keepWhile` | `enqueue`, `job`, `collect`, `accumulate` | Keeps the job while the state allows it, and on `false` cancels it `Cancelled(rules: keepWhile)` | [The rules](state.md#the-rules) |
| `cancellable` | `enqueue`, `job`, `collect`, `accumulate` | `false` turns down manual cancellation and the parent's, and closing once the job runs: a queued one `close()` drops | [A whole job](cancellation.md#a-whole-job) |
| `timeout` | `enqueue`, `job`, `collect`, `accumulate` | A deadline counted from the start of the body, after which the job ends `Cancelled(timeout)`; with `cancellable: false` the call throws `ArgumentError` | [A deadline of a job](cancellation.md#a-deadline-of-a-job) |
| `ifFailed` | `enqueue`, `job`, `collect`, `accumulate` | The state to write when the job fails, once the body, its children and cleanup are over | [The handlers](state.md#the-handlers) |
| `isExpectedError` | `enqueue`, `job`, `collect`, `accumulate` | Names the errors the job expects: one it names is heard by `onError` with `never`, and nobody is asked to answer for it | [Naming the expected errors](errors.md#naming-the-expected-errors) |
| `ifCancelled` | `enqueue`, `job`, `collect`, `accumulate` | The state to write when the job is cancelled, once the body, its children and cleanup are over | [The handlers](state.md#the-handlers) |

## SoloContext

What a body of `solo` gets as `ctx`: the core's `JobContext` plus the state,
narrowed to the working type `W` of the job. `join`, `abandonable`, `onDispose`
and the rest of `ctx` are the core's, in
[The context at a glance](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/reference.md#the-context-at-a-glance)
on the reference page of `async_job`. Here the checkpoints of the core,
`check()` and the waiting methods, also ask the rules of the job, as
`ctx.state` does, and so does `ctx.each`.

| Member | What it does | Where |
| --- | --- | --- |
| `ctx.state` | The state as `W`, read at a checkpoint where a state the rules of the job refuse cancels the job | [Reading and updating state](state.md#reading-and-updating-state) |
| `ctx.stateAs<T>()` | The state narrowed further to `T`, where a mismatch cancels the job | [Reading and updating state](state.md#reading-and-updating-state) |
| `ctx.emit(next)` | The body's only way to write the state, a synchronous one | [Reading and updating state](state.md#reading-and-updating-state) |
| `ctx.child(body)` | Makes an unstarted child of this controller under the rules of this job, its working type `W` and `keepWhile`, for the code that holds only a context | [Children and chains](children.md) |
| `ctx.run(child)` | Runs a child made by `job(...)` of this controller or by `ctx.child` and returns its value; a job of the core or of another controller is refused with an `ArgumentError` | [Children and chains](children.md) |
| `ctx.start(child)` | Starts such a child right now and leaves its outcome to whoever holds it | [Children and chains](children.md) |
| `ctx.runAll(children)` | Runs such children side by side and stops the rest as soon as one of them goes wrong | [Children and chains](children.md) |
| `ctx.each(stream, onData)` | Starts a child that hands the events of a stream to `onData` one at a time, with the child's `SoloContext`, at a checkpoint where a state the rules of the job refuse cancels the job instead | [Processing a stream](streams.md#processing-a-stream) |

## SoloJob

What `enqueue`, `job`, `enqueueJob` and an accumulator's `add` return, and what
`queue.jobs`, `current` and `lastJobWhere` hand out: a `Job<T>` of the core
plus the queue. `value`, `done`, `outcome`, `cancel()` and `ignoreFailure()`
are the core's, in the table of [Jobs and results](jobs.md#jobs-and-results) on
the jobs page. A method the screen calls declares `Job<T>`, and `SoloJob<T>`
only for a caller that reads `isQueued`. A method that makes a child for
`ctx.run` declares `SoloJob<T>`: `ctx.run` takes a `ChildJob<T>`, which
`SoloJob<T>` is and `Job<T>` is not.

| Member | What it does | Where |
| --- | --- | --- |
| `job.isQueued` | Whether the job is waiting in the controller's queue | [Creating and scheduling jobs](jobs.md#creating-and-scheduling-jobs) |
| `job.lane` | The `SoloLaneId` of the lane the job runs in, or `null` for a job of a `Solo` and for one not queued or run yet | [Declaring lanes](lanes.md#declaring-lanes) |

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
| `queue.remove(job)` | Removes one job and returns whether it did | [Working the queue directly](jobs.md#working-the-queue-directly) |
| `queue.removeWhere(test)` | Removes every job that passes the test and returns how many | [When they are separate jobs after all](accumulation.md#when-they-are-separate-jobs-after-all) |
| `queue.clear()` | Removes every job and returns how many | [Commands that arrive during a shot](camera.md#commands-that-arrive-during-a-shot) |

## SoloAccumulator

The type `collect` and `accumulate` return. Keep one instance in a `late final`
field: events combine only within one accumulator, even under the same key.

| Member | What it does | Where |
| --- | --- | --- |
| `accumulator.add(event)` | Adds the event to a waiting group or starts one, and returns the group's job, which every caller continues through `shared()` | [Start, cancellation and errors](accumulation-rules.md#start-cancellation-and-errors) |

## Other types

| Type | What it is | Where |
| --- | --- | --- |
| `Policy` | What `enqueueJob` and `enqueue` do with a job whose key is already queued or running: `sequential`, `droppable`, `keepLatest` or `restart` | [Queue and policies](jobs.md#queue-and-policies) |
| `SoloCloseMode` | How `close()` stops: `cancel` or `drain` | [Three ways to stop](cancellation.md#three-ways-to-stop) |
| `SoloLaneId` | What `job.lane` returns: a lane told apart by identity, with the `name` it was declared with | [Declaring lanes](lanes.md#declaring-lanes) |
| `SoloUnansweredHandler` | The type of `Solo.unansweredHandler`: a function of the controller, the job, the error and its stack trace | [Answering for an error](errors.md#answering-for-an-error) |
| `SoloObserver` | What `Solo.observer` takes, one or several joined by `SoloObserver.all`: `onStart`, `onFinish`, `onError`, `onLog`, `onChange` and `onClose` of every controller, plus `onCreate` | [Watching every controller](diagnostics.md#watching-every-controller) |
| `SoloTransition` | One change of the state: the states before and after, the job that made it and a revision that grows by one per change | [Watching every controller](diagnostics.md#watching-every-controller) |
| `SoloPending` | What `pending` returns: a `SoloPendingJob` with its `job` and `phase`, a `SoloPendingQueue` with its `jobs`, a `SoloPendingLanes` whose `lanes` hold a `SoloPendingLane` with one of those two for each busy lane of a `SoloLanes`, or a `SoloPendingStream` | [What is holding the controller](diagnostics.md#what-is-holding-the-controller) |
| `SoloPhase` | Where the job of a `SoloPendingJob` stands: `body`, `children` or `cleanup` | [What is holding the controller](diagnostics.md#what-is-holding-the-controller) |
| `SoloStream` | A mixin that adds a broadcast `stream` of the states | [Observing state](state.md#observing-state) |
| `AccumulationPolicy` | Which waiting group an event joins: `join`, `adjacent` or `replace` | [Choosing where events join](accumulation-rules.md#choosing-where-events-join) |
| `AccumulationTiming` | When a group may start: `debounce` or `throttle` | [Choosing when a group is ready](accumulation-rules.md#choosing-when-a-group-is-ready) |
| `SoloCancelReason` | The base of the reasons `solo` adds to the core's: `RulesCancelReason`, `ClosedCancelReason`, `DuplicateCancelReason` and `ReplacedCancelReason`, which `SoloListener` of `flutter_solo` gives a replaced reaction as well | [Cancellation details](cancellation.md#cancellation-details) |
