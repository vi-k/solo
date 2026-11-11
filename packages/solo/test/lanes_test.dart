// `SoloLanes`: lanes declared in the constructor, one job at a time in each,
// one pump that walks them in the order of creation, the job's lane, and the
// lines `Solo.debug` prints for them.
// ignore_for_file: no_adjacent_strings_in_list
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/foreign_job.dart';

typedef _AB = ({int a, int b});

/// Two lanes, `first` and `second`, in that order, and a log of the hooks.
final class _Two extends SoloLanes<_AB> {
  final log = <String>[];
  late final SoloLane<_AB> first;
  late final SoloLane<_AB> second;

  _Two() : super((a: 0, b: 0)) {
    first = lane('first');
    second = lane('second');
  }

  List<SoloLane<_AB>> get declared => lanes;

  SoloLane<_AB> declare(String name) => lane(name);

  void outside(_AB state) => externalSetState(state);

  @override
  void onStart(Job<Object?> job) => log.add('start $job');

  @override
  void onFinish(Job<Object?> job) =>
      log.add('finish $job in ${(job as SoloJob<Object?>).lane}');
}

/// Lanes declared by whoever makes it, in its constructor body.
final class _Lanes extends SoloLanes<int> {
  _Lanes([void Function(_Lanes self)? declare]) : super(0) {
    declare?.call(this);
  }

  List<SoloLane<int>> get declared => lanes;

  SoloLane<int> declare(String name) => lane(name);
}

/// A lane in a `late final` field: made on the first read.
final class _LateLane extends SoloLanes<int> {
  late final SoloLane<int> _x = lane('x');
  SoloLane<int>? readInConstructor;

  _LateLane({bool read = false}) : super(0) {
    if (read) readInConstructor = _x;
  }

  List<SoloLane<int>> get declared => lanes;

  /// The field read on a later microtask, as a method of the controller
  /// would read it.
  Future<SoloLane<int>> later() async {
    await Future.microtask(() {});
    return _x;
  }
}

/// A lane declared, a job queued in it, and then another lane: all in the
/// constructor body.
final class _LateDeclaration extends SoloLanes<int> {
  late final SoloLane<int> a;
  late final SoloJob<void> job;
  Object? refusal;

  _LateDeclaration() : super(0) {
    a = lane('a');
    job = a.enqueue<int, void>(key: 'a', (ctx) async => ctx.emit(1));
    try {
      lane('b');
    } on Object catch (error) {
      refusal = error;
    }
  }

  List<SoloLane<int>> get declared => lanes;
}

/// A controller with one queue, for the lines and lanes of a `Solo`.
final class _One extends Solo<int> {
  _One() : super(0);

  SoloJob<void> run(String key) => enqueue<int, void>(key: key, (ctx) async {});

  SoloJob<void> make(String key) => job<int, void>(key: key, (ctx) async {});
}

final class _Streamed extends SoloLanes<int> with SoloStream<int> {
  late final SoloLane<int> a;
  late final SoloLane<int> b;

  _Streamed() : super(0) {
    a = lane('a');
    b = lane('b');
  }
}

/// Logs the closing of every controller.
final class _Closing extends SoloObserver {
  final List<String> log;

  _Closing(this.log);

  @override
  void onClose(SoloController<Object> solo) => log.add('onClose');
}

/// Throws in `onStart` of the job with [key].
final class _ThrowsOnStart extends SoloObserver {
  final Object key;

  _ThrowsOnStart(this.key);

  @override
  void onStart(SoloController<Object> solo, Job<Object?> job) {
    if (job.key == key) throw StateError('observer');
  }
}

/// Logs `tick 0` to `tick n-1`, each on a microtask of its own.
void _ladder(List<String> log, int n, [int i = 0]) {
  if (i == n) return;
  scheduleMicrotask(() {
    log.add('tick $i');
    _ladder(log, n, i + 1);
  });
}

/// A [StateError] of `lane` that says [cause] and sends to the lanes page.
Matcher _refusedLane(String cause) => throwsA(_refusalOf(cause));

/// The matcher of the [StateError] itself, for a refusal that was stored.
Matcher _refusalOf(String cause) => isA<StateError>().having(
  (e) => e.message,
  'message',
  allOf(contains(cause), contains('lanes.md#declaring-lanes')),
);

/// A job that waits until [gate] completes.
Future<void> Function(SoloContext<_AB, _AB> ctx) _waits(Completer<void> gate) =>
    (ctx) => gate.future;

Future<void> _nothing(SoloContext<_AB, _AB> ctx) async {}

void main() {
  tearDown(() {
    Solo.observer = null;
    Solo.debug = null;
  });

  group('lane', () {
    test('a lane per name, in the order of creation', () {
      final controller = _Two();
      final lanes = controller.declared;

      expect(lanes, [same(controller.first), same(controller.second)]);
      expect([for (final lane in lanes) lane.name], ['first', 'second']);
      expect(controller.first.id.name, 'first');
      expect('${controller.first.id}', 'first');
      expect(() => lanes.add(controller.first), throwsUnsupportedError);
    });

    test('a second lane of one name throws', () {
      expect(
        () => _Lanes((self) {
          self
            ..declare('x')
            ..declare('x');
        }),
        _refusedLane('has a lane named x already'),
      );
    });

    test("lane after the constructor's microtask throws", () {
      fakeAsync((async) {
        final controller = _Lanes((self) => self.declare('a'))
          // The same synchronous part as the constructor: still open.
          ..declare('b');
        async.flushMicrotasks();

        expect(
          () => controller.declare('c'),
          _refusedLane('after its constructor'),
        );
        expect([for (final lane in controller.declared) lane.name], ['a', 'b']);
      });
    });

    group('lane after the first enqueueJob throws', () {
      const cause = 'after enqueueJob of one of its lanes was called';

      test('when the job is queued', () {
        final controller = _Lanes((self) => self.declare('a'));
        final job = controller.declared.single.enqueue<int, void>(
          (ctx) async {},
        );

        expect(job.isQueued, isTrue);
        expect(() => controller.declare('b'), _refusedLane(cause));
      });

      // A call that throws leaves nothing behind but the seal, so these
      // two tell the call apart from what it did. A repeated enqueue of one
      // job is not among them: a job is taken only by an enqueue, or by the
      // adoption of a body that runs, which an enqueue came before.
      test('when the call refuses a job of another lane', () {
        final controller = _Lanes((self) {
          self
            ..declare('a')
            ..declare('b');
        });
        final [a, b] = controller.declared;

        expect(
          () => b.enqueueJob(a.job<int, void>((ctx) async {})),
          throwsArgumentError,
        );
        expect(() => controller.declare('c'), _refusedLane(cause));
      });

      test('when the call refuses Policy.droppable without a key', () {
        final controller = _Lanes((self) => self.declare('a'));
        final a = controller.declared.single;

        expect(
          () => a.enqueue<int, void>(policy: Policy.droppable, (ctx) async {}),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'Policy.droppable requires a job key',
            ),
          ),
        );
        expect(() => controller.declare('b'), _refusedLane(cause));
      });

      // The next two hold the outcome, not the cause of the seal: close
      // seals by itself, and the duplicate's first enqueue sealed already.
      test('when the job ends Cancelled(closed)', () {
        final controller = _Lanes((self) => self.declare('a'));
        unawaited(controller.close());
        final job = controller.declared.single.enqueue<int, void>(
          (ctx) async {},
        );

        expect(
          job.outcome,
          isA<Cancelled>().having(
            (c) => c.reason,
            'reason',
            isA<ClosedCancelReason>(),
          ),
        );
        expect(() => controller.declare('b'), throwsStateError);
      });

      test('when the job is dropped as a duplicate', () {
        final controller = _Lanes((self) => self.declare('a'));
        final lane = controller.declared.single;
        final kept = lane.enqueue<int, void>(
          key: 'k',
          policy: Policy.droppable,
          (ctx) async {},
        );
        final dropped = lane.job<int, void>(key: 'k', (ctx) async {});
        final handed = lane.enqueueJob(dropped, policy: Policy.droppable);

        expect(handed, same(kept));
        expect(
          dropped.outcome,
          isA<Cancelled>().having(
            (c) => c.reason,
            'reason',
            isA<DuplicateCancelReason>(),
          ),
        );
        expect(() => controller.declare('b'), throwsStateError);
      });
    });

    test('lane after close throws', () {
      final controller = _Lanes((self) => self.declare('a'));
      unawaited(controller.close());

      expect(() => controller.declare('b'), _refusedLane('after close'));
    });

    test('a late final lane read after the constructor throws', () async {
      final controller = _LateLane();

      await expectLater(
        controller.later(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('after its constructor'),
          ),
        ),
      );
      expect(controller.declared, isEmpty);
    });

    test('a lane read in the constructor before any job is made', () async {
      final controller = _LateLane(read: true);

      expect(controller.declared, [same(controller.readInConstructor)]);
      expect(await controller.later(), same(controller.readInConstructor));
    });

    test('the same name in two controllers is two lanes', () {
      final one = _Lanes((self) => self.declare('x'));
      final two = _Lanes((self) => self.declare('x'));
      final a = one.declared.single;
      final b = two.declared.single;

      expect(a, isNot(same(b)));
      expect(a.id, isNot(same(b.id)));
      expect(a.id, isNot(b.id));
      expect(a.name, b.name);
    });

    test(
      'lane after enqueue in the same constructor body throws and the job runs',
      () {
        fakeAsync((async) {
          final controller = _LateDeclaration();
          async.flushMicrotasks();

          expect(
            controller.refusal,
            _refusalOf('after enqueueJob of one of its lanes was called'),
          );
          expect(controller.declared, [same(controller.a)]);
          expect(controller.job.lane, same(controller.a.id));
          expect(controller.job.outcome, isA<Done<void>>());
          expect(controller.currentState, 1);
        });
      },
    );
  });

  group('one job at a time in each lane', () {
    test('two jobs of one lane run one at a time', () {
      fakeAsync((async) {
        final controller = _Two();
        final gate = Completer<void>();
        controller.first.enqueue<_AB, void>(key: 'a', _waits(gate));
        final b = controller.first.enqueue<_AB, void>(key: 'b', _nothing);
        async.flushMicrotasks();

        expect(controller.log, ['start Job(a)']);
        expect(b.isQueued, isTrue);

        gate.complete();
        async.flushMicrotasks();
        expect(controller.log, [
          'start Job(a)',
          'finish Job(a) in first',
          'start Job(b)',
          'finish Job(b) in first',
        ]);
      });
    });

    test('jobs of two lanes start in one pass', () {
      fakeAsync((async) {
        final controller = _Two();
        final gate = Completer<void>();
        controller.first.enqueue<_AB, void>(key: 'a', _waits(gate));
        controller.second.enqueue<_AB, void>(key: 'b', _waits(gate));
        scheduleMicrotask(() => controller.log.add('tick'));
        async.flushMicrotasks();

        expect(controller.log, ['start Job(a)', 'start Job(b)', 'tick']);
      });
    });

    test('first: true puts a job at the head of its own lane', () {
      fakeAsync((async) {
        final controller = _Two();
        final gate = Completer<void>();
        controller.first.enqueue<_AB, void>(key: 'busy', _waits(gate));
        controller.second.enqueue<_AB, void>(key: 'busy', _waits(gate));
        async.flushMicrotasks();
        final x = controller.first.enqueue<_AB, void>(key: 'x', _nothing);
        final y = controller.second.enqueue<_AB, void>(key: 'y', _nothing);
        final head = controller.first.enqueueJob(
          controller.first.job<_AB, void>(key: 'head', _nothing),
          first: true,
        );

        expect(controller.first.queue.jobs, [same(head), same(x)]);
        expect(controller.second.queue.jobs, [same(y)]);
      });
    });

    test('droppable looks for the key in its own lane only', () {
      fakeAsync((async) {
        final controller = _Two();
        final gate = Completer<void>();
        final other = controller.second.enqueue<_AB, void>(
          key: 'k',
          policy: Policy.droppable,
          _waits(gate),
        );
        async.flushMicrotasks();
        final own = controller.first.enqueue<_AB, void>(
          key: 'k',
          policy: Policy.droppable,
          _waits(gate),
        );

        expect(own, isNot(same(other)));
        expect(own.isQueued, isTrue);
        expect(
          controller.first.enqueue<_AB, void>(
            key: 'k',
            policy: Policy.droppable,
            _waits(gate),
          ),
          same(own),
        );
      });
    });

    test('keepLatest looks for the key in its own lane only', () {
      fakeAsync((async) {
        final controller = _Two();
        final gate = Completer<void>();
        controller.first.enqueue<_AB, void>(key: 'busy', _waits(gate));
        controller.second.enqueue<_AB, void>(key: 'busy', _waits(gate));
        async.flushMicrotasks();
        final other = controller.second.enqueue<_AB, void>(key: 'k', _nothing);
        final own = controller.first.enqueue<_AB, void>(key: 'k', _nothing);
        final latest = controller.first.enqueue<_AB, void>(
          key: 'k',
          policy: Policy.keepLatest,
          _nothing,
        );

        expect(other.isQueued, isTrue);
        expect(
          own.outcome,
          isA<Cancelled>().having(
            (c) => c.reason,
            'reason',
            isA<ReplacedCancelReason>(),
          ),
        );
        expect(controller.first.queue.jobs, [same(latest)]);
      });
    });

    test('restart of first does not touch the current job of second', () {
      fakeAsync((async) {
        final controller = _Two();
        final gate = Completer<void>();
        final other = controller.second.enqueue<_AB, void>(
          key: 'k',
          _waits(gate),
        );
        final own = controller.first.enqueue<_AB, void>(key: 'k', _waits(gate));
        async.flushMicrotasks();
        controller.first.enqueue<_AB, void>(
          key: 'k',
          policy: Policy.restart,
          _nothing,
        );

        expect(other.isCancelled, isFalse);
        expect(own.isCancelled, isTrue);
      });
    });
  });

  group('the order of a pass', () {
    test('a job the synchronous part of first puts into second starts in '
        'the same pass', () {
      fakeAsync((async) {
        final controller = _Two();
        final gate = Completer<void>();
        controller.first.enqueue<_AB, void>(key: 'a', (ctx) {
          controller.second.enqueue<_AB, void>(key: 'b', _waits(gate));
          return gate.future;
        });
        scheduleMicrotask(() => controller.log.add('tick'));
        async.flushMicrotasks();

        expect(controller.log, ['start Job(a)', 'start Job(b)', 'tick']);
      });
    });

    test('a job the synchronous part of second puts into first starts in '
        'the next pass', () {
      fakeAsync((async) {
        final controller = _Two();
        final gate = Completer<void>();
        controller.second.enqueue<_AB, void>(key: 'b', (ctx) {
          controller.first.enqueue<_AB, void>(key: 'a', _waits(gate));
          return gate.future;
        });
        scheduleMicrotask(() => controller.log.add('tick'));
        async.flushMicrotasks();

        expect(controller.log, ['start Job(b)', 'tick', 'start Job(a)']);
      });
    });

    test('canStart of second sees what the start of first wrote', () {
      fakeAsync((async) {
        final controller = _Two();
        final gate = Completer<void>();
        controller.first.enqueue<_AB, void>(key: 'a', (ctx) {
          ctx.emit((a: 1, b: ctx.state.b));
          return gate.future;
        });
        final b = controller.second.enqueue<_AB, void>(
          key: 'b',
          canStart: (state) => state.a == 1,
          _nothing,
        );
        scheduleMicrotask(() => controller.log.add('tick'));
        async.flushMicrotasks();

        expect(controller.log.take(3), [
          'start Job(a)',
          'start Job(b)',
          'tick',
        ]);
        expect(b.outcome, isA<Done<void>>());
      });
    });
  });

  group('refusals', () {
    test('a job of first given to second.enqueueJob', () {
      final controller = _Two();
      final job = controller.first.job<_AB, void>(key: 'a', _nothing);

      expect(
        () => controller.second.enqueueJob(job),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('was not created by this lane'),
          ),
        ),
      );
      expect(job.lane, isNull);
      expect(controller.second.queue.isEmpty, isTrue);
      expect(controller.first.queue.isEmpty, isTrue);
      // Refused before it was taken: its own lane takes it still.
      expect(controller.first.enqueueJob(job).lane, same(controller.first.id));
    });

    test('a job of another controller', () {
      final controller = _Two();
      final job = _Two().first.job<_AB, void>(key: 'a', _nothing);

      expect(
        () => controller.first.enqueueJob(job),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('was not created by this lane'),
          ),
        ),
      );
      expect(job.lane, isNull);
      expect(controller.first.queue.isEmpty, isTrue);
    });

    test('a child already adopted', () {
      fakeAsync((async) {
        final controller = _Two();
        late SoloJob<void> child;
        final refusals = <Object>[];
        controller.first.enqueue<_AB, void>(key: 'parent', (ctx) async {
          child = ctx.child<void>(key: 'child', (ctx) async {});
          await ctx.run(child);
          for (final lane in [controller.first, controller.second]) {
            try {
              lane.enqueueJob(child);
            } on Object catch (error) {
              refusals.add(error);
            }
          }
        });
        async.flushMicrotasks();

        expect(refusals, [
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('has already been enqueued or run'),
          ),
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('was not created by this lane'),
          ),
        ]);
        expect(child.lane, same(controller.first.id));
        expect(controller.second.queue.isEmpty, isTrue);
      });
    });
  });

  test('a job of a lane run as a child by a job of the core', () {
    fakeAsync((async) {
      final controller = _Two();
      final child = controller.first.job<_AB, void>(key: 'child', _nothing);
      Object? thrown;
      ForeignJob<void>((ctx) async {
        try {
          ctx.run(child).ignore();
        } on Object catch (error) {
          thrown = error;
        }
      }).launch();
      async.flushMicrotasks();

      // The child runs in a body of any lane of its controller: the text
      // names the controller, and a Solo's says Solo, as before.
      expect(
        (thrown! as ArgumentError).message,
        'runs as a child only in a body of the controller that made it',
      );
      expect(child.outcome, isNull);
      expect(child.lane, isNull);
    });
  });

  test(
    'a job of another controller started as a child names the controller',
    () {
      fakeAsync((async) {
        final controller = _Two();
        final theirs = _Two().first.job<_AB, void>(key: 'theirs', _nothing);
        Object? thrown;
        controller.first.enqueue<_AB, void>(key: 'parent', (ctx) async {
          try {
            ctx.start(theirs);
          } on Object catch (error) {
            thrown = error;
          }
        });
        async.flushMicrotasks();

        expect(
          '$thrown',
          'Invalid argument (job): was not created by this controller (make it '
              'with job(...) or ctx.child of this controller): "Job(theirs)"',
        );
      });
    },
  );

  group('SoloJob.lane', () {
    test('a root job has the lane that queued it', () {
      fakeAsync((async) {
        final controller = _Two();
        final a = controller.first.enqueue<_AB, void>(key: 'a', _nothing);
        final b = controller.second.enqueue<_AB, void>(key: 'b', _nothing);

        expect(a.lane, same(controller.first.id));
        expect(b.lane, same(controller.second.id));
        expect(controller.first.job<_AB, void>(_nothing).lane, isNull);

        async.flushMicrotasks();
        expect(a.isFinished, isTrue);
        expect(a.lane, same(controller.first.id));
        expect(controller.log, [
          'start Job(a)',
          'start Job(b)',
          'finish Job(a) in first',
          'finish Job(b) in second',
        ]);
      });
    });

    test('a job the enqueue ends at once has its lane in onFinish', () {
      fakeAsync((async) {
        final closed = _Two();
        unawaited(closed.close());
        final late = closed.first.enqueue<_AB, void>(key: 'late', _nothing);

        expect(late.lane, same(closed.first.id));
        expect(closed.log, ['finish Job(late) in first']);

        final duplicated = _Two();
        final gate = Completer<void>();
        duplicated.second.enqueue<_AB, void>(
          key: 'k',
          policy: Policy.droppable,
          _waits(gate),
        );
        final dropped = duplicated.second.job<_AB, void>(key: 'k', _nothing);
        duplicated.second.enqueueJob(dropped, policy: Policy.droppable);

        expect(dropped.lane, same(duplicated.second.id));
        expect(duplicated.log, ['finish Job(k) in second']);
      });
    });

    test('a job of a Solo has none', () {
      fakeAsync((async) {
        final solo = _One();
        final made = solo.make('made');
        final queued = solo.run('queued');
        async.flushMicrotasks();

        expect(made.lane, isNull);
        expect(queued.isFinished, isTrue);
        expect(queued.lane, isNull);
      });
    });

    test('a child has the lane its parent runs in', () {
      fakeAsync((async) {
        final controller = _Two();
        late SoloJob<void> child;
        controller.second.enqueue<_AB, void>(key: 'parent', (ctx) async {
          child = ctx.child<void>(key: 'child', (ctx) async {});
          await ctx.run(child);
        });
        async.flushMicrotasks();

        expect(child.isFinished, isTrue);
        expect(child.lane, same(controller.second.id));
      });
    });

    test('a ctx.child handed to a job of another lane runs in that lane', () {
      fakeAsync((async) {
        final controller = _Two();
        final gate = Completer<void>();
        SoloJob<void>? made;
        controller.first.enqueue<_AB, void>(key: 'maker', (ctx) {
          made = ctx.child<void>(key: 'child', (ctx) async {});
          return gate.future;
        });
        controller.second.enqueue<_AB, void>(
          key: 'runner',
          (ctx) => ctx.run(made!),
        );
        async.flushMicrotasks();

        expect(made!.isFinished, isTrue);
        expect(made!.lane, same(controller.second.id));
      });
    });
  });

  test('a SoloLanes with no lanes closes like an idle Solo', () {
    List<String> trace(SoloController<int> Function() make, String what) {
      final log = <String>[];
      fakeAsync((async) {
        Solo.observer = _Closing(log);
        final controller = make();
        switch (what) {
          case 'close':
            controller.close().then((_) => log.add('done'));
          case 'drain':
            controller
                .close(mode: SoloCloseMode.drain)
                .then((_) => log.add('done'));
          default:
            controller.cancelAll().then((_) => log.add('done'));
        }
        log.add('returned');
        _ladder(log, 3);
        async.flushMicrotasks();
        log.add('finished: ${controller.isFinished}');
      });
      return log;
    }

    for (final what in ['close', 'drain', 'cancelAll']) {
      final solo = trace(_One.new, what);
      expect(trace(_Lanes.new, what), solo, reason: what);
      expect(solo.last, 'finished: ${what != 'cancelAll'}', reason: what);
    }
    expect(trace(_Lanes.new, 'close'), [
      'returned',
      'onClose',
      'tick 0',
      'done',
      'tick 1',
      'tick 2',
      'finished: true',
    ]);
  });

  test("a synchronous throw in one lane does not stop the other's start", () {
    fakeAsync((async) {
      final controller = _Two();
      final gate = Completer<void>();
      final a = controller.first.enqueue<_AB, void>(
        key: 'a',
        (ctx) => throw StateError('a'),
      )..ignoreFailure();
      final b = controller.second.enqueue<_AB, void>(key: 'b', _waits(gate));
      scheduleMicrotask(() => controller.log.add('tick'));
      async.flushMicrotasks();

      expect(a.outcome, isA<Failed>());
      expect(
        controller.log.sublist(0, controller.log.indexOf('tick')),
        containsAllInOrder(['start Job(a)', 'start Job(b)']),
      );
      expect(controller.first.current, isNull);
      expect(controller.second.current, same(b));
    });
  });

  test('an observer that throws in onStart does not stop the other lane', () {
    final errors = <Object>[];
    late _Two controller;
    runZonedGuarded(
      () => fakeAsync((async) {
        Solo.observer = _ThrowsOnStart('a');
        controller = _Two();
        final gate = Completer<void>();
        controller.first.enqueue<_AB, void>(key: 'a', _waits(gate));
        controller.second.enqueue<_AB, void>(key: 'b', _waits(gate));
        scheduleMicrotask(() => controller.log.add('tick'));
        async.flushMicrotasks();
      }),
      (error, stackTrace) => errors.add(error),
    );

    expect(controller.log, ['start Job(a)', 'start Job(b)', 'tick']);
    expect(errors, [
      isA<StateError>().having((e) => e.message, 'message', 'observer'),
    ]);
  });

  test('SoloStream mixes into a SoloLanes', () async {
    final controller = _Streamed();
    final events = <int>[];
    controller.stream.listen(events.add);
    controller.a.enqueue<int, void>((ctx) async => ctx.emit(1));
    controller.b.enqueue<int, void>((ctx) async => ctx.emit(2));
    await pumpEventQueue();

    expect(events, [1, 2]);
    await controller.close();
  });

  group('debug lines', () {
    List<String> lines(void Function(FakeAsync async) body) {
      final lines = <String>[];
      Solo.debug = lines.add;
      try {
        fakeAsync(body);
      } finally {
        Solo.debug = null;
      }
      return lines;
    }

    test('enqueue and restart name the lane, and a tail names a job of the '
        'same lane', () {
      final trace = lines((async) {
        final controller = _Two();
        final gate = Completer<void>();
        controller.first.enqueue<_AB, void>(
          key: 'a',
          policy: Policy.droppable,
          _waits(gate),
        );
        async.flushMicrotasks();
        // The first lane is busy, the second is not: no tail.
        controller.second.enqueue<_AB, void>(key: 'b', _waits(gate));
        controller.first.enqueue<_AB, void>(key: 'c', _nothing);
        controller.first.enqueueJob(
          controller.first.job<_AB, void>(key: 'd', _nothing),
          first: true,
        );
        controller.first.enqueue<_AB, void>(
          key: 'a',
          policy: Policy.droppable,
          _nothing,
        );
        controller.first.enqueue<_AB, void>(
          key: 'c',
          policy: Policy.droppable,
          _nothing,
        );
        async.flushMicrotasks();
        controller.second.enqueue<_AB, void>(
          key: 'b',
          policy: Policy.restart,
          _nothing,
        );
        unawaited(controller.close());
        controller.first.enqueue<_AB, void>(key: 'late', _nothing);
        gate.complete();
        async.flushMicrotasks();
      });

      expect(trace, [
        'first: enqueue Job(a)',
        'second: enqueue Job(b)',
        'first: enqueue Job(c) while Job(a) is running: it starts after '
            'Job(a) ends',
        'first: enqueue Job(d) first while Job(a) is running: it starts '
            'after Job(a) ends',
        'first: enqueue Job(a): duplicate of Job(a), which is running: if '
            'awaited from inside Job(a), it waits for itself',
        'first: enqueue Job(c): duplicate of Job(c), which is queued while '
            'Job(a) is running: it starts after Job(a) ends',
        'second: enqueue Job(b) while Job(b) is running: it starts after '
            'Job(b) ends',
        'second: restart: cancel Job(b)',
        'close',
        'first: enqueue Job(late): closed',
        'closed',
      ]);
    });

    test('the steps of the pump name the lane', () {
      final trace = lines((async) {
        final controller = _Two();
        controller.first.enqueue<_AB, void>(
          key: 'd',
          canStart: (state) => false,
          _nothing,
        );
        late final SoloJob<void> e;
        e = controller.first.enqueue<_AB, void>(
          key: 'e',
          canStart: (state) {
            unawaited(e.cancel());
            return true;
          },
          _nothing,
        );
        controller.second
            .enqueue<_AB, void>(
              key: 'r',
              canStart: (state) => throw StateError('rule'),
              _nothing,
            )
            .ignoreFailure();
        async.flushMicrotasks();
      });

      expect(trace, [
        'first: enqueue Job(d)',
        'first: enqueue Job(e)',
        'second: enqueue Job(r)',
        'first: drop Job(d): Cancelled(rules: canStart)',
        'first: start Job(e): ended while the rules were asked',
        'first: queue has no ready jobs',
        'second: rule of Job(r) threw: Bad state: rule',
        'second: queue has no ready jobs',
      ]);
    });

    test('a removal and a move to the tail name the lane', () {
      final trace = lines((async) {
        final controller = _Two();
        final gate = Completer<void>();
        controller.first.enqueue<_AB, void>(key: 'busy', _waits(gate));
        controller.second.enqueue<_AB, void>(key: 'busy', _waits(gate));
        async.flushMicrotasks();
        final stays = controller.first.enqueue<_AB, void>(
          key: 'stays',
          cancellable: false,
          _nothing,
        );
        final goes = controller.first.enqueue<_AB, void>(key: 'goes', _nothing);
        controller.first.queue
          ..remove(stays)
          ..remove(goes);
        final group = controller.second.collect<_AB, int, void>(
          key: 'g',
          policy: AccumulationPolicy.replace,
          (ctx, events) async {},
        )..add(1);
        controller.second.enqueue<_AB, void>(key: 'x', _nothing);
        group.add(2);
      });

      expect(trace, [
        'first: enqueue Job(busy)',
        'second: enqueue Job(busy)',
        'first: enqueue Job(stays) while Job(busy) is running: it starts '
            'after Job(busy) ends',
        'first: enqueue Job(goes) while Job(busy) is running: it starts '
            'after Job(busy) ends',
        'first: remove Job(stays): not cancellable',
        'first: remove Job(goes): Cancelled(manual)',
        'second: enqueue Job(g) while Job(busy) is running: it starts after '
            'Job(busy) ends',
        'second: enqueue Job(x) while Job(busy) is running: it starts after '
            'Job(busy) ends',
        'second: move Job(g) to the tail',
      ]);
    });

    test('the lines of a job, of the state and of closing name no lane', () {
      final trace = lines((async) {
        final controller = _Two();
        controller.first.enqueue<_AB, void>(
          key: 'w',
          (ctx) async => ctx.emit((a: 1, b: 0)),
        );
        controller.second.enqueue<_AB, void>(
          key: 'x',
          isExpectedError: (error) => error is StateError,
          (ctx) async => throw StateError('x'),
        );
        async.flushMicrotasks();
        controller.outside((a: 2, b: 0));
        unawaited(controller.close(mode: SoloCloseMode.drain));
        unawaited(controller.close());
        async.flushMicrotasks();
      });

      expect(trace, [
        'first: enqueue Job(w)',
        'second: enqueue Job(x)',
        'Job(w) emit: (a: 1, b: 0)',
        'state: (a: 1, b: 0)',
        'Job(x) expected Bad state: x: nobody is asked to answer',
        'externalSetState: (a: 2, b: 0)',
        'state: (a: 2, b: 0)',
        'close: draining',
        'close: the drain gives way',
        'closed',
      ]);
    });

    test(
      'an idle lane that takes nothing from an empty queue says nothing',
      () {
        final trace = lines((async) {
          final controller = _Two();
          final gate = Completer<void>();
          controller.second.enqueue<_AB, void>(key: 'b', _waits(gate));
          async.flushMicrotasks();
          gate.complete();
          async.flushMicrotasks();
          // A group waiting for its window is not an empty queue: the line
          // comes, as for a Solo.
          controller.first
              .collect<_AB, int, void>(
                key: 'g',
                timing: AccumulationTiming.debounce(
                  const Duration(milliseconds: 10),
                ),
                (ctx, events) async {},
              )
              .add(1);
          async.flushMicrotasks();
        });

        expect(trace, [
          'second: enqueue Job(b)',
          'first: enqueue Job(g)',
          'first: queue has no ready jobs',
        ]);
      },
    );

    test(
      'a lane with a group waiting says so once, not for each neighbour',
      () {
        final trace = lines((async) {
          final controller = _Two();
          controller.first
              .collect<_AB, int, void>(
                key: 'g',
                timing: AccumulationTiming.debounce(
                  const Duration(milliseconds: 10),
                ),
                (ctx, events) async {},
              )
              .add(1);
          async.flushMicrotasks();
          for (var i = 0; i < 5; i++) {
            controller.second.enqueue<_AB, void>(key: 'n$i', _nothing);
            async.flushMicrotasks();
          }
        });

        expect(trace.where((line) => line.startsWith('first: queue')), [
          'first: queue has no ready jobs',
        ]);
      },
    );

    test('a group that waits after another group has run says so again', () {
      final trace = lines((async) {
        final controller = _Two();
        final gate = Completer<void>();
        const window = Duration(milliseconds: 10);
        controller.first
            .collect<_AB, int, void>(
              key: 'g',
              timing: AccumulationTiming.debounce(window),
              (ctx, events) => gate.future,
            )
            .add(1);
        async
          ..flushMicrotasks()
          ..elapse(window);
        controller.first
            .collect<_AB, int, void>(
              key: 'h',
              timing: AccumulationTiming.debounce(window),
              (ctx, events) async {},
            )
            .add(1);
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();
      });

      expect(trace.where((line) => line == 'first: queue has no ready jobs'), [
        'first: queue has no ready jobs',
        'first: queue has no ready jobs',
      ]);
    });

    test('a Solo in the same program says its lines as before', () {
      final trace = lines((async) {
        final controller = _Two();
        final solo = _One();
        controller.first.enqueue<_AB, void>(key: 'a', _nothing);
        solo.run('s');
        async.flushMicrotasks();
      });

      expect(trace, [
        'first: enqueue Job(a)',
        'enqueue Job(s)',
        'queue has no ready jobs',
      ]);
    });
  });
}
