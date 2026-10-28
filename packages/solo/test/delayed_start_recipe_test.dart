@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/jobs_page.dart';
import 'support/jobs_stubs.dart';
import 'support/test_solo.dart';

/// The self-timer of `doc/jobs.md` that works: a countdown the controller
/// owns, outside its queue.
///
/// The code is the page's own, verbatim in `support/jobs_page.dart`. Every
/// row of the page's table of cases is pinned here, and so are the two
/// things the prose under the table says: a debounce accumulator parts from
/// the table in two rows, and a signal that fails after the countdown is
/// cancelled reaches the zone unless the call catches it. The two attempts
/// the page shows before it are in `jobs_rakes_test.dart`.

const _second = Duration(seconds: 1);

/// The accumulator the page names for a delay that is the same on every
/// call.
final class _DebounceCamera extends Solo<CameraState>
    with OpenSolo<CameraState>, Workbench {
  _DebounceCamera() : super(const Ready());

  late final _shot = accumulate<Ready, void, void>(
    (ctx, _) => ctx.join(camera.shoot),
    merge: (_, _) {},
    timing: AccumulationTiming.debounce(_second * 10),
  );

  Job<void> shootIn() => _shot.add(null);
}

/// A signal and a countdown on it, made in a zone whose errors go to
/// [errors]: a future does not carry its error out of the zone it was made
/// in, so the two are made in the same one.
(Completer<void>, Job<T>) _onSignal<T>(
  List<Object> errors,
  Future<T> Function(Future<void> signal) wait,
) {
  late final Completer<void> signal;
  late final Job<T> countdown;
  runZonedGuarded(() {
    signal = Completer<void>();
    countdown = Job<T>((ctx) => ctx.abandonable(() => wait(signal.future)))
      ..ignoreFailure();
  }, (error, _) => errors.add(error));
  return (signal, countdown);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() => stage = Stage());

  group('the cases', () {
    test('shootIn, then a zoom: the zoom goes at once, the shot at ten', () {
      fakeAsync((async) {
        final camera = SelfTimerController()..shootIn(_second * 10);
        async.elapse(_second);
        camera.work('zoom', inReady: true);
        async.elapse(_second);

        expect(stage.trace, ['zoom starts', 'zoom ends']);
        async.elapse(_second * 8);
        expect(stage.trace.last, 'shot begins');
        async.elapse(_second);
        expect(stage.trace.last, 'shot ends');
        expect(camera.isCounting, isFalse);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('shootIn again: the countdown starts over, one shot', () {
      fakeAsync((async) {
        final camera = SelfTimerController()..shootIn(_second * 10);
        async.elapse(_second * 5);
        camera.shootIn(_second * 10);
        async.elapse(_second * 9);

        expect(stage.trace, isEmpty, reason: 'fourteen seconds in');
        async.elapse(_second * 2);
        expect(stage.trace, ['shot begins', 'shot ends']);
        async.elapse(_second * 20);
        expect(stage.trace, ['shot begins', 'shot ends']);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('the end of the old countdown leaves the new one to cancelAll()', () {
      fakeAsync((async) {
        final camera = SelfTimerController()..shootIn(_second * 10);
        async.elapse(_second * 5);
        camera.shootIn(_second * 10);
        async.elapse(_second);

        expect(camera.isCounting, isTrue);
        camera.cancelAll().ignore();
        async.elapse(_second * 20);
        expect(stage.trace, isEmpty);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('cancelAll() during the countdown: no shot', () {
      fakeAsync((async) {
        final camera = SelfTimerController()..shootIn(_second * 10);
        async.elapse(_second * 5);
        camera.cancelAll().ignore();
        async.flushMicrotasks();

        expect(camera.isCounting, isFalse);
        expect(async.pendingTimers, isEmpty);
        async.elapse(_second * 20);
        expect(stage.trace, isEmpty);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('cancelAll() completes once the countdown has ended', () {
      fakeAsync((async) {
        final camera = SelfTimerController()..shootIn(_second * 10);
        async.elapse(_second * 5);
        bool? countingAtTheEnd;
        camera.cancelAll().then((_) => countingAtTheEnd = camera.isCounting);
        async.flushMicrotasks();

        expect(countingAtTheEnd, isFalse);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('cancelAll() still clears the queue and cancels the running job', () {
      fakeAsync((async) {
        final camera = SelfTimerController()..shootIn(_second * 10);
        final countdown = camera.countdown!;
        final running = camera.work('running', take: 3000);
        final queued = camera.work('queued');
        async.elapse(_second);
        camera.cancelAll(reason: const ClosedCancelReason()).ignore();
        async.flushMicrotasks();

        expect('${countdown.outcome}', 'Cancelled(closed)');
        expect('${running.outcome}', 'Cancelled(closed)');
        expect('${queued.outcome}', 'Cancelled(closed)');
        expect(camera.isCounting, isFalse);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('queue.clear() during the countdown: the shot is taken', () {
      fakeAsync((async) {
        final camera = SelfTimerController()..shootIn(_second * 10);
        async.elapse(_second * 5);
        camera.queue.clear();
        async.elapse(_second * 6);

        expect(stage.trace, ['shot begins', 'shot ends']);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('close() during the countdown: no shot, and no timer left', () {
      fakeAsync((async) {
        final camera = SelfTimerController()..shootIn(_second * 10);
        async.elapse(_second * 5);
        camera.close().ignore();
        async.flushMicrotasks();

        expect(camera.isFinished, isTrue);
        expect(async.pendingTimers, isEmpty);
        async.elapse(_second * 20);
        expect(stage.trace, isEmpty);
      });
    });

    test('a draining close() takes the countdown once the queue has run', () {
      fakeAsync((async) {
        final camera = SelfTimerController()..shootIn(_second * 10);
        async.elapse(_second);
        camera.work('last batch', take: 2000, inReady: true);
        camera.close(mode: SoloCloseMode.drain).ignore();
        async.elapse(_second * 3);

        expect(stage.trace, ['last batch starts', 'last batch ends']);
        expect(camera.isFinished, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a countdown that ends during a draining close() takes no shot', () {
      fakeAsync((async) {
        final camera = SelfTimerController()
          ..shootIn(_second * 2)
          ..work('last batch', take: 5000, inReady: true);
        camera.close(mode: SoloCloseMode.drain).ignore();
        async.elapse(_second * 3);

        expect(camera.isCounting, isFalse);
        async.elapse(_second * 3);
        expect(stage.trace, ['last batch starts', 'last batch ends']);
        expect(camera.isFinished, isTrue);
      });
    });

    test('shootIn after close(): nothing', () {
      fakeAsync((async) {
        final camera = SelfTimerController();
        camera.close().ignore();
        async.flushMicrotasks();
        camera.shootIn(_second * 10);

        expect(camera.isCounting, isFalse);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('shootIn while close() waits for the running job: no timer left', () {
      fakeAsync((async) {
        final camera = SelfTimerController();
        stage.commandTake = 3000;
        camera.shoot();
        async.flushMicrotasks();
        camera.close().ignore();
        camera.shootIn(_second);

        expect(camera.isCounting, isFalse);
        async.flushTimers();

        expect(camera.isFinished, isTrue);
        expect(stage.trace, ['shot begins', 'shot ends']);
      });
    });
  });

  group('a debounce accumulator', () {
    test('lets the zoom go and starts its window over on another add', () {
      fakeAsync((async) {
        final camera = _DebounceCamera()..shootIn();
        async.elapse(_second);
        camera.work('zoom', inReady: true);
        async.elapse(_second * 4);
        camera.shootIn();
        async.elapse(_second * 9);

        expect(stage.trace, ['zoom starts', 'zoom ends'], reason: '14 s in');
        async.elapse(_second * 2);
        expect(stage.trace.skip(2), ['shot begins', 'shot ends']);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('is dropped by cancelAll(), close() and queue.clear()', () {
      fakeAsync((async) {
        final cancelled = _DebounceCamera();
        final closed = _DebounceCamera();
        final cleared = _DebounceCamera();
        final shots = [
          cancelled.shootIn(),
          closed.shootIn(),
          cleared.shootIn(),
        ];
        async.elapse(_second * 5);
        cancelled.cancelAll().ignore();
        closed.close().ignore();
        cleared.queue.clear();
        async.elapse(_second * 20);

        expect(
          ['${shots[0].outcome}', '${shots[1].outcome}', '${shots[2].outcome}'],
          ['Cancelled(manual)', 'Cancelled(closed)', 'Cancelled(manual)'],
        );
        expect(stage.trace, isEmpty);
        cancelled.close().ignore();
        cleared.close().ignore();
        async.flushTimers();
      });
    });

    test('waits its window out under a draining close() and shoots', () {
      fakeAsync((async) {
        final camera = _DebounceCamera()..shootIn();
        async.elapse(_second * 5);
        camera.close(mode: SoloCloseMode.drain).ignore();
        async.elapse(_second * 20);

        expect(stage.trace, ['shot begins', 'shot ends']);
        expect(camera.isFinished, isTrue);
      });
    });
  });

  group('a countdown on a signal', () {
    test(
      'a failure after the cancel reaches the zone past ignoreFailure()',
      () async {
        final errors = <Object>[];
        final (signal, countdown) = _onSignal(errors, (signal) => signal);
        await _settle();
        await countdown.cancel();
        signal.completeError(StateError('offline'));
        await _settle();

        expect('${countdown.outcome}', 'Cancelled(manual)');
        expect(errors, [isStateError]);
      },
    );

    test('a failure caught inside the call reaches nobody', () async {
      final errors = <Object>[];
      final (signal, countdown) = _onSignal(
        errors,
        (signal) => signal.then((_) => true, onError: (_, _) => false),
      );
      await _settle();
      await countdown.cancel();
      signal.completeError(StateError('offline'));
      await _settle();

      expect('${countdown.outcome}', 'Cancelled(manual)');
      expect(errors, isEmpty);
    });

    test(
      'a failure caught in time ends the countdown with the value',
      () async {
        final errors = <Object>[];
        final (signal, countdown) = _onSignal(
          errors,
          (signal) => signal.then((_) => true, onError: (_, _) => false),
        );
        await _settle();
        signal.completeError(StateError('offline'));
        await _settle();

        expect('${countdown.outcome}', 'Done(false)');
        expect(errors, isEmpty);
      },
    );
  });
}
