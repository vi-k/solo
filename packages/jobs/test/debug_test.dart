@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

void main() {
  tearDown(() => JobBase.debug = null);

  test('the debug channel traces the life of a job', () {
    final traces = <String>[];
    JobBase.debug = traces.add;
    fakeAsync((async) {
      final job = Job<void>(key: 'job', (ctx) => ctx.wait(() => delay(50)));
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
    JobBase.debug = traces.add;
    fakeAsync((async) {
      Job<void>(key: 'dropped', (ctx) async {}).cancel().ignore();
      final stubborn = Job<void>(
        key: 'stubborn',
        cancellable: false,
        (ctx) => ctx.wait(() => delay(20)),
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
    JobBase.debug = traces.add;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>(
            key: 'job',
            (ctx) async {
              ctx.onCancel(() => throw StateError('onCancel'));
              await ctx.wait(() => delay(50));
            },
          )..ignore();
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
}
