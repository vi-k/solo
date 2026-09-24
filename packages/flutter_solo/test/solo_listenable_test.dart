import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/plain_base.dart';

final class _Counter extends Solo<int> with SoloListenable {
  _Counter() : super(0);

  @override
  bool get hasListeners => super.hasListeners;

  void set(int value) => externalSetState(value);

  /// Runs [body] as a job of this controller.
  SoloJob<void> perform(
    Future<void> Function(SoloContext<int, int> ctx) body, {
    bool Function(int state)? keepWhile,
  }) =>
      run<int, void>(body, keepWhile: keepWhile);
}

final class _ObjectController extends Solo<Object> with SoloListenable {
  _ObjectController(super.initialState);

  void set(Object value) => externalSetState(value);
}

final class _Both extends Solo<int> with SoloStream, SoloListenable {
  _Both() : super(0);

  void set(int value) => externalSetState(value);
}

final class _BothReversed extends Solo<int> with SoloListenable, SoloStream {
  _BothReversed() : super(0);

  void set(int value) => externalSetState(value);
}

final class _Leaf extends AppController<int> with SoloListenable {
  _Leaf() : super(0);

  void set(int value) => externalSetState(value);
}

final class _ReportingLeaf extends ReportingBase<int> with SoloListenable {
  _ReportingLeaf() : super(0);

  void set(int value) => externalSetState(value);
}

/// [ReportingBase] with nothing mixed in: its own report is what the leaf
/// above overrides.
final class _PlainReportingLeaf extends ReportingBase<int> {
  _PlainReportingLeaf() : super(0);

  void set(int value) => externalSetState(value);
}

/// What a class extending the old `SoloListenable` class, with an override
/// of its own, becomes: the base mixes the face in itself.
abstract class _FlutterBase<S extends Object> extends Solo<S>
    with SoloListenable {
  final reported = <Object>[];

  _FlutterBase(super.initialState);

  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      reported.add(error);
}

final class _MigratedLeaf extends _FlutterBase<int> {
  _MigratedLeaf() : super(0);

  void set(int value) => externalSetState(value);
}

/// [_FlutterBase] with the face mixed in again on the leaf.
final class _MixedTwiceLeaf extends _FlutterBase<int> with SoloListenable {
  _MixedTwiceLeaf() : super(0);

  void set(int value) => externalSetState(value);
}

final class _ClosingObserver extends SoloObserver {
  final void Function(Solo<Object> solo) onCloseCallback;

  _ClosingObserver(this.onCloseCallback);

  @override
  void onClose(Solo<Object> solo) => onCloseCallback(solo);
}

void main() {
  testWidgets('controller works with ValueListenableBuilder', (tester) async {
    final counter = _Counter();
    addTearDown(counter.close);
    final built = <int>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<int>(
          valueListenable: counter,
          builder: (context, value, _) {
            built.add(value);
            return Text('$value');
          },
        ),
      ),
    );
    expect(built, [0]);
    expect(find.text('0'), findsOneWidget);

    counter.set(1);
    await tester.pump();
    expect(built, [0, 1]);
    expect(find.text('1'), findsOneWidget);

    counter.set(2);
    await tester.pump();
    expect(built, [0, 1, 2]);
    expect(find.text('2'), findsOneWidget);
  });

  test('value mirrors state', () async {
    final counter = _Counter();
    expect(counter.value, 0);
    counter.set(1);
    expect(counter.value, 1);
    expect(counter.value, counter.currentState);
    expect(identical(counter.value, counter.currentState), isTrue);
    await counter.close();
  });

  test('value stays final after the controller finishes closing', () async {
    final counter = _Counter()..set(1);
    await counter.close();

    expect(() => counter.set(2), throwsA(isA<StateError>()));
    expect(counter.value, 1);
  });

  test('value and currentState are the exact same object', () async {
    final initial = Object();
    final next = Object();
    final controller = _ObjectController(initial);
    expect(identical(controller.value, controller.currentState), isTrue);
    expect(identical(controller.value, initial), isTrue);

    controller.set(next);
    expect(identical(controller.value, controller.currentState), isTrue);
    expect(identical(controller.value, next), isTrue);
    await controller.close();
  });

  test('listeners fire inside the change, not on a microtask', () async {
    final counter = _Counter();
    final order = <String>[];
    counter
      ..addListener(() => order.add('listener'))
      ..set(1);
    order.add('after set');
    await Future<void>.microtask(() => order.add('microtask'));
    expect(order, ['listener', 'after set', 'microtask']);
    await counter.close();
  });

  test('a listener removed during notification is not called', () async {
    final counter = _Counter();
    final calls = <String>[];
    late void Function() second;
    counter.addListener(() {
      calls.add('first');
      counter.removeListener(second);
    });
    second = () => calls.add('second');
    counter
      ..addListener(second)
      ..set(1);
    expect(calls, ['first']);
    await counter.close();
  });

  test('a listener added during notification gets the next change', () async {
    final counter = _Counter();
    final calls = <String>[];
    var added = false;
    counter.addListener(() {
      calls.add('first');
      if (!added) {
        added = true;
        counter.addListener(() => calls.add('late'));
      }
    });
    counter.set(1);
    expect(calls, ['first']);
    counter.set(2);
    expect(calls, ['first', 'first', 'late']);
    await counter.close();
  });

  test('a listener registered twice is called twice', () async {
    final counter = _Counter();
    var calls = 0;
    void listener() => calls++;
    counter
      ..addListener(listener)
      ..addListener(listener)
      ..set(1);
    expect(calls, 2);
    counter
      ..removeListener(listener)
      ..set(2);
    expect(calls, 3, reason: 'one removal drops one registration');
    await counter.close();
  });

  test('a throwing listener is reported and the rest still hear', () async {
    final counter = _Counter();
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);

    final calls = <String>[];
    counter
      ..addListener(() => calls.add('before'))
      ..addListener(() => throw StateError('the listener blew up'))
      ..addListener(() => calls.add('after'))
      ..set(1);

    expect(calls, ['before', 'after']);
    expect(reports, hasLength(1));
    final details = reports.single;
    expect(details.exception, isA<StateError>());
    expect(details.library, 'flutter_solo');
    expect(
      details.context.toString(),
      contains('notifying a listener of _Counter'),
    );
    await counter.close();
  });

  test('a throwing listener does not hold back the rules', () async {
    final counter = _Counter();
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = previous);

    final job = counter.perform(
      keepWhile: (state) => state < 10,
      (ctx) => ctx.wait(() => Future<void>.delayed(const Duration(days: 1))),
    )..ignore();
    await Future<void>.delayed(Duration.zero);

    counter
      ..addListener(() => throw StateError('the listener blew up'))
      ..set(42);
    await Future<void>.delayed(Duration.zero);

    expect(
      job.outcome,
      isA<Cancelled>(),
      reason: 'the state no longer matches keepWhile',
    );
    await counter.close();
  });

  test('close removes every listener', () async {
    final counter = _Counter()..addListener(() {});
    expect(counter.hasListeners, isTrue);

    await counter.close();

    expect(counter.hasListeners, isFalse);
  });

  test('a job emit notifies listeners', () async {
    final counter = _Counter();
    final seen = <int>[];
    counter.addListener(() => seen.add(counter.value));
    await counter.perform((ctx) async {
      ctx
        ..emit(5)
        ..emit(6);
    }).done;
    expect(seen, [5, 6]);
    await counter.close();
  });

  test(
    'a listener added after close hears nothing and is not retained',
    () async {
      final counter = _Counter();
      await counter.close();

      final calls = <int>[];
      expect(counter.hasListeners, isFalse);
      counter.addListener(() => calls.add(counter.value));
      expect(counter.hasListeners, isFalse);

      expect(() => counter.set(7), throwsA(isA<StateError>()));
      expect(counter.value, 0);
      expect(calls, isEmpty);
    },
  );

  test('close returns the same future on repeated calls', () async {
    final counter = _Counter();
    final first = counter.close();
    final second = counter.close();
    expect(identical(first, second), isTrue);
    await first;
  });

  test(
    'a microtask scheduled from observer.onClose does not notify listeners',
    () async {
      final counter = _Counter();
      final heard = <int>[];
      counter.addListener(() => heard.add(counter.value));

      final previousObserver = Solo.observer;
      Object? error;
      // Both checks live inside the microtask: taken after it, they would
      // also pass if the drop happened later than the boundary claims.
      bool? retainedInMicrotask;
      Solo.observer = _ClosingObserver((solo) {
        if (identical(solo, counter)) {
          scheduleMicrotask(() {
            retainedInMicrotask = counter.hasListeners;
            try {
              counter.set(9);
            } on Object catch (caught) {
              error = caught;
            }
          });
        }
      });
      addTearDown(() => Solo.observer = previousObserver);

      await counter.close();
      await Future<void>.delayed(Duration.zero);

      expect(retainedInMicrotask, isFalse);
      expect(counter.hasListeners, isFalse);
      expect(counter.value, 0);
      expect(heard, isEmpty);
      expect(error, isA<StateError>());
    },
  );

  test(
    'a synchronous change from observer.onClose notifies listeners before drop',
    () async {
      final counter = _Counter();
      final heard = <int>[];
      counter.addListener(() => heard.add(counter.value));

      final previousObserver = Solo.observer;
      Solo.observer = _ClosingObserver((solo) {
        if (identical(solo, counter)) {
          counter.set(8);
        }
      });
      addTearDown(() => Solo.observer = previousObserver);

      await counter.close();

      expect(counter.value, 8);
      expect(heard, [8]);
    },
  );

  testWidgets(
    'SoloListenable with SoloStream delivers both, on their own schedules',
    (tester) async {
      final controller = _Both();
      addTearDown(controller.close);
      final built = <int>[];
      final streamed = <int>[];
      final subscription = controller.stream.listen(streamed.add);
      addTearDown(subscription.cancel);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<int>(
            valueListenable: controller,
            builder: (context, value, _) {
              built.add(value);
              return const SizedBox();
            },
          ),
        ),
      );

      controller.set(1);
      // The listener behind ValueListenableBuilder fires synchronously;
      // the stream event is still waiting for a microtask.
      expect(streamed, isEmpty);
      await tester.pump();

      expect(built, [0, 1]);
      expect(streamed, [1]);
    },
  );

  testWidgets(
    'SoloListenable ahead of SoloStream in with delivers both too',
    (tester) async {
      final controller = _BothReversed();
      addTearDown(controller.close);
      final built = <int>[];
      final streamed = <int>[];
      final subscription = controller.stream.listen(streamed.add);
      addTearDown(subscription.cancel);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<int>(
            valueListenable: controller,
            builder: (context, value, _) {
              built.add(value);
              return const SizedBox();
            },
          ),
        ),
      );

      controller.set(1);
      expect(streamed, isEmpty);
      await tester.pump();

      expect(built, [0, 1]);
      expect(streamed, [1]);
    },
  );

  test(
    'a paused stream subscription holds close() open on SoloListenable too',
    () async {
      final controller = _Both();
      final subscription = controller.stream.listen((_) {})..pause();
      var closeDone = false;
      final closing = controller.close().then((_) => closeDone = true);

      try {
        await Future<void>.delayed(Duration.zero);
        expect(closeDone, isFalse, reason: 'the paused stream holds close');
      } finally {
        subscription.resume();
        await subscription.cancel();
        await closing;
      }

      expect(closeDone, isTrue);
    },
  );

  testWidgets(
    'a leaf over a base without Flutter drives ValueListenableBuilder and '
    'Listenable.merge',
    (tester) async {
      final leaf = _Leaf();
      addTearDown(leaf.close);
      var merged = 0;
      void onMerged() => merged++;
      final merge = Listenable.merge([leaf])..addListener(onMerged);
      addTearDown(() => merge.removeListener(onMerged));

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<int>(
            valueListenable: leaf,
            builder: (context, value, _) => Text('$value'),
          ),
        ),
      );
      leaf.set(7);
      await tester.pump();

      expect(find.text('7'), findsOneWidget);
      expect(merged, 1);
    },
  );

  test(
    'SoloListenable on the leaf reports over an onListenerError of the base',
    () async {
      final leaf = _ReportingLeaf();
      final reports = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reports.add;
      addTearDown(() => FlutterError.onError = previous);

      final plain = _PlainReportingLeaf()
        ..addListener(() => throw StateError('the listener blew up'))
        ..set(1);
      expect(plain.reported.single, isA<StateError>());
      expect(reports, isEmpty, reason: 'the base reports on its own');

      leaf
        ..addListener(() => throw StateError('the listener blew up'))
        ..set(1);

      expect(reports.single.exception, isA<StateError>());
      expect(leaf.reported, isEmpty);
      await plain.close();
      await leaf.close();
    },
  );

  test('a base that mixes SoloListenable in keeps its own onListenerError',
      () async {
    final leaf = _MigratedLeaf();
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);

    leaf
      ..addListener(() => throw StateError('the listener blew up'))
      ..set(1);

    expect(leaf, isA<ValueListenable<int>>(), reason: 'the base mixes it in');
    expect(leaf.reported.single, isA<StateError>());
    expect(reports, isEmpty);
    await leaf.close();
  });

  test('SoloListenable mixed in again on the leaf silences the base', () async {
    final leaf = _MixedTwiceLeaf();
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);

    leaf
      ..addListener(() => throw StateError('the listener blew up'))
      ..set(1);

    expect(leaf.reported, isEmpty, reason: 'the second mixin sits above');
    expect(reports.single.exception, isA<StateError>());
    await leaf.close();
  });

  test('the mixin repeats @protected on the engine hook', () {
    // Dart does not inherit `@protected`, and an override that leaves it
    // off makes a hook of the engine a public member of every controller
    // with this mixin. The analyzer is the only place this shows, so the
    // guard reads the source: a runtime call cannot tell the two apart.
    final source = File('lib/src/solo_listenable.dart').readAsStringSync();
    expect(
      source,
      contains(RegExp(r'@protected\s+@override\s+void onListenerError\(')),
    );
  });

  test('the bases of these tests import nothing of Flutter', () {
    final source = File('test/support/plain_base.dart').readAsStringSync();
    final imports = RegExp("^import '([^']+)';", multiLine: true)
        .allMatches(source)
        .map((match) => match[1])
        .toList();
    expect(imports, ['package:solo/solo.dart']);
  });
}
