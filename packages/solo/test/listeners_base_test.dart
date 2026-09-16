import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

void main() {
  tearDown(() => Solo.observer = null);

  test(
    'listeners are called on each change, in subscription order, synchronously',
    () {
      final solo = TestSolo();
      final log = <String>[];

      solo
        ..addListener(() => log.add('first:${solo.currentState}'))
        ..addListener(() => log.add('second:${solo.currentState}'));

      solo.externalSetState(const Preparing(progress: 10));
      expect(log, [
        'first:Preparing(progress: 10)',
        'second:Preparing(progress: 10)',
      ]);

      log.clear();
      // Equality is not checked: each change triggers listeners
      solo.externalSetState(const Preparing(progress: 10));
      expect(log, [
        'first:Preparing(progress: 10)',
        'second:Preparing(progress: 10)',
      ]);
    },
  );

  test(
    'listener error goes to zone, pass continues and rules reevaluation '
    'still cancels job',
    () {
      runSolo(initialState: const Preparing(), (solo, journal, async) {
        final zoneErrors = <Object>[];
        var secondCalled = false;

        solo
          ..addListener(() => throw StateError('first listener failed'))
          ..addListener(() => secondCalled = true);

        final job = solo.run<Preparing, void>(
          (ctx) async {
            await delay(100);
            ctx.check();
          },
          key: 'job',
          keepWhile: (state) => state.progress < 100,
        );

        async.elapse(const Duration(milliseconds: 50));

        runZonedGuarded(() {
          solo.externalSetState(const Preparing(progress: 100));
        }, (error, stackTrace) {
          zoneErrors.add(error);
        });

        expect(secondCalled, isTrue);
        expect(zoneErrors, hasLength(1));
        expect(zoneErrors.first, isA<StateError>());
        expect(
          (zoneErrors.first as StateError).message,
          'first listener failed',
        );

        expect(job.isCancelled, isTrue);
        async.elapse(const Duration(milliseconds: 50));
        expect(job.outcome, isA<Cancelled>());
        expect(
          (job.outcome! as Cancelled).reason,
          const RulesCancelReason(),
        );
      });
    },
  );

  test(
    'onListenerError error goes to zone, pass continues and rules reevaluation '
    'still cancels job',
    () async {
      final solo = _ThrowingReporterSolo(const Preparing());
      final zoneErrors = <Object>[];
      var secondCalled = false;
      final started = Completer<void>();
      final parked = Completer<void>();

      final job = solo.run<Preparing, void>(
        (ctx) async {
          started.complete();
          await parked.future;
          ctx.check();
        },
        key: 'job',
        keepWhile: (state) => state.progress < 100,
      );

      await started.future;

      solo
        ..addListener(() => throw StateError('listener failed'))
        ..addListener(() => secondCalled = true);

      runZonedGuarded(() {
        solo.externalSetState(const Preparing(progress: 100));
      }, (error, stackTrace) {
        zoneErrors.add(error);
      });

      expect(secondCalled, isTrue);
      expect(zoneErrors, hasLength(1));
      expect(zoneErrors.first, isA<StateError>());
      expect((zoneErrors.first as StateError).message, 'reporter failed');

      expect(job.isCancelled, isTrue);
      parked.complete();
      try {
        await job.done;
      } on Object catch (_) {}
      expect(
        (job.outcome! as Cancelled).reason,
        const RulesCancelReason(),
      );
    },
  );

  test('nested externalSetState trace matches spec verbatim', () async {
    final log = <String>[];
    final solo = _TracedSolo(log);
    final started = Completer<void>();
    final parked = Completer<void>();

    solo.run<int, void>(
      (ctx) async {
        ctx.onCancel(() => log.add('cancelled'));
        started.complete();
        await parked.future;
      },
      key: 'job',
      keepWhile: (state) => state != 2,
    );

    await started.future;

    void a() {
      log.add('A:${solo.currentState}');
      if (solo.currentState == 1) {
        solo.externalSetState(2);
        log.add('A-return');
      }
    }

    void b() {
      log.add('B:${solo.currentState}');
    }

    solo
      ..addListener(a)
      ..addListener(b)
      ..externalSetState(1);

    expect(log, [
      'publish:1',
      'A:1',
      'cancelled',
      'A-return',
      'B:2',
      'publish:2',
      'A:2',
      'B:2',
    ]);
    parked.complete();
  });

  test(
    'during close drain mode notifications continue and subscription works',
    () {
      runSolo((solo, journal, async) {
        solo.run<TestState, void>(
          (ctx) async {
            await delay(100);
            solo.externalSetState(const Working(a: 1));
            await delay(100);
            solo.externalSetState(const Working(a: 2));
          },
          key: 'work',
        );

        async.elapse(const Duration(milliseconds: 50));
        unawaited(solo.close(mode: SoloCloseMode.drain));

        expect(solo.isClosed, isTrue);
        expect(solo.isDraining, isTrue);

        final log = <String>[];
        solo.addListener(() => log.add('drain-listener:${solo.currentState}'));
        expect(solo.hasListeners, isTrue);

        async.elapse(const Duration(milliseconds: 100));
        expect(log, ['drain-listener:Working(a: 1, b: 0)']);

        async.elapse(const Duration(milliseconds: 100));
        expect(log, [
          'drain-listener:Working(a: 1, b: 0)',
          'drain-listener:Working(a: 2, b: 0)',
        ]);

        async.flushMicrotasks();
        expect(solo.isDraining, isFalse);
        expect(solo.hasListeners, isFalse);
      });
    },
  );

  test(
    'subscription in observer onClose hears synchronous externalSetState '
    'and is dropped immediately after',
    () async {
      final log = <String>[];
      final observer = _OnCloseObserver(log);
      Solo.observer = observer;

      final solo = TestSolo();
      solo.addListener(() => log.add('existing:${solo.currentState}'));

      expect(solo.hasListeners, isTrue);
      await solo.close();

      expect(log, [
        'onClose start',
        'existing:Preparing(progress: 99)',
        'subscribed-in-onClose:Preparing(progress: 99)',
        'onClose end',
      ]);
      expect(solo.hasListeners, isFalse);
    },
  );

  test(
    'after close addListener does not retain listener and does not notify',
    () async {
      final solo = TestSolo();
      await solo.close();

      var called = false;
      solo.addListener(() => called = true);

      expect(solo.hasListeners, isFalse);

      expect(
        () => solo.externalSetState(const Working(a: 42)),
        throwsA(isA<StateError>()),
      );
      expect(solo.currentState, const Initial());
      expect(called, isFalse);
      expect(solo.hasListeners, isFalse);
    },
  );

  test('close from listener does not abort current pass', () {
    final solo = TestSolo();
    final log = <String>[];

    void a() {
      log.add('A');
      unawaited(solo.close());
    }

    void b() {
      log.add('B');
    }

    solo
      ..addListener(a)
      ..addListener(b)
      ..externalSetState(const Working());

    expect(log, ['A', 'B']);
    expect(solo.isClosed, isTrue);
  });

  test(
    'controller without listeners publishes normally without container',
    () {
      final solo = TestSolo();
      expect(solo.hasListeners, isFalse);

      solo.externalSetState(const Working());
      expect(solo.currentState, const Working());
      expect(solo.hasListeners, isFalse);

      solo.removeListener(() {});
      expect(solo.hasListeners, isFalse);
    },
  );
}

final class _ThrowingReporterSolo extends Solo<TestState> {
  _ThrowingReporterSolo(super.initialState);

  @override
  bool get hasListeners => super.hasListeners;

  @override
  void onListenerError(Object error, StackTrace stackTrace) {
    throw StateError('reporter failed');
  }

  @override
  void externalSetState(TestState state) => super.externalSetState(state);
}

final class _TracedSolo extends Solo<int> {
  final List<String> log;

  _TracedSolo(this.log) : super(0);

  @override
  void publish(int previous, int current) {
    log.add('publish:$current');
    super.publish(previous, current);
  }

  @override
  void externalSetState(int state) => super.externalSetState(state);
}

final class _OnCloseObserver extends SoloObserver {
  final List<String> log;

  _OnCloseObserver(this.log);

  @override
  void onClose(Solo<Object> solo) {
    log.add('onClose start');
    solo.addListener(() {
      log.add('subscribed-in-onClose:${solo.currentState}');
    });
    (solo as TestSolo).externalSetState(const Preparing(progress: 99));
    log.add('onClose end');
  }
}
