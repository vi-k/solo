import 'package:meta/meta.dart';

part 'reversed_iterable.dart';
part 'safe_iterable.dart';

/// Элемент для [LinkedList].
abstract base class LinkedListItem<T extends LinkedListItem<T>> {
  LinkedList<T>? _list;
  T? _next;
  T? _previous;
  var _removed = false;

  LinkedListItem() {
    assert(this is T, 'The element type must be $T');
  }

  T get _self => this as T;

  LinkedList<T> get list => LinkedList._checkElementIsLinked(_self);

  T? get next {
    LinkedList._checkElementIsLinked(_self);

    return _self._next;
  }

  T? get previous {
    LinkedList._checkElementIsLinked(_self);

    return _self._previous;
  }

  bool get unlinked => _list == null;

  void unlink() {
    LinkedList._checkElementIsLinked(_self).remove(_self);
  }

  void insertBefore(T target) {
    LinkedList._checkTargetIsLinked(target).insert(_self, before: target);
  }

  void insertAfter(T target) {
    LinkedList._checkTargetIsLinked(target).insert(_self, after: target);
  }
}

/// Двусвязный список.
///
/// Позволяет частично модифицировать (добавлять и удалять элементы, но не
/// переносить) во время прохождения списка с помощью `for (.. in ..)`
/// и итератора [iterator].
///
/// Особенности:
/// - Элементы, добавленные в список перед текущим элементом, в прохождении
///   списка участвовать не будут.
/// - Если текущий элемент был удалён, то прохождение списка продолжится с
///   элемента, ранее следовавшего за текущим.
/// - Если вместе с текущим было удалено несколько элементов, то прохождение
///   списка продолжится с элемента, ранее следовавшего за удалённой группой.
/// - Если сначала был удалён текущий элемент, а затем перед следущим был
///   добавлен новый ([LinkedListItem.insertBefore]), то новый элемент
///   в прохождение не попадёт. Прохождение продолжится с элемента, ранее
///   следовавшего за текущим.
/// - Если, наоборот, сначала перед следущим ([LinkedListItem.insertBefore])
///   или после текущего ([LinkedListItem.insertAfter]) был добавлен новый
///   элемент, а затем удалён текущий, то прохождение продолжится с этого
///   нового элемента.
/// - Если текущий элемент был перенесён (удалён, а затем снова вставлен
///   в список), то прохождение продолжится с элемента, следующего за
///   перенесённым после вставки.
base class LinkedList<T extends LinkedListItem<T>> extends Iterable<T> {
  int _length = 0;
  var _modificationCount = 0;
  var _transferCount = 0;
  T? _first;
  T? _last;

  LinkedList();

  @override
  int get length => _length;

  @override
  bool get isEmpty => _length == 0;

  @override
  bool get isNotEmpty => _length != 0;

  @override
  Iterator<T> get iterator => _LinkedListIterator<T>(this);

  T? get firstOrNull => _first;

  @override
  T get first => _first ?? _throwNoSuchElement();

  T? get lastOrNull => _last;

  @override
  T get last => _last ?? _throwNoSuchElement();

  T? get singleOrNull => _length > 1 ? null : _first;

  @override
  T get single => _length > 1 ? _throwTooManyElements() : first;

  Iterable<T> get reversed => _ReversedLinkedListIterable(this);

  Iterable<T> get safe => _SafeLinkedListIterable(this);

  /// Добавляет [element] в произвольное место в списке.
  ///
  /// Если задан [before], то элемент добавляется перед [before]. Если задан
  /// [after], то после [after]. Если не задан ни [before], ни [after], элемент
  /// добавляется в конец списка. Одновременно оба параметра заданы быть
  /// не могут.
  ///
  /// Все методы добавления элементов в список в конечном итоге используют
  /// [insert].
  @mustCallSuper
  T insert(
    T element, {
    T? before,
    T? after,
  }) {
    if (before != null && after != null) {
      throw ArgumentError(
        'Only one of the parameters can be set: before or after',
      );
    }
    _checkElementIsUnLinked(element, this);

    _modificationCount++;
    if (element._removed) {
      _transferCount++;
    }

    if (before == null && after == null) {
      after = _last;
    }

    if (before != null) {
      _checkTargetIsInList(before, this);

      final previous = before._previous;
      if (previous != null) {
        previous._next = element;
      }
      element
        .._list = this
        .._removed = false
        .._previous = previous
        .._next = before;
      before._previous = element;

      if (identical(before, _first)) {
        _first = element;
      }
    } else if (after != null) {
      _checkTargetIsInList(after, this);

      final next = after._next;
      if (next != null) {
        next._previous = element;
      }
      element
        .._list = this
        .._removed = false
        .._previous = after
        .._next = next;
      after._next = element;

      if (identical(after, _last)) {
        _last = element;
      }
    } else {
      element
        .._list = this
        .._removed = false
        .._previous = null
        .._next = null;
      _first = _last = element;
    }

    _length++;

    return element;
  }

  /// Добавляет [element] в конец списка.
  T add(T element) => insert(element, after: _last);

  /// Добавляет [elements] в конец списка.
  void addAll(Iterable<T> elements) {
    for (final element in elements) {
      insert(element, after: _last);
    }
  }

  /// Добавляет [element] в начало списка.
  T addFirst(T element) => insert(element, before: _first);

  /// Добавляет [elements] в начало списка.
  void addFirstAll(Iterable<T> elements) {
    T? last;

    for (final element in elements) {
      if (last == null) {
        addFirst(element);
      } else {
        insert(element, after: last);
      }
      last = element;
    }
  }

  /// Удаляет [element] из списка.
  ///
  /// Все методы удаления элементов из списка в конечном итоге используют
  /// [remove].
  @mustCallSuper
  void remove(T element) {
    _checkElementIsInList(element, this);

    _modificationCount++;

    final previous = element._previous;
    final next = element._next;
    if (previous != null) {
      previous._next = next;
    }
    if (next != null) {
      next._previous = previous;
    }
    element
      .._list = null
      .._removed = true;

    if (identical(_first, element)) {
      _first = next;
    }

    if (identical(_last, element)) {
      _last = previous;
    }

    _length--;
  }

  /// Удаляет последний элемент из списка.
  ///
  /// Возвращает удалённый элемент.
  T removeFirst() {
    final removedItem = first;
    remove(removedItem);

    return removedItem;
  }

  /// Удаляет последний элемент из списка.
  ///
  /// Возвращает удалённый элемент.
  T removeLast() {
    final removedItem = last;
    remove(removedItem);

    return removedItem;
  }

  /// Удаляет элементы из списка по условию.
  ///
  /// Возвращает количество удалённых элементов.
  int removeWhere(bool Function(T element) test) {
    final length = _length;

    for (var item = _first; item != null;) {
      final next = item._next;

      final savedModificationCount = _modificationCount;
      final ok = test(item);
      _checkModificationCount(this, savedModificationCount);

      if (ok) {
        remove(item);
      }

      item = next;
    }

    return length - _length;
  }

  /// Удаляет все последние элементы из списка по условию.
  ///
  /// Удаляет ТОЛЬКО последние элементы, т.е. до первого элемента,
  /// не соответствующего условию.
  ///
  /// Возвращает количество удалённых элементов.
  int removeLastWhere(bool Function(T element) test) {
    final length = _length;

    for (var item = _last; item != null;) {
      final previous = item._previous;

      final savedModificationCount = _modificationCount;
      final ok = test(item);
      _checkModificationCount(this, savedModificationCount);

      if (!ok) {
        break;
      }

      remove(item);

      item = previous;
    }

    return length - _length;
  }

  /// Удаляет элементы из списка после заданного.
  ///
  /// Возвращает количество удалённых элементов.
  int removeAfter(T element) {
    final length = _length;

    for (var item = element._next; item != null; item = item._next) {
      remove(item);
    }

    return length - _length;
  }

  /// Удаляет элементы из списка по условию.
  ///
  /// Возвращает список удалённых элементов.
  List<T> unlinkWhere(bool Function(T element) test) {
    final unlinked = <T>[];

    for (var item = _first; item != null;) {
      final next = item._next;

      final savedModificationCount = _modificationCount;
      final ok = test(item);
      _checkModificationCount(this, savedModificationCount);

      if (ok) {
        remove(item);
        unlinked.add(item);
      }

      item = next;
    }

    return unlinked;
  }

  @override
  Iterable<T> where(bool Function(T element) test) sync* {
    final savedModificationCount = _modificationCount;

    for (var item = _first; item != null; item = item._next) {
      final ok = test(item);
      _checkModificationCount(this, savedModificationCount);

      if (ok) {
        yield item;
      }
    }
  }

  T? firstWhereOrNull(bool Function(T element) test) {
    final savedModificationCount = _modificationCount;

    for (var item = _first; item != null; item = item._next) {
      final ok = test(item);
      _checkModificationCount(this, savedModificationCount);

      if (ok) {
        return item;
      }
    }

    return null;
  }

  @override
  T firstWhere(
    bool Function(T element) test, {
    T Function()? orElse,
  }) =>
      firstWhereOrNull(test) ??
      (orElse != null ? orElse() : _throwNoSuchElement());

  T? lastWhereOrNull(bool Function(T element) test) {
    final savedModificationCount = _modificationCount;

    for (var item = _last; item != null; item = item._previous) {
      final ok = test(item);
      _checkModificationCount(this, savedModificationCount);

      if (ok) {
        return item;
      }
    }

    return null;
  }

  @override
  T lastWhere(
    bool Function(T element) test, {
    T Function()? orElse,
  }) =>
      lastWhereOrNull(test) ??
      (orElse != null ? orElse() : _throwNoSuchElement());

  T? singleWhereOrNull(bool Function(T element) test) {
    final savedModificationCount = _modificationCount;
    T? result;

    for (var item = _first; item != null; item = item._next) {
      final ok = test(item);
      _checkModificationCount(this, savedModificationCount);

      if (ok) {
        if (result != null) {
          _throwTooManyElements();
        }

        result = item;
      }
    }

    return result;
  }

  @override
  T singleWhere(
    bool Function(T element) test, {
    T Function()? orElse,
  }) =>
      singleWhereOrNull(test) ??
      (orElse != null ? orElse() : _throwNoSuchElement());

  @override
  bool contains(covariant T element) => identical(element._list, this);

  void clear() {
    _modificationCount++;

    for (var item = _first; item != null; item = item._next) {
      _setUnlinked(item);
    }

    _first = _last = null;
    _length = 0;
  }

  void _setUnlinked(T item) {
    item
      .._list = null
      .._removed = true;
  }

  @override
  String toString() {
    final buf = StringBuffer('[');
    var first = true;

    for (var item = _first; item != null; item = item._next) {
      if (first) {
        first = false;
      } else {
        buf.write(', ');
      }
      buf.write(item.toString());
    }

    buf.write(']');

    return buf.toString();
  }

  static void _checkModificationCount(
    LinkedList list,
    int savedModificationCount,
  ) {
    if (savedModificationCount != list._modificationCount) {
      throw ConcurrentModificationError(list);
    }
  }

  static void _checkTransferCount(
    LinkedList list,
    int savedTransferCount,
  ) {
    if (savedTransferCount != list._transferCount) {
      throw ConcurrentModificationError(list);
    }
  }

  static void _checkTargetIsInList(
    LinkedListItem target,
    LinkedList list,
  ) {
    if (!identical(target._list, list)) {
      throw StateError('The target element is not in this list');
    }
  }

  static void _checkElementIsInList(
    LinkedListItem element,
    LinkedList list,
  ) {
    if (!identical(element._list, list)) {
      throw StateError('The element is not in this list');
    }
  }

  static void _checkElementIsUnLinked(
    LinkedListItem element,
    LinkedList list,
  ) {
    final elementList = element._list;
    if (elementList != null) {
      throw StateError(
        identical(elementList, list)
            ? 'The element is already linked'
            : 'The element is already linked to other list',
      );
    }
  }

  static const _targetIsUnlinked = 'The target element is unlinked';

  static LinkedList<T> _checkTargetIsLinked<T extends LinkedListItem<T>>(
    LinkedListItem<T> target,
  ) {
    final list = target._list;
    if (list == null) {
      throw StateError(_targetIsUnlinked);
    }

    return list;
  }

  static LinkedList<T> _checkElementIsLinked<T extends LinkedListItem<T>>(
    LinkedListItem<T> element,
  ) {
    final list = element._list;
    if (list == null) {
      throw StateError('The element is unlinked');
    }

    return list;
  }

  static Never _throwNoSuchElement() => throw StateError('No such element');

  static Never _throwTooManyElements() => throw StateError('Too many elements');

  static Never _throwUsageBeforeMoveNext() =>
      throw StateError('Usage before moveNext');
}

/// Итератор для [LinkedList].
class _LinkedListIterator<T extends LinkedListItem<T>> implements Iterator<T> {
  final int _savedTransferCount;
  final LinkedList<T> _list;

  T? _current;
  var _visitedFirst = false;

  _LinkedListIterator(this._list) : _savedTransferCount = _list._transferCount;

  @override
  T get current =>
      _current ??
      (_visitedFirst
          ? LinkedList._throwNoSuchElement()
          : LinkedList._throwUsageBeforeMoveNext());

  @override
  bool moveNext() {
    LinkedList._checkTransferCount(_list, _savedTransferCount);

    final current = _current;
    if (current == null) {
      if (_visitedFirst) {
        return false;
      }

      _visitedFirst = true;
      return (_current = _list._first) != null;
    }

    if (current._list != null && !identical(current._list, _list)) {
      throw ConcurrentModificationError(_list);
    }

    var next = current._next;
    while (next != null && !identical(next._list, _list)) {
      if (next._list != null) {
        throw ConcurrentModificationError(_list);
      }
      next = next._next;
    }

    return (_current = next) != null;
  }
}
