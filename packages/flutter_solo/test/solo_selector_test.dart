import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';

@immutable
final class _Screen {
  final String name;
  final int progress;

  const _Screen({this.name = '', this.progress = 0});
}

final class _Controller extends SoloListenable<_Screen> {
  _Controller() : super(const _Screen());

  void set(_Screen next) => externalSetState(next);
}

/// Counts every registration and removal, so a leaked listener is a number
/// and not a guess.
final class _CountingSource extends ValueNotifier<int> {
  _CountingSource() : super(0);

  int adds = 0;
  int removes = 0;

  int get live => adds - removes;

  @override
  void addListener(VoidCallback listener) {
    adds++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    removes++;
    super.removeListener(listener);
  }
}

Widget _wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    );

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
          listenable: controller,
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

  testWidgets('the child is handed back untouched', (tester) async {
    final controller = _Controller();
    addTearDown(controller.close);
    const kept = Text('kept');
    final handed = <Widget?>[];

    await tester.pumpWidget(
      _wrap(
        SoloSelector<_Screen, String>(
          listenable: controller,
          selector: (state) => state.name,
          builder: (context, name, child) {
            handed.add(child);

            return Column(children: [Text(name), if (child != null) child]);
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

  testWidgets('compare decides what counts as a change', (tester) async {
    final controller = _Controller();
    addTearDown(controller.close);
    final built = <String>[];

    await tester.pumpWidget(
      _wrap(
        SoloSelector<_Screen, String>(
          listenable: controller,
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

    controller.set(const _Screen(name: 'Ada'));
    await tester.pump();
    controller.set(const _Screen(name: 'ADA'));
    await tester.pump();
    controller.set(const _Screen(name: 'Grace'));
    await tester.pump();

    expect(built, ['', 'Ada', 'Grace']);
  });

  testWidgets('a selector handed over in its place picks instead', (
    tester,
  ) async {
    final controller = _Controller()..set(const _Screen(name: 'Ada'));
    addTearDown(controller.close);

    Widget tree(String Function(_Screen state) selector) => _wrap(
          SoloSelector<_Screen, String>(
            listenable: controller,
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

  testWidgets('the listenable is let go when the widget goes', (tester) async {
    final controller = _Controller();
    addTearDown(controller.close);
    var picks = 0;

    await tester.pumpWidget(
      _wrap(
        SoloSelector<_Screen, String>(
          listenable: controller,
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
          listenable: controller,
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
      final source = _PublishOnListenSource();

      await tester.pumpWidget(
        _wrap(
          SoloSelector<int, bool>(
            listenable: source,
            selector: (value) => value > 0,
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
      final source = _CountingSource();

      // A new closure on every call, so every parent rebuild asks for a new
      // selection and the widget has to move its listener across.
      Widget tree(int seed) => _wrap(
            SoloSelector<int, String>(
              listenable: source,
              selector: (value) => '$value/$seed',
              builder: (context, label, _) => Text(label),
            ),
          );

      await tester.pumpWidget(tree(1));
      expect(source.live, 1);

      await tester.pumpWidget(tree(2));
      await tester.pumpWidget(tree(3));
      await tester.pumpWidget(tree(4));
      expect(
        source.live,
        1,
        reason: 'adds=${source.adds} removes=${source.removes}',
      );

      source.value = 7;
      await tester.pump();
      expect(find.text('7/4'), findsOneWidget);

      await tester.pumpWidget(_wrap(const SizedBox()));
      expect(source.live, 0);
    },
  );
}

final class _PublishOnListenSource implements ValueListenable<int> {
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
