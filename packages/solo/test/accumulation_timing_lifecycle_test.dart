import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/test_solo.dart';
import 'support/test_state.dart';

const _interval = Duration(milliseconds: 200);

enum _TimingKind { debounce, throttle }

void main() {
  tearDown(() {
    SoloBase.observer = null;
    SoloBase.debug = null;
  });

  for (final kind in _TimingKind.values) {
    for (final collect in [true, false]) {
      for (final policy in AccumulationPolicy.values) {
        test(
          '${kind.name} ${collect ? 'collect' : 'accumulate'} '
          '${policy.name}: ready B bypasses waiting A',
          () {
            fakeAsync((async) {
              final solo = TestSolo();
              final calls = <String>[];
              Future<void> handle(int value) async {
                calls.add('A:$value');
              }

              final events = collect
                  ? solo.collect<TestState, int, void>(
                      (ctx, values) => handle(values.reduce((a, b) => a + b)),
                      policy: policy,
                      timing: _timing(kind),
                    )
                  : solo.accumulate<TestState, int, void>(
                      (ctx, value) => handle(value),
                      merge: (a, b) => a + b,
                      policy: policy,
                      timing: _timing(kind),
                    );
              if (kind == _TimingKind.throttle) {
                events.add(0);
                async.flushMicrotasks();
              }

              final first = events.add(1);
              final separator = solo.run<TestState, void>(
                (ctx) async => calls.add('B'),
              );
              final second = events.add(2);

              expect(
                identical(first, second),
                policy == AccumulationPolicy.join,
              );
              expect(
                solo.queue.jobs,
                switch (policy) {
                  AccumulationPolicy.adjacent => [first, separator, second],
                  AccumulationPolicy.replace => [separator, second],
                  AccumulationPolicy.join => [first, separator],
                },
              );
              if (policy == AccumulationPolicy.replace) {
                expect(first.outcome, isA<Cancelled>());
              }

              async.flushMicrotasks();
              expect(
                calls,
                kind == _TimingKind.throttle ? ['A:0', 'B'] : ['B'],
              );
              expect(
                solo.queue.jobs,
                switch (policy) {
                  AccumulationPolicy.adjacent => [first, second],
                  AccumulationPolicy.replace => [second],
                  AccumulationPolicy.join => [first],
                },
              );

              async.elapse(_interval);
              expect(
                calls,
                switch ((kind, policy)) {
                  (_TimingKind.debounce, AccumulationPolicy.adjacent) => [
                      'B',
                      'A:1',
                      'A:2',
                    ],
                  (_TimingKind.debounce, _) => ['B', 'A:3'],
                  (_TimingKind.throttle, AccumulationPolicy.adjacent) => [
                      'A:0',
                      'B',
                      'A:1',
                    ],
                  (_TimingKind.throttle, _) => ['A:0', 'B', 'A:3'],
                },
              );
              if (kind == _TimingKind.throttle &&
                  policy == AccumulationPolicy.adjacent) {
                async.elapse(_interval);
                expect(calls, ['A:0', 'B', 'A:1', 'A:2']);
              }

              solo.close();
              async.flushMicrotasks();
            });
          },
        );
      }
    }
  }

  for (final kind in _TimingKind.values) {
    test('${kind.name} adjacent reuses the tail after B has run', () {
      fakeAsync((async) {
        final solo = TestSolo();
        final calls = <String>[];
        final events = solo.collect<TestState, int, void>(
          (ctx, values) async => calls.add('${async.elapsed}:$values'),
          timing: _timing(kind),
        );
        if (kind == _TimingKind.throttle) {
          events.add(0);
          async.flushMicrotasks();
          calls.clear();
        }

        final first = events.add(1);
        solo.run<TestState, void>((ctx) async => calls.add('B'));
        async.flushMicrotasks();
        expect(calls, ['B']);
        expect(solo.queue.jobs, [first]);

        async.elapse(const Duration(milliseconds: 50));
        final second = events.add(2);
        expect(identical(first, second), isTrue);
        expect(solo.queue.jobs, [first]);
        async.elapse(
          kind == _TimingKind.debounce
              ? _interval
              : const Duration(milliseconds: 150),
        );
        final expected = kind == _TimingKind.debounce
            ? '0:00:00.250000:[1, 2]'
            : '0:00:00.200000:[1, 2]';
        expect(calls, ['B', expected]);

        solo.close();
        async.flushMicrotasks();
      });
    });
  }

  for (final policy in AccumulationPolicy.values) {
    test('debounce $policy does not reopen a sealed group', () {
      fakeAsync((async) {
        final solo = TestSolo();
        final blocker = Completer<void>();
        final calls = <List<int>>[];
        solo.run<TestState, void>((ctx) => ctx.join(() => blocker.future));
        final events = solo.collect<TestState, int, void>(
          (ctx, values) async => calls.add(values),
          policy: policy,
          timing: AccumulationTiming.debounce(_interval),
        );

        async.flushMicrotasks();
        final first = events.add(1);
        async.elapse(_interval);
        final second = events.add(2);
        expect(identical(first, second), isFalse);
        expect(solo.queue.jobs, [first, second]);

        blocker.complete();
        async.flushMicrotasks();
        expect(calls, [
          [1],
        ]);
        async.elapse(_interval);
        expect(calls, [
          [1],
          [2],
        ]);

        solo.close();
        async.flushMicrotasks();
      });
    });
  }

  for (final kind in _TimingKind.values) {
    test('${kind.name} keeps shared settings and equal keys independent', () {
      fakeAsync((async) {
        final solo = TestSolo();
        final calls = <String>[];
        final timing = _timing(kind);
        final a = solo.collect<TestState, int, void>(
          (ctx, values) async => calls.add('A$values'),
          key: 'same',
          policy: AccumulationPolicy.replace,
          timing: timing,
        );
        final b = solo.collect<TestState, int, void>(
          (ctx, values) async => calls.add('B$values'),
          key: 'same',
          policy: AccumulationPolicy.replace,
          timing: timing,
        );

        final first = a.add(1);
        final second = b.add(2);
        expect(identical(first, second), isFalse);
        expect(solo.queue.jobs, [first, second]);
        if (kind == _TimingKind.debounce) async.elapse(_interval);
        async.flushMicrotasks();
        expect(calls, ['A[1]', 'B[2]']);

        solo.close();
        async.flushMicrotasks();
      });
    });
  }

  for (final hook in ['whenCancelled', 'onFinish']) {
    test('debounce replace publishes before $hook re-enters add', () {
      fakeAsync((async) {
        final solo = TestSolo();
        final calls = <String>[];
        final events = solo.accumulate<TestState, int, void>(
          (ctx, value) async => calls.add('${async.elapsed}:$value'),
          merge: (a, b) => a + b,
          policy: AccumulationPolicy.replace,
          timing: AccumulationTiming.debounce(_interval),
        );
        final first = events.add(1);
        Job<Object?>? published;
        SoloJob<void>? reentrant;
        void callback() {
          published = solo.queue.jobs.single;
          expect(identical(published, first), isFalse);
          reentrant = events.add(4);
        }

        if (hook == 'whenCancelled') {
          first.whenCancelled((_) => callback());
        } else {
          SoloBase.observer = _Callbacks(
            onFinish: (job) {
              if (identical(job, first)) callback();
            },
          );
        }
        async.elapse(const Duration(milliseconds: 100));
        final outer = events.add(2);

        expect(identical(outer, published), isTrue);
        expect(outer.outcome, isA<Cancelled>());
        expect(solo.queue.jobs, [reentrant]);
        async.elapse(const Duration(milliseconds: 199));
        expect(calls, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(calls, ['0:00:00.300000:7']);

        solo.close();
        async.flushMicrotasks();
      });
    });

    for (final action in ['cancel', 'close']) {
      test('debounce replace lets $hook $action the published group', () {
        fakeAsync((async) {
          final solo = TestSolo();
          var handlerCalls = 0;
          final events = solo.collect<TestState, int, void>(
            (ctx, values) async => handlerCalls++,
            policy: AccumulationPolicy.replace,
            timing: AccumulationTiming.debounce(_interval),
          );
          final first = events.add(1);
          Job<Object?>? published;
          void callback() {
            published = solo.queue.jobs.single;
            if (action == 'cancel') {
              published!.cancel();
            } else {
              solo.close();
            }
          }

          if (hook == 'whenCancelled') {
            first.whenCancelled((_) => callback());
          } else {
            SoloBase.observer = _Callbacks(
              onFinish: (job) {
                if (identical(job, first)) callback();
              },
            );
          }
          final replacement = events.add(2);

          expect(identical(replacement, published), isTrue);
          expect(replacement.outcome, isA<Cancelled>());
          expect(solo.queue, isEmpty);
          expect(async.nonPeriodicTimerCount, 0);
          async.elapse(_interval);
          expect(handlerCalls, 0);
          solo.close();
          async.flushMicrotasks();
        });
      });
    }
  }

  test('throttle replace re-entry keeps the running cooldown', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final calls = <String>[];
      final events = solo.accumulate<TestState, int, void>(
        (ctx, value) async => calls.add('${async.elapsed}:$value'),
        merge: (a, b) => a + b,
        policy: AccumulationPolicy.replace,
        timing: AccumulationTiming.throttle(_interval),
      );
      // The first start establishes the cooldown used by later additions.
      // ignore: cascade_invocations
      events.add(0);
      async.flushMicrotasks();
      final first = events.add(1);
      SoloJob<void>? reentrant;
      first.whenCancelled((_) {
        expect(solo.queue.jobs.single, isNot(same(first)));
        reentrant = events.add(4);
      });
      async.elapse(const Duration(milliseconds: 50));
      final outer = events.add(2);

      expect(outer.outcome, isA<Cancelled>());
      expect(solo.queue.jobs, [reentrant]);
      async.elapse(const Duration(milliseconds: 149));
      expect(calls, ['0:00:00.000000:0']);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, ['0:00:00.000000:0', '0:00:00.200000:7']);

      solo.close();
      async.flushMicrotasks();
    });
  });

  for (final kind in _TimingKind.values) {
    for (final operation in ['remove', 'clear']) {
      test('$kind $operation needs force and does not release cooldown', () {
        fakeAsync((async) {
          final solo = TestSolo();
          final calls = <int>[];
          final events = solo.accumulate<TestState, int, void>(
            (ctx, value) async => calls.add(value),
            merge: (a, b) => a + b,
            cancellable: false,
            timing: _timing(kind),
          );
          if (kind == _TimingKind.throttle) {
            events.add(0);
            async.flushMicrotasks();
          }
          final first = events.add(1);

          if (operation == 'remove') {
            expect(solo.queue.remove(first), isFalse);
          } else {
            expect(solo.queue.clear(), 0);
          }
          expect(identical(events.add(2), first), isTrue);
          if (operation == 'remove') {
            expect(solo.queue.remove(first, force: true), isTrue);
          } else {
            expect(solo.queue.clear(force: true), 1);
          }
          expect(first.outcome, isA<Cancelled>());

          final next = events.add(3);
          expect(next.isQueued, isTrue);
          async.elapse(const Duration(milliseconds: 199));
          expect(calls, kind == _TimingKind.throttle ? [0] : isEmpty);
          async.elapse(const Duration(milliseconds: 1));
          expect(calls, kind == _TimingKind.throttle ? [0, 3] : [3]);

          solo.close();
          async.flushMicrotasks();
        });
      });
    }
  }

  for (final kind in _TimingKind.values) {
    test('$kind close drops waiting data and cancels its timers', () {
      fakeAsync((async) {
        final solo = TestSolo();
        var merges = 0;
        final events = solo.accumulate<TestState, int, void>(
          (ctx, value) async {},
          merge: (a, b) {
            merges++;
            return a + b;
          },
          timing: _timing(kind),
        );
        if (kind == _TimingKind.throttle) {
          events.add(0);
          async.flushMicrotasks();
        }
        final waiting = events.add(1);
        expect(async.nonPeriodicTimerCount, 1);

        solo.close();
        expect(waiting.outcome, isA<Cancelled>());
        expect(solo.queue, isEmpty);
        expect(async.nonPeriodicTimerCount, 0);
        final afterClose = events.add(2);
        final again = events.add(3);
        expect(identical(afterClose, again), isFalse);
        expect(afterClose.outcome, isA<Cancelled>());
        expect(again.outcome, isA<Cancelled>());
        expect(merges, 0);
        expect(async.nonPeriodicTimerCount, 0);
        async.flushMicrotasks();
      });
    });

    test('$kind close drains timing work while a protected job runs', () {
      fakeAsync((async) {
        final solo = TestSolo();
        final gate = Completer<void>();
        final blocker = solo.run<TestState, void>(
          (ctx) => ctx.join(() => gate.future),
          cancellable: false,
        );
        final events = solo.collect<TestState, int, void>(
          (ctx, values) async => fail('closed group must not run'),
          timing: _timing(kind),
        );
        async.flushMicrotasks();
        final waiting = events.add(1);
        var closed = false;
        solo.close().then((_) => closed = true);

        expect(waiting.outcome, isA<Cancelled>());
        expect(blocker.isCancelled, isFalse);
        expect(closed, isFalse);
        expect(async.nonPeriodicTimerCount, 0);
        gate.complete();
        async.flushMicrotasks();
        expect(closed, isTrue);
      });
    });

    test('$kind close from canStart prevents the handler and timers', () {
      fakeAsync((async) {
        final solo = TestSolo();
        var handlerCalls = 0;
        final events = solo.collect<TestState, int, void>(
          (ctx, values) async => handlerCalls++,
          canStart: (_) {
            solo.close();
            return true;
          },
          timing: _timing(kind),
        );
        final job = events.add(1);
        if (kind == _TimingKind.debounce) async.elapse(_interval);
        async.flushMicrotasks();

        expect(solo.isClosed, isTrue);
        expect(handlerCalls, 0);
        expect((job.outcome! as Cancelled).started, isFalse);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });
  }

  for (final kind in _TimingKind.values) {
    test('$kind close from onStart prevents the handler and timers', () {
      fakeAsync((async) {
        final solo = TestSolo();
        var handlerCalls = 0;
        late SoloJob<void> first;
        SoloBase.observer = _Callbacks(
          onStart: (job) {
            if (identical(job, first)) solo.close();
          },
        );
        final events = solo.collect<TestState, int, void>(
          (ctx, values) async => handlerCalls++,
          timing: _timing(kind),
        );
        first = events.add(1);
        if (kind == _TimingKind.debounce) async.elapse(_interval);
        async.flushMicrotasks();

        expect(handlerCalls, 0);
        expect((first.outcome! as Cancelled).started, isTrue);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });
  }

  test('a rejected start does not spend the throttle interval', () {
    fakeAsync((async) {
      final solo = TestSolo();
      var allow = false;
      final calls = <String>[];
      final events = solo.collect<TestState, int, void>(
        (ctx, values) async => calls.add('${async.elapsed}:$values'),
        canStart: (_) => allow,
        timing: AccumulationTiming.throttle(_interval),
      );
      final rejected = events.add(1);
      async.flushMicrotasks();
      expect((rejected.outcome! as Cancelled).started, isFalse);
      expect(async.nonPeriodicTimerCount, 0);

      allow = true;
      events.add(2);
      async.flushMicrotasks();
      expect(calls, ['0:00:00.000000:[2]']);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('cancellation from onStart spends the throttle interval', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final calls = <String>[];
      late SoloJob<void> first;
      SoloBase.observer = _Callbacks(
        onStart: (job) {
          if (identical(job, first)) job.cancel();
        },
      );
      final events = solo.collect<TestState, int, void>(
        (ctx, values) async => calls.add('${async.elapsed}:$values'),
        timing: AccumulationTiming.throttle(_interval),
      );
      first = events.add(1);
      async.flushMicrotasks();
      expect((first.outcome! as Cancelled).started, isTrue);
      expect(async.nonPeriodicTimerCount, 1);

      events.add(2);
      async.flushMicrotasks();
      expect(calls, isEmpty);
      async.elapse(const Duration(milliseconds: 199));
      expect(calls, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, ['0:00:00.200000:[2]']);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('cancelling a running group keeps its throttle interval', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final gate = Completer<void>();
      final calls = <String>[];
      final events = solo.collect<TestState, int, void>(
        (ctx, values) async {
          calls.add('${async.elapsed}:$values');
          if (values.first == 1) await ctx.join(() => gate.future);
        },
        timing: AccumulationTiming.throttle(_interval),
      );
      final first = events.add(1);
      async.flushMicrotasks();
      final next = events.add(2);
      async.elapse(const Duration(milliseconds: 100));
      first.cancel();
      gate.complete();
      async.flushMicrotasks();

      expect(first.outcome, isA<Cancelled>());
      expect(next.isQueued, isTrue);
      expect(calls, ['0:00:00.000000:[1]']);
      async.elapse(const Duration(milliseconds: 99));
      expect(calls, ['0:00:00.000000:[1]']);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, [
        '0:00:00.000000:[1]',
        '0:00:00.200000:[2]',
      ]);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('throttle waits for the body, child, and cleanup after its deadline',
      () {
    fakeAsync((async) {
      final solo = TestSolo();
      final body = Completer<void>();
      final child = Completer<void>();
      final cleanup = Completer<void>();
      final calls = <String>[];
      final events = solo.collect<TestState, int, void>(
        (ctx, values) async {
          calls.add('${async.elapsed}:body:$values');
          if (values.first != 1) return;
          ctx
            ..run(
              solo.job<TestState, void>((childCtx) async {
                await childCtx.join(() => child.future);
                calls.add('${async.elapsed}:child');
              }),
            ).ignore()
            ..onDispose(() async {
              calls.add('${async.elapsed}:cleanup');
              await cleanup.future;
              calls.add('${async.elapsed}:cleaned');
            });
          await ctx.join(() => body.future);
          calls.add('${async.elapsed}:body ended');
        },
        timing: AccumulationTiming.throttle(_interval),
      );

      final first = events.add(1);
      async.flushMicrotasks();
      final next = events.add(2);
      async.elapse(const Duration(milliseconds: 250));
      expect(calls, ['0:00:00.000000:body:[1]']);
      expect(next.isQueued, isTrue);

      body.complete();
      async.flushMicrotasks();
      expect(calls, [
        '0:00:00.000000:body:[1]',
        '0:00:00.250000:body ended',
      ]);
      child.complete();
      async.flushMicrotasks();
      expect(calls, [
        '0:00:00.000000:body:[1]',
        '0:00:00.250000:body ended',
        '0:00:00.250000:child',
        '0:00:00.250000:cleanup',
      ]);
      expect(first.isFinished, isFalse);
      expect(next.isQueued, isTrue);

      cleanup.complete();
      async.flushMicrotasks();
      expect(calls, [
        '0:00:00.000000:body:[1]',
        '0:00:00.250000:body ended',
        '0:00:00.250000:child',
        '0:00:00.250000:cleanup',
        '0:00:00.250000:cleaned',
        '0:00:00.250000:body:[2]',
      ]);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('multiple pending throttle groups start one interval apart', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final calls = <String>[];
      final events = solo.collect<TestState, int, void>(
        (ctx, values) async => calls.add('${async.elapsed}:A$values'),
        timing: AccumulationTiming.throttle(_interval),
      );
      // Separators below deliberately split subsequent adjacent groups.
      // ignore: cascade_invocations
      events.add(0);
      async.flushMicrotasks();

      // Ordinary jobs below deliberately separate the adjacent groups.
      // ignore: cascade_invocations
      events.add(1);
      solo.run<TestState, void>(
        (ctx) async => calls.add('${async.elapsed}:B'),
      );
      events.add(2);
      solo.run<TestState, void>(
        (ctx) async => calls.add('${async.elapsed}:C'),
      );
      events.add(3);
      async.flushMicrotasks();
      expect(calls, [
        '0:00:00.000000:A[0]',
        '0:00:00.000000:B',
        '0:00:00.000000:C',
      ]);

      async.elapse(_interval);
      expect(calls.last, '0:00:00.200000:A[1]');
      async.elapse(_interval);
      expect(calls.last, '0:00:00.400000:A[2]');
      async.elapse(_interval);
      expect(calls.last, '0:00:00.600000:A[3]');
      expect(calls.length, 6);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('an add callback before the debounce deadline extends the group', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final calls = <String>[];
      final events = solo.collect<TestState, int, void>(
        (ctx, values) async => calls.add('${async.elapsed}:$values'),
        timing: AccumulationTiming.debounce(_interval),
      );
      Timer(_interval, () => events.add(2));
      final first = events.add(1);

      async.elapse(_interval);
      expect(calls, isEmpty);
      expect(solo.queue.jobs, [first]);
      async.elapse(_interval);
      expect(calls, ['0:00:00.400000:[1, 2]']);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('an add callback after the debounce deadline opens a new group', () {
    fakeAsync((async) {
      final solo = TestSolo();
      final calls = <String>[];
      final events = solo.collect<TestState, int, void>(
        (ctx, values) async => calls.add('${async.elapsed}:$values'),
        timing: AccumulationTiming.debounce(_interval),
      );
      final first = events.add(1);
      SoloJob<void>? second;
      Timer(_interval, () => second = events.add(2));

      async.elapse(_interval);
      expect(identical(first, second), isFalse);
      expect(calls, ['0:00:00.200000:[1]']);
      async.elapse(_interval);
      expect(calls, [
        '0:00:00.200000:[1]',
        '0:00:00.400000:[2]',
      ]);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('an elapsed throttle interval leaves no timer without more data', () {
    fakeAsync((async) {
      final solo = TestSolo();
      var calls = 0;
      final events = solo.collect<TestState, int, void>(
        (ctx, values) async => calls++,
        timing: AccumulationTiming.throttle(_interval),
      );
      // Time advances after the first start to inspect the expired interval.
      // ignore: cascade_invocations
      events.add(1);
      async.flushMicrotasks();
      expect(async.nonPeriodicTimerCount, 1);

      async.elapse(_interval);
      expect(async.nonPeriodicTimerCount, 0);
      async.elapse(_interval);
      expect(calls, 1);
      expect(async.nonPeriodicTimerCount, 0);

      solo.close();
      async.flushMicrotasks();
    });
  });
}

AccumulationTiming _timing(_TimingKind kind) => switch (kind) {
      _TimingKind.debounce => AccumulationTiming.debounce(_interval),
      _TimingKind.throttle => AccumulationTiming.throttle(_interval),
    };

final class _Callbacks extends SoloObserver {
  final void Function(Job<Object?>)? _onStart;
  final void Function(Job<Object?>)? _onFinish;

  _Callbacks({
    void Function(Job<Object?>)? onStart,
    void Function(Job<Object?>)? onFinish,
  })  : _onStart = onStart,
        _onFinish = onFinish;

  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) => _onStart?.call(job);

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) =>
      _onFinish?.call(job);
}
