@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/journal.dart';
import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('each returns when the stream is done', () {
    runSolo((solo, journal, async) {
      final events = StreamController<int>();
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        await ctx
            .each(
              events.stream,
              (child, p) => child.emit(Preparing(progress: p)),
            )
            .value;
        ctx.emit(const Working());
      });
      async.flushMicrotasks();
      events
        ..add(1)
        ..add(2);
      async.flushMicrotasks();
      events.close();
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
      expect(journal.take(), [
        '[job] started',
        '> [null: each] started',
        'state: Preparing(progress: 1)',
        'state: Preparing(progress: 2)',
        '> [null: each] finished Done(null)',
        'state: Working(a: 0, b: 0)',
        '[job] finished Done(null)',
      ]);
    });
  });

  test('a cancelled job drops the subscription and stops waiting', () {
    runSolo((solo, journal, async) {
      var cancelled = false;
      final events = StreamController<int>(onCancel: () => cancelled = true);
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        await ctx
            .each(
              events.stream,
              (child, p) => child.emit(Preparing(progress: p)),
            )
            .value;
        ctx.emit(const Working());
      });
      async.flushMicrotasks();
      events.add(1);
      async.flushMicrotasks();
      job.cancel();
      async.flushTimers();
      expect(cancelled, isTrue, reason: 'the subscription goes with the job');
      expect(job.outcome, isA<Cancelled>());
      expect(journal.take(), [
        '[job] started',
        '> [null: each] started',
        'state: Preparing(progress: 1)',
        '> [null: each] finished Cancelled(parent)',
        '[job] finished Cancelled(manual)',
      ]);
      events.close();
    });
  });

  test('a stream error is thrown into the body', () {
    runSolo((solo, journal, async) {
      var cancelled = false;
      final events = StreamController<int>(onCancel: () => cancelled = true);
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        try {
          await ctx
              .each(
                events.stream,
                (child, p) => child.emit(Preparing(progress: p)),
              )
              .value;
        } on FormatException {
          // The parent handles the child's stream failure.
          ctx.emit(const Working());
        }
      });
      async.flushMicrotasks();
      events.addError(const FormatException('the wire is noisy'));
      async.flushTimers();
      expect(cancelled, isTrue);
      expect(job.outcome, isA<Done<void>>());
      expect(journal.take(), [
        '[job] started',
        '> [null: each] started',
        '> [null: each] error FormatException: the wire is noisy',
        '> [null: each] finished Failed(FormatException: the wire is noisy)',
        'state: Working(a: 0, b: 0)',
        '[job] finished Done(null)',
      ]);
      events.close();
    });
  });

  test('a rule that stopped holding ends the job and the subscription', () {
    runSolo((solo, journal, async) {
      var cancelled = false;
      final events = StreamController<int>(onCancel: () => cancelled = true);
      solo.run<NotDisposed, void>(key: 'job', (ctx) async {
        await ctx
            .each(
              events.stream,
              (child, p) => child.emit(Preparing(progress: p)),
            )
            .value;
      });
      async.flushMicrotasks();
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(cancelled, isTrue);
      expect(journal.take(), [
        '[job] started',
        '> [null: each] started',
        'state: Disposed()',
        '> [null: each] finished Cancelled(rules: is not NotDisposed)',
        '[job] finished Cancelled(rules: is not NotDisposed)',
      ]);
      events.close();
    });
  });

  test('an error from the callback is thrown into the body', () {
    runSolo((solo, journal, async) {
      var cancelled = false;
      final events = StreamController<int>(onCancel: () => cancelled = true);
      // `ignore`, because an unobserved `Failed` goes to the zone.
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        await ctx.each(events.stream, (child, p) {
          if (p == 2) {
            throw const FormatException('bad event');
          }
          child.emit(Preparing(progress: p));
        }).value;
      })
        ..ignore();
      async.flushMicrotasks();
      events
        ..add(1)
        ..add(2)
        ..add(3);
      async.flushTimers();
      expect(cancelled, isTrue, reason: 'the stream is over for this job');
      expect(job.outcome, isA<Failed>());
      expect(journal.take(), [
        '[job] started',
        '> [null: each] started',
        'state: Preparing(progress: 1)',
        '> [null: each] error FormatException: bad event',
        '> [null: each] finished Failed(FormatException: bad event)',
        '[job] error FormatException: bad event',
        '[job] finished Failed(FormatException: bad event)',
      ]);
      events.close();
    });
  });

  test('awaiting the child from inside its own callback is a deadlock', () {
    runSolo((solo, journal, async) {
      final events = StreamController<int>();
      var callbackReturned = false;
      final parent = solo.run<TestState, void>(key: 'parent', (ctx) async {
        await ctx.each<int>(events.stream, (child, event) async {
          await child.job.done;
          callbackReturned = true;
        }).value;
      });
      async.flushMicrotasks();
      events.add(1);
      async.flushMicrotasks();
      // Cancelled, so the body of the child is unwinding and the only
      // thing left to wait for is the callback in flight -- which is
      // waiting for the child.
      parent.cancel().ignore();
      async.elapse(const Duration(seconds: 100));
      expect(callbackReturned, isFalse);
      expect(
        parent.outcome,
        isNull,
        reason: 'the child waits for the callback that waits for the child',
      );
      events.close().ignore();
    });
  });

  test('a source that never finishes its cleanup does not hold the child', () {
    runSolo((solo, journal, async) {
      final never = Completer<void>();
      final events = StreamController<int>(onCancel: () => never.future);
      final parent = solo.run<TestState, void>(key: 'parent', (ctx) async {
        await ctx.each<int>(events.stream, (child, event) {}).value;
      });
      async.flushMicrotasks();
      parent.cancel().ignore();
      async.elapse(const Duration(seconds: 10));
      expect(
        parent.outcome,
        isA<Cancelled>(),
        reason: 'the cleanup of the source is not this job to wait for',
      );
      events.close().ignore();
    });
  });

  test('a callback stops its own subscription with an unawaited cancel', () {
    runSolo((solo, journal, async) {
      final events = StreamController<int>();
      final seen = <int>[];
      final parent = solo.run<TestState, void>(key: 'parent', (ctx) async {
        await ctx.each<int>(events.stream, (child, event) async {
          seen.add(event);
          child.job.cancel().ignore();
        }).value;
      });
      async.flushMicrotasks();
      events.add(1);
      async.flushMicrotasks();
      events.add(2);
      async.flushTimers();
      expect(seen, [1], reason: 'the subscription is gone with the child');
      expect(parent.outcome, isA<Cancelled>());
      events.close();
    });
  });

  // The page tells the reader to wait with the callback's own context; the
  // two below are what that buys. The action runs on either way -- what
  // differs is when the job is free to end.
  test('a plain await in the callback holds the parent until it returns', () {
    runSolo((solo, journal, async) {
      final events = StreamController<int>();
      final parent = solo.run<TestState, void>(key: 'parent', (ctx) async {
        await ctx.each<int>(events.stream, (child, event) async {
          await delay(1000);
        }).value;
      });
      async.elapse(const Duration(milliseconds: 10));
      events.add(1);
      async.elapse(const Duration(milliseconds: 40));
      parent.cancel().ignore();
      async.elapse(const Duration(milliseconds: 959));
      expect(
        parent.outcome,
        isNull,
        reason: 'nothing in the callback has a checkpoint to stop at',
      );
      async.elapse(const Duration(milliseconds: 2));
      expect(parent.outcome, isA<Cancelled>());
      events.close();
    });
  });

  test('child.wait in the callback ends the parent with the cancellation', () {
    runSolo((solo, journal, async) {
      final events = StreamController<int>();
      final parent = solo.run<TestState, void>(key: 'parent', (ctx) async {
        await ctx.each<int>(events.stream, (child, event) async {
          await child.wait(() => delay(1000));
        }).value;
      });
      async.elapse(const Duration(milliseconds: 10));
      events.add(1);
      async.elapse(const Duration(milliseconds: 40));
      parent.cancel().ignore();
      async.elapse(const Duration(milliseconds: 5));
      expect(
        parent.outcome,
        isA<Cancelled>(),
        reason: 'the wait ends with the cancellation, the delay runs on',
      );
      async.flushTimers();
      events.close();
    });
  });

  test('a cancellation inside the callback comes back through the wait', () {
    fakeAsync((async) {
      final journal = JournalObserver();
      Solo.observer = journal;
      final solo = _DisposeOnSecond();
      final events = StreamController<int>();
      var past = false;
      try {
        solo.run<NotDisposed, void>(key: 'job', (ctx) async {
          await ctx
              .each(
                events.stream,
                (child, p) => child.emit(Preparing(progress: p)),
              )
              .value;
          past = true;
        });
        async.flushMicrotasks();
        events
          ..add(1)
          ..add(2);
        async.flushTimers();
        expect(past, isFalse, reason: 'the hook cancelled the job meanwhile');
        expect(journal.take(), [
          '[job] started',
          '> [null: each] started',
          'state: Preparing(progress: 1)',
          'state: Preparing(progress: 2)',
          'state: Disposed()',
          '> [null: each] finished Cancelled(rules: is not NotDisposed)',
          '[job] finished Cancelled(rules: is not NotDisposed)',
        ]);
      } finally {
        events.close();
        solo.close();
        async.flushTimers();
        Solo.observer = null;
      }
    });
  });
}

/// Pushes the state out of `NotDisposed` from inside the second change,
/// so the job is cancelled inside its own `emit`, inside a stream callback.
final class _DisposeOnSecond extends Solo<TestState> {
  _DisposeOnSecond() : super(const Initial());

  @override
  void onChange(SoloTransition<TestState> transition) {
    final current = transition.current;
    if (current is Preparing && current.progress == 2) {
      externalSetState(const Disposed());
    }
  }
}
