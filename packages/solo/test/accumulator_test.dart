import 'dart:async';
import 'dart:mirrors';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/test_solo.dart';
import 'support/test_state.dart';

void main() {
  tearDown(() {
    SoloBase.observer = null;
    SoloBase.debug = null;
  });
  test('synchronous events wait for the queue pump', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
      final calls = <List<int>>[];
      final events = solo.collect<int, int, void>((ctx, values) async {
        calls.add(values);
        ctx.emit(values.length);
      });
      async.flushMicrotasks();
      expect(calls, isEmpty);
      final a = events.add(1);
      final b = events.add(2);
      expect(identical(a, b), isTrue);
      expect(solo.state, 0);
      expect(calls, isEmpty);
      async.flushMicrotasks();
      expect(calls, [
        [1, 2],
      ]);
      expect(solo.state, 2);
      solo.close();
      async.flushMicrotasks();
    });
  });

  for (final policy in AccumulationPolicy.values) {
    for (final collect in [true, false]) {
      test('$policy ${collect ? 'collect' : 'accumulate'} across B', () {
        fakeAsync((async) {
          final solo = Solo<String>('');
          final calls = <String>[];
          Future<String> handle(
            SoloContext<String, String> ctx,
            String value,
          ) async {
            calls.add('A$value');
            ctx.emit(ctx.state + value);
            return value;
          }

          final events = collect
              ? solo.collect<String, String, String>(
                  (ctx, values) => handle(ctx, values.join()),
                  policy: policy,
                )
              : solo.accumulate<String, String, String>(
                  handle,
                  merge: (a, b) => a + b,
                  policy: policy,
                );
          final first = events.add('1');
          solo.run<String, void>((ctx) async {
            calls.add('B:${ctx.state}');
          });
          final second = events.add('2');
          expect(identical(first, second), policy == AccumulationPolicy.join);
          expect(solo.state, '');
          if (policy == AccumulationPolicy.replace) {
            final outcome = first.outcome! as Cancelled;
            expect(outcome.reason, isA<ManualCancelReason>());
            expect(outcome.description, 'replaced by accumulated group');
            expect(outcome.started, isFalse);
            first.cancel();
            expect(second.isCancelled, isFalse);
          }
          async.flushMicrotasks();
          expect(
            calls,
            switch (policy) {
              AccumulationPolicy.adjacent => ['A1', 'B:1', 'A2'],
              AccumulationPolicy.replace => ['B:', 'A12'],
              AccumulationPolicy.join => ['A12', 'B:12'],
            },
          );
          expect(
            (second.outcome! as Done<String>).value,
            policy == AccumulationPolicy.adjacent ? '2' : '12',
          );
          solo.close();
          async.flushMicrotasks();
        });
      });
    }

    test('$policy synchronous events and nullable snapshots', () {
      fakeAsync((async) {
        final solo = Solo<int>(0);
        final calls = <List<int?>>[];
        final events = solo.collect<int, int?, int>(
          (ctx, values) async {
            calls.add(values);
            expect(() => values.add(9), throwsUnsupportedError);
            return values.length;
          },
          policy: policy,
        );
        final a = events.add(null);
        final b = events.add(1);
        final c = events.add(1);
        expect(identical(a, b), policy != AccumulationPolicy.replace);
        expect(identical(b, c), policy != AccumulationPolicy.replace);
        async.flushMicrotasks();
        expect(calls, [
          [null, 1, 1],
        ]);
        expect((c.outcome! as Done<int>).value, 3);
        events.add(2);
        async.flushMicrotasks();
        expect(calls, [
          [null, 1, 1],
          [2],
        ]);
        solo.close();
        async.flushMicrotasks();
      });
    });

    test('$policy merge throws without losing the waiting value', () {
      fakeAsync((async) {
        final solo = Solo<int>(0);
        final calls = <int?>[];
        final merges = <(int?, int?)>[];
        final error = StateError('merge failed');
        const cancellation = Cancelled.by(
          reason: ManualCancelReason(),
          started: false,
        );
        final events = solo.accumulate<int, int?, void>(
          (ctx, value) async {
            calls.add(value);
          },
          policy: policy,
          merge: (a, b) {
            merges.add((a, b));
            if (b == 99) throw error;
            if (b == 98) throw cancellation;
            return b == null ? null : (a ?? 0) + b;
          },
        );
        final a = events.add(null);
        expect(merges, isEmpty);
        expect(() => events.add(99), throwsA(same(error)));
        expect(() => events.add(98), throwsA(same(cancellation)));
        expect(a.isQueued, isTrue);
        expect(a.isCancelled, isFalse);
        events
          ..add(2)
          ..add(null);
        final last = events.add(3);
        expect(
          merges,
          [(null, 99), (null, 98), (null, 2), (2, null), (null, 3)],
        );
        async.flushMicrotasks();
        expect(calls, [3]);
        expect(last.isFinished, isTrue);
        solo.close();
        async.flushMicrotasks();
      });
    });

    test('$policy same-accumulator merge reentry and recovery', () {
      fakeAsync((async) {
        final solo = Solo<int>(0);
        var reenter = true;
        var catchReentry = false;
        late SoloAccumulator<int, int> events;
        events = solo.accumulate<int, int, int>(
          (ctx, value) async => value,
          policy: policy,
          merge: (a, b) {
            if (reenter) {
              if (catchReentry) {
                expect(() => events.add(100), throwsStateError);
              } else {
                events.add(100);
              }
            }
            return a + b;
          },
        );
        events.add(1);
        expect(() => events.add(2), throwsStateError);
        catchReentry = true;
        events.add(3);
        reenter = false;
        final last = events.add(4);
        async.flushMicrotasks();
        expect((last.outcome! as Done<int>).value, 8);
        solo.close();
        async.flushMicrotasks();
      });
    });

    for (final mutation in ['append', 'cancel', 'close']) {
      test('$policy merge changes queue with $mutation', () {
        fakeAsync((async) {
          final solo = Solo<int>(0);
          final calls = <int>[];
          late SoloJob<void> first;
          final events = solo.accumulate<int, int, void>(
            (ctx, value) async {
              calls.add(value);
            },
            policy: policy,
            merge: (a, b) {
              switch (mutation) {
                case 'append':
                  solo.run<int, void>((ctx) async {});
                case 'cancel':
                  first.cancel();
                case 'close':
                  solo.close();
              }
              return a + b;
            },
          );
          first = events.add(1);
          final invalid =
              mutation != 'append' || policy == AccumulationPolicy.adjacent;
          if (invalid) {
            expect(() => events.add(2), throwsStateError);
          } else {
            events.add(2);
          }
          async.flushMicrotasks();
          expect(
            calls,
            mutation == 'append' ? [if (invalid) 1 else 3] : isEmpty,
          );
          solo.close();
          async.flushMicrotasks();
        });
      });
    }
  }

  for (final policy in AccumulationPolicy.values) {
    test('$policy keeps accumulator identities separate despite equal keys',
        () {
      fakeAsync((async) {
        final solo = TestSolo();
        final calls = <List<int>>[];
        Future<void> handler(
          SoloContext<TestState, TestState> ctx,
          List<int> values,
        ) async =>
            calls.add(values);
        final a = solo.collect<TestState, int, void>(
          handler,
          key: 'same',
          policy: policy,
        );
        final b = solo.collect<TestState, int, void>(
          handler,
          key: 'same',
          policy: policy,
        );
        final first = a.add(1);
        final foreign = b.add(10);
        final last = a.add(2);
        expect(identical(first, foreign), isFalse);
        expect(foreign.isQueued, isTrue);
        expect(foreign.isCancelled, isFalse);
        expect(
          solo.queue.length,
          policy == AccumulationPolicy.adjacent ? 3 : 2,
        );
        async.flushMicrotasks();
        expect(
          calls,
          switch (policy) {
            AccumulationPolicy.adjacent => [
                [1],
                [10],
                [2],
              ],
            AccumulationPolicy.replace => [
                [10],
                [1, 2],
              ],
            AccumulationPolicy.join => [
                [1, 2],
                [10],
              ],
          },
        );
        expect(last.isFinished, isTrue);
        solo.close();
        async.flushMicrotasks();
      });
    });

    for (final boundary in ['canStart', 'onStart', 'body']) {
      test('$policy add during $boundary opens the next group', () {
        fakeAsync((async) {
          final solo = TestSolo();
          final calls = <List<int>>[];
          late SoloAccumulator<int, void> events;
          SoloJob<void>? next;
          var added = false;
          void addOnce() {
            if (added) return;
            added = true;
            next = events.add(2);
          }

          SoloBase.observer = _Callbacks(
            onStart: (job) {
              if (boundary == 'onStart') addOnce();
            },
          );
          events = solo.collect<TestState, int, void>(
            (ctx, values) async {
              calls.add(values);
              if (boundary == 'body') addOnce();
            },
            policy: policy,
            canStart: (_) {
              if (boundary == 'canStart') addOnce();
              return true;
            },
          );
          final first = events.add(1);
          async.flushMicrotasks();
          expect(calls, [
            [1],
            [2],
          ]);
          expect(identical(first, next), isFalse);
          expect(first.outcome, isA<Done<void>>());
          expect(next!.outcome, isA<Done<void>>());
          solo.close();
          async.flushMicrotasks();
        });
      });
    }

    test('$policy replacement cannot cancel a running protected group', () {
      fakeAsync((async) {
        final solo = TestSolo();
        final gate = Completer<void>();
        final calls = <List<int>>[];
        final events = solo.collect<TestState, int, void>(
          (ctx, values) async {
            calls.add(values);
            await ctx.join(() => gate.future);
          },
          policy: policy,
          cancellable: false,
        );
        final running = events.add(1);
        async.flushMicrotasks();
        final queued = events.add(2);
        final tail = events.add(3);
        expect(running.isCancelled, isFalse);
        expect(identical(running, queued), isFalse);
        expect(queued.isCancelled, policy == AccumulationPolicy.replace);
        expect(solo.queue.length, 1);
        expect(calls, [
          [1],
        ]);
        gate.complete();
        async.flushMicrotasks();
        expect(calls, [
          [1],
          [2, 3],
        ]);
        expect(tail.outcome, isA<Done<void>>());
        solo.close();
        async.flushMicrotasks();
      });
    });
  }

  test('the next group waits for body, children, and cleanup', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final body = Completer<void>();
      final child = Completer<void>();
      final cleanup = Completer<void>();
      final calls = <String>[];
      final events = solo.collect<TestState, int, void>((ctx, values) async {
        calls.add('body:$values');
        if (values.first == 1) {
          ctx
            ..run(
              solo.job<TestState, void>((childCtx) async {
                await childCtx.join(() => child.future);
                calls.add('child');
              }),
            ).ignore()
            ..onDispose(() async {
              calls.add('cleanup');
              await cleanup.future;
              calls.add('cleaned');
            });
          await ctx.join(() => body.future);
          calls.add('body ended');
        }
      });
      final first = events.add(1);
      async.flushMicrotasks();
      final next = events.add(2);
      events.add(3);
      body.complete();
      async.flushMicrotasks();
      expect(calls, ['body:[1]', 'body ended']);
      expect(next.isQueued, isTrue);
      child.complete();
      async.flushMicrotasks();
      expect(calls, ['body:[1]', 'body ended', 'child', 'cleanup']);
      expect(first.isFinished, isFalse);
      expect(next.isQueued, isTrue);
      cleanup.complete();
      async.flushMicrotasks();
      expect(
        calls,
        [
          'body:[1]',
          'body ended',
          'child',
          'cleanup',
          'cleaned',
          'body:[2, 3]',
        ],
      );
      solo.close();
      async.flushMicrotasks();
    });
  });

  for (final rule in ['type', 'canStart', 'keepWhile', 'throw']) {
    test('start rule $rule rejects the whole group', () {
      fakeAsync((async) {
        final solo = TestSolo();
        var called = false;
        var checked = 0;
        final error = StateError('rule');
        final events = solo.collect<Initial, int, void>(
          (ctx, values) async {
            called = true;
          },
          canStart: (_) {
            checked++;
            if (rule == 'throw') throw error;
            return rule != 'canStart';
          },
          keepWhile: (_) => rule != 'keepWhile',
        );
        final a = events.add(1);
        final b = events.add(2);
        expect(checked, 0);
        expect(identical(a, b), isTrue);
        if (rule == 'type') solo.externalSetState(const Disposed());
        a.ignore();
        async.flushMicrotasks();
        expect(called, isFalse);
        if (rule == 'throw') {
          expect((a.outcome! as Failed).error, same(error));
        } else {
          expect((a.outcome! as Cancelled).reason, isA<RulesCancelReason>());
          expect((a.outcome! as Cancelled).started, isFalse);
        }
        solo.close();
        async.flushMicrotasks();
      });
    });
  }

  test('keepWhile cancels a running group even when protected', () {
    fakeAsync((async) {
      final solo = TestSolo(const Working());
      final gate = Completer<void>();
      var passed = false;
      final events = solo.collect<Working, int, void>(
        (ctx, values) async {
          await ctx.join(() => gate.future);
          passed = true;
        },
        cancellable: false,
        keepWhile: (state) => state.a == 0,
      );
      final first = events.add(1);
      events.add(2);
      async.flushMicrotasks();
      solo.externalSetState(const Working(a: 1));
      expect(first.isCancelled, isTrue);
      expect(first.isFinished, isFalse);
      gate.complete();
      async.flushMicrotasks();
      expect(passed, isFalse);
      expect((first.outcome! as Cancelled).reason, isA<RulesCancelReason>());
      solo.close();
      async.flushMicrotasks();
    });
  });

  test('onStart cancellation prevents invoking the accumulated handler', () {
    fakeAsync((async) {
      final solo = TestSolo();
      var called = false;
      SoloBase.observer = _Callbacks(onStart: (job) => job.cancel());
      final events = solo.collect<TestState, int, void>((ctx, values) async {
        called = true;
      });
      final job = events.add(1);
      async.flushMicrotasks();
      expect(called, isFalse);
      expect((job.outcome! as Cancelled).started, isTrue);
      solo.close();
      async.flushMicrotasks();
    });
  });

  test('removing a separator does not merge existing adjacent groups', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final calls = <List<int>>[];
      final events = solo.collect<TestState, int, void>((ctx, values) async {
        calls.add(values);
      });
      final first = events.add(1);
      final separator = solo.run<TestState, void>((ctx) async {});
      final next = events.add(2);
      solo.queue.remove(separator);
      expect(identical(next, events.add(3)), isTrue);
      expect(solo.queue.jobs, [first, next]);
      async.flushMicrotasks();
      expect(calls, [
        [1],
        [2, 3],
      ]);
      solo.close();
      async.flushMicrotasks();
    });
  });

  for (final operation in ['cancel', 'remove', 'clear', 'replace', 'restart']) {
    test('ordinary $operation discards a group without transferring data', () {
      fakeAsync((async) {
        final solo = TestSolo();
        final calls = <List<int>>[];
        final events = solo.collect<TestState, int, void>(
          (ctx, values) async {
            calls.add(values);
          },
          key: 'events',
        );
        final first = events.add(1);
        switch (operation) {
          case 'cancel':
            first.cancel();
          case 'remove':
            solo.queue.remove(first);
          case 'clear':
            solo.queue.clear();
          case 'replace':
            solo.run<TestState, void>(
              (ctx) async {},
              key: 'events',
              policy: Policy.replace,
            );
          case 'restart':
            solo.run<TestState, void>(
              (ctx) async {},
              key: 'events',
              policy: Policy.restart,
            );
        }
        final next = events.add(2);
        expect(first.outcome, isA<Cancelled>());
        expect(identical(first, next), isFalse);
        async.flushMicrotasks();
        expect(calls, [
          [2],
        ]);
        solo.close();
        async.flushMicrotasks();
      });
    });
  }

  test('droppable returns a matching group without adding an event', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final events = solo.collect<TestState, int, int>(
        (ctx, values) async => values.single,
        key: 'same',
      );
      final group = events.add(3);
      final dropped = solo.run<TestState, int>(
        (ctx) async => 99,
        key: 'same',
        policy: Policy.droppable,
      );
      expect(identical(group, dropped), isTrue);
      async.flushMicrotasks();
      expect((group.outcome! as Done<int>).value, 3);
      solo.close();
      async.flushMicrotasks();
    });
  });

  test('clear and cancel respect a protected queued group until forced', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final events = solo.collect<TestState, int, void>(
        (ctx, values) async {},
        cancellable: false,
      );
      final first = events.add(1);
      unawaited(first.cancel());
      expect(solo.queue.clear(), 0);
      expect(identical(events.add(2), first), isTrue);
      expect(solo.queue.clear(force: true), 1);
      expect(first.outcome, isA<Cancelled>());
      expect(identical(events.add(3), first), isFalse);
      solo.close();
      async.flushMicrotasks();
    });
  });

  for (final hook in ['onFinish', 'whenCancelled']) {
    for (final action in ['add', 'cancel', 'clear', 'close']) {
      for (final collect in [true, false]) {
        test('replace ${collect ? 'collect' : 'accumulate'} $hook does $action',
            () {
          fakeAsync((async) {
            final solo = TestSolo();
            final calls = <int>[];
            Future<void> handle(
              SoloContext<TestState, TestState> ctx,
              int value,
            ) async =>
                calls.add(value);
            final events = collect
                ? solo.collect<TestState, int, void>(
                    (ctx, values) =>
                        handle(ctx, values.reduce((a, b) => a + b)),
                    policy: AccumulationPolicy.replace,
                  )
                : solo.accumulate<TestState, int, void>(
                    handle,
                    merge: (a, b) => a + b,
                    policy: AccumulationPolicy.replace,
                  );
            final first = events.add(1);
            Job<Object?>? visible;
            SoloJob<void>? reentrant;
            void callback() {
              expect(first.isQueued, isFalse);
              visible = solo.queue.jobs.single;
              expect(identical(visible, first), isFalse);
              switch (action) {
                case 'add':
                  reentrant = events.add(4);
                case 'cancel':
                  visible!.cancel();
                case 'clear':
                  solo.queue.clear();
                case 'close':
                  solo.close();
              }
            }

            if (hook == 'onFinish') {
              SoloBase.observer = _Callbacks(
                onFinish: (job) {
                  if (identical(job, first)) callback();
                },
              );
            } else {
              first.whenCancelled((_) => callback());
            }
            final outer = events.add(2);
            expect(identical(outer, visible), isTrue);
            expect(outer.outcome, isA<Cancelled>());
            expect((outer.outcome! as Cancelled).started, isFalse);
            async.flushMicrotasks();
            expect(calls, action == 'add' ? [7] : isEmpty);
            if (action == 'add') expect(reentrant!.outcome, isA<Done<void>>());
            solo.close();
            async.flushMicrotasks();
          });
        });
      }
    }
  }

  test('close drains waiting groups and waits for protected running work', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final gate = Completer<void>();
      final calls = <int>[];
      var merged = 0;
      final events = solo.accumulate<TestState, int, void>(
        (ctx, value) async {
          calls.add(value);
          await ctx.join(() => gate.future);
        },
        cancellable: false,
        merge: (a, b) {
          merged++;
          return a + b;
        },
      );
      final running = events.add(1);
      async.flushMicrotasks();
      final waiting = events.add(2);
      events.add(3);
      var closed = false;
      solo.close().then((_) => closed = true);
      final rejected = events.add(9);
      final rejectedAgain = events.add(10);
      expect(identical(rejected, rejectedAgain), isFalse);
      expect(
        (rejected.outcome! as Cancelled).reason,
        isA<ClosedCancelReason>(),
      );
      expect((rejected.outcome! as Cancelled).started, isFalse);
      expect(waiting.outcome, isA<Cancelled>());
      expect(running.isCancelled, isFalse);
      expect(merged, 1);
      async.flushMicrotasks();
      expect(closed, isFalse);
      gate.complete();
      async.flushMicrotasks();
      expect(closed, isTrue);
      expect(calls, [1]);
      expect(running.outcome, isA<Done<void>>());
      final empty = solo.collect<TestState, int, void>((ctx, events) async {
        fail('closed controller must not run a handler');
      });
      expect(empty.add(1).outcome, isA<Cancelled>());
    });
  });

  test('merge reentry is rejected before closure is checked', () {
    fakeAsync((async) {
      final solo = TestSolo();
      late SoloAccumulator<int, void> events;
      events = solo.accumulate<TestState, int, void>(
        (ctx, value) async {},
        merge: (a, b) {
          solo.close();
          expect(() => events.add(3), throwsStateError);
          return a + b;
        },
      );
      events.add(1);
      expect(() => events.add(2), throwsStateError);
      expect(events.add(4).outcome, isA<Cancelled>());
      async.flushMicrotasks();
    });
  });

  for (final failure in ['throw', 'self cancel', 'cancel then throw']) {
    test('handler $failure leaves later groups independent', () {
      fakeAsync((async) {
        final solo = TestSolo();
        final calls = <List<int>>[];
        final error = StateError('handler');
        final errors = <Object>[];
        SoloBase.observer = _Callbacks(onError: errors.add);
        late SoloJob<void> first;
        final events = solo.collect<TestState, int, void>((ctx, values) async {
          calls.add(values);
          if (values.first != 1) return;
          switch (failure) {
            case 'throw':
              throw error;
            case 'self cancel':
              throw const Cancelled.by(
                reason: ManualCancelReason(),
                started: true,
              );
            case 'cancel then throw':
              unawaited(first.cancel());
              throw error;
          }
        });
        first = events.add(1);
        final shared = events.add(2);
        first.ignore();
        async.flushMicrotasks();
        expect(identical(shared, first), isTrue);
        expect(
          first.outcome,
          failure == 'throw' ? isA<Failed>() : isA<Cancelled>(),
        );
        events.add(3);
        async.flushMicrotasks();
        expect(calls, [
          [1, 2],
          [3],
        ]);
        expect(errors, failure == 'self cancel' ? isEmpty : [error]);
        solo.close();
        async.flushMicrotasks();
      });
    });
  }

  test('one unobserved failed group reports one zone error', () {
    fakeAsync((async) {
      final errors = <Object>[];
      final error = StateError('unobserved');
      runZonedGuarded(
        () {
          final solo = TestSolo();
          solo.collect<TestState, int, void>((ctx, values) async {
            throw error;
          })
            ..add(1)
            ..add(2);
          async.flushMicrotasks();
          solo.close();
          async.flushMicrotasks();
        },
        (error, stack) => errors.add(error),
      );
      expect(errors, [error]);
    });
  });

  test('replace transfers a large ordered collect buffer exactly once', () {
    fakeAsync((async) {
      final solo = TestSolo();
      var starts = 0;
      final events = solo.collect<TestState, int, int>(
        (ctx, values) async {
          starts++;
          expect(values, List<int>.generate(10000, (index) => index));
          return values.length;
        },
        policy: AccumulationPolicy.replace,
      );
      late SoloJob<int> last;
      for (var i = 0; i < 10000; i++) {
        last = events.add(i);
      }
      expect(solo.queue.length, 1);
      async.flushMicrotasks();
      expect(starts, 1);
      expect((last.outcome! as Done<int>).value, 10000);
      solo.close();
      async.flushMicrotasks();
    });
  });

  for (final collect in [true, false]) {
    for (final ending in ['done', 'failed', 'cancel', 'rules', 'replace']) {
      test('${collect ? 'collect' : 'accumulate'} releases input after $ending',
          () {
        fakeAsync((async) {
          final solo = TestSolo();
          final event = Object();
          Future<void> handler(
            SoloContext<TestState, TestState> ctx,
            Object value,
          ) async {
            if (ending == 'failed') throw StateError('handler failed');
          }

          final events = collect
              ? solo.collect<TestState, Object, void>(
                  handler,
                  canStart: (_) => ending != 'rules',
                  policy: AccumulationPolicy.replace,
                )
              : solo.accumulate<TestState, Object, void>(
                  handler,
                  merge: (a, b) => b,
                  canStart: (_) => ending != 'rules',
                  policy: AccumulationPolicy.replace,
                );
          final job = events.add(event)..ignore();
          // Inspect ownership directly instead of relying on GC timing.
          // Retain the former storage itself as well as the completed handle.
          final storage = _privateField(job, '_accumulation')!;
          expect(_privateField(storage, '_value'), isNotNull);
          if (ending == 'cancel') job.cancel();
          if (ending == 'replace') events.add(Object()).ignore();
          async.flushMicrotasks();
          expect(job.isFinished, isTrue);
          expect(_privateField(storage, '_value'), isNull);
          expect(_privateField(job, '_accumulation'), isNull);
          solo.close();
          async.flushMicrotasks();
          final rejected = events.add(event);
          expect(_privateField(rejected, '_accumulation'), isNull);
        });
      });
    }
  }

  test('cancellation diagnostics add to a new group', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final calls = <List<int>>[];
      final events = solo.collect<TestState, int, void>((ctx, values) async {
        calls.add(values);
      });
      final first = events.add(1);
      SoloJob<void>? next;
      var reentered = false;
      SoloBase.debug = (message) {
        if (!message.startsWith('remove ') || reentered) return;
        reentered = true;
        next = events.add(2);
      };
      first.cancel();
      expect(identical(first, next), isFalse);
      async.flushMicrotasks();
      expect(calls, [
        [2],
      ]);
      expect(first.outcome, isA<Cancelled>());
      expect(next!.outcome, isA<Done<void>>());
      solo.close();
      async.flushMicrotasks();
    });
  });

  test('settings merge preserves false and applies only in the handler', () {
    fakeAsync((async) {
      final solo = Solo<_Settings>(const _Settings(true, 'light', 'en'));
      solo.accumulate<_Settings, _Patch, void>(
        (ctx, patch) async {
          ctx.emit(
            _Settings(
              patch.notifications ?? ctx.state.notifications,
              patch.theme ?? ctx.state.theme,
              patch.language ?? ctx.state.language,
            ),
          );
        },
        merge: (a, b) => _Patch(
          notifications: b.notifications ?? a.notifications,
          theme: b.theme ?? a.theme,
          language: b.language ?? a.language,
        ),
      )
        ..add(const _Patch(notifications: false))
        ..add(const _Patch(theme: 'dark'))
        ..add(const _Patch(language: 'ru'))
        ..add(const _Patch(theme: 'system'));
      expect(solo.state.notifications, isTrue);
      expect(solo.state.theme, 'light');
      expect(solo.state.language, 'en');
      async.flushMicrotasks();
      expect(solo.state.notifications, isFalse);
      expect(solo.state.theme, 'system');
      expect(solo.state.language, 'ru');
      solo.close();
      async.flushMicrotasks();
    });
  });
}

final class _Callbacks extends SoloObserver {
  final void Function(Job<Object?>)? _onStart;
  final void Function(Job<Object?>)? _onFinish;
  final void Function(Object)? _onError;

  _Callbacks({
    void Function(Job<Object?>)? onStart,
    void Function(Job<Object?>)? onFinish,
    void Function(Object)? onError,
  })  : _onStart = onStart,
        _onFinish = onFinish,
        _onError = onError;

  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) => _onStart?.call(job);

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) =>
      _onFinish?.call(job);

  @override
  void onError(
    SoloBase<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) =>
      _onError?.call(error);
}

Object? _privateField(Object object, String name) {
  final mirror = reflect(object);
  final symbol = mirror.type.declarations.keys.singleWhere(
    (symbol) => MirrorSystem.getName(symbol) == name,
  );
  return mirror.getField(symbol).reflectee;
}

final class _Settings {
  final bool notifications;
  final String theme;
  final String language;

  const _Settings(this.notifications, this.theme, this.language);
}

final class _Patch {
  final bool? notifications;
  final String? theme;
  final String? language;

  const _Patch({this.notifications, this.theme, this.language});
}
