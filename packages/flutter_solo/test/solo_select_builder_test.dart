import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';

@immutable
final class _Screen {
  final String name;
  final int progress;

  const _Screen({this.name = '', this.progress = 0});
}

final class _Controller extends Solo<_Screen> {
  _Controller([super.initial = const _Screen()]);

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

Widget _wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    );

void main() {
  testWidgets(
    'a change that leaves the pick alone rebuilds nothing while a change '
    'affecting it rebuilds',
    (tester) async {
      final controller = _Controller();
      addTearDown(controller.close);
      final built = <String>[];

      await tester.pumpWidget(
        _wrap(
          SoloSelectBuilder<_Screen, String>(
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
      expect(find.text(''), findsOneWidget);

      controller.set(const _Screen(progress: 1));
      await tester.pump();
      expect(built, ['']);

      controller.set(const _Screen(name: 'Ada', progress: 1));
      await tester.pump();
      expect(built, ['', 'Ada']);
      expect(find.text('Ada'), findsOneWidget);
    },
  );

  testWidgets(
    'parent rebuild with identical solo, selector and compare preserves '
    'the selection and its comparison baseline',
    (tester) async {
      final controller = _Controller();
      addTearDown(controller.close);
      int pickProgress(_Screen state) => state.progress;
      bool diffAtLeastTwo(int prev, int curr) => (curr - prev).abs() >= 2;

      final built = <int>[];
      Widget tree() => _wrap(
            SoloSelectBuilder<_Screen, int>(
              solo: controller,
              selector: pickProgress,
              compare: diffAtLeastTwo,
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
      expect(built, [0, 0, 2]);
      expect(find.text('2'), findsOneWidget);
    },
  );

  testWidgets(
    'switching controller recreates selection even when controllers are '
    'equal by operator == and shows the new state',
    (tester) async {
      final first = _EqualController(const _Screen(name: 'Ada'));
      final second = _EqualController(const _Screen(name: 'Grace'));
      addTearDown(first.close);
      addTearDown(second.close);

      String pickName(_Screen state) => state.name;
      final built = <String>[];

      Widget tree(Solo<_Screen> controller) => _wrap(
            SoloSelectBuilder<_Screen, String>(
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
      expect(find.text('Ada'), findsOneWidget);

      await tester.pumpWidget(tree(second));
      expect(built, ['Ada', 'Grace']);
      expect(find.text('Grace'), findsOneWidget);

      first.set(const _Screen(name: 'Margaret'));
      await tester.pump();
      expect(built, ['Ada', 'Grace']);
      expect(find.text('Grace'), findsOneWidget);

      second.set(const _Screen(name: 'Barbara'));
      await tester.pump();
      expect(built, ['Ada', 'Grace', 'Barbara']);
      expect(find.text('Barbara'), findsOneWidget);
    },
  );

  testWidgets(
    'compare callback suppresses rebuild when reporting no change',
    (tester) async {
      final controller = _Controller(const _Screen(name: 'Ada'));
      addTearDown(controller.close);
      final built = <String>[];

      await tester.pumpWidget(
        _wrap(
          SoloSelectBuilder<_Screen, String>(
            solo: controller,
            selector: (state) => state.name,
            compare: (previous, current) =>
                previous.toLowerCase() != current.toLowerCase(),
            builder: (context, name, _) {
              built.add(name);

              return Text(name);
            },
          ),
        ),
      );
      expect(built, ['Ada']);

      controller.set(const _Screen(name: 'ADA'));
      await tester.pump();
      expect(built, ['Ada']);

      controller.set(const _Screen(name: 'Grace'));
      await tester.pump();
      expect(built, ['Ada', 'Grace']);
      expect(find.text('Grace'), findsOneWidget);
    },
  );

  testWidgets(
    'unmounting releases the controller leaving no listeners',
    (tester) async {
      final controller = _Controller();
      addTearDown(controller.close);
      var picks = 0;

      await tester.pumpWidget(
        _wrap(
          SoloSelectBuilder<_Screen, String>(
            solo: controller,
            selector: (state) {
              picks++;

              return state.name;
            },
            builder: (context, name, _) => Text(name),
          ),
        ),
      );
      await tester.pumpWidget(_wrap(const Text('unmounted')));
      picks = 0;

      controller.set(const _Screen(name: 'Ada'));
      await tester.pump();

      expect(picks, 0);
      expect(find.text('unmounted'), findsOneWidget);
    },
  );

  testWidgets(
    'child is handed back to builder untouched and not recreated',
    (tester) async {
      final controller = _Controller(const _Screen(name: 'Ada'));
      addTearDown(controller.close);
      const kept = Text('kept');
      final handed = <Widget?>[];

      await tester.pumpWidget(
        _wrap(
          SoloSelectBuilder<_Screen, String>(
            solo: controller,
            selector: (state) => state.name,
            builder: (context, name, child) {
              handed.add(child);

              return Column(
                children: [Text(name), if (child != null) child],
              );
            },
            child: kept,
          ),
        ),
      );

      controller.set(const _Screen(name: 'Grace'));
      await tester.pump();

      expect(handed, [same(kept), same(kept)]);
      expect(find.text('kept'), findsOneWidget);
    },
  );

  testWidgets('mounting tree contains no ValueListenableBuilder', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.close);

    await tester.pumpWidget(
      _wrap(
        SoloSelectBuilder<_Screen, bool>(
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
    'source publishes on listen',
    (tester) async {
      final solo = _PublishOnListenSolo();
      addTearDown(solo.close);

      await tester.pumpWidget(
        _wrap(
          SoloSelectBuilder<int, bool>(
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
  testWidgets(
    'three selections in a row leave one registration, not three',
    (tester) async {
      final controller = _CountingController();
      addTearDown(controller.close);

      // A new closure on every call, so every parent rebuild asks for a new
      // selection and the widget has to move its listener across.
      Widget tree(int seed) => _wrap(
            SoloSelectBuilder<int, String>(
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
      expect(
        controller.live,
        1,
        reason: 'adds=${controller.adds} removes=${controller.removes}',
      );

      controller.set(7);
      await tester.pump();
      expect(find.text('7/4'), findsOneWidget);

      await tester.pumpWidget(_wrap(const SizedBox()));
      expect(controller.live, 0);
    },
  );
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
