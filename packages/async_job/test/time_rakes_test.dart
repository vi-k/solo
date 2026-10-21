@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/cancellation_page.dart' show nameTheStop;
import 'support/cancellation_stubs.dart';
import 'support/delay.dart';
import 'support/page_code.dart';
import 'support/time_page.dart' as page;

/// The first attempts of `doc/time.md`, and what each one costs.
///
/// The page has no bench: its code stands verbatim in
/// `support/time_page.dart`, each block in a region of its own, and the
/// tests below run it; the variants next to them hold what the code of the
/// page does not show. The tests at the end hold the page to these files:
/// the lines it quotes to the lines its code prints, every block of its
/// code to the region in its place, the durations its prose names to the
/// stubs, and every block to a fence these checks read.

/// What each `text` block of the page says, in the order of the page.
const quoted = [
  [
    'step 1',
    'step 2',
    'migration stopped',
    'onError: DatabaseStopped',
    'database closed',
    'outcome: Cancelled(manual)',
  ],
  [
    'step 1',
    'step 2',
    'migration stopped',
    'onError: DatabaseStopped',
    'database closed',
    'outcome: Cancelled(timeout)',
  ],
  [
    'outcome: Done(page without a thumbnail after 15 ms)',
  ],
];

/// When the user cancels in "Letting time pass": the page's "500 ms in",
/// halfway through the second between two reads.
const pauseCancelMs = 500;

/// Runs the job [start] makes, cancels it [pauseCancelMs] in, and returns
/// how many ms after the cancellation the job ended and for how many more
/// a timer of it was still pending.
({int endedAfter, int timerLeftFor}) waiting(Job<Object?> Function() start) {
  freshRun();
  late final int endedAfter;
  late final int timerLeftFor;
  fakeAsync((async) {
    Duration? ended;
    final job = start()..ignoreFailure();
    unawaited(job.done.then((_) => ended = async.elapsed));
    async.elapse(const Duration(milliseconds: pauseCancelMs));
    unawaited(job.cancel());
    async.flushMicrotasks();
    while (ended == null) {
      async.elapse(const Duration(milliseconds: 1));
    }
    endedAfter = ended!.inMilliseconds - pauseCancelMs;
    final finishedAt = async.elapsed;
    while (async.pendingTimers.isNotEmpty) {
      async.elapse(const Duration(milliseconds: 1));
    }
    timerLeftFor = (async.elapsed - finishedAt).inMilliseconds;
  });
  return (endedAfter: endedAfter, timerLeftFor: timerLeftFor);
}

/// Runs the job [start] makes on a migration that fails before its first
/// step, and returns for how many ms after the end of the job a timer was
/// still pending, and what reached the zone.
({int timerLeftFor, List<String> zone}) failingUnderALimit(
  Job<Object?> Function() start,
) {
  freshRun();
  stage.migrationFails = true;
  var timerLeftFor = -1;
  final zone = <String>[];
  runZonedGuarded(
    () => fakeAsync((async) {
      final job = start();
      async.flushMicrotasks();
      while (!job.isFinished) {
        async.elapse(const Duration(milliseconds: 1));
      }
      final finishedAt = async.elapsed;
      while (async.pendingTimers.isNotEmpty) {
        async.elapse(const Duration(milliseconds: 1));
      }
      timerLeftFor = (async.elapsed - finishedAt).inMilliseconds;
    }),
    (error, stackTrace) => zone.add('$error'),
  );
  return (timerLeftFor: timerLeftFor, zone: zone);
}

/// Starts a run on fresh stubs; the stage stays as the test has set it.
void freshRun() {
  printed.clear();
  database = Database();
  device = Device();
}

/// Runs the job [start] makes, cancels it [cancelAt] ms in, and returns what
/// was printed. An error that reaches the zone is printed as `zone:`.
List<String> watch(Job<Object?> Function() start, {int? cancelAt}) {
  freshRun();
  runZonedGuarded(
    () => fakeAsync((async) {
      final job = start();
      unawaited(job.done.then((outcome) => say('outcome: $outcome')));
      if (cancelAt != null) {
        async.elapse(Duration(milliseconds: cancelAt));
        say('cancel');
        unawaited(job.cancel());
      }
      async.flushTimers();
    }),
    (error, stackTrace) => say('zone: $error'),
  );
  return printed.toList();
}

void main() {
  setUp(() {
    stage = Stage();
    freshRun();
    // The page runs every job with the line the cancellation page sets in
    // `main`.
    nameTheStop();
  });
  tearDown(() => Job.isCancellationError = null);
  // The setUp above names the stop for every test of the file, so the field
  // is checked once the last tearDown has run, not in a test of its own.
  tearDownAll(() => expect(Job.isCancellationError, isNull));

  group('Letting time pass', () {
    String row(String how, ({int endedAfter, int timerLeftFor}) measured) {
      final ended = measured.endedAfter == 0
          ? 'at once'
          : '${measured.endedAfter} ms after the cancellation';
      final timer = measured.timerLeftFor == 0
          ? 'none'
          : 'for ${measured.timerLeftFor} ms more';
      return '| $how | $ended | $timer |';
    }

    final lines = File('doc/time.md').readAsLinesSync();

    test('a plain delay is sat out to its end', () {
      final measured = waiting(page.plainDelay);
      expect(measured, (endedAfter: 510, timerLeftFor: 0));
      expect(lines, contains(row('`await Future.delayed(...)`', measured)));
    });

    test('a delay under abandonable ends at once and leaves its timer', () {
      final measured = waiting(page.delayUnderAbandonable);
      expect(measured, (endedAfter: 0, timerLeftFor: 510));
      expect(
        lines,
        contains(row('`ctx.abandonable(() => Future.delayed(...))`', measured)),
      );
    });

    test('a pause ends at once and takes its timer along', () {
      final measured = waiting(page.pauseOfTheJob);
      expect(measured, (endedAfter: 0, timerLeftFor: 0));
      expect(lines, contains(row('`ctx.pause(...)`', measured)));
    });

    test('uncancelled, all three read once a second', () {
      for (final start in [
        page.plainDelay,
        page.delayUnderAbandonable,
        page.pauseOfTheJob,
      ]) {
        freshRun();
        fakeAsync((async) {
          final job = start()..ignoreFailure();
          async.elapse(const Duration(milliseconds: 2500));
          expect(printed.where((line) => line == 'rows used'), hasLength(3));
          unawaited(job.cancel());
          async.flushTimers();
        });
      }
    });
  });

  group('A deadline', () {
    String row(String how, ({int timerLeftFor, List<String> zone}) measured) {
      final timer = measured.timerLeftFor == 0
          ? 'none'
          : 'for ${measured.timerLeftFor} ms more';
      final zone =
          measured.zone.isEmpty ? 'reaches no zone' : 'reaches the zone';
      return '| $how | $timer | $zone |';
    }

    final text = File('doc/time.md').readAsStringSync();
    final lines = text.split('\n');

    /// What the prose of the page quotes after [before], up to the closing
    /// backtick.
    String quotedAfter(String before) => RegExp(
          '${before.replaceAll(' ', r'\s+')}\\s+`([^`]+)`',
        ).firstMatch(text)!.group(1)!;

    test('a timer cancels the job still running, as the user does', () {
      expect(watch(page.timerOnTheJob), quoted[0]);
    });

    test('the timer does nothing to a job that has already finished', () {
      fakeAsync((async) {
        final quick = Job<int>((ctx) async => 1);
        Timer(page.limit, quick.cancel);
        async.flushTimers();

        expect('${quick.outcome}', 'Done(1)');
      });

      stage.migrationFails = true;
      expect(watch(page.timerOnTheJob), [
        'onError: FormatException: bad schema',
        'database closed',
        'outcome: Failed(FormatException: bad schema)',
      ]);
    });

    test('the timer lives until the limit, and the failure reaches the zone',
        () {
      final measured = failingUnderALimit(page.timerOnTheJob);
      expect(measured.timerLeftFor, page.limit.inMilliseconds);
      expect(measured.zone, ['FormatException: bad schema']);
      expect(lines, contains(row('`Timer(limit, job.cancel)`', measured)));
    });

    test('cancelling the timer when the job ends observes the outcome', () {
      final measured = failingUnderALimit(page.timerCancelledAtTheEnd);
      expect(measured.timerLeftFor, 0);
      expect(measured.zone, isEmpty);
      expect(
        lines,
        contains(row('`job.done.whenComplete(timer.cancel)`', measured)),
      );
      expect(printed, contains('onError: FormatException: bad schema'));
    });

    test('without an observer, nobody hears that failure', () {
      final measured = failingUnderALimit(() {
        final job = Job<Database>((ctx) async {
          final database = await ctx.join(Database.open);
          await ctx.join(() => database.migrate(CancelToken()));
          return database;
        });
        final timer = Timer(page.limit, job.cancel);
        job.done.whenComplete(timer.cancel).ignore();
        return job;
      });
      expect(measured.zone, isEmpty);
      expect(printed, isEmpty);
    });

    test('with a timer cancelled at the end, a running job is still cancelled',
        () {
      expect(watch(page.timerCancelledAtTheEnd), quoted[0]);
    });

    test('a deadline of the job stops it the same way, with its own reason',
        () {
      expect(watch(page.deadlineOfTheJob), quoted[1]);
    });

    test('a deadline leaves no timer and lets the failure reach the zone', () {
      final measured = failingUnderALimit(page.deadlineOfTheJob);
      expect(measured.timerLeftFor, 0);
      expect(measured.zone, ['FormatException: bad schema']);
      expect(lines, contains(row('`timeout: limit`', measured)));
    });

    test('the deadline is counted from the start of the body', () {
      fakeAsync((async) {
        final job = Job.deferred<void>(
          timeout: page.limit,
          (ctx) => ctx.pause(const Duration(milliseconds: 10)),
        );
        async.elapse(const Duration(milliseconds: 50));
        job.start();
        async.flushTimers();

        expect('${job.outcome}', 'Done(null)');
      });
    });

    test('the timer is gone the moment the job ends', () {
      fakeAsync((async) {
        final job = Job<int>(timeout: const Duration(hours: 1), (ctx) async {
          await ctx.pause(const Duration(milliseconds: 10));
          return 1;
        });
        async.elapse(const Duration(milliseconds: 5));
        expect(async.pendingTimers, hasLength(2));
        async.elapse(const Duration(milliseconds: 5));

        expect('${job.outcome}', 'Done(1)');
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a running job holds its timer until it ends', () {
      fakeAsync((async) {
        final job = page.deadlineOfTheJob()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));

        expect(job.isFinished, isFalse);
        expect(async.pendingTimers, isNotEmpty);
        unawaited(job.cancel());
        async.flushTimers();
      });
    });

    test('an uncancellable section holds the deadline until it closes', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = Job<void>(timeout: page.limit, (ctx) async {
          await ctx.uncancellable(() => delay(30));
          seen.add('section closed');
          ctx.check();
          seen.add('after the section');
        });
        async.flushTimers();

        expect(seen, ['section closed']);
        expect('${job.outcome}', 'Cancelled(timeout)');
      });
    });

    test('a job cancelled already keeps its own reason', () {
      fakeAsync((async) {
        final job = page.deadlineOfTheJob()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        unawaited(job.cancel());
        async.flushTimers();

        expect('${job.outcome}', 'Cancelled(manual)');
      });
    });

    test('the children hear the deadline as the cause of their cancellation',
        () {
      fakeAsync((async) {
        final child = Job.deferred<void>((ctx) => ctx.pause(page.limit * 2));
        final job = Job<void>(timeout: page.limit, (ctx) => ctx.run(child));
        async.flushTimers();

        expect('${job.outcome}', 'Cancelled(timeout)');
        final reason = (child.outcome! as Cancelled).reason;
        expect(
          reason,
          isA<ParentCancelReason>().having(
            (reason) => reason.cause?.reason,
            'cause',
            isA<TimeoutCancelReason>().having(
              (reason) => reason.timeout,
              'timeout',
              page.limit,
            ),
          ),
        );
      });
    });

    test('the deadline does not reach the cleanup stack', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = Job<String>(timeout: page.limit, (ctx) async {
          ctx.onDispose(() async {
            await delay(30);
            seen.add('cleaned up');
          });
          return 'done';
        });
        async.flushTimers();

        expect(seen, ['cleaned up']);
        expect('${job.outcome}', 'Done(done)');
      });
    });

    test('a deadline that is not positive, or not refusable, throws', () {
      for (final timeout in [Duration.zero, const Duration(milliseconds: -1)]) {
        expect(
          () => Job<void>(timeout: timeout, (ctx) async {}),
          throwsArgumentError,
        );
      }
      expect(
        () => Job<void>(
          timeout: page.limit,
          cancellable: false,
          (ctx) async {},
        ),
        throwsArgumentError,
      );
    });

    test('a step with a deadline goes out without its thumbnail', () {
      expect(watch(page.thumbnailWithADeadline), quoted[2]);
    });

    test('the clause rethrows the cancellation of the job', () {
      expect(watch(page.thumbnailWithADeadline, cancelAt: 5), [
        'cancel',
        'outcome: Cancelled(manual)',
      ]);
    });

    test('a request a section holds past the body goes with the timer', () {
      late final String outcome;
      fakeAsync((async) {
        final job = Job<int>(
          timeout: const Duration(milliseconds: 10),
          (ctx) async {
            ctx.onDispose(() => delay(200));
            unawaited(ctx.uncancellable(() => delay(100)));
            await ctx.run(Job.deferred((ctx) => delay(50)));
            return 1;
          },
        );
        async.flushTimers();
        outcome = '${job.outcome}';
      });

      expect(outcome, 'Done(1)');
      expect(
        text.replaceAll(RegExp(r'\s+'), ' '),
        contains('Only a body that went on without awaiting the section can be '
            'over while the section still holds the request: then the request '
            'goes with the timer, and the job ends with what the body '
            'returned.'),
      );
    });

    test('a section the body returns lands the request before the return', () {
      late final String outcome;
      var discarded = false;
      fakeAsync((async) {
        final job = Job<int>(
          timeout: const Duration(milliseconds: 100),
          (ctx) {
            ctx.onDiscard(() => discarded = true);
            return ctx.uncancellable(() => delay(300).then((_) => 7));
          },
        );
        async.flushTimers();
        outcome = '${job.outcome}';
      });

      expect(outcome, 'Cancelled(timeout)');
      expect(discarded, isTrue);
      expect(
        text.replaceAll(RegExp(r'\s+'), ' '),
        contains('a body that ends with `return ctx.uncancellable(...)` ends '
            '`Cancelled(timeout)`, the value of the section reaches neither '
            'the outcome nor `value`, and the registrations of `onDiscard` '
            'run.'),
      );
    });

    test('the clause rethrows a thumbnail somebody else cancelled', () {
      stage.thumbnail = Thumbnail.isCancelled;
      expect(watch(page.thumbnailWithADeadline), [
        'outcome: Cancelled(handler: Job(thumbnail): Cancelled(manual))',
      ]);
    });

    for (final key in ['thumbnail', null]) {
      test('let out, the deadline of the child ends the parent (key: $key)',
          () {
        late final String outcome;
        fakeAsync((async) {
          final job = Job<String>((ctx) async {
            final thumbnail = Job.deferred<String>(
              renderThumbnail,
              key: key,
              timeout: const Duration(milliseconds: 15),
            );
            return 'page with ${await ctx.run(thumbnail)}';
          });
          async.flushTimers();
          outcome = '${job.outcome}';
        });

        final child = key == null ? 'Job()' : 'Job($key)';
        expect(outcome, 'Cancelled(handler: $child: Cancelled(timeout))');
        if (key == null) {
          expect(quotedAfter('a child without one prints as'), child);
        } else {
          expect(quotedAfter('deadline ends the parent'), outcome);
        }
      });
    }
  });

  group('The page', () {
    test('quotes what its code prints', () {
      final text = File('doc/time.md').readAsStringSync();
      final blocks = RegExp(r'```text\n(.*?)\n```', dotAll: true)
          .allMatches(text)
          .map((match) => match.group(1)!.split('\n'))
          .toList();

      expect(blocks, quoted);
    });

    test('names the durations its code takes', () {
      final text = File('doc/time.md').readAsStringSync();
      List<String?> after(String pattern) => [
            for (final match in RegExp(pattern).allMatches(text))
              match.group(1),
          ];

      expect(after(r'reads\s+the\s+rows\s+in\s+(\d+)\s+ms'), ['$readMs']);
      expect(after(r'three\s+steps\s+of\s+(\d+)\s+ms'), ['$stepMs']);
      expect(after(r'(\d+)\s+ms\s+in\b'), ['$pauseCancelMs']);
      expect(
        [
          ...after(r'is\s+given\s+(\d+)\s+ms'),
          ...after(r'takes\s+longer\s+than\s+(\d+)\s+ms'),
        ],
        ['${page.limit.inMilliseconds}', '15'],
      );
      expect(after(r'`renderThumbnail`\s+takes\s+(\d+)'), ['20']);
    });

    test('holds every block of its code in the region in its place', () {
      expect(
        codeOutOfPlace('doc/time.md', 'test/support/time_page.dart'),
        isEmpty,
      );
    });

    test('has no fence the checks do not read', () {
      expect(strayFences('doc/time.md'), isEmpty);
    });
  });
}
