// Characterization tests of the 1.x engine, counted in microtasks: where a
// pump start lands and when `cancelAll` completes, against a ladder of
// microtasks started right after the call. They were written against the
// engine before the pump was rebuilt and are never edited afterwards; every
// expected journal below is a snapshot of 1.x.
//
// ignore_for_file: cascade_invocations
//
// The file is self-contained on purpose, as `engine_pins_test.dart` is: it
// uses the protected hooks of the controller and not `SoloObserver`.
@Timeout(Duration(seconds: 10))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

/// Counts [n] microtasks: `tick 0` runs on the first one after the call.
void ladder(List<String> log, int n) {
  var i = 0;
  void step() {
    if (i >= n) return;
    scheduleMicrotask(() {
      log.add('tick $i');
      i++;
      step();
    });
  }

  step();
}

class _Pin extends Solo<int> {
  _Pin(this.log) : super(0);

  final List<String> log;

  @override
  void onStart(Job<Object?> job) => log.add('start ${job.key}');

  @override
  void onFinish(Job<Object?> job) => log.add('finish ${job.key}');

  SoloJob<T> put<T>(
    Object key,
    Future<T> Function(SoloContext<int, int>) body,
  ) => enqueue<int, T>(key: key, body);

  Future<void> cancelEverything() => cancelAll();
}

/// A body that waits until it is cancelled.
Future<void> _untilCancelled(SoloContext<int, int> ctx) =>
    ctx.abandonable(() => Completer<void>().future);

Matcher _cancelledManually({required bool started}) => isA<Cancelled>()
    .having((c) => c.reason, 'reason', isA<ManualCancelReason>())
    .having((c) => c.started, 'started', started);

void main() {
  late List<String> log;

  setUp(() {
    log = [];
    Solo.debug = log.add;
  });

  tearDown(() {
    Solo.debug = null;
  });

  test('a pump start lands on the first microtask after enqueue', () async {
    final pin = _Pin(log);
    pin.put<void>('a', (ctx) async {});
    ladder(log, 5);
    await pumpEventQueue();
    // 1.x snapshot: the job starts on the pump's microtask, scheduled by
    // `enqueue` before `tick 0`; its end wakes the pump once more, which
    // finds the queue empty.
    expect(log, [
      'enqueue Job(a)',
      'start a',
      'tick 0',
      'tick 1',
      'finish a',
      'tick 2',
      'queue has no ready jobs',
      'tick 3',
      'tick 4',
    ]);
  });

  test(
    'cancelAll on an idle controller completes on the first microtask',
    () async {
      final pin = _Pin(log);
      pin.cancelEverything().then((_) => log.add('cancelAll done')).ignore();
      log.add('cancelAll returned');
      ladder(log, 3);
      await pumpEventQueue();
      // 1.x snapshot: the future is a completed one, and its `then` runs
      // before `tick 0`.
      expect(log, [
        'cancelAll returned',
        'cancelAll done',
        'tick 0',
        'tick 1',
        'tick 2',
      ]);
    },
  );

  test(
    "cancelAll with one busy job completes with that job's cancel",
    () async {
      final pin = _Pin(log);
      final a = pin.put<void>('a', _untilCancelled);
      await pumpEventQueue();
      a.whenCancelled((_) => log.add('cancel a'));
      log.clear();
      pin.cancelEverything().then((_) => log.add('cancelAll done')).ignore();
      log.add('cancelAll returned');
      ladder(log, 8);
      await pumpEventQueue();
      // 1.x snapshot: the job hears its cancellation inside the call, ends
      // between `tick 0` and `tick 1`, the pump it wakes runs after `tick 1`,
      // and the future completes in that same microtask, before `tick 2`.
      expect(log, [
        'cancel a',
        'cancelAll returned',
        'tick 0',
        'finish a',
        'tick 1',
        'queue has no ready jobs',
        'cancelAll done',
        'tick 2',
        'tick 3',
        'tick 4',
        'tick 5',
        'tick 6',
        'tick 7',
      ]);
      expect(a.outcome, _cancelledManually(started: true));
    },
  );

  test(
    'cancelAll with one busy job and a queue drops the queue first',
    () async {
      final pin = _Pin(log);
      final a = pin.put<void>('a', _untilCancelled);
      await pumpEventQueue();
      final b = pin.put<void>('b', (ctx) async {});
      final c = pin.put<void>('c', (ctx) async {});
      a.whenCancelled((_) => log.add('cancel a'));
      log.clear();
      pin.cancelEverything().then((_) => log.add('cancelAll done')).ignore();
      log.add('cancelAll returned');
      ladder(log, 8);
      await pumpEventQueue();
      // 1.x snapshot: the queued jobs end inside the call, in queue order,
      // before the running one hears its cancellation; that one and the
      // future land as with no queue.
      expect(log, [
        'remove Job(b): Cancelled(manual)',
        'finish b',
        'remove Job(c): Cancelled(manual)',
        'finish c',
        'cancel a',
        'cancelAll returned',
        'tick 0',
        'finish a',
        'tick 1',
        'queue has no ready jobs',
        'cancelAll done',
        'tick 2',
        'tick 3',
        'tick 4',
        'tick 5',
        'tick 6',
        'tick 7',
      ]);
      expect(a.outcome, _cancelledManually(started: true));
      expect(b.outcome, _cancelledManually(started: false));
      expect(c.outcome, _cancelledManually(started: false));
    },
  );
}
