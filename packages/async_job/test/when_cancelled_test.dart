@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/cancel_reason.dart';
import 'support/delay.dart';
import 'support/probe_job.dart';

class _ErrorObserver extends JobObserver {
  final errors = <Object>[];

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    errors.add(error);
  }
}

void main() {
  test('a running job delivers the cancellation before cancel returns', () {
    fakeAsync((async) {
      final seen = <Cancelled>[];
      final job = Job<void>((ctx) => ctx.abandonable(() => delay(50)))
        ..whenCancelled(seen.add);
      async.flushMicrotasks();
      job.cancel().ignore();
      expect(seen, hasLength(1));
      expect(seen.single.reason, isA<ManualCancelReason>());
      expect(seen.single.started, isTrue);
      expect(seen.single.stackTrace, isNotNull);
      expect(job.outcome, isNull);
      job.cancel().ignore();
      async.flushTimers();
      expect(seen, hasLength(1));
      expect(job.outcome, same(seen.single));
    });
  });

  test('a job cancelled before start delivers its normalized reason', () {
    final seen = <Cancelled>[];
    final job = Job.deferred<void>((ctx) async {})..whenCancelled(seen.add);
    job.cancel().ignore();
    expect(seen.single.reason, isA<ManualCancelReason>());
    expect(seen.single.started, isFalse);
    expect(job.outcome, same(seen.single));
  });

  test('a late subscription runs immediately before and after finish', () {
    fakeAsync((async) {
      final seen = <Cancelled>[];
      final job = Job<void>((ctx) async => delay(50));
      async.flushMicrotasks();
      job.cancel().ignore();
      final remove = job.whenCancelled(seen.add);
      expect(seen, hasLength(1));
      expect(job.isFinished, isFalse);
      remove();
      async.flushTimers();
      job.whenCancelled(seen.add);
      expect(seen, hasLength(2));
      expect(seen.every((event) => identical(event, job.outcome)), isTrue);
    });
  });

  test('removing one registration leaves the same callback registered twice',
      () {
    final seen = <Cancelled>[];
    final job = Job.deferred<void>((ctx) async {});
    final remove = job.whenCancelled(seen.add);
    job
      ..whenCancelled(seen.add)
      ..whenCancelled(seen.add);
    remove();
    remove();
    job.cancel().ignore();
    expect(seen, hasLength(2));
  });

  test('a callback may cancel again and subscribe during notification', () {
    final order = <String>[];
    final job = Job.deferred<void>((ctx) async {});
    job
      ..whenCancelled((cancelled) {
        order.add('first');
        job
          ..cancel().ignore()
          ..whenCancelled((late) {
            expect(late, same(cancelled));
            order.add('late');
          });
      })
      ..whenCancelled((_) => order.add('second'));
    job.cancel().ignore();
    expect(order, ['first', 'late', 'second']);
  });

  test('removal during notification leaves the current snapshot intact', () {
    final order = <String>[];
    late void Function() remove;
    final job = Job.deferred<void>((ctx) async {})
      ..whenCancelled((_) {
        order.add('first');
        remove();
      });
    remove = job.whenCancelled((_) => order.add('second'));
    job.cancel().ignore();
    expect(order, ['first', 'second']);
  });

  test('successful and failed jobs never call early or late subscribers', () {
    fakeAsync((async) {
      final seen = <Cancelled>[];
      final success = Job<int>((ctx) async => 42);
      final failure = Job<int>((ctx) async => throw StateError('body'))
        ..ignore();
      success.whenCancelled(seen.add);
      failure.whenCancelled(seen.add);
      async.flushMicrotasks();
      success.whenCancelled(seen.add);
      failure.whenCancelled(seen.add);
      success.cancel().ignore();
      failure.cancel().ignore();
      async.flushMicrotasks();
      expect(success.outcome, isA<Done<int>>());
      expect(failure.outcome, isA<Failed>());
      expect(seen, isEmpty);
    });
  });

  test('a branch giving itself up is heard with its own reason, once', () {
    // The group asks the siblings to stop as soon as this branch's body
    // ends, and a sibling's `onCancel` cancels the branch in turn. The
    // body decided first: that cancellation finds the branch cancelled
    // already, and one instance is heard and becomes the outcome.
    fakeAsync((async) {
      final heard = <Cancelled>[];
      late Job<void> gaveUp;
      gaveUp = Job.deferred<void>((ctx) async {
        await delay(1);
        throw const Cancelled('gave up');
      })
        ..whenCancelled(heard.add);
      final sibling = Job.deferred<void>((ctx) async {
        ctx.onCancel(
          () => gaveUp.cancel(reason: const TestCancelReason('sibling')),
        );
        await delay(50);
      });
      Object? thrown;
      Job<void>((ctx) async {
        try {
          await ctx.runAll<void>([gaveUp, sibling]);
        } on Cancelled catch (cancelled) {
          thrown = cancelled;
        }
      });
      async.flushTimers();
      expect(heard, hasLength(1));
      expect(heard.single.description, 'gave up');
      expect(gaveUp.outcome, same(heard.single));
      expect(thrown, same(heard.single));
    });
  });

  test('a cancellation made while the body gives up is the one heard', () {
    // Putting the body's cancellation into words formats the child's key,
    // which is the caller's code, and this one cancels the parent right
    // then. That cancellation came first and stands.
    fakeAsync((async) {
      final heard = <Cancelled>[];
      final key = _CancellingKey();
      final child = Job.deferred<void>(key: key, (ctx) async {
        await delay(1);
        throw const Cancelled('child gave up');
      });
      final parent = Job<void>((ctx) async {
        ctx.run(Job.deferred<void>((_) => delay(30))).ignore();
        await ctx.run(child);
      })
        ..whenCancelled(heard.add)
        ..ignore();
      key.onFormat = () => parent.cancel(reason: const TestCancelReason('key'));
      async.flushTimers();
      expect(heard, hasLength(1));
      expect(heard.single.reason, isA<TestCancelReason>());
      expect(parent.outcome, same(heard.single));
    });
  });

  test('a refused cancellation sends no notification', () {
    fakeAsync((async) {
      final seen = <Cancelled>[];
      final job = Job<void>(
        (ctx) => ctx.abandonable(() => delay(50)),
        cancellable: false,
      )..whenCancelled(seen.add);
      async.flushMicrotasks();
      job.cancel().ignore();
      async.flushTimers();
      expect(seen, isEmpty);
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('a held cancellation sends the first reason when the section closes',
      () {
    fakeAsync((async) {
      final seen = <Cancelled>[];
      const first = Cancelled.by(
        reason: ManualCancelReason(),
        started: true,
        description: 'first request',
      );
      final job = ProbeJob<void>(
        (ctx) => ctx.uncancellable(() => delay(50)),
      )
        ..launch()
        ..whenCancelled(seen.add)
        ..cancelBy(first)
        ..cancelBy(const Cancelled('later request'));
      expect(seen, isEmpty);
      async.flushTimers();
      expect(seen, [same(first)]);
      expect(job.outcome, same(first));
    });
  });

  test('self cancellation notifies at the throw, as one from outside does', () {
    fakeAsync((async) {
      final order = <String>[];
      Cancelled? seen;
      final job = Job<void>((ctx) async {
        ctx
          ..onCancel(() => order.add('context cancelled'))
          ..onDispose(() => order.add('cleanup'));
        ctx
            .run(
              Job.deferred<void>(cancellable: false, (child) async {
                await delay(20);
                order.add('child done');
              }),
            )
            .ignore();
        throw const Cancelled('no photo');
      })
        ..whenCancelled((cancelled) {
          seen = cancelled;
          order.add('cancelled');
        });
      async.flushMicrotasks();
      expect(order, ['context cancelled', 'cancelled']);
      async.flushTimers();
      expect(order, [
        'context cancelled',
        'cancelled',
        'child done',
        'cleanup',
      ]);
      expect(seen!.reason, isA<HandlerCancelReason>());
      expect(seen!.description, 'no photo');
      expect(seen!.stackTrace, isNotNull);
      expect(job.outcome, same(seen));
    });
  });

  test(
      'a callback error reaches the observer, then the zone, and other '
      'callbacks still run', () {
    final observer = _ErrorObserver();
    final seen = <Cancelled>[];
    final error = StateError('callback');
    final zone = <Object>[];
    late final Job<void> job;
    runZonedGuarded(
      () {
        job = Job.deferred<void>((ctx) async {}, observer: observer)
          ..whenCancelled((_) => throw error)
          ..whenCancelled(seen.add);
        job.cancel().ignore();
        job.whenCancelled((_) => throw error);
      },
      (error, stackTrace) => zone.add(error),
    );
    // Outside the guarded zone: an `expect` that fails inside it lands in
    // the handler and is counted as a zone error instead of failing.
    expect(observer.errors, [same(error), same(error)]);
    expect(
      zone,
      [same(error), same(error)],
      reason: 'an observer that only watches answers for nothing',
    );
    expect(seen, hasLength(1));
    expect(job.outcome, same(seen.single));
  });

  test('without an observer a callback error goes to the creation zone', () {
    final errors = <Object>[];
    final error = StateError('callback');
    late Job<void> job;
    runZonedGuarded(
      () {
        job = Job.deferred<void>((ctx) async {});
      },
      (error, stackTrace) => errors.add(error),
    );
    final seen = <Cancelled>[];
    job
      ..whenCancelled((_) => throw error)
      ..whenCancelled(seen.add);
    job.cancel().ignore();
    expect(errors, [same(error)]);
    expect(seen, hasLength(1));
  });

  test('a cancellation thrown by a subscriber stays out of the zone', () {
    final errors = <Object>[];
    runZonedGuarded(
      () {
        final job = Job.deferred<void>((ctx) async {})
          ..whenCancelled((_) => throw const Cancelled('listener'));
        job.cancel().ignore();
      },
      (error, stackTrace) => errors.add(error),
    );
    expect(errors, isEmpty);
  });

  test('registration does not observe a failed job', () {
    fakeAsync((async) {
      final errors = <Object>[];
      final error = StateError('body');
      runZonedGuarded(
        () {
          Job<void>((ctx) async => throw error).whenCancelled((_) {});
        },
        (error, stackTrace) => errors.add(error),
      );
      async.flushMicrotasks();
      expect(errors, [same(error)]);
    });
  });

  test('a listener registered during the cascade waits its turn', () {
    fakeAsync((async) {
      final heard = <String>[];
      late Job<void> parent;
      parent = Job<void>((ctx) async {
        ctx
            .run(
              Job.deferred<void>(key: 'child', (child) async {
                child.onCancel(() {
                  // Inside the cascade: the parent is marked, and the pass
                  // that tells its listeners has not run yet.
                  parent.whenCancelled((_) => heard.add('late'));
                });
                await child.abandonable(() => delay(100));
              }),
            )
            .ignore();
        await ctx.abandonable(() => delay(100));
      })
        ..ignore()
        ..whenCancelled((_) => heard.add('early'));
      async.elapse(const Duration(milliseconds: 10));
      parent.cancel().ignore();
      async.flushTimers();
      expect(
        heard,
        ['early', 'late'],
        reason: 'a registration made later never runs before one made '
            'earlier, whatever window it is made in',
      );
    });
  });

  test('whenCancelled from onFinish of a job dropped before start', () {
    // `finish` calls `onFinish` before it tells the listeners; a job dropped
    // before its start is finished by then, but its cancellation is still
    // on its way to them, and a registration made there belongs to it.
    final seen = <Cancelled>[];
    final job = Job.deferred<void>(
      observer: _RegisterOnFinish(seen),
      (ctx) async {},
    );
    job.cancel().ignore();
    expect(seen, hasLength(1));
    expect(seen.single, same(job.outcome));
  });

  test('whenCancelled from onFinish of a job that ended Done', () {
    fakeAsync((async) {
      final seen = <Cancelled>[];
      Job<void>(observer: _RegisterOnFinish(seen), (ctx) async {});
      async.flushTimers();
      expect(seen, isEmpty);
    });
  });
}

class _RegisterOnFinish extends JobObserver {
  final List<Cancelled> seen;

  _RegisterOnFinish(this.seen);

  @override
  void onFinish(Job<Object?> job) => job.whenCancelled(seen.add);
}

/// A key whose formatting runs [onFormat] once.
final class _CancellingKey {
  void Function()? onFormat;

  @override
  String toString() {
    final action = onFormat;
    onFormat = null;
    action?.call();
    return 'key';
  }
}
