@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

/// The first attempts of `doc/errors.md`, and what each one costs.
///
/// Five sections of the page open with the version its vocabulary leads to,
/// and each one is run here: the observer that times a job instead of its
/// cancellation, the observer that reports a failure nobody answered for,
/// the broad catch that takes the cancellation along with the device
/// failures, the rule that throws to refuse, and the bare `unawaited`.
///
/// The page's first section has no first attempt left: reporting and
/// answering are two hooks, and neither can be written for the other.
///
/// The page has no bench: it shows fragments of an application, not a
/// program that runs. So every claim it makes about where an error goes —
/// the hook, the handler, the zone, the outcome — is guarded here as well,
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

/// A controller that keeps what its hooks were given. Its reporting hook
/// reports and returns, which takes nothing away from the route below it.
final class Cam extends Solo<Value> {
  Cam() : super(const Value(0));

  final changes = <SoloTransition<Value>>[];
  final started = <Object?>[];
  final errors = <Object>[];
  final unanswered = <Object>[];
  final logs = <Object?>[];

  void set(int n) => externalSetState(Value(n));

  @override
  void onChange(SoloTransition<Value> transition) => changes.add(transition);

  @override
  void onStart(Job<Object?> job) => started.add(job.key);

  @override
  void onLog(Job<Object?> job, Object? message) => logs.add(message);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      errors.add(error);

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    unanswered.add(error);
    super.onUnanswered(job, error, stackTrace);
  }

  /// A group of two: the caller sees the first failure, and the second,
  /// which refuses to stop and fails on its own, is answered for by
  /// nobody.
  Job<void> groupOfTwo() => run<Value, void>(key: 'group', (ctx) async {
        try {
          await ctx.runAll([
            job<Value, void>(key: 'first', (child) async {
              await child.wait(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
              throw StateError('first');
            }),
            job<Value, void>(key: 'second', cancellable: false, (child) async {
              await child.wait(
                () => Future<void>.delayed(const Duration(milliseconds: 20)),
              );
              throw StateError('second');
            }),
          ]);
        } on Object catch (error) {
          ctx.log('caught $error');
        }
      });

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

  /// A job that turns cancellations down and keeps a section open.
  Job<void> refusing(Completer<void> gate) => run<Value, void>(
        key: 'refusing',
        cancellable: false,
        (ctx) => ctx.uncancellable(() => gate.future),
      );

  /// A body that never comes back.
  Job<void> stuck(Completer<void> gate) => run<Value, void>(
        key: 'stuck',
        (ctx) => ctx.wait(() => gate.future),
      );

  /// A body that never comes back and never looks at its cancellation.
  Job<void> ignores(Completer<void> gate) =>
      run<Value, void>(key: 'ignores', (ctx) => gate.future);

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

  /// A line that costs something to build, logged as the callback that
  /// builds it.
  Job<void> logsLazily(String Function() line) =>
      run<Value, void>(key: 'lazy', (ctx) async => ctx.log(line));

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

  /// Every member of the context that unattended work is refused, each
  /// one caught where it is called.
  Job<void> refusedFromUnattended(List<String> messages) => run<Value, void>(
        key: 'refused',
        (ctx) async {
          ctx.unattended(() async {
            for (final action in <Future<void> Function()>[
              () async => ctx.run(job<Value, void>((child) async {})),
              () async => ctx.runAll([job<Value, void>((child) async {})]),
              () async => ctx.each(const Stream<int>.empty(), (child, e) {}),
              () async => ctx.uncancellable(() async {}),
            ]) {
              try {
                await action();
              } on Object catch (error) {
                messages.add('$error');
              }
            }
          });
        },
      );

  /// The same refusal with nobody to catch it.
  Job<void> forksFromUnattended() => run<Value, void>(
        key: 'fork',
        (ctx) async {
          ctx.unattended(() => ctx.run(job<Value, void>((child) async {})));
        },
      );

  /// The first attempt of "Catching errors inside a body": one catch for
  /// everything that comes out of the device.
  Job<void> broadCatch(Completer<void> gate, Hw hw, List<Object> broken) =>
      run<Value, void>(
        key: 'broad',
        (ctx) async {
          try {
            await ctx.wait(() => gate.future);
            await ctx.join(hw.open);
          } on Object catch (error) {
            await hw.reset();
            // ctx.emit(Broken(error)) on the page.
            broken.add(error);
            ctx.emit(const Value(-1));
            rethrow;
          }
        },
      );

  /// The same body with cancellation let through first.
  Job<void> guardedCatch(Completer<void> gate, Hw hw, List<Object> broken) =>
      run<Value, void>(
        key: 'guarded',
        (ctx) async {
          try {
            await ctx.wait(() => gate.future);
            await ctx.join(hw.open);
          } on Cancelled {
            rethrow;
          } on Object catch (error) {
            await hw.reset();
            broken.add(error);
            ctx.emit(const Value(-1));
            rethrow;
          }
        },
      );

  /// The same separation written inside a single catch clause.
  Job<void> checkedCatch(Completer<void> gate, Hw hw, List<Object> broken) =>
      run<Value, void>(
        key: 'checked',
        (ctx) async {
          try {
            await ctx.wait(() => gate.future);
            await ctx.join(hw.open);
          } on Object catch (error) {
            if (error is Cancelled) rethrow;
            await hw.reset();
            broken.add(error);
            ctx.emit(const Value(-1));
            rethrow;
          }
        },
      );

  /// The first attempt of "Errors in state rules": a rule that throws to
  /// refuse, on a job that also carries a final state handler.
  Job<void> refusesByThrow() => run<Value, void>(
        key: 'refuses',
        canStart: (state) {
          if (state.n == 0) throw StateError('no free slot');

          return true;
        },
        onError: (state, error, stackTrace) => const Value(-1),
        (ctx) async {},
      );

  /// The same refusal as an answer.
  Job<void> refusesByAnswer() => run<Value, void>(
        key: 'answers',
        canStart: (state) => state.n != 0,
        onCancel: (state, cancelled) => const Value(-2),
        (ctx) async {},
      );

  /// A job the state can break under, and the members that break it: the
  /// names are what a stack trace shows, so a guard can tell the trace of
  /// the change from the trace of the checkpoint that noticed it.
  Job<void> keptWhileSmall(Completer<void> gate) => run<Value, void>(
        key: 'kept',
        keepWhile: (state) => state.n < 5,
        (ctx) => ctx.wait(() => gate.future),
      );

  /// A job that breaks its own rule: its own emit is not re-evaluated, so
  /// the checkpoint after it is where the job finds out.
  Job<void> breaksItsOwnRule() => run<Value, void>(
        key: 'own',
        keepWhile: (state) => state.n < 5,
        (ctx) async {
          emitsTooBig(ctx);
          await Future<void>.delayed(Duration.zero);
          readsTheState(ctx);
        },
      );

  /// A job the queue refuses on a state that is already too big.
  Job<void> refusedWhileBig() => run<Value, void>(
        key: 'big',
        canStart: (state) => state.n < 5,
        (ctx) async {},
      );

  void setsTooBig() => externalSetState(const Value(9));

  void emitsTooBig(SoloContext<Value, Value> ctx) => ctx.emit(const Value(9));

  void readsTheState(SoloContext<Value, Value> ctx) => ctx.state;

  /// The first attempt of "Background work and logs": a future the caller
  /// does not wait for.
  Job<void> bareUnawaited(Completer<void> gate) => run<Value, void>(
        key: 'unawaited',
        (ctx) async {
          unawaited(() async {
            await gate.future;
            throw StateError('analytics');
          }());
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

/// A controller of "Reporting an error" that answers for its own errors:
/// it keeps them and hands them on to nobody.
final class Silent extends Cam {
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {}
}

/// The page's recipe for a cancellation that never lands, verbatim.
final class StuckCancellations extends SoloObserver {
  StuckCancellations(this.lines);

  final List<String> lines;

  final _timers = Expando<Timer>('cancellation');

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) => job.whenCancelled(
        (_) => _timers[job] = Timer(
          const Duration(seconds: 5),
          () => lines.add('${job.key} has not stopped: ${solo.pending}'),
        ),
      );

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) => _timers[job]?.cancel();
}

/// The page's recipe for a job that never ends, verbatim.
final class Hangs extends SoloObserver {
  Hangs(this.lines);

  final List<String> lines;

  // An Expando holds its key weakly, so a job takes its timer with it.
  final _timers = Expando<Timer>('hang');

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) => _timers[job] = Timer(
        const Duration(seconds: 5),
        () => lines.add('${job.key} is still running: ${solo.pending}'),
      );

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) => _timers[job]?.cancel();
}

/// The first attempt of "Why cancellation was slow": the two ends of a job,
/// and the lifetime between them.
final class SlowJobs extends SoloObserver {
  SlowJobs(this.lines);

  final List<String> lines;

  final _startedAt = Expando<DateTime>('start');

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      _startedAt[job] = clock.now();

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) {
    final startedAt = _startedAt[job];
    if (startedAt == null) return;
    final ran = clock.now().difference(startedAt);
    if (ran > const Duration(milliseconds: 50)) {
      lines.add('${job.key} ran ${ran.inMilliseconds} ms');
    }
  }
}

/// The first attempt of "Handled and unhandled failures": an observer that
/// reports every failure it sees.
final class Failures extends SoloObserver {
  Failures(this.lines);

  final List<String> lines;

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) {
    final outcome = job.outcome;
    if (outcome is Failed) lines.add('reported ${outcome.error}');
  }
}

/// The camera of "Catching errors inside a body".
final class Hw {
  Hw(this.calls, {this.broken = false});

  final List<String> calls;
  final bool broken;

  Future<void> open() async {
    calls.add('open');
    if (broken) throw StateError('camera');
  }

  Future<void> reset() async => calls.add('reset');
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
  final traceStateChanges = Solo.traceStateChanges;

  tearDown(() {
    Solo.observer = null;
    Solo.errorHandler = null;
    Solo.traceStateChanges = traceStateChanges;
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

    test('a hook that reports and returns keeps the route', () async {
      final taken = <Object>[];
      final zoneErrors = <Object>[];
      final controller = Cam();
      Solo.errorHandler = (solo, job, error, stackTrace) => taken.add(error);

      await runZonedGuarded(
        () async {
          await controller.dirtyCleanup().value;
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(controller.errors, [isA<StateError>()], reason: 'it reports');
      expect(
        controller.unanswered,
        [isA<StateError>()],
        reason: 'and is asked to answer, because an outcome cannot',
      );
      expect(taken, [isA<StateError>()], reason: 'the handler answers');
      expect(zoneErrors, isEmpty);
    });

    test('a failure a group did not throw is answered for', () async {
      final taken = <Object>[];
      final zoneErrors = <Object>[];
      final controller = Cam();
      Solo.errorHandler = (solo, job, error, stackTrace) => taken.add(error);

      await runZonedGuarded(
        () async {
          await controller.groupOfTwo().value;
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(
        controller.errors.map((error) => '$error'),
        ['Bad state: first', 'Bad state: second'],
        reason: 'both failures are reported',
      );
      expect(
        controller.unanswered.map((error) => '$error'),
        ['Bad state: second'],
        reason: 'the caller took the first one, and nobody took this one',
      );
      expect(taken.map((error) => '$error'), ['Bad state: second']);
      expect(zoneErrors, isEmpty);
    });

    test('an override of onUnanswered answers for the error', () async {
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

      expect(controller.errors, [isA<StateError>()], reason: 'it reports');
      expect(taken, isEmpty, reason: 'the handler is not asked');
      expect(zoneErrors, isEmpty, reason: 'and neither is the zone');
    });

    test('the handler is not asked for a failure of the body', () async {
      final taken = <Object>[];
      final zoneErrors = <Object>[];
      final controller = Cam();
      Solo.errorHandler = (solo, job, error, stackTrace) => taken.add(error);

      await runZonedGuarded(
        () async {
          controller.fails();
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(controller.errors, [isA<StateError>()], reason: 'the hook hears');
      expect(
        controller.unanswered,
        isEmpty,
        reason: 'and nobody is asked to answer: the outcome carries it',
      );
      expect(taken, isEmpty, reason: 'that error has an address of its own');
      expect(
        zoneErrors,
        [isA<StateError>()],
        reason: 'the unobserved outcome takes it to the zone by itself',
      );
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

    test('pending names every field of the table', () async {
      final controller = Cam();
      final gate = Completer<void>();
      final job = controller.refusing(gate)..ignore();

      await pumpEventQueue();

      final waiting = controller.pending!;

      expect(waiting.job, same(job));
      expect(waiting.phase, SoloPhase.body);
      expect(waiting.cancellation, isNull);
      expect(waiting.heldCancellation, isNull);
      expect(waiting.children, 0);
      expect(waiting.inUncancellableSection, isTrue);
      expect(waiting.refusesCancellation, isTrue);
      expect(waiting.closing, isFalse);

      final closing = controller.close();
      await pumpEventQueue();

      final asked = controller.pending!;

      expect(asked.closing, isTrue);
      expect(
        asked.cancellationPending,
        isFalse,
        reason: 'a job that refuses turns this cancellation down',
      );

      gate.complete();
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

    test('a timer armed on start catches the job that never ends', () {
      fakeAsync((async) {
        final lines = <String>[];
        Solo.observer = Hangs(lines);

        Cam().stuck(Completer<void>()).ignore();
        async.elapse(const Duration(seconds: 6));

        expect(lines, [
          'stuck is still running: SoloPending([stuck] in its body)',
        ]);
      });
    });

    test('the line carries the held cancellation as well', () {
      fakeAsync((async) {
        final lines = <String>[];
        Solo.observer = Hangs(lines);
        final job = Cam().held(Completer<void>(), <String>[])..ignore();

        async.elapse(const Duration(seconds: 1));
        job.cancel().ignore();
        async.elapse(const Duration(seconds: 6));

        const line = 'held is still running: SoloPending([held] in its '
            'body, holding Cancelled(manual) back)';

        expect(lines, [line]);
      });
    });

    test('a job that ends in time disarms its own timer', () {
      fakeAsync((async) {
        final lines = <String>[];
        Solo.observer = Hangs(lines);

        Cam().waited().ignore();
        async.elapse(const Duration(seconds: 6));

        expect(lines, isEmpty);
      });
    });

    test('the two ends of a job say nothing about a hang', () {
      fakeAsync((async) {
        final lines = <String>[];
        Solo.observer = SlowJobs(lines);

        Cam().stuck(Completer<void>()).ignore();
        async.elapse(const Duration(seconds: 6));

        expect(
          lines,
          isEmpty,
          reason: 'onFinish never comes for a job that never finishes',
        );
      });
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

    test('the first attempt times the job, not its cancellation', () {
      fakeAsync((async) {
        final lines = <String>[];
        Solo.observer = SlowJobs(lines);
        final controller = Cam();

        controller.waited().ignore();
        async.elapse(const Duration(seconds: 1));

        final cancelled = controller.bare();
        async.elapse(const Duration(milliseconds: 10));
        cancelled.cancel().ignore();
        async.elapse(const Duration(seconds: 1));

        expect(
          lines,
          ['waited ran 300 ms', 'bare ran 300 ms'],
          reason: 'the job nobody cancelled reads the same',
        );
      });
    });

    test('the recipe says nothing about a job nobody cancelled', () {
      fakeAsync((async) {
        final lines = <String>[];
        Solo.observer = SlowCancellations(lines);

        Cam().waited().ignore();
        async.elapse(const Duration(seconds: 1));

        expect(lines, isEmpty);
      });
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

    test('a cancellation that never lands is reported while it is on', () {
      fakeAsync((async) {
        final lines = <String>[];
        Solo.observer = StuckCancellations(lines);
        final job = Cam().ignores(Completer<void>())..ignore();

        async.elapse(const Duration(seconds: 1));
        job.cancel().ignore();
        async.elapse(const Duration(seconds: 6));

        const line = 'ignores has not stopped: SoloPending([ignores] in its '
            'body, cancelled by Cancelled(manual))';

        expect(lines, [line]);
      });
    });

    test('a job nobody cancelled arms nothing', () {
      fakeAsync((async) {
        final lines = <String>[];
        Solo.observer = StuckCancellations(lines);

        Cam().ignores(Completer<void>()).ignore();
        async.elapse(const Duration(seconds: 20));

        expect(lines, isEmpty);
      });
    });

    test('a job that stops when asked disarms its timer', () {
      fakeAsync((async) {
        final lines = <String>[];
        Solo.observer = StuckCancellations(lines);
        final job = Cam().waited()..ignore();

        async.elapse(const Duration(milliseconds: 10));
        job.cancel().ignore();
        async.elapse(const Duration(seconds: 6));

        expect(lines, isEmpty);
      });
    });

    test('a held cancellation has not fired, so nothing is armed', () {
      fakeAsync((async) {
        final lines = <String>[];
        Solo.observer = StuckCancellations(lines);
        final job = Cam().held(Completer<void>(), <String>[])..ignore();

        async.elapse(const Duration(seconds: 1));
        job.cancel().ignore();
        async.elapse(const Duration(seconds: 6));

        expect(
          lines,
          isEmpty,
          reason: 'whenCancelled waits for the section to close',
        );
      });
    });
  });

  // --- Handled and unhandled failures -------------------------------------

  group('handled and unhandled failures', () {
    test('the first attempt reports the failure, and the zone gets it too',
        () async {
      final lines = <String>[];
      final zoneErrors = <Object>[];
      final controller = Cam();
      Solo.observer = Failures(lines);

      await runZonedGuarded(
        () async {
          controller.fails();
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(
        lines,
        ['reported Bad state: body'],
        reason: 'the reporter has it',
      );
      expect(
        zoneErrors,
        [isA<StateError>()],
        reason: 'and nobody observed the outcome',
      );
    });

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

    test('an unhandled value takes a Cancelled to the zone after all',
        () async {
      final zoneErrors = <Object>[];

      await runZonedGuarded(
        () async {
          final controller = Cam();
          final job = controller.abandons(Completer<String>());
          // The future is taken and its error is not handled: Dart's own
          // route, not the engine's.
          unawaited(job.value.then((_) {}));
          await pumpEventQueue();
          await job.cancel();
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      await pumpEventQueue();

      expect(zoneErrors, [isA<Cancelled>()]);
    });
  });

  // --- Catching errors inside a body --------------------------------------

  group('catching errors inside a body', () {
    test('the first attempt resets a camera the job never opened', () async {
      final controller = Cam();
      final calls = <String>[];
      final broken = <Object>[];
      final zoneErrors = <Object>[];
      late final Job<void> job;

      await runZonedGuarded(
        () async {
          job = controller.broadCatch(
            Completer<void>(),
            Hw(calls),
            broken,
          )..ignore();
          await pumpEventQueue();
          await job.cancel();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(calls, ['reset'], reason: 'open never ran');
      expect(broken, [isA<Cancelled>()], reason: 'read as a device failure');
      expect(job.outcome, isA<Cancelled>());
      expect(
        controller.currentState.n,
        0,
        reason: 'emit on a cancelled job throws, so Broken never publishes',
      );
      expect(controller.errors, isEmpty);
      expect(zoneErrors, isEmpty);
    });

    test('cancellation let through first leaves the camera alone', () async {
      final controller = Cam();
      final calls = <String>[];
      final broken = <Object>[];
      final job = controller.guardedCatch(
        Completer<void>(),
        Hw(calls),
        broken,
      )..ignore();

      await pumpEventQueue();
      await job.cancel();

      expect(calls, isEmpty);
      expect(broken, isEmpty);
      expect(job.outcome, isA<Cancelled>());
    });

    test('and still handles a failure of the device', () async {
      final controller = Cam();
      final calls = <String>[];
      final broken = <Object>[];
      final gate = Completer<void>()..complete();
      final job = controller.guardedCatch(
        gate,
        Hw(calls, broken: true),
        broken,
      )..ignore();

      await job.done;

      expect(calls, ['open', 'reset']);
      expect(broken, [isA<StateError>()]);
      expect(job.outcome, isA<Failed>());
      expect(controller.currentState.n, -1, reason: 'Broken is published');
    });

    test('the type check leaves the camera alone as well', () async {
      final controller = Cam();
      final calls = <String>[];
      final broken = <Object>[];
      final job = controller.checkedCatch(
        Completer<void>(),
        Hw(calls),
        broken,
      )..ignore();

      await pumpEventQueue();
      await job.cancel();

      expect(calls, isEmpty);
      expect(broken, isEmpty);
      expect(job.outcome, isA<Cancelled>());
    });

    test('and handles a failure of the device the same way', () async {
      final controller = Cam();
      final calls = <String>[];
      final broken = <Object>[];
      final gate = Completer<void>()..complete();
      final job = controller.checkedCatch(
        gate,
        Hw(calls, broken: true),
        broken,
      )..ignore();

      await job.done;

      expect(calls, ['open', 'reset']);
      expect(broken, [isA<StateError>()]);
      expect(job.outcome, isA<Failed>());
      expect(controller.currentState.n, -1, reason: 'Broken is published');
    });

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
    test('the first attempt turns a refusal into a reported failure', () async {
      final controller = Cam();
      final zoneErrors = <Object>[];
      late final Job<void> job;

      await runZonedGuarded(
        () async {
          job = controller.refusesByThrow();
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(job.outcome, isA<Failed>());
      expect(controller.errors, [isA<StateError>()], reason: 'the hooks hear');
      expect(
        zoneErrors,
        [isA<StateError>()],
        reason: 'and the outcome nobody observed reaches the zone',
      );
      expect(
        controller.currentState.n,
        0,
        reason: 'the onError of that run corrects nothing: it never started',
      );
    });

    test('a rule that answers false cancels the job and reports nothing',
        () async {
      final controller = Cam();
      final zoneErrors = <Object>[];
      late final Job<void> job;

      await runZonedGuarded(
        () async {
          job = controller.refusesByAnswer()..ignore();
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(job.outcome, isA<Cancelled>());
      expect(controller.errors, isEmpty);
      expect(zoneErrors, isEmpty);
      expect(controller.currentState.n, 0);
    });

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

    test('a rejected change leaves its own trace on the Cancelled', () async {
      final controller = Cam();
      final job = controller.keptWhileSmall(Completer<void>())..ignore();

      await pumpEventQueue();
      controller.setsTooBig();
      await job.done;

      expect(
        '${(job.outcome! as Cancelled).stackTrace}',
        contains('setsTooBig'),
      );
    });

    test('and leads to the change without that trace as well', () async {
      Solo.traceStateChanges = false;
      final controller = Cam();
      final job = controller.keptWhileSmall(Completer<void>())..ignore();

      await pumpEventQueue();
      controller.setsTooBig();
      await job.done;

      expect(
        '${(job.outcome! as Cancelled).stackTrace}',
        contains('setsTooBig'),
        reason: 'the rejection runs inside the change',
      );
    });

    test('a rule that says no later names the emit that broke it', () async {
      final controller = Cam();
      final job = controller.breaksItsOwnRule()..ignore();

      await job.done;

      expect(
        '${(job.outcome! as Cancelled).stackTrace}',
        contains('emitsTooBig'),
      );
    });

    test('without the trace of the change it names the checkpoint', () async {
      Solo.traceStateChanges = false;
      final controller = Cam();
      final job = controller.breaksItsOwnRule()..ignore();

      await job.done;

      final trace = '${(job.outcome! as Cancelled).stackTrace}';

      expect(trace, contains('readsTheState'));
      expect(trace, isNot(contains('emitsTooBig')));
    });

    test('a start rule names the queue, not the change', () async {
      final controller = Cam()..setsTooBig();
      final job = controller.refusedWhileBig()..ignore();

      await job.done;

      expect(
        '${(job.outcome! as Cancelled).stackTrace}',
        isNot(contains('setsTooBig')),
        reason: 'canStart is asked as the job leaves the queue',
      );
    });

    test('the zone of last resort is the one the job was created in', () async {
      final gate = Completer<void>();
      final caught = <Object>[];
      final controllerZone = <Object>[];
      final creationZone = <Object>[];
      final currentZone = <Object>[];
      late final Cam controller;
      late final Job<void> job;

      runZonedGuarded(
        () => controller = Cam(),
        (error, stackTrace) => controllerZone.add(error),
      );
      runZonedGuarded(
        () => job = controller.refusedAtCheckpoint(gate, caught),
        (error, stackTrace) => creationZone.add(error),
      );
      await runZonedGuarded(
        () async {
          await pumpEventQueue();
          controller.set(1);
          gate.complete();
          await job.done;
        },
        (error, stackTrace) => currentZone.add(error),
      );

      expect(creationZone, [isA<StateError>()]);
      expect(
        controllerZone,
        isEmpty,
        reason: 'the controller was created somewhere else',
      );
      expect(
        currentZone,
        isEmpty,
        reason: 'the state changed somewhere else again',
      );
    });
  });

  // --- Background work and logs -------------------------------------------

  group('background work and logs', () {
    test('the first attempt keeps the error away from the hooks', () async {
      final controller = Cam();
      final gate = Completer<void>();
      final zoneErrors = <Object>[];

      await runZonedGuarded(
        () async {
          await controller.bareUnawaited(gate).value;
          gate.complete();
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(controller.errors, isEmpty, reason: 'no hook is asked');
      expect(zoneErrors, [isA<StateError>()], reason: 'the zone takes it');
    });

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

    test('unattended work is refused whatever acts on the job', () async {
      final controller = Cam();
      final messages = <String>[];

      await controller.refusedFromUnattended(messages).value;
      await pumpEventQueue();

      expect(messages, [
        contains('cannot run a child inside unattended work'),
        contains('cannot run a child inside unattended work'),
        contains('cannot follow a stream inside unattended work'),
        contains('cannot run an uncancellable action inside unattended work'),
      ]);
    });

    test('a refusal nobody catches goes to the hooks, not the outcome',
        () async {
      final controller = Cam();
      final zoneErrors = <Object>[];
      late final Job<void> job;

      await runZonedGuarded(
        () async {
          job = controller.forksFromUnattended()..ignore();
          await job.done;
          await pumpEventQueue();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(controller.errors, [isA<StateError>()]);
      expect(zoneErrors, [isA<StateError>()], reason: 'nobody answered');
      expect(job.outcome, isA<Done<void>>(), reason: 'the job is not it');
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

    test('a message that is a callback is handed on uncalled', () async {
      final controller = Cam();
      var built = 0;

      await controller.logsLazily(() {
        built++;

        return 'zoom to 2';
      }).value;

      expect(built, 0, reason: 'nothing calls it on the way');

      final message = controller.logs.single! as String Function();

      expect(message(), 'zoom to 2');
      expect(built, 1, reason: 'the line is built where it is wanted');
    });
  });
}
