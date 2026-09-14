import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Counter extends SoloListenable<int> {
  _Counter() : super(0);

  @override
  bool get hasListeners => super.hasListeners;

  void set(int value) => externalSetState(value);
}

final class _ObjectController extends SoloListenable<Object> {
  _ObjectController(super.initialState);

  void set(Object value) => externalSetState(value);
}

final class _ClosingObserver extends SoloObserver {
  final void Function(SoloBase<Object> solo) onCloseCallback;

  _ClosingObserver(this.onCloseCallback);

  @override
  void onClose(SoloBase<Object> solo) => onCloseCallback(solo);
}

void main() {
  testWidgets('controller works with ValueListenableBuilder', (tester) async {
    final counter = _Counter();
    addTearDown(counter.close);
    final built = <int>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<int>(
          valueListenable: counter,
          builder: (context, value, _) {
            built.add(value);
            return Text('$value');
          },
        ),
      ),
    );
    expect(built, [0]);
    expect(find.text('0'), findsOneWidget);

    counter.set(1);
    await tester.pump();
    expect(built, [0, 1]);
    expect(find.text('1'), findsOneWidget);

    counter.set(2);
    await tester.pump();
    expect(built, [0, 1, 2]);
    expect(find.text('2'), findsOneWidget);
  });

  test('value mirrors state', () async {
    final counter = _Counter();
    expect(counter.value, 0);
    counter.set(1);
    expect(counter.value, 1);
    expect(counter.value, counter.currentState);
    expect(identical(counter.value, counter.currentState), isTrue);
    await counter.close();
  });

  test('value stays final after the controller finishes closing', () async {
    final counter = _Counter()..set(1);
    await counter.close();

    expect(() => counter.set(2), throwsA(isA<StateError>()));
    expect(counter.value, 1);
  });

  test('value and currentState are the exact same object', () async {
    final initial = Object();
    final next = Object();
    final controller = _ObjectController(initial);
    expect(identical(controller.value, controller.currentState), isTrue);
    expect(identical(controller.value, initial), isTrue);

    controller.set(next);
    expect(identical(controller.value, controller.currentState), isTrue);
    expect(identical(controller.value, next), isTrue);
    await controller.close();
  });

  test('listeners fire inside the change, not on a microtask', () async {
    final counter = _Counter();
    final order = <String>[];
    counter
      ..addListener(() => order.add('listener'))
      ..set(1);
    order.add('after set');
    await Future<void>.microtask(() => order.add('microtask'));
    expect(order, ['listener', 'after set', 'microtask']);
    await counter.close();
  });

  test('a listener removed during notification is not called', () async {
    final counter = _Counter();
    final calls = <String>[];
    late void Function() second;
    counter.addListener(() {
      calls.add('first');
      counter.removeListener(second);
    });
    second = () => calls.add('second');
    counter
      ..addListener(second)
      ..set(1);
    expect(calls, ['first']);
    await counter.close();
  });

  test('a listener added during notification gets the next change', () async {
    final counter = _Counter();
    final calls = <String>[];
    var added = false;
    counter.addListener(() {
      calls.add('first');
      if (!added) {
        added = true;
        counter.addListener(() => calls.add('late'));
      }
    });
    counter.set(1);
    expect(calls, ['first']);
    counter.set(2);
    expect(calls, ['first', 'first', 'late']);
    await counter.close();
  });

  test('a listener registered twice is called twice', () async {
    final counter = _Counter();
    var calls = 0;
    void listener() => calls++;
    counter
      ..addListener(listener)
      ..addListener(listener)
      ..set(1);
    expect(calls, 2);
    counter
      ..removeListener(listener)
      ..set(2);
    expect(calls, 3, reason: 'one removal drops one registration');
    await counter.close();
  });

  test('a throwing listener is reported and the rest still hear', () async {
    final counter = _Counter();
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);

    final calls = <String>[];
    counter
      ..addListener(() => calls.add('before'))
      ..addListener(() => throw StateError('the listener blew up'))
      ..addListener(() => calls.add('after'))
      ..set(1);

    expect(calls, ['before', 'after']);
    expect(reports, hasLength(1));
    final details = reports.single;
    expect(details.exception, isA<StateError>());
    expect(details.library, 'flutter_solo');
    expect(
      details.context.toString(),
      contains('notifying a listener of _Counter'),
    );
    await counter.close();
  });

  test('a throwing listener does not hold back the rules', () async {
    final counter = _Counter();
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = previous);

    final job = counter.run<int, void>(
      keepWhile: (state) => state < 10,
      (ctx) => ctx.wait(() => Future<void>.delayed(const Duration(days: 1))),
    )..ignore();
    await Future<void>.delayed(Duration.zero);

    counter
      ..addListener(() => throw StateError('the listener blew up'))
      ..set(42);
    await Future<void>.delayed(Duration.zero);

    expect(
      job.outcome,
      isA<Cancelled>(),
      reason: 'the state no longer matches keepWhile',
    );
    await counter.close();
  });

  test('close removes every listener', () async {
    final counter = _Counter()..addListener(() {});
    expect(counter.hasListeners, isTrue);

    await counter.close();

    expect(counter.hasListeners, isFalse);
  });

  test('a job emit notifies listeners', () async {
    final counter = _Counter();
    final seen = <int>[];
    counter.addListener(() => seen.add(counter.value));
    await counter.run<int, void>((ctx) async {
      ctx
        ..emit(5)
        ..emit(6);
    }).done;
    expect(seen, [5, 6]);
    await counter.close();
  });

  test(
    'a listener added after close hears nothing and is not retained',
    () async {
      final counter = _Counter();
      await counter.close();

      final calls = <int>[];
      expect(counter.hasListeners, isFalse);
      counter.addListener(() => calls.add(counter.value));
      expect(counter.hasListeners, isFalse);

      expect(() => counter.set(7), throwsA(isA<StateError>()));
      expect(counter.value, 0);
      expect(calls, isEmpty);
    },
  );

  test('close returns the same future on repeated calls', () async {
    final counter = _Counter();
    final first = counter.close();
    final second = counter.close();
    expect(identical(first, second), isTrue);
    await first;
  });

  test(
    'a microtask scheduled from observer.onClose does not notify listeners',
    () async {
      final counter = _Counter();
      final heard = <int>[];
      counter.addListener(() => heard.add(counter.value));

      final previousObserver = SoloBase.observer;
      Object? error;
      // Both checks live inside the microtask: taken after it, they would
      // also pass if the drop happened later than the boundary claims.
      bool? retainedInMicrotask;
      SoloBase.observer = _ClosingObserver((solo) {
        if (identical(solo, counter)) {
          scheduleMicrotask(() {
            retainedInMicrotask = counter.hasListeners;
            try {
              counter.set(9);
            } on Object catch (caught) {
              error = caught;
            }
          });
        }
      });
      addTearDown(() => SoloBase.observer = previousObserver);

      await counter.close();
      await Future<void>.delayed(Duration.zero);

      expect(retainedInMicrotask, isFalse);
      expect(counter.hasListeners, isFalse);
      expect(counter.value, 0);
      expect(heard, isEmpty);
      expect(error, isA<StateError>());
    },
  );

  test(
    'a synchronous change from observer.onClose notifies listeners before drop',
    () async {
      final counter = _Counter();
      final heard = <int>[];
      counter.addListener(() => heard.add(counter.value));

      final previousObserver = SoloBase.observer;
      SoloBase.observer = _ClosingObserver((solo) {
        if (identical(solo, counter)) {
          counter.set(8);
        }
      });
      addTearDown(() => SoloBase.observer = previousObserver);

      await counter.close();

      expect(counter.value, 8);
      expect(heard, [8]);
    },
  );
}
