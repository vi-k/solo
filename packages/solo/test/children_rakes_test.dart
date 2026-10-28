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
import 'support/compile_errors.dart';
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

/// Not on the page: the key of the droppable `sync` the second attempt
/// speaks of.
enum _Op { sync }

/// Not on the page: a `sync` that queues with `Policy.droppable` and whose
/// body retries with `await sync(item).value`.
final class _Retrying extends Solo<AppState> {
  int attempts = 0;

  _Retrying() : super(const Ready());

  Job<void> sync(int item) => enqueue<Ready, void>(
    key: _Op.sync,
    policy: Policy.droppable,
    (ctx) async {
      attempts++;
      if (attempts == 1) {
        await sync(item).value;
      }
    },
  );
}

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
  for (final block in RegExp(
    r'```text\n(.*?)\n```',
    dotAll: true,
  ).allMatches(_page()))
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

Never _throwFromChild() => throw StateError('child failed');

/// A child whose body fails while it still waits for [window] — a child of
/// its own or its cleanup — under a parent that is cancelled afterwards.
/// [silence] is what the parent does about the child: nothing,
/// `child.ignoreFailure()` or `ctx.run(child).ignore()`. With [named] the
/// parent names the error of the child in its `isExpectedError`, and the
/// child takes it.
Bench _coveredFailure(
  FakeAsync async,
  String window, {
  String silence = 'none',
  bool named = false,
}) {
  final bench = Bench();
  final parent = bench.enqueue<Ready, void>(
    key: 'parent',
    isExpectedError: named ? (error) => error is StateError : null,
    (ctx) async {
      final child = bench.job<Ready, void>(key: 'child', (childCtx) async {
        if (window == 'a child of its own') {
          final grandchild = bench.job<Ready, void>(
            key: 'grandchild',
            (ctx) =>
                ctx.abandonable(() => stage.start<void>('grandchild', null)),
          );
          childCtx.run(grandchild).ignore();
        } else {
          childCtx.onDispose(() => stage.start<void>('cleanup', null));
        }
        throw StateError('child failed first');
      });
      if (silence == 'child.ignoreFailure()') {
        child.ignoreFailure();
      }
      if (silence == 'ctx.run(child).ignore()') {
        ctx.run(child).ignore();
        await ctx.abandonable(() => stage.start<void>('parent step', null));
      } else if (silence == 'ctx.start(child)') {
        ctx.start(child);
        await ctx.abandonable(() => stage.start<void>('parent step', null));
      } else {
        try {
          await ctx.run(child);
        } on Object catch (error) {
          _see('the parent body caught $error');
          rethrow;
        }
      }
    },
  );
  async.flushMicrotasks();
  parent.cancel().ignore();
  async.flushMicrotasks();
  if (stage.isRunning('cleanup')) {
    _end(async, 'cleanup');
  }
  _see('parent ${_how(parent)}');

  return bench;
}

/// What an operation of a child throws once the cancellation stops it.
final class _OpStopped implements Exception {
  const _OpStopped();

  @override
  String toString() => 'op stopped';
}

/// An observer of the core that keeps what `onError` told it.
final class _Own extends JobObserver {
  final heard = <String>[];

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => heard.add('$job: $error');
}

final class _Answering extends _Own with JobAnswerer {
  final answered = <String>[];

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      answered.add('$job: $error');
}

/// How a controller refuses a job it did not make, up to the job.
const _refused =
    'Invalid argument (job): was not created by this Solo '
    '(make it with job(...) or ctx.child of this controller)';

void main() {
  setUp(() {
    stage = Stage();
    _seen.clear();
  });

  tearDown(() {
    stage.dispose();
    Solo.observer = null;
    Solo.unansweredHandler = null;
    Solo.debug = null;
    Job.isCancellationError = null;
  });

  group('The opening block', () {
    test('job(...) makes a job and starts nothing', () {
      final errors = _zone((async) {
        final solo = page.Syncer();
        final made = solo.made(1);
        async.elapse(const Duration(seconds: 10));
        _see(
          'queued ${made.isQueued}, running ${made.isRunning}, '
          'outcome ${made.outcome}, current ${solo.current}',
        );
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'queued false, running false, outcome null, current null',
      ]);
      expect(stage.trace, isEmpty);
      _says('`job(...)` makes a job and starts nothing.');
    });

    test('enqueueJob gives that very job a place in the queue', () {
      final errors = _zone((async) {
        final solo = page.Syncer();
        final made = solo.made(1);
        final added = solo.enqueueJob(made);
        _see(
          'the same handle ${identical(added, made)}, '
          'queued ${made.isQueued}',
        );
        async.flushMicrotasks();
        _see('running ${made.isRunning}, current ${solo.current}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'the same handle true, queued true',
        'running true, current Job(_Op.sync)',
      ]);
      _says('`enqueueJob` gives it a place in the queue');
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

    test(
      'the progress goes into the state as it comes, written by the child',
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
      },
    );

    test('sync is over once the upload has returned and the API has closed '
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
        _see(
          'the upload returned: sync ${_how(job)}; the caller got $got; '
          'save queued ${save.isQueued}',
        );
        unawaited(stage.progress.close());
        async.flushMicrotasks();
        _see(
          'the progress closed: sync ${_how(job)}; the caller got $got; '
          'save queued ${save.isQueued}',
        );
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
      _says(
        'The parent keeps the queue occupied until all its children '
        'finish, even if its body returns earlier',
      );
      _says(
        '`sync` is over once the upload has returned its path and the '
        'API has closed the progress',
      );
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

    test(
      'an upload that fails leaves sync waiting for the progress to close',
      () {
        final errors = _zone((async) {
          final job = page.Syncer().sync(1)..ignoreFailure();
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
      },
    );
  });

  group('The future of ctx.run', () {
    test(
      'a failed upload comes into the parent once the progress is closed',
      () {
        final errors = _zone((async) {
          final syncer = page.Trying();
          final job = syncer.trySync(7);
          async.flushMicrotasks();
          _fail(async, 'push 7', const ApiException());
          _see('the upload failed: ${_how(job)}');
          unawaited(stage.progress.close());
          async.flushMicrotasks();
          _see('the progress closed: ${_how(job)}');
          _see('${syncer.currentState}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'the upload failed: no outcome',
          'the progress closed: Done(false)',
          'Ready(sent: 0, position: 0, path: )',
        ]);
        _says(
          'the `catch` above runs once the API has closed the progress '
          '`_sync` follows',
        );
      },
    );

    test('an upload that succeeds leaves its path in the state', () {
      final errors = _zone((async) {
        final syncer = page.Trying();
        final job = syncer.trySync(7);
        async.flushMicrotasks();
        _end(async, 'push 7');
        unawaited(stage.progress.close());
        async.flushMicrotasks();
        _see('${_how(job)}; ${syncer.currentState}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'Done(true)',
        'Ready(sent: 0, position: 0, path: path/7)',
      ]);
    });
  });

  group('The future of ctx.run, a broad clause', () {
    for (final clause in ['on ApiException', 'on Exception', 'on Object']) {
      test('$clause and a cancellation of the job', () {
        final errors = _zone((async) {
          final bench = Bench();
          final parent = bench.enqueue<Ready, bool>(key: 'parent', (ctx) async {
            final child = bench.job<Ready, String>(
              key: 'child',
              (childCtx) => childCtx.join(() => api.push(7)),
            );
            switch (clause) {
              case 'on ApiException':
                try {
                  await ctx.run(child);
                } on ApiException {
                  _see('the clause ran');
                }
              case 'on Exception':
                try {
                  await ctx.run(child);
                } on Exception catch (error) {
                  _see('the clause ran with $error');
                }
              default:
                try {
                  await ctx.run(child);
                } on Object catch (error) {
                  _see('the clause ran with $error');
                }
            }

            return false;
          });
          async.flushMicrotasks();
          parent.cancel().ignore();
          async.flushMicrotasks();
          _end(async, 'push 7');
          _see(_how(parent));
        });

        expect(errors, isEmpty);
        expect(_seen, [
          if (clause != 'on ApiException')
            'the clause ran with Cancelled(parent)',
          'Cancelled(manual)',
        ]);
        _says(
          '`Cancelled` implements `Exception`, so `on Exception` or '
          '`on Object` in its place would take a cancellation along with '
          'the failures of the API',
        );
      });
    }
  });

  group('Working beside a child', () {
    test('the upload runs while the parent sends, and its writes come in', () {
      final errors = _zone((async) {
        final syncer = page.Announcing();
        final job = syncer.syncAndAnnounce(7);
        async.flushMicrotasks();
        _see('${stage.trace}');
        stage.progress.add(40);
        async.flushMicrotasks();
        _see('${syncer.currentState}');
        _end(async, 'send started 7');
        _end(async, 'push 7');
        unawaited(stage.progress.close());
        async.flushMicrotasks();
        _see(_how(job));
      });

      expect(errors, isEmpty);
      expect(_seen, [
        '[push 7 start, send started 7 start]',
        'Ready(sent: 40, position: 0, path: )',
        'Done(path/7)',
      ]);
    });

    for (final listener in ['ignore()', 'nothing']) {
      test(
        'an upload that fails before the await, with $listener on the future',
        () {
          final errors = _zone((async) {
            final bench = Bench();
            final parent = bench.enqueue<Ready, String>(key: 'parent', (
              ctx,
            ) async {
              final child = bench.job<Ready, String>(
                key: 'child',
                (childCtx) => childCtx.join(() => api.push(7)),
              );
              final uploading = ctx.run(child);
              if (listener == 'ignore()') {
                uploading.ignore();
              }
              await ctx.join(() => analytics.send('started 7'));
              return uploading;
            })..ignoreFailure();
            async.flushMicrotasks();
            _fail(async, 'push 7', const ApiException());
            _see('the upload failed: ${_how(parent)}');
            _end(async, 'send started 7');
            _see(_how(parent));
          });

          expect(errors, listener == 'ignore()' ? isEmpty : ['ApiException']);
          expect(_seen, [
            'the upload failed: no outcome',
            'Failed(ApiException)',
          ]);
          _says('Nobody waits for a future kept this way until the `await`');
          _says(
            '`ignore()` on the kept future says that the error is not to '
            'be reported there. The body fails with that error all the same, '
            'at the `return`, where it hands the future on.',
          );
        },
      );
    }

    test('the page code hears a failed upload once, at the return', () {
      final errors = _zone((async) {
        final syncer = page.Announcing();
        final job = syncer.syncAndAnnounce(7)..ignoreFailure();
        async.flushMicrotasks();
        _fail(async, 'push 7', const ApiException());
        unawaited(stage.progress.close());
        async.flushMicrotasks();
        _see('the upload failed: ${_how(job)}');
        _end(async, 'send started 7');
        _see(_how(job));
      });

      expect(errors, isEmpty);
      expect(_seen, ['the upload failed: no outcome', 'Failed(ApiException)']);
    });
  });

  group('A child the rules turn away', () {
    test('paused, the upload never starts and resend ends with the drop', () {
      final errors = _zone((async) {
        final syncer = page.Resending(const Ready(paused: true));
        final job = syncer.resend(7)..ignoreFailure();
        async.flushMicrotasks();
        _see('${stage.trace}; ${_how(job)}');
      });

      expect(errors, isEmpty);
      expect(_seen, ['[]', _quotes().first]);
      _says('With the state paused, nothing is uploaded and `resend` ends:');
    });

    test('handler: in the trace is the reason of a body that lets it out', () {
      late Job<void> job;
      final errors = _zone((async) {
        job = page.Resending(const Ready(paused: true)).resend(7)
          ..ignoreFailure();
        async.flushMicrotasks();
      });

      expect(errors, isEmpty);
      expect(
        (job.outcome! as Cancelled).reason,
        isA<HandlerCancelReason>().having(
          (reason) => reason.cause,
          'cause',
          isA<Cancelled>().having(
            (cancelled) => cancelled.reason,
            'reason',
            isA<RulesCancelReason>(),
          ),
        ),
      );
      _says(
        '`handler:` in that line is not a state handler of `enqueue`. It is '
        '`HandlerCancelReason`, the reason the core gives a body that lets '
        'the cancellation of its child out, and after it come the child '
        'and the cancellation it ended with.',
      );
      _says(
        '[Cancellation details](cancellation.md#cancellation-details) has '
        'every reason and how it prints.',
      );
    });

    test('not paused, the upload runs', () {
      final errors = _zone((async) {
        final job = page.Resending().resend(7);
        async.flushMicrotasks();
        _end(async, 'push 7');
        _see('${stage.trace}; ${_how(job)}');
      });

      expect(errors, isEmpty);
      expect(_seen, ['[push 7 start, push 7 end]', 'Done(path/7)']);
    });
  });

  group('A child of ctx.run', () {
    for (final rule in ['canStart', 'keepWhile', 'the working type']) {
      test('a child turned away by $rule never runs', () {
        late SoloJob<void> child;
        final errors = _zone((async) {
          Solo.observer = _Watch();
          final bench = Bench(const Ready(paused: true));
          bench.enqueue<Ready, void>(key: 'parent', (ctx) async {
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
        expect((child.outcome! as Cancelled).reason, isA<RulesCancelReason>());
        expect(child.isChild, isTrue);
        expect(child.level, 1);
        _says(
          'subject to its own start rules: its working type, `canStart` '
          'and `keepWhile`',
        );
        _says(
          'A child the start rules turn away never runs. It is adopted '
          'first — parent and level — and only then finished `Cancelled` '
          'with a `RulesCancelReason`',
        );
        _says(
          'The observer hears the drop as an outcome of this tree, with '
          '`job.level` telling it how deep under the parent the job '
          'stands',
        );
      });
    }

    test('child.done of a child turned away holds the cancellation', () {
      final errors = _zone((async) {
        final bench = Bench(const Ready(paused: true));
        bench.enqueue<Ready, void>(key: 'parent', (ctx) async {
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

    test('a child turned away joins no waiting list, and the future of run '
        'carries the drop', () {
      final errors = _zone((async) {
        final bench = Bench(const Ready(paused: true));
        final parent = bench.enqueue<Ready, void>(key: 'parent', (ctx) async {
          final child = bench.job<Ready, void>(
            key: 'child',
            canStart: (state) => !state.paused,
            (childCtx) async {},
          );
          unawaited(
            ctx
                .run(child)
                .then<void>(
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
      _says(
        'It joins no waiting list, so the parent waits for nothing; the '
        'future of `ctx.run` carries that cancellation all the same',
      );
      _says('and it is what ends `resend` above.');
    });

    for (final rule in ['canStart', 'keepWhile']) {
      test('a $rule that throws ends the child Failed, and ctx.run throws', () {
        late SoloJob<void> child;
        late Bench bench;
        final errors = _zone((async) {
          bench = Bench();
          bench.enqueue<Ready, void>(key: 'parent', (ctx) async {
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
        _says(
          "The error is the rule's own, the child ends `Failed` with "
          'it, and `ctx.run` throws it synchronously — the line after the '
          'call never runs.',
        );
      });
    }

    test('ctx.run waits for the child, its children and its cleanup', () {
      final errors = _zone((async) {
        final bench = Bench();
        bench.enqueue<Ready, void>(key: 'parent', (ctx) async {
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
      _says("It waits for the child, the child's children and cleanup");
    });

    test(
      'after a child that succeeds, ctx.run throws the parent cancellation',
      () {
        late SoloJob<int> child;
        final errors = _zone((async) {
          final bench = Bench();
          final parent = bench.enqueue<Ready, void>(key: 'parent', (ctx) async {
            child = bench.job<Ready, int>(key: 'child', cancellable: false, (
              childCtx,
            ) async {
              await childCtx.join(() => stage.start<void>('work', null));

              return 7;
            });
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
        _says(
          "On success, it checks the parent's cancellation and state "
          'rules before returning the value',
        );
      },
    );

    test('a value registered on the call is released when ctx.run throws', () {
      final errors = _zone((async) {
        final bench = Bench();
        final parent = bench.enqueue<Ready, void>(key: 'parent', (ctx) async {
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
      _says(
        'So a value the parent has to release is registered on the call, '
        '`ctx.run(child, dispose: ...)`, and not on the line after it',
      );
    });

    test(
      'after a child that succeeds, ctx.run checks the rules of the parent',
      () {
        final errors = _zone((async) {
          final bench = Bench();
          final parent = bench.enqueue<Ready, void>(key: 'parent', (ctx) async {
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
      },
    );

    test('a child error comes into the parent body with its stack trace', () {
      late Bench bench;
      final errors = _zone((async) {
        bench = Bench();
        final parent = bench.enqueue<Ready, void>(key: 'parent', (ctx) async {
          final child = bench.job<Ready, int>(
            key: 'child',
            (childCtx) async => _throwFromChild(),
          );
          try {
            await ctx.run(child);
          } on Object catch (error, stackTrace) {
            _see(
              'caught $error, the trace names the throw: '
              '${'$stackTrace'.contains('_throwFromChild')}',
            );
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
      _says(
        'A child error or cancellation is thrown into the parent body '
        'with its stack trace.',
      );
    });

    test('a child cancellation comes into the parent body', () {
      late Job<void> parent;
      final errors = _zone((async) {
        final bench = Bench();
        late SoloJob<void> child;
        parent = bench.enqueue<Ready, void>(key: 'parent', (ctx) async {
          child = bench.job<Ready, void>(
            key: 'child',
            (childCtx) =>
                childCtx.abandonable(() => stage.start<void>('work', null)),
          );
          try {
            await ctx.run(child);
          } on Cancelled catch (cancelled) {
            _see(
              'caught $cancelled, the parent cancelled '
              '${ctx.job.isCancelled}',
            );
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
        'Cancelled(handler: Job(child): Cancelled(manual))',
      );
      expect((parent.outcome! as Cancelled).reason, isA<HandlerCancelReason>());
    });

    test('a parent that works beside its child: their writes interleave', () {
      final errors = _zone((async) {
        Solo.observer = _Watch();
        final bench = Bench();
        bench.enqueue<Ready, void>(key: 'parent', (ctx) async {
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
      _says(
        'To work in the parent while a child runs, keep the future '
        '`ctx.run` returned and await it later. The state writes of the '
        'two can then interleave',
      );
    });

    for (final rule in ['the working type', 'keepWhile']) {
      test('a write of the child that $rule of the parent refuses', () {
        final errors = _zone((async) {
          final bench = Bench();
          late SoloJob<void> child;
          final parent = bench.enqueue<Ready, void>(
            key: 'parent',
            keepWhile: (state) => !state.paused,
            (ctx) async {
              child = bench.job<AppState, void>(key: 'child', (childCtx) async {
                await childCtx.join(() => stage.start<void>('work', null));
                childCtx.emit(
                  rule == 'keepWhile' ? const Ready(paused: true) : const Off(),
                );
                _see('the child went on past its write');
              });
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
        _says(
          "A write of the child that the parent's working type or "
          '`keepWhile` does not accept cancels the parent, and the child '
          'with it',
        );
      });
    }

    test('a write of the parent that the rules of the child refuse', () {
      final errors = _zone((async) {
        final bench = Bench();
        late SoloJob<void> child;
        final parent = bench.enqueue<AppState, void>(key: 'parent', (
          ctx,
        ) async {
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
      group('a child fails, and a cancellation arrives while it waits for '
          '$window', () {
        test('the parent body catches Cancelled, and the error goes to '
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
          expect(bench.unanswered, [
            'Job(child): Bad state: child failed first',
          ]);
          expect(errors, ['Bad state: child failed first']);
          _says(
            'If the child ends `Cancelled` and its body failed, its error '
            'is not thrown into the parent body',
          );
          _says(
            '`await ctx.run(child)` throws `Cancelled`, and the error goes '
            "to the controller's `onUnanswered`",
          );
        });

        test('with Solo.unansweredHandler set, the error goes there', () {
          final handled = <String>[];
          late Bench bench;
          final errors = _zone((async) {
            Solo.unansweredHandler = (solo, job, error, stackTrace) =>
                handled.add('$job: $error');
            bench = _coveredFailure(async, window);
          });

          expect(handled, ['Job(child): Bad state: child failed first']);
          expect(bench.unanswered, [
            'Job(child): Bad state: child failed first',
          ]);
          expect(errors, isEmpty);
          _says(
            'by default to `Solo.unansweredHandler`, or to the zone without '
            'one',
          );
        });

        test('child.ignoreFailure() silences it', () {
          late Bench bench;
          final errors = _zone((async) {
            bench = _coveredFailure(
              async,
              window,
              silence: 'child.ignoreFailure()',
            );
          });

          expect(bench.heard, ['Job(child): Bad state: child failed first']);
          expect(bench.unanswered, isEmpty);
          expect(errors, isEmpty);
          _says('`child.ignoreFailure()` silences it.');
          _says(
            '| `child.ignoreFailure()` | not handled, goes to the zone | '
            'silenced |',
          );
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
          expect(bench.unanswered, [
            'Job(child): Bad state: child failed first',
          ]);
          expect(errors, ['Bad state: child failed first']);
          _says(
            '| `ctx.run(child).ignore()` | dropped: nobody answers for '
            'it | goes to `onUnanswered` |',
          );
          _says(
            '`ctx.run(child).ignore()` does not: it handles what the '
            'future throws, and the future throws the cancellation.',
          );
        });

        test('ctx.start(child) leaves it to onUnanswered', () {
          late Bench bench;
          final errors = _zone((async) {
            bench = _coveredFailure(async, window, silence: 'ctx.start(child)');
          });

          expect(_seen, ['parent Cancelled(manual)']);
          expect(bench.unanswered, [
            'Job(child): Bad state: child failed first',
          ]);
          expect(errors, ['Bad state: child failed first']);
          _says(
            '| `ctx.start(child)` | there is no future: a failure of the '
            'child goes to `onUnanswered` | goes to `onUnanswered` |',
          );
        });
      });
    }

    for (final named in [false, true]) {
      test(
        named
            ? 'a child whose operation the cancellation stopped, the stop '
                  'named by the app: only onError hears it'
            : 'a child whose operation the cancellation stopped: the stop '
                  'goes to onUnanswered',
        () {
          if (named) {
            Job.isCancellationError = (error) => error is _OpStopped;
          }
          late Bench bench;
          final errors = _zone((async) {
            bench = Bench();
            final parent = bench.enqueue<Ready, void>(key: 'parent', (
              ctx,
            ) async {
              try {
                await ctx.run(
                  bench.job<Ready, void>(key: 'child', (childCtx) async {
                    childCtx.onCancel(
                      () => stage.fail('op', const _OpStopped()),
                    );
                    await childCtx.join(() => stage.start<void>('op', null));
                  }),
                );
              } on Object catch (error) {
                _see('the parent body caught $error');
                rethrow;
              }
            });
            async.flushMicrotasks();
            parent.cancel().ignore();
            async.flushMicrotasks();
            _see('parent ${_how(parent)}');
          });

          expect(_seen, [
            'the parent body caught Cancelled(parent)',
            'parent Cancelled(manual)',
          ]);
          expect(bench.heard, ['Job(child): op stopped']);
          expect(
            bench.unanswered,
            named ? isEmpty : ['Job(child): op stopped'],
          );
          expect(errors, named ? isEmpty : ['op stopped']);
          _says(
            'That happens, for instance, when the cancellation stops an '
            "operation and the body throws that operation's error",
          );
          if (named) {
            _says(
              'An error the app named in `Job.isCancellationError` goes no '
              "further than the controller's `onError`",
            );
          }
        },
      );
    }

    group('the isExpectedError of a child', () {
      for (final silence in ['ctx.run(child).ignore()', 'ctx.start(child)']) {
        test('a child that ends Cancelled after its body failed with an '
            'error the predicate names, under $silence', () {
          late Bench bench;
          final errors = _zone((async) {
            bench = _coveredFailure(
              async,
              'its cleanup',
              silence: silence,
              named: true,
            );
          });

          expect(_seen, ['parent Cancelled(manual)']);
          expect(bench.heard, ['Job(child): Bad state: child failed first']);
          expect(bench.unanswered, isEmpty);
          expect(errors, isEmpty);
          _says(
            "An error that the child's `isExpectedError` names goes to "
            '`onUnanswered` in no row: `onError` hears it, and nobody is '
            'asked to answer for it.',
          );
        });
      }

      // How the child is made, what the parent names, what the child names
      // of its own, what the child throws, and whether it is answered for.
      for (final (made, parent, own, thrown, answered)
          in <(String, String?, String?, Exception, bool)>[
            ('job(...)', 'ApiException', null, const ApiException(), false),
            ('ctx.child', 'ApiException', null, const ApiException(), false),
            ('ctx.each', 'ApiException', null, const ApiException(), false),
            ('job(...)', null, 'ApiException', const ApiException(), false),
            (
              'job(...)',
              'ApiException',
              'op stopped',
              const ApiException(),
              true,
            ),
            (
              'job(...)',
              'Exception',
              null,
              const FormatException('a bug'),
              false,
            ),
          ]) {
        test('a child of $made, the parent naming ${parent ?? 'nothing'} and '
            'the child ${own ?? 'nothing'} of its own, fails with $thrown', () {
          bool Function(Object error)? names(String? type) => switch (type) {
            'ApiException' => (error) => error is ApiException,
            'Exception' => (error) => error is Exception,
            'op stopped' => (error) => error is _OpStopped,
            _ => null,
          };
          late Bench bench;
          final errors = _zone((async) {
            bench = Bench();
            bench.enqueue<Ready, void>(
              key: 'parent',
              isExpectedError: names(parent),
              (ctx) async {
                switch (made) {
                  case 'job(...)':
                    ctx.start(
                      bench.job<Ready, void>(
                        key: 'child',
                        isExpectedError: names(own),
                        (childCtx) async => throw thrown,
                      ),
                    );
                  case 'ctx.child':
                    ctx.start(
                      ctx.child(key: 'child', (childCtx) async => throw thrown),
                    );
                  default:
                    ctx.each(
                      stage.progress.stream,
                      key: 'child',
                      (childCtx, sent) => throw thrown,
                    );
                }
              },
            );
            async.flushMicrotasks();
            stage.progress.add(1);
            async.flushMicrotasks();
          });

          // A child of `each` says so in its name.
          final child = made == 'ctx.each' ? 'Job(child: each)' : 'Job(child)';
          expect(bench.heard, ['$child: $thrown']);
          expect(bench.unanswered, answered ? ['$child: $thrown'] : isEmpty);
          expect(errors, answered ? ['$thrown'] : isEmpty);
          _says(
            'A child started in the body takes the `isExpectedError` of the '
            'job that started it, unless it is made by `job(...)` with one of '
            'its own: `ctx.child` and `ctx.each` have no parameter for one.',
          );
          _says(
            'A broad type such as `error is Exception` in the predicate of '
            'the parent silences the bugs of every child as well',
          );
        });
      }
    });

    group('what the page leaves to the core', () {
      test('a cancellation the parent accepts passes to its children', () {
        final errors = _zone((async) {
          final bench = Bench();
          late SoloJob<void> child;
          final parent = bench.enqueue<Ready, void>(key: 'parent', (ctx) async {
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
          late SoloJob<void> child;
          final parent = bench.enqueue<Ready, void>(key: 'parent', (ctx) async {
            child = bench.job<Ready, void>(
              key: 'child',
              (childCtx) =>
                  childCtx.abandonable(() => stage.start<void>('work', null)),
            );
            ctx.run(child).ignore();
            throw StateError('parent failed');
          })..ignoreFailure();
          async.flushMicrotasks();
          _see(
            'the body failed: parent ${_how(parent)}, '
            'child ${_how(child)}',
          );
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

      for (final silence in [
        'child.ignoreFailure()',
        'ctx.run(child).ignore()',
        'ctx.start(child)',
      ]) {
        test('a child that fails under $silence', () {
          late Bench bench;
          final errors = _zone((async) {
            bench = Bench();
            bench.enqueue<Ready, void>(key: 'parent', (ctx) async {
              final child = bench.job<Ready, void>(
                key: 'child',
                (childCtx) =>
                    childCtx.join(() => stage.start<void>('work', null)),
              );
              switch (silence) {
                case 'child.ignoreFailure()':
                  child.ignoreFailure();
                  unawaited(ctx.run(child));
                case 'ctx.run(child).ignore()':
                  ctx.run(child).ignore();
                default:
                  ctx.start(child);
              }
            });
            async.flushMicrotasks();
            _fail(async, 'work', StateError('child failed'));
          });

          expect(bench.heard, ['Job(child): Bad state: child failed']);
          switch (silence) {
            case 'child.ignoreFailure()':
              expect(bench.unanswered, isEmpty);
              expect(errors, ['Bad state: child failed']);
              _says(
                '`child.ignoreFailure()` alone does not handle errors of '
                'the future returned by `ctx.run`.',
              );
            case 'ctx.run(child).ignore()':
              expect(bench.unanswered, isEmpty);
              expect(errors, isEmpty);
              _says(
                '| `ctx.run(child).ignore()` | dropped: nobody answers for '
                'it | goes to `onUnanswered` |',
              );
              _says(
                '`ctx.run(child).ignore()` explicitly ignores that '
                "future's result while the parent still waits for its "
                'children.',
              );
            default:
              expect(bench.unanswered, ['Job(child): Bad state: child failed']);
              expect(errors, ['Bad state: child failed']);
              _says(
                '`ctx.start(child)` starts the child and returns no '
                "future: its failure goes to the controller's "
                '`onUnanswered`, as any failure nobody observed does',
              );
          }
        });
      }

      test('ctx.runAll takes jobs made by job(...)', () {
        final errors = _zone((async) {
          final bench = Bench();
          final parent = bench.enqueue<Ready, List<int>>(
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
          bench.enqueue<Ready, List<int>>(
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
          'Cancelled(handler: Job(b): Cancelled(rules: canStart))',
        );
        _says(
          'each branch of a group answers to its start rules as a child '
          'of `ctx.run` does',
        );
      });

      for (final call in ['ctx.run', 'ctx.runAll']) {
        test('$call takes no Job.deferred', () {
          final errors = _zone((async) {
            Bench().enqueue<Ready, void>(key: 'parent', (ctx) async {
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
          expect(_seen, ['$_refused: "Job()"']);
          _says(
            'Where those pages make a child with `Job.deferred`, a '
            'controller makes it with `job(...)` or `ctx.child`.',
          );
          _says(
            'The `ctx.run` and `ctx.runAll` of a controller take no '
            'other job',
          );
        });
      }
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
      _says(
        'a job that runs after its source succeeds, including children '
        'and cleanup — for `sync`, once the API has closed the progress',
      );
    });

    test('the callback gets the result and a plain core JobContext', () {
      final errors = _zone((async) {
        final solo = page.Syncer();
        unawaited(stage.progress.close());
        final continuation = solo.sync(1).then((ctx, path) {
          _see(
            'path $path; a SoloContext ${ctx is SoloContext}; '
            'a SoloJob ${ctx.job is SoloJob}; a child ${ctx.job.isChild}; '
            'the queue is held by ${solo.current}',
          );

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
      _says(
        'Its callback receives the result and a new core `JobContext`, '
        'and may return a value or future.',
      );
      _says(
        "A continuation does not inherit the controller's state "
        'context, rules, observer or queue position.',
      );
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
      _says(
        'If `sync` fails, the callback is not called, and the job `then` '
        'returned ends `Failed` with the same error.',
      );
      _says(
        'A failure reaches whoever reads its outcome, the failure of '
        '`sync` passed down the chain included',
      );
    });

    test(
      'a failure of sync nobody reads on the continuation goes to the zone',
      () {
        final handled = <String>[];
        late page.Syncer solo;
        final errors = _zone((async) {
          Solo.unansweredHandler = (solo, job, error, stackTrace) =>
              handled.add('$job: $error');
          solo = page.Syncer()..syncAndReport(1);
          async.flushMicrotasks();
          unawaited(stage.progress.close());
          _fail(async, 'push 1', StateError('push failed'));
        });

        expect(errors, ['Bad state: push failed']);
        expect(handled, isEmpty);
        expect(solo.unanswered, isEmpty);
        expect(solo.heard, [
          'Job(_Op.upload): Bad state: push failed',
          'Job(_Op.sync): Bad state: push failed',
        ]);
        _says(
          'The continuation answers for one nobody reads, and for an error '
          'with no outcome, itself: in `onUnanswered` of its observer when '
          'that observer mixes in `JobAnswerer`, and otherwise in the zone '
          'where `then` was called. `Solo.unansweredHandler` does not hear '
          'them either.',
        );
      },
    );

    test('the hooks of the controller and Solo.observer do not hear a '
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
      _says(
        'It belongs to whoever called `then`, not to the controller: the '
        "controller's hooks and `Solo.observer` do not hear it.",
      );
    });

    test('a continuation has an observer of its own', () {
      final own = _Own();
      final errors = _zone((async) {
        final solo = page.Syncer();
        unawaited(stage.progress.close());
        solo
            .sync(1)
            .then((ctx, path) => analytics.send(path), observer: own)
            .ignoreFailure();
        async.flushMicrotasks();
        _end(async, 'push 1');
        _fail(async, 'send path/1', StateError('send failed'));
      });

      expect(errors, isEmpty);
      expect(own.heard, ['Job(then): Bad state: send failed']);
      _says(
        'It has its own optional observer, and `then` names it '
        '`Job(then)` unless the call gives it a `key` or a `describe`.',
      );
    });

    test(
      'an observer that mixes in JobAnswerer answers for the continuation',
      () {
        final own = _Answering();
        final handled = <String>[];
        final errors = _zone((async) {
          Solo.unansweredHandler = (solo, job, error, stackTrace) =>
              handled.add('$job: $error');
          final solo = page.Syncer();
          unawaited(stage.progress.close());
          solo.sync(1).then((ctx, path) => analytics.send(path), observer: own);
          async.flushMicrotasks();
          _end(async, 'push 1');
          _fail(async, 'send path/1', StateError('send failed'));
        });

        expect(errors, isEmpty);
        expect(handled, isEmpty);
        expect(own.heard, ['Job(then): Bad state: send failed']);
        expect(own.answered, ['Job(then): Bad state: send failed']);
        _says(
          'in `onUnanswered` of its observer when that observer mixes in '
          '`JobAnswerer`',
        );
      },
    );

    test('an error with no outcome goes to the zone where then was called', () {
      final inner = <String>[];
      final handled = <String>[];
      late page.Syncer solo;
      final errors = _zone((async) {
        Solo.unansweredHandler = (solo, job, error, stackTrace) =>
            handled.add('$job: $error');
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
      expect(handled, isEmpty);
      expect(errors, isEmpty);
      expect(solo.heard, isEmpty);
      expect(solo.unanswered, isEmpty);
      _says('and otherwise in the zone where `then` was called');
    });

    test(
      'the job queued behind sync starts while the report still has to run',
      () {
        final errors = _zone((async) {
          final solo = page.Syncer();
          unawaited(stage.progress.close());
          final report = solo.syncAndReport(1);
          final save = solo.save();
          async.flushMicrotasks();
          _end(async, 'push 1');
          _see(
            'current ${solo.current}, report ${_how(report)}, '
            'save ${_how(save)}',
          );
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
        _says(
          'the slot is freed when the root job finishes, and the next '
          'queued job starts while the continuation still has to run',
        );
      },
    );

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
        _see(
          'source ${_how(source)}, report ${_how(report)}; '
          'cancel() came back $back',
        );
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
        _see(
          'closed $closed, finished ${solo.isFinished}, '
          'report ${_how(report)}',
        );
        _end(async, 'send path/1');
        _see('report ${_how(report)}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'closed true, finished true, report no outcome',
        'report Done(null)',
      ]);
      _says(
        'but does not own one already running after the source '
        'finished',
      );
    });

    test(
      'ctx.run does not take a continuation: the error the page quotes',
      () async {
        final errors = await compileErrors('''
import 'package:solo/solo.dart';

final class Probe extends Solo<int> {
  Probe() : super(0);

  void attempt() => enqueue<int, void>((ctx) async {
        final tail = job<int, int>((c) async => 1).then<void>((c, v) {});
        await ctx.run(tail);
      });
}
''');
        expect(errors, [_quotes()[1]]);
        _says('so `ctx.run(tail)` does not compile:');
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test('ctx.run refuses a job of the core in the words the page quotes', () {
      final errors = _zone((async) {
        Bench().enqueue<Ready, void>(key: 'parent', (ctx) async {
          try {
            await ctx.run(Job.deferred<int>((ctx) async => 1));
          } on Object catch (error) {
            _see('$error');
          }
        });
        async.flushMicrotasks();
      });

      expect(errors, isEmpty);
      expect(_seen, [_quotes()[2]]);
      expect(_quotes(), hasLength(5));
      _says('and the controller refuses it with an `ArgumentError`:');
    });

    test('ctx.run takes the jobs job(...) makes and nobody has queued', () {
      final errors = _zone((async) {
        final bench = Bench();
        final other = Bench();
        bench.enqueue<Ready, void>(key: 'parent', (ctx) async {
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
        '$_refused: "Job(theirs)"',
        'made by job(...) and not queued: ran',
      ]);
      _says(
        "Inside a controller's body `ctx.run` takes jobs of that "
        'controller, the ones `job(...)` or `ctx.child` makes and nobody '
        'has queued',
      );
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
        _says(
          'with another method of the controller, `save()`, called while '
          '`sync` was still running, the order is `sync`, `save`, '
          '`recordPath`',
        );
        _says(
          'The end of the source does two things at once: it frees the '
          'slot and it starts the continuation.',
        );
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
          _see(
            'draining ${solo.isDraining}, closed $closed, '
            'chain ${_how(chain)}',
          );
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
        _says(
          'And a controller that is draining takes no new job at all: '
          'the path is never recorded, and the continuation ends '
          '`Cancelled(closed)`.',
        );
      });
    });

    group('the second attempt', () {
      test('the upload never starts, and nothing moves', () {
        final errors = _zone((async) {
          final solo = first.Queued();
          final job = solo.syncAndRecord(1);
          async.elapse(const Duration(hours: 1));
          _see(
            'an hour later: job ${_how(job)}, ${stage.trace}, '
            'queue ${solo.queue.jobs}',
          );
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'an hour later: job no outcome, [], queue [Job(_Op.sync)]',
        ]);
        _says('The caller is waiting for that job: the upload never starts');
      });

      test('Solo.debug warns of it when the job is queued', () {
        final lines = <String>[];
        final errors = _zone((async) {
          Solo.debug = lines.add;
          first.Queued().syncAndRecord(1);
          async.flushMicrotasks();
        });

        expect(errors, isEmpty);
        expect(lines, contains(_quotes()[3]));
        _says(
          'The hang itself shows nothing, but `Solo.debug` warns of it '
          'when the job is queued:',
        );
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

      test(
        'called without the await, such a method queues behind this job',
        () {
          final errors = _zone((async) {
            Solo.observer = _Watch();
            final bench = Bench();
            bench.enqueue<Ready, void>(key: 'caller', (ctx) async {
              bench
                  .enqueue<Ready, void>(key: 'called', (ctx) async {})
                  .ignoreFailure();
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
          _says(
            'what it queues runs after this job and after everything '
            'queued before it',
          );
        },
      );

      test('with droppable, the job awaits itself and close() never ends', () {
        final lines = <String>[];
        final errors = _zone((async) {
          Solo.debug = lines.add;
          final solo = _Retrying();
          final job = solo.sync(1);
          async.elapse(const Duration(hours: 1));
          var closed = false;
          solo.close().then((_) => closed = true);
          async.elapse(const Duration(hours: 1));
          _see(
            'closed $closed, job ${_how(job)}, cancelled ${job.isCancelled}',
          );
          _see('attempts ${solo.attempts}');
        });

        expect(errors, isEmpty);
        expect(lines, contains(_quotes()[4]));
        expect(_seen, [
          'closed false, job no outcome, cancelled true',
          'attempts 1',
        ]);
        _says(
          'A droppable method called from inside its own job sets a trap '
          'that not even `close()` gets out of.',
        );
        _says('It hands back that very job');
        _says(
          '`close()` marks the job cancelled, but a plain `await` does '
          'not wake for that, and the value comes only when the body ends, '
          'so `close()` waits for good as well.',
        );
        _says('`Solo.debug` shows it on the line of the duplicate:');
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
        _says(
          'Use children within one parent when the whole sequence must '
          'occupy the queue without another root job running between its '
          'steps.',
        );
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
    test('one section opens with a first attempt', () {
      expect(
        RegExp(r'^### The first attempt$', multiLine: true).allMatches(_page()),
        hasLength(1),
      );
    });

    test('it goes on to a second attempt', () {
      expect(
        RegExp(
          r'^### The second attempt$',
          multiLine: true,
        ).allMatches(_page()),
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
      '# Children and chains': answers,
      '## The future of `ctx.run`': answers,
      '## Working beside a child': answers,
      '## A child the rules turn away': answers,
      '### The first attempt': attempts,
      '### The second attempt': attempts,
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

    test(
      'every piece of code on the page is a run of lines of these files',
      () {
        expect(
          codeMissingFrom('doc/children.md', answers, alsoIn: [attempts]),
          isEmpty,
        );
      },
    );

    test('every heading with code under it is held to a file', () {
      final withCode = [
        for (final part in _page().split(RegExp('^(?=#)', multiLine: true)))
          if (part.contains('```dart')) part.split('\n').first,
      ];
      expect(withCode.toSet(), holders.keys.toSet());
    });
  });

  test('the filter of cancellation errors is left as it was found', () {
    expect(Job.isCancellationError, isNull);
  });
}

extension on Job<Object?> {
  /// The methods of the page declare `Job<T>`; whether the job still waits
  /// in the queue is on the `SoloJob<T>` the controller made.
  bool get isQueued => (this as SoloJob<Object?>).isQueued;
}
