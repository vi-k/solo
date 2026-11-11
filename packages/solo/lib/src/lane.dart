part of 'solo.dart';

/// What a controller keeps once for every line of its root jobs: the queue,
/// the running root job and the job whose start rules are being asked.
///
/// A [Solo] has exactly one. Everything else — the state, the pump, the
/// listeners, the timers and closing — belongs to the [controller] and is
/// shared by its cores.
final class _SoloLaneCore<S extends Object> {
  /// The controller whose pump steps this core.
  final SoloController<S> controller;

  /// What the debug lines call this core; `null` for the core of a [Solo].
  final String? name;

  /// The root jobs waiting for this core.
  late final _SoloQueue<S> queue = _SoloQueue<S>(this);

  /// The running root job of this core.
  _SoloJob<S, S, Object?>? current;

  /// The job the pump holds while it asks its start rules: taken off the
  /// queue, not started, not yet [current].
  ///
  /// The rules are the caller's code and may cancel everything or close
  /// the controller, and in that window neither the queue nor [current]
  /// leads to this job. It is queued work until it is launched, and this
  /// is what says so.
  _SoloJob<S, S, Object?>? inTransition;

  _SoloLaneCore(this.controller, {required this.name});
}
