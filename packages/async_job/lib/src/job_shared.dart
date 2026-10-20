part of 'job_base.dart';

/// A handle of [Job.shared]: a root with no body that ends with the outcome
/// of its source and never reaches back to it.
///
/// The core can end a root that never started — [JobBase.finish] asks only
/// whether the job is over — so the outcome of the source becomes the
/// outcome of the handle with no body in between. Not a [_ThenJob]: one of
/// those waits for its source when cancelled, and nothing of the source is
/// a handle's to wait for.
final class _SharedJob<T> extends JobBase<T> {
  /// The source until the handle is detached: on the source's outcome, on
  /// the handle's own end, or on the source's accepted cancellation. The
  /// listener on `_done` of the source cannot be removed, so this is what
  /// tells it to do nothing.
  JobBase<T>? _source;
  void Function() _unregisterSource = () {};

  _SharedJob(JobBase<T> source, {super.observer})
      : _source = source,
        super(describe: () => 'shared') {
    source._pendingContinuations++;
    _unregisterSource = source.whenCancelled(_sourceCancelled);
    // In the handle's own zone, as a continuation subscribes in its own.
    _zone.run(() => unawaited(source._done.future.then(_sourceFinished)));
  }

  /// At the mark: the outcome of the source is decided, and its cleanup is
  /// nothing this handle waits for.
  void _sourceCancelled(Cancelled cause) => cancelWith(
        Cancelled.by(
          reason: ChainCancelReason(cause: cause),
          started: false,
          stackTrace: cause.stackTrace,
        ),
      );

  /// Lets go of the source: it no longer waits for this handle before it
  /// answers for an unobserved failure, and no longer tells it of a
  /// cancellation.
  void _detach() {
    final source = _source;
    if (source == null) return;
    _source = null;
    source._pendingContinuations--;
    _unregisterSource();
    _unregisterSource = () {};
  }

  void _sourceFinished(Outcome<T> result) {
    final source = _source;
    if (source == null) return;
    _detach();
    switch (result) {
      case Done<T>():
        finish(result);
      case final Failed failed:
        source._observed = true;
        // One mark for the source and every handle that carries its
        // failure: whichever of them reaches the answer first answers, and
        // a source answered for already is answered for here too.
        _answerMark = source._answer;
        final heardAlready = _failureAnswered;
        if (heardAlready) {
          _observed = true;
        }
        _noteAnnounced(failed.error);
        notifyObserver(failed.error, failed.stackTrace);
        // An observer that cancels the handle while hearing the error ends
        // it there and then, and the cancellation covers the failure.
        if (isFinished) {
          if (!heardAlready) {
            _reportCovered(failed, announced: true);
          }
          return;
        }
        finish(failed);
      case final Cancelled cancelled:
        _sourceCancelled(cancelled);
    }
  }

  @override
  void finished() => _detach();

  @override
  JobContextBase createContext() =>
      throw StateError('$this has no body to run');

  @override
  Future<T> execute(JobContextBase ctx) =>
      throw StateError('$this has no body to run');
}
