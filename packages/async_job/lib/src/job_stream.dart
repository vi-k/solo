part of 'job_base.dart';

/// The subscription body of the child started by [JobContext.each].
extension _JobStreamBody on JobContext {
  Future<void> _followStream<T>(
    Stream<T> stream,
    FutureOr<void> Function(T event) onData,
  ) async {
    final done = Completer<void>();
    // The signal carries no errors: this body owns and awaits the handler.
    // Throw failures from the body after it has stopped, so cancellation
    // uses the ordinary Job error route rather than a late wait's route.
    (Object, StackTrace)? failure;
    // What the source hands out from inside `listen` itself — a
    // synchronous broadcast controller giving a newcomer what it has —
    // arrives before there is a subscription to pause. It waits here and
    // is played back in order once there is one.
    //
    // This is the reason `each` is not `stream.asyncMap(onData).listen(...)`
    // and not a `StreamIterator`: both subscribe to the source from inside
    // their own `listen`, so events delivered during that call reach a
    // subscriber that does not exist yet, and both drop them without a
    // word (measured, 2026-09-07). A stream this package follows does not
    // lose its first events.
    // A queue, not a list: the replay takes events off the head, and a
    // list moves everything behind the head on every one of them. A batch
    // handed over from `onListen` can be large — 100 000 events cost
    // 371 ms of pure shifting at 20 000 (measured, 2026-09-08), and the
    // cost grows with the square.
    final early = ListQueue<T>();
    // What ended the window, if anything did: after either of these the
    // window takes nothing more, the way a live subscription takes
    // nothing after the end of its stream.
    var earlyDone = false;
    (Object, StackTrace)? earlyFailure;
    StreamSubscription<T>? sub;
    // Whether the stream has been let go of. A cancelled subscription
    // drops what was still on its way to it; the buffer below is not the
    // subscription's, so it needs telling — otherwise a job that has been
    // cancelled, or has finished, goes on calling the handler.
    var letGo = false;
    var subscriptionCancelled = false;
    Future<void>? active;

    void letGoOfStream() {
      letGo = true;
      // Dropped, not merely unawaited: `unawaited` leaves the future of
      // the source's own cleanup without a listener, and a cleanup that
      // fails would go from there to the zone, taking the program with
      // it. It is the source's business either way, this end of it too.
      //
      // This end of it, and no more: a source may route the same failure
      // elsewhere by itself — a broadcast controller runs `onCancel`
      // through `_runGuarded`, and one ending its stream hangs the cancel
      // future off a branch of its own — and no listener here reaches
      // those.
      if (sub != null && !subscriptionCancelled) {
        subscriptionCancelled = true;
        sub.cancel().ignore();
      }
    }

    void end() {
      if (!done.isCompleted) {
        done.complete();
      }
    }

    void fail(Object error, StackTrace stackTrace) {
      if (!done.isCompleted) {
        failure = (error, stackTrace);
        done.complete();
      }
    }

    void thrown(Object error, StackTrace stackTrace) {
      // The stream goes first: nothing else is delivered, so a handler
      // that threw is never called again.
      //
      // The source can cancel this job from its own `onCancel`. The
      // failure still leaves this body, and the engine preserves the
      // accepted cancellation as the outcome while notifying the observer.
      letGoOfStream();
      // A cancellation from the context has already marked the job, and the
      // wait below throws it by itself. A body cancelling itself with
      // `throw Cancelled(...)` has not: without this the stream is gone,
      // nothing will ever complete the wait, and the job hangs.
      if (error is Cancelled && job.isCancelled) {
        return;
      }
      fail(error, stackTrace);
    }

    void deliver(T event) {
      try {
        final handled = onData(event);
        if (handled is Future<void>) {
          // Delivery waits for the handler, so the events keep their order.
          // The signal never carries the error: it only says when to go on,
          // and `thrown` has the error already.
          final handling = handled.then<void>((_) {}, onError: thrown);
          active = handling;
          sub!.pause(handling);
        }
      } on Object catch (error, stackTrace) {
        thrown(error, stackTrace);
      }
    }

    /// Plays back what arrived before the subscription existed, one event
    /// at a time and with delivery held, then lets the stream go on.
    Future<void> playBack() async {
      sub!.pause();
      try {
        while (early.isNotEmpty && !letGo) {
          try {
            await onData(early.removeFirst());
          } on Object catch (error, stackTrace) {
            thrown(error, stackTrace);
            return;
          }
        }
        if (letGo) {
          // Everything left here belonged to a stream nobody holds any
          // more, the end of it and its error included.
          return;
        }
        if (earlyFailure case final failure?) {
          letGoOfStream();
          fail(failure.$1, failure.$2);
        } else if (earlyDone) {
          end();
        }
      } finally {
        // Not after the wait is over, and not on a stream already let go
        // of: there is nothing left to let through.
        if (!letGo && !done.isCompleted) {
          sub.resume();
        }
      }
    }

    // Registered before there is anything to subscribe: `onCancel` throws
    // for a job already cancelled or finished, and a subscription made
    // first would be left with nobody to cancel it. The callback may run
    // before `listen` comes back — a stream that cancels the job as it is
    // listened to — and then there is nothing to cancel yet: the `finally`
    // below takes care of it.
    final unregister = onCancel(letGoOfStream);
    // Also release the subscription if an engine finishes the child by
    // hand and unwinds its cleanup before this body returns.
    final undispose = onDispose(letGoOfStream);
    try {
      // Set up the cancellation-aware wait before the source can invoke
      // user code from inside `listen`.
      final waiting = wait(() => done.future);
      try {
        sub = stream.listen(
          (event) {
            if (letGo) {
              return;
            }
            if (sub == null) {
              // Nothing after the end of the stream and nothing after an
              // error of it, here as anywhere.
              if (!earlyDone && earlyFailure == null) {
                early.add(event);
              }
              return;
            }
            deliver(event);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (letGo) {
              return;
            }
            if (sub == null) {
              if (!earlyDone && earlyFailure == null) {
                earlyFailure = (error, stackTrace);
                if (early.isEmpty) {
                  // Nothing to play back ahead of it, so the wait ends
                  // here rather than in `playBack`.
                  letGoOfStream();
                  fail(error, stackTrace);
                }
              }
              return;
            }
            // Let go here rather than through `cancelOnError`: that one
            // hands the error over only once the source has finished its
            // own cleanup, and a source whose `onCancel` takes its time —
            // or never comes back — would hold the error, and the body,
            // for as long as it liked.
            letGoOfStream();
            fail(error, stackTrace);
          },
          onDone: () {
            if (letGo) {
              return;
            }
            if (sub == null) {
              if (!earlyDone && earlyFailure == null) {
                earlyDone = true;
                if (early.isEmpty) {
                  end();
                }
              }
              return;
            }
            end();
          },
          // `false`, and the error path lets go by itself: see `onError`.
          cancelOnError: false,
        );
      } on Object {
        // Nothing will ever complete the waiting now.
        end();
        // A throwing listen takes precedence over an earlier stream error.
        // The wait may already carry cancellation, which nobody awaits now.
        failure = null;
        waiting.ignore();
        rethrow;
      }
      if (early.isNotEmpty) {
        active = playBack();
      }
      await waiting;
    } finally {
      unregister();
      undispose();
      // Cancelled, not awaited: the call stops delivery at once, and its
      // future is the source's own cleanup, which this job does not own.
      // Awaiting it would also park the body forever under `FakeAsync`,
      // where a subscription's cancel future belongs to the root zone.
      letGoOfStream();
      // A callback may still own resources from this child or its parent.
      // Keep both jobs alive until it returns, even after cancellation.
      await active;
      if (failure case final failed?) {
        Error.throwWithStackTrace(failed.$1, failed.$2);
      }
    }
  }
}
