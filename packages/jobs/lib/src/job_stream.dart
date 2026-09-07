import 'dart:async';

import 'job_base.dart';

/// [JobContext] and a stream: following one for as long as the job lives.
extension JobStream on JobContext {
  /// Follows [stream], calling [onData] for every event, until the stream
  /// is done or the job gives up.
  ///
  /// The subscription belongs to the job: it is cancelled when the stream
  /// ends, when the body leaves this call, the moment the job is marked
  /// cancelled — before the body itself learns about it — and, for a call
  /// the body walked away from, when the job ends whatever the outcome.
  /// Nothing is left listening.
  ///
  /// Returns when the stream is done. Throws the job's [Cancelled] if the
  /// job is cancelled meanwhile: the waiting ends there, because a stream
  /// that has gone quiet may never end at all. An error from [stream] and
  /// an error thrown by [onData] end the wait too and are thrown into the
  /// body, which can catch them like any others.
  ///
  /// An [onData] that returns a future is waited for, and delivery is held
  /// until it comes back: the events keep their order, and an error of the
  /// handler ends the wait the same way a synchronous one does. The job is
  /// not cancelled while it waits for a handler — a handler that must be
  /// interrupted takes the job's cancellation through the context, as any
  /// other code of the body does.
  ///
  /// The subscription is cancelled, never awaited: delivery stops at once,
  /// and whatever the source does about it afterwards is the source's own
  /// business. A source that must be waited for is a call of its own —
  /// [JobContext.join] around it.
  ///
  /// ```dart
  /// await ctx.each(hw.positions, (p) => ctx.log('at $p'));
  /// ```
  Future<void> each<T>(
    Stream<T> stream,
    FutureOr<void> Function(T event) onData,
  ) async {
    final done = Completer<void>();
    void end() {
      if (!done.isCompleted) {
        done.complete();
      }
    }

    void fail(Object error, StackTrace stackTrace) {
      if (!done.isCompleted) {
        done.completeError(error, stackTrace);
      }
    }

    // Nullable, and registered before there is anything to subscribe:
    // `onCancel` throws for a job already cancelled or finished, and a
    // subscription made first would be left with nobody to cancel it. The
    // callback may run before `listen` comes back — a stream that cancels
    // the job as it is listened to — and then there is nothing to cancel
    // yet: the `finally` below takes care of it.
    StreamSubscription<T>? sub;
    // A job that ends without ever being marked — the body walked away
    // from this call and then returned — never runs the callback above, so
    // the stack takes the subscription too.
    final unregister = onCancel(() => sub?.cancel());
    final undispose = onDispose(() => unawaited(sub?.cancel()));

    void thrown(Object error, StackTrace stackTrace) {
      unawaited(sub?.cancel());
      // A cancellation from the context has already marked the job, and the
      // wait below throws it by itself. A body cancelling itself with
      // `throw Cancelled(...)` has not: without this the stream is gone,
      // nothing will ever complete the wait, and the job hangs.
      if (error is Cancelled && job.isCancelled) {
        return;
      }
      fail(error, stackTrace);
    }

    // Held until `listen` comes back: a source that delivers from inside
    // `listen` has nothing to pause yet.
    final held = <Future<void>>[];
    try {
      sub = stream.listen(
        (event) {
          try {
            final handled = onData(event);
            if (handled is Future<void>) {
              // Delivery waits for the handler, so the events keep their
              // order. The signal never carries the error: it only says
              // when to go on, and `thrown` has the error already.
              final resume = handled.then<void>((_) {}, onError: thrown);
              final current = sub;
              if (current == null) {
                held.add(resume);
              } else {
                current.pause(resume);
              }
            }
          } on Object catch (error, stackTrace) {
            thrown(error, stackTrace);
          }
        },
        onError: fail,
        onDone: end,
        cancelOnError: true,
      );
      held
        ..forEach(sub.pause)
        ..clear();
      await wait(() => done.future);
    } finally {
      unregister();
      undispose();
      // Cancelled, not awaited: the call stops delivery at once, and its
      // future is the source's own cleanup, which this job does not own.
      // Awaiting it would also park the body forever under `FakeAsync`,
      // where a subscription's cancel future belongs to the root zone.
      unawaited(sub?.cancel());
    }
  }
}
