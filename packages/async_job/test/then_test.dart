@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

class _Observer extends JobObserver {
  final void Function(Job<Object?>)? starting;
  final void Function(Job<Object?>, Object)? error;

  _Observer({this.starting, this.error});

  @override
  void onStart(Job<Object?> job) => starting?.call(job);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      this.error?.call(job, error);
}

void main() {
  test('each continuation starts after its predecessor cleanup', () {
    fakeAsync((async) {
      final order = <String>[];
      final a = Job<int>((ctx) async {
        order.add('a');
        ctx.onDispose(() => order.add('dispose a'));
        return 2;
      });
      final b = a.then<int>((ctx, value) {
        order.add('b');
        ctx.onDispose(() => order.add('dispose b'));
        return value + 3;
      });
      final c = b.then<String>((ctx, value) async {
        order.add('c');
        return 'value=$value';
      });
      expect(order, isEmpty);
      expect(b.isRunning, isFalse);
      async.flushMicrotasks();
      expect(order, ['a', 'dispose a', 'b', 'dispose b', 'c']);
      expect((c.outcome! as Done<String>).value, 'value=5');
    });
  });

  for (final index in [0, 1, 2]) {
    test('cancelling link $index waits for the source body and cleanup', () {
      fakeAsync((async) {
        final body = Completer<int>();
        final cleanup = Completer<void>();
        final order = <String>[];
        final a = Job<int>((ctx) async {
          ctx.onDispose(() async {
            order.add('cleanup');
            await cleanup.future;
            order.add('cleaned');
          });
          return ctx.join(() => body.future);
        });
        final b = a.then<int>((ctx, value) {
          order.add('b');
          return value;
        });
        final c = b.then<int>((ctx, value) {
          order.add('c');
          return value;
        });
        async.flushMicrotasks();
        final links = [a, b, c];
        links[index].cancel().ignore();
        var tailCancelled = false;
        unawaited(c.cancel().then((_) => tailCancelled = true));
        expect(links.every((job) => job.isCancelled), isTrue);
        async.flushMicrotasks();
        expect(links.every((job) => !job.isFinished), isTrue);
        expect(tailCancelled, isFalse);
        body.complete(2);
        async.flushMicrotasks();
        expect(order, ['cleanup']);
        expect(tailCancelled, isFalse);
        cleanup.complete();
        async.flushMicrotasks();
        expect(order, ['cleanup', 'cleaned']);
        expect(tailCancelled, isTrue);
        expect(links.every((job) => job.outcome is Cancelled), isTrue);
        expect((a.outcome! as Cancelled).started, isTrue);
        expect((b.outcome! as Cancelled).started, isFalse);
        expect((c.outcome! as Cancelled).started, isFalse);
      });
    });
  }

  test('cancelling the tail before the source starts skips every body', () {
    fakeAsync((async) {
      final order = <String>[];
      final a = Job<void>((ctx) async => order.add('a'));
      final b = a.then<void>((ctx, _) => order.add('b'));
      final c = b.then<void>((ctx, _) => order.add('c'));
      c.cancel().ignore();
      async.flushMicrotasks();
      expect(order, isEmpty);
      for (final job in [a, b, c]) {
        expect((job.outcome! as Cancelled).started, isFalse);
      }
    });
  });

  test('attaching a continuation does not start a deferred source', () {
    fakeAsync((async) {
      final a = Job.deferred<int>((ctx) async => 7);
      final b = a.then<int>((ctx, value) => value * 2);
      async.flushMicrotasks();
      expect(a.isRunning, isFalse);
      expect(b.isRunning, isFalse);
      expect(b.isFinished, isFalse);
      a.start();
      async.flushMicrotasks();
      expect((b.outcome! as Done<int>).value, 14);
    });
  });

  test('a finished source invokes a continuation asynchronously', () {
    fakeAsync((async) {
      final a = Job<int>((ctx) async => 7);
      async.flushMicrotasks();
      var called = false;
      final b = a.then<int>((ctx, value) {
        called = true;
        return value;
      });
      expect(called, isFalse);
      async.flushMicrotasks();
      expect(called, isTrue);
      expect((b.outcome! as Done<int>).value, 7);
    });
  });

  test('a failed source forwards its error and stack only to the tail', () {
    fakeAsync((async) {
      final error = StateError('source');
      final stack = StackTrace.fromString('source stack');
      final errors = <Object>[];
      final stacks = <StackTrace>[];
      late Job<int> c;
      runZonedGuarded(() {
        final a = Job<int>((ctx) async {
          Error.throwWithStackTrace(error, stack);
        });
        final b = a.then<int>((ctx, value) => fail('b must not run'));
        c = b.then<int>((ctx, value) => fail('c must not run'));
      }, (error, stack) {
        errors.add(error);
        stacks.add(stack);
      });
      async.flushMicrotasks();
      expect(errors, [same(error)]);
      expect(stacks, [same(stack)]);
      final outcome = c.outcome! as Failed;
      expect(outcome.error, same(error));
      expect(outcome.stackTrace, same(stack));
    });
  });

  test('a cancelled tail waits for a source that refuses cancellation', () {
    fakeAsync((async) {
      final body = Completer<int>();
      final a = Job<int>(
        (ctx) => ctx.join(() => body.future),
        cancellable: false,
      );
      final b = a.then<int>((ctx, value) => fail('b must not run'));
      async.flushMicrotasks();
      var cancelled = false;
      unawaited(b.cancel().then((_) => cancelled = true));
      async.flushMicrotasks();
      expect(a.isCancelled, isFalse);
      expect(b.isCancelled, isTrue);
      expect(cancelled, isFalse);
      body.complete(1);
      async.flushMicrotasks();
      expect(a.outcome, isA<Done<int>>());
      expect(b.outcome, isA<Cancelled>());
      expect(cancelled, isTrue);
    });
  });

  test('cancelling the tail leaves completed predecessors unchanged', () {
    fakeAsync((async) {
      final gate = Completer<void>();
      final a = Job<int>((ctx) async => 1);
      final b = a.then<int>((ctx, value) => value + 1);
      final c = b.then<void>((ctx, value) => ctx.wait(() => gate.future));
      async.flushMicrotasks();
      final firstOutcome = a.outcome;
      final secondOutcome = b.outcome;
      c.cancel().ignore();
      async.flushMicrotasks();
      expect(a.outcome, same(firstOutcome));
      expect(b.outcome, same(secondOutcome));
      expect(c.outcome, isA<Cancelled>());
      gate.complete();
      async.flushMicrotasks();
    });
  });

  test('cancellation in the failure observer does not hide the error', () {
    fakeAsync((async) {
      final errors = <Object>[];
      final error = StateError('source');
      late Job<int> b;
      runZonedGuarded(
        () {
          final observer = _Observer(
            error: (job, _) {
              if (identical(job, b)) job.cancel().ignore();
            },
          );
          final a = Job<int>((ctx) async => throw error, observer: observer);
          b = a.then<int>(
            (ctx, value) => fail('must not run'),
            observer: observer,
          );
        },
        (error, stack) => errors.add(error),
      );
      async.flushMicrotasks();
      expect(b.outcome, isA<Cancelled>());
      expect(errors, [same(error)]);
    });
  });

  test('a cancelled continuation does not hide a refused source failure', () {
    fakeAsync((async) {
      late Completer<int> body;
      final error = StateError('source');
      final errors = <Object>[];
      late Job<int> b;
      runZonedGuarded(
        () {
          body = Completer<int>();
          final a = Job<int>(
            (ctx) => ctx.join(() => body.future),
            cancellable: false,
          );
          b = a.then<int>((ctx, value) => fail('must not run'))..ignore();
        },
        (error, stack) => errors.add(error),
      );
      async.flushMicrotasks();
      b.cancel().ignore();
      body.completeError(error);
      async.flushMicrotasks();
      expect(b.outcome, isA<Cancelled>());
      expect(errors, [same(error)]);
    });
  });

  test('observing the tail handles a forwarded failure', () {
    fakeAsync((async) {
      final error = StateError('source');
      final errors = <Object>[];
      Outcome<int>? seen;
      runZonedGuarded(
        () {
          final a = Job<int>((ctx) async => throw error);
          final b = a.then<int>((ctx, value) => fail('must not run'));
          final c = b.then<int>((ctx, value) => fail('must not run'));
          unawaited(c.done.then((outcome) => seen = outcome));
        },
        (error, stack) => errors.add(error),
      );
      async.flushMicrotasks();
      expect((seen! as Failed).error, same(error));
      expect(errors, isEmpty);
    });
  });

  test('a continuation failure skips the next body and preserves its stack',
      () {
    fakeAsync((async) {
      final error = StateError('continuation');
      final stack = StackTrace.fromString('continuation stack');
      final a = Job<int>((ctx) async => 1);
      final b = a.then<int>((ctx, value) {
        Error.throwWithStackTrace(error, stack);
      });
      final c = b.then<int>((ctx, value) => fail('must not run'))..ignore();
      async.flushMicrotasks();
      final failed = c.outcome! as Failed;
      expect(failed.error, same(error));
      expect(failed.stackTrace, same(stack));
      expect(a.outcome, isA<Done<int>>());
    });
  });

  test('a continuation that gives up cancels its successors', () {
    fakeAsync((async) {
      final a = Job<int>((ctx) async => 1);
      final b = a.then<int>((ctx, value) => throw const Cancelled('stop'));
      final c = b.then<int>((ctx, value) => fail('must not run'));
      async.flushMicrotasks();
      expect(a.outcome, isA<Done<int>>());
      expect((b.outcome! as Cancelled).reason, isA<HandlerCancelReason>());
      final reason = (c.outcome! as Cancelled).reason as ChainCancelReason;
      expect(reason.cause, same(b.outcome));
    });
  });

  test('forwarded cancellation preserves the adjacent cause and stack', () {
    fakeAsync((async) {
      final gate = Completer<int>();
      final a = Job<int>((ctx) => ctx.wait(() => gate.future));
      final b = a.then<int>((ctx, value) => value);
      final c = b.then<int>((ctx, value) => value);
      async.flushMicrotasks();
      c.cancel().ignore();
      async.flushMicrotasks();
      final ca = a.outcome! as Cancelled;
      final cb = b.outcome! as Cancelled;
      final cc = c.outcome! as Cancelled;
      expect(cc.reason, isA<ManualCancelReason>());
      expect((cb.reason as ChainCancelReason).cause, same(cc));
      expect((ca.reason as ChainCancelReason).cause, same(cb));
      expect(ca.stackTrace, same(cc.stackTrace));
      gate.complete(1);
      async.flushMicrotasks();
    });
  });

  test('a cancelled source immediately marks a newly attached continuation',
      () {
    fakeAsync((async) {
      final gate = Completer<int>();
      final a = Job<int>((ctx) => ctx.join(() => gate.future));
      async.flushMicrotasks();
      a.cancel().ignore();
      final b = a.then<int>((ctx, value) => fail('must not run'));
      expect(b.isCancelled, isTrue);
      expect(b.isFinished, isFalse);
      final seen = <Cancelled>[];
      b.whenCancelled(seen.add);
      expect(seen, hasLength(1));
      gate.complete(1);
      async.flushMicrotasks();
      expect(b.outcome, same(seen.single));
      final c = b.then<int>((ctx, value) => fail('must not run'));
      expect(c.isCancelled, isTrue);
      async.flushMicrotasks();
      expect(c.outcome, isA<Cancelled>());
    });
  });

  test('a held source cancellation keeps the tail waiting', () {
    fakeAsync((async) {
      final gate = Completer<int>();
      final a = Job<int>((ctx) => ctx.uncancellable(() => gate.future));
      final b = a.then<int>((ctx, value) => fail('must not run'));
      async.flushMicrotasks();
      b.cancel().ignore();
      expect(a.isCancelled, isFalse);
      expect(b.isCancelled, isTrue);
      async.flushMicrotasks();
      expect(b.isFinished, isFalse);
      gate.complete(1);
      async.flushMicrotasks();
      expect(a.outcome, isA<Cancelled>());
      expect(b.outcome, isA<Cancelled>());
    });
  });

  test('a held continuation cancellation delays the forward signal', () {
    fakeAsync((async) {
      final gate = Completer<int>();
      final a = Job<int>((ctx) async => 1);
      final b = a.then<int>(
        (ctx, value) => ctx.uncancellable(() => gate.future),
      );
      final c = b.then<int>((ctx, value) => fail('must not run'));
      async.flushMicrotasks();
      b.cancel().ignore();
      expect(b.isCancelled, isFalse);
      expect(c.isCancelled, isFalse);
      gate.complete(2);
      async.flushMicrotasks();
      expect(a.outcome, isA<Done<int>>());
      expect(b.outcome, isA<Cancelled>());
      expect(c.outcome, isA<Cancelled>());
    });
  });

  test('a continuation waits for its children before its cleanup and tail', () {
    fakeAsync((async) {
      final gate = Completer<void>();
      final order = <String>[];
      final a = Job<int>((ctx) async => 1);
      final b = a.then<int>((ctx, value) {
        ctx
          ..onDispose(() => order.add('dispose b'))
          ..run(
            Job.deferred<void>(cancellable: false, (child) async {
              await child.join(() => gate.future);
              order.add('child done');
            }),
          );
        return value + 1;
      });
      final c = b.then<void>((ctx, value) => order.add('c'));
      async.flushMicrotasks();
      c.cancel().ignore();
      async.flushMicrotasks();
      expect(b.isFinished, isFalse);
      expect(c.isFinished, isFalse);
      expect(order, isEmpty);
      gate.complete();
      async.flushMicrotasks();
      expect(order, ['child done', 'dispose b']);
      expect(b.outcome, isA<Cancelled>());
      expect(c.outcome, isA<Cancelled>());
    });
  });

  test('a continuation cannot be adopted while it waits for its source', () {
    fakeAsync((async) {
      final source = Job.deferred<int>((ctx) async => 1);
      final continuation = source.then<int>((ctx, value) => value);
      final parent = Job<void>((ctx) async {
        expect(() => ctx.run(continuation), throwsArgumentError);
      });
      async.flushMicrotasks();
      expect(parent.outcome, isA<Done<void>>());
      expect(continuation.isChild, isFalse);
      source.start();
      async.flushMicrotasks();
      expect(continuation.outcome, isA<Done<int>>());
    });
  });

  test('cancellation from the start observer skips the continuation body', () {
    fakeAsync((async) {
      late Job<int> b;
      final observer = _Observer(
        starting: (job) {
          if (identical(job, b)) job.cancel().ignore();
        },
      );
      final a = Job<int>((ctx) async => 1, observer: observer);
      b = a.then<int>(
        (ctx, value) => fail('must not run'),
        observer: observer,
      );
      async.flushMicrotasks();
      expect(b.outcome, isA<Cancelled>());
    });
  });

  test('cancelling one branch cancels the shared source and its sibling', () {
    fakeAsync((async) {
      final gate = Completer<int>();
      final a = Job<int>((ctx) => ctx.wait(() => gate.future));
      final b = a.then<int>((ctx, value) => fail('must not run'));
      final c = a.then<int>((ctx, value) => fail('must not run'));
      async.flushMicrotasks();
      b.cancel().ignore();
      async.flushMicrotasks();
      expect(a.outcome, isA<Cancelled>());
      expect(b.outcome, isA<Cancelled>());
      expect(c.outcome, isA<Cancelled>());
      gate.complete(1);
      async.flushMicrotasks();
    });
  });

  for (final cancelTail in [false, true]) {
    test('a 5000-link cascade from the ${cancelTail ? 'tail' : 'source'}', () {
      fakeAsync((async) {
        final gate = Completer<int>();
        final source = Job<int>((ctx) => ctx.wait(() => gate.future));
        final jobs = <Job<int>>[source];
        for (var i = 0; i < 5000; i++) {
          jobs.add(jobs.last.then<int>((ctx, value) => value));
        }
        async.flushMicrotasks();
        (cancelTail ? jobs.last : source).cancel().ignore();
        expect(jobs.every((job) => job.isCancelled), isTrue);
        async.flushMicrotasks();
        expect(jobs.every((job) => job.outcome is Cancelled), isTrue);
        gate.complete(1);
        async.flushMicrotasks();
      });
    });
  }

  for (final cancelContinuation in [false, true]) {
    test(
        'attaching to a failed source inside its cancel completion '
        '${cancelContinuation ? 'then cancelling' : 'then observing'}', () {
      fakeAsync((async) {
        final errors = <Object>[];
        final error = StateError('source');
        late Completer<int> body;
        late Job<int> source;
        late Job<int> continuation;
        runZonedGuarded(
          () {
            body = Completer<int>();
            source = Job<int>(
              (ctx) => ctx.join(() => body.future),
              cancellable: false,
            );
            async.flushMicrotasks();
            unawaited(
              source.cancel().then((_) {
                expect(errors, isEmpty);
                continuation = source.then<int>(
                  (ctx, value) => fail('must not run'),
                )..ignore();
                if (cancelContinuation) continuation.cancel().ignore();
              }),
            );
          },
          (error, stack) => errors.add(error),
        );
        body.completeError(error);
        async.flushMicrotasks();
        if (cancelContinuation) {
          expect(continuation.outcome, isA<Cancelled>());
          expect(errors, [same(error)]);
        } else {
          expect(continuation.outcome, isA<Failed>());
          expect(errors, isEmpty);
        }
      });
    });
  }
}
