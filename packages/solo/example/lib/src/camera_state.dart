import 'dart:math';

import 'package:meta/meta.dart';

/// The camera state. `Failed` would clash with `solo`'s outcome, hence
/// [Broken].
sealed class CameraState {
  /// Creates a state.
  const CameraState();
}

/// Every state but [Disposed]: the hardware can still be talked to.
sealed class NotDisposed extends CameraState {
  /// Creates a state with live hardware.
  const NotDisposed();
}

/// Created, hardware not opened yet.
final class Initial extends NotDisposed {
  /// Creates the initial state.
  const Initial();

  @override
  String toString() => 'Initial()';
}

/// Hardware is opening.
final class Preparing extends NotDisposed {
  /// Creates the opening state.
  const Preparing();

  @override
  String toString() => 'Preparing()';
}

/// Hardware is open and accepts commands.
@immutable
final class Ready extends NotDisposed {
  /// The zoom the hardware is set to.
  final double zoom;

  /// The focus point, or `null` for automatic focus.
  final Point<double>? focusPoint;

  /// Whether the preview is paused; a paused camera takes no commands.
  final bool paused;

  /// Creates a working state.
  const Ready({this.zoom = 1, this.focusPoint, this.paused = false});

  /// A copy of this state with the given fields replaced. A `null` keeps
  /// the old value, so clearing [focusPoint] needs a fresh [Ready].
  Ready copyWith({double? zoom, Point<double>? focusPoint, bool? paused}) =>
      Ready(
        zoom: zoom ?? this.zoom,
        focusPoint: focusPoint ?? this.focusPoint,
        paused: paused ?? this.paused,
      );

  @override
  bool operator ==(Object other) =>
      other is Ready &&
      other.zoom == zoom &&
      other.focusPoint == focusPoint &&
      other.paused == paused;

  @override
  int get hashCode => Object.hash(zoom, focusPoint, paused);

  @override
  String toString() =>
      'Ready(zoom: $zoom, focusPoint: $focusPoint, paused: $paused)';
}

/// The hardware reported [error]; `CameraController.reopen` recovers.
final class Broken extends NotDisposed {
  /// What the hardware reported.
  final Object error;

  /// Creates a broken state.
  const Broken(this.error);

  @override
  String toString() => 'Broken($error)';
}

/// Closed for good.
final class Disposed extends CameraState {
  /// Creates the final state.
  const Disposed();

  @override
  String toString() => 'Disposed()';
}
