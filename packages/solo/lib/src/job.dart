part of 'solo_base.dart';

/// A job of a controller: [Job] plus the queue.
///
/// Returned by [SoloBase.job], [SoloBase.add] and [SoloBase.run]. The
/// queue belongs to the controller, so [isQueued] lives here and not on
/// the handle every job has.
abstract interface class SoloJob<T> implements Job<T> {
  /// Whether the job waits in the controller's queue.
  bool get isQueued;
}

final class _SoloJob<S extends Object, W extends S, T> extends JobBase<T>
    implements SoloJob<T> {
  final SoloBase<S> _solo;
  final Future<T> Function(SoloContext<S, W> ctx) _body;
  final bool Function(W state)? _canStart;
  final bool Function(W state)? _keepWhile;

  /// Whether the controller has taken this handle already.
  ///
  /// The status and the queue together nearly say it, and for a moment
  /// they do not: a job the pump has taken out and not yet started is
  /// `created` and not queued, and a hook running right then — the error
  /// hook of a rule that threw — would be handed a job that looks brand
  /// new.
  var _added = false;

  _SoloJob(
    this._solo,
    this._body, {
    required super.key,
    required bool Function(W state)? canStart,
    required bool Function(W state)? keepWhile,
    required super.cancellable,
    required super.describe,
    required super.observer,
  })  : _canStart = canStart,
        _keepWhile = keepWhile;

  @override
  bool get isQueued => _solo._queue._jobs.contains(this);

  @override
  void adoptedBy(JobContextBase parent) {
    if (parent is! _SoloContext<S, S, Object?> ||
        !identical(parent._solo, _solo)) {
      throw ArgumentError.value(this, 'child', 'was not created by this Solo');
    }
    if (_solo._queue._jobs.contains(this)) {
      throw StateError('$this is queued and cannot be run as a child');
    }
    // Adoption is the controller taking the handle, the same as `add`: from
    // here nothing else may take it, and a rule of the child's own — asked
    // a moment later, while the child is still `created` and in no list —
    // must not be able to put it in the queue.
    _added = true;
  }

  @override
  void cancelWith(Cancelled cancelled, {bool rejectable = true}) {
    if (_solo._queue._jobs.contains(this)) {
      if (!cancellable && rejectable) {
        SoloBase._debug(() => 'remove $this: not cancellable');
        return;
      }
      SoloBase._debug(() => 'remove $this: $cancelled');
      _solo._queue._jobs.remove(this);
    }
    super.cancelWith(cancelled, rejectable: rejectable);
  }

  /// A rejection description if [state] fails the start rules, else null.
  String? _rejectStart(S state) {
    if (state is! W) {
      return 'is not $W';
    }
    final canStart = _canStart;
    if (canStart != null && !canStart(state)) {
      return 'canStart';
    }
    return _rejectKeep(state);
  }

  /// A rejection description if [state] fails the keep rules, else null.
  String? _rejectKeep(S state) {
    if (state is! W) {
      return 'is not $W';
    }
    final keepWhile = _keepWhile;
    if (keepWhile != null && !keepWhile(state)) {
      return 'keepWhile';
    }
    return null;
  }

  @override
  void started() => _solo._running.add(this);

  @override
  void finished() => _solo._onJobFinished(this);

  @override
  JobContextBase createContext() => _SoloContext<S, W, T>(this);

  @override
  Future<T> execute(covariant _SoloContext<S, W, T> ctx) => _body(ctx);

  // The engine reaches a job from the side, and `@protected` holds only
  // inside a subclass; these wrappers are how `SoloBase` and `_SoloQueue`
  // touch it.
  void _launch() => start();

  void _drop(Outcome<T> outcome) => finish(outcome);

  void _notifyObserver(Object error, StackTrace stackTrace) =>
      notifyObserver(error, stackTrace);

  void _notifyError(Object error, StackTrace stackTrace) =>
      notifyError(error, stackTrace);

  void _cancelWith(Cancelled cancelled, {bool rejectable = true}) =>
      cancelWith(cancelled, rejectable: rejectable);

  JobStatus get _jobStatus => status;

  bool get _bodyEnded => bodyEnded;

  Future<void> get _whenDone => whenDone;
}
