part of 'linked_list.dart';

final class _ReversedLinkedListIterable<T extends LinkedListItem<T>>
    extends Iterable<T> {
  final LinkedList<T> _list;

  const _ReversedLinkedListIterable(this._list);

  @override
  Iterator<T> get iterator => _ReversedLinkedListIterator(_list);
}

final class _ReversedLinkedListIterator<T extends LinkedListItem<T>>
    implements Iterator<T> {
  final int _savedTransferCount;
  final LinkedList<T> _list;

  T? _current;
  var _visitedFirst = false;

  _ReversedLinkedListIterator(this._list)
      : _savedTransferCount = _list._transferCount;

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
      return (_current = _list._last) != null;
    }

    if (current._list != null && !identical(current._list, _list)) {
      throw ConcurrentModificationError(_list);
    }

    var previous = current._previous;
    while (previous != null && !identical(previous._list, _list)) {
      if (previous._list != null) {
        throw ConcurrentModificationError(_list);
      }
      previous = previous._previous;
    }

    return (_current = previous) != null;
  }
}
