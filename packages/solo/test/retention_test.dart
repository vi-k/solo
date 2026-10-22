// What a job of a controller lets go of once it is over, and what it does
// not hold before that.
//
// The core answers the same question in
// `packages/async_job/test/retention_test.dart`, and a job of a controller
// is a job of its own: it brought a body, the handlers of its state and a
// link to the job that ran it, and none of the three is of any use once
// there is an outcome.
//
// No `FakeAsync` here, and not by accident: these tests ask the real
// collector a question no fake clock can answer. There is no time in them
// either -- no timer, no delay, only microtasks -- so the rule the rest of
// the suite follows is not being bent, it does not apply.
@Timeout(Duration(seconds: 30))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/reachability.dart';
import 'support/test_solo.dart';

/// What a body captures. Big enough that holding it is worth noticing.
final class Payload {
  final List<int> bytes = List<int>.filled(1024, 7);
}

final class Counter extends Solo<int> with OpenSolo<int> {
  Counter() : super(0);

  void set(int state) => externalSetState(state);
}

/// Made in a frame of its own: a closure captures the variable, not the
/// value, so a payload reassigned later in the same scope would go
/// unreachable for a reason that has nothing to do with the job.
(SoloJob<int>, WeakReference<Payload>) captureInBody(Counter solo) {
  final payload = Payload();
  return (
    solo.enqueue<int, int>((ctx) async => payload.bytes.length),
    WeakReference(payload),
  );
}

/// A payload nothing reaches but the state handlers of one job.
(SoloJob<void>, WeakReference<Payload>) captureInHandlers(Counter solo) {
  final payload = Payload();
  return (
    solo.enqueue<int, void>(
      (ctx) => ctx.abandonable(() => Future<void>.delayed(Duration.zero)),
      ifCancelled: (state, cancelled) => payload.bytes.length,
    ),
    WeakReference(payload),
  );
}

/// Only the child comes back. The value of the parent is then reachable
/// from it alone, through the link a job of a controller keeps to the job
/// that ran it.
///
/// The value and not something the body captured: a body is let go of too,
/// so a capture would be collected even with the link still there, and the
/// test would prove the wrong half.
(SoloJob<int>, WeakReference<Payload>) valueOfAParent(Counter solo) {
  final payload = Payload();
  final child = solo.job<int, int>((ctx) async => 1);
  solo.enqueue<int, Object?>((ctx) async {
    await ctx.run(child);

    return payload;
  }).ignoreFailure();

  return (child, WeakReference(payload));
}

/// Only the job [make] runs inside the unattended work of another comes
/// back, and it comes back once the job that started the work is over.
/// The value of that job is then reachable from it alone, through the zone
/// the job was made in: the fork of the work, which carries the job that
/// started it.
Future<(SoloJob<T>, WeakReference<Payload>)> madeInUnattendedWork<T>(
  Counter solo,
  SoloJob<T> Function() make,
) async {
  final payload = Payload();
  final made = Completer<SoloJob<T>>();
  final starter = solo.enqueue<int, Object?>((ctx) async {
    ctx.unattended(() => made.complete(make()));

    return payload;
  })
    ..ignoreFailure();
  final job = await made.future;
  await starter.done;

  return (job, WeakReference(payload));
}

void main() {
  test('a finished job lets go of its body', () async {
    final solo = Counter();
    final (job, capture) = captureInBody(solo);
    await job.done;

    expect(job.outcome, isA<Done<int>>());
    expect(
      await collected(capture),
      isTrue,
      reason: 'the body ran once and will not run again; held on, it keeps '
          'everything it captured for as long as anyone keeps the handle',
    );

    await solo.close();
  });

  test('a finished job lets go of its state handlers', () async {
    final solo = Counter();
    final (job, capture) = captureInHandlers(solo);
    await job.cancel();

    expect(job.outcome, isA<Cancelled>());
    expect(
      await collected(capture),
      isTrue,
      reason: 'a handler of a job with an outcome has had its turn',
    );

    await solo.close();
  });

  test('a finished child lets go of the job that ran it', () async {
    final solo = Counter();
    final (child, capture) = valueOfAParent(solo);
    await child.done;
    // The parent finishes after the child it was waiting for.
    await Future<void>.delayed(Duration.zero);

    expect(child.outcome, isA<Done<int>>());
    expect(
      await collected(capture),
      isTrue,
      reason: 'the parent chain leads to jobs that are over, and one handle '
          'in a field would keep the whole tree it came out of',
    );

    await solo.close();
  });

  test('a job made in unattended work lets go of the job that started it',
      () async {
    final solo = Counter();
    final (made, capture) = await madeInUnattendedWork(
      solo,
      () => solo.enqueue<int, int>((_) async => 1),
    );
    await made.done;

    expect(made.outcome, isA<Done<int>>());
    expect(
      await collected(capture),
      isTrue,
      reason: 'the zone current where the job was made is the fork of the '
          'work, and a handle that held it would hold the job that started '
          'the work for as long as anyone keeps the handle',
    );
    // Read after the check, so the handle is held through it by the
    // language and not by how the VM keeps a suspended frame.
    expect(made.isFinished, isTrue);

    await solo.close();
  });

  test(
      'a job made in unattended work waits in the queue without holding '
      'the job that started it', () async {
    final solo = Counter();
    final other = Counter();
    final gate = Completer<void>();
    final ahead = other.enqueue<int, void>((_) => gate.future);
    final (made, capture) = await madeInUnattendedWork(
      solo,
      () => other.enqueue<int, int>((_) async => 1),
    );

    expect(made.isQueued, isTrue);
    expect(
      await collected(capture),
      isTrue,
      reason: 'the queue starts a job in the zone it was made in, and a job '
          'made in the work starts where the work was started from; kept '
          'for the start, the fork would hold the job that started the '
          'work for as long as this one waits',
    );
    expect(made.isQueued, isTrue);

    gate.complete();
    await ahead.done;
    await made.done;
    await solo.close();
    await other.close();
  });

  test(
      'a job made in unattended work runs without holding the job that '
      'started it', () async {
    final solo = Counter();
    final other = Counter();
    final gate = Completer<void>();
    final (made, capture) = await madeInUnattendedWork(
      solo,
      () => other.enqueue<int, void>((_) => gate.future),
    );

    expect(made.isRunning, isTrue);
    expect(
      await collected(capture),
      isTrue,
      reason: 'a running job holds nothing of the work it was made in',
    );
    expect(made.isRunning, isTrue);

    gate.complete();
    await made.done;
    await solo.close();
    await other.close();
  });

  test(
      'a job made in unattended work and not yet added holds nothing of the '
      'job that started it', () async {
    final solo = Counter();
    final other = Counter();
    final (made, capture) = await madeInUnattendedWork(
      solo,
      () => other.job<int, int>((_) async => 1),
    );

    expect(made.isQueued, isFalse);
    expect(
      await collected(capture),
      isTrue,
      reason: 'a job made by `job` may wait for `enqueueJob` as long as anyone '
          'keeps the handle, and nothing lets go of what it holds until it '
          'is over',
    );
    expect(made.isFinished, isFalse);

    await solo.close();
    await other.close();
  });

  test('the rules outlive the job, because a leaked context reads them',
      () async {
    final solo = Counter();
    final kept = <String>[];
    late final SoloContext<int, int> leaked;
    final job = solo.enqueue<int, void>(
      keepWhile: (state) => state < 5,
      (ctx) async => leaked = ctx,
    );
    await job.done;
    solo.set(9);

    try {
      leaked.state;
    } on Cancelled catch (cancelled) {
      kept.add(cancelled.description ?? '');
    }

    expect(
      kept,
      ['keepWhile'],
      reason: 'the cancellation a leaked read builds is the whole diagnosis '
          'it has to offer, and it is built out of the rule',
    );

    await solo.close();
  });
}
