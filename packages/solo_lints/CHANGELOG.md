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
