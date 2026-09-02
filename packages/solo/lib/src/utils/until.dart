import 'dart:async';

class UntilException implements Exception {
  final String? message;

  const UntilException(this.message);

  @override
  String toString() => '$UntilException(${message ?? ''})';
}

extension FutureUntilExtension<T> on Future<T> {
  /// Ждать выполнения [Future] до тех пор, пока не исполнится [untilFuture].
  Future<T> until(
    Future<void> untilFuture, {
    String? message,
  }) {
    final completer = Completer<T>();

    void complete(T value) {
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    }

    void completeError(Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      } else {
        // Не пропускаем ошибки.
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    void cancel() {
      if (!completer.isCompleted) {
        completer.completeError(UntilException(message), StackTrace.current);
      }
    }

    then(complete, onError: completeError);
    untilFuture.then((_) => cancel(), onError: completeError);

    return completer.future;
  }
}
