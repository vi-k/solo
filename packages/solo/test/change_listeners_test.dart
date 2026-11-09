@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

void main() {
  group('addChangeListener', () {
    test('every change arrives with its pair, in order', () {
      final counter = _Counter();
      final pairs = <String>[];
      counter
        ..addChangeListener(
          (previous, current) => pairs.add('$previous>$current'),
        )
        ..set(1)
        ..set(2)
        ..set(3);
      expect(pairs, ['0>1', '1>2', '2>3']);
    });

    for (final pairFirst in [true, false]) {
      final order = pairFirst ? 'pair first' : 'plain first';

      test('a nested write from a plain listener arrives as the next pair, '
          '$order', () {
        final counter = _Counter();
        final pairs = <String>[];
        void pair(int previous, int current) => pairs.add('$previous>$current');
        void plain() {
          if (counter.currentState == 1) {
            counter.set(2);
          }
        }

        if (pairFirst) {
          counter
            ..addChangeListener(pair)
            ..addListener(plain);
        } else {
          counter
            ..addListener(plain)
            ..addChangeListener(pair);
        }
        counter.set(1);
        expect(pairs, ['0>1', '1>2']);
      });

      test('a return to the old state is two changes, $order', () {
        final counter = _Counter();
        final pairs = <String>[];
        void pair(int previous, int current) => pairs.add('$previous>$current');
        void plain() {
          if (counter.currentState == 1) {
            counter.set(0);
          }
        }

        if (pairFirst) {
          counter
            ..addChangeListener(pair)
            ..addListener(plain);
        } else {
          counter
            ..addListener(plain)
            ..addChangeListener(pair);
        }
        counter.set(1);
        expect(pairs, ['0>1', '1>0']);
      });

      test("a pair listener sees the plain listener's nested write in "
          'currentState, $order', () {
        final counter = _Counter();
        final seen = <String>[];
        void pair(int previous, int current) =>
            seen.add('$previous>$current at ${counter.currentState}');
        void plain() {
          if (counter.currentState == 1) {
            counter.set(2);
          }
        }

        if (pairFirst) {
          counter
            ..addChangeListener(pair)
            ..addListener(plain);
        } else {
          counter
            ..addListener(plain)
            ..addChangeListener(pair);
        }
        counter.set(1);
        expect(seen, ['0>1 at 2', '1>2 at 2']);
      });
    }

    test('a nested write from a pair listener arrives as the next pair', () {
      final counter = _Counter();
      final pairs = <String>[];
      counter
        ..addChangeListener((previous, current) {
          pairs.add('first $previous>$current');
          if (current == 1) {
            counter.set(2);
          }
        })
        ..addChangeListener(
          (previous, current) => pairs.add('second $previous>$current'),
        )
        ..set(1);
      expect(pairs, ['first 0>1', 'second 0>1', 'first 1>2', 'second 1>2']);
    });

    test('the same object written twice is two changes', () {
      final counter = _Counter();
      final pairs = <String>[];
      counter
        ..addChangeListener(
          (previous, current) => pairs.add('$previous>$current'),
        )
        ..set(1)
        ..set(1);
      expect(pairs, ['0>1', '1>1']);
    });

    test('pairs come after the plain listeners of the same change', () {
      final counter = _Counter();
      final log = <String>[];
      counter
        ..addChangeListener(
          (previous, current) => log.add('pair $previous>$current'),
        )
        ..addListener(() => log.add('plain ${counter.currentState}'))
        ..set(1);
      expect(log, ['plain 1', 'pair 0>1']);
    });

    test('a listener removed during a pass is not called, one added hears '
        'the next change', () {
      final counter = _Counter();
      final log = <String>[];
      void removed(int previous, int current) => log.add('removed $current');
      void added(int previous, int current) => log.add('added $current');
      counter
        ..addChangeListener((previous, current) {
          log.add('first $current');
          if (current == 1) {
            counter
              ..removeChangeListener(removed)
              ..addChangeListener(added);
          }
        })
        ..addChangeListener(removed)
        ..set(1)
        ..set(2);
      expect(log, ['first 1', 'first 2', 'added 2']);
    });

    test('removeChangeListener matches with == and removes one '
        'registration', () {
      final counter = _Counter();
      final holder = _Holder();
      counter
        ..addChangeListener(holder.heard)
        ..removeChangeListener(holder.heard)
        ..set(1);
      expect(holder.calls, 0);

      var calls = 0;
      void twice(int previous, int current) => calls++;
      counter
        ..addChangeListener(twice)
        ..addChangeListener(twice)
        ..removeChangeListener(twice)
        ..set(2);
      expect(calls, 1);
    });

    test('a failing pair listener goes to onListenerError and the rest are '
        'called', () {
      final counter = _Counter();
      final pairs = <String>[];
      counter
        ..addChangeListener((previous, current) => throw StateError('pair'))
        ..addChangeListener(
          (previous, current) => pairs.add('$previous>$current'),
        )
        ..set(1);
      expect(counter.listenerErrors, hasLength(1));
      expect(counter.listenerErrors.single, isA<StateError>());
      expect(pairs, ['0>1']);
    });

    test('a write during close is heard, and after isFinished the listeners '
        'are gone', () async {
      final counter = _Counter(onClosing: (counter) => counter.set(9));
      final pairs = <String>[];
      counter.addChangeListener(
        (previous, current) => pairs.add('$previous>$current'),
      );

      await counter.close();
      expect(pairs, ['0>9']);
      expect(counter.isFinished, isTrue);
      expect(counter.listening, isFalse);

      counter.addChangeListener((previous, current) => pairs.add('late'));
      expect(counter.listening, isFalse);
    });

    test('hasListeners counts a pair listener', () {
      final counter = _Counter();
      expect(counter.listening, isFalse);
      void pair(int previous, int current) {}
      counter.addChangeListener(pair);
      expect(counter.listening, isTrue);
      counter.removeChangeListener(pair);
      expect(counter.listening, isFalse);
    });
  });
}

final class _Counter extends Solo<int> {
  final void Function(_Counter counter)? onClosing;
  final listenerErrors = <Object>[];

  _Counter({this.onClosing}) : super(0);

  void set(int next) => externalSetState(next);

  bool get listening => hasListeners;

  @override
  void onListenerError(Object error, StackTrace stackTrace) {
    listenerErrors.add(error);
  }

  @override
  FutureOr<void> onClose() {
    onClosing?.call(this);
  }
}

final class _Holder {
  int calls = 0;

  void heard(int previous, int current) => calls++;
}
