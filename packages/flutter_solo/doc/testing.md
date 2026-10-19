# Testing

A widget test starts a load and looks at the screen once the load is over. The
controller and the screen are `ProfileController` and `ProfileView` from
[Usage](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.md#usage)
in the package README. `FakeApi` is the test's own: it answers with the name
ten milliseconds after the call.

`testWidgets` runs on a fake clock, and three rules follow from it:

- the test moves the clock, with `pump` or `pumpAndSettle`; awaiting a job does
  not move it;
- a test that reads `done` reads it before it moves the clock;
- the test closes the controller in its body, not in `addTearDown`.

A plain test awaits the job;
[Testing](https://github.com/vi-k/solo/blob/main/packages/solo/doc/testing.md)
of `solo` covers it.

## The first attempt

```dart
// The first attempt: the test waits for a job that waits for the test.
await controller.load().done;
await tester.pump();
```

The test never gets past the first line:

1. The fake answers after ten milliseconds, and those milliseconds are a timer
   of the fake clock.
2. Nothing inside `testWidgets` moves that clock but the test.
3. The job waits for the test to move time, and the test waits for the job.
4. The test stands there until its timeout, ten minutes by default.

## Moving the clock

```dart
testWidgets('the profile appears', (tester) async {
  final controller = ProfileController(FakeApi());
  await tester.pumpWidget(
    MaterialApp(home: ProfileView(controller: controller)),
  );

  await tester.tap(find.text('Load'));
  await tester.pumpAndSettle();

  expect(find.text('Ada Lovelace'), findsOneWidget);
  await controller.close();
});
```

`pumpAndSettle` pumps a frame every hundred milliseconds for as long as another
frame is asked for. The first hundred are more than this fake needs. A slower
one would be waited for as well, because the spinner of `Loading` keeps asking
for frames.

It is the screen that is waited for, not the job. With nothing animating,
`pumpAndSettle` stops after a frame or two, and a load that takes longer than
that is still waiting.

The controller is closed in the body of the test, not in `addTearDown`. A
tear-down runs after the fake clock has stopped. A `close()` awaited there with
a job still running never comes back, and an expectation that failed halfway
through a load is enough to leave one running. The test stands until its
timeout, and the test after it fails with it.

A job given a `timeout` brings a timer of its own, which the core holds until
the job ends. Left running when the body of a `testWidgets` ends, such a job
fails the test with
`A Timer is still pending even after the widget tree was disposed`. The same
job without a deadline lets the test pass. Closing the controller in the body,
as above, ends the job and takes its timer along.

## Waiting for the job

The handle waits for the job itself:

```dart
final done = controller.load().done; // before the job can end
await tester.pump(const Duration(milliseconds: 20)); // let the clock run
final outcome = await done;
```

`pump` with a duration moves the clock and then draws, so the frame it leaves
shows the last state.

`done` is read on the first line, before the clock moves, and the order
matters. A `Failed` nobody has asked about is reported as the job ends, to the
zone it was created in. Here that is the zone of the test, which fails the test
on the spot, and `tester.takeException()` has nothing to take afterwards. A
load that fails makes a test red even though it reads `done`, if it reads it
after the pump.

A job the test starts and drops says so with `ignoreFailure()`.

A `pump()` with no duration decides whether to draw before it runs the
microtask a job starts on. So after `controller.load()` and one `pump()` the
state has moved and the screen has not, unless a frame was already asked for,
as one is right after a `MaterialApp` has been pumped. A second `pump()` draws
it.
