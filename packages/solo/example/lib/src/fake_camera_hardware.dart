import 'dart:math';

import 'package:meta/meta.dart';

/// A photo returned by [FakeCameraHardware.capture].
@immutable
final class Photo {
  /// The number of this photo, counted from one.
  final int id;

  /// Creates a photo numbered [id].
  const Photo(this.id);

  @override
  bool operator ==(Object other) => other is Photo && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Photo#$id';
}

/// Asynchronous hardware with a failure listener.
final class FakeCameraHardware {
  /// How long one operation takes; a capture takes three times as long.
  final Duration latency;

  /// Set by the controller; called when the hardware reports a failure.
  void Function(Object error)? onError;

  /// Every begun and ended operation, for assertions.
  final log = <String>[];

  /// Errors thrown instead of completing, by operation name without its
  /// arguments: `open`, `close`, `zoom`, `focus`, `capture`. The failure
  /// happens after [latency], the way a real one would.
  final failures = <String, Object>{};

  int _photos = 0;

  /// Creates hardware whose operations take [latency].
  FakeCameraHardware({this.latency = const Duration(milliseconds: 10)});

  /// Opens the camera.
  Future<void> open() => _operation('open');

  /// Closes the camera.
  Future<void> close() => _operation('close');

  /// Sets the zoom.
  Future<void> setZoom(double zoom) => _operation('zoom $zoom');

  /// Sets the focus point, or restores automatic focus for `null`.
  Future<void> setFocusPoint(Point<double>? point) =>
      _operation('focus $point');

  /// Takes a photo.
  Future<Photo> capture() async {
    await _operation('capture', factor: 3);
    return Photo(++_photos);
  }

  /// Simulates a hardware failure reported from outside any job.
  void fail(Object error) => onError?.call(error);

  Future<void> _operation(String name, {int factor = 1}) async {
    log.add('$name: begin');
    await Future<void>.delayed(latency * factor);
    final error = failures[name.split(' ').first];
    if (error != null) {
      log.add('$name: failed');
      // Not a bare `throw`: the map holds any object, and real hardware
      // wrappers report whatever their SDK gave them.
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    log.add('$name: end');
  }
}
