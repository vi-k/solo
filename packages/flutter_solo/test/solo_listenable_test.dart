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
    expect(counter.value, counter.state);
    await counter.close();
  });

  test('listeners fire now, the stream on the next microtask', () async {
    final counter = _Counter();
    final order = <String>[];
    counter.stream.listen((_) => order.add('stream'));
    counter
      ..addListener(() => order.add('listener'))
      ..set(1);
    expect(order, ['listener']);
    await Future<void>.microtask(() {});
    expect(order, ['listener', 'stream']);
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

  test('close returns the same future on repeated calls', () async {
    final counter = _Counter();
    final first = counter.close();
    final second = counter.close();
    expect(identical(first, second), isTrue);
    await first;
  });
}
