/// What `SoloBase.close` does with the work the controller already has.
enum SoloCloseMode {
  /// Drop every queued job with `Cancelled(closed)` and cancel the running
  /// one. The default, and what a screen going away wants.
  cancel,

  /// Run what is already queued, then close: no new root job is taken, and
  /// the ones accepted before the call run by the usual rules — in order,
  /// with their own children and cleanup, waiting out an accumulation
  /// window where there is one.
  ///
  /// Running the queue is not a promise of delivery. A drained job can
  /// still fail or be turned down by its rules; a buffer that keeps events
  /// until the sending is confirmed is built on top of this, not inside
  /// it.
  drain,
}
