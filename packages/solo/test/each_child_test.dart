@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('a child emits after the parent body returned and holds the queue', () {
    runSolo((solo, journal, async) {
      final source = StreamController<int>();
      late Job<void> listening;
      final parent = solo.run<NotDisposed, void>((ctx) async {
        listening = ctx.each(source.stream, (child, event) {
          final state = child.state;
          expect(state, isA<NotDisposed>());
          expect(child.job, same(listening));
          child.emit(Preparing(progress: event));
        });
      });
      var nextStarted = false;
      final next = solo.run<TestState, void>((ctx) async {
        nextStarted = true;
      });
      async.flushMicrotasks();
      source.add(3);
      async.flushMicrotasks();
      expect(solo.currentState, const Preparing(progress: 3));
      expect(nextStarted, isFalse);
      expect(parent.isFinished, isFalse);
      expect(listening, isA<SoloJob<void>>());
      listening.cancel().ignore();
      async.flushMicrotasks();
      expect(listening.outcome, isA<Cancelled>());
      expect(parent.outcome, isA<Done<void>>());
      expect(next.outcome, isA<Done<void>>());
      expect(nextStarted, isTrue);
      source.close().ignore();
    });
  });

  test('the working type changes after the parent body returned', () {
    runSolo((solo, journal, async) {
      final source = StreamController<int>();
      late Job<void> listening;
      final parent = solo.run<NotDisposed, void>((ctx) async {
        listening = ctx.each(source.stream, (child, event) {});
      });
      async.flushMicrotasks();
      solo.externalSetState(const Disposed());
      async.flushMicrotasks();
      expect(source.hasListener, isFalse);
      expect(listening.outcome, isA<Cancelled>());
      expect(
        (listening.outcome! as Cancelled).reason,
        isA<RulesCancelReason>(),
      );
      expect(parent.outcome, isA<Done<void>>());
      source.close().ignore();
    });
  });

  test('keepWhile stops a child after the parent body returned', () {
    runSolo((solo, journal, async) {
      final source = StreamController<int>();
      late Job<void> listening;
      final parent = solo.run<TestState, void>(
        keepWhile: (state) => state is! Working,
        (ctx) async {
          listening = ctx.each(source.stream, (child, event) {});
        },
      );
      async.flushMicrotasks();
      solo.externalSetState(const Working());
      async.flushMicrotasks();
      expect(source.hasListener, isFalse);
      expect(listening.outcome, isA<Cancelled>());
      expect((listening.outcome! as Cancelled).description, 'keepWhile');
      expect(parent.outcome, isA<Done<void>>());
      source.close().ignore();
    });
  });

  test('canStart is not repeated when a parent starts following a stream', () {
    runSolo((solo, journal, async) {
      final source = StreamController<int>();
      var checks = 0;
      late Job<void> listening;
      final parent = solo.run<TestState, void>(
        canStart: (_) => ++checks == 1,
        (ctx) async {
          listening = ctx.each(source.stream, (child, event) {});
        },
      );
      async.flushMicrotasks();
      expect(checks, 1);
      expect(source.hasListener, isTrue);
      source.close().ignore();
      async.flushMicrotasks();
      expect(listening.outcome, isA<Done<void>>());
      expect(parent.outcome, isA<Done<void>>());
    });
  });

  test('a noncancellable parent can still have its subscription cancelled', () {
    runSolo((solo, journal, async) {
      final source = StreamController<int>();
      late Job<void> listening;
      final parent = solo.run<TestState, void>(
        cancellable: false,
        (ctx) async {
          listening = ctx.each(source.stream, (child, event) {});
        },
      );
      async.flushMicrotasks();
      parent.cancel().ignore();
      async.flushMicrotasks();
      expect(source.hasListener, isTrue);
      listening.cancel().ignore();
      async.flushMicrotasks();
      expect(source.hasListener, isFalse);
      expect(listening.outcome, isA<Cancelled>());
      expect(parent.outcome, isA<Done<void>>());
      source.close().ignore();
    });
  });

  test('a core-typed context still creates a child owned by the controller',
      () {
    runSolo((solo, journal, async) {
      final source = StreamController<int>();
      final parent = solo.run<NotDisposed, void>((ctx) async {
        final JobContext core = ctx;
        await core.each(source.stream, (child, event) {
          expect(child, isA<SoloContext<TestState, NotDisposed>>());
          (child as SoloContext<TestState, NotDisposed>)
              .emit(Preparing(progress: event));
        }).value;
      });
      async.flushMicrotasks();
      source.add(4);
      async.flushMicrotasks();
      expect(solo.currentState, const Preparing(progress: 4));
      source.close().ignore();
      async.flushMicrotasks();
      expect(parent.outcome, isA<Done<void>>());
    });
  });

  test('close waits for the active handler before releasing resources', () {
    runSolo((solo, journal, async) {
      final active = Completer<void>();
      final source = StreamController<int>();
      final log = <String>[];
      solo.run<TestState, void>((ctx) async {
        ctx
          ..onDispose(() => log.add('dispose'))
          ..each(source.stream, (child, event) async {
            log.add('handler starts');
            await active.future;
            log.add('handler ends');
          });
      });
      async.flushMicrotasks();
      source.add(1);
      async.flushMicrotasks();
      solo.close().then((_) => log.add('close returns'));
      async.flushMicrotasks();
      expect(source.hasListener, isFalse);
      expect(log, ['handler starts']);
      active.complete();
      async.flushMicrotasks();
      expect(
        log,
        ['handler starts', 'handler ends', 'dispose', 'close returns'],
      );
      source.close().ignore();
    });
  });
}
