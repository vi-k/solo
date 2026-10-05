@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

/// A call through one of the two names, with the arguments both take.
typedef _Call = Future<String> Function(
  JobContext ctx,
  FutureOr<String> Function() action, {
  FutureOr<void> Function(String value)? dispose,
});

/// The deprecated alias and the member it forwards to, side by side: until
/// `wait` is removed, a call through either does the same thing.
final _names = <String, _Call>{
  'abandonable': (ctx, action, {dispose}) =>
      ctx.abandonable(action, dispose: dispose),
  // ignore: deprecated_member_use_from_same_package
  'wait': (ctx, action, {dispose}) => ctx.wait(action, dispose: dispose),
};

/// What the [StateError] of a call on a finished job says it cannot do.
const _cannot = {
  'abandonable': 'run an abandonable action',
  'wait': 'wait',
};

void main() {
  for (final MapEntry(key: name, value: call) in _names.entries) {
    group(name, () {
      test('returns the value, and lets go of the action on a cancellation',
          () {
        fakeAsync((async) {
          final seen = <String>[];
          var finishedAt = Duration.zero;
          final job = Job<void>((ctx) async {
            seen.add('got ${await call(ctx, () => 'ready')}');
            try {
              await call(
                ctx,
                () async {
                  await delay(100);
                  finishedAt = async.elapsed;
                  return 'db';
                },
                dispose: (value) => seen.add('disposed $value'),
              );
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
          call(kept, () {
            ran = true;
            return 'value';
          }).then<void>(
            (_) {},
            onError: (Object error) => thrown = error,
          );
          async.flushMicrotasks();

          expect(ran, isFalse);
          expect(
            thrown,
            isA<StateError>().having(
              (error) => error.message,
              'message',
              '$job has already finished, cannot ${_cannot[name]}',
            ),
          );
        });
      });
    });
  }
}
