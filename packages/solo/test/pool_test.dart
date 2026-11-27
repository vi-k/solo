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

/// A pool `p` of two places over a state of any kind, for a job whose
/// working type is narrower than the state.
final class _Any extends SoloLanes<Object> {
  late final SoloPool<Object> p;

  _Any() : super('off') {
    p = pool('p', concurrency: 2);
  }
}

/// The lines [Solo.debug] prints while [body] runs.
List<String> _debugLines(void Function(FakeAsync async) body) {
  final lines = <String>[];
  Solo.debug = lines.add;
  try {
    fakeAsync(body);
  } finally {
    Solo.debug = null;
  }
  return lines;
}

/// A controller with the pools `likes` of two places and `uploads` of one,
/// and the lane `l`.
_Pools _writers() => _Pools(
  (self) => self
    ..declarePool('likes', 2)
    ..declarePool('uploads', 1)
    ..declareLane('l'),
);

/// The lines about a write over another, from the job `p1` of `likes` that
/// reads the state, waits while [write] writes, and writes what it read.
List<String> _overWrites(
  void Function(_Pools controller, FakeAsync async) write,
) {
  final trace = _debugLines((async) {
    final controller = _writers();
    final gate = Completer<void>();
    controller.declaredPools.first.enqueue<int, void>(key: 'p1', (ctx) async {
      final saved = ctx.state;
      await ctx.join(() => gate.future);
      ctx.emit(saved);
    });
    async.flushMicrotasks();
    write(controller, async);
    async.flushMicrotasks();
    gate.complete();
    async.flushMicrotasks();
  });
  return [
    for (final line in trace)
      if (line.contains('emit over')) line,
  ];
}

/// The outcome of a job its start rules turned down.
final _cancelledByRules = isA<Cancelled>()
    .having((c) => c.reason, 'reason', isA<RulesCancelReason>())
    .having((c) => c.started, 'started', isFalse);

/// The outcome of a job that a policy replaced.
final _replaced = isA<Cancelled>().having(
  (c) => c.reason,
  'reason',
  isA<ReplacedCancelReason>(),
);

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
      final lines = _debugLines((async) {
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

  group('accumulation', () {
    /// An accumulator of [pool] of [key] whose group logs its start and
    /// end with the time and runs for [length].
    SoloAccumulator<bool, void> groups(
      FakeAsync async,
      SoloPool<int> pool,
      List<String> log, {
      required AccumulationTiming timing,
      required Duration length,
      Object? key,
    }) {
      String at() => '${async.elapsed.inMilliseconds}';
      return pool.collect<int, bool, void>(key: key, timing: timing, (
        ctx,
        events,
      ) async {
        log.add('start group ${at()}');
        await ctx.join(() => Future<void>.delayed(length));
        log.add('end group ${at()}');
      });
    }

    test('groups of an accumulator without a key run side by side', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final likes = groups(
          async,
          pool,
          log,
          timing: AccumulationTiming.debounce(
            const Duration(milliseconds: 100),
          ),
          length: const Duration(milliseconds: 500),
        );
        likes.add(true);
        async.elapse(const Duration(milliseconds: 150));
        likes.add(false);
        async.elapse(const Duration(seconds: 1));

        expect(log, [
          'start group 100',
          'start group 250',
          'end group 600',
          'end group 750',
        ]);
      });
    });

    test('groups of an accumulator with a key run one at a time', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final likes = groups(
          async,
          pool,
          log,
          key: 'k',
          timing: AccumulationTiming.debounce(
            const Duration(milliseconds: 100),
          ),
          length: const Duration(milliseconds: 500),
        );
        likes.add(true);
        async.elapse(const Duration(milliseconds: 150));
        likes.add(false);
        async.elapse(const Duration(seconds: 2));

        expect(log, [
          'start group 100',
          'end group 600',
          'start group 600',
          'end group 1100',
        ]);
      });
    });

    test('a throttle wakes the pump when the pool has a free place', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        pool.enqueue<int, void>(key: 'long', _gated(log, 'long', Completer()));
        final likes = groups(
          async,
          pool,
          log,
          timing: AccumulationTiming.throttle(
            const Duration(milliseconds: 100),
            startAtOnce: false,
          ),
          length: const Duration(milliseconds: 50),
        );
        likes.add(true);
        async.elapse(const Duration(seconds: 1));

        expect(log, ['start long', 'start group 100', 'end group 150']);
      });
    });

    test('a group of a pool running past its interval does not rearm it', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final likes = groups(
          async,
          pool,
          log,
          timing: AccumulationTiming.throttle(
            const Duration(milliseconds: 100),
            startAtOnce: false,
          ),
          length: const Duration(milliseconds: 300),
        );
        likes.add(true);
        // The group starts at 100 and its interval runs out at 200, while
        // the group still runs: a new group is not counted another one.
        async.elapse(const Duration(milliseconds: 250));
        likes.add(false);
        async.elapse(const Duration(seconds: 1));

        expect(log, [
          'start group 100',
          'start group 250',
          'end group 400',
          'end group 550',
        ]);
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

  group('policies', () {
    /// Queues in [pool] a droppable job of key `a` named [name] that never
    /// ends.
    SoloJob<void> droppable(
      SoloPool<int> pool,
      String name, {
      bool Function(int state)? canStart,
    }) => pool.enqueue<int, void>(
      key: 'a',
      policy: Policy.droppable,
      describe: () => name,
      canStart: canStart,
      (ctx) => Completer<void>().future,
    );

    test('droppable hands back the running job of the key', () {
      late SoloJob<void> a1;
      late SoloJob<void> again;
      final lines = _debugLines((async) {
        final (_, pool) = _onePool(2);
        a1 = droppable(pool, 'a1');
        async.flushMicrotasks();
        again = droppable(pool, 'a2');
      });

      expect(again, same(a1));
      expect(
        lines,
        contains(
          'p: enqueue Job(a: a2): duplicate of Job(a: a1), which is running: '
          'if awaited from inside Job(a: a1), it waits for itself',
        ),
      );
    });

    test('droppable hands back the queued job of the key', () {
      late SoloJob<void> a1;
      late SoloJob<void> again;
      final lines = _debugLines((async) {
        final (controller, pool) = _onePool(1);
        pool.enqueue<int, void>(
          describe: () => 'x',
          _gated(controller.log, 'x', Completer()),
        );
        async.flushMicrotasks();
        a1 = droppable(pool, 'a1');
        again = droppable(pool, 'a2');
      });

      expect(again, same(a1));
      expect(
        lines,
        contains(
          'p: enqueue Job(a: a2): duplicate of Job(a: a1), which is queued',
        ),
      );
    });

    test('droppable in the window of the rules hands back the job there', () {
      late SoloJob<void> a1;
      SoloJob<void>? again;
      final lines = _debugLines((async) {
        final (_, pool) = _onePool(2);
        a1 = droppable(
          pool,
          'a1',
          canStart: (state) {
            again = droppable(pool, 'a2');
            return true;
          },
        );
        async.flushMicrotasks();
      });

      expect(again, same(a1));
      expect(lines, contains('p: enqueue Job(a: a2): duplicate of Job(a: a1)'));
    });

    test('droppable in a drain hands back the accepted job of the key', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(1);
        final log = controller.log;
        final x = Completer<void>();
        pool.enqueue<int, void>(describe: () => 'x', _gated(log, 'x', x));
        final a1 = _keyed(pool, log, 'a', 'a1', Completer()..complete());
        async.flushMicrotasks();
        unawaited(controller.close(mode: SoloCloseMode.drain));
        final again = pool.enqueue<int, void>(
          key: 'a',
          policy: Policy.droppable,
          _gated(log, 'a2', Completer()),
        );
        x.complete();
        async.flushMicrotasks();

        expect(again, same(a1));
        expect(log, ['start x', 'end x', 'start a1', 'end a1']);
      });
    });

    test(
      'keepLatest drops the queued jobs of the key, not the running one',
      () {
        fakeAsync((async) {
          final (controller, pool) = _onePool(2);
          final log = controller.log;
          final gate = Completer<void>();
          SoloJob<void> latest(String name, Completer<void> gate) =>
              pool.enqueue<int, void>(
                key: 'a',
                policy: Policy.keepLatest,
                describe: () => name,
                _gated(log, name, gate),
              );
          final a1 = latest('a1', gate);
          async.flushMicrotasks();
          final a2 = latest('a2', Completer());
          final a3 = latest('a3', Completer());
          async.flushMicrotasks();

          expect(a2.outcome, _replaced);
          expect(a1.isCancelled, isFalse);
          expect(pool.running, [same(a1)]);
          expect(pool.queue.jobs, [same(a3)]);
          gate.complete();
          async.flushMicrotasks();
          expect(log, ['start a1', 'end a1', 'start a3']);
        });
      },
    );

    test('restart cancels the running job of the key and starts after its '
        'end', () {
      late SoloJob<void> a1;
      final log = <String>[];
      final lines = _debugLines((async) {
        final (_, pool) = _onePool(2);
        a1 = pool.enqueue<int, void>(
          key: 'a',
          policy: Policy.restart,
          describe: () => 'a1',
          ifCancelled: (state, cancelled) {
            log.add('a1 ifCancelled');
            return 7;
          },
          (ctx) async {
            log.add('start a1');
            await Future<void>.delayed(const Duration(milliseconds: 100));
            ctx.emit(1);
          },
        );
        async.flushMicrotasks();
        pool.enqueue<int, void>(
          key: 'a',
          policy: Policy.restart,
          describe: () => 'a2',
          (ctx) async => log.add('start a2 with ${ctx.state}'),
        );
        async.elapse(const Duration(seconds: 1));
      });

      expect(a1.outcome, _replaced);
      expect(log, ['start a1', 'a1 ifCancelled', 'start a2 with 7']);
      // a2 read 7 at its start: the cleanup of a1 wrote it before.
      expect(
        lines,
        containsAllInOrder(['p: restart: cancel Job(a: a1)', 'state: 7']),
      );
    });

    test('restart from the window of the rules leaves the job there to the '
        'queue', () {
      final log = <String>[];
      final lines = _debugLines((async) {
        final (_, pool) = _onePool(2);
        // Not cancellable, a1 turns down the cancellation of the queue and
        // starts; it is not running yet, and restart does not ask it again.
        pool.enqueue<int, void>(
          key: 'a',
          policy: Policy.restart,
          cancellable: false,
          describe: () => 'a1',
          canStart: (state) {
            pool.enqueue<int, void>(
              key: 'a',
              policy: Policy.restart,
              describe: () => 'a2',
              (ctx) async => log.add('start a2'),
            );
            return true;
          },
          (ctx) async => log.add('start a1'),
        );
        async.flushMicrotasks();
      });

      expect(log, ['start a1', 'start a2']);
      expect(lines.where((line) => line.contains('restart:')), isEmpty);
    });

    test('restart leaves the running jobs of other keys alone', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final b = _keyed(pool, log, 'b', 'b', Completer());
        final a1 = pool.enqueue<int, void>(
          key: 'a',
          policy: Policy.restart,
          _gated(log, 'a1', Completer()),
        );
        async.flushMicrotasks();
        pool.enqueue<int, void>(
          key: 'a',
          policy: Policy.restart,
          _gated(log, 'a2', Completer()),
        );

        expect(a1.isCancelled, isTrue);
        expect(b.isCancelled, isFalse);
      });
    });
  });

  group('rules', () {
    test('canStart and W are asked at the start, after an overtaking', () {
      fakeAsync((async) {
        final pool = _Any().p;
        final log = <String>[];
        final gate = Completer<void>();
        pool.enqueue<Object, void>(key: 'a', (ctx) async {
          log.add('start a1');
          await gate.future;
        });
        async.flushMicrotasks();
        // The state is not an int yet, and rules asked now would drop a2.
        final a2 = pool.enqueue<int, void>(
          key: 'a',
          canStart: (state) => state > 0,
          (ctx) async => log.add('start a2 with ${ctx.state}'),
        );
        pool.enqueue<Object, void>((ctx) async {
          log.add('start b');
          ctx.emit(1);
        });
        async.flushMicrotasks();
        expect(log, ['start a1', 'start b']);
        gate.complete();
        async.flushMicrotasks();

        expect(a2.outcome, isA<Done<void>>());
        expect(log, ['start a1', 'start b', 'start a2 with 1']);
      });
    });

    test('a write of another job of the pool over a stale read says so', () {
      expect(
        _overWrites(
          (controller, async) => controller.declaredPools.first
              .enqueue<int, void>(key: 'p2', (ctx) async => ctx.emit(1)),
        ),
        [
          'Job(p1) emit over a write of another job of pool likes made after '
              'Job(p1) last read the state: read ctx.state after the wait, or '
              'this write undoes the work of that job',
        ],
      );
    });

    test('a write of a child of the same root says nothing', () {
      final trace = _debugLines((async) {
        final controller = _writers();
        controller.declaredPools.first.enqueue<int, void>(key: 'p1', (
          ctx,
        ) async {
          final saved = ctx.state;
          await ctx.run(
            ctx.child<void>(key: 'child', (ctx) async => ctx.emit(7)),
          );
          ctx.emit(saved);
        });
        async.flushMicrotasks();
      });

      expect(trace, contains('state: 7'));
      expect(trace.where((line) => line.contains('emit over')), isEmpty);
    });

    test('a write of a child after another job of the pool wrote still '
        'says so', () {
      final trace = _debugLines((async) {
        final likes = _writers().declaredPools.first;
        final gate = Completer<void>();
        likes.enqueue<int, void>(key: 'p1', (ctx) async {
          final saved = ctx.state;
          await ctx.join(() => gate.future);
          // The child writes blind: it never read, and its write leaves
          // the read of its root where it was.
          await ctx.run(
            ctx.child<void>(key: 'child', (ctx) async => ctx.emit(7)),
          );
          ctx.emit(saved);
        });
        async.flushMicrotasks();
        likes.enqueue<int, void>(key: 'p2', (ctx) async => ctx.emit(1));
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();
      });

      expect(trace.where((line) => line.contains('emit over')), [
        startsWith('Job(p1) emit over a write of another job of pool likes'),
      ]);
    });

    test('a write of another lane over a pool job reads as today', () {
      expect(
        _overWrites(
          (controller, async) => controller.declaredLanes.single
              .enqueue<int, void>(key: 'l1', (ctx) async => ctx.emit(1)),
        ),
        [
          'Job(p1) emit over a write of lane l made after Job(p1) last read '
              'the state: read ctx.state after the wait, or this write undoes '
              'the work of l',
        ],
      );
    });

    test('a write of another pool says pool', () {
      expect(
        _overWrites(
          (controller, async) => controller.declaredPools.last
              .enqueue<int, void>(key: 'u1', (ctx) async => ctx.emit(1)),
        ),
        [
          'Job(p1) emit over a write of pool uploads made after Job(p1) last '
              'read the state: read ctx.state after the wait, or this write '
              'undoes the work of uploads',
        ],
      );
    });

    test('the line names the latest write, of the own pool or not', () {
      /// A write of another job of `likes` and one of `l`, in this order
      /// or the other.
      List<String> twoWrites({required bool poolFirst}) =>
          _overWrites((controller, async) {
            void pool() => controller.declaredPools.first.enqueue<int, void>(
              key: 'p2',
              (ctx) async => ctx.emit(1),
            );
            void lane() => controller.declaredLanes.single.enqueue<int, void>(
              key: 'l1',
              (ctx) async => ctx.emit(2),
            );
            (poolFirst ? pool : lane)();
            async.flushMicrotasks();
            (poolFirst ? lane : pool)();
          });

      expect(twoWrites(poolFirst: true), [
        contains('a write of lane l made after'),
      ]);
      expect(twoWrites(poolFirst: false), [
        contains('a write of another job of pool likes made after'),
      ]);
    });

    test('a write of the own root after another job of the pool wrote says '
        'nothing more', () {
      final trace = _debugLines((async) {
        final likes = _writers().declaredPools.first;
        final gate = Completer<void>();
        final second = Completer<void>();
        likes.enqueue<int, void>(key: 'p1', (ctx) async {
          final saved = ctx.state;
          await ctx.join(() => gate.future);
          ctx.emit(saved);
          await ctx.join(() => second.future);
          ctx.emit(ctx.state + 1);
        });
        async.flushMicrotasks();
        likes.enqueue<int, void>(key: 'p2', (ctx) async => ctx.emit(1));
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();
        second.complete();
        async.flushMicrotasks();
      });

      expect(trace.where((line) => line.contains('emit over')), hasLength(1));
    });
  });

  group('closing', () {
    test('drain ends once the queue is empty and every place is over', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final gates = [for (var i = 0; i < 3; i++) Completer<void>()];
        final jobs = [
          for (final (i, name) in ['a', 'b', 'c'].indexed)
            pool.enqueue<int, void>(_gated(log, name, gates[i])),
        ];
        async.flushMicrotasks();
        var closed = false;
        controller.close(mode: SoloCloseMode.drain).then((_) => closed = true);

        gates[0].complete();
        async.flushMicrotasks();
        expect(log, ['start a', 'start b', 'end a', 'start c']);
        expect(closed, isFalse);

        // The queue is empty and a place is free, and b still runs.
        gates[2].complete();
        async.flushMicrotasks();
        expect(pool.running, [same(jobs[1])]);
        expect(closed, isFalse);

        gates[1].complete();
        async.flushMicrotasks();
        expect(closed, isTrue);
        expect([
          for (final job in jobs) job.outcome,
        ], everyElement(isA<Done<void>>()));
      });
    });

    test('drain of a pool with a canceled queued upload ends', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final gates = [Completer<void>(), Completer<void>()];
        final up1 = _keyed(pool, log, 'up1', 'up1', gates[0]);
        final up2 = _keyed(pool, log, 'up2', 'up2', gates[1]);
        final up3 = _keyed(pool, log, 'up3', 'up3', Completer());
        async.flushMicrotasks();
        var closed = false;
        controller.close(mode: SoloCloseMode.drain).then((_) => closed = true);

        unawaited(up3.cancel());
        async.flushMicrotasks();
        expect(
          up3.outcome,
          isA<Cancelled>()
              .having((c) => c.reason, 'reason', isA<ManualCancelReason>())
              .having((c) => c.started, 'started', isFalse),
        );
        expect(closed, isFalse);

        gates[0].complete();
        gates[1].complete();
        async.flushMicrotasks();
        expect(up1.outcome, isA<Done<void>>());
        expect(up2.outcome, isA<Done<void>>());
        expect(log, ['start up1', 'start up2', 'end up1', 'end up2']);
        expect(closed, isTrue);
      });
    });

    test('close with a cancel drops the queue before any running job '
        'hears', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final gate = Completer<void>();
        final a = pool.enqueue<int, void>(_gated(log, 'a', gate));
        final b = pool.enqueue<int, void>(_gated(log, 'b', gate));
        final c = pool.enqueue<int, void>(_gated(log, 'c', gate));
        async.flushMicrotasks();
        final heard = <String>[];
        for (final (name, job) in [('a', a), ('b', b)]) {
          job.whenCancelled(
            (_) => heard.add('$name hears, c is finished: ${c.isFinished}'),
          );
        }

        unawaited(controller.close());
        expect(heard, [
          'a hears, c is finished: true',
          'b hears, c is finished: true',
        ]);
        expect(
          c.outcome,
          isA<Cancelled>()
              .having((c) => c.reason, 'reason', isA<ClosedCancelReason>())
              .having((c) => c.started, 'started', isFalse),
        );

        gate.complete();
        async.flushMicrotasks();
        expect(controller.isFinished, isTrue);
      });
    });
  });

  group('pending', () {
    test('pending gives an entry for every running job', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final a1 = _keyed(pool, log, 'a', 'a1', Completer());
        final b = _keyed(pool, log, 'b', 'b', Completer());
        final a2 = _keyed(pool, log, 'a', 'a2', Completer());
        async.flushMicrotasks();

        final pending = controller.pending;
        expect(pending, isA<SoloPendingLanes>());
        final lanes = (pending! as SoloPendingLanes).lanes;
        expect([for (final entry in lanes) entry.lane], [pool.id, pool.id]);
        expect(
          lanes[0].pending,
          isA<SoloPendingJob>().having((p) => p.job, 'job', same(a1)).having(
            (p) => p.queued,
            'queued',
            [same(a2)],
          ),
        );
        expect(
          lanes[1].pending,
          isA<SoloPendingJob>()
              .having((p) => p.job, 'job', same(b))
              .having((p) => p.queued, 'queued', isEmpty),
        );
        expect(
          () => (lanes[0].pending as SoloPendingJob).queued.add(b),
          throwsUnsupportedError,
        );
        expect(
          '$pending',
          'SoloPending(p: SoloPending([a: a1] in its body, 1 queued: [a: a2]), '
              'p: SoloPending([b: b] in its body))',
        );
        expect('${pool.pending}', '$pending');
      });
    });

    test('pending shows the jobs that wait for a place', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(1);
        final log = controller.log;
        final x = pool.enqueue<int, void>(
          describe: () => 'x',
          _gated(log, 'x', Completer()),
        );
        final c = pool.enqueue<int, void>(
          describe: () => 'c',
          _gated(log, 'c', Completer()),
        );
        async.flushMicrotasks();

        final [job, places] = (controller.pending! as SoloPendingLanes).lanes;
        expect(
          job.pending,
          isA<SoloPendingJob>()
              .having((p) => p.job, 'job', same(x))
              .having((p) => p.queued, 'queued', isEmpty),
        );
        expect(places.lane, pool.id);
        expect(
          places.pending,
          isA<SoloPendingQueue>().having((p) => p.jobs, 'jobs', [same(c)]),
        );
        expect(
          '${places.pending}',
          'SoloPending(waiting for a place, 1 queued: [no key: c])',
        );
      });
    });

    test('pending in a drain shows what has not started', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        final gates = [Completer<void>(), Completer<void>()];
        final a1 = _keyed(pool, log, 'a', 'a1', gates[0]);
        final b = _keyed(pool, log, 'b', 'b', gates[1]);
        final a2 = _keyed(pool, log, 'a', 'a2', Completer());
        final c = pool.enqueue<int, void>(
          describe: () => 'c',
          _gated(log, 'c', Completer()),
        );
        async.flushMicrotasks();
        unawaited(controller.close(mode: SoloCloseMode.drain));

        final lanes = (pool.pending! as SoloPendingLanes).lanes;
        expect(lanes, hasLength(3));
        expect(
          lanes[0].pending,
          isA<SoloPendingJob>()
              .having((p) => p.job, 'job', same(a1))
              .having((p) => p.draining, 'draining', isTrue)
              .having((p) => p.queued, 'queued', [same(a2)]),
        );
        expect(
          lanes[1].pending,
          isA<SoloPendingJob>()
              .having((p) => p.job, 'job', same(b))
              .having((p) => p.draining, 'draining', isTrue)
              .having((p) => p.queued, 'queued', isEmpty),
        );
        // In a drain the rest of the queue is what the drain has still to
        // run, and says so, as in a lane.
        expect(
          lanes[2].pending,
          isA<SoloPendingQueue>().having((p) => p.jobs, 'jobs', [same(c)]),
        );
        expect(
          '${lanes[2].pending}',
          'SoloPending(draining, 1 queued: [no key: c])',
        );

        // b ends and c takes its place: nothing waits for a place now.
        gates[1].complete();
        async.flushMicrotasks();
        expect(
          [
            for (final entry in (pool.pending! as SoloPendingLanes).lanes)
              (entry.pending as SoloPendingJob).job,
          ],
          [same(a1), same(c)],
        );
      });
    });

    test('pending in a drain names the job its rules are asked for', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(1);
        final log = controller.log;
        final gate = Completer<void>();
        pool.enqueue<int, void>(describe: () => 'x', _gated(log, 'x', gate));
        String? seen;
        pool.enqueue<int, void>(
          describe: () => 'w',
          _gated(log, 'w', Completer()),
          canStart: (state) {
            seen = '${pool.pending}';
            return true;
          },
        );
        async.flushMicrotasks();
        unawaited(controller.close(mode: SoloCloseMode.drain));
        gate.complete();
        async.flushMicrotasks();

        expect(
          seen,
          'SoloPending(p: SoloPending(draining, 1 queued: [no key: w]))',
        );
      });
    });

    test('pool.pending is a list for one running job as for two', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        final log = controller.log;
        expect(pool.pending, isNull);

        final a = _keyed(pool, log, 'a', 'a', Completer());
        async.flushMicrotasks();
        final one = pool.pending;
        expect(one, isA<SoloPendingLanes>());
        expect((one! as SoloPendingLanes).lanes, hasLength(1));

        _keyed(pool, log, 'b', 'b', Completer());
        async.flushMicrotasks();
        final two = pool.pending! as SoloPendingLanes;
        expect(two.lanes, hasLength(2));
        expect(() => two.lanes.add(two.lanes.first), throwsUnsupportedError);
        expect((one as SoloPendingLanes).lanes, hasLength(1));
        expect((two.lanes.first.pending as SoloPendingJob).job, same(a));
      });
    });

    test('the entries of a pool stand where the pool was declared', () {
      fakeAsync((async) {
        final controller = _Pools(
          (self) => self
            ..declareLane('l1')
            ..declarePool('p', 2)
            ..declareLane('l2'),
        );
        final [l1, l2] = controller.declaredLanes;
        final p = controller.declaredPools.single;
        final log = controller.log;
        for (final owner in <SoloQueueOwner<int>>[l2, p, p, l1]) {
          owner.enqueue<int, void>(_gated(log, 'job', Completer()));
        }
        async.flushMicrotasks();

        expect(
          [
            for (final entry in (controller.pending! as SoloPendingLanes).lanes)
              entry.lane.name,
          ],
          ['l1', 'p', 'p', 'l2'],
        );
      });
    });
  });

  group('awaiting the own pool', () {
    test('a job awaiting a job of its own key in its pool waits for good', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        late final SoloJob<void> inner;
        final outer = pool.enqueue<int, void>(key: 'a', (ctx) async {
          inner = pool.enqueue<int, void>(key: 'a', (ctx) async {});
          await inner.done;
        });
        async.elapse(const Duration(hours: 1));

        expect(outer.isRunning, isTrue);
        expect(inner.isQueued, isTrue);
        expect(pool.running, [same(outer)]);

        unawaited(controller.close());
        async.flushMicrotasks();
        expect(controller.isFinished, isTrue);
      });
    });

    test('a job awaiting another key of its pool with a free place ends', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        Outcome<void>? inner;
        final outer = pool.enqueue<int, void>(key: 'a', (ctx) async {
          inner = await pool.enqueue<int, void>(key: 'b', (ctx) async {}).done;
        });
        async.flushMicrotasks();

        expect(inner, isA<Done<void>>());
        expect(outer.outcome, isA<Done<void>>());
      });
    });

    test('every place awaiting its pool waits for good, and pending says '
        'it', () {
      fakeAsync((async) {
        final (controller, pool) = _onePool(2);
        for (final (key, inner) in [('a', 'c'), ('b', 'd')]) {
          pool.enqueue<int, void>(key: key, (ctx) async {
            await pool.enqueue<int, void>(key: inner, (ctx) async {}).done;
          });
        }
        async.elapse(const Duration(hours: 1));

        expect(pool.running.map((job) => job.key), ['a', 'b']);
        expect(pool.queue.jobs.map((job) => job.key), ['c', 'd']);
        expect(
          '${pool.pending}',
          'SoloPending(p: SoloPending([a] in its body), '
              'p: SoloPending([b] in its body), '
              'p: SoloPending(waiting for a place, 2 queued: [c], [d]))',
        );

        unawaited(controller.close());
        async.flushMicrotasks();
        expect(controller.isFinished, isTrue);
      });
    });
  });
}
