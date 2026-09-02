part of 'conveyor.dart';

/// Результат обработки события.
abstract interface class ConveyorResult {
  /// Сигнал завершения операции.
  ///
  /// Всегда завершается успешно (т.е. без исключений) при любом исходе:
  /// и при успехе, и при отмене, и при ошибке.
  ///
  /// Сигнал срабатывает только после реального завершения операции. В случае
  /// зависания операции сигнал не сработает.
  Future<void> get done;

  /// Сигнал отмены операции.
  ///
  /// В отличие от [done], сигнал срабатывает сразу после отмены операции, не
  /// дожидаясь её реального завершения.
  ///
  /// Как и [done], сигнал всегда завершается успешно: не выкидывает
  /// исключение.
  Future<void> get onCancelled;

  /// Операция завершена (и при успехе, и при отмене, и при ошибке).
  bool get isFinished;

  /// Операция завершена успешно.
  bool get isSuccess;

  /// Операция отменена.
  bool get isCancelled;

  /// Операция завершена с ошибкой.
  bool get isError;

  /// Причина отмены.
  ///
  /// Если операция не была отменена, выкинет исключение
  /// `StateError('Not cancelled')`.
  Cancelled get cancellationReason;

  /// Ошибка.
  ///
  /// Если операция не была завершена ошибкой, выкинет исключение
  /// `StateError('No error')`.
  Object get error;

  /// Стектрейс (и для ошибки, и для отмены).
  ///
  /// Если операция не была ни отменена, ни завершена с ошибкой, выкинет
  /// исключение `StateError('No stacktrace')`.
  StackTrace get stackTrace;
}

final class _ConveyorResult implements ConveyorResult {
  final _doneCompleter = Completer<void>();
  final _cancelCompleter = Completer<void>();

  (Object, StackTrace)? _finisher;

  _ConveyorResult();

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  Future<void> get onCancelled => _cancelCompleter.future;

  @override
  bool get isFinished => _doneCompleter.isCompleted;

  @override
  bool get isSuccess => _doneCompleter.isCompleted && _finisher == null;

  @override
  bool get isError {
    final finisher = _finisher;
    return finisher != null && finisher.$1 is! Cancelled;
  }

  @override
  bool get isCancelled {
    final finisher = _finisher;
    return finisher != null && finisher.$1 is Cancelled;
  }

  @override
  Object get error {
    final finisher = _finisher?.$1;
    if (finisher != null && finisher is! Cancelled) {
      return finisher;
    }

    throw StateError('No error');
  }

  @override
  Cancelled get cancellationReason {
    final finisher = _finisher?.$1;
    if (finisher is Cancelled) {
      return finisher;
    }

    throw StateError('Not cancelled');
  }

  @override
  StackTrace get stackTrace {
    final stackTrace = _finisher?.$2;
    if (stackTrace != null) {
      return stackTrace;
    }

    throw StateError('No stacktrace');
  }

  void complete() {
    _checkResult();
    _finisher = null;
    _doneCompleter.complete();
  }

  void completeError(Object error, StackTrace stackTrace) {
    _checkResult();
    _finisher = (error, stackTrace);
    _doneCompleter.complete();
  }

  void cancel(Cancelled reason, StackTrace stackTrace) {
    cancelStart(reason, stackTrace);
    cancelFinish();
  }

  /// Устанавливает результат как отменённый, но не завершает его.
  /// Срабатывает [onCancelled].
  void cancelStart(Cancelled reason, StackTrace stackTrace) {
    _checkResult();
    _finisher = (reason, stackTrace);
    _cancelCompleter.complete();
  }

  /// Завершает отмену. Срабатывает [done].
  void cancelFinish() {
    _doneCompleter.complete();
  }

  void _checkResult() {
    if (_doneCompleter.isCompleted) {
      throw StateError(
        _finisher!.$1 is Cancelled ? 'Already cancelled' : 'Already completed',
      );
    }
  }

  @override
  String toString() => !isFinished
      ? 'not completed'
      : isCancelled
          ? cancellationReason.toString()
          : isError
              ? error.toString()
              : 'completed';
}
