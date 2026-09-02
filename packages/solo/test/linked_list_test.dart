@Timeout(Duration(seconds: 5))
library;

import 'package:conveyor/src/linked_list/linked_list.dart';
import 'package:test/test.dart';

final class Item extends LinkedListItem<Item> {
  final int value;

  Item(this.value);

  @override
  String toString() => 'Item($value)';
}

extension on Iterable<Item> {
  List<int> get values => map((e) => e.value).toList();
}

void main() {
  group('Linked list.', () {
    test('Basic flow', () {
      // add

      final list = LinkedList<Item>()
        ..addFirst(Item(1))
        ..addFirst(Item(2))
        ..add(Item(3))
        ..add(Item(4))
        ..addAll([Item(5), Item(6)]);
      expect(list.values, [2, 1, 3, 4, 5, 6]);
      expect(list.reversed.values, [6, 5, 4, 3, 1, 2]);
      expect(list.length, 6);

      // insertBefore/insertAfter

      final item2 = list.first;
      Item(7).insertBefore(item2);
      expect(list.values, [7, 2, 1, 3, 4, 5, 6]);
      expect(list.reversed.values, [6, 5, 4, 3, 1, 2, 7]);
      expect(list.length, 7);

      Item(8).insertAfter(item2);
      expect(list.values, [7, 2, 8, 1, 3, 4, 5, 6]);
      expect(list.reversed.values, [6, 5, 4, 3, 1, 8, 2, 7]);
      expect(list.length, 8);

      final item6 = list.last;
      Item(9).insertBefore(item6);
      expect(list.values, [7, 2, 8, 1, 3, 4, 5, 9, 6]);
      expect(list.reversed.values, [6, 9, 5, 4, 3, 1, 8, 2, 7]);
      expect(list.length, 9);

      Item(10).insertAfter(item6);
      expect(list.values, [7, 2, 8, 1, 3, 4, 5, 9, 6, 10]);
      expect(list.reversed.values, [10, 6, 9, 5, 4, 3, 1, 8, 2, 7]);
      expect(list.length, 10);

      // remove

      final item7 = list.removeFirst();
      expect(list.values, [2, 8, 1, 3, 4, 5, 9, 6, 10]);
      expect(list.reversed.values, [10, 6, 9, 5, 4, 3, 1, 8, 2]);
      expect(list.length, 9);

      final item10 = list.removeLast();
      expect(list.values, [2, 8, 1, 3, 4, 5, 9, 6]);
      expect(list.reversed.values, [6, 9, 5, 4, 3, 1, 8, 2]);
      expect(list.length, 8);

      final item3 = list.first.next!.next!.next!;
      list.remove(item3);
      expect(list.values, [2, 8, 1, 4, 5, 9, 6]);
      expect(list.reversed.values, [6, 9, 5, 4, 1, 8, 2]);
      expect(list.length, 7);

      final item9 = list.last.previous!..unlink();
      expect(list.values, [2, 8, 1, 4, 5, 6]);
      expect(list.reversed.values, [6, 5, 4, 1, 8, 2]);
      expect(list.length, 6);

      expect(
        item9.unlink,
        throwsA(
          predicate(
            (e) => e is StateError && e.message == 'The element is unlinked',
          ),
        ),
      );
      expect(list.length, 6);

      // paste removed (swap)

      expect(
        () => item9.insertBefore(item10),
        throwsA(
          predicate(
            (e) =>
                e is StateError &&
                e.message == 'The target element is unlinked',
          ),
        ),
      );
      expect(list.length, 6);

      list.addFirst(item10);
      expect(list.values, [10, 2, 8, 1, 4, 5, 6]);
      expect(list.reversed.values, [6, 5, 4, 1, 8, 2, 10]);
      expect(list.length, 7);

      list.add(item7);
      expect(list.values, [10, 2, 8, 1, 4, 5, 6, 7]);
      expect(list.reversed.values, [7, 6, 5, 4, 1, 8, 2, 10]);
      expect(list.length, 8);

      item3.insertAfter(list.first.next!);
      expect(list.values, [10, 2, 3, 8, 1, 4, 5, 6, 7]);
      expect(list.reversed.values, [7, 6, 5, 4, 1, 8, 3, 2, 10]);
      expect(list.length, 9);

      item9.insertBefore(list.last.previous!);
      expect(list.values, [10, 2, 3, 8, 1, 4, 5, 9, 6, 7]);
      expect(list.reversed.values, [7, 6, 9, 5, 4, 1, 8, 3, 2, 10]);
      expect(list.length, 10);

      expect(
        () => item9.insertBefore(list.first),
        throwsA(
          predicate(
            (e) =>
                e is StateError && e.message == 'The element is already linked',
          ),
        ),
      );
      expect(list.length, 10);

      // for

      for (final item in list) {
        if (item.value.isEven) {
          item.unlink();
        }
      }
      expect(list.values, [3, 1, 5, 9, 7]);
      expect(list.reversed.values, [7, 9, 5, 1, 3]);
      expect(list.length, 5);

      expect(
        () {
          for (final item in list) {
            if (item.value == 1) {
              item
                ..unlink()
                ..insertBefore(list.first);
            }
          }
        },
        throwsA(
          predicate(
            (e) =>
                e is ConcurrentModificationError &&
                identical(e.modifiedObject, list),
          ),
        ),
      );
      expect(list.values, [1, 3, 5, 9, 7]);
      expect(list.reversed.values, [7, 9, 5, 3, 1]);
      expect(list.length, 5);

      expect(
        () {
          for (final _ in list.safe) {
            Item(11).insertBefore(list.last);
          }
        },
        throwsA(
          predicate(
            (e) =>
                e is ConcurrentModificationError &&
                identical(e.modifiedObject, list),
          ),
        ),
      );
      expect(list.values, [1, 3, 5, 9, 11, 7]);
      expect(list.reversed.values, [7, 11, 9, 5, 3, 1]);
      expect(list.length, 6);

      // forEach

      // ignore: avoid_function_literals_in_foreach_calls
      list.forEach((item) {
        Item(item.value - 1).insertBefore(item);
      });
      expect(list.values, [0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 6, 7]);
      expect(list.reversed.values, [7, 6, 11, 10, 9, 8, 5, 4, 3, 2, 1, 0]);
      expect(list.length, 12);

      expect(
        () {
          // ignore: avoid_function_literals_in_foreach_calls
          list.forEach((item) {
            if (item.value == 9) {
              item
                ..unlink()
                ..insertAfter(list.last);
            }
          });
        },
        throwsA(
          predicate(
            (e) =>
                e is ConcurrentModificationError &&
                identical(e.modifiedObject, list),
          ),
        ),
      );
      expect(list.values, [0, 1, 2, 3, 4, 5, 8, 10, 11, 6, 7, 9]);
      expect(list.reversed.values, [9, 7, 6, 11, 10, 8, 5, 4, 3, 2, 1, 0]);
      expect(list.length, 12);

      expect(
        () {
          // ignore: avoid_function_literals_in_foreach_calls
          list.safe.forEach((item) {
            if (item.value == 0) {
              item.unlink();
            }
          });
        },
        throwsA(
          predicate(
            (e) =>
                e is ConcurrentModificationError &&
                identical(e.modifiedObject, list),
          ),
        ),
      );
      expect(list.values, [1, 2, 3, 4, 5, 8, 10, 11, 6, 7, 9]);
      expect(list.reversed.values, [9, 7, 6, 11, 10, 8, 5, 4, 3, 2, 1]);
      expect(list.length, 11);

      // removeWhere

      expect(list.removeWhere((e) => e.value >= 8), 4);
      expect(list.values, [1, 2, 3, 4, 5, 6, 7]);
      expect(list.reversed.values, [7, 6, 5, 4, 3, 2, 1]);
      expect(list.length, 7);

      // where

      final whereResult = list.where((e) => e.value >= 5).values;
      expect(whereResult, [5, 6, 7]);

      expect(
        () => list.where((e) {
          e.unlink();
          return e.value >= 5;
        }).values,
        throwsA(
          predicate(
            (e) =>
                e is ConcurrentModificationError &&
                identical(e.modifiedObject, list),
          ),
        ),
      );
      expect(list.values, [2, 3, 4, 5, 6, 7]);
      expect(list.reversed.values, [7, 6, 5, 4, 3, 2]);
      expect(list.length, 6);

      // first

      expect(list.firstWhereOrNull((e) => e.value >= 5)?.value, 5);

      expect(
        () => list.firstWhereOrNull((e) {
          e.unlink();
          return e.value >= 5;
        }),
        throwsA(
          predicate(
            (e) =>
                e is ConcurrentModificationError &&
                identical(e.modifiedObject, list),
          ),
        ),
      );
      expect(list.values, [3, 4, 5, 6, 7]);
      expect(list.reversed.values, [7, 6, 5, 4, 3]);
      expect(list.length, 5);

      expect(list.firstWhere((e) => e.value >= 5).value, 5);

      expect(
        () => list.firstWhere((e) {
          e.unlink();
          return e.value >= 5;
        }),
        throwsA(
          predicate(
            (e) =>
                e is ConcurrentModificationError &&
                identical(e.modifiedObject, list),
          ),
        ),
      );
      expect(list.values, [4, 5, 6, 7]);
      expect(list.reversed.values, [7, 6, 5, 4]);
      expect(list.length, 4);

      // last

      expect(list.lastWhereOrNull((e) => e.value >= 5)?.value, 7);

      expect(
        () => list.lastWhereOrNull((e) {
          e.unlink();
          return e.value >= 5;
        }),
        throwsA(
          predicate(
            (e) =>
                e is ConcurrentModificationError &&
                identical(e.modifiedObject, list),
          ),
        ),
      );
      expect(list.values, [4, 5, 6]);
      expect(list.reversed.values, [6, 5, 4]);
      expect(list.length, 3);

      expect(list.lastWhere((e) => e.value >= 5).value, 6);

      expect(
        () => list.lastWhereOrNull((e) {
          e.unlink();
          return e.value >= 5;
        }),
        throwsA(
          predicate(
            (e) =>
                e is ConcurrentModificationError &&
                identical(e.modifiedObject, list),
          ),
        ),
      );
      expect(list.values, [4, 5]);
      expect(list.reversed.values, [5, 4]);
      expect(list.length, 2);

      // single

      expect(list.singleOrNull, null);
      expect(
        () => list.single,
        throwsA(
          predicate(
            (e) => e is StateError && e.message == 'Too many elements',
          ),
        ),
      );

      expect(list.singleWhereOrNull((e) => e.value >= 5)?.value, 5);
      expect(list.singleWhereOrNull((e) => e.value >= 6)?.value, null);
      expect(
        () => list.singleWhereOrNull((e) => e.value >= 4),
        throwsA(
          predicate(
            (e) => e is StateError && e.message == 'Too many elements',
          ),
        ),
      );

      expect(list.singleWhere((e) => e.value >= 5).value, 5);
      expect(
        () => list.singleWhere((e) => e.value >= 6),
        throwsA(
          predicate(
            (e) => e is StateError && e.message == 'No such element',
          ),
        ),
      );
      expect(
        () => list.singleWhere((e) => e.value >= 4),
        throwsA(
          predicate(
            (e) => e is StateError && e.message == 'Too many elements',
          ),
        ),
      );

      expect(
        () => list.singleWhereOrNull((e) {
          e.unlink();
          return e.value >= 5;
        }),
        throwsA(
          predicate(
            (e) =>
                e is ConcurrentModificationError &&
                identical(e.modifiedObject, list),
          ),
        ),
      );
      expect(list.values, [5]);
      expect(list.reversed.values, [5]);
      expect(list.length, 1);

      list.addFirst(Item(4));
      expect(
        () => list.singleWhere((e) {
          e.unlink();
          return e.value >= 5;
        }),
        throwsA(
          predicate(
            (e) =>
                e is ConcurrentModificationError &&
                identical(e.modifiedObject, list),
          ),
        ),
      );
      expect(list.values, [5]);
      expect(list.reversed.values, [5]);
      expect(list.length, 1);

      expect(list.singleOrNull?.value, 5);
      expect(list.single.value, 5);

      list.clear();
      expect(list.values, <int>[]);
      expect(list.length, 0);

      expect(list.singleOrNull?.value, null);
      expect(
        () => list.single,
        throwsA(
          predicate(
            (e) => e is StateError && e.message == 'No such element',
          ),
        ),
      );

      // first/last

      expect(list.firstOrNull, null);
      expect(
        () => list.first,
        throwsA(
          predicate(
            (e) => e is StateError && e.message == 'No such element',
          ),
        ),
      );

      expect(list.lastOrNull, null);
      expect(
        () => list.last,
        throwsA(
          predicate(
            (e) => e is StateError && e.message == 'No such element',
          ),
        ),
      );
    });

    test('Item properties', () {
      final list = LinkedList<Item>();
      final item1 = Item(1);
      final item2 = Item(2);
      final item3 = Item(3);

      expect(item1.unlinked, isTrue);
      expect(
        () => item1.list,
        throwsA(
          predicate(
            (e) => e is StateError && e.message == 'The element is unlinked',
          ),
        ),
      );
      expect(
        () => item1.next,
        throwsA(
          predicate(
            (e) => e is StateError && e.message == 'The element is unlinked',
          ),
        ),
      );
      expect(
        () => item1.previous,
        throwsA(
          predicate(
            (e) => e is StateError && e.message == 'The element is unlinked',
          ),
        ),
      );

      list.add(item1);
      expect(item1.unlinked, isFalse);
      expect(item1.list, list);
      expect(item1.next, null);
      expect(item1.previous, null);

      expect(item2.unlinked, isTrue);

      item2.insertAfter(item1);
      expect(item2.unlinked, isFalse);
      expect(item2.list, list);
      expect(item2.next, null);
      expect(item2.previous, item1);
      expect(item1.next, item2);

      expect(item3.unlinked, isTrue);

      item3.insertBefore(item1);
      expect(item3.unlinked, isFalse);
      expect(item3.list, list);
      expect(item3.next, item1);
      expect(item3.previous, null);
      expect(item1.previous, item3);

      expect(list.values, [3, 1, 2]);
      expect(list.length, 3);
    });

    test('unlinkWhere', () {
      final list = LinkedList<Item>()..addAll([3, 1, 2].map(Item.new));

      final unlinkedList = list.unlinkWhere((e) => e.value <= 2);
      expect(unlinkedList.values, [1, 2]);
      expect(unlinkedList.length, 2);
      expect(list.values, [3]);
      expect(list.length, 1);

      list.addFirstAll(unlinkedList);
      expect(list.values, [1, 2, 3]);
      expect(list.length, 3);
    });

    test('unlinkWhere', () {
      final list1 = LinkedList<Item>()..addAll([3, 1, 2].map(Item.new));
      final list2 = LinkedList<Item>();

      expect(
        () {
          for (final item in list1) {
            item.unlink();
            list2.add(item);
          }
        },
        throwsA(
          predicate(
            (e) =>
                e is ConcurrentModificationError &&
                identical(e.modifiedObject, list1),
          ),
        ),
      );
    });

    test('for/forEach', () {
      final list = LinkedList<Item>()..addAll([1, 2, 3].map(Item.new));
      final handled = <Item>[];

      for (final item in list) {
        handled.add(item);
        list.removeWhere((e) => e.value < 3);
      }

      expect(list.values, [3]);
      expect(list.length, 1);
      expect(handled.values, [1, 3]);

      handled.clear();
      list
        ..clear()
        ..addAll([1, 2, 3].map(Item.new))
        ..forEach((item) {
          handled.add(item);
          list.removeWhere((e) => e.value < 3);
        });

      expect(list.values, [3]);
      expect(list.length, 1);
      expect(handled.values, [1, 3]);
    });
  });
}
