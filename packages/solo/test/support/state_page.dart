// The code of `doc/state.md` about the camera, verbatim, less the first
// attempts: every piece of those blocks is a run of lines of this file, and
// `state_rakes_test.dart` and `state_external_recipe_test.dart` run it. The
// page declares `Camera` final, so what the tests need of it beside the page's
// own members stands inside the class, between the page's pieces.
import 'dart:async';

import 'package:meta/meta.dart';
import 'package:solo/solo.dart';

import 'state_camera_stubs.dart';

final class Camera extends Solo<CameraState> with SoloStream {
  final Device device;
  late final StreamSubscription<bool> _link;

  Camera(this.device) : super(const Ready()) {
    _link = device.connection.listen((connected) {
      // The device has already disconnected: reflect the fact at once
      // instead of queueing a job that would wait behind the current one.
      if (!connected) {
        externalSetState(const Disconnected());
      }
    });
  }

  Job<void> record() => enqueue<Ready, void>(
    key: 'record',
    canStart: (state) => state.free > 0,
    keepWhile: (state) => !state.paused,
    (ctx) => ctx.each(device.frames, (child, frame) async {
      await child.join(() => store(frame));
    }).value,
  );

  Job<void> zoomIn() => enqueue<Ready, void>((ctx) async {
    // A read is a checkpoint: cancellation and the rules are checked.
    final state = ctx.state;

    // The body's only way to write, and it is synchronous.
    ctx.emit(state.copyWith(zoom: state.zoom + 1));
  });

  Job<void> switchOn(int zoom) => enqueue<CameraState, void>(
    canStart: (state) => state is Off,
    (ctx) async {
      // W is every state, so after each wait the body names the one
      // it needs.
      await ctx.join(device.powerUp);
      ctx.stateAs<Off>();
      // ignore: cascade_invocations
      ctx.emit(const Ready());

      await ctx.join(() => device.setZoom(zoom));
      ctx.emit(ctx.stateAs<Ready>().copyWith(zoom: zoom));
    },
  );

  /// Not on the page: a fact of the device other than the connection, the
  /// way a source of the application reports one.
  void reflect(CameraState state) => externalSetState(state);

  /// Not on the page: the pause written as a job of the queue.
  Job<void> pauseAsJob() => enqueue<Ready, void>(
    key: 'pause',
    (ctx) async => ctx.emit(ctx.state.copyWith(paused: true)),
  );

  /// Not on the page: a job whose rules require the connection, waiting for
  /// an answer the device gives only when the test says so.
  Job<void> waitForAnswer({bool cancellable = true, bool joined = false}) =>
      enqueue<Ready, void>(key: 'answer', cancellable: cancellable, (
        ctx,
      ) async {
        try {
          await (joined
              ? ctx.join(() => device.answer.future)
              : ctx.abandonable(() => device.answer.future));
        } on Cancelled {
          stage.trace.add('the body resumed');
          rethrow;
        }
      });

  /// Not on the page: the next root job of the queue.
  Job<void> next() => enqueue<CameraState, void>(
    key: 'next',
    (ctx) async => stage.trace.add('the next job started'),
  );

  // Called once, when the last job is over: nothing in the queue needs
  // to hear the device any more.
  @override
  void onClose() => unawaited(_link.cancel());
}

/// The block under "Observing state": a read, a listener and a subscription
/// to the stream.
StreamSubscription<CameraState> observing(Camera camera) {
  // A read at any moment.
  print(camera.currentState);

  // Every change, synchronously, inside the change itself. The listener
  // reads the new state itself, so nothing it reads can be stale.
  camera.addListener(() => print(camera.currentState));

  // Every update, in order, on a microtask. The initial state is not
  // replayed, and an equal state still produces an event. Needs
  // `with SoloStream` on the controller — see the table below.
  final subscription = camera.stream.listen(print);
  return subscription;
}

/// A controller that writes every change to a log.
class Logged<S extends Object> extends Solo<S> {
  final void Function(String line) write;

  Logged(super.initialState, this.write);

  @protected
  @override
  void publish(S previous, S current) {
    super.publish(previous, current);
    try {
      write('$previous -> $current');
    } on Object catch (error, stackTrace) {
      // The state has changed by now, and the rules of the running jobs
      // are asked about it all the same. An error let out of here would
      // reach whoever wrote the state, as if the write had failed.
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }
}
