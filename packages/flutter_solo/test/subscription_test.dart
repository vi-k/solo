import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo/listenable.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reachability.dart';

final class _Counter extends Solo<int> with SoloListenable {
  _Counter() : super(0);

  void set(int value) => externalSetState(value);
}

/// A controller whose `removeListener` refuses, the way a listenable of
/// somebody's own may.
final class _Stuck extends Solo<int> with SoloListenable {
  _Stuck() : super(0);

  void set(int value) => externalSetState(value);

  @override
  void removeListener(VoidCallback listener) =>
      throw StateError('this one does not let go');
}

/// A listenable whose `addListener` keeps the callback and then throws,
/// the way a source that starts up lazily and fails at it may.
final class _Failing implements Listenable {
  final listeners = <VoidCallback>[];

  @override
  void addListener(VoidCallback listener) {
    listeners.add(listener);
    throw StateError('could not start');
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners.remove(listener);
  }

  void notify() {
    for (final listener in List.of(listeners)) {
      listener();
    }
  }
}

/// A listenable that knows a listener by identity, not by `==`: a
/// tear-off made again for `removeListener` is not found.
final class _ByIdentity implements Listenable {
  final _listeners = <VoidCallback>[];

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) {
    final index = _listeners.indexWhere((each) => identical(each, listener));
    if (index >= 0) {
      _listeners.removeAt(index);
    }
  }

  void notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}

/// A notifier that runs [onRemove] each time a listener is taken back:
/// `removeListener` is the source's code, free to do anything there.
final class _Watched extends ChangeNotifier {
  _Watched(this.onRemove);

  final void Function() onRemove;

  bool get listened => hasListeners;

  @override
  void removeListener(VoidCallback listener) {
    onRemove();
    super.removeListener(listener);
  }
}

/// A subscription made, put into [group] and cancelled on its own, in a
/// frame of its own: a closure captures the variable, not the value, so a
/// payload left in the test would be held by the test. The payload,
/// weakly.
WeakReference<Object> _cancelledAlone(SoloSubscriptions group) {
  final payload = List<int>.filled(1024, 7);
  ValueNotifier(0).listen(() => payload.length)
    ..addTo(group)
    ..cancel();
  return WeakReference(payload);
}

/// A group of two dropped without being cancelled, in a frame of its own:
/// one member comes back, the other closed over a payload. The kept member
/// and the payload, weakly.
(SoloSubscription, WeakReference<Object>) _droppedGroup() {
  final payload = List<int>.filled(1024, 7);
  final group = SoloSubscriptions();
  final kept = ValueNotifier(0).listen(() {})..addTo(group);
  ValueNotifier(0).listen(() => payload.length).addTo(group);
  return (kept, WeakReference(payload));
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

  test('a source that registers and then throws keeps no listener', () {
    final source = _Failing();
    var calls = 0;

    // Nobody gets the subscription back, so nobody could cancel it.
    expect(() => source.listen(() => calls++), throwsStateError);
    source.notify();
    expect(source.listeners, isEmpty);
    expect(calls, 0);
  });

  test('a source that cannot let go no longer calls a cancelled listener', () {
    final stuck = _Stuck();
    var calls = 0;
    final subscription = stuck.listen(() => calls++);

    expect(subscription.cancel, throwsStateError);
    expect(subscription.isCancelled, isTrue);
    stuck.set(1);
    expect(calls, 0, reason: 'the source kept it, the subscription did not');
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

  test(
    'cancelling one of two subscriptions of a closure takes back its own',
    () {
      final counter = _Counter();
      final notifier = ValueNotifier(0);
      final byIdentity = _ByIdentity();
      for (final (source, change) in <(Listenable, void Function())>[
        (counter, () => counter.set(1)),
        (notifier, () => notifier.value = 1),
        (byIdentity, byIdentity.notify),
      ]) {
        final heard = <String>[];
        void a() => heard.add('A');
        void b() => heard.add('B');
        source
          ..listen(a)
          ..listen(b)
          ..listen(a).cancel();
        change();
        expect(heard, [
          'A',
          'B',
        ], reason: '$source: the last A went, not the first');
      }
    },
  );

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

  test('a member cancelled on its own is let go of at once', () async {
    final listening = SoloSubscriptions();
    final payload = _cancelledAlone(listening);

    expect(
      await collected(payload),
      isTrue,
      reason:
          'held on to until the next add or read of length, it keeps '
          'the listener and everything it closed over',
    );
    expect(listening.length, 0);
  });

  test('a member kept on its own does not keep its group', () async {
    final (kept, payload) = _droppedGroup();

    expect(
      await collected(payload),
      isTrue,
      reason:
          'the group was dropped; through it, one member would hold '
          'every other and everything they closed over',
    );
    expect(kept.isCancelled, isFalse, reason: 'the member is kept to the end');
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
    expect(errors, [
      isStateError,
      isStateError,
    ], reason: 'every refusal is reported, none is thrown');
    expect(last.isCancelled, isTrue, reason: 'the pass went on to the end');

    counter.set(1);
    expect(calls, 0);
  });

  test(
    'a source that reads or changes the group does not cut the walk short',
    () {
      final listening = SoloSubscriptions();
      late final SoloSubscription last;
      final lengths = <int>[];
      final source = _Watched(() {
        lengths.add(listening.length);
        last.cancel();
      });
      addTearDown(source.dispose);
      final members = [
        for (var i = 0; i < 3; i++) source.listen(() {})..addTo(listening),
      ];
      last = members.last;

      listening.cancel();

      expect(members.map((member) => member.isCancelled), everyElement(isTrue));
      expect(source.listened, isFalse, reason: 'every listener taken back');
      expect(lengths, everyElement(0), reason: 'the group is empty by then');
    },
  );

  test('a reporter that throws does not stop the walk', () {
    final stuck = _Stuck();
    final counter = _Counter();
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => throw StateError('reporter');
    addTearDown(() => FlutterError.onError = previous);
    final listening = SoloSubscriptions();
    stuck.listen(() {}).addTo(listening);
    final last = counter.listen(() {})..addTo(listening);
    final zone = <String>[];

    runZonedGuarded(
      listening.cancel,
      (error, stackTrace) => zone.add('$error'),
    );

    expect(zone, [
      'Bad state: this one does not let go',
      'Bad state: reporter',
    ]);
    expect(last.isCancelled, isTrue, reason: 'the pass went on to the end');
  });

  testWidgets('a member that cannot let go does not stop the frame', (
    tester,
  ) async {
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
