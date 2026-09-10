part of 'solo_base.dart';

enum _AccumulationTimingKind { debounce, throttle }

/// Controls when accumulated event groups become ready to run.
///
/// A debounce window restarts after every accepted event. A throttle
/// interval starts when a group actually starts and is shared by the groups
/// of one accumulator. The same setting can be reused by independent
/// accumulators without sharing their timers.
final class AccumulationTiming {
  /// The length of the debounce window or throttle interval.
  final Duration duration;
  final _AccumulationTimingKind _kind;

  /// Creates a debounce window of [duration].
  ///
  /// Throws [ArgumentError] when [duration] is negative. A zero duration
  /// preserves the behavior of an accumulator without timing.
  AccumulationTiming.debounce(this.duration)
      : _kind = _AccumulationTimingKind.debounce {
    _validateDuration(duration);
  }

  /// Creates a throttle interval of [duration].
  ///
  /// Throws [ArgumentError] when [duration] is negative. A zero duration
  /// preserves the behavior of an accumulator without timing.
  AccumulationTiming.throttle(this.duration)
      : _kind = _AccumulationTimingKind.throttle {
    _validateDuration(duration);
  }

  static void _validateDuration(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
  }
}
