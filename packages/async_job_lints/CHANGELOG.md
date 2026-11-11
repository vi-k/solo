## Unreleased

- Next patch, 0.2.2, which `solo_lints` 0.3.0 requires: `plugin_api.dart`
  exports `isSoloLanes`, `controllerAround`, `declaresLane`, `callsOn` and
  `readsState`, for the rules of a plugin on top about the lanes.
  `declaresLane` tells whether a `lane(...)` on `this` or `super` declares a
  lane where `SoloLanes` lets it, right in a constructor body, and
  `queueLaneOf` takes a lane field from the same place: a field assigned from
  `super.lane(...)` is the controller's own now, as one from `lane(...)` is.

## 0.2.1

- The rules know `solo` 2.0: `SoloController`, the base of `Solo` and of the
  new `SoloLanes`, and `SoloLane`, a lane of `SoloLanes`. `outcome_after_await`
  takes `job` of a lane as it takes `job` of a `Solo`, as a job that does not
  run until it is queued.
- `plugin_api.dart` exports `isSoloController`, `isSoloLane`, `queueLaneOf` and
  `QueueLane`, and `queueCallOf` and `queuedBodyOf`, which a rule on top asks
  to agree with `bare_await` on the call a wait is for and on the body queued
  on the controller. `queueLaneOf` tells whether a wait in a job body is for
  the lane the job runs in, for another lane or not known, and `isSoloMember`
  with `Solo` takes the member of the same name of `SoloLane` too, so the rules
  of a plugin on top that name `enqueue`, `enqueueJob`, `job`, `collect` and
  `accumulate` of a `Solo` see those of a lane.
- `registerAsyncJobLints` takes `ownLaneReportedElsewhere`: with it,
  `bare_await` and `discarded_outcome` leave a wait for the own lane to the
  plugin on top. Without it, as from `solo_lints` 0.2.0, which knows no lanes,
  they report that wait as any other. `ownQueueCall` keeps its signature and
  its answers for a `Solo`, and finds `close` and `cancelAll` of a `SoloStream`
  mixed into a `Solo`.
- `bare_await` and `discarded_outcome` leave a wait for the own lane to the
  plugin on top only from a body queued in that lane, where the plugin reports
  it, and `discarded_outcome` only an awaited one: a `done` dropped without
  `await` waits for nothing. A lane field is the controller's own only when
  every write to it in its class is `lane(...)` in a constructor body: a lane
  the controller takes, from a constructor parameter, an initializer list or a
  setter, may be another controller's, though a constructor declares it too.
  For the own queue of a `Solo` both rules answer as in 0.2.0.

## 0.2.0

- Two new warnings on the result of a job, on as soon as the plugin is named:
  `discarded_outcome` reports an outcome of `done` that is awaited and dropped,
  where the failure reaches nobody, and `outcome_after_await` reports the first
  read of a job's result that comes after a wait, where the failure has gone to
  the zone before the read. `dart analyze` fails on code it passed before, so
  the release is a minor one.
- The README sends the reader for the table of the context to the reference
  page of `async_job`, where the table moved from its README.

## 0.1.1

- The message of `bare_await` and its section of the README no longer set
  `ctx.join` beside `ctx.abandonable` and `ctx.pause` as a wait that a
  cancellation cuts short, with only `ctx.uncancellable` for steps that must
  run to the end. `join` waits for the whole call and throws only after it; the
  message and the README now say what each of the four is for.

## 0.1.0

- The first release. The five rules for code on async_job, `ctx_in_cleanup`,
  `release_on_the_call`, `catch_without_check`, `sync_fake_async` and
  `bare_await`, and the quick fixes of `release_on_the_call` and
  `catch_without_check` come from solo_lints 0.1.4 and behave as they did
  there, with two changes: `bare_await` reports a wait for a job of the own
  queue of a solo controller, which solo_lints leaves to `await_own_queue`, and
  the ids of the quick fixes begin with `async_job_lints.fix.` instead of
  `solo_lints.fix.`.
- `package:async_job_lints/plugin_api.dart` registers the rules in another
  plugin, for analyzer plugins built on top of this one.
- The package has an example: a recorder on async_job with three mistakes, the
  lines the plugin reports and the same job fixed.
