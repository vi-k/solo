@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/cancel_reason.dart';
import 'support/delay.dart';
import 'support/error_observer.dart';
import 'support/journal.dart';
import 'support/probe_job.dart';

void main() {
  test('the values come back in the order of the list', () {
    fakeAsync((async) {
      List<int>? values;
      Job<void>((ctx) async {
        values = await ctx.runAll([
          // The second one finishes first; the list still decides.
          Job.deferred<int>(key: 'a', (ctx) async {
            await ctx.wait(() => delay(50));
            return 1;
          }),
          Job.deferred<int>(key: 'b', (ctx) async => 2),
        ]);
      }).ignore();
      async.flushTimers();
      expect(values, [1, 2]);
    });
  });

  test('an empty group starts nothing and answers as run would', () {
    fakeAsync((async) {
      List<int>? values;
      Object? fromUnattended;
      Object? fromCancelled;
      Object? fromFinished;
      late JobContext outlived;
      final parent = ProbeJob<void>((ctx) async {
        outlived = ctx;
        values = await ctx.runAll(const <Job<int>>[]);
        ctx.unattended(() {
          try {
            ctx.runAll(const <Job<int>>[]).ignore();
          } on Object catch (error) {
            fromUnattended = error;
          }
        });
        await ctx.wait(() => delay(50));
      })
        ..launch();
      async.elapse(const Duration(milliseconds: 10));
      expect(values, isEmpty);
      expect(fromUnattended, isA<StateError>());
      parent.cancelBy(
        Cancelled.by(
          reason: const TestCancelReason('manual'),
          started: true,
          stackTrace: StackTrace.current,
        ),
      );
      try {
        outlived.runAll(const <Job<int>>[]).ignore();
      } on Object catch (error) {
        fromCancelled = error;
      }
      async.elapse(const Duration(milliseconds: 10));
      try {
        outlived.runAll(const <Job<int>>[]).ignore();
      } on Object catch (error) {
        fromFinished = error;
      }
      expect(fromCancelled, isA<Cancelled>());
      expect(fromFinished, isA<StateError>());
    });
  });

  test('a failing branch stops its siblings before it ends itself', () {
    fakeAsync((async) {
      final descendant = Completer<void>();
      var groupReturned = false;
      Object? thrown;
      final failing = Job.deferred<int>(key: 'a', (ctx) async {
        // A descendant of its own, held by the test: the branch cannot end
        // while it runs, and a failure does not cascade onto it.
        ctx
            .run(
              Job.deferred<void>(
                key: 'a-child',
                (ctx) => ctx.join(() => descendant.future),
              ),
            )
            .ignore();
        throw StateError('boom');
      });
      final neighbour = Job.deferred<int>(key: 'b', (ctx) async {
        await ctx.wait(() => delay(1000));
        return 2;
      });
      Job<void>((ctx) async {
        try {
          await ctx.runAll([failing, neighbour]);
        } on Object catch (error) {
          thrown = error;
        }
        groupReturned = true;
      }).ignore();
      async.elapse(const Duration(milliseconds: 20));
      expect(
        neighbour.outcome,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<SiblingCancelReason>(),
        ),
        reason: 'the neighbour is stopped while the source is still running',
      );
      expect(failing.isFinished, isFalse, reason: 'it waits for its own child');
      expect(groupReturned, isFalse);
      descendant.complete();
      async.flushTimers();
      expect(thrown, isA<StateError>());
    });
  });

  test('the list is read once, by copy, before the first start', () {
    fakeAsync((async) {
      var passes = 0;
      Iterable<Job<int>> twice() sync* {
        passes++;
        yield Job.deferred<int>(key: 'a', (ctx) async => 1);
        yield Job.deferred<int>(key: 'b', (ctx) async => 2);
      }

      List<int>? values;
      Job<void>((ctx) async {
        values = await ctx.runAll(twice());
      }).ignore();
      async.flushTimers();
      expect(values, [1, 2]);
      expect(passes, 1);
    });
    fakeAsync((async) {
      // The body of the first branch appends to the list the snapshot was
      // made from: the group neither starts the newcomer nor waits for it.
      final source = <Job<int>>[];
      final extra = Job.deferred<int>(key: 'extra', (ctx) async => 99);
      source
        ..add(
          Job.deferred<int>(key: 'a', (ctx) async {
            source.add(extra);
            return 1;
          }),
        )
        ..add(Job.deferred<int>(key: 'b', (ctx) async => 2));
      List<int>? values;
      Job<void>((ctx) async {
        values = await ctx.runAll(source);
      }).ignore();
      async.flushTimers();
      expect(values, [1, 2]);
      expect(extra.outcome, isNull);
      expect(extra.isRunning, isFalse);
    });
    fakeAsync((async) {
      // The generator throws half way through: the same object comes out,
      // synchronously, and nothing that was listed before it has started.
      final boom = StateError('generator');
      final first = Job.deferred<int>(key: 'a', (ctx) async => 1);
      Iterable<Job<int>> broken() sync* {
        yield first;
        throw boom;
      }

      Object? thrown;
      Job<void>((ctx) async {
        try {
          ctx.runAll(broken()).ignore();
        } on Object catch (error) {
          thrown = error;
        }
      }).ignore();
      async.flushMicrotasks();
      expect(thrown, same(boom));
      expect(first.outcome, isNull);
      expect(first.isRunning, isFalse);
    });
  });

  test('the same child twice is refused before anything starts', () {
    fakeAsync((async) {
      final child = Job.deferred<int>(key: 'a', (ctx) async => 1);
      Object? thrown;
      Job<void>((ctx) async {
        try {
          ctx.runAll([child, child]).ignore();
        } on Object catch (error) {
          thrown = error;
        }
      }).ignore();
      async.flushMicrotasks();
      expect(thrown, isA<ArgumentError>());
      expect(child.outcome, isNull);
      expect(child.isRunning, isFalse);
    });
    fakeAsync((async) {
      // Two different jobs of a domain that compare equal by key are two
      // branches, not a repeat: the comparison is by identity.
      List<int>? values;
      Job<void>((ctx) async {
        values = await ctx.runAll([
          KeyedJob<int>(key: 'twin', (ctx) async => 1),
          KeyedJob<int>(key: 'twin', (ctx) async => 2),
        ]);
      }).ignore();
      async.flushTimers();
      expect(values, [1, 2]);
    });
  });

  test('a real failure beats a cancellation, whenever it arrives', () {
    for (final escapes in [false, true]) {
      fakeAsync((async) {
        final journal = JobJournal();
        final selected = StateError('selected');
        final cancelled = Job.deferred<int>(key: 'b', (ctx) async {
          await ctx.wait(() => delay(1000));
          return 2;
        });
        final failing = Job.deferred<int>(
          key: 'a',
          cancellable: false,
          (ctx) async {
            await ctx.wait(() => delay(50));
            throw selected;
          },
        );
        Object? thrown;
        final parent = Job<void>(
          key: 'parent',
          observer: journal,
          (ctx) async {
            if (escapes) {
              await ctx.runAll([failing, cancelled]);
              return;
            }
            try {
              await ctx.runAll([failing, cancelled]);
            } on Object catch (error) {
              thrown = error;
            }
          },
        )..ignore();
        async.elapse(const Duration(milliseconds: 10));
        cancelled.cancel().ignore();
        async.flushTimers();
        expect(cancelled.outcome, isA<Cancelled>());
        expect(failing.outcome, isA<Failed>());
        if (!escapes) {
          expect(thrown, same(selected));
          expect(parent.outcome, isA<Done<void>>());
        }
        expect(
          journal.take().where((line) => line.contains('error')).toList(),
          escapes
              ? [
                  '> [a] error Bad state: selected',
                  '[parent] error Bad state: selected',
                ]
              : ['> [a] error Bad state: selected'],
          reason: 'the branch tells the observer, and the group never '
              'retells what the caller received',
        );
      });
    }
  });

  test('a failure covered by the stop does not beat a real cancellation', () {
    final zone = <Object>[];
    final journal = JobJournal();
    final covered = StateError('covered');
    Object? thrown;
    Outcome<int>? acceptingOutcome;
    Outcome<int>? foreignOutcome;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final accepting = Job.deferred<int>(key: 'a', (ctx) async {
            try {
              await ctx.wait(() => delay(1000));
              return 1;
            } finally {
              // The point of the run: a failure after the mark is the body
              // giving up, not a diagnosis of its own.
              // ignore: throw_in_finally
              throw covered;
            }
          });
          final foreign = Job.deferred<int>(key: 'b', (ctx) async {
            await ctx.wait(() => delay(1000));
            return 2;
          });
          Job<void>(key: 'parent', observer: journal, (ctx) async {
            try {
              await ctx.runAll([accepting, foreign]);
            } on Object catch (error) {
              thrown = error;
            }
          }).ignore();
          async.elapse(const Duration(milliseconds: 10));
          foreign.cancel().ignore();
          async.flushTimers();
          acceptingOutcome = accepting.outcome;
          foreignOutcome = foreign.outcome;
        });
      },
      (error, stackTrace) => zone.add(error),
    );
    // Outside the guarded zone, every one of them: an `expect` that fails
    // inside it is caught by the handler, added to `zone`, and never fails
    // the test.
    expect(
      acceptingOutcome,
      isA<Cancelled>().having(
        (cancelled) => cancelled.reason,
        'reason',
        isA<SiblingCancelReason>(),
      ),
      reason: 'a failure thrown after the mark is the body giving up',
    );
    expect(thrown, same(foreignOutcome));
    expect(
      journal.take().where((line) => line.contains('error')).toList(),
      ['> [a] error Bad state: covered'],
      reason: 'the observer of the branch hears it, and only it',
    );
    expect(zone, isEmpty);
  });

  test('the cancellation that comes out names the branch it came from', () {
    fakeAsync((async) {
      final descendant = Completer<void>();
      final branch = Job.deferred<int>(key: 'b', (ctx) async {
        ctx
            .run(
              Job.deferred<void>(
                key: 'b-child',
                (ctx) => ctx.join(() => descendant.future),
              ),
            )
            .ignore();
        throw const Cancelled('gave up');
      });
      Object? thrown;
      Job<void>((ctx) async {
        try {
          await ctx.runAll([branch]);
        } on Object catch (error) {
          thrown = error;
        }
      }).ignore();
      async.elapse(const Duration(milliseconds: 10));
      // The outcome of the branch is replaced while it waits for its own
      // child: the object the early seam saw is not the object that ends
      // it, and only the second one may come out.
      branch.cancel(reason: const TestCancelReason('outside')).ignore();
      descendant.complete();
      async.flushTimers();
      expect(thrown, same(branch.outcome));
      expect(
        thrown,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<TestCancelReason>(),
        ),
      );
    });
    fakeAsync((async) {
      // The same cancellation let out of the body of the parent: the
      // kernel classifies it, finds the branch behind it and says so.
      var heardCancelled = 0;
      final branch = Job.deferred<int>(key: 'b', (ctx) async {
        await ctx.wait(() => delay(1000));
        return 1;
      });
      final parent = Job<void>(key: 'parent', (ctx) async {
        await ctx.runAll([branch]);
      })
        ..ignore()
        ..whenCancelled((_) => heardCancelled++);
      async.elapse(const Duration(milliseconds: 10));
      branch.cancel(reason: const TestCancelReason('outside')).ignore();
      async.flushTimers();
      expect(
        parent.outcome,
        isA<Cancelled>()
            .having(
              (cancelled) => cancelled.reason,
              'reason',
              isA<HandlerCancelReason>().having(
                (reason) => reason.cause,
                'cause',
                same(branch.outcome),
              ),
            )
            .having(
              (cancelled) => cancelled.description,
              'description',
              startsWith('child b: '),
            ),
      );
      expect(heardCancelled, 1);
    });
  });

  test('the first outcome to arrive wins, whatever the list order', () {
    for (final listOrder in ['ab', 'ba']) {
      for (final finishOrder in ['ab', 'ba']) {
        fakeAsync((async) {
          final gates = {'a': Completer<void>(), 'b': Completer<void>()};
          final errors = {'a': StateError('a'), 'b': StateError('b')};
          Job<int> branch(String name) => Job.deferred<int>(
                key: name,
                cancellable: false,
                (ctx) async {
                  ctx.onDispose(() => gates[name]!.future);
                  throw errors[name]!;
                },
              );

          final a = branch('a');
          final b = branch('b');
          Object? thrown;
          // An observer, so that the failure the group does not throw has
          // somewhere to go: where it goes is criterion ten's business.
          Job<void>(observer: ErrorObserver(<Object>[]), (ctx) async {
            try {
              await ctx.runAll(listOrder == 'ab' ? [a, b] : [b, a]);
            } on Object catch (error) {
              thrown = error;
            }
          }).ignore();
          async.flushMicrotasks();
          // The test decides the order the group learns the outcomes in.
          gates[finishOrder[0]]!.complete();
          async.flushMicrotasks();
          gates[finishOrder[1]]!.complete();
          async.flushTimers();
          expect(
            thrown,
            same(errors[finishOrder[0]]),
            reason: 'list $listOrder, finish $finishOrder',
          );
        });
      }
    }
  });

  test('the stop is cooperative and reaches only what listens', () {
    fakeAsync((async) {
      var written = false;
      final neighbour = Job.deferred<void>(key: 'b', (ctx) async {
        final device = Completer<void>();
        Timer? timer;
        ctx.onCancel(() {
          timer?.cancel();
          if (!device.isCompleted) device.complete();
        });
        await ctx.join(() {
          timer = Timer(const Duration(milliseconds: 100), () {
            written = true;
            if (!device.isCompleted) device.complete();
          });
          return device.future;
        });
      });
      Job<void>((ctx) async {
        try {
          await ctx.runAll([
            Job.deferred<void>(key: 'a', (ctx) async => throw StateError('go')),
            neighbour,
          ]);
        } on Object catch (_) {
          // The failure is the point of the run, not what it checks.
        }
      }).ignore();
      async.flushTimers();
      expect(written, isFalse, reason: 'the operation was handed the stop');
    });
    fakeAsync((async) {
      // The other half, and it is a boundary rather than a defect: a
      // branch that walks away from its operation ends, and the operation
      // plays out.
      var written = false;
      final neighbour = Job.deferred<void>(key: 'b', (ctx) async {
        await ctx.wait(() async {
          await delay(100);
          written = true;
        });
      });
      Job<void>((ctx) async {
        try {
          await ctx.runAll([
            Job.deferred<void>(key: 'a', (ctx) async => throw StateError('go')),
            neighbour,
          ]);
        } on Object catch (_) {
          // As above.
        }
      }).ignore();
      async.flushTimers();
      expect(written, isTrue);
    });
  });

  test('a cancellation this call asked for never comes out of it', () {
    final zone = <Object>[];
    final errors = <Object>[];
    Object? thrown;
    Outcome<int>? foreignOutcome;
    var stoppedFinishedFirst = false;
    var foreignStillHeldUp = false;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final tail = Completer<void>();
          // The branch the group stops finishes first; the branch somebody
          // else cancelled finishes last. Without the filter the first one
          // would be chosen.
          final stopped = Job.deferred<int>(key: 'a', (ctx) async {
            await ctx.wait(() => delay(1000));
            return 1;
          });
          final foreign = Job.deferred<int>(key: 'b', (ctx) async {
            ctx.onDispose(() => tail.future);
            await ctx.wait(() => delay(1000));
            return 2;
          });
          Job<void>(
            key: 'parent',
            observer: ErrorObserver(errors),
            (ctx) async {
              try {
                await ctx.runAll([stopped, foreign]);
              } on Object catch (error) {
                thrown = error;
              }
            },
          ).ignore();
          async.elapse(const Duration(milliseconds: 10));
          foreign.cancel(reason: const TestCancelReason('outside')).ignore();
          async.elapse(const Duration(milliseconds: 10));
          stoppedFinishedFirst = stopped.isFinished;
          foreignStillHeldUp = !foreign.isFinished;
          tail.complete();
          async.flushTimers();
          foreignOutcome = foreign.outcome;
        });
      },
      (error, stackTrace) => zone.add(error),
    );
    expect(stoppedFinishedFirst, isTrue, reason: 'ours arrives first');
    expect(foreignStillHeldUp, isTrue, reason: 'the other is held up');
    expect(thrown, same(foreignOutcome));
    expect(errors, isEmpty);
    expect(zone, isEmpty, reason: 'a cancellation is nobody’s failure');
  });

  test('a cancellation nobody asked for is trouble, whatever it wears', () {
    fakeAsync((async) {
      // The stop is recognised by whom this call asked, not by the kind of
      // reason the cancellation carries: `SiblingCancelReason` is public,
      // and anyone may build one.
      var neighbourFinishedItsWork = false;
      final neighbour = Job.deferred<int>(key: 'a', (ctx) async {
        await ctx.wait(() => delay(1000));
        neighbourFinishedItsWork = true;
        return 1;
      });
      final foreign = Job.deferred<int>(key: 'b', (ctx) async {
        await ctx.wait(() => delay(1000));
        return 2;
      });
      Object? thrown;
      Job<void>(key: 'parent', (ctx) async {
        try {
          await ctx.runAll([neighbour, foreign]);
        } on Object catch (error) {
          thrown = error;
        }
      }).ignore();
      async.elapse(const Duration(milliseconds: 10));
      foreign
          .cancel(reason: const SiblingCancelReason(cause: 'another group'))
          .ignore();
      async.flushTimers();
      expect(thrown, same(foreign.outcome));
      expect(
        neighbour.outcome,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<SiblingCancelReason>(),
        ),
      );
      expect(
        neighbourFinishedItsWork,
        isFalse,
        reason: 'the neighbour was stopped at once, not left to run out',
      );
    });
  });

  test('a branch registers on arrival what a child of its own opened', () {
    // The promise of `doc/children.md`: the branch that did not take the
    // resource itself is covered by the same recipe as anyone else, and
    // then everything the group promises holds for it too.
    final closed = <String>[];
    late Job<void> group;
    fakeAsync((async) {
      final opener = Job.deferred<String>(
        key: 'opener',
        (ctx) => ctx.wait(() => 'db', discard: closed.add),
      );
      final taker = Job.deferred<String>(
        key: 'taker',
        (ctx) => ctx.wait(() => ctx.run(opener), discard: closed.add),
      );
      final bad = Job.deferred<String>(key: 'bad', (ctx) async {
        await ctx.wait(() => delay(10));
        throw StateError('boom');
      });
      group = Job<void>(
        key: 'group',
        observer: ErrorObserver(<Object>[]),
        (ctx) async {
          await ctx.runAll([taker, bad]);
        },
      )..ignore();
      async.flushTimers();
    });
    expect(group.outcome, isA<Failed>());
    expect(
      closed,
      ['db'],
      reason: 'the branch closed it once, and before the group returned',
    );
  });

  test('a branch the group stopped never gives the group its outcome', () {
    fakeAsync((async) {
      // The request to stop can lose: a cancellation from elsewhere was
      // already held inside `uncancellable` and lands first. The branch
      // then ends with somebody else's object — and it is still the stop
      // this call asked for, so it is not what the group gives back.
      final inside = Completer<void>();
      final tail = Completer<void>();
      final stopped = Job.deferred<int>(key: 'b', (ctx) async {
        await ctx.uncancellable(() => inside.future);
        return 2;
      });
      final source = Job.deferred<int>(key: 'a', (ctx) async {
        ctx.onDispose(() => tail.future);
        await ctx.wait(() => delay(10));
        throw const Cancelled('a gave up');
      });
      Object? thrown;
      Job<void>(key: 'parent', (ctx) async {
        try {
          await ctx.runAll([source, stopped]);
        } on Object catch (error) {
          thrown = error;
        }
      }).ignore();
      async.elapse(const Duration(milliseconds: 5));
      // Held, not accepted: the branch is inside an uncancellable step.
      stopped.cancel(reason: const TestCancelReason('outside')).ignore();
      async.elapse(const Duration(milliseconds: 20));
      inside.complete();
      async.elapse(const Duration(milliseconds: 10));
      expect(stopped.isFinished, isTrue, reason: 'it ends first of the two');
      expect(source.isFinished, isFalse);
      tail.complete();
      async.flushTimers();
      expect(
        stopped.outcome,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<TestCancelReason>(),
        ),
        reason: "the request lost: the object is not the group's",
      );
      expect(
        thrown,
        same(source.outcome),
        reason: 'and the group still gives back the branch nobody stopped',
      );
    });
  });

  test('between two cancellations the first one to arrive wins', () {
    for (final dropOrder in ['ab', 'ba']) {
      fakeAsync((async) {
        // Two branches are ended by hand while they stand at the second
        // barrier, one after the other in the same synchronous burst. The
        // group asked neither of them to stop, so both are outcomes of its
        // own; the one it learned first is the one it gives back.
        final gate = Completer<void>();
        final cancellations = {
          for (final name in ['a', 'b'])
            name: Cancelled.by(
              reason: TestCancelReason('dropped-$name'),
              started: true,
              stackTrace: StackTrace.current,
            ),
        };
        final dropped = {
          for (final name in ['a', 'b'])
            name: ProbeJob<int>(key: name, (ctx) async => 1),
        };
        // The slow branch keeps the group in the first pass, so the other
        // two are standing at the second barrier when they are dropped.
        final slow = Job.deferred<int>(key: 'slow', (ctx) async {
          ctx.onDispose(() => gate.future);
          return 3;
        });
        Object? thrown;
        Job<void>(key: 'parent', (ctx) async {
          try {
            await ctx.runAll(<Job<int>>[dropped['a']!, dropped['b']!, slow]);
          } on Object catch (error) {
            thrown = error;
          }
        }).ignore();
        async.flushMicrotasks();
        expect(dropped['a']!.isFinished, isFalse, reason: 'both are held');
        dropped[dropOrder[0]]!.drop(cancellations[dropOrder[0]]!);
        dropped[dropOrder[1]]!.drop(cancellations[dropOrder[1]]!);
        gate.complete();
        async.flushTimers();
        expect(
          thrown,
          same(cancellations[dropOrder[0]]),
          reason: 'drop order $dropOrder',
        );
        expect(
          slow.outcome,
          isA<Cancelled>().having(
            (cancelled) => cancelled.reason,
            'reason',
            isA<SiblingCancelReason>(),
          ),
          reason: 'and the branch the group stopped is not in the running',
        );
      });
    }
  });

  test('a failure the group received and did not throw is not lost', () {
    fakeAsync((async) {
      final journal = JobJournal();
      final chosen = StateError('chosen');
      final other = StateError('other');
      Job<void>(key: 'parent', observer: journal, (ctx) async {
        try {
          await ctx.runAll([
            Job.deferred<int>(key: 'a', (ctx) async => throw chosen),
            Job.deferred<int>(
              key: 'b',
              cancellable: false,
              (ctx) async {
                await ctx.wait(() => delay(50));
                throw other;
              },
            ),
          ]);
        } on Object catch (_) {
          // Checked through the journal below.
        }
      }).ignore();
      async.flushTimers();
      expect(
        journal.take().where((line) => line.contains('error')).toList(),
        ['> [a] error Bad state: chosen', '> [b] error Bad state: other'],
        reason: 'each branch announces its own failure once, and the group '
            'announces neither',
      );
    });
    final zone = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final chosen = StateError('chosen');
          final other = StateError('other');
          Job<void>(key: 'parent', (ctx) async {
            try {
              await ctx.runAll([
                Job.deferred<int>(key: 'a', (ctx) async => throw chosen),
                Job.deferred<int>(
                  key: 'b',
                  cancellable: false,
                  (ctx) async {
                    await ctx.wait(() => delay(50));
                    throw other;
                  },
                ),
              ]);
            } on Object catch (_) {
              // Checked through the zone below.
            }
          }).ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => zone.add(error),
    );
    // Outside the guarded zone: an `expect` that fails inside it lands in
    // the handler and is counted as a zone error instead of failing.
    expect(
      zone.map((error) => '$error').toList(),
      ['Bad state: other'],
      reason: 'with nobody watching, the one nobody received goes to the '
          'zone, once',
    );
  });

  test('a failure that never went through a body is not lost either', () {
    for (final withObserver in [false, true]) {
      final zone = <Object>[];
      final heard = <Object>[];
      final chosen = StateError('chosen');
      final other = StateError('other');
      runZonedGuarded(
        () {
          fakeAsync((async) {
            // An engine of a domain may end a branch by hand while it
            // stands at a barrier. Such a failure went through no body, so
            // nobody announced it: the group is the last one holding it.
            final gate = Completer<void>();
            final dropped = {
              for (final name in ['a', 'b'])
                name: ProbeJob<int>(key: name, (ctx) async => 1),
            };
            final slow = Job.deferred<int>(key: 'slow', (ctx) async {
              ctx.onDispose(() => gate.future);
              return 3;
            });
            Job<void>(
              key: 'parent',
              observer: withObserver ? ErrorObserver(heard) : null,
              (ctx) async {
                try {
                  await ctx
                      .runAll(<Job<int>>[dropped['a']!, dropped['b']!, slow]);
                } on Object catch (_) {
                  // Which one comes out is settled by the arrival order.
                }
              },
            ).ignore();
            async.flushMicrotasks();
            dropped['a']!.drop(Failed(chosen, StackTrace.current));
            dropped['b']!.drop(Failed(other, StackTrace.current));
            gate.complete();
            async.flushTimers();
          });
        },
        (error, stackTrace) => zone.add(error),
      );
      // Outside the guarded zone: a failing `expect` inside it would be
      // swallowed by the handler and never fail the test.
      expect(
        heard.where((error) => identical(error, other)).length,
        withObserver ? 1 : 0,
        reason: 'observer: $withObserver',
      );
      expect(
        zone.where((error) => identical(error, other)).length,
        withObserver ? 0 : 1,
        reason: 'observer: $withObserver',
      );
    }
  });

  test('a refusal of admission stops whatever already started', () {
    fakeAsync((async) {
      final started = <Job<int>>[
        Job.deferred<int>(key: 'a', (ctx) async {
          await ctx.wait(() => delay(1000));
          return 1;
        }),
        Job.deferred<int>(key: 'b', (ctx) async {
          await ctx.wait(() => delay(1000));
          return 2;
        }),
      ];
      // The third handle starts itself, and the kernel refuses it.
      final refused = Job<int>(key: 'c', (ctx) async => 3)..ignore();
      Object? thrown;
      final zone = <Object>[];
      runZonedGuarded(
        () {
          Job<void>((ctx) async {
            try {
              await ctx.runAll([...started, refused]);
            } on Object catch (error) {
              thrown = error;
            }
          }).ignore();
          async.flushTimers();
        },
        (error, stackTrace) => zone.add(error),
      );
      expect(thrown, isA<ArgumentError>());
      for (final branch in started) {
        expect(
          branch.outcome,
          isA<Cancelled>().having(
            (cancelled) => cancelled.reason,
            'reason',
            isA<SiblingCancelReason>(),
          ),
        );
      }
      expect(zone, isEmpty);
    });
    final zone = <Object>[];
    Object? refusal;
    Outcome<int>? stubbornOutcome;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          // A branch that refuses the stop and then fails: the refusal of
          // admission is still what comes out, and the failure is not lost.
          final other = StateError('other');
          final stubborn = Job.deferred<int>(
            key: 'a',
            cancellable: false,
            (ctx) async {
              await ctx.wait(() => delay(50));
              throw other;
            },
          );
          final refused = Job<int>(key: 'c', (ctx) async => 3)..ignore();
          Object? thrown;
          Job<void>((ctx) async {
            try {
              await ctx.runAll([stubborn, refused]);
            } on Object catch (error) {
              thrown = error;
            }
          }).ignore();
          async.flushTimers();
          refusal = thrown;
          stubbornOutcome = stubborn.outcome;
        });
      },
      (error, stackTrace) => zone.add(error),
    );
    expect(refusal, isA<ArgumentError>());
    expect(stubbornOutcome, isA<Failed>());
    expect(zone.map((error) => '$error').toList(), ['Bad state: other']);
  });

  test('the cancellation of the parent wins over the group', () {
    fakeAsync((async) {
      // In the middle of the waiting.
      final errors = <Object>[];
      final branches = [
        for (final key in ['a', 'b'])
          Job.deferred<int>(key: key, (ctx) async {
            await ctx.wait(() => delay(1000));
            return 1;
          }),
      ];
      Cancelled? accepted;
      final parent = Job<void>(
        key: 'parent',
        observer: ErrorObserver(errors),
        (ctx) async => ctx.runAll(branches),
      )
        ..ignore()
        ..whenCancelled((cancelled) => accepted = cancelled);
      async.elapse(const Duration(milliseconds: 10));
      parent.cancel().ignore();
      async.flushTimers();
      expect(parent.outcome, same(accepted));
      for (final branch in branches) {
        expect(
          branch.outcome,
          isA<Cancelled>().having(
            (cancelled) => cancelled.reason,
            'reason',
            isA<ParentCancelReason>(),
          ),
        );
      }
      expect(errors, isEmpty);
    });
    fakeAsync((async) {
      // The cancellation arrives when the error is already chosen, and it
      // wins: that is the rule of the kernel, not of the group.
      final errors = <Object>[];
      final held = Completer<void>();
      final parent = Job<void>(
        key: 'parent',
        observer: ErrorObserver(errors),
        (ctx) async => ctx.runAll([
          Job.deferred<int>(key: 'a', (ctx) async => throw StateError('boom')),
          Job.deferred<int>(key: 'b', (ctx) async {
            ctx.onDispose(() => held.future);
            await ctx.wait(() => delay(1000));
            return 2;
          }),
        ]),
      )..ignore();
      async.elapse(const Duration(milliseconds: 10));
      parent.cancel().ignore();
      held.complete();
      async.flushTimers();
      expect(parent.outcome, isA<Cancelled>());
    });
    fakeAsync((async) {
      // After the commit: the list is already in the caller's hands, and
      // nothing the cancellation does can take the resources back.
      var closes = 0;
      List<String>? values;
      final parent = Job<void>(key: 'parent', (ctx) async {
        values = await ctx.runAll([
          for (final key in ['a', 'b'])
            Job.deferred<String>(
              key: key,
              (ctx) => ctx.wait(() async => key, discard: (_) => closes++),
            ),
        ]);
        await ctx.wait(() => delay(1000));
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 10));
      expect(values, ['a', 'b']);
      parent.cancel().ignore();
      async.flushTimers();
      expect(parent.outcome, isA<Cancelled>());
      expect(closes, 0, reason: 'the values were handed over before it came');
    });
  });

  test('the group checks the parent before it commits, and reads again', () {
    for (final trigger in ['cancel', 'rules', 'reentrant']) {
      fakeAsync((async) {
        var continued = false;
        var closes = 0;
        List<int>? values;
        Object? thrown;
        final stubborn = [
          for (final key in ['a', 'b'])
            Job.deferred<int>(
              key: key,
              cancellable: trigger == 'reentrant',
              (ctx) async {
                await ctx.wait(() => delay(50));
                // A resource taken for the caller: on every one of these
                // paths the caller gets an error instead, so the branch
                // has to close it itself.
                return ctx.wait(() async => 1, discard: (_) => closes++);
              },
            ),
        ];
        late CheckingContext context;
        final parent = CheckingJob<void>(key: 'parent', (ctx) async {
          context = ctx;
          try {
            values = await ctx.runAll(stubborn);
            continued = true;
          } on Object catch (error) {
            thrown = error;
          }
        })
          ..launch();
        switch (trigger) {
          case 'cancel':
            // The parent is already cancelled, and both branches refused
            // the cascade and kept their values.
            async.elapse(const Duration(milliseconds: 10));
            parent.cancelBy(
              Cancelled.by(
                reason: const TestCancelReason('outside'),
                started: true,
                stackTrace: StackTrace.current,
              ),
            );
          case 'rules':
            // The parent is not marked at all, and the rules of the domain
            // refuse when the group asks.
            context.rules = () => throw const Cancelled('keepWhile');
          case 'reentrant':
            // The rules answer yes and cancel a branch on the way.
            context.rules = () => stubborn.first.cancel().ignore();
        }
        async.flushTimers();
        expect(continued, isFalse, reason: trigger);
        expect(values, isNull, reason: trigger);
        expect(thrown, isA<Cancelled>(), reason: trigger);
        expect(
          closes,
          trigger == 'reentrant' ? 2 : 0,
          reason: trigger == 'reentrant'
              ? 'both branches took the stop and closed what they held'
              : 'both refused the stop and hand their values over through '
                  'their own `value`: the named boundary of cancellable '
                  'false',
        );
      });
    }
  });

  test('a cancellation from outside a branch comes out as it is', () {
    fakeAsync((async) {
      final outside = Job.deferred<int>(key: 'b', (ctx) async {
        await ctx.wait(() => delay(1000));
        return 2;
      });
      final neighbour = Job.deferred<int>(key: 'a', (ctx) async {
        await ctx.wait(() => delay(1000));
        return 1;
      });
      final parent = Job<void>(
        key: 'parent',
        (ctx) async => ctx.runAll([neighbour, outside]),
      )..ignore();
      async.elapse(const Duration(milliseconds: 10));
      outside.cancel(reason: const TestCancelReason('outside')).ignore();
      async.flushTimers();
      expect(
        parent.outcome,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<HandlerCancelReason>().having(
            (reason) => reason.cause,
            'cause',
            same(outside.outcome),
          ),
        ),
      );
      expect(
        neighbour.outcome,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<SiblingCancelReason>(),
        ),
      );
    });
  });

  test('a resource a branch took for the caller is closed by the branch', () {
    fakeAsync((async) {
      // The branch returned its value and a sibling failed afterwards.
      final resource = Object();
      final closed = <Object>[];
      final holder = Job.deferred<Object>(
        key: 'db',
        (ctx) => ctx.wait(() async => resource, discard: closed.add),
      );
      Job<void>(observer: ErrorObserver(<Object>[]), (ctx) async {
        try {
          await ctx.runAll([
            holder,
            Job.deferred<Object>(key: 'bad', (ctx) async {
              await ctx.wait(() => delay(50));
              throw StateError('late');
            }),
          ]);
        } on Object catch (_) {
          // The closing is what this checks.
        }
      }).ignore();
      async.flushTimers();
      expect(closed, [same(resource)]);
      expect(
        holder.outcome,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<SiblingCancelReason>(),
        ),
      );
    });
    fakeAsync((async) {
      // Full success: nothing is closed, and the caller holds it.
      final resource = Object();
      final closed = <Object>[];
      List<Object>? values;
      Job<void>((ctx) async {
        values = await ctx.runAll([
          Job.deferred<Object>(
            key: 'db',
            (ctx) => ctx.wait(() async => resource, discard: closed.add),
          ),
          Job.deferred<Object>(key: 'x', (ctx) async => 'x'),
        ]);
      }).ignore();
      async.flushTimers();
      expect(values, [same(resource), 'x']);
      expect(closed, isEmpty);
    });
    fakeAsync((async) {
      // The parent caught the error and returned success: by the time it
      // catches, the closing has already happened.
      final closed = <Object>[];
      var closedAtCatch = -1;
      Job<void>(observer: ErrorObserver(<Object>[]), (ctx) async {
        try {
          await ctx.runAll([
            Job.deferred<Object>(
              key: 'db',
              (ctx) => ctx.wait(() async => Object(), discard: closed.add),
            ),
            Job.deferred<Object>(key: 'bad', (ctx) async {
              await ctx.wait(() => delay(50));
              throw StateError('late');
            }),
          ]);
        } on Object catch (_) {
          closedAtCatch = closed.length;
        }
      }).ignore();
      async.flushTimers();
      expect(closedAtCatch, 1);
    });
    fakeAsync((async) {
      // A branch that refuses the stop ends [Done] and hands its value
      // over through its own `value`: nothing is closed. A boundary, and
      // it is written down as one.
      final closed = <Object>[];
      final stubborn = Job.deferred<Object>(
        key: 'db',
        cancellable: false,
        (ctx) => ctx.wait(() async => Object(), discard: closed.add),
      );
      Job<void>(observer: ErrorObserver(<Object>[]), (ctx) async {
        try {
          await ctx.runAll([
            stubborn,
            Job.deferred<Object>(key: 'bad', (ctx) async {
              await ctx.wait(() => delay(50));
              throw StateError('late');
            }),
          ]);
        } on Object catch (_) {
          // The closing is what this checks.
        }
      }).ignore();
      async.flushTimers();
      expect(stubborn.outcome, isA<Done<Object>>());
      expect(closed, isEmpty);
    });
  });

  test('the decision of the group is what runs the conditional cleanup', () {
    fakeAsync((async) {
      // The main input: the body of the branch succeeded, and its own
      // outcome would never have run these.
      final order = <String>[];
      final slow = Completer<void>();
      var groupReturned = false;
      final holder = Job.deferred<int>(key: 'db', (ctx) async {
        ctx
          ..onDiscard(() => order.add('first'))
          ..onDiscard(() async {
            order.add('second-start');
            await slow.future;
            order.add('second-end');
          });
        return 1;
      });
      Job<void>(observer: ErrorObserver(<Object>[]), (ctx) async {
        try {
          await ctx.runAll([
            holder,
            Job.deferred<int>(key: 'bad', (ctx) async {
              await ctx.wait(() => delay(50));
              throw StateError('late');
            }),
          ]);
        } on Object catch (_) {
          // The order below is what this checks.
        }
        groupReturned = true;
      }).ignore();
      async.elapse(const Duration(milliseconds: 100));
      expect(
        order,
        ['second-start'],
        reason: 'the last registration unwinds first, and it is awaited',
      );
      expect(groupReturned, isFalse, reason: 'the group waits for it');
      slow.complete();
      async.flushTimers();
      expect(order, ['second-start', 'second-end', 'first']);
      expect(groupReturned, isTrue);
    });
    fakeAsync((async) {
      // An error in that cleanup does not replace what comes out, and does
      // not stop the unwinding of the other branch.
      final errors = <Object>[];
      final closed = <String>[];
      final chosen = StateError('chosen');
      Object? thrown;
      Job<void>(observer: ErrorObserver(errors), (ctx) async {
        try {
          await ctx.runAll([
            Job.deferred<int>(key: 'a', (ctx) async {
              ctx.onDiscard(() => throw StateError('disposer'));
              return 1;
            }),
            Job.deferred<int>(key: 'b', (ctx) async {
              ctx.onDiscard(() => closed.add('b'));
              return 2;
            }),
            Job.deferred<int>(key: 'bad', (ctx) async {
              await ctx.wait(() => delay(50));
              throw chosen;
            }),
          ]);
        } on Object catch (error) {
          thrown = error;
        }
      }).ignore();
      async.flushTimers();
      expect(thrown, same(chosen));
      expect(closed, ['b']);
      expect(errors.map((error) => '$error'), contains('Bad state: disposer'));
    });
    fakeAsync((async) {
      // Two branches unwinding asynchronously at once: the order between
      // them is not promised, only that the group waits for both.
      final gates = {'a': Completer<void>(), 'b': Completer<void>()};
      final closed = <String>[];
      var groupReturned = false;
      Job<void>(observer: ErrorObserver(<Object>[]), (ctx) async {
        try {
          await ctx.runAll([
            for (final key in ['a', 'b'])
              Job.deferred<int>(key: key, (ctx) async {
                ctx.onDiscard(() async {
                  await gates[key]!.future;
                  closed.add(key);
                });
                return 1;
              }),
            Job.deferred<int>(key: 'bad', (ctx) async {
              await ctx.wait(() => delay(50));
              throw StateError('late');
            }),
          ]);
        } on Object catch (_) {
          // The waiting is what this checks.
        }
        groupReturned = true;
      }).ignore();
      async.elapse(const Duration(milliseconds: 100));
      expect(groupReturned, isFalse);
      gates['b']!.complete();
      async.elapse(const Duration(milliseconds: 10));
      expect(groupReturned, isFalse, reason: 'one of the two is still going');
      gates['a']!.complete();
      async.flushTimers();
      expect(closed, ['b', 'a']);
      expect(groupReturned, isTrue);
    });
  });

  test('a group inside a branch of a group stops both levels', () {
    fakeAsync((async) {
      final inner = StateError('inner');
      final outerNeighbour = Job.deferred<int>(key: 'outer-b', (ctx) async {
        await ctx.wait(() => delay(1000));
        return 2;
      });
      late Job<int> innerNeighbour;
      final branch = Job.deferred<int>(key: 'outer-a', (ctx) async {
        innerNeighbour = Job.deferred<int>(key: 'inner-b', (ctx) async {
          await ctx.wait(() => delay(1000));
          return 20;
        });
        final values = await ctx.runAll([
          Job.deferred<int>(key: 'inner-a', (ctx) async => throw inner),
          innerNeighbour,
        ]);
        return values.first;
      });
      Object? thrown;
      Job<void>(observer: ErrorObserver(<Object>[]), (ctx) async {
        try {
          await ctx.runAll([branch, outerNeighbour]);
        } on Object catch (error) {
          thrown = error;
        }
      }).ignore();
      async.flushTimers();
      expect(thrown, same(inner));
      for (final stopped in [innerNeighbour, outerNeighbour]) {
        expect(
          stopped.outcome,
          isA<Cancelled>().having(
            (cancelled) => cancelled.reason,
            'reason',
            isA<SiblingCancelReason>().having(
              (reason) => reason.cause,
              'cause',
              same(inner),
            ),
          ),
        );
      }
    });
    fakeAsync((async) {
      // The outer group does not commit while the inner one is still
      // holding its own branches.
      final held = Completer<void>();
      List<int>? values;
      Job<void>((ctx) async {
        values = await ctx.runAll([
          Job.deferred<int>(key: 'outer-a', (ctx) async {
            final inner = await ctx.runAll([
              Job.deferred<int>(
                key: 'inner-a',
                (ctx) => ctx.join(() async {
                  await held.future;
                  return 10;
                }),
              ),
              Job.deferred<int>(key: 'inner-b', (ctx) async => 20),
            ]);
            return inner.first;
          }),
          Job.deferred<int>(key: 'outer-b', (ctx) async => 2),
        ]);
      }).ignore();
      async.elapse(const Duration(milliseconds: 20));
      expect(values, isNull);
      held.complete();
      async.flushTimers();
      expect(values, [10, 2]);
    });
  });

  test('a branch is held before it unwinds, and let go on every path', () {
    for (final path in ['success', 'branch-error', 'parent-cancel']) {
      fakeAsync((async) {
        final slow = Completer<void>();
        var bodyEnded = false;
        var disposed = 0;
        var discarded = 0;
        final held = Job.deferred<int>(key: 'held', (ctx) async {
          ctx
            ..onDispose(() => disposed++)
            ..onDiscard(() => discarded++);
          bodyEnded = true;
          return 1;
        });
        final other = Job.deferred<int>(key: 'other', (ctx) async {
          await ctx.join(() => slow.future);
          if (path == 'branch-error') throw StateError('boom');
          return 2;
        });
        final parent = Job<void>(
          key: 'parent',
          observer: ErrorObserver(<Object>[]),
          (ctx) async {
            try {
              await ctx.runAll([held, other]);
            } on Object catch (_) {
              // What the group throws is other criteria's business.
            }
          },
        )..ignore();
        async.elapse(const Duration(milliseconds: 10));
        // First half: the branch is in the hold. Its body is over, it
        // registered its cleanups, and none of them has run.
        expect(bodyEnded, isTrue);
        expect(held.isFinished, isFalse);
        expect(disposed, 0, reason: 'the unwinding has not started');
        expect(discarded, 0);
        switch (path) {
          case 'parent-cancel':
            parent.cancel().ignore();
            slow.complete();
          case _:
            slow.complete();
        }
        async.flushTimers();
        expect(held.isFinished, isTrue, reason: path);
        expect(disposed, 1, reason: path);
        expect(
          discarded,
          path == 'success' ? 0 : 1,
          reason: 'on success the value went to the caller: $path',
        );
      });
    }
    for (final barrier in ['first', 'second']) {
      fakeAsync((async) {
        // The code of the group itself throws while branches stand at a
        // barrier: at the first one an engine of a domain fails to stop,
        // at the second one the rules of the parent throw. Neither may
        // leave a branch held, and neither may turn the stop into a bare
        // release — a branch let go without being cancelled would keep
        // what it took for a caller that gets nothing.
        var disposed = 0;
        var discarded = 0;
        final slow = Completer<void>();
        final broken = UncancellableByBugJob<int>(
          key: 'broken',
          (ctx) async => 1,
        );
        final holder = Job.deferred<int>(key: 'holder', (ctx) async {
          ctx
            ..onDispose(() => disposed++)
            ..onDiscard(() => discarded++);
          return 2;
        });
        final bad = Job.deferred<int>(key: 'bad', (ctx) async {
          await ctx.join(() => slow.future);
          throw StateError('boom');
        });
        late CheckingContext context;
        Object? thrown;
        CheckingJob<void>(
          key: 'parent',
          observer: ErrorObserver(<Object>[]),
          (ctx) async {
            context = ctx;
            try {
              await ctx.runAll(
                barrier == 'first'
                    ? <Job<int>>[broken, holder, bad]
                    : <Job<int>>[broken, holder],
              );
            } on Object catch (error) {
              thrown = error;
            }
          },
        ).launch();
        if (barrier == 'second') {
          context.rules = () => throw StateError('rules');
        }
        async.elapse(const Duration(milliseconds: 10));
        slow.complete();
        async.flushTimers();
        expect(thrown, isA<StateError>(), reason: barrier);
        expect(broken.isFinished, isTrue, reason: 'nothing is left held');
        expect(holder.isFinished, isTrue, reason: barrier);
        expect(disposed, 1, reason: barrier);
        expect(
          discarded,
          1,
          reason: 'the branch that could be stopped was stopped, not merely '
              'released: $barrier',
        );
      });
    }
    fakeAsync((async) {
      // A refusal of admission after part of the list has started. The
      // whole list starts before any body continues, so the refusal cannot
      // be asked to come "after the first ones are held".
      var disposed = 0;
      var discarded = 0;
      final started = Job.deferred<int>(key: 'a', (ctx) async {
        ctx
          ..onDispose(() => disposed++)
          ..onDiscard(() => discarded++);
        await ctx.wait(() => delay(1000));
        return 1;
      });
      final refused = Job<int>(key: 'c', (ctx) async => 3)..ignore();
      Object? thrown;
      Job<void>((ctx) async {
        try {
          await ctx.runAll([started, refused]);
        } on Object catch (error) {
          thrown = error;
        }
      }).ignore();
      async.flushTimers();
      expect(thrown, isA<ArgumentError>());
      expect(started.isFinished, isTrue);
      expect(disposed, 1);
      expect(discarded, 1);
    });
  });

  test('the second barrier catches what the first one would have missed', () {
    for (final trigger in ['branch', 'parent']) {
      fakeAsync((async) {
        // Both branches took a resource for the caller and returned. The
        // group let them into the unwinding; one is still in an
        // asynchronous disposer, and a cancellation arrives there.
        final closes = {'a': 0, 'b': 0};
        final unwinding = Completer<void>();
        Job<String> holder(String key) => Job.deferred<String>(
              key: key,
              (ctx) async {
                if (key == 'b') ctx.onDispose(() => unwinding.future);
                return ctx.wait(
                  () async => key,
                  discard: (_) => closes[key] = closes[key]! + 1,
                );
              },
            );

        final a = holder('a');
        final b = holder('b');
        Object? thrown;
        final parent = Job<void>(key: 'parent', (ctx) async {
          try {
            await ctx.runAll([a, b]);
          } on Object catch (error) {
            thrown = error;
          }
        })
          ..ignore();
        async.elapse(const Duration(milliseconds: 10));
        expect(closes, {'a': 0, 'b': 0}, reason: 'nothing is decided yet');
        if (trigger == 'branch') {
          b.cancel(reason: const TestCancelReason('outside')).ignore();
        } else {
          parent.cancel().ignore();
        }
        unwinding.complete();
        async.flushTimers();
        expect(closes, {'a': 1, 'b': 1}, reason: trigger);
        expect(thrown, isA<Cancelled>(), reason: trigger);
      });
    }
    fakeAsync((async) {
      // A cancellation that arrives from the finish of a sibling, in the
      // very window the commit closes: synchronous, with no schedule of
      // microtasks to pick from.
      var closes = 0;
      List<String>? values;
      late Job<String> b;
      var heardCancelled = 0;
      final a = Job.deferred<String>(
        key: 'a',
        (ctx) => ctx.wait(() async => 'a', discard: (_) => closes++),
      );
      b = Job.deferred<String>(
        key: 'b',
        (ctx) => ctx.wait(() async => 'b', discard: (_) => closes++),
      );
      Job<void>(
        key: 'parent',
        observer: FinishHook((job) {
          if (job.key == 'a') {
            b.cancel(reason: const TestCancelReason('from onFinish')).ignore();
          }
        }),
        (ctx) async {
          values = await ctx.runAll([a, b]);
        },
      ).ignore();
      b.whenCancelled((_) => heardCancelled++);
      async.flushTimers();
      expect(values, ['a', 'b'], reason: 'the group still returned success');
      expect(closes, 0, reason: 'the values were already handed over');
      expect(b.outcome, isA<Cancelled>());
      expect(heardCancelled, 1);
    });
  });

  test('on success the group does not wait for the tails of its branches', () {
    fakeAsync((async) {
      final unwinding = Completer<void>();
      final tail = Completer<void>();
      var tailRan = false;
      var tailEnded = false;
      late JobContext quick;
      final bare = Job.deferred<String>(key: 'bare', (ctx) async {
        quick = ctx;
        return 'bare';
      });
      final slow = Job.deferred<String>(key: 'slow', (ctx) async {
        ctx.onDispose(() => unwinding.future);
        return 'slow';
      });
      List<String>? values;
      final parent = Job<void>(key: 'parent', (ctx) async {
        values = await ctx.runAll([slow, bare]);
      })
        ..ignore();
      async.flushMicrotasks();
      Timer.run(() {
        // Registered at the second barrier and not in the body: a tail
        // registered in the body holds the first pass, and then no group
        // reaches its decision early enough to tell the two apart.
        quick.onDispose(() async {
          tailRan = true;
          await tail.future;
          tailEnded = true;
        });
      });
      async.elapse(const Duration(milliseconds: 10));
      unwinding.complete();
      async.elapse(const Duration(milliseconds: 10));
      expect(values, ['slow', 'bare'], reason: 'the list is already here');
      expect(tailRan, isTrue);
      expect(tailEnded, isFalse, reason: 'and the tail is still playing out');
      expect(parent.isFinished, isFalse, reason: 'under the parent, as ever');
      tail.complete();
      async.flushTimers();
      expect(tailEnded, isTrue);
      expect(parent.isFinished, isTrue);
    });
  });

  test('what a branch registers while it waits follows the verdict', () {
    for (final path in ['success', 'accepted', 'late-cancel', 'refused']) {
      fakeAsync((async) {
        var disposed = 0;
        var discarded = 0;
        var isDisposingAtBarrier = false;
        Object? checkAtBarrier;
        final unwinding = Completer<void>();
        late JobContext quick;
        // The branch that registered nothing of its own reaches the second
        // barrier at once and stands there while the other one unwinds.
        final bare = ProbeJob<String>(
          key: 'bare',
          cancellable: path != 'refused',
          (ctx) async {
            quick = ctx;
            return 'bare';
          },
        );
        final slow = Job.deferred<String>(key: 'slow', (ctx) async {
          ctx.onDispose(() => unwinding.future);
          return 'slow';
        });
        List<String>? values;
        Job<void>(
          key: 'parent',
          observer: FinishHook((job) {
            if (path == 'late-cancel' && job.key == 'slow') {
              bare.cancelBy(
                Cancelled.by(
                  reason: const TestCancelReason('late'),
                  started: true,
                  stackTrace: StackTrace.current,
                ),
              );
            }
          }),
          (ctx) async {
            try {
              values = await ctx.runAll([slow, bare]);
            } on Object catch (_) {
              // What comes out is other criteria's business.
            }
          },
        ).ignore();
        async.flushMicrotasks();
        Timer.run(() {
          // The branch stands at the second barrier, and it stands there
          // in the same phase as the branch that has a stack to unwind.
          isDisposingAtBarrier = bare.isDisposingNow;
          try {
            quick.check();
          } on Object catch (error) {
            checkAtBarrier = error;
          }
          quick
            ..onDispose(() => disposed++)
            ..onDiscard(() => discarded++);
        });
        async.elapse(const Duration(milliseconds: 10));
        switch (path) {
          case 'accepted':
            bare.cancelBy(
              Cancelled.by(
                reason: const TestCancelReason('outside'),
                started: true,
                stackTrace: StackTrace.current,
              ),
            );
          case 'refused':
            // The group fails for a reason of its own, and this branch
            // refuses the stop: it ends [Done] and hands its value over.
            slow.cancel(reason: const TestCancelReason('outside')).ignore();
          case _:
        }
        unwinding.complete();
        async.flushTimers();
        expect(isDisposingAtBarrier, isTrue, reason: path);
        expect(checkAtBarrier, isA<StateError>(), reason: path);
        expect(disposed, 1, reason: 'the stack is read again: $path');
        expect(
          discarded,
          path == 'accepted' ? 1 : 0,
          reason: 'only a branch that took the cancellation gives up its '
              'value: $path',
        );
        if (path == 'success') {
          expect(values, ['slow', 'bare']);
        }
        if (path == 'refused') {
          expect(bare.outcome, isA<Done<String>>());
        }
      });
    }
  });

  test('a branch of the bare core can end without a body, and silently', () {
    fakeAsync((async) {
      final journal = JobJournal();
      final started = Job.deferred<int>(key: 'a', (ctx) async {
        await ctx.wait(() => delay(1000));
        return 1;
      });
      // Its own context refuses to be built: the child ends [Failed]
      // without a body, and `startChild` tells nobody — that is the kernel,
      // and `solo` is the other half of criterion twelve.
      final unstartable = UnstartableJob<int>(key: 'b');
      Object? thrown;
      Job<void>(key: 'parent', observer: journal, (ctx) async {
        try {
          await ctx.runAll(<Job<int>>[started, unstartable]);
        } on Object catch (error) {
          thrown = error;
        }
      }).ignore();
      async.flushTimers();
      expect(thrown, isA<StateError>());
      expect(unstartable.outcome, isA<Failed>());
      expect(
        started.outcome,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<SiblingCancelReason>(),
        ),
      );
      expect(
        journal.take().where((line) => line.contains('error')).toList(),
        isEmpty,
        reason: 'the bare kernel announces a refusal of admission to nobody',
      );
    });
  });

  test('a handle refused to a second group keeps the hold of the first', () {
    fakeAsync((async) {
      // A handle already running as a branch of one group is refused to
      // another — and the refusal must cost the first group nothing. Get
      // this wrong and the branch is quietly taken out of its hold: it
      // ends `Done`, its `discard` is passed over, and the resource it
      // took for a caller that gets an error is closed by nobody.
      var closes = 0;
      final shared = Job.deferred<String>(key: 'shared', (ctx) async {
        await ctx.wait(() => delay(40));
        return ctx.wait(() async => 'db', discard: (_) => closes++);
      });
      final bad = Job.deferred<String>(key: 'bad', (ctx) async {
        await ctx.wait(() => delay(80));
        throw StateError('boom');
      });
      Job<void>(key: 'first', observer: ErrorObserver(<Object>[]), (ctx) async {
        try {
          await ctx.runAll([shared, bad]);
        } on Object catch (_) {
          // The closing below is what this checks.
        }
      }).ignore();
      async.elapse(const Duration(milliseconds: 10));
      Object? refused;
      Job<void>(key: 'second', (ctx) async {
        try {
          await ctx.runAll([shared]);
        } on Object catch (error) {
          refused = error;
        }
      }).ignore();
      async.flushTimers();
      expect(refused, isA<StateError>());
      expect(
        shared.outcome,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<SiblingCancelReason>(),
        ),
      );
      expect(closes, 1, reason: 'the branch still closed what it took');
    });
  });

  test('a lone child is not held: it ends on its own', () {
    fakeAsync((async) {
      var discarded = 0;
      late Job<int> child;
      var finishedAtReturn = false;
      Job<void>((ctx) async {
        child = Job.deferred<int>(key: 'child', (ctx) async {
          ctx.onDiscard(() => discarded++);
          return 1;
        });
        await ctx.run(child);
        finishedAtReturn = child.isFinished;
      }).ignore();
      async.flushTimers();
      expect(finishedAtReturn, isTrue);
      expect(discarded, 0);
    });
  });

  test('a child waiting for another child under wait still gets its value', () {
    fakeAsync((async) {
      int? seen;
      final source = Job.deferred<int>(key: 'source', (ctx) async {
        await ctx.wait(() => delay(20));
        return 7;
      });
      final reader = Job.deferred<void>(key: 'reader', (ctx) async {
        seen = await source.value;
      });
      Job<void>((ctx) async {
        final running = [ctx.run(source), ctx.run(reader)];
        await running.wait;
      }).ignore();
      async.flushTimers();
      expect(seen, 7);
      expect(source.outcome, isA<Done<int>>());
      expect(reader.outcome, isA<Done<void>>());
    });
  });
}
