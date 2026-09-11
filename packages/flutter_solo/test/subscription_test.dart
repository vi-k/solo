import 'package:flutter/foundation.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Counter extends SoloListenable<int> {
  _Counter() : super(0);

  void set(int value) => externalSetState(value);
}

/// A controller whose `removeListener` refuses, the way a listenable of
/// somebody's own may.
final class _Stuck extends SoloListenable<int> {
  _Stuck() : super(0);

  @override
  void removeListener(VoidCallback listener) =>
      throw StateError('this one does not let go');
}

void main() {
  test('a subscription takes the listener back', () {
    final counter = _Counter();
    var calls = 0;
    final subscription = counter.listen(() => calls++);

    counter.set(1);
    expect(calls, 1);
    expect(subscription.isCancelled, isFalse);

    subscription.cancel();
    counter.set(2);
    expect(calls, 1);
    expect(subscription.isCancelled, isTrue);
  });

  test('cancelling twice does nothing the second time', () {
    final counter = _Counter();
    var calls = 0;
    final subscription = counter.listen(() => calls++)
      ..cancel()
      ..cancel();

    counter.set(1);
    expect(calls, 0);
    expect(subscription.isCancelled, isTrue);
  });

  test('one closure listened to twice gives two subscriptions', () {
    final counter = _Counter();
    var calls = 0;
    void listener() => calls++;
    final first = counter.listen(listener);
    counter
      ..listen(listener)
      ..set(1);
    expect(calls, 2);
    first.cancel();
    counter.set(2);
    expect(calls, 3, reason: 'the other registration is still there');
  });

  test('a selection is listened to the same way', () {
    final counter = _Counter();
    final even = counter.select((state) => state.isEven);
    final seen = <bool>[];
    final subscription = even.listen(() => seen.add(even.value));

    counter
      ..set(1)
      ..set(3);
    expect(seen, [false], reason: 'the pick did not change the second time');

    subscription.cancel();
    counter.set(4);
    expect(seen, [false]);
  });

  test('a group cancels everything it holds', () {
    final counter = _Counter();
    final even = counter.select((state) => state.isEven);
    final listening = SoloSubscriptions();
    var states = 0;
    var picks = 0;
    counter.listen(() => states++).addTo(listening);
    even.listen(() => picks++).addTo(listening);
    expect(listening.length, 2);

    counter.set(1);
    expect([states, picks], [1, 1]);

    listening.cancel();
    counter.set(2);
    expect([states, picks], [1, 1]);
    expect(listening.isCancelled, isTrue);
    expect(listening.length, 0);
  });

  test('a group that was cancelled cancels what it is handed', () {
    final counter = _Counter();
    final listening = SoloSubscriptions()..cancel();
    var calls = 0;
    final subscription = counter.listen(() => calls++)..addTo(listening);

    counter.set(1);
    expect(calls, 0, reason: 'kept by nobody, so cancelled on the spot');
    expect(subscription.isCancelled, isTrue);
    expect(listening.length, 0);
  });

  test('one member that cannot let go does not keep the others listening', () {
    final stuck = _Stuck();
    final counter = _Counter();
    final errors = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exception);
    addTearDown(() => FlutterError.onError = previous);

    final listening = SoloSubscriptions();
    var calls = 0;
    stuck.listen(() {}).addTo(listening);
    stuck.listen(() {}).addTo(listening);
    final last = counter.listen(() => calls++)..addTo(listening);

    expect(listening.cancel, throwsStateError);
    expect(errors, [isStateError], reason: 'the first throw claimed the throw');
    expect(last.isCancelled, isTrue, reason: 'the pass went on to the end');

    counter.set(1);
    expect(calls, 0);
  });

  test('a group cancelled twice does nothing the second time', () {
    final counter = _Counter();
    var calls = 0;
    final listening = SoloSubscriptions();
    counter.listen(() => calls++).addTo(listening);
    listening
      ..cancel()
      ..cancel();

    counter.set(1);
    expect(calls, 0);
  });
}
