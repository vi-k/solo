// Every widget takes a `SoloLanes`: the controller type of its field is
// `SoloController<S>`, and the writes of each lane reach it.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two lanes over one `int`: each adds to the state through its own queue.
final class _Counter extends SoloLanes<int> with SoloListenable<int> {
  late final SoloLane<int> first;
  late final SoloLane<int> second;

  _Counter() : super(0) {
    first = lane('first');
    second = lane('second');
  }

  Future<void> addInFirst(int delta) => first
      .enqueue<int, void>((ctx) async => ctx.emit(ctx.state + delta))
      .value;

  Future<void> addInSecond(int delta) => second
      .enqueue<int, void>((ctx) async => ctx.emit(ctx.state + delta))
      .value;
}

Widget _wrap(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
  testWidgets('SoloBuilder rebuilds on a write of either lane', (tester) async {
    final controller = _Counter();
    addTearDown(controller.close);
    final built = <int>[];

    await tester.pumpWidget(
      _wrap(
        SoloBuilder<int>(
          solo: controller,
          builder: (context, value, _) {
            built.add(value);

            return Text('$value');
          },
        ),
      ),
    );
    expect(built, [0]);

    await tester.runAsync(() => controller.addInFirst(1));
    await tester.pump();
    expect(built, [0, 1]);
    expect(find.text('1'), findsOneWidget);

    await tester.runAsync(() => controller.addInSecond(10));
    await tester.pump();
    expect(built, [0, 1, 11]);
    expect(find.text('11'), findsOneWidget);
  });

  testWidgets('SoloSelector and SoloSelection.from take a SoloLanes', (
    tester,
  ) async {
    final controller = _Counter();
    addTearDown(controller.close);
    final parity = SoloSelection.from(controller, (state) => state.isEven);
    final flips = <bool>[];
    void onFlip() => flips.add(parity.value);
    parity.addListener(onFlip);
    addTearDown(() => parity.removeListener(onFlip));
    final built = <bool>[];

    await tester.pumpWidget(
      _wrap(
        SoloSelector<int, bool>(
          solo: controller,
          selector: (state) => state.isEven,
          builder: (context, even, _) {
            built.add(even);

            return Text('$even');
          },
        ),
      ),
    );
    expect(built, [true]);

    await tester.runAsync(() => controller.addInFirst(1));
    await tester.pump();
    expect(built, [true, false]);
    expect(flips, [false]);

    await tester.runAsync(() => controller.addInSecond(1));
    await tester.pump();
    expect(built, [true, false, true]);
    expect(flips, [false, true]);
  });

  testWidgets('SoloListener reacts to the writes of both lanes', (
    tester,
  ) async {
    final controller = _Counter();
    addTearDown(controller.close);
    final seen = <int>[];

    await tester.pumpWidget(
      _wrap(
        SoloListener<int>(
          solo: controller,
          listener: (ctx, context, state) => seen.add(state),
          child: const SizedBox(),
        ),
      ),
    );

    await tester.runAsync(() => controller.addInFirst(1));
    await tester.pump();
    expect(seen, [1]);

    await tester.runAsync(() => controller.addInSecond(10));
    await tester.pump();
    expect(seen, [1, 11]);
  });

  test('a SoloLanes with SoloListenable is a ValueListenable', () async {
    final controller = _Counter();
    addTearDown(controller.close);
    final ValueListenable<int> listenable = controller;
    final values = <int>[];
    listenable.addListener(() => values.add(listenable.value));

    expect(listenable.value, 0);
    await controller.addInFirst(2);
    expect(listenable.value, 2);
    await controller.addInSecond(3);
    expect(listenable.value, 5);
    expect(values, [2, 5]);
  });
}
