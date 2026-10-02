// The first attempts of `doc/extending.md`, verbatim: the queue whose
// jobs leave every cancellation to the core, and the rule that replaces
// the checkpoint of the core. They hold classes of the same names as the
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

  // The first attempt: the analyzer points at it, and that is the page's
  // own point.
  @override
  // ignore: must_call_super
  void check() {
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
  final first = MyJob<void>(key: 'first', (ctx) => ctx.wait(upload));
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

/// A job cancelled while `join` waits, which then asks three more members.
void cancelledMidway(List<String> seen) {
  final job = MyJob<void>((ctx) async {
    await ctx.join(work);
    try {
      final value = await ctx.uncancellable(() {
        seen.add('the step began');
        return 2;
      });
      seen.add('uncancellable: $value');
      await ctx.wait(work);
    } on Cancelled catch (error) {
      seen.add('wait: $error');
    }
    try {
      await ctx.run(Job.deferred<int>((child) async => 4));
    } on Cancelled catch (error) {
      seen.add('run: $error');
    }
  })
    .._launch()
    ..ignore();
  Timer(const Duration(milliseconds: 5), () => unawaited(job.cancel()));
}
