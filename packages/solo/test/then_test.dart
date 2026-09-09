@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

void main() {
  test('a continuation cleanup error reaches its zone without an observer', () {
    fakeAsync((async) {
      final errors = <Object>[];
      final error = StateError('continuation cleanup');
      late Solo<int> solo;
      runZonedGuarded(
        () {
          solo = Solo<int>(0);
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

  test('cancelling the tail removes its queued source', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
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
      final solo = Solo<int>(0);
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
      final solo = Solo<int>(0);
      final gate = Completer<void>();
      final source = solo.run<int, int>((ctx) async => 1);
      final continuation = source.then<void>((ctx, value) {
        expect(ctx, isNot(isA<SoloContext<int, int>>()));
        return ctx.wait(() => gate.future);
      });
      final next = solo.run<int, void>((ctx) async => ctx.emit(2));
      async.flushMicrotasks();
      expect(next.outcome, isA<Done<void>>());
      expect(solo.state, 2);
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
