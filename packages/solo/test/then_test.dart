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
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      heard.add('error $job: $error');

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
    StackTrace stackTrace,
  ) =>
      heard.add('error $job: $error');

  @override
  void onLog(Solo<Object> solo, Job<Object?> job, Object? message) =>
      heard.add('log $job: $message');
}

void main() {
  test('a continuation belongs to whoever called then, not to the controller',
      () {
    fakeAsync((async) {
      final watching = _Watching();
      Solo.observer = watching;
      addTearDown(() => Solo.observer = null);
      final solo = _Heard();
      final zone = <String>[];
      Object? read;
      runZonedGuarded(
        () {
          final source = solo.run<int, int>(key: 'source', (ctx) async => 1)
            ..then<void>((ctx, _) {
              ctx
                ..log('hello')
                ..unattended(() => throw StateError('unattended'));
            });
          source.then<void>((ctx, _) => throw StateError('body')).value.then(
            (_) {},
            onError: (Object error) {
              read = error;
            },
          ).ignore();
        },
        (error, stack) => zone.add('$error'),
      );
      async.flushMicrotasks();
      expect(
        solo.heard,
        ['start Job(source)', 'finish Job(source)'],
        reason: 'the hooks of the controller hear its own job alone',
      );
      expect(watching.heard, isEmpty);
      expect(zone, ['Bad state: unattended'], reason: "the caller's zone");
      expect('$read', 'Bad state: body', reason: 'whoever reads the outcome');
      solo.close().ignore();
      async.flushMicrotasks();
    });
  });

  test('a continuation cleanup error reaches its zone without an observer', () {
    fakeAsync((async) {
      final errors = <Object>[];
      final error = StateError('continuation cleanup');
      late PlainSolo<int> solo;
      runZonedGuarded(
        () {
          solo = PlainSolo<int>(0);
          solo.run<int, int>((ctx) async => 1).then<void>((ctx, value) {
            ctx.onDispose(() => throw error);
          });
        },
        (error, stack) => errors.add(error),
      );
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
      solo.run<int, void>((ctx) => ctx.wait(() => gate.future));
      final source = solo.run<int, int>((ctx) async {
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
      final source = solo.run<int, int>((ctx) {
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
      final source = solo.run<int, int>((ctx) async => 1);
      final continuation = source.then<void>((ctx, value) {
        expect(ctx, isNot(isA<SoloContext<int, int>>()));
        return ctx.wait(() => gate.future);
      });
      final next = solo.run<int, void>((ctx) async => ctx.emit(2));
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
