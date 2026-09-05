@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/journal.dart';

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
}
