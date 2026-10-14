# Common mistakes

Seven mistakes that compile, run and often pass a first test. Each section says
what goes wrong, shows the right way in a few lines and links to the section
that shows the mistake in full.

## Waiting through the context

A plain `await` in a body is not a checkpoint: a cancelled job goes on until it
meets one, and `close()` waits that long. Wait through the context instead.
`ctx.join` waits for the call and then throws `Cancelled` in place of its
result; `ctx.abandonable` throws at once and leaves the call running.

```dart
for (final chunk in chunks) {
  // Checks before the write and after it.
  await ctx.join(() => device.write(chunk));
}
```

Cleanup is the other way round. It runs after the body, where `join` throws
`StateError`, so cleanup waits with a plain `await`. See
[Ordinary await and context lifetime](cancellation.md#ordinary-await-and-context-lifetime)
on the cancellation page.

## Registering a release on the call

`ctx.onDispose(db.close)` on the line under `await ctx.join(Database.open)`
leaves a gap. A cancellation during the open throws before that line, and the
open database is lost. Pass the release to the call that brings the resource:

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
failures it was written for, and resets a device nobody broke. Ask the job
first:

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
queues one more. Awaited from a body, that job waits for the body to end, and
the body waits for the job. Run the steps as children of the running job
instead:

```dart
final path = await ctx.run(_sync(item));
await ctx.run(_recordPath(path));
```

`Solo.debug` warns of such a wait when the job is queued. Awaiting `close()` or
`cancelAll()` from a body hangs the same way: both wait for the running job.
See [Steps in a row](children.md#steps-in-a-row) on the children page and
[Closing from a job](cancellation.md#closing-from-a-job) on the cancellation
page.

## Answering for every failure

A failure nobody reads goes to the zone the job was created in, where an
unhandled error can end the app. An observer, the `onError` hook, an `ifFailed`
handler and a look at `job.outcome` all see the failure, but none of them
counts as reading it. Await `job.value` and catch the error, read `job.done`,
or call `ignoreFailure()` when nobody needs the result:

```dart
profile.load().ignoreFailure();
```

Do it before the job ends: a failure nobody has asked about is reported as the
job finishes. See
[Handled and unhandled failures](errors.md#handled-and-unhandled-failures) on
the errors page.

## Moving the clock in fakeAsync

The callback of `fakeAsync` has to stay synchronous. An `await` in it suspends
the callback, and nobody is left to move the fake clock: the test hangs until
its timeout or, with no `await` in front of `fakeAsync`, ends at once and green
with nothing run. Move the clock with `elapse` and read the outcome:

```dart
final job = profile.load()..ignoreFailure();
async.elapse(const Duration(milliseconds: 20));

expect(job.outcome, isA<Done<String>>());
expect(profile.currentState, isA<Loaded>());
```

Nothing can be awaited inside, so `ignoreFailure()` marks the failure as read.
See [Awaiting inside fakeAsync](testing.md#awaiting-inside-fakeasync) on the
testing page.

## A key for each request

A policy compares keys, not arguments. With one key for `load(id)`,
`Policy.droppable` takes `load('grace')`, called while `load('ada')` runs, for
a duplicate and hands its caller Ada's profile. Put the argument into the key:

```dart
Job<Profile> load(String id) => run<Ready, Profile>(
      key: (_Op.load, id),
      policy: Policy.droppable,
      (ctx) => ctx.abandonable(() => api.load(id)),
    );
```

A key is any object compared with `==`, so a record will do. See
[A key for each request](jobs.md#a-key-for-each-request) on the jobs page.
