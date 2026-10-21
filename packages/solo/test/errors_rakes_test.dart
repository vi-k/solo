@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:meta/meta.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/errors_first_attempts.dart' as first;
import 'support/errors_page.dart' as page;
import 'support/errors_page_answering.dart' as answering;
import 'support/errors_rakes.dart';
import 'support/errors_stubs.dart';
import 'support/page_code.dart';
import 'support/test_solo.dart';

/// The sentinel of `doc/errors.md`.
///
/// The code of the page stands verbatim in `test/support/errors_*.dart`: the
/// first attempts in one file, the versions that work and the code the
/// sections open with in another, and the two blocks of "Answering for an
/// error" in a third, because the page shows two versions of one class. The
/// tests below run that code and pin what the prose, the tables and the
/// quoted lines of the page say about it: who is told of an error, who is
/// asked to answer for it and where it ends when nobody does. What the page
/// states of the engine and its code does not show is pinned on `Bench`, a
/// controller whose bodies are written where they are run.
///
/// Every call of a stub runs until the test ends it, so each trace is the
/// order the test set, and fake time moves only where the page speaks of
/// time: the five seconds of the two timers, the delays of the table and
/// the seconds between the attempts of a retry.

/// What a call throws when the token of its cancelled job stops it.
final class _CallStopped implements Exception {
  const _CallStopped();

  @override
  String toString() => 'the call stopped';
}

/// Not on the page: the profile of "A pause between attempts" whose first
/// delivery of [Loaded] fails.
final class _FailingDelivery extends page.RetryingProfile {
  var _failed = false;

  _FailingDelivery() : super(ProfileApi());

  @protected
  @override
  void publish(ProfileState previous, ProfileState current) {
    super.publish(previous, current);
    if (current is Loaded && !_failed) {
      _failed = true;
      throw StateError('delivery');
    }
  }
}

/// Not on the page: the first attempt reporting from `onFinish`, through a
/// look at the outcome, instead of from `onError`.
final class _FailuresOnFinish extends SoloObserver {
  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) {
    final outcome = job.outcome;
    if (outcome is Failed) {
      reportCrash(outcome.error, outcome.stackTrace);
    }
  }
}

/// A reporting hook that calls `super`, and one that does not.
final class _ReportsAndCallsSuper extends Solo<int> with OpenSolo<int> {
  final heard = <String>[];

  _ReportsAndCallsSuper() : super(0);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    heard.add(text(error));
    super.onError(job, error, stackTrace);
  }
}

final class _ReportsAndReturns extends Solo<int> with OpenSolo<int> {
  final heard = <String>[];

  _ReportsAndReturns() : super(0);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      heard.add(text(error));
}

/// An answer that keeps the default route as well.
final class _AnswersAndCallsSuper extends Solo<int> with OpenSolo<int> {
  final kept = <String>[];

  _AnswersAndCallsSuper() : super(0);

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    kept.add(text(error));
    super.onUnanswered(job, error, stackTrace);
  }
}

/// An answer that says nothing.
final class _AnswersInSilence extends Solo<int> with OpenSolo<int> {
  _AnswersInSilence() : super(0);

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {}
}

/// The catches of "Letting cancellation through" around a call that takes a
/// token and stops by throwing: the camera of the page takes none.
final class _TokenCamera extends Solo<CameraState>
    with OpenSolo<CameraState>, Desk<CameraState> {
  final hw = Hardware();

  _TokenCamera() : super(const Closed());

  SoloJob<void> open(String version) => run<CameraState, void>(
        key: version,
        (ctx) async {
          final token = StopToken();
          ctx.onCancel(token.stop);
          switch (version) {
            case 'on Cancelled':
              try {
                await ctx.join(() => hw.openWith(token));
              } on Cancelled {
                rethrow;
              } on Object catch (error) {
                await hw.reset();
                ctx.emit(Broken(error));
                rethrow;
              }
            case 'error is Cancelled':
              try {
                await ctx.join(() => hw.openWith(token));
              } on Object catch (error) {
                if (error is Cancelled) rethrow;
                await hw.reset();
                ctx.emit(Broken(error));
                rethrow;
              }
            default:
              try {
                await ctx.join(() => hw.openWith(token));
              } on Object catch (error) {
                ctx.check();
                await hw.reset();
                ctx.emit(Broken(error));
                rethrow;
              }
          }
        },
      );
}

/// A controller whose members a stack trace names, so a test can tell the
/// trace of a change from the trace of the checkpoint that noticed it.
final class _Traced extends Solo<int> with OpenSolo<int>, Desk<int> {
  _Traced() : super(0);

  void setsTooBig() => externalSetState(9);

  void emitsTooBig(SoloContext<int, int> ctx) => ctx.emit(9);

  void readsTheState(SoloContext<int, int> ctx) => ctx.state;

  void checksTheJob(SoloContext<int, int> ctx) => ctx.check();

  Future<void> waitsOnTheContext(SoloContext<int, int> ctx) =>
      ctx.abandonable(() => stage.start<void>('after', null));

  void followsAStream(SoloContext<int, int> ctx) =>
      ctx.each(const Stream<int>.empty(), (child, event) {});
}

String _page() => errorsPage.source;

void _says(String phrase) => errorsPage.says(phrase);

Map<String, String> _rows(String header) => errorsPage.rows(header);

List<List<String>> _quoted() => errorsPage.quoted;

void _row(String error, String hears, String answers) =>
    errorsRow(error, hears, answers);

/// Fails [call] of a stub with [error].
void _fail(FakeAsync async, String call, Object error) {
  stage.fail(call, error);
  async.flushMicrotasks();
}

/// The members a stack trace names, innermost first.
List<String> _frames(StackTrace? trace) => [
      for (final line in '$trace'.split('\n'))
        if (line.trim().isNotEmpty)
          line.replaceFirst(RegExp(r'^#\d+\s+'), '').split(' (').first,
    ];

/// A job whose disposer throws.
SoloJob<void> _dirtyCleanup(OpenSolo<int> controller) =>
    controller.run<int, void>(key: 'cleanup', (ctx) async {
      ctx.onDispose(() async => throw StateError('disposer'));
    });

void main() {
  setUp(() => stage = Stage());

  tearDown(() {
    Solo.observer = null;
    Solo.unansweredHandler = null;
    Solo.debug = null;
    Job.debug = null;
    Job.isCancellationError = null;
  });

  group('Reporting an error', () {
    test('a controller that overrides the eight hooks the page names', () {
      _says(
        'A controller has a hook for each thing that happens to it and '
        'its jobs: `onStart`, `onFinish`, `onError`, `onUnanswered`, '
        '`onLog`, `onChange` and `onClose`, and `onListenerError` for a '
        'listener that throws while it is notified',
      );
      final called = <String>[];
      final ran = runFaked((async) {
        final controller = EveryHook(called)
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

      expect(called.toSet(), {
        'controller.onStart',
        'controller.onLog',
        'controller.onChange',
        'controller.onListenerError',
        'controller.onError',
        'controller.onUnanswered',
        'controller.onFinish',
        'controller.onClose',
      });
      expect(ran.errors, isEmpty, reason: 'both overrides kept their error');
    });

    test('the hook of the page: a load that fails', () {
      late Job<String> job;
      late page.ProfileController profile;
      final ran = runFaked((async) {
        profile = page.ProfileController(ProfileApi());
        job = profile.load()..ignoreFailure();
        async.flushMicrotasks();
        _fail(async, 'fetchName', StateError('no network'));
      });

      expect(stage.crashes, ['no network'], reason: 'told once');
      expect('${job.outcome}', 'Failed(Bad state: no network)');
      expect('${profile.currentState}', 'Failure(Bad state: no network)');
      expect(
        ran.errors,
        isEmpty,
        reason: 'ignoreFailure() observed the outcome',
      );
    });

    test('the hook of the page: the call it let go of fails later', () {
      late Job<String> job;
      final ran = runFaked((async) {
        final profile = page.ProfileController(ProfileApi());
        job = profile.load()..ignoreFailure();
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        _fail(async, 'fetchName', StateError('late'));
      });

      expect(stage.crashes, ['late'], reason: 'told once');
      expect('${job.outcome}', 'Cancelled(manual)');
      expect(ran.errors, ['late'], reason: 'nobody answered for it');
    });

    test('the errors its jobs run into, once', () {
      _says(
        '`onError` hears the errors the jobs of the controller run '
        'into: - the failure of a body; - an error of cleanup, or of an '
        'operation that `abandonable` stopped waiting for; - a rule '
        'that threw instead of answering.',
      );
      _says(
        'It hears each error once for each job',
      );
      late Bench bench;
      runFaked((async) {
        bench = Bench();
        bench
            .run<int, void>(
              key: 'body',
              (ctx) async => throw StateError('the body'),
            )
            .ignoreFailure();
        _dirtyCleanup(bench);
        final abandons = waits(bench, 'abandons')..ignoreFailure();
        bench
            .run<int, void>(
              key: 'rule',
              canStart: (state) => throw StateError('the rule'),
              (ctx) async {},
            )
            .ignoreFailure();
        async.flushMicrotasks();
        unawaited(abandons.cancel());
        async.flushMicrotasks();
        _fail(async, 'op', StateError('the call'));
      });

      expect(bench.heard, [
        'body: the body',
        'cleanup: disposer',
        'rule: the rule',
        'abandons: the call',
      ]);
    });

    test('an error a child throws and its parent lets through', () {
      _says(
        'An error that a child throws and its parent lets through is a '
        'failure of both, so the hook hears it twice. The `job` it is '
        'given tells the two calls apart',
      );
      late Bench bench;
      late Job<void> job;
      final ran = runFaked((async) {
        bench = Bench();
        job = bench.run<int, void>(key: 'parent', (ctx) async {
          await ctx.run(
            bench.job<int, void>(
              key: 'child',
              (child) async => throw StateError('the child'),
            ),
          );
        })
          ..ignoreFailure();
      });

      expect(bench.heard, ['child: the child', 'parent: the child']);
      expect('${job.outcome}', 'Failed(Bad state: the child)');
      expect(bench.unanswered, isEmpty);
      expect(ran.errors, isEmpty);
    });

    test('an error a child throws and its parent catches', () {
      late Bench bench;
      late Job<void> job;
      runFaked((async) {
        bench = Bench();
        job = bench.run<int, void>(key: 'parent', (ctx) async {
          try {
            await ctx.run(
              bench.job<int, void>(
                key: 'child',
                (child) async => throw StateError('the child'),
              ),
            );
          } on Object {
            // caught: the parent goes on
          }
        });
      });

      expect(bench.heard, ['child: the child'], reason: 'once: one job failed');
      expect('${job.outcome}', 'Done(null)');
    });

    for (final handlerSet in [false, true]) {
      final third = handlerSet ? 'the handler' : 'the zone';
      test(
          'a crash reporter fed from the hook gets one error three times, '
          'the third from $third', () {
        _says(
          'A crash reporter fed from here can get one error three times: '
          'from the child, from the parent and, when nobody observes the '
          "parent's outcome, from `onUnanswered`. By default "
          '`onUnanswered` hands it to `Solo.unansweredHandler` or the '
          'creation zone',
        );
        final handled = <String>[];
        late Bench bench;
        final ran = runFaked((async) {
          if (handlerSet) {
            Solo.unansweredHandler =
                (solo, job, error, stackTrace) => handled.add(text(error));
          }
          bench = Bench();
          bench.run<int, void>(key: 'parent', (ctx) async {
            await ctx.run(
              bench.job<int, void>(
                key: 'child',
                (child) async => throw StateError('the child'),
              ),
            );
          });
        });

        expect(bench.heard, ['child: the child', 'parent: the child']);
        expect(bench.unanswered, ['parent: the child']);
        expect(handled, handlerSet ? ['the child'] : isEmpty);
        expect(ran.errors, handlerSet ? isEmpty : ['the child']);
      });
    }

    for (final make in <OpenSolo<int> Function()>[
      _ReportsAndCallsSuper.new,
      _ReportsAndReturns.new,
    ]) {
      test('overriding it moves no error anywhere: ${make().runtimeType}', () {
        _says(
          'It answers for nothing, and overriding it moves no error '
          'anywhere',
        );
        final handled = <String>[];
        final ran = runFaked((async) {
          Solo.unansweredHandler =
              (solo, job, error, stackTrace) => handled.add(text(error));
          _dirtyCleanup(make());
          async.flushMicrotasks();
          Solo.unansweredHandler = null;
          _dirtyCleanup(make());
        });

        expect(handled, ['disposer'], reason: 'the handler is asked');
        expect(ran.errors, ['disposer'], reason: 'and without one, the zone');
      });
    }
  });

  group('Answering for an error', () {
    test('the override of the page answers, and the error stops there', () {
      _says(
        'The override above answers for them and for a `Failed` nobody '
        'observes. They reach nothing else',
      );
      final handled = <String>[];
      late answering.ProfileController profile;
      final ran = runFaked((async) {
        Solo.unansweredHandler =
            (solo, job, error, stackTrace) => handled.add(text(error));
        profile = answering.ProfileController(ProfileApi());
        final job = profile.load()..ignoreFailure();
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        _fail(async, 'fetchName', StateError('late'));
      });

      expect(profile.apiFailures.map(text), ['late']);
      expect(stage.crashes, ['late'], reason: 'the reporting hook was told');
      expect(handled, isEmpty, reason: 'the handler is not asked');
      expect(ran.errors, isEmpty, reason: 'and neither is the zone');
    });

    test('the failure of a body: the outcome carries it', () {
      _row(
        'An error of the body, and the job ends `Failed` with it',
        '`onError`',
        'Whoever observes the outcome; `onUnanswered` if nobody does',
      );
      _says(
        '`run(ifFailed: ...)` turns the failure into the state the '
        'screen shows',
      );
      _says(
        'When nobody observes the outcome, `onUnanswered` answers for the '
        'error. By default it sends the error to the creation zone, the '
        'zone the job was created in',
      );
      final handled = <String>[];
      late Bench bench;
      late Job<void> job;
      final ran = runFaked((async) {
        Solo.unansweredHandler =
            (solo, job, error, stackTrace) => handled.add(text(error));
        bench = Bench();
        job = bench.run<int, void>(
          key: 'body',
          ifFailed: (state, error, stackTrace) => -1,
          (ctx) async => throw StateError('the body'),
        );
      });

      expect('${job.outcome}', 'Failed(Bad state: the body)');
      expect(bench.currentState, -1, reason: 'the state handler ran');
      expect(bench.heard, ['body: the body']);
      expect(
        bench.unanswered,
        ['body: the body'],
        reason: 'nobody observed the outcome',
      );
      expect(handled, ['the body'], reason: 'the handler is asked');
      expect(ran.errors, isEmpty, reason: 'and the zone is not');
    });

    group('what no outcome carries:', () {
      test('the list of the page', () {
        _says(
          'These are the errors that no outcome carries:',
        );
        final section =
            _page().split(RegExp('^(?=## )', multiLine: true)).singleWhere(
                  (part) => part.startsWith('## Answering for an error'),
                );
        expect(
          RegExp('^- ', multiLine: true).allMatches(section),
          hasLength(6),
        );
        _says(
          '- an operation that `abandonable` stopped waiting for, which '
          'fails later;',
        );
        _says(
          '- what the job calls outside its body: a disposer, a '
          '`ctx.onCancel` callback, a `whenCancelled` or `whenFinished` '
          'listener, a state handler of `run`;',
        );
        _says(
          '- a `keepWhile` that throws when a change of state re-checks it;',
        );
        _says('- work handed to `ctx.unattended`;');
        _says(
          '- the failure of a branch of `ctx.runAll` that the group did not '
          'throw;',
        );
        _says(
          '- the failure of the body of a job that ends `Cancelled`: whoever '
          'reads that outcome gets the cancellation.',
        );
        _says(
          'When nobody does, the controller whose job it was answers in '
          '`onUnanswered`. It answers there as well for the errors that '
          'have no outcome to ride on',
        );
      });

      test('an operation abandoned by abandonable that fails later', () {
        _row(
          'A late error of an operation `abandonable` stopped waiting for',
          '`onError`',
          '`onUnanswered`',
        );
        late Bench bench;
        late Job<void> job;
        final ran = runFaked((async) {
          bench = Bench();
          job = waits(bench, 'abandons')..ignoreFailure();
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          _fail(async, 'op', StateError('late'));
        });

        expect(bench.heard, ['abandons: late']);
        expect(bench.unanswered, ['abandons: late']);
        expect('${job.outcome}', 'Cancelled(manual)');
        expect(ran.errors, ['late']);
      });

      test('a disposer', () {
        _row(
          'An error of a disposer, a `ctx.onCancel` callback, a '
              '`whenCancelled` or `whenFinished` listener, or a state handler '
              'of `run`',
          '`onError`',
          '`onUnanswered`',
        );
        late Bench bench;
        late Job<void> job;
        final ran = runFaked((async) {
          bench = Bench();
          job = _dirtyCleanup(bench);
        });

        expect(bench.heard, ['cleanup: disposer']);
        expect(bench.unanswered, ['cleanup: disposer']);
        expect('${job.outcome}', 'Done(null)');
        expect(ran.errors, ['disposer']);
      });

      test(
          'a ctx.onCancel callback, a whenCancelled and a whenFinished '
          'listener', () {
        late Bench bench;
        final ran = runFaked((async) {
          bench = Bench();
          final job = bench.run<int, void>(key: 'cancelled', (ctx) async {
            ctx.onCancel(() => throw StateError('the callback'));
            await ctx.abandonable(() => stage.start<void>('op', null));
          })
            ..whenCancelled((_) => throw StateError('the listener'))
            ..whenFinished((_) => throw StateError('the end listener'))
            ..ignoreFailure();
          async.flushMicrotasks();
          unawaited(job.cancel());
        });

        const all = [
          'cancelled: the callback',
          'cancelled: the listener',
          'cancelled: the end listener',
        ];
        expect(bench.heard, all);
        expect(bench.unanswered, all);
        expect(
          ran.errors,
          ['the callback', 'the listener', 'the end listener'],
        );
      });

      test('a state handler of run', () {
        late Bench bench;
        late Job<void> job;
        late Job<void> next;
        final ran = runFaked((async) {
          bench = Bench();
          job = bench.run<int, void>(
            key: 'handled',
            ifFailed: (state, error, stackTrace) =>
                throw StateError('the handler'),
            (ctx) async => throw StateError('the body'),
          )..ignoreFailure();
          next = bench.run<int, void>(key: 'next', (ctx) async {});
        });

        expect(bench.heard, ['handled: the body', 'handled: the handler']);
        expect(bench.unanswered, ['handled: the handler']);
        expect('${job.outcome}', 'Failed(Bad state: the body)');
        expect('${next.outcome}', 'Done(null)', reason: 'the queue went on');
        expect(ran.errors, ['the handler']);
      });

      test('a keepWhile that throws when a change of state re-checks it', () {
        _row(
          'A `keepWhile` that throws when a change of state re-checks it',
          '`onError`',
          '`onUnanswered`',
        );
        late Bench bench;
        late Job<void> job;
        var cancelledByIt = true;
        final ran = runFaked((async) {
          bench = Bench();
          job = bench.run<int, void>(
            key: 'kept',
            keepWhile: (state) =>
                state == 0 ? true : throw StateError('the rule'),
            (ctx) => stage.start<void>('op', null),
          )..ignoreFailure();
          async.flushMicrotasks();
          bench.reflect(1);
          async.flushMicrotasks();
          cancelledByIt = job.isCancelled;
          endCall(async, 'op');
        });

        expect(bench.heard, ['kept: the rule']);
        expect(bench.unanswered, ['kept: the rule']);
        expect(cancelledByIt, isFalse);
        expect('${job.outcome}', 'Done(null)');
        expect(ran.errors, ['the rule']);
      });

      test('work handed to ctx.unattended', () {
        _row(
          'An error of work handed to `ctx.unattended`',
          '`onError`',
          '`onUnanswered`',
        );
        late Bench bench;
        late Job<void> job;
        final ran = runFaked((async) {
          bench = Bench();
          job = bench.run<int, void>(key: 'hands', (ctx) async {
            ctx.unattended(() => stage.start<void>('work', null));
          });
          async.flushMicrotasks();
          _fail(async, 'work', StateError('the work'));
        });

        expect(bench.heard, ['hands: the work']);
        expect(bench.unanswered, ['hands: the work']);
        expect('${job.outcome}', 'Done(null)');
        expect(ran.errors, ['the work']);
      });

      test('the failure of a branch of runAll that the group did not throw',
          () {
        _row(
          'An error of a branch of `ctx.runAll` that the group did not throw',
          '`onError`',
          '`onUnanswered`, unless `ignoreFailure()` was called on the branch',
        );
        late Bench bench;
        late Job<void> job;
        final caught = <String>[];
        final ran = runFaked((async) {
          bench = Bench();
          job = bench.run<int, void>(key: 'group', (ctx) async {
            try {
              await ctx.runAll([
                bench.job<int, void>(
                  key: 'first',
                  (child) =>
                      child.abandonable(() => stage.start<void>('first', null)),
                ),
                bench.job<int, void>(
                  key: 'second',
                  cancellable: false,
                  (child) => child
                      .abandonable(() => stage.start<void>('second', null)),
                ),
              ]);
            } on Object catch (error) {
              caught.add(text(error));
            }
          });
          async.flushMicrotasks();
          _fail(async, 'first', StateError('first'));
          _fail(async, 'second', StateError('second'));
        });

        expect(caught, ['first'], reason: 'the group threw this one');
        expect(bench.heard, ['first: first', 'second: second']);
        expect(bench.unanswered, ['second: second']);
        expect('${job.outcome}', 'Done(null)');
        expect(ran.errors, ['second']);
      });

      test('a failure, and a cancellation before the error leaves the body',
          () {
        _row(
          'An error of the body, and the job ends `Cancelled`',
          '`onError`',
          '`onUnanswered`, unless `ignoreFailure()` was called on the job',
        );
        late Bench bench;
        late Job<void> job;
        Object? thrown;
        final ran = runFaked((async) {
          bench = Bench();
          job = waits(bench, 'covered');
          job.value.then<void>((_) {}, onError: (Object e) => thrown = e);
          async.flushMicrotasks();
          stage.fail('op', StateError('the call'));
          // One microtask later the job has seen the failure, and the body
          // has not thrown it yet.
          scheduleMicrotask(job.cancel);
        });

        expect('${job.outcome}', 'Cancelled(manual)');
        expect(thrown, same(job.outcome), reason: 'value gets the Cancelled');
        expect(bench.heard, ['covered: the call']);
        expect(bench.unanswered, ['covered: the call']);
        expect(ran.errors, ['the call']);
      });

      test('a failure, and a cancellation while the job waits for a child', () {
        late Bench bench;
        late Job<void> job;
        Object? thrown;
        final ran = runFaked((async) {
          bench = Bench();
          job = bench.run<int, void>(key: 'covered', (ctx) async {
            ctx
                .run(
                  bench.job<int, void>(
                    key: 'child',
                    (child) =>
                        child.join(() => stage.start<void>('child', null)),
                  ),
                )
                .ignore();
            throw StateError('the body');
          });
          job.value.then<void>((_) {}, onError: (Object e) => thrown = e);
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          endCall(async, 'child');
        });

        expect('${job.outcome}', 'Cancelled(manual)');
        expect(thrown, same(job.outcome));
        expect(bench.heard, ['covered: the body']);
        expect(bench.unanswered, ['covered: the body']);
        expect(ran.errors, ['the body']);
      });

      test('a failure, and a cancellation while the job runs its cleanup', () {
        late Bench bench;
        late Job<void> job;
        Object? thrown;
        final ran = runFaked((async) {
          bench = Bench();
          job = bench.run<int, void>(key: 'covered', (ctx) async {
            ctx.onDispose(() => stage.start<void>('release', null));
            throw StateError('the body');
          });
          job.value.then<void>((_) {}, onError: (Object e) => thrown = e);
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          endCall(async, 'release');
        });

        expect('${job.outcome}', 'Cancelled(manual)');
        expect(thrown, same(job.outcome));
        expect(bench.heard, ['covered: the body']);
        expect(bench.unanswered, ['covered: the body']);
        expect(ran.errors, ['the body']);
      });
    });

    for (final named in [false, true]) {
      test(
          named
              ? 'a failure after the cancellation that the app named goes no '
                  'further than onError'
              : 'a failure after the cancellation is answered for', () {
        if (named) {
          _row(
            'An error that `Job.isCancellationError` names, on a cancelled job',
            '`onError`',
            'Nobody',
          );
          _says(
            'A failure of a cancelled job that it names reaches `onError` '
            'and goes no further: neither `onUnanswered` nor '
            '`Solo.unansweredHandler` hears it',
          );
        } else {
          _says(
            'The last item of the list comes most often from the '
            'cancellation itself. A call that `ctx.join` is still waiting '
            'out stops at a token that `ctx.onCancel` cancelled, and throws '
            'as it stops',
          );
        }
        final handled = <String>[];
        late Bench bench;
        late Job<void> job;
        final ran = runFaked((async) {
          if (named) {
            Job.isCancellationError = (error) => error is _CallStopped;
          }
          Solo.unansweredHandler =
              (solo, job, error, stackTrace) => handled.add(text(error));
          bench = Bench();
          job = bench.run<int, void>(
            key: 'stopped',
            (ctx) => ctx.join(() => stage.start<void>('op', null)),
          );
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          _fail(async, 'op', const _CallStopped());
        });

        expect('${job.outcome}', 'Cancelled(manual)');
        expect(bench.heard, ['stopped: the call stopped']);
        expect(
          bench.unanswered,
          named ? isEmpty : ['stopped: the call stopped'],
        );
        expect(handled, named ? isEmpty : ['the call stopped']);
        expect(ran.errors, isEmpty, reason: 'the handler took what came');
      });
    }

    test('the handler of the page: one for the app, given the controller', () {
      _says(
        'one handler for the whole application, set once at startup',
      );
      final served = <String>[];
      final ran = runFaked((async) {
        Solo.unansweredHandler = (solo, job, error, stackTrace) =>
            served.add('${solo.runtimeType}: ${text(error)}');
        _dirtyCleanup(Bench());
        _dirtyCleanup(_ReportsAndReturns());
      });

      expect(served, ['Bench: disposer', '_ReportsAndReturns: disposer']);
      expect(ran.errors, isEmpty, reason: 'the handler took them');
    });

    test('with no handler set: the zone the job was created in', () {
      _says(
        'With no handler set, the error goes to the creation zone',
      );
      final where = <String, List<String>>{};
      fakeAsync((async) {
        late Bench bench;
        where['the controller was created'] = zoneOf(() => bench = Bench());
        where['the job was created'] = zoneOf(
          () => bench.run<int, void>(key: 'cleanup', (ctx) async {
            ctx.onDispose(() async => throw StateError('disposer'));
            await stage.start<void>('op', null);
          }),
        );
        where['the job ended'] = zoneOf(() {
          async.flushMicrotasks();
          endCall(async, 'op');
        });
      });

      expect(where, {
        'the controller was created': isEmpty,
        'the job was created': ['disposer'],
        'the job ended': isEmpty,
      });
    });

    test('each controller decides whether the handler hears its jobs', () {
      _says(
        'A controller without such an override keeps the default body. '
        'It hands the error to `Solo.unansweredHandler`',
      );
      _says(
        'So each controller decides whether the handler of the '
        'application hears its errors at all',
      );
      final served = <String>[];
      final ran = runFaked((async) {
        Solo.unansweredHandler =
            (solo, job, error, stackTrace) => served.add('${solo.runtimeType}');
        _dirtyCleanup(_AnswersInSilence());
        _dirtyCleanup(Bench());
      });

      expect(served, ['Bench']);
      expect(ran.errors, isEmpty);
    });

    test('an override that calls super keeps that route as well', () {
      _says(
        'An override keeps that route as well by calling '
        '`super.onUnanswered(job, error, stackTrace)`',
      );
      final handled = <String>[];
      late _AnswersAndCallsSuper controller;
      final ran = runFaked((async) {
        Solo.unansweredHandler =
            (solo, job, error, stackTrace) => handled.add(text(error));
        controller = _AnswersAndCallsSuper();
        _dirtyCleanup(controller);
        async.flushMicrotasks();
        Solo.unansweredHandler = null;
        _dirtyCleanup(controller);
      });

      expect(controller.kept, ['disposer', 'disposer']);
      expect(handled, ['disposer']);
      expect(ran.errors, ['disposer'], reason: 'the zone, with no handler');
    });

    /// A job that hands three pieces of work over: a wait with a failure
    /// beside a cancellation, a wait of nothing but cancellations, and a
    /// `Cancelled` alone.
    void handsWorkOver(Bench bench) =>
        bench.run<int, void>(key: 'waits', (ctx) async {
          ctx
            ..unattended(
              () => [
                Future<void>.error(StateError('a failure'), StackTrace.empty),
                Future<void>.error(const Cancelled('a'), StackTrace.empty),
              ].wait,
            )
            ..unattended(
              () => [
                Future<void>.error(const Cancelled('b'), StackTrace.empty),
                Future<void>.error(const Cancelled('c'), StackTrace.empty),
              ].wait,
            )
            ..unattended(() => throw const Cancelled('alone'));
        });

    test('the hook and the handler get one failure at a time', () {
      _says(
        '`onUnanswered` and `Solo.unansweredHandler` get one failure at '
        'a time. A `ParallelWaitError` that `[a, b].wait` throws with '
        'several errors in it comes as several calls, each failure with '
        'its own stack trace',
      );
      _says(
        'An uncaught `Cancelled`, alone or inside one, does not come at all',
      );
      final got = <String>[];
      late Bench bench;
      final ran = runFaked((async) {
        Solo.unansweredHandler =
            (solo, job, error, stackTrace) => got.add(text(error));
        bench = Bench();
        handsWorkOver(bench);
      });

      expect(got, ['a failure']);
      expect(bench.unanswered, ['waits: a failure']);
      expect(ran.errors, isEmpty);
    });

    test('the reporting hook hears them one at a time, each Cancelled too', () {
      _says(
        '`onError` hears them one at a time too, each `Cancelled` '
        'included',
      );
      late Bench bench;
      runFaked((async) {
        Solo.unansweredHandler = (solo, job, error, stackTrace) {};
        bench = Bench();
        handsWorkOver(bench);
      });

      expect(
        bench.heard,
        unorderedEquals([
          'waits: a failure',
          'waits: Cancelled(handler: a)',
          'waits: Cancelled(handler: b)',
          'waits: Cancelled(handler: c)',
          'waits: Cancelled(handler: alone)',
        ]),
      );
    });

    test('the handler of the page: each failure on its own, no Cancelled', () {
      final ran = runFaked((async) {
        answering.installUnansweredHandler();
        handsWorkOver(Bench());
      });

      expect(stage.sentry, ['a failure']);
      expect(ran.errors, isEmpty);
    });

    test('with no handler the zone gets the same failure', () {
      late Bench bench;
      final ran = runFaked((async) {
        bench = Bench();
        handsWorkOver(bench);
      });

      expect(bench.unanswered, ['waits: a failure']);
      expect(ran.errors, ['a failure'], reason: 'the one that failed');
    });

    test('a SoloObserver set, and still nobody answers', () {
      _says(
        'neither does setting a `SoloObserver`: watching is not '
        'answering',
      );
      final watching = Watching();
      final ran = runFaked((async) {
        Solo.observer = watching;
        _dirtyCleanup(Bench());
      });

      expect(watching.heard, ['cleanup: disposer']);
      expect(ran.errors, ['disposer']);
    });
  });
  group('Handled and unhandled failures', () {
    test('the page quotes two lines of a failure, then one', () {
      expect(_quoted().map((block) => block.length), [2, 1]);
    });

    /// Runs [body] under fake time and returns the lines of the page it
    /// printed: the reports, and what reached the zone.
    List<String> printed(void Function() body) {
      fakeAsync((async) {
        runZonedGuarded(
          body,
          (error, stackTrace) => stage.printed.add('zone: $error'),
        );
        async.flushTimers();
      });

      return stage.printed;
    }

    test('the lines of the page: a report, then the zone', () {
      final lines = printed(() {
        Solo.observer = first.Failures();
        Bench().run<int, void>(
          key: 'load',
          (ctx) async => throw StateError('no network'),
        );
      });

      expect(lines, _quoted()[0]);
    });

    test('the line of the page: a report, and the outcome observed', () {
      final lines = printed(() {
        Solo.observer = first.Failures();
        Bench()
            .run<int, void>(
              key: 'load',
              (ctx) async => throw StateError('no network'),
            )
            .ignoreFailure();
      });

      expect(lines, _quoted()[1]);
    });

    group('the first attempt:', () {
      test('a load that fails, and nobody waits for the result', () {
        // The section the first attempt sends its reader to.
        diagnosticsPage.says('An observer only watches');
        _says(
          'A hook that is told of a failure does not observe the outcome, '
          'whichever hook it is',
        );
        _says(
          'Nobody answers for that `Failed` either. `onUnanswered` of the '
          'controller hands it to `Solo.unansweredHandler`, and with no '
          'handler set to the creation zone through '
          '`Zone.handleUncaughtError`',
        );
        late Bench bench;
        final ran = runFaked((async) {
          Solo.observer = first.Failures();
          bench = Bench()
            ..run<int, void>(
              key: 'load',
              (ctx) async => throw StateError('no network'),
            );
        });

        expect(stage.crashes, ['no network'], reason: 'the reporter has it');
        expect(ran.errors, ['no network'], reason: 'and so has the zone');
        expect(bench.unanswered, ['load: no network']);
      });

      test('a load that is cancelled, and one that succeeds', () {
        final ran = runFaked((async) {
          Solo.observer = first.Failures();
          final bench = Bench()..run<int, void>(key: 'fine', (ctx) async {});
          final cancelled = waits(bench, 'cancelled')..ignoreFailure();
          async.flushMicrotasks();
          unawaited(cancelled.cancel());
        });

        expect(stage.crashes, isEmpty);
        expect(ran.errors, isEmpty);
      });

      test('a load that fails just before a cancellation reaches it', () {
        _says(
          'The report goes out, and then the same error reaches the zone',
        );
        late Bench bench;
        final ran = runFaked((async) {
          Solo.observer = first.Failures();
          bench = Bench();
          final load = waits(bench, 'load');
          async.flushMicrotasks();
          stage.fail('op', StateError('no network'));
          scheduleMicrotask(load.cancel);
          async.flushMicrotasks();
        });

        expect(stage.crashes, ['no network'], reason: 'the outcome is not it');
        expect(bench.unanswered, ['load: no network']);
        expect(ran.errors, ['no network'], reason: 'and so has the zone');
      });

      test('reported from onFinish, the failure reaches the zone all the same',
          () {
        _says(
          'whichever hook it is',
        );
        late Bench bench;
        final ran = runFaked((async) {
          Solo.observer = _FailuresOnFinish();
          bench = Bench()
            ..run<int, void>(
              key: 'load',
              (ctx) async => throw StateError('no network'),
            );
        });

        expect(stage.crashes, ['no network'], reason: 'the reporter has it');
        expect(ran.errors, ['no network'], reason: 'and so has the zone');
        expect(bench.unanswered, ['load: no network']);
      });
    });

    group('observing the outcome:', () {
      test('the line of the page: load() and ignoreFailure()', () {
        _says(
          '`ignoreFailure()` is for a caller that needs no result and '
          'leaves the reporting to the hooks',
        );
        late page.ProfileController profile;
        final ran = runFaked((async) {
          profile = page.ProfileController(ProfileApi());
          page.loadAndIgnore(profile);
          async.flushMicrotasks();
          _fail(async, 'fetchName', StateError('no network'));
        });

        expect(stage.crashes, ['no network'], reason: 'the hook reports it');
        expect('${profile.currentState}', 'Failure(Bad state: no network)');
        expect(ran.errors, isEmpty, reason: 'and nothing reaches the zone');
      });

      test('done, value with the error caught, outcome read and nothing more',
          () {
        _says(
          'Reading `job.done` or `job.value`, or calling '
          '`job.ignoreFailure()`, observes the outcome',
        );
        _says('Reading `job.outcome` does not.');
        final caught = <String>[];
        String? read;
        final ran = runFaked((async) {
          final bench = Bench();
          SoloJob<void> failing(String key) => bench.run<int, void>(
                key: key,
                (ctx) async => throw StateError(key),
              );
          unawaited(failing('done').done);
          failing('value').value.then<void>(
                (_) {},
                onError: (Object error) => caught.add(text(error)),
              );
          final job = failing('outcome');
          async.flushMicrotasks();
          read = '${job.outcome}';
        });

        expect(caught, ['value'], reason: 'the caller answers by catching it');
        expect(read, 'Failed(Bad state: outcome)');
        expect(ran.errors, ['outcome'], reason: 'reading outcome observes not');
      });

      /// Cancels [job] one microtask after the call behind its
      /// `ctx.abandonable` fails: the job has seen the failure, and the body
      /// has not thrown it yet.
      void failThenCancel(FakeAsync async, Job<Object?> job) {
        stage.fail('fetchName', StateError('no network'));
        scheduleMicrotask(job.cancel);
        async.flushMicrotasks();
      }

      test('the load fails, and a cancellation reaches the job afterwards', () {
        _says(
          'That caller cannot catch one failure. If the job ends '
          '`Cancelled` after the load failed, `await job.value` throws '
          'the `Cancelled`. The failure goes to `onUnanswered`',
        );
        final handled = <String>[];
        Object? thrown;
        late Job<String> job;
        late page.ProfileController profile;
        final ran = runFaked((async) {
          Solo.unansweredHandler =
              (solo, job, error, stackTrace) => handled.add(text(error));
          profile = page.ProfileController(ProfileApi());
          job = profile.load();
          job.value.then<void>((_) {}, onError: (Object e) => thrown = e);
          async.flushMicrotasks();
          failThenCancel(async, job);
        });

        expect('${job.outcome}', 'Cancelled(manual)');
        expect(thrown, same(job.outcome));
        expect('${profile.currentState}', 'Initial');
        expect(stage.crashes, ['no network'], reason: 'the hook was told');
        expect(handled, ['no network'], reason: 'and somebody had to answer');
        expect(ran.errors, isEmpty);
      });

      test('the same with ignoreFailure() on the job', () {
        _says(
          '`ignoreFailure()` lets that failure go too',
        );
        final handled = <String>[];
        late Job<String> job;
        final ran = runFaked((async) {
          Solo.unansweredHandler =
              (solo, job, error, stackTrace) => handled.add(text(error));
          job = page.ProfileController(ProfileApi()).load()..ignoreFailure();
          async.flushMicrotasks();
          failThenCancel(async, job);
        });

        expect('${job.outcome}', 'Cancelled(manual)');
        expect(stage.crashes, ['no network'], reason: 'the hook is still told');
        expect(handled, isEmpty);
        expect(ran.errors, isEmpty);
      });
    });

    test('an abandoned call that fails once its job has completed', () {
      _row(
        'A late error of an operation `abandonable` stopped waiting for',
        '`onError`',
        '`onUnanswered`',
      );
      _says(
        'The way to the creation zone through `onUnanswered` is the '
        "application's to close: an override of `onUnanswered` or an "
        'installed `Solo.unansweredHandler` closes it',
      );
      _says(
        'With no handler set, the error goes to the creation zone',
      );
      _says(
        'An error that `onUnanswered` takes can come after the job has '
        'completed',
      );
      _says(
        'It does not replace the outcome the job already has',
      );
      late Bench bench;
      late Job<void> job;
      var heardBefore = -1;
      final ran = runFaked((async) {
        bench = Bench();
        job = waits(bench, 'abandons')..ignoreFailure();
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        heardBefore = job.isFinished ? bench.heard.length : -1;
        _fail(async, 'op', StateError('late'));
      });

      expect(heardBefore, 0, reason: 'the job was over, and nothing was told');
      expect(bench.heard, ['abandons: late']);
      expect(bench.unanswered, ['abandons: late']);
      expect('${job.outcome}', 'Cancelled(manual)');
      expect(ran.errors, ['late']);
    });

    for (final withHandler in [true, false]) {
      test(
          'an abandoned call that ends in a Cancelled, '
          '${withHandler ? 'a handler set' : 'no handler'}', () {
        _row(
          'A `Cancelled` from outside the body, such as an abandoned '
              "operation that ended in another job's cancellation",
          '`onError`',
          'Nobody',
        );
        final handled = <String>[];
        final watching = Watching();
        late Bench bench;
        final ran = runFaked((async) {
          Solo.observer = watching;
          if (withHandler) {
            Solo.unansweredHandler =
                (solo, job, error, stackTrace) => handled.add(text(error));
          }
          bench = Bench();
          final job = waits(bench, 'abandons')..ignoreFailure();
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          _fail(async, 'op', const Cancelled('of another job'));
        });

        const line = 'abandons: Cancelled(handler: of another job)';
        expect(bench.heard, [line]);
        expect(watching.heard, [line]);
        expect(bench.unanswered, isEmpty);
        expect(handled, isEmpty);
        expect(ran.errors, isEmpty);
      });
    }

    test('an abandoned call that throws back the cancellation of its job', () {
      _row(
        "The job's own cancellation, thrown back by an abandoned operation",
        'Nobody',
        'Nobody',
      );
      final watching = Watching();
      late Bench bench;
      late Job<void> job;
      final ran = runFaked((async) {
        Solo.observer = watching;
        bench = Bench();
        job = bench.run<int, void>(
          key: 'abandons',
          (ctx) => ctx.abandonable(() async {
            await stage.start<void>('op', null);
            ctx.check();
          }),
        )..ignoreFailure();
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        endCall(async, 'op');
      });

      expect('${job.outcome}', 'Cancelled(manual)');
      expect(bench.heard, isEmpty);
      expect(watching.heard, isEmpty);
      expect(bench.unanswered, isEmpty);
      expect(ran.errors, isEmpty);
    });

    test('the value of a cancelled job, taken and not handled', () {
      _says(
        'Dart has a way of its own to the zone, and the engine does not '
        'stand on it',
      );
      _says(
        'An unhandled error of `job.value` or of `ctx.run(child)` is an '
        'unhandled future error under the rules of Dart, even when that '
        'error is `Cancelled`',
      );
      late Bench bench;
      final ran = runFaked((async) {
        bench = Bench();
        final job = waits(bench, 'value');
        unawaited(job.value.then((_) {}));
        async.flushMicrotasks();
        unawaited(job.cancel());
      });

      expect(ran.errors, ['Cancelled(manual)']);
      expect(bench.heard, isEmpty, reason: 'no hook is told');
    });

    test('ctx.run(child) not awaited, and the child is cancelled', () {
      late Job<void> job;
      final ran = runFaked((async) {
        final bench = Bench();
        late SoloJob<void> child;
        job = bench.run<int, void>(key: 'parent', (ctx) async {
          child = bench.job<int, void>(
            key: 'child',
            (c) => c.abandonable(() => stage.start<void>('op', null)),
          );
          unawaited(ctx.run(child));
          await ctx.join(() => stage.start<void>('body', null));
        });
        async.flushMicrotasks();
        unawaited(child.cancel());
        async.flushMicrotasks();
        endCall(async, 'body');
      });

      expect(ran.errors, ['Cancelled(manual)']);
      expect('${job.outcome}', 'Done(null)');
    });

    test('job.ignoreFailure() on a job whose value is already taken', () {
      _says(
        'Handle those futures like any other: `await` them where the '
        'error is caught, or give them `onError` or `Future.ignore()`. '
        '`job.ignoreFailure()` does not do it for them. It tells the '
        'job that nobody needs its failure. A future already taken '
        'from `job.value` stays an ordinary future whose error somebody '
        'has to handle',
      );
      final caught = <String>[];
      final ran = runFaked((async) {
        SoloJob<void> cancelled(Bench bench) {
          final job = waits(bench, 'value');
          scheduleMicrotask(() => scheduleMicrotask(job.cancel));

          return job;
        }

        final taken = cancelled(Bench());
        // Taken, and Job.ignoreFailure after it: the future is still nobody's.
        final value = taken.value;
        taken.ignoreFailure();
        expect(value, isA<Future<void>>());
        async.flushMicrotasks();

        // Future.ignore on the future itself, and onError on another.
        cancelled(Bench()).value.ignore();
        unawaited(
          cancelled(Bench()).value.onError<Cancelled>(
                (error, stackTrace) => caught.add('$error'),
              ),
        );
      });

      expect(ran.errors, ['Cancelled(manual)'], reason: 'the first one alone');
      expect(caught, ['Cancelled(manual)']);
    });
  });

  group('Where each error goes', () {
    // Each row is pinned by the test that runs it, in the section it comes
    // from or below; this test holds the order and the number of rows.
    test('the table names who hears each error and who answers for it', () {
      final lines = _page().split('\n');
      final start = lines.indexOf(
        '| The error | Who hears it | Who answers for it |',
      );
      final rows = [
        for (final line
            in lines.skip(start + 2).takeWhile((l) => l.startsWith('|')))
          [for (final cell in line.split('|').skip(1).take(3)) cell.trim()],
      ];

      const callbacks = 'An error of a disposer, a `ctx.onCancel` callback, a '
          '`whenCancelled` or `whenFinished` listener, or a state handler of '
          '`run`';
      const fromOutside = 'A `Cancelled` from outside the body, such as an '
          "abandoned operation that ended in another job's cancellation";
      expect(rows, [
        [
          'An error of the body, and the job ends `Failed` with it',
          '`onError`',
          'Whoever observes the outcome; `onUnanswered` if nobody does',
        ],
        [
          'An error of a start rule: `canStart` throws instead of answering',
          '`onError`',
          'The same: the job ends `Failed` with it',
        ],
        [
          'An error of the body, and the job ends `Cancelled`',
          '`onError`',
          '`onUnanswered`, unless `ignoreFailure()` was called on the job',
        ],
        [
          'A late error of an operation `abandonable` stopped waiting for',
          '`onError`',
          '`onUnanswered`',
        ],
        [
          callbacks,
          '`onError`',
          '`onUnanswered`',
        ],
        [
          'A `keepWhile` that throws when a change of state re-checks it',
          '`onError`',
          '`onUnanswered`',
        ],
        [
          'An error of work handed to `ctx.unattended`',
          '`onError`',
          '`onUnanswered`',
        ],
        [
          'An error of a branch of `ctx.runAll` that the group did not throw',
          '`onError`',
          '`onUnanswered`, unless `ignoreFailure()` was called on the branch',
        ],
        [
          'An error that `Job.isCancellationError` names, on a cancelled job',
          '`onError`',
          'Nobody',
        ],
        [
          fromOutside,
          '`onError`',
          'Nobody',
        ],
        [
          'A `Cancelled` the body lets out, such as that of a cancelled child',
          'Nobody',
          'Nobody: the job ends `Cancelled` with it',
        ],
        [
          "The job's own cancellation, thrown back by an abandoned operation",
          'Nobody',
          'Nobody',
        ],
        [
          'An error of a future the body did not await',
          'Nobody',
          'The zone the body runs in',
        ],
        ['An error a hook throws', 'Nobody', 'The current zone'],
        [
          'An error a listener throws while it is notified',
          '`onListenerError`',
          '`onListenerError`; by default the current zone',
        ],
      ]);
    });

    test('a listener that throws: onListenerError, by default the zone', () {
      _row(
        'An error a listener throws while it is notified',
        '`onListenerError`',
        '`onListenerError`; by default the current zone',
      );
      late Bench bench;
      final errors = zoneOf(() {
        bench = Bench()
          ..addListener(() => throw StateError('listener'))
          ..reflect(1);
      });

      expect(errors, ['listener'], reason: 'the current zone');
      expect(bench.heard, isEmpty, reason: 'onError hears no listener');
      expect(bench.unanswered, isEmpty);
    });

    test('a Cancelled the body lets out: nobody, the outcome is that', () {
      _row(
        'A `Cancelled` the body lets out, such as that of a cancelled child',
        'Nobody',
        'Nobody: the job ends `Cancelled` with it',
      );
      final watching = Watching();
      late Bench bench;
      late Job<void> job;
      final ran = runFaked((async) {
        Solo.observer = watching;
        bench = Bench();
        late SoloJob<void> child;
        job = bench.run<int, void>(key: 'parent', (ctx) async {
          child = bench.job<int, void>(
            key: 'child',
            (c) => c.abandonable(() => stage.start<void>('op', null)),
          );
          await ctx.run(child);
        });
        async.flushMicrotasks();
        unawaited(child.cancel());
      });

      expect(job.outcome, isA<Cancelled>());
      expect(bench.heard, isEmpty);
      expect(watching.heard, isEmpty);
      expect(bench.unanswered, isEmpty);
      expect(ran.errors, isEmpty);
    });

    test('a branch of runAll the group did not throw, and ignoreFailure()', () {
      late Bench bench;
      final ran = runFaked((async) {
        bench = Bench();
        final second = bench.job<int, void>(
          key: 'second',
          cancellable: false,
          (child) => child.abandonable(() => stage.start<void>('second', null)),
        )..ignoreFailure();
        bench.run<int, void>(key: 'group', (ctx) async {
          try {
            await ctx.runAll([
              bench.job<int, void>(
                key: 'first',
                (child) =>
                    child.abandonable(() => stage.start<void>('first', null)),
              ),
              second,
            ]);
          } on Object catch (_) {}
        });
        async.flushMicrotasks();
        _fail(async, 'first', StateError('first'));
        _fail(async, 'second', StateError('second'));
      });

      expect(bench.heard, ['first: first', 'second: second']);
      expect(bench.unanswered, isEmpty);
      expect(ran.errors, isEmpty);
    });

    test('a hook of a job throws into the zone the job was created in', () {
      _says(
        'For what happens in a job, that is the zone the job was created '
        'in; for a change made by `externalSetState`, the zone of its '
        'caller',
      );
      final where = <String, List<String>>{};
      fakeAsync((async) {
        late EveryHook controller;
        where['the controller was created'] = zoneOf(
          () => controller = EveryHook([], throwOn: 'onFinish'),
        );
        where['the job was created'] = zoneOf(
          () => controller.run<int, void>(
            key: 'job',
            (ctx) => ctx.abandonable(() => stage.start<void>('op', null)),
          ),
        );
        where['the job started'] = zoneOf(async.flushMicrotasks);
        where['the job ended'] = zoneOf(() => endCall(async, 'op'));
      });

      expect(where, {
        'the controller was created': isEmpty,
        'the job was created': ['controller.onFinish threw'],
        'the job started': isEmpty,
        'the job ended': isEmpty,
      });
    });
  });

  group('Catching errors inside a body', () {
    /// The two versions of the page on one scenario each: the first attempt
    /// and the catch that asks the job.
    final versions = <String, (Solo<CameraState>, SoloJob<void>) Function()>{
      'the first attempt': () {
        final camera = first.BroadCamera(Hardware());

        return (camera, camera.open(2));
      },
      'the catch that asks the job': () {
        final camera = page.Camera(Hardware());

        return (camera, camera.open(2));
      },
    };

    for (final MapEntry(key: name, value: start) in versions.entries) {
      final asks = name != 'the first attempt';

      group('$name:', () {
        test('cancelled while hw.setZoom is in flight', () {
          if (asks) {
            _says(
              '`ctx.check()` asks the job, not the error. It throws the '
              "job's `Cancelled` if the job has accepted one, whatever the "
              'catch took. What follows it handles the failures of a job that '
              'nobody cancelled',
            );
          } else {
            _says(
              'The user cancels this job while `hw.setZoom` is in flight. '
              'Nothing failed, and the camera is reset',
            );
            _says(
              '`join` waits the call out and then throws `Cancelled` in place '
              'of its result',
            );
            _says(
              'so the broad `catch` takes it and reads it as a failure of the '
              'camera. It resets a camera that opened and took its zoom',
            );
            _says(
              'The job ends exactly as a cancelled job should. Neither the '
              'hooks nor the zone mention anything, and the only trace is on '
              'the device',
            );
          }
          late Desk<CameraState> camera;
          late Job<void> job;
          final ran = runFaked((async) {
            final (controller, started) = start();
            camera = controller as Desk<CameraState>;
            job = started..ignoreFailure();
            async.flushMicrotasks();
            endCall(async, 'open');
            unawaited(job.cancel());
            async.flushMicrotasks();
            endCall(async, 'setZoom');
          });

          expect(stage.trace, [
            'open start',
            'open end',
            'setZoom start',
            'setZoom end',
            if (!asks) ...['reset start', 'reset end'],
          ]);
          expect('${job.outcome}', 'Cancelled(manual)');
          expect('${camera.currentState}', 'Closed');
          expect(camera.heard, isEmpty);
          expect(camera.unanswered, isEmpty);
          expect(ran.errors, isEmpty);
        });

        test('cancelled while hw.open is in flight', () {
          late Job<void> job;
          String? whileItOpens;
          runFaked((async) {
            final (_, started) = start();
            job = started..ignoreFailure();
            async.flushMicrotasks();
            unawaited(job.cancel());
            async.flushMicrotasks();
            whileItOpens = '${job.outcome}';
            endCall(async, 'open');
          });

          expect(whileItOpens, 'null', reason: 'join waits the call out');
          expect(stage.trace, [
            'open start',
            'open end',
            if (!asks) ...['reset start', 'reset end'],
          ]);
          expect('${job.outcome}', 'Cancelled(manual)');
        });

        test('closed while hw.setZoom is in flight, and the reset takes time',
            () {
          if (!asks) {
            _says(
              'Whoever cancelled the job waits for the reset as well',
            );
          }
          var backAfterTheCall = false;
          var resetStarted = false;
          runFaked((async) {
            stage.endsByItself.remove('reset');
            final (camera, started) = start();
            started.ignoreFailure();
            async.flushMicrotasks();
            endCall(async, 'open');
            var back = false;
            camera.close().then((_) => back = true);
            async.flushMicrotasks();
            endCall(async, 'setZoom');
            backAfterTheCall = back;
            resetStarted = stage.isRunning('reset');
            if (resetStarted) endCall(async, 'reset');
          });

          expect(resetStarted, !asks);
          expect(backAfterTheCall, asks, reason: 'close() waits for the reset');
        });

        test('nobody cancels, and hw.open fails', () {
          late Desk<CameraState> camera;
          late Job<void> job;
          runFaked((async) {
            final (controller, started) = start();
            camera = controller as Desk<CameraState>;
            job = started..ignoreFailure();
            async.flushMicrotasks();
            _fail(async, 'open', StateError('no camera'));
          });

          expect(stage.trace, [
            'open start',
            'open failed',
            'reset start',
            'reset end',
          ]);
          expect('${camera.currentState}', 'Broken(no camera)');
          expect('${job.outcome}', 'Failed(Bad state: no camera)');
          expect(camera.heard, ['open: no camera']);
        });

        test('nobody cancels, and hw.setZoom fails', () {
          late Desk<CameraState> camera;
          late Job<void> job;
          runFaked((async) {
            final (controller, started) = start();
            camera = controller as Desk<CameraState>;
            job = started..ignoreFailure();
            async.flushMicrotasks();
            endCall(async, 'open');
            _fail(async, 'setZoom', StateError('no zoom'));
          });

          expect(stage.trace.sublist(4), ['reset start', 'reset end']);
          expect('${camera.currentState}', 'Broken(no zoom)');
          expect('${job.outcome}', 'Failed(Bad state: no zoom)');
        });

        test('cancelled, and then hw.open fails on its own', () {
          if (asks) {
            _says(
              'A camera that fails on its own after the job accepted a '
              'cancellation is not reset by this catch either, and no hook '
              'hears of the failure',
            );
          }
          late Desk<CameraState> camera;
          late Job<void> job;
          final ran = runFaked((async) {
            final (controller, started) = start();
            camera = controller as Desk<CameraState>;
            job = started..ignoreFailure();
            async.flushMicrotasks();
            unawaited(job.cancel());
            async.flushMicrotasks();
            _fail(async, 'open', StateError('no camera'));
          });

          expect(stage.trace, [
            'open start',
            'open failed',
            if (!asks) ...['reset start', 'reset end'],
          ]);
          expect('${job.outcome}', 'Cancelled(manual)');
          expect('${camera.currentState}', 'Closed');
          expect(camera.heard, isEmpty);
          expect(ran.errors, isEmpty);
        });

        test('nobody cancels, and nothing fails', () {
          late Job<void> job;
          runFaked((async) {
            final (_, started) = start();
            job = started;
            async.flushMicrotasks();
            endCall(async, 'open');
            endCall(async, 'setZoom');
          });

          expect(stage.trace, hasLength(4), reason: 'no reset');
          expect('${job.outcome}', 'Done(null)');
        });
      });
    }

    test('Cancelled implements Exception', () {
      _says(
        '`Cancelled` implements `Exception`, so the broad `catch` takes '
        'it',
      );
      expect(const Cancelled('why'), isA<Exception>());
    });

    test('on a cancelled job emit throws, and the rethrow never runs', () {
      _says(
        '`ctx.emit` on a cancelled job throws `Cancelled` in turn. '
        '`Broken` never reaches the screen, and the `rethrow` under it '
        'never runs',
      );
      _says(
        'The outcome is the same `Cancelled` that `rethrow` would have '
        'given',
      );
      fakeAsync((async) {
        final bench = Bench();
        Object? fromJoin;
        Object? fromEmit;
        var reachedTheRethrow = false;
        final job = bench.run<int, void>(key: 'broad', (ctx) async {
          try {
            await ctx.join(() => stage.start<void>('op', null));
          } on Object catch (error) {
            fromJoin = error;
            try {
              ctx.emit(-1);
            } on Object catch (thrown) {
              fromEmit = thrown;
              rethrow;
            }
            reachedTheRethrow = true;
            rethrow;
          }
        })
          ..ignoreFailure();
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        endCall(async, 'op');

        expect(fromJoin, isA<Cancelled>());
        expect(fromEmit, same(fromJoin));
        expect(job.outcome, same(fromJoin));
        expect(reachedTheRethrow, isFalse);
        expect(bench.currentState, 0);
      });
    });

    for (final clause in ['on Cancelled', 'error is Cancelled']) {
      test('a clause for the error, "$clause", and a camera with a token', () {
        _says(
          'Take `on Cancelled { rethrow; }` in front of the broad clause, '
          'or `if (error is Cancelled) rethrow;` as its first line. It '
          'holds while every call in the `try` runs to its end',
        );
        _says(
          'The clause lets that error by, and the camera is reset for a '
          'cancellation again',
        );
        late _TokenCamera camera;
        late Job<void> job;
        runFaked((async) {
          camera = _TokenCamera();
          job = camera.open(clause)..ignoreFailure();
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          endCall(async, 'open');
        });

        expect(stage.trace, [
          'open start',
          'open end',
          'open stopped',
          'reset start',
          'reset end',
        ]);
        expect('${job.outcome}', 'Cancelled(manual)');
        expect(camera.heard, isEmpty);
      });

      test('"$clause", and a camera that fails with nobody cancelling', () {
        late _TokenCamera camera;
        late Job<void> job;
        runFaked((async) {
          camera = _TokenCamera();
          job = camera.open(clause)..ignoreFailure();
          async.flushMicrotasks();
          _fail(async, 'open', StateError('no camera'));
        });

        expect(stage.trace.sublist(2), ['reset start', 'reset end']);
        expect('${camera.currentState}', 'Broken(no camera)');
        expect('${job.outcome}', 'Failed(Bad state: no camera)');
      });
    }

    test('the catch that asks the job, and a camera with a token', () {
      _says(
        'may stop by throwing. Then the catch gets an error of the call '
        'in place of the `Cancelled`, because `join` throws an error of '
        'its call as it is',
      );
      late _TokenCamera camera;
      late Job<void> job;
      runFaked((async) {
        camera = _TokenCamera();
        job = camera.open('ctx.check()')..ignoreFailure();
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        endCall(async, 'open');
      });

      expect(stage.trace, ['open start', 'open end', 'open stopped']);
      expect('${job.outcome}', 'Cancelled(manual)');
      expect(camera.heard, isEmpty, reason: 'the error never left the body');
    });

    test('a body that catches its cancellation and returns a value', () {
      _says(
        'Once a job has accepted a cancellation, its outcome stays '
        '`Cancelled` even if the body catches it',
      );
      fakeAsync((async) {
        final bench = Bench();
        final job = bench.run<int, int>(key: 'swallows', (ctx) async {
          try {
            await ctx.abandonable(() => stage.start<void>('op', null));
          } on Cancelled {
            // caught and not rethrown
          }

          return 42;
        })
          ..ignoreFailure();
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();

        expect('${job.outcome}', 'Cancelled(manual)');
      });
    });

    test('the failure state through the ifFailed parameter of run', () {
      _says(
        'For a final failure state, use the `ifFailed` parameter of '
        '`run` rather than a broad catch',
      );
      fakeAsync((async) {
        SoloJob<void> open(Bench bench) => bench.run<int, void>(
              key: 'open',
              ifFailed: (state, error, stackTrace) => -1,
              (ctx) => ctx.join(() => stage.start<void>('op', null)),
            )..ignoreFailure();

        final failing = Bench();
        final failed = open(failing);
        async.flushMicrotasks();
        _fail(async, 'op', StateError('no camera'));

        final stopping = Bench();
        final cancelled = open(stopping);
        async.flushMicrotasks();
        unawaited(cancelled.cancel());
        async.flushMicrotasks();
        endCall(async, 'op');

        expect('${failed.outcome}', 'Failed(Bad state: no camera)');
        expect(failing.currentState, -1);
        expect('${cancelled.outcome}', 'Cancelled(manual)');
        expect(stopping.currentState, 0, reason: 'no failure state for it');
      });
    });
  });

  group('Retrying a failed call', () {
    /// The two versions of the page, each in a profile of its own.
    final versions = <String, (Desk<ProfileState>, SoloJob<String>) Function()>{
      'the first attempt': () {
        final profile = first.DelayingProfile(ProfileApi());

        return (profile, profile.load());
      },
      'the pause between attempts': () {
        final profile = page.RetryingProfile(ProfileApi());

        return (profile, profile.load());
      },
    };

    /// Sends a job to [profile] that notes in [events] when it runs.
    void sendNext(
      Desk<ProfileState> profile,
      FakeAsync async,
      List<String> events,
    ) =>
        (profile as OpenSolo<ProfileState>).run<ProfileState, void>(
          key: 'next',
          (ctx) async => events.add('next ran at ${async.elapsed.inSeconds} s'),
        );

    /// Notes in [events] when [job] ends.
    void noteEnd(SoloJob<String> job, FakeAsync async, List<String> events) =>
        unawaited(
          job.done.then(
            (_) => events.add('load ended at ${async.elapsed.inSeconds} s'),
          ),
        );

    for (final MapEntry(key: name, value: start) in versions.entries) {
      final pauses = name != 'the first attempt';
      final after = pauses ? 0 : 3;

      group('$name:', () {
        test('cancelled while the first call is in flight', () {
          if (pauses) {
            _says(
              'If the catch has taken a cancellation, the pause throws it '
              'again before it waits',
            );
            _says(
              'the pause asks the job, not the error, so the catch needs no '
              'clause for the cancellation',
            );
          } else {
            _says(
              '1. `abandonable` throws `Cancelled`. The catch counts it as a '
              'failed attempt and waits a second. 2. A plain `Future.delayed` '
              'is no checkpoint, so the job sits that second out. 3. The next '
              '`abandonable` throws at once, without calling `fetchName`, and '
              'the catch waits two seconds more. 4. Only the third throw goes '
              'out. The job ends `Cancelled` three seconds after it was '
              'cancelled. All that time the job holds the queue. The next job '
              'waits for a body that has nothing left to do',
            );
          }
          late Desk<ProfileState> profile;
          late SoloJob<String> job;
          final events = <String>[];
          final ran = runFaked((async) {
            final (controller, started) = start();
            profile = controller;
            job = started;
            noteEnd(job, async, events);
            async.flushMicrotasks();
            unawaited(job.cancel());
            sendNext(profile, async, events);
            async.elapse(const Duration(seconds: 5));
          });

          // The next job starts with the end of the load, a microtask before
          // `done` tells of it.
          expect(
            events,
            unorderedEquals(['load ended at $after s', 'next ran at $after s']),
          );
          expect(stage.trace, ['fetchName start'], reason: 'called once');
          expect('${job.outcome}', 'Cancelled(manual)');
          expect('${profile.currentState}', 'Initial');
          expect(profile.heard, isEmpty);
          expect(ran.errors, isEmpty);
        });

        test('closed while the first call is in flight', () {
          if (!pauses) {
            _says('The next job waits for a body that has nothing left to '
                'do, and so does `close()`');
          }
          final events = <String>[];
          final ran = runFaked((async) {
            final (profile, job) = start();
            noteEnd(job, async, events);
            async.flushMicrotasks();
            unawaited(
              profile.close().then(
                    (_) => events.add('closed at ${async.elapsed.inSeconds} s'),
                  ),
            );
            async.elapse(const Duration(seconds: 5));
          });

          expect(events, ['load ended at $after s', 'closed at $after s']);
          expect(ran.errors, isEmpty);
        });

        test('three failures end the job Failed with the third', () {
          if (pauses) {
            _says(
              'After the third failure of the network, `rethrow` lets it out, '
              'and the job ends `Failed` with that error',
            );
          }
          late Desk<ProfileState> profile;
          late SoloJob<String> job;
          final calling = <bool>[];
          final ran = runFaked((async) {
            final (controller, started) = start();
            profile = controller;
            job = started..ignoreFailure();
            async.flushMicrotasks();
            _fail(async, 'fetchName', StateError('no network 1'));
            for (final seconds in [1, 2]) {
              async.elapse(Duration(milliseconds: seconds * 1000 - 1));
              calling.add(stage.isRunning('fetchName'));
              async.elapse(const Duration(milliseconds: 1));
              calling.add(stage.isRunning('fetchName'));
              final error = StateError('no network ${seconds + 1}');
              _fail(async, 'fetchName', error);
            }
          });

          expect(
            calling,
            [false, true, false, true],
            reason: 'the second call a second later, the third two more',
          );
          expect('${job.outcome}', 'Failed(Bad state: no network 3)');
          expect('${profile.currentState}', 'Failure(Bad state: no network 3)');
          expect(
            profile.heard,
            ['load: no network 3'],
            reason: "the failures the catch took are nobody else's",
          );
          expect(ran.errors, isEmpty);
        });

        test('a failure, then the name', () {
          late Desk<ProfileState> profile;
          late SoloJob<String> job;
          final ran = runFaked((async) {
            final (controller, started) = start();
            profile = controller;
            job = started;
            async.flushMicrotasks();
            _fail(async, 'fetchName', StateError('no network'));
            async.elapse(const Duration(seconds: 1));
            endCall(async, 'fetchName');
          });

          expect('${job.outcome}', 'Done(Ada Lovelace)');
          expect('${profile.currentState}', 'Loaded(Ada Lovelace)');
          expect(ran.errors, isEmpty);
        });
      });
    }

    test('the try holds the call alone: a failed delivery is no attempt', () {
      late SoloJob<String> job;
      final ran = runFaked((async) {
        job = _FailingDelivery().load()..ignoreFailure();
        async.flushMicrotasks();
        endCall(async, 'fetchName');
        async.elapse(const Duration(seconds: 5));
      });

      expect(stage.trace, ['fetchName start', 'fetchName end']);
      expect('${job.outcome}', 'Failed(Bad state: delivery)');
      expect(ran.errors, isEmpty);
    });

    test('a clause for the network lets a bug end the job at once', () {
      _says(
        '`on Object` repeats every failure of the call, a bug in '
        'reading the answer among them. A clause for the failures worth '
        'repeating, such as `on SocketException`, lets a bug end the '
        'job at once. It still needs nothing for the cancellation',
      );
      // Not on the page: the loop of the page with the narrower clause.
      SoloJob<String> load(Bench bench) => bench.run<int, String>(
            key: 'load',
            (ctx) async {
              for (var attempt = 1;; attempt++) {
                final String name;
                try {
                  name = await ctx.abandonable(ProfileApi().fetchName);
                } on SocketException {
                  if (attempt == 3) rethrow;
                  await ctx.pause(Duration(seconds: attempt));
                  continue;
                }
                return name;
              }
            },
          )..ignoreFailure();

      final ended = <String>[];
      late SoloJob<String> bug;
      late SoloJob<String> network;
      late SoloJob<String> cancelled;
      final ran = runFaked((async) {
        bug = load(Bench());
        noteEnd(bug, async, ended);
        async.flushMicrotasks();
        _fail(async, 'fetchName', ArgumentError('no name in the answer'));

        network = load(Bench());
        async.flushMicrotasks();
        _fail(async, 'fetchName', const SocketException('no network'));
        async.elapse(const Duration(seconds: 1));
        endCall(async, 'fetchName');

        cancelled = load(Bench());
        noteEnd(cancelled, async, ended);
        async.flushMicrotasks();
        unawaited(cancelled.cancel());
        async.flushMicrotasks();
      });

      expect(
        '${bug.outcome}',
        'Failed(Invalid argument(s): no name in the answer)',
      );
      expect('${network.outcome}', 'Done(Ada Lovelace)');
      expect('${cancelled.outcome}', 'Cancelled(manual)');
      expect(ended, ['load ended at 0 s', 'load ended at 1 s']);
      final calls = stage.trace.where((line) => line == 'fetchName start');
      expect(calls, hasLength(4), reason: 'one, two, one');
      expect(ran.errors, isEmpty);
    });

    test('a cancellation during a pause ends it there, timer and all', () {
      _says(
        'A cancellation that comes during a pause ends the pause there '
        'and cancels its timer. Either way the job ends `Cancelled` at '
        'once',
      );
      late SoloJob<String> job;
      final events = <String>[];
      late int timers;
      final ran = runFaked((async) {
        final profile = page.RetryingProfile(ProfileApi());
        job = profile.load();
        noteEnd(job, async, events);
        async.flushMicrotasks();
        _fail(async, 'fetchName', StateError('no network'));
        async.elapse(const Duration(milliseconds: 500));
        unawaited(job.cancel());
        async.flushMicrotasks();
        events.add('cancelled at ${async.elapsed.inMilliseconds} ms');
        timers = async.pendingTimers.length;
      });

      expect(events, ['load ended at 0 s', 'cancelled at 500 ms']);
      expect(timers, 0);
      expect('${job.outcome}', 'Cancelled(manual)');
      expect(ran.errors, isEmpty);
    });

    test('the pauses hold the queue', () {
      _says(
        'Root jobs run one at a time, so the next job of the profile waits '
        'through every attempt and every pause between them',
      );
      final events = <String>[];
      final ran = runFaked((async) {
        final profile = page.RetryingProfile(ProfileApi());
        noteEnd(profile.load(), async, events);
        async.flushMicrotasks();
        _fail(async, 'fetchName', StateError('no network'));
        sendNext(profile, async, events);
        async.elapse(const Duration(seconds: 1));
        endCall(async, 'fetchName');
      });

      expect(events, unorderedEquals(['load ended at 1 s', 'next ran at 1 s']));
      expect(ran.errors, isEmpty);
    });

    test('the loop in the body stays Loading between the attempts', () {
      _says(
        'With the loop in the body, the state stays `Loading` '
        'throughout',
      );
      _says(
        'so the crash reporter hears each one. The loop in the body let '
        'it hear only the failure that ended the job',
      );
      final states = <String>[];
      late page.RetryingProfile profile;
      final ran = runFaked((async) {
        profile = page.RetryingProfile(ProfileApi())
          ..addListener(() => states.add('${profile.currentState}'));
        profile.load();
        async.flushMicrotasks();
        _fail(async, 'fetchName', StateError('no network'));
        async.elapse(const Duration(seconds: 1));
        _fail(async, 'fetchName', StateError('no network'));
        async.elapse(const Duration(seconds: 2));
        endCall(async, 'fetchName');
      });

      expect(states, ['Loading', 'Loaded(Ada Lovelace)']);
      expect(profile.heard, isEmpty);
      expect(ran.errors, isEmpty);
    });

    group('from the caller:', () {
      /// Starts the loop of the page on a fresh profile, and notes in
      /// [events] what it returns and when.
      page.ProfileController retry(FakeAsync async, List<String> events) {
        final profile = page.ProfileController(ProfileApi());
        unawaited(
          page.loadWithRetries(profile).then(
                (outcome) => events.add(
                  'returned $outcome at ${async.elapsed.inMilliseconds} ms',
                ),
              ),
        );
        async.flushMicrotasks();

        return profile;
      }

      /// Moves [async] to [seconds] and notes whether `fetchName` was called
      /// a millisecond before and at that moment.
      void callingAround(FakeAsync async, int seconds, List<bool> calling) {
        final at = Duration(seconds: seconds);
        async.elapse(at - async.elapsed - const Duration(milliseconds: 1));
        calling.add(stage.isRunning('fetchName'));
        async.elapse(const Duration(milliseconds: 1));
        calling.add(stage.isRunning('fetchName'));
      }

      test('a job sent in the gap runs in it, and close() does not wait', () {
        _says(
          'Where other jobs should run between the attempts, the caller '
          'retries instead of the body',
        );
        _says(
          'it belongs to no job, so it holds nothing. The jobs sent in '
          'between run in the gap, and `close()` does not wait for it',
        );
        final events = <String>[];
        final ran = runFaked((async) {
          final profile = retry(async, events);
          _fail(async, 'fetchName', StateError('no network'));
          async.elapse(const Duration(milliseconds: 300));
          events.add('pending ${profile.pending}');
          unawaited(
            profile.load().done.then(
                  (outcome) => events.add(
                    'sent: $outcome at ${async.elapsed.inMilliseconds} ms',
                  ),
                ),
          );
          async.flushMicrotasks();
          events.add('calling ${stage.isRunning('fetchName')}');
          async.elapse(const Duration(milliseconds: 200));
          endCall(async, 'fetchName');
          unawaited(
            profile.close().then(
                  (_) => events.add(
                    'closed at ${async.elapsed.inMilliseconds} ms',
                  ),
                ),
          );
          async.elapse(const Duration(seconds: 1));
        });

        expect(events, [
          'pending null',
          'calling true',
          'sent: Done(Ada Lovelace) at 500 ms',
          'closed at 500 ms',
          'returned Cancelled(closed) at 1000 ms',
        ]);
        expect(ran.errors, isEmpty);
      });

      test(
          'two failures, then the name: Failure between the attempts, and '
          'the reporter hears each failure', () {
        _says(
          'Between the attempts the state is the `Failure` of `ifFailed`, and '
          'the screen shows the error until the next attempt emits `Loading`',
        );
        _says(
          'Every failed attempt reaches `onError` too, so the crash '
          'reporter hears each one',
        );
        _says(
          '`done` observes each outcome, so no failure of an attempt goes '
          'on to the zone',
        );
        final events = <String>[];
        final states = <String>[];
        final calling = <bool>[];
        late page.ProfileController profile;
        final ran = runFaked((async) {
          profile = retry(async, events)
            ..addListener(() => states.add('${profile.currentState}'));
          _fail(async, 'fetchName', StateError('no network'));
          callingAround(async, 1, calling);
          _fail(async, 'fetchName', StateError('no network'));
          callingAround(async, 3, calling);
          endCall(async, 'fetchName');
        });

        expect(
          calling,
          [false, true, false, true],
          reason: 'the second call a second later, the third two more',
        );
        expect(states, [
          'Failure(Bad state: no network)',
          'Loading',
          'Failure(Bad state: no network)',
          'Loading',
          'Loaded(Ada Lovelace)',
        ]);
        expect(events, ['returned Done(Ada Lovelace) at 3000 ms']);
        expect(stage.crashes, ['no network', 'no network']);
        expect(ran.errors, isEmpty);
      });

      test('three failures: the loop returns the Failed of the third', () {
        final events = <String>[];
        late page.ProfileController profile;
        final ran = runFaked((async) {
          profile = retry(async, events);
          _fail(async, 'fetchName', StateError('no network 1'));
          async.elapse(const Duration(seconds: 1));
          _fail(async, 'fetchName', StateError('no network 2'));
          async.elapse(const Duration(seconds: 2));
          _fail(async, 'fetchName', StateError('no network 3'));
          async.elapse(const Duration(seconds: 5));
        });

        expect(events, ['returned Failed(Bad state: no network 3) at 3000 ms']);
        expect('${profile.currentState}', 'Failure(Bad state: no network 3)');
        expect(stage.crashes, ['no network 1', 'no network 2', 'no network 3']);
        expect(ran.errors, isEmpty);
      });

      test('cancelAll() during an attempt ends the loop', () {
        _says(
          '- A `Cancelled` ends the loop as a `Done` does. - '
          '`cancelAll()` while an attempt runs cancels it, and the loop '
          'returns that `Cancelled`',
        );
        final events = <String>[];
        final ran = runFaked((async) {
          final profile = retry(async, events);
          unawaited(profile.cancelAll());
          async.elapse(const Duration(seconds: 5));
        });

        expect(events, ['returned Cancelled(manual) at 0 ms']);
        expect(stage.trace, ['fetchName start']);
        expect(ran.errors, isEmpty);
      });

      test('cancelAll() in the gap finds nothing; the next attempt starts', () {
        _says(
          '`cancelAll()` in the gap finds no job to cancel, and the next '
          'attempt starts after it all the same',
        );
        _says("The gap itself is the caller's to stop");
        final events = <String>[];
        final calling = <bool>[];
        final ran = runFaked((async) {
          final profile = retry(async, events);
          _fail(async, 'fetchName', StateError('no network'));
          async.elapse(const Duration(milliseconds: 300));
          unawaited(profile.cancelAll());
          async.flushMicrotasks();
          callingAround(async, 1, calling);
          endCall(async, 'fetchName');
        });

        expect(calling, [false, true]);
        expect(events, ['returned Done(Ada Lovelace) at 1000 ms']);
        expect(ran.errors, isEmpty);
      });

      test('the timer of the gap outlives a closed profile; a pause does not',
          () {
        _says(
          "The gap itself is the caller's to stop. Until it does, the timer "
          'outlives a closed profile',
        );
        _says('where the loop in the body passes');
        late int afterGap;
        late int afterPause;
        final ran = runFaked((async) {
          final profile = retry(async, <String>[]);
          _fail(async, 'fetchName', StateError('no network'));
          async.elapse(const Duration(milliseconds: 300));
          unawaited(profile.close());
          async.flushMicrotasks();
          afterGap = async.pendingTimers.length;
          async.elapse(const Duration(seconds: 1));

          final inBody = page.RetryingProfile(ProfileApi());
          inBody.load().ignoreFailure();
          async.flushMicrotasks();
          _fail(async, 'fetchName', StateError('no network'));
          async.elapse(const Duration(milliseconds: 300));
          unawaited(inBody.close());
          async.flushMicrotasks();
          afterPause = async.pendingTimers.length;
        });

        expect(afterGap, 1);
        expect(afterPause, 0);
        expect(ran.errors, isEmpty);
      });

      test('a load sent in the gap does not stop the loop', () {
        _says(
          'Nor does the loop know of a load sent in the gap: if that load '
          'succeeds, the next attempt still loads again',
        );
        final events = <String>[];
        final states = <String>[];
        late page.ProfileController profile;
        final ran = runFaked((async) {
          profile = retry(async, events)
            ..addListener(
              () => states.add(
                '${profile.currentState} at ${async.elapsed.inMilliseconds}',
              ),
            );
          _fail(async, 'fetchName', StateError('no network'));
          async.elapse(const Duration(milliseconds: 300));
          profile.load().ignoreFailure();
          async.elapse(const Duration(milliseconds: 200));
          endCall(async, 'fetchName');
          async.elapse(const Duration(milliseconds: 500));
          endCall(async, 'fetchName');
        });

        expect(states, [
          'Failure(Bad state: no network) at 0',
          'Loading at 300',
          'Loaded(Ada Lovelace) at 500',
          'Loading at 1000',
          'Loaded(Ada Lovelace) at 1000',
        ]);
        expect(
          stage.trace.where((line) => line == 'fetchName start'),
          hasLength(3),
        );
        expect(events, ['returned Done(Ada Lovelace) at 1000 ms']);
        expect(ran.errors, isEmpty);
      });

      test('a profile closed in the gap refuses the next attempt', () {
        _says(
          'Close the profile, and the next attempt is refused: the loop '
          'returns its `Cancelled(closed)` at the end of the gap',
        );
        final events = <String>[];
        final ran = runFaked((async) {
          final profile = retry(async, events);
          _fail(async, 'fetchName', StateError('no network'));
          async.elapse(const Duration(milliseconds: 300));
          unawaited(profile.close());
          async.elapse(const Duration(seconds: 5));
        });

        expect(events, ['returned Cancelled(closed) at 1000 ms']);
        expect(stage.trace, ['fetchName start', 'fetchName failed']);
        expect(ran.errors, isEmpty);
      });
    });
  });

  group('Errors in state rules', () {
    group('the first attempt:', () {
      test('no free slot', () {
        _says(
          '1. The error goes to `onError`: a crash report for an ordinary '
          '"not now". 2. The job ends `Failed`, and `onUnanswered` answers '
          'for that outcome unless somebody observes it',
        );
        _says(
          'The state handler passed as `ifFailed` to that same `run` is '
          'not called. A state handler computes the state after a job '
          'that ran, and this one never started',
        );
        _says('The queue goes on to the next job');
        final started = <String>[];
        late first.ThrowingPool pool;
        late Job<void> job;
        late Job<void> next;
        final ran = runFaked((async) {
          Solo.observer = Saying('observer', started);
          pool = first.ThrowingPool(const Slots(0));
          job = pool.take(
            ifFailed: (state, error, stackTrace) {
              stage.trace.add('the state handler ran');

              return const Slots(-1);
            },
          );
          next = pool.run<Slots, void>(key: 'next', (ctx) async {});
        });

        expect('${job.outcome}', 'Failed(Bad state: no free slot)');
        expect(pool.heard, ['take: no free slot']);
        expect(pool.unanswered, ['take: no free slot']);
        expect(ran.errors, ['no free slot']);
        expect(stage.trace, isEmpty, reason: 'neither body nor handler ran');
        expect('${pool.currentState}', 'Slots(0)');
        expect('${next.outcome}', 'Done(null)');
        expect(
          started.where((hook) => hook == 'observer.onStart'),
          hasLength(1),
          reason: 'only the next job started',
        );
      });

      test('no free slot, and somebody observes the outcome', () {
        late first.ThrowingPool pool;
        final ran = runFaked((async) {
          pool = first.ThrowingPool(const Slots(0));
          pool.take().ignoreFailure();
        });

        expect(pool.heard, ['take: no free slot']);
        expect(ran.errors, isEmpty);
      });

      test('a free slot', () {
        late Job<void> job;
        runFaked((async) {
          job = first.ThrowingPool(const Slots(1)).take();
        });

        expect('${job.outcome}', 'Done(null)');
        expect(stage.trace, ['take ran']);
      });
    });

    group('a rule answers:', () {
      test('no free slot', () {
        _says(
          'A rule that answers `false` is not an error: it cancels the '
          'job. The trace of that `Cancelled` is taken where the rule '
          'said no',
        );
        late page.Pool pool;
        late Job<void> job;
        late Job<void> next;
        final ran = runFaked((async) {
          pool = page.Pool(const Slots(0));
          job = pool.take(
            ifCancelled: (state, cancelled) {
              stage.trace.add('the state handler ran');

              return const Slots(-2);
            },
          );
          next = pool.run<Slots, void>(key: 'next', (ctx) async {});
        });

        final outcome = job.outcome! as Cancelled;
        expect('$outcome', 'Cancelled(rules: canStart)');
        expect(outcome.started, isFalse);
        expect(outcome.stackTrace, isNotNull);
        expect(pool.heard, isEmpty);
        expect(ran.errors, isEmpty);
        expect(stage.trace, isEmpty);
        expect('${pool.currentState}', 'Slots(0)');
        expect('${next.outcome}', 'Done(null)');
      });

      test('a free slot', () {
        late Job<void> job;
        runFaked((async) {
          job = page.Pool(const Slots(1)).take();
        });

        expect('${job.outcome}', 'Done(null)');
        expect(stage.trace, ['take ran']);
      });
    });

    group('the trace of a cancellation by the rules:', () {
      SoloJob<void> kept(_Traced traced) => traced.run<int, void>(
            key: 'kept',
            keepWhile: (state) => state < 5,
            (ctx) => ctx.abandonable(() => stage.start<void>('op', null)),
          )..ignoreFailure();

      Cancelled outcomeOf(Job<void> job) => job.outcome! as Cancelled;

      test('keepWhile re-checked on an externalSetState', () {
        _says(
          'A `keepWhile` re-checked on a change says no from inside that '
          'change, so the trace leads to the `emit` or the '
          '`externalSetState` whose state broke the rule',
        );
        fakeAsync((async) {
          final traced = _Traced();
          final job = kept(traced);
          async.flushMicrotasks();
          traced.setsTooBig();
          async.flushMicrotasks();

          expect('${job.outcome}', 'Cancelled(rules: keepWhile)');
          expect(
            _frames(outcomeOf(job).stackTrace).take(5),
            [
              'Solo._reevaluate',
              'Solo._setState',
              'Solo.externalSetState',
              'OpenSolo.externalSetState',
              '_Traced.setsTooBig',
            ],
          );
        });
      });

      test('keepWhile re-checked on the emit of a child', () {
        fakeAsync((async) {
          final traced = _Traced();
          final job = traced.run<int, void>(
            key: 'parent',
            keepWhile: (state) => state < 5,
            (ctx) async {
              await ctx.run(
                traced.job<int, void>(
                  key: 'child',
                  (child) async => traced.emitsTooBig(child),
                ),
              );
            },
          )..ignoreFailure();
          async.flushMicrotasks();

          expect('${job.outcome}', 'Cancelled(rules: keepWhile)');
          expect(
            _frames(outcomeOf(job).stackTrace).take(4),
            [
              'Solo._reevaluate',
              'Solo._setState',
              '_SoloContext.emit',
              '_Traced.emitsTooBig',
            ],
          );
        });
      });

      /// A job that breaks its own rule with an `emit`, goes on, and reaches
      /// a checkpoint of [kind].
      SoloJob<void> breaksItsOwnRule(_Traced traced, String kind) =>
          traced.run<int, void>(
            key: 'own',
            keepWhile: (state) => state < 5,
            (ctx) async {
              traced.emitsTooBig(ctx);
              stage.trace.add('the body went on');
              await Future<void>.delayed(Duration.zero);
              switch (kind) {
                case 'ctx.state':
                  traced.readsTheState(ctx);
                case 'ctx.check()':
                  traced.checksTheJob(ctx);
                case 'ctx.each':
                  traced.followsAStream(ctx);
                default:
                  await traced.waitsOnTheContext(ctx);
              }
            },
          )..ignoreFailure();

      const checkpoints = {
        'ctx.state': '_Traced.readsTheState',
        'ctx.check()': '_Traced.checksTheJob',
        'a waiting method': '_Traced.waitsOnTheContext',
        'ctx.each': '_Traced.followsAStream',
      };
      for (final MapEntry(key: kind, value: member) in checkpoints.entries) {
        test('a job that breaks its own rule, and then reaches $kind', () {
          _says(
            'A job that breaks its own rule is not re-checked on its own '
            '`emit`. It finds out at its next checkpoint, such as '
            '`ctx.state`, `ctx.check()`, a waiting method or `ctx.each`, '
            'and the trace names that checkpoint',
          );
          fakeAsync((async) {
            final job = breaksItsOwnRule(_Traced(), kind);
            async.flushTimers();

            expect('${job.outcome}', 'Cancelled(rules: keepWhile)');
            expect(
              stage.trace,
              ['the body went on'],
              reason: 'the call of the waiting method never started',
            );
            final frames = _frames(outcomeOf(job).stackTrace);
            expect(frames, contains(member));
            expect(frames, isNot(contains('_Traced.emitsTooBig')));
          });
        });
      }

      test('canStart asked as the job leaves the queue', () {
        _says(
          '`canStart` is asked once, as the job leaves the queue, and names '
          'the queue',
        );
        fakeAsync((async) {
          final controller = _Traced()..setsTooBig();
          final job = controller.run<int, void>(
            key: 'big',
            canStart: (state) => state < 5,
            (ctx) async {},
          )..ignoreFailure();
          async.flushMicrotasks();

          final frames = _frames(outcomeOf(job).stackTrace);
          expect(frames.first, 'Solo._pump');
          expect(frames, isNot(contains('_Traced.setsTooBig')));
        });
      });
    });

    group('where a rule throws:', () {
      final rows = _rows('| Where it throws | What happens |');

      test('the four rows of the table', () {
        expect(rows, {
          'A start rule': 'The job fails and the queue continues.',
          'A rule at a context checkpoint': 'The body receives the error.',
          'Re-evaluation after a state update':
              'Reported; it does not itself cancel the running body.',
          'The same re-evaluation, on a job with a state handler':
              'Reported, and the handler is disabled.',
        });
      });

      for (final rule in ['canStart', 'keepWhile']) {
        test('$rule throws as the job leaves the queue', () {
          late Bench bench;
          late Job<void> job;
          late Job<void> next;
          runFaked((async) {
            bench = Bench();
            bool throws(int state) => throw StateError('the rule');
            job = bench.run<int, void>(
              key: 'start',
              canStart: rule == 'canStart' ? throws : null,
              keepWhile: rule == 'keepWhile' ? throws : null,
              (ctx) async {},
            )..ignoreFailure();
            next = bench.run<int, void>(key: 'next', (ctx) async {});
          });

          expect('${job.outcome}', 'Failed(Bad state: the rule)');
          expect('${next.outcome}', 'Done(null)');
          expect(bench.heard, ['start: the rule']);
          expect(bench.unanswered, isEmpty);
        });
      }

      test('a rule throws at a checkpoint, and the body catches it', () {
        late Bench bench;
        late Job<void> job;
        final caught = <String>[];
        final ran = runFaked((async) {
          bench = Bench();
          var broken = false;
          job = bench.run<int, void>(
            key: 'checkpoint',
            keepWhile: (state) => broken ? throw StateError('the rule') : true,
            (ctx) async {
              await stage.start<void>('op', null);
              try {
                ctx.check();
              } on Object catch (error) {
                caught.add(text(error));
              }
            },
          );
          async.flushMicrotasks();
          broken = true;
          endCall(async, 'op');
        });

        expect(caught, ['the rule']);
        expect('${job.outcome}', 'Done(null)');
        expect(bench.heard, isEmpty, reason: 'the body alone received it');
        expect(ran.errors, isEmpty);
      });

      test('a rule throws at a checkpoint, and the body lets it out', () {
        late Bench bench;
        late Job<void> job;
        runFaked((async) {
          bench = Bench();
          var broken = false;
          job = bench.run<int, void>(
            key: 'checkpoint',
            keepWhile: (state) => broken ? throw StateError('the rule') : true,
            (ctx) async {
              await stage.start<void>('op', null);
              ctx.state;
            },
          )..ignoreFailure();
          async.flushMicrotasks();
          broken = true;
          endCall(async, 'op');
        });

        expect('${job.outcome}', 'Failed(Bad state: the rule)');
        expect(bench.heard, ['checkpoint: the rule']);
        expect(bench.unanswered, isEmpty);
      });

      /// A job whose rule throws once the state has moved on, with a state
      /// handler when [handled], and a body that fails once `op` ends.
      SoloJob<void> reevaluated(Bench bench, {required bool handled}) =>
          bench.run<int, void>(
            key: 'reevaluated',
            keepWhile: (state) =>
                state == 0 ? true : throw StateError('the rule'),
            ifFailed: handled
                ? (state, error, stackTrace) {
                    stage.trace.add('the state handler ran');

                    return 99;
                  }
                : null,
            (ctx) async {
              await stage.start<void>('op', null);
              stage.trace.add('the body went on');
              throw StateError('the body');
            },
          )..ignoreFailure();

      test('a rule throws on re-evaluation after a state update', () {
        late Bench bench;
        late Job<void> job;
        var cancelledByIt = true;
        final ran = runFaked((async) {
          bench = Bench();
          job = reevaluated(bench, handled: false);
          async.flushMicrotasks();
          bench.reflect(1);
          async.flushMicrotasks();
          cancelledByIt = job.isCancelled;
          endCall(async, 'op');
        });

        expect(cancelledByIt, isFalse);
        expect(stage.trace.last, 'the body went on');
        expect(
          bench.heard,
          ['reevaluated: the rule', 'reevaluated: the body'],
        );
        expect(bench.unanswered, ['reevaluated: the rule']);
        expect('${job.outcome}', 'Failed(Bad state: the body)');
        expect(ran.errors, ['the rule']);
      });

      test('the same re-evaluation on a job with a state handler', () {
        late Bench bench;
        late Job<void> job;
        runFaked((async) {
          bench = Bench();
          job = reevaluated(bench, handled: true);
          async.flushMicrotasks();
          bench.reflect(1);
          endCall(async, 'op');
        });

        expect(bench.unanswered, ['reevaluated: the rule']);
        expect('${job.outcome}', 'Failed(Bad state: the body)');
        expect(stage.trace, isNot(contains('the state handler ran')));
        expect(bench.currentState, 1, reason: 'no correction to 99');
      });

      test('the same job with a rule that holds: the handler runs', () {
        late Bench bench;
        runFaked((async) {
          bench = Bench();
          bench.run<int, void>(
            key: 'handled',
            keepWhile: (state) => true,
            ifFailed: (state, error, stackTrace) => 99,
            (ctx) async {
              await stage.start<void>('op', null);
              throw StateError('the body');
            },
          ).ignoreFailure();
          async.flushMicrotasks();
          bench.reflect(1);
          endCall(async, 'op');
        });

        expect(bench.currentState, 99);
      });

      test('a job with a state handler, re-evaluated after its body has ended',
          () {
        _says(
          'A job with a state handler is re-evaluated after its body has '
          'ended as well',
        );
        late Bench bench;
        final ran = runFaked((async) {
          bench = Bench();
          bench.run<int, void>(
            key: 'ended',
            keepWhile: (state) =>
                state == 0 ? true : throw StateError('the rule'),
            ifFailed: (state, error, stackTrace) => 99,
            (ctx) async {
              ctx.onDispose(() => stage.start<void>('release', null));
              throw StateError('the body');
            },
          ).ignoreFailure();
          async.flushMicrotasks();
          bench.reflect(1);
          endCall(async, 'release');
        });

        expect(bench.heard, ['ended: the body', 'ended: the rule']);
        expect(bench.unanswered, ['ended: the rule']);
        expect(bench.currentState, 1, reason: 'the handler is disabled');
        expect(ran.errors, ['the rule']);
      });

      test('a job without one, re-evaluated after its body has ended', () {
        late Bench bench;
        runFaked((async) {
          bench = Bench()
            ..run<int, void>(
              key: 'ended',
              keepWhile: (state) =>
                  state == 0 ? true : throw StateError('the rule'),
              (ctx) async {
                ctx.onDispose(() => stage.start<void>('release', null));
              },
            );
          async.flushMicrotasks();
          bench.reflect(1);
          endCall(async, 'release');
        });

        expect(bench.heard, isEmpty, reason: 'its rules are not asked');
      });

      test('the zone of last resort for a rule that throws on a change', () {
        _says(
          'An error of a re-evaluation takes the way the table of [Where '
          'each error goes](#where-each-error-goes) gives a `keepWhile`: '
          '`onError`, then `onUnanswered`, and the creation zone when '
          'nobody answers',
        );
        final where = <String, List<String>>{};
        fakeAsync((async) {
          late Bench bench;
          where['the controller was created'] = zoneOf(() => bench = Bench());
          where['the job was created'] = zoneOf(
            () => reevaluated(bench, handled: false),
          );
          where['the state changed'] = zoneOf(() {
            async.flushMicrotasks();
            bench.reflect(1);
            endCall(async, 'op');
          });
        });

        expect(where, {
          'the controller was created': isEmpty,
          'the job was created': ['the rule'],
          'the state changed': isEmpty,
        });
      });
    });
  });

  group('Background work', () {
    group('the first attempt:', () {
      test('the send fails once the job is over', () {
        _row(
          'An error of a future the body did not await',
          'Nobody',
          'The zone the body runs in',
        );
        _says(
          'The error of the future belongs to nobody in the job. The '
          'hooks never see it, and `Solo.unansweredHandler` is never '
          'asked',
        );
        final handled = <String>[];
        late first.BroadCamera camera;
        late Job<void> job;
        final ran = runFaked((async) {
          Solo.unansweredHandler =
              (solo, job, error, stackTrace) => handled.add(text(error));
          camera = first.BroadCamera(Hardware());
          job = camera.zoomTo(2);
          async.flushMicrotasks();
          _fail(async, 'send', StateError('analytics offline'));
        });

        expect('${job.outcome}', 'Done(null)');
        expect(camera.heard, isEmpty);
        expect(camera.unanswered, isEmpty);
        expect(handled, isEmpty);
        expect(ran.errors, ['analytics offline']);
      });

      test('the zone it surfaces in is the one the job was created in', () {
        _says(
          'It surfaces as an unhandled error in the zone the body runs '
          'in, which for a job from the queue is the zone the job was '
          'created in. Nothing there names the job it came from',
        );
        final where = <String, List<String>>{};
        fakeAsync((async) {
          late first.BroadCamera camera;
          // The queue starts the second job from the zone its pump was
          // scheduled in, the zone of the first job here, and the body runs
          // in the zone it was created in all the same.
          where['the first job was created'] = zoneOf(() {
            camera = first.BroadCamera(Hardware())
              ..run<CameraState, void>(
                key: 'first',
                (ctx) => ctx.abandonable(() => stage.start<void>('op', null)),
              );
          });
          where['the second job was created'] = zoneOf(() {
            async.flushMicrotasks();
            camera.zoomTo(2);
          });
          where['the rest'] = zoneOf(() {
            endCall(async, 'op');
            _fail(async, 'send', StateError('analytics offline'));
          });
        });

        expect(where, {
          'the first job was created': isEmpty,
          'the second job was created': ['analytics offline'],
          'the rest': isEmpty,
        });
      });
    });

    group('work with a life of its own:', () {
      test('the send fails once the job is over', () {
        _says(
          'Its errors stay with the job, even after the job finishes: '
          '`onError` hears them, `onUnanswered` is asked to answer, and '
          'with nothing to answer they end in the creation zone',
        );
        late page.Camera camera;
        late Job<void> job;
        String? whenTheWorkFailed;
        final ran = runFaked((async) {
          camera = page.Camera(Hardware());
          job = camera.zoomTo(2, page.sendZoom);
          async.flushMicrotasks();
          whenTheWorkFailed = '${job.outcome}';
          _fail(async, 'send', StateError('analytics offline'));
        });

        expect(whenTheWorkFailed, 'Done(null)', reason: 'the job was over');
        expect(camera.heard, ['zoom: analytics offline']);
        expect(camera.unanswered, ['zoom: analytics offline']);
        expect(ran.errors, ['analytics offline']);
      });

      test('the same with a handler set', () {
        final handled = <String>[];
        final ran = runFaked((async) {
          Solo.unansweredHandler =
              (solo, job, error, stackTrace) => handled.add(text(error));
          page.Camera(Hardware()).zoomTo(2, page.sendZoom);
          async.flushMicrotasks();
          _fail(async, 'send', StateError('analytics offline'));
        });

        expect(handled, ['analytics offline']);
        expect(ran.errors, isEmpty);
      });

      test('the zone it ends in is the one the job was created in', () {
        final where = <String, List<String>>{};
        fakeAsync((async) {
          late page.Camera camera;
          where['the first job was created'] = zoneOf(() {
            camera = page.Camera(Hardware())
              ..run<CameraState, void>(
                key: 'first',
                (ctx) => ctx.abandonable(() => stage.start<void>('op', null)),
              );
          });
          where['the second job was created'] = zoneOf(() {
            async.flushMicrotasks();
            camera.zoomTo(2, page.sendZoom);
          });
          where['the rest'] = zoneOf(() {
            endCall(async, 'op');
            _fail(async, 'send', StateError('analytics offline'));
          });
        });

        expect(where, {
          'the first job was created': isEmpty,
          'the second job was created': ['analytics offline'],
          'the rest': isEmpty,
        });
      });

      test('a future made before the call fails past the hooks', () {
        final where = <String, List<String>>{};
        final bench = Bench();
        fakeAsync((async) {
          late Future<void> made;
          where['the future was made'] = zoneOf(() {
            made = stage.start<void>('send', null);
          });
          where['the job was created'] = zoneOf(() {
            bench.run<int, void>(
              key: 'job',
              (ctx) async => ctx.unattended(() => made),
            );
          });
          where['the rest'] = zoneOf(() {
            async.flushMicrotasks();
            _fail(async, 'send', StateError('analytics offline'));
            bench.close().ignore();
            async.flushTimers();
          });
        });

        expect(where, {
          'the future was made': ['analytics offline'],
          'the job was created': isEmpty,
          'the rest': isEmpty,
        });
        expect(bench.heard, isEmpty);
        expect(bench.unanswered, isEmpty);
        _says(
          'Start that work inside the callback. A future made before the '
          'call and only awaited inside fails past the hooks, into the '
          'zone it was made in.',
        );
      });

      test('the job is cancelled, and then closed, while the work goes on', () {
        _says(
          '`ctx.unattended(action)` starts work that the job neither '
          'waits for nor cancels',
        );
        fakeAsync((async) {
          final camera = page.Camera(Hardware());
          final job = camera.run<CameraState, void>(key: 'zoom', (ctx) async {
            page.sendZoom(ctx, 2);
            await ctx.abandonable(() => stage.start<void>('op', null));
          })
            ..ignoreFailure();
          async.flushMicrotasks();
          unawaited(job.cancel());
          var back = false;
          camera.close().then((_) => back = true);
          async.flushMicrotasks();

          expect('${job.outcome}', 'Cancelled(manual)');
          expect(back, isTrue, reason: 'nothing waits for the work');
          expect(stage.isRunning('send'), isTrue);
          endCall(async, 'send');
        });
      });

      test('what the context refuses inside the work, and what it lets do', () {
        _says(
          'Unattended work is not the job, and the context refuses there '
          'whatever acts on the job. `ctx.run`, `ctx.runAll`, `ctx.each` '
          'and `ctx.uncancellable` all throw a `StateError` that names '
          'the call: `cannot run a child inside unattended work` for '
          '`ctx.run`',
        );
        final refused = <String, String>{};
        final let = <String>[];
        late Bench bench;
        runFaked((async) {
          bench = Bench();
          bench.run<int, void>(key: 'work', (ctx) async {
            ctx.unattended(() async {
              final calls = <String, Future<Object?> Function()>{
                'ctx.run': () async =>
                    ctx.run(bench.job<int, void>((c) async {})),
                'ctx.runAll': () async =>
                    ctx.runAll([bench.job<int, void>((c) async {})]),
                'ctx.each': () async =>
                    ctx.each(const Stream<int>.empty(), (c, event) {}),
                'ctx.uncancellable': () async =>
                    ctx.uncancellable<void>(() async {}),
                'ctx.abandonable': () async =>
                    ctx.abandonable<void>(() async {}),
                'ctx.join': () async => ctx.join<void>(() async {}),
                'ctx.pause': () async => ctx.pause(),
                'ctx.emit': () async => ctx.emit(1),
              };
              for (final MapEntry(key: name, value: call) in calls.entries) {
                try {
                  await call();
                  let.add(name);
                } on Object catch (error) {
                  refused[name] = text(error);
                }
              }
            });
            await ctx.abandonable(() => stage.start<void>('op', null));
          });
          async.flushTimers();
          endCall(async, 'op');
        });

        expect(refused, {
          'ctx.run': 'Job(work) cannot run a child inside unattended work',
          'ctx.runAll':
              'Job(work) cannot run a group of children inside unattended work',
          'ctx.each': 'Job(work) cannot follow a stream inside unattended work',
          'ctx.uncancellable':
              'Job(work) cannot run an uncancellable action inside unattended '
                  'work',
        });
        expect(let, ['ctx.abandonable', 'ctx.join', 'ctx.pause', 'ctx.emit']);
        expect(bench.currentState, 1);
      });

      test('a refusal nobody catches inside the work', () {
        _says(
          'That throw is an error of the work it happened in, so it takes '
          'the way above, to the hooks. The job itself still ends `Done`',
        );
        late Bench bench;
        late Job<void> job;
        final ran = runFaked((async) {
          bench = Bench();
          job = bench.run<int, void>(key: 'work', (ctx) async {
            ctx.unattended(() => ctx.run(bench.job<int, void>((c) async {})));
          });
        });

        const refusal =
            'work: Job(work) cannot run a child inside unattended work';
        expect(bench.heard, [refusal]);
        expect(bench.unanswered, [refusal]);
        expect('${job.outcome}', 'Done(null)');
        expect(ran.errors, hasLength(1));
      });

      test('a captured context: an active job, a cancelled one, one over', () {
        _says(
          'A captured context still belongs to the original job. `emit` '
          'works while that job is active and is rejected after a '
          'cancellation or after the job completes',
        );
        fakeAsync((async) {
          final bench = Bench();
          late SoloContext<int, int> captured;
          String emit(int value) {
            try {
              captured.emit(value);

              return 'emitted ${bench.currentState}';
            } on Object catch (error) {
              return text(error);
            }
          }

          bench.run<int, void>(key: 'active', (ctx) async {
            captured = ctx;
            await ctx.abandonable(() => stage.start<void>('op', null));
          });
          async.flushMicrotasks();
          final whileActive = emit(1);
          endCall(async, 'op');
          final afterCompletion = emit(2);

          final cancelled = bench.run<int, void>(key: 'cancelled', (ctx) async {
            captured = ctx;
            await stage.start<void>('op', null);
          })
            ..ignoreFailure();
          async.flushMicrotasks();
          unawaited(cancelled.cancel());
          async.flushMicrotasks();
          final afterCancellation = emit(3);
          endCall(async, 'op');

          expect(whileActive, 'emitted 1');
          expect(
            afterCompletion,
            'Job(active) has already finished, cannot emit',
          );
          expect(afterCancellation, 'Cancelled(manual)');
          expect(bench.currentState, 1);
        });
      });
    });
  });

  group('The page', () {
    test('five sections open with a first attempt', () {
      expect(
        RegExp(r'^### The first attempt$', multiLine: true).allMatches(_page()),
        hasLength(5),
      );
    });

    test('opens with the table of where each error goes', () {
      _says(
        'The first section, [Where each error goes](#where-each-error-goes), '
        'lists every kind',
      );
      expect(
        RegExp(r'^## (.*)$', multiLine: true).firstMatch(_page())?.group(1),
        'Where each error goes',
      );
    });

    test('has no fence the checks do not read', () {
      expect(strayFences('doc/errors.md'), isEmpty);
    });

    // Each version under its own file: an answer turned into its own first
    // attempt would still be found among all of them.
    const answers = 'test/support/errors_page.dart';
    const answer = 'test/support/errors_page_answering.dart';
    const attempts = 'test/support/errors_first_attempts.dart';
    const holders = {
      '## Reporting an error': answers,
      '## Answering for an error': answer,
      '### The first attempt': attempts,
      '### Observing the outcome': answers,
      '### Letting cancellation through': answers,
      '### A pause between attempts': answers,
      '### Retrying from the caller': answers,
      '### A rule answers': answers,
      '### Work with a life of its own': answers,
    };
    for (final MapEntry(key: heading, value: holder) in holders.entries) {
      test('the code under "$heading" is a run of lines of $holder', () {
        expect(
          codeMissingFrom('doc/errors.md', holder, under: heading),
          isEmpty,
        );
      });
    }

    test('every piece of code on the page is a run of lines of these files',
        () {
      expect(
        codeMissingFrom(
          'doc/errors.md',
          answers,
          alsoIn: [answer, attempts],
        ),
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

  test('the filter of cancellation errors is left as it was found', () {
    expect(Job.isCancellationError, isNull);
  });
}
