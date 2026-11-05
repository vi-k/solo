## Unreleased

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
