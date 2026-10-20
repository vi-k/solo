import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo/listenable.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reachability.dart';

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

  /// Runs [body] as a job of this controller.
  SoloJob<void> perform(
    Future<void> Function(SoloContext<_Screen, _Screen> ctx) body, {
    bool Function(_Screen state)? keepWhile,
  }) =>
      run<_Screen, void>(body, keepWhile: keepWhile);
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
  test('from selects from a Solo controller and respects changed', () async {
    final controller = _PlainController();
    addTearDown(controller.close);
    final name = SoloSelection.from(
      controller,
      (state) => state.name,
      changed: (previous, current) =>
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

  test('from selects from a SoloListenable controller', () async {
    final controller = _Controller();
    addTearDown(controller.close);
    final progress = SoloSelection.from(controller, (state) => state.progress);
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

  test('a selector that throws on a change in place keeps no old pick', () {
    // The object is the same one, so a pick kept for it from before the
    // notification would answer a read with the length the list had then.
    final errors = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exception);
    addTearDown(() => FlutterError.onError = previous);
    final source = _InPlaceSource();
    var failing = false;
    final length = SoloSelection<List<int>, int>(source, (list) {
      if (failing) {
        failing = false;
        throw StateError('not now');
      }
      return list.length;
    });
    void listener() {}
    length.addListener(listener);

    failing = true;
    source.grow();
    expect(errors, [isStateError]);
    expect(length.value, 1, reason: 'picked afresh, not the pick from before');
  });

  test('a listener of the source ahead of the selection reads the old pick',
      () {
    final source = _InPlaceSource();
    final length = SoloSelection<List<int>, int>(source, (list) => list.length);
    final ahead = <int>[];
    source.addListener(() => ahead.add(length.value));
    void listener() {}
    length.addListener(listener);

    source.grow();
    expect(ahead, [0], reason: 'the selection has not heard the change yet');
    expect(length.value, 1, reason: 'and once it has, the pick is fresh');
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

  test('changed replaces the answer about a change', () {
    final controller = _Controller();
    final name = controller.select(
      (state) => state.name,
      changed: (previous, current) =>
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

    final job = controller.perform(
      keepWhile: (state) => state.progress < 10,
      (ctx) =>
          ctx.abandonable(() => Future<void>.delayed(const Duration(days: 1))),
    )..ignoreFailure();
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
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
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
    expect(reported.map((details) => details.exception), [isStateError]);
    expect(
      '${reported.single.context}',
      matches(RegExp('SoloSelection<[^>]*>#')),
      reason: 'the report names this selection, not just its type',
    );
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
    // A `changed` that ignores case lets the source move without an
    // announcement. That is the only way to tell a read of the source from
    // a replay of the last announced pick: after the second change the two
    // differ, and only one of them is the state the controller holds.
    final name = controller.select(
      (state) => state.name,
      changed: (previous, current) =>
          previous.toLowerCase() != current.toLowerCase(),
    );
    var calls = 0;
    name.addListener(() => calls++);

    controller.set(const _Screen(name: 'Ada'));
    expect(calls, 1, reason: 'an open controller does announce a pick');

    controller.set(const _Screen(name: 'ADA'));
    expect(calls, 1, reason: 'the same pick by `changed`, nothing announced');

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
    expect(
      zoneErrors.map((error) => (error as StateError).message).toList(),
      ['the listener blew up', 'the reporter blew up'],
      reason: 'a reporter that throws does not take with it the failure it '
          'was called about',
    );
  });

  test('a notification put off while subscribing goes out once', () async {
    final source = EagerSource();
    addTearDown(source.dispose);
    final selection = SoloSelection<int, int>(source, (value) => value);
    final heard = <int>[];
    selection.addListener(() => heard.add(selection.value));
    source.value = 2;
    await Future<void>.delayed(Duration.zero);

    expect(heard, [2], reason: 'the newer pick went out, the older is stale');
  });

  test('a notification put off for one subscription skips the next', () async {
    final source = EagerSource();
    addTearDown(source.dispose);
    final selection = SoloSelection<int, int>(source, (value) => value);
    final first = <int>[];
    final second = <int>[];
    void firstListener() => first.add(selection.value);
    selection
      ..addListener(firstListener)
      ..removeListener(firstListener)
      ..addListener(() => second.add(selection.value));
    await Future<void>.delayed(Duration.zero);

    expect(first, isEmpty);
    expect(
      second,
      isEmpty,
      reason: 'the source has not changed since this subscription',
    );
  });

  test('a selection nobody listens to keeps nothing it picked', () async {
    final source = ValueNotifier(<int>[]);
    addTearDown(source.dispose);
    final selection = source.select((list) => list);
    final payload = _pickedThenIdle(source, selection);

    expect(
      await collected(payload),
      isTrue,
      reason: 'kept until the next subscription, the last pick holds a '
          'value the source let go of long ago',
    );
    expect(selection.value, isEmpty);
  });

  test('a source that calls a listener already removed is let be', () {
    final source = _ReentrantSource();
    final selection = SoloSelection<int, int>(source, (value) => value);
    void listener() {}
    // Registered on the source before the selection is, so it runs first
    // and takes the selection's last listener away; the source, walking a
    // copy, calls the selection all the same.
    source.addListener(() => selection.removeListener(listener));
    selection.addListener(listener);

    expect(() => source.set(1), returnsNormally);
  });

  test('a selection whose subscription failed keeps nothing it picked',
      () async {
    final source = _ThrowingListSource();
    final selection = source.select((list) => list);
    final payload = _pickedThenRefused(source, selection);

    expect(
      await collected(payload),
      isTrue,
      reason: 'nobody listens after the failure, and the pick made for the '
          'subscription holds a value the source let go of',
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

  test('a value of the source is never taken for the empty pick', () {
    final reports = _captureReports();
    final source = ValueNotifier<Object>(Object());
    final selection = SoloSelection<Object, String>(source, (value) {
      if (identical(value, const Object())) {
        throw StateError('cannot pick this value');
      }
      return 'old pick';
    });
    void listener() {}
    selection.addListener(listener);
    addTearDown(() => selection.removeListener(listener));
    // The selector throws on the change and keeps no pick; a `const
    // Object()` of the caller's used to be the marker of that.
    source.value = const Object();
    expect(reports.single, isStateError);
    expect(() => selection.value, throwsStateError);
  });

  test('a listener added while a failed subscription was made is let go', () {
    final source = _ReentrantFailingSource();
    final selection = SoloSelection<int, int>(source, (value) => value);
    final heard = <String>[];
    source.duringAdd = () => selection.addListener(() => heard.add('second'));
    expect(() => selection.addListener(() {}), throwsStateError);
    void third() => heard.add('third');
    selection.addListener(third);
    addTearDown(() => selection.removeListener(third));
    expect(source.listeners, hasLength(1), reason: 'subscribed again');
    source.set(1);
    expect(heard, ['third']);
  });

  test('a source that removes by identity loses the subscription', () {
    final source = _IdentitySource();
    final selection = SoloSelection<int, int>(source, (value) => value);
    void listener() {}
    selection.addListener(listener);
    expect(source.listeners, hasLength(1));
    selection.removeListener(listener);
    expect(source.listeners, isEmpty);
  });

  test('a listener added while the last one is being removed is kept', () {
    final reports = _captureReports();
    final source = _RemovalHookSource();
    addTearDown(source.dispose);
    final selection = SoloSelection<int, int>(source, (value) => value);
    final heard = <int>[];
    void first() {}
    void second() => heard.add(selection.value);
    selection.addListener(first);
    source.onRemove = () => selection.addListener(second);
    selection.removeListener(first);
    addTearDown(() => selection.removeListener(second));
    source.value = 1;
    expect(reports, isEmpty);
    expect(heard, [1]);
  });

  test('a source that fails to subscribe and to let go keeps nobody', () {
    final reports = _captureReports();
    final source = _DoubleFailureSource();
    final selection = SoloSelection<int, int>(source, (value) => value);
    var calls = 0;
    expect(
      () => selection.addListener(() => calls++),
      throwsA(isStateError.having((e) => e.message, 'message', 'subscribe')),
    );
    expect(
      reports.single,
      isStateError.having((e) => e.message, 'message', 'remove'),
    );
    source.publish();
    expect(calls, 0);
  });
}

/// A selection that picked a payload while subscribed and then lost its
/// last listener, with the source moved on since. In a frame of its own: a
/// closure or a local keeps what it holds, so a payload left in the test
/// would be held by the test. The payload, weakly.
WeakReference<Object> _pickedThenIdle(
  ValueNotifier<List<int>> source,
  SoloSelection<List<int>, List<int>> selection,
) {
  source.value = List<int>.filled(1024, 7);
  final payload = WeakReference<Object>(source.value);
  void listener() {}
  selection
    ..addListener(listener)
    ..removeListener(listener);
  source.value = <int>[];
  return payload;
}

/// Picks a payload while subscribing, has the subscription refused, and
/// moves the source on; the payload, weakly. A frame of its own, as for
/// [_pickedThenIdle].
WeakReference<Object> _pickedThenRefused(
  _ThrowingListSource source,
  SoloSelection<List<int>, List<int>> selection,
) {
  source.value = List<int>.filled(1024, 7);
  final payload = WeakReference<Object>(source.value);
  try {
    selection.addListener(() {});
  } on Object catch (_) {
    // Refused, as the source was told to.
  }
  source.value = <int>[];
  return payload;
}

/// A source of lists that refuses every subscription.
final class _ThrowingListSource implements ValueListenable<List<int>> {
  @override
  List<int> value = [];

  @override
  void addListener(VoidCallback listener) =>
      throw StateError('subscription failed');

  @override
  void removeListener(VoidCallback listener) {}
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

/// Collects what [FlutterError.onError] is handed until the test ends.
List<Object> _captureReports() {
  final reports = <Object>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => reports.add(details.exception);
  addTearDown(() => FlutterError.onError = previous);
  return reports;
}

/// Calls [duringAdd] from inside `addListener` and fails the first one.
final class _ReentrantFailingSource implements ValueListenable<int> {
  final listeners = <VoidCallback>[];
  VoidCallback? duringAdd;
  var _fail = true;

  @override
  int value = 0;

  @override
  void addListener(VoidCallback listener) {
    listeners.add(listener);
    final callback = duringAdd;
    duringAdd = null;
    callback?.call();
    if (_fail) {
      _fail = false;
      throw StateError('subscribe');
    }
  }

  @override
  void removeListener(VoidCallback listener) => listeners.remove(listener);

  void set(int next) {
    value = next;
    for (final listener in listeners.toList()) {
      listener();
    }
  }
}

/// Takes listeners off by identity rather than by `==`.
final class _IdentitySource implements ValueListenable<int> {
  final listeners = <VoidCallback>[];

  @override
  int value = 0;

  @override
  void addListener(VoidCallback listener) => listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) =>
      listeners.removeWhere((entry) => identical(entry, listener));
}

/// Calls [onRemove] from inside `removeListener`, before it removes.
final class _RemovalHookSource extends ValueNotifier<int> {
  _RemovalHookSource() : super(0);

  VoidCallback? onRemove;

  @override
  void removeListener(VoidCallback listener) {
    final hook = onRemove;
    onRemove = null;
    hook?.call();
    super.removeListener(listener);
  }
}

/// Keeps the listener and throws on subscribing, then throws on letting go.
final class _DoubleFailureSource implements ValueListenable<int> {
  final listeners = <VoidCallback>[];

  @override
  int value = 0;

  @override
  void addListener(VoidCallback listener) {
    listeners.add(listener);
    throw StateError('subscribe');
  }

  @override
  void removeListener(VoidCallback listener) => throw StateError('remove');

  void publish() {
    value++;
    for (final listener in listeners.toList()) {
      listener();
    }
  }
}
