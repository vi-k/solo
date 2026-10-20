@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/children_page.dart' as page;
import 'support/children_stubs.dart' as stubs;
import 'support/delay.dart';
import 'support/page_code.dart';

/// What `doc/children.md` says about a child: how it runs, what a
/// cancellation of its parent does to it, and where its errors go.

/// Hears what the jobs it watches announce, and answers for nothing.
final class Listening extends JobObserver {
  final heard = <String>[];

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      heard.add('$job: $error');
}

/// Answers for what reaches it, and keeps it out of the zone.
final class _Answering extends JobObserver with JobAnswerer {
  final answered = <String>[];

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      answered.add('$error');
}

/// Starts a job under fake time and returns what was printed.
///
/// The code around the job cancels it at [cancelAt] ms, printing `cancel`
/// first. An error that reaches the zone is printed as `zone:`.
List<String> play(Job<void> Function() start, {int? cancelAt}) {
  final printed = <String>[];
  runZonedGuarded(
    () => fakeAsync((async) {
      final job = start();
      if (cancelAt != null) {
        async.elapse(Duration(milliseconds: cancelAt));
        print('cancel');
        job.cancel().ignore();
      }
      async.flushTimers();
    }),
    (error, stackTrace) => printed.add('zone: $error'),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => printed.add(line),
    ),
  );
  return printed;
}

/// The lines of every `text` block of the page, block by block.
List<List<String>> quotedOutputs() => [
      for (final block in RegExp(r'```text\n(.*?)\n```', dotAll: true)
          .allMatches(File('doc/children.md').readAsStringSync()))
        block.group(1)!.split('\n'),
    ];

void main() {
  group('Children', () {
    for (final cancellable in [false, true]) {
      for (final fromOutside in [false, true]) {
        final how = fromOutside
            ? 'the parent cancelled from outside'
            : 'a parent body that throws Cancelled';
        test(
            'a child with cancellable: $cancellable under $how, and the '
            'parent ends Cancelled after it', () {
          fakeAsync((async) {
            final trace = <String>[];
            final child = Job.deferred<int>(
              cancellable: cancellable,
              (ctx) async {
                ctx.onCancel(() => trace.add('child onCancel'));
                await ctx.abandonable(() => delay(50));
                trace.add('child ran to its end');
                return 1;
              },
            );
            final parent = Job<void>((ctx) async {
              ctx.run(child).ignore();
              if (!fromOutside) {
                await ctx.abandonable(() => delay(5));
                throw const Cancelled('gives up');
              }
              await ctx.abandonable(() => delay(100));
            });
            parent.done.then((_) => trace.add('parent finished')).ignore();
            async.elapse(const Duration(milliseconds: 10));
            if (fromOutside) {
              parent.cancel().ignore();
            }
            async.flushTimers();

            expect(parent.outcome, isA<Cancelled>());
            if (cancellable) {
              expect(trace, ['child onCancel', 'parent finished']);
              expect(
                (child.outcome! as Cancelled).reason,
                isA<ParentCancelReason>(),
              );
            } else {
              expect(
                trace,
                ['child ran to its end', 'parent finished'],
                reason: 'the child refuses, and the parent waits for it',
              );
              expect(child.outcome, isA<Done<int>>());
            }
          });
        });
      }
    }

    for (final fails in [true, false]) {
      test(
          'a run future left unhandled hands the zone '
          "${fails ? "the child's error" : "the child's Cancelled"}", () {
        final zone = <Object>[];
        late final ChildJob<int> child;
        runZonedGuarded(
          () => fakeAsync((async) {
            child = Job.deferred<int>((ctx) async {
              await ctx.abandonable(() => delay(50));
              if (fails) {
                throw StateError('disk');
              }
              return 1;
            });
            Job<void>((ctx) async {
              // ignore: unawaited_futures
              ctx.run(child);
              await ctx.abandonable(() => delay(10));
              if (!fails) {
                child.cancel().ignore();
              }
              await ctx.abandonable(() => delay(100));
            });
            async.flushTimers();
          }),
          (error, stackTrace) => zone.add(error),
        );

        expect(
          zone,
          [if (fails) isA<StateError>() else same(child.outcome)],
        );
        expect(child.outcome, fails ? isA<Failed>() : isA<Cancelled>());
      });
    }

    test(
        'ctx.run(child).ignore() keeps the error from the zone, and the '
        "child's observer still hears it", () {
      final observer = Listening();
      final zone = <Object>[];
      runZonedGuarded(
        () => fakeAsync((async) {
          final child = Job.deferred<int>(key: 'child', (ctx) async {
            await ctx.abandonable(() => delay(50));
            throw StateError('disk');
          });
          Job<void>(observer: observer, (ctx) async {
            ctx.run(child).ignore();
            await ctx.abandonable(() => delay(100));
          });
          async.flushTimers();
        }),
        (error, stackTrace) => zone.add(error),
      );

      expect(observer.heard, ['Job(child): Bad state: disk']);
      expect(zone, isEmpty);
    });
  });

  group('The code of the page', () {
    setUp(() => stubs.stage = stubs.Stage());

    List<String> trace() => stubs.stage.trace;

    test('the overview: a child, a stream and a chain', () {
      fakeAsync((async) {
        final job = page.overview();
        stubs.stage.messages
          ..add('e1')
          ..close().ignore();
        async.flushTimers();
        expect(job.outcome, isA<Done<void>>());
        expect(trace(), ['saved e1', 'reported 21']);
      });
    });

    test('the page quotes what the parent and its child print', () {
      final run = play(page.children);
      stubs.stage = stubs.Stage()..loadTake = 50;
      final cancelled = play(page.children, cancelAt: 10);
      stubs.stage = stubs.Stage()..loadTake = 50;
      final refused = play(page.refusingChild, cancelAt: 10);

      expect(run, [
        'Job(rows): Done(21)',
        'Job(parent): 21 rows',
        'Job(parent): Done(null)',
      ]);
      expect(cancelled, [
        'cancel',
        'Job(rows): Cancelled(parent)',
        'Job(parent): Cancelled(manual)',
      ]);
      expect(refused, [
        'cancel',
        'Job(rows): Done(21)',
        'Job(parent): Cancelled(manual)',
      ]);
      stubs.stage = stubs.Stage()..warmError = StateError('cold');
      final ignored = play(page.childIgnored);
      stubs.stage = stubs.Stage()..warmError = StateError('cold');
      final started = play(page.childStarted);
      expect(ignored, [
        'Job(rows): Done(21)',
        'Job(parent): 21 rows',
        'Job(cache): Failed(Bad state: cold)',
        'Job(parent): Done(null)',
      ]);
      expect(started, [...ignored, 'zone: Bad state: cold']);
      stubs.stage = stubs.Stage();
      final failed = play(page.cancelledChildFails, cancelAt: 15);
      expect(failed, [
        'cancel',
        'Job(migration): Cancelled(parent)',
        'zone: DatabaseStopped',
        'Job(parent): Cancelled(manual)',
      ]);
      expect(
        quotedOutputs(),
        [run, cancelled, refused, ignored, started, failed],
      );
    });

    test(
        'a child started and not awaited warms the cache, and the parent '
        'waits for it', () {
      final ignored = play(page.childIgnored);
      final started = play(page.childStarted);

      final warmed = [
        'Job(rows): Done(21)',
        'Job(parent): 21 rows',
        'Job(cache): Done(null)',
        'Job(parent): Done(null)',
      ];
      expect(ignored, warmed);
      expect(started, warmed);
      expect(trace(), ['cache warm', 'cache warm']);
    });

    test('a started child that fails is answered for by its observer', () {
      stubs.stage.warmError = StateError('cold');
      final answering = _Answering();
      final zone = <Object>[];
      runZonedGuarded(
        () => fakeAsync((async) {
          Job<void>((ctx) async {
            ctx.start(
              Job.deferred<void>(
                observer: answering,
                (c) => c.abandonable(stubs.warmCache),
              ),
            );
          });
          async.flushTimers();
        }),
        (error, stackTrace) => zone.add(error),
      );
      expect(answering.answered, ['Bad state: cold']);
      expect(zone, isEmpty);
    });

    test('ignoreFailure() keeps a started child from being answered for', () {
      stubs.stage.warmError = StateError('cold');
      final listening = Listening();
      final zone = <Object>[];
      runZonedGuarded(
        () => fakeAsync((async) {
          Job<void>((ctx) async {
            ctx.start(
              Job.deferred<void>(
                observer: listening,
                (c) => c.abandonable(stubs.warmCache),
              )..ignoreFailure(),
            );
          });
          async.flushTimers();
        }),
        (error, stackTrace) => zone.add(error),
      );
      expect(listening.heard, ['Job(): Bad state: cold']);
      expect(zone, isEmpty);
    });

    test(
        'how deep a tree goes: with the await, fifty thousand levels build '
        'and finish', () async {
      final root = Job<void>((ctx) => ctx.run(page.level(50000)));
      expect(await root.done, isA<Done<void>>());
    });

    test(
        'how deep a tree goes: without the await, the tree runs out of '
        'stack and still ends', () async {
      // The level of the page with its `await null` taken out.
      ChildJob<void> level(int depth) => Job.deferred<void>((ctx) async {
            if (depth > 0) await ctx.run(level(depth - 1));
          });
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(
        () => root = Job<void>((ctx) => ctx.run(level(50000))),
        (error, stackTrace) => zone.add(error),
      );
      final outcome = await root.done;
      await delay(1);

      expect(outcome, isA<Failed>());
      expect((outcome as Failed).error, isA<StackOverflowError>());
      expect(zone, everyElement(isA<StackOverflowError>()));
    });
  });

  test('every piece of code on children.md is a run of lines of the page file',
      () {
    expect(
      codeMissingFrom('doc/children.md', 'test/support/children_page.dart'),
      isEmpty,
    );
    expect(strayFences('doc/children.md'), isEmpty);
  });
}
