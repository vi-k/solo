part of 'solo.dart';

enum _AccumulationTimingKind { debounce, throttle }

/// Controls when accumulated event groups become ready to run.
///
/// A debounce window restarts after every accepted event. A throttle
/// interval starts when a group actually starts, or, with
/// `startAtOnce: false`, when a group appears on an accumulator that has
/// none of its own queued or running; either way it is shared by the
/// groups of one accumulator. The same setting can be reused by
/// independent accumulators without sharing their timers.
@immutable
final class AccumulationTiming {
  /// The length of the debounce window or throttle interval.
  final Duration duration;
  final _AccumulationTimingKind _kind;

  /// Whether the first group of an idle throttle starts without waiting.
  final bool _startAtOnce;

  /// Creates a debounce window of [duration].
  ///
  /// Throws [ArgumentError] when [duration] is negative. A zero duration
  /// preserves the behavior of an accumulator without timing.
  AccumulationTiming.debounce(this.duration)
      : _kind = _AccumulationTimingKind.debounce,
        _startAtOnce = true {
    _validateDuration(duration);
  }

  /// Creates a throttle interval of [duration].
  ///
  /// With `startAtOnce: false` the interval is counted before the first
  /// group as well: an accumulator with nothing of its own queued or
  /// running starts its interval when the group appears, and the group
  /// runs when the interval ends. Nothing else changes — a running
  /// interval is never restarted, so a group already waiting only for the
  /// execution slot is not pushed back by a later event.
  ///
  /// Throws [ArgumentError] when [duration] is negative. A zero duration
  /// preserves the behavior of an accumulator without timing, whatever
  /// [startAtOnce] says.
  AccumulationTiming.throttle(this.duration, {bool startAtOnce = true})
      : _kind = _AccumulationTimingKind.throttle,
        _startAtOnce = startAtOnce {
    _validateDuration(duration);
  }

  /// Two timings are equal when they are of the same kind, with the same
  /// [duration] and, for a throttle, the same `startAtOnce`.
  @override
  bool operator ==(Object other) =>
      other is AccumulationTiming &&
      other.duration == duration &&
      other._kind == _kind &&
      other._startAtOnce == _startAtOnce;

  @override
  int get hashCode => Object.hash(duration, _kind, _startAtOnce);

  /// The constructor call that makes this timing, such as
  /// `AccumulationTiming.throttle(0:00:01.000000, startAtOnce: false)`.
  @override
  String toString() => switch (_kind) {
        _AccumulationTimingKind.debounce =>
          'AccumulationTiming.debounce($duration)',
        _AccumulationTimingKind.throttle => _startAtOnce
            ? 'AccumulationTiming.throttle($duration)'
            : 'AccumulationTiming.throttle($duration, startAtOnce: false)',
      };

  static void _validateDuration(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
  }
}
