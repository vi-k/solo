@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

/// The first attempts of `doc/children.md`, and what each one costs.
///
/// Four sections of the page open with the version the vocabulary of the
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
  group('Waiting for several children', () {
    test('Future.wait: the failure that came first decides the outcome', () {
      fakeAsync((async) {
        final fails = Job.deferred<int>(key: 'fails', (ctx) async {
          await ctx.wait(() => delay(20));
          throw StateError('disk');
        });
        final stops = Job.deferred<int>(key: 'stops', (ctx) async {
          await ctx.wait(() => delay(80));
          return 2;
        });
        final parent = Job<void>((ctx) async {
          await Future.wait([ctx.run(fails), ctx.run(stops)]);
        })
          ..ignore();

        async.elapse(const Duration(milliseconds: 40));
        stops.cancel().ignore();
        async.flushTimers();

        // The failure reached `Future.wait` first, so the cancellation of
        // the other branch is nowhere in the outcome.
        expect(parent.outcome, isA<Failed>());
        expect((parent.outcome! as Failed).error, isA<StateError>());
      });
    });

    test('Future.wait: the cancellation that came first decides it instead',
        () {
      fakeAsync((async) {
        final fails = Job.deferred<int>(key: 'fails', (ctx) async {
          await ctx.wait(() => delay(80));
          throw StateError('disk');
        });
        final stops = Job.deferred<int>(key: 'stops', (ctx) async {
          await ctx.wait(() => delay(200));
          return 2;
        });
        final parent = Job<void>((ctx) async {
          await Future.wait([ctx.run(fails), ctx.run(stops)]);
        })
          ..ignore();

        async.elapse(const Duration(milliseconds: 20));
        stops.cancel().ignore();
        async.flushTimers();

        // The same two branches, the other order: the failure of `fails`
        // is the one that leaves no trace.
        expect(parent.outcome, isA<Cancelled>());
        expect(
          (parent.outcome! as Cancelled).reason,
          isA<HandlerCancelReason>(),
        );
      });
    });

    for (final observed in [true, false]) {
      test(
          'Future.wait: an observer of the parent is the one that hears it, '
          'observed: $observed', () {
        final observer = Listening();
        final zone = <String>[];
        runZonedGuarded(
          () => fakeAsync((async) {
            final fails = Job.deferred<int>(key: 'fails', (ctx) async {
              await ctx.wait(() => delay(80));
              throw StateError('disk');
            });
            final stops = Job.deferred<int>(key: 'stops', (ctx) async {
              await ctx.wait(() => delay(200));
              return 2;
            });
            Job<void>(observer: observed ? observer : null, (ctx) async {
              await Future.wait([ctx.run(fails), ctx.run(stops)]);
            }).ignore();

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

    test('Future.wait: nobody closes what the other branch handed over', () {
      fakeAsync((async) {
        final trace = <String>[];
        final opens = Job.deferred<Source>(
          key: 'opens',
          (ctx) => ctx.wait(
            () async => Source('rows', trace),
            discard: (source) => source.close(),
          ),
        );
        final fails = Job.deferred<Source>(key: 'fails', (ctx) async {
          await ctx.wait(() => delay(20));
          throw StateError('disk');
        });
        Job<void>((ctx) async {
          final sources = await Future.wait([ctx.run(opens), ctx.run(fails)]);
          trace.add('the body got ${sources.length} sources');
        }).ignore();

        async.flushTimers();

        // The branch ended `Done` and handed its source over, so its own
        // cleanup never closes it; the body it went to never received it.
        expect(opens.outcome, isA<Done<Source>>());
        expect(trace, isEmpty);
      });
    });

    test('Future.wait with eagerError wakes the body and nothing else', () {
      fakeAsync((async) {
        final trace = <String>[];
        final fails = Job.deferred<int>(key: 'fails', (ctx) async {
          await ctx.wait(() => delay(20));
          throw StateError('disk');
        });
        final slow = Job.deferred<int>(key: 'slow', (ctx) async {
          await ctx.wait(() => delay(80));
          trace.add('the slow branch returns');
          return 1;
        });
        final parent = Job<void>((ctx) async {
          try {
            await Future.wait(
              [ctx.run(fails), ctx.run(slow)],
              eagerError: true,
            );
          } on Object {
            trace.add('the body wakes');
          }
          trace.add('the body returns');
        })
          ..done.then((outcome) => trace.add('parent $outcome'));

        async.flushTimers();

        // The body wakes at the first error, and the job still ends when
        // the last branch does.
        expect(trace, [
          'the body wakes',
          'the body returns',
          'the slow branch returns',
          'parent Done(null)',
        ]);
        expect(parent.outcome, isA<Done<void>>());
      });
    });

    test('.wait: one envelope carries the cancellation and the value', () {
      fakeAsync((async) {
        final trace = <String>[];
        final opens = Job.deferred<Source>(
          key: 'opens',
          (ctx) => ctx.wait(
            () async => Source('rows', trace),
            discard: (source) => source.close(),
          ),
        );
        final stops = Job.deferred<Source>(key: 'stops', (ctx) async {
          await ctx.wait(() => delay(80));
          return Source('images', trace);
        });
        Object? caught;
        Job<void>((ctx) async {
          try {
            await [ctx.run(opens), ctx.run(stops)].wait;
          } on Object catch (error) {
            caught = error;
          }
        }).ignore();

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
        (ctx) => ctx.wait(openRows, discard: (source) => source.close()),
      );
      final images = Job.deferred<Source>(
        key: 'images',
        (ctx) => ctx.wait(openImages, discard: (source) => source.close()),
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
        ..ignore();
      return (parent, rows, images);
    }

    test('.wait: every source is closed once when the export succeeds', () {
      fakeAsync((async) {
        final trace = <String>[];
        final (parent, _, _) = export(trace);
        async.flushTimers();
        expect(parent.outcome, isA<Done<void>>());
        expect(trace, ['archive of 2', 'images closed', 'rows closed']);
      });
    });

    test('.wait: the source that came back is closed when the other fails', () {
      fakeAsync((async) {
        final trace = <String>[];
        final (parent, _, _) = export(trace, imagesFail: true);
        async.flushTimers();
        expect(parent.outcome, isA<Failed>());
        expect(trace, ['rows closed']);
      });
    });

    test('.wait: both are closed when the parent is cancelled while writing',
        () {
      fakeAsync((async) {
        final trace = <String>[];
        final (parent, _, _) = export(trace);
        async.elapse(const Duration(milliseconds: 30));
        parent.cancel().ignore();
        async.flushTimers();
        // `join` waits the step out, and the cancellation comes after it.
        expect(parent.outcome, isA<Cancelled>());
        expect(trace, ['archive of 2', 'images closed', 'rows closed']);
      });
    });

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
          (ctx) => ctx.wait(
            () async => Source('rows', trace),
            discard: (source) => source.close(),
          ),
        );
        final images = Job.deferred<Source>((ctx) async {
          await ctx.wait(() => delay(10));
          throw StateError('disk');
        });
        final parent = Job<void>((ctx) async {
          await Future.wait([
            ctx.run(rows, dispose: (source) => source.close()),
            ctx.run(images, dispose: (source) => source.close()),
          ]);
        })
          ..ignore();

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
            await ctx.wait(() => delay(failureFirst ? 20 : 80));
            throw StateError('disk');
          });
          final stops = Job.deferred<int>(key: 'stops', (ctx) async {
            await ctx.wait(() => delay(200));
            return 2;
          });
          final parent = Job<void>((ctx) async {
            await [ctx.run(fails), ctx.run(stops)].wait;
          })
            ..ignore();

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
          await ctx.wait(() => delay(50));
          throw StateError('disk');
        });
        Job<void>((ctx) async {
          await ctx.runAll([quick, slow]);
        }).ignore();

        async.elapse(const Duration(milliseconds: 10));
        // Its body returned a value, and the group has not decided.
        expect(quick.outcome, isNull);
        expect(quick.isCancelled, isFalse);

        async.flushTimers();
        expect(quick.outcome, isA<Cancelled>());
      });
    });
  });

  group('What a group hands back', () {
    // The first attempt, as on the page: the manifest is a step the
    // cancellation can arrive during.
    Job<void> firstAttempt(List<String> trace) {
      final branches = [
        Job.deferred<Source>((ctx) async => Source('rows', trace)),
        Job.deferred<Source>((ctx) async => Source('images', trace)),
      ];
      Future<void> loadManifest() => delay(40);
      return Job<void>((ctx) async {
        final sources = await ctx.runAll(branches);
        await ctx.join(loadManifest);
        await ctx.wait(
          () => sources,
          dispose: (values) {
            for (final source in values) {
              source.close();
            }
          },
        );
        trace.add('registered');
      })
        ..ignore();
    }

    test('the first attempt closes the list when nothing interrupts it', () {
      fakeAsync((async) {
        final trace = <String>[];
        final parent = firstAttempt(trace);
        async.flushTimers();
        expect(parent.outcome, isA<Done<void>>());
        expect(trace, ['registered', 'rows closed', 'images closed']);
      });
    });

    test('the first attempt leaks the list on a stop during the manifest', () {
      fakeAsync((async) {
        final trace = <String>[];
        final parent = firstAttempt(trace);
        async.elapse(const Duration(milliseconds: 20));
        parent.cancel().ignore();
        async.flushTimers();
        // `join` waits the manifest out and lets the cancellation out in
        // place of its value: the body never reaches the registration.
        expect(parent.outcome, isA<Cancelled>());
        expect(trace, isEmpty);
      });
    });

    test('ctx.wait throws before its action on a pending cancellation', () {
      fakeAsync((async) {
        final trace = <String>[];
        Object? thrownAtRegistration;
        final parent = Job<void>((ctx) async {
          final sources = await ctx.runAll([
            Job.deferred<Source>((ctx) async => Source('rows', trace)),
          ]);
          try {
            await ctx.wait(() => delay(40));
          } on Cancelled {
            trace.add('the manifest was cancelled');
          }
          try {
            await ctx.wait(
              () {
                trace.add('the action ran');
                return sources;
              },
              dispose: (values) {
                for (final source in values) {
                  source.close();
                }
              },
            );
            trace.add('registered');
          } on Cancelled catch (error) {
            thrownAtRegistration = error;
          }
        })
          ..ignore();

        async.elapse(const Duration(milliseconds: 20));
        parent.cancel().ignore();
        async.flushTimers();

        // Even a body that caught the first checkpoint gets no further:
        // the one of `wait` comes before its action.
        expect(thrownAtRegistration, isA<Cancelled>());
        expect(trace, ['the manifest was cancelled']);
      });
    });

    test('onDispose registers on a job already marked', () {
      fakeAsync((async) {
        final trace = <String>[];
        final parent = Job<void>((ctx) async {
          final sources = await ctx.runAll([
            Job.deferred<Source>((ctx) async => Source('rows', trace)),
          ]);
          try {
            await ctx.wait(() => delay(40));
          } on Cancelled {
            trace.add('the manifest was cancelled');
          }
          ctx.onDispose(() {
            for (final source in sources) {
              source.close();
            }
          });
          trace.add('registered');
        })
          ..ignore();

        async.elapse(const Duration(milliseconds: 20));
        parent.cancel().ignore();
        async.flushTimers();

        // No checkpoint of its own, so the same window costs nothing.
        expect(trace, [
          'the manifest was cancelled',
          'registered',
          'rows closed',
        ]);
      });
    });
  });

  group('Processing streams', () {
    test('a plain await runs the whole callback after cancellation', () {
      fakeAsync((async) {
        final trace = <String>[];
        final messages = StreamController<String>();
        final parent = Job<void>((ctx) async {
          final processing = ctx.each(messages.stream, (child, message) async {
            trace.add('$message: first step');
            await delay(20);
            trace.add('$message: second step');
            await delay(20);
            trace.add('$message: callback done');
          });
          ctx.onDispose(() => trace.add('parent cleanup'));
          await processing.value;
        })
          ..ignore();

        messages.add('m1');
        async.elapse(const Duration(milliseconds: 5));
        parent.cancel().ignore();
        async.flushTimers();
        messages.close().ignore();

        // Neither step is a checkpoint, so the callback plays out and the
        // parent's cleanup waits for all of it.
        expect(trace, [
          'm1: first step',
          'm1: second step',
          'm1: callback done',
          'parent cleanup',
        ]);
      });
    });

    test('child.join lets the cancellation out at the next step', () {
      fakeAsync((async) {
        final trace = <String>[];
        final messages = StreamController<String>();
        final parent = Job<void>((ctx) async {
          final processing = ctx.each(messages.stream, (child, message) async {
            trace.add('$message: first step');
            await child.join(() => delay(20));
            trace.add('$message: second step');
            await child.join(() => delay(20));
            trace.add('$message: callback done');
          });
          ctx.onDispose(() => trace.add('parent cleanup'));
          await processing.value;
        })
          ..ignore();

        messages.add('m1');
        async.elapse(const Duration(milliseconds: 5));
        parent.cancel().ignore();
        async.flushTimers();
        messages.close().ignore();

        // The step it wraps is waited out; the one after it never starts.
        expect(trace, ['m1: first step', 'parent cleanup']);
      });
    });
  });

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
          }).ignore();

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

    test('two children in a row: the parent waits for both', () {
      fakeAsync((async) {
        final trace = <String>[];
        Future<int> load() async => 21;
        Future<void> report(int rows) async {
          await delay(80);
          trace.add('reported $rows');
        }

        Job<void>((ctx) async {
          final rows =
              await ctx.run(Job.deferred<int>((ctx) => ctx.wait(load)));
          await ctx.run(
            Job.deferred<void>((ctx) => ctx.join(() => report(rows * 2))),
          );
        }).done.then((outcome) => trace.add('parent $outcome'));

        async.flushTimers();
        expect(trace, ['reported 42', 'parent Done(null)']);
      });
    });

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
          ..ignore();

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
          await ctx.wait(() => delay(50));
          return 1;
        });
        final tail = head.then<void>((ctx, rows) async {})..ignore();
        final parent = Job<void>((ctx) async {
          await ctx.run(head);
        })
          ..ignore();

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
          await ctx.wait(() => delay(80));
        });
        final parent = Job<void>((ctx) async {
          await ctx.run(head);
          await ctx.wait(() => delay(50));
        })
          ..ignore();

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
          await ctx.wait(() => delay(80));
          trace.add('the tail ends');
        });
        final parent = Job<void>((ctx) async {
          await ctx.run(head);
        })
          ..ignore();

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
          await ctx.wait(() => delay(80));
        })
          ..ignore();
        final parent = Job<void>((ctx) async {
          ctx.onCancel(() => tail.cancel().ignore());
          await ctx.run(head);
          await ctx.wait(() => delay(50));
        })
          ..ignore();

        async.elapse(const Duration(milliseconds: 10));
        expect(tail.isRunning, isTrue);
        parent.cancel().ignore();
        async.flushTimers();

        expect(tail.outcome, isA<Cancelled>());
      });
    });
  });
}
