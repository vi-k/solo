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

    test('Future.wait: an observer of the parent is the one that hears it', () {
      for (final observed in [true, false]) {
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
      }
    });

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
            final envelope =
                error as ParallelWaitError<List<Source?>, List<AsyncError?>>;
            for (final source in envelope.values.whereType<Source>()) {
              source.close();
            }
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
        // The body that caught the envelope could still release them.
        expect(trace, ['rows closed']);
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

  group('What a group hands back', () {
    test('ctx.wait registers the list when nothing is pending', () {
      fakeAsync((async) {
        final trace = <String>[];
        final parent = Job<void>((ctx) async {
          final sources = await ctx.runAll([
            Job.deferred<Source>((ctx) async => Source('rows', trace)),
          ]);
          await ctx.wait(
            () => sources,
            discard: (values) {
              for (final source in values) {
                source.close();
              }
            },
          );
          await ctx.wait(() => delay(80));
        })
          ..ignore();

        async.elapse(const Duration(milliseconds: 20));
        parent.cancel().ignore();
        async.flushTimers();

        // Nothing was pending at the registration line, so the discard of
        // `wait` did run: the cost of this form is not that it never
        // registers.
        expect(trace, ['rows closed']);
      });
    });

    test('ctx.wait throws instead of registering on a pending cancellation',
        () {
      fakeAsync((async) {
        final trace = <String>[];
        Object? thrownAtRegistration;
        final parent = Job<void>((ctx) async {
          final sources = await ctx.runAll([
            Job.deferred<Source>((ctx) async => Source('rows', trace)),
          ]);
          // Anything awaited between the group and the registration is a
          // door the cancellation can come through.
          try {
            await ctx.wait(() => delay(40));
          } on Cancelled {
            trace.add('the manifest was cancelled');
          }
          try {
            await ctx.wait(
              () => sources,
              discard: (values) {
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

        // The checkpoint of `wait` comes before its action, so the list
        // in hand is never registered and nothing closes it.
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
    test('ctx.run refuses a continuation', () {
      fakeAsync((async) {
        Object? thrown;
        final head = Job.deferred<int>((ctx) async => 1);
        final tail = head.then<void>((ctx, rows) async {});
        Job<void>((ctx) async {
          try {
            await ctx.run(tail);
          } on Object catch (error) {
            thrown = error;
          }
          await ctx.run(head);
        }).ignore();

        async.flushTimers();

        expect(thrown, isA<ArgumentError>());
        expect(
          (thrown! as ArgumentError).message,
          contains('A continuation starts itself after its source finishes'),
        );
      });
    });

    test('the parent ends Done while the tail is still running', () {
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
  });
}
