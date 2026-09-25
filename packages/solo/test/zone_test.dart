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

  test('a global observer leaves the default route alone', () {
    final caught = <String>[];
    Solo.observer = _Silent();
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
      Solo.observer = null;
    }
    expect(
      caught,
      ['Bad state: abandoned boom'],
      reason: 'watching is not answering',
    );
  });

  test('an error handler takes the default route over', () {
    final caught = <String>[];
    final answered = <String>[];
    Solo.errorHandler =
        (solo, job, error, stackTrace) => answered.add('${job.key}: $error');
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
      Solo.errorHandler = null;
    }
    expect(answered, ['j: Bad state: abandoned boom']);
    expect(caught, isEmpty, reason: 'the handler answered for it');
  });

  test('an error handler that throws reaches the zone', () {
    final caught = <String>[];
    Solo.errorHandler =
        (solo, job, error, stackTrace) => throw StateError('handler boom');
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
      Solo.errorHandler = null;
    }
    expect(caught, ['Bad state: handler boom']);
  });

  test('an override of onUnanswered keeps the error out of the zone', () {
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

  test('an override of onError alone leaves the route in place', () {
    final caught = <String>[];
    final solo = _Noting();
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
    expect(solo.errors, ['Bad state: abandoned boom'], reason: 'it notes');
    expect(
      caught,
      ['Bad state: abandoned boom'],
      reason: 'and answers for nothing, so the zone still hears',
    );
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

  group('a failure a cancellation covered in a child', () {
    // The parent took the child's outcome through `ctx.run`, and the
    // outcome carries the cancellation: the controller answers for the
    // failure itself.
    test('reaches onUnanswered of the controller', () {
      final caught = <String>[];
      final solo = _Quiet();
      fakeAsync((async) => _coveredChild(solo, async, caught));
      expect(solo.errors, ['Bad state: child failed first']);
      expect(caught, isEmpty, reason: 'the override answered for it');
    });

    test('reaches the error handler behind it', () {
      final caught = <String>[];
      final answered = <String>[];
      Solo.errorHandler =
          (solo, job, error, stackTrace) => answered.add('${job.key}: $error');
      try {
        fakeAsync((async) => _coveredChild(TestSolo(), async, caught));
      } finally {
        Solo.errorHandler = null;
      }
      expect(answered, ['child: Bad state: child failed first']);
      expect(caught, isEmpty, reason: 'the handler answered for it');
    });

    test('reaches the zone with neither', () {
      final caught = <String>[];
      fakeAsync((async) => _coveredChild(TestSolo(), async, caught));
      expect(caught, ['Bad state: child failed first']);
    });

    test('a step the state stopped while a section held a stop is only told',
        () {
      // The state leaves the child's working type inside the section: that
      // marks the child at once, the step fails after the mark, and the
      // stop the section held has nothing left to land.
      final caught = <String>[];
      final solo = _Loud();
      fakeAsync((async) {
        late final Job<void> parent;
        _inZone(caught, () {
          parent = solo.run<TestState, void>(key: 'parent', (ctx) async {
            await ctx.run(
              solo.job<Initial, int>(key: 'child', (ctx) async {
                final stopped = Completer<void>();
                ctx.onCancel(
                  () => stopped.completeError(StateError('stopped')),
                );
                await ctx.uncancellable<void>(() => stopped.future);
                return 1;
              }),
            );
          });
        });
        async.elapse(const Duration(milliseconds: 5));
        parent.cancel().ignore();
        async.elapse(const Duration(milliseconds: 5));
        solo.set(const Preparing());
        async.flushTimers();
        solo.close();
        async.flushTimers();
      });
      expect(solo.errors, ['Bad state: stopped']);
      expect(caught, isEmpty, reason: 'a failure after the mark is only told');
    });
  });
}

/// A parent that runs a child through `ctx.run` and is cancelled 10 ms
/// in, while the child waits for a child of its own after its body failed
/// 5 ms in.
void _coveredChild(
  OpenSolo<TestState> solo,
  FakeAsync async,
  List<String> caught,
) {
  late final Job<void> parent;
  _inZone(caught, () {
    parent = solo.run<TestState, void>(key: 'parent', (ctx) async {
      await ctx.run(
        solo.job<TestState, int>(key: 'child', (ctx) async {
          ctx
              .run(
                solo.job<TestState, void>(
                  key: 'grandchild',
                  (ctx) => ctx.wait(
                    () => Future<void>.delayed(
                      const Duration(milliseconds: 50),
                    ),
                  ),
                ),
              )
              .ignore();
          await Future<void>.delayed(const Duration(milliseconds: 5));
          throw StateError('child failed first');
        }),
      );
    });
  });
  async.elapse(const Duration(milliseconds: 10));
  parent.cancel().ignore();
  async.flushTimers();
  solo.close();
  async.flushTimers();
}

final class _Silent extends SoloObserver {}

final class _Quiet extends Solo<TestState> with OpenSolo<TestState> {
  final errors = <String>[];

  _Quiet() : super(const Initial());

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      errors.add('$error');
}

/// Notes every error and answers for none: the route stands as it is.
final class _Noting extends Solo<TestState> with OpenSolo<TestState> {
  final errors = <String>[];

  _Noting() : super(const Initial());

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      errors.add('$error');
}

final class _Loud extends Solo<TestState> with OpenSolo<TestState> {
  final errors = <String>[];

  _Loud() : super(const Initial());

  void set(TestState state) => externalSetState(state);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    errors.add('$error');
    super.onError(job, error, stackTrace);
  }
}

final class _Reentrant extends Solo<TestState> with OpenSolo<TestState> {
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
