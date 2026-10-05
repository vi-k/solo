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

import 'support/probe_job.dart';
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

/// A job an engine finishes by hand while its body waits on a `ctx.abandonable`
/// call that fails, after that, with a record holding a payload. The payload is
/// made inside the action and handed out weakly through [made]: a [ProbeJob]
/// keeps its body function, which must not capture it.
(ProbeJob<int>, Completer<void>, Future<void>) failureAfterAHandFinish(
  List<WeakReference<Payload>> made,
) {
  final gate = Completer<void>();
  final bodyDone = Completer<void>();
  return (
    ProbeJob<int>((ctx) async {
      try {
        await ctx.abandonable<void>(() async {
          await gate.future;
          final payload = Payload();
          made.add(WeakReference(payload));
          Error.throwWithStackTrace((payload,), StackTrace.current);
        });
      } on Object catch (_) {
        // Handled: the body is over.
      }
      bodyDone.complete();
      return 1;
    }),
    gate,
    bodyDone.future,
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

  // An error an `Expando` can hold and a record, which it cannot.
  final failures = <String, Object Function(Payload payload)>{
    'an exception': CarryingFailure.new,
    'a record': (payload) => (payload,),
  };
  test('a job finished by hand keeps nothing its body failed with after',
      () async {
    final made = <WeakReference<Payload>>[];
    final (job, gate, bodyDone) = failureAfterAHandFinish(made);
    job.launch();
    await Future<void>.delayed(Duration.zero);
    job.drop(const Done(0));
    gate.complete();
    await bodyDone;
    expect(
      await collected(made.single),
      isTrue,
      reason: 'the job is over, and nothing will read the order again',
    );
  });

  test('a finished job keeps nothing its unattended work failed with',
      () async {
    final (job, capture, gate, workDone) = failureOfWorkAfterTheJob();
    await job.done;
    gate.complete();
    await workDone;
    expect(
      await collected(capture),
      isTrue,
      reason: 'nothing reads the order once the body has ended, so a failure '
          'arriving after it is not noted at all',
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
        reason: 'the core notes a failure on its way to the body, to tell '
            'the order against a cancellation; once the job is over there '
            'is no order left to tell',
      );
    });
  }
}
