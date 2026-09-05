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

  test('each leaves nothing listening for a job already cancelled', () {
    fakeAsync((async) {
      var listened = false;
      final controller = StreamController<int>(
        onListen: () => listened = true,
      );
      Object? thrown;
      final job = Job<void>((ctx) async {
        try {
          await ctx.wait(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        } on Cancelled {
          // Caught: the body walks on to a stream anyway.
        }
        try {
          await ctx.each(controller.stream, (_) {});
        } on Object catch (error) {
          thrown = error;
        }
      });
      async.elapse(const Duration(milliseconds: 5));
      job.cancel().ignore();
      async.flushTimers();
      expect(thrown, isA<Cancelled>());
      expect(listened, isFalse, reason: 'it never subscribed at all');
      expect(controller.hasListener, isFalse);
      controller.close().ignore();
    });
  });

  test('a body that cancels itself from onData does not hang', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, (event) {
          if (event == 2) {
            throw const Cancelled('enough');
          }
        });
      });
      async.flushMicrotasks();
      controller
        ..add(1)
        ..add(2);
      async.elapse(const Duration(milliseconds: 10));
      expect(job.outcome, isA<Cancelled>());
      expect(
        (job.outcome! as Cancelled).description,
        contains('enough'),
        reason: 'a body cancelling itself is not a cancellation from outside',
      );
      expect(controller.hasListener, isFalse);
      controller.close().ignore();
    });
  });
}
