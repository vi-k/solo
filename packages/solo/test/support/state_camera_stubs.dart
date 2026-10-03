// What the camera code of `doc/state.md` takes for granted: the states of
// the camera, the device and the storage of frames. Each test sets the
// stage first, so storing a frame can take its time.
import 'dart:async';

/// How the stubs behave in the test at hand, and what they saw.
final class Stage {
  /// What the storage did, in order.
  final trace = <String>[];

  /// How long one frame takes to store, in milliseconds.
  int storeTake = 0;
}

Stage stage = Stage();

/// The states of the camera.
sealed class CameraState {
  const CameraState();
}

/// The camera is on and takes commands.
final class Ready extends CameraState {
  /// Frames the storage still has room for.
  final int free;

  /// Whether the device has reported a pause.
  final bool paused;

  final int zoom;

  const Ready({this.free = 8, this.paused = false, this.zoom = 1});

  Ready copyWith({int? free, bool? paused, int? zoom}) => Ready(
        free: free ?? this.free,
        paused: paused ?? this.paused,
        zoom: zoom ?? this.zoom,
      );

  @override
  String toString() => 'Ready(free: $free, paused: $paused, zoom: $zoom)';
}

/// The device is gone.
final class Disconnected extends CameraState {
  const Disconnected();

  @override
  String toString() => 'Disconnected';
}

/// The camera is switched off: a state outside `Ready` that is no fact of
/// the connection.
final class Off extends CameraState {
  const Off();

  @override
  String toString() => 'Off';
}

/// The hardware: a stream of frames, the state of the connection, and an
/// answer it gives only when the test says so.
final class Device {
  final _frames = StreamController<int>.broadcast();
  final _connection = StreamController<bool>.broadcast();

  /// The answer a job waits for, and the device never gives on its own.
  final answer = Completer<void>();

  Stream<int> get frames => _frames.stream;

  Stream<bool> get connection => _connection.stream;

  /// Whether anybody listens to [connection].
  bool get isListened => _connection.hasListener;

  /// The device sends a frame.
  void frame(int number) => _frames.add(number);

  /// The frames end.
  void endFrames() => unawaited(_frames.close());

  /// The device reports that the connection is lost.
  void drop() => _connection.add(false);

  /// Closes both streams. Not awaited: a controller nobody listens to
  /// hands back a future of the root zone, which fake time never reaches.
  void dispose() {
    unawaited(_frames.close());
    unawaited(_connection.close());
  }
}

/// Stores one frame.
Future<void> store(int frame) async {
  stage.trace.add('store $frame begins');
  if (stage.storeTake > 0) {
    await Future<void>.delayed(Duration(milliseconds: stage.storeTake));
  }
  stage.trace.add('store $frame ends');
}
