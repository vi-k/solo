@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/errors_first_attempts.dart' as first;
import 'support/errors_page.dart' as page;
import 'support/errors_page_answering.dart' as answering;
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
/// time: the five seconds of the two timers and the delays of the table.

/// An observer that keeps what `onError` told it.
final class _Watching extends SoloObserver {
  final heard = <String>[];

  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) =>
      heard.add('${job.key}: ${text(error)}');
}

/// An observer that says when each of its hooks runs, and may throw from
/// one of them.
final class _Saying extends SoloObserver {
  final String name;
  final List<String> into;
  final String? throwOn;

  _Saying(this.name, this.into, {this.throwOn});

  void _say(String hook) {
    into.add('$name.$hook');
    if (hook == throwOn) throw StateError('$name.$hook threw');
  }

  @override
  void onCreate(Solo<Object> solo) => _say('onCreate');

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) => _say('onStart');

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) => _say('onFinish');

  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) =>
      _say('onError');

  @override
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) =>
      _say('onChange');

  @override
  void onLog(Solo<Object> solo, Job<Object?> job, Object? message) =>
      _say('onLog');

  @override
  void onClose(Solo<Object> solo) => _say('onClose');
}

/// A controller that overrides every hook the page names, calls `super` in
/// none of them and may throw from one.
final class _EveryHook extends Solo<int> with OpenSolo<int> {
  final List<String> into;
  final String? throwOn;

  _EveryHook(this.into, {this.throwOn}) : super(0);

  void _say(String hook) {
    into.add('controller.$hook');
    if (hook == throwOn) throw StateError('controller.$hook threw');
  }

  @override
  void onStart(Job<Object?> job) => _say('onStart');

  @override
  void onFinish(Job<Object?> job) => _say('onFinish');

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      _say('onError');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      _say('onUnanswered');

  @override
  void onLog(Job<Object?> job, Object? message) => _say('onLog');

  @override
  void onChange(SoloTransition<int> transition) => _say('onChange');

  @override
  void onClose() => _say('onClose');

  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      _say('onListenerError');
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
}

String _page() => File('doc/errors.md').readAsStringSync();

/// The page with every run of whitespace turned into one space, so that a
/// phrase is found wherever its lines were broken.
String _prose() => _page().replaceAll(RegExp(r'\s+'), ' ');

/// Holds the page to [phrase]: the test that calls this runs what the phrase
/// says, so a page that stops saying it leaves the test with nothing to
/// stand for.
void _says(String phrase) => expect(
      _prose(),
      contains(phrase),
      reason: 'doc/errors.md no longer says this',
    );

/// The rows of the table under [header], first cell to second.
Map<String, String> _rows(String header) {
  final lines = _page().split('\n');
  final start = lines.indexOf(header);
  if (start < 0) {
    throw StateError('doc/errors.md has no table "$header"');
  }

  return {
    for (final line
        in lines.skip(start + 2).takeWhile((l) => l.startsWith('|')))
      line.split('|')[1].trim(): line.split('|')[2].trim(),
  };
}

/// The lines the page quotes under a `text` fence, block by block.
List<List<String>> _quoted() => [
      for (final block
          in RegExp(r'```text\n(.*?)\n```', dotAll: true).allMatches(_page()))
        block.group(1)!.split('\n'),
    ];

/// What a run under fake time left behind: the errors that reached its zone
/// uncaught and the lines it printed.
final class _Ran {
  final errors = <String>[];
  final printed = <String>[];
}

/// Runs [body] under fake time, in a zone of its own. Nothing is asserted
/// inside: an `expect` that failed in there would be one more error of the
/// zone.
_Ran _run(void Function(FakeAsync async) body) {
  final ran = _Ran();
  fakeAsync((async) {
    runZonedGuarded(
      () => body(async),
      (error, stackTrace) => ran.errors.add(text(error)),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => ran.printed.add(line),
      ),
    );
    async.flushTimers();
  });

  return ran;
}

/// Runs [body] in a zone of its own and returns what reached it uncaught.
List<String> _zoneOf(void Function() body) {
  final errors = <String>[];
  runZonedGuarded(body, (error, stackTrace) => errors.add(text(error)));

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

Future<void> _delay(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

/// The members a stack trace names, innermost first.
List<String> _frames(StackTrace? trace) => [
      for (final line in '$trace'.split('\n'))
        if (line.trim().isNotEmpty)
          line.replaceFirst(RegExp(r'^#\d+\s+'), '').split(' (').first,
    ];

/// A job that waits on a call named `op` through `ctx.abandonable`.
SoloJob<void> _waits(Bench bench, String key) => bench.run<int, void>(
      key: key,
      (ctx) => ctx.abandonable(() => stage.start<void>('op', null)),
    );

/// A job that waits on a call named `op` with a bare `await`.
SoloJob<void> _ignores(Bench bench, String key) =>
    bench.run<int, void>(key: key, (ctx) => stage.start<void>('op', null));

/// A job that waits on a call named `op` inside an uncancellable section.
SoloJob<void> _holds(Bench bench, String key) => bench.run<int, void>(
      key: key,
      (ctx) => ctx.uncancellable(() => stage.start<void>('op', null)),
    );

/// A job whose disposer throws.
SoloJob<void> _dirtyCleanup(OpenSolo<int> controller) =>
    controller.run<int, void>(key: 'cleanup', (ctx) async {
      ctx.onDispose(() async => throw StateError('disposer'));
    });

void main() {
  final traceStateChanges = Solo.traceStateChanges;

  setUp(() => stage = Stage());

  tearDown(() {
    Solo.observer = null;
    Solo.errorHandler = null;
    Solo.debug = null;
    Job.debug = null;
    Solo.traceStateChanges = traceStateChanges;
  });

  group('Reporting an error', () {
    test('a controller that overrides the eight hooks the page names', () {
      _says(
        'A controller can override `onStart`, `onFinish`, `onError`, '
        '`onUnanswered`, `onLog`, `onChange` and `onClose`, and '
        '`onListenerError` for a listener that throws while being notified',
      );
      final called = <String>[];
      final ran = _run((async) {
        final controller = _EveryHook(called)
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
      final ran = _run((async) {
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
      final ran = _run((async) {
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

    test('every error its jobs run into, once', () {
      _says(
        'The hook is told about every error its jobs run into — the failure '
        'of a body, an error from cleanup or from an operation abandoned by '
        '`abandonable`, a rule that threw instead of answering — and it is '
        'told once for each job',
      );
      late Bench bench;
      _run((async) {
        bench = Bench();
        bench
            .run<int, void>(
              key: 'body',
              (ctx) async => throw StateError('the body'),
            )
            .ignoreFailure();
        _dirtyCleanup(bench);
        final abandons = _waits(bench, 'abandons')..ignoreFailure();
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
        'An error a child throws and its parent lets through is the failure '
        'of both: the hook hears it twice, and the `job` it is given tells '
        'the two calls apart',
      );
      late Bench bench;
      late Job<void> job;
      final ran = _run((async) {
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
      _run((async) {
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

    for (final make in <OpenSolo<int> Function()>[
      _ReportsAndCallsSuper.new,
      _ReportsAndReturns.new,
    ]) {
      test('overriding it moves no error anywhere: ${make().runtimeType}', () {
        _says(
          'the hook answers for nothing, and overriding it moves no error '
          'anywhere',
        );
        final handled = <String>[];
        final ran = _run((async) {
          Solo.errorHandler =
              (solo, job, error, stackTrace) => handled.add(text(error));
          _dirtyCleanup(make());
          async.flushMicrotasks();
          Solo.errorHandler = null;
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
        'The override above answers for them here, and they reach nothing '
        'else',
      );
      final handled = <String>[];
      late answering.ProfileController profile;
      final ran = _run((async) {
        Solo.errorHandler =
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
      _says(
        'The failure of a body becomes `Failed`, where `run(ifFailed: ...)` '
        'computes a state from it, and an outcome nobody observes reaches '
        "the job's creation zone by itself",
      );
      final handled = <String>[];
      late Bench bench;
      late Job<void> job;
      final ran = _run((async) {
        Solo.errorHandler =
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
      expect(bench.unanswered, isEmpty, reason: 'nobody is asked to answer');
      expect(handled, isEmpty);
      expect(ran.errors, ['the body'], reason: 'nobody observed the outcome');
    });

    group('what no outcome carries:', () {
      test('the list of the page', () {
        _says('What no outcome carries is the rest:');
        expect(
          RegExp('^- ', multiLine: true).allMatches(_page()),
          hasLength(6),
        );
        _says('- an operation abandoned by `abandonable` that fails later;');
        _says(
          '- what the job calls outside its body: a disposer, a '
          '`ctx.onCancel` callback, a `whenCancelled` listener, a state '
          'handler of `run`;',
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
          '- the failure of a body when a cancellation reaches the job '
          'afterwards, whether before the error leaves the body or while the '
          'job still waits for children of its own or runs its cleanup: '
          'whoever reads that outcome gets the cancellation.',
        );
        _says(
          'Somebody has to answer for those, and the one asked is always the '
          'same: `onUnanswered`, on the controller whose job it was',
        );
      });

      test('an operation abandoned by abandonable that fails later', () {
        late Bench bench;
        late Job<void> job;
        final ran = _run((async) {
          bench = Bench();
          job = _waits(bench, 'abandons')..ignoreFailure();
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
        late Bench bench;
        late Job<void> job;
        final ran = _run((async) {
          bench = Bench();
          job = _dirtyCleanup(bench);
        });

        expect(bench.heard, ['cleanup: disposer']);
        expect(bench.unanswered, ['cleanup: disposer']);
        expect('${job.outcome}', 'Done(null)');
        expect(ran.errors, ['disposer']);
      });

      test('a ctx.onCancel callback and a whenCancelled listener', () {
        late Bench bench;
        final ran = _run((async) {
          bench = Bench();
          final job = bench.run<int, void>(key: 'cancelled', (ctx) async {
            ctx.onCancel(() => throw StateError('the callback'));
            await ctx.abandonable(() => stage.start<void>('op', null));
          })
            ..whenCancelled((_) => throw StateError('the listener'))
            ..ignoreFailure();
          async.flushMicrotasks();
          unawaited(job.cancel());
        });

        const both = ['cancelled: the callback', 'cancelled: the listener'];
        expect(bench.heard, both);
        expect(bench.unanswered, both);
        expect(ran.errors, ['the callback', 'the listener']);
      });

      test('a state handler of run', () {
        late Bench bench;
        late Job<void> job;
        late Job<void> next;
        final ran = _run((async) {
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
        late Bench bench;
        late Job<void> job;
        var cancelledByIt = true;
        final ran = _run((async) {
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
          _end(async, 'op');
        });

        expect(bench.heard, ['kept: the rule']);
        expect(bench.unanswered, ['kept: the rule']);
        expect(cancelledByIt, isFalse);
        expect('${job.outcome}', 'Done(null)');
        expect(ran.errors, ['the rule']);
      });

      test('work handed to ctx.unattended', () {
        late Bench bench;
        late Job<void> job;
        final ran = _run((async) {
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
        late Bench bench;
        late Job<void> job;
        final caught = <String>[];
        final ran = _run((async) {
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
        late Bench bench;
        late Job<void> job;
        Object? thrown;
        final ran = _run((async) {
          bench = Bench();
          job = _waits(bench, 'covered');
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
        final ran = _run((async) {
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
          _end(async, 'child');
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
        final ran = _run((async) {
          bench = Bench();
          job = bench.run<int, void>(key: 'covered', (ctx) async {
            ctx.onDispose(() => stage.start<void>('release', null));
            throw StateError('the body');
          });
          job.value.then<void>((_) {}, onError: (Object e) => thrown = e);
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          _end(async, 'release');
        });

        expect('${job.outcome}', 'Cancelled(manual)');
        expect(thrown, same(job.outcome));
        expect(bench.heard, ['covered: the body']);
        expect(bench.unanswered, ['covered: the body']);
        expect(ran.errors, ['the body']);
      });
    });

    test('a failure that comes after the cancellation', () {
      _says(
        'One error no outcome carries is missing from that list, and nobody '
        'is asked to answer for it: the failure of a body that comes after '
        'its job has accepted a cancellation',
      );
      _says(
        'The job ends `Cancelled`, the reporting hook is told of the error, '
        'and it goes no further',
      );
      final handled = <String>[];
      late Bench bench;
      late Job<void> job;
      final ran = _run((async) {
        Solo.errorHandler =
            (solo, job, error, stackTrace) => handled.add(text(error));
        bench = Bench();
        // Not ignored: ignoreFailure() would silence a failure that asked for
        // an answer, and this one asks for none.
        job = bench.run<int, void>(
          key: 'stopped',
          (ctx) => ctx.join(() => stage.start<void>('op', null)),
        );
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        _fail(async, 'op', StateError('the call'));
      });

      expect('${job.outcome}', 'Cancelled(manual)');
      expect(bench.heard, ['stopped: the call']);
      expect(bench.unanswered, isEmpty);
      expect(handled, isEmpty);
      expect(ran.errors, isEmpty);
    });

    test('the handler of the page: one for the app, given the controller', () {
      _says(
        'One handler for the whole application, set once at startup',
      );
      final served = <String>[];
      final ran = _run((async) {
        Solo.errorHandler = (solo, job, error, stackTrace) =>
            served.add('${solo.runtimeType}: ${text(error)}');
        _dirtyCleanup(Bench());
        _dirtyCleanup(_ReportsAndReturns());
      });

      expect(served, ['Bench: disposer', '_ReportsAndReturns: disposer']);
      expect(ran.errors, isEmpty, reason: 'the handler took them');
    });

    test('with no handler set: the zone the job was created in', () {
      _says(
        'With none set, these errors go to the zone the job was created in',
      );
      final where = <String, List<String>>{};
      fakeAsync((async) {
        late Bench bench;
        where['the controller was created'] = _zoneOf(() => bench = Bench());
        where['the job was created'] = _zoneOf(
          () => bench.run<int, void>(key: 'cleanup', (ctx) async {
            ctx.onDispose(() async => throw StateError('disposer'));
            await stage.start<void>('op', null);
          }),
        );
        where['the job ended'] = _zoneOf(() {
          async.flushMicrotasks();
          _end(async, 'op');
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
        'The error arrives at the hook, and the hook calls the handler, so '
        'each controller decides for its own jobs whether the '
        'application-wide handler hears them at all',
      );
      final served = <String>[];
      final ran = _run((async) {
        Solo.errorHandler =
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
      final ran = _run((async) {
        Solo.errorHandler =
            (solo, job, error, stackTrace) => handled.add(text(error));
        controller = _AnswersAndCallsSuper();
        _dirtyCleanup(controller);
        async.flushMicrotasks();
        Solo.errorHandler = null;
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
        'The hook and the handler get one failure at a time. When the error '
        'is a `ParallelWaitError` that `[a, b].wait` throws with several '
        'errors in it, each failure comes in a call of its own, with its own '
        'stack trace',
      );
      _says(
        'An uncaught `Cancelled`, alone or inside one, does not come at all',
      );
      final got = <String>[];
      late Bench bench;
      final ran = _run((async) {
        Solo.errorHandler =
            (solo, job, error, stackTrace) => got.add(text(error));
        bench = Bench();
        handsWorkOver(bench);
      });

      expect(got, ['a failure']);
      expect(bench.unanswered, ['waits: a failure']);
      expect(ran.errors, isEmpty);
    });

    test('the reporting hook hears the error as it came', () {
      _says('The reporting hook hears the error as it came');
      late Bench bench;
      _run((async) {
        Solo.errorHandler = (solo, job, error, stackTrace) {};
        bench = Bench();
        handsWorkOver(bench);
      });

      expect(bench.heard, hasLength(3), reason: 'two envelopes and one alone');
    });

    test('the handler of the page: each failure on its own, no Cancelled', () {
      final ran = _run((async) {
        answering.installErrorHandler();
        handsWorkOver(Bench());
      });

      expect(stage.sentry, ['a failure']);
      expect(ran.errors, isEmpty);
    });

    test('with no handler the zone gets the same failure', () {
      late Bench bench;
      final ran = _run((async) {
        bench = Bench();
        handsWorkOver(bench);
      });

      expect(bench.unanswered, ['waits: a failure']);
      expect(ran.errors, ['a failure'], reason: 'the one that failed');
    });

    test('a SoloObserver set, and still nobody answers', () {
      _says(
        'Setting a `SoloObserver` is not it either — watching is not '
        'answering',
      );
      final watching = _Watching();
      final ran = _run((async) {
        Solo.observer = watching;
        _dirtyCleanup(Bench());
      });

      expect(watching.heard, ['cleanup: disposer']);
      expect(ran.errors, ['disposer']);
    });
  });

  group('Watching every controller', () {
    test('the observer of the page on the load of the quick start', () {
      late Job<String> job;
      final ran = _run((async) {
        page.main();
        final profile = page.ProfileController(ProfileApi());
        job = profile.load()..ignoreFailure();
        async.flushMicrotasks();
        _end(async, 'fetchName');
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
      final ran = _run((async) {
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
        '`SoloObserver` is told what the controllers are told — `onStart`, '
        '`onFinish`, `onError`, `onLog`, `onChange` and `onClose` — for '
        'every controller of the process, plus `onCreate`',
      );
      _says(
        '`onUnanswered` and `onListenerError` stay with the controller alone',
      );
      _says(
        "The observer is called before the controller's corresponding hook",
      );
      final order = <String>[];
      final ran = _run((async) {
        Solo.observer = _Saying('observer', order);
        final controller = _EveryHook(order)
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
        'The `job` is the one whose `emit` made the change or whose state '
        'handler returned it: `null` for an `externalSetState`, and a child '
        'of the running job rather than the root it belongs to',
      );
      late _Journal journal;
      _run((async) {
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
        'a `revision` that grows by one per change, so two transitions are '
        'in order even when a hook changed the state again from inside the '
        'first',
      );
      final nesting = _Nesting()..externalSetState(1);

      expect(nesting.order, ['in #1', 'in #2', 'out #2', 'out #1']);
      expect(nesting.currentState, 2);
    });

    for (final thrower in ['observer', 'controller']) {
      test('the $thrower hook throws', () {
        _says(
          'Each call is independent; omitting `super` in a controller hook '
          'does not disable the observer',
        );
        _says(
          'An error thrown by either hook is sent to the current Dart zone '
          "without changing the job's outcome, stopping the queue, or "
          'preventing the other hook from running',
        );
        final order = <String>[];
        late Job<void> job;
        late Job<void> next;
        final ran = _run((async) {
          Solo.observer = _Saying(
            'observer',
            order,
            throwOn: thrower == 'observer' ? 'onStart' : null,
          );
          final controller = _EveryHook(
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

    test('the zone a hook error goes to is the current one', () {
      final where = <String, List<String>>{};
      fakeAsync((async) {
        late _EveryHook controller;
        where['the controller was created'] = _zoneOf(
          () => controller = _EveryHook([], throwOn: 'onChange'),
        );
        where['the job was created'] = _zoneOf(
          () => controller.run<int, void>(
            key: 'job',
            (ctx) => ctx.abandonable(() => stage.start<void>('op', null)),
          ),
        );
        where['the state changed'] = _zoneOf(() {
          async.flushMicrotasks();
          controller.externalSetState(5);
        });
        _end(async, 'op');
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
      final watching = _Watching();
      final ran = _run((async) {
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
      _run((async) {
        final bench = Bench();
        _ignores(bench, 'stuck');
        async.flushMicrotasks();
        page.closeWithTimeout(bench);
        async.elapse(const Duration(seconds: 6));
        closed = bench.isFinished;
        _end(async, 'op');
      });

      expect(stage.lines, [_quoted()[0][0]]);
      expect(closed, isFalse, reason: 'the close is still held');
    });

    test('the same line under a drain: the queue it has still to run', () {
      _says(
        'A drain waits for the queue as well, and a group of `collect` or '
        '`accumulate` stays queued until its timing lets it go: with no job '
        'running, `pending` is a `SoloPendingQueue`, and its `jobs` are '
        'what the drain has still to run',
      );
      SoloPending? pending;
      SoloPending? withoutClose;
      var ranAfter = false;
      _run((async) {
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
        'With `SoloStream` the stream closes after the engine and waits for '
        'every subscription to take its done event: one left paused holds '
        '`close()` with `isFinished` already true, and `pending` is a '
        '`SoloPendingStream`',
      );
      _says('The three print alike, so the line above needs no switch');
      SoloPending? pending;
      var finished = false;
      var back = false;
      SoloPending? afterwards;
      _run((async) {
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
      test('the nine the page names', () {
        expect(_rows('| Field | What it says |').keys, [
          '`job`',
          '`phase`',
          '`cancellation`',
          '`heldCancellation`',
          '`children`',
          '`inUncancellableSection`',
          '`refusesCancellation`',
          '`closing`',
          '`draining`',
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
          expect(before.refusesCancellation, isFalse);
          expect(before.closing, isFalse);
          expect(before.draining, isFalse);
          expect(before.cancellationPending, isFalse);

          expect('${after.cancellation}', 'Cancelled(manual)');
          expect(after.heldCancellation, isNull);
          expect(after.cancellationPending, isTrue);
          _end(async, 'op');
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
          _end(async, 'op');
        });
      });

      test('a job created with cancellable: false, asked twice and closed', () {
        _says(
          'A job with `refusesCancellation` turns down the ones it may turn '
          'down, so nothing is pending on it however often it was asked to '
          'stop',
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

          expect(asked.refusesCancellation, isTrue);
          expect(asked.cancellation, isNull);
          expect(asked.heldCancellation, isNull);
          expect(asked.cancellationPending, isFalse);
          expect(asked.closing, isFalse);

          expect(closed.closing, isTrue);
          expect(closed.draining, isFalse);
          expect(closed.cancellationPending, isFalse);
          _end(async, 'op');
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
          _end(async, 'body');
          final waiting = bench.pending! as SoloPendingJob;
          _end(async, 'one');
          final oneLeft = bench.pending! as SoloPendingJob;
          _end(async, 'two');
          final cleaning = bench.pending! as SoloPendingJob;
          _end(async, 'release');

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
          final job = _waits(bench, 'runs');
          async.flushMicrotasks();
          unawaited(bench.close(mode: SoloCloseMode.drain));
          async.flushMicrotasks();
          final pending = bench.pending! as SoloPendingJob;
          _end(async, 'op');

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
        'A timer reads `pending` between the steps of a close, a synchronous '
        'hook in the middle of one: `onFinish` of the last job and `onClose` '
        'read `null`, though `close()` has not come back yet',
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
        _end(async, 'op');

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
        _run((async) {
          Solo.observer = page.Hangs();
          _waits(Bench(), 'stuck');
          async.elapse(const Duration(seconds: 6));
          _end(async, 'op');
        });

        expect(stage.lines, [_quoted()[1][0]]);
      });

      test('a job that holds a cancellation, as the page quotes it', () {
        _run((async) {
          Solo.observer = page.Hangs();
          final job = _holds(Bench(), 'held')..ignoreFailure();
          async.elapse(const Duration(seconds: 1));
          unawaited(job.cancel());
          async.elapse(const Duration(seconds: 6));
          _end(async, 'op');
        });

        expect(stage.lines, [_quoted()[1][1]]);
      });

      test('a job that ends in time', () {
        _says(
          'A job that ends in time disarms its own timer and says nothing',
        );
        var timers = -1;
        _run((async) {
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
          'One that does not is named at the front of its line. The snapshot '
          'beside the name is of the root job the controller is on, which is '
          'the same job unless the one that hangs is a child',
        );
        _run((async) {
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
          _end(async, 'op');
        });

        expect(stage.lines, [
          'root is still running: SoloPending([root] in its body)',
          'child is still running: SoloPending([root] in its body)',
        ]);
      });

      test('a job queued behind the one that hangs', () {
        _run((async) {
          Solo.observer = page.Hangs();
          final bench = Bench();
          _waits(bench, 'stuck');
          bench.run<int, void>(key: 'queued', (ctx) async {});
          async.elapse(const Duration(seconds: 6));
          _end(async, 'op');
        });

        expect(
          stage.lines,
          ['stuck is still running: SoloPending([stuck] in its body)'],
          reason: 'onStart has not come for the queued one',
        );
      });

      test('Hangs only reports, and a deadline stops the job', () {
        _says('`Hangs` only reports: the job it names goes on running');
        _says('A job that must stop at its limit takes the limit itself, '
            '`run(timeout: ...)`, and ends `Cancelled(timeout)`');
        late SoloJob<void> reported;
        late SoloJob<void> limited;
        var runningAtSix = false;
        _run((async) {
          Solo.observer = page.Hangs();
          final bench = Bench();
          reported = _waits(bench, 'stuck')..ignoreFailure();
          async.elapse(const Duration(seconds: 6));
          runningAtSix = !reported.isFinished;
          _end(async, 'op');

          limited = bench.run<int, void>(
            key: 'limited',
            timeout: const Duration(seconds: 3),
            (ctx) => ctx.abandonable(() => stage.start<void>('op', null)),
          );
          async.elapse(const Duration(seconds: 6));
        });

        expect(
          stage.lines,
          ['stuck is still running: SoloPending([stuck] in its body)'],
        );
        expect(runningAtSix, isTrue);
        expect('${reported.outcome}', 'Done(null)');
        expect('${limited.outcome}', 'Cancelled(timeout)');
      });

      test('the two recipes that read onFinish say nothing about a hang', () {
        _says(
          '`onFinish` never comes for a job that never finishes. The recipe '
          'of [Why cancellation was slow](#why-cancellation-was-slow) works '
          'out its delay right there, on `onFinish`, and so says nothing '
          'about a hang',
        );
        _run((async) {
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
        'The phase says where the job is, not why: while the body runs the '
        'phase is `body`, whatever it waits on, and the engine does not '
        'guess',
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
          _end(async, 'op');
        }

        expect(snapshots.toSet(), {'SoloPending([slow] in its body)'});
      });
    });

    test('a resource that takes its time to release', () {
      _says(
        'a resource that takes its time to release holds the job as long, '
        'in its `cleanup` phase',
      );
      _run((async) {
        Solo.observer = page.Hangs();
        Bench().run<int, void>(key: 'slow', (ctx) async {
          ctx.onDispose(() => stage.start<void>('release', null));
        });
        async.elapse(const Duration(seconds: 6));
        _end(async, 'release');
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
        _run((async) {
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
        _run((async) {
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
        _run((async) {
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
          'the same call through `ctx.abandonable` stops waiting at once, and '
          'so does a delay written as `ctx.pause`',
        );
        _says(
          'Only the first row is a line in the log: the other two stay under '
          'the 50 ms the observer starts reporting at',
        );
        final outcomes = <String>[];
        _run((async) {
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
        _run((async) {
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
          _run((async) {
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
          'The number is counted from the moment the job accepted the '
          'cancellation, not from `cancel()`, to the outcome, children and '
          'cleanup included',
        );
        _run((async) {
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
          'A job cancelled before it started reports nothing, because '
          '`onStart` never runs for it and so nothing was ever registered or '
          'stamped',
        );
        final started = <String>[];
        late Job<void> queued;
        late Job<void> refused;
        _run((async) {
          Solo.observer = SoloObserver.all([
            page.SlowCancellations(),
            _Saying('observer', started),
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
          '`clock.now()` rather than `DateTime.now()`: under `fake_async` the '
          'first moves with the fake time and the second stands still',
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
        _run((async) {
          Solo.observer = page.StuckCancellations();
          final job = _ignores(Bench(), 'ignores')..ignoreFailure();
          async.elapse(const Duration(seconds: 1));
          unawaited(job.cancel());
          async.elapse(const Duration(seconds: 6));
          _end(async, 'op');
        });

        expect(stage.lines, [_quoted()[2][0]]);
      });

      test('a job nobody cancelled, one that holds, one that stops', () {
        _says(
          'A job nobody cancelled arms nothing here, however long it runs',
        );
        _says(
          'Nor does it see a job inside an open `ctx.uncancellable` section — '
          'that cancellation is still held back, and `whenCancelled` has not '
          'fired',
        );
        final timers = <int>[];
        _run((async) {
          Solo.observer = page.StuckCancellations();
          Bench().run<int, void>(
            key: 'never',
            (ctx) => stage.start<void>('never', null),
          );
          final holds = Bench().run<int, void>(
            key: 'holds',
            (ctx) => ctx.uncancellable(() => stage.start<void>('held', null)),
          )..ignoreFailure();
          final stops = _waits(Bench(), 'stops')..ignoreFailure();
          async.elapse(const Duration(seconds: 1));
          timers.add(async.pendingTimers.length);
          unawaited(holds.cancel());
          unawaited(stops.cancel());
          async.flushMicrotasks();
          timers.add(async.pendingTimers.length);
          async.elapse(const Duration(seconds: 20));
          _end(async, 'held');
          _end(async, 'never');
        });

        expect(stage.lines, isEmpty);
        expect(timers, [0, 0], reason: 'the one that stopped disarmed its own');
      });

      test('a child the cancellation passed to', () {
        _says(
          'A child the cancellation passed to gets a line of its own, and '
          'the snapshot in it is of the root again',
        );
        _run((async) {
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
          _end(async, 'op');
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
        final ran = _run((async) {
          page.installAll();
          final bare = Bench().run<int, void>(key: 'bare', (ctx) => _delay(300))
            ..ignoreFailure();
          final stuck = _ignores(Bench(), 'ignores')..ignoreFailure();
          async.elapse(const Duration(milliseconds: 10));
          unawaited(bare.cancel());
          unawaited(stuck.cancel());
          async.elapse(const Duration(seconds: 6));
          _end(async, 'op');
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
          'call on its own: one that throws hands its error to the zone, and '
          'the next is called all the same',
        );
        final order = <String>[];
        final ran = _run((async) {
          Solo.observer = SoloObserver.all([
            _Saying('first', order, throwOn: 'onStart'),
            _Saying('second', order),
            _Saying('third', order),
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
          'The same observer twice in the list, and `SoloObserver.all` throws '
          '`ArgumentError`',
        );
        final one = _Watching();

        expect(
          () => SoloObserver.all([one, _Watching(), one]),
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

  group('Handled and unhandled failures', () {
    group('the first attempt:', () {
      test('a load that fails, and nobody waits for the result', () {
        _says(
          'Reading `job.outcome` says what happened without taking '
          'responsibility for it, and an observer only watches: an installed '
          'observer marks no outcome as observed',
        );
        _says(
          "A `Failed` that nobody observed goes to the job's creation zone "
          'through `Zone.handleUncaughtError` as well',
        );
        late Bench bench;
        final ran = _run((async) {
          Solo.observer = first.Failures();
          bench = Bench()
            ..run<int, void>(
              key: 'load',
              (ctx) async => throw StateError('no network'),
            );
        });

        expect(stage.crashes, ['no network'], reason: 'the reporter has it');
        expect(ran.errors, ['no network'], reason: 'and so has the zone');
        expect(bench.unanswered, isEmpty);
      });

      test('a load that is cancelled, and one that succeeds', () {
        final ran = _run((async) {
          Solo.observer = first.Failures();
          final bench = Bench()..run<int, void>(key: 'fine', (ctx) async {});
          final cancelled = _waits(bench, 'cancelled')..ignoreFailure();
          async.flushMicrotasks();
          unawaited(cancelled.cancel());
        });

        expect(stage.crashes, isEmpty);
        expect(ran.errors, isEmpty);
      });
    });

    group('observing the outcome:', () {
      test('the line of the page: load() and ignoreFailure()', () {
        _says(
          '`ignoreFailure()` is for the caller that needs no result and leaves '
          'reporting to the hooks',
        );
        late page.ProfileController profile;
        final ran = _run((async) {
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
          'Accessing `job.done` or `job.value`, or calling '
          '`job.ignoreFailure()`, marks the outcome as observed',
        );
        final caught = <String>[];
        String? read;
        final ran = _run((async) {
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
          'One failure it cannot catch: if the load fails and a cancellation '
          'reaches the job afterwards, whether before the error leaves the '
          'body or while the job still waits for children of its own or runs '
          'its cleanup, `await job.value` throws the `Cancelled`, and the '
          'failure goes to `onUnanswered` like the errors below',
        );
        final handled = <String>[];
        Object? thrown;
        late Job<String> job;
        late page.ProfileController profile;
        final ran = _run((async) {
          Solo.errorHandler =
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
        _says('`ignoreFailure()` silences that one too');
        final handled = <String>[];
        late Job<String> job;
        final ran = _run((async) {
          Solo.errorHandler =
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
      _says(
        'Errors from cleanup, cancellation callbacks and operations abandoned '
        'by `abandonable` go to the reporting hooks, and the controller is '
        'asked to answer for them through `onUnanswered`',
      );
      _says(
        'Without an override of it or an installed `Solo.errorHandler`, they '
        "fall back to the job's creation zone",
      );
      _says('Such an error can arrive after the job has already completed');
      _says('It does not replace an existing cancellation outcome');
      late Bench bench;
      late Job<void> job;
      var heardBefore = -1;
      final ran = _run((async) {
        bench = Bench();
        job = _waits(bench, 'abandons')..ignoreFailure();
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
        _says(
          'A `Cancelled` that arrives this way — an abandoned action that '
          'ended in the cancellation of another job, say — is told to the '
          'reporting hooks, and nobody is asked to answer for it: it reaches '
          'neither `onUnanswered` nor `Solo.errorHandler` nor the zone',
        );
        final handled = <String>[];
        final watching = _Watching();
        late Bench bench;
        final ran = _run((async) {
          Solo.observer = watching;
          if (withHandler) {
            Solo.errorHandler =
                (solo, job, error, stackTrace) => handled.add(text(error));
          }
          bench = Bench();
          final job = _waits(bench, 'abandons')..ignoreFailure();
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
      _says(
        "The job's own cancellation, thrown back by such an action, is news "
        'to nobody and is not reported at all',
      );
      final watching = _Watching();
      late Bench bench;
      late Job<void> job;
      final ran = _run((async) {
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
        _end(async, 'op');
      });

      expect('${job.outcome}', 'Cancelled(manual)');
      expect(bench.heard, isEmpty);
      expect(watching.heard, isEmpty);
      expect(bench.unanswered, isEmpty);
      expect(ran.errors, isEmpty);
    });

    test('the value of a cancelled job, taken and not handled', () {
      _says(
        'An unhandled error of `job.value` or `ctx.run(child)` is still an '
        "unhandled Future error under Dart's rules, even if that error is "
        "`Cancelled`: that route to the zone is Dart's own, not the engine's",
      );
      late Bench bench;
      final ran = _run((async) {
        bench = Bench();
        final job = _waits(bench, 'value');
        unawaited(job.value.then((_) {}));
        async.flushMicrotasks();
        unawaited(job.cancel());
      });

      expect(ran.errors, ['Cancelled(manual)']);
      expect(bench.heard, isEmpty, reason: 'no hook is told');
    });

    test('ctx.run(child) not awaited, and the child is cancelled', () {
      late Job<void> job;
      final ran = _run((async) {
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
        _end(async, 'body');
      });

      expect(ran.errors, ['Cancelled(manual)']);
      expect('${job.outcome}', 'Done(null)');
    });

    test('job.ignoreFailure() on a job whose value is already taken', () {
      _says(
        'Handle those futures like any other: `await` them where the error '
        'is caught, or give them `onError` or `Future.ignore()`. '
        '`job.ignoreFailure()` does nothing for a future already taken',
      );
      final caught = <String>[];
      final ran = _run((async) {
        SoloJob<void> cancelled(Bench bench) {
          final job = _waits(bench, 'value');
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
              '`ctx.check()` asks the job, not the error: it throws the '
              "job's `Cancelled` if the job has accepted one, whatever the "
              'catch took, and what follows handles the failures of a job '
              'nobody cancelled',
            );
          } else {
            _says(
              'Cancel this job while `hw.setZoom` is in flight: `join` waits '
              'the call out and throws `Cancelled` in place of its result, '
              'and the catch reads that as a failure of the camera. It '
              'resets a camera that opened and took its zoom',
            );
            _says(
              'the job ends exactly as a cancelled job should, neither the '
              'hooks nor the zone mention anything, and the only trace is on '
              'the device',
            );
          }
          late Desk<CameraState> camera;
          late Job<void> job;
          final ran = _run((async) {
            final (controller, started) = start();
            camera = controller as Desk<CameraState>;
            job = started..ignoreFailure();
            async.flushMicrotasks();
            _end(async, 'open');
            unawaited(job.cancel());
            async.flushMicrotasks();
            _end(async, 'setZoom');
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
          _run((async) {
            final (_, started) = start();
            job = started..ignoreFailure();
            async.flushMicrotasks();
            unawaited(job.cancel());
            async.flushMicrotasks();
            whileItOpens = '${job.outcome}';
            _end(async, 'open');
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
            _says('whoever cancelled the job waits for the reset as well');
          }
          var backAfterTheCall = false;
          var resetStarted = false;
          _run((async) {
            stage.endsByItself.remove('reset');
            final (camera, started) = start();
            started.ignoreFailure();
            async.flushMicrotasks();
            _end(async, 'open');
            var back = false;
            camera.close().then((_) => back = true);
            async.flushMicrotasks();
            _end(async, 'setZoom');
            backAfterTheCall = back;
            resetStarted = stage.isRunning('reset');
            if (resetStarted) _end(async, 'reset');
          });

          expect(resetStarted, !asks);
          expect(backAfterTheCall, asks, reason: 'close() waits for the reset');
        });

        test('nobody cancels, and hw.open fails', () {
          late Desk<CameraState> camera;
          late Job<void> job;
          _run((async) {
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
          _run((async) {
            final (controller, started) = start();
            camera = controller as Desk<CameraState>;
            job = started..ignoreFailure();
            async.flushMicrotasks();
            _end(async, 'open');
            _fail(async, 'setZoom', StateError('no zoom'));
          });

          expect(stage.trace.sublist(4), ['reset start', 'reset end']);
          expect('${camera.currentState}', 'Broken(no zoom)');
          expect('${job.outcome}', 'Failed(Bad state: no zoom)');
        });

        test('cancelled, and then hw.open fails on its own', () {
          if (asks) {
            _says(
              'a camera that fails on its own once the job has accepted a '
              'cancellation is not reset by this catch either, and no hook '
              'hears of the failure',
            );
          }
          late Desk<CameraState> camera;
          late Job<void> job;
          final ran = _run((async) {
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
          _run((async) {
            final (_, started) = start();
            job = started;
            async.flushMicrotasks();
            _end(async, 'open');
            _end(async, 'setZoom');
          });

          expect(stage.trace, hasLength(4), reason: 'no reset');
          expect('${job.outcome}', 'Done(null)');
        });
      });
    }

    test('Cancelled implements Exception', () {
      _says(
        '`Cancelled` implements `Exception`, so a broad `catch` takes it '
        'along with the device failures',
      );
      expect(const Cancelled('why'), isA<Exception>());
    });

    test('on a cancelled job emit throws, and the rethrow never runs', () {
      _says(
        '`ctx.emit` on a cancelled job throws `Cancelled` in turn, so '
        '`Broken` never reaches the screen and the `rethrow` under it never '
        'runs — and the outcome is the same `Cancelled` that `rethrow` would '
        'have given',
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
        _end(async, 'op');

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
          '`on Cancelled { rethrow; }` in front of the broad clause, or '
          '`if (error is Cancelled) rethrow;` as its first line, holds while '
          'every call in the `try` runs to its end',
        );
        _says(
          'The clause lets that error by, and the camera is reset for a '
          'cancellation again',
        );
        late _TokenCamera camera;
        late Job<void> job;
        _run((async) {
          camera = _TokenCamera();
          job = camera.open(clause)..ignoreFailure();
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          _end(async, 'open');
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
        _run((async) {
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
        'stops by throwing sends the catch an error of its own in place of '
        'the `Cancelled`: `join` throws an error of its call as it is',
      );
      late _TokenCamera camera;
      late Job<void> job;
      _run((async) {
        camera = _TokenCamera();
        job = camera.open('ctx.check()')..ignoreFailure();
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        _end(async, 'open');
      });

      expect(stage.trace, ['open start', 'open end', 'open stopped']);
      expect('${job.outcome}', 'Cancelled(manual)');
      expect(camera.heard, isEmpty, reason: 'the error never left the body');
    });

    test('a body that catches its cancellation and returns a value', () {
      _says(
        'Once a job has accepted cancellation, its outcome remains '
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
        'For a final failure state, prefer the `ifFailed` parameter of `run` '
        'rather than writing that correction inside a broad catch',
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
        _end(async, 'op');

        expect('${failed.outcome}', 'Failed(Bad state: no camera)');
        expect(failing.currentState, -1);
        expect('${cancelled.outcome}', 'Cancelled(manual)');
        expect(stopping.currentState, 0, reason: 'no failure state for it');
      });
    });
  });

  group('Errors in state rules', () {
    group('the first attempt:', () {
      test('no free slot', () {
        _says(
          'The error goes to the reporting hooks — a crash report for an '
          'ordinary "not now" — and the job ends `Failed`, which reaches the '
          'creation zone as well unless somebody observes that outcome',
        );
        _says(
          'The state handler passed as `ifFailed` to that same `run` is not '
          'called for it: a state handler computes the state after a job '
          'that ran, and this one never started',
        );
        _says('The queue goes on to the next job');
        final started = <String>[];
        late first.ThrowingPool pool;
        late Job<void> job;
        late Job<void> next;
        final ran = _run((async) {
          Solo.observer = _Saying('observer', started);
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
        expect(pool.unanswered, isEmpty);
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
        final ran = _run((async) {
          pool = first.ThrowingPool(const Slots(0));
          pool.take().ignoreFailure();
        });

        expect(pool.heard, ['take: no free slot']);
        expect(ran.errors, isEmpty);
      });

      test('a free slot', () {
        late Job<void> job;
        _run((async) {
          job = first.ThrowingPool(const Slots(1)).take();
        });

        expect('${job.outcome}', 'Done(null)');
        expect(stage.trace, ['take ran']);
      });
    });

    group('a rule answers:', () {
      test('no free slot', () {
        _says(
          'A rule that answers `false` is not an error: it cancels the job, '
          'and the `Cancelled` carries a trace',
        );
        late page.Pool pool;
        late Job<void> job;
        late Job<void> next;
        final ran = _run((async) {
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
        _run((async) {
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
          'A `keepWhile` re-checked on a change says no from inside it, so '
          'that trace is the change — the `emit` or the `externalSetState` '
          'whose state broke the rule',
        );
        fakeAsync((async) {
          Solo.traceStateChanges = true;
          final traced = _Traced();
          final job = kept(traced);
          async.flushMicrotasks();
          traced.setsTooBig();
          async.flushMicrotasks();

          expect('${job.outcome}', 'Cancelled(rules: keepWhile)');
          expect(
            _frames(outcomeOf(job).stackTrace).take(3),
            [
              'Solo.externalSetState',
              'OpenSolo.externalSetState',
              '_Traced.setsTooBig',
            ],
          );
        });
      });

      test('the same without the trace of the change', () {
        _says(
          'Dropped, the trace is taken at the rejection instead, a couple of '
          'engine frames above the same change',
        );
        fakeAsync((async) {
          Solo.traceStateChanges = false;
          final traced = _Traced();
          final job = kept(traced);
          async.flushMicrotasks();
          traced.setsTooBig();
          async.flushMicrotasks();

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
          Solo.traceStateChanges = true;
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
            _frames(outcomeOf(job).stackTrace).take(2),
            ['_SoloContext.emit', '_Traced.emitsTooBig'],
          );
        });
      });

      test('traceStateChanges where assertions are on', () {
        _says(
          'it is taken where assertions are on and left out of a release '
          'build: `Solo.traceStateChanges = true` keeps it everywhere, '
          '`false` drops it everywhere',
        );
        var assertionsOn = false;
        assert(assertionsOn = true, 'only evaluated where assertions are on');

        expect(traceStateChanges, assertionsOn);
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
                default:
                  await traced.waitsOnTheContext(ctx);
              }
            },
          )..ignoreFailure();

      const checkpoints = {
        'ctx.state': '_Traced.readsTheState',
        'ctx.check()': '_Traced.checksTheJob',
        'a waiting method': '_Traced.waitsOnTheContext',
      };
      for (final MapEntry(key: kind, value: member) in checkpoints.entries) {
        test('a job that breaks its own rule, and then reaches $kind', () {
          _says(
            'A job that breaks its own rule is not re-evaluated on its own '
            '`emit`: it finds out at its next checkpoint — a `ctx.state`, a '
            '`ctx.check()`, a waiting method — and without the trace of the '
            'change that checkpoint is all the `Cancelled` has',
          );
          fakeAsync((async) {
            Solo.traceStateChanges = true;
            final withTrace = breaksItsOwnRule(_Traced(), kind);
            async.flushTimers();
            Solo.traceStateChanges = false;
            final without = breaksItsOwnRule(_Traced(), kind);
            async.flushTimers();

            expect('${withTrace.outcome}', 'Cancelled(rules: keepWhile)');
            expect(
              stage.trace,
              ['the body went on', 'the body went on'],
              reason: 'the call of the waiting method never started',
            );
            expect(
              _frames(outcomeOf(withTrace).stackTrace).take(2),
              ['_SoloContext.emit', '_Traced.emitsTooBig'],
            );
            final frames = _frames(outcomeOf(without).stackTrace);
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
          for (final traced in [true, false]) {
            Solo.traceStateChanges = traced;
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
          }
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
          _run((async) {
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
        final ran = _run((async) {
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
          _end(async, 'op');
        });

        expect(caught, ['the rule']);
        expect('${job.outcome}', 'Done(null)');
        expect(bench.heard, isEmpty, reason: 'the body alone received it');
        expect(ran.errors, isEmpty);
      });

      test('a rule throws at a checkpoint, and the body lets it out', () {
        late Bench bench;
        late Job<void> job;
        _run((async) {
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
          _end(async, 'op');
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
        final ran = _run((async) {
          bench = Bench();
          job = reevaluated(bench, handled: false);
          async.flushMicrotasks();
          bench.reflect(1);
          async.flushMicrotasks();
          cancelledByIt = job.isCancelled;
          _end(async, 'op');
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
        _run((async) {
          bench = Bench();
          job = reevaluated(bench, handled: true);
          async.flushMicrotasks();
          bench.reflect(1);
          _end(async, 'op');
        });

        expect(bench.unanswered, ['reevaluated: the rule']);
        expect('${job.outcome}', 'Failed(Bad state: the body)');
        expect(stage.trace, isNot(contains('the state handler ran')));
        expect(bench.currentState, 1, reason: 'no correction to 99');
      });

      test('the same job with a rule that holds: the handler runs', () {
        late Bench bench;
        _run((async) {
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
          _end(async, 'op');
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
        final ran = _run((async) {
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
          _end(async, 'release');
        });

        expect(bench.heard, ['ended: the body', 'ended: the rule']);
        expect(bench.unanswered, ['ended: the rule']);
        expect(bench.currentState, 1, reason: 'the handler is disabled');
        expect(ran.errors, ['the rule']);
      });

      test('a job without one, re-evaluated after its body has ended', () {
        late Bench bench;
        _run((async) {
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
          _end(async, 'release');
        });

        expect(bench.heard, isEmpty, reason: 'its rules are not asked');
      });

      test('the zone of last resort for a rule that throws on a change', () {
        _says(
          "Re-evaluation errors fall back to the job's creation zone when "
          'neither an override of `onUnanswered` nor a `Solo.errorHandler` '
          'answers for them',
        );
        final where = <String, List<String>>{};
        fakeAsync((async) {
          late Bench bench;
          where['the controller was created'] = _zoneOf(() => bench = Bench());
          where['the job was created'] = _zoneOf(
            () => reevaluated(bench, handled: false),
          );
          where['the state changed'] = _zoneOf(() {
            async.flushMicrotasks();
            bench.reflect(1);
            _end(async, 'op');
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

  group('Background work and logs', () {
    group('the first attempt:', () {
      test('the send fails once the job is over', () {
        _says(
          "The future's error belongs to nobody in the job: the hooks never "
          'see it, `Solo.errorHandler` is never asked',
        );
        final handled = <String>[];
        late first.BroadCamera camera;
        late Job<void> job;
        final ran = _run((async) {
          Solo.errorHandler =
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

      test('the zone it surfaces in is the one the body ran in', () {
        _says(
          'it surfaces as an unhandled error in whatever zone the body '
          'happened to run in, with nothing there to name the job it came '
          'from',
        );
        final where = <String, List<String>>{};
        fakeAsync((async) {
          late first.BroadCamera camera;
          // The queue starts the second job from the zone its pump was
          // scheduled in, which is the zone of the first job here.
          where['the first job was created'] = _zoneOf(() {
            camera = first.BroadCamera(Hardware())
              ..run<CameraState, void>(
                key: 'first',
                (ctx) => ctx.abandonable(() => stage.start<void>('op', null)),
              );
          });
          where['the second job was created'] = _zoneOf(() {
            async.flushMicrotasks();
            camera.zoomTo(2);
          });
          where['the rest'] = _zoneOf(() {
            _end(async, 'op');
            _fail(async, 'send', StateError('analytics offline'));
          });
        });

        expect(where, {
          'the first job was created': ['analytics offline'],
          'the second job was created': isEmpty,
          'the rest': isEmpty,
        });
      });
    });

    group('work with a life of its own:', () {
      test('the send fails once the job is over', () {
        _says(
          'Its errors stay with the job, even after the job finishes: the '
          'reporting hooks are told, `onUnanswered` is asked to answer, and '
          'with nothing to answer they end in the zone the job was created '
          'in',
        );
        late page.Camera camera;
        late Job<void> job;
        String? whenTheWorkFailed;
        final ran = _run((async) {
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
        final ran = _run((async) {
          Solo.errorHandler =
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
          where['the first job was created'] = _zoneOf(() {
            camera = page.Camera(Hardware())
              ..run<CameraState, void>(
                key: 'first',
                (ctx) => ctx.abandonable(() => stage.start<void>('op', null)),
              );
          });
          where['the second job was created'] = _zoneOf(() {
            async.flushMicrotasks();
            camera.zoomTo(2, page.sendZoom);
          });
          where['the rest'] = _zoneOf(() {
            _end(async, 'op');
            _fail(async, 'send', StateError('analytics offline'));
          });
        });

        expect(where, {
          'the first job was created': isEmpty,
          'the second job was created': ['analytics offline'],
          'the rest': isEmpty,
        });
      });

      test('the job is cancelled, and then closed, while the work goes on', () {
        _says(
          '`ctx.unattended(action)` starts work that the job does not wait '
          'for or cancel',
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
          _end(async, 'send');
        });
      });

      test('what the context refuses inside the work, and what it lets do', () {
        _says(
          'Unattended work is not the job, and the context refuses there '
          'whatever acts on the job: `ctx.run`, `ctx.runAll`, `ctx.each` and '
          '`ctx.uncancellable` all throw a `StateError` that names the call — '
          '`cannot run a child inside unattended work` for `ctx.run`',
        );
        final refused = <String, String>{};
        final let = <String>[];
        late Bench bench;
        _run((async) {
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
          _end(async, 'op');
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
          'the road above, to the hooks, and the job itself still ends '
          '`Done`',
        );
        late Bench bench;
        late Job<void> job;
        final ran = _run((async) {
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
          'A captured context still belongs to the original job: `emit` can '
          'work while that job is active, but is rejected after cancellation '
          'or completion',
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
          _end(async, 'op');
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
          _end(async, 'op');

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

    group('logs:', () {
      test('the data of the page, handed on as it is', () {
        _says(
          '`ctx.log(data)` forwards application data to log hooks and '
          'observers as it is, so a listener that wants a line makes one',
        );
        final watching = <Object?>[];
        _run((async) {
          Solo.observer = _Logs(watching);
          page.Camera(Hardware()).zoomTo(2, page.logZoom);
        });

        expect(watching, [('zoom', 2.0)]);
        expect(stage.fine, [('zoom', 2.0)], reason: 'the hook of the page');
      });

      test('the lazy line of the page, with the logger at FINE', () {
        _says(
          'The body logs unconditionally, and `describe()` runs only where '
          'somebody listens at that level',
        );
        _run((async) {
          page.Camera(Hardware()).zoomTo(2, page.logLazily);
        });

        expect(stage.fine, ['zoom to 2.0 on the back camera']);
        expect(stage.described, 1);
      });

      test('the lazy line of the page, with the logger at INFO', () {
        _says(
          'Everywhere else the message stays a closure nobody called',
        );
        _says('`ctx.log` calls nothing on the way either');
        final watching = <Object?>[];
        _run((async) {
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
        _run((async) {
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
          "`Solo.debug` additionally traces the controller's internal queue "
          'and lifecycle operations',
        );
        _says(
          'Each job reports its start, its errors, a cancellation that '
          "reaches it and its outcome to `Job.debug`, the core's channel; "
          'both sides show when both are set',
        );
        final ran = _run((async) {
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

      test('one channel alone: the queue without the jobs, and the reverse',
          () {
        List<String> printedWith(void Function() install) => _run((async) {
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
  });

  group('The page', () {
    test('five sections open with a first attempt, as the introduction says',
        () {
      expect(
        RegExp(r'^### The first attempt$', multiLine: true).allMatches(_page()),
        hasLength(5),
      );
      _says('Five sections below open with the version');
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
      '### Answering for an error': answer,
      '## Watching every controller': answers,
      '## What is holding the controller': answers,
      '### The first attempt': attempts,
      '### Stamping the cancellation': answers,
      '### A cancellation that never lands': answers,
      '### Observing the outcome': answers,
      '### Letting cancellation through': answers,
      '### A rule answers': answers,
      '### Work with a life of its own': answers,
      '### Logs': answers,
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
}

/// An observer that keeps what `onLog` was handed.
final class _Logs extends SoloObserver {
  final List<Object?> into;

  _Logs(this.into);

  @override
  void onLog(Solo<Object> solo, Job<Object?> job, Object? message) =>
      into.add(message);
}
