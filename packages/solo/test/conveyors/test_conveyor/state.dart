import 'package:meta/meta.dart';

@immutable
sealed class TestState {
  const TestState();
}

sealed class NotDisposed extends TestState {}

sealed class InitialAndPreparing extends TestState {}

sealed class PreparingAndWorking extends TestState {}

sealed class WorkingAndDisposed extends TestState {}

final class Initial extends TestState
    implements NotDisposed, InitialAndPreparing {
  const Initial();

  @override
  bool operator ==(covariant TestState other) => other is Initial;

  @override
  int get hashCode => (Initial).hashCode;

  @override
  String toString() => '$Initial()';
}

final class Preparing extends TestState
    implements NotDisposed, InitialAndPreparing, PreparingAndWorking {
  final int progress;

  const Preparing({
    this.progress = 0,
  });

  Preparing copyWith({
    int? progress,
  }) =>
      Preparing(
        progress: progress ?? this.progress,
      );

  @override
  bool operator ==(covariant TestState other) =>
      other is Preparing && progress == other.progress;

  @override
  int get hashCode => progress.hashCode;

  @override
  String toString() => '$Preparing(progress: $progress)';
}

final class Working extends TestState
    implements NotDisposed, PreparingAndWorking, WorkingAndDisposed {
  final int a;
  final int b;

  const Working({
    this.a = 0,
    this.b = 0,
  });

  Working copyWith({
    int? a,
    int? b,
  }) =>
      Working(
        a: a ?? this.a,
        b: b ?? this.b,
      );

  @override
  bool operator ==(covariant TestState other) =>
      other is Working && a == other.a && b == other.b;

  @override
  int get hashCode => Object.hash(a, b);

  @override
  String toString() => '$Working(a: $a, b: $b)';
}

final class Disposed extends TestState implements WorkingAndDisposed {
  const Disposed();

  @override
  bool operator ==(covariant TestState other) => other is Disposed;

  @override
  int get hashCode => (Disposed).hashCode;

  @override
  String toString() => '$Disposed()';
}

final class Special extends TestState {
  final int noopCount;
  final int sequentialCount;
  final int droppableCount;
  final int restartableCount;
  final int debounceCount;

  const Special()
      : noopCount = 0,
        sequentialCount = 0,
        droppableCount = 0,
        restartableCount = 0,
        debounceCount = 0;

  const Special._({
    required this.noopCount,
    required this.sequentialCount,
    required this.droppableCount,
    required this.restartableCount,
    required this.debounceCount,
  });

  Special copyWith({
    int? noopCount,
    int? sequentialCount,
    int? droppableCount,
    int? restartableCount,
    int? debounceCount,
  }) =>
      Special._(
        noopCount: noopCount ?? this.noopCount,
        sequentialCount: sequentialCount ?? this.sequentialCount,
        droppableCount: droppableCount ?? this.droppableCount,
        restartableCount: restartableCount ?? this.restartableCount,
        debounceCount: debounceCount ?? this.debounceCount,
      );

  Special change(Special Function(Special state) callback) => callback(this);

  @override
  bool operator ==(covariant TestState other) =>
      other is Special &&
      noopCount == other.noopCount &&
      sequentialCount == other.sequentialCount &&
      droppableCount == other.droppableCount &&
      restartableCount == other.restartableCount &&
      debounceCount == other.debounceCount;

  @override
  int get hashCode => Object.hashAll([
        noopCount,
        sequentialCount,
        droppableCount,
        restartableCount,
        debounceCount,
      ]);

  void _addToBuf(StringBuffer buf, int value, String name) {
    if (value != 0) {
      if (buf.isNotEmpty) {
        buf.write(', ');
      }

      buf
        ..write(name)
        ..write(': ')
        ..write(value);
    }
  }

  @override
  String toString() {
    final buf = StringBuffer();

    _addToBuf(buf, noopCount, 'noop');
    _addToBuf(buf, sequentialCount, 'sequential');
    _addToBuf(buf, droppableCount, 'droppable');
    _addToBuf(buf, restartableCount, 'restartable');
    _addToBuf(buf, debounceCount, 'debounce');

    return '$Special($buf)';
  }
}
