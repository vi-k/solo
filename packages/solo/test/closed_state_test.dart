@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/test_state.dart';

void main() {
  tearDown(() => Solo.observer = null);

  test('external state is accepted before close and rejected after it',
      () async {
    final solo = _ExposedSolo()..set(const Preparing(progress: 1));
    expect(solo.currentState, const Preparing(progress: 1));

    await solo.close();

    expect(
      () => solo.set(const Preparing(progress: 2)),
      throwsA(isA<StateError>()),
    );
    expect(solo.currentState, const Preparing(progress: 1));
  });

  test('rejected external state calls neither change hook', () async {
    final solo = _CountingSolo();
    final observer = _CountingObserver();
    Solo.observer = observer;

    solo.set(const Preparing(progress: 1));
    expect(solo.changes, 1);
    expect(observer.changes, 1);

    await solo.close();

    expect(
      () => solo.set(const Preparing(progress: 2)),
      throwsA(isA<StateError>()),
    );
    expect(solo.changes, 1);
    expect(observer.changes, 1);
  });

  test('isFinished is false until a drain has finished', () async {
    final solo = _ExposedSolo();
    expect(solo.isFinished, isFalse);
    final started = Completer<void>();
    final release = Completer<void>();
    var finishedDuringJob = true;

    solo.run<TestState, void>((ctx) async {
      started.complete();
      finishedDuringJob = solo.isFinished;
      await release.future;
      finishedDuringJob = solo.isFinished;
    });
    await started.future;

    final closing = solo.close(mode: SoloCloseMode.drain);
    expect(solo.isFinished, isFalse);
    release.complete();
    await closing;

    expect(finishedDuringJob, isFalse);
    expect(solo.isFinished, isTrue);
  });

  test('external state is delivered during a drain', () async {
    final solo = _ExposedStreamSolo();
    final listenerStates = <TestState>[];
    final streamStates = <TestState>[];
    solo.addListener(() => listenerStates.add(solo.currentState));
    solo.stream.listen(streamStates.add);

    final started = Completer<void>();
    final release = Completer<void>();
    solo.run<TestState, void>((ctx) async {
      started.complete();
      await release.future;
    });
    await started.future;

    final closing = solo.close(mode: SoloCloseMode.drain);
    solo.set(const Preparing(progress: 7));
    expect(listenerStates, [const Preparing(progress: 7)]);
    await Future<void>.delayed(Duration.zero);
    expect(streamStates, [const Preparing(progress: 7)]);

    release.complete();
    await closing;
  });

  test('external state from onClose is synchronous but not from its microtask',
      () async {
    final solo = _ExposedSolo();
    final heard = <String>[];
    solo.addListener(() => heard.add('existing:${solo.currentState}'));

    var finishedInHook = true;
    var listenersInMicrotask = true;
    Object? microtaskError;
    Solo.observer = _CloseObserver((base) {
      final controller = base as _ExposedSolo;
      finishedInHook = controller.isFinished;
      controller.addListener(
        () => heard.add('late:${controller.currentState}'),
      );
      controller.set(const Preparing(progress: 8));
      scheduleMicrotask(() {
        listenersInMicrotask = controller.hasListeners;
        try {
          controller.set(const Preparing(progress: 9));
        } on Object catch (error) {
          microtaskError = error;
        }
      });
    });

    await solo.close();
    await Future<void>.delayed(Duration.zero);

    expect(finishedInHook, isFalse);
    expect(heard, [
      'existing:Preparing(progress: 8)',
      'late:Preparing(progress: 8)',
    ]);
    expect(listenersInMicrotask, isFalse);
    expect(microtaskError, isA<StateError>());
    expect(solo.currentState, const Preparing(progress: 8));
  });

  test('a non-cancellable job emits its final state before close finishes',
      () async {
    final solo = _ExposedSolo();
    final started = Completer<void>();
    final release = Completer<void>();

    solo.run<TestState, void>(
      cancellable: false,
      (ctx) async {
        started.complete();
        ctx.emit(const Preparing(progress: 1));
        await release.future;
        ctx.emit(const Working(a: 2));
      },
    );
    await started.future;

    var closeDone = false;
    final closing = solo.close().then((_) => closeDone = true);
    expect(closeDone, isFalse);
    release.complete();
    await closing;

    expect(solo.currentState, const Working(a: 2));
    expect(closeDone, isTrue);
  });

  test('repeated close returns one future and calls onClose once', () async {
    final solo = _ExposedSolo();
    var closeCalls = 0;
    Solo.observer = _CloseObserver((_) => closeCalls++);

    final first = solo.close();
    final second = solo.close();
    expect(identical(first, second), isTrue);
    await first;
    final third = solo.close();

    expect(identical(first, third), isTrue);
    expect(solo.isFinished, isTrue);
    expect(closeCalls, 1);
  });

  test('engine finishes before a paused Solo stream lets close finish',
      () async {
    final solo = _ExposedStreamSolo();
    final subscription = solo.stream.listen((_) {})..pause();
    var closeDone = false;
    final closing = solo.close().then((_) => closeDone = true);

    try {
      await Future<void>.delayed(Duration.zero);
      expect(solo.isFinished, isTrue);
      expect(closeDone, isFalse);
      expect(
        () => solo.set(const Preparing(progress: 3)),
        throwsA(isA<StateError>()),
      );
    } finally {
      subscription.resume();
      await subscription.cancel();
    }
    await closing;
  });

  test('a disposer of the job close waits for still writes', () async {
    final solo = _ExposedSolo();
    final started = Completer<void>();
    Object? refused;

    solo.run<TestState, void>((ctx) async {
      ctx.onDispose(() {
        // Cleanup unwinds inside the job, before the engine finishes: a
        // fact arriving here is still a fact about a live controller.
        try {
          solo.set(const Working(a: 5));
        } on Object catch (error) {
          refused = error;
        }
      });
      started.complete();
      await ctx.wait(() => Future<void>.delayed(const Duration(seconds: 10)));
    });
    await started.future;

    await solo.close();

    expect(refused, isNull);
    expect(solo.currentState, const Working(a: 5));
    // The other half of the same input: once the engine is done, the very
    // same write is refused.
    expect(
      () => solo.set(const Working(a: 6)),
      throwsA(isA<StateError>()),
    );
  });

  test('overriding isFinished cannot reopen external state', () async {
    final ordinary = _ExposedSolo()..set(const Preparing(progress: 1));
    expect(ordinary.currentState, const Preparing(progress: 1));
    await ordinary.close();

    final lying = _LyingSolo();
    expect(lying.isFinished, isFalse);
    await lying.close();

    expect(
      () => lying.set(const Preparing(progress: 2)),
      throwsA(isA<StateError>()),
    );
    expect(lying.currentState, const Initial());
  });
}

class _ExposedSolo extends Solo<TestState> {
  _ExposedSolo([super.initialState = const Initial()]);

  @override
  bool get hasListeners => super.hasListeners;

  void set(TestState state) => externalSetState(state);
}

final class _LyingSolo extends _ExposedSolo {
  @override
  bool get isFinished => false;
}

final class _CountingSolo extends _ExposedSolo {
  int changes = 0;

  @override
  void onChange(SoloTransition<TestState> transition) {
    changes++;
  }
}

final class _CountingObserver extends SoloObserver {
  int changes = 0;

  @override
  void onChange(
    Solo<Object> solo,
    SoloTransition<Object> transition,
  ) {
    changes++;
  }
}

final class _CloseObserver extends SoloObserver {
  final void Function(Solo<Object> solo) callback;

  _CloseObserver(this.callback);

  @override
  void onClose(Solo<Object> solo) => callback(solo);
}

final class _ExposedStreamSolo extends Solo<TestState> with SoloStream {
  _ExposedStreamSolo() : super(const Initial());

  void set(TestState state) => externalSetState(state);
}
