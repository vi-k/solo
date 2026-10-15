# Common mistakes

Seven mistakes that compile, run and often pass a first test. Each section
shows the mistake, says what goes wrong, shows the right way in a few lines and
links to the section that shows the mistake in full.

## Each wait in its place

A plain `await` in a body is not a checkpoint.

Don't do this:

```dart
// Wrong: a cancelled upload goes on writing.
for (final chunk in chunks) {
  await device.write(chunk);
}
```

A cancelled job goes on until it meets a checkpoint, and `close()` waits that
long: cancelled during the second of four chunks, the upload writes the third
and the fourth as well. Wait through the context instead. `ctx.join` waits for
the call and then throws `Cancelled` in place of its result; `ctx.abandonable`
throws at once and leaves the call running.

Do this:

```dart
for (final chunk in chunks) {
  // Checks before the write and after it.
  await ctx.join(() => device.write(chunk));
}
```

Cleanup is the other way round. It runs after the body, where `join` throws
`StateError`.

Don't do this:

```dart
// Wrong: the flush never happens.
ctx.onDispose(() async {
  // The flush must finish before the queue moves on.
  await ctx.join(() => device.flush());
});
```

No matter how the job ended, `Done` included, the device buffer stays
unflushed. The `StateError` is told to the controller's `onError` hook and then
handed to `Solo.unansweredHandler`, or to the zone when no handler is set. Wait
in cleanup with a plain `await`.

Do this:

```dart
ctx.onDispose(() async {
  // Cleanup runs after the body, where the waiting methods are
  // gone: a plain await is the wait that works here.
  await device.flush();
});
```

The buffer is flushed however the upload ended. See
[Ordinary await and context lifetime](cancellation.md#ordinary-await-and-context-lifetime)
on the cancellation page.

## Registering a release on the call

A resource registered for release on the line under the call that brings it can
be lost.

Don't do this:

```dart
// Wrong: a cancellation fits between open and onDispose.
final db = await ctx.join(Database.open);
ctx.onDispose(db.close);
```

A cancellation during the open throws before the second line, and the open
database is lost. Pass the release to the call that brings the resource.

Do this:

```dart
final db = await ctx.join(
  Database.open,
  dispose: (db) => db.close(),
);
```

A value that does not reach the body is released on the spot, and a value that
does is released when the job ends. See
[Taking a resource from a call](resources.md#taking-a-resource-from-a-call) on
the resources page.

## Letting cancellation through a catch

`Cancelled` implements `Exception`, so a broad `catch` takes it along with the
failures it was written for.

Don't do this:

```dart
// Wrong: a cancellation resets a working camera.
try {
  await ctx.join(hw.open);
  await ctx.join(() => hw.setZoom(zoom));
} on Object catch (error) {
  await hw.reset();
  ctx.emit(Broken(error));
  rethrow;
}
```

Cancelled during `setZoom`, the job resets a device nobody broke, and whoever
cancelled it waits for the reset as well. Ask the job first.

Do this:

```dart
try {
  await ctx.join(hw.open);
  await ctx.join(() => hw.setZoom(zoom));
} on Object catch (error) {
  ctx.check();
  await hw.reset();
  ctx.emit(Broken(error));
  rethrow;
}
```

`ctx.check()` throws the job's `Cancelled` if the job has accepted one,
whatever error the catch took. A clause for the error, `on Cancelled`, is not
enough: a call stopped through a token throws an error of its own. See
[Catching errors inside a body](errors.md#catching-errors-inside-a-body) on the
errors page.

## Steps as children

The controller runs one root job at a time, and a method of the controller
queues one more.

Don't do this:

```dart
// Wrong: an awaited method waits for this very job.
Job<void> syncAndRecord(int item) => run<Ready, void>(
      key: _Op.syncAndRecord,
      (ctx) async {
        final path = await sync(item).value;
        await recordPath(path).value;
      },
    );
```

Awaited from a body, the queued job waits for the body to end, and the body
waits for the job: nothing moves until `close()` cancels both. `sync` and
`recordPath` queue the jobs `_sync` and `_recordPath`; run those as children of
the running job instead.

Do this:

```dart
Job<void> syncAndRecord(int item) => run<Ready, void>(
      key: _Op.syncAndRecord,
      (ctx) async {
        final path = await ctx.run(_sync(item));
        await ctx.run(_recordPath(path));
      },
    );
```

`Solo.debug` warns of such a wait when the job is queued. Awaiting `close()` or
`cancelAll()` from a body hangs the same way: both wait for the running job.
See [Steps in a row](children.md#steps-in-a-row) on the children page and
[Closing from a job](cancellation.md#closing-from-a-job) on the cancellation
page.

## Answering for every failure

A failure nobody reads goes to the zone the job was created in, where an
unhandled error can end the app.

Don't do this:

```dart
// Wrong: the failures still go to the zone.
final class Failures extends SoloObserver {
  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) {
    final outcome = job.outcome;
    if (outcome is Failed) {
      reportCrash(outcome.error, outcome.stackTrace);
    }
  }
}
```

An observer, the `onError` hook, an `ifFailed` handler and a look at
`job.outcome` all see the failure, but none of them counts as reading it. Await
`job.value` and catch the error, read `job.done`, or call `ignoreFailure()`
when nobody needs the result and the reporting is left to the hooks, like the
observer above.

Do this:

```dart
profile.load().ignoreFailure();
```

Do it before the job ends: a failure nobody has asked about is reported as the
job finishes. See
[Handled and unhandled failures](errors.md#handled-and-unhandled-failures) on
the errors page.

## Moving the clock in fakeAsync

The callback of `fakeAsync` has to stay synchronous.

Don't do this:

```dart
// Wrong: nobody moves the fake clock.
test('load fills in the name', () async {
  await fakeAsync((async) async {
    final profile = ProfileController(FakeProfileApi());

    final outcome = await profile.load().done;

    expect(outcome, isA<Done<String>>());
    await profile.close();
  });
});
```

An `await` in the callback suspends it, and nobody is left to move the fake
clock: the test hangs until its timeout or, with no `await` in front of
`fakeAsync`, ends at once and green with nothing run. Move the clock with
`elapse` and read the outcome.

Do this:

```dart
test('load fills in the name', () {
  fakeAsync((async) {
    final profile = ProfileController(FakeProfileApi());

    final job = profile.load()..ignoreFailure();
    async.elapse(const Duration(milliseconds: 20));

    expect(job.outcome, isA<Done<String>>());
    expect(profile.currentState, isA<Loaded>());

    profile.close();
    async.flushTimers();
  });
});
```

Nothing can be awaited inside, so `ignoreFailure()` marks the failure as read,
and `close()` with a last `flushTimers()` ends the test with an empty clock.
See [Awaiting inside fakeAsync](testing.md#awaiting-inside-fakeasync) on the
testing page.

## A key for each request

A policy compares keys, not arguments.

Don't do this:

```dart
// Wrong: one key for every profile.
Job<Profile> load(String id) => run<Ready, Profile>(
      key: _Op.load,
      policy: Policy.droppable,
      (ctx) => ctx.abandonable(() => api.load(id)),
    );
```

With one key for `load(id)`, `Policy.droppable` takes `load('grace')`, called
while `load('ada')` runs, for a duplicate and hands its caller Ada's profile.
Put the argument into the key.

Do this:

```dart
Job<Profile> load(String id) => run<Ready, Profile>(
      key: (_Op.load, id),
      policy: Policy.droppable,
      (ctx) => ctx.abandonable(() => api.load(id)),
    );
```

A key is any object compared with `==`, so a record will do. See
[A key for each request](jobs.md#a-key-for-each-request) on the jobs page.
