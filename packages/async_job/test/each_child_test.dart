@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/journal.dart';

void main() {
  test('the parent body returns while the stream remains open', () {
    fakeAsync((async) {
      final source = StreamController<int>();
      late Job<void> listening;
      final parent = Job<void>((ctx) async {
        listening = ctx.each(source.stream, (_, event) {});
      });
      async.flushMicrotasks();

      expect(listening, isA<Job<void>>());
      expect(listening.isChild, isTrue);
      expect(parent.isFinished, isFalse);
      expect(source.hasListener, isTrue);

      source.close().ignore();
      async.flushMicrotasks();
      expect(parent.outcome, isA<Done<void>>());
      expect(listening.outcome, isA<Done<void>>());
    });
  });

  test('one subscription is cancelled while its sibling keeps listening', () {
    fakeAsync((async) {
      final first = StreamController<int>();
      final second = StreamController<int>();
      final seen = <String>[];
      late Job<void> listening;
      final parent = Job<void>((ctx) async {
        listening = ctx.each(first.stream, (_, event) => seen.add('a$event'));
        ctx.each(second.stream, (_, event) => seen.add('b$event'));
      });
      async.flushMicrotasks();
      listening.cancel().ignore();
      async.flushMicrotasks();
      expect(listening.outcome, isA<Cancelled>());
      expect(parent.isCancelled, isFalse);
      expect(parent.isFinished, isFalse);
      expect(first.hasListener, isFalse);
      expect(second.hasListener, isTrue);
      first.add(1);
      second.add(2);
      async.flushMicrotasks();
      expect(seen, ['b2']);
      first.close().ignore();
      second.close().ignore();
      async.flushMicrotasks();
      expect(parent.outcome, isA<Done<void>>());
    });
  });

  test('parent cancellation waits for an active handler before cleanup', () {
    fakeAsync((async) {
      final log = <String>[];
      final active = Completer<void>();
      final source = StreamController<int>(
        onCancel: () => log.add('unsubscribe'),
      );
      late Job<void> listening;
      final parent = Job<void>((ctx) async {
        ctx.onDispose(() => log.add('parent cleanup'));
        listening = ctx.each(source.stream, (child, event) async {
          child.onDispose(() => log.add('child cleanup'));
          log.add('start $event');
          await active.future;
          log.add('end $event');
        });
      });
      async.flushMicrotasks();
      source
        ..add(1)
        ..add(2);
      async.flushMicrotasks();
      parent.cancel().then((_) => log.add('cancel returned'));
      async.flushMicrotasks();
      expect(log, ['start 1', 'unsubscribe']);
      expect(parent.isFinished, isFalse);
      expect(listening.isCancelled, isTrue);
      expect(listening.isFinished, isFalse);

      active.complete();
      async.flushMicrotasks();
      expect(log, [
        'start 1',
        'unsubscribe',
        'end 1',
        'child cleanup',
        'parent cleanup',
        'cancel returned',
      ]);
      expect(parent.outcome, isA<Cancelled>());
      expect(listening.outcome, isA<Cancelled>());
      source.close().ignore();
    });
  });

  test('child checkpoints stop a handler without cancelling its parent', () {
    fakeAsync((async) {
      final source = StreamController<int>();
      final waiting = Completer<void>();
      late Job<void> listening;
      var past = false;
      final parent = Job<void>((ctx) async {
        listening = ctx.each(source.stream, (child, event) async {
          expect(child.job, same(listening));
          await child.wait(() => waiting.future);
          past = true;
        });
      });
      async.flushMicrotasks();
      source.add(1);
      async.flushMicrotasks();
      listening.cancel().ignore();
      async.flushMicrotasks();
      expect(past, isFalse);
      expect(listening.outcome, isA<Cancelled>());
      expect(parent.outcome, isA<Done<void>>());
      waiting.complete();
      source.close().ignore();
      async.flushMicrotasks();
    });
  });

  test('cancellation waits for a handler replayed from onListen', () {
    fakeAsync((async) {
      final active = Completer<void>();
      final seen = <String>[];
      late StreamController<int> source;
      source = StreamController<int>.broadcast(
        sync: true,
        onListen: () => source
          ..add(1)
          ..add(2),
      );
      late Job<void> listening;
      final parent = Job<void>((ctx) async {
        listening = ctx.each(source.stream, (child, event) async {
          seen.add('start $event');
          await active.future;
          seen.add('end $event');
        });
      });
      async.flushMicrotasks();
      listening.cancel().ignore();
      async.flushMicrotasks();
      expect(seen, ['start 1']);
      expect(listening.isFinished, isFalse);
      expect(parent.isFinished, isFalse);
      expect(source.hasListener, isFalse);
      active.complete();
      async.flushMicrotasks();
      expect(seen, ['start 1', 'end 1']);
      expect(listening.outcome, isA<Cancelled>());
      expect(parent.outcome, isA<Done<void>>());
      source.close().ignore();
    });
  });

  test('a handler fails while cancellation is waiting for it', () {
    fakeAsync((async) {
      final active = Completer<void>();
      final source = StreamController<int>();
      final journal = JobJournal();
      late Job<void> listening;
      final parent = Job<void>(observer: journal, (ctx) async {
        listening = ctx.each(source.stream, (_, event) => active.future);
      });
      async.flushMicrotasks();
      source.add(1);
      async.flushMicrotasks();
      listening.cancel().ignore();
      async.flushMicrotasks();
      expect(listening.isFinished, isFalse);
      active.completeError(StateError('handler'));
      async.flushMicrotasks();
      expect(listening.outcome, isA<Cancelled>());
      expect(parent.outcome, isA<Done<void>>());
      expect(
        journal.lines.where((line) => line.contains('error')),
        ['> [null: each] error Bad state: handler'],
      );
      source.close().ignore();
    });
  });

  test('the child is cancelled from inside a synchronous handler', () {
    fakeAsync((async) {
      final source = StreamController<int>(sync: true);
      final seen = <int>[];
      final parent = Job<void>((ctx) async {
        ctx.each(source.stream, (child, event) {
          seen.add(event);
          child.job.cancel().ignore();
          child.check();
        });
      });
      async.flushMicrotasks();
      source
        ..add(1)
        ..add(2);
      async.flushMicrotasks();
      expect(seen, [1]);
      expect(parent.outcome, isA<Done<void>>());
      expect(source.hasListener, isFalse);
      source.close().ignore();
    });
  });

  for (final early in [false, true]) {
    test('a cancelled handler fails without an observer, early=$early', () {
      final zone = <Object>[];
      runZonedGuarded(
        () {
          fakeAsync((async) {
            final active = Completer<void>();
            late StreamController<int> source;
            source = StreamController<int>.broadcast(
              sync: true,
              onListen: early ? () => source.add(1) : null,
            );
            late Job<void> listening;
            final parent = Job<void>((ctx) async {
              listening = ctx.each(source.stream, (_, event) => active.future)
                ..ignore();
            });
            async.flushMicrotasks();
            if (!early) source.add(1);
            async.flushMicrotasks();
            listening.cancel().ignore();
            async.flushMicrotasks();
            expect(listening.isFinished, isFalse);
            active.completeError(StateError('after cancellation'));
            async.flushMicrotasks();
            expect(listening.outcome, isA<Cancelled>());
            expect(parent.outcome, isA<Done<void>>());
            source.close().ignore();
          });
        },
        (error, stack) => zone.add(error),
      );
      expect(zone, isEmpty);
    });
  }
}
