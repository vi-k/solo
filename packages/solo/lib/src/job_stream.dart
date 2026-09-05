import 'dart:async';

import 'solo_base.dart';

/// [JobContext] and a stream: following one for as long as the job lives.
extension JobStream<S extends Object, W extends S> on JobContext<S, W> {
  /// Follows [stream], calling [onData] for every event, until the stream
  /// is done or the job gives up.
  ///
  /// The subscription belongs to the job: it is cancelled when the stream
  /// ends, when the body leaves this call, and the moment the job is marked
  /// cancelled — before the body itself learns about it. Nothing is left
  /// listening.
  ///
  /// Returns when the stream is done. Throws the job's [Cancelled] if the
  /// job is cancelled meanwhile: the waiting ends there, because a stream
  /// that has gone quiet may never end at all. An error from [stream] and
  /// an error thrown by [onData] end the wait too and are thrown into the
  /// body, which can catch them like any others.
  ///
  /// The subscription is cancelled, never awaited: delivery stops at once,
  /// and whatever the source does about it afterwards is the source's own
  /// business. A source that must be waited for is a call of its own —
  /// [JobContext.join] around it.
  ///
  /// ```dart
  /// await ctx.each(hw.positions, (p) => ctx.emit(Tracking(p)));
  /// ```
  Future<void> each<T>(Stream<T> stream, void Function(T event) onData) async {
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

    late final StreamSubscription<T> sub;
    sub = stream.listen(
      (event) {
        try {
          onData(event);
        } on Cancelled {
          // The job went down inside the callback: the body learns about it
          // from the wait below, and the stream is of no use any more.
          unawaited(sub.cancel());
        } on Object catch (error, stackTrace) {
          unawaited(sub.cancel());
          fail(error, stackTrace);
        }
      },
      onError: fail,
      onDone: end,
      cancelOnError: true,
    );
    final unregister = onCancel(sub.cancel);
    try {
      await wait(() => done.future);
    } finally {
      unregister();
      // Cancelled, not awaited: the call stops delivery at once, and its
      // future is the source's own cleanup, which this job does not own.
      // Awaiting it would also park the body forever under `FakeAsync`,
      // where a subscription's cancel future belongs to the root zone.
      unawaited(sub.cancel());
    }
  }
}
