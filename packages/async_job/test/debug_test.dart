@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

import 'support/cancel_reason.dart';
import 'support/delay.dart';
import 'support/probe_job.dart';

void main() {
  tearDown(() => Job.debug = null);

  test('the debug channel traces the life of a job', () {
    final traces = <String>[];
    Job.debug = traces.add;
    fakeAsync((async) {
      final job =
          Job<void>(key: 'job', (ctx) => ctx.abandonable(() => delay(50)));
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
    });
    expect(traces, [
      'Job(job) started',
      'cancel Job(job): Cancelled(manual)',
      'Job(job) finished: Cancelled(manual)',
    ]);
  });

  test('a refusal and a job dropped before start are traced too', () {
    final traces = <String>[];
    Job.debug = traces.add;
    fakeAsync((async) {
      Job<void>(key: 'dropped', (ctx) async {}).cancel().ignore();
      final stubborn = Job<void>(
        key: 'stubborn',
        cancellable: false,
        (ctx) => ctx.abandonable(() => delay(20)),
      );
      async.elapse(const Duration(milliseconds: 5));
      stubborn.cancel().ignore();
      async.flushTimers();
    });
    expect(
      traces,
      containsAllInOrder(<String>[
        'cancel Job(dropped) before start: Cancelled(manual)',
        'Job(dropped) finished: Cancelled(manual)',
        'Job(stubborn) started',
        'cancel Job(stubborn): not cancellable',
        'Job(stubborn) finished: Done(null)',
      ]),
    );
  });

  test('an error is traced on both paths, observer or none', () {
    final traces = <String>[];
    Job.debug = traces.add;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>(
            key: 'job',
            (ctx) async {
              ctx.onCancel(() => throw StateError('onCancel'));
              await ctx.abandonable(() => delay(50));
            },
          )..ignoreFailure();
          async.elapse(const Duration(milliseconds: 10));
          // No observer here, so the error of the callback goes to the
          // zone — and the trace has to show it all the same.
          job.cancel().ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) {},
    );
    expect(traces, contains('Job(job) error: Bad state: onCancel'));
  });

  test(
      'the same error is traced when an observer hears it, and on to its '
      'answer', () {
    final traces = <String>[];
    final seen = <String>[];
    final zone = <Object>[];
    Job.debug = traces.add;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>(
            key: 'job',
            observer: _RecordingObserver(seen),
            (ctx) async {
              ctx.onCancel(() => throw StateError('onCancel'));
              await ctx.abandonable(() => delay(50));
            },
          );
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => zone.add(error),
    );
    // Outside the guarded zone: an `expect` that fails inside it lands in
    // the handler and is counted as a zone error instead of failing.
    expect(
      traces,
      containsAllInOrder([
        'Job(job) error: Bad state: onCancel',
        'Job(job) error nobody answered for: Bad state: onCancel',
        'Job(job) error went to the zone: Bad state: onCancel',
      ]),
    );
    expect(seen, ['Bad state: onCancel']);
    expect(
      zone.map((error) => '$error'),
      ['Bad state: onCancel'],
      reason: 'an observer that only watches answers for nothing',
    );
  });

  test('finish called by hand tells the tracer about the stack', () {
    final lines = <String>[];
    Job.debug = lines.add;
    addTearDown(() => Job.debug = null);
    fakeAsync((async) {
      final job = ProbeJob<void>((ctx) async {
        ctx.onDispose(() {});
        await ctx.abandonable(() => delay(1000));
      })
        ..launch();
      async.elapse(const Duration(milliseconds: 10));
      // An engine ended the job itself: the children were not waited for and
      // the stack was not unwound, so a line about the cleanups left behind is
      // all there is.
      job
        ..drop(const Done(null))
        ..ignoreFailure();
      async.flushTimers();
    });
    expect(
      lines.where((line) => line.contains('cleanups pending')),
      hasLength(1),
    );
  });

  test('a value released before the unwinding is not left pending', () {
    final lines = <String>[];
    Job.debug = lines.add;
    final released = <String>[];
    fakeAsync((async) {
      final job = ProbeJob<void>((ctx) async {
        ctx
            .run(
              Job.deferred<void>((ctx) => ctx.uncancellable(() => delay(30))),
            )
            .ignore();
        await ctx.abandonable(
          () => delay(10).then((_) => 'db'),
          dispose: released.add,
        );
      })
        ..launch()
        ..ignoreFailure();
      async.elapse(const Duration(milliseconds: 5));
      job.cancel().ignore();
      async.elapse(const Duration(milliseconds: 15));
      // The value came at 10 and was released there; the job still waits for
      // its child when an engine ends it by hand.
      job.drop(const Cancelled('by hand'));
      async.flushTimers();
    });
    expect(released, ['db']);
    expect(
      lines.where((line) => line.contains('cleanups pending')),
      isEmpty,
      reason: 'the wait for a release that is over is off the stack, and '
          'nothing is left behind',
    );
  });

  test('a job that hands its value over says what it dropped', () {
    final traces = <String>[];
    Job.debug = traces.add;
    fakeAsync((async) {
      final opener = Job.deferred<String>(
        key: 'opener',
        (ctx) => ctx.abandonable(() => 'db', discard: (db) {}),
      );
      // The registration of the child is settled by the child's own
      // outcome, so nothing closes `db` when the wrapper fails. The trace
      // is the only place that says so.
      Job<String>(key: 'wrapper', (ctx) async {
        await ctx.run(opener);
        throw StateError('boom');
      }).ignoreFailure();
      async.flushTimers();
    });
    expect(
      traces.where((line) => line.startsWith('Job(opener)')),
      [
        'Job(opener) started',
        'Job(opener) finished: Done(db)',
        'Job(opener) handed its value over: 1 conditional cleanup dropped',
      ],
    );
  });

  test('a cancellation from the channel on that line finds the job over', () {
    final heard = <String>[];
    var closed = 0;
    fakeAsync((async) {
      late final Job<String> opener;
      Job.debug = (message) {
        if (message.contains('handed its value over')) {
          opener.cancel().ignore();
        }
      };
      opener = Job<String>(
        key: 'opener',
        (ctx) => ctx.abandonable(() => 'db', discard: (db) => closed++),
      )..whenCancelled((cancelled) => heard.add('$cancelled'));
      async.flushTimers();
      expect(opener.outcome, isA<Done<String>>());
    });
    expect(closed, 0, reason: 'the value went to the receiver');
    expect(heard, isEmpty);
  });

  test('so does a describe that cancels the job while the line is built', () {
    final heard = <String>[];
    var closed = 0;
    // Once: a cancellation is traced too, and its line asks `describe`
    // again.
    var cancelOnNextLine = false;
    Job.debug = (_) {};
    fakeAsync((async) {
      late final Job<String> opener;
      opener = Job<String>(
        key: 'opener',
        describe: () {
          if (cancelOnNextLine) {
            cancelOnNextLine = false;
            opener.cancel().ignore();
          }
          return 'opens db';
        },
        (ctx) async {
          final db =
              await ctx.abandonable(() => 'db', discard: (db) => closed++);
          cancelOnNextLine = true;
          return db;
        },
      )..whenCancelled((cancelled) => heard.add('$cancelled'));
      async.flushTimers();
      expect(opener.outcome, isA<Done<String>>());
    });
    expect(closed, 0, reason: 'the value went to the receiver');
    expect(heard, isEmpty);
  });

  test('a cancellation from the channel on the cancel line comes too late', () {
    // The caller's code on the line of a cancellation cancels the same job
    // with a reason of its own. The first request has marked the job by
    // then, so the second turns around: the listeners and the outcome
    // speak of the same one.
    final heard = <String>[];
    fakeAsync((async) {
      final job =
          Job<void>(key: 'job', (ctx) => ctx.abandonable(() => delay(50)))
            ..whenCancelled((cancelled) => heard.add(cancelled.reason.name));
      async.elapse(const Duration(milliseconds: 10));
      var reentered = false;
      Job.debug = (message) {
        if (!reentered && message.startsWith('cancel ')) {
          reentered = true;
          job.cancel(reason: const TestCancelReason('inner')).ignore();
        }
      };
      job.cancel(reason: const TestCancelReason('outer')).ignore();
      async.flushTimers();
      expect(heard, ['outer']);
      expect(
        job.outcome,
        isA<Cancelled>().having((c) => c.reason.name, 'reason', 'outer'),
      );
    });
  });

  test('so does one on the line of a held cancellation', () {
    final heard = <String>[];
    fakeAsync((async) {
      final job = Job<void>(
        key: 'job',
        (ctx) => ctx.uncancellable(() => delay(50)),
      )..whenCancelled((cancelled) => heard.add(cancelled.reason.name));
      async.elapse(const Duration(milliseconds: 10));
      var reentered = false;
      Job.debug = (message) {
        if (!reentered && message.startsWith('cancel ')) {
          reentered = true;
          job.cancel(reason: const TestCancelReason('inner')).ignore();
        }
      };
      job.cancel(reason: const TestCancelReason('outer')).ignore();
      async.flushTimers();
      expect(heard, ['outer']);
      expect(
        job.outcome,
        isA<Cancelled>().having((c) => c.reason.name, 'reason', 'outer'),
      );
    });
  });

  test('the line counts them, and a job that keeps them gets no line', () {
    final handedOver = <String>[];
    final ranThem = <String>[];
    fakeAsync((async) {
      Job.debug = handedOver.add;
      final two = Job.deferred<String>(key: 'two', (ctx) async {
        ctx.onDiscard(() {});
        return ctx.abandonable(() => 'db', discard: (db) {});
      });
      Job<String>(key: 'taker', (ctx) async {
        await ctx.run(two);
        throw StateError('boom');
      }).ignoreFailure();
      async.flushTimers();
      Job.debug = ranThem.add;
      Job<String>(key: 'failing', (ctx) async {
        ctx.onDiscard(() {});
        throw StateError('boom');
      }).ignoreFailure();
      async.flushTimers();
    });
    expect(
      handedOver,
      contains(
        'Job(two) handed its value over: 2 conditional cleanups dropped',
      ),
    );
    expect(
      ranThem.where((line) => line.contains('handed its value over')),
      isEmpty,
      reason: 'it ended badly, so it ran them instead of dropping them',
    );
  });

  test('a job finished by hand while unwinding says that instead', () {
    final traces = <String>[];
    Job.debug = traces.add;
    final closed = <String>[];
    late ProbeJob<String> job;
    fakeAsync((async) {
      job = ProbeJob<String>(key: 'j', (ctx) async {
        final db = await ctx.abandonable(() => 'db', discard: closed.add);
        // The unwinding is inside this disposer when an engine ends the job, so
        // the loop carries on with an outcome that is no longer the one it is
        // reading.
        ctx.onDispose(() async {
          job.drop(const Cancelled('by hand'));
          await delay(5);
        });

        return db;
      })
        ..launch()
        ..ignoreFailure();
      async.flushTimers();
    });
    expect(job.outcome, isA<Cancelled>());
    expect(closed, isEmpty, reason: 'nothing unwound the stack');
    expect(
      traces.where((line) => line.contains('handed its value over')),
      isEmpty,
      reason: 'the value went nowhere, and the line must not claim it did',
    );
    expect(
      traces,
      contains(
        'Job(j) was finished as Cancelled(handler: by hand) with '
        '1 conditional cleanup left aside',
      ),
    );
  });

  test('a branch of a group says it too, once the group has committed', () {
    final traces = <String>[];
    Job.debug = traces.add;
    fakeAsync((async) {
      Job<List<String>>(
        key: 'group',
        (ctx) => ctx.runAll([
          Job.deferred<String>(
            key: 'branch',
            (ctx) => ctx.abandonable(() => 'db', discard: (db) {}),
          ),
        ]),
      ).ignoreFailure();
      async.flushTimers();
    });
    expect(
      traces.where((line) => line.contains('handed its value over')),
      ['Job(branch) handed its value over: 1 conditional cleanup dropped'],
      reason: 'the values reached the caller, and so did what they hold; '
          'once: the commit took the put-aside registrations away, and the '
          'branch has nothing left to name at the end of its unwinding',
    );
  });

  group('a value the job did not hand over', () {
    const kept = 'Job(open) ended Done(null) without the value of 1 '
        'conditional cleanup (db): unless it is inside the result, nothing '
        'will dispose of it';

    List<String> tracesOf(void Function() body) {
      final traces = <String>[];
      Job.debug = traces.add;
      fakeAsync((async) {
        body();
        async.flushTimers();
      });
      return [
        for (final line in traces)
          if (line.contains('conditional cleanup')) line,
      ];
    }

    test('a body that returns null instead of the value is named', () {
      expect(
        tracesOf(() {
          Job<String?>(key: 'open', (ctx) async {
            await ctx.abandonable(() => 'db', discard: (db) {});
            return null;
          });
        }),
        [kept],
      );
    });

    test('so is a branch of a group', () {
      expect(
        tracesOf(() {
          Job<List<String?>>(
            (ctx) => ctx.runAll([
              Job.deferred<String?>(key: 'open', (ctx) async {
                await ctx.abandonable(() => 'db', discard: (db) {});
                return null;
              }),
            ]),
          );
        }),
        [kept],
      );
    });

    test('and a job of void', () {
      expect(
        tracesOf(() {
          Job<void>(key: 'open', (ctx) async {
            await ctx.abandonable(() => 'db', discard: (db) {});
          });
        }),
        [kept],
      );
    });

    test('a value inside the result is named too: the line says unless', () {
      const inside = 'Job(open) ended Done((db, 1)) without the value of 1 '
          'conditional cleanup (db): unless it is inside the result, nothing '
          'will dispose of it';
      expect(
        tracesOf(() {
          Job<(String, int)>(key: 'open', (ctx) async {
            final db = await ctx.abandonable(() => 'db', discard: (db) {});
            return (db, 1);
          });
        }),
        [inside],
      );
    });

    test('a registration that was disowned says nothing', () {
      final closed = <String>[];
      expect(
        tracesOf(() {
          Job<void>(key: 'open', (ctx) async {
            final db = await ctx.abandonable(
              () => 'db',
              discard: (db) => closed.add('discard $db'),
            );
            ctx.disown(db);
            closed.add('closed $db');
          });
        }),
        isEmpty,
      );
      expect(closed, ['closed db']);
    });

    test('a value equal to the result but another object is named', () {
      const equal = 'Job(open) ended Done(db) without the value of 1 '
          'conditional cleanup (db): unless it is inside the result, nothing '
          'will dispose of it';
      expect(
        tracesOf(() {
          Job<_Name>(key: 'open', (ctx) async {
            await ctx.abandonable(() => const _Name('db'), discard: (db) {});
            return _Name(['d', 'b'].join());
          });
        }),
        [equal],
      );
    });

    test('a job finished by hand while it unwinds says that instead', () {
      const aside = 'Job(open) was finished as Cancelled(handler: by hand) '
          'with 1 conditional cleanup left aside';
      late ProbeJob<String?> job;
      expect(
        tracesOf(() {
          job = ProbeJob<String?>(key: 'open', (ctx) async {
            await ctx.abandonable(() => 'db', discard: (db) {});
            ctx.onDispose(() async {
              job.drop(const Cancelled('by hand'));
              await delay(5);
            });
            return null;
          })
            ..launch()
            ..ignoreFailure();
        }),
        [aside],
      );
    });

    test('a value returned is handed over, as before', () {
      expect(
        tracesOf(() {
          Job<String>(
            key: 'open',
            (ctx) => ctx.abandonable(() => 'db', discard: (db) {}),
          );
        }),
        ['Job(open) handed its value over: 1 conditional cleanup dropped'],
      );
    });
  });

  test('a branch finished by hand at the second barrier says so too', () {
    final traces = <String>[];
    Job.debug = traces.add;
    final closed = <String>[];
    late ProbeJob<String> branch;
    fakeAsync((async) {
      branch = ProbeJob<String>(key: 'branch', (ctx) async {
        final db = await ctx.abandonable(() => 'db', discard: closed.add);
        // On top of the stack, so it unwinds first -- while the group
        // still holds the branch. The conditional registration under it
        // is put aside, and by the time the second barrier lets go the
        // job has an outcome of its own.
        ctx.onDispose(() => branch.drop(const Cancelled('by hand')));
        return db;
      });
      Job<List<String>>(
        key: 'group',
        (ctx) => ctx.runAll([
          branch,
          Job.deferred<String>(
            key: 'slow',
            (ctx) => ctx.abandonable(() => delay(20).then((_) => 'other')),
          ),
        ]),
      ).ignoreFailure();
      async.flushTimers();
    });
    expect(
      closed,
      isEmpty,
      reason: 'the engine finished the branch by hand while the group held '
          'it: the value went nowhere, the group ends cancelled, and the '
          'discard put aside for the group to settle is never run',
    );
    expect(
      traces,
      contains(
        'Job(branch) was finished as Cancelled(handler: by hand) with '
        '1 conditional cleanup left aside',
      ),
      reason: 'the barrier between the two passes is a way out of its own',
    );
  });

  test('a debug channel that throws does not break the life of a job', () {
    final caught = <Object>[];
    var doneSeen = false;
    Outcome<void>? outcome;
    Job.debug = (message) => throw StateError('logger: $message');
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job =
              Job<void>(key: 'job', (ctx) => ctx.abandonable(() => delay(10)));
          job.done.then((result) {
            doneSeen = true;
            outcome = result;
          }).ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(doneSeen, isTrue, reason: 'the job finished and said so');
    expect(outcome, isA<Done<void>>());
    expect(
      caught.map((error) => '$error').toList(),
      everyElement(startsWith('Bad state: logger: ')),
      reason: 'every refusal of the channel went to the zone and nowhere else',
    );
    expect(caught, isNotEmpty);
  });

  test('a describe that throws does not break the life of a job', () {
    final traces = <String>[];
    final caught = <Object>[];
    var doneSeen = false;
    Job.debug = traces.add;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>(
            key: 'job',
            describe: () => throw StateError('describe'),
            (ctx) => ctx.abandonable(() => delay(10)),
          );
          job.done.then((_) => doneSeen = true).ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(doneSeen, isTrue, reason: 'building the message is guarded too');
    expect(
      caught.map((error) => '$error').toList(),
      everyElement('Bad state: describe'),
    );
    expect(
      traces,
      [
        'Job(job: <describe threw StateError>) started',
        'Job(job: <describe threw StateError>) finished: Done(null)',
      ],
      reason: 'the line is printed with a mark, and the error goes to the '
          'zone once for each line',
    );
    expect(caught, hasLength(2));
  });

  group('the mark of a name that throws', () {
    /// The lines of [Job.debug] and the errors the zone heard, in order,
    /// while [body] runs and its timers run out.
    List<String> heard(
      void Function() body, {
      void Function(String line)? debug,
    }) {
      final heard = <String>[];
      Job.debug = debug ?? (line) => heard.add('debug: $line');
      runZonedGuarded(
        () => fakeAsync((async) {
          body();
          async.flushTimers();
        }),
        (error, stackTrace) => heard.add('zone: $error'),
      );
      return heard;
    }

    test('a line printed inside a name reports its own marks only', () {
      // The describe of the outer job prints a line of a job whose
      // cancellation cannot be put into words: that line throws, and the
      // outer describe that breaks after it is still reported for its own
      // line.
      final lines = heard(() {
        Job<void>(
          key: 'outer',
          describe: () {
            Job.deferred<void>((ctx) async {})
                .cancel(reason: const _BrokenReason())
                .ignore();
            throw StateError('outer failed');
          },
          (ctx) async {},
        );
      });
      expect(
        lines.where((line) => line == 'zone: Bad state: outer failed'),
        hasLength(2),
        reason: 'started and finished, each reported once',
      );
    });

    test('a debug channel that throws reports each mark once', () {
      final lines = heard(
        debug: (line) => throw StateError('sink'),
        () => Job<void>(
          key: 'k',
          describe: () => throw StateError('describe'),
          (ctx) async {},
        ),
      );
      expect(lines, [
        'zone: Bad state: describe',
        'zone: Bad state: sink',
        'zone: Bad state: describe',
        'zone: Bad state: sink',
      ]);
    });

    test('a mark is reported before the line that throws after it', () {
      final lines = heard(() {
        final job = Job<void>(
          key: 'k',
          describe: () => throw StateError('describe'),
          (ctx) => ctx.abandonable(() => delay(10)),
        );
        Timer(
          const Duration(milliseconds: 1),
          () => job.cancel(reason: const _BrokenReason()).ignore(),
        );
      });
      expect(
        lines.where((line) => line.startsWith('zone:')).take(3),
        [
          'zone: Bad state: describe',
          'zone: Bad state: describe',
          'zone: Bad state: name failed',
        ],
        reason: 'started, then the cancellation: its mark, then its throw',
      );
    });

    test('an error whose type cannot be read is still a mark', () {
      fakeAsync((async) {
        final job = Job<void>(
          key: 'k',
          // ignore: only_throw_errors
          describe: () => throw _NoType(),
          (ctx) async {},
        );
        expect('$job', 'Job(k: <describe threw an error>)');
        async.flushTimers();
      });
    });
  });
}

/// A reason of a cancellation that cannot be put into words.
final class _BrokenReason extends CancelReason {
  const _BrokenReason();

  @override
  String get name => throw StateError('name failed');
}

/// An error whose type cannot be read: `runtimeType` is a getter like any
/// other.
final class _NoType {
  @override
  Type get runtimeType => throw StateError('runtimeType failed');
}

/// Keeps the errors it is given, and nothing else.
final class _RecordingObserver extends JobObserver {
  final List<String> _seen;

  _RecordingObserver(this._seen);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      _seen.add('$error');

  @override
  void onStart(Job<Object?> job) {}

  @override
  void onFinish(Job<Object?> job) {}

  @override
  void onLog(Job<Object?> job, Object? message) {}
}

/// A value equal to another of the same text, and not the same object.
@immutable
final class _Name {
  final String text;

  const _Name(this.text);

  @override
  bool operator ==(Object other) => other is _Name && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => text;
}
