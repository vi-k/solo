@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:meta/meta.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/test_solo.dart';

final class _Controller<S extends Object> extends Solo<S> with OpenSolo<S> {
  final log = <String>[];
  final errors = <Object>[];
  final unanswered = <Object>[];
  void Function(S state)? changed;
  void Function(Job<Object?> job)? started;

  _Controller(super.initialState);

  void external(S value) => externalSetState(value);

  @override
  void onChange(SoloTransition<S> transition) {
    final current = transition.current;
    log.add('state:$current');
    changed?.call(current);
  }

  @override
  void onStart(Job<Object?> job) => started?.call(job);

  @override
  void onFinish(Job<Object?> job) => log.add('finish:${job.key}');

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    if (error is TestFailure) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    errors.add(error);
  }

  // A recorder of a test: it reads the errors and answers for them here,
  // so nothing reaches the handler or the zone.
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      unanswered.add(error);
}

void _run(void Function(_Controller<String> solo, FakeAsync clock) body) {
  fakeAsync((clock) {
    final solo = _Controller('initial');
    try {
      body(solo, clock);
    } finally {
      solo.close();
      clock.flushMicrotasks();
    }
  });
}

void main() {
  test('an error corrects state and preserves its outcome and stack', () {
    _run((solo, clock) {
      final failure = StateError('request failed');
      final trace = StackTrace.current;
      final job = solo.run<String, String>(
        (ctx) async {
          ctx.emit('loading');
          Error.throwWithStackTrace(failure, trace);
        },
        ifFailed: (state, error, stackTrace) {
          expect(state, 'loading');
          expect(error, same(failure));
          expect(stackTrace, same(trace));
          return 'failure';
        },
        ifCancelled: (_, __) => fail('unexpected cancellation'),
      )..ignoreFailure();
      clock.flushMicrotasks();
      expect(solo.currentState, 'failure');
      expect(
        job.outcome,
        isA<Failed>().having((o) => o.error, 'error', same(failure)),
      );
      expect(solo.errors, [failure]);
    });
  });

  test('cancel signal precedes finally, cleanup and state correction', () {
    _run((solo, clock) {
      final operation = Completer<void>();
      final cleanup = Completer<void>();
      final job = solo.run<String, void>(
        key: 'first',
        ifCancelled: (state, cancelled) {
          expect(cancelled.reason, isA<ManualCancelReason>());
          solo.log.add('correction');
          return 'initial';
        },
        (ctx) async {
          ctx
            ..emit('loading')
            ..onCancel(() => solo.log.add('signal'))
            ..onDispose(() async {
              solo.log.add('dispose:start');
              await cleanup.future;
              solo.log.add('dispose:end');
            });
          try {
            await ctx.abandonable(() => operation.future);
          } finally {
            solo.log.add('finally');
          }
        },
      )..ignoreFailure();
      solo.run<String, void>(key: 'next', (ctx) async {
        solo.log.add('next:${ctx.state}');
      });
      clock.flushMicrotasks();
      job.cancel();
      clock.flushMicrotasks();
      expect(solo.log, [
        'state:loading',
        'signal',
        'finally',
        'dispose:start',
      ]);
      cleanup.complete();
      clock.flushMicrotasks();
      expect(solo.log, [
        'state:loading',
        'signal',
        'finally',
        'dispose:start',
        'dispose:end',
        'correction',
        'state:initial',
        'finish:first',
        'next:initial',
        'finish:next',
      ]);
      expect(job.outcome, isA<Cancelled>());
      operation.complete();
      clock.flushMicrotasks();
    });
  });

  test('success never calls either correction handler', () {
    _run((solo, clock) {
      final job = solo.run<String, int>(
        (ctx) async {
          ctx.emit('loaded');
          return 42;
        },
        ifFailed: (_, __, ___) => fail('unexpected error'),
        ifCancelled: (_, __) => fail('unexpected cancellation'),
      );
      clock.flushMicrotasks();
      expect(solo.currentState, 'loaded');
      expect(job.outcome, isA<Done<int>>().having((o) => o.value, 'value', 42));
    });
  });

  test('droppable skips correction on a duplicate of a running job', () {
    _run((solo, clock) {
      final operation = Completer<void>();
      SoloJob<void> load() => solo.run<String, void>(
            key: 'load',
            policy: Policy.droppable,
            ifCancelled: (_, __) => 'initial',
            (ctx) async {
              ctx.emit('loading');
              await ctx.abandonable(() => operation.future);
              ctx.emit('loaded');
            },
          );
      final first = load();
      clock.flushMicrotasks();
      expect(load(), same(first));
      expect(solo.currentState, 'loading');
      operation.complete();
      clock.flushMicrotasks();
      expect(solo.currentState, 'loaded');
    });
  });

  test('queued cancellation and rejected start skip both handlers', () {
    _run((solo, clock) {
      final first = solo.run<String, void>(
        (_) async => fail('cancelled before start'),
        ifCancelled: (_, __) => fail('queued callback'),
      )..cancel();
      expect(first.outcome, isA<Cancelled>());
      solo.run<String, void>(
        (_) async => fail('start rejected'),
        canStart: (_) => false,
        ifCancelled: (_, __) => fail('rejected callback'),
      );
      solo
          .run<String, void>(
            (_) async => fail('start rule threw'),
            canStart: (_) => throw StateError('start rule'),
            ifFailed: (_, __, ___) => fail('start error callback'),
          )
          .ignoreFailure();
      clock.flushMicrotasks();
      expect(solo.currentState, 'initial');
      expect(solo.errors, hasLength(1));
    });
  });

  for (final failBody in [false, true]) {
    test(
        'external disconnect during cleanup after '
        '${failBody ? 'failure' : 'manual cancellation'}', () {
      _run((solo, clock) {
        final operation = Completer<void>();
        final cleanup = Completer<void>();
        final job = solo.run<String, void>(
          keepWhile: (state) => state != 'disconnected',
          ifFailed: (_, __, ___) => fail('revoked error handler'),
          ifCancelled: (_, __) => fail('revoked cancel handler'),
          (ctx) async {
            ctx
              ..emit('loading')
              ..onDispose(() => cleanup.future);
            await ctx.abandonable(() => operation.future);
          },
        )..ignoreFailure();
        clock.flushMicrotasks();
        if (failBody) {
          operation.completeError(StateError('request failed'));
        } else {
          job.cancel();
        }
        clock.flushMicrotasks();
        solo.external('disconnected');
        cleanup.complete();
        clock.flushMicrotasks();
        expect(solo.currentState, 'disconnected');
        expect(job.outcome, failBody ? isA<Failed>() : isA<Cancelled>());
        if (!failBody) operation.complete();
      });
    });
  }

  test('a compatible external state is passed to the cancellation handler', () {
    _run((solo, clock) {
      final cleanup = Completer<void>();
      final job = solo.run<String, void>(
        keepWhile: (state) => state != 'disconnected',
        ifCancelled: (state, _) => 'cancelled:$state',
        (ctx) async {
          ctx.onDispose(() => cleanup.future);
          await ctx.abandonable(() => Completer<void>().future);
        },
      );
      clock.flushMicrotasks();
      job.cancel();
      clock.flushMicrotasks();
      solo.external('connected');
      cleanup.complete();
      clock.flushMicrotasks();
      expect(solo.currentState, 'cancelled:connected');
    });
  });

  test('a manual cancellation with the reason of the rules keeps correction',
      () {
    _run((solo, clock) {
      final job = solo.run<String, void>(
        ifCancelled: (_, __) => 'cancelled',
        (ctx) => ctx.abandonable(() => Completer<void>().future),
      );
      clock.flushMicrotasks();
      job.cancel(reason: const RulesCancelReason());
      clock.flushMicrotasks();
      expect(solo.currentState, 'cancelled');
    });
  });

  test('rules turning a checkpoint down suppress correction', () {
    _run((solo, clock) {
      var allowed = true;
      final gate = Completer<void>();
      final job = solo.run<String, void>(
        keepWhile: (_) => allowed,
        ifCancelled: (_, __) => 'corrected',
        (ctx) async {
          await gate.future;
          ctx.state;
        },
      );
      clock.flushMicrotasks();
      allowed = false;
      gate.complete();
      clock.flushMicrotasks();
      expect(
        job.outcome,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<RulesCancelReason>(),
        ),
      );
      expect(solo.currentState, 'initial');
    });
  });

  test('a stateAs that does not match suppresses correction', () {
    fakeAsync((clock) {
      final solo = _Controller<Object>('initial');
      final gate = Completer<void>();
      final job = solo.run<Object, void>(
        ifCancelled: (_, __) => 'corrected',
        (ctx) async {
          await gate.future;
          ctx.stateAs<int>();
        },
      );
      clock.flushMicrotasks();
      gate.complete();
      clock.flushMicrotasks();
      expect(
        job.outcome,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<RulesCancelReason>(),
        ),
      );
      expect(solo.currentState, 'initial');
      solo.close();
      clock.flushMicrotasks();
    });
  });

  test('a forbidden external type suppresses correction', () {
    fakeAsync((clock) {
      final solo = _Controller<Object>('initial');
      final job = solo.run<String, void>(
        ifCancelled: (_, __) => fail('wrong working type'),
        (ctx) => ctx.abandonable(() => Completer<void>().future),
      );
      clock.flushMicrotasks();
      solo.external(42);
      clock.flushMicrotasks();
      expect(solo.currentState, 42);
      expect(job.outcome, isA<Cancelled>());
      solo.close();
      clock.flushMicrotasks();
    });
  });

  test('returning to a compatible state does not restore correction', () {
    _run((solo, clock) {
      final cleanup = Completer<void>();
      solo.run<String, void>(
        keepWhile: (state) => state != 'disconnected',
        ifCancelled: (_, __) => fail('revoked permission restored'),
        (ctx) async {
          ctx.onDispose(() => cleanup.future);
          await ctx.abandonable(() => Completer<void>().future);
        },
      );
      clock.flushMicrotasks();
      solo
        ..external('disconnected')
        ..external('reconnected');
      clock.flushMicrotasks();
      cleanup.complete();
      clock.flushMicrotasks();
      expect(solo.currentState, 'reconnected');
    });
  });

  test('an observer cannot hide a forbidden external transition', () {
    _run((solo, clock) {
      final cleanup = Completer<void>();
      final job = solo.run<String, void>(
        keepWhile: (state) => state != 'disconnected',
        ifCancelled: (_, __) => fail('transient disconnect lost'),
        (ctx) async {
          ctx.onDispose(() => cleanup.future);
          await ctx.abandonable(() => Completer<void>().future);
        },
      );
      clock.flushMicrotasks();
      job.cancel();
      clock.flushMicrotasks();
      solo.changed = (state) {
        if (state == 'disconnected') solo.external('reconnected');
      };
      solo.external('disconnected');
      cleanup.complete();
      clock.flushMicrotasks();
      expect(solo.currentState, 'reconnected');
    });
  });

  test('canStart is not repeated and own emit does not revoke correction', () {
    fakeAsync((clock) {
      final solo = _Controller<Object>('initial');
      var starts = 0;
      final job = solo.run<String, void>(
        canStart: (_) => ++starts == 1,
        ifFailed: (state, _, __) {
          expect(state, 42);
          return 'failure';
        },
        (ctx) async {
          ctx.emit(42);
          throw StateError('after transition');
        },
      )..ignoreFailure();
      clock.flushMicrotasks();
      expect(starts, 1);
      expect(solo.currentState, 'failure');
      expect(job.outcome, isA<Failed>());
      solo.close();
      clock.flushMicrotasks();
    });
  });

  test('a child inherits correction revocation from a waiting parent', () {
    _run((solo, clock) {
      final cleanup = Completer<void>();
      late SoloJob<void> child;
      solo.run<String, void>(
        keepWhile: (state) => state != 'disconnected',
        (ctx) {
          child = solo.job<String, void>(
            (ctx) async {
              ctx.onDispose(() => cleanup.future);
              await ctx.abandonable(() => Completer<void>().future);
            },
            ifCancelled: (_, __) => fail('parent permission lost'),
          );
          return ctx.run(child);
        },
      ).ignoreFailure();
      clock.flushMicrotasks();
      child.cancel();
      clock.flushMicrotasks();
      solo.external('disconnected');
      cleanup.complete();
      clock.flushMicrotasks();
      expect(solo.currentState, 'disconnected');
    });
  });

  test('a correction handler failure preserves the original outcome', () {
    _run((solo, clock) {
      final failure = StateError('body');
      final correctionFailure = StateError('correction');
      final job = solo.run<String, void>(
        (_) async => throw failure,
        ifFailed: (_, __, ___) => throw correctionFailure,
      )..ignoreFailure();
      solo.run<String, void>((ctx) async => ctx.emit('next'));
      clock.flushMicrotasks();
      expect(
        job.outcome,
        isA<Failed>().having((o) => o.error, 'error', same(failure)),
      );
      expect(solo.errors, [failure, correctionFailure]);
      expect(solo.currentState, 'next');
    });
  });

  test('cancel during correction publication cannot replace a fixed failure',
      () {
    _run((solo, clock) {
      late Job<void> job;
      solo.changed = (state) {
        if (state == 'failure') job.cancel();
      };
      job = solo.run<String, void>(
        (_) async => throw StateError('body'),
        ifFailed: (_, __, ___) => 'failure',
        ifCancelled: (_, __) => fail('second correction'),
      )..ignoreFailure();
      clock.flushMicrotasks();
      expect(job.outcome, isA<Failed>());
      expect(solo.currentState, 'failure');
    });
  });

  test('external disconnect inside a handler prevents its returned write', () {
    _run((solo, clock) {
      final job = solo.run<String, void>(
        (_) async => throw StateError('body'),
        keepWhile: (state) => state != 'disconnected',
        ifFailed: (_, __, ___) {
          solo.external('disconnected');
          return 'failure';
        },
      )..ignoreFailure();
      clock.flushMicrotasks();
      expect(solo.currentState, 'disconnected');
      expect(job.outcome, isA<Failed>());
    });
  });

  test('close waits for cleanup and applies cancellation state', () {
    _run((solo, clock) {
      final cleanup = Completer<void>();
      solo.run<String, void>(
        ifCancelled: (_, cancelled) {
          expect(cancelled.reason, isA<ClosedCancelReason>());
          return 'initial';
        },
        (ctx) async {
          ctx
            ..emit('loading')
            ..onDispose(() => cleanup.future);
          await ctx.abandonable(() => Completer<void>().future);
        },
      );
      clock.flushMicrotasks();
      var closed = false;
      solo.close().then((_) => closed = true);
      clock.flushMicrotasks();
      expect(closed, isFalse);
      cleanup.complete();
      clock.flushMicrotasks();
      expect(closed, isTrue);
      expect(solo.currentState, 'initial');
    });
  });
  test('a throwing external rule is reported once and blocks correction', () {
    _run((solo, clock) {
      final ruleError = StateError('rule');
      var shouldThrow = false;
      final job = solo.run<String, void>(
        keepWhile: (_) {
          if (shouldThrow) throw ruleError;
          return true;
        },
        ifCancelled: (_, __) => fail('uncertain permission'),
        (ctx) => ctx.abandonable(() => Completer<void>().future),
      );
      clock.flushMicrotasks();
      shouldThrow = true;
      solo.external('changed');
      expect(solo.errors, [ruleError]);
      job.cancel();
      clock.flushMicrotasks();
      expect(solo.currentState, 'changed');
    });
  });

  test('a finished parent body waits for child cleanup before correction', () {
    _run((solo, clock) {
      final stream = StreamController<void>(sync: true);
      final cleanup = Completer<void>();
      late Job<void> child;
      final parent = solo.run<String, void>(
        key: 'parent',
        ifCancelled: (_, __) {
          solo.log.add('parent:correction');
          return 'cancelled';
        },
        (ctx) async {
          child = ctx.each<void>(stream.stream, (ctx, _) async {
            ctx.onDispose(() async {
              await cleanup.future;
              solo.log.add('child:disposed');
            });
            await ctx.abandonable(() => Completer<void>().future);
          });
        },
      );
      clock.flushMicrotasks();
      stream.add(null);
      clock.flushMicrotasks();
      parent.cancel();
      clock.flushMicrotasks();
      expect(parent.isFinished, isFalse);
      expect(child.isFinished, isFalse);
      expect(solo.log, isEmpty);
      cleanup.complete();
      clock.flushMicrotasks();
      expect(solo.log, [
        'child:disposed',
        'finish:null',
        'parent:correction',
        'state:cancelled',
        'finish:parent',
      ]);
      stream.close();
      clock.flushMicrotasks();
    });
  });

  test('a body that returned still loses correction rights during child wait',
      () {
    _run((solo, clock) {
      final stream = StreamController<void>();
      final parent = solo.run<String, void>(
        keepWhile: (state) => state != 'disconnected',
        ifCancelled: (_, __) => fail('finished body lost permission'),
        (ctx) async {
          ctx.each<void>(stream.stream, (_, __) {});
        },
      );
      clock.flushMicrotasks();
      solo.external('disconnected');
      parent.cancel();
      clock.flushMicrotasks();
      expect(solo.currentState, 'disconnected');
      expect(parent.outcome, isA<Cancelled>());
      stream.close();
      clock.flushMicrotasks();
    });
  });

  test('parent rule cancellation suppresses a compatible child handler', () {
    _run((solo, clock) {
      final parent = solo.run<String, void>(
        keepWhile: (state) => state != 'disconnected',
        (ctx) => ctx.run(
          solo.job<String, void>(
            (ctx) => ctx.abandonable(() => Completer<void>().future),
            ifCancelled: (_, __) => fail('parent rule cancellation'),
          ),
        ),
      );
      clock.flushMicrotasks();
      solo.external('disconnected');
      clock.flushMicrotasks();
      expect(solo.currentState, 'disconnected');
      expect(parent.outcome, isA<Cancelled>());
    });
  });

  test('an error handler does not observe a failed job for its caller', () {
    _run((solo, clock) {
      final failure = StateError('unobserved');
      solo.run<String, void>(
        (_) async => throw failure,
        ifFailed: (_, __, ___) => 'failure',
      );
      clock.flushMicrotasks();
      expect(solo.currentState, 'failure');
      expect(solo.errors, [failure]);
      expect(solo.unanswered, [failure]);
    });
  });

  test('observer changes a parent predicate without replacing state again', () {
    _run((solo, clock) {
      var allowed = true;
      solo.changed = (_) => allowed = false;
      final parent = solo.run<String, void>(
        keepWhile: (_) => allowed,
        (ctx) => ctx.run(
          solo.job<String, void>(
            (ctx) => ctx.abandonable(() => Completer<void>().future),
            ifCancelled: (_, __) => fail('parent permission revoked'),
          ),
        ),
      );
      clock.flushMicrotasks();
      solo.external('changed');
      clock.flushMicrotasks();
      expect(parent.outcome, isA<Cancelled>());
      expect(solo.currentState, 'changed');
    });
  });

  test('a later descendant uses its rules after an ordinary parent body', () {
    _run((solo, clock) {
      final startGrandchild = Completer<void>();
      var corrections = 0;
      final parent = solo.run<String, void>(
        keepWhile: (state) => state != 'disconnected',
        (ctx) async {
          unawaited(
            ctx.run(
              solo.job<String, void>((ctx) async {
                await ctx.abandonable(() => startGrandchild.future);
                try {
                  await ctx.run(
                    solo.job<String, void>(
                      (_) async => throw StateError('grandchild'),
                      ifFailed: (_, __, ___) {
                        corrections++;
                        return 'failure';
                      },
                    ),
                  );
                } on Object {
                  // The child observes its failed descendant.
                }
              }),
            ),
          );
        },
      );
      clock.flushMicrotasks();
      solo
        ..external('disconnected')
        ..external('reconnected');
      startGrandchild.complete();
      clock.flushMicrotasks();
      expect(corrections, 1);
      expect(solo.currentState, 'failure');
      expect(parent.outcome, isA<Done<void>>());
    });
  });

  test('fresh errors from the same transition produce one diagnostic', () {
    _run((solo, clock) {
      final job = solo.run<String, void>(
        keepWhile: (state) {
          if (state == 'changed') throw StateError('rule');
          return true;
        },
        ifCancelled: (_, __) => fail('uncertain permission'),
        (ctx) => ctx.abandonable(() => Completer<void>().future),
      );
      clock.flushMicrotasks();
      solo.external('changed');
      expect(solo.errors, hasLength(1));
      job.cancel();
      clock.flushMicrotasks();
      expect(solo.currentState, 'changed');
    });
  });
  test('an ordinary parent does not check rules after its body returns', () {
    _run((solo, clock) {
      final finishChild = Completer<void>();
      var checks = 0;
      late Job<void> parent;
      parent = solo.run<String, void>(
        keepWhile: (state) {
          checks++;
          if (state == 'changed') {
            parent.cancel();
            throw StateError('unexpected late rule');
          }
          return true;
        },
        (ctx) async {
          unawaited(
            ctx.run(
              solo.job<String, void>(
                (ctx) => ctx.abandonable(() => finishChild.future),
              ),
            ),
          );
        },
      );
      clock.flushMicrotasks();
      final checksBeforeChange = checks;
      solo.external('changed');
      clock.flushMicrotasks();
      expect(checks, checksBeforeChange);
      expect(solo.errors, isEmpty);
      expect(parent.isCancelled, isFalse);
      expect(parent.isFinished, isFalse);
      finishChild.complete();
      clock.flushMicrotasks();
      expect(parent.outcome, isA<Done<void>>());
    });
  });

  group('a handler that returns the state it was given', () {
    test('publishes nothing after a cancellation or a failure', () {
      _run((solo, clock) {
        var notified = 0;
        solo.addListener(() => notified++);
        final cancelled = solo.run<String, void>(
          ifCancelled: (state, _) => state,
          (ctx) => ctx.abandonable(() => Completer<void>().future),
        );
        clock.flushMicrotasks();
        cancelled.cancel();
        clock.flushMicrotasks();
        solo
            .run<String, void>(
              (_) async => throw StateError('body'),
              ifFailed: (state, _, __) => state,
            )
            .ignoreFailure();
        clock.flushMicrotasks();
        expect(solo.currentState, 'initial');
        expect(notified, 0, reason: 'listeners hear no change');
        expect(solo.log.where((line) => line.startsWith('state:')), isEmpty);
      });
    });

    test('leaves a write made from inside it in place', () {
      _run((solo, clock) {
        solo.run<String, void>(
          (_) async => throw StateError('body'),
          ifFailed: (state, _, __) {
            solo.external('offline');
            return state;
          },
        ).ignoreFailure();
        clock.flushMicrotasks();
        expect(
          solo.currentState,
          'offline',
          reason: 'the state it was given is not written back over it',
        );
      });
    });

    test('and a const the state already holds is that same object', () {
      fakeAsync((clock) {
        final solo = _Controller<_Box>(const _Box(1));
        var notified = 0;
        solo.addListener(() => notified++);
        solo
            .run<_Box, void>(
              (_) async => throw StateError('body'),
              ifFailed: (_, __, ___) => const _Box(1),
            )
            .ignoreFailure();
        clock.flushMicrotasks();
        expect(notified, 0);
        solo.close();
        clock.flushMicrotasks();
      });
    });

    test('and an equal state that is another object is published', () {
      fakeAsync((clock) {
        final solo = _Controller<_Box>(const _Box(1));
        var notified = 0;
        solo.addListener(() => notified++);
        solo
            .run<_Box, void>(
              (_) async => throw StateError('body'),
              ifFailed: (state, _, __) => _Box(state.value),
            )
            .ignoreFailure();
        clock.flushMicrotasks();
        expect(notified, 1);
        solo.close();
        clock.flushMicrotasks();
      });
    });
  });

  group('an accumulator', () {
    test('runs ifCancelled once for a cancelled group of three events', () {
      _run((solo, clock) {
        final calls = <List<int>>[];
        final events = solo.collect<String, int, void>(
          ifFailed: (_, __, ___) => fail('unexpected failure'),
          ifCancelled: (state, cancelled) => 'cancelled:$state',
          (ctx, batch) async {
            calls.add(batch);
            ctx.emit('sending:${batch.length}');
            await ctx.abandonable(() => Completer<void>().future);
          },
        );
        final job = events.add(1);
        events
          ..add(2)
          ..add(3);
        clock.flushMicrotasks();
        expect(calls, [
          [1, 2, 3],
        ]);
        job.cancel();
        clock.flushMicrotasks();
        expect(job.outcome, isA<Cancelled>());
        expect(solo.currentState, 'cancelled:sending:3');
        expect(solo.log.where((entry) => entry.startsWith('state:')), [
          'state:sending:3',
          'state:cancelled:sending:3',
        ]);
      });
    });

    test('runs ifFailed for a failed group and keeps the failure', () {
      _run((solo, clock) {
        final failure = StateError('upload failed');
        final job = solo
            .collect<String, int, void>(
              ifFailed: (state, error, _) {
                expect(error, same(failure));
                return 'failed:$state';
              },
              ifCancelled: (_, __) => fail('unexpected cancellation'),
              (ctx, batch) async {
                ctx.emit('sending:${batch.length}');
                throw failure;
              },
            )
            .add(1)
          ..ignoreFailure();
        clock.flushMicrotasks();
        expect(solo.currentState, 'failed:sending:1');
        expect(job.outcome, isA<Failed>());
        expect(job.value, throwsA(same(failure)));
        clock.flushMicrotasks();
      });
    });

    test('runs ifCancelled when close() cancels a running group', () {
      _run((solo, clock) {
        Cancelled? seen;
        final job = solo.collect<String, int, void>(
          ifCancelled: (_, cancelled) {
            seen = cancelled;
            return 'waiting';
          },
          (ctx, batch) async {
            ctx.emit('-99');
            await ctx.abandonable(() => Completer<void>().future);
          },
        ).add(1);
        clock.flushMicrotasks();
        expect(solo.currentState, '-99');
        solo.close();
        clock.flushMicrotasks();
        expect(job.outcome, isA<Cancelled>());
        expect(seen?.reason, isA<ClosedCancelReason>());
        expect(solo.currentState, 'waiting');
      });
    });

    test('passes a timeout to ifCancelled', () {
      _run((solo, clock) {
        Cancelled? seen;
        final job = solo.collect<String, int, void>(
          timeout: const Duration(seconds: 1),
          ifCancelled: (_, cancelled) {
            seen = cancelled;
            return 'timed out';
          },
          (ctx, batch) => ctx.abandonable(() => Completer<void>().future),
        ).add(1);
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 1));
        expect(job.outcome, isA<Cancelled>());
        expect(seen?.reason, isA<TimeoutCancelReason>());
        expect(solo.currentState, 'timed out');
      });
    });

    test('skips both handlers for a group removed before it started', () {
      _run((solo, clock) {
        final events = solo.collect<String, int, void>(
          timing: AccumulationTiming.debounce(
            const Duration(milliseconds: 200),
          ),
          ifFailed: (_, __, ___) => fail('failure callback'),
          ifCancelled: (_, __) => fail('cancellation callback'),
          (_, __) async => fail('started'),
        );
        final cancelled = events.add(1)..cancel();
        clock.flushMicrotasks();
        expect(cancelled.outcome, isA<Cancelled>());
        final closed = events.add(2);
        clock.flushMicrotasks();
        solo.close();
        clock.flushMicrotasks();
        expect(closed.outcome, isA<Cancelled>());
        final late = events.add(3);
        clock.flushMicrotasks();
        expect(late.outcome, isA<Cancelled>());
        expect(solo.currentState, 'initial');
      });
    });

    test('skips both handlers for a group keepWhile cancelled', () {
      _run((solo, clock) {
        final job = solo
            .collect<String, int, void>(
              keepWhile: (state) => state != 'disconnected',
              ifFailed: (_, __, ___) => fail('failure callback'),
              ifCancelled: (_, __) => fail('cancellation callback'),
              (ctx, batch) => ctx.abandonable(() => Completer<void>().future),
            )
            .add(1);
        clock.flushMicrotasks();
        solo.external('disconnected');
        clock.flushMicrotasks();
        expect(job.outcome, isA<Cancelled>());
        expect(solo.currentState, 'disconnected');
      });
    });

    test('runs ifCancelled for a cancellation in onStart', () {
      _run((solo, clock) {
        final seen = <String>[];
        solo.started = (job) => job.cancel();
        final job = solo.collect<String, int, void>(
          ifCancelled: (_, cancelled) {
            seen.add('ifCancelled ${cancelled.reason}');
            return 'cancelled';
          },
          (_, __) async => seen.add('handler'),
        ).add(1);
        clock.flushMicrotasks();
        expect(job.outcome, isA<Cancelled>());
        expect(seen, ['ifCancelled manual']);
        expect(solo.currentState, 'cancelled');
      });
    });

    test('skips both handlers for a canStart refusal and a cleared queue', () {
      _run((solo, clock) {
        final refused = solo
            .collect<String, int, void>(
              canStart: (_) => false,
              ifFailed: (_, __, ___) => fail('failure callback'),
              ifCancelled: (_, __) => fail('cancellation callback'),
              (_, __) async => fail('started'),
            )
            .add(1);
        clock.flushMicrotasks();
        expect(refused.outcome, isA<Cancelled>());
        final cleared = solo
            .collect<String, int, void>(
              timing: AccumulationTiming.debounce(
                const Duration(milliseconds: 200),
              ),
              ifFailed: (_, __, ___) => fail('failure callback'),
              ifCancelled: (_, __) => fail('cancellation callback'),
              (_, __) async => fail('started'),
            )
            .add(1);
        clock.flushMicrotasks();
        solo.queue.clear();
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 200));
        expect(cleared.outcome, isA<Cancelled>());
        expect(solo.currentState, 'initial');
      });
    });

    test('runs ifCancelled when a restart of its key replaces the group', () {
      _run((solo, clock) {
        Cancelled? seen;
        final group = solo.collect<String, int, void>(
          key: 'upload',
          ifCancelled: (state, cancelled) {
            seen = cancelled;
            return state;
          },
          (ctx, _) => ctx.abandonable(() => Completer<void>().future),
        ).add(1);
        clock.flushMicrotasks();
        solo.run<String, void>(
          key: 'upload',
          policy: Policy.restart,
          (ctx) async => ctx.emit('restarted'),
        );
        clock.flushMicrotasks();
        expect(group.outcome, isA<Cancelled>());
        expect(seen?.reason, isA<ReplacedCancelReason>());
        expect(solo.currentState, 'restarted');
      });
    });

    test('runs ifFailed for a group a draining close waits for', () {
      _run((solo, clock) {
        final job = solo
            .collect<String, int, void>(
              timing: AccumulationTiming.debounce(
                const Duration(milliseconds: 200),
              ),
              ifFailed: (_, error, __) => 'failed:$error',
              (_, __) async => throw StateError('offline'),
            )
            .add(1)
          ..ignoreFailure();
        clock.flushMicrotasks();
        solo.close(mode: SoloCloseMode.drain).ignore();
        clock.elapse(const Duration(milliseconds: 200));
        expect(job.outcome, isA<Failed>());
        expect(solo.currentState, 'failed:Bad state: offline');
      });
    });

    test('accumulate passes both handlers on', () {
      _run((solo, clock) {
        final values = solo.accumulate<String, int, void>(
          merge: (accumulated, incoming) => accumulated + incoming,
          ifFailed: (state, error, _) => 'failed:$error',
          ifCancelled: (state, _) => 'cancelled',
          (ctx, sum) async {
            if (sum > 2) throw StateError('$sum');
            await ctx.abandonable(() => Completer<void>().future);
          },
        );
        final failed = values.add(1);
        values.add(2);
        failed.ignoreFailure();
        clock.flushMicrotasks();
        expect(solo.currentState, 'failed:Bad state: 3');
        final cancelled = values.add(1);
        clock.flushMicrotasks();
        cancelled.cancel();
        clock.flushMicrotasks();
        expect(solo.currentState, 'cancelled');
      });
    });

    test('moves a group under replace without a handler call', () {
      _run((solo, clock) {
        final gate = Completer<void>();
        final seen = <String>[];
        solo.run<String, void>((_) => gate.future);
        final events = solo.collect<String, int, void>(
          policy: AccumulationPolicy.replace,
          ifFailed: (_, __, ___) => fail('failure callback'),
          ifCancelled: (_, __) {
            seen.add('ifCancelled');
            return 'cancelled';
          },
          (ctx, batch) async {
            seen.add('handler $batch');
            ctx.emit('sending:${batch.length}');
            await ctx.abandonable(() => Completer<void>().future);
          },
        );
        final group = events.add(1);
        solo.run<String, void>((_) async => seen.add('between'));
        expect(events.add(2), same(group));
        clock.flushMicrotasks();
        expect(seen, isEmpty);
        gate.complete();
        clock.flushMicrotasks();
        expect(seen, ['between', 'handler [1, 2]']);
        group.cancel();
        clock.flushMicrotasks();
        expect(seen, ['between', 'handler [1, 2]', 'ifCancelled']);
        expect(solo.currentState, 'cancelled');
      });
    });

    test('calls neither handler for a group that turns cancellation down', () {
      _run((solo, clock) {
        final gate = Completer<void>();
        final job = solo.collect<String, int, void>(
          cancellable: false,
          ifFailed: (_, __, ___) => fail('failure callback'),
          ifCancelled: (_, __) => fail('cancellation callback'),
          (ctx, _) async {
            ctx.emit('sending');
            await gate.future;
          },
        ).add(1);
        clock.flushMicrotasks();
        job.cancel();
        solo.close().ignore();
        clock.flushMicrotasks();
        expect(job.isFinished, isFalse);
        gate.complete();
        clock.flushMicrotasks();
        expect(job.outcome, isA<Done<void>>());
        expect(solo.currentState, 'sending');
      });
    });
  });
}

@immutable
final class _Box {
  final int value;

  const _Box(this.value);

  @override
  bool operator ==(Object other) => other is _Box && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
