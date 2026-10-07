// The deadline of a job: `timeout` on `Job`, `Job.deferred` and `JobBase`.
@Timeout(Duration(seconds: 30))
library;

import 'dart:async';

import 'package:async_job/engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/error_observer.dart';
import 'support/reachability.dart';

Duration ms(int milliseconds) => Duration(milliseconds: milliseconds);

/// Far enough that no test reaches it: a timer still pending at the end of
/// a job is one the job left behind, not one that has not fired yet.
const hour = Duration(hours: 1);

/// Made in a frame of its own, so the trace of the deadline can be told to
/// lead here.
Job<void> jobWithADeadline() => Job<void>(
      timeout: ms(10),
      (ctx) => ctx.abandonable(() => delay(50)),
    );

/// An engine of a domain, with the protected surface the tests need.
final class Engine<T> extends JobBase<T> {
  final Future<T> Function(JobContext ctx) _body;

  /// Called from [started], the way an engine does its bookkeeping there.
  final void Function(Engine<T> job)? onStarted;

  /// Whether [createContext] ends the job before it can start.
  final bool refuseContext;

  /// Whether [cancelWith] wraps every cancellation into a new [Cancelled]
  /// with the same reason before it calls `super`.
  final bool wrap;

  /// Whether [cancelWith] throws after `super` for the request of a
  /// deadline.
  final bool throwOnTimeout;

  /// Whether [cancelWith] turns down what a closing section lands, the way
  /// a rule of a domain may turn down a request that comes too late.
  final bool refuseLanded;

  var _landing = false;

  Engine(
    this._body, {
    super.timeout,
    super.observer,
    this.onStarted,
    this.refuseContext = false,
    this.wrap = false,
    this.throwOnTimeout = false,
    this.refuseLanded = false,
  });

  void launch() => start();

  void drop(Outcome<T> outcome) => finish(outcome);

  /// A cancellation the job cannot refuse, the way the rules of a domain
  /// make one.
  void cancelHard() => cancelWith(
        Cancelled.by(
          reason: const ManualCancelReason(),
          stackTrace: StackTrace.current,
        ),
        rejectable: false,
      );

  Cancelled? get held => heldCancel;

  @override
  void started() => onStarted?.call(this);

  @override
  void cancelWith(Cancelled cancelled, {bool rejectable = true}) {
    if (refuseLanded && _landing) {
      return;
    }
    super.cancelWith(
      wrap
          ? Cancelled.by(
              reason: cancelled.reason,
              started: cancelled.started,
              description: cancelled.description,
              stackTrace: cancelled.stackTrace,
            )
          : cancelled,
      rejectable: rejectable,
    );
    if (throwOnTimeout && cancelled.reason is TimeoutCancelReason) {
      throw StateError('engine');
    }
  }

  @override
  void leaveUncancellable() {
    _landing = true;
    try {
      super.leaveUncancellable();
    } finally {
      _landing = false;
    }
  }

  @override
  JobContextBase createContext() {
    if (refuseContext) {
      finish(
        Cancelled.by(
          reason: const ManualCancelReason(),
          started: false,
          stackTrace: StackTrace.current,
        ),
      );
    }
    return EngineContext(this);
  }

  @override
  Future<T> execute(covariant EngineContext ctx) => _body(ctx);
}

final class EngineContext extends JobContextBase {
  EngineContext(super.owner);
}

/// Hears how a job ended.
final class FinishObserver extends JobObserver {
  final List<String> seen;

  FinishObserver(this.seen);

  @override
  void onFinish(Job<Object?> job) {
    final outcome = job.outcome;
    seen.add(
      'onFinish ${outcome is Cancelled ? outcome.reason.runtimeType : ''}',
    );
  }
}

/// A reason heavy enough that holding it is worth noticing.
final class HeavyReason extends CancelReason {
  final List<int> bytes = List<int>.filled(1 << 16, 1);

  @override
  String get name => 'heavy ${bytes.length}';
}

/// Cancels [job] with a [HeavyReason] made in a frame of its own, and
/// returns nothing that holds it.
WeakReference<Object> cancelHeavily(Job<Object?> job) {
  final reason = HeavyReason();
  job.cancel(reason: reason).ignore();
  return WeakReference(reason);
}

/// Whether [reference] is gone, asked from inside [async].
bool collectedIn(FakeAsync async, WeakReference<Object> reference) {
  bool? gone;
  collected(reference).then((value) => gone = value).ignore();
  async.flushMicrotasks();
  return gone!;
}

void main() {
  test('a body longer than its deadline ends Cancelled(timeout)', () {
    fakeAsync((async) {
      final job = jobWithADeadline();
      async.elapse(ms(9));
      expect(job.isCancelled, isFalse);
      async.elapse(ms(1));
      final outcome = job.outcome! as Cancelled;
      expect('$outcome', 'Cancelled(timeout)');
      expect(outcome.started, isTrue);
      expect(outcome.reason, isA<TimeoutCancelReason>());
      expect((outcome.reason as TimeoutCancelReason).timeout, ms(10));
      expect(
        '${outcome.stackTrace}',
        contains('jobWithADeadline'),
        reason: 'the trace leads to the code that set the deadline',
      );
      async.flushTimers();
    });
  });

  group('the timer goes the moment the job ends:', () {
    test('Done', () {
      fakeAsync((async) {
        final gate = Completer<void>();
        final job = Job<int>(timeout: hour, (ctx) async {
          await ctx.abandonable(() => gate.future);
          return 1;
        });
        async.flushMicrotasks();
        expect(async.pendingTimers, hasLength(1));
        gate.complete();
        async.flushMicrotasks();
        expect(job.outcome, isA<Done<int>>());
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('Failed', () {
      fakeAsync((async) {
        final gate = Completer<void>();
        final job = Job<void>(timeout: hour, (ctx) async {
          await ctx.abandonable(() => gate.future);
          throw StateError('boom');
        })
          ..ignoreFailure();
        async.flushMicrotasks();
        expect(async.pendingTimers, hasLength(1));
        gate.complete();
        async.flushMicrotasks();
        expect(job.outcome, isA<Failed>());
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('Cancelled', () {
      fakeAsync((async) {
        final gate = Completer<void>();
        final job = Job<void>(
          timeout: hour,
          (ctx) => ctx.abandonable(() => gate.future),
        );
        async.flushMicrotasks();
        expect(async.pendingTimers, hasLength(1));
        job.cancel().ignore();
        async.flushMicrotasks();
        expect('${job.outcome}', 'Cancelled(manual)');
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('an engine refusing the context', () {
      fakeAsync((async) {
        final job = Engine<void>(
          timeout: hour,
          refuseContext: true,
          (ctx) async {},
        )..launch();
        expect(job.outcome, isA<Cancelled>());
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('an engine ending the job by hand from started', () {
      fakeAsync((async) {
        final job = Engine<int>(
          timeout: hour,
          onStarted: (job) => job.drop(const Done(0)),
          (ctx) async => 1,
        )..launch();
        expect(job.outcome, isA<Done<int>>());
        expect(async.pendingTimers, isEmpty);
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('an engine ending the job by hand while the body runs', () {
      fakeAsync((async) {
        final first = Completer<void>();
        final gate = Completer<void>();
        late final Engine<int> job;
        job = Engine<int>(timeout: hour, (ctx) async {
          await first.future;
          job.drop(const Done(0));
          await gate.future;
          return 1;
        });
        job.launch();
        expect(async.pendingTimers, hasLength(1));
        first.complete();
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
        expect(job.outcome, isA<Done<int>>());
        gate.complete();
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  test('a failed job with a deadline reaches the zone as one without', () {
    final caught = <Object>[];
    int? timersLeft;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>(timeout: hour, (ctx) async => throw StateError('boom'));
          async.flushMicrotasks();
          timersLeft = async.pendingTimers.length;
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught.map((error) => '$error').toList(), ['Bad state: boom']);
    expect(timersLeft, 0);
  });

  test('a failed body whose child outlives the deadline', () {
    final caught = <Object>[];
    Outcome<void>? outcome;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>(timeout: ms(10), (ctx) async {
            ctx
                .run(
                  Job.deferred<void>(
                    (child) => child.abandonable(() => delay(50)),
                  ),
                )
                .ignore();
            throw StateError('body');
          });
          async.flushTimers();
          outcome = job.outcome;
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect('$outcome', 'Cancelled(timeout)');
    expect(
      caught.map((error) => '$error').toList(),
      ['Bad state: body'],
      reason: 'the cancellation covered the failure, which goes to the zone',
    );
  });

  test('a deferred job started after more than its deadline', () {
    fakeAsync((async) {
      final job = Job.deferred<int>(timeout: ms(10), (ctx) async {
        await ctx.abandonable(() => delay(5));
        return 1;
      });
      async.elapse(ms(50));
      expect(async.pendingTimers, isEmpty, reason: 'counted from the start');
      job.start();
      async.elapse(ms(5));
      expect(job.outcome, isA<Done<int>>());
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('a job cancelled before its start', () {
    fakeAsync((async) {
      final deferred = Job.deferred<void>(timeout: hour, (ctx) async {});
      deferred.cancel().ignore();
      final auto = Job<void>(timeout: hour, (ctx) async {});
      auto.cancel().ignore();
      async.flushMicrotasks();
      expect((deferred.outcome! as Cancelled).started, isFalse);
      expect((auto.outcome! as Cancelled).started, isFalse);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('children the job waits for after its body', () {
    fakeAsync((async) {
      late Job<void> child;
      final job = Job<void>(timeout: ms(10), (ctx) async {
        child = Job.deferred<void>((ctx) => ctx.abandonable(() => delay(50)));
        ctx.run(child).ignore();
      });
      async.elapse(ms(10));
      final outcome = job.outcome! as Cancelled;
      expect('$outcome', 'Cancelled(timeout)');
      final childOutcome = child.outcome! as Cancelled;
      final reason = childOutcome.reason as ParentCancelReason;
      expect(reason.cause!.reason, isA<TimeoutCancelReason>());
      expect(identical(reason.cause!.reason, outcome.reason), isTrue);
      async.flushTimers();
    });
  });

  test('a parent cancelling a child before the child deadline', () {
    fakeAsync((async) {
      final gate = Completer<void>();
      final child = Job.deferred<void>(
        timeout: hour,
        (ctx) => ctx.abandonable(() => gate.future),
      );
      final parent = Job<void>((ctx) => ctx.run(child));
      async.flushMicrotasks();
      expect(async.pendingTimers, hasLength(1));
      parent.cancel().ignore();
      async.flushMicrotasks();
      expect('${child.outcome}', 'Cancelled(parent)');
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('a cleanup longer than what is left of the deadline', () {
    fakeAsync((async) {
      var discarded = false;
      final job = Job<int>(timeout: ms(10), (ctx) async {
        ctx
          ..onDiscard(() => discarded = true)
          ..onDispose(() => delay(50));
        await ctx.abandonable(() => delay(5));
        return 1;
      });
      async.elapse(ms(100));
      expect(job.outcome, isA<Done<int>>());
      expect(discarded, isFalse);
    });
  });

  test('a section the body left running holds the deadline past the body', () {
    fakeAsync((async) {
      var discarded = false;
      final job = Job<int>(timeout: ms(10), (ctx) async {
        ctx
          ..onDiscard(() => discarded = true)
          ..onDispose(() => delay(100));
        unawaited(ctx.uncancellable(() => delay(50)));
        await ctx.join(() => delay(20));
        return 1;
      });
      async.elapse(ms(10));
      expect(job.isCancelled, isFalse, reason: 'the section holds it');
      async.elapse(ms(300));
      expect(job.outcome, isA<Done<int>>());
      expect(discarded, isFalse);
    });
  });

  test('a branch whose section it left running holds the deadline', () {
    fakeAsync((async) {
      var discarded = false;
      final branch = Job.deferred<int>(timeout: ms(10), (ctx) async {
        ctx.onDiscard(() => discarded = true);
        unawaited(ctx.uncancellable(() => delay(50)));
        await ctx.join(() => delay(20));
        return 1;
      });
      final sibling = Job.deferred<int>((ctx) async {
        await ctx.abandonable(() => delay(100));
        return 2;
      });
      final parent = Job<List<int>>((ctx) => ctx.runAll([branch, sibling]));
      async.elapse(ms(300));
      expect((parent.outcome! as Done<List<int>>).value, [1, 2]);
      expect(branch.outcome, isA<Done<int>>());
      expect(discarded, isFalse);
    });
  });

  test('an engine that wraps the request into a new Cancelled', () {
    fakeAsync((async) {
      var discarded = false;
      final job = Engine<int>(timeout: ms(10), wrap: true, (ctx) async {
        ctx
          ..onDiscard(() => discarded = true)
          ..onDispose(() => delay(100));
        unawaited(ctx.uncancellable(() => delay(50)));
        await ctx.join(() => delay(20));
        return 1;
      })
        ..launch();
      async.elapse(ms(15));
      expect(job.held?.reason, isA<TimeoutCancelReason>());
      async.elapse(ms(300));
      expect(job.outcome, isA<Done<int>>());
      expect(discarded, isFalse);
    });
  });

  test('a section inside the body holds the deadline until it closes', () {
    fakeAsync((async) {
      var stepEnded = false;
      var afterStep = false;
      final job = Job<void>(timeout: ms(10), (ctx) async {
        await ctx.uncancellable(() => delay(50));
        stepEnded = true;
        await ctx.abandonable(() => delay(10));
        afterStep = true;
      });
      async.elapse(ms(30));
      expect(job.isCancelled, isFalse);
      async.flushTimers();
      expect(stepEnded, isTrue);
      expect(afterStep, isFalse);
      expect('${job.outcome}', 'Cancelled(timeout)');
    });
  });

  test('a branch whose body is over waits for its group', () {
    fakeAsync((async) {
      final fast = Job.deferred<int>(timeout: ms(10), (ctx) async => 1);
      final slow = Job.deferred<int>((ctx) async {
        await ctx.abandonable(() => delay(50));
        return 2;
      });
      final parent = Job<List<int>>((ctx) => ctx.runAll([fast, slow]));
      async.elapse(ms(100));
      expect((parent.outcome! as Done<List<int>>).value, [1, 2]);
      expect(fast.outcome, isA<Done<int>>());
    });
  });

  test('a branch whose deadline runs out', () {
    fakeAsync((async) {
      final expiring = Job.deferred<int>(timeout: ms(10), (ctx) async {
        await ctx.abandonable(() => delay(50));
        return 1;
      });
      final other = Job.deferred<int>((ctx) async {
        await ctx.abandonable(() => delay(100));
        return 2;
      });
      final parent = Job<List<int>>((ctx) => ctx.runAll([expiring, other]));
      async.flushTimers();
      expect('${expiring.outcome}', 'Cancelled(timeout)');
      final sibling = (other.outcome! as Cancelled).reason;
      expect(sibling, isA<SiblingCancelReason>());
      final cause = (sibling as SiblingCancelReason).cause as Cancelled;
      expect(cause.reason, isA<TimeoutCancelReason>());
      final parentOutcome = parent.outcome! as Cancelled;
      expect(parentOutcome.reason, isA<HandlerCancelReason>());
    });
  });

  test('a job cancelled by hand before its deadline', () {
    fakeAsync((async) {
      final job = Job<void>(
        timeout: ms(10),
        (ctx) => ctx.join(() => delay(50)),
      );
      async.elapse(ms(5));
      job.cancel().ignore();
      async.flushTimers();
      expect('${job.outcome}', 'Cancelled(manual)');
    });
  });

  group('arguments:', () {
    Matcher timeoutError(String message) => isA<ArgumentError>()
        .having((error) => error.name, 'name', 'timeout')
        .having((error) => error.message, 'message', contains(message));

    test('zero and negative deadlines', () {
      fakeAsync((async) {
        expect(
          () => Job<void>(timeout: Duration.zero, (ctx) async {}),
          throwsA(timeoutError('must be positive')),
        );
        expect(
          () => Job.deferred<void>(timeout: ms(-1), (ctx) async {}),
          throwsA(timeoutError('must be positive')),
        );
        expect(
          () => Engine<void>(timeout: Duration.zero, (ctx) async {}),
          throwsA(timeoutError('must be positive')),
        );
        expect(async.microtaskCount, 0, reason: 'nothing was scheduled');
      });
    });

    test('a deadline with cancellable: false', () {
      fakeAsync((async) {
        expect(
          () => Job<void>(
            cancellable: false,
            timeout: ms(10),
            (ctx) async {},
          ),
          throwsA(timeoutError('cancellable: false')),
        );
        expect(
          () => Job.deferred<void>(
            cancellable: false,
            timeout: ms(10),
            (ctx) async {},
          ),
          throwsA(timeoutError('cancellable: false')),
        );
        expect(async.microtaskCount, 0, reason: 'nothing was scheduled');
      });
    });
  });

  test('an engine whose cancelWith throws for the deadline', () {
    final errors = <Object>[];
    final caught = <Object>[];
    Outcome<void>? outcome;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Engine<void>(
            timeout: ms(10),
            observer: ErrorObserver.answering(errors),
            throwOnTimeout: true,
            (ctx) => ctx.abandonable(() => delay(50)),
          )..launch();
          async.flushTimers();
          outcome = job.outcome;
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect('$outcome', 'Cancelled(timeout)');
    expect(errors.map((error) => '$error').toList(), ['Bad state: engine']);
    expect(caught, isEmpty);
  });

  test('a child with a deadline caught by its parent', () {
    fakeAsync((async) {
      final job = Job<String>((ctx) async {
        try {
          await ctx.run(
            Job.deferred<void>(
              key: 'step',
              timeout: ms(10),
              (ctx) => ctx.abandonable(() => delay(50)),
            ),
          );
          return 'finished';
        } on Cancelled catch (cancelled) {
          if (cancelled.reason is! TimeoutCancelReason) {
            rethrow;
          }
          return 'timed out';
        }
      });
      async.flushTimers();
      expect((job.outcome! as Done<String>).value, 'timed out');
    });
  });

  test('a child with a deadline its parent lets out', () {
    fakeAsync((async) {
      final job = Job<void>(
        (ctx) => ctx.run(
          Job.deferred<void>(
            key: 'step',
            timeout: ms(10),
            (ctx) => ctx.abandonable(() => delay(50)),
          ),
        ),
      );
      async.flushTimers();
      expect(
        '${job.outcome}',
        'Cancelled(handler: child step: Cancelled(timeout))',
      );
    });
  });

  test('whenCancelled, onCancel and the observer hear the reason', () {
    fakeAsync((async) {
      final seen = <String>[];
      Job<void>(
        timeout: ms(10),
        observer: FinishObserver(seen),
        (ctx) async {
          ctx.onCancel(() {
            try {
              ctx.check();
            } on Cancelled catch (cancelled) {
              seen.add('onCancel ${cancelled.reason.runtimeType}');
            }
          });
          await ctx.abandonable(() => delay(50));
        },
      ).whenCancelled(
        (cancelled) =>
            seen.add('whenCancelled ${cancelled.reason.runtimeType}'),
      );
      async.flushTimers();
      expect(seen, [
        'onCancel TimeoutCancelReason',
        'whenCancelled TimeoutCancelReason',
        'onFinish TimeoutCancelReason',
      ]);
    });
  });

  test('a job started from unattended work', () {
    fakeAsync((async) {
      Zone? work;
      Zone? body;
      Zone? cancel;
      late Job<void> inner;
      Job<void>((ctx) async {
        ctx.unattended(() {
          work = Zone.current;
          inner = Job.deferred<void>(timeout: ms(10), (ctx) async {
            body = Zone.current;
            ctx.onCancel(() => cancel = Zone.current);
            await ctx.abandonable(() => delay(50));
          })
            ..start();
        });
      });
      async.flushTimers();
      expect('${inner.outcome}', 'Cancelled(timeout)');
      expect(identical(cancel, body), isTrue, reason: 'the zone of the start');
      expect(identical(cancel, work), isFalse, reason: 'not the work');
    });
  });

  group('a manual cancellation a left section holds', () {
    test('arriving before the deadline', () {
      fakeAsync((async) {
        var discarded = false;
        final job = Job<int>(timeout: ms(10), (ctx) async {
          ctx
            ..onDiscard(() => discarded = true)
            ..onDispose(() => delay(100));
          unawaited(ctx.uncancellable(() => delay(50)));
          await ctx.join(() => delay(20));
          return 1;
        });
        async.elapse(ms(5));
        job.cancel().ignore();
        async.elapse(ms(300));
        expect('${job.outcome}', 'Cancelled(manual)');
        expect(discarded, isTrue);
      });
    });

    test('arriving behind the deadline', () {
      fakeAsync((async) {
        var discarded = false;
        final job = Engine<int>(timeout: ms(10), (ctx) async {
          ctx
            ..onDiscard(() => discarded = true)
            ..onDispose(() => delay(100));
          unawaited(ctx.uncancellable(() => delay(50)));
          await ctx.join(() => delay(20));
          return 1;
        })
          ..launch();
        async.elapse(ms(15));
        job.cancel().ignore();
        expect(job.held?.reason, isA<TimeoutCancelReason>());
        async.elapse(ms(10));
        expect(job.held?.reason, isA<ManualCancelReason>());
        async.elapse(ms(300));
        expect('${job.outcome}', 'Cancelled(manual)');
        expect(discarded, isTrue);
      });
    });
  });

  group('a request behind the deadline is let go of', () {
    test('when the job ends by hand', () {
      fakeAsync((async) {
        final section = Completer<void>();
        final job = Engine<int>(timeout: ms(10), (ctx) async {
          await ctx.uncancellable(() => section.future);
          return 1;
        })
          ..launch();
        async.elapse(ms(10));
        final reason = cancelHeavily(job);
        job.drop(const Done(0));
        expect(collectedIn(async, reason), isTrue);
        expect(job.outcome, isA<Done<int>>());
        section.complete();
        async.flushMicrotasks();
      });
    });

    test('when a cancellation the job cannot refuse lands', () {
      fakeAsync((async) {
        final section = Completer<void>();
        final job = Engine<int>(timeout: ms(10), (ctx) async {
          await ctx.uncancellable(() => section.future);
          return 1;
        })
          ..launch();
        async.elapse(ms(10));
        final reason = cancelHeavily(job);
        job.cancelHard();
        expect(job.isRunning, isTrue);
        expect(collectedIn(async, reason), isTrue);
        section.complete();
        async.flushMicrotasks();
        expect('${job.outcome}', 'Cancelled(manual)');
      });
    });

    test('when the section lands the deadline', () {
      fakeAsync((async) {
        final section = Completer<void>();
        final after = Completer<void>();
        final job = Engine<int>(timeout: ms(10), (ctx) async {
          await ctx.uncancellable(() => section.future);
          await after.future;
          return 1;
        })
          ..launch();
        async.elapse(ms(10));
        final reason = cancelHeavily(job);
        section.complete();
        async.flushMicrotasks();
        expect(job.isCancelled, isTrue);
        expect(job.isRunning, isTrue);
        expect(collectedIn(async, reason), isTrue);
        after.complete();
        async.flushMicrotasks();
        expect('${job.outcome}', 'Cancelled(timeout)');
      });
    });

    test(
        'when the section lets the deadline go to an engine that turns it '
        'down', () {
      fakeAsync((async) {
        final section = Completer<void>();
        final after = Completer<void>();
        final job = Engine<int>(refuseLanded: true, timeout: ms(10), (
          ctx,
        ) async {
          await ctx.uncancellable(() => section.future);
          await after.future;
          return 1;
        })
          ..launch();
        async.elapse(ms(10));
        final reason = cancelHeavily(job);
        section.complete();
        async.flushMicrotasks();
        expect(job.isCancelled, isFalse);
        expect(job.held, isNull);
        expect(collectedIn(async, reason), isTrue);
        after.complete();
        async.flushMicrotasks();
        expect((job.outcome! as Done<int>).value, 1);
      });
    });

    test('when the body gives itself up', () {
      fakeAsync((async) {
        final section = Completer<void>();
        final body = Completer<void>();
        final cleanup = Completer<void>();
        final job = Engine<int>(timeout: ms(10), (ctx) async {
          ctx.onDispose(() => cleanup.future);
          unawaited(ctx.uncancellable(() => section.future));
          await body.future;
          throw const Cancelled('gave up');
        })
          ..launch();
        async.elapse(ms(10));
        final reason = cancelHeavily(job);
        body.complete();
        async.flushMicrotasks();
        expect(job.isRunning, isTrue, reason: 'the cleanup is running');
        expect(collectedIn(async, reason), isTrue);
        cleanup.complete();
        section.complete();
        async.flushMicrotasks();
        expect('${job.outcome}', 'Cancelled(handler: gave up)');
      });
    });
  });
}
