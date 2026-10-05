// The first attempts of `doc/extending.md`, verbatim: the queue whose
// jobs leave every cancellation to the core, and the rule that throws an
// error of the engine's own. They hold classes of the same names as the
// answers, so they live in a library of their own.
import 'dart:async';

import 'package:async_job/engine.dart';

import 'extending_stubs.dart';

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

  @override
  void check() {
    super.check();
    if (!account.signedIn) throw const SignedOut();
  }
}

final class MyQueue {
  final _waiting = <MyJob<Object?>>[];

  void add(MyJob<Object?> job) => _waiting.add(job);

  Future<void> run() async {
    while (_waiting.isNotEmpty) {
      final job = _waiting.removeAt(0);
      if (job.isFinished) continue;
      job._launch();
      await job._whenDone;
    }
  }
}

Future<void> runQueue() async {
  final first = MyJob<void>(key: 'first', (ctx) => ctx.abandonable(upload));
  final second = MyJob<void>(
    key: 'second',
    cancellable: false,
    (_) async => print('second runs'),
  );
  final third = MyJob<void>(key: 'third', (_) async => print('third runs'));
  final queue = MyQueue()
    ..add(first)
    ..add(second)
    ..add(third);
  final running = queue.run();
  await second.cancel();
  await running;
  print('second: ${await second.done}');
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
    await ctx.abandonable(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
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
