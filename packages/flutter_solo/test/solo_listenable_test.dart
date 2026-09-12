import 'package:flutter/foundation.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Counter extends SoloListenable<int> {
  _Counter() : super(0);

  void set(int value) => externalSetState(value);
}

void main() {
  test('value mirrors state', () async {
    final counter = _Counter();
    expect(counter.value, 0);
    counter.set(1);
    expect(counter.value, 1);
    expect(counter.value, counter.currentState);
    await counter.close();
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
    final errors = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exception);
    addTearDown(() => FlutterError.onError = previous);

    final calls = <String>[];
    counter
      ..addListener(() => calls.add('before'))
      ..addListener(() => throw StateError('the listener blew up'))
      ..addListener(() => calls.add('after'))
      ..set(1);

    expect(calls, ['before', 'after']);
    expect(errors, [isStateError]);
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
    final counter = _Counter();
    var calls = 0;
    counter.addListener(() => calls++);
    await counter.close();
    counter.set(1);
    expect(calls, 0);
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

  test('a listener added after close hears nothing', () async {
    final counter = _Counter();
    await counter.close();

    final calls = <int>[];
    counter.addListener(() => calls.add(counter.value));
    counter.set(7);

    expect(counter.value, 7);
    expect(calls, isEmpty);
  });

  test('close returns the same future on repeated calls', () async {
    final counter = _Counter();
    final first = counter.close();
    final second = counter.close();
    expect(identical(first, second), isTrue);
    await first;
  });
}
