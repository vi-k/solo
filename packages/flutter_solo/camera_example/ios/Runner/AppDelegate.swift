import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CameraLights")
    else { return }
    answerLights(registrar.messenger())
  }

  /// Answers `CameraLights` of the Dart side: the `camera` plugin cannot say
  /// which cameras have a torch and a flash.
  private func answerLights(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "dev.yet_another.flutter_solo_camera_example/lights",
      binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "lights", let names = call.arguments as? [String] else {
        result(FlutterMethodNotImplemented)
        return
      }
      // The name of a camera of `camera_avfoundation` is the `uniqueID` of
      // its capture device.
      var answer: [String: [String: Bool]] = [:]
      for name in names {
        guard let device = AVCaptureDevice(uniqueID: name) else { continue }
        answer[name] = ["torch": device.hasTorch, "flash": device.hasFlash]
      }
      result(answer)
    }
  }
}
