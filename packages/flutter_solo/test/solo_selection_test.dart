import 'package:flutter/foundation.dart';
import 'package:flutter_solo/flutter_solo.dart';
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

final class _Controller extends SoloListenable<_Screen> {
  _Controller() : super(const _Screen());

  void set(_Screen next) => externalSetState(next);
}

/// A controller with a `select` of its own: the extension must step aside
/// and leave this member the winner.
final class _ListController extends SoloListenable<String> {
  _ListController() : super('');

  void select(String id) => externalSetState(id);
}

void main() {
  test('a change that leaves the pick alone notifies nobody', () {
    final controller = _Controller();
    final name = controller.select((state) => state.name);
    var calls = 0;
    name.addListener(() => calls++);

    for (var progress = 1; progress <= 10; progress++) {
      controller.set(controller.state.copyWith(progress: progress));
    }
    expect(calls, 0);
    expect(name.value, '');

    controller.set(controller.state.copyWith(name: 'Ada'));
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
    expect(picks, 1, reason: 'the constructor picked once, the change did not');

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
    final name = controller.select((state) => state.name);
    var calls = 0;
    name.addListener(() => calls++);
    await controller.close();
    controller.set(const _Screen(name: 'Ada'));

    expect(calls, 0, reason: 'a closed controller notifies nobody');
    expect(name.value, 'Ada', reason: 'the state still answers');
  });
}
