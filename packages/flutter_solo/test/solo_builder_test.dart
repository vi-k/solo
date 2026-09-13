import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';

@immutable
final class _Screen {
  final String name;

  const _Screen({this.name = ''});
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

/// An ordinary `Solo`, the controller this widget exists for: it carries a
/// `stream` and is no `ValueListenable`, so `ValueListenableBuilder` cannot
/// take it.
final class _StreamController extends Solo<_Screen> {
  _StreamController([super.initial = const _Screen()]);

  void set(_Screen next) => externalSetState(next);
}

Widget _wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    );

void main() {
  testWidgets(
    'rebuilds on state change and builder receives the new state',
    (tester) async {
      final controller = _Controller(const _Screen(name: 'Ada'));
      addTearDown(controller.close);
      final built = <String>[];

      await tester.pumpWidget(
        _wrap(
          SoloBuilder<_Screen>(
            solo: controller,
            builder: (context, state, _) {
              built.add(state.name);

              return Text(state.name);
            },
          ),
        ),
      );
      expect(built, ['Ada']);
      expect(find.text('Ada'), findsOneWidget);

      controller.set(const _Screen(name: 'Grace'));
      await tester.pump();

      expect(built, ['Ada', 'Grace']);
      expect(find.text('Grace'), findsOneWidget);
    },
  );

  testWidgets(
    'a change before subscription is visible on the very first build',
    (tester) async {
      final controller = _Controller(const _Screen(name: 'Ada'));
      addTearDown(controller.close);
      controller.set(const _Screen(name: 'Grace'));

      final built = <String>[];
      await tester.pumpWidget(
        _wrap(
          SoloBuilder<_Screen>(
            solo: controller,
            builder: (context, state, _) {
              built.add(state.name);

              return Text(state.name);
            },
          ),
        ),
      );

      expect(built, ['Grace']);
      expect(find.text('Grace'), findsOneWidget);
    },
  );

  testWidgets(
    'didUpdateWidget with a different controller switches subscription '
    'and shows the new state on the first build',
    (tester) async {
      final first = _Controller(const _Screen(name: 'Ada'));
      final second = _Controller(const _Screen(name: 'Grace'));
      addTearDown(first.close);
      addTearDown(second.close);

      final built = <String>[];
      Widget tree(_Controller controller) => _wrap(
            SoloBuilder<_Screen>(
              solo: controller,
              builder: (context, state, _) {
                built.add(state.name);

                return Text(state.name);
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
    'dispose removes listener so state change neither rebuilds nor throws',
    (tester) async {
      final controller = _Controller(const _Screen(name: 'Ada'));
      addTearDown(controller.close);
      var buildCount = 0;

      await tester.pumpWidget(
        _wrap(
          SoloBuilder<_Screen>(
            solo: controller,
            builder: (context, state, _) {
              buildCount++;

              return Text(state.name);
            },
          ),
        ),
      );
      expect(buildCount, 1);

      await tester.pumpWidget(_wrap(const Text('unmounted')));
      expect(buildCount, 1);

      controller.set(const _Screen(name: 'Grace'));
      await tester.pump();

      expect(buildCount, 1);
      expect(find.text('unmounted'), findsOneWidget);
    },
  );

  testWidgets(
    'externalSetState after close rebuilds nothing',
    (tester) async {
      final controller = _Controller(const _Screen(name: 'Ada'));
      var buildCount = 0;

      await tester.pumpWidget(
        _wrap(
          SoloBuilder<_Screen>(
            solo: controller,
            builder: (context, state, _) {
              buildCount++;

              return Text(state.name);
            },
          ),
        ),
      );
      expect(buildCount, 1);

      await controller.close();
      controller.set(const _Screen(name: 'Grace'));
      await tester.pump();

      expect(buildCount, 1);
      expect(find.text('Ada'), findsOneWidget);
    },
  );

  testWidgets(
    'connecting an already closed controller shows its state and does not '
    'update further',
    (tester) async {
      final controller = _Controller(const _Screen(name: 'Ada'))
        ..set(const _Screen(name: 'Grace'));
      await controller.close();

      var buildCount = 0;
      await tester.pumpWidget(
        _wrap(
          SoloBuilder<_Screen>(
            solo: controller,
            builder: (context, state, _) {
              buildCount++;

              return Text(state.name);
            },
          ),
        ),
      );

      expect(buildCount, 1);
      expect(find.text('Grace'), findsOneWidget);

      controller.set(const _Screen(name: 'Margaret'));
      await tester.pump();

      expect(buildCount, 1);
      expect(find.text('Grace'), findsOneWidget);
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
          SoloBuilder<_Screen>(
            solo: controller,
            builder: (context, state, child) {
              handed.add(child);

              return Column(
                children: [Text(state.name), if (child != null) child],
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

  testWidgets(
    'switching to a controller that is merely equal still switches the '
    'subscription',
    (tester) async {
      final first = _EqualController(const _Screen(name: 'Ada'));
      final second = _EqualController(const _Screen(name: 'Grace'));
      addTearDown(first.close);
      addTearDown(second.close);
      expect(first == second, isTrue);
      expect(identical(first, second), isFalse);

      final built = <String>[];
      Widget tree(SoloBase<_Screen> controller) => _wrap(
            SoloBuilder<_Screen>(
              solo: controller,
              builder: (context, state, _) {
                built.add(state.name);

                return Text(state.name);
              },
            ),
          );

      await tester.pumpWidget(tree(first));
      await tester.pumpWidget(tree(second));
      expect(built, ['Ada', 'Grace']);

      first.set(const _Screen(name: 'Margaret'));
      await tester.pump();
      expect(built, ['Ada', 'Grace']);

      second.set(const _Screen(name: 'Barbara'));
      await tester.pump();
      expect(built, ['Ada', 'Grace', 'Barbara']);
      expect(find.text('Barbara'), findsOneWidget);
    },
  );

  testWidgets(
    'takes a plain Solo, which no ValueListenableBuilder would',
    (tester) async {
      final controller = _StreamController(const _Screen(name: 'Ada'));
      addTearDown(controller.close);

      await tester.pumpWidget(
        _wrap(
          SoloBuilder<_Screen>(
            solo: controller,
            builder: (context, state, _) => Text(state.name),
          ),
        ),
      );
      expect(find.text('Ada'), findsOneWidget);

      controller.set(const _Screen(name: 'Grace'));
      await tester.pump();
      expect(find.text('Grace'), findsOneWidget);
    },
  );
}
