import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo/listenable.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Counter extends Solo<int> with SoloListenable {
  _Counter() : super(0);

  void set(int value) => externalSetState(value);
}

/// A controller whose `removeListener` refuses, the way a listenable of
/// somebody's own may.
final class _Stuck extends Solo<int> with SoloListenable {
  _Stuck() : super(0);

  @override
  void removeListener(VoidCallback listener) =>
      throw StateError('this one does not let go');
}

/// Records its own `dispose`, so a frame that stopped halfway shows up as
/// a name missing from the list.
final class _Marker extends StatefulWidget {
  const _Marker(this.name, this.disposed);

  final String name;
  final List<String> disposed;

  @override
  State<_Marker> createState() => _MarkerState();
}

final class _MarkerState extends State<_Marker> {
  @override
  void dispose() {
    widget.disposed.add(widget.name);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// The recipe of the README: a group of subscriptions cancelled in
/// `dispose()`.
final class _Listening extends StatefulWidget {
  const _Listening(this.listenable, this.disposed);

  final Listenable listenable;
  final List<String> disposed;

  @override
  State<_Listening> createState() => _ListeningState();
}

final class _ListeningState extends State<_Listening> {
  final _listening = SoloSubscriptions();

  @override
  void initState() {
    super.initState();
    widget.listenable.listen(() {}).addTo(_listening);
  }

  @override
  void dispose() {
    widget.disposed.add('listening');
    _listening.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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

  test('a member cancelled on its own leaves the group', () {
    final counter = _Counter();
    final listening = SoloSubscriptions();
    var first = 0;
    var second = 0;
    final one = counter.listen(() => first++)..addTo(listening);
    counter.listen(() => second++).addTo(listening);
    expect(listening.length, 2);

    one.cancel();
    expect(
      listening.length,
      1,
      reason: 'the group holds what it would cancel, and nothing else',
    );

    counter.set(1);
    expect([first, second], [0, 1]);

    listening.cancel();
    counter.set(2);
    expect([first, second], [0, 1]);
    expect(listening.length, 0);
  });

  test('a group takes no notice of a subscription already cancelled', () {
    final counter = _Counter();
    final listening = SoloSubscriptions();
    counter.listen(() {})
      ..cancel()
      ..addTo(listening);

    expect(listening.length, 0, reason: 'there is nothing left to take back');
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

    listening.cancel();
    expect(
      errors,
      [isStateError, isStateError],
      reason: 'every refusal is reported, none is thrown',
    );
    expect(last.isCancelled, isTrue, reason: 'the pass went on to the end');

    counter.set(1);
    expect(calls, 0);
  });

  testWidgets('a member that cannot let go does not stop the frame',
      (tester) async {
    final stuck = _Stuck();
    final errors = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exception);
    addTearDown(() => FlutterError.onError = previous);
    final disposed = <String>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            _Marker('before', disposed),
            _Listening(stuck, disposed),
            _Marker('after', disposed),
          ],
        ),
      ),
    );
    // The whole tree goes at once, so all three elements are unmounted in
    // one pass. A throw out of the middle `dispose()` used to stop it,
    // and `after` kept its listeners with nobody left to take them back.
    await tester.pumpWidget(const SizedBox.shrink());

    expect(disposed, ['before', 'listening', 'after']);
    expect(errors, [isStateError]);
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

  test('a listenable of the framework is listened to the same way', () {
    final notifier = ValueNotifier(0);
    addTearDown(notifier.dispose);
    var calls = 0;
    final subscription = notifier.listen(() => calls++);

    notifier.value = 1;
    expect(calls, 1);

    subscription.cancel();
    notifier.value = 2;
    expect(calls, 1);
  });
}
