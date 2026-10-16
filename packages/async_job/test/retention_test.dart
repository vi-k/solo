// What a finished job lets go of.
//
// No `FakeAsync` here, and not by accident: these tests ask the real
// collector a question no fake clock can answer. There is no time in them
// either -- no timer, no delay, only microtasks -- so the rule the rest of
// the suite follows is not being bent, it does not apply.
@Timeout(Duration(seconds: 30))
library;

import 'dart:async';

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
  }).ignoreFailure();
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
  }).ignoreFailure();
  return (first, WeakReference(payload));
}

/// Only one of two children comes back, the one that ends first. The value
/// of the other is then reachable from it alone, through the neighbours a
/// child keeps while its parent waits for it: the one adopted before it and
/// the one adopted after.
(Job<Object?>, WeakReference<Payload>) valueOfANeighbour({
  required bool adoptedFirst,
}) {
  final payload = Payload();
  final gate = Completer<void>();
  final kept = Job.deferred<Object?>((ctx) async => 1);
  final other = Job.deferred<Object?>((ctx) async {
    await ctx.abandonable(() => gate.future);
    return payload;
  });
  Job<void>((ctx) async {
    final (first, second) = adoptedFirst ? (kept, other) : (other, kept);
    final values = [ctx.run(first), ctx.run(second)];
    await kept.done;
    gate.complete();
    await values.wait;
  }).ignoreFailure();
  return (kept, WeakReference(payload));
}

/// Only a job made inside the unattended work of another comes back. The
/// value of the job that started the work is then reachable from it alone,
/// through the fork the work runs in: the fork carries that job.
Future<(Job<int>, WeakReference<Payload>)> madeInUnattendedWork() async {
  final payload = Payload();
  final made = Completer<Job<int>>();
  Job<Object?>((ctx) async {
    ctx.unattended(() => made.complete(Job<int>((_) async => 1)));
    return payload;
  }).ignoreFailure();
  return (await made.future, WeakReference(payload));
}

/// A failure that holds what it carries.
final class CarryingFailure implements Exception {
  final Payload payload;
  CarryingFailure(this.payload);

  @override
  String toString() => 'CarryingFailure(${payload.bytes.length} bytes)';
}

/// A body that catches the failure of an operation it waited for and goes
/// on. The payload is then reachable only through that failure, made of it
/// by [failure].
(Job<int>, WeakReference<Payload>) failureTheBodyCaught(
  Object Function(Payload payload) failure,
) {
  final payload = Payload();
  return (
    Job<int>((ctx) async {
      try {
        await ctx.abandonable(() => Future<void>.error(failure(payload)));
      } on Object catch (_) {
        // Handled: the job goes on and ends with a value.
      }
      return 1;
    }),
    WeakReference(payload),
  );
}

/// Answers for every error and keeps none of them.
final class Answering extends JobObserver with JobAnswerer {
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {}
}

/// A body that fails once the gate opens, after a cancellation marked the
/// job: the cancellation is the outcome, and the failure it covers is in
/// none. It goes to the answer, and the observer answers for it and keeps
/// nothing.
(Job<void>, WeakReference<Payload>, Completer<void>)
    failureACancellationCovered() {
  final payload = Payload();
  final gate = Completer<void>();
  return (
    Job<void>(observer: Answering(), (ctx) async {
      await gate.future;
      throw CarryingFailure(payload);
    }),
    WeakReference(payload),
    gate,
  );
}

/// Unattended work whose `ctx.abandonable` fails once the gate opens, with a
/// record that holds the payload; the job itself is over by then.
(Job<int>, WeakReference<Payload>, Completer<void>, Future<void>)
    failureOfWorkAfterTheJob() {
  final payload = Payload();
  final gate = Completer<void>();
  final workDone = Completer<void>();
  return (
    Job<int>((ctx) async {
      ctx.unattended(() async {
        try {
          await ctx.abandonable<void>(() async {
            await gate.future;
            Error.throwWithStackTrace((payload,), StackTrace.current);
          });
        } on Object catch (_) {
          // Handled: the work is over.
        }
        workDone.complete();
      });
      return 1;
    }),
    WeakReference(payload),
    gate,
    workDone.future,
  );
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

  for (final (adoptedFirst, neighbour) in [
    (true, 'after'),
    (false, 'before'),
  ]) {
    test('a finished child lets go of the child adopted $neighbour it',
        () async {
      final (child, capture) = valueOfANeighbour(adoptedFirst: adoptedFirst);
      await child.done;
      expect(child.outcome, isA<Done<Object?>>());
      expect(
        await collected(capture),
        isTrue,
        reason: 'the parent stopped waiting for it; a handle kept for its '
            'outcome must not hold the children it stood between',
      );
    });
  }

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

  test('a job made in unattended work lets go of the job that started it',
      () async {
    final (made, capture) = await madeInUnattendedWork();
    await made.done;
    expect(made.outcome, isA<Done<int>>());
    expect(
      await collected(capture),
      isTrue,
      reason: 'the job is not the work and keeps nothing of it; a handle '
          'kept for its outcome would otherwise hold the job that started '
          'the work, through the zone it was made in',
    );
    // Read after the check, so the handle is held through it by the
    // language and not by how the VM keeps a suspended frame.
    expect(made.isFinished, isTrue);
  });

  // An error an `Expando` can hold and a record, which it cannot.
  final failures = <String, Object Function(Payload payload)>{
    'an exception': CarryingFailure.new,
    'a record': (payload) => (payload,),
  };
  test('a finished job keeps nothing its unattended work failed with',
      () async {
    final (job, capture, gate, workDone) = failureOfWorkAfterTheJob();
    await job.done;
    gate.complete();
    await workDone;
    expect(
      await collected(capture),
      isTrue,
      reason: 'the work caught the failure, and nothing of the job holds it',
    );
  });

  test('a cancelled job keeps nothing its body failed with after the mark',
      () async {
    final (job, capture, gate) = failureACancellationCovered();
    await Future<void>.delayed(Duration.zero);
    job.cancel().ignore();
    gate.complete();
    await job.done;
    expect(job.outcome, isA<Cancelled>());
    expect(
      await collected(capture),
      isTrue,
      reason: 'the failure is in no outcome, and the core keeps it only to '
          'not announce it twice',
    );
  });

  for (final MapEntry(key: kind, value: failure) in failures.entries) {
    test('a finished job lets go of $kind it caught', () async {
      final (job, capture) = failureTheBodyCaught(failure);
      await job.done;
      expect(job.outcome, isA<Done<int>>());
      expect(
        await collected(capture),
        isTrue,
        reason: 'the body caught the failure, and nothing of the job holds '
            'it',
      );
    });
  }
}
