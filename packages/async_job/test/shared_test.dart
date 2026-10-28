@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/probe_job.dart';

// A job is continued once: by one `then`, or by handles of `shared()`. A
// handle ends with the outcome of its source and never reaches back to it.

/// Answers for every failure it is asked about and keeps the list.
final class Answers extends JobObserver with JobAnswerer {
  final answered = <String>[];
  final finished = <String>[];
  final started = <String>[];

  @override
  void onStart(Job<Object?> job) => started.add('$job');

  @override
  void onFinish(Job<Object?> job) => finished.add('$job');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      answered.add('$job: $error');
}

/// Answers like [Answers], keeps what it hears, and with [cancels] cancels
/// the job it hears an error of.
final class Hears extends Answers {
  final bool cancels;
  final heard = <String>[];

  Hears({this.cancels = false});

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) {
    heard.add('$job: $error');
    if (cancels) job.cancel().ignore();
  }
}

/// A source that runs until [gate] completes.
Job<int> gated(Completer<int> gate, {String? key, JobObserver? observer}) =>
    Job<int>(
      key: key,
      observer: observer,
      (ctx) => ctx.abandonable(() => gate.future),
    );

/// What reached the zone while [body] and the fake time ran.
List<String> zoneOf(void Function(FakeAsync async) body) {
  final errors = <String>[];
  fakeAsync((async) {
    runZonedGuarded(() => body(async), (error, _) => errors.add('$error'));
    async.flushTimers();
  });
  return errors;
}

const continuedOnce =
    'Bad state: Job(load) already has a continuation: a job '
    'is continued once; call shared() for each branch';

void main() {
  group('a job is continued once', () {
    test('a second then throws before anything is made', () {
      fakeAsync((async) {
        final load = Job<int>(key: 'load', (ctx) async => 1);
        final first = load.then<int>((ctx, value) => value + 1);
        expect(
          () => load.then<int>((ctx, value) => value),
          throwsA(isA<StateError>().having((e) => '$e', 'text', continuedOnce)),
        );
        async.flushMicrotasks();
        expect('${first.outcome}', 'Done(2)');
      });
    });

    test('a then that has ended still holds its place', () {
      fakeAsync((async) {
        final load = Job<int>(key: 'load', (ctx) async => 1);
        final first = load.then<int>((ctx, value) => value);
        async.flushMicrotasks();
        expect(first.isFinished, isTrue);
        expect(() => load.then<int>((ctx, value) => value), throwsStateError);
      });
    });

    test('then on a job with a handle throws', () {
      fakeAsync((async) {
        final load = Job<int>(key: 'load', (ctx) async => 1)..shared();
        expect(
          () => load.then<int>((ctx, value) => value),
          throwsA(isA<StateError>().having((e) => '$e', 'text', continuedOnce)),
        );
        async.flushMicrotasks();
      });
    });

    test('shared on a job with a then throws', () {
      fakeAsync((async) {
        final load = Job<int>(key: 'load', (ctx) async => 1)
          ..then<int>((ctx, value) => value);
        expect(
          load.shared,
          throwsA(isA<StateError>().having((e) => '$e', 'text', continuedOnce)),
        );
        async.flushMicrotasks();
      });
    });

    test('a handle is continued once too', () {
      fakeAsync((async) {
        final handle = Job<int>((ctx) async => 1).shared()
          ..then<int>((ctx, value) => value);
        expect(handle.shared, throwsStateError);
        expect(() => handle.then<int>((ctx, value) => value), throwsStateError);
        async.flushMicrotasks();
      });
    });
  });

  group('a job an engine hands to several callers', () {
    const handedOut =
        'Bad state: Job(load) is handed to every caller of its '
        'key: continue it through shared(), a handle for each caller';

    ProbeJob<int> handed() =>
        ProbeJob<int>(key: 'load', (ctx) async => 1)
          ..handOut('is handed to every caller of its key');

    test('throws on the first then, before anything is made', () {
      fakeAsync((async) {
        final load = handed();
        expect(
          () => load.then<int>((ctx, value) => value),
          throwsA(isA<StateError>().having((e) => '$e', 'text', handedOut)),
        );
        // Nothing was taken: every caller still gets a handle.
        final first = load.shared();
        final second = load.shared();
        load.launch();
        async.flushMicrotasks();
        expect('${first.outcome}', 'Done(1)');
        expect('${second.outcome}', 'Done(1)');
      });
    });

    test('throws on then next to a handle with its own reason', () {
      fakeAsync((async) {
        final load = handed()..shared();
        expect(
          () => load.then<int>((ctx, value) => value),
          throwsA(isA<StateError>().having((e) => '$e', 'text', handedOut)),
        );
        load.launch();
        async.flushMicrotasks();
      });
    });

    test('keeps a then taken before the mark', () {
      fakeAsync((async) {
        final load = ProbeJob<int>(key: 'load', (ctx) async => 1);
        final first = load.then<int>((ctx, value) => value + 1);
        load.handOut('is handed to every caller of its key');
        expect(
          load.shared,
          throwsA(isA<StateError>().having((e) => '$e', 'text', continuedOnce)),
        );
        expect(
          () => load.then<int>((ctx, value) => value),
          throwsA(isA<StateError>().having((e) => '$e', 'text', handedOut)),
        );
        load.launch();
        async.flushMicrotasks();
        expect('${first.outcome}', 'Done(2)');
      });
    });

    test('keeps the reason it was first given', () {
      fakeAsync((async) {
        final load = handed()..handOut('is somebody else');
        expect(
          () => load.then<int>((ctx, value) => value),
          throwsA(isA<StateError>().having((e) => '$e', 'text', handedOut)),
        );
        load.launch();
        async.flushMicrotasks();
      });
    });

    test('leaves the handles free to be continued by then', () {
      fakeAsync((async) {
        final handle = handed().shared();
        final next = handle.then<int>((ctx, value) => value + 1);
        expect('${next.outcome}', 'null');
        async.flushMicrotasks();
      });
    });
  });

  group('a handle of shared()', () {
    test('ends with the Done of its source', () {
      fakeAsync((async) {
        final source = Job<int>((ctx) async => 21);
        final one = source.shared();
        final two = source.shared();
        async.flushMicrotasks();
        expect('${one.outcome}', 'Done(21)');
        expect('${two.outcome}', 'Done(21)');
        expect('$one', 'Job(shared)');
      });
    });

    test('cancelled, ends at once and leaves the source and the other '
        'handle', () {
      fakeAsync((async) {
        final gate = Completer<int>();
        final source = gated(gate);
        final one = source.shared();
        final two = source.shared();
        async.flushMicrotasks();
        var returned = false;
        one.cancel().then((_) => returned = true);
        async.flushMicrotasks();
        expect(returned, isTrue, reason: 'cancel() does not wait for source');
        expect(one.outcome, isA<Cancelled>());
        expect((one.outcome! as Cancelled).reason, isA<ManualCancelReason>());
        expect(source.isCancelled, isFalse);
        expect(two.isFinished, isFalse);
        gate.complete(3);
        async.flushMicrotasks();
        expect('${source.outcome}', 'Done(3)');
        expect('${two.outcome}', 'Done(3)');
        expect('${one.outcome}', startsWith('Cancelled'));
      });
    });

    test('a cancelled continuation of a handle leaves the source', () {
      fakeAsync((async) {
        final gate = Completer<int>();
        final source = gated(gate);
        final handle = source.shared();
        final tail = handle.then<int>((ctx, value) => value);
        async.flushMicrotasks();
        tail.cancel().ignore();
        async.flushMicrotasks();
        expect((handle.outcome! as Cancelled).reason, isA<ChainCancelReason>());
        expect(tail.outcome, isA<Cancelled>());
        expect(source.isCancelled, isFalse);
        gate.complete(3);
        async.flushMicrotasks();
        expect('${source.outcome}', 'Done(3)');
      });
    });

    test('ends Cancelled(chain) at the mark when the source accepts a '
        'cancellation, before its cleanup', () {
      fakeAsync((async) {
        final cleanup = Completer<void>();
        final source = Job<int>((ctx) async {
          ctx.onDispose(() => cleanup.future);
          return ctx.abandonable(() => Completer<int>().future);
        });
        final one = source.shared();
        final two = source.shared();
        async.flushMicrotasks();
        source.cancel().ignore();
        async.flushMicrotasks();
        expect(source.isFinished, isFalse, reason: 'cleanup is still on');
        for (final handle in [one, two]) {
          final reason = (handle.outcome! as Cancelled).reason;
          expect(reason, isA<ChainCancelReason>());
        }
        cleanup.complete();
        async.flushMicrotasks();
        expect(source.outcome, isA<Cancelled>());
      });
    });

    for (final alternate in [false, true]) {
      test('a 5000-deep nest of '
          '${alternate ? 'handles and continuations' : 'handles'} is '
          'cancelled from the source', () {
        late List<Job<int>> jobs;
        late bool allCancelled;
        final errors = zoneOf((async) {
          final gate = Completer<int>();
          final source = gated(gate);
          jobs = <Job<int>>[source];
          for (var i = 0; i < 5000; i++) {
            final last = jobs.last;
            jobs.add(
              alternate && i.isOdd
                  ? last.then<int>((ctx, value) => value)
                  : last.shared(),
            );
          }
          async.flushMicrotasks();
          source.cancel().ignore();
          async.flushMicrotasks();
          allCancelled = jobs.every((job) => job.outcome is Cancelled);
          gate.complete(1);
        });
        expect(errors, isEmpty);
        expect(allCancelled, isTrue);
        expect(jobs.every((job) => job.outcome is Cancelled), isTrue);
      });
    }

    test('waits while its source refuses a cancellation', () {
      fakeAsync((async) {
        final gate = Completer<int>();
        final source = Job<int>(
          cancellable: false,
          (ctx) => ctx.join(() => gate.future),
        );
        final handle = source.shared();
        async.flushMicrotasks();
        source.cancel().ignore();
        async.flushMicrotasks();
        expect(handle.isFinished, isFalse);
        gate.complete(5);
        async.flushMicrotasks();
        expect('${handle.outcome}', 'Done(5)');
      });
    });

    test('does not start a deferred source', () {
      fakeAsync((async) {
        final source = Job.deferred<int>((ctx) async => 1);
        final handle = source.shared();
        async.flushTimers();
        expect(source.isRunning || source.isFinished, isFalse);
        expect(handle.isFinished, isFalse);
        source.start();
        async.flushMicrotasks();
        expect('${handle.outcome}', 'Done(1)');
      });
    });

    for (final (kind, expected) in [
      ('done', 'Done(42)'),
      ('failed', 'Failed(Bad state: failed)'),
      ('cancelled', 'Cancelled(chain)'),
    ]) {
      test('of a source already $kind ends on the next microtask', () {
        fakeAsync((async) {
          final source = Job<int>((ctx) async {
            if (kind == 'failed') throw StateError('failed');
            return 42;
          })..ignoreFailure();
          if (kind == 'cancelled') source.cancel().ignore();
          async.flushMicrotasks();
          expect(source.isFinished, isTrue);
          final answers = Answers();
          final handle = source.shared(observer: answers);
          expect(handle.outcome, isNull, reason: 'not inside the call');
          expect(answers.finished, isEmpty);
          async.flushMicrotasks();
          expect('${handle.outcome}', startsWith(expected));
          expect(answers.finished, ['Job(shared)']);
        });
      });
    }

    test('of a source that took a cancellation and still runs ends on the '
        'next microtask', () {
      fakeAsync((async) {
        final gate = Completer<void>();
        // A bare await is no checkpoint: the job takes the cancellation and
        // its body runs on.
        final unwinding = Job<int>((ctx) async {
          await gate.future;
          return 1;
        })..ignoreFailure();
        async.flushMicrotasks();
        unwinding.cancel().ignore();
        async.flushMicrotasks();
        expect(unwinding.isCancelled, isTrue);
        expect(unwinding.isFinished, isFalse);
        final answers = Answers();
        final handle = unwinding.shared(observer: answers);
        expect(handle.outcome, isNull, reason: 'not inside the call');
        expect(answers.finished, isEmpty);
        async.flushMicrotasks();
        expect('${handle.outcome}', startsWith('Cancelled(chain)'));
        expect(answers.finished, ['Job(shared)']);
        expect(unwinding.isFinished, isFalse, reason: 'the source still runs');
        gate.complete();
        async.flushMicrotasks();
        expect(unwinding.outcome, isA<Cancelled>());
      });
    });

    test('is not a child: run does not take it', () {
      fakeAsync((async) {
        final handle = Job<int>((ctx) async => 1).shared();
        expect(handle, isNot(isA<ChildJob<int>>()));
        Object? thrown;
        final parent = ProbeJob<void>((ctx) async {
          try {
            (ctx as ProbeContext).adopt(handle);
          } on Object catch (error) {
            thrown = error;
          }
        })..launch();
        async.flushMicrotasks();
        expect(
          '$thrown',
          'Invalid argument (child): is a continuation, which finishes with '
              'its source: "Job(shared)"',
        );
        expect(parent.outcome, isA<Done<void>>());
        expect('${handle.outcome}', 'Done(1)');
      });
    });

    test('has an observer of its own that hears onFinish, not onStart', () {
      fakeAsync((async) {
        final answers = Answers();
        final handle = Job<int>((ctx) async => 1).shared(observer: answers);
        async.flushMicrotasks();
        expect(handle.outcome, isA<Done<int>>());
        expect(answers.started, isEmpty);
        expect(answers.finished, ['Job(shared)']);
      });
    });
  });

  group('a failure the handles carry', () {
    test('two unobserved handles answer for it once', () {
      final answers = Answers();
      final errors = zoneOf((async) {
        Job<int>(
            key: 'load',
            observer: answers,
            (ctx) async => throw StateError('load'),
          )
          ..shared(observer: answers)
          ..shared(observer: answers);
      });
      expect(answers.answered, ['Job(shared): Bad state: load']);
      expect(errors, isEmpty);
    });

    test('an observed handle hears it, and the other answers', () {
      final answers = Answers();
      final heard = <String>[];
      final errors = zoneOf((async) {
        final source = Job<int>(
          key: 'load',
          observer: answers,
          (ctx) async => throw StateError('load'),
        );
        source.shared().done.then((outcome) => heard.add('$outcome'));
        source.shared(observer: answers);
      });
      expect(heard, ['Failed(Bad state: load)']);
      expect(answers.answered, ['Job(shared): Bad state: load']);
      expect(errors, isEmpty);
    });

    test('with no answerer, it reaches the zone once', () {
      final errors = zoneOf((async) {
        Job<int>((ctx) async => throw StateError('load'))
          ..shared()
          ..shared();
      });
      expect(errors, ['Bad state: load']);
    });

    test('a handle cancelled before the failure leaves it to the source', () {
      final answers = Answers();
      final errors = zoneOf((async) {
        final gate = Completer<int>();
        final source = gated(gate, key: 'load', observer: answers);
        final handle = source.shared(observer: answers);
        async.flushMicrotasks();
        handle.cancel().ignore();
        async.flushMicrotasks();
        gate.completeError(StateError('load'));
      });
      expect(answers.answered, ['Job(load): Bad state: load']);
      expect(errors, isEmpty);
    });

    test('a handle made after the answer carries it with no answer', () {
      final answers = Answers();
      late Job<int> handle;
      late List<String> answeredBefore;
      final errors = zoneOf((async) {
        final source = Job<int>(
          key: 'load',
          observer: answers,
          (ctx) async => throw StateError('load'),
        );
        async.flushMicrotasks();
        answeredBefore = [...answers.answered];
        handle = source.shared(observer: answers);
      });
      expect(answeredBefore, ['Job(load): Bad state: load']);
      expect(handle.outcome, isA<Failed>());
      expect(answers.answered, ['Job(load): Bad state: load']);
      expect(errors, isEmpty);
    });

    test('a branch the group answers for and its handle answer once', () {
      final answers = Answers();
      late Job<int> handle;
      final errors = zoneOf((async) {
        // `a` refuses the cancellation the failure of `b` brings, and fails
        // after the group chose `b`: the group answers for `a`, and the
        // handle carries the same failure.
        final a = Job.deferred<int>(key: 'a', cancellable: false, (ctx) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          throw StateError('a');
        });
        final b = Job.deferred<int>(
          key: 'b',
          (ctx) async => throw StateError('b'),
        );
        Job<void>(key: 'parent', observer: answers, (ctx) async {
          handle = a.shared(observer: answers);
          await ctx.runAll([b, a]);
        }).ignoreFailure();
      });
      expect(handle.outcome, isA<Failed>());
      expect(answers.answered.where((line) => line.endsWith('state: a')), [
        anyOf('Job(a): Bad state: a', 'Job(shared): Bad state: a'),
      ]);
      expect(errors, isEmpty);
    });

    test('a handle made after the group answered for a branch carries it', () {
      final answers = Answers();
      late ChildJob<int> a;
      late Job<int> handle;
      late List<String> answeredBefore;
      final errors = zoneOf((async) {
        a = Job.deferred<int>(key: 'a', cancellable: false, (ctx) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          throw StateError('a');
        });
        final b = Job.deferred<int>(
          key: 'b',
          (ctx) async => throw StateError('b'),
        );
        Job<void>(
          key: 'parent',
          observer: answers,
          (ctx) => ctx.runAll([b, a]),
        ).ignoreFailure();
        async.elapse(const Duration(milliseconds: 2));
        answeredBefore = [...answers.answered];
        handle = a.shared(observer: answers);
      });
      expect(answeredBefore, ['Job(a): Bad state: a']);
      expect(handle.outcome, isA<Failed>());
      expect(answers.answered, ['Job(a): Bad state: a']);
      expect(errors, isEmpty);
    });

    test('the observer of a handle hears it once', () {
      final answers = Answers();
      final hears = Hears();
      final errors = zoneOf((async) {
        Job<int>(
          key: 'load',
          observer: answers,
          (ctx) async => throw StateError('load'),
        ).shared(observer: hears);
      });
      expect(hears.heard, ['Job(shared): Bad state: load']);
      expect(hears.answered, ['Job(shared): Bad state: load']);
      expect(answers.answered, isEmpty);
      expect(errors, isEmpty);
    });

    test('a handle its observer cancels on hearing it answers for it', () {
      final answers = Answers();
      final cancels = Hears(cancels: true);
      late Job<int> handle;
      final errors = zoneOf((async) {
        handle = Job<int>(
          key: 'load',
          observer: answers,
          (ctx) async => throw StateError('load'),
        ).shared(observer: cancels);
      });
      expect(handle.outcome, isA<Cancelled>());
      expect(cancels.answered, ['Job(shared): Bad state: load']);
      expect(answers.answered, isEmpty);
      expect(errors, isEmpty);
    });

    test('a handle cancelled on hearing it and another answer once', () {
      final answers = Answers();
      final cancels = Hears(cancels: true);
      final errors = zoneOf((async) {
        Job<int>(
            key: 'load',
            observer: answers,
            (ctx) async => throw StateError('load'),
          )
          ..shared(observer: cancels)
          ..shared(observer: answers);
      });
      expect(
        [...cancels.answered, ...answers.answered],
        ['Job(shared): Bad state: load'],
      );
      expect(errors, isEmpty);
    });

    test('a continuation cancelled on hearing it and a handle answer once', () {
      final answers = Answers();
      final cancels = Hears(cancels: true);
      final errors = zoneOf((async) {
        final source = Job<int>(
          key: 'load',
          observer: answers,
          (ctx) async => throw StateError('load'),
        );
        source.shared().then<int>((ctx, value) => value, observer: cancels);
        source.shared(observer: answers);
      });
      expect([...cancels.answered, ...answers.answered], hasLength(1));
      expect(errors, isEmpty);
    });

    test(
      'a handle cancelled on hearing an answered failure gives no answer',
      () {
        final answers = Answers();
        final cancels = Hears(cancels: true);
        late Job<int> handle;
        final errors = zoneOf((async) {
          final source = Job<int>(
            key: 'load',
            observer: answers,
            (ctx) async => throw StateError('load'),
          );
          async.flushMicrotasks();
          handle = source.shared(observer: cancels);
        });
        expect(handle.outcome, isA<Cancelled>());
        expect(cancels.heard, ['Job(shared): Bad state: load']);
        expect(cancels.answered, isEmpty);
        expect(answers.answered, ['Job(load): Bad state: load']);
        expect(errors, isEmpty);
      },
    );
  });
}
