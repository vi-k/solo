// The first attempts of `doc/testing.md`, verbatim: the test each section
// opens with. `test` is the one of `testing_stubs.dart`, which keeps a test
// instead of running it: most of these fail, one hangs, and
// `testing_rakes_test` runs each as the body of a test case of its own to
// see how. The deadline of the last section needs a controller of its own
// and stands in `testing_first_attempt_timeout.dart`.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart' hide test;

import 'testing_page_fixtures.dart';
import 'testing_stubs.dart';

/// `## Awaiting a job`: the assertion right after the call.
final assertedAfterTheCall = test('load fills in the name', () {
  final profile = ProfileController(FakeProfileApi());

  // ignore: cascade_invocations
  profile.load();

  expect(profile.currentState, isA<Loaded>());
});

/// `## Closing the controller`: the `close` that should let the work finish.
final closedToWait = test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  // ignore: cascade_invocations
  profile.load();
  await profile.close();

  expect(profile.currentState, isA<Loaded>());
});

/// `## A failure nobody read`: the drain does the waiting.
final failureNobodyRead = test('a failed load shows the failure', () async {
  final profile = ProfileController(
    FakeProfileApi(error: StateError('no network')),
  );

  // ignore: cascade_invocations
  profile.load();
  await profile.close(mode: SoloCloseMode.drain);

  expect(profile.currentState, isA<Failure>());
});

/// `## The order of what happened`: two calls in one turn.
final secondLoadInTheSameTurn =
    test('a second load while the first one runs is dropped', () {
  fakeAsync((async) {
    final journal = Journal();
    Solo.observer = journal;
    addTearDown(() => Solo.observer = null);
    final profile = ProfileController(FakeProfileApi());

    final first = profile.load();
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

/// `## Awaiting inside fakeAsync`: the `await` inside the callback.
final awaitedInsideFakeAsync = test('load fills in the name', () async {
  await fakeAsync((async) async {
    final profile = ProfileController(FakeProfileApi());

    final outcome = await profile.load().done;

    expect(outcome, isA<Done<String>>());
    await profile.close();
  });
});

/// `## What one test leaves for the next`: the reset on the last line. The
/// page leaves the test itself out; an expectation that fails stands for it
/// here, which is the case the section is about.
final resetOnTheLastLine =
    test('a second load while the first one runs is dropped', () {
  final journal = Journal();
  Solo.observer = journal;

  // ...the test...
  expect(journal.lines, ['load started']);

  Solo.observer = null;
});

/// `## Assertions inside a zone`: both expectations inside.
final assertedInsideTheZone =
    test('a failure nobody read reaches the zone', () async {
  await runZonedGuarded(
    () async {
      final profile = ProfileController(
        FakeProfileApi(error: StateError('no network')),
      )..load();
      await profile.close(mode: SoloCloseMode.drain);

      expect(profile.currentState, isA<Failure>());
    },
    (error, stackTrace) => expect(error, isA<StateError>()),
  );
});
