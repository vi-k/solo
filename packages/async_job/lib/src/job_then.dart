part of 'job_base.dart';

/// A self-starting root that waits for another job before running its body.
final class _ThenJob<T, R> extends JobBase<R> {
  static final _cancellations = Queue<void Function()>();
  static var _drainingCancellations = false;

  JobBase<T>? _source;
  FutureOr<R> Function(JobContext ctx, T value)? _onValue;
  Done<T>? _sourceValue;
  var _waitingForSource = true;
  void Function() _unregisterSource = () {};

  _ThenJob(JobBase<T> source, this._onValue, {super.observer})
      : _source = source,
        super(describe: () => 'then') {
    source._pendingContinuations++;
    whenCancelled(_cancelSource);
    _unregisterSource = source.whenCancelled(_cancelFromSource);
    // Do not observe until a failure is actually forwarded. A cancelled
    // continuation must not swallow a source failure it will never carry.
    unawaited(source._done.future.then(_sourceFinished));
  }

  void _cancelFromSource(Cancelled cause) => _forwardCancellation(this, cause);

  void _cancelSource(Cancelled cause) {
    final source = _source;
    if (source == null || source.isFinished) return;
    _forwardCancellation(source, cause);
  }

  void _forwardCancellation(JobBase<Object?> target, Cancelled cause) {
    // Drain within this synchronous call, but do not recurse through every
    // predecessor and successor. A long chain must not grow the call stack.
    _cancellations.add(() {
      try {
        target.cancelWith(
          Cancelled.by(
            reason: ChainCancelReason(cause: cause),
            started: target.isRunning,
            stackTrace: cause.stackTrace,
          ),
        );
      } on Object catch (error, stackTrace) {
        notifyError(error, stackTrace);
      }
    });
    if (_drainingCancellations) return;
    _drainingCancellations = true;
    try {
      while (_cancellations.isNotEmpty) {
        _cancellations.removeFirst()();
      }
    } finally {
      _drainingCancellations = false;
    }
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
        _source!._observed = true;
        notifyObserver(result.error, result.stackTrace);
        // An observer may cancel this continuation while hearing the error.
        final decided = outcome ?? _pendingCancel ?? result;
        finish(decided);
        if (decided is Cancelled) _reportCovered(result);
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
  void adoptedBy(JobContextBase parent) => throw ArgumentError.value(
        this,
        'child',
        'A continuation starts itself after its source finishes',
      );

  @override
  JobContextBase createContext() => _CoreContext(this);

  @override
  Future<R> execute(covariant _CoreContext ctx) async {
    ctx.check();
    return _onValue!(ctx, _sourceValue!.value);
  }
}
