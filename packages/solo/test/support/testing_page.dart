// The code of `doc/testing.md` that works, verbatim: the tests under every
// heading but "The first attempt", and the controller of the camera around
// the `connect` of "A deadline of the job". `test` is the one of
// `testing_stubs.dart`, and `testing_rakes_test` runs each of these as a
// test of its suite. Where the page shows a few lines of a test, the test
// around them is this file's own.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart' hide test;

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
final failedValue =
    test('a failed load carries the error to the caller', () async {
  final profile = ProfileController(
    FakeProfileApi(error: StateError('no network')),
  );

  await expectLater(profile.load().value, throwsA(isA<StateError>()));
  expect(profile.currentState, isA<Failure>());

  await profile.close();
});

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

/// `### Letting the work finish`: the job first, the close after it.
final closedAfterTheJob = test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  final outcome = await profile.load().done;
  await profile.close();

  expect(outcome, isA<Done<String>>());
  expect(profile.currentState, isA<Loaded>());
});

/// `### Letting the work finish`: the drain, for a job the test does not
/// hold.
final drained = test('a drain runs the load nobody holds', () async {
  final profile = ProfileController(FakeProfileApi())..load();

  await profile.close(mode: SoloCloseMode.drain);

  expect(profile.currentState, isA<Loaded>());
});

/// `### Reading the outcome`.
final outcomeRead = test('a failed load shows the failure', () async {
  final profile = ProfileController(
    FakeProfileApi(error: StateError('no network')),
  );

  final outcome = await profile.load().done;

  expect(outcome, isA<Failed>());
  expect(profile.currentState, isA<Failure>());

  await profile.close();
});

/// `### Letting the first job start`: the test of the first attempt with
/// the three lines of the answer in it. The two lines of `### addTearDown`
/// stand at its top.
final firstJobStarted =
    test('a second load while the first one runs is dropped', () {
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
});

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

/// `### addTearDown`: the static with a default of its own.
final tracingPutBack = test('tracing goes back to what it was', () {
  final tracing = Solo.traceStateChanges;
  addTearDown(() => Solo.traceStateChanges = tracing);

  Solo.traceStateChanges = false;

  expect(Solo.traceStateChanges, isFalse);
});

/// `### Collecting in the zone, asserting outside`.
final collectedInTheZone =
    test('a failure nobody read reaches the zone', () async {
  final zoneErrors = <Object>[];
  late final ProfileController profile;

  await runZonedGuarded(
    () async {
      profile = ProfileController(
        FakeProfileApi(error: StateError('no network')),
      )..load();
      await profile.close(mode: SoloCloseMode.drain);
    },
    (error, stackTrace) => zoneErrors.add(error),
  );

  expect(profile.currentState, isA<Failure>());
  expect(zoneErrors, [isA<StateError>()]);
});

/// The controller of the camera: `connect` is the page's, the class around
/// it is what the page takes for granted.
final class CameraController extends Solo<CameraState> {
  final FakeCamera hw;

  CameraController(this.hw) : super(const Idle());

  Job<void> connect() => run<Idle, void>(
        key: 'connect',
        timeout: const Duration(seconds: 5),
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          await ctx.join(() => hw.open(cancelToken: token));
          ctx.emit(const Connected());
        },
      );

  /// A job behind `connect` in the queue, for the tests of what the queue
  /// waits for.
  Job<void> next() => run<CameraState, void>(key: 'next', (ctx) async {});
}

/// `### A deadline of the job`: the five seconds under fake time.
final connectGivesUp = test('connect gives up after five seconds', () {
  fakeAsync((async) {
    final camera = CameraController(FakeCamera());

    final job = camera.connect();
    async.elapse(const Duration(seconds: 5));

    expect('${job.outcome}', 'Cancelled(timeout)');
    expect(camera.currentState, isA<Idle>());

    camera.close();
    async.flushTimers();
  });
});
