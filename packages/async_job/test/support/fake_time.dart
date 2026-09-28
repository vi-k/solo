import 'package:fake_async/fake_async.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

/// A test whose [body] is written with `await` and runs on fake time.
///
/// The body is started inside `fakeAsync`, and every timer it schedules
/// fires as soon as nothing else is left to run: a step of `Duration.zero`
/// is still a step after the microtasks, as it is on the real event loop,
/// but no wall clock is waited for. A body still waiting once no timer is
/// left fails the test instead of hanging it.
@isTest
void fakeAsyncTest(String description, Future<void> Function() body) {
  test(description, () {
    fakeAsync((async) {
      var finished = false;
      Object? failure;
      StackTrace? failureTrace;
      body().then(
        (_) => finished = true,
        onError: (Object error, StackTrace stackTrace) {
          failure = error;
          failureTrace = stackTrace;
          finished = true;
        },
      );
      async.flushTimers();
      if (failure case final error?) {
        Error.throwWithStackTrace(error, failureTrace!);
      }
      // A future of the root zone -- `close` of a stream controller whose
      // subscription is cancelled hands one back -- completes through a
      // microtask fake time does not run; do not await one here.
      expect(
        finished,
        isTrue,
        reason: 'the body waits for what no timer brings',
      );
    });
  });
}
