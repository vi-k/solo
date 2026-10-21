// The camera of the last section of `doc/testing.md`, which the page links
// to: the device its controller holds, the states of that controller, a
// fake of the device that never answers on its own, and stand-ins for the
// token and the error a device's API comes with.
import 'dart:async';

/// The device, as the controller of the camera calls it.
// ignore: one_member_abstracts
abstract interface class Camera {
  /// Opens the device; cancelling [cancelToken] fails the call.
  Future<void> open({required CancelToken cancelToken});
}

/// The states of the camera.
sealed class CameraState {
  const CameraState();
}

/// The device is not open.
final class Idle extends CameraState {
  const Idle();
}

/// The device is open.
final class Connected extends CameraState {
  const Connected();
}

/// A token the way a device's API offers one: cancelling it fails the call
/// it was given to.
class CancelToken {
  final _callbacks = <void Function()>[];

  bool isCancelled = false;

  /// Calls [callback] when the token is cancelled, at once if it already is.
  void whenCancelled(void Function() callback) {
    if (isCancelled) {
      callback();
      return;
    }
    _callbacks.add(callback);
  }

  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    for (final callback in _callbacks) {
      callback();
    }
  }
}

/// What a call of the device fails with when its token is cancelled.
final class OpenCancelled implements Exception {
  const OpenCancelled();

  @override
  String toString() => 'OpenCancelled';
}

/// A camera that never opens on its own: the call waits until the test
/// says [answer], or until its token is cancelled, which fails it with
/// [OpenCancelled].
class FakeCamera implements Camera {
  Completer<void>? _opening;

  /// How many waiting calls of [open] a cancelled token has failed.
  int refused = 0;

  @override
  Future<void> open({required CancelToken cancelToken}) {
    final opening = _opening = Completer<void>();
    cancelToken.whenCancelled(() {
      if (opening.isCompleted) return;
      refused++;
      opening.completeError(const OpenCancelled(), StackTrace.current);
    });
    return opening.future;
  }

  /// The device answers the call that is waiting.
  void answer() {
    final opening = _opening;
    if (opening == null || opening.isCompleted) return;
    opening.complete();
  }
}
