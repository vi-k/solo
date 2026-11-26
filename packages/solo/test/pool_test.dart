// `SoloLanes.pool`: a pool declared in the constructor among the lanes, up
// to `concurrency` root jobs of its one queue running at once, the children
// of its jobs, and closing and cancelling with several jobs running in it.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

/// Pools and lanes declared by whoever makes it, in its constructor body.
final class _Pools extends SoloLanes<int> {
  final log = <String>[];

  _Pools([void Function(_Pools self)? declare]) : super(0) {
    declare?.call(this);
  }

  SoloPool<int> declarePool(String name, int concurrency) =>
      pool(name, concurrency: concurrency);

  SoloLane<int> declareLane(String name) => lane(name);

  List<SoloPool<int>> get declaredPools => pools;

  List<SoloLane<int>> get declaredLanes => lanes;
}

/// A body that logs `start name`, waits for [gate] and logs `end name`.
Future<void> Function(SoloContext<int, int>) _gated(
  List<String> log,
  String name,
  Completer<void> gate,
) => (ctx) async {
  log.add('start $name');
  await gate.future;
  log.add('end $name');
};

/// A [StateError] whose message contains [text].
Matcher _stateError(String text) => throwsA(
  isA<StateError>().having((e) => e.message, 'message', contains(text)),
);

/// A pool of [concurrency] places named `p`, the only one of its controller.
(_Pools, SoloPool<int>) _onePool(int concurrency) {
  final controller = _Pools((self) => self.declarePool('p', concurrency));
  return (controller, controller.declaredPools.single);
}

void main() {
  group('declaring', () {
    test('pool takes a place among lanes in the order of declaration', () {
      final controller = _Pools((self) {
        self
          ..declareLane('a')
          ..declarePool('p', 2)
          ..declareLane('b');
      });
      final pool = controller.declaredPools.single;

      expect(
        [for (final lane in controller.declaredLanes) lane.name],
        ['a', 'b'],
      );
      expect([for (final pool in controller.declaredPools) pool.name], ['p']);
      expect(pool.concurrency, 2);
      expect('$pool', 'SoloPool(p)');
      expect(pool.id.name, 'p');
      expect(() => controller.declaredPools.add(pool), throwsUnsupportedError);
    });

    test('a pool and a lane of one name throw', () {
      expect(
        () => _Pools((self) {
          self
            ..declareLane('x')
            ..declarePool('x', 2);
        }),
        _stateError('has a lane named x already'),
      );
      expect(
        () => _Pools((self) {
          self
            ..declarePool('y', 2)
            ..declareLane('y');
        }),
        _stateError('has a pool named y already'),
      );
      expect(
        () => _Pools((self) {
          self
            ..declarePool('z', 2)
            ..declarePool('z', 3);
        }),
        _stateError('has a pool named z already'),
      );
    });

    test('concurrency below 1 throws ArgumentError', () {
      for (final concurrency in [0, -1]) {
        expect(
          () => _Pools((self) => self.declarePool('p', concurrency)),
          throwsA(
            isA<ArgumentError>()
                .having((e) => e.name, 'name', 'concurrency')
                .having((e) => e.invalidValue, 'value', concurrency),
          ),
          reason: '$concurrency',
        );
      }
    });

    test('pool after the constructor throws', () {
      fakeAsync((async) {
        final controller = _Pools((self) => self.declareLane('a'));
        async.flushMicrotasks();

        expect(
          () => controller.declarePool('p', 2),
          _stateError('Cannot declare pool p'),
        );
        expect(controller.declaredPools, isEmpty);
      });
    });

    test('a job of the pool says the pool in job.lane', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        late SoloJob<void> child;
        final root = pool.enqueue<int, void>((ctx) async {
          child = ctx.child<void>((ctx) async {});
          await ctx.run(child);
        });
        async.flushMicrotasks();

        expect(root.outcome, isA<Done<void>>());
        expect(root.lane, same(pool.id));
        expect(child.lane, same(pool.id));
        expect(controller.declaredLanes, isEmpty);
      });
    });

    test('a job of another pool or lane is refused', () {
      final controller = _Pools((self) {
        self
          ..declarePool('p', 2)
          ..declarePool('q', 2)
          ..declareLane('a');
      });
      final [pool, other] = controller.declaredPools;
      final lane = controller.declaredLanes.single;
      final refused = throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('was not created by this pool'),
        ),
      );

      expect(
        () => pool.enqueueJob(lane.job<int, void>((ctx) async {})),
        refused,
      );
      expect(
        () => pool.enqueueJob(other.job<int, void>((ctx) async {})),
        refused,
      );
      expect(pool.queue.isEmpty, isTrue);
    });
  });

  group('places', () {
    test('up to concurrency root jobs run at once', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final gates = [for (var i = 0; i < 3; i++) Completer<void>()];
        final a = pool.enqueue<int, void>(_gated(log, 'a', gates[0]));
        final b = pool.enqueue<int, void>(_gated(log, 'b', gates[1]));
        final c = pool.enqueue<int, void>(_gated(log, 'c', gates[2]));
        async.flushMicrotasks();

        expect(log, ['start a', 'start b']);
        expect(pool.running, [same(a), same(b)]);
        expect(pool.queue.jobs, [same(c)]);

        gates[0].complete();
        async.flushMicrotasks();
        expect(log, ['start a', 'start b', 'end a', 'start c']);
        expect(pool.running, [same(b), same(c)]);
        expect(pool.queue.isEmpty, isTrue);
      });
    });

    test('a pool of one runs like a lane', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(1);
        final log = controller.log;
        final gate = Completer<void>();
        final a = pool.enqueue<int, void>(_gated(log, 'a', gate));
        final b = pool.enqueue<int, void>(_gated(log, 'b', Completer()));
        async.flushMicrotasks();

        expect(log, ['start a']);
        expect(pool.running, [same(a)]);
        expect(pool.queue.jobs, [same(b)]);

        gate.complete();
        async.flushMicrotasks();
        expect(log, ['start a', 'end a', 'start b']);
        expect(pool.running, [same(b)]);
      });
    });

    test('running is a snapshot', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final gate = Completer<void>();
        final a = pool.enqueue<int, void>(_gated(controller.log, 'a', gate));
        async.flushMicrotasks();
        final before = pool.running;

        gate.complete();
        async.flushMicrotasks();
        expect(a.isFinished, isTrue);
        expect(before, [same(a)]);
        expect(pool.running, isEmpty);
        expect(() => before.add(a), throwsUnsupportedError);
      });
    });

    test('a child of a pool job takes no place', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(1);
        final log = controller.log;
        final gates = [Completer<void>(), Completer<void>()];
        final root = pool.enqueue<int, void>((ctx) async {
          log.add('start root');
          await [
            ctx.run(ctx.child<void>(_gated(log, 'one', gates[0]))),
            ctx.run(ctx.child<void>(_gated(log, 'two', gates[1]))),
          ].wait;
          log.add('end root');
        });
        async.flushMicrotasks();

        expect(log, ['start root', 'start one', 'start two']);
        expect(pool.running, [same(root)]);

        for (final gate in gates) {
          gate.complete();
        }
        async.flushMicrotasks();
        expect(log.last, 'end root');
        expect(root.outcome, isA<Done<void>>());
      });
    });

    test('lastJobWhere finds a running job of the pool', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final a = pool.enqueue<int, void>(
          _gated(controller.log, 'a', Completer()),
        );
        final b = pool.enqueue<int, void>(
          _gated(controller.log, 'b', Completer()),
        );
        async.flushMicrotasks();

        expect(pool.running, [same(a), same(b)]);
        expect(pool.lastJobWhere((job) => true), same(b));
        expect(pool.lastJobWhere((job) => identical(job, a)), same(a));
      });
    });

    test('cancelAll cancels every running job of a pool and waits for all', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final gates = [Completer<void>(), Completer<void>()];
        final a = pool.enqueue<int, void>(_gated(log, 'a', gates[0]));
        final b = pool.enqueue<int, void>(_gated(log, 'b', gates[1]));
        final c = pool.enqueue<int, void>(_gated(log, 'c', Completer()));
        async.flushMicrotasks();
        var cancelled = false;
        controller.cancelAll().then((_) => cancelled = true);

        expect(
          c.outcome,
          isA<Cancelled>()
              .having((c) => c.reason, 'reason', isA<ManualCancelReason>())
              .having((c) => c.started, 'started', isFalse),
        );
        expect(a.isCancelled, isTrue);
        expect(b.isCancelled, isTrue);

        gates[0].complete();
        async.flushMicrotasks();
        expect(a.isFinished, isTrue);
        expect(cancelled, isFalse);

        gates[1].complete();
        async.flushMicrotasks();
        expect(b.isFinished, isTrue);
        expect(cancelled, isTrue);
        expect(log, ['start a', 'start b', 'end a', 'end b']);
      });
    });

    test('close waits for every running job of a pool', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final gates = [Completer<void>(), Completer<void>()];
        final a = pool.enqueue<int, void>(_gated(log, 'a', gates[0]));
        final b = pool.enqueue<int, void>(_gated(log, 'b', gates[1]));
        async.flushMicrotasks();
        var closed = false;
        controller.close().then((_) => closed = true);
        async.flushMicrotasks();

        expect(a.isCancelled, isTrue);
        expect(b.isCancelled, isTrue);

        gates[1].complete();
        async.flushMicrotasks();
        expect(b.isFinished, isTrue);
        expect(closed, isFalse);

        gates[0].complete();
        async.flushMicrotasks();
        expect(a.isFinished, isTrue);
        expect(closed, isTrue);
        expect(controller.isFinished, isTrue);
      });
    });
  });
}
