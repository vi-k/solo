import 'dart:collection';

import 'package:async_job/async_job.dart';

import 'call_hook.dart';
import 'solo.dart';
import 'transition.dart';

/// Cross-cutting hooks for every controller: analytics, error reporting, a
/// single log. Set [Solo.observer] once at startup.
///
/// The engine calls the observer before the controller's own hook, and
/// independently of it: a subclass that forgets `super` does not switch the
/// observer off. A hook that throws hands its error to the current zone and
/// changes nothing else — the engine goes on, and the controller's own hook
/// is still called.
///
/// Several observers watch every controller through [SoloObserver.all].
abstract class SoloObserver {
  /// Creates an observer; a subclass calls it implicitly.
  SoloObserver();

  /// One observer made of [observers], in their order.
  ///
  /// Every hook goes to each of [observers] in turn, each call on its own:
  /// one that throws hands its error to the current zone, the way a single
  /// observer's does, and the next is called all the same.
  ///
  /// ```dart
  /// Solo.observer = SoloObserver.all([Log(), SlowCancellations()]);
  /// ```
  ///
  /// Throws [ArgumentError] when the same observer comes twice, counting those
  /// inside one made by [SoloObserver.all]: it would hear every hook twice.
  /// [observers] is walked once, here, and kept as a copy.
  factory SoloObserver.all(Iterable<SoloObserver> observers) {
    final all = List<SoloObserver>.unmodifiable(observers);
    final seen = HashSet<SoloObserver>.identity();
    void visit(SoloObserver observer) {
      if (!seen.add(observer)) {
        throw ArgumentError.value(
          observers,
          'observers',
          '$observer comes twice and would hear every hook twice',
        );
      }
      if (observer is _AllSoloObservers) {
        observer._observers.forEach(visit);
      }
    }

    all.forEach(visit);
    return _AllSoloObservers(all);
  }

  /// A controller was created.
  void onCreate(Solo<Object> solo) {}

  /// A job body is about to run.
  void onStart(Solo<Object> solo, Job<Object?> job) {}

  /// A job has an outcome, including jobs dropped before start.
  void onFinish(Solo<Object> solo, Job<Object?> job) {}

  /// Something a job did threw where there was nowhere else to put it.
  ///
  /// The body; an action abandoned by `JobContext.abandonable` failing later; a
  /// disposer or an `onCancel` callback; and a rule of the controller —
  /// `canStart` or `keepWhile` — that threw instead of answering.
  ///
  /// Called for every such error, including the ones that end as
  /// [Cancelled], which are never handed to the zone: a body that throws
  /// after cancellation, or an abandoned action that fails later. The
  /// job's own cancellation is not an error and never comes here; a
  /// [Cancelled] thrown by an abandoned action does, because for an
  /// observer that is a late failure like any other. One error at a time:
  /// each failure and each cancellation inside a `ParallelWaitError` comes
  /// in a call of its own.
  ///
  /// Watching changes nothing about where the error then goes: an error
  /// with nowhere else to go reaches the zone the job was created in
  /// whether an observer is set or not. To take that route over, set
  /// [Solo.errorHandler] — answering for an error is a job of its own,
  /// and setting up a log must not quietly turn reporting off. See
  /// [Failed] for the errors that also reach the zone.
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) {}

  /// The state changed, from a job or from `externalSetState`.
  ///
  /// [SoloTransition.job] says whose change it was, and
  /// [SoloTransition.revision] puts two of them in order.
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) {}

  /// A job called [JobContext.log].
  void onLog(Solo<Object> solo, Job<Object?> job, Object? message) {}

  /// The engine is about to finish closing: [Solo.isFinished] is still
  /// false, listeners are still registered, and a synchronous
  /// `externalSetState` still reaches them. Work scheduled after this hook
  /// runs after the engine has crossed that boundary.
  void onClose(Solo<Object> solo) {}
}

/// Answers for an error that has nowhere else to go; see
/// [Solo.errorHandler].
typedef SoloErrorHandler = void Function(
  Solo<Object> solo,
  Job<Object?> job,
  Object error,
  StackTrace stackTrace,
);

/// [SoloObserver.all].
final class _AllSoloObservers extends SoloObserver {
  final List<SoloObserver> _observers;

  _AllSoloObservers(this._observers);

  void _each(void Function(SoloObserver observer) hook) {
    for (final observer in _observers) {
      callHook(() => hook(observer));
    }
  }

  @override
  void onCreate(Solo<Object> solo) => _each((o) => o.onCreate(solo));

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      _each((o) => o.onStart(solo, job));

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) =>
      _each((o) => o.onFinish(solo, job));

  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) =>
      _each((o) => o.onError(solo, job, error, stackTrace));

  @override
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) =>
      _each((o) => o.onChange(solo, transition));

  @override
  void onLog(Solo<Object> solo, Job<Object?> job, Object? message) =>
      _each((o) => o.onLog(solo, job, message));

  @override
  void onClose(Solo<Object> solo) => _each((o) => o.onClose(solo));

  @override
  String toString() => 'SoloObserver.all($_observers)';
}
