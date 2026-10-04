// The attempts of "A failure after the disposal" in `doc/camera.md`,
// verbatim, in a library of their own: the first is a constructor, so its
// class is named like the example's and cannot stand beside it.
import 'package:solo/solo.dart';
import 'package:solo_example/solo_example.dart' hide CameraController;

import 'camera_page.dart';

/// The first attempt: the listener set and never taken off. The disposal
/// is the one of "Checking in the body".
base class CameraController extends Solo<CameraState>
    with CameraParts, CheckedDisposal {
  @override
  final FakeCameraHardware hw;

  CameraController(this.hw) : super(const Initial()) {
    hw.onError = (error) => externalSetState(Broken(error));
  }
}

/// The second attempt: the listener taken off where the state page stops a
/// source.
base class ClosingCameraController extends CameraController {
  ClosingCameraController(super.hw);

  @override
  void onClose() => hw.onError = null;
}
