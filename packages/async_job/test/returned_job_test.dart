@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/probe_job.dart';

/// A job of no core: the protocol of an engine, implemented. Every getter
/// it is asked for throws.
class _Foreign implements JobBase<void> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Hears the errors of the jobs it watches, into [heard].
final class _Errors extends JobObserver {
  _Errors(this.heard);

  final List<Object> heard;

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required bool answered,
  }) =>
      heard.add(error);
}

Matcher _neverStarted([String job = 'Job()']) => isA<ArgumentError>().having(
      (error) => error.message,
      'message',
      allOf(
        startsWith('$job returned Job('),
        endsWith(
          ', a deferred job that never started; '
          'run it with ctx.run or start it',
        ),
      ),
    );

Matcher _failedNeverStarted([String job = 'Job()']) => isA<Failed>().having(
      (failed) => failed.error,
      'error',
      _neverStarted(job),
    );

void main() {
  group('a job of void that ends with a job never started fails', () {
    test('a body', () {
      fakeAsync((async) {
        var ran = false;
        final saving = Job.deferred<void>((ctx) async => ran = true);
        final job = Job<void>((ctx) async => saving, key: 'outer');
        Outcome<void>? outcome;
        job.done.then((done) => outcome = done).ignore();

        async.flushTimers();

        expect(outcome, _failedNeverStarted('Job(outer)'));
        expect(ran, isFalse);
        expect(saving.isRunning, isFalse);
        expect(saving.isFinished, isFalse);
        saving.cancel().ignore();
        async.flushTimers();
      });
    });

    test('a callback of then', () {
      fakeAsync((async) {
        var ran = false;
        final saving = Job.deferred<void>((ctx) async => ran = true);
        final stored =
            Job<int>((ctx) async => 21).then<void>((ctx, number) => saving);
        Outcome<void>? outcome;
        stored.done.then((done) => outcome = done).ignore();

        async.flushTimers();

        expect(outcome, _failedNeverStarted('Job(then)'));
        expect(ran, isFalse);
        saving.cancel().ignore();
        async.flushTimers();
      });
    });

    // `FutureOr<void>` takes any value here too. A delivered event and one
    // played back from inside `listen` go two ways through the code: a
    // broadcast stream hands `listen` the events its `onListen` adds before
    // `listen` returns, where a single-subscription one would buffer them
    // and deliver them after. And an `async` callback hides the job in its
    // future, the form the mistake most often takes.
    for (final (route, subscribe) in [
      ('delivered', (Stream<int> Function() make) => make()),
      (
        'played back',
        (Stream<int> Function() make) {
          late final StreamController<int> source;
          source = StreamController<int>.broadcast(
            sync: true,
            onListen: () => source
              ..add(1)
              ..add(2),
          );
          addTearDown(source.close);
          return source.stream;
        },
      ),
    ]) {
      for (final asynchronous in [false, true]) {
        final form = asynchronous ? 'an async callback' : 'a callback';
        test('$form of Job.each, $route', () {
          fakeAsync((async) {
            var ran = false;
            final events = <int>[];
            final saving = Job.deferred<void>((ctx) async => ran = true);
            Job<void> handle(int event) {
              events.add(event);
              return saving;
            }

            final job = Job.each<int>(
              subscribe(() => Stream.fromIterable([1, 2])),
              asynchronous
                  // The mistake under test, which no lint sees.
                  ? (ctx, event) async => handle(event)
                  // The same mistake, one the lint sees.
                  // ignore: void_checks
                  : (ctx, event) => handle(event),
            )..ignoreFailure();

            async.flushTimers();

            expect(
              job.outcome,
              isA<Failed>().having(
                (failed) => failed.error,
                'error',
                isA<ArgumentError>().having(
                  (error) => error.message,
                  'message',
                  '$job: the callback returned $saving, a deferred job that '
                      'never started; run it with ctx.run or start it',
                ),
              ),
            );
            expect(events, [1], reason: 'nothing after the callback failed');
            expect(ran, isFalse);
            saving.cancel().ignore();
            async.flushTimers();
          });
        });
      }
    }

    for (final asynchronous in [false, true]) {
      final form = asynchronous ? 'an async callback' : 'a callback';
      test('$form of ctx.each, and its parent through it', () {
        fakeAsync((async) {
          final saving = Job.deferred<void>((ctx) async {});
          late Job<void> child;
          final parent = Job<void>((ctx) async {
            child = ctx.each<int>(
              Stream.value(1),
              asynchronous
                  ? (child, event) async => saving
                  // ignore: void_checks
                  : (child, event) => saving,
            );
            await child.value;
          })
            ..ignoreFailure();

          async.flushTimers();

          expect(child.outcome, isA<Failed>());
          expect((child.outcome! as Failed).error, isA<ArgumentError>());
          expect(parent.outcome, isA<Failed>());
          saving.cancel().ignore();
          async.flushTimers();
        });
      });
    }

    test('a body of FutureOr<void>, which is void', () {
      fakeAsync((async) {
        final saving = Job.deferred<void>((ctx) async {});
        final job = Job<FutureOr<void>>((ctx) async => saving)..ignoreFailure();

        async.flushTimers();

        expect(job.outcome, _failedNeverStarted());
        saving.cancel().ignore();
        async.flushTimers();
      });
    });

    test('the observer hears the error as the body ends, before cleanup', () {
      fakeAsync((async) {
        final saving = Job.deferred<void>((ctx) async {});
        final heard = <Object>[];
        DeferredJob<void> cleanedUp(JobContext ctx) {
          ctx.onDispose(() => heard.add('cleanup'));
          return saving;
        }

        Job<void>((ctx) async => cleanedUp(ctx), observer: _Errors(heard))
            .ignoreFailure();

        async.flushTimers();

        expect(heard, [_neverStarted(), 'cleanup']);
        saving.cancel().ignore();
        async.flushTimers();
      });
    });

    test('nobody observing, the error reaches the zone', () {
      final zone = <Object>[];
      late final DeferredJob<void> saving;
      runZonedGuarded(
        () => fakeAsync((async) {
          saving = Job.deferred<void>((ctx) async {});
          Job<void>((ctx) async => saving);
          async.flushTimers();
        }),
        (error, stackTrace) => zone.add(error),
      );

      expect(zone, [_neverStarted()]);
      saving.cancel().ignore();
    });

    test('a deferred job, run as a child, and its parent through it', () {
      fakeAsync((async) {
        final saving = Job.deferred<void>((ctx) async {});
        final child = Job.deferred<void>((ctx) async => saving);
        final parent = Job<void>((ctx) => ctx.run(child));
        Outcome<void>? outcome;
        parent.done.then((done) => outcome = done).ignore();

        async.flushTimers();

        expect(child.outcome, _failedNeverStarted());
        expect(outcome, _failedNeverStarted());
        saving.cancel().ignore();
        async.flushTimers();
      });
    });
  });

  group('the value is kept as it is', () {
    for (final (name, make) in [
      ('Object?', (Job<void> saving) => Job<Object?>((ctx) async => saving)),
      ('dynamic', (Job<void> saving) => Job<dynamic>((ctx) async => saving)),
    ]) {
      test('a body of $name that ends with a job never started', () {
        fakeAsync((async) {
          final saving = Job.deferred<void>((ctx) async {});
          final job = make(saving);

          async.flushTimers();

          expect(job.outcome, isA<Done<Object?>>());
          expect((job.outcome! as Done<Object?>).value, same(saving));
          saving.cancel().ignore();
          async.flushTimers();
        });
      });
    }

    test('a body of void that ends with a running job, not waited for', () {
      fakeAsync((async) {
        final running = Job<void>(
          (ctx) => ctx.pause(const Duration(seconds: 1)),
        );
        final job = Job<void>((ctx) async => running);

        async.elapse(const Duration(milliseconds: 1));

        expect(job.outcome, isA<Done<void>>());
        expect(running.isFinished, isFalse);
        async.flushTimers();
      });
    });

    test('a body of void that ends with a finished job', () {
      fakeAsync((async) {
        final finished = Job<void>((ctx) async {});
        async.flushTimers();
        final job = Job<void>((ctx) async => finished);

        async.flushTimers();

        expect(job.outcome, isA<Done<void>>());
      });
    });

    test('a body of void that ends with a deferred job started by hand', () {
      fakeAsync((async) {
        var ran = false;
        final saving = Job.deferred<void>((ctx) async => ran = true)..start();
        final job = Job<void>((ctx) async => saving);

        async.flushTimers();

        expect(job.outcome, isA<Done<void>>());
        expect(ran, isTrue);
      });
    });

    test('a body of void that ends with a continuation still waiting', () {
      fakeAsync((async) {
        var ran = false;
        final source = Job<int>((ctx) async {
          await ctx.pause(const Duration(seconds: 1));
          return 1;
        });
        final job = Job<void>(
          (ctx) async => source.then<void>((ctx, number) => ran = true),
        );

        async.elapse(const Duration(milliseconds: 1));
        expect(job.outcome, isA<Done<void>>());

        async.flushTimers();
        expect(ran, isTrue);
      });
    });

    test('a body of void that ends with a Job(...) not yet started', () {
      fakeAsync((async) {
        var ran = false;
        final job = Job<void>(
          (ctx) => ctx
              .pause(const Duration(milliseconds: 1))
              .then((_) => Job<void>((ctx) async => ran = true)),
        );

        async.flushTimers();

        expect(job.outcome, isA<Done<void>>());
        expect(ran, isTrue);
      });
    });

    test('a body of void that ends with a job an engine starts later', () {
      fakeAsync((async) {
        var ran = false;
        final queued = ProbeJob<void>((ctx) async => ran = true);
        final job = Job<void>((ctx) async => queued);

        async.flushTimers();
        expect(job.outcome, isA<Done<void>>());

        queued.launch();
        async.flushTimers();
        expect(ran, isTrue);
      });
    });

    test('a body of void that ends with a job of no core', () {
      fakeAsync((async) {
        final job = Job<void>((ctx) async => _Foreign());

        async.flushTimers();

        expect(job.outcome, isA<Done<void>>());
      });
    });
  });
}
