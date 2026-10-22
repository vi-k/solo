part of 'job_base.dart';

/// Cancellations a chain passes along, drained by the call that queued the
/// first of them. One queue for continuations and handles of [Job.shared]:
/// a chain may alternate the two.
final _chainCancellations = Queue<void Function()>();
var _drainingChainCancellations = false;

/// Cancels [target] for [cause] with a [ChainCancelReason]; an error the
/// cancellation throws goes to [by].
///
/// Drains within this synchronous call, but does not recurse through every
/// link of the chain: a long chain must not grow the call stack.
void _forwardCancellation(
  JobBase<Object?> by,
  JobBase<Object?> target,
  Cancelled cause,
) {
  _chainCancellations.add(() {
    try {
      target.cancelWith(
        Cancelled.by(
          reason: ChainCancelReason(cause: cause),
          stackTrace: cause.stackTrace,
        ),
      );
    } on Object catch (error, stackTrace) {
      by.notifyError(error, stackTrace);
    }
  });
  if (_drainingChainCancellations) return;
  _drainingChainCancellations = true;
  try {
    while (_chainCancellations.isNotEmpty) {
      _chainCancellations.removeFirst()();
    }
  } finally {
    _drainingChainCancellations = false;
  }
}

/// A self-starting root that waits for another job before running its body.
final class _ThenJob<T, R> extends JobBase<R> {
  JobBase<T>? _source;
  FutureOr<R> Function(JobContext ctx, T value)? _onValue;
  Done<T>? _sourceValue;
  var _waitingForSource = true;
  void Function() _unregisterSource = () {};

  _ThenJob(
    JobBase<T> source,
    this._onValue, {
    super.key,
    super.describe,
    super.observer,
  }) : _source = source {
    source._pendingContinuations++;
    whenCancelled(_cancelSource);
    _unregisterSource = source.whenCancelled(_cancelFromSource);
    // Do not observe until a failure is actually forwarded. A cancelled
    // continuation must not swallow a source failure it will never carry.
    // Subscribed in the continuation's own zone, for the reason `_AutoJob`
    // starts in it: the body runs from this callback.
    _zone.run(() => unawaited(source._done.future.then(_sourceFinished)));
  }

  void _cancelFromSource(Cancelled cause) =>
      _forwardCancellation(this, this, cause);

  void _cancelSource(Cancelled cause) {
    final source = _source;
    if (source == null || source.isFinished) return;
    _forwardCancellation(this, source, cause);
  }

  void _sourceFinished(Outcome<T> result) {
    _source!._pendingContinuations--;
    _waitingForSource = false;
    _unregisterSource();
    if (_pendingCancel case final cancelled?) {
      finish(cancelled);
      return;
    }
    switch (result) {
      case Done<T>():
        _sourceValue = result;
        start();
      case Failed():
        final source = _source!.._observed = true;
        // Attached after the failure of the source was answered for: the
        // continuation carries the failure on, and its observer hears it,
        // but nobody is left to answer it for. Unobserved, it would be
        // answered for a second time -- and so would it from a continuation
        // of this one, which is why the mark passes on.
        _answerMark = source._answer;
        final heardAlready = _failureAnswered;
        if (heardAlready) {
          _observed = true;
        }
        _noteAnnounced(result.error);
        notifyObserver(result.error, result.stackTrace);
        // An observer may cancel this continuation while hearing the error.
        // The failure is this continuation's now, and a cancellation that
        // decides its outcome covers it, as it would a failure of a body.
        // The answer goes on the mark: a handle beside the source's other
        // carriers shares it with them.
        final decided = outcome ?? _pendingCancel ?? result;
        finish(decided);
        if (decided is Cancelled && !heardAlready) {
          if (!_ignored) _answer.answered = true;
          _reportCovered(result, announced: true);
        }
      case Cancelled():
        _cancelFromSource(result);
    }
  }

  @override
  void finish(Outcome<R> outcome) {
    if (_waitingForSource && outcome is Cancelled) {
      if (_pendingCancel != null) return;
      // Mark first: listeners synchronously forward cancellation in both
      // directions and may immediately come back to this job. Keep waiting
      // for the source; only the signal, never the wait, travels backwards.
      _pendingCancel = outcome;
      _markCancelled(outcome);
      return;
    }
    super.finish(outcome);
  }

  @override
  void finished() {
    _unregisterSource();
    _unregisterSource = () {};
    _source = null;
    _sourceValue = null;
    _onValue = null;
  }

  @override
  JobContextBase createContext() => _CoreContext(this);

  @override
  Future<R> execute(covariant _CoreContext ctx) async {
    ctx.check();
    return _onValue!(ctx, _sourceValue!.value);
  }
}
