// What the code of `doc/testing.md` takes for granted: the device of its
// last section, and what stands between a test of the page and the runner.
//
// The code of the page is tests. In the files that hold it `test` is the
// function below, not the one of `package:test`: it keeps the name and the
// body it was given instead of handing them to the runner, and
// `testing_rakes_test` decides how each one runs — as a test of the suite,
// under the name the page gives it, or as the body of a test case of its
// own, where a test that is meant to fail can fail and be looked at.
import 'dart:async';

/// A test of the page: what its `test(name, body)` was given.
typedef PageTest = ({String name, FutureOr<void> Function() body});

/// Stands in for `test` of `package:test` in the files of the page's code.
PageTest test(String name, FutureOr<void> Function() body) =>
    (name: name, body: body);

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

/// A token the way a device SDK offers one: cancelling it fails the call
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

/// A camera that never opens on its own: the call waits until the test
/// says [answer], or until its token is cancelled, which fails it.
class FakeCamera {
  Completer<void>? _opening;

  bool isOpen = false;

  /// How many calls of [open] a cancelled token has failed.
  int refused = 0;

  Future<void> open({required CancelToken cancelToken}) {
    final opening = _opening = Completer<void>();
    cancelToken.whenCancelled(() {
      if (opening.isCompleted) return;
      refused++;
      opening.completeError(StateError('open cancelled'), StackTrace.current);
    });
    return opening.future;
  }

  /// The device answers the call that is waiting.
  void answer() {
    final opening = _opening;
    if (opening == null || opening.isCompleted) return;
    isOpen = true;
    opening.complete();
  }
}
