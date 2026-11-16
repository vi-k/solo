import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

/// What each camera of the phone can light: a torch, and a flash for a
/// picture.
///
/// The plugin cannot say, so the app asks the platform itself, through a
/// channel of its own: `MainActivity.kt` answers with the flash unit of the
/// camera, which is its torch as well, and `AppDelegate.swift` with whether
/// the capture device has a torch and a flash. The camera screen shows the
/// button of the flash and of the torch by this answer, and the controllers
/// call neither on a camera without it.
final class CameraLights {
  /// The channel of the answer, named after the id of the app.
  static const channel = MethodChannel(
    'dev.yet_another.flutter_solo_camera_example/lights',
  );

  /// No answer: no camera has a torch, and every camera has a flash.
  ///
  /// A torch asked of a camera without one takes the screen to `Broken` on
  /// a Galaxy A55, while a mode of the flash is a setting every camera of
  /// both phones took.
  static const none = CameraLights._({});

  final Map<String, ({bool torch, bool flash})> _cameras;

  const CameraLights._(this._cameras);

  /// Asks the platform about [cameras], by their names, in one call.
  ///
  /// A platform without the handler of the [channel], as under
  /// `flutter test`, or one that fails, gives [none]; a camera it does not
  /// know is left out of the answer and goes by [none] alone.
  static Future<CameraLights> ask(List<CameraDescription> cameras) async {
    final Map<String, Object?>? answer;
    try {
      answer = await channel.invokeMapMethod<String, Object?>('lights', [
        for (final camera in cameras) camera.name,
      ]);
    } on PlatformException {
      return none;
    } on MissingPluginException {
      return none;
    }
    return CameraLights._({
      for (final MapEntry(:key, :value) in (answer ?? const {}).entries)
        if (value case {'torch': final bool torch, 'flash': final bool flash})
          key: (torch: torch, flash: flash),
    });
  }

  /// Whether [camera] has a torch.
  bool torch(CameraDescription camera) => _cameras[camera.name]?.torch ?? false;

  /// Whether [camera] has a flash for a picture.
  bool flash(CameraDescription camera) => _cameras[camera.name]?.flash ?? true;
}
