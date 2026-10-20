@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/errors_first_attempts.dart' as first;
import 'support/errors_page.dart' as page;
import 'support/errors_rakes.dart';
import 'support/errors_stubs.dart';
import 'support/page_code.dart';
import 'support/test_solo.dart';

/// The sentinel of `doc/diagnostics.md`.
///
/// The code of the page stands verbatim in `test/support/errors_*.dart`,
/// beside the code of `doc/errors.md`: the first attempt in one file, the
/// versions that work and the code the sections open with in another. The
/// tests below run that code and pin what the prose, the tables and the
/// quoted lines of the page say about it: what an observer is told, what
/// `pending` says holds a close and how long a job ran past its
/// cancellation. What the page states of the engine and its code does not
/// show is pinned on `Bench`, a controller whose bodies are written where
/// they are run.
///
/// Every call of a stub runs until the test ends it, so each trace is the
/// order the test set, and fake time moves only where the page speaks of
/// time: the five seconds of the two timers and the delays of the table.

/// An observer whose `onStart` throws a [Cancelled].
final class _GivingUp extends SoloObserver {
  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      throw const Cancelled('observer.onStart');
}

/// A controller whose `onStart` throws a [Cancelled].
final class _GivingUpController extends Solo<int> with OpenSolo<int> {
  _GivingUpController() : super(0);

  @override
  void onStart(Job<Object?> job) => throw const Cancelled('controller.onStart');
}

/// A hook that changes the state again from inside the first change.
final class _Nesting extends Solo<int> with OpenSolo<int> {
  final order = <String>[];
  var _nested = false;

  _Nesting() : super(0);

  @override
  void onChange(SoloTransition<int> transition) {
    order.add('in #${transition.revision}');
    if (!_nested) {
      _nested = true;
      externalSetState(2);
    }
    order.add('out #${transition.revision}');
  }
}

/// A controller that keeps the transitions it was given, and reads
/// `pending` from the two hooks in the middle of a close.
final class _Journal extends Solo<int> with OpenSolo<int> {
  final changes = <String>[];
  final read = <String>[];

  _Journal() : super(0);

  @override
  void onChange(SoloTransition<int> transition) => changes.add(
        '#${transition.revision} ${transition.job?.key ?? 'external'}: '
        '${transition.previous} -> ${transition.current}',
      );

  @override
  void onFinish(Job<Object?> job) => read.add('onFinish: $pending');

  @override
  void onClose() => read.add('onClose: $pending');
}

String _page() => diagnosticsPage.source;

void _says(String phrase) => diagnosticsPage.says(phrase);

Map<String, String> _rows(String header) => diagnosticsPage.rows(header);

List<List<String>> _quoted() => diagnosticsPage.quoted;

Future<void> _delay(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

/// A job that waits on a call named `op` with a bare `await`.
SoloJob<void> _ignores(Bench bench, String key) =>
    bench.run<int, void>(key: key, (ctx) => stage.start<void>('op', null));

/// A job that waits on a call named `op` inside an uncancellable section.
SoloJob<void> _holds(Bench bench, String key) => bench.run<int, void>(
      key: key,
      (ctx) => ctx.uncancellable(() => stage.start<void>('op', null)),
    );

void main() {
  setUp(() => stage = Stage());

  tearDown(() {
    Solo.observer = null;
    Solo.unansweredHandler = null;
    Solo.debug = null;
    Job.debug = null;
    Job.isCancellationError = null;
  });

  group('Logs', () {
    test('the data of the page, handed on as it is', () {
      _says(
        '`ctx.log(data)` hands application data to the log hooks and '
        'observers as it is, so a listener that wants a line makes one',
      );
      final watching = <Object?>[];
      runFaked((async) {
        Solo.observer = _Logs(watching);
        page.Camera(Hardware()).zoomTo(2, page.logZoom);
      });

      expect(watching, [('zoom', 2.0)]);
      expect(stage.fine, [('zoom', 2.0)], reason: 'the hook of the page');
    });

    test('the lazy line of the page, with the logger at FINE', () {
      _says(
        'The body logs every time. The line is built, the call of '
        '`describe()` included, only where somebody listens at that '
        'level',
      );
      runFaked((async) {
        page.Camera(Hardware()).zoomTo(2, page.logLazily);
      });

      expect(stage.fine, ['zoom to 2.0 on the back camera']);
      expect(stage.described, 1);
    });

    test('the lazy line of the page, with the logger at INFO', () {
      _says(
        'Everywhere else the message stays a closure that nobody called',
      );
      _says('`ctx.log` calls nothing on the way either');
      final watching = <Object?>[];
      runFaked((async) {
        stage.level = Level.INFO;
        Solo.observer = _Logs(watching);
        page.Camera(Hardware()).zoomTo(2, page.logLazily);
      });

      expect(stage.fine, isEmpty);
      expect(stage.described, 0);
      expect(watching.single, isA<String Function()>());
    });

    test('a callback that may return null, and a plain message', () {
      String? name() => null;
      runFaked((async) {
        page.Camera(Hardware()).zoomTo(2, (ctx, zoom) {
          ctx
            ..log(name)
            ..log('a plain line');
        });
      });

      expect(stage.fine, [null, 'a plain line']);
    });

    test('the two channels of the page', () {
      _says(
        '`Solo.debug` traces the queue of the controller and its '
        'lifecycle as well',
      );
      _says(
        'Each job reports its start, its errors, a cancellation that '
        'reaches it and its outcome to `Job.debug`, the channel of the '
        'core; when both are set, both show',
      );
      final ran = runFaked((async) {
        page.traceTheEngine();
        page.traceTheCore();
        final bench = Bench();
        final job = bench.run<int, void>(key: 'zoom', (ctx) async {
          ctx
            ..emit(1)
            ..onDispose(() async => throw StateError('disposer'));
          await ctx.abandonable(() => stage.start<void>('op', null));
        })
          ..ignoreFailure();
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        unawaited(bench.close());
      });

      expect(ran.printed, [
        'add Job(zoom)',
        'Job(zoom) started',
        'Job(zoom) emit: 1',
        'state: 1',
        'cancel Job(zoom): Cancelled(manual)',
        'Job(zoom) error: Bad state: disposer',
        'Job(zoom) error nobody answered for: Bad state: disposer',
        'Job(zoom) error went to the zone: Bad state: disposer',
        'Job(zoom) finished: Cancelled(manual)',
        'queue has no ready jobs',
        'close',
        'closed',
      ]);
    });

    test('one channel alone: the queue without the jobs, and the reverse', () {
      List<String> printedWith(void Function() install) => runFaked((async) {
            install();
            Bench().run<int, void>(key: 'zoom', (ctx) async {});
          }).printed;

      expect(
        printedWith(page.traceTheEngine),
        ['add Job(zoom)', 'queue has no ready jobs'],
      );
      Solo.debug = null;
      expect(
        printedWith(page.traceTheCore),
        ['Job(zoom) started', 'Job(zoom) finished: Done(null)'],
      );
    });
  });

  group('Watching every controller', () {
    test('the observer of the page on the load of the quick start', () {
      late Job<String> job;
      final ran = runFaked((async) {
        page.main();
        final profile = page.ProfileController(ProfileApi());
        job = profile.load()..ignoreFailure();
        async.flushMicrotasks();
        endCall(async, 'fetchName');
      });

      expect(ran.printed, [
        'Job(load) started',
        'Job(load): Loading',
        'Job(load): Loaded(Ada Lovelace)',
        'Job(load) finished Done(Ada Lovelace)',
      ]);
      expect('${job.outcome}', 'Done(Ada Lovelace)');
    });

    test('the observer of the page on a change from outside and on a child',
        () {
      final ran = runFaked((async) {
        page.main();
        final bench = Bench()..reflect(1);
        bench.run<int, void>(key: 'root', (ctx) async {
          await ctx.run(
            bench.job<int, void>(key: 'child', (child) async => child.emit(7)),
          );
        });
      });

      expect(ran.printed, [
        'external: 1',
        'Job(root) started',
        'Job(child) started',
        'Job(child): 7',
        'Job(child) finished Done(null)',
        'Job(root) finished Done(null)',
      ]);
    });

    test('what the observer is told, and what stays with the controller', () {
      _says(
        '`SoloObserver` is told what the controllers are told, '
        '`onStart`, `onFinish`, `onError`, `onLog`, `onChange` and '
        '`onClose`, for every controller of the process, and `onCreate` '
        'besides',
      );
      _says(
        '`onUnanswered` and `onListenerError` stay with the controller alone',
      );
      _says(
        'The observer is called before the corresponding hook of the '
        'controller',
      );
      final order = <String>[];
      final ran = runFaked((async) {
        Solo.observer = Saying('observer', order);
        final controller = EveryHook(order)
          ..addListener(() => throw StateError('listener'))
          ..run<int, void>(key: 'job', (ctx) async {
            ctx
              ..log('line')
              ..emit(1)
              ..onDispose(() async => throw StateError('disposer'));
          });
        async.flushMicrotasks();
        unawaited(controller.close());
      });

      expect(order, [
        'observer.onCreate',
        'observer.onStart',
        'controller.onStart',
        'observer.onLog',
        'controller.onLog',
        'observer.onChange',
        'controller.onChange',
        'controller.onListenerError',
        'observer.onError',
        'controller.onError',
        'controller.onUnanswered',
        'observer.onFinish',
        'controller.onFinish',
        'observer.onClose',
        'controller.onClose',
      ]);
      expect(ran.errors, isEmpty);
    });

    test('the job of a transition: an emit, a child, a handler, the outside',
        () {
      _says(
        'The `job` is the one whose `emit` made the change or whose '
        'state handler returned it. It is `null` for an '
        '`externalSetState`, and it is a child of the running job when '
        'the child made the change, not the root the child belongs to',
      );
      late _Journal journal;
      runFaked((async) {
        journal = _Journal()..externalSetState(1);
        journal.run<int, void>(
          key: 'root',
          ifFailed: (state, error, stackTrace) => -1,
          (ctx) async {
            ctx.emit(2);
            await ctx.run(
              journal.job<int, void>(
                key: 'child',
                (child) async => child.emit(3),
              ),
            );
            throw StateError('the body');
          },
        ).ignoreFailure();
        final cancelled = journal.run<int, void>(
          key: 'cancelled',
          ifCancelled: (state, cancelled) => -2,
          (ctx) => ctx.abandonable(() => stage.start<void>('op', null)),
        )..ignoreFailure();
        async.flushMicrotasks();
        unawaited(cancelled.cancel());
      });

      expect(journal.changes, [
        '#1 external: 0 -> 1',
        '#2 root: 1 -> 2',
        '#3 child: 2 -> 3',
        '#4 root: 3 -> -1',
        '#5 cancelled: -1 -> -2',
      ]);
    });

    test('a hook that changes the state again from inside the first change',
        () {
      _says(
        'a `revision` that grows by one per change. The revision keeps '
        'two transitions in order even when a hook changed the state '
        'again from inside the first',
      );
      final nesting = _Nesting()..externalSetState(1);

      expect(nesting.order, ['in #1', 'in #2', 'out #2', 'out #1']);
      expect(nesting.currentState, 2);
    });

    for (final thrower in ['observer', 'controller']) {
      test('the $thrower hook throws', () {
        errorsRow(
          'An error a hook throws',
          'Nobody',
          'The current zone',
        );
        _says(
          'Each call stands on its own: a controller hook that leaves out '
          '`super` does not switch the observer off',
        );
        _says(
          'An error either hook throws goes to the current zone. It does '
          'not change the outcome of the job, stop the queue or keep the '
          'other hook from running',
        );
        final order = <String>[];
        late Job<void> job;
        late Job<void> next;
        final ran = runFaked((async) {
          Solo.observer = Saying(
            'observer',
            order,
            throwOn: thrower == 'observer' ? 'onStart' : null,
          );
          final controller = EveryHook(
            order,
            throwOn: thrower == 'controller' ? 'onStart' : null,
          );
          job = controller.run<int, void>(key: 'job', (ctx) async {});
          next = controller.run<int, void>(key: 'next', (ctx) async {});
        });

        expect(order, [
          'observer.onCreate',
          for (var i = 0; i < 2; i++) ...[
            'observer.onStart',
            'controller.onStart',
            'observer.onFinish',
            'controller.onFinish',
          ],
        ]);
        expect('${job.outcome}', 'Done(null)');
        expect('${next.outcome}', 'Done(null)', reason: 'the queue went on');
        expect(ran.errors, [
          '$thrower.onStart threw',
          '$thrower.onStart threw',
        ]);
      });
    }

    test('both hooks throw a Cancelled', () {
      _says(
        'A `Cancelled` a hook throws neither reaches the zone nor '
        'cancels the job',
      );
      late Job<void> job;
      final ran = runFaked((async) {
        Solo.observer = _GivingUp();
        job = _GivingUpController().run<int, void>(key: 'job', (ctx) async {});
      });

      expect('${job.outcome}', 'Done(null)');
      expect(ran.errors, isEmpty);
    });

    test('the zone a hook error goes to is the current one', () {
      final where = <String, List<String>>{};
      fakeAsync((async) {
        late EveryHook controller;
        where['the controller was created'] = zoneOf(
          () => controller = EveryHook([], throwOn: 'onChange'),
        );
        where['the job was created'] = zoneOf(
          () => controller.run<int, void>(
            key: 'job',
            (ctx) => ctx.abandonable(() => stage.start<void>('op', null)),
          ),
        );
        where['the state changed'] = zoneOf(() {
          async.flushMicrotasks();
          controller.externalSetState(5);
        });
        endCall(async, 'op');
      });

      expect(where, {
        'the controller was created': isEmpty,
        'the job was created': isEmpty,
        'the state changed': ['controller.onChange threw'],
      });
    });

    test('an observer set, and a failure nobody observed', () {
      _says(
        'An observer only watches. Setting one changes nothing about where '
        'an error then goes',
      );
      final watching = Watching();
      final ran = runFaked((async) {
        Solo.observer = watching;
        Bench().run<int, void>(
          key: 'body',
          (ctx) async => throw StateError('the body'),
        );
      });

      expect(watching.heard, ['body: the body']);
      expect(ran.errors, ['the body']);
    });
  });

  group('What is holding the controller', () {
    test('the page quotes three lines of a close, two of a hang, one more', () {
      expect(_quoted().map((block) => block.length), [3, 2, 1]);
    });

    test('the line of the page: close() on a job that has not stopped', () {
      _says(
        '`close()` waits for the running job, and a job can take its time',
      );
      var closed = false;
      runFaked((async) {
        final bench = Bench();
        _ignores(bench, 'stuck');
        async.flushMicrotasks();
        page.closeWithTimeout(bench);
        async.elapse(const Duration(seconds: 6));
        closed = bench.isFinished;
        endCall(async, 'op');
      });

      expect(stage.lines, [_quoted()[0][0]]);
      expect(closed, isFalse, reason: 'the close is still held');
    });

    test('the same line under a drain: the queue it has still to run', () {
      _says(
        'A drain waits for the queue as well. A group of `collect` or '
        '`accumulate` stays queued until its timing lets it go. With no '
        'job running, `pending` is a `SoloPendingQueue`, and its `jobs` '
        'are what the drain still has to run',
      );
      SoloPending? pending;
      SoloPending? withoutClose;
      var ranAfter = false;
      runFaked((async) {
        final bench = Bench();
        bench
            .collect<int, int, void>(
              key: 'group',
              timing: AccumulationTiming.debounce(const Duration(seconds: 20)),
              (ctx, events) async => ranAfter = true,
            )
            .add(1);
        async.flushMicrotasks();
        withoutClose = bench.pending;
        unawaited(
          bench.close(mode: SoloCloseMode.drain).timeout(
                const Duration(seconds: 5),
                onTimeout: () => log('closing is held by ${bench.pending}'),
              ),
        );
        async.elapse(const Duration(seconds: 6));
        pending = bench.pending;
      });

      expect(stage.lines, [_quoted()[0][1]]);
      expect(pending, isA<SoloPendingQueue>());
      expect(
        (pending! as SoloPendingQueue).jobs.map((job) => job.key),
        ['group'],
      );
      expect(withoutClose, isNull, reason: 'nothing is closing yet');
      expect(ranAfter, isTrue, reason: 'the drain ran it in the end');
    });

    test('the same line with SoloStream: a subscription left paused', () {
      _says(
        'With `SoloStream`, the stream closes after the engine and '
        'waits for every subscription to take its done event. One left '
        'paused holds `close()` with `isFinished` already true, and '
        '`pending` is a `SoloPendingStream`',
      );
      _says('The three print alike, so the line above needs no switch');
      SoloPending? pending;
      var finished = false;
      var back = false;
      SoloPending? afterwards;
      runFaked((async) {
        final bench = StreamBench();
        final subscription = bench.stream.listen((_) {})..pause();
        bench.close().then((_) => back = true);
        page.closeWithTimeout(bench);
        async.elapse(const Duration(seconds: 6));
        pending = bench.pending;
        finished = bench.isFinished && !back;
        subscription.resume();
        async.flushMicrotasks();
        afterwards = bench.pending;
        unawaited(subscription.cancel());
      });

      expect(stage.lines, [_quoted()[0][2]]);
      expect(pending, isA<SoloPendingStream>());
      expect(finished, isTrue, reason: 'finished, and close() not back');
      expect(back, isTrue, reason: 'the resumed subscription let it go');
      expect(afterwards, isNull);
    });

    group('the fields of the table:', () {
      test('the ten the page names', () {
        expect(_rows('| Field | What it says |').keys, [
          '`job`',
          '`phase`',
          '`cancellation`',
          '`heldCancellation`',
          '`children`',
          '`inUncancellableSection`',
          '`cancellable`',
          '`closing`',
          '`draining`',
          '`queued`',
        ]);
        _says(
          'While a job holds it, `pending` is a `SoloPendingJob`, a snapshot '
          'of that job',
        );
      });

      test('a job nobody asked to stop, then one that accepted it', () {
        fakeAsync((async) {
          final bench = Bench();
          final job = _ignores(bench, 'bare')..ignoreFailure();
          async.flushMicrotasks();
          final before = bench.pending! as SoloPendingJob;
          unawaited(job.cancel());
          async.flushMicrotasks();
          final after = bench.pending! as SoloPendingJob;

          expect(before.job, same(job));
          expect(before.phase, SoloPhase.body);
          expect(before.cancellation, isNull);
          expect(before.heldCancellation, isNull);
          expect(before.children, 0);
          expect(before.inUncancellableSection, isFalse);
          expect(before.cancellable, isTrue);
          expect(before.closing, isFalse);
          expect(before.draining, isFalse);
          expect(before.queued, isEmpty);
          expect(before.cancellationPending, isFalse);

          expect('${after.cancellation}', 'Cancelled(manual)');
          expect(after.heldCancellation, isNull);
          expect(after.cancellationPending, isTrue);
          endCall(async, 'op');
          expect(bench.pending, isNull);
        });
      });

      test('a job inside a section, then one that holds a cancellation', () {
        _says(
          '`SoloPendingJob.cancellationPending` is true when either '
          'cancellation above is there, the accepted one or the held one',
        );
        fakeAsync((async) {
          final bench = Bench();
          final job = _holds(bench, 'held')..ignoreFailure();
          async.flushMicrotasks();
          final before = bench.pending! as SoloPendingJob;
          unawaited(job.cancel());
          async.flushMicrotasks();
          final after = bench.pending! as SoloPendingJob;

          expect(before.inUncancellableSection, isTrue);
          expect(before.heldCancellation, isNull);
          expect(before.cancellationPending, isFalse);

          expect(after.inUncancellableSection, isTrue);
          expect(after.cancellation, isNull);
          expect('${after.heldCancellation}', 'Cancelled(manual)');
          expect(after.cancellationPending, isTrue);
          endCall(async, 'op');
        });
      });

      test('a job created with cancellable: false, asked twice and closed', () {
        _says(
          'A job whose `cancellable` is false turns down the '
          'cancellations it may turn down, so nothing is pending on it '
          'however often it was asked to stop',
        );
        fakeAsync((async) {
          final bench = Bench();
          final job = bench.run<int, void>(
            key: 'refuses',
            cancellable: false,
            (ctx) => stage.start<void>('op', null),
          );
          async.flushMicrotasks();
          unawaited(job.cancel());
          unawaited(job.cancel());
          async.flushMicrotasks();
          final asked = bench.pending! as SoloPendingJob;
          unawaited(bench.close());
          async.flushMicrotasks();
          final closed = bench.pending! as SoloPendingJob;

          expect(asked.cancellable, isFalse);
          expect(asked.cancellation, isNull);
          expect(asked.heldCancellation, isNull);
          expect(asked.cancellationPending, isFalse);
          expect(asked.closing, isFalse);

          expect(closed.closing, isTrue);
          expect(closed.draining, isFalse);
          expect(closed.cancellationPending, isFalse);
          endCall(async, 'op');
        });
      });

      test('a job with two children: its body, the children, the cleanup', () {
        fakeAsync((async) {
          final bench = Bench();
          bench.run<int, void>(key: 'root', (ctx) async {
            ctx.onDispose(() => stage.start<void>('release', null));
            for (final name in ['one', 'two']) {
              ctx
                  .run(
                    bench.job<int, void>(
                      key: name,
                      (child) => child
                          .abandonable(() => stage.start<void>(name, null)),
                    ),
                  )
                  .ignore();
            }
            await ctx.abandonable(() => stage.start<void>('body', null));
          });
          async.flushMicrotasks();
          final inBody = bench.pending! as SoloPendingJob;
          endCall(async, 'body');
          final waiting = bench.pending! as SoloPendingJob;
          endCall(async, 'one');
          final oneLeft = bench.pending! as SoloPendingJob;
          endCall(async, 'two');
          final cleaning = bench.pending! as SoloPendingJob;
          endCall(async, 'release');

          expect(inBody.phase, SoloPhase.body);
          expect(inBody.children, 2);
          expect(waiting.phase, SoloPhase.children);
          expect(waiting.children, 2);
          expect(oneLeft.children, 1);
          expect(cleaning.phase, SoloPhase.cleanup);
          expect(cleaning.children, 0);
          expect(
            SoloPhase.values.map((phase) => phase.name),
            ['body', 'children', 'cleanup'],
          );
          _says('what it is doing: `body`, `children`, `cleanup`');
        });
      });

      test('a drain on a running job, which runs to its end', () {
        _says(
          'whether that `close()` is a drain, which lets the job run to its '
          'end',
        );
        fakeAsync((async) {
          final bench = Bench();
          final job = waits(bench, 'runs');
          async.flushMicrotasks();
          unawaited(bench.close(mode: SoloCloseMode.drain));
          async.flushMicrotasks();
          final pending = bench.pending! as SoloPendingJob;
          endCall(async, 'op');

          expect(pending.closing, isTrue);
          expect(pending.draining, isTrue);
          expect(pending.cancellation, isNull);
          expect('$pending', 'SoloPending([runs] in its body, draining)');
          expect('${job.outcome}', 'Done(null)');
        });
      });
    });

    test('null: an idle controller, and the hooks in the middle of a close',
        () {
      _says('`null` says that nothing the controller knows of holds the close');
      _says(
        'A timer reads `pending` between the steps of a close, and a '
        'synchronous hook reads it in the middle of one: `onFinish` of '
        'the last job and `onClose` read `null`, though `close()` has '
        'not come back yet',
      );
      fakeAsync((async) {
        final journal = _Journal()
          ..run<int, void>(
            key: 'last',
            cancellable: false,
            (ctx) => stage.start<void>('op', null),
          );
        async.flushMicrotasks();
        var back = false;
        journal.close().then((_) => back = true);
        String? atTheTimer;
        Timer(
          const Duration(seconds: 1),
          () => atTheTimer = '${journal.pending}',
        );
        async.elapse(const Duration(seconds: 2));
        journal.read.add('close() is back: $back');
        endCall(async, 'op');

        const held =
            'SoloPending([last] in its body, closing, created cancellable: '
            'false)';
        expect(atTheTimer, held);
        expect(journal.read, [
          'close() is back: false',
          'onFinish: null',
          'onClose: null',
        ]);
        expect(back, isTrue);
        expect(Bench().pending, isNull, reason: 'an idle controller');
      });
    });

    group('Hangs:', () {
      test('a job that never ends, as the page quotes it', () {
        runFaked((async) {
          Solo.observer = page.Hangs();
          waits(Bench(), 'stuck');
          async.elapse(const Duration(seconds: 6));
          endCall(async, 'op');
        });

        expect(stage.lines, [_quoted()[1][0]]);
      });

      test('a job that holds a cancellation, as the page quotes it', () {
        runFaked((async) {
          Solo.observer = page.Hangs();
          final job = _holds(Bench(), 'held')..ignoreFailure();
          async.elapse(const Duration(seconds: 1));
          unawaited(job.cancel());
          async.elapse(const Duration(seconds: 6));
          endCall(async, 'op');
        });

        expect(stage.lines, [_quoted()[1][1]]);
      });

      test('a job that ends in time', () {
        _says(
          'A job that ends in time disarms its own timer and says nothing',
        );
        var timers = -1;
        runFaked((async) {
          Solo.observer = page.Hangs();
          Bench().run<int, void>(key: 'quick', (ctx) => _delay(300));
          async.elapse(const Duration(seconds: 1));
          timers = async.pendingTimers.length;
          async.elapse(const Duration(seconds: 6));
        });

        expect(stage.lines, isEmpty);
        expect(timers, 0, reason: 'the timer went with the job');
      });

      test('a child that hangs under its root', () {
        _says(
          'One that does not is named at the front of its line. The '
          'snapshot beside the name is of the root job the controller is '
          'on. That is the same job, unless the one that hangs is a child',
        );
        runFaked((async) {
          Solo.observer = page.Hangs();
          final bench = Bench();
          bench.run<int, void>(key: 'root', (ctx) async {
            await ctx.run(
              bench.job<int, void>(
                key: 'child',
                (child) =>
                    child.abandonable(() => stage.start<void>('op', null)),
              ),
            );
          });
          async.elapse(const Duration(seconds: 6));
          endCall(async, 'op');
        });

        expect(stage.lines, [
          'root is still running: SoloPending([root] in its body)',
          'child is still running: SoloPending([root] in its body)',
        ]);
      });

      test('a job queued behind the one that hangs', () {
        runFaked((async) {
          Solo.observer = page.Hangs();
          final bench = Bench();
          waits(bench, 'stuck');
          bench.run<int, void>(key: 'queued', (ctx) async {});
          async.elapse(const Duration(seconds: 6));
          endCall(async, 'op');
        });

        const snapshot = 'SoloPending([stuck] in its body, 1 queued: [queued])';
        expect(
          stage.lines,
          ['stuck is still running: $snapshot'],
          reason: 'onStart has not come for the queued one',
        );
      });

      test('Hangs only reports, and a deadline stops the job', () {
        _says('`Hangs` only reports: the job it names goes on running');
        _says('A job that must stop at its limit takes the limit itself, '
            '`run(timeout: ...)`. The limit cancels the job, and the job '
            'ends `Cancelled(timeout)` when its body reaches a checkpoint or '
            'returns');
        _says('`ctx.abandonable` around the call ends the wait and leaves '
            'the call running');
        late SoloJob<void> reported;
        late SoloJob<void> limited;
        var runningAtSix = false;
        var callRunsOn = false;
        runFaked((async) {
          Solo.observer = page.Hangs();
          final bench = Bench();
          reported = waits(bench, 'stuck')..ignoreFailure();
          async.elapse(const Duration(seconds: 6));
          runningAtSix = !reported.isFinished;
          endCall(async, 'op');

          limited = bench.run<int, void>(
            key: 'limited',
            timeout: const Duration(seconds: 3),
            (ctx) => ctx.abandonable(() => stage.start<void>('op', null)),
          );
          async.elapse(const Duration(seconds: 6));
          callRunsOn = limited.isFinished && stage.isRunning('op');
        });

        expect(
          stage.lines,
          ['stuck is still running: SoloPending([stuck] in its body)'],
        );
        expect(runningAtSix, isTrue);
        expect('${reported.outcome}', 'Done(null)');
        expect('${limited.outcome}', 'Cancelled(timeout)');
        expect(callRunsOn, isTrue, reason: 'abandonable leaves the call');
      });

      test('a deadline does not stop a body that awaits a call bare', () {
        _says('A body that awaits a call bare reaches none until the call '
            'returns, and the queue and `close()` wait for it all that time');
        late SoloJob<void> deaf;
        late SoloJob<void> queued;
        late bool cancelledAtSix;
        late bool finishedAtSix;
        late bool queuedFinishedAtSix;
        var closed = false;
        runFaked((async) {
          final bench = Bench();
          deaf = bench.run<int, void>(
            key: 'deaf',
            timeout: const Duration(seconds: 3),
            (ctx) => stage.start<void>('op', null),
          );
          queued = bench.run<int, void>(key: 'queued', (ctx) async {});
          unawaited(
            bench.close(mode: SoloCloseMode.drain).then((_) => closed = true),
          );
          async.elapse(const Duration(seconds: 6));
          cancelledAtSix = deaf.isCancelled;
          finishedAtSix = deaf.isFinished;
          queuedFinishedAtSix = queued.isFinished;
          expect(closed, isFalse, reason: 'close() waits for the body');
          endCall(async, 'op');
          async.flushTimers();
        });

        expect(cancelledAtSix, isTrue);
        expect(finishedAtSix, isFalse);
        expect(queuedFinishedAtSix, isFalse);
        expect('${deaf.outcome}', 'Cancelled(timeout)');
        expect('${queued.outcome}', 'Done(null)');
        expect(closed, isTrue);
      });

      test('the two recipes that read onFinish say nothing about a hang', () {
        _says(
          '`onFinish` never comes for a job that never finishes. The '
          'recipe of [Why cancellation was '
          'slow](#why-cancellation-was-slow) works out its delay in '
          '`onFinish`, and so it says nothing about a hang',
        );
        runFaked((async) {
          Solo.observer = SoloObserver.all([
            first.SlowJobs(),
            page.SlowCancellations(),
          ]);
          final job = _ignores(Bench(), 'stuck')..ignoreFailure();
          async.elapse(const Duration(seconds: 1));
          unawaited(job.cancel());
          async.elapse(const Duration(hours: 1));
        });

        expect(stage.lines, isEmpty);
      });
    });

    test('the phase of a body: through the context, bare, inside a call', () {
      _says(
        'The phase says where the job is, not why. While the body runs, '
        'the phase is `body` whatever it waits on, and the engine does '
        'not guess',
      );
      fakeAsync((async) {
        final snapshots = <String>[];
        for (final body in <Future<void> Function(SoloContext<int, int> ctx)>[
          (ctx) => ctx.abandonable(() => stage.start<void>('op', null)),
          (ctx) => stage.start<void>('op', null),
          (ctx) => ctx.join(() => stage.start<void>('op', null)),
        ]) {
          final bench = Bench()..run<int, void>(key: 'slow', body);
          async.flushMicrotasks();
          snapshots.add('${bench.pending}');
          endCall(async, 'op');
        }

        expect(snapshots.toSet(), {'SoloPending([slow] in its body)'});
      });
    });

    test('a resource that takes its time to release', () {
      _says(
        'A resource that takes its time to release holds the job as long, '
        'and the phase is then `cleanup`',
      );
      runFaked((async) {
        Solo.observer = page.Hangs();
        Bench().run<int, void>(key: 'slow', (ctx) async {
          ctx.onDispose(() => stage.start<void>('release', null));
        });
        async.elapse(const Duration(seconds: 6));
        endCall(async, 'release');
      });

      expect(
        stage.lines,
        ['slow is still running: SoloPending([slow] in its cleanup)'],
      );
    });
  });

  group('Why cancellation was slow', () {
    group('the first attempt:', () {
      test('honest work and a job that ran on past its cancellation', () {
        _says(
          'A job that takes 300 ms because the work takes 300 ms reports the '
          'same line as one that was cancelled 10 ms in and ran to the end '
          'regardless',
        );
        late Job<void> honest;
        late Job<void> late_;
        runFaked((async) {
          Solo.observer = first.SlowJobs();
          final bench = Bench();
          honest = bench.run<int, void>(
            key: 'honest',
            (ctx) => ctx.abandonable(() => _delay(300)),
          );
          async.elapse(const Duration(seconds: 1));
          late_ = bench.run<int, void>(key: 'late', (ctx) => _delay(300))
            ..ignoreFailure();
          async.elapse(const Duration(milliseconds: 10));
          unawaited(late_.cancel());
          async.elapse(const Duration(seconds: 1));
        });

        expect(stage.lines, ['honest ran 300 ms', 'late ran 300 ms']);
        expect('${honest.outcome}', 'Done(null)');
        expect('${late_.outcome}', 'Cancelled(manual)');
      });

      test('a job quicker than 50 ms, and one dropped from the queue', () {
        runFaked((async) {
          Solo.observer = first.SlowJobs();
          final bench = Bench()
            ..run<int, void>(key: 'quick', (ctx) => _delay(40));
          final queued = bench.run<int, void>(key: 'queued', (ctx) async {});
          async.flushMicrotasks();
          unawaited(queued.cancel());
          async.elapse(const Duration(seconds: 1));
        });

        expect(stage.lines, isEmpty);
      });
    });

    group('stamping the cancellation:', () {
      final rows = _rows('| how the body waits | the number |');

      test('the three rows of the table', () {
        expect(rows, {
          '`await Future.delayed(...)`': '290 ms',
          '`ctx.abandonable(() => Future.delayed(...))`': '0 ms',
          '`ctx.pause(...)`': '0 ms',
        });
        _says('A 300 ms wait, cancelled 10 ms in');
      });

      test('a bare await of 300 ms, cancelled 10 ms in', () {
        _says(
          'A body that waits on something slow with a bare `await` notices '
          'the cancellation only when the wait is over',
        );
        runFaked((async) {
          Solo.observer = page.SlowCancellations();
          final job = Bench().run<int, void>(key: 'bare', (ctx) => _delay(300))
            ..ignoreFailure();
          async.elapse(const Duration(milliseconds: 10));
          unawaited(job.cancel());
          async.elapse(const Duration(seconds: 1));
        });

        final number = rows['`await Future.delayed(...)`'];
        expect(stage.lines, ['bare ran $number past its cancellation']);
      });

      test('the same wait through ctx.abandonable and as ctx.pause', () {
        _says(
          'The same call through `ctx.abandonable` stops waiting at once, '
          'and so does a delay written as `ctx.pause`',
        );
        _says(
          'Only the first row is a line in the log: the other two stay '
          'under the 50 ms where the observer starts to report',
        );
        final outcomes = <String>[];
        runFaked((async) {
          Solo.observer = page.SlowCancellations();
          for (final body in <Future<void> Function(SoloContext<int, int> ctx)>[
            (ctx) => ctx.abandonable(() => _delay(300)),
            (ctx) => ctx.pause(const Duration(milliseconds: 300)),
          ]) {
            final job = Bench().run<int, void>(key: 'waits', body)
              ..ignoreFailure();
            async.elapse(const Duration(milliseconds: 10));
            unawaited(job.cancel());
            async.flushMicrotasks();
            outcomes.add('${job.outcome}');
            async.elapse(const Duration(seconds: 1));
          }
        });

        expect(outcomes, ['Cancelled(manual)', 'Cancelled(manual)']);
        expect(stage.lines, isEmpty);
      });

      test('a job nobody cancelled, however long it runs', () {
        _says(
          'A job nobody cancelled is never stamped and never reported, '
          'however long it runs',
        );
        runFaked((async) {
          Solo.observer = page.SlowCancellations();
          Bench().run<int, void>(key: 'long', (ctx) => _delay(3000));
          async.elapse(const Duration(seconds: 5));
        });

        expect(stage.lines, isEmpty);
      });

      for (final call in ['cancel', 'close']) {
        test('a 100 ms section cancelled 10 ms in by $call()', () {
          _says(
            'A cancellation that comes while a `ctx.uncancellable` section is '
            'open is accepted when the section ends: a 100 ms section '
            'cancelled 10 ms in gives 0 ms, while the caller of `cancel` or '
            '`close` waited 90 ms',
          );
          Duration? waited;
          Duration? stamped;
          runFaked((async) {
            Solo.observer = page.SlowCancellations();
            final bench = Bench();
            final job = bench.run<int, void>(
              key: 'section',
              (ctx) => ctx.uncancellable(() => _delay(100)),
            )..ignoreFailure();
            async.elapse(const Duration(milliseconds: 10));
            final calledAt = clock.now();
            job.whenCancelled(
              (_) => stamped = clock.now().difference(calledAt),
            );
            (call == 'cancel' ? job.cancel() : bench.close()).then(
              (_) => waited = clock.now().difference(calledAt),
            );
            async.elapse(const Duration(seconds: 1));
          });

          expect(waited, const Duration(milliseconds: 90));
          expect(stamped, const Duration(milliseconds: 90));
          expect(stage.lines, isEmpty, reason: '0 ms past the cancellation');
        });
      }

      test('a job whose child and cleanup take time after it is cancelled', () {
        _says(
          'The number counts from the moment the job accepted the '
          'cancellation, not from `cancel()`, to the outcome, children '
          'and cleanup included',
        );
        runFaked((async) {
          Solo.observer = page.SlowCancellations();
          final bench = Bench();
          final job = bench.run<int, void>(key: 'root', (ctx) async {
            ctx.onDispose(() => _delay(200));
            ctx
                .run(
                  bench.job<int, void>(
                    key: 'child',
                    cancellable: false,
                    (child) => _delay(100),
                  ),
                )
                .ignore();
            await ctx.abandonable(() => _delay(1000));
          })
            ..ignoreFailure();
          async.elapse(const Duration(milliseconds: 10));
          unawaited(job.cancel());
          async.elapse(const Duration(seconds: 2));
        });

        // The child runs 90 ms more, and the cleanup 200 ms after it.
        expect(stage.lines, ['root ran 290 ms past its cancellation']);
      });

      test('a job cancelled before it started', () {
        _says(
          'A job cancelled before it started reports nothing. `onStart` '
          'never runs for it, so nothing was registered or stamped',
        );
        final started = <String>[];
        late Job<void> queued;
        late Job<void> refused;
        runFaked((async) {
          Solo.observer = SoloObserver.all([
            page.SlowCancellations(),
            Saying('observer', started),
          ]);
          final bench = Bench()
            ..run<int, void>(
              key: 'runs',
              (ctx) => ctx.abandonable(() => _delay(9)),
            );
          queued = bench.run<int, void>(key: 'queued', (ctx) => _delay(300));
          refused = bench.run<int, void>(
            key: 'refused',
            canStart: (state) => false,
            (ctx) => _delay(300),
          )..ignoreFailure();
          async.flushMicrotasks();
          unawaited(queued.cancel());
          async.elapse(const Duration(seconds: 1));
        });

        expect('${queued.outcome}', 'Cancelled(manual)');
        expect('${refused.outcome}', 'Cancelled(rules: canStart)');
        expect(
          started.where((hook) => hook == 'observer.onStart'),
          hasLength(1),
          reason: 'onStart came for the running job alone',
        );
        expect(stage.lines, isEmpty);
      });

      test('clock.now() and DateTime.now() under fake time', () {
        _says(
          'The observer reads `clock.now()` rather than `DateTime.now()`. '
          'Under `fake_async` the first moves with the fake time and the '
          'second stands still',
        );
        fakeAsync((async) {
          final byClock = clock.now();
          final byDateTime = DateTime.now();
          async.elapse(const Duration(milliseconds: 300));

          expect(
            clock.now().difference(byClock),
            const Duration(milliseconds: 300),
          );
          expect(
            DateTime.now().difference(byDateTime),
            lessThan(const Duration(milliseconds: 100)),
          );
        });
      });
    });

    group('a cancellation that never lands:', () {
      test('a job that ignores its cancellation, as the page quotes it', () {
        runFaked((async) {
          Solo.observer = page.StuckCancellations();
          final job = _ignores(Bench(), 'ignores')..ignoreFailure();
          async.elapse(const Duration(seconds: 1));
          unawaited(job.cancel());
          async.elapse(const Duration(seconds: 6));
          endCall(async, 'op');
        });

        expect(stage.lines, [_quoted()[2][0]]);
      });

      test('a job nobody cancelled, one that holds, one that stops', () {
        _says(
          'A job nobody cancelled arms nothing here, however long it runs',
        );
        _says(
          'A `ctx.uncancellable` section holds back a cancellation that '
          'comes while it is open, and `whenCancelled` fires when the '
          'section closes',
        );
        final timers = <int>[];
        runFaked((async) {
          Solo.observer = page.StuckCancellations();
          Bench().run<int, void>(
            key: 'never',
            (ctx) => stage.start<void>('never', null),
          );
          final holds = Bench().run<int, void>(
            key: 'holds',
            (ctx) => ctx.uncancellable(() => stage.start<void>('held', null)),
          )..ignoreFailure();
          final stops = waits(Bench(), 'stops')..ignoreFailure();
          async.elapse(const Duration(seconds: 1));
          timers.add(async.pendingTimers.length);
          unawaited(holds.cancel());
          unawaited(stops.cancel());
          async.flushMicrotasks();
          timers.add(async.pendingTimers.length);
          async.elapse(const Duration(seconds: 20));
          endCall(async, 'held');
          endCall(async, 'never');
        });

        expect(stage.lines, isEmpty);
        expect(timers, [0, 0], reason: 'the one that stopped disarmed its own');
      });

      test('the five seconds are counted from the close of the section', () {
        _says(
          'The five seconds count from there',
        );
        runFaked((async) {
          Solo.observer = page.StuckCancellations();
          final holds = Bench().run<int, void>(key: 'holds', (ctx) async {
            await ctx.uncancellable(() => stage.start<void>('held', null));
            await stage.start<void>('after', null);
          })
            ..ignoreFailure();
          async.elapse(const Duration(seconds: 1));
          unawaited(holds.cancel());
          async.elapse(const Duration(seconds: 20));
          expect(stage.lines, isEmpty);
          endCall(async, 'held');
          async.elapse(const Duration(seconds: 4));
          expect(stage.lines, isEmpty);
          async.elapse(const Duration(seconds: 2));
          endCall(async, 'after');
        });

        const holds =
            'SoloPending([holds] in its body, cancelled by Cancelled(manual))';
        expect(stage.lines, ['holds has not stopped: $holds']);
      });

      test('a child the cancellation passed to', () {
        _says(
          'A child the cancellation passed to gets a line of its own, and '
          'the snapshot in it is of the root again',
        );
        runFaked((async) {
          Solo.observer = page.StuckCancellations();
          final bench = Bench();
          final job = bench.run<int, void>(key: 'root', (ctx) async {
            await ctx.run(
              bench.job<int, void>(
                key: 'child',
                (child) => stage.start<void>('op', null),
              ),
            );
          })
            ..ignoreFailure();
          async.elapse(const Duration(seconds: 1));
          unawaited(job.cancel());
          async.elapse(const Duration(seconds: 6));
          endCall(async, 'op');
        });

        const root =
            'SoloPending([root] in its body, cancelled by Cancelled(manual))';
        expect(stage.lines, [
          'child has not stopped: $root',
          'root has not stopped: $root',
        ]);
      });
    });

    group('SoloObserver.all:', () {
      test('the four of the page under one', () {
        _says(
          '`Solo.observer` holds one observer, and this page has four to '
          'install by now',
        );
        final ran = runFaked((async) {
          page.installAll();
          final bare = Bench().run<int, void>(key: 'bare', (ctx) => _delay(300))
            ..ignoreFailure();
          final stuck = _ignores(Bench(), 'ignores')..ignoreFailure();
          async.elapse(const Duration(milliseconds: 10));
          unawaited(bare.cancel());
          unawaited(stuck.cancel());
          async.elapse(const Duration(seconds: 6));
          endCall(async, 'op');
        });

        const pending = 'SoloPending([ignores] in its body, cancelled by '
            'Cancelled(manual))';
        expect(stage.lines, [
          'bare ran 290 ms past its cancellation',
          'ignores is still running: $pending',
          'ignores has not stopped: $pending',
          'ignores ran 6000 ms past its cancellation',
        ]);
        expect(ran.printed, [
          'Job(bare) started',
          'Job(ignores) started',
          'Job(bare) finished Cancelled(manual)',
          'Job(ignores) finished Cancelled(manual)',
        ]);
      });

      test('three observers, and the first of them throws', () {
        _says(
          'Every hook goes to each of them in the order of the list, each '
          'call on its own. One that throws hands its error to the zone, '
          'and the next is called all the same',
        );
        final order = <String>[];
        final ran = runFaked((async) {
          Solo.observer = SoloObserver.all([
            Saying('first', order, throwOn: 'onStart'),
            Saying('second', order),
            Saying('third', order),
          ]);
          Bench().run<int, void>(key: 'job', (ctx) async {});
        });

        expect(order, [
          for (final hook in ['onCreate', 'onStart', 'onFinish'])
            for (final name in ['first', 'second', 'third']) '$name.$hook',
        ]);
        expect(ran.errors, ['first.onStart threw']);
      });

      test('the same observer twice in the list', () {
        _says(
          'If the same observer is in the list twice, `SoloObserver.all` '
          'throws `ArgumentError`',
        );
        final one = Watching();

        expect(
          () => SoloObserver.all([one, Watching(), one]),
          throwsArgumentError,
        );
        expect(
          () => SoloObserver.all([
            one,
            SoloObserver.all([one]),
          ]),
          throwsArgumentError,
          reason: 'counting the ones inside another list',
        );
      });
    });
  });

  group('The page', () {
    test('one section opens with a first attempt', () {
      expect(
        RegExp(r'^### The first attempt$', multiLine: true).allMatches(_page()),
        hasLength(1),
      );
    });

    test('has no fence the checks do not read', () {
      expect(strayFences('doc/diagnostics.md'), isEmpty);
    });

    // Each version under its own file: an answer turned into its own first
    // attempt would still be found among all of them.
    const answers = 'test/support/errors_page.dart';
    const attempts = 'test/support/errors_first_attempts.dart';
    const holders = {
      '## Logs': answers,
      '## Watching every controller': answers,
      '## What is holding the controller': answers,
      '### The first attempt': attempts,
      '### Stamping the cancellation': answers,
      '### A cancellation that never lands': answers,
    };
    for (final MapEntry(key: heading, value: holder) in holders.entries) {
      test('the code under "$heading" is a run of lines of $holder', () {
        expect(
          codeMissingFrom('doc/diagnostics.md', holder, under: heading),
          isEmpty,
        );
      });
    }

    test('every piece of code on the page is a run of lines of these files',
        () {
      expect(
        codeMissingFrom('doc/diagnostics.md', answers, alsoIn: [attempts]),
        isEmpty,
      );
    });

    test('every heading with code under it is held to a file', () {
      final withCode = [
        for (final part in _page().split(RegExp('^(?=#)', multiLine: true)))
          if (part.contains('```dart')) part.split('\n').first,
      ];
      expect(withCode.toSet(), holders.keys.toSet());
    });
  });
}

/// An observer that keeps what `onLog` was handed.
final class _Logs extends SoloObserver {
  final List<Object?> into;

  _Logs(this.into);

  @override
  void onLog(Solo<Object> solo, Job<Object?> job, Object? message) =>
      into.add(message);
}
