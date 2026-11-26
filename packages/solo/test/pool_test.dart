// `SoloLanes.pool`: a pool declared in the constructor among the lanes, up
// to `concurrency` root jobs of its one queue running at once, the children
// of its jobs, closing and cancelling with several jobs running in it, the
// keys that keep two jobs of one key apart, and the lines `Solo.debug`
// prints for a pool.
// ignore_for_file: cascade_invocations, no_adjacent_strings_in_list
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:meta/meta.dart';
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

/// Queues in [pool] a job of [key] named [name] that runs [_gated].
SoloJob<void> _keyed(
  SoloPool<int> pool,
  List<String> log,
  Object key,
  String name,
  Completer<void> gate,
) => pool.enqueue<int, void>(
  key: key,
  describe: () => name,
  _gated(log, name, gate),
);

/// A key whose `==` throws at any other key of its kind: one hash for
/// all, so a map compares it with every key of the kind it holds.
@immutable
final class _Touchy {
  final String name;

  const _Touchy(this.name);

  @override
  bool operator ==(Object other) {
    if (other is! _Touchy) return false;
    if (other.name != name) throw const _TouchyError();
    return true;
  }

  @override
  int get hashCode => 0;

  @override
  String toString() => name;
}

final class _TouchyError implements Exception {
  const _TouchyError();
}

/// The outcome of a job its start rules turned down.
final _cancelledByRules = isA<Cancelled>()
    .having((c) => c.reason, 'reason', isA<RulesCancelReason>())
    .having((c) => c.started, 'started', isFalse);

void main() {
  tearDown(() => Solo.debug = null);

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

    test(
      'a job refused by its rules frees its place in the same step',
      () async {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final a = pool.enqueue<int, void>(
          _gated(log, 'a', Completer()),
          canStart: (state) => false,
        );
        final b = pool.enqueue<int, void>(_gated(log, 'b', Completer()));
        final c = pool.enqueue<int, void>(_gated(log, 'c', Completer()));
        // One continuation: the pump scheduled by the enqueues has made one
        // pass, and a second pass would come after this.
        await Future<void>.value();

        expect(a.outcome, _cancelledByRules);
        expect(pool.running, [same(b), same(c)]);
      },
    );

    test('first: true without a key starts before the queued jobs', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(1);
        final log = controller.log;
        final gate = Completer<void>();
        pool.enqueue<int, void>(_gated(log, 'x', gate));
        pool.enqueue<int, void>(_gated(log, 'a', Completer()));
        pool.enqueue<int, void>(_gated(log, 'b', Completer()));
        async.flushMicrotasks();
        final first = pool.enqueueJob(
          pool.job<int, void>(_gated(log, 'first', Completer())),
          first: true,
        );
        async.flushMicrotasks();
        expect(log, ['start x']);

        gate.complete();
        async.flushMicrotasks();
        expect(log, ['start x', 'end x', 'start first']);
        expect(pool.running, [same(first)]);
      });
    });
  });

  group('keys', () {
    test('two jobs of one key never run together', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(4);
        final log = controller.log;
        final gate = Completer<void>();
        final a1 = _keyed(pool, log, 'a', 'a1', gate);
        final a2 = _keyed(pool, log, 'a', 'a2', Completer());
        final b = _keyed(pool, log, 'b', 'b', Completer());
        async.flushMicrotasks();

        expect(log, ['start a1', 'start b']);
        expect(pool.running, [same(a1), same(b)]);
        expect(pool.queue.jobs, [same(a2)]);

        gate.complete();
        async.flushMicrotasks();
        expect(log, ['start a1', 'start b', 'end a1', 'start a2']);
        expect(pool.running, [same(b), same(a2)]);
      });
    });

    test('a job of a held key is overtaken by the jobs behind it', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final a1 = _keyed(pool, log, 'a', 'a1', Completer());
        final a2 = _keyed(pool, log, 'a', 'a2', Completer());
        final c = pool.enqueue<int, void>(_gated(log, 'c', Completer()));
        async.flushMicrotasks();

        expect(log, ['start a1', 'start c']);
        expect(pool.running, [same(a1), same(c)]);
        expect(pool.queue.jobs, [same(a2)]);
      });
    });

    test('the jobs of one key keep their order', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(4);
        final log = controller.log;
        final gates = [for (var i = 0; i < 3; i++) Completer<void>()];
        for (var i = 0; i < 3; i++) {
          _keyed(pool, log, 'a', 'a${i + 1}', gates[i]);
        }
        async.flushMicrotasks();
        expect(log, ['start a1']);

        gates[0].complete();
        async.flushMicrotasks();
        expect(log, ['start a1', 'end a1', 'start a2']);

        gates[1].complete();
        async.flushMicrotasks();
        expect(log, ['start a1', 'end a1', 'start a2', 'end a2', 'start a3']);
      });
    });

    test('the likes of the debate', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(4);
        final log = controller.log;
        void tap(String post, {required bool liked, required int lasting}) {
          final name = '${liked ? 'like' : 'unlike'} $post';
          pool.enqueue<int, void>(key: post, (ctx) async {
            // The heart lights up as the job starts: a mark, then its time.
            ctx.emit(ctx.state + 1);
            log.add('$name ${async.elapsed.inMilliseconds} mark ${ctx.state}');
            await ctx.join(
              () => Future<void>.delayed(Duration(milliseconds: lasting)),
            );
          });
        }

        Timer(
          const Duration(milliseconds: 10),
          () => tap('p1', liked: true, lasting: 2000),
        );
        Timer(
          const Duration(milliseconds: 20),
          () => tap('p1', liked: false, lasting: 100),
        );
        Timer(
          const Duration(milliseconds: 150),
          () => tap('p2', liked: true, lasting: 100),
        );
        async.elapse(const Duration(milliseconds: 160));
        expect(log, ['like p1 10 mark 1', 'like p2 150 mark 2']);

        async.elapse(const Duration(seconds: 3));
        expect(log, [
          'like p1 10 mark 1',
          'like p2 150 mark 2',
          'unlike p1 2010 mark 3',
        ]);
      });
    });

    test('Policy.sequential with a key keeps the order in a pool', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final gate = Completer<void>();
        SoloJob<void> sequential(String name, Completer<void> gate) =>
            pool.enqueue<int, void>(
              key: 'a',
              policy: Policy.sequential,
              _gated(log, name, gate),
            );
        final a1 = sequential('a1', gate);
        final a2 = sequential('a2', Completer());
        async.flushMicrotasks();

        expect(log, ['start a1']);
        expect(pool.running, [same(a1)]);
        expect(pool.queue.jobs, [same(a2)]);

        gate.complete();
        async.flushMicrotasks();
        expect(log, ['start a1', 'end a1', 'start a2']);
        expect(pool.running, [same(a2)]);
      });
    });

    test('first: true with a held key waits for the running job', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(4);
        final log = controller.log;
        final gates = [Completer<void>(), Completer<void>()];
        final a1 = _keyed(pool, log, 'a', 'a1', gates[0]);
        final a2 = _keyed(pool, log, 'a', 'a2', Completer());
        async.flushMicrotasks();
        final a0 = pool.enqueueJob(
          pool.job<int, void>(key: 'a', _gated(log, 'a0', gates[1])),
          first: true,
        );
        async.flushMicrotasks();

        expect(log, ['start a1']);
        expect(pool.running, [same(a1)]);
        expect(pool.queue.jobs, [same(a0), same(a2)]);

        gates[0].complete();
        async.flushMicrotasks();
        expect(log, ['start a1', 'end a1', 'start a0']);

        gates[1].complete();
        async.flushMicrotasks();
        expect(log, ['start a1', 'end a1', 'start a0', 'end a0', 'start a2']);
      });
    });

    test('first: true with a free key heads its key alone', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final gates = [Completer<void>(), Completer<void>()];
        pool.enqueue<int, void>(_gated(log, 'x', gates[0]));
        pool.enqueue<int, void>(_gated(log, 'y', gates[1]));
        async.flushMicrotasks();
        final a1 = _keyed(pool, log, 'a', 'a1', Completer());
        final a0 = pool.enqueueJob(
          pool.job<int, void>(key: 'a', _gated(log, 'a0', Completer())),
          first: true,
        );
        async.flushMicrotasks();

        gates[0].complete();
        async.flushMicrotasks();
        expect(pool.running.last, same(a0));

        // A place is free and a1 is the next of its key: it waits for a0.
        gates[1].complete();
        async.flushMicrotasks();
        expect(log, ['start x', 'start y', 'end x', 'start a0', 'end y']);
        expect(pool.running, [same(a0)]);
        expect(pool.queue.jobs, [same(a1)]);
      });
    });

    test('a key not equal to itself shares nothing', () {
      final lines = <String>[];
      Solo.debug = lines.add;
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final x = Completer<void>();
        final one = _keyed(pool, log, double.nan, 'one', Completer());
        pool.enqueue<int, void>(describe: () => 'x', _gated(log, 'x', x));
        async.flushMicrotasks();
        final two = _keyed(pool, log, double.nan, 'two', Completer());
        x.complete();
        async.flushMicrotasks();

        expect(log, ['start one', 'start x', 'end x', 'start two']);
        expect(pool.running, [same(one), same(two)]);
      });
      Solo.debug = null;

      // Every place is taken when `two` comes, and `one` runs with a key
      // of the same value: what `two` waits for is a place, not the key.
      expect(
        lines,
        contains(
          'p: enqueue Job(NaN: two) while all 2 places are taken: '
          'it starts when one is free',
        ),
      );
    });

    test('a key whose == throws at a held key leaves the job in no list', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        _keyed(pool, log, const _Touchy('a'), 'a', Completer());
        async.flushMicrotasks();

        expect(
          () => _keyed(pool, log, const _Touchy('b'), 'b', Completer()),
          throwsA(isA<_TouchyError>()),
        );
        expect(pool.queue.jobs, isEmpty);
        // Nothing is left behind for the next job of the key to wait on.
        _keyed(pool, log, 'c', 'c', Completer());
        async.flushMicrotasks();
        expect(log, ['start a', 'start c']);
      });
    });

    test('a job dropped in the window frees its key at once', () async {
      final (controller, pool) = _onePool(2);
      final log = controller.log;
      final a1 = pool.enqueue<int, void>(
        key: 'a',
        canStart: (state) => false,
        _gated(log, 'a1', Completer()),
      );
      final a2 = _keyed(pool, log, 'a', 'a2', Completer());
      // One continuation: the pump scheduled by the enqueues has made one
      // pass, and a second pass would come after this.
      await Future<void>.value();

      expect(a1.outcome, _cancelledByRules);
      expect(pool.running, [same(a2)]);
    });

    test('a group waiting for its window holds the jobs of its key', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        String at() => '${async.elapsed.inMilliseconds}';
        final likes = pool.collect<int, bool, void>(
          key: 'p1',
          timing: AccumulationTiming.debounce(
            const Duration(milliseconds: 300),
          ),
          (ctx, events) async {
            log.add('start group ${at()}');
            await ctx.join(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            log.add('end group ${at()}');
          },
        );
        likes.add(true);
        async.elapse(const Duration(milliseconds: 10));
        pool.enqueue<int, void>(
          key: 'p1',
          (ctx) async => log.add('start p1 ${at()}'),
        );
        pool.enqueue<int, void>(
          key: 'p2',
          (ctx) async => log.add('start p2 ${at()}'),
        );
        async.elapse(const Duration(seconds: 1));

        expect(log, [
          'start p2 10',
          'start group 300',
          'end group 400',
          'start p1 400',
        ]);
      });
    });

    test('removing the head of a free key lets the next one start', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(1);
        final log = controller.log;
        final gate = Completer<void>();
        pool.enqueue<int, void>(_gated(log, 'x', gate));
        final a1 = _keyed(pool, log, 'a', 'a1', Completer());
        final a2 = _keyed(pool, log, 'a', 'a2', Completer());
        async.flushMicrotasks();

        expect(pool.queue.remove(a1), isTrue);
        gate.complete();
        async.flushMicrotasks();
        expect(log, ['start x', 'end x', 'start a2']);
        expect(pool.running, [same(a2)]);
      });
    });

    test('removing a waiting group of a key lets the next job start', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final likes = pool.collect<int, bool, void>(
          key: 'a',
          timing: AccumulationTiming.debounce(
            const Duration(milliseconds: 300),
          ),
          (ctx, events) async => log.add('start group'),
        );
        final group = likes.add(true);
        final a = _keyed(pool, log, 'a', 'a', Completer());
        async.flushMicrotasks();
        expect(log, isEmpty);

        // No job ends and no timer is left to bring the pump back: the
        // removal has to.
        expect(pool.queue.remove(group), isTrue);
        async.flushMicrotasks();
        expect(log, ['start a']);
        expect(pool.running, [same(a)]);
      });
    });

    test('a group of a key moved to the tail lets the next job start', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        String at() => '${async.elapsed.inMilliseconds}';
        final likes = pool.collect<int, bool, void>(
          key: 'a',
          policy: AccumulationPolicy.replace,
          timing: AccumulationTiming.debounce(
            const Duration(milliseconds: 300),
          ),
          (ctx, events) async => log.add('start group ${at()}'),
        );
        likes.add(true);
        pool.enqueue<int, void>(
          key: 'a',
          (ctx) async => log.add('start a ${at()}'),
        );
        async.elapse(const Duration(milliseconds: 10));
        expect(log, isEmpty);

        // The group's timer is still ahead: only the move brings the pump.
        likes.add(false);
        async.flushMicrotasks();
        expect(log, ['start a 10']);

        async.elapse(const Duration(seconds: 1));
        expect(log, ['start a 10', 'start group 310']);
      });
    });

    test('a held key costs nothing to the jobs of other keys', () {
      fakeAsync((async) {
        const count = 40000;
        final (controller, pool) = _onePool(2);
        final watch = Stopwatch()..start();
        pool.enqueue<int, void>(
          key: 'k',
          _gated(controller.log, 'held', Completer()),
        );
        for (var i = 0; i < count; i++) {
          pool.enqueue<int, void>(key: 'k', (ctx) async {});
        }
        final free = [
          for (var i = 0; i < count; i++)
            pool.enqueue<int, void>((ctx) async {}),
        ];
        async.flushMicrotasks();
        watch.stop();

        expect(free.where((job) => job.isFinished), hasLength(count));
        expect(pool.queue.length, count);
        printOnFailure('${watch.elapsed}');
        expect(watch.elapsed, lessThan(const Duration(seconds: 6)));
      });
    });
  });

  group('debug lines', () {
    /// The enqueue lines of a pool `p` of two places while [body] runs.
    List<String> enqueues(
      void Function(FakeAsync async, SoloPool<int> pool) body,
    ) {
      final lines = <String>[];
      Solo.debug = lines.add;
      fakeAsync((async) => body(async, _onePool(2).$2));
      Solo.debug = null;
      return [
        for (final line in lines)
          if (line.startsWith('p: enqueue')) line,
      ];
    }

    /// Queues in [pool] a job named [name] that never ends.
    void hangs(
      SoloPool<int> pool,
      String name, {
      Object? key,
      bool first = false,
    }) => pool.enqueueJob(
      pool.job<int, void>(
        key: key,
        describe: () => name,
        (ctx) => Completer<void>().future,
      ),
      first: first,
    );

    test('a job waiting for a held key is not a waiting group', () {
      final lines = <String>[];
      Solo.debug = lines.add;
      fakeAsync((async) {
        final (_, pool) = _onePool(2);
        hangs(pool, 'a1', key: 'a');
        hangs(pool, 'a2', key: 'a');
        async.flushMicrotasks();
      });
      Solo.debug = null;

      expect(lines, isNot(contains('p: queue has no ready jobs')));
      expect(lines, contains('p: enqueue Job(a: a1)'));
    });

    test('a job with a free key and a free place says nothing more', () {
      expect(
        enqueues((async, pool) {
          hangs(pool, 'a1', key: 'a');
          hangs(pool, 'x');
        }),
        ['p: enqueue Job(a: a1)', 'p: enqueue Job(x)'],
      );
    });

    test('a job of a held key says the job that holds it', () {
      expect(
        enqueues((async, pool) {
          hangs(pool, 'a1', key: 'a');
          hangs(pool, 'x');
          async.flushMicrotasks();
          hangs(pool, 'a2', key: 'a');
        }),
        [
          'p: enqueue Job(a: a1)',
          'p: enqueue Job(x)',
          'p: enqueue Job(a: a2) while Job(a: a1) holds key a: '
              'it starts after Job(a: a1) ends',
        ],
      );
    });

    test('first: true is said in the line of a held key', () {
      expect(
        enqueues((async, pool) {
          hangs(pool, 'a1', key: 'a');
          async.flushMicrotasks();
          hangs(pool, 'a0', key: 'a', first: true);
        }).last,
        'p: enqueue Job(a: a0) first while Job(a: a1) holds key a: '
        'it starts after Job(a: a1) ends',
      );
    });

    test('a job behind another of its key says the one ahead', () {
      expect(
        enqueues((async, pool) {
          hangs(pool, 'x');
          hangs(pool, 'y');
          async.flushMicrotasks();
          hangs(pool, 'a1', key: 'a');
          hangs(pool, 'a2', key: 'a');
        }).last,
        'p: enqueue Job(a: a2) behind Job(a: a1) of key a: '
        'it starts after Job(a: a1) ends',
      );
    });

    test('a job that waits for a place says so', () {
      expect(
        enqueues((async, pool) {
          hangs(pool, 'x');
          hangs(pool, 'y');
          async.flushMicrotasks();
          hangs(pool, 'a1', key: 'a');
          hangs(pool, 'z');
        }).sublist(2),
        [
          'p: enqueue Job(a: a1) while all 2 places are taken: '
              'it starts when one is free',
          'p: enqueue Job(z) while all 2 places are taken: '
              'it starts when one is free',
        ],
      );
    });
  });
}
