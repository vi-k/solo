@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/test_solo.dart';
import 'support/test_state.dart';

void main() {
  test('a homeless error with no observer reaches the zone', () {
    final caught = <String>[];
    fakeAsync((async) {
      final solo = TestSolo();
      _inZone(caught, () {
        solo.run<TestState, void>(key: 'j', (ctx) async {
          ctx.unattended(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            throw StateError('abandoned boom');
          });
        });
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(caught, ['Bad state: abandoned boom']);
  });

  test("the body's failure does not reach the zone twice", () {
    final caught = <String>[];
    Outcome<void>? outcome;
    fakeAsync((async) {
      final solo = TestSolo();
      _inZone(caught, () {
        final job = solo.run<TestState, void>(
          key: 'j',
          (ctx) async => throw StateError('body boom'),
        );
        Future<void> watch() async => outcome = await job.done;
        unawaited(watch());
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(outcome, isA<Failed>());
    expect(caught, isEmpty);
  });

  test('a global observer switches the default route off', () {
    final caught = <String>[];
    SoloBase.observer = _Silent();
    try {
      fakeAsync((async) {
        final solo = TestSolo();
        _inZone(caught, () {
          solo.run<TestState, void>(key: 'j', (ctx) async {
            ctx.unattended(() async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              throw StateError('abandoned boom');
            });
          });
        });
        async.flushTimers();
        solo.close();
        async.flushTimers();
      });
    } finally {
      SoloBase.observer = null;
    }
    expect(caught, isEmpty);
  });

  test('an override without super keeps the error out of the zone', () {
    final caught = <String>[];
    final solo = _Quiet();
    fakeAsync((async) {
      _inZone(caught, () {
        solo.run<TestState, void>(key: 'j', (ctx) async {
          ctx.unattended(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            throw StateError('abandoned boom');
          });
        });
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(caught, isEmpty);
    expect(solo.errors, ['Bad state: abandoned boom']);
  });

  test('an override calling super still hands it to the zone', () {
    final caught = <String>[];
    final solo = _Loud();
    fakeAsync((async) {
      _inZone(caught, () {
        solo.run<TestState, void>(key: 'j', (ctx) async {
          ctx.unattended(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            throw StateError('abandoned boom');
          });
        });
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(caught, ['Bad state: abandoned boom']);
    expect(solo.errors, ['Bad state: abandoned boom']);
  });

  test('a rule that throws reaches the zone', () {
    final caught = <String>[];
    fakeAsync((async) {
      final solo = TestSolo();
      _inZone(caught, () {
        solo.run<TestState, void>(
          key: 'j',
          keepWhile: (state) {
            if (state is Working) {
              throw StateError('rule boom');
            }
            return true;
          },
          (ctx) async {
            await ctx.wait(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
          },
        );
      });
      async.elapse(const Duration(milliseconds: 5));
      solo.externalSetState(const Working());
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(caught, ['Bad state: rule boom']);
  });

  test('a reentrant notification does not lose the outer error', () {
    final caught = <String>[];
    final solo = _Reentrant();
    fakeAsync((async) {
      _inZone(caught, () {
        solo
          ..run<TestState, void>(key: 'j', (ctx) async {
            ctx.unattended(() async {
              await Future<void>.delayed(const Duration(milliseconds: 30));
              throw StateError('outer boom');
            });
          })
          ..run<TestState, void>(
            key: 'k',
            keepWhile: (state) {
              if (state is Working) {
                throw StateError('inner boom');
              }
              return true;
            },
            (ctx) async {
              await ctx.wait(
                () => Future<void>.delayed(const Duration(milliseconds: 100)),
              );
            },
          );
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(caught, ['Bad state: inner boom', 'Bad state: outer boom']);
  });

  test('a disposer that throws reaches the zone', () {
    final caught = <String>[];
    fakeAsync((async) {
      final solo = TestSolo();
      _inZone(caught, () {
        solo.run<TestState, void>(key: 'j', (ctx) async {
          ctx.onDispose(() => throw StateError('cleanup boom'));
        });
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    // The commonest case of the widened route, and the one the README
    // paragraph about disposers had to be rewritten for.
    expect(caught, ['Bad state: cleanup boom']);
  });

  test('a cancellation never reaches the zone', () {
    final caught = <String>[];
    final solo = _Loud();
    fakeAsync((async) {
      _inZone(caught, () {
        solo
          ..run<TestState, void>(key: 'j', (ctx) async {
            ctx.unattended(() => throw const Cancelled('mine'));
          })
          ..run<TestState, void>(
            key: 'k',
            keepWhile: (state) => state is! Working,
            (ctx) async {
              ctx.unattended(() async {
                await Future<void>.delayed(const Duration(milliseconds: 30));
                // The job is over and the state has left the rule: the
                // leaked context builds a fresh `Cancelled(rules)` and
                // hands it to the hook.
                ctx.state;
              });
            },
          );
      });
      async.elapse(const Duration(milliseconds: 10));
      solo.set(const Working());
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    // Both reached the hook; neither reached the zone. Without the
    // `error is! Cancelled` guard the zone would hold them too.
    expect(solo.errors, [
      'Cancelled(handler: mine)',
      'Cancelled(rules: keepWhile)',
    ]);
    expect(caught, isEmpty);
  });
}

final class _Silent extends SoloObserver {}

final class _Quiet extends Solo<TestState> {
  final errors = <String>[];

  _Quiet() : super(const Initial());

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      errors.add('$error');
}

final class _Loud extends Solo<TestState> {
  final errors = <String>[];

  _Loud() : super(const Initial());

  void set(TestState state) => externalSetState(state);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    errors.add('$error');
    super.onError(job, error, stackTrace);
  }
}

final class _Reentrant extends Solo<TestState> {
  bool _nested = false;

  _Reentrant() : super(const Initial());

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    if (!_nested) {
      _nested = true;
      externalSetState(const Working());
    }
    super.onError(job, error, stackTrace);
  }
}

void _inZone(List<String> errors, void Function() body) {
  Zone.current
      .fork(
        specification: ZoneSpecification(
          handleUncaughtError: (self, parent, zone, error, stackTrace) =>
              errors.add('$error'),
        ),
      )
      .run<void>(body);
}
