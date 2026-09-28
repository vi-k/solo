// The second attempt of the rule in `doc/extending.md`, verbatim: it asks
// the checkpoint of the core and throws a cancellation of its own. It
// holds classes of the same names as the answer, so it lives in a library
// of its own.
import 'package:async_job/engine.dart';

import 'extending_stubs.dart';

final class MyJob<T> extends JobBase<T> {
  MyJob(this._body, {super.key, super.observer});

  final Future<T> Function(MyContext ctx) _body;

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<T> execute(covariant MyContext ctx) => _body(ctx);

  // `start` and `whenDone` are protected: the engine opens doors of its
  // own to them, private to the library it lives in.
  void _launch() => start();

  Future<void> get _whenDone => whenDone;
}

final class MyContext extends JobContextBase {
  MyContext(super.owner);

  @override
  void check() {
    super.check();
    if (!account.signedIn) {
      throw Cancelled.by(
        reason: const SignedOutReason(),
        started: true,
        stackTrace: StackTrace.current,
      );
    }
  }
}

void runDownload(String act) {
  final job = MyJob<void>(observer: printer, (ctx) async {
    ctx.onCancel(() => print('close the connection'));
    final rows = await ctx.join(download);
    print('downloaded $rows rows');
    await ctx.join(() => save(rows));
    print('saved');
  })
    .._launch();
  userDoes(act, job);
}

/// A job with a child, signed out of while both run; returns the child.
Job<void> signOutWithChild(List<String> seen) {
  final child = Job.deferred<void>((ctx) async {
    ctx.onCancel(() => seen.add('child told to stop'));
    await ctx
        .wait(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  });
  final job = MyJob<void>((ctx) async {
    ctx.onCancel(() => seen.add('parent told to stop'));
    ctx.run(child).ignore();
    await ctx.join(download);
  })
    .._launch();
  job.done.then((outcome) => seen.add('outcome: $outcome')).ignore();
  job._whenDone.ignore();
  return child;
}
