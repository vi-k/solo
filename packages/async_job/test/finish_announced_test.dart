// Every `Failed` a job ends with is announced to `onError` once: the body's
// where it was caught, one a continuation receives from its source, and one
// an engine of a domain hands to `finish` — even to a job already over.
import 'dart:async';

import 'package:async_job/engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/probe_job.dart';

/// Every hook it hears, in order; answers for nothing.
final class Hearing extends JobObserver with JobAnswerer {
  final seen = <String>[];

  /// Called from `onError`, to act on the job while it is being told.
  void Function(Job<Object?> job)? onHeard;

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    seen.add('onError ${job.key}: $error');
    onHeard?.call(job);
  }

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    seen.add('onUnanswered ${job.key}: $error');
    super.onUnanswered(job, error, stackTrace);
  }

  @override
  void onFinish(Job<Object?> job) => seen.add('onFinish ${job.key}');
}

/// Runs [scenario] with the zone's uncaught errors collected.
List<Object> zoneOf(void Function(FakeAsync async) scenario) {
  final zone = <Object>[];
  runZonedGuarded(
    () => fakeAsync(scenario),
    (error, stackTrace) => zone.add(error),
  );
  return zone;
}

void main() {
  group('a Failed an engine hands to finish', () {
    test('is announced once, before onFinish, and reaches the zone', () {
      final hearing = Hearing();
      late ProbeJob<int> job;
      final zone = zoneOf((async) {
        job = ProbeJob<int>(
          key: 'j',
          observer: hearing,
          (ctx) async {
            await ctx.abandonable(() => delay(100));
            return 1;
          },
        )..launch();
        async.elapse(const Duration(milliseconds: 10));
        job.drop(Failed(StateError('by hand'), StackTrace.current));
        async.flushTimers();
      });
      // Outside the guarded zone: a failing `expect` inside it would be
      // swallowed by the handler and never fail the test.
      expect(job.outcome, isA<Failed>());
      expect(hearing.seen, ['onError j: Bad state: by hand', 'onFinish j']);
      expect(job.hooks, ['started', 'finished']);
      expect(zone, [isA<StateError>()]);
    });

    test('is announced before the engine hears finished', () {
      final hooksAtOnError = <String>[];
      late ProbeJob<int> job;
      final hearing = Hearing()
        ..onHeard =
            (heard) => hooksAtOnError.addAll((heard as ProbeJob<int>).hooks);
      final zone = zoneOf((async) {
        job = ProbeJob<int>(observer: hearing, (ctx) async => 1)
          ..drop(Failed(StateError('by hand'), StackTrace.current));
        async.flushMicrotasks();
      });
      expect(zone, [isA<StateError>()]);
      expect(hooksAtOnError, isEmpty);
      expect(job.hooks, ['finished']);
    });

    test('an onError that cancels finds the job over', () {
      final hearing = Hearing();
      late ProbeJob<int> job;
      final heardCancel = <Cancelled>[];
      zoneOf((async) {
        job = ProbeJob<int>(
          key: 'j',
          observer: hearing,
          (ctx) async {
            await ctx.abandonable(() => delay(100));
            return 1;
          },
        )
          ..launch()
          ..whenCancelled(heardCancel.add);
        hearing.onHeard = (job) => job.cancel().ignore();
        async.elapse(const Duration(milliseconds: 10));
        job.drop(Failed(StateError('by hand'), StackTrace.current));
        async.flushTimers();
      });
      expect(job.outcome, isA<Failed>());
      expect(job.isCancelled, isFalse);
      expect(heardCancel, isEmpty);
    });

    test('over the mark goes to onError and onUnanswered, once each', () {
      final hearing = Hearing();
      late ProbeJob<int> job;
      final zone = zoneOf((async) {
        job = ProbeJob<int>(
          key: 'j',
          observer: hearing,
          (ctx) async {
            await ctx.join(() => delay(100));
            return 1;
          },
        )..launch();
        async.elapse(const Duration(milliseconds: 10));
        job.cancel().ignore();
        job.drop(Failed(StateError('by hand'), StackTrace.current));
        async.flushTimers();
      });
      expect(job.outcome, isA<Cancelled>());
      expect(hearing.seen, [
        'onFinish j',
        'onError j: Bad state: by hand',
        'onUnanswered j: Bad state: by hand',
      ]);
      expect(zone, [isA<StateError>()]);
    });

    test('on a finished job goes to onError and onUnanswered', () {
      final hearing = Hearing();
      late ProbeJob<int> job;
      final zone = zoneOf((async) {
        job = ProbeJob<int>(key: 'j', observer: hearing, (ctx) async => 1);
        job.cancel().ignore();
        job.drop(Failed(StateError('late'), StackTrace.current));
        async.flushTimers();
      });
      expect(job.outcome, isA<Cancelled>());
      expect(hearing.seen, [
        'onFinish j',
        'onError j: Bad state: late',
        'onUnanswered j: Bad state: late',
      ]);
      expect(zone, [isA<StateError>()]);
    });

    test('on a finished job that was ignored goes to onError alone', () {
      final hearing = Hearing();
      final zone = zoneOf((async) {
        ProbeJob<int>(key: 'j', observer: hearing, (ctx) async => 1)
          ..ignore()
          ..cancel().ignore()
          ..drop(Failed(StateError('late'), StackTrace.current));
        async.flushTimers();
      });
      expect(hearing.seen, ['onFinish j', 'onError j: Bad state: late']);
      expect(zone, isEmpty);
    });

    test('twice is announced once', () {
      final hearing = Hearing();
      final failed = Failed(StateError('twice'), StackTrace.current);
      final zone = zoneOf((async) {
        ProbeJob<int>(key: 'j', observer: hearing, (ctx) async => 1)
          ..drop(failed)
          ..drop(failed);
        async.flushTimers();
      });
      expect(hearing.seen, ['onError j: Bad state: twice', 'onFinish j']);
      expect(zone, [isA<StateError>()]);
    });

    test('that the body throws afterwards is announced once', () {
      final hearing = Hearing();
      final error = StateError('both');
      late ProbeJob<int> job;
      final zone = zoneOf((async) {
        job = ProbeJob<int>(
          key: 'j',
          observer: hearing,
          (ctx) async {
            await ctx.abandonable(() => delay(100));
            throw error;
          },
        )..launch();
        async.elapse(const Duration(milliseconds: 10));
        job.drop(Failed(error, StackTrace.current));
        async.flushTimers();
      });
      expect(hearing.seen, ['onError j: Bad state: both', 'onFinish j']);
      expect(zone, [error]);
    });

    test('that the body has already failed with is announced once', () {
      final hearing = Hearing();
      final error = StateError('both');
      late ProbeJob<int> job;
      final zone = zoneOf((async) {
        job = ProbeJob<int>(
          key: 'j',
          observer: hearing,
          (ctx) async {
            // Keeps the job alive after its body has failed.
            ctx.run(
              Job.deferred<int>((child) async {
                await child.join(() => delay(100));
                return 1;
              }),
            ).ignore();
            throw error;
          },
        )..launch();
        async.elapse(const Duration(milliseconds: 10));
        job.drop(Failed(error, StackTrace.current));
        async.flushTimers();
      });
      expect(job.outcome, isA<Failed>());
      // The child inherits the observer; only the parent's lines count.
      expect(
        hearing.seen.where((line) => line.contains(' j')),
        ['onError j: Bad state: both', 'onFinish j'],
      );
      expect(zone, [error]);
    });

    test(
        'over the mark, when the body failed with it first, is not '
        'announced again', () {
      final hearing = Hearing();
      final error = StateError('both');
      late ProbeJob<int> job;
      final zone = zoneOf((async) {
        job = ProbeJob<int>(
          key: 'j',
          observer: hearing,
          (ctx) async {
            // Keeps the job alive after its body has failed.
            ctx
                .run(
                  Job.deferred<int>(key: 'c', (child) async {
                    await child.join(() => delay(100));
                    return 1;
                  }),
                )
                .ignore();
            throw error;
          },
        )..launch();
        async.elapse(const Duration(milliseconds: 10));
        job.cancel().ignore();
        job.drop(Failed(error, StackTrace.current));
        async.flushTimers();
      });
      expect(job.outcome, isA<Cancelled>());
      // The engine decided the outcome while the failed body waited for its
      // child: the failure is the body's, and `onError` alone has heard it.
      expect(
        hearing.seen.where((line) => line.contains(' j')),
        ['onError j: Bad state: both', 'onFinish j'],
      );
      expect(zone, isEmpty);
    });
  });

  test(
      'a body that fails after the engine ended the job is heard by '
      'onError alone', () {
    final hearing = Hearing();
    late ProbeJob<int> job;
    final zone = zoneOf((async) {
      job = ProbeJob<int>(
        key: 'j',
        observer: hearing,
        (ctx) async {
          await ctx.abandonable(() => delay(100));
          throw StateError('body');
        },
      )..launch();
      async.elapse(const Duration(milliseconds: 10));
      job.drop(Failed(StateError('by hand'), StackTrace.current));
      async.flushTimers();
    });
    expect(hearing.seen, [
      'onError j: Bad state: by hand',
      'onFinish j',
      'onError j: Bad state: body',
    ]);
    expect(zone, [isA<StateError>()]);
  });

  test('a child a rule has ended and then refused is announced', () {
    final hearing = Hearing();
    Object? caught;
    final zone = zoneOf((async) {
      ChildEndingRulesJob<void>((ctx) async {
        try {
          await ctx.run(
            Job.deferred<int>(key: 'c', observer: hearing, (child) async => 1),
          );
        } on Object catch (error) {
          caught = error;
        }
      }).launch();
      async.flushTimers();
    });
    expect(caught, isA<StateError>());
    expect(hearing.seen, ['onFinish c', 'onError c: Bad state: rule failed']);
    expect(zone, isEmpty);
  });

  test('the failure of a body is announced once', () {
    final hearing = Hearing();
    final zone = zoneOf((async) {
      Job<int>(key: 'j', observer: hearing, (ctx) async {
        await ctx.abandonable(() => delay(10));
        throw StateError('body');
      });
      async.flushTimers();
    });
    expect(hearing.seen, ['onError j: Bad state: body', 'onFinish j']);
    expect(zone, [isA<StateError>()]);
  });

  test('a failure a continuation receives is announced once on it', () {
    final hearing = Hearing();
    final zone = zoneOf((async) {
      Job<int>(key: 'source', (ctx) async {
        await ctx.abandonable(() => delay(10));
        throw StateError('source');
      }).then<int>(observer: hearing, (ctx, value) => value);
      async.flushTimers();
    });
    expect(
      hearing.seen.where((line) => line.startsWith('onError')),
      ['onError null: Bad state: source'],
    );
    expect(zone, [isA<StateError>()]);
  });
}
