import 'package:jobs/jobs.dart';

/// A job of the core with its protected surface opened for tests.
final class ProbeJob<T> extends JobBase<T> {
  final Future<T> Function(JobContext ctx) _body;

  ProbeJob(this._body, {super.key, super.observer});

  /// How many children are still being waited for.
  int get childCount => children.length;

  /// Starts the body the way an engine of a domain would.
  void launch() => start();

  @override
  JobContextBase createContext() => ProbeContext(this);

  @override
  Future<T> execute(covariant ProbeContext ctx) => _body(ctx);
}

/// The context that goes with [ProbeJob].
final class ProbeContext extends JobContextBase {
  ProbeContext(super.owner);
}
