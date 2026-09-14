import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    SoloBase.debug = null;
  });

  test('debounce restarts the window while ready jobs bypass it', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
      final calls = <String>[];
      final events = solo.collect<int, int, void>(
        (ctx, values) async => calls.add('A:$values'),
        timing: AccumulationTiming.debounce(
          const Duration(milliseconds: 200),
        ),
      );

      // Calls are interleaved with clock changes, so a cascade is misleading.
      // ignore: cascade_invocations
      events.add(1);
      async.elapse(const Duration(milliseconds: 60));
      events.add(2);
      // The event between these calls makes a cascade change the timeline.
      // ignore: cascade_invocations
      async.elapse(const Duration(milliseconds: 60));
      events.add(3);
      solo.run<int, void>((ctx) async => calls.add('B'));
      async.flushMicrotasks();

      expect(calls, ['B']);
      async.elapse(const Duration(milliseconds: 199));
      expect(calls, ['B']);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, ['B', 'A:[1, 2, 3]']);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('a successful no-op merge restarts debounce', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
      final calls = <String>[];
      final events = solo.accumulate<int, int, void>(
        (ctx, value) async => calls.add('${async.elapsed}:$value'),
        merge: (previous, incoming) => previous,
        timing: AccumulationTiming.debounce(
          const Duration(milliseconds: 200),
        ),
      );

      // Calls are interleaved with clock changes, so a cascade is misleading.
      // ignore: cascade_invocations
      events.add(1);
      async.elapse(const Duration(milliseconds: 100));
      events.add(2);
      async.elapse(const Duration(milliseconds: 199));
      expect(calls, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, ['0:00:00.300000:1']);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('a failed merge leaves debounce data and deadline unchanged', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
      final calls = <String>[];
      final error = StateError('merge failed');
      final events = solo.accumulate<int, int, void>(
        (ctx, value) async => calls.add('${async.elapsed}:$value'),
        merge: (previous, incoming) {
          if (incoming == 99) throw error;
          return previous + incoming;
        },
        timing: AccumulationTiming.debounce(
          const Duration(milliseconds: 200),
        ),
      );

      // Calls are interleaved with clock changes, so a cascade is misleading.
      // ignore: cascade_invocations
      events.add(1);
      async.elapse(const Duration(milliseconds: 100));
      expect(() => events.add(99), throwsA(same(error)));
      async.elapse(const Duration(milliseconds: 99));
      expect(calls, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, ['0:00:00.200000:1']);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('continuous input keeps debounce waiting until silence', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
      final calls = <String>[];
      final events = solo.collect<int, int, void>(
        (ctx, values) async => calls.add('${async.elapsed}:${values.length}'),
        timing: AccumulationTiming.debounce(
          const Duration(milliseconds: 200),
        ),
      );

      for (var event = 0; event < 20; event++) {
        events.add(event);
        if (event < 19) {
          async.elapse(const Duration(milliseconds: 100));
        }
      }
      expect(async.elapsed, const Duration(milliseconds: 1900));
      expect(calls, isEmpty);

      async.elapse(const Duration(milliseconds: 199));
      expect(calls, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, ['0:00:02.100000:20']);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('debounce seals its snapshot while another job owns the slot', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
      final gate = Completer<void>();
      final calls = <String>[];
      solo.run<int, void>((ctx) => ctx.join(() => gate.future));
      final events = solo.collect<int, int, void>(
        (ctx, values) async => calls.add('${async.elapsed}:$values'),
        timing: AccumulationTiming.debounce(
          const Duration(milliseconds: 200),
        ),
      );

      async.flushMicrotasks();
      final first = events.add(1);
      async.elapse(const Duration(milliseconds: 200));
      final second = events.add(2);
      events.add(3);
      expect(identical(first, second), isFalse);
      gate.complete();
      async.flushMicrotasks();
      expect(calls, ['0:00:00.200000:[1]']);
      async.elapse(const Duration(milliseconds: 199));
      expect(calls, ['0:00:00.200000:[1]']);
      async.elapse(const Duration(milliseconds: 1));
      expect(
        calls,
        ['0:00:00.200000:[1]', '0:00:00.400000:[2, 3]'],
      );

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('throttle starts the first group and later data at its deadline', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
      final calls = <String>[];
      final events = solo.collect<int, int, void>(
        (ctx, values) async => calls.add('${async.elapsed}:A$values'),
        timing: AccumulationTiming.throttle(
          const Duration(milliseconds: 200),
        ),
      );

      // Calls are interleaved with clock changes, so a cascade is misleading.
      // ignore: cascade_invocations
      events.add(1);
      async.flushMicrotasks();
      expect(calls, ['0:00:00.000000:A[1]']);
      async.elapse(const Duration(milliseconds: 60));
      events.add(2);
      async.elapse(const Duration(milliseconds: 60));
      events.add(3);
      solo.run<int, void>(
        (ctx) async => calls.add('${async.elapsed}:B'),
      );
      async.flushMicrotasks();
      expect(calls, ['0:00:00.000000:A[1]', '0:00:00.120000:B']);
      async.elapse(const Duration(milliseconds: 79));
      expect(calls, ['0:00:00.000000:A[1]', '0:00:00.120000:B']);
      async.elapse(const Duration(milliseconds: 1));
      expect(
        calls,
        [
          '0:00:00.000000:A[1]',
          '0:00:00.120000:B',
          '0:00:00.200000:A[2, 3]',
        ],
      );
      async.elapse(const Duration(milliseconds: 200));
      expect(calls.length, 3);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('a delayed throttle start begins the next interval when it runs', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
      final gate = Completer<void>();
      final calls = <String>[];
      final events = solo.collect<int, int, void>(
        (ctx, values) async => calls.add('${async.elapsed}:A$values'),
        timing: AccumulationTiming.throttle(
          const Duration(milliseconds: 200),
        ),
      );

      // Calls are interleaved with clock changes, so a cascade is misleading.
      // ignore: cascade_invocations
      events.add(1);
      async.flushMicrotasks();
      // Timeline operations are separated by event additions and assertions.
      // ignore: cascade_invocations
      async.elapse(const Duration(milliseconds: 60));
      events.add(2);
      async.elapse(const Duration(milliseconds: 90));
      solo.run<int, void>((ctx) async {
        calls.add('${async.elapsed}:B');
        await ctx.join(() => gate.future);
      });
      async.flushMicrotasks();
      // Timeline operations are separated by event additions and assertions.
      // ignore: cascade_invocations
      async.elapse(const Duration(milliseconds: 350));
      expect(calls, ['0:00:00.000000:A[1]', '0:00:00.150000:B']);
      gate.complete();
      async.flushMicrotasks();
      expect(
        calls,
        [
          '0:00:00.000000:A[1]',
          '0:00:00.150000:B',
          '0:00:00.500000:A[2]',
        ],
      );
      events.add(3);
      async.elapse(const Duration(milliseconds: 199));
      expect(calls.length, 3);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls.last, '0:00:00.700000:A[3]');

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('a shared timing setting keeps accumulator intervals independent', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
      final calls = <String>[];
      final timing = AccumulationTiming.throttle(
        const Duration(milliseconds: 200),
      );
      final a = solo.collect<int, int, void>(
        (ctx, values) async => calls.add('A$values'),
        timing: timing,
      );
      final b = solo.collect<int, int, void>(
        (ctx, values) async => calls.add('B$values'),
        timing: timing,
      );

      a.add(1);
      b.add(2);
      async.flushMicrotasks();
      expect(calls, ['A[1]', 'B[2]']);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('an elapsed throttle interval does not pump an empty queue', () {
    fakeAsync((async) {
      final debug = <String>[];
      SoloBase.debug = debug.add;
      final solo = Solo<int>(0);
      final events = solo.collect<int, int, void>(
        (ctx, values) async {},
        timing: AccumulationTiming.throttle(
          const Duration(milliseconds: 200),
        ),
      );

      // Keep the accumulator visible for the timing-specific setup above.
      // ignore: cascade_invocations
      events.add(1);
      async.flushMicrotasks();
      final pumpsAfterFinish =
          debug.where((message) => message == 'queue has no ready jobs').length;
      expect(pumpsAfterFinish, 1);

      async.elapse(const Duration(milliseconds: 200));
      expect(
        debug.where((message) => message == 'queue has no ready jobs').length,
        pumpsAfterFinish,
      );

      solo.close();
      async.flushMicrotasks();
    });
  });

  // Criterion 17 of 2026-09-14[20]-accumulation-rules-design.md: what a
  // throttle does in all three shapes a burst arrives in. The wave's change
  // B adds a mode to `AccumulationTiming.throttle`, and this is the promise
  // that makes it a non-breaking one; without these three it hangs on the
  // count of the suite alone.
  test('a throttle burst written in one synchronous pass', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
      final calls = <String>[];
      final events = solo.collect<int, int, void>(
        (ctx, values) async => calls.add('${async.elapsed}:$values'),
        timing: AccumulationTiming.throttle(
          const Duration(milliseconds: 200),
        ),
      );

      // Keep the accumulator visible for the timing-specific setup above.
      // ignore: cascade_invocations
      events
        ..add(1)
        ..add(2)
        ..add(3);
      async.flushMicrotasks();
      expect(calls, ['0:00:00.000000:[1, 2, 3]']);
      async.elapse(const Duration(milliseconds: 400));
      expect(calls.length, 1);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('a throttle burst with a microtask after the first event', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
      final calls = <String>[];
      final events = solo.collect<int, int, void>(
        (ctx, values) async => calls.add('${async.elapsed}:$values'),
        timing: AccumulationTiming.throttle(
          const Duration(milliseconds: 200),
        ),
      );

      // The microtask between the additions is the shape under test.
      // ignore: cascade_invocations
      events.add(1);
      async.flushMicrotasks();
      expect(calls, ['0:00:00.000000:[1]']);
      events
        ..add(2)
        ..add(3);
      async.elapse(const Duration(milliseconds: 199));
      expect(calls.length, 1);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, ['0:00:00.000000:[1]', '0:00:00.200000:[2, 3]']);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('a throttle burst that arrives while another job runs', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
      final gate = Completer<void>();
      final calls = <String>[];
      solo.run<int, void>((ctx) => ctx.join(() => gate.future));
      final events = solo.collect<int, int, void>(
        (ctx, values) async => calls.add('${async.elapsed}:$values'),
        timing: AccumulationTiming.throttle(
          const Duration(milliseconds: 200),
        ),
      );

      async.flushMicrotasks();
      final first = events.add(1);
      async.elapse(const Duration(milliseconds: 50));
      events.add(2);
      expect(calls, isEmpty);
      expect(first.isQueued, isTrue);
      gate.complete();
      async.flushMicrotasks();
      expect(calls, ['0:00:00.050000:[1, 2]']);
      events.add(3);
      async.elapse(const Duration(milliseconds: 199));
      expect(calls.length, 1);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls.last, '0:00:00.250000:[3]');

      solo.close();
      async.flushMicrotasks();
    });
  });

  // `startAtOnce: false` counts the interval before the first group too.
  // Each of the three below keeps the half that tells the mode from an
  // ordinary throttle: drop `startAtOnce: false` and it fails.
  test('a trailing throttle burst with a microtask after the first', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
      final calls = <String>[];
      final events = solo.collect<int, int, void>(
        (ctx, values) async => calls.add('${async.elapsed}:$values'),
        timing: AccumulationTiming.throttle(
          const Duration(seconds: 1),
          startAtOnce: false,
        ),
      );

      // The microtask between the additions is the shape under test.
      // ignore: cascade_invocations
      events.add(1);
      async.flushMicrotasks();
      expect(calls, isEmpty);
      events
        ..add(2)
        ..add(3);
      async.elapse(const Duration(seconds: 3));
      expect(calls, ['0:00:01.000000:[1, 2, 3]']);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('a trailing throttle with a single event', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
      final calls = <String>[];
      final events = solo.collect<int, int, void>(
        (ctx, values) async => calls.add('${async.elapsed}:$values'),
        timing: AccumulationTiming.throttle(
          const Duration(seconds: 1),
          startAtOnce: false,
        ),
      );

      // The clock moves between the assertions, so a cascade is misleading.
      // ignore: cascade_invocations
      events.add(1);
      async.elapse(const Duration(milliseconds: 999));
      expect(calls, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, ['0:00:01.000000:[1]']);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('a trailing throttle under input that never stops', () {
    fakeAsync((async) {
      final solo = Solo<int>(0);
      final calls = <String>[];
      final events = solo.collect<int, int, void>(
        (ctx, values) async => calls.add('${async.elapsed}:${values.length}'),
        timing: AccumulationTiming.throttle(
          const Duration(seconds: 1),
          startAtOnce: false,
        ),
      );

      for (var event = 0; event < 20; event++) {
        events.add(event);
        async.elapse(const Duration(milliseconds: 200));
      }
      async.elapse(const Duration(seconds: 3));
      // Every group carries the five events of its own interval, the first
      // one included: the ceiling holds from the start, and it is what a
      // debounce under input like this would never reach.
      expect(calls, [
        '0:00:01.000000:5',
        '0:00:02.000000:5',
        '0:00:03.000000:5',
        '0:00:04.000000:5',
      ]);

      solo.close();
      async.flushMicrotasks();
    });
  });

  test('negative timing is rejected and zero preserves queue order', () {
    expect(
      () => AccumulationTiming.debounce(
        const Duration(microseconds: -1),
      ),
      throwsArgumentError,
    );
    expect(
      () => AccumulationTiming.throttle(
        const Duration(microseconds: -1),
      ),
      throwsArgumentError,
    );

    for (final timing in [
      AccumulationTiming.debounce(Duration.zero),
      AccumulationTiming.throttle(Duration.zero),
    ]) {
      fakeAsync((async) {
        final solo = Solo<int>(0);
        final calls = <String>[];
        final events = solo.collect<int, int, void>(
          (ctx, values) async => calls.add('A$values'),
          timing: timing,
        );
        // The ordinary job deliberately separates these accumulation calls.
        // ignore: cascade_invocations
        events.add(1);
        solo.run<int, void>((ctx) async => calls.add('B'));
        events.add(2);
        async.flushMicrotasks();
        expect(calls, ['A[1]', 'B', 'A[2]']);
        solo.close();
        async.flushMicrotasks();
      });
    }
  });
}
