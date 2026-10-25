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
import 'support/groups_first_attempts.dart' as attempts;
import 'support/page_code.dart';

/// The first attempts of `doc/groups.md`, and what each one costs.
///
/// The sections of the page open with the version the vocabulary of the API
/// leads to and say what that version does instead of what it was meant to
/// do. Nothing else guards those statements: the page has no bench, so an
/// outcome or an order quoted there rots silently. Every claim the page
/// makes about a first attempt is pinned here, next to the version it then
/// shows.

/// A resource a branch opens, and a trace of who closed it.
final class Source {
  final String name;
  final List<String> trace;

  Source(this.name, this.trace);

  void close() => trace.add('$name closed');
}

/// Hears what the jobs it watches announce, and answers for nothing.
final class Listening extends JobObserver {
  final heard = <String>[];

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) =>
      heard.add('$job: $error');
}

/// The lines of every `text` block of the page, block by block.
List<List<String>> quotedOutputs() => [
      for (final block in RegExp(r'```text\n(.*?)\n```', dotAll: true)
          .allMatches(File('doc/groups.md').readAsStringSync()))
        block.group(1)!.split('\n'),
    ];

void main() {
  group('Waiting for several children', () {
    for (final observed in [true, false]) {
      test(
          'Future.wait: an observer of the parent is the one that hears it, '
          'observed: $observed', () {
        final observer = Listening();
        final zone = <String>[];
        runZonedGuarded(
          () => fakeAsync((async) {
            final fails = Job.deferred<int>(key: 'fails', (ctx) async {
              await ctx.abandonable(() => delay(80));
              throw StateError('disk');
            });
            final stops = Job.deferred<int>(key: 'stops', (ctx) async {
              await ctx.abandonable(() => delay(200));
              return 2;
            });
            Job<void>(observer: observed ? observer : null, (ctx) async {
              await Future.wait([ctx.run(fails), ctx.run(stops)]);
            }).ignoreFailure();

            async.elapse(const Duration(milliseconds: 20));
            stops.cancel().ignore();
            async.flushTimers();
          }),
          (error, stackTrace) => zone.add('$error'),
        );

        // The children have no observer of their own and inherit the
        // parent's. With none on the parent either, nothing hears the
        // failure, and the zone does not get it.
        final reason = observed ? 'the parent observed' : 'no observer';
        expect(
          observer.heard,
          observed ? ['Job(fails): Bad state: disk'] : isEmpty,
          reason: reason,
        );
        expect(zone, isEmpty, reason: reason);
      });
    }

    test('.wait: one envelope carries the cancellation and the value', () {
      fakeAsync((async) {
        final trace = <String>[];
        final opens = Job.deferred<Source>(
          key: 'opens',
          (ctx) => ctx.abandonable(
            () async => Source('rows', trace),
            discard: (source) => source.close(),
          ),
        );
        final stops = Job.deferred<Source>(key: 'stops', (ctx) async {
          await ctx.abandonable(() => delay(80));
          return Source('images', trace);
        });
        Object? caught;
        Job<void>((ctx) async {
          try {
            await [ctx.run(opens), ctx.run(stops)].wait;
          } on Object catch (error) {
            caught = error;
          }
        }).ignoreFailure();

        async.elapse(const Duration(milliseconds: 20));
        stops.cancel().ignore();
        async.flushTimers();

        final envelope =
            caught! as ParallelWaitError<List<Source?>, List<AsyncError?>>;
        expect(
          envelope.errors.whereType<AsyncError>().map((a) => a.error),
          [isA<Cancelled>()],
        );
        expect(envelope.values.whereType<Source>().map((s) => s.name), [
          'rows',
        ]);
      });
    });

    // The solution of the section, the body as on the page: each value is
    // registered on the parent the moment its branch hands it over. The
    // branches are made here only so a test can hold their handles.
    (Job<void>, Job<Source>, Job<Source>) export(
      List<String> trace, {
      bool imagesFail = false,
      bool closeTheEnvelope = false,
    }) {
      Future<Source> openRows() async {
        await delay(5);
        return Source('rows', trace);
      }

      Future<Source> openImages() async {
        await delay(10);
        if (imagesFail) throw StateError('disk');
        return Source('images', trace);
      }

      Future<void> writeArchive(List<Source> sources) async {
        await delay(50);
        trace.add('archive of ${sources.length}');
      }

      final rows = Job.deferred<Source>(
        key: 'rows',
        (ctx) => ctx.abandonable(openRows, discard: (source) => source.close()),
      );
      final images = Job.deferred<Source>(
        key: 'images',
        (ctx) =>
            ctx.abandonable(openImages, discard: (source) => source.close()),
      );
      final parent = closeTheEnvelope
          ? Job<void>((ctx) async {
              try {
                final sources = await [
                  ctx.run(rows, dispose: (source) => source.close()),
                  ctx.run(images, dispose: (source) => source.close()),
                ].wait;
                await ctx.join(() => writeArchive(sources));
              } on Object catch (error) {
                if (error
                    is ParallelWaitError<List<Source?>, List<AsyncError?>>) {
                  for (final source in error.values.whereType<Source>()) {
                    source.close();
                  }
                }
                rethrow;
              }
            })
          : Job<void>((ctx) async {
              final sources = await [
                ctx.run(rows, dispose: (source) => source.close()),
                ctx.run(images, dispose: (source) => source.close()),
              ].wait;
              await ctx.join(() => writeArchive(sources));
            })
        ..ignoreFailure();
      return (parent, rows, images);
    }

    test('.wait: closing the values of the envelope as well closes twice', () {
      fakeAsync((async) {
        final trace = <String>[];
        export(trace, imagesFail: true, closeTheEnvelope: true);
        async.flushTimers();
        expect(trace, ['rows closed', 'rows closed']);
      });
    });

    test('registering on arrival closes the source under Future.wait too', () {
      fakeAsync((async) {
        final trace = <String>[];
        final rows = Job.deferred<Source>(
          (ctx) => ctx.abandonable(
            () async => Source('rows', trace),
            discard: (source) => source.close(),
          ),
        );
        final images = Job.deferred<Source>((ctx) async {
          await ctx.abandonable(() => delay(10));
          throw StateError('disk');
        });
        final parent = Job<void>((ctx) async {
          await Future.wait([
            ctx.run(rows, dispose: (source) => source.close()),
            ctx.run(images, dispose: (source) => source.close()),
          ]);
        })
          ..ignoreFailure();

        async.flushTimers();
        // The registration closes what the first attempt lost; what
        // `.wait` adds is the outcome.
        expect(parent.outcome, isA<Failed>());
        expect(trace, ['rows closed']);
      });
    });

    test('.wait: a branch cancelled on its own leaves its sibling running', () {
      fakeAsync((async) {
        final trace = <String>[];
        final (parent, rows, images) = export(trace);
        async.elapse(const Duration(milliseconds: 2));
        images.cancel().ignore();
        async.flushTimers();
        expect(rows.outcome, isA<Done<Source>>());
        expect(images.outcome, isA<Cancelled>());
        expect(parent.outcome, isA<Cancelled>());
        // The late image closed by its branch, the rows by the parent.
        expect(trace, unorderedEquals(['images closed', 'rows closed']));
      });
    });

    test("the parent's cancellation reaches the branches of .wait", () {
      fakeAsync((async) {
        final trace = <String>[];
        final (parent, rows, images) = export(trace);
        async.elapse(const Duration(milliseconds: 2));
        parent.cancel().ignore();
        async.flushTimers();
        // Each branch walked away from its opening, and the source that
        // came late is closed by the branch's own `discard`.
        expect(trace, unorderedEquals(['rows closed', 'images closed']));
        for (final branch in [rows, images]) {
          expect(
            (branch.outcome! as Cancelled).reason,
            isA<ParentCancelReason>(),
          );
        }
      });
    });

    test('.wait: the same outcome whichever trouble arrived first', () {
      fakeAsync((async) {
        Outcome<void>? outcomeOnFailureFirst;
        Outcome<void>? outcomeOnCancellationFirst;

        for (final failureFirst in [true, false]) {
          final fails = Job.deferred<int>(key: 'fails', (ctx) async {
            await ctx.abandonable(() => delay(failureFirst ? 20 : 80));
            throw StateError('disk');
          });
          final stops = Job.deferred<int>(key: 'stops', (ctx) async {
            await ctx.abandonable(() => delay(200));
            return 2;
          });
          final parent = Job<void>((ctx) async {
            await [ctx.run(fails), ctx.run(stops)].wait;
          })
            ..ignoreFailure();

          async.elapse(Duration(milliseconds: failureFirst ? 40 : 30));
          stops.cancel().ignore();
          async.flushTimers();
          if (failureFirst) {
            outcomeOnFailureFirst = parent.outcome;
          } else {
            outcomeOnCancellationFirst = parent.outcome;
          }
        }

        expect(outcomeOnFailureFirst, isA<Failed>());
        expect(outcomeOnCancellationFirst, isA<Failed>());
        expect(
          (outcomeOnFailureFirst! as Failed).error,
          isA<ParallelWaitError<List<int?>, List<AsyncError?>>>(),
        );
        expect(
          (outcomeOnCancellationFirst! as Failed).error,
          isA<ParallelWaitError<List<int?>, List<AsyncError?>>>(),
        );
      });
    });
  });

  group('What ctx.runAll waits for', () {
    // The table of forms: on success the cleanup of every branch, except
    // one a branch registers after running it, and the values come out
    // before the branches end; on failure every branch to its end.
    for (final fails in [false, true]) {
      test(
          'on ${fails ? 'failure' : 'success'} the group comes out after the '
          'cleanup, ${fails ? 'after' : 'before'} the end of the branches', () {
        fakeAsync((async) {
          final trace = <String>[];
          final branches = <Job<int>>[];
          ChildJob<int> branch(String name, {bool failing = false}) {
            final job = Job.deferred<int>((ctx) async {
              ctx.onDispose(() async {
                await delay(30);
                trace.add('$name cleaned up');
              });
              await ctx.abandonable(() => delay(10));
              if (failing) throw StateError(name);
              return 1;
            });
            branches.add(job);
            return job;
          }

          String ended() => [
                for (final job in branches)
                  if (job.isFinished) 'ended' else 'not',
              ].join(' ');
          Job<void>((ctx) async {
            try {
              await ctx.runAll([branch('a'), branch('b', failing: fails)]);
              trace.add('values, branches ${ended()}');
            } on Object {
              trace.add('error, branches ${ended()}');
            }
          });
          async.flushTimers();
          expect(trace, [
            'a cleaned up',
            'b cleaned up',
            if (fails)
              'error, branches ended ended'
            else
              'values, branches not not',
          ]);
        });
      });
    }

    test(
        'a cleanup a branch registers after its own has run comes after the '
        'values', () {
      fakeAsync((async) {
        final trace = <String>[];
        final early = Job.deferred<int>((ctx) async {
          // By the time the timer fires, the group has decided and this
          // branch has run its cleanup: it waits for the cleanup of `late`.
          Timer(const Duration(milliseconds: 30), () {
            trace.add('a registered late');
            ctx.onDispose(() => trace.add('a late cleanup'));
          });
          return 1;
        });
        final late = Job.deferred<int>((ctx) async {
          ctx.onDispose(() async {
            await delay(30);
            trace.add('b cleaned up');
          });
          await ctx.abandonable(() => delay(20));
          return 2;
        });
        Job<void>((ctx) async {
          final values = await ctx.runAll([early, late]);
          trace.add('values $values');
        });
        async.flushTimers();
        expect(trace, [
          'a registered late',
          'b cleaned up',
          'values [1, 2]',
          'a late cleanup',
        ]);
      });
    });

    // The table of stages: a `discard` is set aside at the cleanup, and on
    // success it never runs, neither on the stack nor after the hand-over.
    test('on success no discard of a branch ever runs', () {
      fakeAsync((async) {
        final trace = <String>[];
        ChildJob<int> branch(String name, int value) =>
            Job.deferred<int>((ctx) async {
              ctx
                ..onDispose(() => trace.add('$name dispose'))
                ..onDiscard(() => trace.add('$name onDiscard'));
              await ctx.abandonable(
                () => delay(value * 10),
                discard: (_) => trace.add('$name discard'),
              );
              return value;
            });
        final a = branch('a', 1);
        final b = branch('b', 2);
        final parent = Job<void>((ctx) async {
          final values = await ctx.runAll([a, b]);
          trace.add('values $values');
        });
        async.flushTimers();
        expect(trace, ['a dispose', 'b dispose', 'values [1, 2]']);
        expect(a.outcome, isA<Done<int>>());
        expect(b.outcome, isA<Done<int>>());
        expect(parent.outcome, isA<Done<void>>());
      });
    });

    test('a cleanup a branch registers before its own has run comes first', () {
      fakeAsync((async) {
        final trace = <String>[];
        final early = Job.deferred<int>((ctx) async {
          Timer(const Duration(milliseconds: 5), () {
            ctx.onDispose(() => trace.add('a cleanup'));
          });
          return 1;
        });
        final late = Job.deferred<int>((ctx) async {
          await ctx.abandonable(() => delay(20));
          return 2;
        });
        Job<void>((ctx) async {
          final values = await ctx.runAll([early, late]);
          trace.add('values $values');
        });
        async.flushTimers();
        expect(trace, ['a cleanup', 'values [1, 2]']);
      });
    });
  });

  group('When one failure makes the rest pointless', () {
    test('a branch held for the group has no outcome yet', () {
      fakeAsync((async) {
        final quick = Job.deferred<int>(key: 'quick', (ctx) async => 1);
        final slow = Job.deferred<int>(key: 'slow', (ctx) async {
          await ctx.abandonable(() => delay(50));
          throw StateError('disk');
        });
        Job<void>((ctx) async {
          await ctx.runAll([quick, slow]);
        }).ignoreFailure();

        async.elapse(const Duration(milliseconds: 10));
        // Its body returned a value, and the group has not decided.
        expect(quick.outcome, isNull);
        expect(quick.isCancelled, isFalse);

        async.flushTimers();
        expect(quick.outcome, isA<Cancelled>());
        expect(quick.isCancelled, isTrue);
      });
    });

    test('a held branch with cancellable: false refuses and ends Done', () {
      fakeAsync((async) {
        final quick = Job.deferred<int>(
          key: 'quick',
          cancellable: false,
          (ctx) async => 1,
        );
        final slow = Job.deferred<int>(key: 'slow', (ctx) async {
          await ctx.abandonable(() => delay(50));
          throw StateError('disk');
        });
        Job<void>((ctx) async {
          await ctx.runAll([quick, slow]);
        }).ignoreFailure();

        async.flushTimers();
        expect(quick.outcome, isA<Done<int>>());
        expect(quick.isCancelled, isFalse);
      });
    });
  });

  group('The list a group returns', () {
    var closed = <String>[];
    setUp(() => closed = []);

    Job<void> onDisposeOnTheNextLine() => Job<void>((ctx) async {
          final sources = await ctx.runAll([
            Job.deferred<Source>((ctx) async => Source('rows', closed)),
          ]);
          ctx.onDispose(() {
            for (final source in sources) {
              source.close();
            }
          });
          await ctx.join(() => delay(50));
          throw StateError('disk');
        });

    test('onDispose on the next line closes the list on a stop', () {
      fakeAsync((async) {
        final parent = onDisposeOnTheNextLine()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));
        parent.cancel().ignore();
        async.flushTimers();
        expect(parent.outcome, isA<Cancelled>());
        expect(closed, ['rows closed']);
      });
    });

    test('onDispose on the next line closes the list on an error', () {
      fakeAsync((async) {
        final parent = onDisposeOnTheNextLine()..ignoreFailure();
        async.flushTimers();
        expect(parent.outcome, isA<Failed>());
        expect(closed, ['rows closed']);
      });
    });
  });

  group('The code of the page', () {
    setUp(() => stubs.stage = stubs.Stage());

    List<String> trace() => stubs.stage.trace;

    test('Future.wait: the failure that came first decides the outcome', () {
      fakeAsync((async) {
        stubs.stage
          ..rowsTake = 20
          ..rowsError = StateError('disk')
          ..imagesTake = 40
          ..imagesError = stubs.selfCancel();
        final parent = attempts.exportWithFutureWait()..ignoreFailure();
        async.flushTimers();
        expect(parent.outcome, isA<Failed>());
        expect((parent.outcome! as Failed).error, isA<StateError>());
      });
    });

    test('Future.wait: the cancellation that came first decides it instead',
        () {
      fakeAsync((async) {
        stubs.stage
          ..rowsTake = 40
          ..rowsError = StateError('disk')
          ..imagesTake = 20
          ..imagesError = stubs.selfCancel();
        final parent = attempts.exportWithFutureWait()..ignoreFailure();
        async.flushTimers();
        // The failure of `rows` is nowhere in the outcome.
        expect(parent.outcome, isA<Cancelled>());
        expect(
          (parent.outcome! as Cancelled).reason,
          isA<HandlerCancelReason>(),
        );
      });
    });

    test('Future.wait: nobody closes the source of the branch that succeeded',
        () {
      fakeAsync((async) {
        stubs.stage
          ..imagesTake = 20
          ..imagesError = StateError('disk');
        final parent = attempts.exportWithFutureWait()..ignoreFailure();
        async.flushTimers();
        expect(parent.outcome, isA<Failed>());
        expect(trace(), isEmpty);
      });
    });

    test('eagerError wakes the body and changes nothing else', () {
      fakeAsync((async) {
        stubs.stage
          ..rowsTake = 20
          ..rowsError = StateError('disk')
          ..imagesTake = 80;
        final parent = attempts.exportWithEagerError();
        async.elapse(const Duration(milliseconds: 40));
        expect(trace(), ['the body wakes', 'the body returns']);
        expect(parent.isFinished, isFalse, reason: 'images still opens');
        async.flushTimers();
        expect(parent.outcome, isA<Done<void>>());
        expect(trace(), ['the body wakes', 'the body returns']);
      });
    });

    test(
        'eagerError: a branch that ends Cancelled first cancels the job '
        'and the other branch', () {
      fakeAsync((async) {
        stubs.stage
          ..rowsTake = 20
          ..rowsError = stubs.selfCancel()
          ..imagesTake = 80;
        late final ChildJob<stubs.Source> images;
        final parent = Job<void>((ctx) async {
          final rows = Job.deferred<stubs.Source>(
            (ctx) => ctx.abandonable(
              stubs.openRows,
              discard: (source) => source.close(),
            ),
          );
          images = Job.deferred<stubs.Source>(
            (ctx) => ctx.abandonable(
              stubs.openImages,
              discard: (source) => source.close(),
            ),
          );
          final sources = await Future.wait(
            [ctx.run(rows), ctx.run(images)],
            eagerError: true,
          );
          await ctx.join(() => stubs.writeArchive(sources));
        });

        async.elapse(const Duration(milliseconds: 40));

        expect(
          (parent.outcome! as Cancelled).reason,
          isA<HandlerCancelReason>(),
        );
        expect(
          (images.outcome! as Cancelled).reason,
          isA<ParentCancelReason>(),
          reason: 'the job ended before images opened',
        );
        async.flushTimers();
        expect(trace(), ['images closed']);
      });
    });

    test('.wait: every source is closed once when the export succeeds', () {
      fakeAsync((async) {
        final parent = page.exportWithWait();
        async.flushTimers();
        expect(parent.outcome, isA<Done<void>>());
        expect(trace(), ['archive of 2', 'images closed', 'rows closed']);
      });
    });

    test('.wait: the source that came back is closed when the other fails', () {
      fakeAsync((async) {
        stubs.stage.imagesError = StateError('disk');
        final parent = page.exportWithWait()..ignoreFailure();
        async.flushTimers();
        expect(parent.outcome, isA<Failed>());
        expect(trace(), ['rows closed']);
      });
    });

    test(
        '.wait: a branch cancelling itself ends the parent '
        'with that cancellation', () {
      fakeAsync((async) {
        stubs.stage.imagesError = stubs.selfCancel();
        final parent = page.exportWithWait()..ignoreFailure();
        async.flushTimers();
        expect(parent.outcome, isA<Cancelled>());
        expect(trace(), ['rows closed']);
      });
    });

    test('.wait: both are closed when the parent is cancelled while writing',
        () {
      fakeAsync((async) {
        final parent = page.exportWithWait();
        async.elapse(const Duration(milliseconds: 30));
        parent.cancel().ignore();
        async.flushTimers();
        // `join` waits the step out, and the cancellation comes after it.
        expect(parent.outcome, isA<Cancelled>());
        expect(trace(), ['archive of 2', 'images closed', 'rows closed']);
      });
    });

    test('the page quotes what the export and the lock scenes report', () {
      List<String> run(Job<Object?> Function() start) {
        stubs.stage = stubs.Stage();
        late List<String> printed;
        fakeAsync((async) {
          if (start == page.exportWithWait) {
            stubs.stage.imagesError = StateError('disk');
          }
          final parent = start()..ignoreFailure();
          parent.done.then((o) => trace().add('outcome: $o')).ignore();
          async.flushTimers();
          printed = [...trace()];
          if (!parent.isFinished) parent.cancel().ignore();
          async.flushTimers();
        });
        return printed;
      }

      final registered = run(page.exportWithWait);
      final hung = run(attempts.readingTwice);
      final locked = run(page.readingTwice);

      expect(registered, [
        'rows closed',
        'outcome: Failed(ParallelWaitError: Bad state: disk)',
      ]);
      expect(hung, ['lock acquired', 'lock waits']);
      expect(locked, [
        'lock acquired',
        'lock waits',
        'lock released',
        'lock acquired',
        'lock released',
        'outcome: Done([21, 21])',
      ]);
      expect(quotedOutputs(), [registered, hung, locked]);
    });

    test('a cancelled parent does not untie the lock of the first attempt', () {
      fakeAsync((async) {
        final parent = attempts.readingTwice()..ignoreFailure();
        async.flushTimers();
        parent.cancel().ignore();
        async.flushTimers();
        expect(parent.isFinished, isFalse);
        expect(trace(), ['lock acquired', 'lock waits']);
      });
    });

    test('cancelling the branch that holds the lock unties nothing', () {
      fakeAsync((async) {
        final holding = attempts.reading();
        final parent = Job<List<int>>(
          (ctx) => ctx.runAll([holding, attempts.reading()]),
        )..ignoreFailure();
        async.flushTimers();
        holding.cancel().ignore();
        async.flushTimers();
        expect(holding.isFinished, isFalse);
        expect(parent.isFinished, isFalse);
        expect(trace(), ['lock acquired', 'lock waits']);
      });
    });

    test(
        'a branch that gets its source from a child closes it when the '
        'group fails', () {
      fakeAsync((async) {
        final fails = Job.deferred<stubs.Source>((ctx) async {
          await ctx.abandonable(() => delay(50));
          throw StateError('disk');
        });
        final parent = Job<void>((ctx) async {
          await ctx.runAll<stubs.Source>([page.openingBranch(), fails]);
        })
          ..ignoreFailure();
        async.flushTimers();
        expect(parent.outcome, isA<Failed>());
        expect(trace(), ['rows closed']);
      });
    });

    test(
        'a branch that gets its source from a child hands it over open when '
        'the group succeeds', () {
      fakeAsync((async) {
        final parent = Job<void>((ctx) async {
          final sources = await ctx.runAll<stubs.Source>([
            page.openingBranch(),
            page.openingBranch(),
          ]);
          trace().add('${sources.length} arrived');
        });
        async.flushTimers();
        expect(parent.outcome, isA<Done<void>>());
        expect(trace(), ['2 arrived']);
      });
    });

    test(
        'a branch with cancellable: false ends Done under a failed group, '
        'and the body closes its value through the job it passed', () {
      fakeAsync((async) {
        stubs.stage.imagesError = StateError('disk');
        final parent = page.refusingBranch()..ignoreFailure();
        async.flushTimers();
        expect(parent.outcome, isA<Failed>());
        expect(trace(), ['rows closed']);
      });
    });

    test('runAll hands the values back in the order of the list', () {
      fakeAsync((async) {
        final job = page.loadAll();
        async.flushTimers();
        expect((job.outcome! as Done<List<int>>).value, [21, 1]);
      });
    });

    test('a branch closes what it keeps and hands out what it returns', () {
      fakeAsync((async) {
        Job<void>((ctx) async {
          final rows = await ctx.run(page.warmingBranch());
          stubs.stage.trace.add('the caller got ${rows.name}');
          rows.close();
        });
        async.flushTimers();
        expect(trace(), [
          'cache warmed',
          'cache closed',
          'the caller got rows',
          'rows closed',
        ]);
      });
    });

    test('a branch closes what it took before a failed group returns', () {
      fakeAsync((async) {
        Job<void>((ctx) async {
          try {
            await ctx.runAll([
              page.warmingBranch(),
              Job.deferred<stubs.Source>((ctx) async {
                await ctx.abandonable(() => delay(20));
                throw StateError('disk');
              }),
            ]);
          } on Object catch (error) {
            stubs.stage.trace.add('the parent catches $error');
          }
        });
        async.flushTimers();
        expect(trace(), [
          'cache warmed',
          // The cleanup unwinds from the last registration.
          'rows closed',
          'cache closed',
          'the parent catches Bad state: disk',
        ]);
      });
    });

    List<ChildJob<stubs.Source>> branches() => [
          Job.deferred<stubs.Source>((ctx) async => stubs.Source('rows')),
          Job.deferred<stubs.Source>((ctx) async => stubs.Source('images')),
        ];

    test(
        'the first attempt of the group closes the list when nothing '
        'interrupts it', () {
      fakeAsync((async) {
        final parent = attempts.groupFirstAttempt(branches());
        async.flushTimers();
        expect(parent.outcome, isA<Done<void>>());
        expect(trace(), ['archive of 2', 'rows closed', 'images closed']);
      });
    });

    test(
        'the first attempt of the group leaks the list on a stop during '
        'the archive', () {
      fakeAsync((async) {
        final parent = attempts.groupFirstAttempt(branches())..ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));
        parent.cancel().ignore();
        async.flushTimers();
        // `join` waits the archive out and lets the cancellation out in
        // place of its value: the body never reaches the loop.
        expect(parent.outcome, isA<Cancelled>());
        expect(trace(), ['archive of 2']);
      });
    });

    test('the first attempt of the group leaks the list on a failing archive',
        () {
      fakeAsync((async) {
        stubs.stage.archiveError = StateError('disk');
        final parent = attempts.groupFirstAttempt(branches())..ignoreFailure();
        async.flushTimers();
        expect(parent.outcome, isA<Failed>());
        expect(trace(), isEmpty);
      });
    });

    test('the try closes the list on a stop during the archive', () {
      fakeAsync((async) {
        final parent = page.groupTry(branches())..ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));
        parent.cancel().ignore();
        async.flushTimers();
        expect(parent.outcome, isA<Cancelled>());
        expect(trace(), ['archive of 2', 'rows closed', 'images closed']);
      });
    });

    test('the try closes the list on a failing archive', () {
      fakeAsync((async) {
        stubs.stage.archiveError = StateError('disk');
        final parent = page.groupTry(branches())..ignoreFailure();
        async.flushTimers();
        expect(parent.outcome, isA<Failed>());
        expect(trace(), ['rows closed', 'images closed']);
      });
    });

    test('a close that throws ends the loop of the try', () {
      fakeAsync((async) {
        stubs.stage.closeFails = 'rows';
        final parent = page.groupTry(branches())..ignoreFailure();
        async.flushTimers();
        expect(parent.outcome, isA<Failed>());
        expect(trace(), ['archive of 2', 'rows close failed']);
      });
    });

    test('the registrations close the list on a stop during the archive', () {
      fakeAsync((async) {
        final parent = page.groupRegistered(branches())..ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));
        parent.cancel().ignore();
        async.flushTimers();
        expect(parent.outcome, isA<Cancelled>());
        expect(trace(), ['archive of 2', 'images closed', 'rows closed']);
      });
    });

    test('the registrations close the list on a failing archive', () {
      fakeAsync((async) {
        stubs.stage.archiveError = StateError('disk');
        final parent = page.groupRegistered(branches())..ignoreFailure();
        async.flushTimers();
        expect(parent.outcome, isA<Failed>());
        expect(trace(), ['images closed', 'rows closed']);
      });
    });

    for (final fails in ['images', 'rows']) {
      test('the registrations close the other source when $fails throws', () {
        final zone = <Object>[];
        late Job<void> parent;
        runZonedGuarded(
          () => fakeAsync((async) {
            stubs.stage.closeFails = fails;
            parent = page.groupRegistered(branches());
            async.flushTimers();
          }),
          (error, stackTrace) => zone.add(error),
        );
        expect(parent.outcome, isA<Done<void>>());
        expect(trace(), [
          'archive of 2',
          if (fails == 'images') 'images close failed' else 'images closed',
          if (fails == 'rows') 'rows close failed' else 'rows closed',
        ]);
        expect(zone, [isA<StateError>()]);
      });
    }

    /// Runs [exported] next to a sibling that fails after it returned.
    Job<void> beside(
      ChildJob<List<stubs.Source>> exported, {
      bool fails = true,
    }) {
      final sibling = Job.deferred<void>((ctx) async {
        await ctx.join(() => delay(80));
        if (fails) throw StateError('sibling');
      });
      return Job<void>((ctx) async {
        final lists = await ctx.runAll<Object?>([exported, sibling]);
        stubs.stage.trace.add('${(lists.first! as List).length} arrived');
      });
    }

    test('catch closes a handed-out list on a failing archive', () {
      fakeAsync((async) {
        stubs.stage.archiveError = StateError('disk');
        final exported = page.handedOutCatch(branches());
        final parent = beside(exported)..ignoreFailure();
        async.flushTimers();
        expect(parent.outcome, isA<Failed>());
        expect(trace(), ['rows closed', 'images closed']);
      });
    });

    test('catch leaks a handed-out list a failing sibling takes away', () {
      fakeAsync((async) {
        final exported = page.handedOutCatch(branches());
        final parent = beside(exported)..ignoreFailure();
        async.flushTimers();
        // The body returned at 50, the sibling fails at 80: the branch is
        // cancelled with its value in hand, and nothing closes the list.
        expect(exported.outcome, isA<Cancelled>());
        expect(parent.outcome, isA<Failed>());
        expect(trace(), ['archive of 2']);
      });
    });

    test('onDiscard closes a handed-out list a failing sibling takes away', () {
      fakeAsync((async) {
        final exported = page.handedOutDiscard(branches());
        final parent = beside(exported)..ignoreFailure();
        async.flushTimers();
        expect(exported.outcome, isA<Cancelled>());
        expect(parent.outcome, isA<Failed>());
        expect(trace(), ['archive of 2', 'images closed', 'rows closed']);
      });
    });

    test(
        'onDiscard closes the other source of a list taken away when one '
        'throws', () {
      final zone = <Object>[];
      late Job<void> parent;
      runZonedGuarded(
        () => fakeAsync((async) {
          stubs.stage.closeFails = 'images';
          parent = beside(page.handedOutDiscard(branches()))..ignoreFailure();
          async.flushTimers();
        }),
        (error, stackTrace) => zone.add(error),
      );
      expect(parent.outcome, isA<Failed>());
      expect(trace(), ['archive of 2', 'images close failed', 'rows closed']);
      expect(zone, [isA<StateError>()]);
    });

    test('onDiscard leaves a handed-out list open when it arrives', () {
      fakeAsync((async) {
        final exported = page.handedOutDiscard(branches());
        final parent = beside(exported, fails: false);
        async.flushTimers();
        expect(parent.outcome, isA<Done<void>>());
        expect(trace(), ['archive of 2', '2 arrived']);
      });
    });
  });

  test('every piece of code on groups.md is a run of lines of these files', () {
    expect(
      codeMissingFrom(
        'doc/groups.md',
        'test/support/children_page.dart',
        alsoIn: ['test/support/groups_first_attempts.dart'],
      ),
      isEmpty,
    );
    expect(strayFences('doc/groups.md'), isEmpty);
  });

  test('the code under every first attempt is the first attempt', () {
    expect(
      codeMissingFrom(
        'doc/groups.md',
        'test/support/groups_first_attempts.dart',
        under: '### The first attempt',
      ),
      isEmpty,
    );
  });
}
