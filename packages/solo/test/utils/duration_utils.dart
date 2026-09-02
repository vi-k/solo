const _defaultStepInMs = 40;
const defaultStep = Duration(milliseconds: _defaultStepInMs);
const defaultHalfStep = Duration(milliseconds: _defaultStepInMs ~/ 2);

extension DurationExt on Duration {
  Duration mult(num k) {
    final ms = inMilliseconds;
    return Duration(milliseconds: (ms * k).round());
  }

  bool get isZero => this == Duration.zero;
}

Duration max(Duration duration1, Duration duration2) =>
    duration1 >= duration2 ? duration1 : duration2;
