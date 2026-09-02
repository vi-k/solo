import 'dart:math';

import 'package:solo/solo.dart';
import 'package:solo_example/solo_example.dart';

Future<void> main() async {
  SoloBase.observer = _PrintObserver();
  final camera = CameraController(FakeCameraHardware());
  await camera.init().done;
  camera
    ..setZoom(2)
    ..setFocusPoint(const Point(0.5, 0.5));
  final shot = camera.takePhoto();
  await Future<void>.delayed(const Duration(milliseconds: 35));
  await camera.dispose().done;
  print('shot: ${shot.outcome}');
  await camera.close();
}

/// Same formatting as `test/support/journal.dart`, printing each line.
final class _PrintObserver extends SoloObserver {
  static String _label(Job<Object?> job) {
    final indent = job.level == 0 ? '' : '${'>' * job.level} ';
    final description = job.describe();
    final key = job.key is Enum ? (job.key! as Enum).name : '${job.key}';
    final name = description.isEmpty ? key : '$key: $description';
    return '$indent[$name]';
  }

  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) =>
      print('${_label(job)} started');

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) {
    final outcome = job.outcome;
    final verb =
        outcome is Cancelled && !outcome.started ? 'dropped' : 'finished';
    print('${_label(job)} $verb $outcome');
  }

  @override
  void onError(
    SoloBase<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) =>
      print('${_label(job)} error $error');

  @override
  void onLog(SoloBase<Object> solo, Job<Object?> job, String message) =>
      print('${_label(job)} log $message');

  @override
  void onChange(SoloBase<Object> solo, Object previous, Object current) =>
      print('state: $current');

  @override
  void onClose(SoloBase<Object> solo) => print('closed');
}
