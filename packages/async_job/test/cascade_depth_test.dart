import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:test/test.dart';

import 'support/cancel_reason.dart';
import 'support/delay.dart';
import 'support/error_observer.dart';

void main() {
  // Deep enough that no stack survives the cascade. The point of the run
  // is not the depth itself but what the kernel leaves behind when it
  // runs out: on the machine these tests were written on the cascade
  // reaches about 2900 levels.
  const depth = 50000;

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
        unawaited(ctx.run(chain.deferred()));
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
      observer: ErrorObserver(errors),
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
}

/// A chain of nested jobs, one child per level, as deep as asked.
///
/// Every level records that it was told to stop, which is what a body does
/// with a cancellation — hand it to the work it started.
final class _Chain {
  final int depth;
  final jobs = <Job<void>>[];
  final List<bool> toldToStop;

  /// Completes when the deepest level is running and the chain is whole.
  final bottom = Completer<void>();

  final _never = Completer<void>();

  _Chain(this.depth) : toldToStop = List<bool>.filled(depth + 1, false);

  /// The head of the chain, started the way any root is.
  Job<void> start() {
    final head = Job<void>((ctx) => _down(ctx, 0));
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
  /// at the deep end: those last few run their callbacks on a stack that
  /// has only just run out, and lose them to a second overflow. Measured
  /// at five; without the guard on the unwinding it is every one of them.
  List<int> get silent {
    final reached = marked;
    return [
      for (var index = 0; index < reached - 16; index++)
        if (!toldToStop[index]) index,
    ];
  }

  Future<void> _down(JobContext ctx, int index) async {
    ctx.onCancel(() => toldToStop[index] = true);
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
