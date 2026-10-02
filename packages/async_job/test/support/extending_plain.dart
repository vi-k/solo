// The job of `doc/extending.md` as its first part shows it, verbatim:
// before the queue and before the rule, which give its classes other
// members, so it lives in a library of its own.
import 'package:async_job/engine.dart';

final class MyJob<T> extends JobBase<T> {
  final Future<T> Function(MyContext ctx) _body;

  MyJob(this._body, {super.key, super.observer, super.cancellable});

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<T> execute(covariant MyContext ctx) => _body(ctx);

  // `start` and `whenDone` are protected: the rest of the engine calls
  // them through these wrappers, private to its library.
  void _launch() => start();

  Future<void> get _whenDone => whenDone;
}

final class MyContext extends JobContextBase {
  MyContext(super.owner);
}

/// Starts [job] the way the engine does and waits for it the way the
/// engine does, without looking at its outcome.
Future<void> launchAndWait(MyJob<Object?> job) {
  job._launch();
  return job._whenDone;
}
