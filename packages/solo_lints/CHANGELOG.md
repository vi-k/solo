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
