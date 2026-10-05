@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/children_first_attempts.dart' as first;
import 'support/children_page.dart' as page;
import 'support/children_stubs.dart';
import 'support/page_code.dart';

/// The sentinel of `doc/children.md`.
///
/// The code of the page stands verbatim in `test/support/children_*.dart`:
/// the first and second attempts in one file, the versions that work and the
/// block the page opens with in another. The tests below run that code and
/// pin what the prose and the comments of the page say about it. What the
/// page states of the engine and its code does not show is pinned on `Bench`,
/// a controller whose bodies are written where they are run.
///
/// Every call of a stub runs until the test ends it, so each trace is the
/// order the test set and no timer decides it. A test collects what it saw in
/// [_seen] and asserts once the zone it ran in has returned: an `expect` that
/// failed inside would be one more error of that zone.

/// What the test at hand saw, in order.
final _seen = <String>[];

/// Adds [line] to [_seen], one entry for each fact it names: the facts of a
/// line are set apart by `; `.
void _see(String line) => _seen.addAll(line.split('; '));

/// A job with a `>` for every level it stands under its root.
String _label(Job<Object?> job) =>
    '${'>' * job.level}${job.level == 0 ? '' : ' '}$job';

/// An observer that writes what it hears to [_seen].
final class _Watch extends SoloObserver {
  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      _see('${_label(job)} started');

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) =>
      _see('${_label(job)} finished ${job.outcome}');

  @override
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) =>
      _see('state ${transition.current} by ${transition.job}');
}

/// The lines of [_seen] that say a job started.
List<String> get _starts => [
      for (final line in _seen)
        if (line.endsWith(' started')) line,
    ];

String _page() => File('doc/children.md').readAsStringSync();

/// The page with every run of whitespace turned into one space, so that a
/// phrase is found wherever its lines were broken.
String _prose() => _page().replaceAll(RegExp(r'\s+'), ' ');

/// Holds the page to [phrase]: the test that calls this runs what the phrase
/// says, so a page that stops saying it leaves the test with nothing to
/// stand for.
void _says(String phrase) => expect(
      _prose(),
      contains(phrase),
      reason: 'doc/children.md no longer says this',
    );

/// What the page quotes under its `text` fences, in order.
List<String> _quotes() => [
      for (final block
          in RegExp(r'```text\n(.*?)\n```', dotAll: true).allMatches(_page()))
        block.group(1)!,
    ];

/// Runs [body] under fake time, in a zone of its own, and returns the errors
/// that reached that zone uncaught. Nothing is asserted inside: an `expect`
/// that failed in there would be one more error of the list.
List<String> _zone(void Function(FakeAsync async) body) {
  final errors = <String>[];
  fakeAsync((async) {
    runZonedGuarded(
      () => body(async),
      (error, stackTrace) => errors.add('$error'),
    );
    async.flushTimers();
  });

  return errors;
}

/// Ends [call] of a stub the way it would end on its own, and lets whatever
/// waited for it go on.
void _end(FakeAsync async, String call) {
  stage.end(call);
  async.flushMicrotasks();
}

/// Fails [call] of a stub with [error].
void _fail(FakeAsync async, String call, Object error) {
  stage.fail(call, error);
  async.flushMicrotasks();
}

/// How [job] stands: its outcome, or that it has none yet.
String _how(Job<Object?> job) => '${job.outcome ?? 'no outcome'}';

Future<void> _delay(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

Never _throwFromChild() => throw StateError('child failed');

/// A child whose body fails while it still waits for [window] — a child of
/// its own or its cleanup — under a parent that is cancelled afterwards.
/// [silence] is what the parent does about the child: nothing,
/// `child.ignore()` or `ctx.run(child).ignore()`.
Bench _coveredFailure(
  FakeAsync async,
  String window, {
  String silence = 'none',
}) {
  final bench = Bench();
  final parent = bench.run<Ready, void>(key: 'parent', (ctx) async {
    final child = bench.job<Ready, void>(key: 'child', (childCtx) async {
      if (window == 'a child of its own') {
        final grandchild = bench.job<Ready, void>(
          key: 'grandchild',
          (ctx) => ctx.abandonable(() => stage.start<void>('grandchild', null)),
        );
        childCtx.run(grandchild).ignore();
      } else {
        childCtx.onDispose(() => stage.start<void>('cleanup', null));
      }
      throw StateError('child failed first');
    });
    if (silence == 'child.ignore()') {
      child.ignore();
    }
    if (silence == 'ctx.run(child).ignore()') {
      ctx.run(child).ignore();
      await ctx.abandonable(() => stage.start<void>('parent step', null));
    } else {
      try {
        await ctx.run(child);
      } on Object catch (error) {
        _see('the parent body caught $error');
        rethrow;
      }
    }
  });
  async.flushMicrotasks();
  parent.cancel().ignore();
  async.flushMicrotasks();
  if (stage.isRunning('cleanup')) {
    _end(async, 'cleanup');
  }
  _see('parent ${_how(parent)}');

  return bench;
}

/// A controller that follows a session from a subscription of its own, and
/// queues a short job for each update.
final class _Queueing extends Solo<Screen> {
  final SoloStream<Session> session;
  late final StreamSubscription<Session> _link;

  _Queueing(this.session) : super(const Screen()) {
    _take(session.currentState);
    _link = session.stream.listen(_take);
  }

  void _take(Session next) => run<Screen, void>(
        key: 'take',
        (ctx) async => ctx.emit(ctx.state.copyWith(signedIn: next.signedIn)),
      );

  Job<void> other() => run<Screen, void>(
        key: 'other',
        (ctx) => ctx.join(() => stage.start<void>('other', null)),
      );

  @override
  void onClose() => unawaited(_link.cancel());
}

/// A controller that follows a session from a subscription of its own, and
/// writes each update with `externalSetState`.
final class _Reflecting extends Solo<Screen> {
  final SoloStream<Session> session;
  late final StreamSubscription<Session> _link;

  _Reflecting(this.session)
      : super(Screen(signedIn: session.currentState.signedIn)) {
    _link = session.stream.listen(
      (next) => externalSetState(
        currentState.copyWith(signedIn: next.signedIn),
      ),
    );
  }

  Job<void> other() => run<Screen, void>(
        key: 'other',
        (ctx) => ctx.join(() => stage.start<void>('other', null)),
      );

  @override
  void onClose() => unawaited(_link.cancel());
}

/// An observer of the core that keeps what `onError` told it.
final class _Own extends JobObserver {
  final heard = <String>[];

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      heard.add('$job: $error');
}

void main() {
  setUp(() {
    stage = Stage();
    _seen.clear();
  });

  tearDown(() {
    stage.dispose();
    Solo.observer = null;
    Solo.errorHandler = null;
  });

  group('The opening block', () {
    test('job(...) makes a job and starts nothing', () {
      final errors = _zone((async) {
        final solo = page.Syncer();
        final made = solo.made(1);
        async.elapse(const Duration(seconds: 10));
        _see('queued ${made.isQueued}, running ${made.isRunning}, '
            'outcome ${made.outcome}, current ${solo.current}');
      });

      expect(errors, isEmpty);
      expect(
        _seen,
        ['queued false, running false, outcome null, current null'],
      );
      expect(stage.trace, isEmpty);
      _says('`job(...)` makes a job and starts nothing.');
    });

    test('add gives that very job a place in the queue', () {
      final errors = _zone((async) {
        final solo = page.Syncer();
        final made = solo.made(1);
        final added = solo.add(made);
        _see('the same handle ${identical(added, made)}, '
            'queued ${made.isQueued}');
        async.flushMicrotasks();
        _see('running ${made.isRunning}, current ${solo.current}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'the same handle true, queued true',
        'running true, current Job(_Op.sync)',
      ]);
      _says('`add` gives it a place in the queue');
    });

    test('both children start at once, past a job that waits in the queue', () {
      final errors = _zone((async) {
        Solo.observer = _Watch();
        final solo = page.Syncer()..sync(1);
        final save = solo.save();
        async.flushMicrotasks();
        _see('save queued ${save.isQueued}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'Job(_Op.sync) started',
        '> Job(each) started',
        '> Job(_Op.upload) started',
        'save queued true',
      ]);
      expect(stage.trace, ['push 1 start']);
      _says('A child starts immediately, bypassing the queue');
    });

    test('the progress goes into the state as it comes, written by the child',
        () {
      final errors = _zone((async) {
        final solo = page.Syncer()..sync(1);
        async.flushMicrotasks();
        Solo.observer = _Watch();
        stage.progress
          ..add(40)
          ..add(70);
        async.flushMicrotasks();
        _see('${solo.currentState}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'state Ready(sent: 40, position: 0, path: ) by Job(each)',
        'state Ready(sent: 70, position: 0, path: ) by Job(each)',
        'Ready(sent: 70, position: 0, path: )',
      ]);
    });

    test(
        'sync is over once the upload has returned and the API has closed '
        'the progress', () {
      final errors = _zone((async) {
        final solo = page.Syncer();
        final job = solo.sync(1);
        final save = solo.save();
        Object? got;
        job.value.then<void>((path) => got = path);
        async.flushMicrotasks();
        _end(async, 'push 1');
        async.elapse(const Duration(hours: 1));
        _see('the upload returned: sync ${_how(job)}; the caller got $got; '
            'save queued ${save.isQueued}');
        unawaited(stage.progress.close());
        async.flushMicrotasks();
        _see('the progress closed: sync ${_how(job)}; the caller got $got; '
            'save queued ${save.isQueued}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'the upload returned: sync no outcome',
        'the caller got null',
        'save queued true',
        'the progress closed: sync Done(path/1)',
        'the caller got path/1',
        'save queued false',
      ]);
      expect(stage.trace, ['push 1 start', 'push 1 end', 'save start']);
      _says('The parent keeps the queue occupied until all its children '
          'finish, even if its body returns earlier');
      _says('`sync` is over once the upload has returned its path and the '
          'API has closed the progress');
    });

    test('the progress may close first: sync is over with the upload', () {
      final errors = _zone((async) {
        final job = page.Syncer().sync(1);
        async.flushMicrotasks();
        unawaited(stage.progress.close());
        async.flushMicrotasks();
        _see('the progress closed: sync ${_how(job)}');
        _end(async, 'push 1');
        _see('the upload returned: sync ${_how(job)}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'the progress closed: sync no outcome',
        'the upload returned: sync Done(path/1)',
      ]);
    });

    test('cancelling the parent cancels the stream child and the upload', () {
      final errors = _zone((async) {
        Solo.observer = _Watch();
        final job = page.Syncer().sync(1);
        async.flushMicrotasks();
        _seen.clear();
        job.cancel().ignore();
        async.flushMicrotasks();
        _see('listening ${stage.progress.hasListener}');
        _end(async, 'push 1');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        '> Job(each) finished Cancelled(parent)',
        'listening false',
        '> Job(_Op.upload) finished Cancelled(parent)',
        'Job(_Op.sync) finished Cancelled(manual)',
      ]);
    });

    test('an upload that fails leaves sync waiting for the progress to close',
        () {
      final errors = _zone((async) {
        final job = page.Syncer().sync(1)..ignore();
        async.flushMicrotasks();
        _fail(async, 'push 1', StateError('push failed'));
        _see('the upload failed: sync ${_how(job)}');
        unawaited(stage.progress.close());
        async.flushMicrotasks();
        _see('the progress closed: sync ${_how(job)}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'the upload failed: sync no outcome',
        'the progress closed: sync Failed(Bad state: push failed)',
      ]);
    });
  });

  group('A child of ctx.run', () {
    for (final rule in ['canStart', 'keepWhile', 'the working type']) {
      test('a child turned away by $rule never runs', () {
        late Job<void> child;
        final errors = _zone((async) {
          Solo.observer = _Watch();
          final bench = Bench(const Ready(paused: true));
          bench.run<Ready, void>(key: 'parent', (ctx) async {
            child = switch (rule) {
              'canStart' => bench.job<Ready, void>(
                  key: 'child',
                  canStart: (state) => !state.paused,
                  (childCtx) async => _see('the child ran'),
                ),
              'keepWhile' => bench.job<Ready, void>(
                  key: 'child',
                  keepWhile: (state) => !state.paused,
                  (childCtx) async => _see('the child ran'),
                ),
              _ => bench.job<Off, void>(
                  key: 'child',
                  (childCtx) async => _see('the child ran'),
                ),
            };
            try {
              await ctx.run(child);
            } on Cancelled catch (cancelled) {
              _see('ctx.run threw $cancelled, started ${cancelled.started}');
            }
            _see('the parent goes on');
          });
          async.flushMicrotasks();
        });

        final reason = rule == 'the working type' ? 'is not Off' : rule;
        expect(errors, isEmpty);
        expect(_seen, [
          'Job(parent) started',
          '> Job(child) finished Cancelled(rules: $reason)',
          'ctx.run threw Cancelled(rules: $reason), started false',
          'the parent goes on',
          'Job(parent) finished Done(null)',
        ]);
        expect(
          (child.outcome! as Cancelled).reason,
          isA<RulesCancelReason>(),
        );
        expect(child.isChild, isTrue);
        expect(child.level, 1);
        _says('subject to its own start rules: its working type, `canStart` '
            'and `keepWhile`');
        _says('A child the start rules turn away never runs. It is adopted '
            'first — parent and level — and only then finished `Cancelled` '
            'with a `RulesCancelReason`');
        _says('the observer hears the drop as an outcome of this tree, with '
            '`job.level` telling it how deep under the parent the job '
            'stands');
      });
    }

    test('child.done of a child turned away holds the cancellation', () {
      final errors = _zone((async) {
        final bench = Bench(const Ready(paused: true));
        bench.run<Ready, void>(key: 'parent', (ctx) async {
          final child = bench.job<Ready, void>(
            key: 'child',
            canStart: (state) => !state.paused,
            (childCtx) async {},
          );
          ctx.run(child).ignore();
          _see('done gave ${await child.done}');
        });
        async.flushMicrotasks();
      });

      expect(errors, isEmpty);
      expect(_seen, ['done gave Cancelled(rules: canStart)']);
      _says('`child.done` holds the cancellation');
    });

    test(
        'a child turned away joins no waiting list, and the future of run '
        'carries the drop', () {
      final errors = _zone((async) {
        final bench = Bench(const Ready(paused: true));
        final parent = bench.run<Ready, void>(key: 'parent', (ctx) async {
          final child = bench.job<Ready, void>(
            key: 'child',
            canStart: (state) => !state.paused,
            (childCtx) async {},
          );
          unawaited(
            ctx.run(child).then<void>(
                  (_) => _see('the future gave a value'),
                  onError: (Object error) => _see('the future threw $error'),
                ),
          );
        });
        async.flushMicrotasks();
        _see('parent ${_how(parent)}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'the future threw Cancelled(rules: canStart)',
        'parent Done(null)',
      ]);
      _says('It joins no waiting list, so the parent waits for nothing; the '
          'future of `ctx.run` carries that cancellation all the same.');
    });

    for (final rule in ['canStart', 'keepWhile']) {
      test('a $rule that throws ends the child Failed, and ctx.run throws', () {
        late Job<void> child;
        late Bench bench;
        final errors = _zone((async) {
          bench = Bench();
          bench.run<Ready, void>(key: 'parent', (ctx) async {
            bool thrower(Ready state) => throw StateError('$rule threw');
            child = bench.job<Ready, void>(
              key: 'child',
              canStart: rule == 'canStart' ? thrower : null,
              keepWhile: rule == 'keepWhile' ? thrower : null,
              (childCtx) async => _see('the child ran'),
            );
            var pastTheCall = false;
            try {
              final future = ctx.run(child);
              pastTheCall = true;
              await future;
            } on Object catch (error) {
              _see('caught $error, the line after the call ran $pastTheCall');
            }
          });
          async.flushMicrotasks();
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'caught Bad state: $rule threw, the line after the call ran false',
        ]);
        expect('${child.outcome}', 'Failed(Bad state: $rule threw)');
        expect(bench.heard, ['Job(child): Bad state: $rule threw']);
        _says("The error is the rule's own, the child ends `Failed` with "
            'it, and `ctx.run` throws it synchronously — the line after the '
            'call never runs.');
      });
    }

    test('ctx.run waits for the child, its children and its cleanup', () {
      final errors = _zone((async) {
        final bench = Bench();
        bench.run<Ready, void>(key: 'parent', (ctx) async {
          final child = bench.job<Ready, int>(key: 'child', (childCtx) async {
            childCtx.onDispose(() => stage.start<void>('cleanup', null));
            final grandchild = bench.job<Ready, void>(
              key: 'grandchild',
              (ctx) => ctx.join(() => stage.start<void>('grandchild', null)),
            );
            childCtx.run(grandchild).ignore();

            return 7;
          });
          stage.trace.add('run returned ${await ctx.run(child)}');
        });
        async.flushMicrotasks();
        _see('the body of the child returned: ${stage.trace}');
        _end(async, 'grandchild');
        _see('its child ended: ${stage.trace}');
        _end(async, 'cleanup');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'the body of the child returned: [grandchild start]',
        'its child ended: [grandchild start, grandchild end, cleanup start]',
      ]);
      expect(stage.trace.last, 'run returned 7');
      _says("It waits for the child, the child's children and cleanup.");
    });

    test('after a child that succeeds, ctx.run throws the parent cancellation',
        () {
      late Job<int> child;
      final errors = _zone((async) {
        final bench = Bench();
        final parent = bench.run<Ready, void>(key: 'parent', (ctx) async {
          child = bench.job<Ready, int>(
            key: 'child',
            cancellable: false,
            (childCtx) async {
              await childCtx.join(() => stage.start<void>('work', null));

              return 7;
            },
          );
          try {
            _see('ctx.run returned ${await ctx.run(child)}');
          } on Cancelled catch (cancelled) {
            _see('ctx.run threw $cancelled');
            rethrow;
          }
        });
        async.flushMicrotasks();
        parent.cancel().ignore();
        async.flushMicrotasks();
        _see('cancelled: parent ${_how(parent)}, child ${_how(child)}');
        _end(async, 'work');
        _see('parent ${_how(parent)}, child ${_how(child)}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'cancelled: parent no outcome, child no outcome',
        'ctx.run threw Cancelled(manual)',
        'parent Cancelled(manual), child Done(7)',
      ]);
      _says("On success, it checks the parent's cancellation and state "
          'rules before returning the value');
    });

    test('a value registered on the call is released when ctx.run throws', () {
      final errors = _zone((async) {
        final bench = Bench();
        final parent = bench.run<Ready, void>(key: 'parent', (ctx) async {
          final child = bench.job<Ready, String>(
            key: 'child',
            cancellable: false,
            (childCtx) => childCtx.join(() => stage.start('open', 'handle')),
          );
          final handle = await ctx.run(
            child,
            dispose: (handle) => _see('released $handle'),
          );
          _see('the line after the call ran with $handle');
        });
        async.flushMicrotasks();
        parent.cancel().ignore();
        async.flushMicrotasks();
        _end(async, 'open');
        _see('parent ${_how(parent)}');
      });

      expect(errors, isEmpty);
      expect(_seen, ['released handle', 'parent Cancelled(manual)']);
      _says('so a value the parent has to release is registered on the call, '
          '`ctx.run(child, dispose: ...)`, and not on the line after it');
    });

    test('after a child that succeeds, ctx.run checks the rules of the parent',
        () {
      final errors = _zone((async) {
        final bench = Bench();
        final parent = bench.run<Ready, void>(key: 'parent', (ctx) async {
          // The job that wrote a state is not asked about it at once.
          ctx.emit(const Off());
          final child = bench.job<AppState, int>(
            key: 'child',
            (childCtx) async => 7,
          );
          try {
            _see('ctx.run returned ${await ctx.run(child)}');
          } on Cancelled catch (cancelled) {
            _see('ctx.run threw $cancelled');
            rethrow;
          }
        });
        async.flushMicrotasks();
        _see('parent ${_how(parent)}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'ctx.run threw Cancelled(rules: is not Ready)',
        'parent Cancelled(rules: is not Ready)',
      ]);
    });

    test('a child error comes into the parent body with its stack trace', () {
      late Bench bench;
      final errors = _zone((async) {
        bench = Bench();
        final parent = bench.run<Ready, void>(key: 'parent', (ctx) async {
          final child = bench.job<Ready, int>(
            key: 'child',
            (childCtx) async => _throwFromChild(),
          );
          try {
            await ctx.run(child);
          } on Object catch (error, stackTrace) {
            _see('caught $error, the trace names the throw: '
                '${'$stackTrace'.contains('_throwFromChild')}');
          }
        });
        async.flushMicrotasks();
        _see('parent ${_how(parent)}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'caught Bad state: child failed, the trace names the throw: true',
        'parent Done(null)',
      ]);
      expect(bench.heard, ['Job(child): Bad state: child failed']);
      _says('A child error or cancellation is thrown into the parent body '
          'with its stack trace.');
    });

    test('a child cancellation comes into the parent body', () {
      late Job<void> parent;
      final errors = _zone((async) {
        final bench = Bench();
        late Job<void> child;
        parent = bench.run<Ready, void>(key: 'parent', (ctx) async {
          child = bench.job<Ready, void>(
            key: 'child',
            (childCtx) =>
                childCtx.abandonable(() => stage.start<void>('work', null)),
          );
          try {
            await ctx.run(child);
          } on Cancelled catch (cancelled) {
            _see('caught $cancelled, the parent cancelled '
                '${ctx.job.isCancelled}');
            rethrow;
          }
        });
        async.flushMicrotasks();
        child.cancel().ignore();
        async.flushMicrotasks();
      });

      expect(errors, isEmpty);
      expect(_seen, ['caught Cancelled(manual), the parent cancelled false']);
      expect(
        '${parent.outcome}',
        'Cancelled(handler: child child: Cancelled(manual))',
      );
      expect(
        (parent.outcome! as Cancelled).reason,
        isA<HandlerCancelReason>(),
      );
    });

    test('a parent that works beside its child: their writes interleave', () {
      final errors = _zone((async) {
        Solo.observer = _Watch();
        final bench = Bench();
        bench.run<Ready, void>(key: 'parent', (ctx) async {
          final child = bench.job<Ready, void>(key: 'child', (childCtx) async {
            childCtx.emit(childCtx.state.copyWith(sent: 1));
            await childCtx.join(() => stage.start<void>('child step', null));
            childCtx.emit(childCtx.state.copyWith(sent: 2));
          });
          final running = ctx.run(child);
          ctx.emit(ctx.state.copyWith(position: 1));
          await ctx.join(() => stage.start<void>('parent step', null));
          ctx.emit(ctx.state.copyWith(position: 2));
          await running;
        });
        async.flushMicrotasks();
        _end(async, 'parent step');
        _end(async, 'child step');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'Job(parent) started',
        '> Job(child) started',
        'state Ready(sent: 1, position: 0, path: ) by Job(child)',
        'state Ready(sent: 1, position: 1, path: ) by Job(parent)',
        'state Ready(sent: 1, position: 2, path: ) by Job(parent)',
        'state Ready(sent: 2, position: 2, path: ) by Job(child)',
        '> Job(child) finished Done(null)',
        'Job(parent) finished Done(null)',
      ]);
      _says('To work in the parent while a child runs, keep the future '
          '`ctx.run` returned and await it later. The state writes of the '
          'two can then interleave');
    });

    for (final rule in ['the working type', 'keepWhile']) {
      test('a write of the child that $rule of the parent refuses', () {
        final errors = _zone((async) {
          final bench = Bench();
          late Job<void> child;
          final parent = bench.run<Ready, void>(
            key: 'parent',
            keepWhile: (state) => !state.paused,
            (ctx) async {
              child = bench.job<AppState, void>(
                key: 'child',
                (childCtx) async {
                  await childCtx.join(() => stage.start<void>('work', null));
                  childCtx.emit(
                    rule == 'keepWhile'
                        ? const Ready(paused: true)
                        : const Off(),
                  );
                  _see('the child went on past its write');
                },
              );
              await ctx.run(child);
            },
          );
          async.flushMicrotasks();
          _end(async, 'work');
          _see('parent ${_how(parent)}, child ${_how(child)}');
        });

        final reason = rule == 'keepWhile' ? 'keepWhile' : 'is not Ready';
        expect(errors, isEmpty);
        expect(_seen, [
          'parent Cancelled(rules: $reason), child Cancelled(parent)',
        ]);
        _says("a write of the child that the parent's working type or "
            '`keepWhile` does not accept cancels the parent, and the child '
            'with it');
      });
    }

    test('a write of the parent that the rules of the child refuse', () {
      final errors = _zone((async) {
        final bench = Bench();
        late Job<void> child;
        final parent = bench.run<AppState, void>(key: 'parent', (ctx) async {
          child = bench.job<Ready, void>(
            key: 'child',
            (childCtx) =>
                childCtx.abandonable(() => stage.start<void>('work', null)),
          );
          final running = ctx.run(child);
          ctx.emit(const Off());
          try {
            await running;
          } on Cancelled catch (cancelled) {
            _see('the future of run threw $cancelled');
          }
        });
        async.flushMicrotasks();
        _see('parent ${_how(parent)}, child ${_how(child)}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'the future of run threw Cancelled(rules: is not Ready)',
        'parent Done(null), child Cancelled(rules: is not Ready)',
      ]);
      _says('each job answers to its own rules for every one of them');
    });

    for (final window in ['a child of its own', 'its cleanup']) {
      group(
          'a child fails, and a cancellation arrives while it waits for '
          '$window', () {
        test(
            'the parent body catches Cancelled, and the error goes to '
            'onUnanswered and the zone', () {
          late Bench bench;
          final errors = _zone((async) {
            bench = _coveredFailure(async, window);
          });

          expect(_seen, [
            'the parent body caught Cancelled(parent)',
            'parent Cancelled(manual)',
          ]);
          expect(bench.heard, ['Job(child): Bad state: child failed first']);
          expect(
            bench.unanswered,
            ['Job(child): Bad state: child failed first'],
          );
          expect(errors, ['Bad state: child failed first']);
          _says('The child ends `Cancelled`, `await ctx.run(child)` throws '
              "`Cancelled`, and the error goes to the controller's "
              '`onUnanswered`');
        });

        test('with Solo.errorHandler set, the error goes there', () {
          final handled = <String>[];
          late Bench bench;
          final errors = _zone((async) {
            Solo.errorHandler =
                (solo, job, error, stackTrace) => handled.add('$job: $error');
            bench = _coveredFailure(async, window);
          });

          expect(handled, ['Job(child): Bad state: child failed first']);
          expect(
            bench.unanswered,
            ['Job(child): Bad state: child failed first'],
          );
          expect(errors, isEmpty);
          _says('by default to `Solo.errorHandler`, or to the zone without '
              'one');
        });

        test('child.ignore() silences it', () {
          late Bench bench;
          final errors = _zone((async) {
            bench = _coveredFailure(async, window, silence: 'child.ignore()');
          });

          expect(bench.heard, ['Job(child): Bad state: child failed first']);
          expect(bench.unanswered, isEmpty);
          expect(errors, isEmpty);
          _says('`child.ignore()` silences it.');
        });

        test('ctx.run(child).ignore() does not', () {
          late Bench bench;
          final errors = _zone((async) {
            bench = _coveredFailure(
              async,
              window,
              silence: 'ctx.run(child).ignore()',
            );
          });

          expect(_seen, ['parent Cancelled(manual)']);
          expect(
            bench.unanswered,
            ['Job(child): Bad state: child failed first'],
          );
          expect(errors, ['Bad state: child failed first']);
          _says('`ctx.run(child).ignore()` does not: it handles what the '
              'future throws, and the future throws the cancellation.');
        });
      });
    }

    group('what the page leaves to the core', () {
      test('a cancellation the parent accepts passes to its children', () {
        final errors = _zone((async) {
          final bench = Bench();
          late Job<void> child;
          final parent = bench.run<Ready, void>(key: 'parent', (ctx) async {
            child = bench.job<Ready, void>(
              key: 'child',
              (childCtx) =>
                  childCtx.abandonable(() => stage.start<void>('work', null)),
            );
            await ctx.run(child);
          });
          async.flushMicrotasks();
          parent.cancel().ignore();
          async.flushMicrotasks();
          _see('parent ${_how(parent)}, child ${_how(child)}');
        });

        expect(errors, isEmpty);
        expect(_seen, ['parent Cancelled(manual), child Cancelled(parent)']);
        _says('a cancellation the parent accepts passes to its children');
      });

      test('a body that fails lets its children finish and waits for them', () {
        final errors = _zone((async) {
          final bench = Bench();
          late Job<void> child;
          final parent = bench.run<Ready, void>(key: 'parent', (ctx) async {
            child = bench.job<Ready, void>(
              key: 'child',
              (childCtx) =>
                  childCtx.abandonable(() => stage.start<void>('work', null)),
            );
            ctx.run(child).ignore();
            throw StateError('parent failed');
          })
            ..ignore();
          async.flushMicrotasks();
          _see('the body failed: parent ${_how(parent)}, '
              'child ${_how(child)}');
          _end(async, 'work');
          _see('parent ${_how(parent)}, child ${_how(child)}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'the body failed: parent no outcome, child no outcome',
          'parent Failed(Bad state: parent failed), child Done(null)',
        ]);
        _says('a body that fails lets them finish and waits for them');
      });

      for (final silence in ['child.ignore()', 'ctx.run(child).ignore()']) {
        test('a child that fails under $silence', () {
          final errors = _zone((async) {
            final bench = Bench();
            bench.run<Ready, void>(key: 'parent', (ctx) async {
              final child = bench.job<Ready, void>(
                key: 'child',
                (childCtx) =>
                    childCtx.join(() => stage.start<void>('work', null)),
              );
              if (silence == 'child.ignore()') {
                child.ignore();
                unawaited(ctx.run(child));
              } else {
                ctx.run(child).ignore();
              }
            });
            async.flushMicrotasks();
            _fail(async, 'work', StateError('child failed'));
          });

          expect(
            errors,
            silence == 'child.ignore()' ? ['Bad state: child failed'] : isEmpty,
          );
          _says('`child.ignore()` alone does not handle errors of the '
              'future returned by `run`.');
          _says("`ctx.run(child).ignore()` explicitly ignores that future's "
              'result while the parent still waits for its children.');
        });
      }

      test('ctx.runAll takes jobs made by job(...)', () {
        final errors = _zone((async) {
          final bench = Bench();
          final parent = bench.run<Ready, List<int>>(
            key: 'parent',
            (ctx) => ctx.runAll([
              bench.job<Ready, int>(key: 'a', (childCtx) async {
                await childCtx.join(() => stage.start<void>('a', null));

                return 1;
              }),
              bench.job<Ready, int>(key: 'b', (childCtx) async {
                await childCtx.join(() => stage.start<void>('b', null));

                return 2;
              }),
            ]),
          );
          async.flushMicrotasks();
          _see('${stage.trace}');
          _end(async, 'b');
          _end(async, 'a');
          _see('parent ${_how(parent)}');
        });

        expect(errors, isEmpty);
        expect(_seen, ['[a start, b start]', 'parent Done([1, 2])']);
        _says('Several children side by side are a group of `ctx.runAll`');
      });

      test('a branch of a group answers to its start rules', () {
        final errors = _zone((async) {
          Solo.observer = _Watch();
          final bench = Bench(const Ready(paused: true));
          bench.run<Ready, List<int>>(
            key: 'parent',
            (ctx) => ctx.runAll([
              bench.job<Ready, int>(key: 'a', (childCtx) async {
                await childCtx.abandonable(() => stage.start<void>('a', null));

                return 1;
              }),
              bench.job<Ready, int>(
                key: 'b',
                canStart: (state) => !state.paused,
                (childCtx) async => 2,
              ),
            ]),
          );
          async.flushMicrotasks();
        });

        expect(errors, isEmpty);
        expect(_seen.take(4), [
          'Job(parent) started',
          '> Job(a) started',
          '> Job(b) finished Cancelled(rules: canStart)',
          '> Job(a) finished Cancelled(sibling)',
        ]);
        expect(
          _seen.skip(4).single,
          'Job(parent) finished '
          'Cancelled(handler: child b: Cancelled(rules: canStart))',
        );
        _says('each branch of a group answers to its start rules as a child '
            'of `ctx.run` does');
      });

      for (final call in ['ctx.run', 'ctx.runAll']) {
        test('$call takes no Job.deferred', () {
          final errors = _zone((async) {
            Bench().run<Ready, void>(key: 'parent', (ctx) async {
              final deferred = Job.deferred<int>((ctx) async => 1);
              try {
                if (call == 'ctx.run') {
                  await ctx.run(deferred);
                } else {
                  await ctx.runAll([deferred]);
                }
              } on Object catch (error) {
                _see('$error');
              }
            });
            async.flushMicrotasks();
          });

          expect(errors, isEmpty);
          expect(_seen, [
            'Invalid argument (job): was not created by this Solo: "Job()"',
          ]);
          _says('Where that page makes a child with `Job.deferred`, a '
              'controller makes it with `job(...)`: its `ctx.run` and '
              '`ctx.runAll` take no other job');
        });
      }
    });
  });

  group('Processing a stream', () {
    group('the first attempt', () {
      test('the job is over before the first position, and the queue moves on',
          () {
        final errors = _zone((async) {
          final solo = first.Listening();
          final job = solo.track();
          final next = solo.run<Ready, void>(key: 'next', (ctx) async {});
          async.flushMicrotasks();
          _see('track ${_how(job)}, next ${_how(next)}, '
              'listening ${stage.positions.hasListener}');
        });

        expect(errors, isEmpty);
        expect(_seen, ['track Done(null), next Done(null), listening true']);
        _says('The body subscribes and returns, so the job is over before '
            'the first position arrives, and the queue moves on.');
      });

      test('each position throws out of emit into the zone', () {
        final errors = _zone((async) {
          final solo = first.Listening()..track();
          async.flushMicrotasks();
          stage.positions
            ..add(1)
            ..add(2);
          async.flushMicrotasks();
          _see('${solo.currentState}');
        });

        expect(_seen, ['Ready(sent: 0, position: 0, path: )']);
        expect(errors, [_quotes().first, _quotes().first]);
        expect(
          _quotes().first,
          'Bad state: Job(track) has already finished, cannot emit',
        );
        _says('Each position it delivers throws out of `emit` into the zone, '
            'and the state never changes:');
      });

      test('close() leaves the subscription where it is', () {
        final errors = _zone((async) {
          final solo = first.Listening()..track();
          async.flushMicrotasks();
          var closed = false;
          solo.close().then((_) => closed = true);
          async.flushMicrotasks();
          _see('closed $closed, listening ${stage.positions.hasListener}');
          stage.positions.add(1);
          async.flushMicrotasks();
        });

        expect(_seen, ['closed true, listening true']);
        expect(errors, [_quotes().first]);
        _says('Nothing ends that subscription either: there is no job left '
            'to cancel, and `close()` knows nothing of it.');
      });
    });

    test('onDispose(sub.cancel) ends the subscription with the body', () {
      final errors = _zone((async) {
        final bench = Bench();
        final job = bench.run<Ready, void>(key: 'track', (ctx) async {
          final sub = hw.positions.listen(
            (p) => ctx.emit(ctx.state.copyWith(position: p)),
          );
          ctx.onDispose(sub.cancel);
        });
        async.flushMicrotasks();
        _see('track ${_how(job)}, listening ${stage.positions.hasListener}');
        stage.positions.add(1);
        async.flushMicrotasks();
        _see('${bench.currentState}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'track Done(null), listening false',
        'Ready(sent: 0, position: 0, path: )',
      ]);
      _says('Registering `sub.cancel` with `ctx.onDispose` does not repair '
          'that: the cleanup runs as soon as the body returns, and the '
          'subscription is gone before the first position.');
    });

    group('a child that owns the subscription', () {
      test('positions go into the state, written by the child', () {
        final errors = _zone((async) {
          Solo.observer = _Watch();
          final solo = page.Syncer()..track();
          async.flushMicrotasks();
          stage.positions
            ..add(1)
            ..add(2);
          async.flushMicrotasks();
          _see('${solo.currentState}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'Job(track) started',
          '> Job(each) started',
          'state Ready(sent: 0, position: 1, path: ) by Job(each)',
          'state Ready(sent: 0, position: 2, path: ) by Job(each)',
          'Ready(sent: 0, position: 2, path: )',
        ]);
        _says('Observers see it as a separate job, `Job(each)`.');
      });

      test('the callback gets a SoloContext, and the child is a SoloJob', () {
        final errors = _zone((async) {
          Bench().run<Ready, void>(key: 'track', (ctx) async {
            final child = ctx.each(hw.positions, (childCtx, p) {
              // `state` is a member of `SoloContext` alone.
              _see('the job of that context is ${childCtx.job}; '
                  'its state is ${childCtx.state}');
            });
            _see('SoloJob ${child is SoloJob}, child ${child.isChild}, '
                'level ${child.level}, key ${child.key}, '
                'describe ${child.describe()}');
          });
          async.flushMicrotasks();
          stage.positions.add(1);
          async.flushMicrotasks();
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'SoloJob true, child true, level 1, key null, describe each',
          'the job of that context is Job(each)',
          'its state is Ready(sent: 0, position: 0, path: )',
        ]);
        _says("Each event callback receives that child's context.");
      });

      test('the job ends when the source sends onDone', () {
        final errors = _zone((async) {
          final job = page.Syncer().track();
          async.elapse(const Duration(hours: 1));
          _see('an hour later: track ${_how(job)}');
          unawaited(stage.positions.close());
          async.flushMicrotasks();
          _see('the source is done: track ${_how(job)}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'an hour later: track no outcome',
          'the source is done: track Done(null)',
        ]);
        _says('The child ends when the source sends `onDone`');
      });

      test('value brings a stream error into the parent body', () {
        late page.Syncer solo;
        final errors = _zone((async) {
          solo = page.Syncer();
          final job = solo.track()..ignore();
          async.flushMicrotasks();
          stage.positions.addError(StateError('hardware broke'));
          async.flushMicrotasks();
          _see('track ${_how(job)}, '
              'listening ${stage.positions.hasListener}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'track Failed(Bad state: hardware broke), listening false',
        ]);
        expect(solo.heard, [
          'Job(each): Bad state: hardware broke',
          'Job(track): Bad state: hardware broke',
        ]);
        _says("Returning the child's `.value` makes stream and callback "
            'errors propagate into the parent body.');
      });

      test('value brings a callback error into the parent body', () {
        final errors = _zone((async) {
          final bench = Bench();
          final job = bench.run<Ready, void>(
            key: 'track',
            (ctx) => ctx.each(hw.positions, (childCtx, p) {
              if (p == 2) {
                throw StateError('callback failed');
              }
              childCtx.emit(childCtx.state.copyWith(position: p));
            }).value,
          )..ignore();
          async.flushMicrotasks();
          stage.positions
            ..add(1)
            ..add(2)
            ..add(3);
          async.flushMicrotasks();
          _see('track ${_how(job)}; state ${bench.currentState}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'track Failed(Bad state: callback failed)',
          'state Ready(sent: 0, position: 1, path: )',
        ]);
      });

      test('done gives the outcome, and cancel() stops this subscription alone',
          () {
        final errors = _zone((async) {
          final bench = Bench();
          late Job<void> following;
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            following = ctx.each(hw.positions, (childCtx, p) {});
            _see('done gave ${await following.done}, the parent is cancelled '
                '${ctx.job.isCancelled}');
            await ctx.join(() => stage.start<void>('more', null));
          });
          async.flushMicrotasks();
          following.cancel().ignore();
          async.flushMicrotasks();
          _see('listening ${stage.positions.hasListener}, '
              'track ${_how(job)}');
          _end(async, 'more');
          _see('track ${_how(job)}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'done gave Cancelled(manual), the parent is cancelled false',
          'listening false, track no outcome',
          'track Done(null)',
        ]);
        _says('Use `.done` to inspect the outcome, or retain the returned '
            'job and call its `cancel()` to stop only this subscription.');
        _says('Cancelling only the child does not directly cancel the '
            'parent.');
      });

      test('an uncaught Cancelled from value cancels the parent', () {
        late Job<void> job;
        final errors = _zone((async) {
          final bench = Bench();
          late Job<void> following;
          job = bench.run<Ready, void>(key: 'track', (ctx) async {
            following = ctx.each(hw.positions, (childCtx, p) {});
            await following.value;
          });
          async.flushMicrotasks();
          following.cancel().ignore();
          async.flushMicrotasks();
        });

        expect(errors, isEmpty);
        expect(
          '${job.outcome}',
          'Cancelled(handler: child null: Cancelled(manual))',
        );
        _says("An uncaught `Cancelled` from the child's `.value` does "
            'cancel the parent through its body.');
      });

      test('an open stream with no events holds the parent and the queue', () {
        final errors = _zone((async) {
          final bench = Bench();
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            ctx.each(hw.positions, (childCtx, p) {});
          });
          final next = bench.run<Ready, void>(key: 'next', (ctx) async {});
          async.elapse(const Duration(hours: 1));
          _see('an hour later: track ${_how(job)}, next queued '
              '${next.isQueued}');
          unawaited(stage.positions.close());
          async.flushMicrotasks();
          _see('the source is done: track ${_how(job)}, next ${_how(next)}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'an hour later: track no outcome, next queued true',
          'the source is done: track Done(null), next Done(null)',
        ]);
        _says('so an open stream with no events is a child still running; '
            'and the parent waits for its children with or without an '
            'explicit await, so it keeps running too, and holds the queue');
      });

      test('close() cancels the child', () {
        final errors = _zone((async) {
          Solo.observer = _Watch();
          final bench = Bench()
            ..run<Ready, void>(key: 'track', (ctx) async {
              ctx.each(hw.positions, (childCtx, p) {});
            });
          async.flushMicrotasks();
          _seen.clear();
          var closed = false;
          bench.close().then((_) => closed = true);
          async.flushMicrotasks();
          _see('closed $closed, listening ${stage.positions.hasListener}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          '> Job(each) finished Cancelled(parent)',
          'Job(track) finished Cancelled(closed)',
          'closed true, listening false',
        ]);
        _says('Accepted parent cancellation, including during `close()`, '
            'cancels the child');
      });

      test('a draining close cancels nothing and waits for the stream to end',
          () {
        final errors = _zone((async) {
          final bench = Bench();
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            ctx.each(hw.positions, (childCtx, p) {});
          });
          async.flushMicrotasks();
          var closed = false;
          bench.close(mode: SoloCloseMode.drain).then((_) => closed = true);
          async.elapse(const Duration(hours: 1));
          _see('an hour into the drain: track ${_how(job)}; closed $closed; '
              'listening ${stage.positions.hasListener}');
          unawaited(stage.positions.close());
          async.flushMicrotasks();
          _see('the source is done: track ${_how(job)}, closed $closed');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'an hour into the drain: track no outcome',
          'closed false',
          'listening true',
          'the source is done: track Done(null), closed true',
        ]);
        _says('a draining `close(mode: SoloCloseMode.drain)` cancels nothing '
            'and waits for the stream to end');
      });

      test('the child is cancellable even if the parent is not', () {
        final errors = _zone((async) {
          final bench = Bench();
          late Job<void> following;
          final job = bench.run<Ready, void>(
            key: 'track',
            cancellable: false,
            (ctx) async {
              following = ctx.each(hw.positions, (childCtx, p) {});
            },
          );
          async.flushMicrotasks();
          var closed = false;
          bench.close().then((_) => closed = true);
          async.elapse(const Duration(hours: 1));
          _see('close(): track ${_how(job)}, child ${_how(following)}, '
              'closed $closed');
          following.cancel().ignore();
          async.flushMicrotasks();
          _see('child.cancel(): track ${_how(job)}; '
              'child ${_how(following)}, closed $closed');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'close(): track no outcome, child no outcome, closed false',
          'child.cancel(): track Done(null)',
          'child Cancelled(manual), closed true',
        ]);
        _says('The child is cancellable even if the parent is not.');
      });

      test('the child keeps keepWhile of the parent and skips canStart', () {
        final errors = _zone((async) {
          final bench = Bench();
          var asked = 0;
          late Job<void> following;
          final job = bench.run<Ready, void>(
            key: 'track',
            canStart: (state) {
              asked++;

              return true;
            },
            keepWhile: (state) => !state.paused,
            (ctx) async {
              following = ctx.each(hw.positions, (childCtx, p) {});
            },
          );
          async.flushMicrotasks();
          _see('canStart was asked $asked time(s)');
          bench.reflect(const Ready(paused: true));
          async.flushMicrotasks();
          _see('child ${_how(following)}, track ${_how(job)}; '
              'listening ${stage.positions.hasListener}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'canStart was asked 1 time(s)',
          'child Cancelled(rules: keepWhile), track Done(null)',
          'listening false',
        ]);
        _says("It retains the parent's working type and `keepWhile` after "
            'the parent body returns, but does not repeat `canStart`.');
      });

      test('the child keeps the working type of the parent', () {
        final errors = _zone((async) {
          final bench = Bench();
          late Job<void> following;
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            following = ctx.each(hw.positions, (childCtx, p) {});
          });
          async.flushMicrotasks();
          bench.reflect(const Off());
          async.flushMicrotasks();
          _see('child ${_how(following)}, track ${_how(job)}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'child Cancelled(rules: is not Ready), track Done(null)',
        ]);
      });

      test(
          'a child nobody reads: its failure goes to the zone, not to the '
          'parent', () {
        late Bench bench;
        final errors = _zone((async) {
          bench = Bench();
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            ctx.each(
              hw.positions,
              (childCtx, p) => throw StateError('callback failed'),
            );
          });
          async.flushMicrotasks();
          _see('the body returned: track ${_how(job)}');
          stage.positions.add(1);
          async.flushMicrotasks();
          _see('track ${_how(job)}');
        });

        expect(_seen, [
          'the body returned: track no outcome',
          'track Done(null)',
        ]);
        expect(errors, ['Bad state: callback failed']);
        expect(bench.heard, ['Job(each): Bad state: callback failed']);
        expect(bench.unanswered, isEmpty);
        _says("still holds the parent, but its failure is not the parent's: "
            'the parent ends `Done`, and the failure goes where a failure '
            'nobody read goes, to the zone');
      });

      test('the progress in _sync is such a child', () {
        late page.Syncer solo;
        final errors = _zone((async) {
          solo = page.Syncer();
          final job = solo.sync(1);
          async.flushMicrotasks();
          stage.progress.addError(StateError('progress broke'));
          async.flushMicrotasks();
          _end(async, 'push 1');
          _see('sync ${_how(job)}');
        });

        expect(_seen, ['sync Done(path/1)']);
        expect(errors, ['Bad state: progress broke']);
        expect(solo.heard, ['Job(each): Bad state: progress broke']);
        _says('A child whose outcome nobody reads, like the progress in '
            '`_sync` at the top of this page');
      });

      test('ignore() on the child keeps its failure out of the zone', () {
        late Bench bench;
        final errors = _zone((async) {
          bench = Bench()
            ..run<Ready, void>(key: 'track', (ctx) async {
              ctx.each(hw.positions, (childCtx, p) {
                throw StateError('callback failed');
              }).ignore();
            });
          async.flushMicrotasks();
          stage.positions.add(1);
          async.flushMicrotasks();
        });

        expect(errors, isEmpty);
        expect(bench.heard, ['Job(each): Bad state: callback failed']);
        _says('`ignore()` on the child keeps it out of the zone.');
      });

      test('events are delivered one at a time', () {
        final errors = _zone((async) {
          Bench().run<Ready, void>(
            key: 'track',
            (ctx) => ctx.each(hw.positions, (childCtx, p) async {
              await childCtx.join(() => stage.start<void>('handle $p', null));
            }).value,
          );
          async.flushMicrotasks();
          stage.positions
            ..add(1)
            ..add(2);
          async.flushMicrotasks();
          _see('${stage.trace}');
          _end(async, 'handle 1');
          _see('${stage.trace}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          '[handle 1 start]',
          '[handle 1 start, handle 1 end, handle 2 start]',
        ]);
        _says('Events are delivered one at a time, and a cancellation waits '
            'for the callback in flight.');
      });

      for (final waiting in ['a plain await', 'childCtx.abandonable']) {
        test('$waiting in the callback, and close()', () {
          final errors = _zone((async) {
            final bench = Bench();
            String? returned;
            String? closed;
            final job = bench.run<Ready, void>(
              key: 'track',
              (ctx) => ctx.each(hw.positions, (childCtx, p) async {
                try {
                  if (waiting == 'childCtx.abandonable') {
                    await childCtx.abandonable(() => _delay(1000));
                  } else {
                    await _delay(1000);
                  }
                } finally {
                  returned = '${async.elapsed.inMilliseconds} ms';
                }
              }).value,
            );
            final next = bench.run<Ready, void>(key: 'next', (ctx) async {});
            async.flushMicrotasks();
            stage.positions.add(1);
            async.elapse(const Duration(milliseconds: 50));
            bench
                .close()
                .then((_) => closed = '${async.elapsed.inMilliseconds} ms');
            async.flushMicrotasks();
            _see('at 50 ms: listening ${stage.positions.hasListener}; '
                'track ${_how(job)}, next ${_how(next)}');
            async.elapse(const Duration(seconds: 5));
            _see('the callback returned at $returned, close() at $closed');
          });

          final at = waiting == 'childCtx.abandonable' ? '50 ms' : '1000 ms';
          final track = waiting == 'childCtx.abandonable'
              ? 'Cancelled(closed)'
              : 'no outcome';
          expect(errors, isEmpty);
          expect(_seen, [
            'at 50 ms: listening false',
            'track $track, next Cancelled(closed)',
            'the callback returned at $at, close() at $at',
          ]);
          _says(
              '`childCtx.abandonable` ends with the cancellation the moment it '
              'arrives and leaves the action running alone, while a plain '
              '`await` ends only when its own future does');
          _says('until the callback returns, the child and the parent are '
              'still running, the queue is held and `close()` does not come '
              'back');
        });
      }

      for (final awaited in ['done', 'value', 'cancel()']) {
        test('a callback that awaits $awaited of its own child never returns',
            () {
          final errors = _zone((async) {
            final bench = Bench();
            late Job<void> following;
            var returned = false;
            final job = bench.run<Ready, void>(key: 'track', (ctx) async {
              following = ctx.each(hw.positions, (childCtx, p) async {
                switch (awaited) {
                  case 'done':
                    await following.done;
                  case 'value':
                    await following.value;
                  default:
                    await following.cancel();
                }
                returned = true;
              });
            });
            async.flushMicrotasks();
            stage.positions.add(1);
            async.flushMicrotasks();
            var closed = false;
            bench.close().then((_) => closed = true);
            async.elapse(const Duration(seconds: 100));
            _see('the callback returned $returned; '
                'child ${_how(following)}, track ${_how(job)}, '
                'closed $closed');
          });

          expect(errors, isEmpty);
          expect(_seen, [
            'the callback returned false',
            'child no outcome, track no outcome, closed false',
          ]);
          _says("Do not await the child's own completion or its `cancel()` "
              'inside an event callback: that is a deadlock.');
        });
      }

      test('a callback stops its own subscription with an unawaited cancel()',
          () {
        final errors = _zone((async) {
          final bench = Bench();
          late Job<void> following;
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            following = ctx.each(hw.positions, (childCtx, p) {
              _see('position $p');
              following.cancel().ignore();
            });
          });
          async.flushMicrotasks();
          stage.positions
            ..add(1)
            ..add(2);
          async.flushMicrotasks();
          _see('child ${_how(following)}, track ${_how(job)}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'position 1',
          'child Cancelled(manual), track Done(null)',
        ]);
        _says('To stop the subscription from inside a callback, call '
            '`cancel()` and do not await it.');
      });

      test('the child does not wait for the cleanup of the source', () {
        final errors = _zone((async) {
          final bench = Bench();
          final source = StreamController<int>(
            onCancel: () => Completer<void>().future,
          );
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            ctx.each(source.stream, (childCtx, p) {});
          });
          async.flushMicrotasks();
          job.cancel().ignore();
          async.flushMicrotasks();
          _see('track ${_how(job)}');
          unawaited(source.close());
        });

        expect(errors, isEmpty);
        expect(_seen, ['track Cancelled(manual)']);
        _says('The child does not wait for the source');
      });

      test(
          'a cleanup of the source that fails goes to onError and on to '
          'onUnanswered', () {
        late Bench bench;
        final errors = _zone((async) {
          bench = Bench();
          final source = StreamController<int>(
            onCancel: () => Future<void>.error(StateError('cleanup failed')),
          );
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            ctx.each(source.stream, (childCtx, p) {});
          });
          async.flushMicrotasks();
          job.cancel().ignore();
          async.flushMicrotasks();
          _see('track ${_how(job)}');
          unawaited(source.close());
        });

        expect(_seen, ['track Cancelled(manual)']);
        expect(bench.heard, ['Job(each): Bad state: cleanup failed']);
        expect(bench.unanswered, ['Job(each): Bad state: cleanup failed']);
        expect(errors, ['Bad state: cleanup failed']);
        _says('If that cleanup fails, its error goes to `Solo.onError` and '
            'on to `Solo.onUnanswered`, as an error no outcome carries does.');
      });

      test(
          'a job with the closing of its source on its cleanup stack ends '
          'after it', () {
        final errors = _zone((async) {
          final bench = Bench();
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            ctx.onDispose(() => stage.start<void>('close the source', null));
            await ctx.each(hw.positions, (childCtx, p) {}).value;
          });
          async.flushMicrotasks();
          job.cancel().ignore();
          async.flushMicrotasks();
          _see('cancelled: track ${_how(job)}, ${stage.trace}');
          _end(async, 'close the source');
          _see('the source closed: track ${_how(job)}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'cancelled: track no outcome, [close the source start]',
          'the source closed: track Cancelled(manual)',
        ]);
        _says('A job that must not end before its source has closed waits '
            'for that itself');
      });

      test(
          'a child for the event, made with job(...), closes what the event '
          'opened before the next one', () {
        final errors = _zone((async) {
          final bench = Bench();
          SoloJob<void> forEvent(int p) =>
              bench.job<Ready, void>(key: 'event', (eventCtx) async {
                eventCtx.onDispose(() => stage.trace.add('close $p'));
                stage.trace.add('open $p');
              });
          bench.run<Ready, void>(
            key: 'track',
            (ctx) => ctx
                .each(hw.positions, (childCtx, p) => childCtx.run(forEvent(p)))
                .value,
          );
          async.flushMicrotasks();
          stage.positions
            ..add(1)
            ..add(2);
          async.flushMicrotasks();
        });

        expect(errors, isEmpty);
        expect(stage.trace, ['open 1', 'close 1', 'open 2', 'close 2']);
        _says('The rest of that page holds here as well, with `job(...)` '
            'where it writes `Job.deferred`');
      });

      test('a callback in several steps stops between them for a cancellation',
          () {
        final errors = _zone((async) {
          final bench = Bench();
          final job = bench.run<Ready, void>(
            key: 'track',
            (ctx) => ctx.each(hw.positions, (childCtx, p) async {
              await childCtx.join(() => stage.start<void>('first step', null));
              await childCtx.join(() => stage.start<void>('second step', null));
            }).value,
          );
          async.flushMicrotasks();
          stage.positions.add(1);
          async.flushMicrotasks();
          job.cancel().ignore();
          async.flushMicrotasks();
          _end(async, 'first step');
          _see('track ${_how(job)}');
        });

        expect(errors, isEmpty);
        expect(_seen, ['track Cancelled(manual)']);
        expect(stage.trace, ['first step start', 'first step end']);
      });
    });
  });

  group('Following another controller', () {
    group('the first attempt', () {
      test('a session already signed in sends nothing', () {
        final errors = _zone((async) {
          final session = SessionController(const Session(signedIn: true));
          final screen = first.ScreenController(session)..follow();
          async.elapse(const Duration(hours: 1));
          _see('an hour later: session ${session.currentState}; '
              'screen ${screen.currentState}');
          session.sign(signedIn: false);
          async.flushMicrotasks();
          session.sign(signedIn: true);
          async.flushMicrotasks();
          _see('the session changed: screen ${screen.currentState}');
          screen.close();
          session.close();
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'an hour later: session Session(signedIn: true)',
          'screen Screen(signedIn: false)',
          'the session changed: screen Screen(signedIn: true)',
        ]);
        _says('A session that is already signed in when `follow()` starts '
            'sends nothing, and the screen goes on showing `signedIn: false` '
            'until the session changes.');
      });
    });

    group('the state first, then the stream', () {
      test('follow() takes what has already happened, then what happens next',
          () {
        final errors = _zone((async) {
          final session = SessionController(const Session(signedIn: true));
          final screen = page.ScreenController(session)..follow();
          async.flushMicrotasks();
          _see('started: ${screen.currentState}');
          session.sign(signedIn: false);
          async.flushMicrotasks();
          _see('signed out: ${screen.currentState}');
          session.sign(signedIn: true);
          async.flushMicrotasks();
          _see('signed in: ${screen.currentState}');
          screen.close();
          session.close();
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'started: Screen(signedIn: true)',
          'signed out: Screen(signedIn: false)',
          'signed in: Screen(signedIn: true)',
        ]);
      });

      test("the first write is the parent's, the later ones are the child's",
          () {
        final errors = _zone((async) {
          Solo.observer = _Watch();
          final session = SessionController(const Session(signedIn: true));
          page.ScreenController(session).follow();
          async.flushMicrotasks();
          session.sign(signedIn: false);
          async.flushMicrotasks();
        });

        expect(errors, isEmpty);
        expect(
          [
            for (final line in _seen)
              if (line.startsWith('state Screen')) line,
          ],
          [
            'state Screen(signedIn: true) by Job(follow)',
            'state Screen(signedIn: false) by Job(each)',
          ],
        );
      });

      test('a change right before the job starts and right after is not lost',
          () {
        final errors = _zone((async) {
          final session = SessionController();
          final screen = page.ScreenController(session);
          session.sign(signedIn: true);
          screen.follow();
          async.flushMicrotasks();
          _see('${session.currentState}, ${screen.currentState}');
          session.sign(signedIn: false);
          async.flushMicrotasks();
          _see('${session.currentState}, ${screen.currentState}');
          screen.close();
          session.close();
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'Session(signedIn: true), Screen(signedIn: true)',
          'Session(signedIn: false), Screen(signedIn: false)',
        ]);
        _says('so no change of the session falls between the two');
      });

      test('the job ends when the session closes its stream', () {
        final errors = _zone((async) {
          final session = SessionController();
          final screen = page.ScreenController(session);
          final following = screen.follow();
          final other = screen.other();
          async.elapse(const Duration(hours: 1));
          _see('an hour later: follow ${_how(following)}, '
              'other ${_how(other)}, ${stage.trace}');
          session.close();
          async.flushMicrotasks();
          _see('the session closed: follow ${_how(following)}; '
              'other ${_how(other)}, ${stage.trace}');
          screen.close();
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'an hour later: follow no outcome, other no outcome, []',
          'the session closed: follow Done(null)',
          'other Done(null), [other ran]',
        ]);
        _says('no other job of that controller starts before the session '
            'closes its stream');
      });

      test('closing the following controller cancels the job', () {
        final errors = _zone((async) {
          final session = SessionController();
          final screen = page.ScreenController(session);
          final following = screen.follow();
          async.flushMicrotasks();
          var closed = false;
          screen.close().then((_) => closed = true);
          async.flushMicrotasks();
          _see('follow ${_how(following)}, closed $closed');
          session.close();
        });

        expect(errors, isEmpty);
        expect(_seen, ['follow Cancelled(closed), closed true']);
      });

      test('a draining close waits for the session to close', () {
        final errors = _zone((async) {
          final session = SessionController();
          final screen = page.ScreenController(session);
          final following = screen.follow();
          async.flushMicrotasks();
          var closed = false;
          screen.close(mode: SoloCloseMode.drain).then((_) => closed = true);
          async.elapse(const Duration(hours: 1));
          _see('an hour into the drain: follow ${_how(following)}, '
              'closed $closed');
          session.close();
          async.flushMicrotasks();
          _see('the session closed: follow ${_how(following)}, '
              'closed $closed');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'an hour into the drain: follow no outcome, closed false',
          'the session closed: follow Done(null), closed true',
        ]);
        _says('and a draining `close` waits for the same');
      });

      test('a subscription of its own that queues a short job for each update',
          () {
        final errors = _zone((async) {
          final session = SessionController(const Session(signedIn: true));
          final screen = _Queueing(session);
          async.flushMicrotasks();
          _see('started: ${screen.currentState}');
          final other = screen.other();
          async.flushMicrotasks();
          session.sign(signedIn: false);
          async.flushMicrotasks();
          _see('while another job runs: ${screen.currentState}');
          _end(async, 'other');
          _see('that job is over: ${screen.currentState}, '
              'other ${_how(other)}');
          screen.close();
          async.flushMicrotasks();
          session.sign(signedIn: true);
          async.flushMicrotasks();
          _see('after onClose: ${screen.currentState}');
          session.close();
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'started: Screen(signedIn: true)',
          'while another job runs: Screen(signedIn: true)',
          'that job is over: Screen(signedIn: false), other Done(null)',
          'after onClose: Screen(signedIn: false)',
        ]);
        _says('made in its constructor and cancelled in `onClose`, and from '
            'it either queues a short job for each update');
      });

      test('a subscription of its own that writes with externalSetState', () {
        final errors = _zone((async) {
          final session = SessionController(const Session(signedIn: true));
          final screen = _Reflecting(session);
          final other = screen.other();
          async.flushMicrotasks();
          session.sign(signedIn: false);
          async.flushMicrotasks();
          _see('while another job runs: ${screen.currentState}, '
              'other ${_how(other)}');
          _end(async, 'other');
          screen.close();
          async.flushMicrotasks();
          session.sign(signedIn: true);
          async.flushMicrotasks();
          _see('after onClose: ${screen.currentState}');
          session.close();
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'while another job runs: Screen(signedIn: false), other no outcome',
          'after onClose: Screen(signedIn: false)',
        ]);
        _says('when the update is a fact the running work has to hear at '
            'once, writes it with `externalSetState`');
      });
    });
  });

  group('Chaining completed work', () {
    test('the report starts once the API has closed the progress', () {
      final errors = _zone((async) {
        final report = page.Syncer().syncAndReport(1);
        async.flushMicrotasks();
        _end(async, 'push 1');
        async.elapse(const Duration(hours: 1));
        _see('the upload returned: ${stage.trace}');
        unawaited(stage.progress.close());
        async.flushMicrotasks();
        _see('the progress closed: ${stage.trace}');
        _end(async, 'send path/1');
        _see('report ${_how(report)}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'the upload returned: [push 1 start, push 1 end]',
        'the progress closed: [push 1 start, push 1 end, send path/1 start]',
        'report Done(null)',
      ]);
      _says('a job that runs after its source succeeds, including children '
          'and cleanup — for `sync`, once the API has closed the progress');
    });

    test('the callback gets the result and a plain core JobContext', () {
      final errors = _zone((async) {
        final solo = page.Syncer();
        unawaited(stage.progress.close());
        final continuation = solo.sync(1).then((ctx, path) {
          _see('path $path; a SoloContext ${ctx is SoloContext}; '
              'a SoloJob ${ctx.job is SoloJob}; a child ${ctx.job.isChild}; '
              'the queue is held by ${solo.current}');

          return path.length;
        });
        async.flushMicrotasks();
        _end(async, 'push 1');
        _see('continuation ${_how(continuation)}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'path path/1',
        'a SoloContext false',
        'a SoloJob false',
        'a child false',
        'the queue is held by null',
        'continuation Done(6)',
      ]);
      _says('Its callback receives the result and a new core `JobContext`, '
          'and may return a value or future.');
      _says("A continuation does not inherit the controller's state "
          'context, rules, observer or queue position.');
    });

    test('a failure of sync comes down the chain to whoever reads it', () {
      final errors = _zone((async) {
        final report = page.Syncer().syncAndReport(1);
        report.value.then<void>(
          (_) {},
          onError: (Object error) => _see('the reader got $error'),
        );
        async.flushMicrotasks();
        unawaited(stage.progress.close());
        _fail(async, 'push 1', StateError('push failed'));
        _see('report ${_how(report)}; ${stage.trace}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'the reader got Bad state: push failed',
        'report Failed(Bad state: push failed)',
        '[push 1 start, push 1 failed]',
      ]);
      _says('A source failure propagates without calling the callback.');
      _says('A failure reaches whoever reads its outcome, the failure of '
          '`sync` passed down the chain included');
    });

    test('a failure of sync nobody reads on the continuation goes to the zone',
        () {
      late page.Syncer solo;
      final errors = _zone((async) {
        solo = page.Syncer()..syncAndReport(1);
        async.flushMicrotasks();
        unawaited(stage.progress.close());
        _fail(async, 'push 1', StateError('push failed'));
      });

      expect(errors, ['Bad state: push failed']);
      expect(solo.heard, [
        'Job(_Op.upload): Bad state: push failed',
        'Job(_Op.sync): Bad state: push failed',
      ]);
      _says('and one nobody reads goes to the zone');
    });

    test(
        'the hooks of the controller and Solo.observer do not hear a '
        'continuation', () {
      late page.Syncer solo;
      final errors = _zone((async) {
        Solo.observer = _Watch();
        solo = page.Syncer();
        unawaited(stage.progress.close());
        solo.syncAndReport(1);
        async.flushMicrotasks();
        _end(async, 'push 1');
        _seen.clear();
        _fail(async, 'send path/1', StateError('send failed'));
      });

      expect(errors, ['Bad state: send failed']);
      expect(_seen, isEmpty);
      expect(solo.heard, isEmpty);
      expect(solo.unanswered, isEmpty);
      _says('It belongs to whoever called `then`, not to the controller: the '
          "controller's hooks and `Solo.observer` do not hear it.");
    });

    test('a continuation has an observer of its own', () {
      final own = _Own();
      final errors = _zone((async) {
        final solo = page.Syncer();
        unawaited(stage.progress.close());
        solo
            .sync(1)
            .then((ctx, path) => analytics.send(path), observer: own)
            .ignore();
        async.flushMicrotasks();
        _end(async, 'push 1');
        _fail(async, 'send path/1', StateError('send failed'));
      });

      expect(errors, isEmpty);
      expect(own.heard, ['Job(then): Bad state: send failed']);
      _says('It has its own optional observer.');
    });

    test('an error with no outcome goes to the zone where then was called', () {
      final inner = <String>[];
      late page.Syncer solo;
      final errors = _zone((async) {
        solo = page.Syncer();
        unawaited(stage.progress.close());
        final source = solo.sync(1);
        runZonedGuarded(
          () => source.then((ctx, path) {
            ctx.unattended(() async => throw StateError('unattended failed'));
          }),
          (error, stackTrace) => inner.add('$error'),
        );
        async.flushMicrotasks();
        _end(async, 'push 1');
      });

      expect(inner, ['Bad state: unattended failed']);
      expect(errors, isEmpty);
      expect(solo.heard, isEmpty);
      expect(solo.unanswered, isEmpty);
      _says('An error with no outcome goes to the zone where `then` was '
          'called.');
    });

    test('the job queued behind sync starts while the report still has to run',
        () {
      final errors = _zone((async) {
        final solo = page.Syncer();
        unawaited(stage.progress.close());
        final report = solo.syncAndReport(1);
        final save = solo.save();
        async.flushMicrotasks();
        _end(async, 'push 1');
        _see('current ${solo.current}, report ${_how(report)}, '
            'save ${_how(save)}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'current Job(save), report no outcome, save no outcome',
      ]);
      expect(stage.trace, [
        'push 1 start',
        'push 1 end',
        'save start',
        'send path/1 start',
      ]);
      _says('the slot is freed when the root job finishes, and the next '
          'queued job starts while the continuation still has to run');
    });

    test('cancelling the continuation goes back to the unfinished source', () {
      final errors = _zone((async) {
        final solo = page.Syncer();
        final source = solo.sync(1);
        final report = source.then((ctx, path) => analytics.send(path));
        async.flushMicrotasks();
        var back = false;
        report.cancel().then((_) => back = true);
        async.flushMicrotasks();
        _see('cancel() came back $back');
        _end(async, 'push 1');
        _see('source ${_how(source)}, report ${_how(report)}; '
            'cancel() came back $back');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'cancel() came back false',
        'source Cancelled(chain), report Cancelled(manual)',
        'cancel() came back true',
      ]);
      expect(stage.trace, ['push 1 start', 'push 1 end']);
      _says('Cancellation travels along a chain both ways');
    });

    test('cancelling the source goes forward to the continuation', () {
      final errors = _zone((async) {
        final solo = page.Syncer();
        final source = solo.sync(1);
        final report = source.then((ctx, path) => analytics.send(path));
        async.flushMicrotasks();
        source.cancel().ignore();
        async.flushMicrotasks();
        _end(async, 'push 1');
        _see('source ${_how(source)}, report ${_how(report)}');
      });

      expect(errors, isEmpty);
      expect(_seen, ['source Cancelled(manual), report Cancelled(chain)']);
    });

    test('close() reaches a continuation through an unfinished source', () {
      final errors = _zone((async) {
        final solo = page.Syncer();
        final report = solo.syncAndReport(1);
        async.flushMicrotasks();
        var closed = false;
        solo.close().then((_) => closed = true);
        async.flushMicrotasks();
        _end(async, 'push 1');
        _see('report ${_how(report)}, closed $closed, ${stage.trace}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'report Cancelled(chain), closed true, [push 1 start, push 1 end]',
      ]);
      _says('`close()` reaches a continuation through an unfinished source');
    });

    test('close() does not own a continuation that is already running', () {
      final errors = _zone((async) {
        final solo = page.Syncer();
        unawaited(stage.progress.close());
        final report = solo.syncAndReport(1);
        async.flushMicrotasks();
        _end(async, 'push 1');
        var closed = false;
        solo.close().then((_) => closed = true);
        async.flushMicrotasks();
        _see('closed $closed, finished ${solo.isFinished}, '
            'report ${_how(report)}');
        _end(async, 'send path/1');
        _see('report ${_how(report)}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'closed true, finished true, report no outcome',
        'report Done(null)',
      ]);
      _says('but does not own one already running after the source '
          'finished');
    });

    test('ctx.run refuses a continuation in the words the page quotes', () {
      final errors = _zone((async) {
        final bench = Bench();
        bench.run<Ready, void>(key: 'parent', (ctx) async {
          final continuation = bench
              .job<Ready, int>(key: 'source', (childCtx) async => 1)
              .then((ctx, value) => value);
          try {
            await ctx.run(continuation);
          } on Object catch (error) {
            _see('$error');
          }
          try {
            await ctx.run(Job.deferred<int>((ctx) async => 1));
          } on Object catch (error) {
            _see('$error');
          }
        });
        async.flushMicrotasks();
      });

      expect(errors, isEmpty);
      expect(_seen, [
        _quotes().last,
        _quotes().last.replaceFirst('Job(then)', 'Job()'),
      ]);
      expect(
        _quotes().last,
        'Invalid argument (job): was not created by this Solo: "Job(then)"',
      );
      expect(_quotes(), hasLength(2));
      _says('The controller refuses it with an `ArgumentError`:');
      _says('A job of the core made by hand is refused in the same words.');
    });

    test('ctx.run takes the jobs job(...) makes and nobody has queued', () {
      final errors = _zone((async) {
        final bench = Bench();
        final other = Bench();
        bench.run<Ready, void>(key: 'parent', (ctx) async {
          try {
            await ctx.run(bench.save());
          } on Object catch (error) {
            _see('queued: $error');
          }
          try {
            await ctx.run(other.job<Ready, void>(key: 'theirs', (c) async {}));
          } on Object catch (error) {
            _see('of another controller; $error');
          }
          await ctx.run(bench.job<Ready, void>(key: 'ours', (c) async {}));
          _see('made by job(...) and not queued: ran');
        });
        async.flushMicrotasks();
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'queued: Bad state: Job(save) is queued and cannot be run as a child',
        'of another controller',
        'Invalid argument (job): was not created by this Solo: "Job(theirs)"',
        'made by job(...) and not queued: ran',
      ]);
      _says("Inside a controller's body `ctx.run` takes jobs of that "
          'controller, the ones `job(...)` makes and nobody has queued');
    });
  });

  group('Steps in a row', () {
    test('recordPath through the queue writes the path', () {
      final errors = _zone((async) {
        final solo = page.Syncer()..recordPath('path/7');
        async.flushMicrotasks();
        _see('${solo.currentState}');
      });

      expect(errors, isEmpty);
      expect(_seen, ['Ready(sent: 0, position: 0, path: path/7)']);
    });

    group('the first attempt', () {
      test('a save queued while sync was running goes ahead of recordPath', () {
        final errors = _zone((async) {
          Solo.observer = _Watch();
          final solo = first.Chained();
          unawaited(stage.progress.close());
          final chain = solo.syncAndRecord(1);
          async.flushMicrotasks();
          solo.save();
          _end(async, 'push 1');
          _see('sync is over: ${solo.currentState}; chain ${_how(chain)}');
          _end(async, 'save');
          _see('save is over: ${solo.currentState}; chain ${_how(chain)}');
        });

        expect(errors, isEmpty);
        expect(_starts, [
          'Job(_Op.sync) started',
          '> Job(each) started',
          '> Job(_Op.upload) started',
          'Job(save) started',
          'Job(_Op.record) started',
        ]);
        expect(
          [
            for (final line in _seen)
              if (line.contains(' is over: ') || line.startsWith('chain '))
                line,
          ],
          [
            'sync is over: Ready(sent: 0, position: 0, path: )',
            'chain no outcome',
            'save is over: Ready(sent: 0, position: 0, path: path/1)',
            'chain Done(null)',
          ],
        );
        _says('with another method of the controller, `save()`, called while '
            '`sync` was still running, the order is `sync`, `save`, '
            '`recordPath`');
        _says('The end of the source does two things at once: it frees the '
            'slot and it starts the continuation.');
      });

      test('a drain that is still running takes no new job', () {
        final errors = _zone((async) {
          final solo = first.Chained();
          unawaited(stage.progress.close());
          final chain = solo.syncAndRecord(1);
          async.flushMicrotasks();
          solo.save();
          var closed = false;
          solo.close(mode: SoloCloseMode.drain).then((_) => closed = true);
          _end(async, 'push 1');
          _see('draining ${solo.isDraining}, closed $closed, '
              'chain ${_how(chain)}');
          _end(async, 'save');
          _see('closed $closed; ${solo.currentState}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'draining true, closed false, chain Cancelled(closed)',
          'closed true',
          'Ready(sent: 0, position: 0, path: )',
        ]);
      });

      test('a drain that ends with sync: the path is not recorded either', () {
        final errors = _zone((async) {
          final solo = first.Chained();
          unawaited(stage.progress.close());
          final chain = solo.syncAndRecord(1);
          async.flushMicrotasks();
          var closed = false;
          solo.close(mode: SoloCloseMode.drain).then((_) => closed = true);
          _end(async, 'push 1');
          _see('closed $closed, chain ${_how(chain)}; ${solo.currentState}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'closed true, chain Cancelled(closed)',
          'Ready(sent: 0, position: 0, path: )',
        ]);
        _says('And a controller that is draining takes no new job at all: '
            'the path is never recorded, and the continuation ends '
            '`Cancelled(closed)`.');
      });
    });

    group('the second attempt', () {
      test('the upload never starts, and nothing moves', () {
        final errors = _zone((async) {
          final solo = first.Queued();
          final job = solo.syncAndRecord(1);
          async.elapse(const Duration(hours: 1));
          _see('an hour later: job ${_how(job)}, ${stage.trace}, '
              'queue ${solo.queue.jobs}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'an hour later: job no outcome, [], queue [Job(_Op.sync)]',
        ]);
        _says('The caller is waiting for that job: the upload never starts');
      });

      test('close() cancels both', () {
        final errors = _zone((async) {
          Solo.observer = _Watch();
          final solo = first.Queued()..syncAndRecord(1);
          async.flushMicrotasks();
          _seen.clear();
          var closed = false;
          solo.close().then((_) => closed = true);
          async.flushMicrotasks();
          _see('closed $closed');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'Job(_Op.sync) finished Cancelled(closed)',
          'Job(_Op.syncAndRecord) finished Cancelled(closed)',
          'closed true',
        ]);
        _says('and nothing moves until `close()` cancels both');
      });

      test('called without the await, such a method queues behind this job',
          () {
        final errors = _zone((async) {
          Solo.observer = _Watch();
          final bench = Bench();
          bench.run<Ready, void>(key: 'caller', (ctx) async {
            bench.run<Ready, void>(key: 'called', (ctx) async {}).ignore();
          });
          bench.save();
          async.flushMicrotasks();
          _end(async, 'save');
        });

        expect(errors, isEmpty);
        expect(_starts, [
          'Job(caller) started',
          'Job(save) started',
          'Job(called) started',
        ]);
        _says('what it queues runs after this job and after everything '
            'queued before it');
      });
    });

    group('two children in a row', () {
      test('a save queued meanwhile waits for both steps', () {
        final errors = _zone((async) {
          Solo.observer = _Watch();
          final solo = page.Together();
          unawaited(stage.progress.close());
          final job = solo.syncAndRecord(1);
          async.flushMicrotasks();
          solo.save();
          _end(async, 'push 1');
          _see('${solo.currentState}, job ${_how(job)}');
        });

        expect(errors, isEmpty);
        expect(_starts, [
          'Job(_Op.syncAndRecord) started',
          '> Job(_Op.sync) started',
          '>> Job(each) started',
          '>> Job(_Op.upload) started',
          '> Job(_Op.record) started',
          'Job(save) started',
        ]);
        expect(
          _seen.last,
          'Ready(sent: 0, position: 0, path: path/1), job Done(null)',
        );
        _says('Use children within one parent when the whole sequence must '
            'occupy the queue without another root job running between its '
            'steps.');
      });

      test('a draining controller lets both steps run', () {
        final errors = _zone((async) {
          final solo = page.Together();
          unawaited(stage.progress.close());
          final job = solo.syncAndRecord(1);
          async.flushMicrotasks();
          var closed = false;
          solo.close(mode: SoloCloseMode.drain).then((_) => closed = true);
          _end(async, 'push 1');
          _see('closed $closed, job ${_how(job)}; ${solo.currentState}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'closed true, job Done(null)',
          'Ready(sent: 0, position: 0, path: path/1)',
        ]);
      });
    });
  });

  group('The page', () {
    test('three sections open with a first attempt, as the introduction says',
        () {
      expect(
        RegExp(r'^### The first attempt$', multiLine: true).allMatches(_page()),
        hasLength(3),
      );
      _says('Three sections below open with the version');
    });

    test('one of them goes on to a second attempt', () {
      expect(
        RegExp(r'^### The second attempt$', multiLine: true)
            .allMatches(_page()),
        hasLength(1),
      );
    });

    test('has no fence the checks do not read', () {
      expect(strayFences('doc/children.md'), isEmpty);
    });

    // Each version under its own file: an answer turned into its own first
    // attempt would still be found among all of them.
    const answers = 'test/support/children_page.dart';
    const attempts = 'test/support/children_first_attempts.dart';
    const holders = {
      '# Children and streams': answers,
      '### The first attempt': attempts,
      '### The second attempt': attempts,
      '### A child that owns the subscription': answers,
      '### The state first, then the stream': answers,
      '## Chaining completed work': answers,
      '## Steps in a row': answers,
      '### Two children in a row': answers,
    };
    for (final MapEntry(key: heading, value: holder) in holders.entries) {
      test('the code under "$heading" is a run of lines of $holder', () {
        expect(
          codeMissingFrom('doc/children.md', holder, under: heading),
          isEmpty,
        );
      });
    }

    test('every piece of code on the page is a run of lines of these files',
        () {
      expect(
        codeMissingFrom('doc/children.md', answers, alsoIn: [attempts]),
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
