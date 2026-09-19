// What a finished job of a controller lets go of.
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
    solo.run<int, int>((ctx) async => payload.bytes.length),
    WeakReference(payload),
  );
}

/// A payload nothing reaches but the state handlers of one job.
(SoloJob<void>, WeakReference<Payload>) captureInHandlers(Counter solo) {
  final payload = Payload();
  return (
    solo.run<int, void>(
      (ctx) => ctx.wait(() => Future<void>.delayed(Duration.zero)),
      onCancel: (state, cancelled) => payload.bytes.length,
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
  solo.run<int, Object?>((ctx) async {
    await ctx.run(child);

    return payload;
  }).ignore();

  return (child, WeakReference(payload));
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

  test('the rules outlive the job, because a leaked context reads them',
      () async {
    final solo = Counter();
    final kept = <String>[];
    late final SoloContext<int, int> leaked;
    final job = solo.run<int, void>(
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
