@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/page_code.dart';
import 'support/state_camera_stubs.dart' as camera;
import 'support/state_first_attempts.dart' as first;
import 'support/state_page.dart' as page;
import 'support/state_page_profile.dart' as profile;
import 'support/state_profile_stubs.dart' as stubs;

/// The sentinel of `doc/state.md`.
///
/// The code of the page stands verbatim in `test/support/state_*.dart`: the
/// first attempts in one file, the versions that work in two more, one for
/// the camera and one for the profile. The tests below run that code and pin
/// what the prose, the tables and the comments of the page say about it.
/// What the page states of the engine and its code does not show is pinned
/// on the controllers of this file. The recipe of `externalSetState` and the
/// closing around it have a file of their own,
/// `state_external_recipe_test.dart`.

/// A controller over any object. A job whose `W` is `String` leaves its
/// working type by emitting a number, and the rule the jobs here share
/// turns down the state `'blocked'`.
final class _Any extends Solo<Object> {
  final trace = <String>[];

  /// Whether `onChange` corrects `'preparing'` to `'working'`.
  bool corrects = false;

  int canStartAsked = 0;

  Job<String>? child;

  _Any([super.initialState = 'initial']);

  bool get listened => hasListeners;

  void reflect(Object state) => externalSetState(state);

  @override
  void onChange(SoloTransition<Object> transition) {
    if (corrects && transition.current == 'preparing') {
      externalSetState('working');
    }
  }

  @override
  void onFinish(Job<Object?> job) {
    if (job.key != null) {
      trace.add('onFinish of ${job.key} in $currentState');
    }
  }

  static bool _notBlocked(String state) => state != 'blocked';

  /// Leaves `W` with an emit, then takes one more [step] through the
  /// context.
  Job<String> afterLeavingW(
    FutureOr<void> Function(SoloContext<Object, String> ctx) step,
  ) =>
      run<String, String>((ctx) async {
        ctx.emit(42);
        await step(ctx);
        return 'went on';
      });

  /// Leaves `W` with its last step.
  Job<String> leavesWLast() => run<String, String>(
        canStart: (state) {
          canStartAsked++;
          return true;
        },
        (ctx) async {
          ctx.emit(42);
          return 'done';
        },
      );

  Job<int> readsAsInt() => run<Object, int>((ctx) async => ctx.stateAs<int>());

  /// Waits on a plain `await`, where nothing is checked.
  Job<String> plainAwait(Completer<void> gate) => run<String, String>(
        keepWhile: _notBlocked,
        (ctx) async {
          await gate.future;
          trace.add('walked on, cancelled: ${ctx.job.isCancelled}');
          return 'done';
        },
      );

  /// Comes back from an uncancellable section, then asks.
  Job<String> section(Completer<void> gate) => run<String, String>(
        keepWhile: _notBlocked,
        (ctx) async {
          await ctx.uncancellable(() => gate.future);
          trace.add('the section returned, cancelled: ${ctx.job.isCancelled}');
          ctx.check();
          trace.add('past the check');
          return 'done';
        },
      );

  /// Publishes `'preparing'`, which [onChange] may correct on the spot.
  Job<String> initialize() => run<String, String>(
        keepWhile: (state) => state != 'working',
        (ctx) async {
          try {
            ctx.emit('preparing');
          } on Cancelled catch (cancelled) {
            trace.add('emit threw $cancelled over $currentState');
            rethrow;
          }
          return 'went on';
        },
      );

  /// Ends its body at once and leaves a child and a cleanup behind.
  Job<String> endsEarly(Completer<void> child, Completer<void> cleanup) =>
      run<String, String>(
        keepWhile: _notBlocked,
        (ctx) async {
          ctx
            ..run(job<Object, void>((c) => child.future)).ignore()
            ..onDispose(() => cleanup.future);
          return 'body ended';
        },
      );

  /// A parent whose [child] ends its body at once and leaves a cleanup
  /// behind.
  Job<void> parentOfEnded(Completer<void> cleanup, Completer<void> gate) =>
      run<Object, void>((ctx) async {
        final ended = child = job<Object, String>((c) async {
          c.onDispose(() => cleanup.future);
          return 'child body ended';
        });
        ctx.run(ended).ignore();
        await ctx.wait(() => gate.future);
      });

  /// Watches the state until [gate] opens.
  Job<void> watch(Completer<void> gate) => run<String, void>(
        keepWhile: _notBlocked,
        (ctx) => ctx.wait(() => gate.future),
      );

  /// A parent whose child writes `'blocked'` while the parent waits on a
  /// plain `await`, where nothing is checked. The child is one of `each`:
  /// `run` would check the parent itself once the child's value arrived.
  Job<String> parentOfWriter(Completer<void> gate) => run<String, String>(
        keepWhile: _notBlocked,
        (ctx) async {
          ctx.each(Stream.value(1), (child, _) => child.emit('blocked'));
          await gate.future;
          return 'went on';
        },
      );

  /// Writes `'blocked'` itself and goes on without a checkpoint.
  Job<String> writesItself() => run<String, String>(
        keepWhile: _notBlocked,
        (ctx) async {
          ctx.emit('blocked');
          return 'went on';
        },
      );

  /// The `catch` of the first attempt, saying what its `emit` did.
  Job<void> emitsInCatch(Completer<void> gate) => run<Object, void>(
        (ctx) async {
          try {
            await ctx.wait(() => gate.future);
          } on Object {
            trace.add('the catch ran');
            try {
              ctx.emit('written by the catch');
            } on Cancelled catch (cancelled) {
              trace.add('emit threw $cancelled');
            }
            rethrow;
          }
        },
      );

  /// Fails with a child still running and a cleanup registered.
  Job<void> failsLeavingWork() => run<Object, void>(
        key: 'first',
        onError: (state, error, stackTrace) {
          trace.add('onError: state $state, $error, ${current?.outcome}');
          return 'corrected';
        },
        (ctx) async {
          ctx
            ..each(
              Stream<int>.fromFuture(
                Future<int>.delayed(const Duration(milliseconds: 10), () => 1),
              ),
              (child, event) => trace.add('child'),
            )
            ..onDispose(() => trace.add('cleanup'));
          trace.add('body');
          throw StateError('boom');
        },
      );

  Job<void> cancelledWithHandler(Completer<void> gate) => run<Object, void>(
        onCancel: (state, cancelled) {
          trace.add('onCancel: state $state, $cancelled');
          return 'corrected';
        },
        (ctx) => ctx.wait(() => gate.future),
      );

  Job<void> next() => run<Object, void>(
        key: 'next',
        (ctx) async => trace.add('the next job in $currentState'),
      );
}

/// [_Any] with a report of its own for a listener that throws.
final class _Reporting extends _Any {
  final reported = <Object>[];

  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      reported.add(error);
}

/// A widget-like listener: a method of its own, torn off twice.
final class _Screen {
  final _Any controller;
  final heard = <Object>[];

  _Screen(this.controller);

  void onChange() => heard.add(controller.currentState);
}

/// The controller of the order diagram under "Observing state".
///
/// One listener, one running job whose `keepWhile` records what it was
/// asked about, and a write made from inside the listener.
final class _Order extends Solo<String> {
  final trace = <String>[];

  /// What the job's `keepWhile` answered, in order, next to the state it
  /// was asked about.
  final answers = <String>[];

  /// The job's rule. The diagram's job keeps on every state.
  final bool Function(_Order order, String state) keep;

  /// Whether the listener sets [blocked] once it hears C.
  final bool blockOnC;

  /// Whether the job has an `onCancel` that corrects the state to
  /// `corrected`.
  final bool corrects;

  /// A field of the controller, not of the state.
  bool blocked = false;

  var _nested = false;
  var _inNestedWrite = false;

  _Order({this.keep = _keepAll, this.blockOnC = false, this.corrects = false})
      : super('A') {
    addListener(() {
      final seen = currentState;
      trace.add('    listeners of $seen');
      if (!_nested && seen == 'B') {
        _nested = true;
        trace.add('        externalSetState(C)');
        // The flag is the test's own bookkeeping, and it is what turns
        // the sequence below into the diagram: it says which of the two
        // re-evaluations ran inside the nested write.
        _inNestedWrite = true;
        set('C');
        _inNestedWrite = false;
        trace.add('        next line of the listener');
      }
      if (blockOnC && seen == 'C') blocked = true;
    });
  }

  static bool _keepAll(_Order order, String state) => true;

  void set(String next) => externalSetState(next);

  Job<void> watch() => run<String, void>(
        keepWhile: (state) {
          final indent = _inNestedWrite ? ' ' * 12 : ' ' * 4;
          trace.add('${indent}rules, against $state');
          final kept = keep(this, state);
          answers.add('$state: ${kept ? 'keep' : 'reject'}');
          return kept;
        },
        onCancel: corrects ? (state, cancelled) => 'corrected' : null,
        (ctx) => ctx.wait(() => Completer<void>().future),
      );
}

/// The page's `Logged` over numbers, with a way to write and a job to
/// watch.
final class _LoggedNumbers extends page.Logged<int> {
  _LoggedNumbers(void Function(String line) write) : super(0, write);

  void set(int value) => externalSetState(value);

  Job<void> watch() => run<int, void>(
        keepWhile: (state) => state < 5,
        (ctx) => ctx.wait(() => Completer<void>().future),
      );
}

/// A delivery that lets its failure out, against the rule of the page.
final class _Leaky extends Solo<int> {
  final trace = <String>[];

  /// Whether `publish` throws.
  bool bomb = true;

  /// Whether `onChange` answers the state `1` with a write of `9`.
  bool writesFromHook = false;

  _Leaky() : super(0);

  void set(int value) => externalSetState(value);

  @override
  void publish(int previous, int current) {
    super.publish(previous, current);
    if (bomb) throw StateError('delivery boom on $current');
  }

  @override
  void onChange(SoloTransition<int> transition) {
    if (writesFromHook && transition.current == 1) {
      externalSetState(9);
      trace.add('the write of the hook returned');
    }
  }

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      trace.add('onError: $error');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      trace.add('onUnanswered: $error');

  Job<void> watch() => run<int, void>(
        keepWhile: (state) => state < 5,
        (ctx) => ctx.wait(() => Completer<void>().future),
      );

  Job<String> emitter() => run<int, String>((ctx) async {
        try {
          ctx.emit(3);
          return 'emit returned';
        } on Object catch (error) {
          return 'emit threw: $error';
        }
      });

  Job<void> corrected(Completer<void> gate) => run<int, void>(
        onCancel: (state, cancelled) => 4,
        (ctx) => ctx.wait(() => gate.future),
      );
}

/// A delivery that gives up on the states named in [bombAt], and writes
/// [writeFromFirst] from inside the first publish it is asked for.
///
/// Two states written from inside one publish are the shape the
/// publication queue is there for: they join it instead of being published
/// ahead of the change their writer is nested in.
final class _Delivery extends Solo<String> {
  /// Every state this delivery got all the way through.
  final seen = <String>[];

  Set<String> bombAt = const {};
  List<String> writeFromFirst = const [];

  _Delivery() : super('a');

  void set(String next) => externalSetState(next);

  @override
  void publish(String previous, String current) {
    super.publish(previous, current);
    final more = writeFromFirst;
    writeFromFirst = const [];
    more.forEach(externalSetState);
    if (bombAt.contains(current)) {
      throw StateError('delivery boom on $current');
    }
    seen.add(current);
  }
}

/// The jobs of "Handler eligibility and errors". A state that starts with
/// `'bad'` is one the rule turns down.
final class _Eligible extends Solo<String> {
  final trace = <String>[];

  /// Whether the rule throws instead of answering.
  bool ruleThrows = false;

  /// Whether the body of [parent] ends at once.
  bool parentEndsEarly = false;

  /// The child of [writingParent] and of [writingSibling] that has the
  /// rule and the handler.
  Job<void>? watcher;

  _Eligible() : super('ok');

  void reflect(String state) => externalSetState(state);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      trace.add('onError of ${job.key}: $error');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      trace.add('onUnanswered of ${job.key}: $error');

  bool _keep(String state) {
    if (ruleThrows) throw StateError('rule boom');
    return !state.startsWith('bad');
  }

  /// A rule and both handlers. The body waits for [gate], then the job
  /// waits for [child] and for [cleanup], where they are given.
  Job<String> guarded(
    Completer<void> gate, {
    Completer<void>? child,
    Completer<void>? cleanup,
  }) =>
      run<String, String>(
        key: 'guarded',
        keepWhile: _keep,
        onError: (state, error, stackTrace) => 'corrected by onError',
        onCancel: (state, cancelled) => 'corrected by onCancel',
        (ctx) async {
          if (child != null) {
            ctx.run(job<String, void>((c) => child.future)).ignore();
          }
          if (cleanup != null) {
            ctx.onDispose(() async {
              await cleanup.future;
              trace.add('cleanup ran');
            });
          }
          await ctx.wait(() => gate.future);
          return 'done';
        },
      );

  /// A parent with a rule; its child has a handler and no rule.
  Job<void> parent(Completer<void> gate, {bool handlers = false}) =>
      run<String, void>(
        key: 'parent',
        keepWhile: _keep,
        onCancel: handlers ? (state, cancelled) => 'parent corrected' : null,
        (ctx) async {
          final child = job<String, void>(
            key: 'child',
            onCancel: (state, cancelled) => 'child corrected',
            (c) => c.wait(() => gate.future),
          );
          ctx.run(child).ignore();
          if (parentEndsEarly) return;
          await ctx.wait(() => gate.future);
        },
      );

  /// A parent with a rule and a handler, whose child writes a state the
  /// rule turns down.
  Job<void> parentOfWriter() => run<String, void>(
        key: 'parent',
        keepWhile: _keep,
        onCancel: (state, cancelled) => 'parent corrected',
        (ctx) async {
          await ctx.run(
            job<String, void>((c) async => c.emit('bad from the child')),
          );
          await ctx.wait(() => Completer<void>().future);
        },
      );

  /// A parent that writes a state the rule of its child turns down; the
  /// child has a handler.
  Job<void> writingParent() => run<String, void>(
        key: 'parent',
        (ctx) async {
          final watcher = _watcher();
          final watching = ctx.run(watcher)..ignore();
          await Future<void>.delayed(const Duration(milliseconds: 1));
          ctx.emit('bad from the parent');
          await watching.then<void>((_) {}, onError: (Object _) {});
        },
      );

  /// Two children: one writes a state the rule of the other turns down.
  Job<void> writingSibling() => run<String, void>(
        key: 'parent',
        (ctx) async {
          final watching = ctx.run(_watcher())..ignore();
          await ctx.run(
            job<String, void>((c) async => c.emit('bad from the sibling')),
          );
          await watching.then<void>((_) {}, onError: (Object _) {});
        },
      );

  Job<void> _watcher() => watcher = job<String, void>(
        key: 'watcher',
        keepWhile: _keep,
        onCancel: (state, cancelled) => 'watcher corrected',
        (c) => c.wait(() => Completer<void>().future),
      );

  /// Writes a state its own rule turns down, waits on a plain `await`,
  /// then reads the state if [thenReads] and fails otherwise.
  Job<void> ownEmit(Completer<void> gate, {bool thenReads = false}) =>
      run<String, void>(
        key: 'own',
        keepWhile: _keep,
        onError: (state, error, stackTrace) => 'corrected by onError',
        onCancel: (state, cancelled) => 'corrected by onCancel',
        (ctx) async {
          ctx.emit('bad from the job itself');
          await gate.future;
          if (thenReads) ctx.state;
          throw StateError('boom');
        },
      );

  Job<void> stateAsMismatch() => run<String, void>(
        key: 'stateAs',
        onCancel: (state, cancelled) => 'corrected by onCancel',
        (ctx) async {
          ctx
            ..emit('loading')
            ..stateAs<Never>();
        },
      );

  Job<void> handlerThrows(Completer<void> gate) => run<String, void>(
        key: 'thrower',
        onCancel: (state, cancelled) => throw StateError('handler boom'),
        (ctx) => ctx.wait(() => gate.future),
      );

  Job<void> next() => run<String, void>(
        key: 'next',
        (ctx) async => trace.add('the next job ran in $currentState'),
      );

  Job<String> droppable(Completer<void> gate) => run<String, String>(
        key: 'droppable',
        policy: Policy.droppable,
        onError: (state, error, stackTrace) => 'corrected by onError',
        onCancel: (state, cancelled) => 'corrected by onCancel',
        (ctx) async {
          await ctx.wait(() => gate.future);
          return 'done';
        },
      );

  Job<String> refused() => run<String, String>(
        key: 'refused',
        canStart: (state) => false,
        onCancel: (state, cancelled) => 'corrected by onCancel',
        (ctx) async => 'done',
      );

  /// A handler that writes a fact itself before it returns its result.
  Job<void> writesFromHandler(Completer<void> gate, {required bool rule}) =>
      run<String, void>(
        key: 'writer',
        keepWhile: rule ? _keep : null,
        onCancel: (state, cancelled) {
          externalSetState('bad fact');
          return 'corrected from $state';
        },
        (ctx) => ctx.wait(() => gate.future),
      );
}

String _page() => File('doc/state.md').readAsStringSync();

/// The outcome of [job], with `started` where it is a cancellation.
String _ended(Job<Object?> job) => switch (job.outcome) {
      final Cancelled cancelled => '$cancelled, started: ${cancelled.started}',
      final outcome => '$outcome',
    };

/// Runs [body] under fake time in a zone of its own and returns what
/// reached that zone uncaught. Expectations go after the call: inside the
/// zone a failed one would land in the handler.
List<String> _zone(void Function(FakeAsync async) body) {
  final errors = <String>[];
  runZonedGuarded(
    () => fakeAsync(body),
    (error, stackTrace) => errors.add('$error'),
  );
  return errors;
}

void main() {
  setUp(() => camera.stage = camera.Stage());

  group('State and rules', () {
    test('the first attempt stores on after the pause, and holds the close',
        () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = first.Camera(device);
        final job = cam.record();
        async.flushMicrotasks();
        device.frame(1);
        async.flushMicrotasks();
        cam.reflect(const camera.Ready(paused: true));
        device
          ..frame(2)
          ..frame(3);
        async.flushMicrotasks();

        expect(
          camera.stage.trace,
          [
            'store 1 begins',
            'store 1 ends',
            'store 2 begins',
            'store 2 ends',
            'store 3 begins',
            'store 3 ends',
          ],
          reason: 'the check does not come back',
        );
        expect(job.isCancelled, isFalse);
        expect(job.isFinished, isFalse, reason: 'and the job does not end');

        // `await for` is no checkpoint: the body never hears the
        // cancellation `close` sends it.
        var closed = false;
        cam.close().then((_) => closed = true);
        async.flushMicrotasks();
        expect(job.isCancelled, isTrue);
        expect(closed, isFalse, reason: 'close waits for a body that goes on');
        device.frame(4);
        async.flushMicrotasks();
        expect(camera.stage.trace.last, 'store 4 ends');

        device.endFrames();
        async.flushMicrotasks();
        expect(closed, isTrue, reason: 'only the stream ending lets it go');
        expect(_ended(job), 'Cancelled(closed), started: true');
        device.dispose();
      });
    });

    test('the rules stop the recording when the device reports the pause', () {
      fakeAsync((async) {
        camera.stage.storeTake = 20;
        final device = camera.Device();
        final cam = page.Camera(device);
        final job = cam.record();
        async.flushMicrotasks();
        device.frame(1);
        async.elapse(const Duration(milliseconds: 30));
        device.frame(2);
        async.elapse(const Duration(milliseconds: 5));

        cam.reflect(const camera.Ready(paused: true));
        expect(job.isCancelled, isTrue, reason: 'cancelled at the update');
        device.frame(3);
        async.flushTimers();

        expect(
          camera.stage.trace,
          ['store 1 begins', 'store 1 ends', 'store 2 begins', 'store 2 ends'],
          reason: 'the frame being stored is waited out, the next is not taken',
        );
        expect(_ended(job), 'Cancelled(rules: keepWhile), started: true');
        expect((job.outcome! as Cancelled).reason, isA<RulesCancelReason>());
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('a pause written as a job waits for the recording to end', () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = page.Camera(device);
        final job = cam.record();
        async.flushMicrotasks();
        final pause = cam.pauseAsJob();
        device.frame(1);
        async.elapse(const Duration(minutes: 10));

        expect((pause as SoloJob<void>).isQueued, isTrue);
        expect(cam.currentState.toString(), contains('paused: false'));
        expect(job.isFinished, isFalse, reason: 'the rule was never asked');

        device.endFrames();
        async.flushMicrotasks();
        expect('${job.outcome}', 'Done(null)');
        expect('${pause.outcome}', 'Done(null)');
        expect(cam.currentState.toString(), contains('paused: true'));
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('an update a child makes is asked of the parent rule as well', () {
      fakeAsync((async) {
        final byChild = _Any();
        final byBody = _Any();
        final gate = Completer<void>();
        final parent = byChild.parentOfWriter(gate);
        final own = byBody.writesItself();
        async.flushTimers();

        expect(
          parent.isCancelled,
          isTrue,
          reason: 'at the emit of the child, with no checkpoint of its own',
        );
        gate.complete();
        async.flushMicrotasks();
        expect(_ended(parent), 'Cancelled(rules: keepWhile), started: true');
        expect(
          '${own.outcome}',
          'Done(went on)',
          reason: "the job's own emit is not asked of its rule",
        );
        expect(byBody.currentState, 'blocked');
        byChild.close().ignore();
        byBody.close().ignore();
        async.flushTimers();
      });
    });

    test('a refused start ends the job with started: false, and for good', () {
      fakeAsync((async) {
        final refusals = {
          const camera.Off(): 'Cancelled(rules: is not Ready), started: false',
          const camera.Ready(free: 0):
              'Cancelled(rules: canStart), started: false',
          const camera.Ready(paused: true):
              'Cancelled(rules: keepWhile), started: false',
        };
        for (final MapEntry(key: state, value: outcome) in refusals.entries) {
          final device = camera.Device();
          final cam = page.Camera(device)..reflect(state);
          final job = cam.record();
          async.flushMicrotasks();
          expect(_ended(job), outcome, reason: '$state');
          expect((job.outcome! as Cancelled).reason, isA<RulesCancelReason>());
          expect((job as SoloJob<void>).isQueued, isFalse);

          // The rules reject the work; they do not keep it for a state
          // that suits it.
          cam.reflect(const camera.Ready());
          device.frame(1);
          async.flushMicrotasks();
          expect(_ended(job), outcome);
          expect(camera.stage.trace, isEmpty);
          cam.close().ignore();
          device.dispose();
          async.flushTimers();
        }
      });
    });

    test('canStart is asked once; W and keepWhile on every other update', () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = page.Camera(device);
        final job = cam.record();
        async.flushMicrotasks();

        cam.reflect(const camera.Ready(free: 0));
        async.flushMicrotasks();
        expect(job.isCancelled, isFalse, reason: 'canStart is not asked again');

        cam.reflect(const camera.Off());
        async.flushMicrotasks();
        expect(_ended(job), 'Cancelled(rules: is not Ready), started: true');
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('with the rules, close ends the recording while frames go on', () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = page.Camera(device);
        final job = cam.record();
        async.flushMicrotasks();
        device.frame(1);
        async.flushMicrotasks();

        var closed = false;
        cam.close().then((_) => closed = true);
        async.flushMicrotasks();
        expect(closed, isTrue);
        expect(_ended(job), 'Cancelled(closed), started: true');
        device.dispose();
        async.flushTimers();
      });
    });
  });

  group('Reading and updating state', () {
    test('zoomIn reads the state and writes the next one', () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = page.Camera(device)
          ..reflect(const camera.Ready(free: 3, zoom: 4));
        final job = cam.zoomIn();
        async.flushMicrotasks();
        expect('${job.outcome}', 'Done(null)');
        expect(
          '${cam.currentState}',
          'Ready(free: 3, paused: false, zoom: 5)',
        );
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('after an emit outside W a read or a wait ends the job', () {
      var started = 0;
      Future<void> action() async => started++;
      final giveUp =
          <String, FutureOr<void> Function(SoloContext<Object, String>)>{
        'state': (ctx) => ctx.state,
        'stateAs': (ctx) => ctx.stateAs<String>(),
        'check': (ctx) => ctx.check(),
        'wait': (ctx) => ctx.wait(action),
        'join': (ctx) => ctx.join(action),
        'uncancellable': (ctx) => ctx.uncancellable(action),
        'pause': (ctx) => ctx.pause(),
      };
      final goOn =
          <String, FutureOr<void> Function(SoloContext<Object, String>)>{
        'emit': (ctx) => ctx.emit(43),
        'log': (ctx) => ctx.log('a line'),
        'onDispose': (ctx) => ctx.onDispose(() {}),
        'a plain await': (ctx) => Future<void>.delayed(Duration.zero),
      };
      fakeAsync((async) {
        for (final MapEntry(key: member, value: step) in giveUp.entries) {
          final any = _Any();
          final job = any.afterLeavingW(step);
          async.flushTimers();
          expect(
            _ended(job),
            'Cancelled(rules: is not String), started: true',
            reason: member,
          );
          any.close().ignore();
        }
        expect(started, 0, reason: 'the job ends before the action starts');

        for (final MapEntry(key: member, value: step) in goOn.entries) {
          final any = _Any();
          final job = any.afterLeavingW(step);
          async.flushTimers();
          expect('${job.outcome}', 'Done(went on)', reason: member);
          any.close().ignore();
        }
        async.flushTimers();
      });
    });

    test('an emit outside W as the last step ends Done, canStart not asked',
        () {
      fakeAsync((async) {
        final any = _Any();
        final job = any.leavesWLast();
        async.flushTimers();
        expect('${job.outcome}', 'Done(done)');
        expect(any.currentState, 42);
        expect(any.canStartAsked, 1);
        any.close().ignore();
        async.flushTimers();
      });
    });

    test('a stateAs mismatch cancels the job by the rules', () {
      fakeAsync((async) {
        final any = _Any();
        final job = any.readsAsInt();
        async.flushTimers();
        expect(_ended(job), 'Cancelled(rules: is not int), started: true');

        final number = _Any(7);
        final read = number.readsAsInt();
        async.flushTimers();
        expect('${read.outcome}', 'Done(7)');
        any.close().ignore();
        number.close().ignore();
        async.flushTimers();
      });
    });

    test('a plain await checks nothing: the cancelled job walks on', () {
      fakeAsync((async) {
        final any = _Any();
        final gate = Completer<void>();
        final job = any.plainAwait(gate);
        async.flushMicrotasks();

        any.reflect('blocked');
        expect(job.isCancelled, isTrue, reason: 'the rules cancel at once');
        async.elapse(const Duration(hours: 1));
        expect(job.isFinished, isFalse, reason: 'the body hears nothing');

        gate.complete();
        async.flushMicrotasks();
        expect(any.trace, ['walked on, cancelled: true']);
        expect(_ended(job), 'Cancelled(rules: keepWhile), started: true');
        any.close().ignore();
        async.flushTimers();
      });
    });

    test('the return from uncancellable checks nothing, and check() does', () {
      fakeAsync((async) {
        final any = _Any();
        final gate = Completer<void>();
        final job = any.section(gate);
        async.flushMicrotasks();

        any.reflect('blocked');
        expect(job.isCancelled, isTrue, reason: 'the rules pass the section');
        gate.complete();
        async.flushMicrotasks();

        expect(any.trace, ['the section returned, cancelled: true']);
        expect(_ended(job), 'Cancelled(rules: keepWhile), started: true');
        any.close().ignore();
        async.flushTimers();
      });
    });

    test('a hook that corrects the state cancels the job inside its emit', () {
      fakeAsync((async) {
        final any = _Any()..corrects = true;
        final job = any.initialize();
        async.flushTimers();

        expect(
          any.trace,
          ['emit threw Cancelled(rules: keepWhile) over working'],
          reason: 'the emit wrote, and then threw the cancellation',
        );
        expect(_ended(job), 'Cancelled(rules: keepWhile), started: true');

        final plain = _Any();
        final undisturbed = plain.initialize();
        async.flushTimers();
        expect('${undisturbed.outcome}', 'Done(went on)');
        any.close().ignore();
        plain.close().ignore();
        async.flushTimers();
      });
    });

    test('once the body has ended the rules cancel nothing', () {
      fakeAsync((async) {
        final any = _Any();
        final child = Completer<void>();
        final cleanup = Completer<void>();
        final job = any.endsEarly(child, cleanup);
        async.flushMicrotasks();

        any.reflect('blocked');
        async.flushMicrotasks();
        expect(job.isCancelled, isFalse, reason: 'while it waits for a child');
        child.complete();
        async.flushMicrotasks();
        any.reflect(42);
        expect(job.isCancelled, isFalse, reason: 'and during its cleanup');
        cleanup.complete();
        async.flushMicrotasks();

        expect('${job.outcome}', 'Done(body ended)');
        any.close().ignore();
        async.flushTimers();
      });
    });

    test('cancel, close and the parent still reach a job whose body ended', () {
      fakeAsync((async) {
        for (final what in ['cancel', 'close']) {
          final any = _Any();
          final child = Completer<void>();
          final cleanup = Completer<void>();
          final job = any.endsEarly(child, cleanup);
          async.flushMicrotasks();
          if (what == 'cancel') {
            job.cancel().ignore();
          } else {
            any.close().ignore();
          }
          child.complete();
          cleanup.complete();
          async.flushMicrotasks();
          expect(
            '${job.outcome}',
            what == 'cancel' ? 'Cancelled(manual)' : 'Cancelled(closed)',
          );
          any.close().ignore();
        }

        final any = _Any();
        final cleanup = Completer<void>();
        final parent = any.parentOfEnded(cleanup, Completer<void>());
        async.flushMicrotasks();
        parent.cancel().ignore();
        async.flushMicrotasks();
        cleanup.complete();
        async.flushMicrotasks();
        final outcome = any.child!.outcome;
        expect(outcome, isA<Cancelled>());
        expect((outcome! as Cancelled).reason, isA<ParentCancelReason>());
        any.close().ignore();
        async.flushTimers();
      });
    });
  });

  group('Observing state', () {
    test('the block prints the read, each change at once, each event later',
        () {
      final lines = <String>[];
      runZoned(
        () => fakeAsync((async) {
          final device = camera.Device();
          final cam = page.Camera(device)..reflect(const camera.Ready(zoom: 2));
          async.flushMicrotasks();

          final subscription = page.observing(cam);
          async.flushMicrotasks();
          lines.add('subscribed, nothing replayed');

          cam.reflect(const camera.Ready(zoom: 3));
          lines.add('the next line of the writer');
          async.flushMicrotasks();

          cam.reflect(const camera.Ready(zoom: 3));
          lines.add('the next line of the writer');
          cam.reflect(const camera.Ready(zoom: 4));
          lines.add('the next line of the writer');
          async.flushMicrotasks();

          subscription.cancel().ignore();
          cam.close().ignore();
          device.dispose();
          async.flushTimers();
        }),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => lines.add(line),
        ),
      );

      expect(lines, [
        'Ready(free: 8, paused: false, zoom: 2)',
        'subscribed, nothing replayed',
        'Ready(free: 8, paused: false, zoom: 3)',
        'the next line of the writer',
        'Ready(free: 8, paused: false, zoom: 3)',
        // An equal state is a change and an event all the same, and both
        // events come on a microtask, in order.
        'Ready(free: 8, paused: false, zoom: 3)',
        'the next line of the writer',
        'Ready(free: 8, paused: false, zoom: 4)',
        'the next line of the writer',
        'Ready(free: 8, paused: false, zoom: 3)',
        'Ready(free: 8, paused: false, zoom: 4)',
      ]);
    });

    test('a stream event may be older than currentState when it arrives', () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = page.Camera(device);
        final seen = <String>[];
        cam.stream.listen(
          (state) => seen.add(
            'event zoom ${(state as camera.Ready).zoom}, '
            'currentState zoom ${(cam.currentState as camera.Ready).zoom}',
          ),
        );
        cam
          ..reflect(const camera.Ready(zoom: 2))
          ..reflect(const camera.Ready(zoom: 3));
        async.flushMicrotasks();
        expect(seen, [
          'event zoom 2, currentState zoom 3',
          'event zoom 3, currentState zoom 3',
        ]);
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('a plain Solo has listeners and no stream; nobody has a state', () {
      final any = _Any();
      final cam = page.Camera(camera.Device());
      expect(any, isNot(isA<SoloStream<Object>>()));
      expect(() => (any as dynamic).stream, throwsNoSuchMethodError);
      expect(cam, isA<SoloStream<camera.CameraState>>());
      expect(() => (any as dynamic).state, throwsNoSuchMethodError);
      expect(() => (cam as dynamic).state, throwsNoSuchMethodError);
      any.addListener(() {});
      expect(any.listened, isTrue);
      any.close().ignore();
      cam.close().ignore();
    });

    test('listeners: in order, inside the change, before the rules', () {
      fakeAsync((async) {
        final any = _Any();
        final job = any.watch(Completer<void>());
        async.flushMicrotasks();
        final trace = <String>[];
        any
          ..addListener(
            () => trace.add(
              'first reads ${any.currentState}, '
              'job cancelled: ${job.isCancelled}',
            ),
          )
          ..addListener(() => trace.add('second reads ${any.currentState}'))
          ..reflect('blocked');
        trace.add('the next line, job cancelled: ${job.isCancelled}');

        expect(trace, [
          'first reads blocked, job cancelled: false',
          'second reads blocked',
          'the next line, job cancelled: true',
        ]);
        any.close().ignore();
        async.flushTimers();
      });
    });

    test('the diagram of the page is the order a nested change gets', () {
      fakeAsync((async) {
        final order = _Order()..watch();
        async.flushMicrotasks();
        order.trace.clear();

        order
          ..trace.add('externalSetState(B)')
          ..set('B')
          ..trace.add('next line of the writer');

        // The diagram under "Observing state", line for line, its `//`
        // annotations aside.
        final diagram = RegExp(r'```text\n(.*?)\n```', dotAll: true)
            .firstMatch(_page())!
            .group(1)!
            .split('\n')
            .map((line) => line.split('//').first.trimRight())
            .toList();
        expect(diagram, hasLength(8));
        expect(order.trace, diagram);
        order.close().ignore();
        async.flushTimers();
      });
    });

    test('a rule of the state alone is not asked again once it has refused',
        () {
      fakeAsync((async) {
        final order = _Order(keep: (_, state) => state != 'C');
        final job = order.watch();
        async.flushMicrotasks();
        order.answers.clear();

        order.set('B');
        async.flushMicrotasks();

        expect(order.answers, ['C: reject']);
        expect('${job.outcome}', 'Cancelled(rules: keepWhile)');
        order.close().ignore();
        async.flushTimers();
      });
    });

    test('only the second question hears what the listeners of C set', () {
      fakeAsync((async) {
        final order =
            _Order(keep: (order, _) => !order.blocked, blockOnC: true);
        final job = order.watch();
        async.flushMicrotasks();
        order.answers.clear();

        order.set('B');
        async.flushMicrotasks();

        expect(order.answers, ['C: keep', 'C: reject']);
        expect('${job.outcome}', 'Cancelled(rules: keepWhile)');
        order.close().ignore();
        async.flushTimers();
      });
    });

    test('a job with handlers is asked about B, and a refused B disables them',
        () {
      fakeAsync((async) {
        final order = _Order(keep: (_, state) => state != 'B', corrects: true);
        final job = order.watch();
        async.flushMicrotasks();
        order.answers.clear();

        order.set('B');

        expect(
          order.answers.first,
          'B: reject',
          reason: 'asked about B at the write itself, before any listener',
        );
        expect(order.currentState, 'C');
        expect(job.isCancelled, isFalse, reason: 'the question cancels nobody');

        job.cancel().ignore();
        async.flushMicrotasks();
        expect(
          order.currentState,
          'C',
          reason: 'the handler no longer corrects, though B was gone at once',
        );
        order.close().ignore();
        async.flushTimers();
      });
    });

    test('without B the same handler corrects the state', () {
      fakeAsync((async) {
        final order = _Order(keep: (_, state) => state != 'B', corrects: true);
        final job = order.watch();
        async.flushMicrotasks();

        order.set('C');
        job.cancel().ignore();
        async.flushMicrotasks();

        expect(order.currentState, 'corrected');
        order.close().ignore();
        async.flushTimers();
      });
    });

    test('removeListener takes a method torn off again', () {
      final any = _Any();
      final screen = _Screen(any);
      expect(identical(screen.onChange, screen.onChange), isFalse);
      any
        ..addListener(screen.onChange)
        ..reflect('one')
        ..removeListener(screen.onChange)
        ..reflect('two');
      expect(screen.heard, ['one']);
      expect(any.listened, isFalse);
      any.close().ignore();
    });

    test('a listener that throws stops neither the others nor the rules', () {
      final trace = <String>[];
      late Job<void> job;
      final zone = _zone((async) {
        final any = _Any();
        job = any.watch(Completer<void>());
        async.flushMicrotasks();
        any
          ..addListener(() => throw StateError('listener boom'))
          ..addListener(() => trace.add('the listener after it ran'))
          ..reflect('blocked');
        trace.add('the write returned');
        async.flushMicrotasks();
        any.close().ignore();
        async.flushTimers();
      });

      expect(trace, ['the listener after it ran', 'the write returned']);
      expect('${job.outcome}', 'Cancelled(rules: keepWhile)');
      expect(zone, ['Bad state: listener boom']);
    });

    test('onListenerError of a subclass takes the error from the zone', () {
      late _Reporting reporting;
      final zone = _zone((async) {
        reporting = _Reporting()
          ..addListener(() => throw StateError('listener boom'))
          ..reflect('next');
        reporting.close().ignore();
        async.flushTimers();
      });

      expect(reporting.reported.single, isA<StateError>());
      expect(zone, isEmpty);
    });

    test('the listeners go when closing finishes, and so does the write', () {
      fakeAsync((async) {
        final any = _Any();
        final job = any.cancelledWithHandler(Completer<void>());
        async.flushMicrotasks();
        final heard = <String>[];
        any.addListener(
          () => heard.add('${any.currentState}, finished: ${any.isFinished}'),
        );

        any.close().ignore();
        expect(any.listened, isTrue, reason: 'close() was only called');
        any.reflect('written while closing');
        async.flushMicrotasks();

        expect(heard, [
          'written while closing, finished: false',
          'corrected, finished: false',
        ]);
        expect(job.outcome, isA<Cancelled>());
        expect(any.isFinished, isTrue);
        expect(any.listened, isFalse);

        any.addListener(() => heard.add('late'));
        expect(any.listened, isFalse, reason: 'neither registered nor kept');
        expect(() => any.reflect('after the end'), throwsStateError);
        expect(any.currentState, 'corrected');
        expect(heard, hasLength(2));
        async.flushTimers();
      });
    });
  });

  group('A delivery of your own', () {
    test('Logged writes each change after the listeners heard it', () {
      fakeAsync((async) {
        final lines = <String>[];
        final logged = _LoggedNumbers(lines.add);
        logged
          ..addListener(
            () => lines.add('listener reads ${logged.currentState}'),
          )
          ..set(1)
          ..set(2);
        expect(lines, [
          'listener reads 1',
          '0 -> 1',
          'listener reads 2',
          '1 -> 2',
        ]);
        logged.close().ignore();
        async.flushTimers();
      });
    });

    test('a write that fails goes to the zone, and the rules still run', () {
      late Job<void> job;
      var returned = false;
      final zone = _zone((async) {
        final logged = _LoggedNumbers((line) => throw StateError('disk full'));
        job = logged.watch();
        async.flushMicrotasks();
        logged.set(9);
        returned = true;
        async.flushMicrotasks();
        logged.close().ignore();
        async.flushTimers();
      });

      expect(returned, isTrue, reason: 'nothing left publish');
      expect('${job.outcome}', 'Cancelled(rules: keepWhile)');
      expect(zone, ['Bad state: disk full']);
    });

    test('publish is protected in the engine and in the override of the page',
        () {
      // Annotations are the analyzer's to read, so the sources are read here.
      expect(
        File('lib/src/solo.dart').readAsStringSync(),
        contains(
          RegExp(
            r'@protected\s+@mustCallSuper\s+'
            r'void publish\(S previous, S current\)',
          ),
        ),
      );
      // The check of the code would not miss the line: a piece of the page
      // that lost it is still a run of lines of the support file.
      expect(
        _page(),
        contains('  @protected\n  @override\n  void publish(S previous, '),
      );
    });

    test('called from outside, publish delivers a state nobody wrote', () {
      fakeAsync((async) {
        final lines = <String>[];
        final logged = _LoggedNumbers(lines.add);
        var heard = 0;
        logged
          ..addListener(() => heard++)
          // What `@protected` on the override keeps code outside the class
          // from writing.
          // ignore: invalid_use_of_protected_member
          ..publish(0, 99);

        expect(heard, 1, reason: 'the listeners are called');
        expect(lines, ['0 -> 99'], reason: 'and the delivery runs');
        expect(logged.currentState, 0, reason: 'while the state stays');
        logged.close().ignore();
        async.flushTimers();
      });
    });

    test('a failure let out of publish costs a job its cancellation', () {
      fakeAsync((async) {
        final leaky = _Leaky();
        final job = leaky.watch();
        async.flushMicrotasks();

        expect(
          () => leaky.set(9),
          throwsA(
            isA<StateError>()
                .having((e) => e.message, 'message', 'delivery boom on 9'),
          ),
          reason: 'out of externalSetState, to whoever called it',
        );
        async.flushMicrotasks();
        expect(leaky.currentState, 9);
        expect(job.isCancelled, isFalse, reason: 'the rules were not asked');

        // The same state published by a delivery that holds.
        leaky
          ..bomb = false
          ..set(9);
        async.flushMicrotasks();
        expect('${job.outcome}', 'Cancelled(rules: keepWhile)');
        leaky.close().ignore();
        async.flushTimers();
      });
    });

    test('a failure let out of publish goes into the body that called emit',
        () {
      fakeAsync((async) {
        final leaky = _Leaky();
        final job = leaky.emitter();
        async.flushTimers();
        expect(
          '${job.outcome}',
          'Done(emit threw: Bad state: delivery boom on 3)',
        );
        expect(leaky.currentState, 3);
        leaky.close().ignore();
        async.flushTimers();
      });
    });

    test('a failure let out of publish reaches the zone from a hook', () {
      late _Leaky leaky;
      var returned = false;
      final zone = _zone((async) {
        leaky = _Leaky()
          ..writesFromHook = true
          ..set(1);
        returned = true;
        async.flushMicrotasks();
        leaky.close().ignore();
        async.flushTimers();
      });

      expect(returned, isTrue, reason: 'the write that ran the hook returns');
      expect(leaky.trace, isEmpty, reason: 'the hook was thrown out of');
      expect(leaky.currentState, 9);
      expect(
        zone,
        ['Bad state: delivery boom on 9', 'Bad state: delivery boom on 1'],
        reason: 'the second failure at once, the first through the hook',
      );
    });

    test('a failure let out of publish over a handler result is reported', () {
      late _Leaky leaky;
      late Job<void> job;
      final zone = _zone((async) {
        leaky = _Leaky();
        job = leaky.corrected(Completer<void>());
        async.flushMicrotasks();
        job.cancel().ignore();
        async.flushMicrotasks();
        leaky.close().ignore();
        async.flushTimers();
      });

      expect('${job.outcome}', 'Cancelled(manual)');
      expect(leaky.currentState, 4);
      expect(leaky.trace, [
        'onError: Bad state: delivery boom on 4',
        'onUnanswered: Bad state: delivery boom on 4',
      ]);
      expect(zone, isEmpty, reason: 'onUnanswered answered for it');
    });

    test('the changes behind the failed one are published all the same', () {
      // A mixin of somebody else in the same `with` can throw whatever the
      // page forbids. What must not happen then is a change that nothing
      // ever publishes: the failed one is gone, but the ones behind it are
      // the state the controller now holds.
      final delivery = _Delivery()
        ..writeFromFirst = ['c', 'd']
        ..bombAt = {'c'};

      expect(() => delivery.set('b'), throwsStateError);

      expect(delivery.currentState, 'd');
      expect(delivery.seen, ['b', 'd']);
      delivery.close().ignore();
    });

    test('of several failures the first is thrown, the rest go to the zone',
        () {
      String? escaped;
      final zone = _zone((async) {
        final delivery = _Delivery()
          ..writeFromFirst = ['c', 'd']
          ..bombAt = {'c', 'd'};
        try {
          delivery.set('b');
        } on Object catch (error) {
          escaped = '$error';
        }
        delivery.close().ignore();
        async.flushTimers();
      });

      expect(escaped, 'Bad state: delivery boom on c');
      expect(zone, ['Bad state: delivery boom on d']);
    });

    test('SoloStream closes after the engine; a paused subscription holds it',
        () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = page.Camera(device);
        final subscription = cam.stream.listen((_) {})..pause();
        var closed = false;
        cam.close().then((_) => closed = true);
        async.elapse(const Duration(hours: 1));

        expect(cam.isFinished, isTrue, reason: 'the engine has finished');
        expect(closed, isFalse, reason: 'close() is held by the stream');
        expect(cam.pending, isA<SoloPendingStream>());

        subscription.resume();
        async.flushMicrotasks();
        expect(closed, isTrue);
        expect(cam.pending, isNull);
        subscription.cancel().ignore();
        device.dispose();
        async.flushTimers();
      });
    });
  });

  group('External state', () {
    test('queued as a job, even first, the fact waits behind the running job',
        () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = first.Camera(device);
        final waiting = cam.waitForAnswer();
        async.flushMicrotasks();
        cam.later();
        final asked = cam.ruleAsked;
        device.drop();
        async.elapse(const Duration(hours: 1));

        expect(
          cam.queued,
          ['disconnect', 'later'],
          reason: 'first: true puts the fact ahead of everything waiting',
        );
        expect(cam.currentState, isA<camera.Ready>());
        expect(cam.ruleAsked, asked, reason: 'no change, so no question');
        expect(waiting.isFinished, isFalse, reason: 'and nothing frees it');

        // The answer the device was never going to give.
        device.answer.complete();
        async.flushMicrotasks();
        expect('${waiting.outcome}', 'Done(null)');
        expect(cam.currentState, isA<camera.Disconnected>());
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('reflected at once, the fact cancels the job that needs the link', () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = page.Camera(device);
        final job = cam.waitForAnswer();
        async.flushMicrotasks();
        cam.next();
        device.drop();
        async.flushMicrotasks();

        expect(cam.currentState, isA<camera.Disconnected>());
        expect(_ended(job), 'Cancelled(rules: is not Ready), started: true');
        expect(
          camera.stage.trace,
          ['the body resumed', 'the next job started'],
          reason: 'wait lets go of the call at once',
        );
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('under join the body resumes when the call ends, the queue waits', () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = page.Camera(device);
        final job = cam.waitForAnswer(joined: true);
        async.flushMicrotasks();
        cam.next();
        device.drop();
        async.elapse(const Duration(hours: 1));

        expect(job.isCancelled, isTrue, reason: 'cancelled by the fact');
        expect(job.isFinished, isFalse, reason: 'the call is waited out');
        expect(camera.stage.trace, isEmpty, reason: 'the queue waits too');

        device.answer.complete();
        async.flushMicrotasks();
        expect(
          camera.stage.trace,
          ['the body resumed', 'the next job started'],
        );
        expect(_ended(job), 'Cancelled(rules: is not Ready), started: true');
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });
  });

  group('State after failure or cancellation', () {
    late stubs.ProfileApi api;
    late List<String> heard;

    first.ProfileController byHand() {
      api = stubs.ProfileApi();
      heard = <String>[];
      final controller = first.ProfileController(api);
      controller.addListener(
        () => heard.add(stubs.describe(controller.currentState)),
      );
      return controller;
    }

    profile.ProfileController byHandlers() {
      api = stubs.ProfileApi();
      heard = <String>[];
      final controller = profile.ProfileController(api);
      controller.addListener(
        () => heard.add(stubs.describe(controller.currentState)),
      );
      return controller;
    }

    test('the first attempt: on a failure the catch writes the state back', () {
      fakeAsync((async) {
        final controller = byHand();
        final job = controller.loadWithCatch()..ignore();
        async.flushMicrotasks();
        api.fail(StateError('offline'));
        async.flushMicrotasks();

        expect(heard, ['Loading', 'Initial']);
        expect('${job.outcome}', 'Failed(Bad state: offline)');
        controller.close().ignore();
        async.flushTimers();
      });
    });

    test('the first attempt: cancelled, the controller stays in Loading', () {
      fakeAsync((async) {
        final controller = byHand();
        final job = controller.loadWithCatch();
        async.flushMicrotasks();
        job.cancel().ignore();
        async.elapse(const Duration(hours: 1));

        expect(
          heard,
          ['Loading'],
          reason: 'the emit in the catch wrote nothing',
        );
        expect(stubs.describe(controller.currentState), 'Loading');
        expect('${job.outcome}', 'Cancelled(manual)');
        controller.close().ignore();
        async.flushTimers();
      });
    });

    test('the first attempt: the answer reaches Loaded', () {
      fakeAsync((async) {
        final controller = byHand();
        final job = controller.loadWithCatch();
        async.flushMicrotasks();
        api.answer('Ada');
        async.flushMicrotasks();

        expect(heard, ['Loading', 'Loaded(Ada)']);
        expect('${job.outcome}', 'Done(Ada)');
        controller.close().ignore();
        async.flushTimers();
      });
    });

    test('a catch runs on a cancellation, and the emit inside it throws', () {
      fakeAsync((async) {
        final any = _Any();
        final job = any.emitsInCatch(Completer<void>());
        async.flushMicrotasks();
        job.cancel().ignore();
        async.flushMicrotasks();

        expect(any.trace, ['the catch ran', 'emit threw Cancelled(manual)']);
        expect(any.currentState, 'initial', reason: 'nothing was written');
        any.close().ignore();
        async.flushTimers();
      });
    });

    test('the handlers: the answer reaches Loaded', () {
      fakeAsync((async) {
        final controller = byHandlers();
        final job = controller.loadWithHandlers();
        async.flushMicrotasks();
        api.answer('Ada');
        async.flushMicrotasks();

        expect(heard, ['Loading', 'Loaded(Ada)']);
        expect('${job.outcome}', 'Done(Ada)');
        controller.close().ignore();
        async.flushTimers();
      });
    });

    test('the handlers: a cancellation leaves Loading for Initial', () {
      fakeAsync((async) {
        final controller = byHandlers();
        final job = controller.loadWithHandlers();
        async.flushMicrotasks();
        job.cancel().ignore();
        async.flushMicrotasks();

        expect(heard, ['Loading', 'Initial']);
        expect('${job.outcome}', 'Cancelled(manual)', reason: 'not Done');
        controller.close().ignore();
        async.flushTimers();
      });
    });

    test('the handlers: a failure leaves Loading and still reaches the zone',
        () {
      late Job<String> job;
      late List<String> states;
      final zone = _zone((async) {
        final controller = byHandlers();
        states = heard;
        job = controller.loadWithHandlers();
        async.flushMicrotasks();
        api.fail(StateError('offline'));
        async.flushMicrotasks();
        controller.close().ignore();
        async.flushTimers();
      });

      expect(states, ['Loading', 'Failure(Bad state: offline)']);
      expect(
        '${job.outcome}',
        'Failed(Bad state: offline)',
        reason: 'not Done',
      );
      expect(
        zone,
        ['Bad state: offline'],
        reason: 'the handler does not observe the outcome',
      );
    });

    test('a handler runs after body, children and cleanup, the outcome fixed',
        () {
      late _Any any;
      final zone = _zone((async) {
        any = _Any()
          ..failsLeavingWork()
          ..next();
        async.flushTimers();
        any.close().ignore();
        async.flushTimers();
      });

      expect(any.trace, [
        'body',
        'child',
        'cleanup',
        'onError: state initial, Bad state: boom, Failed(Bad state: boom)',
        'onFinish of first in corrected',
        'the next job in corrected',
        'onFinish of next in corrected',
      ]);
      expect(zone, ['Bad state: boom']);
    });

    test('onCancel is handed the current state and the cancellation', () {
      fakeAsync((async) {
        final any = _Any();
        final job = any.cancelledWithHandler(Completer<void>());
        async.flushMicrotasks();
        any.reflect('changed meanwhile');
        job.cancel().ignore();
        async.flushMicrotasks();

        expect(
          any.trace,
          ['onCancel: state changed meanwhile, Cancelled(manual)'],
        );
        expect(any.currentState, 'corrected');
        any.close().ignore();
        async.flushTimers();
      });
    });
  });

  group('Preserving an incompatible external state', () {
    late stubs.ProfileApi api;
    late List<String> heard;

    first.ProfileController withoutRule() {
      api = stubs.ProfileApi();
      heard = <String>[];
      final controller = first.ProfileController(api);
      controller.addListener(
        () => heard.add(stubs.describe(controller.currentState)),
      );
      return controller;
    }

    profile.ProfileController withRule() {
      api = stubs.ProfileApi();
      heard = <String>[];
      final controller = profile.ProfileController(api);
      controller.addListener(
        () => heard.add(stubs.describe(controller.currentState)),
      );
      return controller;
    }

    test('the first attempt: the load runs on through Disconnected', () {
      fakeAsync((async) {
        final controller = withoutRule();
        final job = controller.load();
        async.flushMicrotasks();
        controller.reflect(const stubs.Disconnected());
        async.elapse(const Duration(hours: 1));

        expect(job.isCancelled, isFalse);
        expect(heard, ['Loading', 'Disconnected']);
        controller.close().ignore();
        async.flushTimers();
      });
    });

    test('the first attempt: cancelled, onCancel writes over the fact', () {
      fakeAsync((async) {
        for (final what in ['the user', 'a screen closing']) {
          final controller = withoutRule();
          final job = controller.load();
          async.flushMicrotasks();
          controller.reflect(const stubs.Disconnected());
          if (what == 'the user') {
            job.cancel().ignore();
          } else {
            controller.close().ignore();
          }
          async.flushMicrotasks();

          expect(heard, ['Loading', 'Disconnected', 'Initial'], reason: what);
          expect(job.outcome, isA<Cancelled>(), reason: what);
          controller.close().ignore();
        }
        async.flushTimers();
      });
    });

    test('the first attempt: a duplicate cancels nothing', () {
      fakeAsync((async) {
        final controller = withoutRule();
        final job = controller.load();
        async.flushMicrotasks();
        controller.reflect(const stubs.Disconnected());

        final again = controller.load();
        async.flushMicrotasks();
        expect(
          identical(again, job),
          isTrue,
          reason: 'droppable hands it back',
        );
        expect(job.isCancelled, isFalse);
        expect(heard, ['Loading', 'Disconnected']);
        expect(api.calls, 1);
        controller.close().ignore();
        async.flushTimers();
      });
    });

    test('the first attempt: a failure writes over the fact as well', () {
      fakeAsync((async) {
        final controller = withoutRule();
        final job = controller.load()..ignore();
        async.flushMicrotasks();
        controller.reflect(const stubs.Disconnected());
        api.fail(StateError('offline'));
        async.flushMicrotasks();

        expect(
          heard,
          ['Loading', 'Disconnected', 'Failure(Bad state: offline)'],
        );
        expect(job.outcome, isA<Failed>());
        controller.close().ignore();
        async.flushTimers();
      });
    });

    test('the rules: the fact cancels the load and stays visible', () {
      late Job<String> job;
      late List<String> states;
      final zone = _zone((async) {
        final controller = withRule();
        states = heard;
        job = controller.load();
        async.flushMicrotasks();
        controller.reflect(const stubs.Disconnected());
        async.flushMicrotasks();
        // The request the load let go of fails afterwards.
        api.fail(StateError('offline'));
        async.flushMicrotasks();
        controller.close().ignore();
        async.flushTimers();
      });

      expect(_ended(job), 'Cancelled(rules: keepWhile), started: true');
      expect(
        states,
        ['Loading', 'Disconnected'],
        reason: 'neither Initial nor Failure replaces the fact',
      );
      expect(
        zone,
        ['Bad state: offline'],
        reason: 'the late failure of a call the job let go of',
      );
    });

    test('the rules: cancelled in a compatible state, onCancel still corrects',
        () {
      fakeAsync((async) {
        final controller = withRule();
        final job = controller.load();
        async.flushMicrotasks();
        job.cancel().ignore();
        async.flushMicrotasks();

        expect(heard, ['Loading', 'Initial']);
        expect('${job.outcome}', 'Cancelled(manual)');
        controller.close().ignore();
        async.flushTimers();
      });
    });

    test('the rules: a failure and an answer end where they did before', () {
      fakeAsync((async) {
        final failing = withRule();
        final failed = failing.load()..ignore();
        async.flushMicrotasks();
        api.fail(StateError('offline'));
        async.flushMicrotasks();
        expect(heard, ['Loading', 'Failure(Bad state: offline)']);
        expect(failed.outcome, isA<Failed>());

        final answering = withRule();
        final done = answering.load();
        async.flushMicrotasks();
        api.answer('Ada');
        async.flushMicrotasks();
        expect(heard, ['Loading', 'Loaded(Ada)']);
        expect('${done.outcome}', 'Done(Ada)');
        failing.close().ignore();
        answering.close().ignore();
        async.flushTimers();
      });
    });
  });

  group('Handler eligibility and errors', () {
    test('an incompatible external update disables them, whenever it arrives',
        () {
      fakeAsync((async) {
        for (final phase in ['the body', 'the children', 'the cleanup']) {
          final eligible = _Eligible();
          final gate = Completer<void>();
          final child = Completer<void>();
          final cleanup = Completer<void>();
          final job = eligible.guarded(gate, child: child, cleanup: cleanup);
          async.flushMicrotasks();

          void fact() => eligible
            ..reflect('bad')
            ..reflect('ok again');

          if (phase == 'the body') fact();
          gate.complete();
          async.flushMicrotasks();
          if (phase == 'the children') fact();
          child.complete();
          async.flushMicrotasks();
          if (phase == 'the cleanup') fact();
          job.cancel().ignore();
          cleanup.complete();
          async.flushMicrotasks();

          expect(job.outcome, isA<Cancelled>(), reason: phase);
          expect(
            eligible.currentState,
            'ok again',
            reason: '$phase: a compatible update does not bring them back',
          );
          expect(eligible.trace, ['cleanup ran'], reason: phase);
          eligible.close().ignore();
        }

        // The same cancellation with no incompatible update before it.
        final eligible = _Eligible();
        final job = eligible.guarded(Completer<void>());
        async.flushMicrotasks();
        eligible.reflect('ok again');
        job.cancel().ignore();
        async.flushMicrotasks();
        expect(eligible.currentState, 'corrected by onCancel');
        eligible.close().ignore();
        async.flushTimers();
      });
    });

    test('so does an emit of a child, of the parent or of a sibling', () {
      fakeAsync((async) {
        final byChild = _Eligible();
        final parent = byChild.parentOfWriter();
        final byParent = _Eligible()..writingParent();
        final bySibling = _Eligible()..writingSibling();
        async.flushTimers();

        expect('${parent.outcome}', 'Cancelled(rules: keepWhile)');
        expect(byChild.currentState, 'bad from the child');
        expect('${byParent.watcher!.outcome}', 'Cancelled(rules: keepWhile)');
        expect(byParent.currentState, 'bad from the parent');
        expect('${bySibling.watcher!.outcome}', 'Cancelled(rules: keepWhile)');
        expect(bySibling.currentState, 'bad from the sibling');
        byChild.close().ignore();
        byParent.close().ignore();
        bySibling.close().ignore();
        async.flushTimers();
      });
    });

    test('a parent that loses its permission blocks the handlers of children',
        () {
      fakeAsync((async) {
        String after({required bool early, required bool handlers}) {
          final eligible = _Eligible()..parentEndsEarly = early;
          final job = eligible.parent(Completer<void>(), handlers: handlers);
          async.flushMicrotasks();
          eligible
            ..reflect('bad')
            ..reflect('ok again');
          job.cancel().ignore();
          async.flushMicrotasks();
          final state = eligible.currentState;
          eligible.close().ignore();
          return state;
        }

        expect(
          after(early: false, handlers: false),
          'ok again',
          reason: 'the rules cancelled the parent, the child corrects nothing',
        );
        expect(
          after(early: true, handlers: true),
          'ok again',
          reason: 'a parent with handlers is asked after its body as well',
        );
        expect(
          after(early: true, handlers: false),
          'child corrected',
          reason: 'a parent without handlers stops asking when its body ends',
        );
        async.flushTimers();
      });
    });

    test('success, a duplicate and a body that never started run no handler',
        () {
      fakeAsync((async) {
        final eligible = _Eligible();
        final heard = <String>[];
        eligible.addListener(() => heard.add(eligible.currentState));

        final gate = Completer<void>();
        final running = eligible.droppable(gate);
        async.flushMicrotasks();
        final duplicate = eligible.droppable(gate);
        expect(identical(duplicate, running), isTrue);
        gate.complete();
        async.flushMicrotasks();
        expect('${running.outcome}', 'Done(done)');

        final refused = eligible.refused();
        final queued = eligible.droppable(Completer<void>());
        queued.cancel().ignore();
        async.flushMicrotasks();
        expect(_ended(refused), 'Cancelled(rules: canStart), started: false');
        expect(_ended(queued), 'Cancelled(manual), started: false');

        eligible.close().ignore();
        async.flushMicrotasks();
        final late = eligible.droppable(Completer<void>());
        async.flushMicrotasks();
        expect(_ended(late), 'Cancelled(closed), started: false');

        expect(heard, isEmpty);
        async.flushTimers();
      });
    });

    test("the job's own emit does not disable its handlers", () {
      fakeAsync((async) {
        final failing = _Eligible();
        final failed = failing.ownEmit(Completer<void>()..complete())..ignore();
        async.flushMicrotasks();
        expect(failed.outcome, isA<Failed>());
        expect(failing.currentState, 'corrected by onError');

        final cancelling = _Eligible();
        final gate = Completer<void>();
        final cancelled = cancelling.ownEmit(gate);
        async.flushMicrotasks();
        expect(cancelling.currentState, 'bad from the job itself');
        cancelled.cancel().ignore();
        gate.complete();
        async.flushMicrotasks();
        expect('${cancelled.outcome}', 'Cancelled(manual)');
        expect(cancelling.currentState, 'corrected by onCancel');
        failing.close().ignore();
        cancelling.close().ignore();
        async.flushTimers();
      });
    });

    test('a job its rules cancel at its own checkpoint runs no handler', () {
      fakeAsync((async) {
        final reading = _Eligible();
        final read = reading.ownEmit(
          Completer<void>()..complete(),
          thenReads: true,
        );
        final narrowing = _Eligible();
        final narrowed = narrowing.stateAsMismatch();
        async.flushTimers();

        expect(_ended(read), 'Cancelled(rules: keepWhile), started: true');
        expect(reading.currentState, 'bad from the job itself');
        expect(
          _ended(narrowed),
          'Cancelled(rules: is not Never), started: true',
        );
        expect(narrowing.currentState, 'loading');
        reading.close().ignore();
        narrowing.close().ignore();
        async.flushTimers();
      });
    });

    test('a handler that throws is reported; outcome and queue are untouched',
        () {
      fakeAsync((async) {
        final eligible = _Eligible();
        final job = eligible.handlerThrows(Completer<void>());
        eligible.next();
        async.flushMicrotasks();
        job.cancel().ignore();
        async.flushTimers();

        expect('${job.outcome}', 'Cancelled(manual)');
        expect(eligible.currentState, 'ok');
        expect(eligible.trace, [
          'onError of thrower: Bad state: handler boom',
          'onUnanswered of thrower: Bad state: handler boom',
          'the next job ran in ok',
        ]);
        eligible.close().ignore();
        async.flushTimers();
      });
    });

    test('a rule that throws while eligibility is checked disables them', () {
      fakeAsync((async) {
        final eligible = _Eligible();
        final cleanup = Completer<void>();
        final job = eligible.guarded(Completer<void>(), cleanup: cleanup);
        async.flushMicrotasks();
        eligible
          ..ruleThrows = true
          ..reflect('ok still')
          ..ruleThrows = false;
        expect(
          job.isCancelled,
          isFalse,
          reason: 'a rule that threw cancels nothing',
        );
        job.cancel().ignore();
        cleanup.complete();
        async.flushTimers();

        expect('${job.outcome}', 'Cancelled(manual)');
        expect(eligible.currentState, 'ok still', reason: 'no handler ran');
        expect(
          eligible.trace,
          [
            'onError of guarded: Bad state: rule boom',
            'onUnanswered of guarded: Bad state: rule boom',
            'cleanup ran',
          ],
          reason: 'reported once, and the cleanup still runs',
        );
        eligible.close().ignore();
        async.flushTimers();
      });
    });

    test('a write from inside a handler: accepted, the result lands on top',
        () {
      fakeAsync((async) {
        final eligible = _Eligible();
        final job = eligible.writesFromHandler(Completer<void>(), rule: false);
        async.flushMicrotasks();
        final heard = <String>[];
        eligible.addListener(() => heard.add(eligible.currentState));
        job.cancel().ignore();
        async.flushMicrotasks();

        expect(
          heard,
          ['bad fact', 'corrected from ok'],
          reason: 'computed from the state before the write, the fact is lost',
        );
        eligible.close().ignore();
        async.flushTimers();
      });
    });

    test('a write from inside a handler: refused, the result is dropped', () {
      fakeAsync((async) {
        final eligible = _Eligible();
        final job = eligible.writesFromHandler(Completer<void>(), rule: true);
        async.flushMicrotasks();
        final heard = <String>[];
        eligible.addListener(() => heard.add(eligible.currentState));
        job.cancel().ignore();
        async.flushMicrotasks();

        expect(heard, ['bad fact']);
        expect(eligible.currentState, 'bad fact');
        eligible.close().ignore();
        async.flushTimers();
      });
    });
  });

  group('The page', () {
    test('four sections open with a first attempt, as the introduction says',
        () {
      final attempts = RegExp(r'^#{3,4} The first attempt$', multiLine: true)
          .allMatches(_page())
          .length;
      expect(attempts, 4);
      expect(
        _page(),
        contains(RegExp(r'Four sections below\s+open with the version')),
      );
    });

    test('has no fence the checks do not read', () {
      expect(strayFences('doc/state.md'), isEmpty);
    });

    // Each version under its own file: a line of an answer turned into the
    // line of a first attempt would still be found among all of them.
    const answers = 'test/support/state_page.dart';
    const profileAnswers = 'test/support/state_page_profile.dart';
    const firstAttempts = 'test/support/state_first_attempts.dart';
    const profileStates = 'test/support/state_profile_stubs.dart';
    const holders = {
      '### The first attempt': firstAttempts,
      '### The rules': answers,
      '### Reading and updating state': answers,
      '### Observing state': answers,
      '### A delivery of your own': answers,
      '### externalSetState': answers,
      '### The handlers': profileAnswers,
      '#### The first attempt': firstAttempts,
      '#### The rules': profileAnswers,
    };
    for (final MapEntry(key: heading, value: holder) in holders.entries) {
      test('the code under "$heading" is a run of lines of $holder', () {
        expect(
          codeMissingFrom(
            'doc/state.md',
            holder,
            // The class the last first attempt adds to the profile states
            // stands next to them.
            alsoIn: [if (heading == '#### The first attempt') profileStates],
            under: heading,
          ),
          isEmpty,
        );
      });
    }

    test('every piece of code on the page is a run of lines of these files',
        () {
      expect(
        codeMissingFrom(
          'doc/state.md',
          answers,
          alsoIn: [profileAnswers, firstAttempts, profileStates],
        ),
        isEmpty,
      );
    });
  });
}
