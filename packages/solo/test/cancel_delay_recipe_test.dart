@Timeout(Duration(seconds: 5))
library;

import 'package:clock/clock.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

/// The recipe from `doc/errors.md`, written as the page shows it.
///
/// The page promises three things about it, and all three are promises
/// about cancellation rather than about the observer, so they are pinned
/// here: a change to when `whenCancelled` fires would turn the recipe
/// into a lie without touching a line of it.
final class _SlowCancellations extends SoloObserver {
  final lines = <String>[];
  final _markedAt = Expando<DateTime>('cancellation');

  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) {
    job.whenCancelled((_) => _markedAt[job] = clock.now());
  }

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) {
    final markedAt = _markedAt[job];
    if (markedAt == null) return;
    final delay = clock.now().difference(markedAt);
    lines.add('${job.key} ${delay.inMilliseconds}');
  }
}

void main() {
  test('a bare await in the body is reported for its whole length', () {
    final observer = _SlowCancellations();
    runSolo((solo, journal, async) {
      SoloBase.observer = observer;
      // No checkpoint: nothing here notices the cancellation.
      solo.run<TestState, void>(key: 'bare', (ctx) async => delay(300));
      async.elapse(const Duration(milliseconds: 10));
      solo.cancelAll();
      async.flushTimers();
    });

    expect(observer.lines, ['bare 290']);
  });

  test('the same wait through the context is reported as no delay', () {
    final observer = _SlowCancellations();
    runSolo((solo, journal, async) {
      SoloBase.observer = observer;
      solo.run<TestState, void>(key: 'guarded', (ctx) => pause(ctx, 300));
      async.elapse(const Duration(milliseconds: 10));
      solo.cancelAll();
      async.flushTimers();
    });

    expect(observer.lines, ['guarded 0']);
  });

  test('a job dropped from the queue is not reported', () {
    final observer = _SlowCancellations();
    runSolo((solo, journal, async) {
      SoloBase.observer = observer;
      solo
        ..run<TestState, void>(key: 'running', (ctx) => pause(ctx, 100))
        ..run<TestState, void>(key: 'queued', (ctx) => pause(ctx, 100));
      async.flushMicrotasks();
      // Drops the queued job before it starts and cancels the running one.
      solo.cancelAll();
      async.flushTimers();
    });

    // Only the running job is heard: the queued one never reached onStart,
    // so nothing was registered for it and nothing was stamped.
    expect(observer.lines, ['running 0']);
  });

  test('a step held by uncancellable is not counted as delay', () {
    final observer = _SlowCancellations();
    runSolo((solo, journal, async) {
      SoloBase.observer = observer;
      solo.run<TestState, void>(key: 'held', (ctx) async {
        await ctx.uncancellable(() => delay(100));
        await delay(50);
      });
      async.elapse(const Duration(milliseconds: 10));
      solo.cancelAll();
      async.flushTimers();
    });

    // The protected step ran its remaining 90 ms untouched; only the bare
    // await after it counts.
    expect(observer.lines, ['held 50']);
  });
}
