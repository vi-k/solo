// Characterization tests of the 1.x engine: the order of events, the number
// of microtasks in the pump, `close`, `cancelAll` and the drain, the debug
// lines, and the virtual paths a job and an accumulator take into the queue.
// They were written against `main` before the pump was rebuilt and are never
// edited afterwards; every expected journal below is a snapshot of 1.x.
//
// ignore_for_file: cascade_invocations, no_adjacent_strings_in_list
//
// The file is self-contained on purpose: it uses the protected hooks of the
// controller and not `SoloObserver`, whose types change later.
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
  void Function(Job<Object?> job)? whenJobFinished;

  @override
  void onStart(Job<Object?> job) => log.add('start ${job.key}');

  @override
  void onFinish(Job<Object?> job) {
    log.add('finish ${job.key}');
    whenJobFinished?.call(job);
  }

  @override
  void onClose() => log.add('onClose');

  SoloJob<T> put<T>(
    Object key,
    Future<T> Function(SoloContext<int, int> ctx) body, {
    bool Function(int state)? canStart,
    bool cancellable = true,
    Policy policy = Policy.sequential,
  }) => enqueue<int, T>(
    key: key,
    canStart: canStart,
    cancellable: cancellable,
    policy: policy,
    body,
  );

  void cancelEverything() => cancelAll().ignore();

  // The rule that throws in the last test is reported to the zone by
  // default; the journal has no use for that.
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {}
}

/// Writes down the virtual calls the engine makes.
class _Tracing extends _Pin {
  _Tracing(super.log);

  @override
  SoloJob<T> job<W extends int, T>(
    Future<T> Function(SoloContext<int, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    Duration? timeout,
    String Function()? describe,
    int Function(int state, Object error, StackTrace stackTrace)? ifFailed,
    bool Function(Object error)? isExpectedError,
    int Function(int state, Cancelled cancelled)? ifCancelled,
  }) {
    log.add('job');
    return super.job<W, T>(
      body,
      key: key,
      canStart: canStart,
      keepWhile: keepWhile,
      cancellable: cancellable,
      timeout: timeout,
      describe: describe,
      ifFailed: ifFailed,
      isExpectedError: isExpectedError,
      ifCancelled: ifCancelled,
    );
  }

  @override
  SoloJob<T> enqueueJob<T>(
    Job<T> job, {
    bool first = false,
    Policy policy = Policy.sequential,
  }) {
    log.add('enqueueJob');
    return super.enqueueJob<T>(job, first: first, policy: policy);
  }

  SoloAccumulator<int, void> groups() =>
      collect<int, int, void>(key: 'group', (ctx, events) async {});
}

void main() {
  late List<String> log;

  setUp(() {
    log = [];
    Solo.debug = log.add;
  });

  tearDown(() {
    Solo.debug = null;
  });

  test('an idle close finishes on a microtask of its own', () async {
    final pin = _Pin(log);
    pin.close().ignore();
    log.add('close returned');
    ladder(log, 3);
    await pumpEventQueue();
    // 1.x snapshot: `onClose` never arrives from inside `close`; it comes
    // from a microtask of its own, before `tick 0`.
    expect(log, [
      'close',
      'close returned',
      'closed',
      'onClose',
      'tick 0',
      'tick 1',
      'tick 2',
    ]);
  });

  test('a busy close finishes straight from the end of the job', () async {
    final pin = _Pin(log);
    final gate = Completer<void>();
    pin.put<void>('a', (ctx) => gate.future);
    await pumpEventQueue();
    pin.whenJobFinished = (_) => ladder(log, 3);
    log.clear();
    pin.close().ignore();
    gate.complete();
    await pumpEventQueue();
    // 1.x snapshot: `onClose` comes between `tick 0` and `tick 1`, straight
    // from the end of the job.
    expect(log, [
      'close',
      'finish a',
      'tick 0',
      'closed',
      'onClose',
      'tick 1',
      'tick 2',
    ]);
  });

  test('a drain ends in the pump\'s microtask with no "queue has no ready '
      'jobs" line', () async {
    final pin = _Pin(log);
    pin.put<void>('a', (ctx) async {});
    pin.put<void>('b', (ctx) async {});
    pin.whenJobFinished = (job) {
      if (job.key == 'b') ladder(log, 3);
    };
    pin.close(mode: SoloCloseMode.drain).ignore();
    await pumpEventQueue();
    // 1.x snapshot: no `queue has no ready jobs` line, and `onClose` before
    // the ladder started in the last `onFinish`.
    expect(log, [
      'enqueue Job(a)',
      'enqueue Job(b)',
      'close: draining',
      'start a',
      'finish a',
      'start b',
      'finish b',
      'closed',
      'onClose',
      'tick 0',
      'tick 1',
      'tick 2',
    ]);
  });

  test('a rejectable cancel of a cancellable: false job in its start rules '
      'is turned down', () async {
    final pin = _Pin(log);
    late final SoloJob<void> job;
    job = pin.put<void>(
      'a',
      cancellable: false,
      canStart: (_) {
        unawaited(job.cancel());
        return true;
      },
      (ctx) async {},
    );
    await pumpEventQueue();
    // 1.x snapshot.
    expect(log, [
      'enqueue Job(a)',
      'remove Job(a): not cancellable',
      'start a',
      'finish a',
      'queue has no ready jobs',
    ]);
    expect(job.outcome, isA<Done<void>>());
  });

  test('a job put from a finish handler of a job close dropped is cancelled '
      'closed', () async {
    final pin = _Pin(log);
    final gate = Completer<void>();
    pin.put<void>('running', (ctx) => gate.future);
    await pumpEventQueue();
    final queued = pin.put<void>('queued', (ctx) async {});
    SoloJob<void>? late;
    queued.whenFinished((_) {
      late = pin.put<void>('late', (ctx) async {});
    });
    log.clear();
    pin.close().ignore();
    gate.complete();
    await pumpEventQueue();
    // 1.x snapshot.
    expect(log, [
      'close',
      'finish queued',
      'enqueue Job(late): closed',
      'finish late',
      'finish running',
      'closed',
      'onClose',
    ]);
    expect(
      late?.outcome,
      isA<Cancelled>().having(
        (c) => c.reason,
        'reason',
        isA<ClosedCancelReason>(),
      ),
    );
  });

  test('a job put from a finish handler of a job cancelAll dropped survives '
      'and starts', () async {
    final pin = _Pin(log);
    final gate = Completer<void>();
    pin.put<void>('running', (ctx) => gate.future);
    await pumpEventQueue();
    final queued = pin.put<void>('queued', (ctx) async {});
    SoloJob<void>? late;
    queued.whenFinished((_) {
      late = pin.put<void>('late', (ctx) async {});
    });
    log.clear();
    pin.cancelEverything();
    gate.complete();
    await pumpEventQueue();
    // 1.x snapshot.
    expect(log, [
      'remove Job(queued): Cancelled(manual)',
      'finish queued',
      'enqueue Job(late) while Job(running) is running: it starts after '
          'Job(running) ends',
      'finish running',
      'start late',
      'finish late',
      'queue has no ready jobs',
    ]);
    expect(late?.outcome, isA<Done<void>>());
  });

  test('enqueue goes through the virtual enqueueJob and job', () async {
    final pin = _Tracing(log);
    pin.put<void>('a', (ctx) async {});
    await pumpEventQueue();
    expect(log.where((line) => line == 'job' || line == 'enqueueJob'), [
      'job',
      'enqueueJob',
    ]);
  });

  test(
    'an accumulator puts its groups through the virtual enqueueJob',
    () async {
      final pin = _Tracing(log);
      final groups = pin.groups();
      groups.add(1);
      groups.add(2);
      await pumpEventQueue();
      groups.add(3);
      await pumpEventQueue();
      pin.close().ignore();
      groups.add(4);
      await pumpEventQueue();
      // Two events of one group are one group; a closed controller is asked
      // through the same call.
      expect(log.where((line) => line == 'job' || line == 'enqueueJob'), [
        'enqueueJob',
        'enqueueJob',
        'enqueueJob',
      ]);
    },
  );

  test('ctx.child makes the child through the virtual job', () async {
    final pin = _Tracing(log);
    pin.put<void>('a', (ctx) async {
      await ctx.run(ctx.child((child) async {}));
    });
    await pumpEventQueue();
    expect(log.where((line) => line == 'job' || line == 'enqueueJob'), [
      'job',
      'enqueueJob',
      'job',
    ]);
  });

  test('the debug lines of a busy pass are word for word', () async {
    final pin = _Pin(log);
    final gate = Completer<void>();
    pin.put<void>('a', (ctx) => gate.future);
    await pumpEventQueue();
    pin.put<void>(
      'b',
      policy: Policy.droppable,
      canStart: (_) => false,
      (ctx) async {},
    );
    pin.put<void>('b', policy: Policy.droppable, (ctx) async {});
    pin.put<void>(
      'c',
      canStart: (_) => throw StateError('rule'),
      (ctx) async {},
    );
    pin.put<void>('d', policy: Policy.keepLatest, (ctx) async {});
    pin.put<void>('d', policy: Policy.keepLatest, (ctx) async {});
    pin.put<void>('a', policy: Policy.restart, (ctx) async {});
    gate.complete();
    await pumpEventQueue();
    // 1.x snapshot.
    expect(log, [
      'enqueue Job(a)',
      'start a',
      'enqueue Job(b) while Job(a) is running: it starts after Job(a) ends',
      'enqueue Job(b): duplicate of Job(b), which is queued while Job(a) is '
          'running: it starts after Job(a) ends',
      'finish b',
      'enqueue Job(c) while Job(a) is running: it starts after Job(a) ends',
      'enqueue Job(d) while Job(a) is running: it starts after Job(a) ends',
      'enqueue Job(d) while Job(a) is running: it starts after Job(a) ends',
      'remove Job(d): Cancelled(replaced)',
      'finish d',
      'enqueue Job(a) while Job(a) is running: it starts after Job(a) ends',
      'restart: cancel Job(a)',
      'finish a',
      'drop Job(b): Cancelled(rules: canStart)',
      'finish b',
      'rule of Job(c) threw: Bad state: rule',
      'finish c',
      'start d',
      'finish d',
      'start a',
      'finish a',
      'queue has no ready jobs',
    ]);
  });
}
