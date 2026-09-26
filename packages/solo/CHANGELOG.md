## Unreleased

- **Breaking:** the reporting hook no longer carries the errors nobody answered
  for. `Solo.onError` is a notice now, with an empty body: it is told about
  every error of the controller, once, and overriding it moves no error
  anywhere. The route it used to hold -- `Solo.errorHandler`, and the job's
  creation zone when no handler is set -- moved to the new hook
  `Solo.onUnanswered`, asked only about the errors no outcome carries: an
  operation abandoned by `wait` failing later, a disposer, an `onCancel`
  callback, work handed to `ctx.unattended`, the failure of a branch of
  `ctx.runAll` that the group did not throw, and the failure of a body when a
  cancellation reaches the job afterwards, while it still waits for children of
  its own or runs its cleanup. Whoever reads that outcome gets the
  cancellation, so such a failure of a root or of a child of `ctx.each` reaches
  `Solo.errorHandler` even when its `value` was awaited; `job.ignore()`
  silences it. Any other failure of a body is not one of them: it becomes
  `Failed`, where `run(onError: ...)` computes a state and an outcome nobody
  observes reaches the zone by itself. An override of `onError` that called
  `super` keeps working -- that call now runs an empty body, and the route
  stands without it. An override that did not call `super` is what this
  changes, and quietly: the errors it used to swallow reach the handler or the
  zone again. To keep them where that override put them, move its body to
  `onUnanswered`; an override there answers for these errors and stops them,
  and `super.onUnanswered(job, error, stackTrace)` reports and keeps the route
  as well.

- **Breaking, inherited from `async_job`:** `solo` re-exports the core whole,
  so the core's breaking changes are this package's too, and three of them
  reach an ordinary job body. A cancellation that travels inside a
  `ParallelWaitError` is a cancellation again: a child cancelled under
  `[ctx.run(a), ctx.run(b)].wait` ends the job `Cancelled` where it used to end
  it `Failed`, so the job's `onCancel` handler takes the outcome instead of
  `onError`, `job.value` throws the `Cancelled`, and a
  `catch (ParallelWaitError)` around it no longer runs. `JobContext` gains
  `runAll`, and an extension of that name on `JobContext` is shadowed by it.
  `ctx.run` takes `dispose` and `discard`: no call site breaks, but a
  registration written on the line after `await ctx.run(child)` belongs in the
  call now. One more reaches code that gives a job of the core an observer of
  its own: `JobObserver.onError` is a notice, and the new
  `JobObserver.onUnanswered` answers for an error no outcome carries, so such
  an observer no longer keeps those errors out of the zone, and a class that
  implements `JobObserver` needs an `onUnanswered`. The hooks of a controller
  are unchanged. The rest concern an engine built on the kernel only: the
  protected `JobBase.inUncancellableSection` and `JobBase.heldCancel`, and the
  move of `JobBase`, `JobContextBase` and `JobStatus` to
  `package:async_job/engine.dart` -- which also takes them out of what an app
  sees through this package. Read the core's own entries before migrating:
  [the `async_job` changelog](https://github.com/vi-k/solo/blob/main/packages/async_job/CHANGELOG.md).

- **Breaking:** `SoloBase` is renamed to `Solo`, and the former `Solo` -- the
  broadcast stream it carried -- becomes the mixin `SoloStream`. `Solo` stays
  the class every controller extends; a stream is no longer part of that by
  default, only of controllers that add `with SoloStream`. Most
  `extends Solo<...>` declarations never read `.stream` and need no change at
  all; the few that do gain the mixin. `SoloListenable` of `flutter_solo`
  becomes a mixin of the same kind, and the two combine for a controller that
  needs both deliveries: `with SoloStream, SoloListenable`. A bare
  `Solo<T>(value)` -- the former `Solo`, instantiated directly for its engine
  and its stream together -- no longer compiles: `Solo` is `abstract`, as
  `SoloBase` always was, and there is no concrete class left that carries a
  stream on its own. Write a one-line class instead, which takes the
  constructor of `Solo` as it is:
  `class C<T extends Object> = Solo<T> with SoloStream;`. Code that goes on to
  call `run` on it from outside needs the next entry as well. Migration:
  `extends SoloBase<S>` becomes `extends Solo<S>`; a controller that read
  `.stream` adds `with SoloStream`, the type argument inferred from the
  superclass; a field or parameter typed `Solo<S>` that reads `.stream` becomes
  `SoloStream<S>`, and there the argument is written out -- the analyzer does
  not ask for it, and a bare `SoloStream` is a `SoloStream<Object>`;
  `SoloBase.observer`, `.errorHandler` and `.debug` become `Solo.observer`,
  `.errorHandler` and `.debug`.

- **Breaking:** `job`, `add`, `run`, `collect` and `accumulate` are
  `@protected`. A controller's operations are its own methods, such as `load()`
  or `setZoom()`, and those are what a caller sees; the five members they are
  built from belong to the controller, as `externalSetState` and `queue`
  already did. The analyzer reports a call from outside the class as
  `invalid_use_of_protected_member`; the code still compiles and runs as
  before. Migration: give the controller a method for each operation called
  from outside, and call that. A controller that is a queue for jobs somebody
  else writes reopens what that code calls with an override that forwards to
  `super` and leaves the annotation off: `@protected` does not carry over to an
  override.

- **Breaking:** `Policy.droppable` compares the result types of the two jobs
  with each other, instead of matching the one it found against the type
  argument of the call. `void` is a top type, so the old check said yes to
  every job there is: a `Job<void>` added under a key a `Job<String>` held was
  dropped as an ordinary duplicate and `add` handed back the `Job<String>`
  typed as `SoloJob<void>`, so the work the caller asked for never ran and the
  handle it holds is somebody else's. A supertype was waved through the same
  way -- a `Job<Object>` on a key held by a `Job<String>`. Both throw
  `ArgumentError` now, and, as before, they throw before the new job is taken,
  so the refused handle is untouched and can still be added. A closed
  controller never reaches the check: there the job finishes with
  `Cancelled(closed)`, as it did before.

- **The comparison is of the types as written**, so a key shared by two
  spellings of one thing throws where one direction of it used to pass:
  `Job<dynamic>`, `Job<Object?>` and `Job<void>` against each other, the same
  inside an argument -- `List<Object?>` against `List<dynamic>` -- and
  `Job<int>` against `Job<int?>` or `Job<FutureOr<int>>`. Watch for the pair
  inference makes on its own: a body that returns nothing gives `Job<Null>`
  where the call writes no types and `Job<void>` where the method's return type
  says so, so one operation spelled both ways under one key is a collision now.
  Writing the arguments out -- `run<Ready, void>` -- is what keeps the answer
  from depending on how a call was spelled.

- **Breaking:** `collect` and `accumulate` default to
  `AccumulationPolicy.join`, not `adjacent`. A job of another kind queued
  between two events is no longer a boundary: the events are one group, where
  the group already stands in the queue. The old default made the same two
  events one group or two depending on what else the controller happened to be
  doing at that moment, which is a decision no caller made, and under a
  `timing` it also cost the second group a whole interval.

- **Staying on `adjacent`.** Name it explicitly where the boundary is the
  point: where `merge` throws away what it replaces and a job queued between
  two events has to run between them — a transport control that keeps only the
  last command is the case — or where such a job changes what the accumulated
  input means. Everywhere else the default is what the call already wanted. A
  call that names a policy today is unaffected.

- **Breaking:** `AccumulationPolicy.replace` moves the waiting group's job to
  the tail instead of building a new job and cancelling this one. Every event
  of one group now shares its handle and outcome under every policy: five
  events into a busy queue give one handle and one `Done`, where they used to
  give five handles and four
  `Cancelled(manual, 'replaced by accumulated group')`. The grouping and the
  moments a group starts are unchanged; what changes is the handle and the
  outcome of the events that used to be replaced. `cancellable: false` no
  longer means anything here -- a move is not a removal -- and the cancellation
  callbacks that used to run in the middle of a replacement do not run at all,
  so a group can no longer be cancelled or closed from inside another event's
  `add`. The engine's debug trace says `move <job> to the tail` where the
  observer used to see a job dropped.

- **Migrating.** Code that waits on the handle an `add` returned keeps working
  and now sees the group's real outcome. Code that treated
  `Cancelled(manual, 'replaced by accumulated group')` as "mine was pushed out"
  has nothing to react to any more: the event was not pushed out, it is in the
  group. Code that held an earlier handle and compared it with a later one to
  detect a replacement has nothing left to compare: there is one handle per
  group now, and its outcome is the group's.

- `AccumulationTiming.throttle` takes `startAtOnce`. With `startAtOnce: false`
  the interval is counted before the first group as well: an accumulator with
  nothing of its own queued or running starts its interval where the group
  appears, and the group runs when the interval ends, carrying everything
  written meanwhile. The default is unchanged, and so is everything else about
  the mode -- a running interval is never restarted, so a group that has waited
  its interval out and needs only the execution slot is not pushed back by a
  later event. Take it where the rate matters more than the latency of the
  first event; the cost is that a single event waits the whole interval, and a
  draining `close` waits with it.

- **Breaking:** the state of a closed controller is final. Once the engine has
  finished closing, `externalSetState` throws a `StateError` where it used to
  change `currentState` and call the change hooks with nobody left to hear them
  -- the listeners were gone and a closed stream dropped the event, so the
  state moved in silence and every reader had to choose for itself between the
  last thing it was told and what the controller holds now.

- **Breaking:** `Solo` gains `isFinished`, the guard a subclass checks before
  feeding an external fact. `isClosed` will not do: it is true from the first
  line of `close`, so guarding with it starves a `SoloCloseMode.drain` of the
  very facts the queue it is running still needs. The line is where the
  listeners are dropped, not where the future `close` returns completes: a
  paused stream subscription holds that future open long after the engine is
  done. Check it after the last `await` -- a suspension between the check and
  the write lets the engine finish in between. The documented order changes
  with it: a source is no longer stopped before `super.close()`, it is guarded
  and cancelled afterwards, which is the one order that serves both close
  modes. Adding a member to a class meant to be extended is breaking on its
  own, and this name is not a free one: `Job` in `async_job` already has
  `isFinished`, and a controller that drives a download or a sync is where a
  subclass would most likely have spelled it the same way.

- **Migrating a subclass.** A terminal state set after closing has to move:
  write it before `super.close()`, or synchronously from the observer's
  `onClose`, which still reaches the listeners. After `await super.close()`
  there is nowhere left to put it. And if the subclass already has an
  `isFinished` of its own that happens to be a `bool` -- a download that is
  complete, a sync that is done -- it keeps compiling, which is the dangerous
  case: the member now overrides the engine's, every `if (!isFinished)` in the
  subclass answers from the domain flag, and the engine, which checks its own
  private state, goes on refusing the write. Rename the domain one. A member of
  another type fails to compile instead, which is the easy case.

- `doc/vs-bloc.md` is rebuilt around the mistake. Every one of the eleven
  scenarios now opens with "The first attempt" — the code the requirement
  invites, and the proof that it does not hold — before the implementation that
  does. Leaving a loading state on cancellation, which used to trail section 3
  as an unnamed second half, is a scenario of its own. Nine of those attempts
  are new runnable snippets: two registrations with a transformer each, one
  registration with none, a chat handler without its `isClosed` guard, a player
  with a registration per command, a player with one queue and no replacement,
  a leaving flag instead of a screen generation, `droppable()` with a completer
  that nobody completes, one funnel for a failure that must not wait, a
  restartable loop without `emit.isDone`. Section 1 also quotes the order of
  execution, so that the lost note is explained by what happened rather than
  asserted.

- Two stale snippets in `doc/vs-bloc.md` fixed: the recorder and the telemetry
  observer still overrode `onChange(previous, current)` and no longer compiled
  against the hook's new `SoloTransition`.

- `doc/children.md` adds what a chain costs on a controller: inside a body
  `ctx.run` takes jobs of that controller alone, so a continuation is turned
  away there as a job of nobody's; and the queue does not wait for a tail — the
  slot is freed when the root job finishes, and the next queued job starts
  while the continuation still has to run.

- **Breaking:** `Solo` carries its own listeners: `addListener` and
  `removeListener`, and the protected `hasListeners` and `onListenerError`
  beside them. A controller is now observable without a delivery of its own,
  which is what a widget or another package's binding needs; `SoloStream` keeps
  its stream and notifies listeners before it. Adding members to a class meant
  to be extended is breaking on its own: a subclass with a member of one of
  those names stops compiling. Notification is synchronous and in subscription
  order, one call per registration; a listener that throws is reported through
  `onListenerError` -- the zone by default -- and the pass goes on, because an
  error escaping `publish` would cost a running job the cancellation the new
  state owes it. Listeners are dropped when the engine finishes closing, right
  after the observer's `onClose` -- which is not the same moment as the future
  of a subclass's `close` completing: a paused stream subscription holds that
  future open long after the engine is done -- and a registration made after
  that is ignored rather than retained.

- `doc/state.md` says what the listeners are and what is left for `publish`.
  "Observing state" now shows `addListener` beside `currentState` and the
  stream, and names what the engine promises: the order, the `==` that
  `removeListener` matches on, the error that goes to `onListenerError` without
  stopping the pass, and the drop at close. "A delivery of your own" is about
  the other kind of delivery — a stream, a signal, a line in a log — and what
  such an override owes.

- **Breaking:** the controller's synchronous read is `currentState`, not
  `state`. A job body is a closure inside a method of the controller, so every
  member of the controller is in scope there, and a read named `state` looked
  exactly like the checked `ctx.state` while doing none of its work: no
  `Cancelled` for a job that had lost the state, no `keepWhile` check, and the
  whole of `S` instead of the job's working type `W`. Under the new name that
  mistake is a compile error. Reads through the context, the `state` parameters
  of `canStart`, `keepWhile`, `onError` and `onCancel`, and `externalSetState`
  are unchanged. No deprecated alias is kept: one that still compiled inside a
  body would leave the hole open.

- A recipe for `doc/errors.md`: why cancellation was slow. An observer that
  stamps the clock in `Job.whenCancelled` and subtracts in `onFinish` reports
  how long a job ran past its cancellation — 290 ms against 0 on a 300 ms wait
  cancelled 10 ms in, which is the difference between a bare `await` and the
  same call through `ctx.wait`. `SoloPending` reports while the wait is on;
  this reports once it is over, where nobody is watching. The count starts when
  the cancellation takes effect, not at `cancel()`: the rest of an open
  `ctx.uncancellable` section is not counted, though the caller of `cancel` or
  `close` waits for it. A job dropped before it started is not reported at all.
  The stamp lives in an `Expando`, so it goes with the job and there is nothing
  to clean up. No API was added: the hooks it needs were already there.

- The README is a starting page again: what the package is, `Install`,
  `Quick start`, `The dozen calls` — one controller holding everything reached
  for day to day — and a map of the guides. The reference material it grew over
  the releases moved to `doc/`, one page per subject: `jobs.md`, `state.md`,
  `cancellation.md`, `resources.md`, `children.md`, `errors.md`, `testing.md`,
  `camera.md`. The Flutter section went to the package it is about: the README
  of `flutter_solo` and its `doc/mixins.md`. Nothing was dropped; the bloc
  correspondence table now opens `doc/vs-bloc.md` and the accumulation API
  opens `doc/accumulation.md`.
- Every page in `doc/` starts with the code it is about, and the rules that
  lived only in prose became tables: handler eligibility, where a throwing
  state rule is heard, what each waiting method does to the operation behind
  it. The sections that had no code at all — external state, closing a
  controller, protecting a step, background work — have it now, compiled and
  run before it was written down.
- Document what a job key can be: any object compared with `==`, so a record
  gives a policy the identity of one request — `(_Op.load, id)` — rather than
  of the operation.
- Document what `add(first: true)` passes: the queue, and nothing else. A
  replacement queued by `Policy.restart` waits at the tail like any other job,
  so a job added `first` after it starts ahead of it — cancelling the running
  job does not reserve the slot after it.
- Document commands where only the last one counts, in `doc/accumulation.md`: a
  burst that cancels itself out never becomes jobs to take back, and what to do
  when they are separate jobs after all. A recipes table in the README points
  at this and at nine other situations.
- **Breaking:** `Solo.close` takes a `SoloCloseMode`. Calls are unchanged — the
  default is `SoloCloseMode.cancel`, which is what `close` always did — but an
  override of `close` has to take the parameter too. `SoloCloseMode.drain`
  closes by running what is already queued instead of dropping it: no new root
  job is taken from the call onwards, and the ones accepted before it go by the
  usual rules, children, cleanup and accumulation windows included. A plain
  `close()` over a running drain stops it where it is. `Solo.isDraining` says
  whether one is running. Running the queue is not a promise of delivery: a
  buffer that keeps events until the sending is confirmed is built on top of
  this.
- **Breaking:** the change hooks take a `SoloTransition<S>` instead of a pair
  of states: `Solo.onChange(transition)` and
  `SoloObserver.onChange(solo, transition)`. Beside `previous` and `current` it
  carries `job` — whose `emit` made the change, `null` for an
  `externalSetState`, and a child rather than the root it belongs to — and
  `revision`, which grows by one per change and orders two transitions even
  when a hook changed the state again from inside the first. The engine knew
  both and told nobody, and neither can be worked out from outside. Migration:
  `previous` becomes `transition.previous`, `current` becomes
  `transition.current`.
- Add `Solo.pending`: a `SoloPending` snapshot of the job the controller is
  waiting for — its phase (body, children or cleanup), the cancellation it
  carries, the one a `ctx.uncancellable` section is holding back, whether such
  a section is open, and whether it was created `cancellable: false`. For a
  `close` that has not come back. It reports what the engine knows: a body
  waiting on a bare `await` is in its body, an open section is an open section
  until somebody asks, and the snapshot does not guess at why.
- **Breaking:** setting `Solo.observer` no longer takes an error with nowhere
  else to go off its default route to the zone. Watching is not answering: an
  observer set for a log used to switch reporting off for the whole process
  without saying so. `Solo.errorHandler` is the new seam that answers for such
  an error — one handler for the process, set once at startup — and with nobody
  set there the error reaches the zone the job was created in, observer or no
  observer. An observer that used to rely on the old silence now needs
  `errorHandler` set as well.
- **Breaking:** `Policy.droppable` throws `ArgumentError`, not `TypeError`,
  when the key it finds belongs to a job of another result type — and it throws
  before the new job is taken, so a job refused this way is untouched and can
  be added again under a key of its own. It used to finish the new job as a
  duplicate first and then refuse to hand anything back, leaving the caller
  with an error and no job at all.

- **Fix:** `close(mode: drain)` finishes when the last job is taken off the
  queue, not only when one is run off it. A group waiting for its accumulation
  window keeps the queue full with nothing running, and taking it away --
  `cancelAll`, `queue.remove`, `queue.clear`, or `cancel()` on the group's own
  handle -- left a controller closed, draining and never finished: the pump
  that ends a drain is woken by a job finishing, and the job that emptied the
  queue had never started. In Flutter that is a `dispose()` that does not
  return, with `pending` empty and no error anywhere; a second, plain `close()`
  was the only way out.

- **Fix:** `Policy.droppable` no longer hands back a job that is not going to
  do the work. The current job stays current for the whole of its unwinding and
  for the state handlers after that, so `cancelAll()` and a fresh request a
  line later -- a screen left and opened again, a pull-to-refresh -- answered
  the second call with the handle the first had just cancelled: a `Cancelled`
  outcome for a request made a moment ago, and the operation never ran.
  `lastJobWhere`, the protected form of the same search, answers by the same
  rule, so a subclass that used it to find "the job already doing this" gets
  `null` in that window instead of a job that will not.

- **Fix:** a drain takes the accumulation timers down with it. `close()`
  cancelled every timing timer where `close(mode: drain)` cancelled none: an
  interval timer outliving the controller holds its accumulator, and the
  accumulator holds the controller. In a widget test that is "A Timer is still
  pending even after the widget tree was disposed" for somebody who only closed
  a controller. Both ways of closing end in one place now, and the timers go
  down there.

- **Fix:** a `publish` that throws no longer loses the changes queued behind
  it. The change it failed on is gone either way -- it left the queue before
  the call, and nothing publishes a change twice -- but the ones behind it are
  the state `currentState` already holds, and they stayed in the queue for
  good: no listener and no stream saw them, then or after closing. The queue is
  drained to the end now, the first failure leaves once it is, and the ones
  after it go where a failing hook's error goes.

- **Fix:** a finished job lets go of its body, of its state handlers and of the
  job that ran it, the way the core lets go of its own. Held on, one handle
  kept in a field -- what `ctx.each` hands back, what `Policy.droppable` hands
  back, what a widget keeps to read an outcome later -- held the whole tree of
  finished jobs it came out of and everything that tree had captured. The rules
  stay: a context that leaked out of a body reads the state through `keepWhile`
  long after the outcome, and the cancellation it builds out of a rejection is
  the whole diagnosis it has to offer.

- Add `Solo.onClose`, the twin the observer's `onClose` did not have. The
  engine calls it once -- whatever mode closed the controller and however many
  times `close` was called -- after the observer's `onClose` and after the last
  job, while `isFinished` is still false. It is where a controller stops what
  it holds beside its jobs, a subscription to a source it reflects above all,
  and the `Camera` of `doc/state.md` stops its link there now. The page used to
  do that in an `async` override of `close`, after `super.close()`: the moment
  was right, but every call ran the override again and handed back a future of
  its own, where `close` promises the same one. `doc/vs-bloc.md` points its
  controller at the hook too.

- `doc/cancellation.md` opens with a `join` that hands the device it opens to
  `dispose`. The opening example registered the release on the line after the
  call, and a cancellation accepted while the device was opening left it open:
  `join` throws in place of the value, and the body never reaches that line.
  `doc/resources.md` takes the same line apart as a first attempt; the
  introduction no longer teaches it.

- `Solo.pending`, `SoloStream.close`, `doc/errors.md` and `doc/state.md` say
  when a close waits with nothing pending. `null` means that no job is running,
  and a close can wait without one: a drain waits for a group of `collect` or
  `accumulate` its timing still holds in the queue, and the stream of
  `SoloStream` closes after the engine and waits for a subscription left
  paused, with `isFinished` already true. The recipe that logs `pending` on a
  slow close printed `null` for both and said nothing of why.

- **Breaking:** `SoloQueue.lastWhere` is gone. `Solo.lastJobWhere` finds the
  same job and looks at the running one as well, so the queue had a second way
  to ask one question. Migration: `queue.lastWhere(test)` becomes
  `lastJobWhere(test)`, or `queue.jobs.lastWhere` where only the queue should
  answer.

- `cancelAll`, `SoloQueue.remove`, `removeWhere` and `clear` take a `reason`.
  Every job they end carries it, so a policy of the domain that clears the
  controller can tell its cancellations from a user's; without one it is
  `ManualCancelReason`, as before. An implementation of `SoloQueue` of its own
  has to take the parameter too.

- Add `Solo.traceStateChanges`. A change of state recorded its stack trace
  every time, which cost most of what the change costs, for one reader: the
  trace of a job its rules cancel. The record is now taken where assertions are
  on -- in development and in tests -- and the flag turns it on in a release
  build or off everywhere. Without it that trace is taken where the rules
  noticed; for a change that cancels a running job that place is inside the
  change, so the trace still leads back to it.

- `Policy` and `doc/jobs.md` say what a policy looks at: the queue and the root
  job the controller is running. They promised "queued or running", and a child
  running under the same key is running without being seen -- it runs inside
  another job and never went through the queue.

- **Fix:** `cancelAll` and `close` reach the job the engine is about to start.
  Between taking a job off the queue and launching it the engine asks that
  job's start rules, which are the caller's code, and a rule that cancelled
  everything or closed the controller was answered with the very job it had
  just stopped: the queue no longer held it and nothing else did yet, so it
  started anyway. It is queued work until it is launched, and a
  `cancellable: false` one turns down a `cancelAll` without `force` exactly as
  it does in the queue.

- **Fix:** a listener's failure survives an `onListenerError` that throws. The
  hook is where a listener's error is reported, and one that threw instead took
  that error with it -- the zone heard about the broken reporter and never
  about the listener. Both now reach the zone, the listener's first.

- **Fix:** `SoloQueue.removeWhere` and `Solo.lastJobWhere` take their snapshot
  of the queue before asking the predicate rather than while asking it. The
  predicate is the caller's code, and one that removed a job walked into a
  `ConcurrentModificationError` on the list it had just changed.

- Add `package:solo/listeners.dart`: `Listeners`, the list of listeners a
  notifier walks, for a package that builds a delivery of its own on top of
  `solo`. An application does not need it -- a controller's listeners are
  behind `addListener` -- and `flutter_solo` no longer keeps a copy of the
  mechanics to serve `SoloSelection`.

- `SoloTransition.job` says what it holds: the job the change belongs to. It is
  usually the job whose `emit` made the change, and a state returned by that
  job's `onError` or `onCancel` handler is its change as well, although by then
  its body has ended and emitted nothing itself.

- `doc/cancellation.md` no longer promises that a `whenCancelled` registered
  after a cancellation always fires on the spot. It does once the cancellation
  has been announced; one made while the cancellation is still cascading onto
  the children joins that announcement in its own place, which is what the
  dartdoc of `whenCancelled` has been saying.

- `doc/errors.md` says what an overridden error hook replaces. The default body
  of `Solo.onError` is the route to `Solo.errorHandler`, and to the job's
  creation zone when no handler is set, so a hook that reports and returns
  takes those errors nowhere else -- the page's own example now calls `super`.
  The page also corrects what it said about `Cancelled`: one that arrives as a
  late failure from an abandoned action does reach the reporting hooks, and it
  is the zone that never sees it. It adds `Solo.traceStateChanges`, which was
  documented nowhere in prose, notes that reading `job.outcome` does not mark
  an outcome observed where `done`, `value` and `ignore()` do, names
  `onListenerError` among the hooks a controller can override, and no longer
  implies that `package:clock` comes for free with `fake_async` in an
  application that ships the observer.

- `doc/errors.md` opens six of its sections with the version its own vocabulary
  leads to, and puts the one that works under the next heading: the hook that
  reports and returns, an observer that times a job instead of its
  cancellation, an observer that reports a failure nobody answered for, a broad
  `catch` that takes the cancellation along with the device failures, a rule
  that throws to refuse, and a bare `unawaited`. Reporting and the observer get
  a section each, where they used to share the page's introduction. The section
  on rules now says what a throw costs: the error goes to the reporting hooks
  and, unless somebody observes the outcome, to the creation zone, and the
  `onError` of that same `run` corrects nothing, because the job never started.

- `doc/testing.md` opens each of its eight sections with the version the
  vocabulary of the API and of `package:test` leads to, and puts the one that
  works under the next heading: an assertion right after the call, `close()` as
  the way to let the work finish, a failure nobody reads, two calls in one turn
  taken for a running job and its duplicate, `await` inside `fakeAsync`, a
  reset on the last line of the test, `expect` inside `runZonedGuarded`, and
  `Future.timeout` on the call. The page used to be two sections with none of
  them. It now shows the controller and the fake it tests, says which tests
  await real time and which run on the fake clock, how a static with a default
  of its own is put back, and that a job dropped as a duplicate reaches only
  `onFinish`.

- The runnable camera example lands a failed or cancelled opening in `Broken`
  through the `onError` and `onCancel` of `run`. `init` and `reopen` used to
  catch the failure in the body, and a cancellation passed through that catch
  with its `emit` refused: an opening cancelled half way left the camera in
  `Preparing`, where neither of them could start again. `dispose()` no longer
  forces the queue clear. An earlier disposal still in the queue survives it,
  and a second call gets that same job back instead of cancelling it under its
  caller.

- `doc/camera.md` opens its sections with the version the API's vocabulary
  leads to: a working type named after the starting state, a landing written as
  a catch, a zoom with no policy, a disposal queued like any other job, a
  `close()` in the same turn as `dispose()`, and a hardware listener left in
  place through the disposal. The last fragment of each method is the example's
  code, and the example's tests hold the page to it.

## 0.2.0

The first published release. 0.1.0 never left the tree, so nothing below is a
migration anybody has to make; what changed since it is at the end, for a tree
that followed the package before it went out.

- Add `onError` and `onCancel` state handlers to `run` and `job`. They apply
  state after children and cleanup, before the next queued job, while
  preserving the failed or cancelled outcome. Incompatible external state
  changes suppress correction, including during cleanup and for descendants.
  The quick start now uses sealed loading/result/error states.

- Add `AccumulationTiming.debounce` and `.throttle` to `collect` and
  `accumulate`. Debounce seals a group after a pause between events; throttle
  spaces actual group starts. Waiting groups let ready jobs pass, while
  handlers, children and cleanup remain sequential. `collect` retains every
  event; `accumulate` retains the `merge` result. Closing cancels timing timers
  and queued groups without a final batch.

- **Breaking:** `ctx.run(child)` returns the child's result as `Future<T>`.
  Replace `await ctx.run(child).value` with `await ctx.run(child)`; keep the
  original child handle to cancel it or inspect its outcome. After success,
  `run` checks the parent's cancellation and state rules before returning.
  Concurrent starts must handle or explicitly ignore the returned future.
  Controller `run` and `ctx.each` still return job handles immediately.

- Add `collect` and `accumulate` factories returning `SoloAccumulator`: gather
  events in a list or merge them into one value before execution.
  `AccumulationPolicy` selects adjacent grouping, replacement at the queue's
  tail with data transfer, or joining an existing queued group. Groups use
  ordinary `SoloJob` lifecycle, state rules and cancellation.
- Re-export `Job.then` and `ChainCancelReason` from the core. Continuations
  support cancellation chains and have their own `JobContext`; they do not
  inherit controller state, rules, observers or a queue slot.

- `SoloBase<S>` engine: one root job at a time, exclusive state ownership.
- `Solo<S>` with a broadcast `stream`, delivered on the next microtask.
- Jobs as `async` bodies with a working type `W`, `canStart` and `keepWhile`
  rules, `cancellable: false`.
- Keep a replacement cancelled by a synchronous listener out of the queue, so
  it cannot absorb a later `droppable` job.
- Requires `async_job: ^0.2.0`: `job.whenCancelled(callback)` registers a
  synchronous listener receiving `Cancelled` and returns an unregister
  function.
- `Job<T>` handle: `done`, `value`, `outcome`, `whenCancelled`, `cancel`,
  `ignore`.
- `Outcome<T>`: `Done`, `Failed`, `Cancelled` with `CancelReason`.
- A `Failed` outcome nobody observed goes to the zone that created the job, the
  way Dart reports an unhandled `Future` error. Reading `done` or `value`, or
  calling `ignore`, counts as observing it; `Cancelled` never reaches the zone.
- `JobContext` of the kernel: `check`, `wait`, `join`, `uncancellable`,
  `unattended`, `onCancel`, `run`, `each`, `log`.
- `SoloContext<S, W>` on top of it, where the state lives: `state`, `stateAs`,
  `emit`.
- A body does not `await` on its own: every call goes through the context, and
  the member it picks says what a cancellation does to that call. `wait` ends
  the waiting and lets the action run on; `join` waits for all of the action
  and gives up afterwards, so a device call is never left mid-flight;
  `uncancellable` holds the cancellation for the length of the call and gives
  up once the step is over; `unattended` does not wait at all and hands the
  work to the engine, which hears it fail even after the job is over.
- `ctx.unattended(action)` for work a body starts and does not wait for. It
  runs in an error zone of its own, and whatever it leaves uncaught — now, or
  long after the job is over — reaches `onError` instead of the process.
- **Behaviour change.** With no `SoloBase.observer` and no override of
  `SoloBase.onError`, an error with nowhere else to go no longer stops in the
  empty hook: it goes to the zone the job was created in, the way the core
  reports one when a job has no observer. That covers a disposer, an `onCancel`
  callback, a late failure of an abandoned call or of unattended work, and a
  `canStart` or `keepWhile` that threw instead of answering while the job runs.
  A `Cancelled` is the one exception and never goes there. Install an observer,
  or override the hook, and the route is yours again; call `super.onError(...)`
  from the override to keep it. A rule that throws *before* the job starts is
  not on this route at all: it becomes a `Failed` outcome and reaches the zone
  as any unobserved failure does, whatever the observer.
- A cleanup stack instead of a `finally` in the body: `ctx.onDispose` releases
  whatever the outcome, `ctx.onDiscard` only when the value reaches nobody, and
  `wait` and `join` take the same two as `dispose` and `discard` for the value
  they hand over — a connection or a file an abandoned action opened is still
  closed. The engine unwinds the stack after the children and before the
  outcome, and `close` waits for it; `ctx.disown(value)` takes a registration
  back when the body hands the value over itself.
- `JobContext.uncancellable` is `wait`'s counterpart: it runs a step that
  cannot be taken back — a payment on its way to the server — with the
  cancellation held until the step is over, and `close` waits for it.
- **Breaking:** `ctx.each(stream, (child, event) { ... })` returns a child
  `Job<void>` immediately. Await `.value` for a throwing result, inspect
  `.done`, or cancel the subscription separately through `.cancel()`. The
  callback receives a `SoloContext<S, W>` retaining the parent's working type
  and `keepWhile`, without inheriting `canStart`. The parent waits for this
  child even without an explicit await, and observers see the child. Parent
  cancellation cascades to it.
- Cancelling `each` removes the subscription immediately, then waits for the
  running callback before child completion and cleanup. Use child context
  checkpoints to respond to cancellation; a plain `await` can delay
  cancellation and `close()`. Source cleanup from subscription cancellation is
  still not awaited. `each` is now a context method and follows `run`'s
  restrictions on when and where children can start.
- `JobContext.onCancel` hands a cancellation to something that can really
  stop — a device's cancel token, an HTTP abort. `wait` ends the waiting, not
  the work.
- Child jobs via `ctx.run`; a parent finishes after its children.
- `SoloQueue` with `remove`, `removeWhere`, `clear`, `lastWhere`; policies
  `sequential`, `droppable`, `replace`, `restart`.
- `externalSetState` for hardware listeners; every change re-evaluates the
  rules of running jobs.
- `SoloObserver` and instance hooks; `SoloBase.debug` engine tracing.
- A hook that throws changes nothing: the engine hands its error to the current
  zone and carries on, and the hook next to it is still called.

### Since 0.1.0

- The job kernel now lives in `package:async_job` and is re-exported whole:
  `package:solo/solo.dart` stays the only import. Code using the old reason API
  must migrate to the reason classes. The job's lifecycle, context, outcomes
  and observer moved to the kernel; the state, queue and rules stay in `solo`.
- `CancelReason` is an extensible class hierarchy: `ManualCancelReason`,
  `ParentCancelReason` and `HandlerCancelReason` from the core, plus
  `RulesCancelReason` and `ClosedCancelReason` from `solo`. Inspect types;
  `name` is only a log label, with no equality by name. Custom subclasses can
  carry arbitrary data through `job.cancel(reason: reason)`. Parent and child
  propagation retain the original cancellation in `cause`.
- `Cancelled.by({reason, started, description, stackTrace})` is public: an
  engine of a domain builds cancellations with a reason of its own.
- `JobContext<S, W>` is renamed to `SoloContext<S, W>`, and the name
  `JobContext` now belongs to the interface of the kernel: cancellation, the
  waiting family and children, without the state. `SoloContext` implements it
  and adds `state`, `stateAs` and `emit`. Job bodies do not write the name, so
  code written against the README keeps compiling.
- The job and its context are split along the seam the kernel will be taken out
  at: `JobBase<T>` and `JobContextBase` carry the lifecycle, the waiting
  family, the children and the outcome, and the solo subclasses add the state,
  the rules and the queue. Nothing moves in the public API of a controller.
- The list of children a job waits for now shrinks as they finish: a long-lived
  job starting children in a loop no longer grows one entry per child. The
  description of a parent's own outcome is unchanged — the link from an outcome
  to the child that carried it lives in an `Expando`, so a child without a key
  still shows in it.
- A value a body returned after its cancellation had already arrived is
  released rather than dropped: the body registers it on the cleanup stack, the
  outcome stays the cancellation, and `close` waits for the release.
- A job says who may adopt it: `ctx.run(child)` refuses a job of another
  controller with `ArgumentError` and a job still waiting in the queue with
  `StateError`, and a job of `solo` is refused by a context of the bare kernel.
  A child without an observer of its own inherits the parent's.
- `JobBase.debug` traces the life of a job, `SoloBase.debug` the queue, the
  state and the closing. Set both to follow both.
- `JobObserver` is the observer of a single job: `onStart`, `onFinish`,
  `onError` and `onLog`, without the controller in the signatures. A controller
  feeds its own `SoloObserver` and its instance hooks from it, so nothing
  changes for a user of `solo`.
- `isQueued` moves from `Job<T>` to the new `SoloJob<T>`, returned by `job`,
  `add` and `run`. The queue is the controller's, not the job's. `JobStatus` is
  public and has three values: a queued job is `created` until it starts, and
  `isQueued` is computed from the queue itself — inside `canStart` a job taken
  from the queue is no longer queued.

## 0.1.0

Never published.
