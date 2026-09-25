import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:test/test.dart';

import 'support/cancel_reason.dart';
import 'support/delay.dart';
import 'support/error_observer.dart';
import 'support/probe_job.dart';

void main() {
  // Deep enough that no stack survives the cascade, with room to spare on
  // a machine whose frames are smaller. The point of the run is not the
  // depth itself but what the kernel leaves behind when it runs out: on
  // the machine these tests were written on the cascade marks about 3100
  // levels, and a run that reached the bottom instead would fail on the
  // first expectation rather than pass quietly.
  const depth = 50000;
  // The observers that collect a report answer for it too: the subject is
  // what a cascade out of stack reports, and how many times. Where the
  // report goes after the observer is the business of the test right
  // after the first one that reports.

  test('a cascade out of stack still tells what it marked to stop', () async {
    final chain = _Chain(depth);
    final root = chain.start();
    await chain.bottom.future;

    Object? thrown;
    try {
      root.cancel().ignore();
    } on Object catch (error) {
      thrown = error;
    }
    expect(
      thrown,
      isA<StackOverflowError>(),
      reason: 'the cascade is recursive, and $depth levels do not fit',
    );

    // The mark goes top-down, so what the cascade reached is a prefix of
    // the chain.
    final marked = chain.marked;
    expect(marked, greaterThan(100));
    expect(
      chain.jobs.take(marked).every((job) => job.isCancelled),
      isTrue,
      reason: 'the marked jobs are the ones nearest the root',
    );

    final silent = chain.silent;
    expect(
      silent,
      isEmpty,
      reason: '$marked jobs were marked and ${silent.length} of them were '
          'never told to stop; first of those: ${silent.take(3)}',
    );
  });

  test('a body giving itself up reports a cascade out of stack', () async {
    final chain = _Chain(depth);
    final errors = <Object>[];
    final root = Job<void>(
      (ctx) async {
        ctx.run(chain.deferred()).ignore();
        await chain.bottom.future;
        // The body gives itself up, the way one does when it catches a
        // cancellation of somebody else: the children go from inside the
        // engine, and there is no caller to hand a failure of that to.
        throw Cancelled.by(
          reason: const TestCancelReason('handler'),
          started: true,
          stackTrace: StackTrace.current,
        );
      },
      observer: ErrorObserver.answering(errors),
    );

    for (var attempt = 0; errors.isEmpty && attempt < 100; attempt++) {
      await delay(1);
    }
    expect(
      errors.single,
      isA<StackOverflowError>(),
      reason: 'the cascade ran out of stack and nobody else could hear it',
    );
    expect(root.isCancelled, isTrue);

    final silent = chain.silent;
    expect(
      silent,
      isEmpty,
      reason: '${chain.marked} jobs were marked and ${silent.length} of '
          'them were never told to stop',
    );
  });

  test('a cascade out of stack goes on to the zone like any error', () async {
    final chain = _Chain(depth);
    final errors = <Object>[];
    final zone = <Object>[];
    runZonedGuarded(
      () => Job<void>(
        (ctx) async {
          ctx.run(chain.deferred()).ignore();
          await chain.bottom.future;
          throw Cancelled.by(
            reason: const TestCancelReason('handler'),
            started: true,
            stackTrace: StackTrace.current,
          );
        },
        observer: ErrorObserver(errors),
      ),
      (error, stackTrace) => zone.add(error),
    );

    for (var attempt = 0; zone.isEmpty && attempt < 100; attempt++) {
      await delay(1);
    }
    // Outside the guarded zone: an `expect` that fails inside it lands in
    // the handler and is counted as a zone error instead of failing.
    expect(errors.single, isA<StackOverflowError>());
    expect(
      zone.single,
      isA<StackOverflowError>(),
      reason: 'an observer that only watches answers for nothing',
    );
  });

  test('a shallow sibling of a deep chain is cancelled all the same', () async {
    final chain = _Chain(depth);
    final never = Completer<void>();
    final ready = Completer<void>();
    var leafTold = false;
    late final Job<void> leaf;

    final root = Job<void>((ctx) async {
      leaf = Job.deferred<void>((ctx) async {
        ctx.onCancel(() => leafTold = true);
        await never.future;
      });
      // The leaf goes first, so the cascade -- which takes the children
      // last started first -- reaches it after the chain, and only if the
      // chain running out of stack did not take the loop with it.
      ctx.run(leaf).ignore();
      await null;
      ctx.run(chain.deferred()).ignore();
      ready.complete();
      await never.future;
    });
    await ready.future;
    await chain.bottom.future;

    Object? thrown;
    try {
      root.cancel().ignore();
    } on Object catch (error) {
      thrown = error;
    }
    expect(thrown, isA<StackOverflowError>());
    expect(leaf.isCancelled, isTrue, reason: 'the sibling is not deep');
    expect(leafTold, isTrue, reason: 'and it was told to stop');
  });

  test('the window closes when the engine ends the job by hand', () async {
    // Three things at once, which is why it is worth a test of its own: a
    // cascade deep enough to run out of stack, an engine of a domain that
    // ends the job from a callback of a child, and a listener registered
    // afterwards with a bug of its own.
    final chain = _Chain(depth);
    final errors = <Object>[];
    final never = Completer<void>();
    final ready = Completer<void>();
    var leafTold = false;
    late final ProbeJob<void> parent;
    parent = ProbeJob<void>(
      (ctx) async {
        final leaf = Job.deferred<void>((ctx) async {
          ctx.onCancel(() {
            leafTold = true;
            parent.drop(
              Cancelled.by(
                reason: const TestCancelReason('rules'),
                started: true,
                stackTrace: StackTrace.current,
              ),
            );
          });
          await never.future;
        });
        ctx.run(leaf).ignore();
        await null;
        ctx.run(chain.deferred()).ignore();
        ready.complete();
        await never.future;
      },
      observer: ErrorObserver.answering(errors),
    );
    parent.launch();
    await ready.future;
    await chain.bottom.future;

    try {
      parent.cancel().ignore();
    } on Object catch (_) {
      // The cascade running out of stack is the premise of the run.
    }
    expect(leafTold, isTrue, reason: 'the sibling was reached');
    expect(parent.isFinished, isTrue, reason: 'the engine ended it');

    // The pass that closes the window is the one this path skips, so the
    // window has to be closed where it is skipped.
    Object? escaped;
    try {
      parent.whenCancelled((_) => _forever(0));
    } on Object catch (error) {
      escaped = error;
    }
    expect(escaped, isNull, reason: 'the bug belongs to the listener');
    expect(errors.last, isA<StackOverflowError>());
  });

  test('the window closes for a body that gave itself up too', () async {
    final chain = _Chain(depth);
    final errors = <Object>[];
    final never = Completer<void>();
    final head = ProbeJob<void>((ctx) async {
      ctx.run(chain.deferred()).ignore();
      await never.future;
    });
    var second = false;
    final root = Job<void>(
      (ctx) async {
        ctx.run(head).ignore();
        await chain.bottom.future;
        throw Cancelled.by(
          reason: const TestCancelReason('handler'),
          started: true,
          stackTrace: StackTrace.current,
        );
      },
      observer: ErrorObserver.answering(errors),
    );
    for (var attempt = 0; errors.isEmpty && attempt < 100; attempt++) {
      await delay(1);
    }
    expect(errors.single, isA<StackOverflowError>());

    // On this path the pass that tells the listeners waits for the
    // children first, so it runs on a stack that is whole again. The
    // engine ending the child by hand is what lets it get there without
    // the depth below the break.
    root
      ..whenCancelled((_) => _forever(0))
      ..whenCancelled((_) => second = true);
    head.drop(
      Cancelled.by(
        reason: const TestCancelReason('rules'),
        started: true,
        stackTrace: StackTrace.current,
      ),
    );

    expect(
      await root.done.timeout(const Duration(seconds: 5)),
      isA<Cancelled>(),
    );
    expect(second, isTrue, reason: 'the listener after it still runs');
    expect(errors.length, 2, reason: 'the bug belongs to the listener');
  });

  test('the window closes with the pass that told the callbacks', () async {
    final chain = _Chain(depth);
    final errors = <Object>[];
    final root = chain.start(observer: ErrorObserver.answering(errors));
    await chain.bottom.future;
    try {
      root.cancel().ignore();
    } on Object catch (_) {
      // The cascade running out of stack is the premise of the run.
    }

    // The cascade is over, and a listener registered now runs on the
    // spot -- on a stack that is whole again, where a bug of its own is
    // its own again.
    root.whenCancelled((_) => _forever(0));
    expect(errors.single, isA<StackOverflowError>());
  });

  test('a callback that runs out of stack on its own is still its own',
      () async {
    // No cascade and no depth: one job, a listener with a bug of its
    // own. What the engine lets through while it unwinds its own
    // overflow it must not let through here.
    final errors = <Object>[];
    var second = false;
    final job = Job<void>(
      (ctx) async {
        await null;
        throw Cancelled.by(
          reason: const TestCancelReason('probe'),
          started: true,
          stackTrace: StackTrace.current,
        );
      },
      observer: ErrorObserver.answering(errors),
    )
      ..whenCancelled((_) => _forever(0))
      ..whenCancelled((_) => second = true);

    expect(
      await job.done.timeout(const Duration(seconds: 5)),
      isA<Cancelled>(),
    );
    expect(second, isTrue, reason: 'the listener after it still runs');
    expect(errors.single, isA<StackOverflowError>());
  });

  test('an onCancel that runs out of stack does not take the rest with it',
      () async {
    final errors = <Object>[];
    var second = false;
    final job = Job<void>(
      (ctx) async {
        ctx
          ..onCancel(() => _forever(0))
          ..onCancel(() => second = true);
        await ctx.wait(() => Completer<void>().future);
      },
      observer: ErrorObserver.answering(errors),
    );
    await delay(1);

    await job.cancel().timeout(const Duration(seconds: 5));
    expect(job.outcome, isA<Cancelled>());
    expect(second, isTrue, reason: 'the callback after it still runs');
    expect(errors.single, isA<StackOverflowError>());
  });

  test('a callback that runs out of stack is not a callback that failed',
      () async {
    final chain = _Chain(depth, framesPerCallback: 400);
    final errors = <Object>[];
    final root = chain.start(observer: ErrorObserver(errors));
    await chain.bottom.future;

    try {
      root.cancel().ignore();
    } on Object catch (_) {
      // The cascade running out of stack is the point of the run.
    }

    // The deepest callbacks ask for frames that are no longer there: that
    // is what makes this run different from the first one, and without it
    // the test would prove nothing.
    expect(
      chain.interrupted,
      greaterThan(0),
      reason: 'no callback was cut short, so nothing here was tested',
    );
    expect(
      errors,
      isEmpty,
      reason: 'an overflow of the cascade is not a failure of the callback '
          'it landed in, and must not be announced as one',
    );
  });
}

/// A chain of nested jobs, one child per level, as deep as asked.
///
/// Every level records that it was told to stop, which is what a body does
/// with a cancellation — hand it to the work it started.
final class _Chain {
  final int depth;

  /// How many frames a callback of this chain asks for of its own.
  final int framesPerCallback;

  final jobs = <Job<void>>[];
  final List<bool> toldToStop;

  /// How many callbacks began and never reached their last line.
  int interrupted = 0;

  /// Completes when the deepest level is running and the chain is whole.
  final bottom = Completer<void>();

  final _never = Completer<void>();

  _Chain(this.depth, {this.framesPerCallback = 0})
      : toldToStop = List<bool>.filled(depth + 1, false);

  /// The head of the chain, started the way any root is.
  Job<void> start({JobObserver? observer}) {
    final head = Job<void>((ctx) => _down(ctx, 0), observer: observer);
    jobs.add(head);
    return head;
  }

  /// The head of the chain, for a parent to run as its child.
  DeferredJob<void> deferred() {
    final head = Job.deferred<void>((ctx) => _down(ctx, 0));
    jobs.add(head);
    return head;
  }

  /// How many levels the cascade reached before it ran out of stack.
  int get marked => jobs.where((job) => job.isCancelled).length;

  /// The marked levels that were never told to stop, apart from a handful
  /// at the deep end.
  ///
  /// The handful is real and it moves. A callback of this chain only
  /// writes a flag, so it asks for almost no stack of its own -- and
  /// still, between runs of the same file, between none and five of the
  /// deepest lose theirs: the cascade calls the same method thousands of
  /// times in a row, the compiler installs optimized code somewhere in
  /// the middle of the descent, and whether it got there before the
  /// bottom decides how large the frames down there are. Under
  /// `--no-background-compilation` the count is zero every time; a run
  /// that lost five was seen under the plain runner. Sixteen is that
  /// handful with room over it. Without the guard on the unwinding the
  /// count is not a handful but every one of them, so the slack costs
  /// the test nothing.
  List<int> get silent {
    final reached = marked;
    return [
      for (var index = 0; index < reached - 16; index++)
        if (!toldToStop[index]) index,
    ];
  }

  Future<void> _down(JobContext ctx, int index) async {
    ctx.onCancel(() {
      interrupted++;
      _burn(framesPerCallback);
      interrupted--;
      toldToStop[index] = true;
    });
    if (index == depth) {
      bottom.complete();
      await _never.future;
      return;
    }
    // Suspended before the child is made: starting a child runs its body
    // up to its first await, so without this the chain would be built on
    // one synchronous stack and would run out of it long before the
    // cascade does.
    await null;
    final child = Job.deferred<void>((ctx) => _down(ctx, index + 1));
    jobs.add(child);
    await ctx.run(child);
  }
}

/// Asks the stack for [frames] frames and gives them back.
int _burn(int frames) => frames == 0 ? 0 : _burn(frames - 1) + 1;

/// Asks the stack for everything it has, the way a callback with a bug
/// of its own does.
int _forever(int depth) => _forever(depth + 1) + 1;
