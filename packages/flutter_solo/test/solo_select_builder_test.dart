import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';

@immutable
final class _Screen {
  final String name;
  final int progress;

  const _Screen({this.name = '', this.progress = 0});
}

final class _Controller extends SoloBase<_Screen> {
  _Controller([super.initial = const _Screen()]);

  void set(_Screen next) => externalSetState(next);
}

/// A controller whose `==` says two distinct instances are the same one.
/// `identical` still tells them apart, and the widget has to agree with
/// `identical`: handed a new controller, it must let go of the old one even
/// when the two compare equal.
final class _EqualController extends SoloBase<_Screen> with _EqualByKind {
  _EqualController([super.initial = const _Screen()]);

  void set(_Screen next) => externalSetState(next);
}

/// The equality above lives in a mixin because a controller is mutable by
/// trade, and on the class itself the analyzer refuses the pair:
/// `avoid_equals_and_hash_code_on_mutable_classes`.
mixin _EqualByKind on SoloBase<_Screen> {
  @override
  bool operator ==(Object other) => other is _EqualByKind;

  @override
  int get hashCode => 0;
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

      Widget tree(SoloBase<_Screen> controller) => _wrap(
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
}
