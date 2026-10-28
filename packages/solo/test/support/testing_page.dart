// The code of `doc/testing.md` that works, verbatim: the tests under every
// heading but "The first attempt", and the controller of the camera of "A
// deadline of the job". `test` is the one of `testing_stubs.dart`, and
// `testing_rakes_test` runs each of these as a test of its suite. Where the
// page shows a few lines of a test, the test around them is this file's
// own. The camera the controller holds is the one of `testing_camera.dart`,
// which the page links to.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart' hide test;

import 'testing_camera.dart';
import 'testing_page_fixtures.dart';
import 'testing_stubs.dart';

/// `### Awaiting the outcome`: the load, awaited.
final awaited = test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  final outcome = await profile.load().done;

  expect(outcome, isA<Done<String>>());
  expect(
    profile.currentState,
    isA<Loaded>().having((state) => state.name, 'name', 'Ada Lovelace'),
  );

  await profile.close();
});

/// `### Awaiting the outcome`: the other half, `value`.
final failedValue = test(
  'a failed load carries the error to the caller',
  () async {
    final profile = ProfileController(
      FakeProfileApi(error: const ApiException('no network')),
    );

    await expectLater(profile.load().value, throwsA(isA<ApiException>()));
    expect(profile.currentState, isA<Failure>());

    await profile.close();
  },
);

/// `### Awaiting the outcome`: a cancellation.
final cancelledLoad = test('a cancelled load ends Cancelled', () async {
  final profile = ProfileController(FakeProfileApi());
  final job = profile.load();

  await job.cancel();

  expect(
    await job.done,
    isA<Cancelled>().having((outcome) => outcome.started, 'started', isFalse),
  );
  expect(profile.currentState, isA<Initial>());

  await profile.close();
});

/// `### Letting the work finish`: the drain, for a job the test does not
/// hold.
final drained = test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  // ignore: cascade_invocations
  profile.load();
  await profile.close(mode: SoloCloseMode.drain);

  expect(profile.currentState, isA<Loaded>());
});

/// `### ignoreFailure`.
final failureIgnored = test('a failed load shows the failure', () async {
  final profile = ProfileController(
    FakeProfileApi(error: const ApiException('no network')),
  );

  profile.load().ignoreFailure();
  await profile.close(mode: SoloCloseMode.drain);

  expect(profile.currentState, isA<Failure>());
});

/// `### Letting the first job start`: the test of the first attempt with
/// the three lines of the answer in it. The two lines of `### addTearDown`
/// stand at its top.
final firstJobStarted = test(
  'a second load while the first one runs is dropped',
  () {
    fakeAsync((async) {
      final journal = Journal();
      Solo.observer = journal;
      addTearDown(() => Solo.observer = null);
      final profile = ProfileController(FakeProfileApi());

      final first = profile.load();
      async.flushMicrotasks();
      final second = profile.load();
      expect(identical(first, second), isTrue);

      async.elapse(const Duration(milliseconds: 20));
      expect(journal.lines, [
        'load started',
        'state: Loading',
        'load Cancelled(duplicate)',
        'state: Loaded',
        'load Done(Ada Lovelace)',
      ]);

      profile.close();
      async.flushTimers();
    });
  },
);

/// `### Elapsing instead of awaiting`.
final elapsed = test('load fills in the name', () {
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

/// `### Elapsing instead of awaiting`: the cancellation no clock moves for.
final cancelledUnderFakeTime = test('a running load is cancelled', () {
  fakeAsync((async) {
    final profile = ProfileController(FakeProfileApi());

    final job = profile.load();
    async.flushMicrotasks();

    job.cancel();
    expect(job.outcome, isNull);

    async.flushMicrotasks();
    expect('${job.outcome}', 'Cancelled(manual)');

    profile.close();
    async.flushTimers();
  });
});

/// `### Collecting in the zone, asserting outside`.
final collectedInTheZone = test(
  'a failure nobody read reaches the zone',
  () async {
    final zoneErrors = <Object>[];
    late final ProfileController profile;

    await runZonedGuarded(() async {
      profile = ProfileController(
        FakeProfileApi(error: const ApiException('no network')),
      )..load();
      await profile.close(mode: SoloCloseMode.drain);
    }, (error, stackTrace) => zoneErrors.add(error));

    expect(profile.currentState, isA<Failure>());
    expect(zoneErrors, [isA<ApiException>()]);
  },
);

/// `### A deadline of the job`: the controller of the camera.
final class CameraController extends Solo<CameraState> {
  final Camera hw;

  CameraController(this.hw) : super(const Idle());

  Job<void> connect() => enqueue<Idle, void>(
    key: 'connect',
    timeout: const Duration(seconds: 5),
    (ctx) async {
      final token = CancelToken();
      ctx.onCancel(token.cancel);
      await ctx.join(() => hw.open(cancelToken: token));
      ctx.emit(const Connected());
    },
  );
}

/// The page's controller with a job to queue behind `connect`, for the
/// tests of what the queue waits for.
final class QueuedCamera extends CameraController {
  QueuedCamera(super.hw);

  /// A job behind `connect` in the queue.
  Job<void> next() => enqueue<CameraState, void>(key: 'next', (ctx) async {});
}

/// `### A deadline of the job`: the five seconds under fake time, a
/// millisecond before the deadline and at it, with the stop of the device
/// named the way the app names it in `main`.
final connectGivesUp = test('connect gives up after five seconds', () {
  Job.isCancellationError = (error) => error is OpenCancelled;
  addTearDown(() => Job.isCancellationError = null);

  fakeAsync((async) {
    final hw = FakeCamera();
    final camera = CameraController(hw);

    final job = camera.connect();
    async.elapse(const Duration(milliseconds: 4999));
    expect(job.outcome, isNull);

    async.elapse(const Duration(milliseconds: 1));
    expect('${job.outcome}', 'Cancelled(timeout)');
    expect(hw.refused, 1);
    expect(camera.currentState, isA<Idle>());

    camera.close();
    async.flushTimers();
  });
});
