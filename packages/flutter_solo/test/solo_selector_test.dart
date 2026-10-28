import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';

@immutable
final class _Screen {
  final String name;
  final int progress;

  const _Screen({this.name = '', this.progress = 0});
}

/// A plain controller: not a `ValueListenable`, which the widget does not
/// need.
final class _Controller extends Solo<_Screen> {
  _Controller([super.initial = const _Screen()]);

  void set(_Screen next) => externalSetState(next);
}

/// A controller that is a `ValueListenable` too, which the widget takes
/// the same way.
final class _ListenableController extends Solo<_Screen> with SoloListenable {
  _ListenableController() : super(const _Screen());

  void set(_Screen next) => externalSetState(next);
}

/// A controller whose `==` says two distinct instances are the same one.
/// `identical` still tells them apart, and the widget has to agree with
/// `identical`: handed a new controller, it must let go of the old one even
/// when the two compare equal.
final class _EqualController extends Solo<_Screen> with _EqualByKind {
  _EqualController([super.initial = const _Screen()]);

  void set(_Screen next) => externalSetState(next);
}

/// The equality above lives in a mixin because a controller is mutable by
/// trade, and on the class itself the analyzer refuses the pair:
/// `avoid_equals_and_hash_code_on_mutable_classes`.
mixin _EqualByKind on Solo<_Screen> {
  @override
  bool operator ==(Object other) => other is _EqualByKind;

  @override
  int get hashCode => 0;
}

/// Counts every registration and removal, so a leaked listener is a number
/// and not a guess.
final class _CountingController extends Solo<int> {
  _CountingController() : super(0);

  int adds = 0;
  int removes = 0;

  int get live => adds - removes;

  void set(int next) => externalSetState(next);

  @override
  void addListener(void Function() listener) {
    adds++;
    super.addListener(listener);
  }

  @override
  void removeListener(void Function() listener) {
    removes++;
    super.removeListener(listener);
  }
}

final class _PublishOnListenSolo extends Solo<int> {
  _PublishOnListenSolo() : super(0);

  var _published = false;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_published) {
      return;
    }
    _published = true;
    externalSetState(1);
  }
}

/// A controller whose `removeListener` throws, the way one of somebody's
/// own may: a listener it was given stays on it.
final class _StuckController extends Solo<_Screen> {
  _StuckController() : super(const _Screen());

  void set(_Screen next) => externalSetState(next);

  @override
  void removeListener(VoidCallback listener) =>
      throw StateError('this one does not let go');
}

Widget _wrap(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
  testWidgets('a change that leaves the pick alone rebuilds nothing', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.close);
    final built = <String>[];

    await tester.pumpWidget(
      _wrap(
        SoloSelector<_Screen, String>(
          solo: controller,
          selector: (state) => state.name,
          builder: (context, name, _) {
            built.add(name);

            return Text(name);
          },
        ),
      ),
    );
    expect(built, ['']);

    controller.set(const _Screen(progress: 1));
    await tester.pump();
    expect(built, [''], reason: 'the progress is not what is picked');

    controller.set(const _Screen(name: 'Ada', progress: 1));
    await tester.pump();
    expect(built, ['', 'Ada']);
    expect(find.text('Ada'), findsOneWidget);
  });

  testWidgets('a controller that is a ValueListenable is taken the same way', (
    tester,
  ) async {
    final controller = _ListenableController();
    addTearDown(controller.close);

    await tester.pumpWidget(
      _wrap(
        SoloSelector<_Screen, String>(
          solo: controller,
          selector: (state) => state.name,
          builder: (context, name, _) => Text(name),
        ),
      ),
    );

    controller.set(const _Screen(name: 'Ada'));
    await tester.pump();
    expect(find.text('Ada'), findsOneWidget);
  });

  testWidgets('the child is handed back untouched', (tester) async {
    final controller = _Controller();
    addTearDown(controller.close);
    const kept = Text('kept');
    final handed = <Widget?>[];

    await tester.pumpWidget(
      _wrap(
        SoloSelector<_Screen, String>(
          solo: controller,
          selector: (state) => state.name,
          builder: (context, name, child) {
            handed.add(child);

            return Column(children: [Text(name), ?child]);
          },
          child: kept,
        ),
      ),
    );

    controller.set(const _Screen(name: 'Ada'));
    await tester.pump();

    expect(handed, [same(kept), same(kept)]);
    expect(find.text('kept'), findsOneWidget);
  });

  testWidgets('changed decides what counts as a change', (tester) async {
    final controller = _Controller();
    addTearDown(controller.close);
    final built = <String>[];

    await tester.pumpWidget(
      _wrap(
        SoloSelector<_Screen, String>(
          solo: controller,
          selector: (state) => state.name,
          changed: (previous, current) =>
              previous.toLowerCase() != current.toLowerCase(),
          builder: (context, name, _) {
            built.add(name);

            return Text(name);
          },
        ),
      ),
    );

    controller.set(const _Screen(name: 'Ada'));
    await tester.pump();
    controller.set(const _Screen(name: 'ADA'));
    await tester.pump();
    controller.set(const _Screen(name: 'Grace'));
    await tester.pump();

    expect(built, ['', 'Ada', 'Grace']);
  });

  testWidgets(
    'a parent rebuild with the same controller, selector and changed keeps '
    'the value the answer is given from',
    (tester) async {
      final controller = _Controller();
      addTearDown(controller.close);
      int pickProgress(_Screen state) => state.progress;
      bool movedByTwo(int previous, int current) =>
          (current - previous).abs() >= 2;

      final built = <int>[];
      Widget tree() => _wrap(
        SoloSelector<_Screen, int>(
          solo: controller,
          selector: pickProgress,
          changed: movedByTwo,
          builder: (context, progress, _) {
            built.add(progress);

            return Text('$progress');
          },
        ),
      );

      await tester.pumpWidget(tree());
      expect(built, [0]);

      controller.set(const _Screen(progress: 1));
      await tester.pump();
      expect(built, [0]);

      await tester.pumpWidget(tree());
      expect(built, [0, 0]);

      controller.set(const _Screen(name: 'Ada', progress: 1));
      await tester.pump();
      expect(built, [0, 0]);

      controller.set(const _Screen(progress: 2));
      await tester.pump();
      expect(
        built,
        [0, 0, 2],
        reason:
            'two away from the 0 announced before the rebuild; a '
            'selection made again would have announced 1 and missed this',
      );
      expect(find.text('2'), findsOneWidget);
    },
  );

  testWidgets(
    'closures written in place keep the value the answer is given from',
    (tester) async {
      final controller = _Controller();
      addTearDown(controller.close);

      final built = <int>[];
      // New closures on every call, the way a `build` writes them.
      Widget tree() => _wrap(
        SoloSelector<_Screen, int>(
          solo: controller,
          selector: (state) => state.progress,
          changed: (previous, current) => (current - previous).abs() >= 2,
          builder: (context, progress, _) {
            built.add(progress);

            return Text('$progress');
          },
        ),
      );

      await tester.pumpWidget(tree());
      controller.set(const _Screen(progress: 1));
      await tester.pump();
      expect(built, [0]);

      await tester.pumpWidget(tree());
      expect(built, [
        0,
        0,
      ], reason: 'the parent rebuilt, and 1 is still no change from 0');

      controller.set(const _Screen(progress: 2));
      await tester.pump();
      expect(built, [0, 0, 2], reason: 'two away from the 0 on the screen');
    },
  );

  testWidgets('closures written in place move no subscription', (tester) async {
    final controller = _CountingController();
    addTearDown(controller.close);

    Widget tree() => _wrap(
      SoloSelector<int, bool>(
        solo: controller,
        selector: (state) => state > 0,
        changed: (previous, current) => previous != current,
        builder: (context, positive, _) => Text('$positive'),
      ),
    );

    await tester.pumpWidget(tree());
    await tester.pumpWidget(tree());
    await tester.pumpWidget(tree());
    await tester.pumpWidget(tree());
    expect((controller.adds, controller.removes), (1, 0));

    controller.set(1);
    await tester.pump();
    expect(find.text('true'), findsOneWidget);
  });

  testWidgets('held functions are not called for a parent rebuild', (
    tester,
  ) async {
    final controller = _Controller(const _Screen(name: 'Ada'));
    addTearDown(controller.close);
    var picks = 0;
    var asked = 0;
    String pickName(_Screen state) {
      picks++;

      return state.name;
    }

    bool differs(String previous, String current) {
      asked++;

      return previous != current;
    }

    Widget tree() => _wrap(
      SoloSelector<_Screen, String>(
        solo: controller,
        selector: pickName,
        changed: differs,
        builder: (context, name, _) => Text(name),
      ),
    );

    await tester.pumpWidget(tree());
    expect((picks, asked), (1, 0), reason: 'the mount picks and asks nothing');

    await tester.pumpWidget(tree());
    await tester.pumpWidget(tree());
    expect((picks, asked), (1, 0), reason: 'nothing new to pick with');

    controller.set(const _Screen(name: 'Grace'));
    await tester.pump();
    expect((picks, asked), (2, 1));
    expect(find.text('Grace'), findsOneWidget);
  });

  testWidgets('a new controller starts the value over', (tester) async {
    final first = _Controller();
    final second = _Controller(const _Screen(progress: 1));
    addTearDown(first.close);
    addTearDown(second.close);
    int pickProgress(_Screen state) => state.progress;
    bool movedByTwo(int previous, int current) =>
        (current - previous).abs() >= 2;

    final built = <int>[];
    Widget tree(Solo<_Screen> controller) => _wrap(
      SoloSelector<_Screen, int>(
        solo: controller,
        selector: pickProgress,
        changed: movedByTwo,
        builder: (context, progress, _) {
          built.add(progress);

          return Text('$progress');
        },
      ),
    );

    await tester.pumpWidget(tree(first));
    await tester.pumpWidget(tree(second));
    expect(
      built,
      [0, 1],
      reason:
          'the 1 is the first value of another controller, and changed '
          'is not asked about it',
    );
  });

  testWidgets('a selector handed over in its place picks instead', (
    tester,
  ) async {
    final controller = _Controller(const _Screen(name: 'Ada'));
    addTearDown(controller.close);

    Widget tree(String Function(_Screen state) selector) => _wrap(
      SoloSelector<_Screen, String>(
        solo: controller,
        selector: selector,
        builder: (context, picked, _) => Text(picked),
      ),
    );

    await tester.pumpWidget(tree((state) => state.name));
    expect(find.text('Ada'), findsOneWidget);

    await tester.pumpWidget(tree((state) => 'progress ${state.progress}'));
    expect(find.text('progress 0'), findsOneWidget);

    controller.set(const _Screen(name: 'Grace', progress: 7));
    await tester.pump();
    expect(find.text('progress 7'), findsOneWidget);
  });

  testWidgets('a changed handed over in its place answers instead', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.close);
    String pickName(_Screen state) => state.name;
    final built = <String>[];

    Widget tree(bool Function(String previous, String current) changed) =>
        _wrap(
          SoloSelector<_Screen, String>(
            solo: controller,
            selector: pickName,
            changed: changed,
            builder: (context, name, _) {
              built.add(name);

              return Text(name);
            },
          ),
        );

    await tester.pumpWidget(tree((previous, current) => false));
    controller.set(const _Screen(name: 'Ada'));
    await tester.pump();
    expect(built, [''], reason: 'the first answer is that nothing changes');

    await tester.pumpWidget(tree((previous, current) => previous != current));
    built.clear();
    controller.set(const _Screen(name: 'Grace'));
    await tester.pump();
    expect(built, ['Grace'], reason: 'the answer handed over is the one used');
  });

  testWidgets(
    'a new controller is followed even when == calls it the old one',
    (tester) async {
      final first = _EqualController(const _Screen(name: 'Ada'));
      final second = _EqualController(const _Screen(name: 'Grace'));
      addTearDown(first.close);
      addTearDown(second.close);

      String pickName(_Screen state) => state.name;
      final built = <String>[];

      Widget tree(Solo<_Screen> controller) => _wrap(
        SoloSelector<_Screen, String>(
          solo: controller,
          selector: pickName,
          builder: (context, name, _) {
            built.add(name);

            return Text(name);
          },
        ),
      );

      await tester.pumpWidget(tree(first));
      expect(built, ['Ada']);

      await tester.pumpWidget(tree(second));
      expect(built, ['Ada', 'Grace']);
      expect(find.text('Grace'), findsOneWidget);

      first.set(const _Screen(name: 'Margaret'));
      await tester.pump();
      expect(built, ['Ada', 'Grace'], reason: 'the old one is let go');

      second.set(const _Screen(name: 'Barbara'));
      await tester.pump();
      expect(built, ['Ada', 'Grace', 'Barbara']);
      expect(find.text('Barbara'), findsOneWidget);
    },
  );

  testWidgets('a mount, a parent rebuild and a change pick once each', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.close);
    var picks = 0;

    // A new closure on every call, so the rebuild has to pick with it.
    Widget tree() => _wrap(
      SoloSelector<_Screen, String>(
        solo: controller,
        selector: (state) {
          picks++;

          return state.name;
        },
        builder: (context, name, _) => Text(name),
      ),
    );

    await tester.pumpWidget(tree());
    expect(picks, 1, reason: 'mount');

    picks = 0;
    await tester.pumpWidget(tree());
    expect(picks, 1, reason: 'parent rebuild');

    picks = 0;
    controller.set(const _Screen(name: 'Ada'));
    await tester.pump();
    expect(picks, 1, reason: 'one change of the state');
    expect(find.text('Ada'), findsOneWidget);
  });

  testWidgets('the controller is let go when the widget goes', (tester) async {
    final controller = _Controller();
    addTearDown(controller.close);
    var picks = 0;

    await tester.pumpWidget(
      _wrap(
        SoloSelector<_Screen, String>(
          solo: controller,
          selector: (state) {
            picks++;

            return state.name;
          },
          builder: (context, name, _) => Text(name),
        ),
      ),
    );

    await tester.pumpWidget(_wrap(const Text('gone')));
    picks = 0;
    controller.set(const _Screen(name: 'Ada'));
    await tester.pump();

    expect(picks, 0, reason: 'the last listener took the subscription away');
  });

  testWidgets('mounting tree contains no ValueListenableBuilder', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.close);

    await tester.pumpWidget(
      _wrap(
        SoloSelector<_Screen, bool>(
          solo: controller,
          selector: (state) => state.name.isNotEmpty,
          builder: (context, hasName, _) => Text('$hasName'),
        ),
      ),
    );

    expect(find.byType(ValueListenableBuilder<bool>), findsNothing);
    expect(find.text('false'), findsOneWidget);
  });

  testWidgets(
    'mounting and immediate unmounting in one frame does not throw when '
    'the controller publishes on listen',
    (tester) async {
      final solo = _PublishOnListenSolo();
      addTearDown(solo.close);

      await tester.pumpWidget(
        _wrap(
          SoloSelector<int, bool>(
            solo: solo,
            selector: (state) => state > 0,
            builder: (context, positive, _) => Text('$positive'),
          ),
        ),
      );
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a selector that throws on mounting leaves no listener behind', (
    tester,
  ) async {
    final controller = _CountingController();
    addTearDown(controller.close);

    await tester.pumpWidget(
      _wrap(
        SoloSelector<int, String>(
          solo: controller,
          selector: (state) => throw StateError('no pick'),
          builder: (context, label, _) => Text(label),
        ),
      ),
    );

    expect(tester.takeException(), isStateError);
    expect(
      controller.live,
      0,
      reason: 'the widget never came to be, and nothing will dispose of it',
    );
  });

  testWidgets(
    'a selector or a changed that throws for a parent rebuild leaves none '
    'either',
    (tester) async {
      Future<int> liveAfter({required bool selectorThrows}) async {
        final controller = _CountingController();
        Widget tree({required bool throws}) => _wrap(
          SoloSelector<int, String>(
            solo: controller,
            selector: (state) => throws && selectorThrows
                ? throw StateError('no pick')
                : '$state',
            changed: (previous, current) => throws && !selectorThrows
                ? throw StateError('no answer')
                : previous != current,
            builder: (context, label, _) => Text(label),
          ),
        );

        await tester.pumpWidget(tree(throws: false));
        expect(controller.live, 1);
        await tester.pumpWidget(tree(throws: true));
        expect(tester.takeException(), isStateError);
        final live = controller.live;
        await tester.pumpWidget(_wrap(const SizedBox()));
        await controller.close();

        return live;
      }

      // The framework drops a widget whose update threw without disposing
      // of its `State`, so a listener left there would stay for good.
      expect(await liveAfter(selectorThrows: true), 0);
      expect(await liveAfter(selectorThrows: false), 0);
    },
  );

  testWidgets(
    'three selectors in a row leave the one registration where it was',
    (tester) async {
      final controller = _CountingController();
      addTearDown(controller.close);

      // A new closure on every call, so every parent rebuild picks with a
      // new selector; the listener is not moved for it.
      Widget tree(int seed) => _wrap(
        SoloSelector<int, String>(
          solo: controller,
          selector: (state) => '$state/$seed',
          builder: (context, label, _) => Text(label),
        ),
      );

      await tester.pumpWidget(tree(1));
      expect(controller.live, 1);

      await tester.pumpWidget(tree(2));
      await tester.pumpWidget(tree(3));
      await tester.pumpWidget(tree(4));
      expect((controller.adds, controller.removes), (1, 0));
      expect(find.text('0/4'), findsOneWidget);

      controller.set(7);
      await tester.pump();
      expect(find.text('7/4'), findsOneWidget);

      await tester.pumpWidget(_wrap(const SizedBox()));
      expect(controller.live, 0);
    },
  );

  // The framework disposes of the `State` all the same, and a listener
  // the controller kept would rebuild an element that is gone.
  testWidgets(
    'a controller that cannot let go does not rebuild a widget that is gone',
    (tester) async {
      final controller = _StuckController();
      addTearDown(controller.close);
      var builds = 0;

      await tester.pumpWidget(
        _wrap(
          SoloSelector<_Screen, String>(
            solo: controller,
            selector: (state) => state.name,
            builder: (context, name, _) {
              builds++;
              return Text(name);
            },
          ),
        ),
      );
      await tester.pumpWidget(_wrap(const SizedBox()));
      expect(tester.takeException(), isStateError);

      controller.set(const _Screen(name: 'Grace'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(builds, 1);
    },
  );
}
