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
import 'support/reachability.dart';

final class MyJob<T> extends JobBase<T> implements ChildJob<T> {
  // Dropped once the job is over, as the core drops its own: the body
  // holds everything it captured, and a job is held to read its outcome
  // long after.
  Future<T> Function(MyContext ctx)? _body;

  MyQueue? _queue;

  MyJob(
    Future<T> Function(MyContext ctx) body, {
    super.key,
    super.observer,
    super.cancellable,
  }) : _body = body;

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<T> execute(covariant MyContext ctx) => _body!(ctx);

  @override
  void finished() {
    _body = null;
    _queue = null;
  }

  // `start` and `untilFinished` are protected: the rest of the engine calls
  // them through these wrappers, private to its library. The queue starts
  // a job later, from a zone of its own, so `_launch` starts it in the zone
  // it was created in.
  void _launch() => creationZone.run(start);

  Future<void> get _untilFinished => untilFinished;

  void _stop(Cancelled cancelled) => cancelWith(cancelled, rejectable: false);

  @override
  void cancelWith(Cancelled cancelled, {bool rejectable = true}) {
    final waits = _queue?._waiting.contains(this) ?? false;
    if (waits && !cancellable && rejectable) return;
    _queue?._waiting.remove(this);
    super.cancelWith(cancelled, rejectable: rejectable);
  }

  @override
  void adoptedBy(JobContextBase parent) {
    if (_queue?._waiting.contains(this) ?? false) {
      throw StateError('$this waits in its queue');
    }
  }
}

/// The three copies of the page's job: as it is first shown, in the first
/// attempt at a queue, and with the queue of the answer.
enum _Copy { firstShown, firstQueue, withQueue }

/// A job of the page, in [copy], whose body captures a payload; the job,
/// the wait for its end and the payload, weakly. Made in a frame of its
/// own: a closure captures the variable, not the value, so a payload left
/// in the test would be held by the test.
(Object, Future<void>, WeakReference<Object>) _capturing(_Copy copy) {
  final payload = List<int>.filled(1024, 7);
  switch (copy) {
    case _Copy.firstShown:
      final job = plain.MyJob<int>((ctx) async => payload.length);
      return (job, plain.launchAndWait(job), WeakReference(payload));
    case _Copy.firstQueue:
      final job = first.MyJob<int>((ctx) async => payload.length);
      final queue = first.MyQueue()..add(job);
      return (job, queue.run(), WeakReference(payload));
    case _Copy.withQueue:
      final job = MyJob<int>((ctx) async => payload.length).._launch();
      return (job, job._untilFinished, WeakReference(payload));
  }
}

/// A job that ran in a queue, and a payload held by a job added to that
/// queue after it, which nobody runs. A frame of its own, as for
/// [_capturing]. The payload, weakly.
(MyJob<void>, Future<void>, WeakReference<Object>) _ranThenQueued() {
  final payload = List<int>.filled(1024, 7);
  final ran = MyJob<void>((ctx) async {});
  final queue = MyQueue()..add(ran);
  final over = queue.run().then((_) {
    queue.add(MyJob<int>((ctx) async => payload.length));
  });
  return (ran, over, WeakReference(payload));
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
        stackTrace: StackTrace.current,
      );
    }
  }
}

final class MyQueue {
  final _waiting = <MyJob<Object?>>[];
  Future<void>? _running;

  void add(MyJob<Object?> job) {
    if (job._queue != null) throw StateError('$job is in a queue already');
    if (job.isRunning) throw StateError('$job runs already');
    _waiting.add(job);
    if (!job.isFinished) job._queue = this;
  }

  // One loop at a time: a second call gets the future of the loop that
  // runs. Started in a microtask, the loop clears `_running` after it is
  // set, even when there is nothing to run.
  Future<void> run() => _running ??= Future.microtask(_loop);

  Future<void> _loop() async {
    try {
      while (_waiting.isNotEmpty) {
        final job = _waiting.removeAt(0);
        if (job.isFinished) continue;
        job._launch();
        await job._untilFinished;
      }
    } finally {
      _running = null;
    }
  }
}

Future<void> runQueue() async {
  final first = MyJob<void>(key: 'first', (ctx) => ctx.abandonable(upload));
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

Future<void> runWholeEngine() async {
  final queue = MyQueue();
  for (final name in ['photo', 'video']) {
    final job = MyJob<void>((ctx) async {
      print('$name starts');
      await ctx.abandonable(upload);
      print('$name ends');
    });
    queue.add(job);
  }
  await Future.wait([queue.run(), queue.run()]);
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

/// The download with `abandonable` in place of the first `join`, signed out of
/// while it runs; with [engineStops] the engine cancels the job itself.
void runAbandonableDownload({required bool engineStops}) {
  final job = MyJob<void>(observer: printer, (ctx) async {
    ctx.onCancel(() => print('close the connection'));
    final rows = await ctx.abandonable(download);
    print('downloaded $rows rows');
    await ctx.join(() => save(rows));
    print('saved');
  })
    .._launch();
  if (engineStops) {
    account.onSignOut = () => job._stop(
          Cancelled.by(
            reason: const SignedOutReason(),
            stackTrace: StackTrace.current,
          ),
        );
  }
  userDoes('sign out', job);
}

/// A job with a child, signed out of while both run; returns the child.
Job<void> signOutWithChild(List<String> seen) {
  final child = Job.deferred<void>((ctx) async {
    ctx.onCancel(() => seen.add('child told to stop'));
    await ctx.abandonable(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
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
final class HookJob extends JobBase<void> implements ChildJob<void> {
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
  Future<void> execute(covariant MyContext ctx) => ctx.abandonable(work);
}

/// A job of the engine created with `cancellable: false`.
final class StubbornJob<T> extends JobBase<T> implements ChildJob<T> {
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
final class CountingJob extends JobBase<int> implements ChildJob<int> {
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

/// The job of the page created with `cancellable: false`.
final class PatientJob<T> extends MyJob<T> {
  PatientJob(super.body, {super.key}) : super(cancellable: false);
}

Cancelled signedOut() => Cancelled.by(
      reason: const SignedOutReason(),
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
final class ReportingJob extends JobBase<void> implements ChildJob<void> {
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
  setUp(() {
    account
      ..signedIn = true
      ..onSignOut = null;
  });

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

    test('untilFinished waits without looking: a failure reaches the zone', () {
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
          ..ignoreFailure();
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
                .shared()
                .then<void>((ctx, _) {
                  ctx.unattended(() => throw StateError('then'));
                })
                .done
                .ignore();
            job
                .shared()
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
          ..ignoreFailure();
      });
      expect(answer.answered, ['FormatException: known']);
      expect(errors, ['Bad state: of MyJob', 'Bad state: of a plain child']);
    });

    test('the queue starts a job in the zone it was created in', () {
      fakeAsync((async) {
        final seen = <Object?>[];
        late MyJob<void> job;
        runZoned(
          () => job = MyJob<void>((_) async => seen.add(Zone.current[#who])),
          zoneValues: {#who: 'screen'},
        );
        final queue = MyQueue()..add(job);
        runZoned(() => queue.run().ignore(), zoneValues: {#who: 'app'});
        async.flushTimers();
        expect(seen, ['screen'], reason: 'not the zone the queue runs in');
      });
    });

    test('a failing future of the zone a job was created in reaches its body',
        () {
      fakeAsync((async) {
        final screen = <String>[];
        final app = <String>[];
        late Completer<void> connected;
        late MyJob<void> job;
        runZonedGuarded(
          () {
            connected = Completer<void>();
            job = MyJob<void>((_) async {
              await connected.future;
            })
              ..ignoreFailure();
          },
          (error, stackTrace) => screen.add('$error'),
        );
        final next = MyJob<void>((_) async {});
        final queue = MyQueue()
          ..add(job)
          ..add(next);
        var over = false;
        runZonedGuarded(
          () => queue.run().then((_) => over = true).ignore(),
          (error, stackTrace) => app.add('$error'),
        );
        async.flushMicrotasks();
        expect(job.isRunning, isTrue);
        connected.completeError(StateError('connection lost'));
        async.flushTimers();
        expect(
          '${job.outcome}',
          'Failed(Bad state: connection lost)',
          reason: "started under the queue's runZonedGuarded, the body would "
              'never hear of the failure and would wait for good',
        );
        expect(screen, isEmpty, reason: "the failure is the body's");
        expect(app, isEmpty);
        expect(next.outcome, isA<Done<void>>(), reason: 'the queue goes on');
        expect(over, isTrue);
      });
    });

    test('every MyJob of the bench launches the way the page shows', () {
      const opening = '  // `start` and `untilFinished` are protected: '
          'the rest of the engine calls';
      for (final file in [
        'test/support/extending_plain.dart',
        'test/support/extending_first_attempts.dart',
      ]) {
        expect(
          _declaration(file, opening, ''),
          _declaration('test/extending_rakes_test.dart', opening, ''),
          reason: 'the page shows the wrappers once, and a piece of the page '
              'is found in any one of the files',
        );
      }
    });

    for (final (version, copy) in [
      ('as first shown', _Copy.firstShown),
      ('in the first attempt at a queue', _Copy.firstQueue),
      ('with its queue', _Copy.withQueue),
    ]) {
      test('a finished MyJob lets go of its body, $version', () async {
        final (job, over, capture) = _capturing(copy);
        await over;
        expect(
          await collected(capture),
          isTrue,
          reason: 'the body ran once; held on, it keeps everything it '
              'captured for as long as anyone keeps the job',
        );
        expect(job, isNotNull, reason: 'the job is kept to the end');
      });
    }
  });

  group('A queue of your own', () {
    test('a finished job lets go of the queue it ran in', () async {
      final (job, over, payload) = _ranThenQueued();
      await over;
      expect(
        await collected(payload),
        isTrue,
        reason: 'held for its outcome, the job would hold the queue and the '
            'job left waiting in it',
      );
      expect(job.outcome, isA<Done<void>>());
    });

    test('a job in a queue is refused by another, and by its own', () async {
      final job = MyJob<void>((ctx) async {});
      final queue = MyQueue()..add(job);
      expect(() => MyQueue().add(job), throwsStateError);
      expect(() => queue.add(job), throwsStateError);
      await queue.run();
      expect(job.outcome, isA<Done<void>>());
    });

    test('a job a parent has started is refused by the queue', () async {
      final gate = Completer<void>();
      final job = MyJob<void>((ctx) async {
        await gate.future;
      });
      final parent = Job<void>((ctx) => ctx.run(job));
      await Future<void>.delayed(Duration.zero);
      expect(job.isRunning, isTrue);
      expect(() => MyQueue().add(job), throwsStateError);
      gate.complete();
      await parent.done;
      expect(job.outcome, isA<Done<void>>());
    });

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
          ..add(MyJob<void>((ctx) => ctx.abandonable(upload)))
          ..add(second)
          ..add(MyJob<void>((_) async => seen.add('third runs')));
        var over = false;
        queue.run().then((_) => over = true).ignore();
        async.flushMicrotasks();
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
          ..add(MyJob<void>(key: 'first', (ctx) => ctx.abandonable(upload)))
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
            await ctx.abandonable(upload);
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

    test('a second run waits for the loop that runs: one job at a time', () {
      fakeAsync((async) {
        final seen = <String>[];
        MyJob<void> job(String name) => MyJob<void>((ctx) async {
              seen.add('$name starts');
              await ctx.abandonable(upload);
              seen.add('$name ends');
            });
        final queue = MyQueue()
          ..add(job('first'))
          ..add(job('second'));
        final running = queue.run();
        expect(identical(queue.run(), running), isTrue);
        async.flushTimers();
        expect(seen, [
          'first starts',
          'first ends',
          'second starts',
          'second ends',
        ]);
      });
    });

    test('a run that found nothing leaves the next run its own loop', () {
      fakeAsync((async) {
        final seen = <String>[];
        final queue = MyQueue()..run().ignore();
        async.flushMicrotasks();
        queue
          ..add(MyJob<void>((_) async => seen.add('runs')))
          ..run().ignore();
        async.flushTimers();
        expect(seen, ['runs']);
      });
    });

    test('ctx.run turns away a job that waits in the queue', () {
      fakeAsync((async) {
        final seen = <String>[];
        final queued =
            MyJob<void>(key: 'queued', (_) async => seen.add('runs'));
        final queue = MyQueue()
          ..add(
            MyJob<void>((ctx) async {
              try {
                await ctx.run(queued);
              } on Object catch (error) {
                seen.add('$error');
              }
            }),
          )
          ..add(queued)
          ..add(MyJob<void>((_) async => seen.add('third runs')));
        queue.run().ignore();
        async.flushTimers();
        expect(seen, [
          'Bad state: Job(queued) waits in its queue',
          'runs',
          'third runs',
        ]);
      });
    });

    test('the answer keeps the run and the loop of the first attempt', () {
      expect(
        _declaration(
          'test/extending_rakes_test.dart',
          'Future<void> runQueue() async {',
          '}',
        ),
        _declaration(
          'test/support/extending_first_attempts.dart',
          'Future<void> runQueue() async {',
          '}',
        ),
        reason: 'the page shows it once and says "the same run"',
      );
      // The answer moves the loop into a `try`, one level deeper.
      String loop(String file, String indent) => [
            for (final line in _declaration(
              file,
              '$indent  while (_waiting.isNotEmpty) {',
              '$indent  }',
            ).split('\n'))
              line.trim(),
          ].join('\n');
      expect(
        loop('test/extending_rakes_test.dart', '    '),
        loop('test/support/extending_first_attempts.dart', '  '),
      );
    });

    test('the cascade and cancelOwnJob arrive at cancelWith as well', () {
      fakeAsync((async) {
        late MyContext context;
        final child = CountingJob((ctx) async {
          context = ctx;
          await ctx.abandonable(work);
          return 1;
        });
        final parent = MyJob<void>((ctx) => ctx.run(child))
          .._launch()
          ..ignoreFailure();
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

        final running = StubbornJob<void>((ctx) => ctx.abandonable(work))
          ..launch();
        async.flushMicrotasks();
        running.cancel().ignore();
        async.flushTimers();
        expect(running.outcome, isA<Done<void>>(), reason: 'once it runs');
      });
    });
  });

  group('A rule of your own', () {
    test('a cancelled job closes the connection and ends Cancelled', () {
      expect(printed(() => first.runDownload('cancel')), [
        'cancel',
        'close the connection',
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
                await child.abandonable(work);
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
          ..ignoreFailure();
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
                await child.abandonable(work);
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
          ..ignoreFailure();
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
          ..ignoreFailure();
        async.flushTimers();
        expect(
          seen,
          ['the step stopped: Cancelled(signed out)', 'told to stop'],
          reason: 'the step throws, and the body cancels itself after it',
        );
        expect('${job.outcome}', 'Cancelled(signed out)');
      });
    });

    test('nor does cancellable: false', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = StubbornJob<void>((ctx) async {
          ctx.onCancel(() => seen.add('told to stop'));
          await ctx.abandonable(work);
          account.signedIn = false;
          await ctx.join(work);
        })
          ..launch()
          ..ignoreFailure();
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
          ..ignoreFailure();
        async.flushTimers();
        expect(seen, ['caught Cancelled(signed out)']);
        expect(job.outcome, isA<Done<int>>());
        expect(job.isCancelled, isFalse);
      });
    });

    test('a body that cancels itself does not come through cancelWith', () {
      fakeAsync((async) {
        final job = CountingJob((ctx) async {
          account.signedIn = false;
          await ctx.join(work);
          return 1;
        })
          .._launch()
          ..ignoreFailure();
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
          await ctx.abandonable(download);
          seen.add('the wait came back');
          ctx.check();
          seen.add('the body went on');
        })
          .._launch()
          ..ignoreFailure();
        async.elapse(const Duration(milliseconds: 10));
        account.signedIn = false;
        async.flushTimers();
        expect(seen, ['the wait came back']);
        expect('${job.outcome}', 'Cancelled(signed out)');
      });
    });

    test('with abandonable the body goes on with the rows after a sign-out',
        () {
      expect(printed(() => runAbandonableDownload(engineStops: false)), [
        'sign out',
        'downloaded 42 rows',
        'close the connection',
        'outcome: Cancelled(signed out)',
      ]);
    });

    test('the engine that cancels the job itself stops it at the sign-out', () {
      expect(printed(() => runAbandonableDownload(engineStops: true)), [
        'sign out',
        'close the connection',
        'outcome: Cancelled(signed out)',
      ]);
    });

    test('the job accepts that cancellation inside the sign-out', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = MyJob<void>((ctx) async {
          ctx.onCancel(() => seen.add('${async.elapsed.inMilliseconds} ms'));
          await ctx.abandonable(download);
        })
          .._launch()
          ..ignoreFailure();
        account.onSignOut = () => job._stop(signedOut());
        async.elapse(const Duration(milliseconds: 10));
        account.signOut();
        expect(seen, ['10 ms'], reason: 'onCancel runs inside the sign-out');
        async.flushMicrotasks();
        expect(
          '${job.outcome}',
          'Cancelled(signed out)',
          reason: 'abandonable threw at once, 10 ms before the download ends',
        );
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
            ..ignoreFailure();
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
          await ctx.abandonable(work);
          seen.add('child ran to its end');
        });
        final job = StubbornJob<void>((ctx) async {
          ctx.onCancel(() => seen.add('told to stop'));
          await ctx.run(child);
        })
          ..launch()
          ..ignoreFailure();
        async.flushMicrotasks();
        job.end(signedOut());
        expect('${job.outcome}', 'Cancelled(signed out)');
        async.flushTimers();
        expect(seen, ['child ran to its end']);
        expect(child.outcome, isA<Done<void>>());
      });
    });

    test('mustCallSuper holds an override of check() to super', () {
      expect(
        File('lib/src/job_context.dart').readAsStringSync(),
        contains('  @override\n  @mustCallSuper\n  void check() {'),
        reason: 'the page says the analyzer requires the call, and nothing '
            'else here would notice the annotation gone',
      );
    });
  });

  test('Deferred start', () {
    fakeAsync((async) {
      final job = Job.deferred<void>((ctx) => ctx.abandonable(work));
      // ... later, or from a queue of your own
      // ignore: cascade_invocations
      job.start();
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('a queue starts a deferred job in the zone the job was made in', () {
    fakeAsync((async) {
      final made = <String>[];
      final queue = <String>[];
      late Zone zone;
      late Completer<void> connected;
      late DeferredJob<void> job;
      runZonedGuarded(
        () {
          zone = Zone.current;
          connected = Completer<void>();
          job = Job.deferred<void>((_) async {
            await connected.future;
          })
            ..ignoreFailure();
        },
        (error, stackTrace) => made.add('$error'),
      );
      runZonedGuarded(
        () => zone.run(job.start),
        (error, stackTrace) => queue.add('$error'),
      );
      async.flushMicrotasks();
      connected.completeError(StateError('connection lost'));
      async.flushTimers();
      expect(
        '${job.outcome}',
        'Failed(Bad state: connection lost)',
        reason: "started by job.start() from the queue's runZonedGuarded, "
            'the body would never hear of the failure',
      );
      expect(made, isEmpty);
      expect(queue, isEmpty);
    });
  });

  test('every quote on the page is what its code prints', () {
    final prints = [
      printed(() => first.runQueue().ignore()),
      printed(() => runQueue().ignore()),
      printed(() => runWholeEngine().ignore()),
      printed(() => first.runDownload('cancel')),
      printed(() => first.runDownload('sign out')),
      printed(() {
        account.signedIn = true;
        runDownload('sign out');
      }),
      printed(() {
        account.signedIn = true;
        runAbandonableDownload(engineStops: false);
      }),
      printed(() {
        account.signedIn = true;
        runAbandonableDownload(engineStops: true);
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
    '### One loop, and no other way to start': 'test/extending_rakes_test.dart',
    "### A cancellation of the engine's own": 'test/extending_rakes_test.dart',
    '### Not waiting for the checkpoint': 'test/extending_rakes_test.dart',
    '### The whole engine': 'test/extending_rakes_test.dart',
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

  // The whole engine shows no code of the engine: a table names, class by
  // class, the members each section above shows. Every member of the job
  // and the queue of this file is in that table, but for `_stop`, which
  // comes with the rule, and `MyContext` has none, as first shown. Each
  // member a row names is declared in the code under the heading the row
  // links to, and a row of the constructor alone finds the constructor
  // there. The link is read by its anchor, the way GitHub makes it, so the
  // two sections called "The first attempt" stay apart, and its text is the
  // heading of that anchor. A member moved to another section, renamed or
  // added turns this red.
  test(
      'the table under "### The whole engine" names every member of this '
      'file and the section that declares it', () {
    // A declaration at the indentation of a member: a type, `final` or
    // `get` in front of the name, and a parameter list, a value or a `;`
    // after it. The front is greedy: `Future<T> Function(MyContext ctx)?`
    // in front of `_body` would otherwise give `Function`.
    final declaration = RegExp(
      r'^  (?! )(?:final |[\w<>?,() ]*[\w>?)] )(?:get )?(\w+) *[(=;]',
      multiLine: true,
    );
    Set<String> declaredIn(String code) => {
          for (final match in declaration.allMatches(code)) match.group(1)!,
        };
    String body(String type, String path) {
      final file = File(path).readAsStringSync();
      final start = file.indexOf('final class $type');
      return file.substring(start, file.indexOf('\n}\n', start));
    }

    final dart = RegExp(r'```dart\n(.*?)\n```', dotAll: true);
    // The anchor GitHub gives a heading: lower case, no punctuation but `-`
    // and `_`, a `-` for each space, and `-1`, `-2` on a repeat.
    final code = <String, String>{};
    final titles = <String, String>{};
    var table = '';
    for (final part in File('doc/extending.md')
        .readAsStringSync()
        .split(RegExp('^(?=#)', multiLine: true))) {
      final heading = part.split('\n').first;
      final name = heading.replaceFirst(RegExp('^#+ '), '');
      final base = name
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\- ]'), '')
          .replaceAll(' ', '-');
      var anchor = base;
      for (var n = 1; titles.containsKey(anchor); n++) {
        anchor = '$base-$n';
      }
      titles[anchor] = name;
      code[anchor] = [
        for (final block in dart.allMatches(part)) block.group(1)!,
      ].join('\n');
      if (heading == '### The whole engine') table = part;
    }

    final named = <String, Set<String>>{};
    final row = RegExp(r'^\| `(\w+)` \| (.*) \| \[(.*)\]\(#(.*)\) \|$');
    for (final line in table.split('\n')) {
      final match = row.firstMatch(line);
      if (match == null) continue;
      final [type!, members!, section!, anchor!] = match.groups([1, 2, 3, 4]);
      expect(titles[anchor], section, reason: line);
      final names = {
        for (final name in RegExp(r'`(\w+)(?:\(\))?`').allMatches(members))
          name.group(1)!,
      };
      expect(declaredIn(code[anchor]!), containsAll(names), reason: line);
      if (members.contains('the constructor')) {
        expect(
          code[anchor],
          matches(RegExp('^  $type\\(', multiLine: true)),
          reason: line,
        );
      }
      (named[type] ??= {}).addAll(names);
    }
    const file = 'test/extending_rakes_test.dart';
    expect(named.keys, unorderedEquals(['MyJob', 'MyQueue', 'MyContext']));
    expect(named['MyJob'], declaredIn(body('MyJob', file))..remove('_stop'));
    expect(named['MyQueue'], declaredIn(body('MyQueue', file)));
    expect(named['MyContext'], isEmpty);
    expect(
      declaredIn(body('MyContext', 'test/support/extending_plain.dart')),
      isEmpty,
    );
  });

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
