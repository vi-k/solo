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
  /// the handle's own end, or on the source's accepted cancellation.
  JobBase<T>? _source;
  void Function() _unregisterSource = () {};

  /// What the source's `_done` holds instead of the handle. A listener on a
  /// future cannot be removed, and one bound to the handle would keep a
  /// cancelled handle, its observer and all they hold for as long as the
  /// source runs; [_detach] empties the relay instead.
  late final _relay = _SharedRelay<T>(this);

  _SharedJob(JobBase<T> source, {super.key, super.describe, super.observer})
    : _source = source {
    source._pendingContinuations++;
    // A source that has told its listeners of a cancellation tells a late
    // one at once, which would end the handle inside this call. A finished
    // source hands its outcome through `_done` on the next microtask, as a
    // Done or a Failed does; one still unwinding hands its cancellation
    // over on the next microtask too.
    if (source.isFinished) {
      // `_done` below.
    } else if (source._cancelled case final cancelled?) {
      _zone.run(
        () => scheduleMicrotask(() {
          if (_source != null) _sourceCancelled(cancelled);
        }),
      );
    } else {
      _unregisterSource = source.whenCancelled(_sourceCancelled);
    }
    // In the handle's own zone, as a continuation subscribes in its own.
    _zone.run(() => unawaited(source._done.future.then(_relay.call)));
  }

  /// At the mark: the outcome of the source is decided, and its cleanup is
  /// nothing this handle waits for. Through the queue a chain of
  /// continuations uses: handles nest, and a deep nest must not grow the
  /// call stack.
  void _sourceCancelled(Cancelled cause) =>
      _forwardCancellation(this, this, cause);

  /// Lets go of the source: it no longer waits for this handle before it
  /// answers for an unobserved failure, and no longer tells it of a
  /// cancellation.
  void _detach() {
    final source = _source;
    if (source == null) return;
    _source = null;
    _relay.handle = null;
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
        _notifyObserver(
          failed.error,
          failed.stackTrace,
          otherwise: heardAlready ? JobErrorAnswer.never : _laterOrNever,
        );
        // An observer that cancels the handle while hearing the error ends
        // it there and then, and the cancellation covers the failure. The
        // handle answers for it then, on the mark the other carriers read.
        if (isFinished) {
          if (!heardAlready) {
            if (!_ignored) _answer.answered = true;
            _reportCovered(failed, announced: true);
          }
          return;
        }
        finish(failed);
      // Reached only from a source that had finished when the handle was
      // made: on a later cancellation the source accepts, it comes through
      // [Job.whenCancelled] before its outcome, and detaches the handle.
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

/// Stands between the source's `_done` and a [_SharedJob]: holds the handle
/// until it lets go of the source, and nothing after.
final class _SharedRelay<T> {
  _SharedJob<T>? handle;

  _SharedRelay(this.handle);

  void call(Outcome<T> result) => handle?._sourceFinished(result);
}
