@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/state_camera_stubs.dart' as camera;
import 'support/state_page.dart' as page;

/// The `Camera` recipe of `doc/state.md` and the closing around it.
///
/// The controller is the page's own, from `support/state_page.dart`. The
/// page makes three promises about its closing. The moment: the
/// subscription is cancelled in `onClose`, once every job is over, so the
/// source goes on publishing for as long as the engine runs, a drain
/// included. The price of the tidier-looking moment, stopping the source
/// when `close` is called: a job the device could have freed holds the
/// close. And the guard: a callback that awaits before it writes checks
/// `isFinished` after its last `await`, where the callback of the recipe
/// needs no check at all.
///
/// The recipe once stopped the subscription in an `async` override of
/// `close`, after `super.close()`. The moment was right and the promise of
/// `close` was not: every call ran the override again and handed back a
/// future of its own. The first test holds the hook to that promise.

/// The same controller with the tidier-looking moment: the source is
/// stopped when `close` is called.
final class _TidyCamera extends Solo<camera.CameraState> {
  final camera.Device device;
  late final StreamSubscription<bool> _link;

  _TidyCamera(this.device) : super(const camera.Ready()) {
    _link = device.connection.listen((connected) {
      if (!connected) {
        externalSetState(const camera.Disconnected());
      }
    });
  }

  Job<void> waitForAnswer({bool cancellable = true}) => run<camera.Ready, void>(
        key: 'answer',
        cancellable: cancellable,
        (ctx) => ctx.abandonable(() => device.answer.future),
      );

  @override
  Future<void> close({SoloCloseMode mode = SoloCloseMode.cancel}) {
    unawaited(_link.cancel());
    return super.close(mode: mode);
  }
}

/// A camera whose callback awaits [reason] before it writes, and checks
/// `isFinished` on one side of that `await` or the other.
final class _AwaitingCamera extends Solo<camera.CameraState> {
  final camera.Device device;
  final Completer<void> reason;
  final bool checksAfterTheAwait;
  final trace = <String>[];
  late final StreamSubscription<bool> _link;

  _AwaitingCamera(
    this.device,
    this.reason, {
    required this.checksAfterTheAwait,
  }) : super(const camera.Ready()) {
    _link = device.connection.listen((connected) async {
      if (connected) {
        return;
      }
      if (!checksAfterTheAwait && isFinished) {
        return;
      }
      await reason.future;
      if (checksAfterTheAwait && isFinished) {
        trace.add('the write was left out');
        return;
      }
      try {
        externalSetState(const camera.Disconnected());
        trace.add('the write went through');
      } on Object catch (error) {
        trace.add('the write threw: $error');
      }
    });
  }

  @override
  void onClose() => unawaited(_link.cancel());
}

/// Runs [body] under fake time in a zone of its own and returns what
/// reached that zone uncaught. Expectations go after the call: inside the
/// zone a failed one would land in the handler.
List<String> _zone(void Function(FakeAsync async) body) {
  final errors = <String>[];
  runZonedGuarded(
    () => fakeAsync(body),
    (error, stackTrace) => errors.add('$error'),
  );
  return errors;
}

void main() {
  setUp(() => camera.stage = camera.Stage());

  test('every close is the one close, and the link goes once', () {
    fakeAsync((async) {
      final device = camera.Device();
      final cam = page.Camera(device);
      final first = cam.close();
      final second = cam.close(mode: SoloCloseMode.drain);

      expect(
        identical(first, second),
        isTrue,
        reason: 'repeated calls return the same future, as close promises',
      );
      expect(device.isListened, isTrue, reason: 'no job is over yet');
      async.flushMicrotasks();
      expect(cam.isFinished, isTrue);
      expect(device.isListened, isFalse);
      device.dispose();
      async.flushTimers();
    });
  });

  test('a drain hears the device, and the job it frees lets close finish', () {
    fakeAsync((async) {
      final device = camera.Device();
      final cam = page.Camera(device);
      final job = cam.waitForAnswer();
      async.flushMicrotasks();

      var closed = false;
      cam.close(mode: SoloCloseMode.drain).then((_) => closed = true);
      async.elapse(const Duration(hours: 1));
      expect(cam.isClosed, isTrue);
      expect(
        cam.isFinished,
        isFalse,
        reason: 'false for as long as the engine runs, a drain included',
      );
      expect(device.isListened, isTrue, reason: 'the drain still hears it');

      device.drop();
      async.flushMicrotasks();
      expect(
        closed,
        isTrue,
        reason: 'the disconnection freed the queue the drain was waiting for',
      );
      expect(cam.isFinished, isTrue, reason: 'true once the state is final');
      expect(
        (job.outcome! as Cancelled).reason,
        isA<RulesCancelReason>(),
        reason: 'the state rule cancelled it, not the close',
      );
      expect(cam.currentState, isA<camera.Disconnected>());
      device.dispose();
      async.flushTimers();
    });
  });

  test('a job that refuses the close is freed by the device all the same', () {
    fakeAsync((async) {
      final device = camera.Device();
      final cam = page.Camera(device);
      final job = cam.waitForAnswer(cancellable: false);
      async.flushMicrotasks();

      var closed = false;
      cam.close().then((_) => closed = true);
      async.elapse(const Duration(hours: 1));
      expect(closed, isFalse, reason: 'close waits for a job it cannot stop');

      device.drop();
      async.flushMicrotasks();
      expect(closed, isTrue);
      expect(
        (job.outcome! as Cancelled).reason,
        isA<RulesCancelReason>(),
        reason: 'the rule freed it, so it is not Cancelled(closed)',
      );
      device.dispose();
      async.flushTimers();
    });
  });

  test('once onClose has run the callback is not called, and nothing throws',
      () {
    late page.Camera cam;
    late camera.Device device;
    final zone = _zone((async) {
      device = camera.Device();
      cam = page.Camera(device);
      // One report with the close, one right behind it, one after the end.
      cam.close().ignore();
      device.drop();
      scheduleMicrotask(device.drop);
      async.flushMicrotasks();
      device.drop();
      async.flushMicrotasks();
      device.dispose();
      async.flushTimers();
    });

    expect(cam.isFinished, isTrue);
    expect(device.isListened, isFalse);
    expect(
      cam.currentState,
      isA<camera.Ready>(),
      reason: 'the state a controller stops at is the state it keeps',
    );
    expect(zone, isEmpty, reason: 'no write arrived after the end');
  });

  test('stopping the source at the call costs the drain', () {
    fakeAsync((async) {
      final device = camera.Device();
      final cam = _TidyCamera(device);
      final job = cam.waitForAnswer();
      async.flushMicrotasks();

      var closed = false;
      cam.close(mode: SoloCloseMode.drain).then((_) => closed = true);
      device.drop();
      async.elapse(const Duration(hours: 1));
      expect(
        closed,
        isFalse,
        reason: 'the link is gone, so the disconnection reaches nobody',
      );
      expect(job.outcome, isNull, reason: 'the job is still waiting');
      expect(cam.currentState, isA<camera.Ready>());

      // Let it end: the answer the device was never going to give.
      device.answer.complete();
      async.flushMicrotasks();
      expect(closed, isTrue);
      device.dispose();
      async.flushTimers();
    });
  });

  test('stopping the source at the call leaves a refusing job waiting', () {
    fakeAsync((async) {
      final device = camera.Device();
      final cam = _TidyCamera(device);
      final job = cam.waitForAnswer(cancellable: false);
      async.flushMicrotasks();

      var closed = false;
      cam.close().then((_) => closed = true);
      device.drop();
      async.elapse(const Duration(hours: 1));
      expect(closed, isFalse, reason: 'nothing frees the job any more');
      expect(job.outcome, isNull);

      device.answer.complete();
      async.flushMicrotasks();
      expect(closed, isTrue);
      expect('${job.outcome}', 'Done(null)');
      device.dispose();
      async.flushTimers();
    });
  });

  group('a callback that awaits before it writes', () {
    String after({required bool checksAfterTheAwait, required bool closes}) {
      late _AwaitingCamera cam;
      fakeAsync((async) {
        final device = camera.Device();
        final reason = Completer<void>();
        cam = _AwaitingCamera(
          device,
          reason,
          checksAfterTheAwait: checksAfterTheAwait,
        );
        device.drop();
        async.flushMicrotasks();
        if (closes) {
          cam.close().ignore();
          async.flushMicrotasks();
        }
        reason.complete();
        async.flushMicrotasks();
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
      return cam.trace.single;
    }

    test('a check made before the await goes stale, and the write throws', () {
      expect(
        after(checksAfterTheAwait: false, closes: true),
        'the write threw: Bad state: _AwaitingCamera has finished closing, '
        'cannot set state',
      );
    });

    test('checked after its last await, the write is left out', () {
      expect(
        after(checksAfterTheAwait: true, closes: true),
        'the write was left out',
      );
    });

    test('while the engine runs, either callback writes', () {
      expect(
        after(checksAfterTheAwait: false, closes: false),
        'the write went through',
      );
      expect(
        after(checksAfterTheAwait: true, closes: false),
        'the write went through',
      );
    });
  });
}
