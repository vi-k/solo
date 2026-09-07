@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/probe_job.dart';

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

  test('the same error is traced when an observer takes it', () {
    final traces = <String>[];
    final seen = <String>[];
    JobBase.debug = traces.add;
    fakeAsync((async) {
      final job = Job<void>(
        key: 'job',
        observer: _RecordingObserver(seen),
        (ctx) async {
          ctx.onCancel(() => throw StateError('onCancel'));
          await ctx.wait(() => delay(50));
        },
      );
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
    });
    expect(traces, contains('Job(job) error: Bad state: onCancel'));
    expect(seen, ['Bad state: onCancel'], reason: 'and it stopped there');
  });

  test('finish called by hand tells the tracer about the stack', () {
    final lines = <String>[];
    JobBase.debug = lines.add;
    addTearDown(() => JobBase.debug = null);
    fakeAsync((async) {
      final job = ProbeJob<void>((ctx) async {
        ctx.onDispose(() {});
        await ctx.wait(() => delay(1000));
      })
        ..launch();
      async.elapse(const Duration(milliseconds: 10));
      // An engine of a domain ended the job itself: the children were not
      // waited for and the stack was not unwound, so a line about the
      // cleanups left behind is all there is.
      job
        ..drop(const Done(null))
        ..ignore();
      async.flushTimers();
    });
    expect(
      lines.where((line) => line.contains('cleanups pending')),
      hasLength(1),
    );
  });
}

/// Keeps the errors it is given, and nothing else.
final class _RecordingObserver implements JobObserver {
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
  void onLog(Job<Object?> job, String message) {}
}
