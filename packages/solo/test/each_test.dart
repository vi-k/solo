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
        await ctx.each(
          events.stream,
          (p) => ctx.emit(Preparing(progress: p)),
        );
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
        'state: Preparing(progress: 1)',
        'state: Preparing(progress: 2)',
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
        await ctx.each(
          events.stream,
          (p) => ctx.emit(Preparing(progress: p)),
        );
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
        'state: Preparing(progress: 1)',
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
          await ctx.each(
            events.stream,
            (p) => ctx.emit(Preparing(progress: p)),
          );
        } on FormatException {
          // The stream failed; the job reports it itself.
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
        await ctx.each(
          events.stream,
          (p) => ctx.emit(Preparing(progress: p)),
        );
      });
      async.flushMicrotasks();
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(cancelled, isTrue);
      expect(journal.take(), [
        '[job] started',
        'state: Disposed()',
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
        await ctx.each(events.stream, (p) {
          if (p == 2) {
            throw const FormatException('bad event');
          }
          ctx.emit(Preparing(progress: p));
        });
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
        'state: Preparing(progress: 1)',
        '[job] error FormatException: bad event',
        '[job] finished Failed(FormatException: bad event)',
      ]);
      events.close();
    });
  });

  test('a cancellation inside the callback comes back through the wait', () {
    fakeAsync((async) {
      final journal = JournalObserver();
      SoloBase.observer = journal;
      final solo = _DisposeOnSecond();
      final events = StreamController<int>();
      var past = false;
      try {
        solo.run<NotDisposed, void>(key: 'job', (ctx) async {
          await ctx.each(
            events.stream,
            (p) => ctx.emit(Preparing(progress: p)),
          );
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
          'state: Preparing(progress: 1)',
          'state: Preparing(progress: 2)',
          'state: Disposed()',
          '[job] finished Cancelled(rules: is not NotDisposed)',
        ]);
      } finally {
        events.close();
        solo.close();
        async.flushTimers();
        SoloBase.observer = null;
      }
    });
  });
}

/// Pushes the state out of `NotDisposed` from inside the second change,
/// so the job is cancelled inside its own `emit`, inside a stream callback.
final class _DisposeOnSecond extends Solo<TestState> {
  _DisposeOnSecond() : super(const Initial());

  @override
  void onChange(TestState previous, TestState current) {
    if (current is Preparing && current.progress == 2) {
      externalSetState(const Disposed());
    }
  }
}
