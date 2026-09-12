@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

final class _Controller<S extends Object> extends Solo<S> {
  final log = <String>[];
  final errors = <Object>[];
  void Function(S state)? changed;

  _Controller(super.initialState);

  void external(S value) => externalSetState(value);

  @override
  void onChange(SoloTransition<S> transition) {
    final current = transition.current;
    log.add('state:$current');
    changed?.call(current);
  }

  @override
  void onFinish(Job<Object?> job) => log.add('finish:${job.key}');

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    if (error is TestFailure) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    errors.add(error);
  }
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
        onError: (state, error, stackTrace) {
          expect(state, 'loading');
          expect(error, same(failure));
          expect(stackTrace, same(trace));
          return 'failure';
        },
        onCancel: (_, __) => fail('unexpected cancellation'),
      )..ignore();
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
        onCancel: (state, cancelled) {
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
            await ctx.wait(() => operation.future);
          } finally {
            solo.log.add('finally');
          }
        },
      )..ignore();
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
        onError: (_, __, ___) => fail('unexpected error'),
        onCancel: (_, __) => fail('unexpected cancellation'),
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
            onCancel: (_, __) => 'initial',
            (ctx) async {
              ctx.emit('loading');
              await ctx.wait(() => operation.future);
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
        onCancel: (_, __) => fail('queued callback'),
      )..cancel();
      expect(first.outcome, isA<Cancelled>());
      solo.run<String, void>(
        (_) async => fail('start rejected'),
        canStart: (_) => false,
        onCancel: (_, __) => fail('rejected callback'),
      );
      solo
          .run<String, void>(
            (_) async => fail('start rule threw'),
            canStart: (_) => throw StateError('start rule'),
            onError: (_, __, ___) => fail('start error callback'),
          )
          .ignore();
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
          onError: (_, __, ___) => fail('revoked error handler'),
          onCancel: (_, __) => fail('revoked cancel handler'),
          (ctx) async {
            ctx
              ..emit('loading')
              ..onDispose(() => cleanup.future);
            await ctx.wait(() => operation.future);
          },
        )..ignore();
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
        onCancel: (state, _) => 'cancelled:$state',
        (ctx) async {
          ctx.onDispose(() => cleanup.future);
          await ctx.wait(() => Completer<void>().future);
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

  test('a forbidden external type suppresses correction', () {
    fakeAsync((clock) {
      final solo = _Controller<Object>('initial');
      final job = solo.run<String, void>(
        onCancel: (_, __) => fail('wrong working type'),
        (ctx) => ctx.wait(() => Completer<void>().future),
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
        onCancel: (_, __) => fail('revoked permission restored'),
        (ctx) async {
          ctx.onDispose(() => cleanup.future);
          await ctx.wait(() => Completer<void>().future);
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
        onCancel: (_, __) => fail('transient disconnect lost'),
        (ctx) async {
          ctx.onDispose(() => cleanup.future);
          await ctx.wait(() => Completer<void>().future);
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
        onError: (state, _, __) {
          expect(state, 42);
          return 'failure';
        },
        (ctx) async {
          ctx.emit(42);
          throw StateError('after transition');
        },
      )..ignore();
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
      late Job<void> child;
      solo.run<String, void>(
        keepWhile: (state) => state != 'disconnected',
        (ctx) {
          child = solo.job<String, void>(
            (ctx) async {
              ctx.onDispose(() => cleanup.future);
              await ctx.wait(() => Completer<void>().future);
            },
            onCancel: (_, __) => fail('parent permission lost'),
          );
          return ctx.run(child);
        },
      ).ignore();
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
        onError: (_, __, ___) => throw correctionFailure,
      )..ignore();
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
        onError: (_, __, ___) => 'failure',
        onCancel: (_, __) => fail('second correction'),
      )..ignore();
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
        onError: (_, __, ___) {
          solo.external('disconnected');
          return 'failure';
        },
      )..ignore();
      clock.flushMicrotasks();
      expect(solo.currentState, 'disconnected');
      expect(job.outcome, isA<Failed>());
    });
  });

  test('close waits for cleanup and applies cancellation state', () {
    _run((solo, clock) {
      final cleanup = Completer<void>();
      solo.run<String, void>(
        onCancel: (_, cancelled) {
          expect(cancelled.reason, isA<ClosedCancelReason>());
          return 'initial';
        },
        (ctx) async {
          ctx
            ..emit('loading')
            ..onDispose(() => cleanup.future);
          await ctx.wait(() => Completer<void>().future);
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
        onCancel: (_, __) => fail('uncertain permission'),
        (ctx) => ctx.wait(() => Completer<void>().future),
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
        onCancel: (_, __) {
          solo.log.add('parent:correction');
          return 'initial';
        },
        (ctx) async {
          child = ctx.each<void>(stream.stream, (ctx, _) async {
            ctx.onDispose(() async {
              await cleanup.future;
              solo.log.add('child:disposed');
            });
            await ctx.wait(() => Completer<void>().future);
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
        'state:initial',
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
        onCancel: (_, __) => fail('finished body lost permission'),
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
            (ctx) => ctx.wait(() => Completer<void>().future),
            onCancel: (_, __) => fail('parent rule cancellation'),
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
    final uncaught = <Object>[];
    final failure = StateError('unobserved');
    runZonedGuarded(
      () {
        _run((solo, clock) {
          solo.run<String, void>(
            (_) async => throw failure,
            onError: (_, __, ___) => 'failure',
          );
          clock.flushMicrotasks();
          expect(solo.currentState, 'failure');
          expect(solo.errors, [failure]);
        });
      },
      (error, _) => uncaught.add(error),
    );
    expect(uncaught, [failure]);
  });

  test('observer changes a parent predicate without replacing state again', () {
    _run((solo, clock) {
      var allowed = true;
      solo.changed = (_) => allowed = false;
      final parent = solo.run<String, void>(
        keepWhile: (_) => allowed,
        (ctx) => ctx.run(
          solo.job<String, void>(
            (ctx) => ctx.wait(() => Completer<void>().future),
            onCancel: (_, __) => fail('parent permission revoked'),
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
                await ctx.wait(() => startGrandchild.future);
                try {
                  await ctx.run(
                    solo.job<String, void>(
                      (_) async => throw StateError('grandchild'),
                      onError: (_, __, ___) {
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
        onCancel: (_, __) => fail('uncertain permission'),
        (ctx) => ctx.wait(() => Completer<void>().future),
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
                (ctx) => ctx.wait(() => finishChild.future),
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
}
