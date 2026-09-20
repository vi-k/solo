@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

/// What `doc/errors.md` states, pinned next to the page.
///
/// The page has no bench: it shows fragments of an application, not a
/// program that runs. So every claim it makes about where an error goes —
/// the hook, the handler, the zone, the outcome — is guarded here instead,
/// and so are the two numbers of its delay table. The observer recipe is
/// copied from the page as it stands, with `log` collecting lines instead
/// of printing them.

// --- The domain -----------------------------------------------------------

final class Value {
  final int n;

  const Value(this.n);

  @override
  String toString() => 'Value($n)';
}

/// The page's recipe for "Why cancellation was slow", verbatim.
final class SlowCancellations extends SoloObserver {
  SlowCancellations(this.lines);

  final List<String> lines;

  // An Expando holds its key weakly, so a job takes its stamp with it and
  // there is nothing to clean up.
  final _markedAt = Expando<DateTime>('cancellation');

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) {
    // whenCancelled fires when the cancellation takes effect, not when
    // cancel() was called: a step held by ctx.uncancellable runs first.
    job.whenCancelled((_) => _markedAt[job] = clock.now());
  }

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) {
    final markedAt = _markedAt[job];
    if (markedAt == null) return;
    final delay = clock.now().difference(markedAt);
    if (delay > const Duration(milliseconds: 50)) {
      lines.add(
        '${job.key} ran ${delay.inMilliseconds} ms past its cancellation',
      );
    }
  }
}

/// A controller that keeps what its hooks were given, and passes the
/// reporting hook on to `super` — the page's default route.
final class Cam extends Solo<Value> {
  Cam() : super(const Value(0));

  final changes = <SoloTransition<Value>>[];
  final started = <Object?>[];
  final errors = <Object>[];
  final logs = <Object?>[];

  void set(int n) => externalSetState(Value(n));

  @override
  void onChange(SoloTransition<Value> transition) => changes.add(transition);

  @override
  void onStart(Job<Object?> job) => started.add(job.key);

  @override
  void onLog(Job<Object?> job, Object? message) => logs.add(message);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    errors.add(error);
    super.onError(job, error, stackTrace);
  }

  /// A body that holds its cancellation for the whole wait.
  Job<void> bare() => run<Value, void>(
        key: 'bare',
        (ctx) => Future<void>.delayed(const Duration(milliseconds: 300)),
      );

  /// The same call handed to the context.
  Job<void> waited() => run<Value, void>(
        key: 'waited',
        (ctx) => ctx.wait(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        ),
      );

  /// A root whose child emits.
  Job<void> withChild() => run<Value, void>(
        key: 'root',
        (ctx) => ctx.run(
          job<Value, void>(
            key: 'child',
            (child) async => child.emit(const Value(7)),
          ),
        ),
      );

  /// A body that catches its own cancellation and returns normally.
  Job<void> swallows(Completer<void> gate) => run<Value, void>(
        key: 'swallows',
        (ctx) async {
          try {
            await ctx.wait(() => gate.future);
          } on Cancelled {
            // caught and not rethrown
          }
        },
      );

  /// A body that holds cancellation in an uncancellable section.
  Job<void> held(Completer<void> gate, List<String> marks) => run<Value, void>(
        key: 'held',
        (ctx) => ctx.uncancellable(() async {
          marks.add('section in');
          await gate.future;
          marks.add('section out');
        }),
      );

  /// A job whose disposer throws.
  Job<void> dirtyCleanup() => run<Value, void>(
        key: 'cleanup',
        (ctx) async {
          await ctx.join(
            () async => 'handle',
            dispose: (value) async => throw StateError('dispose'),
          );
        },
      );

  /// A job cancelled while a waited call is still in flight.
  Job<void> abandons(Completer<String> late) => run<Value, void>(
        key: 'abandons',
        (ctx) => ctx.wait(() => late.future),
      );

  /// A job that just fails.
  Job<void> fails() => run<Value, void>(
        key: 'fails',
        (ctx) async => throw StateError('body'),
      );

  /// A job that hands its context out and ends.
  Job<void> capture(void Function(SoloContext<Value, Value> ctx) take) =>
      run<Value, void>(key: 'capture', (ctx) async => take(ctx));

  /// Application data for the log hooks.
  Job<void> logsData() =>
      run<Value, void>(key: 'log', (ctx) async => ctx.log(('zoom', 2)));

  /// Work with a life of its own.
  Job<void> unattended(Completer<void> gate, List<Object> caught) =>
      run<Value, void>(
        key: 'unattended',
        (ctx) async {
          ctx.unattended(() async {
            await gate.future;
            throw StateError('background');
          });
          ctx.unattended(() async {
            try {
              await ctx.run(job<Value, void>((child) async {}));
            } on Object catch (error) {
              caught.add(error);
            }
          });
        },
      );

  /// A start rule that throws instead of answering.
  Job<void> refusedByStart() => run<Value, void>(
        key: 'start',
        canStart: (state) => throw StateError('canStart'),
        (ctx) async {},
      );

  /// A rule that throws once the state has moved on.
  Job<void> refusedAtCheckpoint(
    Completer<void> gate,
    List<Object> caught,
  ) =>
      run<Value, void>(
        key: 'checkpoint',
        keepWhile: _movedOn,
        (ctx) async {
          await gate.future;
          try {
            ctx.check();
          } on Object catch (error) {
            caught.add(error);
          }
        },
      );

  /// The same rule on a job that also carries a final state handler.
  Job<void> withHandler(Completer<void> gate, List<String> marks) =>
      run<Value, void>(
        key: 'handler',
        keepWhile: _movedOn,
        onError: (state, error, stackTrace) {
          marks.add('onError');

          return const Value(99);
        },
        (ctx) async {
          await ctx.wait(() => gate.future);
          throw StateError('body');
        },
      );

  /// A group that waits for its window with nothing running.
  SoloAccumulator<int, void> group() => collect<Value, int, void>(
        key: 'group',
        timing: AccumulationTiming.debounce(const Duration(seconds: 1)),
        (ctx, events) async {},
      );

  static bool _movedOn(Value state) {
    if (state.n == 0) return true;
    throw StateError('keepWhile');
  }
}

/// The page's opening example: a reporting hook that omits `super`.
final class Silent extends Cam {
  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      errors.add(error);
}

/// A hook that changes the state again from inside the first.
final class Nesting extends Solo<Value> {
  Nesting() : super(const Value(0));

  final order = <String>[];
  var _nested = false;

  void set(int n) => externalSetState(Value(n));

  @override
  void onChange(SoloTransition<Value> transition) {
    order.add('in ${transition.revision}');
    if (!_nested) {
      _nested = true;
      externalSetState(const Value(2));
    }
    order.add('out ${transition.revision}');
  }
}

final class Streaming extends Solo<Value> with SoloStream<Value> {
  Streaming() : super(const Value(0));
}

void main() {
  tearDown(() {
    Solo.observer = null;
    Solo.errorHandler = null;
  });

  // --- Hooks, the observer and the handler --------------------------------

  group('hooks', () {
    test('a nested change carries a higher revision', () {
      final controller = Nesting()..set(1);

      expect(controller.order, ['in 1', 'in 2', 'out 2', 'out 1']);
    });

    test('transition.job is null for an externalSetState', () {
      final controller = Cam()..set(1);

      expect(controller.changes.single.job, isNull);
    });

    test('transition.job is the child, not the root it belongs to', () async {
      final controller = Cam();
      await controller.withChild().value;

      final change = controller.changes.single;
      expect(change.current.n, 7);
      expect(change.job?.key, 'child');
    });

    test('an observer alone does not mark an outcome as observed', () async {
      final zoneErrors = <Object>[];
      final controller = Cam();
      Solo.observer = SlowCancellations(<String>[]);

      await runZonedGuarded(
        () async {
          controller.fails();
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(zoneErrors, [isA<StateError>()]);
    });

    test('errorHandler takes what would otherwise go to the zone', () async {
      final taken = <Object>[];
      final zoneErrors = <Object>[];
      Solo.errorHandler = (solo, job, error, stackTrace) => taken.add(error);

      await runZonedGuarded(
        () async {
          await Cam().dirtyCleanup().value;
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(taken, [isA<StateError>()]);
      expect(zoneErrors, isEmpty);
    });

    test('an onError that omits super takes the error nowhere', () async {
      final taken = <Object>[];
      final zoneErrors = <Object>[];
      final controller = Silent();
      Solo.errorHandler = (solo, job, error, stackTrace) => taken.add(error);

      await runZonedGuarded(
        () async {
          await controller.dirtyCleanup().value;
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(controller.errors, [isA<StateError>()]);
      expect(taken, isEmpty, reason: 'the handler is never asked');
      expect(zoneErrors, isEmpty, reason: 'and neither is the zone');
    });
  });

  // --- What is holding the controller -------------------------------------

  group('what is holding the controller', () {
    test('pending is null while a group waits for its window', () async {
      final controller = Cam();
      controller.group().add(1);
      final closing = controller.close(mode: SoloCloseMode.drain);

      await pumpEventQueue();

      expect(controller.pending, isNull);
      expect(controller.isDraining, isTrue);

      await closing;
    });

    test('a paused subscription holds close with isFinished true', () async {
      final controller = Streaming();
      final taken = <Value>[];
      final subscription = controller.stream.listen(taken.add)..pause();
      var closed = false;
      final closing = controller.close().then((_) => closed = true);

      await pumpEventQueue();

      expect(controller.isFinished, isTrue);
      expect(closed, isFalse);

      subscription.resume();
      await closing;
      await subscription.cancel();

      expect(closed, isTrue);
    });
  });

  // --- Why cancellation was slow ------------------------------------------

  group('why cancellation was slow', () {
    test('whenCancelled waits for the uncancellable section', () async {
      final controller = Cam();
      final gate = Completer<void>();
      final marks = <String>[];
      final job = controller.held(gate, marks)
        ..whenCancelled((_) => marks.add('whenCancelled'));

      await pumpEventQueue();
      unawaited(job.cancel());
      await pumpEventQueue();
      marks.add('cancel asked');
      gate.complete();
      await job.done;

      expect(marks, [
        'section in',
        'cancel asked',
        'section out',
        'whenCancelled',
      ]);
    });

    test('a bare await reports 290 ms of a 300 ms wait', () {
      fakeAsync((async) {
        final lines = <String>[];
        Solo.observer = SlowCancellations(lines);
        final job = Cam().bare();

        async.elapse(const Duration(milliseconds: 10));
        job.cancel().ignore();
        async.elapse(const Duration(seconds: 1));

        expect(lines, ['bare ran 290 ms past its cancellation']);
      });
    });

    test('the same call through ctx.wait reports nothing', () {
      fakeAsync((async) {
        final lines = <String>[];
        Solo.observer = SlowCancellations(lines);
        final job = Cam().waited();

        async.elapse(const Duration(milliseconds: 10));
        job.cancel().ignore();
        async.elapse(const Duration(seconds: 1));

        expect(lines, isEmpty);
      });
    });

    test('a job cancelled before it started reports nothing', () async {
      final controller = Cam();
      final gate = Completer<void>();
      final running = controller.swallows(gate);
      final queued = controller.swallows(gate);

      await pumpEventQueue();
      await queued.cancel();
      gate.complete();
      await running.value;

      expect(controller.started, ['swallows'], reason: 'onStart ran once');
    });
  });

  // --- Handled and unhandled failures -------------------------------------

  group('handled and unhandled failures', () {
    test('value marks the outcome as observed', () async {
      final zoneErrors = <Object>[];
      final controller = Cam();

      await runZonedGuarded(
        () async {
          await expectLater(controller.fails().value, throwsStateError);
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(zoneErrors, isEmpty);
      expect(
        controller.errors,
        [isA<StateError>()],
        reason: 'the hook sees the body failure as well',
      );
    });

    test('done marks the outcome as observed', () async {
      final zoneErrors = <Object>[];

      await runZonedGuarded(
        () async {
          await Cam().fails().done;
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(zoneErrors, isEmpty);
    });

    test('ignore marks the outcome as observed', () async {
      final zoneErrors = <Object>[];

      await runZonedGuarded(
        () async {
          Cam().fails().ignore();
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(zoneErrors, isEmpty);
    });

    test('outcome alone does not mark it observed', () async {
      final zoneErrors = <Object>[];

      await runZonedGuarded(
        () async {
          final job = Cam().fails();
          await pumpEventQueue();

          expect(job.outcome, isA<Failed>(), reason: 'read, and not enough');

          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(zoneErrors, [isA<StateError>()]);
    });

    test('a disposer that throws is reported, and reaches the zone', () async {
      final controller = Cam();
      final zoneErrors = <Object>[];

      await runZonedGuarded(
        () async {
          await controller.dirtyCleanup().value;
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(controller.errors, [isA<StateError>()]);
      expect(zoneErrors, [isA<StateError>()], reason: 'no handler is set');
    });

    test('an abandoned action reports late and leaves the outcome alone',
        () async {
      final controller = Cam();
      final zoneErrors = <Object>[];
      late final Job<void> job;

      await runZonedGuarded(
        () async {
          final late = Completer<String>();
          job = controller.abandons(late)..ignore();
          await pumpEventQueue();
          await job.cancel();
          late.completeError(StateError('late'));
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(controller.errors, [isA<StateError>()]);
      expect(zoneErrors, [isA<StateError>()]);
      expect(job.outcome, isA<Cancelled>(), reason: 'outcome unchanged');
    });

    test('a Cancelled from an abandoned action reaches the hook, not the zone',
        () async {
      final controller = Cam();
      final zoneErrors = <Object>[];
      final spare = controller.abandons(Completer<String>())..ignore();

      await pumpEventQueue();
      await spare.cancel();
      final cancelled = spare.outcome! as Object;

      await runZonedGuarded(
        () async {
          final late = Completer<String>();
          controller.abandons(late).ignore();
          await pumpEventQueue();
          await controller.cancelAll();
          late.completeError(cancelled);
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(controller.errors, [isA<Cancelled>()]);
      expect(zoneErrors, isEmpty);
    });
  });

  // --- Catching errors inside a body --------------------------------------

  group('catching errors inside a body', () {
    test('Cancelled implements Exception', () async {
      final controller = Cam();
      final job = controller.swallows(Completer<void>());

      await pumpEventQueue();
      await job.cancel();

      expect(job.outcome, isA<Cancelled>());
      expect(job.outcome, isA<Exception>());
    });

    test('a body that catches its cancellation still ends Cancelled', () async {
      final controller = Cam();
      final job = controller.swallows(Completer<void>());

      await pumpEventQueue();
      await job.cancel();

      expect(job.outcome, isA<Cancelled>());
    });
  });

  // --- Errors in state rules ----------------------------------------------

  group('errors in state rules', () {
    test('a start rule that throws fails the job, the queue continues',
        () async {
      final controller = Cam();
      final refused = controller.refusedByStart()..ignore();
      final after = controller.logsData();

      await after.value;

      expect(refused.outcome, isA<Failed>());
      expect(controller.errors, [isA<StateError>()]);
      expect(controller.logs, [('zoom', 2)], reason: 'the queue went on');
    });

    test('a rule that throws at a checkpoint reaches the body', () async {
      final controller = Cam();
      final gate = Completer<void>();
      final caught = <Object>[];
      final zoneErrors = <Object>[];

      await runZonedGuarded(
        () async {
          final job = controller.refusedAtCheckpoint(gate, caught);
          await pumpEventQueue();
          controller.set(1);
          gate.complete();
          await job.done;
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(caught, [isA<StateError>()], reason: 'the body got it');
      expect(
        zoneErrors,
        [isA<StateError>()],
        reason: 're-evaluation reported it first, with nobody to answer',
      );
    });

    test('a rule that throws on re-evaluation is reported, not fatal',
        () async {
      final controller = Cam();
      final gate = Completer<void>();
      final marks = <String>[];
      final zoneErrors = <Object>[];
      late final Job<void> job;

      await runZonedGuarded(
        () async {
          job = controller.withHandler(gate, marks)..ignore();
          await pumpEventQueue();
          controller.set(1);
          await pumpEventQueue();

          expect(job.isCancelled, isFalse, reason: 'the body runs on');
          expect(controller.errors, [isA<StateError>()]);

          gate.complete();
          await job.done;
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(marks, isEmpty, reason: 'the final handler is disabled');
      expect(controller.currentState.n, 1, reason: 'no correction to 99');
      expect(zoneErrors, isNotEmpty, reason: 'reported, and nobody answers');
    });
  });

  // --- Background work and logs -------------------------------------------

  group('background work and logs', () {
    test('unattended reports after the job, and refuses children', () async {
      final controller = Cam();
      final gate = Completer<void>();
      final caught = <Object>[];
      final zoneErrors = <Object>[];
      late final Job<void> job;

      await runZonedGuarded(
        () async {
          job = controller.unattended(gate, caught);
          await job.value;

          expect(job.isFinished, isTrue);
          expect(controller.errors, isEmpty, reason: 'the gate is still shut');

          gate.complete();
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(controller.errors, [isA<StateError>()]);
      expect(caught, hasLength(1), reason: 'a child from there is refused');
    });

    test('a captured context is refused after its job is done', () async {
      final controller = Cam();
      late final SoloContext<Value, Value> captured;
      await controller.capture((ctx) => captured = ctx).value;

      expect(() => captured.emit(const Value(5)), throwsA(isA<Object>()));
      expect(controller.currentState.n, 0);
    });

    test('ctx.log forwards application data as it is', () async {
      final controller = Cam();
      await controller.logsData().value;

      expect(controller.logs, [('zoom', 2)]);
    });
  });
}
