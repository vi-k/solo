import 'package:clock/clock.dart';

final class Debouncer<T extends Object?> {
  final Duration duration;

  DateTime? _timestamp;
  late T _data;
  bool _hasData = false;

  Debouncer(this.duration);

  T get data =>
      _hasData ? _data : throw Exception('The data has not yet been set');

  bool start() {
    final now = clock.now().toUtc();
    final timestamp = _timestamp;
    if (timestamp != null && now.difference(timestamp) < duration) {
      return false;
    }

    _timestamp = now;

    return true;
  }

  T startWithData({
    required T Function() onStart,
    void Function()? onSkip,
  }) {
    if (start()) {
      _data = onStart();
      _hasData = true;
    } else {
      onSkip?.call();
    }

    return _data;
  }

  T? startWithDataOrNull({
    required T Function() onStart,
    void Function()? onSkip,
  }) {
    if (start()) {
      _hasData = true;
      return _data = onStart();
    }

    onSkip?.call();

    return null;
  }
}

final class DebouncerSkip implements Exception {
  const DebouncerSkip();
}
