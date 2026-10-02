// `doc/extending.md` runs here. This file holds the engine as the page
// answers it: the job that refuses while it waits, its queue, the rule.
// The versions before the answers carry classes of the same names and live
// in libraries of their own — `support/extending_plain.dart` for the job as
// the page first shows it, `support/extending_first_attempts.dart` for the
// first attempts. Every piece of code on the page is a run of lines of one
// of these files, and every quote under it is what that code prints: a
// piece or a quote that drifts turns this file red.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async_job/engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/extending_first_attempts.dart' as first;
import 'support/extending_plain.dart' as plain;
import 'support/extending_stubs.dart';
import 'support/page_code.dart';

final class MyJob<T> extends JobBase<T> {
  final Future<T> Function(MyContext ctx) _body;

  MyQueue? _queue;

  MyJob(this._body, {super.key, super.observer, super.cancellable});

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<T> execute(covariant MyContext ctx) => _body(ctx);

  // `start` and `whenDone` are protected: the rest of the engine calls
  // them through these wrappers, private to its library.
  void _launch() => start();

  Future<void> get _whenDone => whenDone;

  @override
  void cancelWith(Cancelled cancelled, {bool rejectable = true}) {
    final waits = _queue?._waiting.contains(this) ?? false;
    if (waits && !cancellable && rejectable) return;
    _queue?._waiting.remove(this);
    super.cancelWith(cancelled, rejectable: rejectable);
  }
}

final class MyContext extends JobContextBase {
  MyContext(super.owner);

  // The wrapper the page's last paragraph on the rule speaks of.
  void _stop(Cancelled cancelled) => cancelOwnJob(cancelled);

  @override
  void check() {
    super.check();
    if (!account.signedIn) {
      throw Cancelled.by(
        reason: const SignedOutReason(),
        started: true,
        stackTrace: StackTrace.current,
      );
    }
  }
}

final class MyQueue {
  final _waiting = <MyJob<Object?>>[];

  void add(MyJob<Object?> job) => _waiting.add(job.._queue = this);

  Future<void> run() async {
    while (_waiting.isNotEmpty) {
      final job = _waiting.removeAt(0);
      if (job.isFinished) continue;
      job._launch();
      await job._whenDone;
    }
  }
}

Future<void> runQueue() async {
  final first = MyJob<void>(key: 'first', (ctx) => ctx.wait(upload));
  final second = MyJob<void>(
    key: 'second',
    cancellable: false,
    (_) async => print('second runs'),
  );
  final third = MyJob<void>(key: 'third', (_) async => print('third runs'));
  final queue = MyQueue()
    ..add(first)
    ..add(second)
    ..add(third);
  final running = queue.run();
  await second.cancel();
  await running;
  print('second: ${await second.done}');
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
  final bool failToStart;
  final hooks = <String>[];

  HookJob({this.failToStart = false});

  void launch() => start();

  @override
  void started() {
    hooks.add(status == JobStatus.running ? 'started' : 'started as $status');
    if (failToStart) {
      throw StateError('started failed');
    }
  }

  @override
  void finished() => hooks.add('finished');

  @override
  void cancelWith(Cancelled cancelled, {bool rejectable = true}) {
    hooks.add('cancelWith');
    super.cancelWith(cancelled, rejectable: rejectable);
  }

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<void> execute(covariant MyContext ctx) => ctx.wait(work);
}

/// A job of the engine created with `cancellable: false`.
final class StubbornJob<T> extends JobBase<T> {
  final Future<T> Function(MyContext ctx) _body;

  StubbornJob(this._body) : super(cancellable: false);

  void launch() => start();

  /// A cancellation no job may refuse.
  void stop(Cancelled cancelled) => cancelWith(cancelled, rejectable: false);

  /// Ends the job by hand.
  void end(Outcome<T> outcome) => finish(outcome);

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<T> execute(covariant MyContext ctx) => _body(ctx);
}

/// A job of the engine that keeps every cancellation asked of it.
final class CountingJob extends JobBase<int> {
  final Future<int> Function(MyContext ctx) _body;

  final cancelsAsked = <String>[];

  CountingJob(this._body);

  void _launch() => start();

  @override
  void cancelWith(Cancelled cancelled, {bool rejectable = true}) {
    cancelsAsked.add('$cancelled');
    super.cancelWith(cancelled, rejectable: rejectable);
  }

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<int> execute(covariant MyContext ctx) => _body(ctx);
}

/// The job of the page created with `cancellable: false`, with a wrapper
/// for a cancellation no job may refuse.
final class PatientJob<T> extends MyJob<T> {
  PatientJob(super.body, {super.key}) : super(cancellable: false);

  void _stop(Cancelled cancelled) => cancelWith(cancelled, rejectable: false);
}

Cancelled signedOut() => Cancelled.by(
      reason: const SignedOutReason(),
      started: true,
      stackTrace: StackTrace.current,
    );

/// The answer of an engine that takes the errors it knows and has nobody
/// to hand the rest to.
final class KnownOnly extends JobObserver with JobAnswerer {
  final answered = <String>[];

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    if (error is FormatException) {
      answered.add('$error');
    } else {
      super.onUnanswered(job, error, stackTrace);
    }
  }
}

/// The answer of an engine: it keeps what nobody else answered for.
final class Answer extends JobObserver with JobAnswerer {
  final answered = <String>[];

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      answered.add('$error');
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

/// The lines of [file] from the line [opening] to the first line [closing]
/// after it.
String _declaration(String file, String opening, String closing) {
  final lines = File(file).readAsLinesSync();
  final from = lines.indexOf(opening);
  if (from < 0) {
    throw StateError('$file has no "$opening"');
  }
  return lines.sublist(from, lines.indexOf(closing, from) + 1).join('\n');
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
        expect(job.hooks, ['cancelWith', 'finished']);
        expect(job.outcome, isA<Cancelled>());
      });
    });

    test('a started that throws is told, and the job runs to its end', () {
      late HookJob job;
      final errors = reachingTheZone(() {
        job = HookJob(failToStart: true)..launch();
      });
      expect(errors, ['Bad state: started failed']);
      expect(job.outcome, isA<Done<void>>());
      expect(job.hooks, ['started', 'finished']);
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

    test('a continuation answers to whoever called then', () {
      final answer = Answer();
      final caller = Answer();
      final engineZone = <String>[];
      final callerZone = <String>[];
      fakeAsync((async) {
        late MyJob<int> job;
        runZonedGuarded(
          () => job = MyJob<int>(observer: answer, (ctx) async => 1).._launch(),
          (error, stackTrace) => engineZone.add('$error'),
        );
        runZonedGuarded(
          () {
            job
                .then<void>((ctx, _) {
                  ctx.unattended(() => throw StateError('then'));
                })
                .done
                .ignore();
            job
                .then<void>(
                  (ctx, _) {
                    ctx.unattended(() => throw StateError('then with its own'));
                  },
                  observer: caller,
                )
                .done
                .ignore();
          },
          (error, stackTrace) => callerZone.add('$error'),
        );
        async.flushTimers();
      });
      expect(callerZone, ['Bad state: then']);
      expect(engineZone, isEmpty, reason: 'not the zone of the source');
      expect(caller.answered, ['Bad state: then with its own']);
      expect(answer.answered, isEmpty, reason: 'not the engine of the source');
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

    test('reportToZone hands the error to the zone the job was created in', () {
      final created = <String>[];
      final reported = <String>[];
      late ReportingJob job;
      runZonedGuarded(
        () => job = ReportingJob(),
        (error, stackTrace) => created.add('$error'),
      );
      runZonedGuarded(
        () => job.report(StateError('nobody answered')),
        (error, stackTrace) => reported.add('$error'),
      );
      expect(created, ['Bad state: nobody answered']);
      expect(reported, isEmpty);
    });

    test('super.onUnanswered sends on the error of a child of another kind',
        () {
      final answer = KnownOnly();
      final errors = reachingTheZone(() {
        MyJob<void>(observer: answer, (ctx) async {
          ctx
            ..unattended(() => throw const FormatException('known'))
            ..unattended(() => throw StateError('of MyJob'));
          await ctx.run(
            Job.deferred<void>((ctx) async {
              ctx.unattended(() => throw StateError('of a plain child'));
            }),
          );
        })
          .._launch()
          ..ignore();
      });
      expect(answer.answered, ['FormatException: known']);
      expect(errors, ['Bad state: of MyJob', 'Bad state: of a plain child']);
    });
  });

  group('A queue of your own', () {
    test('the first attempt cancels a waiting job that may not be cancelled',
        () {
      expect(printed(() => first.runQueue().ignore()), [
        'third runs',
        'second: Cancelled(manual)',
      ]);
    });

    test('a job that refuses while it waits runs when its turn comes', () {
      expect(printed(() => runQueue().ignore()), [
        'second runs',
        'third runs',
        'second: Done(null)',
      ]);
    });

    test('a job the user may cancel leaves the queue at once', () {
      fakeAsync((async) {
        final seen = <String>[];
        final second = MyJob<void>((_) async => seen.add('second runs'));
        final queue = MyQueue()
          ..add(MyJob<void>((ctx) => ctx.wait(upload)))
          ..add(second)
          ..add(MyJob<void>((_) async => seen.add('third runs')));
        var over = false;
        queue.run().then((_) => over = true).ignore();
        second.cancel().ignore();
        expect('${second.outcome}', 'Cancelled(manual)', reason: 'on the spot');
        expect(queue._waiting, hasLength(1), reason: 'the third is left');
        expect(queue._waiting, isNot(contains(second)));
        async.flushTimers();
        expect(seen, ['third runs']);
        expect(over, isTrue);
      });
    });

    test('the loop skips a job cancelled before it was added', () {
      fakeAsync((async) {
        final seen = <String>[];
        final early = MyJob<void>((_) async => seen.add('early runs'));
        early.cancel().ignore();
        final queue = MyQueue()
          ..add(early)
          ..add(MyJob<void>((_) async => seen.add('next runs')));
        Object? failure;
        var over = false;
        queue.run().then<void>(
              (_) => over = true,
              onError: (Object error) => failure = error,
            );
        async.flushTimers();
        expect(failure, isNull, reason: 'start() of a finished job throws');
        expect(seen, ['next runs']);
        expect(over, isTrue);
      });
    });

    test('the refusal is for a cancellation the job may refuse, no other', () {
      fakeAsync((async) {
        final seen = <String>[];
        final second =
            PatientJob<void>(key: 'second', (ctx) async => seen.add('runs'));
        final queue = MyQueue()
          ..add(MyJob<void>(key: 'first', (ctx) => ctx.wait(upload)))
          ..add(second)
          ..run().ignore();
        var back = false;
        second.cancel().then((_) => back = true).ignore();
        async.flushMicrotasks();
        expect(second.isFinished, isFalse);
        expect(second.isRunning, isFalse);
        expect(queue._waiting, [second], reason: 'still waits for its turn');
        expect(back, isFalse, reason: 'cancel() waits for the job to be over');
        async.flushTimers();
        expect(seen, ['runs']);
        expect(second.outcome, isA<Done<void>>());
        expect(back, isTrue);

        final stopped = PatientJob<void>(key: 'stopped', (ctx) async {});
        queue.add(stopped);
        stopped._stop(signedOut());
        expect(
          '${stopped.outcome}',
          'Cancelled(signed out)',
          reason: 'rejectable: false is not its to refuse',
        );
        expect(queue._waiting, isEmpty);
      });
    });

    test('a job in no queue is left to the core: a parent turns it away', () {
      fakeAsync((async) {
        final child = MyJob<void>(cancellable: false, (_) async {});
        Object? thrown;
        final parent = MyJob<void>((ctx) async {
          try {
            await ctx.wait(upload);
          } on Cancelled {
            // Goes on after its cancellation, and runs one more child.
          }
          try {
            await ctx.run(child);
          } on Cancelled catch (error) {
            thrown = error;
          }
        })
          .._launch();
        parent.cancel().ignore();
        async.flushTimers();
        expect('$thrown', 'Cancelled(manual)');
        expect(
          '${child.outcome}',
          'Cancelled(parent)',
          reason: 'refused, it would stay created, and its done would hang',
        );
      });
    });

    test('the answer keeps the run and the loop of the first attempt', () {
      for (final (opening, closing) in [
        ('Future<void> runQueue() async {', '}'),
        ('  Future<void> run() async {', '  }'),
      ]) {
        expect(
          _declaration('test/extending_rakes_test.dart', opening, closing),
          _declaration(
            'test/support/extending_first_attempts.dart',
            opening,
            closing,
          ),
          reason: 'the page shows them once and says "the same run"',
        );
      }
    });

    test('the cascade and cancelOwnJob arrive at cancelWith as well', () {
      fakeAsync((async) {
        late MyContext context;
        final child = CountingJob((ctx) async {
          context = ctx;
          await ctx.wait(work);
          return 1;
        });
        final parent = MyJob<void>((ctx) => ctx.run(child))
          .._launch()
          ..ignore();
        async.flushMicrotasks();
        parent.cancel().ignore();
        expect(child.cancelsAsked, ['Cancelled(parent)']);
        context._stop(signedOut());
        expect(
          child.cancelsAsked,
          ['Cancelled(parent)', 'Cancelled(signed out)'],
          reason: 'asked again, though the job has accepted the first',
        );
        async.flushTimers();
      });
    });

    test('mustCallSuper holds an override of cancelWith to super', () {
      expect(
        File('lib/src/job_base.dart').readAsStringSync(),
        contains('  @protected\n  @mustCallSuper\n  void cancelWith('),
        reason: 'the page says the analyzer holds the override to it',
      );
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

    test('the rule closes the connection', () {
      expect(printed(() => runDownload('cancel')), [
        'cancel',
        'close the connection',
        'outcome: Cancelled(manual)',
      ]);
      expect(printed(() => runDownload('sign out')), [
        'sign out',
        'close the connection',
        'outcome: Cancelled(signed out)',
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
          ['the step stopped: Cancelled(signed out)', 'told to stop'],
          reason: 'the step throws, and the body gives itself up after it',
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
        expect(seen, ['told to stop'], reason: 'given up, not refused');
        expect('${job.outcome}', 'Cancelled(signed out)');
      });
    });

    test('a body that catches the rule and goes on is not cancelled', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = CountingJob((ctx) async {
          ctx.onCancel(() => seen.add('told to stop'));
          account.signedIn = false;
          try {
            await ctx.join(work);
          } on Cancelled catch (error) {
            seen.add('caught $error');
          }
          return 1;
        })
          .._launch()
          ..ignore();
        async.flushTimers();
        expect(seen, ['caught Cancelled(signed out)']);
        expect(job.outcome, isA<Done<int>>());
        expect(job.isCancelled, isFalse);
      });
    });

    test('a body that gives itself up does not come through cancelWith', () {
      fakeAsync((async) {
        final job = CountingJob((ctx) async {
          account.signedIn = false;
          await ctx.join(work);
          return 1;
        })
          .._launch()
          ..ignore();
        async.flushTimers();
        expect('${job.outcome}', 'Cancelled(signed out)');
        expect(job.cancelsAsked, isEmpty);
      });
    });

    test('a sign-out during a wait is noticed only at the next call that asks',
        () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = MyJob<void>((ctx) async {
          await ctx.wait(download);
          seen.add('the wait came back');
          ctx.check();
          seen.add('the body went on');
        })
          .._launch()
          ..ignore();
        async.elapse(const Duration(milliseconds: 10));
        account.signedIn = false;
        async.flushTimers();
        expect(seen, ['the wait came back']);
        expect('${job.outcome}', 'Cancelled(signed out)');
      });
    });

    // The engine cancels the job itself: at once, whatever the body catches,
    // and neither `cancellable: false` nor a section holds it.
    for (final through in ['cancelWith', 'cancelOwnJob']) {
      test('the engine stops a running job itself, through $through', () {
        fakeAsync((async) {
          final seen = <String>[];
          late MyContext context;
          String at(String what) => '${async.elapsed.inMilliseconds} ms: $what';
          final job = StubbornJob<void>((ctx) async {
            context = ctx;
            ctx.onCancel(() => seen.add(at('told to stop')));
            try {
              await ctx.uncancellable(() => ctx.join(download));
            } on Cancelled catch (error) {
              seen.add(at('caught $error'));
            }
          })
            ..launch()
            ..ignore();
          async.elapse(const Duration(milliseconds: 10));
          // The user is still signed in for `check()`: the rule is not what
          // stops the job here.
          if (through == 'cancelWith') {
            job.stop(signedOut());
          } else {
            context._stop(signedOut());
          }
          async.flushTimers();
          expect(seen, [
            '10 ms: told to stop',
            '20 ms: caught Cancelled(signed out)',
          ]);
          expect('${job.outcome}', 'Cancelled(signed out)');
        });
      });
    }

    test('finish by hand stops no child and runs no onCancel', () {
      fakeAsync((async) {
        final seen = <String>[];
        final child = Job.deferred<void>((ctx) async {
          ctx.onCancel(() => seen.add('child told to stop'));
          await ctx.wait(work);
          seen.add('child ran to its end');
        });
        final job = StubbornJob<void>((ctx) async {
          ctx.onCancel(() => seen.add('told to stop'));
          await ctx.run(child);
        })
          ..launch()
          ..ignore();
        async.flushMicrotasks();
        job.end(signedOut());
        expect('${job.outcome}', 'Cancelled(signed out)');
        async.flushTimers();
        expect(seen, ['child ran to its end']);
        expect(child.outcome, isA<Done<void>>());
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
        runDownload('cancel');
      }),
      printed(() {
        account.signedIn = true;
        runDownload('sign out');
      }),
    ].map((lines) => lines.join('\n')).toList();
    final quotes = [
      for (final block in RegExp(r'```text\n(.*?)\n```', dotAll: true)
          .allMatches(File('doc/extending.md').readAsStringSync()))
        block.group(1)!,
    ];
    expect(quotes, prints, reason: 'each quote under the code that prints it');
  });

  test('the page has no fence the checks do not read', () {
    expect(strayFences('doc/extending.md'), isEmpty);
  });

  // Each version under its own file: a line of the answer turned into the
  // line of a first attempt would still be found among all of them.
  final holders = {
    '### The first attempt': 'test/support/extending_first_attempts.dart',
    '### Refusing while the job waits': 'test/extending_rakes_test.dart',
    "### A cancellation of the engine's own": 'test/extending_rakes_test.dart',
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
          'test/support/extending_stubs.dart',
        ],
      ),
      isEmpty,
    );
  });
}
