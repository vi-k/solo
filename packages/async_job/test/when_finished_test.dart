@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/error_observer.dart';
import 'support/probe_job.dart';

void main() {
  test('a listener hears the outcome after the cleanup, before done', () {
    fakeAsync((async) {
      final order = <String>[];
      // Through `Job<Object?>`, as a widget holding any job registers.
      final Job<Object?> job = Job<int>((ctx) async {
        ctx.onDispose(() => order.add('cleanup'));
        return 42;
      });
      job
        ..whenFinished((outcome) {
          expect(job.isFinished, isTrue);
          order.add('listener $outcome');
        })
        ..done.then((_) => order.add('done')).ignore();
      async.flushTimers();
      expect(order, ['cleanup', 'listener Done(42)', 'done']);
    });
  });

  test('registration does not observe a failed job', () {
    fakeAsync((async) {
      final zone = <Object>[];
      final heard = <Outcome<void>>[];
      final error = StateError('body');
      runZonedGuarded(
        () {
          Job<void>((ctx) async => throw error).whenFinished(heard.add);
        },
        (error, stackTrace) => zone.add(error),
      );
      async.flushTimers();
      expect(heard.single, isA<Failed>());
      expect(zone, [same(error)]);
    });
  });

  test('a listener that observes the failure keeps it out of the zone', () {
    fakeAsync((async) {
      final zone = <Object>[];
      runZonedGuarded(
        () {
          late Job<void> job;
          job = Job<void>((ctx) async => throw StateError('body'))
            ..whenFinished((outcome) {
              if (outcome is Failed) job.ignoreFailure();
            });
        },
        (error, stackTrace) => zone.add(error),
      );
      async.flushTimers();
      expect(zone, isEmpty);
    });
  });

  test('ignoreFailure from a listener quenches a body a cancellation ended',
      () {
    // The outcome is the cancellation; the failure of the body is answered
    // as the job finishes, and the listener is still in time for it.
    for (final quench in [true, false]) {
      fakeAsync((async) {
        final zone = <Object>[];
        runZonedGuarded(
          () {
            late Job<void> job;
            job = Job<void>((ctx) async {
              try {
                await ctx.abandonable(() => delay(50));
              } on Cancelled {
                throw StateError('body');
              }
            })
              ..whenFinished((_) {
                if (quench) job.ignoreFailure();
              });
            async.elapse(const Duration(milliseconds: 5));
            job.cancel().ignore();
          },
          (error, stackTrace) => zone.add(error),
        );
        async.flushTimers();
        expect(
          zone.map((error) => '$error'),
          quench ? isEmpty : ['Bad state: body'],
        );
      });
    }
  });

  test('a cancelled job tells whenCancelled first, then whenFinished', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) => ctx.abandonable(() => delay(50)))
        ..whenFinished((outcome) => order.add('finished $outcome'))
        ..whenCancelled((cancelled) => order.add('cancelled $cancelled'));
      async.elapse(const Duration(milliseconds: 5));
      job.cancel().ignore();
      expect(order, ['cancelled Cancelled(manual)']);
      async.flushTimers();
      expect(order, [
        'cancelled Cancelled(manual)',
        'finished Cancelled(manual)',
      ]);
    });
  });

  test('a job dropped before start tells whenCancelled first there too', () {
    // Its cancellation reaches the listeners on the way out, in the same
    // routine that tells the end: the order is the routine's.
    final order = <String>[];
    Job.deferred<void>((ctx) async {})
      ..whenFinished((_) => order.add('finished'))
      ..whenCancelled((_) => order.add('cancelled'))
      ..cancel().ignore();
    expect(order, ['cancelled', 'finished']);
  });

  test('a registration from whenCancelled of a dropped job waits its turn', () {
    // A job dropped before start tells `whenCancelled` with its outcome
    // already set, as `onFinish` is: a registration made there belongs to
    // the pass, after the ones made earlier.
    final order = <String>[];
    late DeferredJob<void> job;
    job = Job.deferred<void>((ctx) async {})
      ..whenFinished((_) => order.add('early'))
      ..whenCancelled((_) => job.whenFinished((_) => order.add('late')));
    job.cancel().ignore();
    expect(order, ['early', 'late']);
  });

  test('a job dropped before start calls its listeners as it is dropped', () {
    final heard = <Outcome<void>>[];
    final job = Job.deferred<void>((ctx) async {})..whenFinished(heard.add);
    job.cancel().ignore();
    expect(heard, [same(job.outcome)]);
    expect((heard.single as Cancelled).started, isFalse);
  });

  test('a job that never starts never calls its listeners', () {
    fakeAsync((async) {
      final heard = <Outcome<void>>[];
      Job.deferred<void>((ctx) async {}).whenFinished(heard.add);
      async.flushTimers();
      expect(heard, isEmpty);
    });
  });

  test('a listener hears the outcome the job decided on', () {
    fakeAsync((async) {
      final heard = <Outcome<int>>[];
      // An engine hands in `Done` while a cancelled job unwinds: the job
      // keeps its cancellation, and so does the listener.
      late ProbeJob<int> job;
      job = ProbeJob<int>((ctx) async {
        ctx.onDispose(() => job.drop(const Done(5)));
        await ctx.abandonable(() => delay(50));
        return 1;
      })
        ..whenFinished(heard.add)
        ..launch();
      async.elapse(const Duration(milliseconds: 5));
      job.cancel().ignore();
      async.flushTimers();
      expect('${job.outcome}', 'Cancelled(manual)');
      expect(heard, [same(job.outcome)]);
    });
  });

  test('an engine that ends a job by hand calls the listeners at once', () {
    fakeAsync((async) {
      final order = <String>[];
      late ProbeJob<int> job;
      job = ProbeJob<int>((ctx) async {
        ctx
          ..onDispose(() => order.add('cleanup still to run'))
          ..onDispose(() => job.drop(const Done(5)));
        return 1;
      })
        ..whenFinished((outcome) => order.add('listener $outcome'))
        ..launch();
      async.flushTimers();
      expect(order, ['listener Done(5)', 'cleanup still to run']);
    });
  });

  test('a registration on a finished job runs at once', () {
    fakeAsync((async) {
      final heard = <Outcome<int>>[];
      final job = Job<int>((ctx) async => 1);
      async.flushTimers();
      final remove = job.whenFinished(heard.add);
      expect(heard, [same(job.outcome)]);
      remove();
      remove();
    });
  });

  test('removing one registration leaves the same callback registered twice',
      () {
    fakeAsync((async) {
      final heard = <Outcome<int>>[];
      final job = Job<int>((ctx) async => 1);
      final remove = job.whenFinished(heard.add);
      job
        ..whenFinished(heard.add)
        ..whenFinished(heard.add);
      remove();
      remove();
      async.flushTimers();
      expect(heard, hasLength(2));
    });
  });

  test('removal during notification leaves the current snapshot intact', () {
    fakeAsync((async) {
      final order = <String>[];
      late void Function() remove;
      final job = Job<int>((ctx) async => 1)
        ..whenFinished((_) {
          order.add('first');
          remove();
        });
      remove = job.whenFinished((_) => order.add('second'));
      async.flushTimers();
      expect(order, ['first', 'second']);
    });
  });

  test('a registration during notification runs at once, ahead of the rest',
      () {
    fakeAsync((async) {
      final order = <String>[];
      late Job<int> job;
      job = Job<int>((ctx) async => 1)
        ..whenFinished((_) {
          order.add('first');
          job.whenFinished((_) => order.add('late'));
        })
        ..whenFinished((_) => order.add('second'));
      async.flushTimers();
      expect(order, ['first', 'late', 'second']);
    });
  });

  test('a registration from onFinish waits its turn', () {
    fakeAsync((async) {
      final order = <String>[];
      // `onFinish` runs with the outcome already set and before the pass
      // that tells the listeners: a registration made there belongs to the
      // pass, after the ones made earlier.
      Job<void>(
        observer: _RegisterOnFinish(() => order.add('from onFinish')),
        (ctx) async {},
      ).whenFinished((_) => order.add('early'));
      async.flushTimers();
      expect(order, ['early', 'from onFinish']);
    });
  });

  test(
      'an error of a listener goes to onError and on to the zone, and the '
      'rest still run', () {
    fakeAsync((async) {
      final errors = <Object>[];
      final zone = <Object>[];
      final heard = <Outcome<void>>[];
      final error = StateError('listener');
      runZonedGuarded(
        () {
          Job<void>(observer: ErrorObserver(errors), (ctx) async {})
            ..whenFinished((_) => throw error)
            ..whenFinished(heard.add);
        },
        (error, stackTrace) => zone.add(error),
      );
      async.flushTimers();
      expect(errors, [same(error)]);
      expect(zone, [same(error)]);
      expect(heard, hasLength(1));
    });
  });

  test('an error of a listener registered on a finished job is guarded too',
      () {
    fakeAsync((async) {
      final errors = <Object>[];
      final zone = <Object>[];
      final error = StateError('late listener');
      runZonedGuarded(
        () {
          final job =
              Job<void>(observer: ErrorObserver(errors), (ctx) async {});
          async.flushTimers();
          job.whenFinished((_) => throw error);
        },
        (error, stackTrace) => zone.add(error),
      );
      async.flushTimers();
      expect(errors, [same(error)]);
      expect(zone, [same(error)]);
    });
  });

  test('a cancellation thrown by a listener stays out of the zone', () {
    fakeAsync((async) {
      final zone = <Object>[];
      runZonedGuarded(
        () {
          Job<void>((ctx) async {})
              .whenFinished((_) => throw const Cancelled('listener'));
        },
        (error, stackTrace) => zone.add(error),
      );
      async.flushTimers();
      expect(zone, isEmpty);
    });
  });

  test('a continuation tells its listeners as any job does', () {
    fakeAsync((async) {
      final heard = <Outcome<int>>[];
      Job<int>((ctx) async => 1)
          .then((ctx, value) => value + 1)
          .whenFinished(heard.add);
      async.flushTimers();
      expect('${heard.single}', 'Done(2)');
    });
  });
}

class _RegisterOnFinish extends JobObserver {
  final void Function() onHeard;

  _RegisterOnFinish(this.onHeard);

  @override
  void onFinish(Job<Object?> job) => job.whenFinished((_) => onHeard());
}
