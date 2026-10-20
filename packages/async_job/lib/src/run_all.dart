part of 'job_base.dart';

/// What a group of [JobContext.runAll] needs from a branch it holds.
///
/// It lives on the branch because the barriers are inside the core's own
/// unwinding, in [JobBase._execute]; every call here goes straight back to
/// the group.
final class _GroupHold {
  /// The body of the branch has ended with this outcome. Nothing is decided by
  /// that, except that a value an engine hands the branch once the group has
  /// heard of a failure comes too late for the group: see [takeFailure].
  final void Function(Outcome<Object?> outcome) bodyEnded;

  /// Stands at the first barrier until the group lets the branch unwind.
  final Future<void> Function() beforeDisposal;

  /// Stands at the second barrier. The answer is the verdict of the group:
  /// `true` when it has committed the value of this branch.
  final Future<bool> Function() beforeOutcome;

  /// An engine has ended the branch by hand with a value. The answer is `true`
  /// when the group heard by the early word that the body failed before that:
  /// it then goes by that failure, throws it or answers for it, and the value
  /// is too late for it.
  final bool Function() takeFailure;

  _GroupHold({
    required this.bodyEnded,
    required this.beforeDisposal,
    required this.beforeOutcome,
    required this.takeFailure,
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

  /// Whether the group listens for the outcome of the branch.
  bool heard = false;

  /// Whether the group goes by the failure of the body, which it heard first,
  /// and not by the value an engine handed in later.
  bool failureTaken = false;

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

  /// Whether [run] is on the stack: the group is forming.
  ///
  /// Up from the construction, and [run] takes it down once [_settle] has
  /// been entered. While it stands the owner does not judge the group. A
  /// turn later [run] is on no stack, for it is synchronous, and a mark
  /// that still stands then was left by a [run] that was thrown out: the
  /// owner takes it down -- see [JobBase._awaitChildren].
  bool _forming = true;

  /// Whether [_settle] is alive: entered, and not thrown out.
  ///
  /// Written by that routine and by nobody else. A group on the chain of its
  /// owner that is neither forming nor settling has no routine deciding for its
  /// branches: it was cut short while it was forming. The stack ran out under
  /// [run], and whatever the handlers on the way up called ran out of it again,
  /// so nothing is done down there. The owner takes the group up once its own
  /// body is over, on a stack of its own -- see [_concludeTorn].
  bool _settling = false;

  /// The group that went on the chain of the owner before this one -- see
  /// [JobBase._firstGroup].
  _RunAllGroup<Object?>? _next;

  _RunAllGroup(this._ctx, this._children);

  Future<List<T>> run() {
    // On the chain of the owner before anything starts, and off it once
    // the group has ended. By two stores, and not into a list: this may be
    // the bottom of a stack that has run out, and a call made there may
    // stop halfway.
    final owner = _ctx._owner;
    _next = owner._firstGroup;
    owner._firstGroup = this;
    for (var index = 0; index < _children.length; index++) {
      final child = _children[index];
      try {
        _ctx.startChild(child);
      } on Object catch (error, stackTrace) {
        // A child refused before adoption is left as it was. One refused
        // after it `startChild` has already finished with this very
        // error, or, when the stack ran out under its start, has left
        // where the throw found it: on the list of the owner, if it got
        // there, for the owner to end. Either way the error is what comes
        // out of the group. The child does not join the branches, or the
        // group would report it a second time as a failure nobody chose.
        _refusal = (error, stackTrace);
        if (identical(error, _ctx.pendingCancel)) {
          _turnAwayTheRest(index + 1);
        }
        break;
      }
      // Always so: `startChild` refuses a handle that is not a job of this
      // core before it starts anything. A cast and not a branch that skips
      // the child: such a branch would hide the day this stops being true.
      child as JobBase<T>;
      // Attached after the admission and not before it, and the difference
      // is not cosmetic: a handle already running as a branch of another
      // group is refused here by `StateError`, and touching its hold on
      // the way would take that group's branch out of its hold — the very
      // hole this member exists to close. The barriers are safe after:
      // `_execute` awaits the descendants before it reaches one. The early
      // word is not, and it is read off the branch below.
      final branch = _GroupBranch<T>(child);
      // On the list before it has a hold: a branch that stands at a
      // barrier is then always one the group knows, wherever this loop is
      // cut short.
      _branches.add(branch);
      // A branch that is over already -- an engine ended it by hand in its
      // start -- stands at no barrier, and its outcome is all the group goes
      // by. A hold would carry word of a failure of the body that comes too
      // late, and keep the group reachable from the branch for good: the finish
      // that would let go of it has run already.
      if (!branch.job.isFinished) {
        branch.job._hold = _holdFor(branch);
      }
      _hear(branch);
    }
    // The early word a branch said before it had a hold. A body that is not
    // `async` and throws in its start runs to its end inside `startChild`, and
    // the hold attached a line later was not there to hear it. Read here and
    // not from the loop: until every branch is admitted and on the list, a stop
    // would go round the siblings the loop has not started yet. Still the same
    // synchronous step, so none of them has moved past its first suspension
    // point, and the stop reaches every one of them before it does any more
    // work.
    //
    // Not from a branch that is over: its outcome is all the group goes by, as
    // above.
    for (final branch in _branches) {
      if (branch.bodyOutcome != null || branch.job.isFinished) {
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
        _leave();
        Error.throwWithStackTrace(refusal.$1, refusal.$2);
      }
      _beginFailing(refusal.$1, null);
    }
    final settled = _settle();
    // By a store: the routine has been entered, and from here it is the
    // one that speaks for the group.
    _forming = false;
    return settled;
  }

  /// Listens for the outcome of [branch] and takes the answering for it.
  ///
  /// The group looks at every outcome and answers for the failures it does not
  /// throw, so no branch is left reporting one on its own as well: the branch
  /// is marked observed, the way `done` marks it. By a store after the
  /// listening and not by `done` before it: cut short between the two, the
  /// branch would be observed with nobody listening, and its failure would
  /// reach no one. A failure of the body of a branch that ends [Cancelled] is
  /// in no outcome, and the group never sees it: the branch answers for that
  /// one itself, as any job does. So does a branch an engine ended by hand,
  /// unless the group heard of the failure before the value came: the group
  /// then goes by the failure — see [_takeFailure].
  void _hear(_GroupBranch<T> branch) {
    branch.job._done.future
        .then((outcome) => _branchFinished(branch, outcome))
        .ignore();
    branch.heard = true;
    branch.job._observed = true;
  }

  /// The group has ended, and its owner no longer keeps it.
  ///
  /// Stores and nothing else, as on the way in: a group refused before it
  /// started anything leaves from wherever [run] stands.
  void _leave() {
    final owner = _ctx._owner;
    if (identical(owner._firstGroup, this)) {
      owner._firstGroup = _next;
      return;
    }
    for (var group = owner._firstGroup; group != null; group = group._next) {
      if (identical(group._next, this)) {
        group._next = _next;
        return;
      }
    }
  }

  /// Takes up a group that was cut short while it was forming.
  ///
  /// Called on a stack of its own, once the body of the owner is over, so
  /// [run] is on no stack. The caller of [run] has its answer: whatever
  /// threw the group out reached the body by the throw, [error] if nothing
  /// else is written down. What is left is all a group does for its
  /// branches when it fails -- they are asked to stop, none is left
  /// standing at a barrier, and the group answers for the failures it
  /// listened for.
  ///
  /// The branches are the ones [run] wrote down. A handle it started and
  /// did not get to writing down has no hold and stands at no barrier: it
  /// is a child of the owner like any other.
  void _concludeTorn(Object error, StackTrace stackTrace) {
    // Written down as a refusal, so that no failure of a branch is taken
    // for the one the caller receives: the caller receives nothing more.
    _refusal ??= (error, stackTrace);
    // Before anything here that may throw. The owner comes back for the
    // group once, and a group that is failing holds no branch at a barrier:
    // if the rest is cut short as well, every branch still ends.
    _beginFailing(_refusal!.$1, null);
    // A branch the loop wrote down and did not get to listening for has
    // answered for itself if it is over.
    _branches.removeWhere((branch) => !branch.heard && branch.job.isFinished);
    for (final branch in _branches) {
      if (!branch.heard) {
        _hear(branch);
      }
    }
    _settle().ignore();
  }

  /// Turns away the handles from [from] on: a branch started earlier in the
  /// list cancelled the parent before its first `await`, and the rest would
  /// be left `created` for good, the way [JobContext.runAll] would have
  /// left them under a parent cancelled before the call. An engine refusing
  /// one of them is the answer `run` would give, and it comes out instead.
  void _turnAwayTheRest(int from) {
    final pending = _ctx.pendingCancel;
    for (final child in _children.skip(from)) {
      try {
        _ctx.startChild(child);
      } on Object catch (error, stackTrace) {
        if (!identical(error, pending) && identical(_refusal?.$1, pending)) {
          _refusal = (error, stackTrace);
        }
      }
    }
  }

  _GroupHold _holdFor(_GroupBranch<T> branch) => _GroupHold(
        bodyEnded: (outcome) => _branchBodyEnded(branch, outcome),
        beforeDisposal: () => _parkBeforeDisposal(branch),
        beforeOutcome: () => _parkBeforeOutcome(branch),
        takeFailure: () => _takeFailure(branch),
      );

  /// A value handed to [branch] by hand after the group heard its body fail
  /// comes too late: the group goes by the failure, as if the branch had ended
  /// with it. Asked by [JobBase.finish], among its stores.
  ///
  /// The group goes by what it heard first. A failure it has not heard of is
  /// not taken: the value came from `onError`, before the early word, or the
  /// body ended in its start, before the branch had a hold, and the value came
  /// before [run] read the body. Nor is one of a branch it does not listen for:
  /// a group cut short forgets such a branch once it is over, and the failure
  /// would reach nobody.
  bool _takeFailure(_GroupBranch<T> branch) {
    if (!branch.heard || branch.bodyOutcome is! Failed) {
      return false;
    }
    branch.failureTaken = true;
    return true;
  }

  /// What the group goes by for [branch]: the failure of its body when it took
  /// that, and the outcome of the branch otherwise.
  Outcome<T>? _endOf(_GroupBranch<T> branch) =>
      branch.failureTaken ? branch.bodyOutcome : branch.settled;

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
        // An engine threw while being asked to stop. That is not an outcome of
        // any branch, and above all it must not leave the rest of them standing
        // at their barriers: the loop goes on, and the error comes out of the
        // group the way a refusal of admission does.
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

  /// How many branches from the start of the list [_settle] has already
  /// seen at the first barrier or finished. A branch that is one of these
  /// stays one while [_settle] waits, so a wake looks on from here rather
  /// than over every branch again: with branches that come to the barrier
  /// one per turn, a walk over all of them on every wake was a square of
  /// their number.
  ///
  /// The walk counts a branch let past the barrier too, though while
  /// [_settle] waits for the first barrier there is none: before that wait
  /// is over a branch is let past only once [_failing] is raised, and that
  /// ends the wait. The check stays so that the count does not depend on
  /// that order.
  var _atFirstBarrier = 0;

  /// The same for the second barrier, which a branch leaves only when the
  /// group commits or fails — past the waiting either way.
  var _atSecondBarrier = 0;

  bool _everyBranchIsAtFirstBarrier() {
    while (_atFirstBarrier < _branches.length) {
      final branch = _branches[_atFirstBarrier];
      if (!branch.atFirstBarrier &&
          !branch.pastFirstBarrier.isCompleted &&
          !branch.job.isFinished) {
        return false;
      }
      _atFirstBarrier++;
    }
    return true;
  }

  bool _everyBranchIsAtSecondBarrier() {
    while (_atSecondBarrier < _branches.length) {
      final branch = _branches[_atSecondBarrier];
      if (!branch.atSecondBarrier && !branch.job.isFinished) {
        return false;
      }
      _atSecondBarrier++;
    }
    return true;
  }

  Future<List<T>> _settle() async {
    try {
      _settling = true;
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
          // domain no longer hold. Not once the body has ended, the same as
          // `run`: nobody is left to hear the answer, and a cancellation
          // thrown into a future nobody awaits goes to the zone.
          if (!_ctx._owner.bodyEnded) {
            _ctx.check();
          }
          // Step three, and after the check rather than before it: the check
          // runs a predicate of a domain, and that predicate may cancel a
          // branch on its way to answering yes.
          _rereadBranches();
        }
        if (!_failing) {
          final values = _commit();
          _leave();
          return values;
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
      _leave();
      return _conclude();
    } on Object {
      // A store and nothing else: this may be the bottom of a stack that
      // has run out. An error that leaves the routine after the group has
      // ended -- the one it fails with -- finds nobody asking.
      _settling = false;
      rethrow;
    }
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
    final traces = <void Function()>[];
    for (final branch in _branches) {
      // Step four. On the successful path nobody runs them — exactly as
      // nobody runs what is still put aside at the end of the unwinding.
      // Traced by the group and not by the branch: by the time it reaches
      // the end of its own unwinding the list is already empty, and the
      // receiver of the values would learn nothing.
      final trace = branch.job._droppedCleanupsTrace(_provisionalOf(branch));
      if (trace != null) {
        traces.add(trace);
      }
      branch.job._skipped.clear();
    }
    for (final branch in _branches) {
      // Step five: released with the verdict, and the list goes back. The
      // branch learns the verdict a turn later, at its barrier, and is
      // marked now: a cancellation reaching it in between, or while it
      // unwinds, must not turn a value already in the caller's hands into
      // a [Cancelled] outcome.
      branch.job._committedByGroup = true;
      _letPastSecondBarrier(branch, committed: true);
    }
    // Said only now. The line runs the code of whoever turned the channel
    // on, `describe` and [Job.debug] both, and that code may cancel a
    // branch: every branch must already be marked when it does.
    for (final trace in traces) {
      trace();
    }
    return values;
  }

  List<T> _conclude() {
    final chosen = _chooseOutcome();
    final refusal = _refusal ?? _ownError;
    for (final branch in _received) {
      final outcome = _endOf(branch);
      if (outcome is! Failed) {
        continue;
      }
      if (refusal == null && identical(outcome, chosen)) {
        // The caller is about to receive this one.
        continue;
      }
      // Received and not chosen. Every [Failed] the group goes by has been
      // announced already — a failure the body threw where it was caught, taken
      // in place of a value or not, one an engine handed in by [JobBase.finish]
      // — so only the route for an error nobody answered for is left, and the
      // group is the last one holding it. A branch that [Job.ignoreFailure] was
      // called on wants no answer: the notice stays, as it does for a failure
      // of the body of a cancelled job. A handle of [Job.shared] carries the
      // same failure on the branch's mark: whichever answers first answers.
      final job = branch.job;
      if (!job._ignored && !job._failureAnswered) {
        job._answer.answered = true;
        job._handleUnanswered(outcome.error, outcome.stackTrace);
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
      final outcome = _endOf(branch);
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
