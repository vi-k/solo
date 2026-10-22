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

/// A listener of the end of [job] that captures a payload of its own.
WeakReference<Payload> captureInListener(Job<int> job) {
  final payload = Payload();
  job.whenFinished((_) => payload.bytes.length);
  return WeakReference(payload);
}

/// Like [captureInListener], through [kind], and the remover comes back with
/// the capture.
(void Function(), WeakReference<Payload>) captureWithRemover(
  Job<int> job,
  String kind,
) {
  final payload = Payload();
  final remove = kind == 'whenFinished'
      ? job.whenFinished((_) => payload.bytes.length)
      : job.whenCancelled((_) => payload.bytes.length);
  return (remove, WeakReference(payload));
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

/// A job of the core whose body ends it by hand in its start.
///
/// Made in a frame of its own: a probe keeps its body, and the closures of one
/// frame share what they capture, so a body made next to the payload would hold
/// it.
ProbeJob<Object?> endsItselfInItsStart() {
  late final ProbeJob<Object?> job;
  return job = ProbeJob<Object?>((ctx) async {
    job.drop(const Done(1));
    return 2;
  });
}

/// Only one branch comes back, and its body ended it by hand in its start,
/// before the group got to it. The value of its sibling is then reachable from
/// it alone, through what the group would leave on a branch that is over
/// already.
(Job<Object?>, WeakReference<Payload>) valueOfASiblingOfOneEndedInItsStart() {
  final payload = Payload();
  final first = endsItselfInItsStart();
  final second = Job.deferred<Object?>((ctx) async => payload);
  Job<void>((ctx) async {
    await ctx.runAll([first, second]);
  }).ignoreFailure();
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

/// A body that fails once the gate opens, after an engine ended the job by
/// hand: the value is the outcome, and the failure is in none. It goes to the
/// answer, and the observer answers for it and keeps nothing.
(ProbeJob<void>, WeakReference<Payload>, Completer<void>) failureAfterAHand() {
  final payload = Payload();
  final gate = Completer<void>();
  // Handed over in a box and not captured: a probe keeps its body.
  final box = [payload];
  final job = ProbeJob<void>(observer: Answering(), (ctx) async {
    await gate.future;
    throw CarryingFailure(box.removeLast());
  })
    ..launch();
  return (job, WeakReference(payload), gate);
}

/// A body that returns once the gate opens, after an engine ended the job by
/// hand with a value of its own: that value is the outcome, and the body's is
/// in none.
(ProbeJob<Object?>, WeakReference<Payload>, Completer<void>) valueAfterAHand() {
  final payload = Payload();
  final gate = Completer<void>();
  // Handed over in a box and not captured: a probe keeps its body.
  final box = [payload];
  final job = ProbeJob<Object?>((ctx) async {
    await gate.future;
    return box.removeLast();
  })
    ..launch();
  return (job, WeakReference(payload), gate);
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

/// Registers a cleanup that holds a payload, from a frame of its own: the
/// body that called this does not hold the payload while it waits.
WeakReference<Payload> holdInACleanup(
  JobContext ctx, {
  bool conditional = false,
}) {
  final payload = Payload();
  void release() => payload.bytes.length;
  conditional ? ctx.onDiscard(release) : ctx.onDispose(release);
  return WeakReference(payload);
}

/// An observer that holds a payload, the way one made for a screen holds
/// what the screen needs.
final class HoldingObserver extends JobObserver {
  final Payload payload;

  HoldingObserver(this.payload);

  @override
  void onFinish(Job<Object?> job) => payload.bytes.length;
}

/// A handle of [source] with an observer that holds a payload, cancelled
/// while [source] still runs.
Future<WeakReference<Payload>> cancelledShared(Job<int> source) async {
  final payload = Payload();
  await source.shared(observer: HoldingObserver(payload)).cancel();
  return WeakReference(payload);
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

  test('a finished job lets go of its whenFinished listeners', () async {
    final job = Job<int>((ctx) async => 1);
    final capture = captureInListener(job);
    await job.done;
    expect(
      await collected(capture),
      isTrue,
      reason: 'a listener runs once; held on, it keeps what it captured for '
          'as long as anyone keeps the handle',
    );
  });

  for (final kind in ['whenFinished', 'whenCancelled']) {
    for (final removed in [false, true]) {
      test(
          'a kept remover of $kind lets go of the listener '
          '${removed ? 'once called' : 'once the job ends'}', () async {
        final job = Job<int>((ctx) async => 1);
        final (remove, capture) = captureWithRemover(job, kind);
        if (removed) remove();
        await job.done;
        expect(
          await collected(capture),
          isTrue,
          reason: 'an owner that keeps its removers until it is disposed '
              'would keep what the listeners captured',
        );
        // Kept alive through the collection.
        remove();
      });
    }
  }

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

  test('a branch ended by hand in its start lets go of its group', () async {
    final (branch, capture) = valueOfASiblingOfOneEndedInItsStart();
    await branch.done;
    expect(branch.outcome, isA<Done<Object?>>());
    expect(
      await collected(capture),
      isTrue,
      reason: 'the branch was over before the group got to it, and nothing '
          'the group leaves on it is let go of by a finish already behind it',
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

  test('a job ended by hand keeps nothing its body failed with after it',
      () async {
    final (job, capture, gate) = failureAfterAHand();
    await Future<void>.delayed(Duration.zero);
    job.drop(const Done(null));
    gate.complete();
    await job.done;
    expect(job.outcome, isA<Done<void>>());
    expect(
      await collected(capture),
      isTrue,
      reason: 'the failure is in no outcome, and the core keeps it only to '
          'not announce it twice',
    );
  });

  test('a job ended by hand keeps nothing its body returned after it',
      () async {
    final (job, capture, gate) = valueAfterAHand();
    await Future<void>.delayed(Duration.zero);
    job.drop(const Done(1));
    gate.complete();
    await job.done;
    expect(
      job.outcome,
      isA<Done<Object?>>().having((d) => d.value, 'value', 1),
    );
    expect(
      await collected(capture),
      isTrue,
      reason: 'the value of the body is in no outcome',
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

  test('a job finished by hand lets go of the cleanups it never ran', () async {
    final gate = Completer<void>();
    late WeakReference<Payload> capture;
    final job = ProbeJob<int>((ctx) async {
      capture = holdInACleanup(ctx);
      await gate.future;
      return 1;
    })
      ..ignoreFailure()
      ..launch();
    await Future<void>.microtask(() {});
    job.drop(const Done(1));
    expect(
      await collected(capture),
      isTrue,
      reason: 'nothing unwinds the stack of a job an engine ended by hand, '
          'and held on, it keeps what each registration captured',
    );
    gate.complete();
  });

  test('a branch ended by hand while it unwinds drops what it put aside',
      () async {
    final gate = Completer<String>();
    late WeakReference<Payload> capture;
    late final ProbeJob<String> branch;
    branch = ProbeJob<String>((ctx) async {
      capture = holdInACleanup(ctx, conditional: true);
      // On top of the stack, so it unwinds first: the conditional one
      // under it is put aside, and the branch waits at the second barrier
      // with an outcome of its own.
      ctx.onDispose(() => branch.drop(const Cancelled('by hand')));
      return 'db';
    });
    final parent = Job<List<String>>(
      (ctx) => ctx.runAll([
        branch,
        Job.deferred<String>((ctx) => ctx.abandonable(() => gate.future)),
      ]),
    )..ignoreFailure();
    await Future<void>.microtask(() {});
    gate.complete('other');
    await parent.done;
    expect(branch.outcome, isA<Cancelled>());
    expect(
      await collected(capture),
      isTrue,
      reason: 'the second pass never runs, and what it would have read is '
          'held for as long as the handle is',
    );
  });

  test(
      'a branch ended by hand at the second barrier lets go of what it '
      'registered there', () async {
    final gate = Completer<void>();
    late JobContext context;
    final branch = ProbeJob<String>((ctx) async {
      context = ctx;
      return 'db';
    });
    final parent = Job<List<String>>(
      (ctx) => ctx.runAll([
        branch,
        Job.deferred<String>((ctx) async {
          // Its first pass waits, so the branch waits at the second barrier.
          ctx.onDispose(() => gate.future);
          return 'other';
        }),
      ]),
    )..ignoreFailure();
    for (var i = 0; i < 20 && !branch.isDisposingNow; i++) {
      await Future<void>.microtask(() {});
    }
    // Legal there: the branch is not over, and the stack is read again.
    final capture = holdInACleanup(context);
    branch.drop(const Cancelled('by hand'));
    gate.complete();
    await parent.done;
    expect(
      await collected(capture),
      isTrue,
      reason: 'the stack is never read again, and what is on it is held for '
          'as long as the handle is',
    );
  });

  test('a cancelled shared handle lets go while its source still runs',
      () async {
    final release = Completer<int>();
    final source = Job<int>((ctx) => ctx.join(() => release.future));
    final capture = await cancelledShared(source);
    expect(source.isFinished, isFalse);
    expect(
      await collected(capture),
      isTrue,
      reason: 'the handle has ended and waits for nothing; held by the '
          'source, every screen that left keeps its observer for as long '
          'as the source runs',
    );
    release.complete(1);
    await source.done;
  });

  // The handle waits for its source in its own zone, and a zone can put a
  // closure of its own around what it is given to wait with. The three
  // below are the zones a handle is made in outside a test: one of tooling
  // that wraps every callback, as `Chain.capture` of `stack_trace` does,
  // one of `runZonedGuarded`, and the one of unattended work.
  test(
      'a cancelled shared handle lets go under a zone that wraps every '
      'callback', () async {
    final release = Completer<int>();
    final source = Job<int>((ctx) => ctx.join(() => release.future));
    final capture = await runZoned(
      () => cancelledShared(source),
      zoneSpecification: wrappingEveryCallback(),
    );
    expect(source.isFinished, isFalse);
    expect(
      await collected(capture),
      isTrue,
      reason: 'the wrapper holds what it was given to wait with, and that '
          'must not be the handle',
    );
    release.complete(1);
    await source.done;
  });

  test('a cancelled shared handle lets go in a guarded zone', () async {
    final release = Completer<int>();
    final source = Job<int>((ctx) => ctx.join(() => release.future));
    final caught = <Object>[];
    final capture = await runZonedGuarded(
      () => cancelledShared(source),
      (error, stackTrace) => caught.add(error),
    )!;
    expect(source.isFinished, isFalse);
    expect(
      await collected(capture),
      isTrue,
      reason: 'a guarded zone is where an app runs; the handle made there '
          'must let go as it does in the root zone',
    );
    release.complete(1);
    await source.done;
    expect(caught, isEmpty);
  });

  test('a cancelled shared handle made in unattended work lets go', () async {
    final release = Completer<int>();
    final source = Job<int>((ctx) => ctx.join(() => release.future));
    final made = Completer<WeakReference<Payload>>();
    await Job<void>((ctx) async {
      ctx.unattended(() async => made.complete(await cancelledShared(source)));
    }).done;
    final capture = await made.future;
    expect(source.isFinished, isFalse);
    expect(
      await collected(capture),
      isTrue,
      reason: 'the handle waits in the zone of the work it was made in, '
          'and that zone is not one to keep it in either',
    );
    release.complete(1);
    await source.done;
  });
}

/// A zone that puts a closure of its own around every callback it
/// registers, the way tooling that records where a callback came from
/// does.
ZoneSpecification wrappingEveryCallback() => ZoneSpecification(
      registerCallback: <R>(self, parent, zone, f) =>
          parent.registerCallback(zone, () => f()),
      registerUnaryCallback: <R, T>(self, parent, zone, f) =>
          parent.registerUnaryCallback(zone, (arg) => f(arg)),
      registerBinaryCallback: <R, T1, T2>(self, parent, zone, f) =>
          parent.registerBinaryCallback(
        zone,
        (arg1, arg2) => f(arg1, arg2),
      ),
    );
