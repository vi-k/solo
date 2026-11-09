# async_job_lints

`async_job_lints` is an analyzer plugin for code built on
[async_job](https://pub.dev/packages/async_job). It reports the mistakes that
compile, run and often pass a first test: a wait in cleanup that never happens,
a resource lost to a cancellation, a catch that resets a working device, a test
that never moves its fake clock, a wait that a cancellation does not end, an
outcome awaited and dropped, a result read after its failure has gone to the
zone. Each rule links to the page of async_job that shows the mistake and the
right way.

Code built on [solo](https://pub.dev/packages/solo) or
[flutter_solo](https://pub.dev/packages/flutter_solo) needs
[solo_lints](https://pub.dev/packages/solo_lints) instead: it includes these
rules and adds those of the controller. Name one of the two plugins, not both:
the analysis server resolves the versions of all plugins together, and when
they disagree, no plugin runs.

Also on the
[documentation site](https://docs.yet-another.dev/async_job_lints/), with
search.

## Install

Name the plugin in `analysis_options.yaml` at the root of the package or the
workspace:

```yaml
plugins:
  async_job_lints: ^0.1.1
```

The analysis server fetches the plugin itself, so it is not a dependency in
`pubspec.yaml`. Plugins need Dart 3.10 or later. `dart analyze` and the editor
report its diagnostics. Run `dart analyze` on the root of the package or on
single files: on a folder below the root, such as `dart analyze lib`, it shows
none of them. `flutter analyze` reports them on Flutter 3.38, but from Flutter
3.44 on it shows none of them; in a Flutter package, run `dart analyze` for the
plugin. An editor sees a change to the `plugins` section after its analysis
server restarts.

The warnings are on as soon as the plugin is named. The two lints,
`catch_without_check` and `bare_await`, are turned on by name:

```yaml
plugins:
  async_job_lints:
    version: ^0.1.1
    diagnostics:
      catch_without_check: true
      bare_await: true
```

A rule takes a severity in place of `true`: `error`, `warning` or `info`.
`bare_await: warning` turns the lint on as a warning, and `dart analyze` then
fails on it, as on any warning. `false` turns a warning off.

A diagnostic is silenced with the name of the plugin in front of the rule:
`// ignore: async_job_lints/ctx_in_cleanup` on the line above it, or
`// ignore_for_file: async_job_lints/ctx_in_cleanup` for the whole file.

The quick fixes are offered in the editor. `dart fix` does not apply them: it
applies the fixes of the analyzer itself, not those of plugins.

On Dart 3.12, `dart analyze` in a package that names a plugin prints each
diagnostic of the analyzer itself twice. Dart 3.13 prints it once.

The library `package:async_job_lints/plugin_api.dart` is for analyzer plugins
built on top of this one, such as solo_lints, and not for the code a plugin
checks.

## Rules

| Rule | Kind | Reports |
| --- | --- | --- |
| `ctx_in_cleanup` | warning | a waiting member of the context called in cleanup |
| `release_on_the_call` | warning | a release registered on the line under the call that brings the resource |
| `catch_without_check` | lint | a broad catch in a body that acts before asking the job |
| `sync_fake_async` | warning | an `async` callback of `fakeAsync` |
| `bare_await` | lint | an `await` in a job body that does not go through the context |
| `discarded_outcome` | warning | an outcome of `done` that is awaited and dropped |
| `outcome_after_await` | warning | the first read of a job's result that comes after a wait |

### ctx_in_cleanup

```dart
ctx.onDispose(() async {
  await ctx.join(() => device.flush()); // ctx_in_cleanup
});
```

Cleanup runs after the body, where `join` throws `StateError`, so the buffer
stays unflushed however the job ended. Wait there with a plain `await`. The
rule looks into the functions given to `ctx.onDispose` and `ctx.onDiscard` and
to `dispose:` and `discard:` of `join`, `abandonable` and `run`, literals, and
local functions and final variables holding a literal passed by name, and
reports the members that throw there: the checkpoints, `onCancel`, `start` and
`each`. `onDispose`, `onDiscard`, `disown`, `log` and `unattended` are left
alone. The checkpoints include those solo adds to its context, such as `emit`.
See
[Cleanup](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cleanup.md#dispose-for-what-the-job-keeps).

### release_on_the_call

```dart
final db = await ctx.join(Database.open);
ctx.onDispose(db.close); // release_on_the_call
```

A cancellation during the open throws before the second line, and the open
database is lost. Pass the release to the call that brings the resource:
`ctx.join(Database.open, dispose: (db) => db.close())`. The rule takes `join`,
`abandonable` and `run` with no release of their own, followed at once by
`onDispose` or `onDiscard` that mentions the variable. See
[Registering on arrival](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cleanup-rules.md#registering-on-arrival).

The quick fix removes the `onDispose` or `onDiscard` and passes the release to
the call as `dispose:` or `discard:`, so the lines above become
`ctx.join(Database.open, dispose: (db) => db.close())`. It is offered for a
release that is a tear-off of a method of the variable, such as `db.close`, or
a function literal without parameters.

### catch_without_check

```dart
try {
  await ctx.join(hw.open);
  await ctx.join(() => hw.setZoom(zoom));
} on Object { // catch_without_check
  await hw.reset();
  rethrow;
}
```

`Cancelled` implements `Exception`, so a catch without `on`, or on `Object`,
`Exception` or `Outcome`, takes it along with the failures it was written for,
and a cancelled job resets a camera nobody broke. Make `ctx.check()` the first
line of the catch. The rule looks at a job body, at the local functions
declared in it and at the actions it waits for through `join`, `abandonable`
and `uncancellable`; cleanup and unattended work are left alone. It is quiet
when the try block neither awaits nor reaches a checkpoint, and when the catch
begins with a checkpoint, after any `if (...) rethrow;` lines, begins with
`if (ctx.job.isCancelled) rethrow;`, or ends in `rethrow;` with no wait and no
checkpoint on the way, as a synchronous release or a log does. It is a lint
rather than a warning because a catch that has to wait for a release on a
cancellation too is reported as well: there `ctx.check()` first would leave the
resource behind, and the catch keeps its lines under an `// ignore:`. See
[Catching errors of the operation](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cancellation.md#catching-errors-of-the-operation).

The quick fix inserts `ctx.check();` as the first line of the catch.

### sync_fake_async

```dart
fakeAsync((async) async { // sync_fake_async
  async.elapse(const Duration(milliseconds: 10));
  await job.cancel();
  expect(job.outcome, isA<Cancelled>());
});
```

An `await` in the callback suspends it, and nobody is left to move the fake
clock: the test hangs, or ends green with nothing run. Keep the callback
synchronous, move the clock with `elapse` and read `job.outcome`. The rule
reports the `async` of a callback given to `fakeAsync` or `FakeAsync.run`. See
[A cancelled open](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/testing.md#a-cancelled-open).

### bare_await

```dart
final job = Job<void>((ctx) async {
  while (true) {
    use(await ctx.abandonable(database.readAll));
    await Future<void>.delayed(const Duration(seconds: 1)); // bare_await
  }
});
```

A plain `await` does not hear a cancellation: the job is cancelled, and the
body still sits the delay out and goes on to the next line. Wait through the
context: `ctx.pause` instead of `Future.delayed`, `ctx.each` instead of
`await for`, which the rule reports with a message of its own, and for a call
`ctx.join` or `ctx.abandonable`. The two differ in what a cancellation does to
the call. `join` is for a call that must finish: it accepts the cancellation at
once, so `onCancel` can stop the call, waits for the call to come back and
throws only then. `abandonable` stops waiting at the cancellation and leaves
the call in flight. Steps that must not hear a cancellation until they end go
into `ctx.uncancellable`. See
[The context at a glance](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/reference.md#the-context-at-a-glance)
on the reference page of `async_job` and
[Letting time pass](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/time.md#letting-time-pass)
on its time page.

The rule looks at a job body, a function literal or a top-level function whose
first parameter is a `JobContext`, also when it is named `_`. Functions
declared inside the body are left alone: the actions of `join` and
`uncancellable`, cleanup, `unattended` work, local functions. A local function
is reported where the body awaits its call. The rule is quiet on a wait through
a member of the context of this body: `join`, `abandonable`, `uncancellable`,
`pause`, `run` and `runAll`. It is quiet on `value`, `done` and `cancel()` of a
child that `ctx.each` brings or that the body passed to `ctx.start` before in a
final variable or a final field, and on `Future.wait`, `[...].wait` and
`(...).wait` of such futures, a conditional of them and a final local variable
holding one. A call that passes the context to a parameter typed `JobContext`,
positional or named, waits through it. A release right after `ctx.disown(v)`,
on the next line or under `if (ctx.disown(v))`, has to run for a cancellation
too. It is quiet on a value that is not a future, in `finally`, in a catch that
is `on Cancelled`, and in a catch that takes a cancellation, untyped,
`on Object`, `on Exception` or `on Outcome`, and ends in `rethrow;` with no
`return` and no `break` or `continue` out of it before. A check at the top of a
catch is not enough: it hears a cancellation that has come, not one that comes
during the wait after it. A body of a job made with `cancellable: false`, as a
literal or a constant, is left alone, and so is a top-level function every job
of which is made so.

A loop of plain waits inside one `ctx.join(() async { ... })` is not reported,
although a cancellation does not end it either. A child held in a `var`, a
parameter or a field that is not final, and a `...` in the list of
`Future.wait`, are reported though they wait through the context. So are a
local function that waits through the context itself, where the body awaits its
call, a future of the context taken further by `timeout` or `then`,
`Future.any`, a mapped list such as `jobs.map(ctx.run)` and a variable of a
pattern.

In a solo controller, a job that waits for a job of the controller's own queue
waits for itself: the job it waits for is queued behind it. This rule reports
that wait like any other plain one. solo_lints reports it as `await_own_queue`,
with a message about the queue, and keeps `bare_await` quiet there.

It is a lint rather than a warning because tests wait in bodies on purpose, to
cancel a job midway. A project that gates CI on it turns it on as
`bare_await: warning` and puts `// ignore_for_file: async_job_lints/bare_await`
into the test files that hold a body on a plain wait.

### discarded_outcome

```dart
final upload = Job<void>((ctx) => ctx.join(() => api.upload(file)));
await upload.done; // discarded_outcome
showUploaded();
```

Reading `done` tells the core that the failure is handled, and the outcome it
brings is dropped here: a failed upload goes on to `showUploaded()`, and
nothing answers for the failure, not an observer's `onUnanswered` and not the
zone. Only an observer's `onError` hears it. Read the outcome with a `switch`,
await `value` to have the failure thrown, or call `ignoreFailure()` on the job
if its failure is not wanted. `value` throws a cancellation too, as
`Cancelled`, so it fits code for which a cancellation is a failure; other code
switches over the outcome. See
[A switch over `done`](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/outcomes.md#a-switch-over-done).

The rule reports a statement that awaits or just reads a `Future` of an
`Outcome` of async_job, `await job.done;` or `job.done;`, and such a future
returned from a function whose return type is `void`, `Future<void>` or
`FutureOr<void>`, as in `onRefresh: () => controller.load().done`. It goes by
the type, so a function of your own that returns `done` is reported where its
result is dropped. It is quiet when the job is a local variable or a parameter
whose `outcome`, `value` or `done` is read later in the same function, when
`ignoreFailure()` was called on it before, as a statement or in a cascade of
its declaration, and on a wait of a job body for a job of the controller's own
queue, which `bare_await` reports. A test that waits for a job only to look at
it afterwards reads `job.outcome` after `await job.done;` and keeps the rule
quiet that way.

The failure is answered for without anybody reading the outcome when the job is
continued with `then` or a handle of `shared()`, when it runs under `ctx.run`
or in `ctx.runAll`, or when the method that made it has called
`ignoreFailure()`. The rule does not see that and reports the line. A job of
solo with `isExpectedError` keeps an expected error away from `onUnanswered`,
but an unexpected one still goes there, and `await job.done;` silences exactly
that one. Switch over the outcome and rethrow what was not expected, or wait
for the end without observing the job through `whenFinished`, as
[Hearing the end without the failure](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/outcomes.md#hearing-the-end-without-the-failure)
shows.

The rule does not report `final _ = await job.done;`, outcomes dropped in a
list given to `Future.wait` or `[...].wait`, a callback of `done.then` that
does not look at the outcome, or `ctx.run(child).ignore()`.

### outcome_after_await

```dart
final upload = Job<void>((ctx) => ctx.join(() => api.upload(file)));
await saveDraft();
final outcome = await upload.done; // outcome_after_await
```

A failure nobody has observed is answered for one microtask after the job ends:
by the observer's `onUnanswered` if it mixes in `JobAnswerer`, otherwise by the
zone the job was made in. If the upload fails during `saveDraft()`, the zone
gets the error, and `outcome` brings the same failure a second time. Read
`done` right after the job is made, `final outcome = upload.done;`, and await
that outcome where the result is needed. For `value`, take the future at once
and mark it, `final value = upload.value..ignore();`: an early `value` alone is
a future that fails with nobody listening, and `ignore()` silences only that
report, while `await value` still throws. See
[Telling the core it is handled](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/outcomes.md#telling-the-core-it-is-handled).

The rule takes a local variable that is final or never assigned again, made by
a call, without a cascade and without `await`, whose type is a `Job` of
async_job, a `SoloJob` of solo included. It reports the first observation of
the job, `done`, `value`, `ignoreFailure()`, `then` or `shared()`, when a wait
stands between the declaration and it in the same function: `await`,
`await for`, or `yield` in an `async*` function. The actions of `join`,
`abandonable`, `wait` and `uncancellable` count as the same function, since
they run when the call is made. A job of `Job.deferred` does not run until it
is started, so for it only a wait after `start()` counts. `await job.cancel()`
of the job itself is not such a wait: its future ends before the failure is
answered for. The members that do not observe the job, such as `outcome`,
`isRunning`, `cancel()`, `whenFinished` and `start()`, do not stop the search.
Any other use first, as an argument, `ctx.run(job)` included, an assignment, a
return, an element of a collection or a variable captured by a closure, hands
the job to code the rule does not follow, and the rule is quiet.

The early read has a cost the rule does not hide. It marks the job observed, so
if the function leaves before it awaits the outcome, by an exception, a
`return` or, in a job body, a cancellation at a checkpoint, nobody hears the
failure. In a body a cancellation is an ordinary way out, so there run the job
as a child with `ctx.run`, whose failure the parent answers for, or wait in a
`try` and read the outcome in its `finally`.

A read after the wait costs nothing when the failure is taken care of
elsewhere: by an observer with `JobAnswerer` whose `onUnanswered` handles it,
by an `unansweredHandler` of a solo controller that takes it, by a method that
returns a job it has already observed, or in a test that waits for a job ending
in `Done` or `Cancelled`. Such a line is silenced with
`// ignore: async_job_lints/outcome_after_await`. The rule does not see an
observation in a loop whose wait stands later in the text but ran earlier, in
the previous pass, a job held in a field, a job made in one function and read
in another, or an observation in a closure other than the action of a waiting
call.

## Versions

The plugin works on Dart 3.10 and later, with `analyzer` from 12.1 to 14. A
Dart SDK that needs `analyzer` 15 does not load this version, and its rules
stay silent until a release lifts the bound.

The rules know the types of async_job by their names and the library they come
from, without depending on the package, and the same way the checkpoints solo
adds to the context. On a version of those packages where a name has changed, a
rule stays silent rather than reports code that is right. The rules also know
`wait`, the name of `abandonable` before async_job 1.0, so they check code on
0.x the same way.
