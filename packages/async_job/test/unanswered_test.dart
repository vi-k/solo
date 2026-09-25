@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/probe_job.dart';

// Two hooks see an error no outcome carries, and they do different work:
// `onError` is told about it, `onUnanswered` answers for it. An observer
// that overrides only the first changes nowhere the error goes; one that
// overrides the second takes the answer, and `super` hands it on to the
// zone the job was created in.

/// Watches and answers for nothing: every body is the default one.
final class Plain extends JobObserver {}

/// Both hooks in one list, in order; with [answers] it answers and stops
/// the error, without it `super` sends the error on.
final class Counting extends JobObserver {
  final bool answers;
  final seen = <String>[];

  Counting({this.answers = false});

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      seen.add('onError: $error');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    seen.add('onUnanswered: $error');
    if (!answers) {
      super.onUnanswered(job, error, stackTrace);
    }
  }
}

/// Somebody else's superclass.
class Base {}

/// A class that extends another one and mixes the observer in.
final class Mixed extends Base with JobObserver {}

final class ThrowingAnswer extends JobObserver {
  final finished = <String>[];

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      throw StateError('onUnanswered');

  @override
  void onFinish(Job<Object?> job) => finished.add('$job');
}

final class ThrowingNotice extends JobObserver {
  final answered = <Object>[];

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      throw StateError('onError');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    answered.add(error);
    super.onUnanswered(job, error, stackTrace);
  }
}

/// A job of another kind, which the core never hands a hook.
final class ForeignJob implements Job<Object?> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const outside = [
  'Bad state: discard',
  'Bad state: cleanup',
  'Bad state: onCancel',
  'Bad state: whenCancelled',
  'Bad state: unattended',
  'Bad state: abandoned',
];

/// Every error a job can run into outside its body, one of each: a
/// `discard` releasing a value the cancellation kept from the body,
/// cleanup, a callback of `onCancel` and of `whenCancelled`, unattended
/// work, and the late failure of an action `wait` walked away from.
Job<void> failingOutside(JobObserver? observer) {
  final job = Job<void>(key: 'j', observer: observer, (ctx) async {
    ctx
      ..onDispose(() => throw StateError('cleanup'))
      ..onCancel(() => throw StateError('onCancel'))
      ..unattended(() async {
        await delay(1);
        throw StateError('unattended');
      });
    // `ignore`, so the Cancelled thrown into the abandoned future does not
    // reach the zone on its own account.
    ctx.wait(() async {
      await delay(50);
      throw StateError('abandoned');
    }).ignore();
    // Cancelled 10 ms in, `join` waits the action out and hands the value
    // to `discard`, which throws.
    await ctx.join(
      () => delay(20),
      discard: (_) => throw StateError('discard'),
    );
  })
    ..whenCancelled((_) => throw StateError('whenCancelled'));
  return job;
}

/// Runs [body] under fake time in a zone of its own and returns what
/// reached that zone.
List<String> zoneOf(void Function(FakeAsync async) body) {
  final caught = <String>[];
  runZonedGuarded(
    () => fakeAsync(body),
    (error, stackTrace) => caught.add('$error'),
  );
  return caught;
}

/// Runs the job of [failingOutside] and cancels it 10 ms in.
List<String> cancelledOutside(JobObserver? observer) => zoneOf((async) {
      final job = failingOutside(observer);
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
    });

/// A child whose body fails 5 ms in while a child of its own still runs:
/// it waits for that one, and a cancellation arriving 10 ms in covers the
/// failure.
Job<int> failingFirst(String key, {JobObserver? observer}) =>
    Job.deferred<int>(key: key, observer: observer, (ctx) async {
      ctx.run(Job.deferred<void>((ctx) => ctx.wait(() => delay(50)))).ignore();
      await delay(5);
      throw StateError('$key failed first');
    });

/// A parent that runs [child] through `ctx.run` and is cancelled 10 ms in.
List<String> runCancelled(
  JobObserver? observer,
  Job<int> Function() child,
) =>
    zoneOf((async) {
      final parent = Job<void>(observer: observer, (ctx) async {
        await ctx.run(child());
      });
      async.elapse(const Duration(milliseconds: 10));
      parent.cancel().ignore();
      async.flushTimers();
    });

/// Runs [scenario] with an observer that watches, with none and with one
/// that answers, and expects [error] answered for: told once, after
/// whatever [alsoTold] names, then asked once, and in the zone unless the
/// override kept it out.
void expectAnswered(
  List<String> Function(JobObserver? observer) scenario,
  String error, {
  List<String> alsoTold = const [],
}) {
  final watching = Counting();
  expect(
    scenario(watching),
    [error],
    reason: 'the default answer is the zone, once',
  );
  expect(
    watching.seen,
    [...alsoTold, 'onError: $error', 'onUnanswered: $error'],
  );
  expect(scenario(null), [error], reason: 'without an observer, the zone');
  final answering = Counting(answers: true);
  expect(
    scenario(answering),
    isEmpty,
    reason: 'an override answers, and nothing reaches the zone',
  );
  expect(answering.seen, watching.seen);
}

/// Runs [scenario] with an observer that watches and with none, and
/// expects [error] told once and nothing in the zone.
void expectOnlyTold(
  List<String> Function(JobObserver? observer) scenario,
  String error,
) {
  final watching = Counting();
  expect(scenario(watching), isEmpty);
  expect(watching.seen, ['onError: $error']);
  expect(scenario(null), isEmpty);
}

void main() {
  test('an observer that only watches keeps the route to the zone', () {
    expect(cancelledOutside(Plain()), unorderedEquals(outside));
    expect(
      cancelledOutside(null),
      unorderedEquals(outside),
      reason: 'the same as with no observer at all',
    );
  });

  test('the default answer goes to the zone the job was created in', () {
    final creation = <Object>[];
    final starting = <Object>[];
    fakeAsync((async) {
      late final DeferredJob<void> job;
      runZonedGuarded(
        () {
          job = Job.deferred<void>(observer: Plain(), (ctx) async {
            ctx.onDispose(() => throw StateError('cleanup'));
          });
        },
        (error, stackTrace) => creation.add(error),
      );
      runZonedGuarded(job.start, (error, stackTrace) => starting.add(error));
      async.flushTimers();
    });
    expect(creation.map((error) => '$error'), ['Bad state: cleanup']);
    expect(starting, isEmpty, reason: 'not the zone the job was started in');
  });

  test('an override without super answers, and nothing reaches the zone', () {
    final observer = Counting(answers: true);
    expect(cancelledOutside(observer), isEmpty);
    expect(
      [
        for (final line in observer.seen)
          if (line.startsWith('onUnanswered')) line,
      ],
      unorderedEquals([for (final error in outside) 'onUnanswered: $error']),
      reason: 'the override was asked about every one of them',
    );
  });

  test('an override with super answers and keeps the zone as well', () {
    final observer = Counting();
    expect(cancelledOutside(observer), unorderedEquals(outside));
    expect(
      observer.seen.where((line) => line.startsWith('onUnanswered')),
      hasLength(outside.length),
    );
  });

  test('each error is told once and asked about once, onError first', () {
    final observer = Counting(answers: true);
    cancelledOutside(observer);
    expect(observer.seen, hasLength(2 * outside.length));
    for (var i = 0; i < observer.seen.length; i += 2) {
      final error = observer.seen[i].substring('onError: '.length);
      expect(observer.seen[i], 'onError: $error');
      expect(observer.seen[i + 1], 'onUnanswered: $error');
    }
    expect(
      observer.seen.map((line) => line.split(': ').last).toSet(),
      unorderedEquals([
        for (final error in outside) error.split(': ').last,
      ]),
    );
  });

  group('a failure of the body no parent took is never asked about', () {
    // Each job also fails in its cleanup, so a hook that is never called
    // at all cannot pass for one that is called at the right times.
    List<String> asked(Job<void> Function(JobObserver observer) start) {
      final observer = Counting(answers: true);
      zoneOf((async) {
        final job = start(observer);
        async.elapse(const Duration(milliseconds: 10));
        job.cancel().ignore();
        async.flushTimers();
      });
      return [
        for (final line in observer.seen)
          if (line.startsWith('onUnanswered')) line,
      ];
    }

    test('a Failed outcome', () {
      expect(
        asked(
          (observer) => Job<void>(observer: observer, (ctx) async {
            ctx.onDispose(() => throw StateError('cleanup'));
            throw StateError('body');
          }),
        ),
        ['onUnanswered: Bad state: cleanup'],
      );
    });

    test('a failure after the job accepted a cancellation', () {
      expect(
        asked(
          (observer) => Job<void>(observer: observer, (ctx) async {
            ctx.onDispose(() => throw StateError('cleanup'));
            await ctx.join(() => delay(20));
            throw StateError('stopped at the token');
          }),
        ),
        ['onUnanswered: Bad state: cleanup'],
      );
    });

    test('a failure the cancellation covered while children finished', () {
      expect(
        asked(
          (observer) => Job<void>(observer: observer, (ctx) async {
            ctx
              ..onDispose(() => throw StateError('cleanup'))
              ..run(
                Job.deferred<void>(
                  cancellable: false,
                  (ctx) => ctx.join(() => delay(50)),
                ),
              ).ignore();
            await delay(5);
            throw StateError('failed first');
          }),
        ),
        ['onUnanswered: Bad state: cleanup'],
      );
    });
  });

  group('a failure a cancellation covered, when a parent took the outcome', () {
    // The parent passes on what the outcome carries, and the outcome
    // carries the cancellation: the failure is in nothing it passes on, so
    // the child answers for it the way a branch the group did not throw
    // does.
    const error = 'Bad state: child failed first';

    test('a child of run whose parent was cancelled', () {
      expectAnswered(
        (observer) => runCancelled(observer, () => failingFirst('child')),
        error,
      );
    });

    test('a child of run cancelled through its own handle', () {
      expectAnswered(
        (observer) => zoneOf((async) {
          final child = failingFirst('child');
          Job<void>(observer: observer, (ctx) async {
            await ctx.run(child);
          }).ignore();
          async.elapse(const Duration(milliseconds: 10));
          child.cancel().ignore();
          async.flushTimers();
        }),
        error,
      );
    });

    test('a branch of runAll whose parent was cancelled', () {
      expectAnswered(
        (observer) => zoneOf((async) {
          final parent = Job<void>(observer: observer, (ctx) async {
            await ctx.runAll([
              failingFirst('branch'),
              Job.deferred<int>((ctx) async {
                await ctx.wait(() => delay(100));
                return 2;
              }),
            ]);
          });
          async.elapse(const Duration(milliseconds: 10));
          parent.cancel().ignore();
          async.flushTimers();
        }),
        'Bad state: branch failed first',
      );
    });

    test('a branch that failed inside uncancellable while holding the stop',
        () {
      expectAnswered(
        (observer) => zoneOf((async) {
          Job<void>(observer: observer, (ctx) async {
            try {
              await ctx.runAll([
                Job.deferred<int>((ctx) async {
                  await ctx.wait(() => delay(5));
                  throw StateError('first');
                }),
                Job.deferred<int>((ctx) async {
                  await ctx.uncancellable<void>(() async {
                    await delay(10);
                    throw StateError('held');
                  });
                  return 2;
                }),
              ]);
            } on Object catch (_) {
              // The group throws the first failure; the one under test is
              // the other.
            }
          }).ignore();
          async.flushTimers();
        }),
        'Bad state: held',
        alsoTold: ['onError: Bad state: first'],
      );
    });

    test('a branch that failed first and was stopped by a refused sibling', () {
      // A body that throws before its first `await` has failed before the
      // group hears a word from it, and the refusal of the next child
      // stops every branch already admitted -- this one too.
      expectAnswered(
        (observer) => zoneOf((async) {
          Job<void>(observer: observer, (ctx) async {
            try {
              await ctx.runAll<int>([
                Job.deferred<int>((ctx) {
                  ctx
                      .run(
                        Job.deferred<void>(
                          (ctx) => ctx.wait(() => delay(50)),
                        ),
                      )
                      .ignore();
                  throw StateError('failed at once');
                }),
                Job<int>((ctx) async => 0),
              ]);
            } on Object catch (_) {
              // The refusal is what comes out of the group.
            }
          }).ignore();
          async.flushTimers();
        }),
        'Bad state: failed at once',
      );
    });

    test('a failure an engine handed in over the mark is told, then asked', () {
      // It never went through the body, so nobody has announced it yet.
      expectAnswered(
        (observer) => zoneOf((async) {
          final child = ProbeJob<int>((ctx) async {
            await delay(100);
            return 1;
          });
          final parent = Job<void>(observer: observer, (ctx) async {
            await ctx.run(child);
          });
          async.elapse(const Duration(milliseconds: 10));
          parent.cancel().ignore();
          async.elapse(const Duration(milliseconds: 10));
          child.drop(Failed(StateError('by hand'), StackTrace.current));
          async.flushTimers();
        }),
        'Bad state: by hand',
      );
    });

    test('ignore on the child does not silence it', () {
      expectAnswered(
        (observer) =>
            runCancelled(observer, () => failingFirst('child')..ignore()),
        error,
      );
    });

    test('a child with an observer of its own answers with it', () {
      final parent = Counting();
      final own = Counting(answers: true);
      final zone = runCancelled(
        parent,
        () => failingFirst('child', observer: own),
      );
      expect(own.seen, ['onError: $error', 'onUnanswered: $error']);
      expect(parent.seen, isEmpty, reason: "the parent's is not asked");
      expect(zone, isEmpty, reason: 'the child answered with its own');
    });
  });

  group('a failure after the child accepted a cancellation is only told', () {
    test('a stop at the token', () {
      expectOnlyTold(
        (observer) => runCancelled(
          observer,
          () => Job.deferred<int>((ctx) async {
            final stopped = Completer<int>();
            ctx.onCancel(
              () => stopped.completeError(StateError('stopped at the token')),
            );
            return stopped.future;
          }),
        ),
        'Bad state: stopped at the token',
      );
    });

    test('the failure of a step caught earlier, thrown again after the stop',
        () {
      // The section held nothing when its step failed, so it said nothing
      // about the order, and the same error thrown after the job accepted
      // the cancellation is a failure after the mark.
      expectOnlyTold(
        (observer) => runCancelled(
          observer,
          () => Job.deferred<int>((ctx) async {
            Object? step;
            try {
              await ctx.uncancellable<void>(() async {
                await delay(1);
                throw StateError('the step failed');
              });
            } on Object catch (error) {
              step = error;
            }
            final stopped = Completer<void>();
            ctx.onCancel(stopped.complete);
            await stopped.future;
            Error.throwWithStackTrace(step!, StackTrace.current);
          }),
        ),
        'Bad state: the step failed',
      );
    });

    test('another failure after a step that failed under a held stop', () {
      // The section put the order right for its own error, and for no
      // other: the body caught that one and threw a new one after the mark.
      expectOnlyTold(
        (observer) => runCancelled(
          observer,
          () => Job.deferred<int>((ctx) async {
            try {
              await ctx.uncancellable<void>(() async {
                await delay(20);
                throw StateError('the step failed');
              });
            } on Object catch (_) {
              // Handled: the job goes on, cancelled by now.
            }
            throw StateError('after the step');
          }),
        ),
        'Bad state: after the step',
      );
    });
  });

  group('a job no parent took keeps the rule of its outcome', () {
    /// A child of `each` whose callback fails while a child of its own
    /// still runs.
    Job<void> eachFailingFirst(JobContext ctx) =>
        ctx.each(Stream<int>.fromIterable([1]), (child, event) {
          child
              .run(Job.deferred<void>((ctx) => ctx.wait(() => delay(50))))
              .ignore();
          throw StateError('each failed first');
        });

    test('a child of each nobody reads goes to the zone, unasked', () {
      final observer = Counting();
      final zone = zoneOf((async) {
        final parent = Job<void>(observer: observer, (ctx) async {
          eachFailingFirst(ctx);
          await ctx.wait(() => delay(100));
        });
        async.elapse(const Duration(milliseconds: 10));
        parent.cancel().ignore();
        async.flushTimers();
      });
      expect(observer.seen, ['onError: Bad state: each failed first']);
      expect(zone, ['Bad state: each failed first']);
    });

    test('an outcome somebody reads keeps it out of the zone', () {
      // The reader got the cancellation and not the failure; the rule of an
      // observed outcome decides here, for a root and for a child of `each`.
      final observer = Counting();
      final zone = zoneOf((async) {
        final root = Job<void>(observer: observer, (ctx) async {
          ctx
              .run(Job.deferred<void>((ctx) => ctx.wait(() => delay(50))))
              .ignore();
          await delay(5);
          throw StateError('root failed first');
        });
        root.value.ignore();
        final parent = Job<void>(observer: observer, (ctx) async {
          await eachFailingFirst(ctx).value;
        });
        async.elapse(const Duration(milliseconds: 10));
        root.cancel().ignore();
        parent.cancel().ignore();
        async.flushTimers();
      });
      expect(
        observer.seen,
        unorderedEquals([
          'onError: Bad state: root failed first',
          'onError: Bad state: each failed first',
        ]),
      );
      expect(zone, isEmpty);
    });
  });

  test('a branch failure the group did not throw is asked about once', () {
    final observer = Counting(answers: true);
    zoneOf((async) {
      Job<void>(observer: observer, (ctx) async {
        try {
          await ctx.runAll([
            Job.deferred<int>((ctx) async {
              await ctx.wait(() => delay(10));
              throw StateError('first');
            }),
            Job.deferred<int>(cancellable: false, (ctx) async {
              await ctx.wait(() => delay(20));
              throw StateError('second');
            }),
          ]);
        } on Object catch (_) {
          // The group throws the first one.
        }
      }).ignore();
      async.flushTimers();
    });
    expect(observer.seen, [
      'onError: Bad state: first',
      'onError: Bad state: second',
      'onUnanswered: Bad state: second',
    ]);
  });

  test('a cancellation is asked about, and the default body drops it', () {
    for (final answers in [true, false]) {
      final observer = Counting(answers: answers);
      final zone = zoneOf((async) {
        Job<void>(observer: observer, (ctx) async {
          ctx
            ..onDispose(() => throw const Cancelled('thrown by cleanup'))
            ..unattended(() async {
              await [
                Future<void>.error(const Cancelled('a'), StackTrace.empty),
                Future<void>.error(const Cancelled('b'), StackTrace.empty),
              ].wait;
            });
          await delay(10);
        }).ignore();
        async.flushTimers();
      });
      expect(
        observer.seen.where((line) => line.startsWith('onUnanswered')),
        hasLength(2),
        reason: 'answers: $answers',
      );
      expect(
        observer.seen,
        contains(startsWith('onUnanswered: ParallelWaitError')),
        reason: 'answers: $answers',
      );
      expect(zone, isEmpty, reason: 'answers: $answers');
    }
  });

  test('a child without an observer of its own answers with its parent', () {
    final observer = Counting(answers: true);
    final zone = zoneOf((async) {
      Job<void>(observer: observer, (ctx) async {
        await ctx.run(
          Job.deferred<void>((ctx) async {
            ctx.onDispose(() => throw StateError('child cleanup'));
          }),
        );
      }).ignore();
      async.flushTimers();
    });
    expect(observer.seen, contains('onUnanswered: Bad state: child cleanup'));
    expect(zone, isEmpty);
  });

  test('an onUnanswered that throws changes nothing else', () {
    final observer = ThrowingAnswer();
    late final Job<void> job;
    final zone = zoneOf((async) {
      job = Job<void>(key: 'j', observer: observer, (ctx) async {
        ctx.onDispose(() => throw StateError('cleanup'));
      });
      async.flushTimers();
    });
    expect(job.outcome, isA<Done<void>>());
    expect(zone, ['Bad state: onUnanswered']);
    expect(observer.finished, ['Job(j)'], reason: 'the next hook still ran');
  });

  test('an onError that throws does not cost the error its answer', () {
    final observer = ThrowingNotice();
    final zone = zoneOf((async) {
      Job<void>(observer: observer, (ctx) async {
        ctx.onDispose(() => throw StateError('cleanup'));
      }).ignore();
      async.flushTimers();
    });
    expect(observer.answered.map((error) => '$error'), ['Bad state: cleanup']);
    expect(zone, ['Bad state: onError', 'Bad state: cleanup']);
  });

  test('with JobObserver, a class that extends another keeps the route', () {
    final zone = zoneOf((async) {
      Job<void>(observer: Mixed(), (ctx) async {
        ctx.onDispose(() => throw StateError('cleanup'));
      }).ignore();
      async.flushTimers();
    });
    expect(zone, ['Bad state: cleanup']);
  });

  test('an error of the finished hook of an engine is answered for', () {
    final observer = Counting();
    late final Job<int> job;
    final zone = zoneOf((async) {
      job = FailingHookJob<int>(observer: observer, (ctx) async => 1)..launch();
      async.flushTimers();
    });
    expect(job.outcome, isA<Done<int>>());
    expect(observer.seen, [
      'onError: Bad state: hook failed',
      'onUnanswered: Bad state: hook failed',
    ]);
    expect(zone, ['Bad state: hook failed']);
  });

  test('a source that fails to stop is answered for on the continuation', () {
    final observer = Counting();
    final zone = zoneOf((async) {
      final source = UncancellableByBugJob<int>((ctx) async => 1);
      source.then((ctx, value) => value, observer: observer).cancel().ignore();
      async.flushTimers();
    });
    expect(observer.seen, [
      'onError: Bad state: engine failed to cancel',
      'onUnanswered: Bad state: engine failed to cancel',
    ]);
    expect(zone, ['Bad state: engine failed to cancel']);
  });

  test('called by hand with a job of another kind, the filter holds', () async {
    final zone = <Object>[];
    await runZonedGuarded(
      () async {
        // A clean envelope, the way `wait` on a list of futures builds one.
        Object? envelope;
        try {
          await [
            Future<void>.error(const Cancelled('a'), StackTrace.empty),
            Future<void>.error(const Cancelled('b'), StackTrace.empty),
          ].wait;
        } on Object catch (error) {
          envelope = error;
        }
        final observer = Plain();
        final job = ForeignJob();
        observer
          ..onUnanswered(job, const Cancelled('dropped'), StackTrace.empty)
          ..onUnanswered(job, envelope!, StackTrace.empty)
          ..onUnanswered(job, StateError('kept'), StackTrace.empty);
      },
      (error, stackTrace) => zone.add(error),
    );
    expect(zone.map((error) => '$error'), ['Bad state: kept']);
  });
}
