# solo_lints

`solo_lints` is an analyzer plugin for code built on
[async_job](https://pub.dev/packages/async_job) and
[solo](https://pub.dev/packages/solo). It reports the mistakes that compile,
run and often pass a first test: a wait in cleanup that never happens, a
resource lost to a cancellation, a catch that resets a working device, a job
that waits for itself, one key for every request, a wait that a cancellation
does not end. Most rules stand for a section of
[Common mistakes](https://github.com/vi-k/solo/blob/main/packages/solo/doc/mistakes.md),
the page of solo that shows each mistake and the right way side by side.

## Install

Name the plugin in `analysis_options.yaml` at the root of the package or the
workspace:

```yaml
plugins:
  solo_lints: ^0.1.1
```

The analysis server fetches the plugin itself, so it is not a dependency in
`pubspec.yaml`. Plugins need Dart 3.10 or later. `dart analyze` and the editor
report its diagnostics. `flutter analyze` reports them on Flutter 3.38, but
from Flutter 3.44 on it shows none of them; in a Flutter package, run
`dart analyze` for the plugin. An editor sees a change to the `plugins` section
after its analysis server restarts.

The warnings are on as soon as the plugin is named. The four lints,
`catch_without_check`, `key_per_request`, `ignore_failure_hides_bugs` and
`bare_await`, are turned on by name:

```yaml
plugins:
  solo_lints:
    version: ^0.1.1
    diagnostics:
      catch_without_check: true
      key_per_request: true
      ignore_failure_hides_bugs: true
      bare_await: true
```

A rule takes a severity in place of `true`: `error`, `warning` or `info`.
`key_per_request: warning` turns the lint on as a warning, and `dart analyze`
then fails on it, as on any warning. `false` turns a warning off.

A diagnostic is silenced with the name of the plugin in front of the rule:
`// ignore: solo_lints/ctx_in_cleanup` on the line above it, or
`// ignore_for_file: solo_lints/ctx_in_cleanup` for the whole file.

The quick fixes are offered in the editor. `dart fix` does not apply them: it
applies the fixes of the analyzer itself, not those of plugins.

On Dart 3.12, `dart analyze` in a package that names a plugin prints each
diagnostic of the analyzer itself twice. Dart 3.13 prints it once.

## Rules

| Rule | Kind | Reports |
| --- | --- | --- |
| `ctx_in_cleanup` | warning | a waiting member of the context called in cleanup |
| `release_on_the_call` | warning | a release registered on the line under the call that brings the resource |
| `catch_without_check` | lint | a broad catch in a body that acts before asking the job |
| `sync_fake_async` | warning | an `async` callback of `fakeAsync` |
| `await_own_queue` | warning | a job that waits for a job of its own controller's queue |
| `key_per_request` | lint | one key for a `Policy.droppable` job whose body reads an argument |
| `ignore_failure_hides_bugs` | lint | `ignoreFailure()` on a job that names its expected errors |
| `bare_await` | lint | an `await` in a job body that does not go through the context |

### ctx_in_cleanup

```dart
ctx.onDispose(() async {
  await ctx.join(() => device.flush()); // ctx_in_cleanup
});
```

Cleanup runs after the body, where `join` throws `StateError`, so the buffer
stays unflushed however the job ended. Wait there with a plain `await`. The
rule looks into the functions given to `ctx.onDispose` and `ctx.onDiscard` and
to `dispose:` and `discard:` of `join`, `abandonable`, `wait` and `run`,
literals, and local functions and final variables holding a literal passed by
name, and reports the members that throw there: the checkpoints, `onCancel`,
`start` and `each`. `onDispose`, `onDiscard`, `disown`, `log` and `unattended`
are left alone. See
[Each wait in its place](https://github.com/vi-k/solo/blob/main/packages/solo/doc/mistakes.md#each-wait-in-its-place).

### release_on_the_call

```dart
final db = await ctx.join(Database.open);
ctx.onDispose(db.close); // release_on_the_call
```

A cancellation during the open throws before the second line, and the open
database is lost. Pass the release to the call that brings the resource:
`ctx.join(Database.open, dispose: (db) => db.close())`. The rule takes `join`,
`abandonable`, `wait` and `run` with no release of their own, followed at once
by `onDispose` or `onDiscard` that mentions the variable. See
[Registering a release on the call](https://github.com/vi-k/solo/blob/main/packages/solo/doc/mistakes.md#registering-a-release-on-the-call).

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
} on Object catch (error) { // catch_without_check
  await hw.reset();
  ctx.emit(Broken(error));
  rethrow;
}
```

`Cancelled` implements `Exception`, so a catch without `on`, or on `Object`,
`Exception` or `Outcome`, takes it along with the failures it was written for,
and a cancelled job resets a camera nobody broke. Make `ctx.check()` the first
line of the catch. The rule looks at a job body, at the local functions
declared in it and at the actions it waits for through `join`, `abandonable`,
`wait` and `uncancellable`; cleanup and unattended work are left alone. It is
quiet when the try block neither awaits nor reaches a checkpoint, and when the
catch begins with a checkpoint, after any `if (...) rethrow;` lines, begins
with `if (ctx.job.isCancelled) rethrow;`, or ends in `rethrow;` with no wait
and no checkpoint on the way, as a synchronous release or a log does. It is a
lint rather than a warning because a catch that has to wait for a release on a
cancellation too is reported as well: there `ctx.check()` first would leave the
resource behind, and the catch keeps its lines under an `// ignore:`. See
[Letting cancellation through a catch](https://github.com/vi-k/solo/blob/main/packages/solo/doc/mistakes.md#letting-cancellation-through-a-catch).

The quick fix inserts `ctx.check();` as the first line of the catch.

### sync_fake_async

```dart
await fakeAsync((async) async { // sync_fake_async
  final outcome = await profile.load().done;
  expect(outcome, isA<Done<String>>());
});
```

An `await` in the callback suspends it, and nobody is left to move the fake
clock: the test hangs, or ends green with nothing run. Keep the callback
synchronous, move the clock with `elapse` and read `job.outcome`. The rule
reports the `async` of a callback given to `fakeAsync` or `FakeAsync.run`. See
[Moving the clock in fakeAsync](https://github.com/vi-k/solo/blob/main/packages/solo/doc/mistakes.md#moving-the-clock-in-fakeasync).

### await_own_queue

```dart
Job<void> syncAndRecord(int item) =>
    enqueue<Ready, void>(key: _Op.syncAndRecord, (ctx) async {
      final path = await sync(item).value; // await_own_queue
      await recordPath(path).value; // await_own_queue
    });
```

`sync(item)` queues a job behind the one that waits for it, and nothing moves
until `close()` cancels both. Run the job through `ctx.run(_sync(item))`
instead. The rule takes a method of the same controller that brings a
`SoloJob`, by its declared type or by what it returns when it is declared in
the same file, and `close()` and `cancelAll()`. It looks at the body of a
`SoloContext` job queued on this controller, what the body returns included, at
the actions that body waits for through `join`, `abandonable`, `wait` and
`uncancellable`, and at its cleanup, which the queue waits for as well. A mixin
`on Solo` is the controller too. See
[Steps as children](https://github.com/vi-k/solo/blob/main/packages/solo/doc/mistakes.md#steps-as-children).

### key_per_request

```dart
Job<Profile> load(String id) => enqueue<Ready, Profile>(
  key: _Op.load, // key_per_request
  policy: Policy.droppable,
  (ctx) => ctx.abandonable(() => api.load(id)),
);
```

A policy compares keys, not arguments. With one key for every `load(id)`,
`Policy.droppable` takes `load('grace')`, called while `load('ada')` runs, for
a duplicate and hands its caller Ada's profile. Put the argument into the key:
`key: (_Op.load, id)`. The rule takes `enqueue` of `Solo` with
`Policy.droppable` and `enqueueJob` of a `job` with that policy, when the key
reads no parameter of the enclosing method or function and the body reads one.
A key that reads a local variable or a parameter of a closure is left alone. It
is a lint rather than a warning because one key is sometimes meant, when the
result does not depend on the argument. See
[A key for each request](https://github.com/vi-k/solo/blob/main/packages/solo/doc/mistakes.md#a-key-for-each-request).

The quick fix replaces the key `K` with the record `(K, a, b)` of the
parameters the body reads. It is offered when each of them compares by value: a
`String`, a number, a `bool`, an enum, or one of those that can be `null`.

### ignore_failure_hides_bugs

```dart
SoloJob<Profile> load() => enqueue<Ready, Profile>(
  (ctx) => api.load(),
  isExpectedError: (e) => e is ApiException,
);

profiles.load().ignoreFailure(); // ignore_failure_hides_bugs
```

`isExpectedError` already keeps the errors it names quiet and lets the bugs
through to the zone, and `ignoreFailure()` hides those as well. Drop
`ignoreFailure()`: the expected errors stay quiet, and a bug is still reported.
The rule takes `ignoreFailure()` on a job that comes from `job` or `enqueue`
with `isExpectedError`, or from the `add` of a `collect` or `accumulate` field
with one, also through a method or function of the same library whose body is
`=>` or a single `return`, when nobody uses the job afterwards: the call
itself, or a cascade whose value is dropped, as the `onPressed` of a button is.
The page of common mistakes has no section for this one. It is a lint rather
than a warning because a job whose outcome nobody needs, with the reporting
left to the hooks, may call `ignoreFailure()` on purpose: see
[Answering for every failure](https://github.com/vi-k/solo/blob/main/packages/solo/doc/mistakes.md#answering-for-every-failure).

### bare_await

```dart
Job<void> upload(Note note) => enqueue<Ready, void>((ctx) async {
  await api.upload(note); // bare_await
  ctx.emit(Ready(note));
});
```

A plain `await` does not hear a cancellation: the job is cancelled, and the
body still waits for the server and goes on to the next line. Wait through the
context: `ctx.abandonable(() => api.upload(note))` or `ctx.join`, `ctx.pause`
instead of `Future.delayed`, and `ctx.each` instead of `await for`, which the
rule reports with a message of its own. Steps that must all run go into
`ctx.uncancellable`.

The rule looks at a job body, a function literal or a top-level function whose
first parameter is a `JobContext`, also when it is named `_`. Functions
declared inside the body are left alone: the actions of `join` and
`uncancellable`, cleanup, `unattended` work, local functions. A local function
is reported where the body awaits its call. The rule is quiet on a wait through
a member of the context of this body: `join`, `abandonable`, `wait`,
`uncancellable`, `pause`, `run` and `runAll`. It is quiet on `value`, `done`
and `cancel()` of a child that `ctx.each` brings or that the body passed to
`ctx.start` before in a final variable or a final field, and on `Future.wait`,
`[...].wait` and `(...).wait` of such futures, a conditional of them and a
final local variable holding one. A call that passes the context to a parameter
typed `JobContext`, positional or named, waits through it. A release right
after `ctx.disown(v)`, on the next line or under `if (ctx.disown(v))`, has to
run for a cancellation too. It is quiet on a value that is not a future, in
`finally`, in a catch that is `on Cancelled`, and in a catch that takes a
cancellation, untyped, `on Object`, `on Exception` or `on Outcome`, and ends in
`rethrow;` with no `return` and no `break` or `continue` out of it before. A
check at the top of a catch is not enough: it hears a cancellation that has
come, not one that comes during the wait after it. A body of a job made with
`cancellable: false`, as a literal or a constant, is left alone, and so is a
top-level function every job of which is made so, although a rule of a `solo`
state still cancels it. A wait for the controller's own queue is reported by
`await_own_queue` instead.

A loop of plain waits inside one `ctx.join(() async { ... })` is not reported,
although a cancellation does not end it either. A child held in a `var`, a
parameter or a field that is not final, and a `...` in the list of
`Future.wait`, are reported though they wait through the context. So are a
local function that waits through the context itself, where the body awaits its
call, a future of the context taken further by `timeout` or `then`,
`Future.any`, a mapped list such as `jobs.map(ctx.run)` and a variable of a
pattern.

It is a lint rather than a warning because tests wait in bodies on purpose, to
cancel a job midway. A project that gates CI on it turns it on as
`bare_await: warning` and puts `// ignore_for_file: solo_lints/bare_await` into
the test files that hold a body on a plain wait. See
[Each wait in its place](https://github.com/vi-k/solo/blob/main/packages/solo/doc/mistakes.md#each-wait-in-its-place).

## Versions

The plugin works on Dart 3.10 and later, with `analyzer` from 12.1 to 14. A
Dart SDK that needs `analyzer` 15 does not load this version, and its rules
stay silent until a release lifts the bound.

The rules know the types of async_job and solo by their names and the libraries
they come from, without depending on either package. On a version of those
packages where a name has changed, a rule stays silent rather than reports code
that is right.
