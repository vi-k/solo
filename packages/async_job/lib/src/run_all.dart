part of 'job_base.dart';

/// What a group of [JobContext.runAll] needs from a branch it holds.
///
/// It lives on the branch because the barriers are inside the core's own
/// unwinding, in [JobBase._execute]; every call here goes straight back to
/// the group.
final class _GroupHold {
  /// The body of the branch has ended with this outcome, and nothing at
  /// all is decided by that.
  final void Function(Outcome<Object?> outcome) bodyEnded;

  /// Stands at the first barrier until the group lets the branch unwind.
  final Future<void> Function() beforeDisposal;

  /// Stands at the second barrier. The answer is the verdict of the group:
  /// `true` when it has committed the value of this branch.
  final Future<bool> Function() beforeOutcome;

  _GroupHold({
    required this.bodyEnded,
    required this.beforeDisposal,
    required this.beforeOutcome,
  });
}

/// One branch of a group, and everything the group keeps about it.
final class _GroupBranch<T> {
  final JobBase<T> job;

  /// Completed when the group lets the branch into its unwinding.
  final pastFirstBarrier = Completer<void>();

  /// Completed with the verdict when the group lets the branch to its
  /// outcome.
  final pastSecondBarrier = Completer<bool>();

  /// Whether the branch is standing at the first barrier right now.
  bool atFirstBarrier = false;

  /// Whether the branch is standing at the second barrier right now.
  bool atSecondBarrier = false;

  /// The outcome of the body, as the early word gave it.
  Outcome<T>? bodyOutcome;

  /// Whether this call asked the branch to stop.
  ///
  /// The cancellation that then ends the branch is not an outcome of the
  /// group, whoever built it: the request may have been refused, or lost
  /// to a cancellation that arrived in the same minute, and a match of
  /// objects would not prove who created one anyway. A [Failed] is never
  /// filtered — a branch that refused the stop and failed on its own has
  /// a diagnosis of its own.
  bool askedToStop = false;

  /// The final outcome, once the branch has one.
  Outcome<T>? settled;

  _GroupBranch(this.job);
}

/// The coordinator behind [JobContext.runAll].
///
/// It starts every branch, asks the others to stop as soon as one goes
/// wrong, holds each of them at two barriers so that none can reach an
/// outcome before the group has decided, and then either hands the values
/// over in one synchronous step or waits for every branch to finish and
/// throws.
final class _RunAllGroup<T> {
  final JobContextBase _ctx;
  final List<Job<T>> _children;
  final _branches = <_GroupBranch<T>>[];

  /// The branches that have finished, in the order the group learned it.
  /// Which one came first is what decides between two cancellations.
  final _received = <_GroupBranch<T>>[];

  /// Set once the group is on its way out with an error.
  bool _failing = false;

  /// Whether the group has handed its values over.
  bool _committed = false;

  /// A refusal of admission. It wins over whatever the branches end with:
  /// the caller asked for a group that was never allowed to form.
  (Object, StackTrace)? _refusal;

  /// An error thrown by the code of the group itself — the check of the
  /// parent above all. It wins the same way.
  (Object, StackTrace)? _ownError;

  Completer<void>? _changing;

  _RunAllGroup(this._ctx, this._children);

  Future<List<T>> run() {
    for (final child in _children) {
      try {
        _ctx.startChild(child);
      } on Object catch (error, stackTrace) {
        // `startChild` has already finished this child with this very
        // error, and the error is what comes out of the group. The child
        // does not join the branches, or the group would report it a
        // second time as a failure nobody chose.
        _refusal = (error, stackTrace);
        break;
      }
      if (child is! JobBase<T>) {
        // Unreachable: `startChild` refuses a handle that is not a job of
        // this core before it starts anything.
        continue;
      }
      // Attached after the admission and not before it, and the difference
      // is not cosmetic: a handle already running as a branch of another
      // group is refused here by `StateError`, and touching its hold on
      // the way would take that group's branch out of its hold — the very
      // hole this member exists to close. The barriers are safe after:
      // `_execute` awaits the descendants before it reaches one. The early
      // word is not, and it is read off the branch below.
      final branch = _GroupBranch<T>(child);
      branch.job._hold = _holdFor(branch);
      _branches.add(branch);
      // `done` and not `whenDone`: the group looks at every outcome and
      // answers for the failures it does not throw, so no branch is left
      // reporting one on its own as well. A failure a cancellation covered
      // is in no outcome, and the group never sees it: the branch answers
      // for that one itself, as any job does.
      branch.job.done
          .then((outcome) => _branchFinished(branch, outcome))
          .ignore();
    }
    // The early word a branch said before it had a hold. A body that
    // throws before its first `await` runs to its end inside `startChild`,
    // and the hold attached a line later was not there to hear it. Read
    // here and not from the loop: until every branch is admitted and on
    // the list, a stop would go round the siblings the loop has not
    // started yet. Still the same synchronous step, so none of them has
    // moved past its first suspension point, and the stop reaches every
    // one of them before it does any more work.
    for (final branch in _branches) {
      if (branch.bodyOutcome != null) {
        continue;
      }
      if (branch.job._bodyOutcome case final outcome?) {
        _branchBodyEnded(branch, outcome);
      }
    }
    if (_refusal case final refusal?) {
      if (_branches.isEmpty) {
        // Nothing started and nobody to wait for: the refusal comes out
        // the way `run` gives one, synchronously.
        Error.throwWithStackTrace(refusal.$1, refusal.$2);
      }
      _beginFailing(refusal.$1, null);
    }
    return _settle();
  }

  _GroupHold _holdFor(_GroupBranch<T> branch) => _GroupHold(
        bodyEnded: (outcome) => _branchBodyEnded(branch, outcome),
        beforeDisposal: () => _parkBeforeDisposal(branch),
        beforeOutcome: () => _parkBeforeOutcome(branch),
      );

  void _branchBodyEnded(_GroupBranch<T> branch, Outcome<Object?> outcome) {
    // The branch is a `JobBase<T>`, so this is an outcome of its own type.
    branch.bodyOutcome = outcome as Outcome<T>;
    _sawTrouble(branch, outcome);
    _wake();
  }

  void _branchFinished(_GroupBranch<T> branch, Outcome<T> outcome) {
    branch.settled = outcome;
    _received.add(branch);
    _sawTrouble(branch, outcome);
    _wake();
  }

  /// Starts the stop unless [outcome] is a value, or the cancellation this
  /// very call asked for.
  void _sawTrouble(_GroupBranch<T> branch, Outcome<Object?> outcome) {
    if (_failing || _committed || outcome is Done<Object?>) {
      return;
    }
    if (outcome is Cancelled && branch.askedToStop) {
      // Not trouble: the stop working.
      return;
    }
    _beginFailing(_causeOf(outcome), branch);
  }

  Object _causeOf(Outcome<Object?> outcome) =>
      outcome is Failed ? outcome.error : outcome;

  /// Asks every branch but [source] to stop, and lets go of whoever is
  /// already waiting at a barrier.
  void _beginFailing(Object cause, _GroupBranch<T>? source) {
    _failing = true;
    final reason = SiblingCancelReason(cause: cause);
    for (final branch in _branches) {
      if (identical(branch, source) ||
          branch.askedToStop ||
          branch.job.isFinished) {
        continue;
      }
      final cancelled = Cancelled.by(
        reason: reason,
        started: branch.job.isRunning,
        stackTrace: StackTrace.current,
      );
      // Remembered before the call and not after it: `cancelWith` reaches
      // code that may come straight back here.
      branch.askedToStop = true;
      try {
        branch.job.cancelWith(cancelled);
      } on Object catch (error, stackTrace) {
        // An engine of a domain threw while being asked to stop. That is
        // not an outcome of any branch, and above all it must not leave
        // the rest of them standing at their barriers: the loop goes on,
        // and the error comes out of the group the way a refusal of
        // admission does.
        _ownError ??= (error, stackTrace);
      }
    }
    for (final branch in _branches) {
      _letPastFirstBarrier(branch);
      _letPastSecondBarrier(branch, committed: false);
    }
  }

  void _letPastFirstBarrier(_GroupBranch<T> branch) {
    if (!branch.atFirstBarrier) {
      return;
    }
    branch.atFirstBarrier = false;
    branch.pastFirstBarrier.complete();
  }

  void _letPastSecondBarrier(
    _GroupBranch<T> branch, {
    required bool committed,
  }) {
    if (!branch.atSecondBarrier) {
      return;
    }
    branch.atSecondBarrier = false;
    branch.pastSecondBarrier.complete(committed);
  }

  Future<void> _parkBeforeDisposal(_GroupBranch<T> branch) {
    branch.atFirstBarrier = true;
    if (_failing) {
      _letPastFirstBarrier(branch);
    }
    _wake();
    return branch.pastFirstBarrier.future;
  }

  Future<bool> _parkBeforeOutcome(_GroupBranch<T> branch) {
    branch.atSecondBarrier = true;
    if (_failing) {
      _letPastSecondBarrier(branch, committed: false);
    }
    _wake();
    return branch.pastSecondBarrier.future;
  }

  Future<void> _somethingChanges() => (_changing ??= Completer<void>()).future;

  void _wake() {
    final changing = _changing;
    if (changing == null) {
      return;
    }
    _changing = null;
    changing.complete();
  }

  bool _everyBranchIsAtFirstBarrier() => _branches.every(
        (branch) =>
            branch.atFirstBarrier ||
            branch.pastFirstBarrier.isCompleted ||
            branch.job.isFinished,
      );

  bool _everyBranchIsAtSecondBarrier() => _branches.every(
        (branch) => branch.atSecondBarrier || branch.job.isFinished,
      );

  Future<List<T>> _settle() async {
    try {
      while (!_failing && !_everyBranchIsAtFirstBarrier()) {
        await _somethingChanges();
      }
      if (!_failing) {
        _branches.forEach(_letPastFirstBarrier);
        while (!_failing && !_everyBranchIsAtSecondBarrier()) {
          await _somethingChanges();
        }
      }
      if (!_failing) {
        // Step two of the commit: the parent. The successful path does not
        // wait for `child.value`, and the check of the parent that waiting
        // makes goes with it — without this one a group would commit under
        // a parent that is already cancelled, or one whose rules of a
        // domain no longer hold.
        _ctx.check();
        // Step three, and after the check rather than before it: the check
        // runs a predicate of a domain, and that predicate may cancel a
        // branch on its way to answering yes.
        _rereadBranches();
      }
      if (!_failing) {
        return _commit();
      }
    } on Object catch (error, stackTrace) {
      // The code of the group itself threw while the branches stood at
      // their barriers. Nothing may be left held, and a branch whose body
      // returned a value must not slip away as [Done] with what it took
      // for the caller passed over.
      _ownError ??= (error, stackTrace);
      if (!_failing) {
        _beginFailing(error, null);
      }
    }
    // Every branch is stopped and every branch unwinds; the group waits
    // for all of them. That waiting is the promise: by the time the error
    // reaches the parent, whatever the branches took is closed.
    while (_received.length < _branches.length) {
      await _somethingChanges();
    }
    return _conclude();
  }

  /// The outcome a branch would end with if it ended right now.
  Outcome<T>? _provisionalOf(_GroupBranch<T> branch) =>
      branch.job._outcome ?? branch.job._pendingCancel ?? branch.bodyOutcome;

  void _rereadBranches() {
    for (final branch in _branches) {
      final provisional = _provisionalOf(branch);
      if (provisional is Done<T>) {
        continue;
      }
      // The branch that changed is the source, exactly as it would be had
      // it spoken up earlier: naming nobody would mark it asked-to-stop
      // along with the rest, and the filter would then swallow the very
      // outcome the group has to give.
      _beginFailing(
        provisional == null
            ? StateError('${branch.job} stands at the barrier with no outcome')
            : _causeOf(provisional),
        branch,
      );
      return;
    }
  }

  List<T> _commit() {
    // From here to the return there is no `await`. The group decides, takes
    // the put-aside registrations off the branches and hands the values
    // over in one synchronous step, so that a cancellation arriving after
    // it finds nothing left to close.
    final values = [
      for (final branch in _branches)
        (_provisionalOf(branch)! as Done<T>).value,
    ];
    _committed = true;
    for (final branch in _branches) {
      // Step four. On the successful path nobody runs them — exactly as
      // nobody runs what is still put aside at the end of the unwinding.
      // Traced here and not by the branch: by the time it reaches the end
      // of its own unwinding the list is already empty, and the receiver of
      // the values would learn nothing.
      branch.job
        .._traceDroppedCleanups()
        .._skipped.clear();
    }
    for (final branch in _branches) {
      // Step five: released with the verdict, and the list goes back.
      _letPastSecondBarrier(branch, committed: true);
    }
    return values;
  }

  List<T> _conclude() {
    final chosen = _chooseOutcome();
    final refusal = _refusal ?? _ownError;
    for (final branch in _received) {
      final outcome = branch.settled;
      if (outcome is! Failed) {
        continue;
      }
      if (refusal == null && identical(outcome, chosen)) {
        // The caller is about to receive this one.
        continue;
      }
      // Received and not chosen. Every [Failed] a branch ends with has been
      // announced already — a failure the body threw where it was caught,
      // one an engine of a domain handed in by [JobBase.finish] — so only
      // the route for an error nobody answered for is left, and the group is
      // the last one holding it. A branch that [Job.ignore] was called on
      // wants no answer: the notice stays, as it does for a failure a
      // cancellation covered.
      if (!branch.job._ignored) {
        branch.job._handleUnanswered(outcome.error, outcome.stackTrace);
      }
    }
    if (refusal != null) {
      Error.throwWithStackTrace(refusal.$1, refusal.$2);
    }
    if (chosen is Failed) {
      Error.throwWithStackTrace(chosen.error, chosen.stackTrace);
    }
    if (chosen is Cancelled) {
      Error.throwWithStackTrace(
        chosen,
        chosen.stackTrace ?? StackTrace.current,
      );
    }
    throw StateError('${_ctx._owner}: a group failed with nothing to throw');
  }

  /// A real failure if the group received one, otherwise the first
  /// cancellation that arrived — never one this call asked for.
  Outcome<T>? _chooseOutcome() {
    Cancelled? cancelled;
    for (final branch in _received) {
      final outcome = branch.settled;
      if (outcome == null || (outcome is Cancelled && branch.askedToStop)) {
        continue;
      }
      if (outcome is Failed) {
        return outcome;
      }
      if (outcome is Cancelled) {
        cancelled ??= outcome;
      }
    }
    return cancelled;
  }
}
