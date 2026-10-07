@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/journal.dart';

void main() {
  test('a stream followed to its end', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final seen = <int>[];
      final job = Job.each(controller.stream, (ctx, event) => seen.add(event));
      controller
        ..add(1)
        ..add(2);
      async.flushMicrotasks();
      controller.close().ignore();
      async.flushMicrotasks();
      expect(seen, [1, 2]);
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('a broadcast event sent right after the call', () {
    fakeAsync((async) {
      final controller = StreamController<int>.broadcast();
      final seen = <int>[];
      final job = Job.each(controller.stream, (ctx, event) => seen.add(event));
      controller.add(1);
      async.flushMicrotasks();
      expect(seen, [1]);
      job.cancel().ignore();
      async.flushMicrotasks();
      controller.close().ignore();
    });
  });

  test('an observer asked before the call returns', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final journal = JobJournal();
      final job = Job.each(
        controller.stream,
        (ctx, event) {},
        key: 'job',
        observer: journal,
      );
      expect(journal.lines, ['[job: each] started']);
      controller.close().ignore();
      async.flushMicrotasks();
      expect(journal.lines, [
        '[job: each] started',
        '[job: each] finished Done(null)',
      ]);
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('a second event while an asynchronous callback runs', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final log = <String>[];
      Job.each(controller.stream, (ctx, event) async {
        log.add('begin $event');
        await delay(10);
        log.add('end $event');
      });
      controller
        ..add(1)
        ..add(2);
      async.flushMicrotasks();
      expect(log, ['begin 1']);
      async.elapse(const Duration(milliseconds: 10));
      expect(log, ['begin 1', 'end 1', 'begin 2']);
      async.elapse(const Duration(milliseconds: 10));
      controller.close().ignore();
      async.flushMicrotasks();
    });
  });

  test('a stream error nobody reads', () {
    fakeAsync((async) {
      final zoneErrors = <Object>[];
      var cancelled = false;
      final controller = StreamController<int>(
        onCancel: () => cancelled = true,
      );
      late final Job<void> job;
      runZonedGuarded(
        () => job = Job.each(controller.stream, (ctx, event) {}),
        (error, _) => zoneErrors.add(error),
      );
      controller.addError(StateError('stream'));
      async.flushMicrotasks();
      expect(job.outcome, isA<Failed>());
      expect(cancelled, isTrue);
      expect(zoneErrors, [isA<StateError>()]);
      controller.close().ignore();
    });
  });

  test('a callback that throws on the first of two events', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      var calls = 0;
      final job = Job.each(controller.stream, (ctx, event) {
        calls++;
        throw StateError('onData');
      })
        ..ignoreFailure();
      controller
        ..add(1)
        ..add(2);
      async.flushMicrotasks();
      expect(calls, 1);
      expect(job.outcome, isA<Failed>());
      controller.close().ignore();
    });
  });

  test('a cancellation while the callback runs', () {
    fakeAsync((async) {
      var cancelled = false;
      final controller = StreamController<int>(
        onCancel: () => cancelled = true,
      );
      final job = Job.each(controller.stream, (ctx, event) => delay(10));
      controller.add(1);
      async.flushMicrotasks();
      job.cancel().ignore();
      async.flushMicrotasks();
      expect(cancelled, isTrue);
      expect(job.isFinished, isFalse, reason: 'the callback is still at it');
      async.elapse(const Duration(milliseconds: 10));
      expect(
        job.outcome,
        isA<Cancelled>().having((c) => c.started, 'started', isTrue),
      );
      controller.close().ignore();
    });
  });

  test('a cancellation right after the call', () {
    fakeAsync((async) {
      var listened = false;
      var cancelled = false;
      final controller = StreamController<int>(
        onListen: () => listened = true,
        onCancel: () => cancelled = true,
      );
      final job = Job.each(controller.stream, (ctx, event) {})
        ..cancel().ignore();
      async.flushMicrotasks();
      expect(listened, isTrue);
      expect(cancelled, isTrue);
      expect(
        job.outcome,
        isA<Cancelled>().having((c) => c.started, 'started', isTrue),
      );
      controller.close().ignore();
    });
  });

  test('cancellable: false cancelled right after the call', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final seen = <int>[];
      final job = Job.each(
        controller.stream,
        (ctx, event) => seen.add(event),
        cancellable: false,
      )..cancel().ignore();
      async.flushMicrotasks();
      expect(job.isCancelled, isFalse);
      controller.add(1);
      async.flushMicrotasks();
      controller.close().ignore();
      async.flushMicrotasks();
      expect(seen, [1]);
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('a stream that is already listened to', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      controller.stream.listen((_) {});
      final job = Job.each(controller.stream, (ctx, event) {})..ignoreFailure();
      async.flushMicrotasks();
      expect(
        job.outcome,
        isA<Failed>().having((f) => f.error, 'error', isA<StateError>()),
      );
      controller.close().ignore();
    });
  });

  test('an event handed over from inside listen', () {
    fakeAsync((async) {
      late final StreamController<int> controller;
      controller = StreamController<int>.broadcast(
        sync: true,
        onListen: () => controller.add(1),
      );
      final seen = <int>[];
      Job<Object?>? own;
      final job = Job.each(controller.stream, (ctx, event) {
        seen.add(event);
        own = ctx.job;
      });
      expect(seen, [1], reason: 'the playback starts inside the call');
      expect(own, same(job), reason: 'the handle the caller had not got yet');
      async.flushMicrotasks();
      expect(seen, [1]);
      job.cancel().ignore();
      async.flushMicrotasks();
      controller.close().ignore();
    });
  });

  test('handed to ctx.run', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      Object? refusal;
      late final Job<void> root;
      Job<void>((ctx) async {
        root = Job.each(controller.stream, (ctx, event) {});
        try {
          await ctx.run(root);
        } on Object catch (error) {
          refusal = error;
        }
      });
      async.flushMicrotasks();
      expect(refusal, isA<ArgumentError>());
      expect(
        '$refusal',
        contains('follows its stream by itself; a child is made with ctx.each'),
      );
      expect(root.isRunning, isTrue, reason: 'a refusal cancels nothing');
      root.cancel().ignore();
      async.flushMicrotasks();
      controller.close().ignore();
    });
  });

  test('handed to ctx.runAll next to a deferred sibling', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      Object? refusal;
      var siblingRan = false;
      late final Job<void> root;
      Job<void>((ctx) async {
        root = Job.each(controller.stream, (ctx, event) {});
        try {
          await ctx.runAll([
            Job.deferred<void>((ctx) async => siblingRan = true),
            root,
          ]);
        } on Object catch (error) {
          refusal = error;
        }
      });
      async.flushMicrotasks();
      expect(refusal, isA<ArgumentError>());
      expect(
        '$refusal',
        contains('follows its stream by itself; a child is made with ctx.each'),
      );
      expect(siblingRan, isFalse);
      root.cancel().ignore();
      async.flushMicrotasks();
      controller.close().ignore();
    });
  });

  test('with a key, with a description and with neither', () {
    fakeAsync((async) {
      final controller = StreamController<int>.broadcast();
      final plain = Job.each(controller.stream, (ctx, event) {});
      final keyed = Job.each(controller.stream, (ctx, event) {}, key: 'k');
      final named = Job.each(
        controller.stream,
        (ctx, event) {},
        key: 'k',
        describe: () => 'saving',
      );
      expect('$plain', 'Job(each)');
      expect('$keyed', 'Job(k: each)');
      expect('$named', 'Job(k: saving)');
      for (final job in [plain, keyed, named]) {
        job.cancel().ignore();
      }
      async.flushMicrotasks();
      controller.close().ignore();
    });
  });

  test('a child the callback starts and does not await', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final journal = JobJournal();
      final job = Job.each(
        controller.stream,
        (ctx, event) {
          ctx
              .run(Job.deferred<void>((ctx) => delay(10), key: 'child'))
              .ignore();
        },
        key: 'job',
        observer: journal,
      );
      controller.add(1);
      async.flushMicrotasks();
      controller.close().ignore();
      async.flushMicrotasks();
      expect(job.isFinished, isFalse);
      async.elapse(const Duration(milliseconds: 10));
      expect(job.outcome, isA<Done<void>>());
      expect(journal.lines, [
        '[job: each] started',
        '> [child] started',
        '> [child] finished Done(null)',
        '[job: each] finished Done(null)',
      ]);
    });
  });

  test('made inside unattended work, under a zone forked in it', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final outerJournal = JobJournal();
      final zoneErrors = <Object>[];
      Object? tag;
      Object? fork;
      runZonedGuarded(
        () {
          Job<void>(
            (ctx) async {
              ctx.unattended(() {
                runZoned(
                  () {
                    Job.each(controller.stream, (ctx, event) {
                      tag = Zone.current[#tag];
                      fork = Zone.current[#fork];
                      throw StateError('inner');
                    });
                  },
                  zoneValues: {#fork: true},
                );
              });
            },
            key: 'outer',
            observer: outerJournal,
          );
        },
        (error, _) => zoneErrors.add(error),
        zoneValues: {#tag: 'outside'},
      );
      async.flushMicrotasks();
      controller.add(1);
      async.flushMicrotasks();
      expect(tag, 'outside');
      expect(fork, isNull, reason: 'past the zone forked inside the work');
      expect(zoneErrors, [isA<StateError>()]);
      expect(outerJournal.lines, [
        '[outer] started',
        '[outer] finished Done(null)',
      ]);
      controller.close().ignore();
    });
  });

  test('no type argument and no annotation on the event', () {
    fakeAsync((async) {
      final controller = StreamController<String>();
      final lengths = <int>[];
      // No type argument and no annotation: `event` must be a String.
      final job = Job.each(controller.stream, (ctx, event) {
        lengths.add(event.length);
      });
      final asyncJob = Job.each(
        const Stream<int>.empty(),
        (ctx, event) async => ctx.log(event.isEven),
      );
      controller.add('abc');
      async.flushMicrotasks();
      controller.close().ignore();
      async.flushMicrotasks();
      expect(lengths, [3]);
      expect(job.outcome, isA<Done<void>>());
      expect(asyncJob.outcome, isA<Done<void>>());
    });
  });

  test('the job of the callback context', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      Job<Object?>? seen;
      final job = Job.each(controller.stream, (ctx, event) => seen = ctx.job);
      controller.add(1);
      async.flushMicrotasks();
      expect(seen, same(job));
      expect(job.level, 0);
      expect(job.isChild, isFalse);
      job.cancel().ignore();
      async.flushMicrotasks();
      controller.close().ignore();
    });
  });

  test('made inside the body of another job', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      late final Job<void> inner;
      final outer = Job<void>((ctx) async {
        inner = Job.each(controller.stream, (ctx, event) {});
      });
      async.flushMicrotasks();
      expect(outer.outcome, isA<Done<void>>(), reason: 'it did not wait');
      expect(inner.isRunning, isTrue);
      expect(inner.isChild, isFalse);
      inner.cancel().ignore();
      async.flushMicrotasks();
      controller.close().ignore();
    });
  });

  test('cancel() of a cancellable: false one', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      var finished = false;
      final job = Job.each(
        controller.stream,
        (ctx, event) {},
        cancellable: false,
      );
      job.cancel().then((_) => finished = true).ignore();
      async.flushMicrotasks();
      expect(finished, isFalse, reason: 'cancel() waits for the stream to end');
      expect(controller.hasListener, isTrue);
      controller.close().ignore();
      async.flushMicrotasks();
      expect(finished, isTrue);
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('a cancellable: false one whose callback throws Cancelled', () {
    fakeAsync((async) {
      var cancelled = false;
      final controller = StreamController<int>(
        onCancel: () => cancelled = true,
      );
      final job = Job.each(
        controller.stream,
        (ctx, event) => throw const Cancelled('enough'),
        cancellable: false,
      );
      controller.add(1);
      async.flushMicrotasks();
      expect(job.outcome, isA<Cancelled>());
      expect(cancelled, isTrue, reason: 'nothing is left listening');
      controller.close().ignore();
    });
  });

  test('then and whenCancelled over a cancelled one', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final job = Job.each(controller.stream, (ctx, event) {});
      final next = job.then<String>((ctx, _) async => 'after');
      Cancelled? heard;
      job.whenCancelled((cancelled) => heard = cancelled);
      job.cancel().ignore();
      async.flushMicrotasks();
      expect(heard, isNotNull);
      expect(next.outcome, isA<Cancelled>());
      controller.close().ignore();
    });
  });
}
