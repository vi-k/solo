// `SoloLanes`: close, drain and `cancelAll` over every lane. A close drops
// every queue, cancels every running job before it waits, and finishes once,
// with the last lane; a drain ends when every lane is empty; `cancelAll`
// takes its snapshots at the call and completes after every running job.
//
// All of these are green on the engine as the earlier tasks left it: the
// close and `cancelAll` were written for every core from the start. Every
// group below names the mutation of that code it was seen red under, in a
// saved copy of the library.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

/// Two lanes, `a` and `b`, in that order, and a log of the hooks.
final class _Two extends SoloLanes<int> {
  final List<String> log;
  late final SoloLane<int> a;
  late final SoloLane<int> b;

  _Two(this.log) : super(0) {
    a = lane('a');
    b = lane('b');
  }

  @override
  void onStart(Job<Object?> job) => log.add('start ${job.key}');

  @override
  void onFinish(Job<Object?> job) => log.add('finish ${job.key}');

  @override
  void onClose() => log.add('onClose');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      log.add('unanswered ${job.key}: $error');
}

/// Lanes declared by whoever makes it, in its constructor body.
final class _Lanes extends SoloLanes<int> {
  final List<String> log;

  _Lanes(this.log, [void Function(_Lanes self)? declare]) : super(0) {
    declare?.call(this);
  }

  SoloLane<int> declare(String name) => lane(name);

  @override
  void onClose() => log.add('onClose');
}

/// A controller with one queue, logged as [_Two] is.
final class _One extends Solo<int> {
  final List<String> log;

  _One(this.log) : super(0);

  SoloJob<void> put(
    Object key,
    Future<void> Function(SoloContext<int, int> ctx) body, {
    bool cancellable = true,
    bool Function(int state)? canStart,
  }) => enqueue<int, void>(
    key: key,
    cancellable: cancellable,
    canStart: canStart,
    body,
  );

  @override
  void onStart(Job<Object?> job) => log.add('start ${job.key}');

  @override
  void onFinish(Job<Object?> job) => log.add('finish ${job.key}');

  @override
  void onClose() => log.add('onClose');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      log.add('unanswered ${job.key}: $error');
}

/// Logs the closing of every controller.
final class _Closing extends SoloObserver {
  final List<String> log;

  _Closing(this.log);

  @override
  void onClose(SoloController<Object> solo) => log.add('observer onClose');
}

/// A job that waits until [gate] completes, whatever cancels it meanwhile.
Future<void> Function(SoloContext<int, int> ctx) _waits(Completer<void> gate) =>
    (ctx) => gate.future;

Future<void> _nothing(SoloContext<int, int> ctx) async {}

/// Logs `tick 0` to `tick n-1`, each on a microtask of its own.
void _ladder(List<String> log, int n, [int i = 0]) {
  if (i == n) return;
  scheduleMicrotask(() {
    log.add('tick $i');
    _ladder(log, n, i + 1);
  });
}

Matcher _cancelled<R extends CancelReason>({required bool started}) =>
    isA<Cancelled>()
        .having((c) => c.reason, 'reason', isA<R>())
        .having((c) => c.started, 'started', started);

void main() {
  tearDown(() {
    Solo.observer = null;
    Solo.debug = null;
  });

  // Held by: `_stopWork` cancelling the running jobs one after another,
  // each from the end of the one before (the first test); the counter
  // finishing the close at the first end, `unfinished == 0` read as
  // `unfinished < running.length` (the second); and that same counter with
  // the guard of `_finishClose` gone as well, so that every end finishes it
  // (the third: `onClose` twice). The guard gone alone leaves all three
  // green: the counter calls `_finishClose` once.
  group('a close', () {
    test('close cancels the current jobs of every lane before it waits', () {
      fakeAsync((async) {
        final log = <String>[];
        final controller = _Two(log);
        final gate = Completer<void>();
        final a = controller.a.enqueue<int, void>(key: 'a', _waits(gate));
        final b = controller.b.enqueue<int, void>(key: 'b', _waits(gate));
        async.flushMicrotasks();
        a.whenCancelled((_) => log.add('cancel a'));
        b.whenCancelled((_) => log.add('cancel b'));
        log.clear();

        unawaited(controller.close());
        log.add('close returned');
        gate.complete();
        async.flushMicrotasks();

        expect(log.take(3), ['cancel a', 'cancel b', 'close returned']);
        expect(a.outcome, _cancelled<ClosedCancelReason>(started: true));
        expect(b.outcome, _cancelled<ClosedCancelReason>(started: true));
      });
    });

    test('close finishes when the last lane ends', () {
      fakeAsync((async) {
        final log = <String>[];
        final controller = _Two(log);
        final gateA = Completer<void>();
        final gateB = Completer<void>();
        controller.a.enqueue<int, void>(key: 'a', _waits(gateA));
        controller.b.enqueue<int, void>(key: 'b', _waits(gateB));
        async.flushMicrotasks();
        log.clear();

        controller.close().then((_) => log.add('done'));
        gateB.complete();
        async.flushMicrotasks();
        log.add('b is over');
        expect(controller.isFinished, isFalse);
        gateA.complete();
        async.flushMicrotasks();

        expect(log, ['finish b', 'b is over', 'finish a', 'onClose', 'done']);
        expect(controller.isFinished, isTrue);
      });
    });

    test('two lanes that end in one microtask close once', () {
      fakeAsync((async) {
        final log = <String>[];
        Solo.observer = _Closing(log);
        final controller = _Two(log);
        final gate = Completer<void>();
        controller.a.enqueue<int, void>(key: 'a', _waits(gate));
        controller.b.enqueue<int, void>(key: 'b', _waits(gate));
        async.flushMicrotasks();
        log.clear();

        final first = controller.close()..then((_) => log.add('done'));
        final second = controller.close();
        gate.complete();
        _ladder(log, 6);
        async.flushMicrotasks();

        expect(second, same(first));
        // No tick between the two ends: they are one microtask.
        expect(log, [
          'tick 0',
          'finish a',
          'finish b',
          'tick 1',
          'observer onClose',
          'onClose',
          'tick 2',
          'done',
          'tick 3',
          'tick 4',
          'tick 5',
        ]);
      });
    });
  });

  // Held by: the plain `close` over a drain that leaves out `_stopWork`
  // and only stops the drain (`_draining = false`), and by the cancels one
  // after another of the first group.
  test('a plain close over a drain of two busy lanes cancels both and closes '
      'once', () {
    fakeAsync((async) {
      final log = <String>[];
      Solo.observer = _Closing(log);
      final controller = _Two(log);
      final gate = Completer<void>();
      final a = controller.a.enqueue<int, void>(key: 'a', _waits(gate));
      final b = controller.b.enqueue<int, void>(key: 'b', _waits(gate));
      async.flushMicrotasks();
      a.whenCancelled((_) => log.add('cancel a'));
      b.whenCancelled((_) => log.add('cancel b'));
      log.clear();

      final drain = controller.close(mode: SoloCloseMode.drain)
        ..then((_) => log.add('done'));
      async.flushMicrotasks();
      log.add('drain goes on');
      final stop = controller.close();
      log.add('close returned');
      async.flushMicrotasks();
      gate.complete();
      async.flushMicrotasks();

      expect(stop, same(drain));
      expect(log, [
        'drain goes on',
        'cancel a',
        'cancel b',
        'close returned',
        'finish a',
        'finish b',
        'observer onClose',
        'onClose',
        'done',
      ]);
      expect(a.outcome, _cancelled<ClosedCancelReason>(started: true));
      expect(b.outcome, _cancelled<ClosedCancelReason>(started: true));
    });
  });

  // Held by: `_stopWork` waiting for the running jobs through `done`
  // instead of `_untilFinished`, which observes the failure (the second
  // test). The first is held by no mutation of the close: the failure of a
  // body that ends `Cancelled` has no outcome to carry it, so it is
  // answered for however the close waits; it holds the lane to the `Solo`.
  group('a lane job that fails during close is still answered for', () {
    /// The hooks of a job of the second lane of [_Two], or of a [_One],
    /// that throws once a close has asked it to stop.
    List<String> trace({required bool lanes, required bool cancellable}) {
      final log = <String>[];
      fakeAsync((async) {
        final gate = Completer<void>();
        Future<void> body(SoloContext<int, int> ctx) async {
          await gate.future;
          throw StateError('late');
        }

        final SoloController<int> controller;
        if (lanes) {
          controller = _Two(log)
            ..b.enqueue<int, void>(key: 'job', cancellable: cancellable, body);
        } else {
          controller = _One(log)..put('job', cancellable: cancellable, body);
        }
        async.flushMicrotasks();
        controller.close().then((_) => log.add('done'));
        gate.complete();
        async.flushMicrotasks();
      });
      return log;
    }

    test('a job that ends Cancelled', () {
      final lanes = trace(lanes: true, cancellable: true);
      expect(lanes, trace(lanes: false, cancellable: true));
      expect(lanes, contains('unanswered job: Bad state: late'));
    });

    test('a cancellable: false job that ends Failed', () {
      final lanes = trace(lanes: true, cancellable: false);
      expect(lanes, trace(lanes: false, cancellable: false));
      expect(lanes, contains('unanswered job: Bad state: late'));
    });
  });

  // Held by: `_stopWork` draining the queue of the first lane only (the
  // first test: the pass ends after `a`, and a step of a closed controller
  // takes nothing anyway, so the job of `b` stays only if the close leaves
  // it in its queue); `_stepEnd` answering `stop` for any closed
  // controller, a drain included (the second); and `cancelAll` clearing
  // with `force: true`, or `_stepEnd` answering `stop` always (the third).
  group('a rule that closes or cancels', () {
    test('a cancelling close from a rule ends the pass after its lane', () {
      // The hooks log apart: only the lines of `Solo.debug` are compared.
      List<String> lines(void Function(List<String> log) body) {
        final lines = <String>[];
        Solo.debug = lines.add;
        fakeAsync((async) {
          body([]);
          async.flushMicrotasks();
        });
        Solo.debug = null;
        return lines;
      }

      late SoloJob<void> a;
      late SoloJob<void> b;
      final lanes = lines((log) {
        final controller = _Two(log);
        a = controller.a.enqueue<int, void>(
          key: 'a',
          canStart: (state) {
            unawaited(controller.close());
            return true;
          },
          _nothing,
        );
        b = controller.b.enqueue<int, void>(key: 'b', _nothing);
      });
      final solo = lines((log) {
        final controller = _One(log);
        controller.put(
          'a',
          canStart: (state) {
            unawaited(controller.close());
            return true;
          },
          _nothing,
        );
      });

      expect(solo, [
        'enqueue Job(a)',
        'close',
        'start Job(a): ended while the rules were asked',
        'queue has no ready jobs',
        'closed',
      ]);
      // The lines of the step of `a` are those of a `Solo`, with the name
      // of the lane; `b` takes no step, and its job is dropped by the close.
      expect(lanes, [
        'a: enqueue Job(a)',
        'b: enqueue Job(b)',
        'close',
        'a: start Job(a): ended while the rules were asked',
        'a: queue has no ready jobs',
        'closed',
      ]);
      expect(a.outcome, _cancelled<ClosedCancelReason>(started: false));
      expect(b.outcome, _cancelled<ClosedCancelReason>(started: false));
    });

    test('close(drain) from a rule lets the pass go on', () {
      fakeAsync((async) {
        final log = <String>[];
        final controller = _Two(log);
        final gate = Completer<void>();
        controller.a.enqueue<int, void>(
          key: 'a',
          canStart: (state) {
            unawaited(
              controller
                  .close(mode: SoloCloseMode.drain)
                  .then((_) => log.add('done')),
            );
            return true;
          },
          _waits(gate),
        );
        controller.b.enqueue<int, void>(key: 'b', _waits(gate));
        scheduleMicrotask(() => log.add('tick'));
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();

        expect(log, [
          'start a',
          'start b',
          'tick',
          'finish a',
          'finish b',
          'onClose',
          'done',
        ]);
      });
    });

    test('cancelAll from a rule lets the pass go on, and a cancellable: '
        'false job survives in its queue', () {
      fakeAsync((async) {
        final log = <String>[];
        final controller = _Two(log);
        final a = controller.a.enqueue<int, void>(
          key: 'a',
          canStart: (state) {
            unawaited(controller.cancelAll());
            return true;
          },
          _nothing,
        );
        final stays = controller.b.enqueue<int, void>(
          key: 'stays',
          cancellable: false,
          _nothing,
        );
        final goes = controller.b.enqueue<int, void>(key: 'goes', _nothing);
        scheduleMicrotask(() => log.add('tick'));
        async.flushMicrotasks();

        expect(log, [
          'finish a',
          'finish goes',
          'start stays',
          'tick',
          'finish stays',
        ]);
        expect(a.outcome, _cancelled<ManualCancelReason>(started: false));
        expect(goes.outcome, _cancelled<ManualCancelReason>(started: false));
        expect(stays.outcome, isA<Done<void>>());
      });
    });
  });

  // Held by: the end of a drain counting any drained lane, `drained > 0`
  // (the first and the third), or `_stepEnd` answering `stop` for a drain
  // (the first); the pump's check reading `drained == _cores.length &&
  // drained > 0` (the third, which hangs); the drain ended on a microtask
  // of its own after the pass, or no pump scheduled by `close(drain)` (the
  // second, the third and the fourth); and the drain ended from the step
  // of each lane, as 1.x did, with `_finishClose` neither guarded nor
  // resetting `_draining` (the fourth: `onClose` twice). The last two of
  // these change the drain of a `Solo` too, so the expected log is written
  // out rather than taken from a `Solo`.
  group('a drain', () {
    /// The log of a drain of [make], with three microtasks after the call.
    List<String> drain(SoloController<int> Function(List<String> log) make) {
      final log = <String>[];
      fakeAsync((async) {
        Solo.observer = _Closing(log);
        final controller = make(log);
        controller
            .close(mode: SoloCloseMode.drain)
            .then((_) => log.add('done'));
        log.add('returned');
        _ladder(log, 3);
        async.flushMicrotasks();
        log.add('finished: ${controller.isFinished}');
      });
      return log;
    }

    // The drain of an idle `Solo`: written out, not only compared with, since
    // a change of the pump changes the drain of a `Solo` as well.
    const idle = [
      'returned',
      'observer onClose',
      'onClose',
      'tick 0',
      'done',
      'tick 1',
      'tick 2',
      'finished: true',
    ];

    test('a drain ends when every lane is empty', () {
      fakeAsync((async) {
        final log = <String>[];
        final controller = _Two(log);
        final gateA = Completer<void>();
        final gateB = Completer<void>();
        controller.a.enqueue<int, void>(key: 'a', _waits(gateA));
        controller.b.enqueue<int, void>(key: 'b', _waits(gateB));
        controller.b.enqueue<int, void>(key: 'b2', _nothing);
        async.flushMicrotasks();
        log.clear();

        controller
            .close(mode: SoloCloseMode.drain)
            .then((_) => log.add('done'));
        gateB.complete();
        async.flushMicrotasks();
        log.add('b is empty');
        expect(controller.isFinished, isFalse);
        gateA.complete();
        async.flushMicrotasks();

        expect(log, [
          'finish b',
          'start b2',
          'finish b2',
          'b is empty',
          'finish a',
          'onClose',
          'done',
        ]);
      });
    });

    test('a drain of an idle SoloLanes with one lane ends on a microtask', () {
      expect(drain(_One.new), idle);
      expect(drain((log) => _Lanes(log, (self) => self.declare('a'))), idle);
    });

    test('a drain of a SoloLanes with no lanes ends on a microtask', () {
      expect(drain(_Lanes.new), idle);
    });

    test('a drain of two empty lanes closes once', () {
      final two = drain(
        (log) => _Lanes(log, (self) {
          self
            ..declare('a')
            ..declare('b');
        }),
      );
      expect(two, idle);
    });

    // Held by: `enqueueJob` refusing a closed controller only when it is
    // not draining.
    test('a job put into another lane during a drain is cancelled closed', () {
      fakeAsync((async) {
        final log = <String>[];
        final controller = _Two(log);
        final gate = Completer<void>();
        SoloJob<void>? put;
        controller.a.enqueue<int, void>(key: 'a', (ctx) async {
          await gate.future;
          put = controller.b.enqueue<int, void>(key: 'put', _nothing);
        });
        async.flushMicrotasks();
        unawaited(controller.close(mode: SoloCloseMode.drain));
        gate.complete();
        async.flushMicrotasks();

        expect(put?.outcome, _cancelled<ClosedCancelReason>(started: false));
        expect(log, isNot(contains('start put')));
        expect(controller.isFinished, isTrue);
      });
    });
  });

  // Held by: a snapshot taken lane by lane, each queue just before it is
  // cleared, in the order of the lanes (the first: the job put into `b`
  // from the handler of `a` is cleared with `b`) or the other way round
  // (the second); the one running job answered with one more hop,
  // `current.cancel(...).then((_) => Future<void>.value())` (the third:
  // `cancelAll done` lands a microtask after the job's own cancel); and
  // `Future.wait` replaced by the cancel of the first running job (the
  // fourth).
  group('cancelAll', () {
    for (final (from, to) in [('a', 'b'), ('b', 'a')]) {
      test('a job put into another lane from a finish handler during '
          'cancelAll survives, from $from into $to', () {
        fakeAsync((async) {
          final log = <String>[];
          final controller = _Two(log);
          SoloLane<int> named(String name) =>
              name == 'a' ? controller.a : controller.b;
          SoloJob<void>? put;
          final removed =
              named(from).enqueue<int, void>(key: 'removed', _nothing)
                ..whenFinished((_) {
                  put = named(to).enqueue<int, void>(key: 'put', _nothing);
                });

          unawaited(controller.cancelAll());
          async.flushMicrotasks();

          expect(
            removed.outcome,
            _cancelled<ManualCancelReason>(started: false),
          );
          expect(put?.outcome, isA<Done<void>>());
          expect(log, contains('start put'));
        });
      });
    }

    test("cancelAll with one busy lane returns that job's cancel", () {
      fakeAsync((async) {
        final log = <String>[];
        final controller = _Two(log);
        final job = controller.b.enqueue<int, void>(
          key: 'b',
          (ctx) => ctx.abandonable(() => Completer<void>().future),
        );
        async.flushMicrotasks();
        log.clear();

        controller.cancelAll().then((_) => log.add('cancelAll done'));
        job.cancel().then((_) => log.add('cancel done'));
        log.add('returned');
        _ladder(log, 5);
        async.flushMicrotasks();

        expect(log, [
          'returned',
          'tick 0',
          'finish b',
          'tick 1',
          'cancelAll done',
          'cancel done',
          'tick 2',
          'tick 3',
          'tick 4',
        ]);
      });
    });

    test('cancelAll with two busy lanes completes after both', () {
      fakeAsync((async) {
        final log = <String>[];
        final controller = _Two(log);
        final gateA = Completer<void>();
        final gateB = Completer<void>();
        controller.a.enqueue<int, void>(key: 'a', _waits(gateA));
        controller.b.enqueue<int, void>(key: 'b', _waits(gateB));
        async.flushMicrotasks();
        log.clear();

        controller.cancelAll().then((_) => log.add('cancelAll done'));
        gateA.complete();
        async.flushMicrotasks();
        log.add('a is over');
        gateB.complete();
        async.flushMicrotasks();

        expect(log, ['finish a', 'a is over', 'finish b', 'cancelAll done']);
      });
    });
  });
}
