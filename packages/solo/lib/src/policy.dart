/// How `Solo.add` treats jobs with the same key.
///
/// Every policy except [sequential] requires a non-null key and throws
/// [ArgumentError] otherwise.
enum Policy {
  /// Append to the queue; keys are ignored.
  sequential,

  /// If a job with the same key is queued or is the root job the
  /// controller is running, return that job and finish the new one with
  /// `Cancelled(manual, 'duplicate')`.
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
  droppable,

  /// Remove queued jobs with the same key, then append. The running root
  /// job is left alone, and so is a queued job created with
  /// `cancellable: false` — the removal is the one `SoloQueue.removeWhere`
  /// does without `force`.
  replace,

  /// Like [replace], and also cancel the running root job with the same
  /// key without waiting for it — unless that one was created with
  /// `cancellable: false`, which refuses.
  restart,
}
