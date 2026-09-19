import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo/listenable.dart';
import 'package:flutter_test/flutter_test.dart';

@immutable
final class _Screen {
  final String name;
  final int progress;

  const _Screen({this.name = '', this.progress = 0});

  _Screen copyWith({String? name, int? progress}) => _Screen(
        name: name ?? this.name,
        progress: progress ?? this.progress,
      );
}

final class _Controller extends Solo<_Screen> with SoloListenable {
  _Controller() : super(const _Screen());

  void set(_Screen next) => externalSetState(next);
}

final class _PlainController extends Solo<_Screen> {
  _PlainController() : super(const _Screen());

  void set(_Screen next) => externalSetState(next);
}

final class _SubscribePublishingSource implements ValueListenable<int> {
  final _listeners = <VoidCallback>[];
  var _value = 0;
  var _published = false;

  @override
  int get value => _value;

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
    if (_published) {
      return;
    }
    _published = true;
    _value = 1;
    for (final current in List<VoidCallback>.of(_listeners)) {
      current();
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }
}

final class _ReentrantSource implements ValueListenable<int> {
  final _listeners = <VoidCallback>[];
  int subscriptionCount = 0;
  var _value = 0;
  VoidCallback? onFirstSubscription;

  @override
  int get value => _value;

  @override
  void addListener(VoidCallback listener) {
    subscriptionCount++;
    _listeners.add(listener);
    final callback = onFirstSubscription;
    onFirstSubscription = null;
    callback?.call();
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void set(int value) {
    _value = value;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }
}

final class _ThrowingSource implements ValueListenable<int> {
  final _listeners = <VoidCallback>[];
  final error = StateError('subscription failed');
  var _value = 0;
  bool failNextSubscription = true;

  @override
  int get value => _value;

  int get listenerCount => _listeners.length;

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
    if (failNextSubscription) {
      failNextSubscription = false;
      throw error;
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void set(int value) {
    _value = value;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }
}

/// A controller with a `select` of its own: the extension must step aside
/// and leave this member the winner.
final class _ListController extends Solo<String> with SoloListenable {
  _ListController() : super('');

  void select(String id) => externalSetState(id);
}

void main() {
  test('of selects from a Solo controller and respects compare', () async {
    final controller = _PlainController();
    addTearDown(controller.close);
    final name = SoloSelection.of(
      controller,
      (state) => state.name,
      compare: (previous, current) =>
          previous.toLowerCase() != current.toLowerCase(),
    );
    var calls = 0;
    name.addListener(() => calls++);

    controller
      ..set(const _Screen(name: 'Ada'))
      ..set(const _Screen(name: 'ADA'))
      ..set(const _Screen(name: 'Grace'));

    expect(name.value, 'Grace');
    expect(calls, 2);
  });

  test('of selects from a SoloListenable controller', () async {
    final controller = _Controller();
    addTearDown(controller.close);
    final progress = SoloSelection.of(controller, (state) => state.progress);
    final values = <int>[];
    progress.addListener(() => values.add(progress.value));

    controller.set(const _Screen(progress: 7));

    expect(progress.value, 7);
    expect(values, [7]);
  });

  test('nullable source selection keeps the existing constructor working', () {
    final source = ValueNotifier<int?>(null);
    addTearDown(source.dispose);
    final selection = SoloSelection<int?, int>(source, (value) => value ?? 0);
    final values = <int>[];
    selection.addListener(() => values.add(selection.value));

    source.value = 3;

    expect(selection.value, 3);
    expect(values, [3]);
  });

  testWidgets(
    'the first value published during subscription reaches the builder',
    (tester) async {
      final source = _SubscribePublishingSource();
      final selection = SoloSelection(source, (value) => value);
      final built = <int>[];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<int>(
            valueListenable: selection,
            builder: (context, value, _) {
              built.add(value);

              return Text('$value');
            },
          ),
        ),
      );
      await tester.pump();

      expect(built, [0, 1]);
      expect(find.text('1'), findsOneWidget);
    },
  );

  test('a failed source subscription rolls back the listener', () {
    final source = _ThrowingSource();
    final selection = SoloSelection(source, (value) => value);
    var calls = 0;
    void listener() => calls++;

    expect(() => selection.addListener(listener), throwsA(source.error));
    expect(source.listenerCount, 0);

    selection.addListener(listener);
    source.set(1);
    expect(calls, 1, reason: 'the failed registration was removed');

    selection.removeListener(listener);
    expect(source.listenerCount, 0);
  });

  test('a reentrant listener does not subscribe to the source twice', () {
    final source = _ReentrantSource();
    late final SoloSelection<int, int> selection;
    var reentrantCalls = 0;
    selection = SoloSelection(source, (value) => value);
    source.onFirstSubscription = () {
      selection.addListener(() => reentrantCalls++);
    };

    selection.addListener(() {});
    source.set(1);

    expect(source.subscriptionCount, 1);
    expect(reentrantCalls, 1);
  });

  test('a change that leaves the pick alone notifies nobody', () {
    final controller = _Controller();
    final name = controller.select((state) => state.name);
    var calls = 0;
    name.addListener(() => calls++);

    for (var progress = 1; progress <= 10; progress++) {
      controller.set(controller.currentState.copyWith(progress: progress));
    }
    expect(calls, 0);
    expect(name.value, '');

    controller.set(controller.currentState.copyWith(name: 'Ada'));
    expect(calls, 1);
    expect(name.value, 'Ada');
  });

  test('value answers without a listener and stays fresh', () {
    final controller = _Controller();
    final name = controller.select((state) => state.name);
    expect(name.value, '');
    controller.set(const _Screen(name: 'Ada'));
    expect(name.value, 'Ada', reason: 'computed on the spot, not kept stale');
  });

  test('the source is subscribed to only while somebody listens', () {
    final controller = _Controller();
    var picks = 0;
    final name = controller.select((state) {
      picks++;

      return state.name;
    });

    controller.set(const _Screen(progress: 1));
    expect(picks, 0, reason: 'neither the constructor nor the change picked');

    void listener() {}
    name.addListener(listener);
    picks = 0;
    controller.set(const _Screen(progress: 2));
    expect(picks, 1, reason: 'subscribed: the change is picked');

    name.removeListener(listener);
    picks = 0;
    controller.set(const _Screen(progress: 3));
    expect(picks, 0, reason: 'the last listener took the subscription away');
  });

  test('a listener reads back the pick its notification was decided on', () {
    final controller = _Controller();
    var picks = 0;
    final name = controller.select((state) {
      picks++;

      return state.name;
    });
    final heard = <String>[];
    name.addListener(() => heard.add(name.value));
    expect(picks, 1, reason: 'subscribing picks once');

    picks = 0;
    controller.set(const _Screen(name: 'Ada'));
    expect(heard, ['Ada']);
    expect(picks, 1, reason: 'the change is picked once, not again on read');
  });

  test('a source that changes its value in place is picked again', () {
    final source = _InPlaceSource();
    final length = SoloSelection<List<int>, int>(source, (list) => list.length);
    final heard = <int>[];
    length.addListener(() => heard.add(length.value));

    source.grow();
    expect(heard, [1], reason: 'the notification is the sign, not identity');
    expect(length.value, 1);
  });

  test('a source changed in place while subscribing is picked again', () async {
    final source = _InPlaceSource(growOnFirstListener: true);
    final length = SoloSelection<List<int>, int>(source, (list) => list.length);
    final heard = <int>[];
    length.addListener(() => heard.add(length.value));
    await Future<void>.delayed(Duration.zero);

    expect(heard, [1], reason: 'the notification was held back, not lost');
  });

  test('a selection nobody listens to any more picks every time', () {
    final source = _InPlaceSource();
    final length = SoloSelection<List<int>, int>(source, (list) => list.length);
    void listener() {}
    length
      ..addListener(listener)
      ..removeListener(listener);

    source.grow();
    expect(length.value, 1, reason: 'no subscription, so nothing kept');
  });

  test('subscribing to a source that stays put announces nothing', () async {
    final controller = _Controller();
    // A new list on every pick is never `==` to the last one.
    final names = controller.select((state) => [state.name]);
    var calls = 0;
    names.addListener(() => calls++);
    await Future<void>.delayed(Duration.zero);

    expect(calls, 0, reason: 'nothing moved while it was subscribed to');
  });

  test('a pick made before the first listener is refreshed on subscribing', () {
    final controller = _Controller();
    final name = controller.select((state) => state.name);
    controller.set(const _Screen(name: 'Ada'));

    var calls = 0;
    name.addListener(() => calls++);
    controller.set(const _Screen(name: 'Ada', progress: 1));

    expect(calls, 0, reason: 'the pick has been Ada since before the listener');
    expect(name.value, 'Ada');
  });

  test('compare replaces the answer about a change', () {
    final controller = _Controller();
    final name = controller.select(
      (state) => state.name,
      compare: (previous, current) =>
          previous.toLowerCase() != current.toLowerCase(),
    );
    var calls = 0;
    name.addListener(() => calls++);

    controller.set(const _Screen(name: 'Ada'));
    expect(calls, 1);
    controller.set(const _Screen(name: 'ADA'));
    expect(calls, 1, reason: 'the same name to this comparison');
    controller.set(const _Screen(name: 'Grace'));
    expect(calls, 2);
  });

  test('a listener registered twice is called twice', () {
    final controller = _Controller();
    final name = controller.select((state) => state.name);
    var calls = 0;
    void listener() => calls++;
    name
      ..addListener(listener)
      ..addListener(listener);
    controller.set(const _Screen(name: 'Ada'));
    expect(calls, 2);

    name.removeListener(listener);
    controller.set(const _Screen(name: 'Grace'));
    expect(calls, 3, reason: 'one removal drops one registration');
  });

  test('a throwing selector is reported and changes nothing else', () async {
    final controller = _Controller();
    final errors = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exception);
    addTearDown(() => FlutterError.onError = previous);

    final name = controller.select<String>((state) {
      if (state.progress > 0) {
        throw StateError('the selector blew up');
      }

      return state.name;
    })
      ..addListener(() {});

    final job = controller.run<_Screen, void>(
      keepWhile: (state) => state.progress < 10,
      (ctx) => ctx.wait(() => Future<void>.delayed(const Duration(days: 1))),
    )..ignore();
    await Future<void>.delayed(Duration.zero);

    controller.set(const _Screen(progress: 42));
    await Future<void>.delayed(Duration.zero);

    expect(errors, [isStateError]);
    expect(
      job.outcome,
      isA<Cancelled>(),
      reason: 'the rules ran despite the selector',
    );
    expect(name, isA<SoloSelection<_Screen, String>>());
    await controller.close();
  });

  test('a listener that throws misses a rebuild, not the value', () {
    final controller = _Controller();
    final errors = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exception);
    addTearDown(() => FlutterError.onError = previous);

    final name = controller.select((state) => state.name);
    final seen = <String>[];
    var blowUp = true;
    name.addListener(() {
      if (blowUp) {
        blowUp = false;

        throw StateError('the listener blew up');
      }
      seen.add(name.value);
    });

    controller.set(const _Screen(name: 'Ada'));
    expect(errors, [isStateError]);
    expect(seen, isEmpty, reason: 'this notification was lost to the throw');
    expect(name.value, 'Ada', reason: 'value reads the state, not the pick');

    controller.set(const _Screen(name: 'Grace'));
    expect(seen, ['Grace'], reason: 'the next change still gets through');
  });

  test('a select of its own wins over the extension', () {
    final controller = _ListController()..select('row-7');
    expect(controller.value, 'row-7');
  });

  test('a selection of a closed controller answers from the state', () async {
    final controller = _Controller();
    // A `compare` that ignores case lets the source move without an
    // announcement. That is the only way to tell a read of the source from
    // a replay of the last announced pick: after the second change the two
    // differ, and only one of them is the state the controller holds.
    final name = controller.select(
      (state) => state.name,
      // `compare` answers whether the pick CHANGED, the way `!=` does.
      compare: (previous, current) =>
          previous.toLowerCase() != current.toLowerCase(),
    );
    var calls = 0;
    name.addListener(() => calls++);

    controller.set(const _Screen(name: 'Ada'));
    expect(calls, 1, reason: 'an open controller does announce a pick');

    controller.set(const _Screen(name: 'ADA'));
    expect(calls, 1, reason: 'the same pick by `compare`, nothing announced');

    await controller.close();

    expect(name.value, 'ADA', reason: 'the source is read, not replayed');
    expect(
      () => controller.set(const _Screen(name: 'Grace')),
      throwsA(isA<StateError>()),
      reason: 'a closed controller has no state to move',
    );
    expect(calls, 1, reason: 'and therefore announces nothing more');
  });

  test('the source is any value listenable, not only a controller', () {
    final source = ValueNotifier(const _Screen());
    addTearDown(source.dispose);
    final name = source.select((state) => state.name);
    var calls = 0;
    name.addListener(() => calls++);

    source.value = const _Screen(progress: 1);
    expect(calls, 0, reason: 'the progress is not what is picked');

    source.value = const _Screen(name: 'Ada', progress: 1);
    expect(calls, 1);
    expect(name.value, 'Ada');
  });

  test('a selection picked out of a selection narrows further', () {
    final controller = _Controller();
    final name = controller.select((state) => state.name);
    final initial = name.select((it) => it.isEmpty);
    var calls = 0;
    initial.addListener(() => calls++);

    controller.set(const _Screen(name: 'Ada'));
    expect(calls, 1);
    expect(initial.value, isFalse);

    controller.set(const _Screen(name: 'Grace'));
    expect(calls, 1, reason: 'still not empty');
  });

  test('a throwing FlutterError.onError does not abort the selection pass', () {
    final controller = _Controller();
    final zoneErrors = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (_) => throw StateError('the reporter blew up');
    addTearDown(() => FlutterError.onError = previous);

    final name = controller.select((state) => state.name);
    var secondCalled = false;
    name
      ..addListener(() => throw StateError('the listener blew up'))
      ..addListener(() => secondCalled = true);

    runZonedGuarded(() {
      controller.set(const _Screen(name: 'Ada'));
    }, (error, stackTrace) {
      zoneErrors.add(error);
    });

    expect(
      secondCalled,
      isTrue,
      reason: 'the second listener of the selection still receives the event',
    );
    expect(zoneErrors, hasLength(1));
    expect(
      (zoneErrors.first as StateError).message,
      'the reporter blew up',
    );
  });

  test('a source publishing during addListener must not notify synchronously',
      () {
    final selection = SoloSelection<int, int>(EagerSource(), (value) => value);
    var inside = true;
    var calls = 0;
    selection.addListener(() {
      calls++;
      if (inside) {
        fail('notified synchronously from inside addListener');
      }
    });
    inside = false;
    expect(calls, 0, reason: 'nothing may arrive before addListener returns');
  });
}

/// Holds one list and grows it in place, telling its listeners: the value
/// changes while the object stays the same.
final class _InPlaceSource extends ChangeNotifier
    implements ValueListenable<List<int>> {
  _InPlaceSource({this.growOnFirstListener = false});

  final bool growOnFirstListener;

  @override
  final List<int> value = [];

  void grow() {
    value.add(value.length);
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (growOnFirstListener && value.isEmpty) {
      grow();
    }
  }
}

/// Publishes a new value from inside `addListener`, the way a lazy source
/// hooked up on its first subscriber does.
class EagerSource extends ValueNotifier<int> {
  EagerSource() : super(0);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    value = 1;
  }
}
