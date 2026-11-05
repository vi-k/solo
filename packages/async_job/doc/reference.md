# Reference

Every member of the context, `ctx`, with what it does once the job is
cancelled, and the four words the other pages of `async_job` use for errors and
cancellation.

## The context at a glance

What each member of `ctx` does, how it behaves once the job is cancelled, and
what a cancellation that comes while it runs does to it:

| Member | What it does | Once the job is cancelled | Cancelled while it runs |
| --- | --- | --- | --- |
| `ctx.check()` | A bare checkpoint | Throws `Cancelled` |  |
| `ctx.join(action)` | Waits for all of the action | Throws `Cancelled` | Waits, then throws |
| `ctx.abandonable(action)` | Waits while the job lives | Throws `Cancelled` | Throws at once |
| `ctx.uncancellable(action)` | Holds the cancellation back | Throws `Cancelled` | Holds it until the step ends |
| `ctx.pause(duration)` | Lets time pass | Throws `Cancelled` | Ends and throws |
| `ctx.child(body)` | Makes a child to run | Works as usual |  |
| `ctx.run(child)` | Runs a child and waits | Throws `Cancelled` | Passes it on, waits, throws |
| `ctx.start(child)` | Starts a child, no waiting | Throws `Cancelled` | Passes it on |
| `ctx.runAll(children)` | Runs children side by side | Throws `Cancelled` | Passes it on, waits, throws |
| `ctx.each(stream, onData)` | Follows a stream in a child | Throws `Cancelled` | Passes it on |
| `ctx.onCancel(callback)` | Calls back on a cancellation | Throws `Cancelled` |  |
| `ctx.onDispose(disposer)` | Cleans up at the end | Works as usual |  |
| `ctx.onDiscard(disposer)` | Cleans up unless `Done` | Works as usual |  |
| `ctx.disown(value)` | Drops a value's cleanup | Works as usual |  |
| `ctx.unattended(action)` | Starts work nobody waits for | Works as usual | Not cancelled |
| `ctx.log(message)` | Hands a message to the observer | Works as usual |  |
| `ctx.job` | The job of this context | Works as usual |  |
| `ctx.heldCancellation` | The held cancellation, or `null` | Works as usual |  |

What the cells leave out:

- `ctx.check()` is the checkpoint for a place where there is no call to wrap.
- `ctx.abandonable` stops waiting when the job is cancelled, and the action
  runs on. `ctx.uncancellable` holds the cancellation until the step ends, and
  the next checkpoint throws it.
- `ctx.child` makes an unstarted child that the engine of the job accepts, for
  code that holds the context and does not know the engine: a `Job.deferred` is
  a child of the core, and an engine that owns its children turns it away. It
  starts and checks nothing; the members that start a child do the refusing.
- `ctx.run`, `ctx.start` and `ctx.runAll` take a `ChildJob`, such as one made
  with `Job.deferred` or `ctx.child`, and pass the cancellation to their
  children. `ctx.start` leaves the outcome of its child to whoever holds the
  child. `ctx.runAll` stops the rest as soon as one child ends without a value.
- `ctx.each` hands the events of the stream to its callback one at a time.

- `ctx.onCancel` calls back the moment the job accepts a cancellation.
  `ctx.onDispose` cleans up whatever the outcome. `ctx.onDiscard` cleans up
  unless the job ends `Done`, and a body that ends `Done` without returning the
  value disposes of it itself.
- The errors of the work of `ctx.unattended` go to `onError`, then are answered
  for.
- A closure handed to `ctx.log` is called by the observer that builds the line.
- `ctx.heldCancellation` is the cancellation an open `uncancellable` section
  holds back.

The last column holds where the job accepts the cancellation as it comes.
Inside `ctx.uncancellable`, and in a job created with `cancellable: false`, the
job does not accept it while the member runs, and the member goes on as if none
had come.

## Four words

Four words carry the model of errors and cancellation, and each means less than
it does in everyday English:

| Word | What it means | Page |
| --- | --- | --- |
| Observe a failure | Read `done` or `value`, forward the failure through `then`, or call `ignoreFailure()`, by the microtask after the job ends; reading `outcome` or giving the job an observer does not count. | [Outcomes](outcomes.md#a-failure-nobody-waits-for) |
| Answer for an error | What happens to a failure nobody observes and to an error no outcome carries: `onUnanswered` of an observer that mixes in `JobAnswerer` takes it, or the zone if the job has no such observer. | [Errors](errors.md#answering-for-errors) |
| The zone | The zone the job was created in; an error that reaches it is an uncaught error there. | [Errors](errors.md) |
| Accept a cancellation | The job becomes cancelled: the cancellation passes to its children, its `onCancel` callbacks run, and it ends `Cancelled` whatever the body does next. | [Cancellation](cancellation.md) |
