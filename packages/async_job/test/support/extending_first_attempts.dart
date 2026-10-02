// The first attempts of `doc/extending.md`, verbatim: the queue that starts
// its jobs and nothing else, and the rule that replaces the checkpoint of
// the core. They hold classes of the same names as the answers, so they
// live in a library of their own.
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
      final job = _waiting.removeAt(0).._launch();
      await job._whenDone;
    }
  }
}

Future<void> runQueue() async {
  final first = MyJob<void>(key: 'first', (ctx) => ctx.wait(upload));
  final second = MyJob<void>(key: 'second', (_) async => print('second runs'));
  final third = MyJob<void>(key: 'third', (_) async => print('third runs'));
  final queue = MyQueue()
    ..add(first)
    ..add(second)
    ..add(third);
  final running = queue.run();
  await second.cancel();
  print('second: ${await second.done}');
  try {
    await running;
    print('the queue is empty');
    // ignore: avoid_catching_errors
  } on StateError catch (error) {
    print('the queue stopped: $error');
  }
}

/// The first attempt's job with one thing added: it takes itself out of
/// the queue in `finished()`. Its `cancelWith` is the core's own.
final class LeavingJob<T> extends MyJob<T> {
  final MyQueue _queue;

  LeavingJob(this._queue, super.body, {super.key}) {
    _queue.add(this);
  }

  @override
  void finished() => _queue._waiting.remove(this);
}

/// The run of the page through the queue of the first attempt, with jobs
/// that leave it in `finished()`.
Future<void> runQueueLeavingInFinished() async {
  final queue = MyQueue();
  LeavingJob<void>(queue, key: 'first', (ctx) => ctx.wait(upload));
  final second =
      LeavingJob<void>(queue, key: 'second', (_) async => print('second runs'));
  LeavingJob<void>(queue, key: 'third', (_) async => print('third runs'));
  final running = queue.run();
  await second.cancel();
  print('second: ${await second.done}');
  try {
    await running;
    print('the queue is empty');
    // ignore: avoid_catching_errors
  } on StateError catch (error) {
    print('the queue stopped: $error');
  }
}

/// The queue of the page again, handing back the third job, the one
/// behind the cancelled one.
Job<void> queueOfThree() {
  final second = MyJob<void>(key: 'second', (ctx) => ctx.wait(upload));
  final third = MyJob<void>(key: 'third', (ctx) => ctx.wait(upload));
  final queue = MyQueue()
    ..add(MyJob<void>(key: 'first', (ctx) => ctx.wait(upload)))
    ..add(second)
    ..add(third);
  queue.run().ignore();
  second.cancel().ignore();
  return third;
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
