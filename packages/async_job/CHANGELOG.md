## Unreleased

- **Breaking:** `JobBase`, `JobContextBase` and `JobStatus` moved to
  `package:async_job/engine.dart`. They are the protocol for building an engine
  on the kernel, and the main import handed them to every file that merely runs
  a job -- and, through `solo` and `flutter_solo`, to every file of an app.
  `engine.dart` exports the rest of the package as well, so an engine swaps one
  import for the other: `import 'package:async_job/engine.dart';` in place of
  `async_job.dart`. Code that only runs jobs is untouched. See
  `doc/extending.md`.

- **Fix:** a `whenCancelled` registered while the cancellation is still
  cascading onto the children now runs in its turn instead of ahead of everyone
  who registered earlier. Between the mark and the pass that tells the
  listeners there is a window, and a registration made in there was called on
  the spot because the cancellation had been accepted -- which is true, and is
  not the same thing as the pass having run.
- **Fix:** a job of a domain that compares itself by a key is no longer taken
  for another one inside unattended work. The fork of `ctx.unattended` carries
  a zone value under the job as its key, and a zone looks a key up by `==`, so
  two jobs equal by key were one: the inner one, started from inside the
  other's fork, refused `uncancellable` and `each` with "cannot ... inside
  unattended work". The job is now the value as well as the key, and the
  readers compare it by identity.
- **Fix:** an envelope whose branches share a node is walked once per node
  rather than once per path. The walk marked a node visited and never read the
  mark, so a graph of twenty-seven shared nodes took sixty-seven million steps;
  only a hand-built envelope can be shaped that way, and now it is linear.
- **Fix:** an action failing after the body walked away from it is no longer
  swallowed. A `ctx.wait` the body left through a `.timeout` or a `Future.any`
  handed its late error to the future the wrapper was holding, and a wrapper
  that has already fired drops what it is given: the error reached nobody at
  all, not the observer and not the zone. It now goes to `onError`, the way the
  failure of any abandoned action does, and the future is completed as well so
  that nothing left waiting on it waits for ever. A `wait` made inside work
  handed over with `unattended` is untouched: the work is still holding that
  future and the fork announces what it leaves uncaught, so it is announced
  once, there.
- **Fix:** a step that failed inside `ctx.uncancellable` while a cancellation
  was held keeps its diagnosis. The section applies the held cancellation on
  the way out, which is before the error reaches the body, so the kernel read
  the order the wrong way round -- it saw a failure thrown after a mark, which
  belongs to the observer alone, and without an observer that was silence. The
  section now says which came first, and the failure of the one step that
  cannot be rolled back goes to the zone as any uncovered one does.
- **Fix:** a job that has accepted a cancellation no longer ends with a value.
  The protected `finish`, which an engine of a domain uses to end a job by
  hand, took whatever it was handed: after `cancel()` a `finish(Done(42))` left
  a handle saying both at once -- `isCancelled` true, `check` throwing,
  `whenCancelled` fired, and `outcome` a `Done(42)`. The mark now decides a
  `Done` or a `Failed` handed in over it, and a failure so replaced goes where
  one a cancellation covered goes, so nothing is lost silently. A `Cancelled`
  handed in still stands: the handle stays coherent, and an engine ending a job
  from inside the cascade keeps the description that is its whole diagnosis.
- **Fix:** a value arriving for a job an engine ended by hand is released
  instead of leaking. There was no cleanup stack left to register it on, so the
  registration threw a complaint about a finished job into the body, which saw
  that instead of its value and had nothing to close. The value is now released
  on the spot, the way one that came back too late is, and the body hears the
  plain `StateError` about the job.
- **Fix:** a value that comes back after the body has ended no longer finishes
  the same wait twice. Putting the late value on the cleanup stack costs a
  microtask even when there is nothing to put there, and a cancellation
  arriving in that microtask finished the wait through the callback still
  standing; the completion that followed threw `Future already completed` out
  of the kernel, and the job reported that to `onError` as an error of its own.
  The value was never in danger -- the registration had it -- but whoever
  listens saw a defect of the package where there was none.
- **Fix:** a body that gives itself up is marked there and then. Until now the
  mark went on only after the job had waited for its children, so between the
  `throw Cancelled(...)` and that wait the job answered `isCancelled` with
  `false`, `ctx.check()` let work through, and a `cancel()` arriving in the
  window went through in full and put its own reason over the one the body
  chose -- the description the body wrote disappeared from the diagnosis. The
  children were cascaded to at once, so they carried a `ParentCancelReason`
  whose cause their parent then did not end with. What a caller may see
  differently: cancelling a job whose body has already given up now keeps the
  body's reason, and `Job.cancel` returns when the job finishes, as a second
  call always did. What is unchanged is the reason the mark is late at all --
  the `onCancel` callbacks still do not run on this path, and the waits the
  body walked away from still get their values quietly.
- **Fix:** a finished job lets go of its body, of its parent and of the group
  of `ctx.runAll` that held it. The body of a core job ran once and was kept
  for good, so everything it captured -- a controller, a connection, a buffer
  -- stayed alive for as long as anyone kept the handle; the link to the parent
  turned one child handle into the whole chain it came out of, and the hold of
  a group turned one branch handle into the coordinator and every sibling in
  it. A handle is kept precisely to be read later, by a controller holding its
  last job, by a widget, by a journal, so the retention grew with ordinary use.
  Nothing an outcome carries is touched: `outcome`, `value` and the key read
  exactly as they did.
- **Fix:** `ctx.runAll` stops the siblings when a branch throws before its
  first `await`. The group attaches its hold once the branch is admitted --
  before that a handle already running as somebody else's branch would be
  pulled out of their hold -- and a body that is not `async` has ended inside
  `startChild`, one line earlier. Its early word found nothing to say itself
  to, so the group learned of the trouble only at the second barrier: the
  siblings played out in full, opened what they opened, wrote what they wrote,
  and were then handed `Cancelled(sibling)`, which says the opposite. The group
  now reads that early word off the branch itself, in the same synchronous step
  that started them all, so the stop reaches every sibling before it moves past
  its first suspension point.
- **Fix:** a job giving up no longer reaches `JobObserver.onError`. A call the
  body walked away from with `ctx.wait` keeps the context, and after the mark
  every door back into it -- `check`, `join`, `run` -- throws the very
  `Cancelled` that became the outcome; the kernel took that for a late failure
  of the abandoned action and reported it. `JobObserver.onError` says the
  opposite in so many words -- "never the job giving up, which is not an error"
  -- and in an engine of a domain that hook is the error channel of the
  application, so every cancellation of a job written with a helper that takes
  the context showed up there as a failure. The filter `unattended` already
  applies to work handed over now stands on this path as well, by identity
  against the outcome and the mark: a `Cancelled` built inside the action, and
  one belonging to another job, report exactly as they did.
- **Breaking:** `ctx.run` takes `dispose` and `discard`, the way `ctx.wait`
  does, and makes the registration the moment the child's value comes back. New
  named parameters on a member of an `abstract interface class`, so an
  implementation of `JobContext` written by hand no longer compiles;
  `JobContextBase` gets them once and every engine built on it, `solo`
  included, gets them for nothing. Why they belong on the call: `run` checks
  the parent once the value is in hand -- for its own cancellation, and for the
  rules of its domain -- and a checkpoint that throws there takes the value
  with it. The child ended `Done`, so its own conditional registration went
  with the value and is gone, and the line that would have made the next one is
  never reached: `parent=Cancelled(rules) child=Done(db)` with nothing closed.
  **Migrating.** Nothing breaks at a call site: `ctx.run(child)` is unchanged,
  and `ctx.wait(() => ctx.run(child), discard: ...)` still compiles and still
  closes what it took on every path it ever did. It does not close this one,
  and it never could: its registration is made against the value `run` returns,
  and at this checkpoint `run` throws instead of returning. That wrapper and a
  registration written on the line after `await ctx.run(child)` are both the
  ones to move into the call. See `doc/cleanup.md`.
- **Added:** the debug channel names a job that handed its value over and
  dropped the conditional registrations that went with it --
  `Job(opener) handed its value over: 1 conditional cleanup dropped`. A
  registration made by `discard` or `onDiscard` is settled by the outcome of
  the job that made it and travels with no value, so a receiver that keeps the
  resource has to register it again; forgetting that leaks nothing visible
  until the receiver ends badly. The line marks every hand-over, a branch of
  `ctx.runAll` included, where the group strips the registrations as it
  commits. See `doc/cleanup.md`.
- **Breaking:** `JobContext` gains `runAll`, which runs children side by side
  and asks the rest to stop as soon as one of them goes wrong. New on an
  `abstract interface class`, so an implementation of `JobContext` written by
  hand no longer compiles, and so does an extension of the same name on
  `JobContext` -- the member now wins over it. `JobContextBase` gets it once
  and every engine built on it, `solo` included, gets it for nothing. It brings
  a fifth built-in reason with it, `SiblingCancelReason`, which is what the
  group gives the branches it asks to stop; its `cause` is what went wrong. The
  contract of `discard` is untouched: it still runs only when the job ends
  without handing its value over, and in a branch of a group the group is what
  says whether it did. See `doc/children.md`.
- **Breaking:** a cancellation that travels inside a `ParallelWaitError` is a
  cancellation again. `[...].wait` wraps every branch error in that envelope,
  and the kernel read a caught error by type, so a child cancelled under
  `[ctx.run(a), ctx.run(b)].wait` ended the parent `Failed` -- where the same
  code written as `await ctx.run(child)` ends it `Cancelled`, as
  `doc/children.md` promises. An envelope carrying cancellations and successful
  branches now decides the outcome the way the cancellation it carries would,
  with the stack trace of that branch; the children the body started outside
  the waiting are cascaded to, and an unobserved outcome no longer sends the
  envelope to the zone. An envelope carrying a real failure is untouched: the
  outcome stays `Failed` with the same object, its `errors` and `values`
  intact, because a failure must not hide behind a cancellation. What changes
  for a caller: `job.value` throws the `Cancelled` instead of the envelope, a
  `catch (ParallelWaitError)` around it no longer runs, `whenCancelled` fires,
  and in `solo` the job's `onCancel` handler takes the outcome where `onError`
  used to. **Migrating.** A resource opened in a successful branch and closed
  from that outer `catch` should be taken through
  `ctx.wait(() => open(), dispose: (value) => value.close())`: the kernel then
  closes it whatever the outcome, and nothing is needed at the call site. For a
  branch that cannot go through `ctx.wait`, catch the envelope inside the body,
  where it still arrives as it did. An envelope built by hand is read by the
  same rule -- it cannot be told apart from the one the language builds -- so
  code that deliberately throws an aggregate with a cancellation inside should
  wrap it in an error of its own. `Future.wait` is unchanged and cannot be
  changed: it reports the first error to reach it and discards the rest before
  anything else can see them.

- `doc/children.md` says what `ctx.run` does with a chain, and why: a
  continuation starts itself when its source finishes, so no link of one can be
  adopted — the head is the only job in a chain a parent can take. And the
  parent waits for its children, not for what hangs off them: a slow tail runs
  on after the parent has finished `Done`, its failure goes to the zone that
  built the chain rather than to the parent, and only cancellation still
  reaches it, forward through the source.

- `doc/observing.md` now says how to measure the wait a cancellation costs,
  with no hook of its own: `Job.whenCancelled` fires when the cancellation
  takes effect and `onFinish` when the outcome arrives, so an observer that
  stamps the clock in one and subtracts in the other has the number. `solo`
  shows the observer in full.

- The README is a starting page: what a job is, why a plain `Future` does not
  cover it — now shown as the flag that asks and the job that answers —
  `Install`, `Quick start` and a map of the guides. The reference material
  moved to `doc/`: `outcomes.md`, `cancellation.md`, `children.md`,
  `cleanup.md`, `observing.md`, `extending.md`. Nothing was dropped, and every
  section now starts with the code it is about.
- **Fix:** `ctx.join` releases the value through `dispose` or `discard` when
  the checkpoint after the action throws anything, not only a `Cancelled`. A
  rule of a domain that threw instead of answering used to cost the job the
  resource it already held: the value reached no body and was registered on no
  cleanup stack.
- **Breaking:** add the protected `JobBase.handleUnanswered`, the route for an
  error of a job that nobody answered for -- today a branch of `ctx.runAll`
  whose failure the group did not throw. Its default is `notifyError` with the
  second announcement left out, and an engine of a domain overrides it to reach
  an answer of its own: `solo` sends it to `Solo.errorHandler`. Such an engine
  has to, because one that puts an observer on every job makes the kernel's
  check for an observer true always, and the error would stop there. Adding a
  member to a class meant to be extended is breaking on its own: a subclass
  with a member of that name stops compiling. See `doc/extending.md`.
- **Breaking:** add the protected `JobBase.inUncancellableSection` and
  `JobBase.heldCancel`, for an engine that waits for a job and wants to say
  why. The first says a section is open; the second is the cancellation such a
  section holds back, which marks nothing until the section closes and so shows
  nowhere else. An open section alone does not mean anybody asked. Adding a
  member to a class meant to be extended is breaking on its own: a subclass
  with a member of that name stops compiling.

- **Fix:** a cancellation cascade that runs out of stack no longer leaves the
  tree jammed. The cascade is recursive, and a tree thousands of levels deep
  overflows inside it; the mark goes on before the descent and the callbacks
  run after it, so the unwinding left every job the cascade had reached marked
  and unannounced -- no `onCancel` ran, nothing was told to stop, and a second
  `cancel()` turned around at the mark. The callbacks now run as the cascade
  unwinds, and the error still reaches whoever asked. A body giving itself up
  meets the same descent with nobody to hand a failure to, so there the error
  goes to `onError` and the job still waits for its children and unwinds its
  cleanup stack instead of stopping where it stood. The siblings of the child
  that overflowed are no longer skipped either -- one child is not the rest of
  them, and the one that runs the stack out may be a chain of thousands next to
  a leaf -- and an overflow landing in a cancellation callback at the very
  bottom is not announced as a failure of that callback, which would name it
  for something it did not do -- there and nowhere else, though: a callback
  that runs out of stack anywhere but under that unwinding did it by itself,
  and its error goes to `onError` and changes nothing else, as it always has.
  What lies below the break is still left running: the depth of a tree is
  bounded by the stack either way, and `doc/children.md` says by how much.

- `doc/outcomes.md` no longer promises that a `whenCancelled` registered after
  a cancellation always fires on the spot. It does once the cancellation has
  been announced; one made in between -- while the cancellation cascades onto
  the children, or while a job whose body gave itself up waits for them --
  joins that announcement in its own place, and a registration made later never
  runs before one made earlier. The dartdoc of `whenCancelled` has been saying
  so; the page had the short version.

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
