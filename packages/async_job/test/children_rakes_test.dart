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

/// The first attempts of `doc/children.md`, and what each one costs.
///
/// Three sections of the page open with the version the vocabulary of the
/// API leads to and say what that version does instead of what it was
/// meant to do. Nothing else guards those statements: the page has no
/// bench, so an outcome or an order quoted there rots silently. Every
/// claim the page makes about a first attempt is pinned here, next to the
/// version it then shows.

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
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      heard.add('$job: $error');
}

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
        late final Job<int> child;
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

  group('Processing streams', () {});

  group('Chains', () {
    // The same answer whichever got there first: in the page's order the
    // source has finished and the tail is already running, in the other
    // one the tail still waits for its source.
    final orders = <String,
        Future<void> Function(
      JobContext ctx,
      Job<int> head,
      Job<void> tail,
    )>{
      'after the source, as on the page': (ctx, head, tail) async {
        await ctx.run(head);
        await ctx.run(tail);
      },
      'before the source': (ctx, head, tail) async {
        try {
          await ctx.run(tail);
        } finally {
          await ctx.run(head);
        }
      },
    };
    for (final MapEntry(key: order, value: body) in orders.entries) {
      test('ctx.run refuses a continuation $order', () {
        fakeAsync((async) {
          Object? thrown;
          final head = Job.deferred<int>((ctx) async => 1);
          final tail = head.then<void>((ctx, rows) async {});
          Job<void>((ctx) async {
            try {
              await body(ctx, head, tail);
            } on Object catch (error) {
              thrown = error;
            }
          }).ignoreFailure();

          async.flushTimers();

          expect(thrown, isA<ArgumentError>());
          // The page quotes the error whole.
          expect(
            '$thrown',
            'Invalid argument (child): is a continuation, which starts itself '
                'once its source finishes: "Job(then)"',
          );
        });
      });
    }

    test("two children in a row: the parent's cancellation reaches the second",
        () {
      fakeAsync((async) {
        late Job<void> second;
        final parent = Job<void>((ctx) async {
          final rows = await ctx.run(Job.deferred<int>((ctx) async => 21));
          second = Job.deferred<void>(
            (ctx) => ctx.join(() => delay(80 + rows)),
          );
          await ctx.run(second);
        })
          ..ignoreFailure();

        async.elapse(const Duration(milliseconds: 10));
        parent.cancel().ignore();
        async.flushTimers();

        expect(
          (second.outcome! as Cancelled).reason,
          isA<ParentCancelReason>(),
        );
      });
    });

    test(
        "the parent's cancellation reaches a continuation still waiting "
        'for its source', () {
      fakeAsync((async) {
        final head = Job.deferred<int>((ctx) async {
          await ctx.abandonable(() => delay(50));
          return 1;
        });
        final tail = head.then<void>((ctx, rows) async {})..ignoreFailure();
        final parent = Job<void>((ctx) async {
          await ctx.run(head);
        })
          ..ignoreFailure();

        async.elapse(const Duration(milliseconds: 10));
        parent.cancel().ignore();
        async.flushTimers();

        expect((tail.outcome! as Cancelled).reason, isA<ChainCancelReason>());
      });
    });

    test(
        "the parent's cancellation does not reach a continuation already "
        'running', () {
      fakeAsync((async) {
        final head = Job.deferred<int>((ctx) async => 1);
        final tail = head.then<void>((ctx, rows) async {
          await ctx.abandonable(() => delay(80));
        });
        final parent = Job<void>((ctx) async {
          await ctx.run(head);
          await ctx.abandonable(() => delay(50));
        })
          ..ignoreFailure();

        async.elapse(const Duration(milliseconds: 10));
        expect(tail.isRunning, isTrue);
        parent.cancel().ignore();
        async.flushTimers();

        expect(parent.outcome, isA<Cancelled>());
        expect(tail.outcome, isA<Done<void>>());
      });
    });

    test('the parent ends Done while the continuation is still running', () {
      fakeAsync((async) {
        final trace = <String>[];
        final head = Job.deferred<int>((ctx) async => 1);
        final tail = head.then<void>((ctx, rows) async {
          trace.add('the tail starts');
          await ctx.abandonable(() => delay(80));
          trace.add('the tail ends');
        });
        final parent = Job<void>((ctx) async {
          await ctx.run(head);
        })
          ..ignoreFailure();

        async.elapse(const Duration(milliseconds: 20));

        // The parent waits for its children, not for what hangs off them.
        expect(parent.outcome, isA<Done<void>>());
        expect(trace, ['the tail starts']);

        async.flushTimers();
        expect(trace, ['the tail starts', 'the tail ends']);
        expect(tail.outcome, isA<Done<void>>());
      });
    });

    test(
        'a parent still running stops a running continuation through '
        'onCancel', () {
      fakeAsync((async) {
        final head = Job.deferred<int>((ctx) async => 1);
        final tail = head.then<void>((ctx, rows) async {
          await ctx.abandonable(() => delay(80));
        })
          ..ignoreFailure();
        final parent = Job<void>((ctx) async {
          ctx.onCancel(() => tail.cancel().ignore());
          await ctx.run(head);
          await ctx.abandonable(() => delay(50));
        })
          ..ignoreFailure();

        async.elapse(const Duration(milliseconds: 10));
        expect(tail.isRunning, isTrue);
        parent.cancel().ignore();
        async.flushTimers();

        expect(tail.outcome, isA<Cancelled>());
      });
    });

    test(
        'a job the callback returns is not waited for, and a deferred one '
        'never starts', () {
      fakeAsync((async) {
        var ran = false;
        final saving = Job.deferred<void>((ctx) async {
          ran = true;
        });
        final parsed = Job<int>((ctx) async => 21);
        // The page says this compiles under `then<void>`.
        final stored = parsed.then<void>((ctx, number) => saving);

        async.flushTimers();

        expect(stored.outcome, isA<Done<void>>());
        expect(ran, isFalse);
        expect(saving.isFinished, isFalse);
        saving.cancel().ignore();
        async.flushTimers();
      });
    });

    test('a continuation waits for the job it runs as its child', () {
      fakeAsync((async) {
        stubs.stage = stubs.Stage();
        final parsed = Job<int>((ctx) async => 21);
        final stored = page.storeParsed(parsed);
        stored.done
            .then((outcome) => stubs.stage.trace.add('stored $outcome'))
            .ignore();

        async.flushTimers();

        expect(stubs.stage.trace, ['saved number 21', 'stored Done(null)']);
      });
    });

    test('then does not start a deferred source, whatever the length', () {
      fakeAsync((async) {
        var ran = false;
        final source = Job.deferred<int>((ctx) async {
          ran = true;
          return 1;
        });
        final last = source
            .then<int>((ctx, value) => value + 1)
            .then<int>((ctx, value) => value + 1);

        async.flushTimers();
        expect(ran, isFalse);
        expect(last.isFinished, isFalse);

        source.start();
        async.flushTimers();
        expect(last.outcome, isA<Done<int>>().having((d) => d.value, 'v', 3));
      });
    });

    test('a continuation made in a body is a root the body does not wait for',
        () {
      fakeAsync((async) {
        late final Job<void> tail;
        final parent = Job<void>((ctx) async {
          final rows = Job.deferred<int>((ctx) async => 1);
          tail = rows.then<void>((ctx, value) => ctx.join(() => delay(50)))
            ..ignoreFailure();
          await ctx.run(rows);
        });

        async.elapse(const Duration(milliseconds: 10));

        expect(parent.outcome, isA<Done<void>>());
        expect(tail.isChild, isFalse);
        expect(tail.isRunning, isTrue);
        async.flushTimers();
        expect(tail.outcome, isA<Done<void>>());
      });
    });

    test('the continuation closes the source it receives', () {
      fakeAsync((async) {
        stubs.stage = stubs.Stage();
        final (opened, archived) = page.archiveOpened();

        async.flushTimers();

        expect(opened.outcome, isA<Done<stubs.Source>>());
        expect(archived.outcome, isA<Done<void>>());
        expect(stubs.stage.trace, ['archive of 1', 'rows closed']);
      });
    });

    test(
        'cancelled while it waited, the continuation never runs, and the '
        'discard of the source closes what arrives', () {
      fakeAsync((async) {
        stubs.stage = stubs.Stage()..rowsTake = 50;
        final (opened, archived) = page.archiveOpened();
        opened.ignoreFailure();

        async.elapse(const Duration(milliseconds: 10));
        archived.cancel().ignore();
        async.flushMicrotasks();
        expect(archived.outcome, isA<Cancelled>());
        expect(opened.outcome, isA<Cancelled>());
        expect(stubs.stage.trace, isEmpty);

        async.flushTimers();
        expect(stubs.stage.trace, ['rows closed']);
      });
    });

    test(
        'a source that refuses the cancellation ends Done with the source '
        'open, and the handle closes it', () {
      fakeAsync((async) {
        stubs.stage = stubs.Stage()..rowsTake = 50;
        final opened = Job<stubs.Source>(
          cancellable: false,
          (ctx) => ctx.abandonable(
            stubs.openRows,
            discard: (source) => source.close(),
          ),
        );
        final archived = opened.then<void>((ctx, rows) async {
          ctx.onDispose(rows.close);
        });

        async.elapse(const Duration(milliseconds: 10));
        archived.cancel().ignore();
        async.flushTimers();

        expect(opened.outcome, isA<Done<stubs.Source>>());
        expect(archived.outcome, isA<Cancelled>());
        expect(stubs.stage.trace, isEmpty);

        opened.value.then((source) => source.close()).ignore();
        async.flushMicrotasks();
        expect(stubs.stage.trace, ['rows closed']);
      });
    });

    test('a source whose body awaits its continuation never finishes', () {
      fakeAsync((async) {
        final loaded = page.loadedAwaitingParsed();

        async.flushTimers();
        expect(loaded.isFinished, isFalse);

        var back = false;
        loaded.cancel().then((_) => back = true).ignore();
        async.flushTimers();
        expect(back, isFalse);
        expect(loaded.isFinished, isFalse);
      });
    });

    test('the same with done in place of value', () {
      fakeAsync((async) {
        late final Job<int> tail;
        final source = Job<int>((ctx) async {
          await tail.done;
          return 1;
        });
        tail = source.then<int>((ctx, value) => value)..ignoreFailure();

        async.flushTimers();
        expect(source.isFinished, isFalse);
        expect(tail.isFinished, isFalse);

        var back = false;
        source.cancel().then((_) => back = true).ignore();
        async.flushTimers();
        expect(back, isFalse);
      });
    });

    test(
        'a source whose cleanup awaits its continuation never finishes, '
        'and cancel() does not return', () {
      fakeAsync((async) {
        late final Job<int> tail;
        final source = Job<int>((ctx) async {
          ctx.onDispose(() => tail.done);
          return 1;
        });
        tail = source.then<int>((ctx, value) => value)..ignoreFailure();

        async.flushTimers();
        expect(source.isFinished, isFalse);
        expect(tail.isFinished, isFalse);

        var back = false;
        source.cancel().then((_) => back = true).ignore();
        async.flushTimers();
        expect(back, isFalse);
        expect(source.isFinished, isFalse);
      });
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

    test('Children: run starts the child and hands its value back', () {
      fakeAsync((async) {
        final parent = page.children();
        async.flushTimers();
        expect(parent.outcome, isA<Done<void>>());
      });
    });

    for (final fails in [false, true]) {
      test(
          'a child the body does not await: the parent waits for it, and '
          'its ignored ${fails ? 'failure' : 'value'} stays out of the zone',
          () {
        final zone = <Object>[];
        late Job<void> parent;
        runZonedGuarded(
          () => fakeAsync((async) {
            if (fails) stubs.stage.warmError = StateError('cold');
            parent = page.childNotAwaited();
            parent.done.then((outcome) => trace().add('parent $outcome'));
            async.flushTimers();
          }),
          (error, stackTrace) => zone.add(error),
        );
        expect(parent.outcome, isA<Done<void>>());
        expect(trace(), [if (!fails) 'cache warm', 'parent Done(null)']);
        expect(zone, isEmpty);
      });
    }

    test(
        'how deep a tree goes: with the await, fifty thousand levels build '
        'and finish', () async {
      final root = Job<void>((ctx) => ctx.run(page.level(50000)));
      expect(await root.done, isA<Done<void>>());
    });

    test('Future.wait: the failure that came first decides the outcome', () {
      fakeAsync((async) {
        stubs.stage
          ..rowsTake = 20
          ..rowsError = StateError('disk')
          ..imagesTake = 40
          ..imagesError = stubs.givenUp();
        final parent = page.exportWithFutureWait()..ignoreFailure();
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
          ..imagesError = stubs.givenUp();
        final parent = page.exportWithFutureWait()..ignoreFailure();
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
        final parent = page.exportWithFutureWait()..ignoreFailure();
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
        final parent = page.exportWithEagerError();
        async.elapse(const Duration(milliseconds: 40));
        expect(trace(), ['the body wakes', 'the body returns']);
        expect(parent.isFinished, isFalse, reason: 'images still opens');
        async.flushTimers();
        expect(parent.outcome, isA<Done<void>>());
        expect(trace(), ['the body wakes', 'the body returns']);
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

    test('.wait: a branch giving up ends the parent with that cancellation',
        () {
      fakeAsync((async) {
        stubs.stage.imagesError = stubs.givenUp();
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

    test(
        'a lock taken in a child of the branch: two branches share it, '
        'and the group ends', () {
      fakeAsync((async) {
        final parent = Job<void>((ctx) async {
          final sources =
              await ctx.runAll([page.lockedBranch(), page.lockedBranch()]);
          for (final source in sources) {
            source.close();
          }
        });
        async.flushTimers();
        expect(parent.outcome, isA<Done<void>>());
        expect(trace(), [
          'lock acquired',
          'lock waits',
          'lock released',
          'lock acquired',
          'lock released',
          'rows closed',
          'rows closed',
        ]);
      });
    });

    test(
        'a lock taken in a child of the branch: when the group fails, the '
        'branch closes the source after the child released the lock', () {
      fakeAsync((async) {
        final fails = Job.deferred<stubs.Source>((ctx) async {
          await ctx.abandonable(() => delay(50));
          throw StateError('disk');
        });
        final parent = Job<void>((ctx) async {
          await ctx.runAll([page.lockedBranch(), fails]);
        })
          ..ignoreFailure();
        async.flushTimers();
        expect(parent.outcome, isA<Failed>());
        expect(trace(), ['lock acquired', 'lock released', 'rows closed']);
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

    test('the same lock taken in the branch itself hangs the group', () {
      fakeAsync((async) {
        Job<stubs.Source> branch() => Job.deferred<stubs.Source>((ctx) async {
              await ctx.join(
                stubs.Lock.acquire,
                dispose: (lock) => lock.release(),
              );
              return ctx.abandonable(
                stubs.openRows,
                discard: (source) => source.close(),
              );
            });
        final parent = Job<void>((ctx) async {
          await ctx.runAll([branch(), branch()]);
        })
          ..ignoreFailure();
        async.flushTimers();
        expect(parent.isFinished, isFalse);
        expect(trace(), ['lock acquired', 'lock waits']);
        parent.cancel().ignore();
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

    List<Job<stubs.Source>> branches() => [
          Job.deferred<stubs.Source>((ctx) async => stubs.Source('rows')),
          Job.deferred<stubs.Source>((ctx) async => stubs.Source('images')),
        ];

    test(
        'the first attempt of the group closes the list when nothing '
        'interrupts it', () {
      fakeAsync((async) {
        final parent = page.groupFirstAttempt(branches());
        async.flushTimers();
        expect(parent.outcome, isA<Done<void>>());
        expect(trace(), ['archive of 2', 'rows closed', 'images closed']);
      });
    });

    test(
        'the first attempt of the group leaks the list on a stop during '
        'the archive', () {
      fakeAsync((async) {
        final parent = page.groupFirstAttempt(branches())..ignoreFailure();
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
        final parent = page.groupFirstAttempt(branches())..ignoreFailure();
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

    /// Runs [exported] next to a sibling that fails after it returned.
    Job<void> beside(Job<List<stubs.Source>> exported, {bool fails = true}) {
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
        expect(trace(), ['archive of 2', 'rows closed', 'images closed']);
      });
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

    test('saveMessages saves one message after the other', () {
      fakeAsync((async) {
        final messages = StreamController<String>();
        var over = false;
        page.saveMessages(messages.stream, (message) async {
          stubs.stage.trace.add('$message begins');
          await delay(10);
          stubs.stage.trace.add('$message saved');
        }).then((_) => over = true);
        messages
          ..add('a')
          ..add('b')
          ..close().ignore();
        async.flushTimers();
        expect(trace(), ['a begins', 'a saved', 'b begins', 'b saved']);
        expect(over, isTrue);
      });
    });

    test('the chain saves the parsed number', () {
      fakeAsync((async) {
        page.chain();
        async.flushTimers();
        expect(trace(), ['saved number 21']);
      });
    });

    test('ctx.run refuses the continuation with the error the page quotes', () {
      fakeAsync((async) {
        Object? thrown;
        page.reportedRows(adoptTheTail: true).catchError((Object error) {
          thrown = error;
        });
        async.flushTimers();
        final text = File('doc/children.md').readAsStringSync();
        final quoted = RegExp(
          r'throws `ArgumentError`:\n\n```text\n(.*?)\n```',
          dotAll: true,
        );
        final quote = quoted.firstMatch(text)!.group(1)!.replaceAll('\n', ' ');
        expect(thrown, isA<ArgumentError>());
        expect('$thrown', quote);
      });
    });

    test('with the source the only child, the parent ends first', () {
      fakeAsync((async) {
        page.reportedRows(adoptTheTail: false);
        async.flushTimers();
        expect(trace(), ['parent Done(null)', 'reported 21']);
      });
    });

    test('two children in a row: the parent waits for both', () {
      fakeAsync((async) {
        final parent = page.twoChildrenInARow();
        parent.done.then((outcome) => stubs.stage.trace.add('parent $outcome'));
        async.flushTimers();
        expect(trace(), ['reported 21', 'parent Done(null)']);
      });
    });
  });

  test('every piece of code on the page is a run of lines of these files', () {
    expect(
      codeMissingFrom(
        'doc/children.md',
        'test/support/children_page.dart',
      ),
      isEmpty,
    );
  });
}
