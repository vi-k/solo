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
  /// the body walked away from, when the job's cleanup reaches this
  /// registration. Nothing is left listening.
  ///
  /// Returns when the stream is done. Throws the job's [Cancelled] if the
  /// job is cancelled meanwhile: the waiting ends there, because a stream
  /// that has gone quiet may never end at all. An error from [stream] and
  /// an error thrown by [onData] end the wait too and are thrown into the
  /// body, which can catch them like any others.
  ///
  /// An [onData] that returns a future is waited for, and delivery is held
  /// meanwhile: the events keep their order, whatever the source does, and
  /// a handler that threw is not called again. The job is not cancelled
  /// while it waits for a handler — a handler that must be interrupted
  /// takes the job's cancellation through the context, as any other code
  /// of the body does.
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
    if (job.isFinished) {
      // Said here rather than by the first registration below, which would
      // name a member of the context the caller never mentioned.
      throw StateError('$job has already finished, cannot follow a stream');
    }
    final done = Completer<void>();
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
    final early = <T>[];
    var earlyDone = false;
    Object? earlyError;
    StackTrace? earlyStack;
    StreamSubscription<T>? sub;
    // Whether the stream has been let go of. A cancelled subscription
    // drops what was still on its way to it; the buffer below is not the
    // subscription's, so it needs telling — otherwise a job that has been
    // cancelled, or has finished, goes on calling the handler.
    var letGo = false;

    void letGoOfStream() {
      letGo = true;
      unawaited(sub?.cancel());
    }

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

    void thrown(Object error, StackTrace stackTrace) {
      // The stream goes first: nothing else is delivered, so a handler
      // that threw is never called again.
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
          sub!.pause(handled.then<void>((_) {}, onError: thrown));
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
            await onData(early.removeAt(0));
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
        if (earlyError case final error?) {
          letGoOfStream();
          fail(error, earlyStack ?? StackTrace.current);
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
    // On the stack as well: a body that walks away from this call leaves a
    // job that may end without ever being marked, and then the callback
    // above never runs.
    final undispose = onDispose(letGoOfStream);
    try {
      // The waiting starts before the stream does: a source that hands over
      // an error from inside `listen` would otherwise end the wait before
      // anything was waiting on it, and Dart would take that error to the
      // zone instead of to the observer.
      final waiting = wait(() => done.future);
      try {
        sub = stream.listen(
          (event) {
            if (letGo) {
              return;
            }
            if (sub == null) {
              // Nothing after an error of the stream, here as anywhere.
              if (earlyError == null) {
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
            if (sub == null && early.isNotEmpty) {
              earlyError ??= error;
              earlyStack ??= stackTrace;
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
            if (sub == null && early.isNotEmpty) {
              earlyDone = true;
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
        rethrow;
      }
      if (early.isNotEmpty) {
        unawaited(playBack());
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
    }
  }
}
