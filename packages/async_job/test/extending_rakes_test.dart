// `doc/extending.md` runs here. This file holds the engine as the page
// answers it: the job with its queue, the queue, the rule. The versions
// before the answers carry classes of the same names and live in
// libraries of their own — `support/extending_plain.dart` for the job as
// the page first shows it, `support/extending_first_attempts.dart` and
// `support/extending_second_attempt.dart` for the attempts. Every piece of
// code on the page is a run of lines of one of these files, and every
// quote under it is what that code prints: a piece or a quote that drifts
// turns this file red.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async_job/engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/extending_first_attempts.dart' as first;
import 'support/extending_plain.dart' as plain;
import 'support/extending_second_attempt.dart' as second;
import 'support/extending_stubs.dart';
import 'support/page_code.dart';

final class MyJob<T> extends JobBase<T> {
  MyJob(this._body, {super.key, super.observer});

  final Future<T> Function(MyContext ctx) _body;

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<T> execute(covariant MyContext ctx) => _body(ctx);

  // `start` and `whenDone` are protected: the engine opens doors of its
  // own to them, private to the library it lives in.
  void _launch() => start();

  Future<void> get _whenDone => whenDone;

  MyQueue? _queue;

  @override
  void cancelWith(Cancelled cancelled, {bool rejectable = true}) {
    _queue?._waiting.remove(this);
    super.cancelWith(cancelled, rejectable: rejectable);
  }
}

final class MyContext extends JobContextBase {
  MyContext(super.owner);

  @override
  void check() {
    super.check();
    if (!account.signedIn) {
      final cancelled = Cancelled.by(
        reason: const SignedOutReason(),
        started: true,
        stackTrace: StackTrace.current,
      );
      cancelOwnJob(cancelled);
      throw pendingCancel ?? cancelled;
    }
  }
}

final class MyQueue {
  final _waiting = <MyJob<Object?>>[];

  void add(MyJob<Object?> job) => _waiting.add(job.._queue = this);

  Future<void> run() async {
    while (_waiting.isNotEmpty) {
      final job = _waiting.removeAt(0).._launch();
      await job._whenDone;
    }
  }
}

Future<void> runQueue() async {
  final second = MyJob<void>(key: 'second', (ctx) => ctx.wait(upload));
  final queue = MyQueue()
    ..add(MyJob<void>(key: 'first', (ctx) => ctx.wait(upload)))
    ..add(second);
  final running = queue.run();
  await second.cancel();
  print('second: ${await second.done}');
  try {
    await running;
    print('the queue is empty');
    // ignore: avoid_catching_errors
  } on StateError catch (error) {
    print('the queue stopped: $error');
  }
}

void runDownload(String act) {
  final job = MyJob<void>(observer: printer, (ctx) async {
    ctx.onCancel(() => print('close the connection'));
    final rows = await ctx.join(download);
    print('downloaded $rows rows');
    await ctx.join(() => save(rows));
    print('saved');
  })
    .._launch();
  userDoes(act, job);
}

/// A job with a child, signed out of while both run; returns the child.
Job<void> signOutWithChild(List<String> seen) {
  final child = Job.deferred<void>((ctx) async {
    ctx.onCancel(() => seen.add('child told to stop'));
    await ctx
        .wait(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  });
  final job = MyJob<void>((ctx) async {
    ctx.onCancel(() => seen.add('parent told to stop'));
    ctx.run(child).ignore();
    await ctx.join(download);
  })
    .._launch();
  job.done.then((outcome) => seen.add('outcome: $outcome')).ignore();
  return child;
}

/// A job of the engine that records its lifecycle hooks, and may fail to
/// join the run.
final class HookJob extends JobBase<void> {
  HookJob({this.failToStart = false});

  final bool failToStart;
  final hooks = <String>[];

  void launch() => start();

  @override
  void started() {
    hooks.add('started');
    if (failToStart) {
      throw StateError('started failed');
    }
  }

  @override
  void finished() => hooks.add('finished');

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<void> execute(covariant MyContext ctx) => ctx.wait(work);
}

/// A job of the engine created with `cancellable: false`.
final class StubbornJob<T> extends JobBase<T> {
  StubbornJob(this._body) : super(cancellable: false);

  final Future<T> Function(MyContext ctx) _body;

  void launch() => start();

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<T> execute(covariant MyContext ctx) => _body(ctx);
}

/// The answer of an engine: it keeps what nobody else answered for.
final class Answer extends JobObserver {
  final answered = <String>[];

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      answered.add('$error');
}

/// A job of an engine that passes its answer to its continuations.
final class AnsweredJob<T> extends JobBase<T> {
  AnsweredJob(this._answer, this._body) : super(observer: _answer);

  final JobObserver _answer;
  final Future<T> Function(JobContext ctx) _body;

  void launch() => start();

  @override
  Job<R> then<R>(
    FutureOr<R> Function(JobContext ctx, T value) onValue, {
    JobObserver? observer,
  }) =>
      super.then(onValue, observer: observer ?? _answer);

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<T> execute(covariant MyContext ctx) => _body(ctx);
}

/// A job of the engine that hands an error to the zone by hand.
final class ReportingJob extends JobBase<void> {
  ReportingJob();

  void report(Object error) => reportToZone(error, StackTrace.current);

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<void> execute(covariant MyContext ctx) async {}
}

/// The rule of the page asked before `super.check()`, not after it.
final class LateSuperContext extends JobContextBase {
  LateSuperContext(super.owner);

  @override
  void check() {
    if (!account.signedIn) {
      final cancelled = Cancelled.by(
        reason: const SignedOutReason(),
        started: true,
        stackTrace: StackTrace.current,
      );
      cancelOwnJob(cancelled);
      throw pendingCancel ?? cancelled;
    }
    super.check();
  }
}

/// A job whose context is [MyContext], or [LateSuperContext] if [late].
final class CleaningJob extends JobBase<int> {
  CleaningJob({required this.late});

  final bool late;
  final seen = <String>[];

  void launch() => start();

  @override
  JobContextBase createContext() =>
      late ? LateSuperContext(this) : MyContext(this);

  // The disposer asks the checkpoint after the user signed out, while the
  // engine cleans up after a body that returned a value.
  @override
  Future<int> execute(covariant JobContextBase ctx) async {
    ctx.onDispose(() {
      account.signedIn = false;
      try {
        ctx.check();
      } on Object catch (error) {
        seen.add('$error');
      }
    });
    return 42;
  }
}

/// What [scenario] prints while fake time runs it to its end.
List<String> printed(void Function() scenario) {
  final lines = <String>[];
  runZoned(
    () => fakeAsync((async) {
      scenario();
      async.flushTimers();
    }),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

/// The errors that reach the zone while fake time runs [scenario].
List<String> reachingTheZone(void Function() scenario) {
  final errors = <String>[];
  runZonedGuarded(
    () => fakeAsync((async) {
      scenario();
      async.flushTimers();
    }),
    (error, stackTrace) => errors.add('$error'),
  );
  return errors;
}

void main() {
  setUp(() => account.signedIn = true);

  group('A job of your own', () {
    test('finished runs for a job dropped before its body, started not', () {
      fakeAsync((async) {
        final job = HookJob();
        job.cancel().ignore();
        async.flushTimers();
        expect(job.hooks, ['finished']);
        expect(job.outcome, isA<Cancelled>());
      });
    });

    test('a started that throws leaves a running job nothing finishes', () {
      fakeAsync((async) {
        final job = HookJob(failToStart: true);
        expect(job.launch, throwsA(isA<StateError>()));
        var finished = false;
        job.done.then((_) => finished = true).ignore();
        async.flushTimers();
        expect(job.isRunning, isTrue);
        expect(finished, isFalse, reason: 'nothing will ever finish it');
        expect(job.hooks, ['started']);
      });
    });

    test('whenDone waits without looking: a failure reaches the zone', () {
      var waited = false;
      final errors = reachingTheZone(() {
        plain
            .launchAndWait(
              plain.MyJob<void>((ctx) async => throw StateError('lost')),
            )
            .then((_) => waited = true)
            .ignore();
      });
      expect(waited, isTrue);
      expect(errors, ['Bad state: lost']);
    });

    test("an adopted child takes the engine's observer, its own keeps its own",
        () {
      final answer = Answer();
      final own = Answer();
      final errors = reachingTheZone(() {
        MyJob<void>(observer: answer, (ctx) async {
          await ctx.run(
            Job.deferred<void>((ctx) async {
              ctx.unattended(() => throw StateError('plain child'));
            }),
          );
          await ctx.run(
            Job.deferred<void>(observer: own, (ctx) async {
              ctx.unattended(() => throw StateError('own child'));
            }),
          );
        })
          .._launch()
          ..ignore();
      });
      expect(answer.answered, ['Bad state: plain child']);
      expect(own.answered, ['Bad state: own child']);
      expect(errors, isEmpty);
    });

    test('then gets only the observer passed to it, unless then is overridden',
        () {
      final answer = Answer();
      final errors = reachingTheZone(() {
        final job = MyJob<int>(observer: answer, (ctx) async => 1).._launch();
        job
            .then<void>((ctx, _) {
              ctx.unattended(() => throw StateError('then'));
            })
            .done
            .ignore();
        final answered = AnsweredJob<int>(answer, (ctx) async => 1)..launch();
        answered
            .then<void>((ctx, _) {
              ctx.unattended(() => throw StateError('then overridden'));
            })
            .done
            .ignore();
      });
      expect(errors, ['Bad state: then']);
      expect(answer.answered, ['Bad state: then overridden']);
    });

    test('reportToZone keeps a cancellation out of the zone', () {
      final errors = reachingTheZone(() {
        ReportingJob()
          ..report(
            Cancelled.by(
              reason: const ManualCancelReason(),
              started: true,
              stackTrace: StackTrace.current,
            ),
          )
          ..report(StateError('nobody answered'));
      });
      expect(errors, ['Bad state: nobody answered']);
    });
  });

  group('A queue of your own', () {
    test('the first attempt stops at the job cancelled while it waited', () {
      expect(printed(() => first.runQueue().ignore()), [
        'second: Cancelled(manual)',
        'the queue stopped: Bad state: Job(second) has already finished',
      ]);
    });

    test('and every job behind it waits for good', () {
      fakeAsync((async) {
        final third = first.queueOfThree();
        async.flushTimers();
        expect(third.isRunning, isFalse);
        expect(third.isFinished, isFalse);
      });
    });

    test('a job that leaves the queue on cancellation lets the rest run', () {
      expect(printed(() => runQueue().ignore()), [
        'second: Cancelled(manual)',
        'the queue is empty',
      ]);
    });

    test('the core finishes a job that has not started, cancellable or not',
        () {
      fakeAsync((async) {
        final waiting = StubbornJob<void>((ctx) async {});
        waiting.cancel().ignore();
        async.flushTimers();
        expect(waiting.outcome, isA<Cancelled>());

        final running = StubbornJob<void>((ctx) => ctx.wait(work))..launch();
        async.flushMicrotasks();
        running.cancel().ignore();
        async.flushTimers();
        expect(running.outcome, isA<Done<void>>(), reason: 'once it runs');
      });
    });
  });

  group('A rule of your own', () {
    test('the first attempt lets a cancelled job save the rows', () {
      expect(printed(() => first.runDownload('cancel')), [
        'cancel',
        'close the connection',
        'downloaded 42 rows',
        'saved',
        'outcome: Cancelled(manual)',
      ]);
    });

    test('the first attempt fails the job when the user signs out', () {
      expect(printed(() => first.runDownload('sign out')), [
        'sign out',
        'onError: SignedOut',
        'outcome: Failed(SignedOut)',
      ]);
    });

    test('under the first attempt a child runs on to its end', () {
      final seen = <String>[];
      fakeAsync((async) {
        final child = first.signOutWithChild(seen);
        async.elapse(const Duration(milliseconds: 10));
        account.signedIn = false;
        async.flushTimers();
        expect(child.outcome, isA<Done<void>>());
      });
      expect(seen, ['outcome: Failed(SignedOut)']);
    });

    test('the second attempt ends the job Cancelled and closes nothing', () {
      expect(printed(() => second.runDownload('sign out')), [
        'sign out',
        'outcome: Cancelled(signed out)',
      ]);
      account.signedIn = true;
      expect(printed(() => second.runDownload('cancel')), [
        'cancel',
        'close the connection',
        'outcome: Cancelled(manual)',
      ]);
    });

    test('under the second attempt the children stop, onCancel does not run',
        () {
      final seen = <String>[];
      fakeAsync((async) {
        final child = second.signOutWithChild(seen);
        async.elapse(const Duration(milliseconds: 10));
        account.signedIn = false;
        async.flushTimers();
        expect(
          (child.outcome! as Cancelled).reason,
          isA<ParentCancelReason>(),
        );
      });
      expect(seen, ['child told to stop', 'outcome: Cancelled(signed out)']);
    });

    test('the rule that cancels the job closes the connection', () {
      expect(printed(() => runDownload('sign out')), [
        'sign out',
        'close the connection',
        'outcome: Cancelled(signed out)',
      ]);
      account.signedIn = true;
      expect(printed(() => runDownload('cancel')), [
        'cancel',
        'close the connection',
        'outcome: Cancelled(manual)',
      ]);
    });

    test('and stops the children the way cancel() does', () {
      final seen = <String>[];
      fakeAsync((async) {
        final child = signOutWithChild(seen);
        async.elapse(const Duration(milliseconds: 10));
        account.signedIn = false;
        async.flushTimers();
        expect(
          (child.outcome! as Cancelled).reason,
          isA<ParentCancelReason>(),
        );
      });
      expect(seen, [
        'child told to stop',
        'parent told to stop',
        'outcome: Cancelled(signed out)',
      ]);
    });

    test('run asks the rule once the value of the child has arrived', () {
      fakeAsync((async) {
        Object? thrown;
        final job = MyJob<void>((ctx) async {
          try {
            await ctx.run(
              Job.deferred<int>((child) async {
                await child.wait(work);
                account.signedIn = false;
                return 1;
              }),
            );
          } on Cancelled catch (error) {
            thrown = error;
            rethrow;
          }
        })
          .._launch()
          ..ignore();
        async.flushTimers();
        expect('$thrown', 'Cancelled(signed out)');
        expect('${job.outcome}', 'Cancelled(signed out)');
      });
    });

    test('runAll asks the rule before it hands the values back', () {
      fakeAsync((async) {
        Object? thrown;
        final job = MyJob<void>((ctx) async {
          try {
            await ctx.runAll([
              Job.deferred<int>((child) async {
                await child.wait(work);
                account.signedIn = false;
                return 1;
              }),
            ]);
          } on Cancelled catch (error) {
            thrown = error;
            rethrow;
          }
        })
          .._launch()
          ..ignore();
        async.flushTimers();
        expect('$thrown', 'Cancelled(signed out)');
        expect('${job.outcome}', 'Cancelled(signed out)');
      });
    });

    test('an uncancellable section does not hold the rule back', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = MyJob<void>((ctx) async {
          ctx.onCancel(() => seen.add('told to stop'));
          await ctx.uncancellable(() async {
            account.signedIn = false;
            try {
              await ctx.join(work);
              seen.add('the step went on');
            } on Cancelled catch (error) {
              seen.add('the step stopped: $error');
              rethrow;
            }
          });
        })
          .._launch()
          ..ignore();
        async.flushTimers();
        expect(
          seen,
          ['told to stop', 'the step stopped: Cancelled(signed out)'],
          reason: 'the job is marked inside the section, not given up on',
        );
        expect('${job.outcome}', 'Cancelled(signed out)');
      });
    });

    test('nor does cancellable: false', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = StubbornJob<void>((ctx) async {
          ctx.onCancel(() => seen.add('told to stop'));
          await ctx.wait(work);
          account.signedIn = false;
          await ctx.join(work);
        })
          ..launch()
          ..ignore();
        async.flushTimers();
        expect(seen, ['told to stop'], reason: 'marked, not refused');
        expect('${job.outcome}', 'Cancelled(signed out)');
      });
    });

    test('super.check() goes first: during cleanup it throws a StateError', () {
      fakeAsync((async) {
        final first = CleaningJob(late: false)..launch();
        async.flushTimers();
        expect(first.seen.single, startsWith('Bad state:'));
        expect(first.outcome, isA<Done<int>>());

        account.signedIn = true;
        final late = CleaningJob(late: true)..launch();
        async.flushTimers();
        expect(late.seen, ['Cancelled(signed out)']);
        expect(
          '${late.outcome}',
          'Cancelled(signed out)',
          reason: 'a job that returned a value, turned into a cancelled one',
        );
      });
    });

    test(
        'under the first attempt uncancellable begins its step, wait and run '
        'still throw', () {
      final seen = <String>[];
      fakeAsync((async) {
        first.cancelledMidway(seen);
        async.flushTimers();
      });
      expect(seen, [
        'the step began',
        'uncancellable: 2',
        'wait: Cancelled(manual)',
        'run: Cancelled(manual)',
      ]);
    });

    test('mustCallSuper holds an override of check() to super', () {
      expect(
        File('lib/src/job_context.dart').readAsStringSync(),
        contains('  @override\n  @mustCallSuper\n  void check() {'),
        reason: 'the first attempt of the page is what the analyzer points '
            'at, and nothing else here would notice the annotation gone',
      );
    });

    test('after the job has ended, the rule throws a cancellation of its own',
        () {
      fakeAsync((async) {
        late JobContext kept;
        final job = MyJob<void>((ctx) async => kept = ctx).._launch();
        async.flushTimers();
        account.signedIn = false;
        expect(kept.check, throwsA(isA<Cancelled>()));
        expect(job.outcome, isA<Done<void>>());

        account.signedIn = true;
        late JobContext keptFailed;
        final failed = MyJob<void>((ctx) async {
          keptFailed = ctx;
          throw StateError('failed');
        })
          .._launch()
          ..ignore();
        async.flushTimers();
        account.signedIn = false;
        expect(
          keptFailed.check,
          throwsA(
            isA<Cancelled>()
                .having((c) => '$c', 'text', 'Cancelled(signed out)'),
          ),
        );
        expect(failed.outcome, isA<Failed>());
      });
    });
  });

  test('Deferred start', () {
    fakeAsync((async) {
      final job = Job.deferred<void>((ctx) => ctx.wait(work));
      // ... later, or from a queue of your own
      // ignore: cascade_invocations
      job.start();
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('every quote on the page is what its code prints', () {
    final prints = [
      printed(() => first.runQueue().ignore()),
      printed(() => runQueue().ignore()),
      printed(() => first.runDownload('cancel')),
      printed(() => first.runDownload('sign out')),
      printed(() {
        account.signedIn = true;
        second.runDownload('sign out');
      }),
      printed(() {
        account.signedIn = true;
        runDownload('sign out');
      }),
      printed(() {
        account.signedIn = true;
        runDownload('cancel');
      }),
    ].map((lines) => lines.join('\n')).toList();
    final quotes = [
      for (final block in RegExp(r'```text\n(.*?)\n```', dotAll: true)
          .allMatches(File('doc/extending.md').readAsStringSync()))
        block.group(1)!,
    ];
    expect(quotes, prints, reason: 'each quote under the code that prints it');
  });

  // Each version under its own file: a line of the answer turned into the
  // line of a first attempt would still be found among all of them.
  final holders = {
    '### The first attempt': 'test/support/extending_first_attempts.dart',
    '### The second attempt': 'test/support/extending_second_attempt.dart',
    '### Leaving the queue on cancellation': 'test/extending_rakes_test.dart',
    '### Cancelling the job from the rule': 'test/extending_rakes_test.dart',
  };
  for (final MapEntry(key: heading, value: holder) in holders.entries) {
    test('the code under "$heading" is a run of lines of $holder', () {
      final pieces = codeMissingFrom(
        'doc/extending.md',
        holder,
        alsoIn: ['test/support/extending_stubs.dart'],
        under: heading,
      );
      expect(pieces, isEmpty);
    });
  }

  test('every piece of code on the page is a run of lines of these files', () {
    expect(
      codeMissingFrom(
        'doc/extending.md',
        'test/extending_rakes_test.dart',
        alsoIn: [
          'test/support/extending_plain.dart',
          'test/support/extending_first_attempts.dart',
          'test/support/extending_second_attempt.dart',
          'test/support/extending_stubs.dart',
        ],
      ),
      isEmpty,
    );
  });
}
