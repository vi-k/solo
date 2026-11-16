import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_solo_camera_example/camera_lights.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;

  const back = CameraDescription(
    name: '0',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );
  const front = CameraDescription(
    name: '1',
    lensDirection: CameraLensDirection.front,
    sensorOrientation: 270,
  );
  const unknown = CameraDescription(
    name: '9',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );

  /// The channel answers with [handler]; `null` leaves it without one.
  void answer(Future<Object?> Function(MethodCall call)? handler) =>
      messenger.setMockMethodCallHandler(CameraLights.channel, handler);

  tearDown(() => answer(null));

  test('one call with the names, and the answer of each camera', () async {
    final calls = <MethodCall>[];
    answer((call) async {
      calls.add(call);
      return {
        '0': {'torch': true, 'flash': true},
        '1': {'torch': false, 'flash': false},
      };
    });
    final lights = await CameraLights.ask([back, front, unknown]);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'lights');
    expect(calls.single.arguments, ['0', '1', '9']);
    expect((lights.torch(back), lights.flash(back)), (true, true));
    expect((lights.torch(front), lights.flash(front)), (false, false));
    // A camera the platform left out: no torch, and the flash.
    expect((lights.torch(unknown), lights.flash(unknown)), (false, true));
  });

  for (final (name, handler)
      in <(String, Future<Object?> Function(MethodCall)?)>[
        ('no handler', null),
        ('a failure', (call) async => throw PlatformException(code: 'error')),
        ('no answer', (call) async => null),
      ]) {
    test('$name: no torch, and the flash on every camera', () async {
      answer(handler);
      final lights = await CameraLights.ask([back, front]);

      for (final camera in [back, front]) {
        expect(lights.torch(camera), isFalse);
        expect(lights.flash(camera), isTrue);
      }
    });
  }
}
