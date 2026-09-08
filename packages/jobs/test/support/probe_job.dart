import 'package:jobs/jobs.dart';

/// A job of the core with its protected surface opened for tests.
final class ProbeJob<T> extends JobBase<T> {
  final Future<T> Function(JobContext ctx) _body;

  /// The lifecycle hooks a subclass gets, in the order they were called.
  final hooks = <String>[];

  ProbeJob(this._body, {super.key, super.observer, super.cancellable});

  @override
  void started() => hooks.add('started');

  @override
  void finished() => hooks.add('finished');

  /// How many children are still being waited for.
  int get childCount => children.length;

  /// The waiting list itself, as a subclass of the core sees it.
  List<JobBase<Object?>> get childrenList => children;

  /// Starts the body the way an engine of a domain would.
  void launch() => start();

  /// Ends the job from the outside, the way an engine of a domain would.
  void drop(Outcome<T> outcome) => finish(outcome);

  /// Cancels the job with a cancellation of its own, the way an engine of
  /// a domain does.
  void cancelBy(Cancelled cancelled) => cancelWith(cancelled);

  /// Sends an error to the zone the way an engine of a domain does, when
  /// its own route for one with nowhere to go ends with nobody.
  void report(Object error, StackTrace stackTrace) =>
      reportToZone(error, stackTrace);

  @override
  JobContextBase createContext() => ProbeContext(this);

  @override
  Future<T> execute(covariant ProbeContext ctx) => _body(ctx);
}

/// The context that goes with [ProbeJob].
final class ProbeContext extends JobContextBase {
  ProbeContext(super.owner);
}

/// A job of the core that refuses whoever tries to adopt it.
final class UnadoptableJob<T> extends JobBase<T> {
  final Future<T> Function(JobContext ctx) _body;

  UnadoptableJob(this._body, {super.key});

  /// Where the job is in its life; protected on [JobBase].
  JobStatus get statusNow => status;

  /// Starts the body the way an engine of a domain would.
  void launch() => start();

  @override
  void adoptedBy(JobContextBase parent) =>
      throw ArgumentError.value(this, 'child', 'refuses this parent');

  @override
  JobContextBase createContext() => ProbeContext(this);

  @override
  Future<T> execute(covariant ProbeContext ctx) => _body(ctx);
}

/// A job whose context turns every child away before it starts.
final class RefusingParentJob<T> extends JobBase<T> {
  final Future<T> Function(JobContext ctx) _body;

  RefusingParentJob(this._body, {super.key, super.observer});

  /// Starts the body the way an engine of a domain would.
  void launch() => start();

  @override
  JobContextBase createContext() => RefusingContext(this);

  @override
  Future<T> execute(covariant RefusingContext ctx) => _body(ctx);
}

/// The context of [RefusingParentJob].
final class RefusingContext extends JobContextBase {
  RefusingContext(super.owner);

  @override
  Cancelled? beforeChildStart(JobBase<Object?> child) => Cancelled.by(
        reason: const CancelReason('rules'),
        started: false,
        description: 'not now',
        // A fresh instance, never a canonicalized constant: the parent
        // keys its Expando by the outcome itself.
        stackTrace: StackTrace.current,
      );
}

/// A job whose context cancels the job itself and still lets the child in.
///
/// Stands in for a rule of a domain that says yes and, on the way, gives
/// up on the job it belongs to: `canStart` in `solo` may call `cancel()`
/// or `close()` and still answer that the child may start.
final class SelfCancellingRulesJob<T> extends JobBase<T> {
  final Future<T> Function(JobContext ctx) _body;

  SelfCancellingRulesJob(this._body, {super.key});

  /// Starts the body the way an engine of a domain would.
  void launch() => start();

  @override
  JobContextBase createContext() => SelfCancellingContext(this);

  @override
  Future<T> execute(covariant SelfCancellingContext ctx) => _body(ctx);
}

/// The context of [SelfCancellingRulesJob].
final class SelfCancellingContext extends JobContextBase {
  SelfCancellingContext(super.owner);

  @override
  Cancelled? beforeChildStart(JobBase<Object?> child) {
    job.cancel().ignore();
    return null;
  }
}

/// A job of the core whose context refuses to be built.
///
/// Stands in for an engine of a domain whose [JobBase.createContext]
/// throws: the child never starts, and the parent must not wait for it.
final class UnstartableJob<T> extends JobBase<T> {
  UnstartableJob({super.key});

  @override
  JobContextBase createContext() => throw StateError('no context');

  @override
  Future<T> execute(covariant ProbeContext ctx) async =>
      throw StateError('never runs');
}

/// A job whose context throws when a child asks to start.
///
/// Stands in for a rule of a domain — `canStart` in `solo` — that throws
/// instead of turning the child away.
final class ThrowingRulesJob<T> extends JobBase<T> {
  final Future<T> Function(JobContext ctx) _body;

  ThrowingRulesJob(this._body, {super.key});

  /// Starts the body the way an engine of a domain would.
  void launch() => start();

  @override
  JobContextBase createContext() => ThrowingRulesContext(this);

  @override
  Future<T> execute(covariant ThrowingRulesContext ctx) => _body(ctx);
}

/// The context of [ThrowingRulesJob].
final class ThrowingRulesContext extends JobContextBase {
  ThrowingRulesContext(super.owner);

  @override
  Cancelled? beforeChildStart(JobBase<Object?> child) =>
      throw StateError('rule failed');
}

/// A job whose `finished` hook throws, the way an engine of a domain can.
final class FailingHookJob<T> extends JobBase<T> {
  final Future<T> Function(JobContext ctx) _body;

  FailingHookJob(this._body, {super.key, super.observer});

  /// Starts the body the way an engine of a domain would.
  void launch() => start();

  @override
  void finished() => throw StateError('hook failed');

  @override
  JobContextBase createContext() => ProbeContext(this);

  @override
  Future<T> execute(covariant ProbeContext ctx) => _body(ctx);
}

/// A job whose context cancels it the way the rules of a domain do.
///
/// The rules cancel through a cancellation nobody may refuse: neither a
/// job created with `cancellable: false` nor an uncancellable section.
final class RulesJob<T> extends JobBase<T> {
  final Future<T> Function(RulesContext ctx) _body;

  RulesJob(this._body, {super.key, super.cancellable});

  /// Starts the body the way an engine of a domain would.
  void launch() => start();

  @override
  JobContextBase createContext() => RulesContext(this);

  @override
  Future<T> execute(covariant RulesContext ctx) => _body(ctx);
}

/// The context of [RulesJob].
final class RulesContext extends JobContextBase {
  RulesContext(super.owner);

  /// Cancels the job the way a rule of a domain does.
  void breakRule(String description) => cancelOwnJob(
        Cancelled.by(
          reason: const CancelReason('rules'),
          started: true,
          description: description,
          stackTrace: StackTrace.current,
        ),
      );
}
