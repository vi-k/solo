part of 'conveyor.dart';

final class ConveyorQueue<BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>>
    extends LinkedList<Event> {
  final void Function()? onPause;
  final void Function()? onResume;
  final void Function(Event event)? onRemove;

  bool _closed = false;

  ConveyorQueue({
    this.onPause,
    this.onResume,
    this.onRemove,
  });

  bool get isClosed => _closed;

  @override
  Event insert(
    // ignore: avoid_renaming_method_parameters
    Event event, {
    Event? before,
    Event? after,
  }) {
    debug(
      'insert $event'
      '${before == null ? '' : ' before $before'}'
      '${after == null ? '' : ' after $after'}',
    );

    if (_closed) {
      event._result.cancel(
        const RemovedAsClosed._(),
        StackTrace.current,
      );
      onRemove?.call(event);

      return event;
    }

    final isEmpty = this.isEmpty;
    super.insert(event, before: before, after: after);
    if (isEmpty) {
      onResume?.call();
    }

    return event;
  }

  @override
  // ignore: avoid_renaming_method_parameters
  void remove(Event event, {bool force = false}) {
    if (!force && event.unkilled) {
      debug("remove $event - can't be removed");
      return;
    }

    debug('remove $event');
    super.remove(event);

    if (isEmpty) {
      onPause?.call();
    }

    event._result.cancel(
      const RemovedManually._(),
      StackTrace.current,
    );

    onRemove?.call(event);
  }

  @override
  void clear({bool force = false}) {
    for (final e in this) {
      remove(e, force: force);
    }
  }

  /// Закрывает очередь.
  ///
  /// Форсированно очищает очередь даже от неубиваемых событий.
  /// Помечает очередь как закрытую: новые события будут удаляться сразу
  /// с признаком [RemovedAsClosed].
  void close() {
    debug('close queue');

    _closed = true;

    for (final event in this) {
      debug(
        'remove $event'
        '${event.unkilled ? ' (forced because the queue is closed' : ''}',
      );
      super.remove(event);

      event._result.cancel(
        const RemovedAsClosed._(),
        StackTrace.current,
      );

      onRemove?.call(event);
    }
  }

  /// Вынимает из очереди первый элемент, но не отменяет его.
  Event? _unsafePull() {
    final event = firstOrNull;
    if (event != null) {
      super.remove(event);
    }

    return event;
  }
}
