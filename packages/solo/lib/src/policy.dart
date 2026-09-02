/// How `SoloBase.add` treats jobs with the same key.
///
/// Every policy except [sequential] requires a non-null key and throws
/// [ArgumentError] otherwise.
enum Policy {
  /// Append to the queue; keys are ignored.
  sequential,

  /// If a job with the same key is queued or running, return that job and
  /// finish the new one with `Cancelled(manual, 'duplicate')`.
  droppable,

  /// Remove queued jobs with the same key, then append. The running job is
  /// left alone.
  replace,

  /// Like [replace], and also cancel the running job with the same key
  /// without waiting for it.
  restart,
}
