@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

void main() {
  test('each follows the stream until it is done', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final seen = <int>[];
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, seen.add);
      });
      async.flushMicrotasks();
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

  test('the subscription lives exactly as long as the job', () {
    fakeAsync((async) {
      var cancelled = false;
      final controller = StreamController<int>(
        onCancel: () => cancelled = true,
      );
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, (_) {});
      });
      async.flushMicrotasks();
      expect(cancelled, isFalse);
      job.cancel().ignore();
      async.flushTimers();
      expect(cancelled, isTrue, reason: 'nothing is left listening');
      expect(job.outcome, isA<Cancelled>());
      controller.close().ignore();
    });
  });

  test('an error from the stream ends the wait and reaches the body', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      Object? caught;
      final job = Job<void>((ctx) async {
        try {
          await ctx.each(controller.stream, (_) {});
        } on Object catch (error) {
          caught = error;
        }
      });
      async.flushMicrotasks();
      controller.addError(StateError('stream'));
      async.flushMicrotasks();
      expect(caught, isA<StateError>());
      expect(job.outcome, isA<Done<void>>(), reason: 'the body caught it');
      controller.close().ignore();
    });
  });

  test('an error from onData ends the wait too', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, (_) => throw StateError('onData'));
      })
        ..ignore();
      async.flushMicrotasks();
      controller.add(1);
      async.elapse(const Duration(milliseconds: 10));
      expect(job.outcome, isA<Failed>());
      expect((job.outcome! as Failed).error, isA<StateError>());
      controller.close().ignore();
      async.flushTimers();
    });
  });
}
