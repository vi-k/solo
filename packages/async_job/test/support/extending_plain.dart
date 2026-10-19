// The job of `doc/extending.md` as its first part shows it, verbatim:
// before the queue and before the rule, which give its classes other
// members, so it lives in a library of its own.
import 'package:async_job/engine.dart';

final class MyJob<T> extends JobBase<T> implements ChildJob<T> {
  // Dropped once the job is over, as the core drops its own: the body
  // holds everything it captured, and a job is held to read its outcome
  // long after.
  Future<T> Function(MyContext ctx)? _body;

  MyJob(
    Future<T> Function(MyContext ctx) body, {
    super.key,
    super.observer,
    super.cancellable,
  }) : _body = body;

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<T> execute(covariant MyContext ctx) => _body!(ctx);

  @override
  void finished() => _body = null;

  // `start` and `untilFinished` are protected: the rest of the engine calls
  // them through these wrappers, private to its library. The queue starts
  // a job later, from a zone of its own, so `_launch` starts it in the zone
  // it was created in.
  void _launch() => creationZone.run(start);

  Future<void> get _untilFinished => untilFinished;
}

final class MyContext extends JobContextBase {
  MyContext(super.owner);
}

/// Starts [job] the way the engine does and waits for it the way the
/// engine does, without looking at its outcome.
Future<void> launchAndWait(MyJob<Object?> job) {
  job._launch();
  return job._untilFinished;
}
