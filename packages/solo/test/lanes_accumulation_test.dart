// `SoloLanes`: the accumulator of a lane keeps every group in its lane and
// reads the queue and the current job of its own lane only; a job waits for
// a job of another lane, and hangs on its own lane as it does in `Solo`.
//
// Every group below names the mutation that holds it, in the lane code of
// `accumulator.dart` and `lane.dart`; each was seen red in a saved copy of
// the library.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

/// Two lanes, `a` first, and a log of the starts with their lanes.
final class _Two extends SoloLanes<int> {
  final log = <String>[];
  late final SoloLane<int> a;
  late final SoloLane<int> b;

  _Two() : super(0) {
    a = lane('a');
    b = lane('b');
  }

  @override
  void onStart(Job<Object?> job) =>
      log.add('${(job as SoloJob<Object?>).lane}:$job');
}

Future<void> Function(SoloContext<int, int> ctx) _waits(Completer<void> gate) =>
    (ctx) => gate.future;

void main() {
  // Held by: `_enqueue` (`accumulator.dart`) sending a group to the first
  // lane instead of its own (the first test); the pump stepping a lane that
  // holds a current job (the second); the throttle wake reading the current
  // jobs of all lanes instead of its own (the third); `_candidate` reading
  // the queue of the last lane (adjacent); `_isIdle` reading the current job
  // of the first lane (the idle test).
  group("a lane's accumulator", () {
    test('puts every group in its lane', () {
      fakeAsync((async) {
        final two = _Two();
        final gate = Completer<void>();
        two.a.enqueue<int, void>(key: 'busy a', _waits(gate));
        two.b.enqueue<int, void>(key: 'busy b', _waits(gate));
        async.flushMicrotasks();
        final events = two.b.collect<int, int, void>(
          key: 'events',
          (ctx, values) async {},
        );

        final group = events.add(1);

        expect(group.lane?.name, 'b');
        expect(two.b.queue.jobs, [same(group)]);
        expect(two.a.queue.jobs, isEmpty);
        gate.complete();
        async.flushMicrotasks();
        expect(group.outcome, isA<Done<void>>());
        expect(two.log, contains('b:Job(events)'));
        two.close();
        async.flushMicrotasks();
      });
    });

    test('two groups of one accumulator never run at once', () {
      fakeAsync((async) {
        final two = _Two();
        final gate = Completer<void>();
        var running = 0;
        var most = 0;
        final calls = <List<int>>[];
        final events = two.a.collect<int, int, void>(
          key: 'events',
          policy: AccumulationPolicy.adjacent,
          (ctx, values) async {
            calls.add(values);
            running++;
            most = running > most ? running : most;
            await gate.future;
            running--;
          },
        );
        // The other lane stays busy and free in turn; it must not matter.
        two.b.enqueue<int, void>(key: 'other', (ctx) async {});

        final first = events.add(1);
        async.flushMicrotasks();
        final second = events.add(2);
        two.b.enqueue<int, void>(key: 'other 2', (ctx) async {});
        async.flushMicrotasks();

        expect(first.isRunning, isTrue);
        expect(second.isQueued, isTrue);
        expect(identical(first, second), isFalse);
        gate.complete();
        async.flushMicrotasks();

        expect(calls, [
          [1],
          [2],
        ]);
        expect(most, 1);
        two.close();
        async.flushMicrotasks();
      });
    });

    test('a throttle window wakes its group while the other lane is busy', () {
      fakeAsync((async) {
        final two = _Two();
        final gate = Completer<void>();
        final calls = <String>[];
        final events = two.a.collect<int, int, void>(
          key: 'events',
          timing: AccumulationTiming.throttle(
            const Duration(milliseconds: 200),
          ),
          (ctx, values) async => calls.add('${async.elapsed}:$values'),
        );
        two.b.enqueue<int, void>(key: 'long', _waits(gate));

        // Calls are interleaved with clock changes, not a cascade.
        // ignore: cascade_invocations
        events.add(1);
        async.flushMicrotasks();
        // ignore: cascade_invocations
        async.elapse(const Duration(milliseconds: 60));
        events.add(2);
        async.elapse(const Duration(milliseconds: 139));
        expect(calls, ['0:00:00.000000:[1]']);
        async.elapse(const Duration(milliseconds: 1));

        expect(calls, ['0:00:00.000000:[1]', '0:00:00.200000:[2]']);
        expect(
          two.b.current?.key,
          'long',
          reason: 'the other lane was busy the whole time',
        );
        gate.complete();
        two.close();
        async.flushMicrotasks();
      });
    });

    test('a group running in its lane keeps the accumulator from idling', () {
      fakeAsync((async) {
        final two = _Two();
        final calls = <String>[];
        final events = two.b.collect<int, int, void>(
          key: 'events',
          timing: AccumulationTiming.throttle(
            const Duration(milliseconds: 200),
            startAtOnce: false,
          ),
          (ctx, values) async {
            calls.add('${async.elapsed}:$values');
            await Future<void>.delayed(const Duration(milliseconds: 300));
          },
        );

        // The first group starts at the end of its interval and runs past
        // the next one.
        // Calls are interleaved with clock changes, not a cascade.
        // ignore: cascade_invocations
        events.add(1);
        async.elapse(const Duration(milliseconds: 450));
        expect(calls, ['0:00:00.200000:[1]']);
        // It is running in lane b, so the accumulator is not idle and the
        // second group does not wait for an interval of its own.
        events.add(2);
        async.elapse(const Duration(milliseconds: 50));

        expect(calls, ['0:00:00.200000:[1]', '0:00:00.500000:[2]']);
        two.close();
        async.flushTimers();
      });
    });

    test('adjacent looks at the tail of its own lane', () {
      fakeAsync((async) {
        final two = _Two();
        final gate = Completer<void>();
        final calls = <List<int>>[];
        two.a.enqueue<int, void>(key: 'busy a', _waits(gate));
        two.b.enqueue<int, void>(key: 'busy b', _waits(gate));
        async.flushMicrotasks();
        final events = two.a.collect<int, int, void>(
          key: 'events',
          policy: AccumulationPolicy.adjacent,
          (ctx, values) async => calls.add(values),
        );

        // The tail of its own lane is its group: the other lane's tail does
        // not matter.
        final one = events.add(1);
        two.b.enqueue<int, void>(key: 'tail of b', (ctx) async {});
        final joined = events.add(2);
        expect(identical(one, joined), isTrue);

        // A job of its own lane behind the group: a new group.
        two.a.enqueue<int, void>(key: 'tail of a', (ctx) async {});
        final next = events.add(3);
        expect(identical(one, next), isFalse);

        gate.complete();
        async.flushMicrotasks();
        expect(calls, [
          [1, 2],
          [3],
        ]);
        two.close();
        async.flushMicrotasks();
      });
    });
  });

  // Held by: `_enqueueIn` looking for the duplicate in the first lane
  // instead of the lane of the call (`_lastJobWhereIn(_cores.first, ...)`):
  // the test for lane `b` goes red.
  group('a droppable call during a drain', () {
    for (final name in ['a', 'b']) {
      test('gets back the job that holds its key, in lane $name', () {
        fakeAsync((async) {
          final two = _Two();
          final lane = name == 'a' ? two.a : two.b;
          SoloJob<void> keyed(String key) => lane.enqueue<int, void>(
            key: key,
            policy: Policy.droppable,
            (ctx) async =>
                Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          final running = keyed('running');
          final queued = keyed('queued');
          async.flushMicrotasks();

          two.close(mode: SoloCloseMode.drain).ignore();
          expect(identical(keyed('running'), running), isTrue);
          expect(identical(keyed('queued'), queued), isTrue);
          final fresh = keyed('fresh');
          async.flushTimers();

          expect(running.outcome, isA<Done<void>>());
          expect(queued.outcome, isA<Done<void>>());
          expect(
            fresh.outcome,
            isA<Cancelled>().having(
              (c) => c.reason,
              'reason',
              isA<ClosedCancelReason>(),
            ),
          );
        });
      });
    }
  });

  // Held by: `_step` starting a job in a lane that holds a current one
  // (`core.current != null` removed): the hang on one's own lane goes red.
  // The wait between lanes has no mutation of its own: it is the absence of
  // a wait that the pump of one lane would add.
  group('waiting between lanes', () {
    test('a job of one lane awaits a job of the other', () {
      fakeAsync((async) {
        final two = _Two();
        Outcome<void>? inner;
        final outer = two.a.enqueue<int, void>(key: 'outer', (ctx) async {
          inner = await two.b
              .enqueue<int, void>(
                key: 'inner',
                (ctx) async =>
                    Future<void>.delayed(const Duration(milliseconds: 30)),
              )
              .done;
        });
        async.flushMicrotasks();
        expect(outer.isRunning, isTrue);
        async.elapse(const Duration(milliseconds: 30));

        expect(inner, isA<Done<void>>());
        expect(outer.outcome, isA<Done<void>>());
        two.close();
        async.flushMicrotasks();
      });
    });

    test("waiting for one's own lane hangs", () {
      fakeAsync((async) {
        final two = _Two();
        final outer = two.a.enqueue<int, void>(key: 'outer', (ctx) async {
          await two.a.enqueue<int, void>(key: 'inner', (ctx) async {}).done;
        });
        // The other lane runs on while the first hangs.
        final free = two.b.enqueue<int, void>(key: 'free', (ctx) async {});
        async.elapse(const Duration(seconds: 100));

        expect(free.outcome, isA<Done<void>>());
        expect(outer.outcome, isNull);
        expect(two.a.queue.jobs.map((job) => job.key), ['inner']);

        two.close();
        async.flushTimers();
      });
    });
  });
}
