part of '../conveyor.dart';

/// Класс, сигнализирующий об отмене обработчика события.
@immutable
sealed class Cancelled implements Exception {
  const Cancelled._();

  @override
  bool operator ==(covariant Cancelled other) =>
      identical(this, other) || runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Отменено выбрасыванием исключения.
///
/// Позволяем пользователю вручную отменять функцию-обработчик, вызывая
/// исключение внутри обработчика:
///
/// ```
/// throw CancelledByException();
/// ```
///
/// Это единственное исключение, которое пользователь может создать сам.
final class CancelledByException extends Cancelled {
  const CancelledByException() : super._();

  @override
  String toString() => '$CancelledByException()';
}

/// Отменено вручную.
///
/// Позволяем пользователю отменять текущий процесс обработки события.
///
/// ```
/// conveyor.currentProcess.cancel();
/// ```
final class CancelledManually extends Cancelled {
  const CancelledManually._() : super._();

  @override
  String toString() => '$CancelledManually()';
}

/// Отменено родительским процессом.
final class CancelledByParent extends Cancelled {
  const CancelledByParent._() : super._();

  @override
  String toString() => '$CancelledByParent()';
}

/// Состояние не удовлетворяет условиям обработки события.
///
/// Причина срабатывает при изменении состояния во время обработки
/// события, если в событии заданы ограничения на допустимое состояние.
/// В этом случае сразу происходит отмена подписки на функцию-обработчик
/// события.
///
/// Проверяется во время установки состояние извне и при проверке с помощью
/// [ConveyorStateProvider].
final class CancelledByEventRules extends Cancelled {
  final String? description;

  const CancelledByEventRules._([this.description]) : super._();

  @override
  String toString() => '$CancelledByEventRules(${description ?? ''})';
}

/// Состояние не удовлетворяет условию работы в текущем месте
/// функции-обработчика.
///
/// Причина срабатывает при ручной проверке с помощью [ConveyorStateProvider]
/// через дополнительные условия [ConveyorStateProvider.test],
/// [ConveyorStateProvider.isA], [ConveyorStateProvider.map].
final class CancelledByCheckState extends Cancelled {
  final String? description;

  const CancelledByCheckState._([this.description]) : super._();

  @override
  String toString() => '$CancelledByCheckState(${description ?? ''})';
}

/// Событие отменено по причине закрытия конвейера.
final class CancelledAsClosed extends Cancelled {
  const CancelledAsClosed._() : super._();

  @override
  String toString() => '$CancelledAsClosed()';
}

/// Класс, сигнализирующий об удалении события из очереди.
sealed class Removed extends Cancelled {
  const Removed._() : super._();
}

/// Событие удалено из очереди вручную.
///
/// ```
/// conveyor.remove(...);
/// ```
final class RemovedManually extends Removed {
  const RemovedManually._() : super._();

  @override
  String toString() => '$RemovedManually()';
}

/// Удалено из очереди, потому что состояние не удовлетворяет условиям
/// обработки события.
///
/// Причина срабатывает при поиске очередного события для обработки.
final class RemovedByEventRules extends Removed {
  final String? description;

  const RemovedByEventRules._([this.description]) : super._();

  @override
  String toString() => '$RemovedByEventRules(${description ?? ''})';
}

/// Событие удалено по причине закрытия очереди.
final class RemovedAsClosed extends Removed {
  const RemovedAsClosed._() : super._();

  @override
  String toString() => '$RemovedAsClosed()';
}
