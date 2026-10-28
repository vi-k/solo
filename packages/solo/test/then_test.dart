@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/plain_solo.dart';
import 'support/test_solo.dart';

/// A controller that writes down what its hooks hear and answers for
/// everything that reaches [onUnanswered].
final class _Heard extends Solo<int> with OpenSolo<int> {
  _Heard() : super(0);

  final heard = <String>[];

  @override
  void onStart(Job<Object?> job) => heard.add('start $job');

  @override
  void onFinish(Job<Object?> job) => heard.add('finish $job');

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => heard.add('error $job: $error');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      heard.add('unanswered $job: $error');

  @override
  void onLog(Job<Object?> job, Object? message) =>
      heard.add('log $job: $message');
}

/// What every controller's observer hears.
final class _Watching extends SoloObserver {
  final heard = <String>[];

  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => heard.add('error $job: $error');

  @override
  void onLog(Solo<Object> solo, Job<Object?> job, Object? message) =>
      heard.add('log $job: $message');
}

/// The error of a plain `then` on a job a droppable call may hand back.
const _droppable =
    'Bad state: Job(load) is handed back to every call of its '
    'key under Policy.droppable: continue it through shared(), a handle for '
    'each caller';

/// The error of a second continuation of one job.
const _continuedOnce =
    'Bad state: Job(load) already has a continuation: a '
    'job is continued once; call shared() for each branch';

/// The error of a plain `then` on a job of an accumulation group.
const _group =
    'Bad state: Job(events) is handed back to every event of its '
    'group: continue it through shared(), a handle for each caller';

/// A plain `then`, the way a caller writes it.
Job<int> _plainThen(Job<int> job) => job.then<int>((ctx, value) => value);

Matcher _throwing(String text) =>
    throwsA(isA<StateError>().having((e) => '$e', 'text', text));

void main() {
  group(
    'a job handed to more than one caller is continued through shared()',
    () {
      SoloJob<int> load(PlainSolo<int> solo, [Policy? policy]) =>
          solo.enqueue<int, int>(
            key: 'load',
            policy: policy ?? Policy.droppable,
            (ctx) async => 1,
          );

      test('then throws on the job of the first droppable call', () {
        fakeAsync((async) {
          final solo = PlainSolo<int>(0);
          final first = load(solo);
          expect(() => _plainThen(first), _throwing(_droppable));
          final second = load(solo);
          expect(identical(first, second), isTrue);
          final a = first.shared().then<int>((ctx, value) => value + 1);
          final b = second.shared().then<int>((ctx, value) => value + 2);
          async.flushMicrotasks();
          expect(['${a.outcome}', '${b.outcome}'], ['Done(2)', 'Done(3)']);
          solo.close().ignore();
          async.flushMicrotasks();
        });
      });

      test('then throws on a droppable job a closed controller dropped', () {
        fakeAsync((async) {
          final solo = PlainSolo<int>(0)..close().ignore();
          final job = load(solo);
          expect(() => _plainThen(job), _throwing(_droppable));
          async.flushMicrotasks();
        });
      });

      test(
        'a droppable call marks the job of another policy it hands back',
        () {
          fakeAsync((async) {
            final solo = PlainSolo<int>(0);
            final first = load(solo, Policy.replace);
            final second = load(solo);
            expect(identical(first, second), isTrue);
            expect(() => _plainThen(second), _throwing(_droppable));
            async.flushMicrotasks();
            solo.close().ignore();
            async.flushMicrotasks();
          });
        },
      );

      test('the job a droppable call drops refuses then as well', () {
        fakeAsync((async) {
          final solo = PlainSolo<int>(0);
          final first = load(solo);
          final mine = solo.job<int, int>(key: 'load', (ctx) async => 2);
          final taken = solo.enqueueJob(mine, policy: Policy.droppable);
          expect(identical(taken, first), isTrue);
          expect(mine.isCancelled, isTrue);
          expect(() => _plainThen(mine), _throwing(_droppable));
          async.flushMicrotasks();
          solo.close().ignore();
          async.flushMicrotasks();
        });
      });

      test('a droppable call during a drain marks the job it hands back', () {
        fakeAsync((async) {
          final solo = PlainSolo<int>(0);
          final gate = Completer<int>();
          final first = solo.enqueue<int, int>(
            key: 'load',
            (ctx) => ctx.abandonable(() => gate.future),
          );
          async.flushMicrotasks();
          solo.close(mode: SoloCloseMode.drain).ignore();
          final second = load(solo);
          expect(identical(first, second), isTrue);
          expect(() => _plainThen(second), _throwing(_droppable));
          gate.complete(1);
          async.flushMicrotasks();
        });
      });

      test(
        'a then taken before a droppable call leaves that caller no shared',
        () {
          fakeAsync((async) {
            final solo = PlainSolo<int>(0);
            final first = load(solo, Policy.sequential);
            final next = first.then<int>((ctx, value) => value + 1);
            final second = load(solo);
            expect(identical(first, second), isTrue);
            expect(second.shared, _throwing(_continuedOnce));
            expect(() => _plainThen(second), _throwing(_droppable));
            async.flushMicrotasks();
            expect('${next.outcome}', 'Done(2)');
            expect('${second.outcome}', 'Done(1)');
            solo.close().ignore();
            async.flushMicrotasks();
          });
        },
      );

      test('a job of another policy keeps its then', () {
        fakeAsync((async) {
          final solo = PlainSolo<int>(0);
          for (final policy in [
            Policy.sequential,
            Policy.replace,
            Policy.restart,
          ]) {
            final next = load(
              solo,
              policy,
            ).then<int>((ctx, value) => value + 1);
            async.flushMicrotasks();
            expect('${next.outcome}', 'Done(2)', reason: '$policy');
          }
          solo.close().ignore();
          async.flushMicrotasks();
        });
      });

      for (final policy in AccumulationPolicy.values) {
        test('then throws on the job of an accumulation group, $policy', () {
          fakeAsync((async) {
            final solo = PlainSolo<int>(0);
            final events = solo.collect<int, int, int>(
              key: 'events',
              policy: policy,
              (ctx, values) async => values.length,
            );
            final first = events.add(1);
            expect(() => _plainThen(first), _throwing(_group));
            final second = events.add(2);
            expect(identical(first, second), isTrue);
            final a = first.shared().then<int>((ctx, value) => value);
            final b = second.shared().then<int>((ctx, value) => value);
            async.flushMicrotasks();
            expect(['${a.outcome}', '${b.outcome}'], ['Done(2)', 'Done(2)']);
            solo.close().ignore();
            async.flushMicrotasks();
          });
        });
      }

      test(
        'then throws on an accumulation job a closed controller dropped',
        () {
          fakeAsync((async) {
            final solo = PlainSolo<int>(0);
            final events = solo.collect<int, int, int>(
              key: 'events',
              (ctx, values) async => values.length,
            );
            solo.close().ignore();
            final job = events.add(1);
            expect(() => _plainThen(job), _throwing(_group));
            async.flushMicrotasks();
          });
        },
      );
    },
  );

  test(
    'a continuation belongs to whoever called then, not to the controller',
    () {
      fakeAsync((async) {
        final watching = _Watching();
        Solo.observer = watching;
        addTearDown(() => Solo.observer = null);
        final solo = _Heard();
        final zone = <String>[];
        Object? read;
        runZonedGuarded(() {
          final source = solo.enqueue<int, int>(
            key: 'source',
            (ctx) async => 1,
          );
          source.shared().then<void>((ctx, _) {
            ctx
              ..log('hello')
              ..unattended(() => throw StateError('unattended'));
          });
          source
              .shared()
              .then<void>((ctx, _) => throw StateError('body'))
              .value
              .then(
                (_) {},
                onError: (Object error) {
                  read = error;
                },
              )
              .ignore();
        }, (error, stack) => zone.add('$error'));
        async.flushMicrotasks();
        expect(solo.heard, [
          'start Job(source)',
          'finish Job(source)',
        ], reason: 'the hooks of the controller hear its own job alone');
        expect(watching.heard, isEmpty);
        expect(zone, ['Bad state: unattended'], reason: "the caller's zone");
        expect('$read', 'Bad state: body', reason: 'whoever reads the outcome');
        solo.close().ignore();
        async.flushMicrotasks();
      });
    },
  );

  test('a continuation cleanup error reaches its zone without an observer', () {
    fakeAsync((async) {
      final errors = <Object>[];
      final error = StateError('continuation cleanup');
      late PlainSolo<int> solo;
      runZonedGuarded(() {
        solo = PlainSolo<int>(0);
        solo.enqueue<int, int>((ctx) async => 1).then<void>((ctx, value) {
          ctx.onDispose(() => throw error);
        });
      }, (error, stack) => errors.add(error));
      async.flushMicrotasks();
      expect(errors, [same(error)]);
      solo.close().ignore();
      async.flushMicrotasks();
    });
  });

  test('cancelling the continuation removes its queued source', () {
    fakeAsync((async) {
      final solo = PlainSolo<int>(0);
      final gate = Completer<void>();
      solo.enqueue<int, void>((ctx) => ctx.abandonable(() => gate.future));
      final source = solo.enqueue<int, int>((ctx) async {
        fail('queued source must not run');
      });
      final continuation = source.then<int>((ctx, value) {
        fail('continuation must not run');
      });
      async.flushMicrotasks();
      expect(source.isQueued, isTrue);
      continuation.cancel().ignore();
      expect(source.isQueued, isFalse);
      async.flushMicrotasks();
      expect(source.outcome, isA<Cancelled>());
      expect(continuation.outcome, isA<Cancelled>());
      solo.close().ignore();
      gate.complete();
      async.flushMicrotasks();
    });
  });

  test('closing the controller cancels continuations of its current job', () {
    fakeAsync((async) {
      final solo = PlainSolo<int>(0);
      final body = Completer<int>();
      final cleanup = Completer<void>();
      final source = solo.enqueue<int, int>((ctx) {
        ctx.onDispose(() => cleanup.future);
        return ctx.join(() => body.future);
      });
      final b = source.then<int>((ctx, value) => fail('must not run'));
      final c = b.then<int>((ctx, value) => fail('must not run'));
      async.flushMicrotasks();
      solo.close().ignore();
      expect(c.isCancelled, isTrue);
      body.complete(1);
      async.flushMicrotasks();
      expect(c.isFinished, isFalse);
      cleanup.complete();
      async.flushMicrotasks();
      expect(source.outcome, isA<Cancelled>());
      expect(b.outcome, isA<Cancelled>());
      expect(c.outcome, isA<Cancelled>());
    });
  });

  test('a running core continuation does not hold the controller queue', () {
    fakeAsync((async) {
      final solo = PlainSolo<int>(0);
      final gate = Completer<void>();
      final source = solo.enqueue<int, int>((ctx) async => 1);
      final continuation = source.then<void>((ctx, value) {
        expect(ctx, isNot(isA<SoloContext<int, int>>()));
        return ctx.abandonable(() => gate.future);
      });
      final next = solo.enqueue<int, void>((ctx) async => ctx.emit(2));
      async.flushMicrotasks();
      expect(next.outcome, isA<Done<void>>());
      expect(solo.currentState, 2);
      expect(continuation.isRunning, isTrue);
      var closed = false;
      unawaited(solo.close().then((_) => closed = true));
      async.flushMicrotasks();
      expect(closed, isTrue);
      expect(continuation.isCancelled, isFalse);
      continuation.cancel().ignore();
      gate.complete();
      async.flushMicrotasks();
    });
  });
}
