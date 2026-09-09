@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

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
      final job = Job<void>((ctx) => ctx.wait(() => delay(50)))
        ..whenCancelled(seen.add);
      async.flushMicrotasks();
      job.cancel().ignore();
      expect(seen, hasLength(1));
      expect(seen.single.reason, CancelReason.manual);
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
    expect(seen.single.reason, CancelReason.manual);
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

  test('a refused cancellation sends no notification', () {
    fakeAsync((async) {
      final seen = <Cancelled>[];
      final job = Job<void>(
        (ctx) => ctx.wait(() => delay(50)),
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
        reason: CancelReason.manual,
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

  test('self cancellation waits for children and notifies before cleanup', () {
    fakeAsync((async) {
      final order = <String>[];
      Cancelled? seen;
      final job = Job<void>((ctx) async {
        ctx
          ..onCancel(() => order.add('context cancelled'))
          ..onDispose(() => order.add('cleanup'))
          ..run(
            Job.deferred<void>(cancellable: false, (child) async {
              await delay(20);
              order.add('child done');
            }),
          );
        throw const Cancelled('no photo');
      })
        ..whenCancelled((cancelled) {
          seen = cancelled;
          order.add('cancelled');
        });
      async.flushMicrotasks();
      expect(order, isEmpty);
      async.flushTimers();
      expect(order, ['child done', 'cancelled', 'cleanup']);
      expect(seen!.reason, CancelReason.handler);
      expect(seen!.description, 'no photo');
      expect(seen!.stackTrace, isNotNull);
      expect(job.outcome, same(seen));
    });
  });

  test('a callback error reaches the observer and other callbacks still run',
      () {
    final observer = _ErrorObserver();
    final seen = <Cancelled>[];
    final error = StateError('callback');
    final job = Job.deferred<void>((ctx) async {}, observer: observer)
      ..whenCancelled((_) => throw error)
      ..whenCancelled(seen.add);
    job.cancel().ignore();
    job.whenCancelled((_) => throw error);
    expect(observer.errors, [same(error), same(error)]);
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
}
