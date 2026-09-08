@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/journal.dart';
import 'support/probe_job.dart';

void main() {
  test('an unobserved failure goes to the zone that created the job', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>((ctx) async => throw StateError('boom'));
          async.flushMicrotasks();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught.map((error) => '$error').toList(), ['Bad state: boom']);
  });

  test('a failure someone observed stays out of the zone', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>((ctx) async => throw StateError('boom')).ignore();
          async.flushMicrotasks();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught, isEmpty);
  });

  test('the body error reaches the observer once, not the zone twice', () {
    final journal = JobJournal();
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>(
            key: 'job',
            observer: journal,
            (ctx) async => throw StateError('boom'),
          ).ignore();
          async.flushMicrotasks();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(journal.take(), [
      '[job] started',
      '[job] error Bad state: boom',
      '[job] finished Failed(Bad state: boom)',
    ]);
    expect(caught, isEmpty, reason: 'the outcome was observed by ignore');
  });

  test('the homeless errors go to the zone without an observer', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>((ctx) async {
            ctx.onCancel(() => throw StateError('onCancel'));
            unawaited(
              ctx.wait(() async {
                await delay(20);
                throw StateError('late action');
              }),
            );
            await ctx.wait(() => delay(100));
          });
          async.elapse(const Duration(milliseconds: 5));
          job.cancel().ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught.map((error) => '$error').toList(),
      containsAll(<String>['Bad state: onCancel', 'Bad state: late action']),
      // The abandoned `wait` also throws its own Cancelled into the zone:
      // nobody awaits the future it returned.
      reason: 'both errors have nowhere else to go',
    );
  });

  test('the same errors go to the observer when there is one', () {
    final journal = JobJournal();
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>(
            key: 'job',
            observer: journal,
            (ctx) async {
              ctx.onCancel(() => throw StateError('onCancel'));
              // `ignore`, so the Cancelled thrown into the abandoned
              // future does not reach the zone on its own account.
              ctx.wait(() async {
                await delay(20);
                throw StateError('late action');
              }).ignore();
              await ctx.wait(() => delay(100));
            },
          );
          async.elapse(const Duration(milliseconds: 5));
          job.cancel().ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      journal.take(),
      containsAll(<String>[
        '[job] error Bad state: onCancel',
        '[job] error Bad state: late action',
      ]),
    );
    expect(caught, isEmpty, reason: 'an observer takes the whole path');
  });
  test('an error a late cancellation covers still reaches the zone', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>((ctx) async {
            ctx.run(
              Job.deferred<void>(
                key: 'child',
                (child) => child.wait(() => delay(50)),
              ),
            );
            throw StateError('boom');
          });
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.elapse(const Duration(milliseconds: 100));
          expect(job.outcome, isA<Cancelled>());
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught.map((error) => '$error').toList(), ['Bad state: boom']);
  });

  test('an error a late cancellation covers goes where an uncovered one goes',
      () {
    final journal = JobJournal();
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>(
            key: 'job',
            observer: journal,
            (ctx) async {
              ctx.run(
                Job.deferred<void>(
                  key: 'child',
                  (child) => child.wait(() => delay(50)),
                ),
              );
              throw StateError('boom');
            },
          );
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.elapse(const Duration(milliseconds: 100));
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught.map((error) => '$error').toList(),
      ['Bad state: boom'],
      reason: 'nobody looked at the outcome, so the zone hears — as it '
          'does for a failure no cancellation covered',
    );
    expect(
      journal.lines.where((line) => line.contains('error')).toList(),
      ['[job] error Bad state: boom'],
      reason: 'and the observer hears once, not twice',
    );
  });
  test('a join the body walked away from puts no cancellation in the zone', () {
    final caught = <Object>[];
    final closed = <String>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>((ctx) async {
            unawaited(
              ctx.join<String>(
                () => delay(50).then((_) => 'db'),
                discard: closed.add,
              ),
            );
            throw const Cancelled('enough');
          }).ignore();
          async.elapse(const Duration(milliseconds: 200));
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught, isEmpty);
    expect(closed, ['db'], reason: 'the value is still cleaned up');
  });
  test("a child's failure nobody looked at reaches the zone", () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>((ctx) async {
            ctx.run(
              Job.deferred<void>(key: 'child', (child) async {
                // Outlives the body, so the parent really waits for it: a
                // child that finished earlier is not on the waiting list
                // at all.
                await child.wait(() => delay(20));
                throw StateError('child boom');
              }),
            );
            await ctx.wait(() => delay(10));
          }).ignore();
          async.elapse(const Duration(milliseconds: 50));
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught.map((error) => '$error').toList(),
      ['Bad state: child boom'],
      reason: 'waiting for a child is not looking at its outcome',
    );
  });

  test('cancelling a job does not silence the failure it ends with', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>(cancellable: false, (ctx) async {
            await ctx.wait(() => delay(10));
            throw StateError('boom');
          });
          async.elapse(const Duration(milliseconds: 5));
          job.cancel().ignore();
          async.elapse(const Duration(milliseconds: 50));
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught.map((error) => '$error').toList(),
      ['Bad state: boom'],
      reason: 'the waiting of an engine is not observation',
    );
  });

  test('a listener that arrives one microtask later still counts', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          late Job<void> job;
          job = Job<void>(
            observer: _TouchAfterFinish(() => job.done.ignore()),
            (ctx) async => throw StateError('boom'),
          );
          async.flushMicrotasks();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught, isEmpty, reason: 'one microtask of grace, as Dart gives');
  });
  test('a body that turns its cancellation into an error keeps it in hand', () {
    // No observer: the zone is the only place such an error could land.
    final caught = <Object>[];
    late Job<void> job;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          job = Job<void>((ctx) async {
            try {
              await ctx.wait(() => delay(100));
            } on Cancelled {
              // The device said no in its own words, as a real one does
              // through the token it was handed.
              throw StateError('device aborted');
            }
          });
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught,
      isEmpty,
      reason: 'the job was already cancelled when the body threw',
    );
    expect(job.outcome, isA<Cancelled>());
  });

  test('ignore silences a failure a late cancellation covered', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>((ctx) async {
            ctx.run(
              Job.deferred<void>(
                key: 'child',
                (child) => child.wait(() => delay(50)),
              ),
            );
            throw StateError('boom');
          })
            ..ignore();
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught, isEmpty);
  });

  test('a cancellation with nowhere to go stays out of the zone', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>((ctx) async {
            ctx
              ..onDispose(() {
                throw const Cancelled('disposer');
              })
              ..onCancel(() {
                throw const Cancelled('onCancel');
              })
              ..unattended(() async {
                await delay(10);
                throw const Cancelled('unattended');
              })
              // `ignore`, so the cancellation the abandoned future itself
              // carries does not reach the zone on its own account: that
              // one is Dart's doing, not the engine's.
              ..wait(() async {
                await delay(20);
                throw const Cancelled('late action');
              }).ignore();
            await ctx.wait(() => delay(100));
          });
          async.elapse(const Duration(milliseconds: 5));
          job.cancel().ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught,
      isEmpty,
      reason: 'a cancellation is a decision somebody made, not a failure, '
          'and the engine hands one to nobody',
    );
  });

  test('the same cancellations reach the observer when there is one', () {
    final journal = JobJournal();
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>(
            key: 'job',
            observer: journal,
            (ctx) async {
              ctx
                ..onDispose(() {
                  throw const Cancelled('disposer');
                })
                ..onCancel(() {
                  throw const Cancelled('onCancel');
                })
                ..unattended(() async {
                  await delay(10);
                  throw const Cancelled('unattended');
                })
                ..wait(() async {
                  await delay(20);
                  throw const Cancelled('late action');
                }).ignore();
              await ctx.wait(() => delay(100));
            },
          );
          async.elapse(const Duration(milliseconds: 5));
          job.cancel().ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      journal.lines.where((line) => line.contains('error')).toList(),
      containsAll(<String>[
        '[job] error Cancelled(handler: onCancel)',
        '[job] error Cancelled(handler: late action)',
        '[job] error Cancelled(handler: disposer)',
        '[job] error Cancelled(handler: unattended)',
      ]),
      reason: 'held back from the zone, not from whoever listens',
    );
    expect(caught, isEmpty);
  });

  test('the zone route of an engine of a domain refuses a cancellation', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = ProbeJob<void>((ctx) async {})..launch();
          async.flushMicrotasks();
          job
            ..report(const Cancelled('by hand'), StackTrace.empty)
            ..report(StateError('boom'), StackTrace.empty);
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught.map((error) => '$error').toList(),
      ['Bad state: boom'],
      reason: 'the rule holds at the door an engine of a domain uses too',
    );
  });

  test('an unobserved failure carrying a cancellation still reaches the zone',
      () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          // The outcome decides here, not the object it holds: somebody
          // made this a failure on purpose, and a failure nobody looked at
          // goes to the zone whatever is inside it.
          ProbeJob<void>((ctx) async {}).drop(
            const Failed(Cancelled('as a failure'), StackTrace.empty),
          );
          async.flushMicrotasks();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught.map((error) => '$error').toList(),
      ['Cancelled(handler: as a failure)'],
    );
  });

  test('an observer that cancels from onError does not hide the failure', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>(key: 'job', observer: _CancelOnError(), (ctx) async {
            throw StateError('boom');
          });
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught.map((error) => '$error').toList(),
      ['Bad state: boom'],
      reason: 'the body failed first, and a cancellation decided afterwards '
          'leaves that failure on the same road it would have taken anyway',
    );
  });

  test('a covered error waits for the same window an uncovered one waits for',
      () {
    final order = <String>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>(
            key: 'job',
            observer: _IgnoreOnFinish(order),
            (ctx) async {
              ctx.run(
                Job.deferred<void>(
                  key: 'child',
                  // An observer of its own: the child would inherit the
                  // parent's, and its finish would take the outcome of the
                  // parent through the closure long before this is about.
                  observer: _Quiet(),
                  (child) => child.wait(() => delay(50)),
                ),
              );
              throw StateError('boom');
            },
          );
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => order.add('zone'),
    );
    expect(
      order,
      ['onFinish job'],
      reason: 'an observer taking the outcome at finish is in time here as '
          'it is for a failure no cancellation covered',
    );
  });

  test('a listener one microtask late still counts for a covered error too',
      () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          late Job<void> job;
          job = Job<void>(
            key: 'job',
            observer: _TouchAfterFinish(() => job.done.ignore()),
            (ctx) async {
              ctx.run(
                Job.deferred<void>(
                  key: 'child',
                  observer: _Quiet(),
                  (child) => child.wait(() => delay(50)),
                ),
              );
              throw StateError('boom');
            },
          );
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught,
      isEmpty,
      reason: 'the same microtask of grace an uncovered failure gives',
    );
  });
}

/// Touches the outcome one microtask after the job finished.
final class _TouchAfterFinish extends JobObserver {
  final void Function() _touch;

  _TouchAfterFinish(this._touch);

  @override
  void onFinish(Job<Object?> job) => scheduleMicrotask(_touch);
}

/// Cancels the job from inside `onError`, the way an engine of a domain
/// that treats a failure as a reason to give up would.
final class _CancelOnError extends JobObserver {
  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      job.cancel().ignore();
}

/// Takes the outcome the moment the job finishes, the way an engine of a
/// domain that routes failures itself would.
final class _IgnoreOnFinish extends JobObserver {
  final List<String> order;

  _IgnoreOnFinish(this.order);

  @override
  void onFinish(Job<Object?> job) {
    order.add('onFinish ${job.key}');
    job.ignore();
  }
}

/// Hears everything and does nothing: keeps a child out of a scenario that
/// is about its parent.
final class _Quiet extends JobObserver {}
