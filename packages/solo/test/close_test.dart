@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/journal.dart';
import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('close of an idle controller closes the stream after onClose', () {
    runSolo((solo, journal, async) {
      solo.stream.listen(
        (_) {},
        onDone: () => journal.lines.add('stream done'),
      );
      final first = solo.close();
      final second = solo.close();
      expect(identical(first, second), isTrue);
      expect(solo.isClosed, isTrue);
      async.flushMicrotasks();
      expect(journal.take(), ['closed', 'stream done']);
    });
  });

  test('close drops every queued job, cancellable or not', () {
    runSolo((solo, journal, async) {
      solo
        ..run<TestState, void>(key: 'a', (ctx) async {})
        ..run<TestState, void>(
          key: 'keep',
          cancellable: false,
          (ctx) async {},
        )
        ..close();
      async.flushMicrotasks();
      expect(journal.take(), [
        '[a] dropped Cancelled(closed)',
        '[keep] dropped Cancelled(closed)',
        'closed',
      ]);
    });
  });

  test('close cancels the current job and waits for its body', () {
    runSolo((solo, journal, async) {
      solo
        ..run<TestState, void>(key: 'job', (ctx) async {
          await delay(100);
          ctx.check();
        })
        ..run<TestState, void>(key: 'next', (ctx) async {});
      async.elapse(const Duration(milliseconds: 50));
      var closed = false;
      solo.close().then((_) => closed = true);
      async.flushMicrotasks();
      expect(closed, isFalse);
      expect(journal.take(), [
        '[job] started',
        '[next] dropped Cancelled(closed)',
      ]);
      async.elapse(const Duration(milliseconds: 50));
      expect(closed, isTrue);
      expect(journal.take(), ['[job] finished Cancelled(closed)', 'closed']);
    });
  });

  test('close waits for a cancellable: false job without cancelling', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(
        key: 'stubborn',
        cancellable: false,
        (ctx) async {
          await delay(100);
          ctx.emit(const Preparing());
        },
      );
      async.elapse(const Duration(milliseconds: 50));
      solo.close();
      async.elapse(const Duration(milliseconds: 50));
      expect(journal.take(), [
        '[stubborn] started',
        'state: Preparing(progress: 0)',
        '[stubborn] finished Done(null)',
        'closed',
      ]);
    });
  });

  test('add after close finishes the job with Cancelled(closed)', () {
    runSolo((solo, journal, async) {
      final early = solo.run<TestState, void>(key: 'early', (ctx) async {});
      solo.close();
      final job = solo.run<TestState, void>(key: 'late', (ctx) async {});
      expect(job.isFinished, isTrue);
      final dropped = job.outcome! as Cancelled;
      expect(dropped.reason, CancelReason.closed);
      final drained = early.outcome! as Cancelled;
      expect(
        identical(dropped.stackTrace, drained.stackTrace),
        isTrue,
        reason: 'both point at the close call',
      );
      async.flushMicrotasks();
      expect(journal.take(), [
        '[early] dropped Cancelled(closed)',
        '[late] dropped Cancelled(closed)',
        'closed',
      ]);
    });
  });

  test('whenCancelled completes for a job added after close', () {
    runSolo((solo, journal, async) {
      solo.close();
      final job = solo.run<TestState, void>(key: 'late', (ctx) async {});
      var cancelled = false;
      job.whenCancelled.then((_) => cancelled = true);
      async.flushMicrotasks();
      expect(cancelled, isTrue);
      expect(journal.take(), ['[late] dropped Cancelled(closed)', 'closed']);
    });
  });

  test('close re-entered from a hook returns the same future', () {
    fakeAsync((async) {
      final solo = _CloseOnFinish()
        ..run<TestState, void>(key: 'dropped', (ctx) async {});
      final outer = solo.close();
      expect(solo.reentered, isNotNull, reason: 'the hook ran');
      expect(identical(solo.reentered, outer), isTrue);
      async.flushTimers();
    });
  });

  test('close does not touch the state', () {
    runSolo(initialState: const Working(), (solo, journal, async) {
      solo.close();
      async.flushMicrotasks();
      expect(solo.state, const Working());
    });
  });

  test('externalSetState from onChange keeps state fresh after emit', () {
    fakeAsync((async) {
      final journal = JournalObserver();
      SoloBase.observer = journal;
      final solo = _Reentrant();
      final seen = <TestState>[];
      solo.stream.listen(seen.add);
      // Read inside the body, asserted outside: a failing `expect` in a
      // job body ends the job as `Failed` instead of failing the test.
      TestState? stateAfterEmit;
      try {
        solo.run<NotDisposed, void>(key: 'job', (ctx) async {
          ctx.emit(const Preparing());
          stateAfterEmit = solo.state;
        });
        async.flushMicrotasks();
        expect(stateAfterEmit, const Working(), reason: 'hook already ran');
        expect(seen, [const Preparing(), const Working()]);
        expect(journal.take(), [
          '[job] started',
          'state: Preparing(progress: 0)',
          'state: Working(a: 0, b: 0)',
          '[job] finished Done(null)',
        ]);
      } finally {
        solo.close();
        async.flushTimers();
        SoloBase.observer = null;
      }
    });
  });

  test('externalSetState from a stream listener runs after the job step', () {
    runSolo((solo, journal, async) {
      final seen = <TestState>[];
      solo.stream.listen((state) {
        seen.add(state);
        if (state is Preparing) {
          solo.externalSetState(const Working());
        }
      });
      TestState? stateAfterEmit;
      solo.run<NotDisposed, void>(key: 'job', (ctx) async {
        ctx.emit(const Preparing());
        stateAfterEmit = solo.state;
      });
      async.flushMicrotasks();
      expect(
        stateAfterEmit,
        const Preparing(),
        reason: 'listener not yet run',
      );
      expect(seen, [const Preparing(), const Working()]);
      expect(solo.state, const Working());
    });
  });

  test('publish runs after onChange and before rules re-evaluation', () {
    runSolo((solo, journal, async) {
      final order = <String>[];
      final recorder = _Recorder(order);
      final job = recorder.run<Initial, void>(key: 'job', (ctx) async {
        await delay(100);
        ctx.check();
      });
      async.elapse(const Duration(milliseconds: 50));
      recorder.setState(const Working(), job);
      expect(order, ['onChange', 'publish not cancelled', 'cancelled']);
      async.elapse(const Duration(milliseconds: 50));
      recorder.close();
    });
  });
}

final class _CloseOnFinish extends Solo<TestState> {
  _CloseOnFinish() : super(const Initial());

  /// The future returned by the `close` called from inside `close`.
  Future<void>? reentered;

  @override
  void onFinish(Job<Object?> job) {
    reentered ??= close();
  }
}

final class _Reentrant extends Solo<TestState> {
  _Reentrant() : super(const Initial());

  @override
  void onChange(TestState previous, TestState current) {
    if (current is Preparing) {
      externalSetState(const Working());
    }
  }
}

final class _Recorder extends SoloBase<TestState> {
  final List<String> order;
  Job<Object?>? watched;

  _Recorder(this.order) : super(const Initial());

  void setState(TestState state, Job<Object?> job) {
    watched = job;
    externalSetState(state);
    order.add(job.isCancelled ? 'cancelled' : 'not cancelled');
  }

  @override
  void onChange(TestState previous, TestState current) => order.add('onChange');

  @override
  void publish(TestState previous, TestState current) {
    super.publish(previous, current);
    final cancelled = watched?.isCancelled ?? false;
    order.add('publish ${cancelled ? 'cancelled' : 'not cancelled'}');
  }
}
