@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

void main() {
  group('abandonable', () {
    test('returns the value, and lets go of the action on a cancellation', () {
      fakeAsync((async) {
        final seen = <String>[];
        var finishedAt = Duration.zero;
        final job = Job<void>((ctx) async {
          seen.add('got ${await ctx.abandonable(() => 'ready')}');
          try {
            await ctx.abandonable(() async {
              await delay(100);
              finishedAt = async.elapsed;
              return 'db';
            }, dispose: (value) => seen.add('disposed $value'));
          } on Cancelled {
            seen.add('Cancelled at ${async.elapsed.inMilliseconds} ms');
            rethrow;
          }
        });
        async.elapse(const Duration(milliseconds: 10));
        job.cancel().ignore();
        async.flushTimers();

        expect(job.outcome, isA<Cancelled>());
        expect(seen, ['got ready', 'Cancelled at 10 ms', 'disposed db']);
        expect(
          finishedAt.inMilliseconds,
          100,
          reason: 'the action ran on after the call let go of it',
        );
      });
    });

    test('on a finished job throws a StateError that names the call', () {
      fakeAsync((async) {
        late JobContext kept;
        final job = Job<void>(key: 'late', (ctx) async {
          kept = ctx;
        });
        async.flushMicrotasks();
        expect(job.isFinished, isTrue);

        var ran = false;
        Object? thrown;
        kept
            .abandonable(() {
              ran = true;
              return 'value';
            })
            .then<void>((_) {}, onError: (Object error) => thrown = error);
        async.flushMicrotasks();

        expect(ran, isFalse);
        expect(
          thrown,
          isA<StateError>().having(
            (error) => error.message,
            'message',
            '$job has already finished, cannot run an abandonable action',
          ),
        );
      });
    });
  });
}
