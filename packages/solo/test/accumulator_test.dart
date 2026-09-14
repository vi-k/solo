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
      expect(solo.currentState, 0);
      expect(calls, isEmpty);
      async.flushMicrotasks();
      expect(calls, [
        [1, 2],
      ]);
      expect(solo.currentState, 2);
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
          expect(
            identical(first, second),
            policy != AccumulationPolicy.adjacent,
          );
          expect(solo.currentState, '');
          if (policy == AccumulationPolicy.replace) {
            // The group moved behind B, and nothing was cancelled on the
            // way: one handle, and it is still waiting its turn.
            expect(first.outcome, isNull);
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
        expect(identical(a, b), isTrue);
        expect(identical(b, c), isTrue);
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

    test('$policy adds while a protected group runs', () {
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
        expect(queued.isCancelled, isFalse);
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
      final events = solo.collect<TestState, int, void>(
        (ctx, values) async {
          calls.add(values);
        },
        policy: AccumulationPolicy.adjacent,
      );
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
      expect(solo.currentState.notifications, isTrue);
      expect(solo.currentState.theme, 'light');
      expect(solo.currentState.language, 'en');
      async.flushMicrotasks();
      expect(solo.currentState.notifications, isFalse);
      expect(solo.currentState.theme, 'system');
      expect(solo.currentState.language, 'ru');
      solo.close();
      async.flushMicrotasks();
    });
  });

  // The default rule is `AccumulationPolicy.join`: a job of another kind
  // between two events is not a boundary, and the events of one group share
  // one handle. All three below fail against `adjacent` as the default.
  for (final timing in _defaultTimings.entries) {
    test('a call without a policy, ${timing.key}, behind a running job', () {
      final handles = <SoloJob<void>>[];
      expect(
        _defaultTrace(timing: timing.value, handles: handles),
        ['run[a1+a2]@100', 'other@100'],
      );
      expect(identical(handles.first, handles.last), isTrue);
    });
  }

  test('a call without a policy under a trailing throttle', () {
    final handles = <SoloJob<void>>[];
    expect(
      _defaultTrace(
        timing: AccumulationTiming.throttle(
          const Duration(seconds: 1),
          startAtOnce: false,
        ),
        handles: handles,
      ),
      ['other@100', 'run[a1+a2]@1000'],
    );
    expect(identical(handles.first, handles.last), isTrue);
  });

  // What the wave of three accumulator changes must not move. These are
  // green on the untouched tree and stay green with the wave applied; the
  // plan 2026-09-14[32]-accumulation-rules-plan.md names what proves each.
  //
  // None of them asserts a handle beyond the one the last `add` returned:
  // `replace` changes handles on purpose, and a guard that named them
  // would be rewritten by the very change it is there to witness.
  for (final policy in AccumulationPolicy.values) {
    for (final timing in _zeroTimings.entries) {
      test('$policy with ${timing.key} on a free queue', () {
        expect(
          _rulesTrace(policy, timing: timing.value, busy: false),
          ['run[a1]@0', 'other@0', 'run[a2]@50'],
        );
      });

      test('$policy with ${timing.key} behind a running job', () {
        expect(
          _rulesTrace(policy, timing: timing.value, busy: true),
          switch (policy) {
            AccumulationPolicy.adjacent => [
                'run[a1]@100',
                'other@100',
                'run[a2]@100',
              ],
            AccumulationPolicy.replace => ['other@100', 'run[a1+a2]@100'],
            AccumulationPolicy.join => ['run[a1+a2]@100', 'other@100'],
          },
        );
      });
    }
  }

  // `AccumulationPolicy.replace` moves the waiting group to the tail instead
  // of building a new job and cancelling this one. All five below fail
  // against the rule as it was: it answered every event with a new handle.
  for (final protected in [false, true]) {
    test(
        'replace: five events into a busy queue'
        '${protected ? ', protected' : ''}', () {
      fakeAsync((async) {
        final solo = TestSolo();
        final gate = Completer<void>();
        final calls = <int>[];
        solo.run<TestState, void>(
          key: 'busy',
          (ctx) => ctx.join(() => gate.future),
        );
        final events = solo.accumulate<TestState, int, void>(
          (ctx, value) async => calls.add(value),
          merge: (a, b) => a + b,
          key: 'a',
          policy: AccumulationPolicy.replace,
          cancellable: !protected,
        );
        async.flushMicrotasks();
        final handles = <SoloJob<void>>[
          for (var event = 1; event <= 5; event++) events.add(event),
        ];

        expect(handles.every((job) => identical(job, handles.first)), isTrue);
        expect(handles.first.isCancelled, isFalse);
        expect(solo.queue.length, 1);
        gate.complete();
        async.flushMicrotasks();
        expect(calls, [15]);
        expect(handles.first.outcome, isA<Done<void>>());

        solo.close();
        async.flushMicrotasks();
      });
    });
  }

  test('replace: what an observer sees for five events', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final gate = Completer<void>();
      final journal = <String>[];
      SoloBase.observer = _Callbacks(
        onStart: (job) => journal.add('start ${job.key}'),
        onFinish: (job) => journal.add('finish ${job.key} ${job.outcome}'),
      );
      solo.run<TestState, void>(
        key: 'busy',
        (ctx) => ctx.join(() => gate.future),
      );
      final events = solo.accumulate<TestState, int, void>(
        (ctx, value) async {},
        merge: (a, b) => a + b,
        key: 'a',
        policy: AccumulationPolicy.replace,
      );
      async.flushMicrotasks();
      for (var event = 1; event <= 5; event++) {
        events.add(event);
      }
      gate.complete();
      async.flushMicrotasks();

      // Four events for six jobs' worth of additions: the queue is busy, so
      // the group waits and every event after the first joins it.
      expect(journal, [
        'start busy',
        'finish busy Done(null)',
        'start a',
        'finish a Done(null)',
      ]);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('replace: clear without force and the event after it', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final gate = Completer<void>();
      final calls = <int>[];
      solo.run<TestState, void>(
        key: 'busy',
        (ctx) => ctx.join(() => gate.future),
      );
      final events = solo.accumulate<TestState, int, void>(
        (ctx, value) async => calls.add(value),
        merge: (a, b) => a + b,
        key: 'a',
        policy: AccumulationPolicy.replace,
        cancellable: false,
      );
      async.flushMicrotasks();
      final first = events.add(1);
      expect(solo.queue.clear(), 0);
      expect(identical(events.add(2), first), isTrue);
      gate.complete();
      async.flushMicrotasks();
      expect(calls, [3]);
      expect(first.outcome, isA<Done<void>>());

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('replace: an event for a group already at the tail', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final gate = Completer<void>();
      final calls = <String>[];
      solo.run<TestState, void>(
        key: 'busy',
        (ctx) => ctx.join(() => gate.future),
      );
      final events = solo.accumulate<TestState, int, void>(
        (ctx, value) async => calls.add('a:$value'),
        merge: (a, b) => a + b,
        key: 'a',
        policy: AccumulationPolicy.replace,
      );
      async.flushMicrotasks();
      final first = events.add(1);
      final separator = solo.run<TestState, void>(
        key: 'b',
        (ctx) async => calls.add('b'),
      );
      final moved = events.add(2);
      expect(solo.queue.jobs, [separator, first]);

      // The group is at the tail now, and the next event finds it there.
      final again = events.add(4);
      expect(identical(moved, first), isTrue);
      expect(identical(again, first), isTrue);
      expect(solo.queue.jobs, [separator, first]);
      gate.complete();
      async.flushMicrotasks();
      expect(calls, ['b', 'a:7']);
      expect(first.outcome, isA<Done<void>>());

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('replace: a restart with the same key takes the waiting group', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final calls = <String>[];
      final gate = Completer<void>();
      solo.run<TestState, void>(
        key: 'busy',
        (ctx) => ctx.join(() => gate.future),
      );
      final events = solo.accumulate<TestState, int, void>(
        (ctx, value) async => calls.add('group:$value'),
        merge: (a, b) => a + b,
        key: 'shared',
        policy: AccumulationPolicy.replace,
      );
      async.flushMicrotasks();
      events.add(1);
      expect(solo.queue.length, 1);
      final group = events.add(2);
      solo.run<TestState, void>(
        key: 'shared',
        policy: Policy.restart,
        (ctx) async => calls.add('restart'),
      );
      expect(solo.queue.length, 1);
      expect(group.isCancelled, isTrue);
      gate.complete();
      async.flushMicrotasks();
      expect(calls, ['restart']);
      solo.close();
      async.flushMicrotasks();
    });
  });

  test('replace: an open group stays behind a sealed one', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final calls = <String>[];
      final gate = Completer<void>();
      solo.run<TestState, void>(
        key: 'busy',
        (ctx) => ctx.join(() => gate.future),
      );
      final events = solo.accumulate<TestState, int, void>(
        (ctx, value) async => calls.add('${async.elapsed}:$value'),
        merge: (a, b) => a + b,
        key: 'shared',
        policy: AccumulationPolicy.replace,
        timing: AccumulationTiming.debounce(const Duration(milliseconds: 200)),
      );
      async.flushMicrotasks();
      events.add(1);
      async.elapse(const Duration(milliseconds: 250));
      events.add(2);
      final second = events.add(4);
      expect(solo.queue.length, 2);
      gate.complete();
      async.flushMicrotasks();
      expect(calls, ['0:00:00.250000:1']);
      async.elapse(const Duration(milliseconds: 200));
      expect(calls, ['0:00:00.250000:1', '0:00:00.450000:6']);
      expect(second.outcome, isA<Done<void>>());
      solo.close();
      async.flushMicrotasks();
    });
  });

  test('replace: a failed merge leaves the group and its deadline', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final calls = <String>[];
      final error = StateError('merge failed');
      final events = solo.accumulate<TestState, int, void>(
        (ctx, value) async => calls.add('${async.elapsed}:$value'),
        merge: (a, b) => b == 99 ? throw error : a + b,
        policy: AccumulationPolicy.replace,
        timing: AccumulationTiming.debounce(const Duration(milliseconds: 200)),
      );
      // The clock moves between the additions, so a cascade is misleading.
      // ignore: cascade_invocations
      events.add(1);
      async.elapse(const Duration(milliseconds: 100));
      expect(() => events.add(99), throwsA(same(error)));
      expect(solo.queue.length, 1);
      async.elapse(const Duration(milliseconds: 99));
      expect(calls, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, ['0:00:00.200000:1']);
      solo.close();
      async.flushMicrotasks();
    });
  });

  test('replace: clear without force leaves a protected group', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final calls = <int>[];
      final gate = Completer<void>();
      solo.run<TestState, void>(
        key: 'busy',
        (ctx) => ctx.join(() => gate.future),
      );
      final events = solo.accumulate<TestState, int, void>(
        (ctx, value) async => calls.add(value),
        merge: (a, b) => a + b,
        policy: AccumulationPolicy.replace,
        cancellable: false,
      );
      async.flushMicrotasks();
      events.add(1);
      final group = events.add(2);
      expect(solo.queue.clear(), 0);
      expect(solo.queue.length, 1);
      expect(group.isCancelled, isFalse);
      expect(solo.queue.clear(force: true), 1);
      expect(group.isCancelled, isTrue);
      gate.complete();
      async.flushMicrotasks();
      expect(calls, isEmpty);
      solo.close();
      async.flushMicrotasks();
    });
  });

  test('replace: cancelAll takes the waiting group', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final calls = <int>[];
      final gate = Completer<void>();
      solo.run<TestState, void>(
        key: 'busy',
        (ctx) => ctx.join(() => gate.future),
      );
      final events = solo.accumulate<TestState, int, void>(
        (ctx, value) async => calls.add(value),
        merge: (a, b) => a + b,
        policy: AccumulationPolicy.replace,
      );
      async.flushMicrotasks();
      events.add(1);
      final group = events.add(2);
      solo.cancelAll();
      expect(solo.queue.isEmpty, isTrue);
      expect(group.isCancelled, isTrue);
      gate.complete();
      async.flushMicrotasks();
      expect(calls, isEmpty);
      solo.close();
      async.flushMicrotasks();
    });
  });

  for (final mode in SoloCloseMode.values) {
    test('replace: close(mode: ${mode.name}) treats it as any queued job', () {
      fakeAsync((async) {
        final solo = TestSolo();
        final calls = <int>[];
        final gate = Completer<void>();
        solo.run<TestState, void>(
          key: 'busy',
          (ctx) => ctx.join(() => gate.future),
        );
        final events = solo.accumulate<TestState, int, void>(
          (ctx, value) async => calls.add(value),
          merge: (a, b) => a + b,
          policy: AccumulationPolicy.replace,
        );
        async.flushMicrotasks();
        events.add(1);
        final group = events.add(2);
        solo.close(mode: mode);
        gate.complete();
        async.flushMicrotasks();
        expect(calls, mode == SoloCloseMode.drain ? [3] : isEmpty);
        expect(group.isCancelled, mode == SoloCloseMode.cancel);
      });
    });
  }

  test('replace: a job added first runs ahead of the waiting group', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final calls = <String>[];
      final gate = Completer<void>();
      solo.run<TestState, void>(
        key: 'busy',
        (ctx) => ctx.join(() => gate.future),
      );
      final events = solo.accumulate<TestState, int, void>(
        (ctx, value) async => calls.add('group:$value'),
        merge: (a, b) => a + b,
        policy: AccumulationPolicy.replace,
      );
      async.flushMicrotasks();
      events
        ..add(1)
        ..add(2);
      solo.add(
        solo.job<TestState, void>(
          key: 'ahead',
          (ctx) async => calls.add('ahead'),
        ),
        first: true,
      );
      gate.complete();
      async.flushMicrotasks();
      expect(calls, ['ahead', 'group:3']);
      solo.close();
      async.flushMicrotasks();
    });
  });

  test('replace: a refused start cancels the group with its rules', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final calls = <int>[];
      final events = solo.accumulate<TestState, int, void>(
        (ctx, value) async => calls.add(value),
        merge: (a, b) => a + b,
        policy: AccumulationPolicy.replace,
        canStart: (state) => state is Working,
      );
      // What the queue holds between the additions is the point here.
      // ignore: cascade_invocations
      events.add(1);
      expect(solo.queue.length, 1);
      final group = events.add(2);
      async.flushMicrotasks();
      expect(calls, isEmpty);
      expect((group.outcome! as Cancelled).reason, isA<RulesCancelReason>());
      solo.close();
      async.flushMicrotasks();
    });
  });

  test('replace: a new event leaves a running group to its keepWhile', () {
    fakeAsync((async) {
      final solo = TestSolo(const Working());
      final gate = Completer<void>();
      final calls = <String>[];
      final events = solo.accumulate<Working, int, void>(
        (ctx, value) async {
          calls.add('start:$value');
          await ctx.join(() => gate.future);
          calls.add('end:$value');
        },
        merge: (a, b) => a + b,
        policy: AccumulationPolicy.replace,
        keepWhile: (state) => state.a == 0,
      );
      final running = events.add(1);
      async.flushMicrotasks();
      expect(calls, ['start:1']);
      final next = events.add(2);
      solo.externalSetState(const Working(a: 1));
      expect(running.isCancelled, isTrue);
      expect(running.isFinished, isFalse);
      expect(next.isCancelled, isFalse);
      gate.complete();
      async.flushMicrotasks();
      expect(calls, ['start:1']);
      expect((running.outcome! as Cancelled).reason, isA<RulesCancelReason>());
      expect((next.outcome! as Cancelled).reason, isA<RulesCancelReason>());
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

/// The timings a zero duration makes indistinguishable from none at all.
/// A zero duration is cut off before `startAtOnce` means anything, so the
/// trailing throttle belongs in this table as much as the other two.
final _zeroTimings = <String, AccumulationTiming?>{
  'no timing': null,
  'a zero debounce': AccumulationTiming.debounce(Duration.zero),
  'a zero throttle': AccumulationTiming.throttle(Duration.zero),
  'a zero trailing throttle': AccumulationTiming.throttle(
    Duration.zero,
    startAtOnce: false,
  ),
};

/// Runs A1, a job of another kind, then A2 fifty milliseconds later, and
/// returns what ran and when. With [busy] another job holds the queue for
/// the first hundred milliseconds, so the rule has something to rule on:
/// on a free queue every event finds the queue empty and starts its own
/// group whatever the rule says.
List<String> _rulesTrace(
  AccumulationPolicy policy, {
  required AccumulationTiming? timing,
  required bool busy,
}) {
  final trace = <String>[];
  fakeAsync((async) {
    int now() => async.elapsed.inMilliseconds;
    final solo = Solo<int>(0);
    final events = solo.accumulate<int, String, void>(
      (ctx, value) async => trace.add('run[$value]@${now()}'),
      merge: (accumulated, incoming) => '$accumulated+$incoming',
      key: 'a',
      policy: policy,
      timing: timing,
    );
    if (busy) {
      solo.run<int, void>(
        key: 'busy',
        (ctx) => ctx.wait(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        ),
      );
    }
    events.add('a1');
    solo.run<int, void>(
      key: 'other',
      (ctx) async => trace.add('other@${now()}'),
    );
    async.elapse(const Duration(milliseconds: 50));
    events.add('a2');
    async.elapse(const Duration(seconds: 2));
    solo.close();
    async.flushMicrotasks();
  });
  return trace;
}

/// The timings a call without a policy is written with in the wild: none,
/// and the two zero durations that used to be a reason for the rule to
/// differ. Comparing them with each other proves nothing -- before the
/// default changed they agreed too -- so each is checked against the trace.
final _defaultTimings = <String, AccumulationTiming?>{
  'no timing': null,
  'a zero debounce': AccumulationTiming.debounce(Duration.zero),
  'a zero throttle': AccumulationTiming.throttle(Duration.zero),
};

/// [_rulesTrace] for a call that names no policy at all, collecting the
/// handles the two additions came back with.
List<String> _defaultTrace({
  required AccumulationTiming? timing,
  required List<SoloJob<void>> handles,
}) {
  final trace = <String>[];
  fakeAsync((async) {
    int now() => async.elapsed.inMilliseconds;
    final solo = Solo<int>(0);
    final events = solo.accumulate<int, String, void>(
      (ctx, value) async => trace.add('run[$value]@${now()}'),
      merge: (accumulated, incoming) => '$accumulated+$incoming',
      key: 'a',
      timing: timing,
    );
    solo.run<int, void>(
      key: 'busy',
      (ctx) => ctx.wait(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      ),
    );
    handles.add(events.add('a1'));
    solo.run<int, void>(
      key: 'other',
      (ctx) async => trace.add('other@${now()}'),
    );
    async.elapse(const Duration(milliseconds: 50));
    handles.add(events.add('a2'));
    async.elapse(const Duration(seconds: 3));
    solo.close();
    async.flushMicrotasks();
  });
  return trace;
}
