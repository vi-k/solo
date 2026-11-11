// `pending` of a `SoloLanes`: a `SoloPendingLanes` of the busy lanes, in
// the order of creation, each lane by the rules of a `Solo`; `null` with no
// busy lane. A `Solo` keeps its three variants.
//
// The first five are red while `SoloLanes.pending` answers `null`, as it
// did before it gathered its lanes. Seen red as well, in a saved copy of
// the library: the lanes listed last first (the order test and the print),
// the list handed out as it is built (the order test), an empty
// `SoloPendingLanes` for no busy lane (the idle, order and stream tests),
// and idle lanes listed (all five). `a Solo never says SoloPendingLanes`
// holds the variants of a `Solo`, which the gathering must not reach.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

/// Three lanes, `a`, `b` and `c`, in that order.
final class _Three extends SoloLanes<int> {
  late final SoloLane<int> a;
  late final SoloLane<int> b;
  late final SoloLane<int> c;

  _Three() : super(0) {
    a = lane('a');
    b = lane('b');
    c = lane('c');
  }
}

final class _Streamed extends SoloLanes<int> with SoloStream<int> {
  late final SoloLane<int> a;
  late final SoloLane<int> b;

  _Streamed() : super(0) {
    a = lane('a');
    b = lane('b');
  }
}

final class _One extends Solo<int> {
  _One() : super(0);

  SoloJob<void> put(Object key, Completer<void> gate) =>
      enqueue<int, void>(key: key, (ctx) => gate.future);
}

final class _BrokenKey {
  @override
  String toString() => throw StateError('key');
}

/// A job that waits until [gate] completes.
Future<void> Function(SoloContext<int, int> ctx) _waits(Completer<void> gate) =>
    (ctx) => gate.future;

/// The lanes of [pending] by name, each with the type of its snapshot.
List<String> _lanes(SoloPending? pending) => [
  for (final entry in (pending! as SoloPendingLanes).lanes)
    '${entry.lane.name}: ${entry.pending.runtimeType}',
];

void main() {
  test('pending is null with every lane idle', () {
    fakeAsync((async) {
      final controller = _Three();
      expect(controller.pending, isNull);

      // A group waiting for its window holds nothing without a close, as
      // in a `Solo`.
      controller.b
          .collect<int, int, void>(
            (ctx, events) async {},
            timing: AccumulationTiming.debounce(const Duration(seconds: 1)),
          )
          .add(1);
      final gate = Completer<void>();
      controller.a.enqueue<int, void>(key: 'a', _waits(gate));
      async.flushMicrotasks();
      expect(controller.pending, isNotNull);

      gate.complete();
      async.flushMicrotasks();
      expect(controller.b.queue.length, 1);
      expect(controller.pending, isNull);
      async.flushTimers();
    });
  });

  test('one busy lane is still SoloPendingLanes', () {
    fakeAsync((async) {
      final controller = _Three();
      final gate = Completer<void>();
      final job = controller.b.enqueue<int, void>(key: 'job', _waits(gate));
      async.flushMicrotasks();

      final pending = controller.pending;
      expect(pending, isA<SoloPendingLanes>());
      final [entry] = (pending! as SoloPendingLanes).lanes;
      expect(entry.lane, same(controller.b.id));
      expect(
        entry.pending,
        isA<SoloPendingJob>()
            .having((p) => p.job, 'job', same(job))
            .having((p) => p.phase, 'phase', SoloPhase.body),
      );
      expect('$pending', 'SoloPending(b: SoloPending([job] in its body))');
      gate.complete();
      async.flushMicrotasks();
    });
  });

  test('pending lists busy lanes in the order of creation', () {
    fakeAsync((async) {
      final controller = _Three();
      final gate = Completer<void>();
      // Made busy in the order c, a; b gets a job only once the drain is
      // called, so it has a queue and no running job.
      controller.c.enqueue<int, void>(key: 'c', _waits(gate));
      controller.a.enqueue<int, void>(key: 'a', _waits(gate));
      async.flushMicrotasks();
      controller.a.enqueue<int, void>(key: 'a2', _waits(gate));
      controller.b.enqueue<int, void>(key: 'b', _waits(gate));
      unawaited(controller.close(mode: SoloCloseMode.drain));

      final pending = controller.pending! as SoloPendingLanes;
      expect(_lanes(pending), [
        'a: SoloPendingJob',
        'b: SoloPendingQueue',
        'c: SoloPendingJob',
      ]);
      expect(pending.lanes.removeLast, throwsUnsupportedError);
      expect(
        '$pending',
        'SoloPending('
            'a: SoloPending([a] in its body, draining, 1 queued: [a2]), '
            'b: SoloPending(draining, 1 queued: [b]), '
            'c: SoloPending([c] in its body, draining))',
      );

      // A snapshot, not a view: the lanes moving on do not change it.
      gate.complete();
      async.flushMicrotasks();
      expect(controller.pending, isNull);
      expect(controller.isFinished, isTrue);
      expect(_lanes(pending), hasLength(3));
    });
  });

  test('SoloPendingLanes prints as SoloPending and never throws', () {
    fakeAsync((async) {
      final controller = _Three();
      final gate = Completer<void>();
      controller.a.enqueue<int, void>(key: _BrokenKey(), _waits(gate));
      controller.b.enqueue<int, void>(key: 'b', _waits(gate));
      async.flushMicrotasks();
      unawaited(controller.close());

      expect(
        '${controller.pending}',
        'SoloPending('
            'a: SoloPending([<key threw StateError>] in its body, closing, '
            'cancelled by Cancelled(closed)), '
            'b: SoloPending([b] in its body, closing, '
            'cancelled by Cancelled(closed)))',
      );
      gate.complete();
      async.flushMicrotasks();
    });
  });

  test(
    'a SoloStream over SoloLanes says SoloPendingStream after the lanes',
    () {
      fakeAsync((async) {
        final controller = _Streamed();
        final subscription = controller.stream.listen((_) {})..pause();
        final gate = Completer<void>();
        controller.b.enqueue<int, void>(key: 'b', _waits(gate));
        async.flushMicrotasks();
        var returned = false;
        controller.close().then((_) => returned = true);

        final seen = ['${controller.pending.runtimeType}'];
        gate.complete();
        async.flushMicrotasks();
        seen.add('${controller.pending.runtimeType}');
        expect(controller.isFinished, isTrue);
        expect(returned, isFalse);

        unawaited(subscription.cancel());
        async.flushMicrotasks();
        seen.add('${controller.pending.runtimeType}');

        expect(seen, ['SoloPendingLanes', 'SoloPendingStream', 'Null']);
        expect(returned, isTrue);
      });
    },
  );

  test('a Solo never says SoloPendingLanes', () {
    fakeAsync((async) {
      final busy = _One();
      final gate = Completer<void>();
      busy.put('busy', gate);
      async.flushMicrotasks();

      final draining = _One()..put('queued', gate);
      unawaited(draining.close(mode: SoloCloseMode.drain));

      final idle = _One();

      expect(busy.pending, isA<SoloPendingJob>());
      expect(draining.pending, isA<SoloPendingQueue>());
      expect(idle.pending, isNull);
      gate.complete();
      async.flushMicrotasks();
    });
  });
}
