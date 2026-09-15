@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

/// The `Camera` recipe from `doc/state.md`, written as the page shows it.
///
/// The page makes two promises about it that nothing else here guards. One
/// is the guard itself: `isFinished` lets the source keep publishing for as
/// long as the engine runs, a drain included. The other is the order —
/// `super.close()` first and the subscription after it — and the page names
/// its price, so the price is pinned here too: the tidier-looking order
/// leaves `close` waiting for a job the device could have freed.
///
/// Real time rather than `fakeAsync`: the recipe ends with
/// `subscription.cancel()`, and the future that returns completes in the
/// root zone, where a fake clock cannot reach it. The waits here are the
/// short ones a disconnection needs, not timers of a domain.

sealed class CameraState {
  const CameraState();
}

final class Ready extends CameraState {
  const Ready();
}

final class Disconnected extends CameraState {
  const Disconnected();
}

final class Device {
  final _connection = StreamController<bool>.broadcast();

  /// The answer that never comes on its own.
  final answer = Completer<void>();

  Stream<bool> get connection => _connection.stream;

  void drop() => _connection.add(false);

  Future<void> dispose() => _connection.close();
}

final class Camera extends Solo<CameraState> {
  final Device device;
  late final StreamSubscription<bool> _link;

  Camera(this.device) : super(const Ready()) {
    _link = device.connection.listen((connected) {
      if (!connected) {
        reflectDisconnection();
      }
    });
  }

  /// What the listener does, reachable after the subscription is gone.
  void reflectDisconnection() {
    if (!isFinished) {
      externalSetState(const Disconnected());
    }
  }

  /// Waits for an answer the device will never give on its own.
  Job<void> waitForAnswer({bool cancellable = true}) => run<Ready, void>(
        key: 'answer',
        cancellable: cancellable,
        (ctx) => ctx.wait(() => device.answer.future),
      );

  @override
  Future<void> close({SoloCloseMode mode = SoloCloseMode.cancel}) async {
    await super.close(mode: mode);
    await _link.cancel();
  }
}

/// The same controller with the tidier-looking order.
final class TidyCamera extends Camera {
  TidyCamera(super.device);

  @override
  Future<void> close({SoloCloseMode mode = SoloCloseMode.cancel}) async {
    await _link.cancel();
    await super.close(mode: mode);
  }
}

void main() {
  test('a drain hears the device, and the job it frees lets close finish',
      () async {
    final device = Device();
    final camera = Camera(device);
    final job = camera.waitForAnswer();
    await pump();

    final closing = camera.close(mode: SoloCloseMode.drain);
    device.drop();
    await closing;

    expect(
      camera.isFinished,
      isTrue,
      reason: 'the disconnection freed the queue the drain was waiting for',
    );
    expect(job.outcome, isA<Cancelled>());
    expect(
      (job.outcome! as Cancelled).reason,
      isA<RulesCancelReason>(),
      reason: 'the state rule cancelled it, not the close',
    );
    expect(camera.currentState, isA<Disconnected>());
    await device.dispose();
  });

  test('a job that refuses the close is freed by the device all the same',
      () async {
    final device = Device();
    final camera = Camera(device);
    final job = camera.waitForAnswer(cancellable: false);
    await pump();

    final closing = camera.close();
    await pump();
    expect(
      camera.isFinished,
      isFalse,
      reason: 'close waits for a job it cannot stop',
    );

    device.drop();
    await closing;

    expect(camera.isFinished, isTrue);
    expect(
      (job.outcome! as Cancelled).reason,
      isA<RulesCancelReason>(),
      reason: 'the rule freed it, so it is not Cancelled(closed)',
    );
    await device.dispose();
  });

  test('a disconnection after the end is refused, not thrown', () async {
    final device = Device();
    final camera = Camera(device);
    await camera.close();
    expect(camera.isFinished, isTrue);

    // The subscription is gone with the close, so the recipe's own link
    // cannot deliver this one. A source that kept a reference can, and the
    // guard is what stands between it and a `StateError`.
    camera.reflectDisconnection();

    expect(
      camera.currentState,
      isA<Ready>(),
      reason: 'the state a controller stops at is the state it keeps',
    );
    await device.dispose();
  });

  test('stopping the source first costs the drain', () async {
    final device = Device();
    final camera = TidyCamera(device);
    final job = camera.waitForAnswer();
    await pump();

    final closing = camera.close(mode: SoloCloseMode.drain);
    device.drop();
    await pump();

    expect(
      camera.isFinished,
      isFalse,
      reason: 'the link is gone, so the disconnection reaches nobody',
    );
    expect(job.outcome, isNull, reason: 'the job is still waiting');
    expect(camera.currentState, isA<Ready>());

    // Let it end: the answer the device was never going to give.
    device.answer.complete();
    await closing;
    expect(camera.isFinished, isTrue);
    await device.dispose();
  });
}

/// Lets the engine and the device stream have their turns.
Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));
