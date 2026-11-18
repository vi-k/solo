## 0.3.1

- Requires `async_job_lints` 0.2.3. `await_own_queue` and `stale_emit` no
  longer report `close()` or `emit` in the child of a job that a `SoloLanes`
  hands to a `Solo`: the child runs in that `Solo`. `await super.close()` and
  `await super.cancelAll()` in a job body are reported as `await close()` is,
  and a body given to `super.enqueue(...)` counts as queued here.

## 0.3.0

- Two new rules for the lanes of `SoloLanes` in `solo` 2.0. `stale_emit`, a
  lint, reports `ctx.emit` in a job of a `SoloLanes` that writes a value built
  on the state as the job read it before an `await`: the other lanes write
  while the job waits, and the copy goes over what they wrote. It is a
  heuristic, and it does not see the answer of a server written whole, which
  loses those writes as well. `lane_outside_constructor`, a warning, reports
  `lane(...)` of `SoloLanes` called anywhere but right in a constructor body,
  as in a `late final` initializer or a method, where it throws once the set of
  lanes is sealed. The warning is on as soon as the plugin is named, so
  `dart analyze` fails on code it passed before, and the release is a minor
  one. The README describes both rules. They require `async_job_lints` 0.2.2,
  which exports what they ask of it.

## 0.2.1

- `await_own_queue` knows the lanes of `SoloLanes` in `solo` 2.0. It reports a
  job that waits for a job of the lane it runs in, queued by
  `_likes.enqueue(...)` or by a method that queues in `_likes`, from a body
  queued in `_likes`, and names the lane. A wait for another lane is no
  deadlock and stays with `bare_await`, as does a wait where the lane is not
  seen: a lane from a getter, a lane the controller takes rather than declares
  by `lane(...)` in its constructor body, a lane declared in another file (a
  superclass there or another part of the library), a job from a field or a
  parameter, a body of a child or a handler of an accumulator. `close` and
  `cancelAll` are reported for any controller, `SoloLanes` and a controller
  with `SoloStream` included.
- `discarded_outcome` leaves a wait for the own lane to `await_own_queue`, as
  it leaves the wait for the own queue of a `Solo`.
- `key_per_request` and `ignore_failure_hides_bugs` take `enqueue`,
  `enqueueJob`, `job`, `collect` and `accumulate` of a lane as they take those
  of a `Solo`.
- Requires `async_job_lints` 0.2.1, which knows the lanes.

## 0.2.0

- The two new warnings of `async_job_lints`, `discarded_outcome` and
  `outcome_after_await`, come with it: an outcome of `done` that is awaited and
  dropped, and the first read of a job's result that comes after a wait. They
  are on as soon as the plugin is named, so `dart analyze` fails on code it
  passed before, and the release is a minor one. The README lists them among
  the seven rules of the core.

## 0.1.5

- The five rules of the core, `ctx_in_cleanup`, `release_on_the_call`,
  `catch_without_check`, `sync_fake_async` and `bare_await`, come from the new
  package `async_job_lints`, for code on async_job alone. This plugin includes
  them under the same names, so `diagnostics:` and `// ignore:` stay as they
  are. Their changes are listed in the changelog of `async_job_lints`. The ids
  of the quick fixes of `release_on_the_call` and `catch_without_check` begin
  with `async_job_lints.fix.` instead of `solo_lints.fix.`, so an editor
  binding that names an old id needs the new one. Name one of the two plugins,
  not both.
- The README describes the package as the plugin for solo and flutter_solo, and
  the rules of the core link to the README of `async_job_lints`.
- The package has an example: a recorder with three mistakes, the lines the
  plugin reports and the same job fixed.
- `pubspec.yaml` names the documentation site, and pub.dev links to it.
- The blocks of the README ask for this version.

## 0.1.4

- The tests run against async_job and solo 1.0.0; the rules have not changed.
- The README no longer names `wait` among the members of the context, since
  async_job 1.0 has no `ctx.wait`. Its Versions section says that the rules
  still know `wait`, the name of `abandonable` before 1.0.
- The blocks of the README ask for this version.

## 0.1.3

- The README links to the page of the package on the documentation site.
- The README says that `dart analyze` shows the diagnostics of the plugin on
  the root of the package or on single files, but not on a folder below the
  root, such as `lib`.

## 0.1.2

- The README no longer says that `flutter analyze` reports the diagnostics of
  the plugin: from Flutter 3.44 on it shows none of them, and a Flutter package
  runs `dart analyze` for the plugin.

## 0.1.1

- `bare_await`, a lint: an `await` in a job body that waits past the context,
  so a cancellation of the job does not end the wait, and an `await for` that
  reads a stream past `ctx.each`. It is quiet in cleanup, in the actions of
  `join` and `uncancellable`, in `unattended` work, in `finally`, in a body
  made with `cancellable: false` and on a release right after `ctx.disown`.
- The README says how to raise a rule to a warning, that `dart fix` does not
  apply the quick fixes of a plugin, and that Dart 3.12 prints each diagnostic
  of the analyzer twice in a package that names a plugin.

## 0.1.0

Initial release. An analyzer plugin for code built on `async_job` and `solo`,
for Dart 3.10 and later.

- `ctx_in_cleanup`, a warning: a waiting member of the context called in
  cleanup, where it throws `StateError`.
- `release_on_the_call`, a warning: a release registered on the line under the
  call that brings the resource, where a cancellation loses it.
- `catch_without_check`, a lint: a broad catch in a body that acts before
  asking the job whether it was cancelled.
- `sync_fake_async`, a warning: an `async` callback of `fakeAsync` or
  `FakeAsync.run`.
- `await_own_queue`, a warning: a job of a `Solo` controller that waits for a
  job queued on the same controller, or for its `close()` or `cancelAll()`.
- `key_per_request`, a lint: a `Policy.droppable` job whose key reads no
  argument while its body does, so a later caller gets the result of the first.
- `ignore_failure_hides_bugs`, a lint: `ignoreFailure()` on a job that names
  its expected errors in `isExpectedError`, which hides the bugs the predicate
  lets through.
- Quick fixes for `release_on_the_call` (the release moves into `dispose:` or
  `discard:` of the call), `catch_without_check` (`ctx.check();` becomes the
  first line of the catch) and `key_per_request` (the arguments the body reads
  go into the key).
