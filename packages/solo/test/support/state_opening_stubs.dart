// What the opening of "Reading and updating state" in `doc/state.md` names
// from the camera page: the key and the first two states of `init`. The
// names match `doc/camera.md`, so the line `Solo.debug` prints is the line
// the page quotes.

/// The keys of the camera jobs.
enum CameraKey {
  /// The job that opens the camera.
  init,
}

/// A state of the camera.
sealed class CameraState {
  const CameraState();
}

/// The camera before anything has opened it.
final class Initial extends CameraState {
  const Initial();

  @override
  String toString() => 'Initial()';
}

/// The camera while its hardware opens.
final class Preparing extends CameraState {
  const Preparing();

  @override
  String toString() => 'Preparing()';
}

/// The camera once its hardware is open.
final class Ready extends CameraState {
  const Ready();

  @override
  String toString() => 'Ready()';
}
