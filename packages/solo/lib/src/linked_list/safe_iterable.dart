part of 'linked_list.dart';

final class _SafeLinkedListIterable<T extends LinkedListItem<T>>
    extends Iterable<T> {
  final LinkedList<T> _list;

  const _SafeLinkedListIterable(this._list);

  @override
  Iterator<T> get iterator => _SafeLinkedListIterator(_list);
}

class _SafeLinkedListIterator<T extends LinkedListItem<T>>
    implements Iterator<T> {
  final int _savedModificationCount;
  final LinkedList<T> _list;

  T? _current;
  var _visitedFirst = false;

  _SafeLinkedListIterator(this._list)
      : _savedModificationCount = _list._modificationCount;

  @override
  T get current =>
      _current ??
      (_visitedFirst
          ? LinkedList._throwNoSuchElement()
          : LinkedList._throwUsageBeforeMoveNext());

  @override
  bool moveNext() {
    LinkedList._checkModificationCount(_list, _savedModificationCount);

    final current = _current;
    if (current == null) {
      if (_visitedFirst) {
        return false;
      }

      _visitedFirst = true;
      return (_current = _list._first) != null;
    }

    return (_current = current._next) != null;
  }
}
