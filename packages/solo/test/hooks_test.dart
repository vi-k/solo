@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/journal.dart';
import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('log lines carry the job level', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        ctx.log('hello');
        final child = solo.job<TestState, void>(key: 'child', (ctx) async {
          ctx.log(42);
        });
        await ctx.run(child).done;
      });
      async.flushTimers();
      expect(journal.take(), [
        '[parent] started',
        '[parent] log hello',
        '> [child] started',
        '> [child] log 42',
        '> [child] finished Done(null)',
        '[parent] finished Done(null)',
      ]);
    });
  });

  test('the observer runs before each instance hook, super or not', () {
    fakeAsync((async) {
      final journal = JournalObserver();
      SoloBase.observer = journal;
      final solo = _Hooked(journal.lines);
      try {
        solo.run<TestState, void>(key: 'job', (ctx) async {
          ctx
            ..emit(const Preparing())
            ..log('x');
          throw StateError('boom');
        });
        async.flushMicrotasks();
        expect(journal.take(), [
          '[job] started',
          'hook: start job',
          'state: Preparing(progress: 0)',
          'hook: change Preparing(progress: 0)',
          '[job] log x',
          'hook: log x',
          '[job] error Bad state: boom',
          'hook: error Bad state: boom',
          '[job] finished Failed(Bad state: boom)',
          'hook: finish job',
        ]);
      } finally {
        solo.close();
        async.flushTimers();
        SoloBase.observer = null;
      }
    });
  });

  test('SoloBase.debug receives engine traces', () {
    final traces = <String>[];
    SoloBase.debug = traces.add;
    try {
      runSolo((solo, journal, async) {
        solo.run<TestState, void>(key: 'job', (ctx) async {
          ctx.emit(const Preparing());
        });
        async.flushMicrotasks();
      });
    } finally {
      SoloBase.debug = null;
    }
    expect(traces, contains('add Job(job)'));
    expect(traces, contains('Job(job) started'));
    expect(traces, contains('state: Preparing(progress: 0)'));
    expect(traces, contains('Job(job) finished: Done(null)'));
  });
}

final class _Hooked extends Solo<TestState> {
  final List<String> lines;

  _Hooked(this.lines) : super(const Initial());

  @override
  void onStart(Job<Object?> job) => lines.add('hook: start ${job.key}');

  @override
  void onFinish(Job<Object?> job) => lines.add('hook: finish ${job.key}');

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      lines.add('hook: error $error');

  @override
  void onLog(Job<Object?> job, String message) =>
      lines.add('hook: log $message');

  @override
  void onChange(TestState previous, TestState current) =>
      lines.add('hook: change $current');
}
