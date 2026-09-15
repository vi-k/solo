// What a finished job lets go of.
//
// No `FakeAsync` here, and not by accident: these tests ask the real
// collector a question no fake clock can answer. There is no time in them
// either -- no timer, no delay, only microtasks -- so the rule the rest of
// the suite follows is not being bent, it does not apply.
@Timeout(Duration(seconds: 30))
library;

import 'package:async_job/async_job.dart';
import 'package:test/test.dart';

import 'support/reachability.dart';

/// What a body captures. Big enough that holding it is worth noticing.
final class Payload {
  final List<int> bytes = List<int>.filled(1024, 7);
}

/// Made in a frame of its own: a closure captures the variable, not the
/// value, so a payload reassigned later in the same scope would go
/// unreachable for a reason that has nothing to do with the job.
(Job<int>, WeakReference<Payload>) captureInBody() {
  final payload = Payload();
  return (
    Job<int>((ctx) async => payload.bytes.length),
    WeakReference(payload),
  );
}

/// Only the child comes back. The value of the parent is then reachable
/// from it alone, through the link a child keeps to its parent.
///
/// The value and not something the body captured: a body is let go of too,
/// so a capture would be collected even with the link still there, and the
/// test would prove the wrong half.
(Job<int>, WeakReference<Payload>) valueOfAParent() {
  final payload = Payload();
  final child = Job.deferred<int>((ctx) async => 1);
  Job<Object?>((ctx) async {
    await ctx.run(child);
    return payload;
  }).ignore();
  return (child, WeakReference(payload));
}

/// Only one branch comes back. The value of its sibling is then reachable
/// from it alone, through what the group left on the branch.
(Job<Object?>, WeakReference<Payload>) valueOfASibling() {
  final payload = Payload();
  final first = Job.deferred<Object?>((ctx) async => 1);
  final second = Job.deferred<Object?>((ctx) async => payload);
  Job<void>((ctx) async {
    await ctx.runAll([first, second]);
  }).ignore();
  return (first, WeakReference(payload));
}

void main() {
  test('a finished job lets go of its body', () async {
    final (job, capture) = captureInBody();
    await job.done;
    expect(job.outcome, isA<Done<int>>());
    expect(
      await collected(capture),
      isTrue,
      reason: 'the body ran once and will not run again; held on, it keeps '
          'everything it captured for as long as anyone keeps the handle',
    );
  });

  test('a finished child lets go of its parent', () async {
    final (child, capture) = valueOfAParent();
    await child.done;
    expect(child.outcome, isA<Done<int>>());
    expect(
      await collected(capture),
      isTrue,
      reason: 'a handle kept for its outcome would otherwise drag the whole '
          'chain it came out of, up to the root',
    );
  });

  test('a finished branch lets go of its group', () async {
    final (branch, capture) = valueOfASibling();
    await branch.done;
    expect(branch.outcome, isA<Done<Object?>>());
    expect(
      await collected(capture),
      isTrue,
      reason: 'the group has taken its verdict; one branch handle must not '
          'hold the coordinator and every sibling in it',
    );
  });
}
