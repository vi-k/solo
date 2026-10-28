# solo_lints

`solo_lints` is an analyzer plugin for code built on
[async_job](https://pub.dev/packages/async_job) and
[solo](https://pub.dev/packages/solo). It reports the mistakes that compile,
run and often pass a first test: a wait in cleanup that never happens, a
resource lost to a cancellation, a catch that resets a working device, a job
that waits for itself. Each rule stands for a section of
[Common mistakes](https://github.com/vi-k/solo/blob/main/packages/solo/doc/mistakes.md),
the page of solo that shows each mistake and the right way side by side.

## Install

Name the plugin in `analysis_options.yaml` at the root of the package or the
workspace:

```yaml
plugins:
  solo_lints: ^0.1.0
```

The analysis server fetches the plugin itself, so it is not a dependency in
`pubspec.yaml`. Plugins need Dart 3.10 or later. `dart analyze`,
`flutter analyze` and the editor report its diagnostics. An editor sees a
change to the `plugins` section after its analysis server restarts.

The warnings are on as soon as the plugin is named. The lint,
`catch_without_check`, is turned on by name:

```yaml
plugins:
  solo_lints:
    version: ^0.1.0
    diagnostics:
      catch_without_check: true
```

A diagnostic is silenced with the name of the plugin in front of the rule:
`// ignore: solo_lints/ctx_in_cleanup` on the line above it, or
`// ignore_for_file: solo_lints/ctx_in_cleanup` for the whole file.

## Rules

| Rule | Kind | Reports |
| --- | --- | --- |
| `ctx_in_cleanup` | warning | a waiting member of the context called in cleanup |
| `release_on_the_call` | warning | a release registered on the line under the call that brings the resource |
| `catch_without_check` | lint | a broad catch in a body that acts before asking the job |
| `sync_fake_async` | warning | an `async` callback of `fakeAsync` |
| `await_own_queue` | warning | a job that waits for a job of its own controller's queue |

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

## Versions

The plugin works on Dart 3.10 and later, with `analyzer` from 12.1 to 14. A
Dart SDK that needs `analyzer` 15 does not load this version, and its rules
stay silent until a release lifts the bound.

The rules know the types of async_job and solo by their names and the libraries
they come from, without depending on either package. On a version of those
packages where a name has changed, a rule stays silent rather than reports code
that is right.
