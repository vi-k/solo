import 'package:jobs/jobs.dart';

/// A job of the core with its protected surface opened for tests.
final class ProbeJob<T> extends JobBase<T> {
  final Future<T> Function(JobContext ctx) _body;

  ProbeJob(this._body, {super.key, super.observer});

  /// How many children are still being waited for.
  int get childCount => children.length;

  /// Starts the body the way an engine of a domain would.
  void launch() => start();

  /// Ends the job from the outside, the way an engine of a domain would.
  void drop(Outcome<T> outcome) => finish(outcome);

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
