import 'package:solo/solo.dart';

/// A job of the core alone: no state, no queue, no rules.
///
/// Stands in for another engine built on [JobBase] — the kind `solo` must
/// not adopt from, and must not hand its own jobs to.
final class ForeignJob<T> extends JobBase<T> {
  final Future<T> Function(JobContext ctx) _body;

  ForeignJob(this._body, {super.key, super.describe});

  /// How many children are still being waited for.
  int get childCount => children.length;

  /// Starts the body the way an engine of a domain would.
  void launch() => start();

  @override
  JobContextBase createContext() => ForeignContext(this);

  @override
  Future<T> execute(covariant ForeignContext ctx) => _body(ctx);
}

/// The context that goes with [ForeignJob].
final class ForeignContext extends JobContextBase {
  ForeignContext(super.owner);
}
