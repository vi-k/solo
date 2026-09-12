# Testing

Await a job's outcome to synchronize a test before asserting state. The
following example uses `package:test`; `FakeProfileApi` is a test
implementation that returns `'Ada Lovelace'`:

```dart
test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  final outcome = await profile.load().done;

  expect(outcome, isA<Done<String>>());
  expect(
    profile.currentState,
    isA<Loaded>().having((state) => state.name, 'name', 'Ada Lovelace'),
  );

  await profile.close();
});
```

Use `job.value` when testing the returned value, or
`await expectLater(profile.load().value, throwsA(...))` for a failure.

For timing and ordering, use `package:fake_async`. In the following test,
the fake API completes after 20 ms. An observer records state changes and
job completion in one ordered list:

```dart
final class Journal extends SoloObserver {
  final lines = <String>[];

  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} started');

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} ${job.outcome}');

  @override
  void onChange(SoloBase<Object> solo, SoloTransition<Object> transition) =>
      lines.add('state: ${transition.current.runtimeType}');
}

test('a second load while the first one runs is dropped', () {
  fakeAsync((async) {
    final journal = Journal();
    SoloBase.observer = journal;
    addTearDown(() => SoloBase.observer = null);
    final profile = ProfileController(FakeProfileApi());

    final first = profile.load();
    async.flushMicrotasks();
    final second = profile.load();
    expect(identical(first, second), isTrue);

    async.elapse(const Duration(milliseconds: 20));
    expect(journal.lines, [
      'load started',
      'state: Loading',
      'load Cancelled(manual: duplicate)',
      'state: Loaded',
      'load Done(Ada Lovelace)',
    ]);

    profile.close();
    async.flushTimers();
  });
});
```

The cancelled duplicate in the journal is the newly created job that
`droppable` discarded. Both method calls returned the original job.
Reset the global observer with `addTearDown` so a failed test cannot leave
it installed for later tests.

Inside `fakeAsync`, request cancellation with `job.cancel().ignore()` and
advance pending work before asserting. `flushMicrotasks()` runs microtasks;
`Future(...)` and `Future.delayed(...)` use timers and require `elapse(...)`
or `flushTimers()`. Use `emitsInOrder` when the stream itself matters;
for final state, reading `currentState` after `job.done` is usually
sufficient.

## Timeouts

`Future.timeout` limits waiting for a future; it does not stop the
underlying operation. For a request whose result may be abandoned,
`ctx.wait(() => api.fetch().timeout(...))` can be sufficient.

For a device operation that must stop before the next job, connect a timer
to the device's cancellation mechanism and await the operation with
`join`. In this example, the hardware API completes with an error when
its token is cancelled, so a timeout fails the job:

```dart
Job<void> connect() => run<Idle, void>(
      key: 'connect',
      (ctx) async {
        final token = CancelToken();
        final timer = Timer(const Duration(seconds: 5), token.cancel);
        ctx.onCancel(token.cancel);
        try {
          await ctx.join(() => hw.open(cancelToken: token));
        } finally {
          timer.cancel();
        }
        ctx.emit(const Connected());
      },
    );
```

The `finally` block cancels the timer on every exit. Whether the device
actually stops, and which error it returns, depends on that device's API.
