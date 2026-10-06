@Timeout(Duration(seconds: 10))
library;

import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';
import 'package:test_api/hooks_testing.dart' as nested;

import 'support/page_code.dart';
import 'support/testing_first_attempt_timeout.dart' as deadline;
import 'support/testing_first_attempts.dart' as first;
import 'support/testing_page.dart' as page;
import 'support/testing_page_fixtures.dart';
import 'support/testing_stubs.dart' hide test;

/// The sentinel of `doc/testing.md`.
///
/// The code of the page is tests, and it stands verbatim in
/// `test/support/testing_*.dart`: the controller, the fake and the journal
/// in one file, the tests that work in another, the first attempts in a
/// third and the deadline of the last section in a fourth. A test that works
/// is declared here as a test of this suite, under the name the page gives
/// it. A first attempt is run as the body of a test case of its own —
/// `TestCaseMonitor` of `package:test_api`, the same machinery the runner
/// puts a test in — and what it ends with is looked at from outside: a
/// failure, an error that reached its zone, an error that came after it was
/// over, or no end at all.
///
/// What the prose of the page says about that code is pinned next to it:
/// a test that checks a sentence holds the page to it through [_says].
///
/// The first three sections of the page await real time, twenty
/// milliseconds a load, and so do the tests of them here.

String _page() => File('doc/testing.md').readAsStringSync();

/// The page with every run of whitespace turned into one space, so that a
/// phrase is found wherever its lines were broken.
String _prose() => _page().replaceAll(RegExp(r'\s+'), ' ');

/// Holds the page to [phrase]: the test that calls this runs what the phrase
/// says, so a page that stops saying it leaves the test with nothing to
/// stand for.
void _says(String phrase) => expect(
      _prose(),
      contains(phrase),
      reason: 'doc/testing.md no longer says this',
    );

/// What the page quotes under its `text` fences, in order, line by line.
List<List<String>> _quotes() => [
      for (final block
          in RegExp(r'```text\n(.*?)\n```', dotAll: true).allMatches(_page()))
        block.group(1)!.split('\n'),
    ];

/// The sections of the page: each `## ` heading with the text under it.
List<String> _sections() => [
      for (final part in _page().split(RegExp('^(?=## )', multiLine: true)))
        if (part.startsWith('## ')) part,
    ];

/// Declares [written] as a test of this suite, as the page writes it.
void _asWritten(PageTest written) => test(written.name, written.body);

/// Runs [body] as the body of a test case of its own, to its end.
Future<nested.TestCaseMonitor> _run(FutureOr<void> Function() body) =>
    nested.TestCaseMonitor.run(body);

/// What [error] is, in a line.
String _what(Object error) => switch (error) {
      TestFailure() => 'TestFailure',
      StateError() => 'StateError: ${error.message}',
      TimeoutException() => 'TimeoutException',
      String() => error.split('\n').first,
      _ => '$error',
    };

/// The errors the test case of [run] has surfaced so far.
List<String> _errors(nested.TestCaseMonitor run) =>
    [for (final error in run.errors) _what(error.error)];

/// What the one failed expectation of [run] printed.
String _message(nested.TestCaseMonitor run) =>
    (run.errors.single.error as TestFailure).message ?? '';

/// Waits for the next error [run] surfaces, and for whatever the runner
/// adds to it in the same turn.
Future<void> _nextError(nested.TestCaseMonitor run) async {
  await run.onError.first.timeout(const Duration(seconds: 5));
  await pumpEventQueue();
}

/// Runs [body] in a zone of its own and returns what reached it uncaught.
/// Nothing is asserted inside: an `expect` that failed in there would be
/// one more error of the list.
Future<List<String>> _zoned(Future<void> Function() body) async {
  final errors = <String>[];
  await runZonedGuarded(
    body,
    (error, stackTrace) => errors.add(_what(error)),
  );
  return errors;
}

/// The same under fake time: what reached the zone while [body] ran.
List<String> _fakeZoned(
  void Function(FakeAsync async, List<String> errors) body,
) {
  final errors = <String>[];
  runZonedGuarded(
    () => fakeAsync((async) => body(async, errors)),
    (error, stackTrace) => errors.add(_what(error)),
  );
  return errors;
}

/// How [job] stands: its outcome, or that it has none yet.
String _how(Job<Object?> job) => '${job.outcome ?? 'no outcome'}';

/// The name of the state [solo] is in.
String _state(Solo<Object> solo) => switch (solo.currentState) {
      Initial() => 'Initial',
      Loading() => 'Loading',
      Loaded() => 'Loaded',
      Failure() => 'Failure',
      Idle() => 'Idle',
      Connected() => 'Connected',
      final other => '$other',
    };

/// The page's fake, counting its calls: whether the API was reached at all,
/// and whether a call is still in flight.
final class _CountingApi extends FakeProfileApi {
  int started = 0;
  int finished = 0;

  _CountingApi({super.error});

  @override
  Future<String> fetchName() async {
    started++;
    try {
      return await super.fetchName();
    } finally {
      finished++;
    }
  }
}

/// The quick start's controller without `Policy.droppable`, with a deadline
/// of [limit] when it is given one and a second job to queue: what the page
/// says of controllers it does not show.
final class _Plain extends Solo<ProfileState> {
  final ProfileApi api;
  final Duration? limit;

  _Plain(this.api, {this.limit}) : super(const Initial());

  Job<String> load() => run<ProfileState, String>(
        key: 'load',
        (ctx) async {
          ctx.emit(const Loading());
          final limit = this.limit;
          final name = await ctx.abandonable(
            () => limit == null
                ? api.fetchName()
                : api.fetchName().timeout(limit),
          );
          ctx.emit(Loaded(name));
          return name;
        },
      );

  Job<void> next() => run<ProfileState, void>(key: 'next', (ctx) async {});
}

/// An API whose call never answers.
final class _HungApi implements ProfileApi {
  @override
  Future<String> fetchName() => Completer<String>().future;
}

/// An observer that keeps the jobs it saw finish.
final class _Finished extends SoloObserver {
  final jobs = <Job<Object?>>[];

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) => jobs.add(job);
}

const _failed = nested.State.failed;
const _passed = nested.State.passed;
const _tooLate = 'This test failed after it had already completed.';

/// The `connect` of "A deadline of the job" with both state handlers of
/// `run`, each saying it was called.
final class _HandledCamera extends Solo<CameraState> {
  final FakeCamera hw;
  final List<String> seen;

  _HandledCamera(this.hw, this.seen) : super(const Idle());

  Job<void> connect() => run<Idle, void>(
        key: 'connect',
        timeout: const Duration(seconds: 5),
        onError: (state, error, stackTrace) {
          seen.add('onError: $error');
          return state;
        },
        onCancel: (state, cancelled) {
          seen.add('onCancel: ${cancelled.reason.name}');
          return state;
        },
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          await ctx.join(() => hw.open(cancelToken: token));
          ctx.emit(const Connected());
        },
      );
}

void main() {
  tearDown(() {
    Solo.observer = null;
    Solo.errorHandler = null;
  });

  // First in the file: nothing has touched a static yet.
  group('The statics, before any test has set one', () {
    test('four of the five start as null, and tracing is on with assertions',
        () {
      expect(Solo.observer, isNull);
      expect(Solo.errorHandler, isNull);
      expect(Solo.debug, isNull);
      expect(Job.debug, isNull);
      expect(Solo.traceStateChanges, isTrue, reason: 'assertions are on');
      _says('Five statics belong to the process rather than to a controller');
      _says('The first four start as `null`');
      _says('`traceStateChanges` is on wherever assertions are');
    });
  });

  group('The fixtures', () {
    test('the controller is the one of the quick start of the README', () {
      final block =
          RegExp(r'```dart\n(.*?)\n```', dotAll: true).firstMatch(_page())!;
      final readme = File('README.md').readAsStringSync();
      final quickStart = readme.substring(
        readme.indexOf('\n## Quick start\n'),
        readme.indexOf('\n## ', readme.indexOf('\n## Quick start\n') + 1),
      );

      expect(block.group(1), startsWith('final class ProfileController '));
      expect(quickStart, contains(block.group(1)));
      _says('drive the `load` of the controller from');
    });

    test('the fake answers twenty milliseconds after the call, not before', () {
      fakeAsync((async) {
        String? name;
        FakeProfileApi().fetchName().then((value) => name = value);

        async.elapse(const Duration(milliseconds: 19));
        expect(name, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(name, 'Ada Lovelace');
        _says('twenty milliseconds after the call it answers with the name');
      });
    });

    test('or throws the error it was given, after the same wait', () {
      fakeAsync((async) {
        final given = StateError('no network');
        Object? thrown;
        FakeProfileApi(error: given)
            .fetchName()
            .then<void>((_) {}, onError: (Object error) => thrown = error);

        async.elapse(const Duration(milliseconds: 19));
        expect(thrown, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(thrown, same(given));
        _says('or throws the error it was given');
      });
    });

    test('a second call joins the load already in flight', () async {
      final api = _CountingApi();
      final profile = ProfileController(api);

      final job = profile.load();
      await pumpEventQueue();
      final second = profile.load();
      await job.done;

      expect(second, same(job));
      expect(api.started, 1);
      _says('is what makes a second call join the load already in flight');

      await profile.close();
    });

    test('a test that awaits waits the fake out for real', () async {
      final profile = ProfileController(FakeProfileApi());
      final watch = Stopwatch()..start();

      await profile.load().done;

      // Not twenty sharp: the two clocks are not one.
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(15));
      _says("the fake's twenty milliseconds are waited out for real");

      await profile.close();
    });
  });

  group('Awaiting a job', () {
    group('the first attempt', () {
      test('fails, and the state it prints is Initial', () async {
        final run = await _run(first.assertedAfterTheCall.body);

        expect(run.state, _failed);
        expect(_errors(run), ['TestFailure']);
        expect(
          _message(run),
          allOf(
            contains("Expected: <Instance of 'Loaded'>"),
            contains("Actual: <Instance of 'Initial'>"),
          ),
        );
        _says('The test fails, and the state it prints is `Initial`');
      });

      test('nothing of the load has happened when the call returns', () async {
        final profile = ProfileController(FakeProfileApi());

        final job = profile.load();
        final atOnce = '${_state(profile)}, ${_how(job)}, '
            'running ${job.isRunning}';
        await Future<void>.microtask(() {});
        final aMicrotaskLater = '${_state(profile)}, running ${job.isRunning}';

        expect(atOnce, 'Initial, no outcome, running false');
        expect(aMicrotaskLater, 'Loading, running true');
        _says('not even `Loading`, the state the body emits on its first line');
        _says('the body starts on a later microtask');
        _says('Nothing of the load has happened by the time the expectation '
            'runs');

        await job.done;
        await profile.close();
      });
    });

    group('awaiting the outcome, as the page writes it:', () {
      _asWritten(page.awaited);
      _asWritten(page.failedValue);
      _asWritten(page.cancelledLoad);
    });

    group('awaiting the outcome', () {
      test('done never throws, whichever way the load ends', () async {
        final loaded = ProfileController(FakeProfileApi());
        final failed = ProfileController(
          FakeProfileApi(error: StateError('no network')),
        );
        final cancelled = ProfileController(FakeProfileApi());
        final job = cancelled.load();
        await pumpEventQueue();
        unawaited(job.cancel());

        expect('${await loaded.load().done}', 'Done(Ada Lovelace)');
        expect('${await failed.load().done}', 'Failed(Bad state: no network)');
        expect('${await job.done}', 'Cancelled(manual)');
        _says('`done` completes with the outcome and never throws');

        await loaded.close();
        await failed.close();
        await cancelled.close();
      });

      test('the state handlers have run by the time done completes', () async {
        final journal = Journal();
        Solo.observer = journal;
        final failed = ProfileController(
          FakeProfileApi(error: StateError('no network')),
        );

        await failed.load().done;

        expect(_state(failed), 'Failure');
        expect(journal.lines, [
          'load started',
          'state: Loading',
          'state: Failure',
          'load Failed(Bad state: no network)',
        ]);
        _says('By the time it completes the state handlers have run as well');

        await failed.close();
      });

      test('value throws the cancellation that done hands over', () async {
        final profile = ProfileController(FakeProfileApi());
        final job = profile.load();

        await job.cancel();

        expect(await job.done, isA<Cancelled>());
        await expectLater(job.value, throwsA(isA<Cancelled>()));
        _says('`done` hands it over like any other, while `value` would throw '
            'it');

        await profile.close();
      });

      test('value returns what the body returned', () async {
        final profile = ProfileController(FakeProfileApi());

        expect(await profile.load().value, 'Ada Lovelace');
        _says('the value the body returned, or the error it threw');

        await profile.close();
      });

      test('a load cancelled in the queue never ran: one line, no state',
          () async {
        final journal = Journal();
        Solo.observer = journal;
        final api = _CountingApi();
        final profile = ProfileController(api);
        final job = profile.load();

        await job.cancel();

        expect(_how(job), 'Cancelled(manual)');
        expect(journal.lines, ['load Cancelled(manual)']);
        expect(api.started, 0);
        _says('`cancel()` completes when the job has finished');
        _says('its body never ran, and its `onCancel` handler was not called '
            'at all');

        await profile.close();
      });

      test('a load cancelled while it runs ends in the state of its handler',
          () async {
        final journal = Journal();
        Solo.observer = journal;
        final profile = ProfileController(FakeProfileApi());
        final job = profile.load();
        await pumpEventQueue();

        await job.cancel();

        expect(
          job.outcome,
          isA<Cancelled>()
              .having((outcome) => outcome.started, 'started', isTrue),
        );
        expect(journal.lines, [
          'load started',
          'state: Loading',
          'state: Initial',
          'load Cancelled(manual)',
        ]);
        _says('A load cancelled while it runs ends `Cancelled` as well, with '
            '`started: true`');

        await profile.close();
      });
    });
  });

  group('Closing the controller', () {
    group('the first attempt', () {
      test('fails: close() cancels, and the state is Initial', () async {
        final run = await _run(first.closedToWait.body);

        expect(run.state, _failed);
        expect(_errors(run), ['TestFailure']);
        expect(_message(run), contains("Actual: <Instance of 'Initial'>"));
        _says('`close()` cancels, and the state the expectation sees is '
            '`Initial`');
      });

      test('the job never leaves the queue', () async {
        final journal = Journal();
        Solo.observer = journal;
        final api = _CountingApi();
        final profile = ProfileController(api);
        final job = profile.load();

        await profile.close();

        expect(_how(job), 'Cancelled(closed)');
        expect(journal.lines, ['load Cancelled(closed)']);
        expect(api.started, 0);
        expect(_state(profile), 'Initial');
        _says('so `close` drops it with `Cancelled(closed)` before the body '
            'starts');
      });

      test('a load that had started is cancelled where it was waiting',
          () async {
        final journal = Journal();
        Solo.observer = journal;
        final api = _CountingApi();
        final profile = ProfileController(api);
        final job = profile.load();
        await pumpEventQueue();

        await profile.close();

        expect(_how(job), 'Cancelled(closed)');
        expect(journal.lines, [
          'load started',
          'state: Loading',
          'state: Initial',
          'load Cancelled(closed)',
        ]);
        expect(
          'started ${api.started}, finished ${api.finished}',
          'started 1, finished 0',
        );
        _says('its `onCancel` handler would publish `Initial` over the '
            '`Loading` its body had emitted');
      });
    });

    group('letting the work finish, as the page writes it:', () {
      _asWritten(page.closedAfterTheJob);
      _asWritten(page.drained);
    });

    group('letting the work finish', () {
      test('a drained job can still fail', () async {
        late ProfileController profile;

        final errors = await _zoned(() async {
          profile = ProfileController(
            FakeProfileApi(error: StateError('no network')),
          )..load();
          await profile.close(mode: SoloCloseMode.drain);
        });

        expect(_state(profile), 'Failure');
        expect(errors, ['StateError: no network']);
        _says('A drain runs the queue; it does not promise the work '
            'succeeds.');
      });
    });
  });

  group('A failure nobody read', () {
    group('the first attempt', () {
      test('is red with the failure of the load, its expectation holding',
          () async {
        final run = await _run(first.failureNobodyRead.body);

        expect(run.state, _failed);
        expect(_errors(run), ['StateError: no network']);
        expect('${run.errors.single.error}', 'Bad state: no network');
        _says('The expectation holds and the test is red anyway.');
        _says('the runner fails the test with `Bad state: no network`');
      });

      test('the trace names the fake and the engine, and no line of the test',
          () async {
        final traces = <String>[];

        await runZonedGuarded(
          first.failureNobodyRead.body,
          (error, stackTrace) => traces.add('$stackTrace'),
        );

        expect(traces, hasLength(1));
        expect(traces.single, contains('FakeProfileApi.fetchName'));
        expect(traces.single, contains('package:async_job/'));
        expect(traces.single, isNot(contains('testing_first_attempts.dart')));
        _says('under a stack trace that names the line of the fake that threw '
            'and a frame of the engine, and no line of the test');
      });

      test('a test that does not wait at all has passed when the failure comes',
          () async {
        final run = await _run(() {
          ProfileController(FakeProfileApi(error: StateError('no network')))
              .load();
        });
        final whenOver = '${run.state}, ${_errors(run)}';

        await _nextError(run);

        expect(whenOver, '$_passed, []');
        expect(run.state, _failed);
        expect(_errors(run), ['StateError: no network', _tooLate]);
        _says('the failure arrives after the test has ended');
        _says('`This test failed after it had already completed`');
        _says('With no later test still running by then, the run is over '
            'before the failure arrives');
      });
    });

    group('reading the outcome, as the page writes it:', () {
      _asWritten(page.outcomeRead);
    });

    group('reading the outcome', () {
      test('done, value and ignore() mark the job observed, outcome does not',
          () async {
        final reached = <String, List<String>>{};

        for (final read in ['nothing', 'done', 'value', 'ignore', 'outcome']) {
          reached[read] = await _zoned(() async {
            final profile = ProfileController(
              FakeProfileApi(error: StateError('no network')),
            );
            final job = profile.load();
            switch (read) {
              case 'done':
                unawaited(job.done);
              case 'value':
                job.value.ignore();
              case 'ignore':
                job.ignore();
              case 'outcome':
                job.outcome;
            }
            await profile.close(mode: SoloCloseMode.drain);
          });
        }

        expect(reached, {
          'nothing': ['StateError: no network'],
          'done': isEmpty,
          'value': isEmpty,
          'ignore': isEmpty,
          'outcome': ['StateError: no network'],
        });
        _says('Reading `done` or `value` marks the job observed');
        _says('`job.ignore()`, which marks it observed without waiting for '
            'it');
        _says('Reading `job.outcome` does not mark anything');
      });

      test('a read that comes after the job has ended comes too late',
          () async {
        final run = await _run(() async {
          final profile = ProfileController(
            FakeProfileApi(error: StateError('no network')),
          );

          final job = profile.load();
          await profile.close(mode: SoloCloseMode.drain);

          expect(await job.done, isA<Failed>());
          expect(profile.currentState, isA<Failure>());
        });

        expect(run.state, _failed);
        expect(_errors(run), ['StateError: no network']);
        _says('The read has to come before the job ends');
        _says('so a test that holds the job, drains the controller and reads '
            '`done` afterwards is red all the same');
      });

      test('the field is null until the job has finished', () {
        fakeAsync((async) {
          final profile = ProfileController(FakeProfileApi());
          final job = profile.load()..ignore();

          async.elapse(const Duration(milliseconds: 19));
          expect(job.outcome, isNull);
          async.elapse(const Duration(milliseconds: 1));
          expect(_how(job), 'Done(Ada Lovelace)');
          _says('the field is `null` until the job has finished');

          profile.close();
          async.flushTimers();
        });
      });
    });

    group('a call the job has walked away from', () {
      test('fails after the test is over, whatever the test read', () async {
        final run = await _run(() async {
          final profile = ProfileController(
            FakeProfileApi(error: StateError('no network')),
          );
          final job = profile.load()..ignore();
          await pumpEventQueue();

          await job.cancel();

          expect(await job.done, isA<Cancelled>());
          await profile.close();
        });
        final whenOver = '${run.state}, ${_errors(run)}';

        await _nextError(run);

        expect(whenOver, '$_passed, []');
        expect(_errors(run), ['StateError: no network', _tooLate]);
        _says('One failure is out of reach of all three');
        _says('The job ends `Cancelled`; the call fails twenty milliseconds '
            'later, and its error belongs to no outcome.');
        _says("the test's again, and by then the test is over");
      });

      test('closing the controller on a running load lets go of it the same',
          () async {
        final run = await _run(() async {
          final profile = ProfileController(
            FakeProfileApi(error: StateError('no network')),
          )..load().ignore();
          await pumpEventQueue();

          await profile.close();
        });
        final whenOver = '${run.state}, ${_errors(run)}';

        await _nextError(run);

        expect(whenOver, '$_passed, []');
        expect(_errors(run), ['StateError: no network', _tooLate]);
        _says('or close the controller on it, and `ctx.abandonable` lets go of '
            'the call');
      });

      test('Solo.errorHandler takes it in place of the zone', () async {
        final answered = Completer<Object>();
        Solo.errorHandler =
            (solo, job, error, stackTrace) => answered.complete(error);

        final run = await _run(() async {
          final profile = ProfileController(
            FakeProfileApi(error: StateError('no network')),
          );
          final job = profile.load();
          await pumpEventQueue();

          await job.cancel();
          await profile.close();
        });
        final error = await answered.future.timeout(const Duration(seconds: 5));
        await pumpEventQueue();

        expect(_what(error), 'StateError: no network');
        expect(run.state, _passed);
        expect(_errors(run), isEmpty);
        _says('sets `Solo.errorHandler`, which takes it in place of the zone');
      });

      test('a call that answers after the job is over reports nothing',
          () async {
        final errors = await _zoned(() async {
          final profile = ProfileController(FakeProfileApi());
          final job = profile.load();
          await pumpEventQueue();
          await job.cancel();
          await profile.close();
          await Future<void>.delayed(const Duration(milliseconds: 40));
        });

        expect(errors, isEmpty);
      });
    });
  });

  group('The order of what happened', () {
    group('the first attempt', () {
      test('fails on the journal the page quotes first', () async {
        final run = await _run(first.secondLoadInTheSameTurn.body);
        final message = _message(run);
        final actual = message.substring(
          message.indexOf('Actual:'),
          message.indexOf('Which:'),
        );

        expect(run.state, _failed);
        expect(
          [
            for (final line in RegExp("'(.*)'").allMatches(actual))
              line.group(1),
          ],
          _quotes().first,
        );
        _says('The journal comes out in another order:');
      });

      test('the second call drops the job it has just created, in the call',
          () {
        fakeAsync((async) {
          final journal = Journal();
          final finished = _Finished();
          Solo.observer = SoloObserver.all([journal, finished]);
          final profile = ProfileController(FakeProfileApi());

          final job = profile.load();
          final second = profile.load();
          final dropped = finished.jobs.single;
          final outcome = dropped.outcome! as Cancelled;

          expect(second, same(job));
          expect(journal.lines, ['load Cancelled(duplicate)']);
          expect(dropped, isNot(same(job)));
          expect(dropped.key, 'load');
          expect(outcome.reason, isA<DuplicateCancelReason>());
          expect(outcome.started, isFalse);
          _says('the second call drops the job it has just created — inside '
              'the call itself, before anything has started');
          _says('The key in the line is the key the policy matched on');
          _says('`duplicate` is the reason, a `DuplicateCancelReason`');

          profile.close();
          async.flushTimers();
        });
      });

      test('the dropped job gets one line: no start, no state of its own', () {
        fakeAsync((async) {
          final journal = Journal();
          Solo.observer = journal;
          final profile = ProfileController(FakeProfileApi())
            ..load()
            ..load();

          async.elapse(const Duration(milliseconds: 20));

          expect(journal.lines, _quotes().first);
          expect(
            journal.lines.where((line) => line == 'load started'),
            hasLength(1),
          );
          expect(journal.lines, isNot(contains('state: Initial')));
          _says('That first line is the `onFinish` of the dropped job, and '
              'the only line it ever gets');
          _says('nothing was running');

          profile.close();
          async.flushTimers();
        });
      });

      test('a cancel() from outside says manual in the same place', () {
        fakeAsync((async) {
          final profile = ProfileController(FakeProfileApi());
          final job = profile.load();
          async.flushMicrotasks();

          job.cancel();
          async.flushMicrotasks();
          final outcome = job.outcome! as Cancelled;

          expect('$outcome', 'Cancelled(manual)');
          expect(outcome.reason, isA<ManualCancelReason>());
          _says('a `cancel()` from outside says `manual` in the same place');

          profile.close();
          async.flushTimers();
        });
      });

      test('the state ends Loaded whether the second call is dropped or runs',
          () {
        fakeAsync((async) {
          final journal = Journal();
          Solo.observer = journal;
          final dropping = ProfileController(FakeProfileApi())
            ..load()
            ..load();
          final running = _Plain(FakeProfileApi())
            ..load().ignore()
            ..load().ignore();

          async.elapse(const Duration(milliseconds: 40));

          expect('${_state(dropping)}, ${_state(running)}', 'Loaded, Loaded');
          expect(
            journal.lines.where((line) => line == 'load started'),
            hasLength(3),
          );
          _says('The state cannot show that: it ends up `Loaded` either way.');

          dropping.close();
          running.close();
          async.flushTimers();
        });
      });

      test('one observer hears every controller of the process', () async {
        final journal = Journal();
        Solo.observer = journal;
        final one = ProfileController(FakeProfileApi());
        final other = ProfileController(FakeProfileApi());

        await one.load().done;
        await other.load().done;

        expect(
          journal.lines.where((line) => line == 'load started'),
          hasLength(2),
        );
        _says('collected by an observer — one for every controller in the '
            'process');

        await one.close();
        await other.close();
      });
    });

    group('letting the first job start, as the page writes it:', () {
      _asWritten(page.firstJobStarted);
    });

    group('letting the first job start', () {
      test('with the flush the journal is the second one the page quotes', () {
        fakeAsync((async) {
          final journal = Journal();
          Solo.observer = journal;
          final profile = ProfileController(FakeProfileApi());

          final job = profile.load();
          async.flushMicrotasks();
          final afterTheFlush = '${_state(profile)}, running ${job.isRunning}';
          profile.load();
          async.elapse(const Duration(milliseconds: 20));

          expect(afterTheFlush, 'Loading, running true');
          expect(journal.lines, _quotes().last);
          expect(_quotes(), hasLength(2));
          _says('With it the first job leaves the queue and emits `Loading`, '
              'and the second call finds a load that is running');

          profile.close();
          async.flushTimers();
        });
      });
    });
  });

  group('Awaiting inside fakeAsync', () {
    group('the first attempt', () {
      test('hangs: the load never starts, and the test case never ends',
          () async {
        final journal = Journal();
        Solo.observer = journal;

        final run =
            nested.TestCaseMonitor.start(first.awaitedInsideFakeAsync.body);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(run.state, nested.State.running);
        expect(_errors(run), isEmpty);
        expect(journal.lines, isEmpty);
        _says("The test hangs until the test's own timeout kills it.");
        _says('the load never starts, and no timer inside will ever fire');
      });

      test('without the await in front of fakeAsync it is green, unrun',
          () async {
        var reached = 'the first await';

        final run = await _run(() {
          fakeAsync((async) async {
            final profile = ProfileController(FakeProfileApi());

            final outcome = await profile.load().done;

            reached = 'the line under it';
            expect(outcome, isA<Failed>(), reason: 'would fail if it ran');
            await profile.close();
          });
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(run.state, _passed);
        expect(_errors(run), isEmpty);
        expect(reached, 'the first await');
        _says('the test ends at once and green, and neither line under the '
            'first `await` has run');
      });
    });

    group('elapsing instead of awaiting, as the page writes it:', () {
      _asWritten(page.elapsed);
      _asWritten(page.cancelledUnderFakeTime);
    });

    group('elapsing instead of awaiting', () {
      test('microtasks alone leave the job with no outcome, on Loading', () {
        fakeAsync((async) {
          final profile = ProfileController(FakeProfileApi());
          final job = profile.load()..ignore();

          async.flushMicrotasks();

          expect('${_how(job)}, ${_state(profile)}', 'no outcome, Loading');
          _says('`flushMicrotasks()` alone leaves the job with no outcome at '
              'all and the state on `Loading`');

          profile.close();
          async.flushTimers();
        });
      });

      test('a failure reaches the zone unless ignore() stands in for the read',
          () {
        final reached = <bool, List<String>>{};

        for (final ignored in [false, true]) {
          reached[ignored] = _fakeZoned((async, errors) {
            final profile = ProfileController(
              FakeProfileApi(error: StateError('no network')),
            );
            final job = profile.load();
            if (ignored) job.ignore();
            async.elapse(const Duration(milliseconds: 20));
            job.outcome;
            profile.close();
            async.flushTimers();
          });
        }

        expect(reached, {
          false: ['StateError: no network'],
          true: isEmpty,
        });
        _says('`ignore()` is what stands in for that read');
      });

      test('the test as written ends with an empty clock', () {
        fakeAsync((async) {
          page.elapsed.body();

          expect(async.pendingTimers, isEmpty);
          _says('`close()` and a last `flushTimers()` end the test with an '
              'empty clock');
        });
      });

      test('a controller left with work in flight passes all the same',
          () async {
        var timers = 0;

        final run = await _run(() {
          fakeAsync((async) {
            ProfileController(FakeProfileApi()).load().ignore();
            async.flushMicrotasks();
            timers = async.pendingTimers.length;
          });
        });

        expect(run.state, _passed);
        expect(timers, 1);
        _says('`fakeAsync` says nothing about a timer nobody fired');
      });

      test('the last flush fires what a cancelled load left in flight', () {
        var beforeTheFlush = <String>['not reached'];

        final errors = _fakeZoned((async, errors) {
          final profile = ProfileController(
            FakeProfileApi(error: StateError('no network')),
          );
          final job = profile.load();
          async.flushMicrotasks();
          job.cancel();
          async.flushMicrotasks();
          beforeTheFlush = [_how(job), ...errors];

          profile.close();
          async.flushTimers();
        });

        expect(beforeTheFlush, ['Cancelled(manual)']);
        expect(errors, ['StateError: no network']);
        _says('so a call that fails late fails inside the test that made it');
      });

      test('the job accepts the cancellation inside the call', () {
        fakeAsync((async) {
          final profile = ProfileController(FakeProfileApi());
          final job = profile.load();
          async.flushMicrotasks();
          var heard = false;

          job
            ..whenCancelled((_) => heard = true)
            ..cancel();
          final underTheCall = 'cancelled ${job.isCancelled}, heard $heard, '
              '${_how(job)}, ${_state(profile)}';
          async.flushMicrotasks();

          expect(
            underTheCall,
            'cancelled true, heard true, no outcome, Loading',
          );
          expect(
            '${_how(job)}, ${_state(profile)}',
            'Cancelled(manual), Initial',
          );
          _says('The job accepts the cancellation inside the call, and the '
              'outcome is still a few microtasks away');
          _says('the `onCancel` handler has to run');

          profile.close();
          async.flushTimers();
        });
      });

      test('a load still in the queue is dropped inside the call', () {
        fakeAsync((async) {
          final profile = ProfileController(FakeProfileApi());
          final job = profile.load()..cancel();

          expect(_how(job), 'Cancelled(manual)');
          _says('one still in the queue is dropped inside the call, with its '
              'outcome there on the next line');

          profile.close();
          async.flushTimers();
        });
      });

      test('elapse moves clock.now() along with the timers', () {
        fakeAsync((async) {
          final before = clock.now();

          async.elapse(const Duration(seconds: 3));

          expect(clock.now().difference(before), const Duration(seconds: 3));
          _says('`elapse` moves `clock.now()` along with the timers');
        });
      });
    });
  });

  group('What one test leaves for the next', () {
    group('the first attempt', () {
      test('fails, and its journal stays installed and goes on collecting',
          () async {
        final run = await _run(first.resetOnTheLastLine.body);
        final left = Solo.observer;

        final next = ProfileController(FakeProfileApi());
        await next.load().done;
        await next.close();

        expect(run.state, _failed);
        expect(_errors(run), ['TestFailure']);
        expect(left, isA<Journal>());
        expect((left! as Journal).lines, [
          'load started',
          'state: Loading',
          'state: Loaded',
          'load Done(Ada Lovelace)',
        ]);
        _says('The reset runs only when the test passes.');
        _says('the journal of a test that is over stays installed for the '
            'next one');
      });

      test('an expectation that fails throws, and skips the line under it', () {
        var reset = false;

        expect(
          () {
            expect(1 + 1, 3);
            reset = true;
          },
          throwsA(isA<TestFailure>()),
        );

        expect(reset, isFalse);
        _says('so the first expectation that fails skips every line under '
            'it');
      });
    });

    group('addTearDown, as the page writes it:', () {
      _asWritten(page.tracingPutBack);
    });

    group('addTearDown', () {
      test('runs whether the test passed or failed', () async {
        final afterAFailure = await _run(first.secondLoadInTheSameTurn.body);
        final left = Solo.observer;
        final afterASuccess = await _run(page.firstJobStarted.body);

        expect(afterAFailure.state, _failed);
        expect(left, isNull);
        expect(afterASuccess.state, _passed);
        expect(Solo.observer, isNull);
        _says('`addTearDown` runs whether the test passed or failed.');
      });

      test('puts back the value the test found, whichever it was', () async {
        final found = Solo.traceStateChanges;
        addTearDown(() => Solo.traceStateChanges = found);
        final after = <bool, String>{};

        for (final outside in [true, false]) {
          Solo.traceStateChanges = outside;
          final run = await _run(page.tracingPutBack.body);
          after[outside] = '${run.state}, ${Solo.traceStateChanges}';
        }

        expect(after, {true: '$_passed, true', false: '$_passed, false'});
        _says('Read the value before changing it, and put back what was '
            'read');
        _says('Any of the five can be put back this way, and the last one '
            'only this way.');
      });
    });
  });

  group('Assertions inside a zone', () {
    group('the first attempt', () {
      test('passes as it stands', () async {
        final run = await _run(first.assertedInsideTheZone.body);

        expect(run.state, _passed);
        expect(_errors(run), isEmpty);
        _says('The test passes, and it would pass with no failure reaching '
            'the zone at all.');
      });

      test('passes with nothing reaching the zone: the handler never runs',
          () async {
        var handled = 0;

        final run = await _run(() async {
          await runZonedGuarded(
            () async {
              final profile = ProfileController(
                FakeProfileApi(error: StateError('no network')),
              )..load().ignore();
              await profile.close(mode: SoloCloseMode.drain);

              expect(profile.currentState, isA<Failure>());
            },
            (error, stackTrace) {
              handled++;
              expect(error, isA<StateError>());
            },
          );
        });

        expect(run.state, _passed);
        expect(handled, 0);
        _says('the handler is called only when an error arrives');
        _says('When none does it never runs, the test is green, and nothing '
            'has been said about the zone.');
      });

      test(
          'a failed expectation in the body is reported by the handler, '
          'and the await never returns', () async {
        var returned = false;

        final run = nested.TestCaseMonitor.start(() async {
          await runZonedGuarded(
            () async {
              final profile = ProfileController(
                FakeProfileApi(error: StateError('no network')),
              )..load();
              await profile.close(mode: SoloCloseMode.drain);

              expect(profile.currentState, isA<Loaded>());
            },
            (error, stackTrace) => expect(error, isA<StateError>()),
          );
          returned = true;
        });
        await _nextError(run);

        expect(run.state, _failed);
        expect(_errors(run), ['TestFailure']);
        expect(
          _message(run),
          allOf(
            contains("Expected: <Instance of 'StateError'>"),
            contains('Actual: TestFailure:<'),
            contains("Actual: <Instance of 'Failure'>"),
          ),
        );
        expect(returned, isFalse);
        _says('compare it to `StateError`, find no match and report that on '
            'a line of the handler');
        _says('the `await` would never return');
        _says('so the test would end on a timeout');
      });

      test(
          'a failed expectation inside a zone goes to the handler of the '
          'zone', () {
        final caught = <String>[];
        var went = 'into the zone';

        runZonedGuarded(
          () {
            expect(1 + 1, 3);
            went = 'past the expectation';
          },
          (error, stackTrace) => caught.add(_what(error)),
        );

        expect(caught, ['TestFailure']);
        expect(went, 'into the zone');
        _says("a throw from inside the zone belongs to the zone's handler");
      });
    });

    group('collecting in the zone, as the page writes it:', () {
      _asWritten(page.collectedInTheZone);
    });

    group('collecting in the zone', () {
      test(
          'a job reports to the zone it was created in, not the one it ends '
          'in', () async {
        final inner = <String>[];
        late ProfileController profile;

        final outer = await _zoned(() async {
          runZonedGuarded(
            () => profile = ProfileController(
              FakeProfileApi(error: StateError('no network')),
            )..load(),
            (error, stackTrace) => inner.add(_what(error)),
          );
          await profile.close(mode: SoloCloseMode.drain);
        });

        expect(inner, ['StateError: no network']);
        expect(outer, isEmpty);
        _says('A job reports to the zone it was created in');
      });

      test('by the time close returns the failure has been reported', () async {
        var whenCloseReturned = <String>['not reached'];
        final errors = <String>[];

        await runZonedGuarded(
          () async {
            final profile = ProfileController(
              FakeProfileApi(error: StateError('no network')),
            )..load();
            await profile.close(mode: SoloCloseMode.drain);
            whenCloseReturned = [...errors];
          },
          (error, stackTrace) => errors.add(_what(error)),
        );

        expect(whenCloseReturned, ['StateError: no network']);
        _says('by the time `close` returns, the job has finished and its '
            'failure has been reported');
      });
    });
  });

  group('Timeouts', () {
    group('the first attempt, as the page writes it:', () {
      _asWritten(deadline.deadlineOnTheCall);
    });

    group('the first attempt', () {
      test('five milliseconds in the job ends Failed with a TimeoutException',
          () {
        fakeAsync((async) {
          final profile = deadline.ProfileController(FakeProfileApi());
          final job = profile.load()..ignore();

          async.elapse(const Duration(milliseconds: 4));
          final before = _how(job);
          async.elapse(const Duration(milliseconds: 1));

          expect(before, 'no outcome');
          expect(
            job.outcome,
            isA<Failed>().having(
              (outcome) => outcome.error,
              'error',
              isA<TimeoutException>(),
            ),
          );
          expect(_state(profile), 'Failure');
          _says('Five milliseconds in, the job ends `Failed` with a '
              '`TimeoutException`');

          profile.close();
          async.flushTimers();
        });
      });

      test('the queue moves on while the call is still in flight', () {
        fakeAsync((async) {
          final api = _CountingApi();
          final profile = deadline.ProfileController(api)..load().ignore();
          final next = profile.next();

          async.elapse(const Duration(milliseconds: 5));

          expect(_how(next), 'Done(null)');
          expect(
            'started ${api.started}, finished ${api.finished}',
            'started 1, finished 0',
          );
          _says('and the queue moves on, while the call is still in flight');
          _says('the fake has been called and has not returned');

          profile.close();
          async.flushTimers();
        });
      });

      test('the call returns at its twentieth millisecond, into nothing', () {
        final failing = _CountingApi(error: StateError('no network'));
        var at19 = 'not reached';
        var at20 = 'not reached';

        final errors = _fakeZoned((async, errors) {
          final profile = deadline.ProfileController(failing);
          final job = profile.load()..ignore();
          async.elapse(const Duration(milliseconds: 19));
          at19 = 'finished ${failing.finished}';
          async.elapse(const Duration(milliseconds: 1));
          at20 = 'finished ${failing.finished}, ${_state(profile)}, '
              '${job.outcome is Failed}';

          profile.close();
          async.flushTimers();
        });

        expect(at19, 'finished 0');
        expect(at20, 'finished 1, Failure, true');
        expect(errors, isEmpty);
        _says('finishes later into nothing');
        _says('It returns at its twentieth millisecond, fifteen after the job '
            'was over, with nobody waiting for it.');
      });

      test('a call that never answers holds the queue', () {
        fakeAsync((async) {
          final profile = _Plain(_HungApi())..load().ignore();
          async.flushMicrotasks();
          final next = profile.next();

          async.elapse(const Duration(hours: 1));

          expect(_how(next), 'no outcome');
          _says('A call that never answers would hold the queue for good');

          profile.close();
          async.flushTimers();
        });
      });

      test('against this fake a deadline of seconds never fires', () {
        fakeAsync((async) {
          final profile = _Plain(
            FakeProfileApi(),
            limit: const Duration(seconds: 5),
          );
          final job = profile.load();

          async.elapse(const Duration(milliseconds: 20));

          expect(_how(job), 'Done(Ada Lovelace)');
          _says('against this fake a deadline of seconds never fires, and the '
              'job ends `Done`');

          profile.close();
          async.flushTimers();
        });
      });
    });

    group('a deadline of the job, as the page writes it:', () {
      _asWritten(page.connectGivesUp);
    });

    group('a deadline of the job', () {
      test('the fake camera never answers on its own', () {
        fakeAsync((async) {
          var answered = false;
          FakeCamera()
              .open(cancelToken: CancelToken())
              .then((_) => answered = true);

          async.elapse(const Duration(hours: 1));

          expect(answered, isFalse);
          _says('its `FakeCamera` is a device that never answers on its own');
        });
      });

      test('the deadline stops the device at five seconds, and not before', () {
        fakeAsync((async) {
          final hw = FakeCamera();
          final camera = page.CameraController(hw);
          final job = camera.connect();

          async.elapse(const Duration(milliseconds: 4999));
          final before = '${_how(job)}, refused ${hw.refused}';
          async.elapse(const Duration(milliseconds: 1));

          expect(before, 'no outcome, refused 0');
          expect(_how(job), 'Cancelled(timeout)');
          expect(hw.refused, 1);
          expect(_state(camera), 'Idle');
          expect(async.pendingTimers, isEmpty);
          _says('The hardware API completes with an error when its token is '
              'cancelled, and `join` throws that error, but the job is '
              'cancelled by then: it ends `Cancelled(timeout)`, not `Failed`');
          _says('`async.pendingTimers` is empty after the five seconds');

          camera.close();
          async.flushTimers();
        });
      });

      test('the deadline is counted from the start of the body', () {
        fakeAsync((async) {
          final camera = page.CameraController(FakeCamera())
            ..connect().ignore();
          final second = camera.connect();

          async.elapse(const Duration(milliseconds: 9999));
          final before = _how(second);
          async.elapse(const Duration(milliseconds: 1));

          expect(before, 'no outcome');
          expect(_how(second), 'Cancelled(timeout)');
          _says('Five seconds after the body starts, the job is cancelled');

          camera.close();
          async.flushTimers();
        });
      });

      test('the timer goes away when the device answers first', () {
        fakeAsync((async) {
          final hw = FakeCamera();
          final camera = page.CameraController(hw);
          final job = camera.connect();

          async.elapse(const Duration(seconds: 1));
          expect(async.pendingTimers, hasLength(1));
          hw.answer();
          async.flushMicrotasks();

          expect(_how(job), 'Done(null)');
          expect(_state(camera), 'Connected');
          expect(async.pendingTimers, isEmpty);
          _says('The timer the core keeps for it is gone as soon as the job '
              'ends');

          camera.close();
          async.flushTimers();
        });
      });

      test('a cancelled job stops the device as well, inside the call', () {
        late FakeCamera hw;
        var underTheCall = 'not reached';
        var afterTheFlush = 'not reached';

        final errors = _fakeZoned((async, errors) {
          hw = FakeCamera();
          final camera = page.CameraController(hw);
          final job = camera.connect();
          async.flushMicrotasks();

          job.cancel();
          underTheCall = 'refused ${hw.refused}';
          async.flushMicrotasks();
          afterTheFlush = '${_how(job)}, ${async.pendingTimers.length} timers';

          camera.close();
          async.flushTimers();
        });

        expect(underTheCall, 'refused 1');
        expect(afterTheFlush, 'Cancelled(manual), 0 timers');
        expect(errors, isEmpty);
        _says('A cancellation that comes from outside takes the same way, so '
            'a cancelled job stops the device as well');
      });

      test('the next job waits for the device to stop', () {
        fakeAsync((async) {
          final camera = page.CameraController(FakeCamera())..connect();
          async.flushMicrotasks();
          final next = camera.next();

          async.elapse(const Duration(milliseconds: 4999));
          final before = _how(next);
          async.elapse(const Duration(milliseconds: 1));

          expect(before, 'no outcome');
          expect(_how(next), 'Done(null)');
          _says('For a device operation that must stop before the next job');
          _says('`join` waits for the device to stop, so the next job starts '
              'after it');

          camera.close();
          async.flushTimers();
        });
      });

      test('without ignore() nothing reaches the zone', () {
        final errors = _fakeZoned((async, errors) {
          final camera = page.CameraController(FakeCamera())..connect();
          async.elapse(const Duration(seconds: 5));
          camera.close();
          async.flushTimers();
        });

        expect(errors, isEmpty);
        _says('nothing reaches the zone, and the test needs no `ignore()`');
      });

      test('the deadline reaches onCancel of run, not onError', () {
        final seen = <String>[];
        fakeAsync((async) {
          final camera = _HandledCamera(FakeCamera(), seen);
          final job = camera.connect();
          async.elapse(const Duration(seconds: 5));

          expect(_how(job), 'Cancelled(timeout)');
          camera.close();
          async.flushTimers();
        });

        expect(seen, ['onCancel: timeout']);
        _says('A `run` with `onCancel` gets the deadline there, not in '
            '`onError`');
      });
    });
  });

  group('The page', () {
    test('every section opens with a first attempt', () {
      final sections = _sections();
      final opening = [
        for (final section in sections)
          RegExp(r'^### (.*)$', multiLine: true).firstMatch(section)?.group(1),
      ];

      expect(sections, hasLength(8));
      expect(opening, everyElement('The first attempt'));
      expect(
        RegExp(r'^### The first attempt$', multiLine: true).allMatches(_page()),
        hasLength(8),
      );
      _says('Every section below opens with the version');
    });

    test('every section states what the test is after before its attempt', () {
      for (final section in _sections()) {
        final lines = section.split('\n');
        final before = lines.sublist(1, lines.indexOf('### The first attempt'));
        expect(
          before.where((line) => line.trim().isNotEmpty),
          isNotEmpty,
          reason: lines.first,
        );
      }
    });

    test('the three sections that await come first, fakeAsync is the fourth',
        () {
      final underFakeTime = [
        for (final section in _sections()) section.contains('fakeAsync(('),
      ];

      expect(underFakeTime.take(4), [false, false, false, true]);
      _says('The three sections below await; `fakeAsync` starts with the '
          'fourth.');
    });

    test('all but the last section drive the load of the profile', () {
      final ofTheCamera = [
        for (final section in _sections()) section.contains('connect()'),
      ];

      expect(ofTheCamera, [...List.filled(7, false), true]);
      _says('all but the last drive the `load` of the controller');
    });

    test('has no fence the checks do not read', () {
      expect(strayFences('doc/testing.md'), isEmpty);
    });

    // Each version under its own files: an answer turned into its own first
    // attempt would still be found among all of them.
    const fixtures = 'test/support/testing_page_fixtures.dart';
    const answers = 'test/support/testing_page.dart';
    const attempts = 'test/support/testing_first_attempts.dart';
    const timeout = 'test/support/testing_first_attempt_timeout.dart';
    const holders = {
      '# Testing': [fixtures],
      '### The first attempt': [attempts, timeout, fixtures],
      '### Awaiting the outcome': [answers],
      '### Letting the work finish': [answers],
      '### Reading the outcome': [answers],
      '### Letting the first job start': [answers],
      '### Elapsing instead of awaiting': [answers],
      '### addTearDown': [answers],
      '### Collecting in the zone, asserting outside': [answers],
      '### A deadline of the job': [answers],
    };
    for (final MapEntry(key: heading, value: files) in holders.entries) {
      test('the code under "$heading" is a run of lines of ${files.first}', () {
        expect(
          codeMissingFrom(
            'doc/testing.md',
            files.first,
            alsoIn: files.sublist(1),
            under: heading,
          ),
          isEmpty,
        );
      });
    }

    test('every piece of code on the page is a run of lines of these files',
        () {
      expect(
        codeMissingFrom(
          'doc/testing.md',
          answers,
          alsoIn: [attempts, timeout, fixtures],
        ),
        isEmpty,
      );
    });

    test('every heading with code under it is held to a file', () {
      final withCode = [
        for (final part in _page().split(RegExp('^(?=#)', multiLine: true)))
          if (part.contains('```dart')) part.split('\n').first,
      ];

      expect(withCode.toSet(), holders.keys.toSet());
    });
  });
}
