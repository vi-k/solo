import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/probe_job.dart';

void main() {
  // Deeper than any stack: every level starts the next one before its
  // first `await`, so the whole tree is built on the stack of the root's
  // body, and on the machine these tests were written on that stack holds
  // about nine hundred levels. The subject is not the depth but what the
  // core leaves behind when the stack runs out half-way down: a tree that
  // reached the bottom instead would fail on the first expectation rather
  // than pass quietly.
  const depth = 50000;
  // Where the overflow lands decides which handler of the core it cuts
  // short, and a few frames one way or the other move it. Each tree is
  // built that many frames lower than the one before.
  const shifts = 8;

  group('a tree built on one stack runs out of it and still ends', () {
    test('when every level awaits the next', () async {
      for (var frames = 0; frames < shifts; frames++) {
        final tree = _Tree((tree, ctx, level) async {
          await ctx.run(tree.level(level - 1));
        });
        await tree.runsOut(depth, frames);
      }
    });

    test('when a body hands back the call that starts the next', () async {
      for (var frames = 0; frames < shifts; frames++) {
        // Not `async`: an error of the start is thrown through the body
        // and not into its future.
        final tree = _Tree(
          (tree, ctx, level) => ctx.run(tree.level(level - 1)),
        );
        await tree.runsOut(depth, frames);
      }
    });

    test('and every cleanup a body registered runs', () async {
      for (var frames = 0; frames < shifts; frames++) {
        final tree = _Tree((tree, ctx, level) async {
          ctx.onDispose(() => tree.disposed++);
          tree.registered++;
          await ctx.run(tree.level(level - 1));
        });
        await tree.runsOut(depth, frames);
        expect(
          tree.disposed,
          tree.registered,
          reason: 'shifted by $frames frames',
        );
      }
    });

    test('and no level ends before a child it left running', () async {
      for (var frames = 0; frames < shifts; frames++) {
        final tree = _Tree((tree, ctx, level) async {
          ctx.run(tree.leaf(level)).ignore();
          await ctx.run(tree.level(level - 1));
        });
        await tree.runsOut(depth, frames);
      }
    });

    test('when every level is a group of one', () async {
      for (var frames = 0; frames < shifts; frames++) {
        final tree = _Tree((tree, ctx, level) async {
          await ctx.runAll([tree.level(level - 1)]);
        });
        await tree.runsOut(depth, frames);
      }
    });

    test('when a sibling of the group started before the descent', () async {
      for (var frames = 0; frames < shifts; frames++) {
        final tree = _Tree((tree, ctx, level) async {
          await ctx.runAll([tree.leaf(level), tree.level(level - 1)]);
        });
        await tree.runsOut(depth, frames);
      }
    });

    test('when a sibling of the group was to start after it', () async {
      for (var frames = 0; frames < shifts; frames++) {
        final tree = _Tree((tree, ctx, level) async {
          await ctx.runAll([tree.level(level - 1), tree.leaf(level)]);
        });
        await tree.runsOut(depth, frames);
      }
    });
  });

  test('a child with no stack for its context ends with the body', () async {
    final child = NoStackForContextJob(key: 'child');
    Object? thrown;
    bool? finishedInBody;
    final zone = <Object>[];
    late Job<void> root;
    runZonedGuarded(() {
      root = Job<void>((ctx) async {
        try {
          await ctx.run(child);
        } on Object catch (error) {
          thrown = error;
        }
        await delay(1);
        finishedInBody = child.isFinished;
      });
    }, (error, _) => zone.add(error));
    await _ends(root);
    await delay(1);

    expect(thrown, isA<StackOverflowError>());
    expect(
      finishedInBody,
      isFalse,
      reason:
          'nothing is done where the stack ran out: the child is ended '
          'once the body of its parent is over',
    );
    expect(root.outcome, isA<Done<void>>());
    expect(
      child.outcome,
      isA<Failed>().having(
        (failed) => failed.error,
        'error',
        isA<StackOverflowError>(),
      ),
    );
    expect(zone, isEmpty, reason: 'the body heard it by the throw');
  });

  test('a child cut short and started again is waited for once', () async {
    final release = Completer<void>();
    final child = NoStackAtFirstJob(() => release.future, key: 'child');
    final between = Job.deferred<void>((ctx) => release.future);
    Object? thrown;
    final parent = ProbeJob<void>((ctx) async {
      try {
        await ctx.run(child);
      } on Object catch (error) {
        thrown = error;
      }
      ctx.run(between).ignore();
      ctx.run(child).ignore();
    })..launch();
    await delay(1);

    expect(thrown, isA<StackOverflowError>());
    expect(
      parent.childrenList,
      [same(between), same(child)],
      reason:
          'once, and where a child adopted now stands: the list is in '
          'the order of adoption',
    );
    expect(child.isRunning, isTrue);
    expect(parent.isFinished, isFalse, reason: 'it waits for the child');

    release.complete();
    expect(await _ends(parent), isA<Done<void>>());
    expect(child.outcome, isA<Done<void>>());
  });

  test(
    'a child cut short and started by another job leaves the first',
    () async {
      final release = Completer<void>();
      final child = NoStackAtFirstJob(() => release.future, key: 'child');
      Object? thrown;
      final first = ProbeJob<void>((ctx) async {
        try {
          await ctx.run(child);
        } on Object catch (error) {
          thrown = error;
        }
        await release.future;
      }, key: 'first')..launch();
      await delay(1);
      final second = ProbeJob<void>((ctx) async {
        ctx.run(child).ignore();
      }, key: 'second')..launch();
      await delay(1);

      expect(thrown, isA<StackOverflowError>());
      expect(first.childrenList, isEmpty);
      expect(second.childrenList, [same(child)]);
      expect(child.isRunning, isTrue);
      expect(second.isFinished, isFalse, reason: 'it waits for the child');

      release.complete();
      expect(await _ends(first), isA<Done<void>>());
      expect(await _ends(second), isA<Done<void>>());
      expect(child.outcome, isA<Done<void>>());
    },
  );

  test(
    'a child cut short under one job and turned away by another leaves it',
    () async {
      final release = Completer<void>();
      final child = NoStackAtFirstJob(() async {}, key: 'child');
      Object? thrown;
      final first = ProbeJob<void>((ctx) async {
        try {
          await ctx.run(child);
        } on Object catch (error) {
          thrown = error;
        }
        await release.future;
      }, key: 'first')..launch();
      await delay(1);
      expect(thrown, isA<StackOverflowError>());
      expect(first.childrenList, [same(child)]);

      Object? refused;
      final second = RefusingParentJob<void>((ctx) async {
        try {
          await ctx.run(child);
        } on Object catch (error) {
          refused = error;
        }
      }, key: 'second')..launch();
      await delay(1);

      expect(refused, isA<Cancelled>());
      expect(child.outcome, same(refused));
      expect(
        first.childrenList,
        isEmpty,
        reason:
            'the child has a new parent by now, and it was never on the '
            'list of that one: it leaves the list it is on',
      );

      release.complete();
      expect(await _ends(first), isA<Done<void>>());
      expect(await _ends(second), isA<Done<void>>());
    },
  );

  test(
    'a child turned away by a rule that overflowed is ended on the spot',
    () async {
      late ProbeJob<void> child;
      Object? thrown;
      bool? finishedInBody;
      final zone = <Object>[];
      late OverflowingRulesJob<void> root;
      runZonedGuarded(() {
        child = ProbeJob<void>((ctx) async {}, key: 'child');
        root = OverflowingRulesJob<void>((ctx) async {
          try {
            await ctx.run(child);
          } on Object catch (error) {
            thrown = error;
          }
          finishedInBody = child.isFinished;
        })..launch();
      }, (error, _) => zone.add(error));
      await _ends(root);
      await delay(1);

      expect(thrown, isA<StackOverflowError>());
      expect(
        finishedInBody,
        isTrue,
        reason:
            'the rule threw before the child joined the waiting list: no '
            'start was cut short, and there is nothing to put off',
      );
      expect(
        child.outcome,
        isA<Failed>().having(
          (failed) => failed.error,
          'error',
          isA<StackOverflowError>(),
        ),
      );
      expect(root.outcome, isA<Done<void>>());
      expect(zone, isEmpty, reason: 'the body heard it by the throw');
    },
  );

  test(
    'a child with no stack for its timer runs the rest of its life',
    () async {
      final heard = <String>[];
      final child = TimedProbeJob(
        key: 'child',
        timeout: const Duration(seconds: 1),
        observer: _Heard(heard),
      );
      Object? thrown;
      bool? runningInBody;
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(() {
        root = Job<void>((ctx) async {
          try {
            await runZoned(
              () => ctx.run(child),
              zoneSpecification: ZoneSpecification(
                createTimer: (self, parent, zone, duration, callback) =>
                    throw const StackOverflowError(),
              ),
            );
          } on Object catch (error) {
            thrown = error;
          }
          await delay(1);
          runningInBody = child.isRunning;
        });
      }, (error, _) => zone.add(error));
      await _ends(root);
      await delay(1);

      expect(thrown, isA<StackOverflowError>());
      expect(runningInBody, isTrue);
      expect(
        child.outcome,
        isA<Failed>().having(
          (failed) => failed.error,
          'error',
          isA<StackOverflowError>(),
        ),
      );
      expect(
        child.hooks,
        ['disposed', 'finished'],
        reason:
            'the body never ran, and what the context had registered is '
            'released all the same: the job is ended by the rest of its own '
            'routine, not by hand',
      );
      expect(heard, ['error child StackOverflowError', 'finish child']);
      expect(zone, isEmpty, reason: 'the body heard it by the throw');
    },
  );

  test(
    'a child cut short after its body failed ends with that failure',
    () async {
      final heard = <String>[];
      late ProbeJob<void> child;
      Object? thrown;
      List<String>? hooksInBody;
      var scheduled = 0;
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(() {
        child = ProbeJob<void>(
          (ctx) => throw StateError('of the body'),
          key: 'child',
          observer: _Heard(heard),
        );
        root = Job<void>((ctx) async {
          try {
            // The body throws before its first `await`, so the routine
            // goes on, on the stack of the start, to the first thing it
            // has to wait for; and the zone has no stack for that.
            await runZoned(
              () => ctx.run(child),
              zoneSpecification: ZoneSpecification(
                scheduleMicrotask: (self, parent, zone, callback) {
                  if (scheduled++ == 0) {
                    throw const StackOverflowError();
                  }
                  parent.scheduleMicrotask(zone, callback);
                },
              ),
            );
          } on Object catch (error) {
            thrown = error;
          }
          await delay(1);
          hooksInBody = [if (child.isRunning) 'running', ...child.hooks];
        });
      }, (error, _) => zone.add(error));
      await _ends(root);
      await delay(1);

      expect(
        thrown,
        isA<StackOverflowError>(),
        reason: 'the start throws what cut the routine short',
      );
      expect(hooksInBody, ['running', 'started']);
      expect(
        child.outcome,
        isA<Failed>().having((failed) => failed.error, 'error', isStateError),
        reason:
            'the body got as far as failing, and that is what it ended '
            'with',
      );
      expect(child.hooks, ['started', 'finished']);
      expect(heard, [
        'start child',
        'error child StateError',
        'finish child',
      ], reason: 'the failure is announced once, not once a pass');
      expect(
        zone,
        [isStateError],
        reason:
            'the body of the parent heard the overflow and not this, so '
            'nobody has answered for it',
      );
    },
  );

  test('a child cut short after its body failed, then ended by hand, answers '
      'for that failure', () async {
    final heard = <String>[];
    late ProbeJob<void> child;
    var scheduled = 0;
    final zone = <Object>[];
    late Job<void> root;
    runZonedGuarded(() {
      child = ProbeJob<void>(
        (ctx) {
          // An engine ending the job by hand as the second pass unwinds the
          // stack.
          ctx.onDispose(() => child.drop(const Done(null)));
          throw StateError('of the body');
        },
        key: 'child',
        observer: _Heard(heard),
      );
      root = Job<void>((ctx) async {
        try {
          await runZoned(
            () => ctx.run(child),
            zoneSpecification: ZoneSpecification(
              scheduleMicrotask: (self, parent, zone, callback) {
                if (scheduled++ == 0) {
                  throw const StackOverflowError();
                }
                parent.scheduleMicrotask(zone, callback);
              },
            ),
          );
        } on Object {
          // The overflow: the test above holds what the start throws.
        }
        await delay(1);
      });
    }, (error, _) => zone.add(error));
    await _ends(root);
    await delay(1);

    expect(child.outcome, isA<Done<void>>());
    expect(heard, [
      'start child',
      'error child StateError',
      'finish child',
    ], reason: 'the failure is announced once, not once a pass');
    expect(
      zone,
      [isStateError],
      reason:
          'the first pass announced the failure and answered for none, '
          'and the outcome is the one the engine gave',
    );
  });

  test(
    'a child cut short by another error ends by its routine all the same',
    () async {
      final heard = <String>[];
      var released = false;
      late ProbeJob<void> child;
      Object? thrown;
      bool? runningInBody;
      var scheduled = 0;
      final broken = ArgumentError('of the zone');
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(() {
        child = ProbeJob<void>(
          (ctx) {
            ctx.onDispose(() => released = true);
            throw StateError('of the body');
          },
          key: 'child',
          observer: _Heard(heard),
        );
        root = Job<void>((ctx) async {
          try {
            // As in the test above, and the zone has not run out of stack:
            // it is broken, and what it throws is no overflow.
            await runZoned(
              () => ctx.run(child),
              zoneSpecification: ZoneSpecification(
                scheduleMicrotask: (self, parent, zone, callback) {
                  if (scheduled++ == 0) {
                    throw broken;
                  }
                  parent.scheduleMicrotask(zone, callback);
                },
              ),
            );
          } on Object catch (error) {
            thrown = error;
          }
          await delay(1);
          runningInBody = child.isRunning;
        });
      }, (error, _) => zone.add(error));
      await _ends(root);
      await delay(1);

      expect(thrown, same(broken));
      expect(
        runningInBody,
        isTrue,
        reason:
            'its body ran, and only the rest of its own routine ends such '
            'a job: ended by hand at the throw, it would release nothing',
      );
      expect(
        child.outcome,
        isA<Failed>().having((failed) => failed.error, 'error', isStateError),
      );
      expect(released, isTrue);
      expect(heard, ['start child', 'error child StateError', 'finish child']);
      expect(
        zone,
        [isStateError],
        reason:
            'the body of the parent heard what the zone threw and not '
            'this, so nobody has answered for it',
      );
    },
  );

  test(
    'a child that cancelled itself before it was cut short ends cancelled',
    () async {
      final heard = <String>[];
      late ProbeJob<void> child;
      Object? thrown;
      var scheduled = 0;
      final broken = ArgumentError('of the zone');
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(() {
        child = ProbeJob<void>(
          (ctx) => throw const Cancelled('gave up'),
          key: 'child',
          observer: _Heard(heard),
        );
        root = Job<void>((ctx) async {
          try {
            // As in the test above: the zone is broken, and the body of
            // the child was over, with no failure, before the routine met
            // it.
            await runZoned(
              () => ctx.run(child),
              zoneSpecification: ZoneSpecification(
                scheduleMicrotask: (self, parent, zone, callback) {
                  if (scheduled++ == 0) {
                    throw broken;
                  }
                  parent.scheduleMicrotask(zone, callback);
                },
              ),
            );
          } on Object catch (error) {
            thrown = error;
          }
        });
      }, (error, _) => zone.add(error));
      await _ends(root);
      await delay(1);

      expect(thrown, same(broken));
      expect(
        child.outcome,
        isA<Cancelled>(),
        reason:
            'the body decided before anything was cut short, and that '
            'decision stands',
      );
      expect(
        heard,
        ['start child', 'error child ArgumentError', 'finish child'],
        reason:
            'the job is ended with what its own routine was thrown out '
            'by, and not with an overflow nobody saw',
      );
      expect(zone, isEmpty, reason: 'the body of the parent heard it');
    },
  );

  test(
    'a child cut short by a body that threw at once outlives the start',
    () async {
      final child = NoStackForContextJob(key: 'child');
      bool? finishedAtOnce;
      final zone = <Object>[];
      late ProbeJob<void> parent;
      runZonedGuarded(() {
        // Not `async`: the overflow goes through the body, and when the
        // body is over the routine of the parent is still on the stack it
        // was started on.
        parent = ProbeJob<void>((ctx) => ctx.run(child), key: 'parent')
          ..launch();
        finishedAtOnce = child.isFinished;
      }, (error, _) => zone.add(error));
      await _ends(parent);
      await delay(1);

      expect(
        finishedAtOnce,
        isFalse,
        reason:
            'the stack the parent was started on may be the one that ran '
            'out, and nothing is ended on it',
      );
      expect(
        parent.outcome,
        isA<Failed>().having(
          (failed) => failed.error,
          'error',
          isA<StackOverflowError>(),
        ),
      );
      expect(
        child.outcome,
        isA<Failed>().having(
          (failed) => failed.stackTrace,
          'stackTrace',
          same((parent.outcome! as Failed).stackTrace),
        ),
        reason:
            'the child ends with the very overflow the body of its parent '
            'failed with',
      );
      expect(zone, isEmpty);
    },
  );

  test('children cut short one under another are ended a stack each', () async {
    final order = <Object?>[];
    final grandchild = NoStackForContextJob(key: 'grandchild');
    final second = NoStackForContextJob(key: 'second');
    var scheduled = 0;
    final zone = <Object>[];
    late ProbeJob<void> root;
    runZonedGuarded(() {
      // Not `async`: the overflow under `grandchild` goes through the
      // body, and the routine of `child` goes on, on the stack of its
      // start, to the first thing it has to wait for; and the zone has
      // no stack for that. Both are cut short, one under the other.
      final child = ProbeJob<void>((ctx) => ctx.run(grandchild), key: 'child');
      root = ProbeJob<void>(
        (ctx) async {
          try {
            await runZoned(
              () => ctx.run(child),
              zoneSpecification: ZoneSpecification(
                scheduleMicrotask: (self, parent, zone, callback) {
                  if (scheduled++ == 0) {
                    throw const StackOverflowError();
                  }
                  parent.scheduleMicrotask(zone, callback);
                },
              ),
            );
          } on Object {
            // The overflow.
          }
          try {
            await ctx.run(second);
          } on Object {
            // The overflow.
          }
        },
        key: 'root',
        // Every job below inherits it as it is adopted.
        observer: FinishHook((job) => order.add(job.key)),
      )..launch();
    }, (error, _) => zone.add(error));
    await _ends(root);
    await delay(1);

    expect(
      order,
      ['second', 'grandchild', 'child', 'root'],
      reason:
          'the parent goes round its own children before any of them '
          'is back for its own: no job is ended under another',
    );
    expect(zone, isEmpty);
  });

  test('a child cut short and then cancelled ends cancelled', () async {
    final child = TimedProbeJob(
      key: 'child',
      timeout: const Duration(seconds: 1),
    );
    final caught = Completer<void>();
    final zone = <Object>[];
    late Job<void> root;
    runZonedGuarded(() {
      root = Job<void>((ctx) async {
        try {
          await runZoned(
            () => ctx.run(child),
            zoneSpecification: ZoneSpecification(
              createTimer: (self, parent, zone, duration, callback) =>
                  throw const StackOverflowError(),
            ),
          );
        } on Object {
          caught.complete();
        }
        await ctx.abandonable(() => Completer<void>().future);
      });
    }, (error, _) => zone.add(error));
    await caught.future;
    await root.cancel();
    await delay(1);

    expect(root.outcome, isA<Cancelled>());
    expect(child.outcome, isA<Cancelled>());
    expect(child.hooks, ['disposed', 'finished']);
    expect(zone, isEmpty);
  });

  test(
    'a child cut short whose end fails is not ended a second time',
    () async {
      final child = HardToEndJob(key: 'child');
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(() {
        root = Job<void>((ctx) async {
          try {
            await ctx.run(child);
          } on Object {
            // The overflow.
          }
        });
      }, (error, _) => zone.add(error));
      await delay(5);

      expect(
        child.asked,
        1,
        reason: 'an end that fails every time would be asked for without end',
      );
      expect(zone, [isStateError]);
      expect(
        root.isRunning,
        isTrue,
        reason:
            'the child is not over, and its parent waits for it as for '
            'any other',
      );

      await root.cancel();
      expect(child.outcome, isA<Cancelled>());
    },
  );

  test(
    'an error that leaves the routine of a child cut short reaches the zone',
    () async {
      final child = HardToEndTimedJob(
        key: 'child',
        timeout: const Duration(seconds: 1),
      );
      final zone = <Object>[];
      runZonedGuarded(() {
        Job<void>((ctx) async {
          try {
            await runZoned(
              () => ctx.run(child),
              zoneSpecification: ZoneSpecification(
                createTimer: (self, parent, zone, duration, callback) =>
                    throw const StackOverflowError(),
              ),
            );
          } on Object {
            // The overflow.
          }
        });
      }, (error, _) => zone.add(error));
      await delay(5);

      expect(child.asked, 1);
      expect(
        zone,
        [isStateError],
        reason:
            'the routine that came back for the child is on a stack of its '
            'own, and what leaves it goes where an error of any routine goes: '
            'kept for a parent, it would reach nobody',
      );
    },
  );

  test(
    'a child still starting when the body of its parent ends is left alone',
    () async {
      // Nothing runs out of stack here. The body of the parent ends inside
      // the start of the child, before the child has reached its routine,
      // and a job like that looks exactly like one that never will.
      final gate = Completer<void>.sync();
      late JobContext handed;
      late ProbeJob<void> child;
      var ran = 0;
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(() {
        root = Job<void>((ctx) async {
          handed = ctx;
          await gate.future;
        });
        child = ProbeJob<void>(
          (ctx) async {
            ran++;
            await delay(1);
          },
          key: 'child',
          observer: _OnStart(gate.complete),
        );
      }, (error, _) => zone.add(error));
      await delay(1);
      handed.run(child).ignore();
      await _ends(root);
      await delay(1);

      expect(ran, 1, reason: 'the body of the child ran, and once');
      expect(child.outcome, isA<Done<void>>());
      expect(root.outcome, isA<Done<void>>());
      expect(zone, isEmpty);
    },
  );

  test(
    'an error that leaves a routine after the start reaches the zone',
    () async {
      // What is kept for the parent is what escaped the first, synchronous
      // part of a routine. Anything later did not happen on the stack of the
      // start, and goes where it always went.
      final zone = <Object>[];
      runZonedGuarded(() {
        Job<void>((ctx) async {
          ctx.run(UnwaitableJob(key: 'child')).ignore();
        });
      }, (error, _) => zone.add(error));
      await delay(5);

      expect(zone, [isStateError]);
    },
  );

  test(
    'a parent taking a child where the stack runs out takes it whole',
    () async {
      // Four of them: the size at which a hash set of the SDK grows to take
      // one more, by calls any of which the stack may refuse.
      const had = 4;
      // In a turn of its own, as every call below is made: the stack under
      // the test is the same each time.
      await delay(0);
      final bottom = _Bottom()..find();
      var took = 0;
      var tookNone = 0;
      for (var call = 0; call < _Bottom.calls; call++) {
        final body = Completer<void>();
        final release = Completer<void>();
        late ProbeContext context;
        final others = [
          for (var child = 0; child < had; child++)
            Job.deferred<void>((ctx) => release.future),
        ];
        final leave = Completer<void>();
        final last = Job.deferred<void>((ctx) => leave.future);
        final after = Job.deferred<void>((ctx) => release.future);
        final parent = ProbeJob<void>((ctx) async {
          context = ctx as ProbeContext;
          for (final child in others) {
            ctx.run(child).ignore();
          }
          await body.future;
        })..launch();
        await delay(0);

        // By the door a child is taken through and no further. `run` goes on
        // from there into an `async` function, and an overflow thrown by the
        // machinery of its first `await` completes the future on the spot,
        // before the caller has it: with nobody listening the VM reports it
        // to the zone as unhandled, from a depth the handler of the zone has
        // no stack to run on, and the root zone ends the isolate. About one
        // run of this test in forty went that way, the runner waiting for
        // good.
        bottom.at(call, () => context.adopt(last));

        final waitedFor = parent.childrenList;
        expect(
          waitedFor.take(had),
          others,
          reason:
              'call $call: the stack may refuse the child, and with it the '
              'whole of the call that takes it; never the children the parent '
              'was waiting for already',
        );
        final taken = waitedFor.length > had;
        taken ? took++ : tookNone++;

        // A child written on the list by half is there to a walk from the
        // front and has no place of its own: the child adopted next and the
        // first one to leave are where that shows.
        context.run(after).ignore();
        expect(parent.childrenList, [
          ...others,
          if (taken) same(last),
          same(after),
        ], reason: 'call $call: the child adopted next stands after it');
        last.ignoreFailure();
        if (last.isRunning) {
          leave.complete();
        } else {
          last.cancel().ignore();
        }
        await delay(0);
        // Not asked about itself: a child whose start was cut short once it
        // was running stays until the body of the parent is over.
        expect(
          parent.childrenList.where((child) => !identical(child, last)),
          [...others, same(after)],
          reason: 'call $call: it leaves alone, and takes no neighbour with it',
        );

        body.complete();
        await delay(0);
        expect(
          parent.isFinished,
          isFalse,
          reason: 'call $call: five children are still running',
        );

        release.complete();
        expect(await _ends(parent), isA<Done<void>>());
        expect(
          [...others, after].map((child) => child.outcome),
          everyElement(isA<Done<void>>()),
          reason: 'call $call',
        );
        expect(last.isFinished, isTrue, reason: 'call $call');
        expect(parent.childrenList, isEmpty, reason: 'call $call');
      }
      expect(
        [took, tookNone],
        everyElement(isPositive),
        reason:
            'the calls are to stand on both sides of the place where the '
            'stack runs out, or none of them was cut short halfway',
      );
    },
  );

  test(
    'a group one branch of which had no stack fails with the overflow',
    () async {
      final torn = NoStackForContextJob(key: 'torn');
      final sibling = ProbeJob<void>(
        (ctx) => ctx.abandonable(() => Completer<void>().future),
        key: 'sibling',
      );
      Object? thrown;
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(() {
        root = Job<void>((ctx) async {
          try {
            await ctx.runAll(<ChildJob<void>>[sibling, torn]);
          } on Object catch (error) {
            thrown = error;
          }
        });
      }, (error, _) => zone.add(error));
      await _ends(root);
      await delay(1);

      expect(thrown, isA<StackOverflowError>());
      expect(sibling.outcome, isA<Cancelled>());
      expect(
        torn.outcome,
        isA<Failed>().having(
          (failed) => failed.error,
          'error',
          isA<StackOverflowError>(),
        ),
      );
      expect(zone, isEmpty);
    },
  );

  test(
    'a group cut short while it formed stops its branches with the body',
    () async {
      final torn = NoStackForContextJob(key: 'torn');
      final sibling = ProbeJob<void>(
        (ctx) => ctx.abandonable(() => Completer<void>().future),
        key: 'sibling',
      );
      Object? thrown;
      bool? runningInBody;
      final zone = <Object>[];
      late NoStackForGroupJob<void> root;
      runZonedGuarded(() {
        root = NoStackForGroupJob<void>((ctx) async {
          // The start of `torn` is cut short, and so is the group on its
          // way to answering for it.
          ctx.outOfStack = true;
          try {
            await ctx.runAll(<ChildJob<void>>[sibling, torn]);
          } on Object catch (error) {
            thrown = error;
          }
          await delay(1);
          runningInBody = sibling.isRunning;
        })..launch();
      }, (error, _) => zone.add(error));
      await _ends(root);
      await delay(1);

      expect(thrown, isA<StackOverflowError>());
      expect(
        runningInBody,
        isTrue,
        reason:
            'nothing is done where the stack ran out: the branches are '
            'asked to stop once the body of their parent is over',
      );
      expect(root.outcome, isA<Done<void>>());
      expect(
        sibling.outcome,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<SiblingCancelReason>(),
        ),
      );
      expect(
        torn.outcome,
        isA<Failed>().having(
          (failed) => failed.error,
          'error',
          isA<StackOverflowError>(),
        ),
      );
      expect(zone, isEmpty, reason: 'the body heard it by the throw');
    },
  );

  test(
    'a branch at a barrier of a group cut short is let go with the body',
    () async {
      final torn = NoStackForContextJob(key: 'torn');
      final sibling = ProbeJob<void>((ctx) async {}, key: 'sibling');
      bool? runningInBody;
      final zone = <Object>[];
      late NoStackForGroupJob<void> root;
      runZonedGuarded(() {
        root = NoStackForGroupJob<void>((ctx) async {
          ctx.outOfStack = true;
          try {
            await ctx.runAll(<ChildJob<void>>[sibling, torn]);
          } on Object {
            // The overflow, as in the test above.
          }
          await delay(1);
          runningInBody = sibling.isRunning;
        })..launch();
      }, (error, _) => zone.add(error));
      await _ends(root);
      await delay(1);

      expect(
        runningInBody,
        isTrue,
        reason:
            'its body is over, and it waits for a group that is not there '
            'to decide',
      );
      expect(root.outcome, isA<Done<void>>());
      expect(
        sibling.outcome,
        isA<Cancelled>(),
        reason: 'a group that failed lets no branch end as done',
      );
      expect(sibling.hooks, ['started', 'finished']);
      expect(zone, isEmpty);
    },
  );

  test(
    'a failure of a branch of a group cut short reaches the zone once',
    () async {
      final gate = Completer<void>();
      final listener = _NoStackForListener();
      late ProbeJob<void> failing;
      late ProbeJob<void> unheard;
      Object? thrown;
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(() {
        // In the zone: a failure nobody answered for goes to the zone the
        // job was made in.
        failing = ProbeJob<void>((ctx) async {
          await gate.future;
          throw StateError('of the branch');
        }, key: 'failing');
        unheard = ProbeJob<void>((ctx) {
          final stopped = ctx.abandonable(() => Completer<void>().future);
          // The group is thrown out as it begins to listen for this
          // branch, with nothing written down about why.
          listener.outOfStack = true;
          return stopped;
        }, key: 'unheard');
        root = Job<void>((ctx) async {
          try {
            await listener.run(() => ctx.runAll([failing, unheard]));
          } on Object catch (error) {
            thrown = error;
          }
          gate.complete();
          await delay(1);
        });
      }, (error, _) => zone.add(error));
      await _ends(root);
      await delay(1);

      expect(thrown, isA<StackOverflowError>());
      expect(root.outcome, isA<Done<void>>());
      expect(
        failing.outcome,
        isA<Failed>().having((failed) => failed.error, 'error', isStateError),
      );
      expect(unheard.outcome, isA<Cancelled>());
      expect(
        zone,
        [isStateError],
        reason:
            'the caller of the group heard the overflow and nothing else, '
            'so nobody has answered for the failure of the branch',
      );
    },
  );

  test(
    'a group cut short waits for a branch it had not begun to hear',
    () async {
      final gate = Completer<void>();
      final release = Completer<void>();
      final listener = _NoStackForListener();
      late ProbeJob<void> failing;
      late ProbeJob<void> unheard;
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(() {
        failing = ProbeJob<void>((ctx) async {
          await gate.future;
          throw StateError('of the branch');
        }, key: 'failing');
        // Deaf to the stop until the test lets it go.
        unheard = ProbeJob<void>((ctx) {
          listener.outOfStack = true;
          return release.future;
        }, key: 'unheard');
        root = Job<void>((ctx) async {
          try {
            await listener.run(() => ctx.runAll([failing, unheard]));
          } on Object {
            // The overflow.
          }
          gate.complete();
          // Long enough for `failing` to end before the body does: asked
          // to stop on its way out, it would end cancelled and hand its
          // failure on by itself.
          await delay(1);
        });
      }, (error, _) => zone.add(error));
      await delay(5);
      final heardEarly = List.of(zone);
      final rootEndedEarly = root.isFinished;
      release.complete();
      await _ends(root);
      await delay(1);

      expect(rootEndedEarly, isFalse);
      expect(
        heardEarly,
        isEmpty,
        reason:
            'the group answers for a failure once every branch is closed, '
            'and one of them is not',
      );
      expect(
        failing.outcome,
        isA<Failed>().having((failed) => failed.error, 'error', isStateError),
      );
      expect(unheard.outcome, isA<Cancelled>());
      expect(zone, [isStateError]);
    },
  );

  test('a branch the group never heard answers for its own failure', () async {
    final gate = Completer<void>();
    final listener = _NoStackForListener();
    late ProbeJob<void> sibling;
    late ProbeJob<void> unheard;
    final zone = <Object>[];
    late Job<void> root;
    runZonedGuarded(() {
      sibling = ProbeJob<void>(
        (ctx) => ctx.abandonable(() => Completer<void>().future),
        key: 'sibling',
      );
      unheard = ProbeJob<void>((ctx) async {
        listener.outOfStack = true;
        await gate.future;
        throw StateError('of the branch');
      }, key: 'unheard');
      root = Job<void>((ctx) async {
        try {
          await listener.run(() => ctx.runAll([sibling, unheard]));
        } on Object {
          // The overflow.
        }
        gate.complete();
        await delay(1);
      });
    }, (error, _) => zone.add(error));
    await _ends(root);
    await delay(1);

    expect(
      unheard.outcome,
      isA<Failed>().having((failed) => failed.error, 'error', isStateError),
    );
    expect(sibling.outcome, isA<Cancelled>());
    expect(
      zone,
      [isStateError],
      reason:
          'nobody was listening when the branch failed, so it reported '
          'the failure itself, and the group does not report it again',
    );
  });

  // The same, and an engine hands the branch a value after its body failed: the
  // group takes no failure of a branch it never heard.
  test(
    'a branch the group never heard answers for its failure past a value',
    () async {
      final gate = Completer<void>();
      final listener = _NoStackForListener();
      late ProbeJob<void> sibling;
      late ProbeJob<void> unheard;
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(() {
        sibling = ProbeJob<void>(
          (ctx) => ctx.abandonable(() => Completer<void>().future),
          key: 'sibling',
        );
        unheard = ProbeJob<void>((ctx) async {
          listener.outOfStack = true;
          ctx.onDispose(() => unheard.drop(const Done(null)));
          await gate.future;
          throw StateError('of the branch');
        }, key: 'unheard');
        root = Job<void>((ctx) async {
          try {
            await listener.run(() => ctx.runAll([sibling, unheard]));
          } on Object {
            // The overflow.
          }
          gate.complete();
          await delay(1);
        });
      }, (error, _) => zone.add(error));
      await _ends(root);
      await delay(1);

      expect(unheard.outcome, isA<Done<void>>());
      expect(sibling.outcome, isA<Cancelled>());
      expect(
        zone,
        [isStateError],
        reason:
            'nobody was listening when the branch failed, so it answers '
            'for the failure itself, value or not',
      );
    },
  );

  test(
    'a group cut short whose end fails holds no branch at a barrier',
    () async {
      final gate = Completer<void>();
      final listener = _NoStackForListener();
      late ProbeJob<void> waiting;
      late ProbeJob<void> unheard;
      Object? thrown;
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(() {
        // Over with its body by the time the owner comes back for the group,
        // and standing at the barrier.
        waiting = ProbeJob<void>((ctx) => gate.future, key: 'waiting');
        unheard = ProbeJob<void>((ctx) {
          // Asked to stop by the owner that has come back for the group,
          // it leaves that owner with no stack to listen for it either.
          ctx.onCancel(() => listener.outOfStack = true);
          final stopped = ctx.abandonable(() => Completer<void>().future);
          listener.outOfStack = true;
          return stopped;
        }, key: 'unheard');
        // The routine of the root is in the zone as well: it is the owner
        // that comes back.
        listener.run(() {
          root = Job<void>((ctx) async {
            try {
              await ctx.runAll([waiting, unheard]);
            } on Object catch (error) {
              thrown = error;
            }
            gate.complete();
            await delay(1);
          });
        });
      }, (error, _) => zone.add(error));
      await _ends(root);
      await delay(1);

      expect(thrown, isA<StackOverflowError>());
      expect(root.outcome, isA<Done<void>>());
      expect(
        waiting.outcome,
        isA<Cancelled>(),
        reason:
            'the group began to fail before its end was cut short, and a '
            'group that is failing holds nobody',
      );
      expect(unheard.outcome, isA<Cancelled>());
      expect(
        zone,
        [isA<StackOverflowError>()],
        reason:
            'the end of a group is tried once, and what cut it short has '
            'nowhere else to go',
      );
    },
  );

  test(
    'a group thrown out as it began to wait still answers for a branch',
    () async {
      var outOfStack = false;
      late ProbeJob<void> failing;
      late ProbeJob<void> sibling;
      Object? thrown;
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(() {
        failing = ProbeJob<void>(
          (ctx) => throw StateError('of the branch'),
          key: 'failing',
        );
        sibling = ProbeJob<void>((ctx) {
          // The group has every branch, and asks this one to stop on its
          // way to the routine that waits for them all; the first `await`
          // of that routine finds no stack.
          ctx.onCancel(() => outOfStack = true);
          return ctx.abandonable(() => Completer<void>().future);
        }, key: 'sibling');
        root = Job<void>((ctx) async {
          try {
            await runZoned(
              () => ctx.runAll([failing, sibling]),
              zoneSpecification: ZoneSpecification(
                registerUnaryCallback: <S, T>(self, parent, zone, callback) {
                  // An `await` comes through here, with a callback that
                  // takes anything.
                  if (outOfStack && <Object?>[] is List<T>) {
                    outOfStack = false;
                    throw const StackOverflowError();
                  }
                  return parent.registerUnaryCallback(zone, callback);
                },
              ),
            );
          } on Object catch (error) {
            thrown = error;
          }
          await delay(1);
        });
      }, (error, _) => zone.add(error));
      await _ends(root);
      await delay(1);

      expect(
        thrown,
        isA<StackOverflowError>(),
        reason:
            'the group was thrown out before it could say what it failed '
            'with',
      );
      expect(root.outcome, isA<Done<void>>());
      expect(
        failing.outcome,
        isA<Failed>().having((failed) => failed.error, 'error', isStateError),
      );
      expect(sibling.outcome, isA<Cancelled>());
      expect(
        zone,
        [isA<StackOverflowError>(), isStateError],
        reason:
            'the overflow ended a routine whose future nobody had yet, and '
            'Dart reports such an error on the spot; the failure of the branch '
            'the group listened for, so the branch does not report it, and '
            'the group does once its owner has taken it up',
      );
    },
  );

  test('a group that is alive is left alone when a child beside it is cut '
      'short', () async {
    final gate = Completer<void>();
    final torn = NoStackForContextJob(key: 'torn');
    final branch = ProbeJob<int>((ctx) async {
      await gate.future;
      return 1;
    }, key: 'branch');
    late Future<List<int>> values;
    final zone = <Object>[];
    late Job<void> root;
    runZonedGuarded(() {
      root = Job<void>((ctx) async {
        // Not awaited: the group outlives the body.
        values = ctx.runAll([branch]);
        try {
          await ctx.run(torn);
        } on Object {
          // The overflow.
        }
      });
    }, (error, _) => zone.add(error));
    await delay(1);
    gate.complete();
    await _ends(root);
    final committed = await values;
    await delay(1);

    expect(committed, [1]);
    expect(branch.outcome, isA<Done<int>>());
    expect(
      torn.outcome,
      isA<Failed>().having(
        (failed) => failed.error,
        'error',
        isA<StackOverflowError>(),
      ),
    );
    expect(zone, isEmpty);
  });

  test(
    'a group still forming when the body of its owner ends is left alone',
    () async {
      // Nothing runs out of stack here either. The body of the owner ends
      // while the group is listening for its last branch: no start of a
      // child is on the stack, and the group has no routine yet.
      final gate = Completer<void>.sync();
      late JobContext handed;
      late ProbeJob<int> first;
      late ProbeJob<int> second;
      var listened = 0;
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(() {
        root = Job<void>((ctx) async {
          handed = ctx;
          await gate.future;
        });
        first = ProbeJob<int>((ctx) async {
          await delay(1);
          return 1;
        }, key: 'first');
        second = ProbeJob<int>((ctx) async => 2, key: 'second');
      }, (error, _) => zone.add(error));
      await delay(1);
      final values = runZoned(
        () => handed.runAll([first, second]),
        zoneSpecification: ZoneSpecification(
          registerUnaryCallback: <S, T>(self, parent, zone, callback) {
            // The group asks for the outcome of a branch right after it has
            // started it; an `await` in the zone comes through here too,
            // with a callback that takes anything.
            if (<T>[] is List<Outcome<Object?>> && ++listened == 2) {
              gate.complete();
            }
            return parent.registerUnaryCallback(zone, callback);
          },
        ),
      );
      final committed = await values.timeout(const Duration(seconds: 5));
      await _ends(root);
      await delay(1);

      expect(committed, [1, 2]);
      expect(first.outcome, isA<Done<int>>());
      expect(second.outcome, isA<Done<int>>());
      expect(root.outcome, isA<Done<void>>());
      expect(zone, isEmpty);
    },
  );

  test(
    'a group that failed beside a younger one is not ended a second time',
    () async {
      // Nothing runs out of stack here either. The owner has two groups, and
      // the one that fails is not the last that came: the younger is alive
      // when the older leaves, and when the body of the owner ends.
      final gate = Completer<void>();
      late ProbeJob<int> failing;
      late ProbeJob<int> waiting;
      late Future<List<int>> younger;
      Object? thrown;
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(() {
        failing = ProbeJob<int>((ctx) async {
          await delay(1);
          throw StateError('of the branch');
        }, key: 'failing');
        waiting = ProbeJob<int>((ctx) async {
          await gate.future;
          return 2;
        }, key: 'waiting');
        root = Job<void>((ctx) async {
          final older = ctx.runAll([failing]);
          // Not awaited: the group outlives the body.
          younger = ctx.runAll([waiting]);
          try {
            await older;
          } on Object catch (error) {
            thrown = error;
          }
        });
      }, (error, _) => zone.add(error));
      await delay(5);
      gate.complete();
      await _ends(root);
      final committed = await younger;
      await delay(1);

      expect(thrown, isStateError);
      expect(committed, [2]);
      expect(
        failing.outcome,
        isA<Failed>().having((failed) => failed.error, 'error', isStateError),
      );
      expect(waiting.outcome, isA<Done<int>>());
      expect(root.outcome, isA<Done<void>>());
      expect(
        zone,
        isEmpty,
        reason:
            'the body caught the failure of the group, and the group was '
            'over: nobody is left to answer for it again',
      );
    },
  );

  test(
    'the end of a group cut short is tried once, a failed branch or not',
    () async {
      final gate = Completer<void>();
      final release = Completer<void>();
      var counting = false;
      var groupListened = 0;
      late ProbeJob<void> failing;
      late ProbeJob<void> unheard;
      Object? thrown;
      final zone = <Object>[];
      late Job<void> root;
      runZonedGuarded(() {
        // Heard by the group before it was cut short, and failed by the
        // time the owner comes back for it.
        failing = ProbeJob<void>((ctx) async {
          await gate.future;
          throw StateError('of the branch');
        }, key: 'failing');
        unheard = ProbeJob<void>((ctx) {
          counting = true;
          // Deaf to the stop until the test lets it go: the owner must not
          // find it over and pass it by.
          return release.future;
        }, key: 'unheard');
        // The routine of the root is in the zone as well: it is the owner
        // that comes back.
        runZoned(
          () {
            root = Job<void>((ctx) async {
              try {
                await ctx.runAll([failing, unheard]);
              } on Object catch (error) {
                thrown = error;
              }
              gate.complete();
              await delay(1);
            });
          },
          zoneSpecification: ZoneSpecification(
            registerUnaryCallback: <S, T>(self, parent, zone, callback) {
              // An `await` in the zone comes through here as well, with a
              // callback that takes anything; only the ones that listen for
              // an outcome count, and of those only the group's. It listens
              // for a branch first as it forms, and again when the owner
              // takes it up. The owner's own listening is on a stack of its
              // own, never the one that runs out, and passes.
              if (counting &&
                  <T>[] is List<Outcome<Object?>> &&
                  StackTrace.current.toString().contains(
                    '_RunAllGroup._hear',
                  ) &&
                  ++groupListened <= 2) {
                throw const StackOverflowError();
              }
              return parent.registerUnaryCallback(zone, callback);
            },
          ),
        );
      }, (error, _) => zone.add(error));
      await delay(10);
      expect(
        groupListened,
        isPositive,
        reason:
            'the zone tells the group by the frame of `_RunAllGroup._hear`; '
            'with no such frame it refuses nothing, and the branches wait for '
            'each other for good',
      );
      release.complete();
      await _ends(root);
      await delay(1);

      expect(thrown, isA<StackOverflowError>());
      expect(root.outcome, isA<Done<void>>());
      expect(
        failing.outcome,
        isA<Failed>().having((failed) => failed.error, 'error', isStateError),
      );
      expect(unheard.outcome, isA<Cancelled>());
      expect(
        zone,
        [isA<StackOverflowError>()],
        reason:
            'the end of a group is tried once: taken up a second time, it '
            'would decide and hand on the failure of the branch, and an end '
            'that throws every time would be taken up without end',
      );
      expect(
        groupListened,
        2,
        reason:
            'the group listened as it formed, and once more when the owner '
            'took it up',
      );
    },
  );
}

/// Calls [then] when a job starts.
final class _OnStart extends JobObserver {
  final void Function() then;

  _OnStart(this.then);

  @override
  void onStart(Job<Object?> job) => then();
}

/// A zone with no stack for whoever listens for an outcome next.
///
/// Stands in for the bottom of a stack under a group that has started a
/// branch and is about to listen for how it ends.
final class _NoStackForListener {
  /// Whether the next one to listen for an outcome finds no stack.
  bool outOfStack = false;

  /// Runs [body] in the zone.
  R run<R>(R Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      registerUnaryCallback: <S, T>(self, parent, zone, callback) {
        // An `await` in the zone comes through here as well, with a
        // callback that takes anything; the group asks for an outcome.
        if (outOfStack && <T>[] is List<Outcome<Object?>>) {
          outOfStack = false;
          throw const StackOverflowError();
        }
        return parent.registerUnaryCallback(zone, callback);
      },
    ),
  );
}

/// A tree every level of which starts the next one before its first
/// `await`.
final class _Tree {
  /// The body of a level: how it starts the next one.
  final Future<void> Function(_Tree tree, JobContext ctx, int level) _grow;

  /// Every job made, started or not.
  ///
  /// It grows at the bottom of the stack. Under the VM, a stack that runs out
  /// inside `add` can leave a `null` at the end of the list: a test that fails
  /// on a `null` job read from here has met that limit of the VM and says
  /// nothing about the tree.
  final jobs = <ProbeJob<void>>[];

  final _parentOf = Map<ProbeJob<void>, int>.identity();
  final _levels = <int, ProbeJob<void>>{};
  final _finishedAt = Map<Job<Object?>, int>.identity();
  final _release = Completer<void>();

  /// What reached the zone the tree was started in.
  final zone = <Object>[];

  int registered = 0;
  int disposed = 0;
  int _clock = 0;

  _Tree(this._grow);

  /// The job of [level], for the level above to start.
  ProbeJob<void> level(int level) {
    final job = ProbeJob<void>(
      (ctx) => level == 0 ? Future.value() : _grow(this, ctx, level),
      key: level,
    );
    jobs.add(job);
    _levels[level] = job;
    _parentOf[job] = level + 1;
    return job;
  }

  /// A child of [level] that outlives the descent.
  ///
  /// It waits for the test and not for a timer: a timer made where the
  /// stack is about to run out is a way to lose every timer of the
  /// isolate, and that is not what these tests are about.
  ProbeJob<void> leaf(int level) {
    final job = ProbeJob<void>((ctx) => _release.future, key: 'leaf of $level');
    jobs.add(job);
    _parentOf[job] = level;
    return job;
  }

  /// Builds the tree [frames] frames below the body of its root, waits for
  /// the root and checks what is left.
  Future<void> runsOut(int depth, int frames) async {
    final shifted = 'shifted by $frames frames';
    // From inside the loop of the microtask queue, where a job made by
    // `Job(...)` starts as well. The first microtask of an event callback,
    // scheduled where the stack is about to run out, is a way to leave the
    // isolate with no microtask queue at all, and after that not even a
    // failure of this test would be heard.
    await null;
    late ProbeJob<void> root;
    runZonedGuarded(() {
      root = ProbeJob<void>(
        (ctx) {
          late Future<void> below;
          _lower(frames, () => below = ctx.run(level(depth)));
          return below;
        },
        key: 'root',
        observer: FinishHook((job) => _finishedAt[job] = _clock++),
      )..launch();
    }, (error, _) => zone.add(error));
    _levels[depth + 1] = root;
    // Long enough for a level that does not wait for its leaf to end
    // before it.
    await delay(20);
    _release.complete();

    final outcome = await root.done.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail(
        'the root never ended, $shifted: ${jobs.length} jobs made, '
        '${jobs.where((job) => job.isFinished).length} of them finished',
      ),
    );
    // Whatever reaches the zone gets there a microtask after the job it
    // belongs to has ended.
    await delay(10);

    expect(
      outcome,
      isA<Failed>().having(
        (failed) => failed.error,
        'error',
        isA<StackOverflowError>(),
      ),
      reason: shifted,
    );
    expect(
      jobs.length,
      lessThan(depth),
      reason: 'the tree must not fit on the stack',
    );
    expect(
      [
        for (final job in jobs)
          if (job.isRunning) job.key,
      ],
      isEmpty,
      reason: 'jobs left running for good, $shifted',
    );
    expect(
      [
        for (final job in [root, ...jobs])
          if (job.childCount > 0) job.key,
      ],
      isEmpty,
      reason: 'jobs still waiting for a child, $shifted',
    );
    expect(
      [
        for (final MapEntry(key: job, value: above) in _parentOf.entries)
          // A job nobody took is not finished and has no place in the
          // order: its level ran out of stack before `run` got to it.
          if (_finishedAt[job] case final mine?)
            if (_finishedAt[_levels[above]] case final parent?
                when parent < mine)
              job.key,
      ],
      isEmpty,
      reason: 'jobs that outlived their parent, $shifted',
    );
    expect(
      zone,
      everyElement(isA<StackOverflowError>()),
      reason: 'the zone hears nothing but the overflow, $shifted',
    );
  }
}

/// The bottom of the stack, and the calls made just above it.
///
/// [at] makes a call so far down that it finds room for a part of its work
/// and not for the rest. From one number to the next that part is a frame
/// longer, and the [calls] numbers between them stand on both sides of the
/// place where the stack runs out.
final class _Bottom {
  /// The levels of the way down the calls are made on.
  static const levels = 40;

  /// The calls made on a level, each a frame lower than the one before.
  static const steps = 24;

  /// The calls there are, numbered from zero.
  static const calls = levels * steps;

  var _reached = 0;
  var _from = 0;

  /// Walks down to where the stack runs out.
  void find() {
    // More than once: the bottom moves while the VM is still compiling the
    // way down.
    for (var warm = 0; warm < 8; warm++) {
      try {
        _descend(0, -1, 0, null);
      } on Object catch (error) {
        if (error is! StackOverflowError) {
          rethrow;
        }
      }
    }
    // A few of the levels lie below what was reached: the bottom moves
    // afterwards as well, by less.
    _from = _reached - levels + 8;
  }

  /// Makes [call] at the depth its [number] stands for.
  void at(int number, void Function() call) {
    try {
      _descend(0, _from + number ~/ steps, number % steps, call);
    } on Object catch (error) {
      if (error is! StackOverflowError) {
        rethrow;
      }
      // The way down ran out before the level: the call was never made.
    }
  }

  @pragma('vm:never-inline')
  void _descend(int depth, int stop, int lower, void Function()? call) {
    _reached = depth;
    if (depth == stop) {
      try {
        _lowerBy(lower, call!);
      } on Object catch (error) {
        if (error is! StackOverflowError) {
          rethrow;
        }
        // The stack ran out under the call, and what that left behind is
        // the subject. Caught on the level and not at the top of the way:
        // a handler is looked for through every frame an error passes, and
        // there are thousands of them above.
      }
      return;
    }
    _descend(depth + 1, stop, lower, call);
  }

  @pragma('vm:never-inline')
  void _lowerBy(int frames, void Function() call) {
    if (frames > 0) {
      _lowerBy(frames - 1, call);
      return;
    }
    call();
  }
}

/// Waits for [job], and not for good: a job these tests are about is one
/// that used never to end.
Future<Outcome<T>> _ends<T>(Job<T> job) =>
    job.done.timeout(const Duration(seconds: 5));

/// Calls [then] [frames] frames below the caller.
///
/// Answers the number of frames, counted on the way back up, so that no
/// call here is the last thing its frame does and none can be dropped.
int _lower(int frames, void Function() then) {
  if (frames == 0) {
    then();
    return 0;
  }
  return _lower(frames - 1, then) + 1;
}

final class _Heard extends JobObserver {
  final List<String> log;

  _Heard(this.log);

  @override
  void onStart(Job<Object?> job) => log.add('start ${job.key}');

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => log.add('error ${job.key} ${error.runtimeType}');

  @override
  void onFinish(Job<Object?> job) => log.add('finish ${job.key}');
}
