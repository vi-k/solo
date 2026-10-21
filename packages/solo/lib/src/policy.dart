/// How `Solo.add` treats jobs with the same key.
///
/// Every policy except [sequential] requires a non-null key and throws
/// [ArgumentError] otherwise.
///
/// A job whose start rules are being asked counts as queued for every
/// policy: it is off the queue and not started yet, and a rule of it may
/// call `add`. Its `isQueued` says `false` all the same. [droppable] hands
/// that job back, so a rule that turns its job down afterwards ends the
/// job the call got as well.
enum Policy {
  /// Append to the queue; keys are ignored.
  sequential,

  /// If a job with the same key is queued or is the root job the controller is
  /// running, return that job and finish the new one with
  /// `Cancelled(duplicate)`, whose reason is a `DuplicateCancelReason`.
  ///
  /// A child is not looked at, running or not: it runs inside another job
  /// and never went through the queue, which is all a policy rules.
  ///
  /// The running job counts only while it is still going to do the work.
  /// One that has been cancelled and is unwinding is not a duplicate —
  /// it will never do what the new call is asking for — and the new job
  /// is added as usual.
  ///
  /// The job found by the key is handed back as the result type of the new
  /// one, so the two result types have to be the same one: a key held by a
  /// job of another type throws [ArgumentError], and it throws before the
  /// new job is touched, which leaves that handle good for another `add`.
  /// The two jobs are compared with each other rather than matched against
  /// the type argument of the call, which would let a `SoloJob<void>` take
  /// any job at all. Give every result type its own key.
  ///
  /// The new job goes with all it was given: the `timeout` of a call that
  /// found a live duplicate is lost along with it, and the job handed back
  /// keeps the deadline it was made with, or none. Once that job has ended
  /// — by its own deadline too — the next call queues a job of its own.
  ///
  /// Every caller of the key may hold the same job, so each one continues
  /// it through its own handle of `shared()`, and a plain `then` on a job
  /// of this policy throws a [StateError], on the first call as well. So
  /// does one on a job of another policy from the moment a call of this
  /// one hands it back. A `then` its own caller took before stays, and then
  /// `shared()` throws for the caller of this policy, who is left with
  /// `done` and `value`: give this policy a key of its own.
  droppable,

  /// Append, then remove queued jobs with the same key: their `onFinish`
  /// and cancellation listeners already see the new job queued. The running
  /// root job is left alone, and so is a queued job created with
  /// `cancellable: false` — the removal is the one `SoloQueue.removeWhere`
  /// does without `force`. A removed job ends `Cancelled(replaced)`, whose
  /// reason is a `ReplacedCancelReason`.
  replace,

  /// Like [replace], and also cancel the running root job with the same
  /// key without waiting for it — unless that one was created with
  /// `cancellable: false`, which refuses. The reason of that cancellation
  /// is a `ReplacedCancelReason` as well.
  restart,
}
