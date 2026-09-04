/// When a job may be cancelled by someone else's decision.
///
/// Its own rules are not covered by any of these: a state that stopped
/// matching `W`, or a `keepWhile` that turned false, cancels a running job
/// whatever it says here. Neither is `SoloBase.close` covered for a job
/// still in the queue — nothing will run it once the controller is gone, so
/// it is dropped with `Cancelled(closed)`.
enum Cancellable {
  /// In the queue and while the body runs.
  always,

  /// In the queue only. Once the body has started it runs to the end:
  /// `Job.cancel` waits for it instead of cancelling it, a cancelled parent
  /// leaves it alone, and `SoloBase.close` waits for it.
  ///
  /// For work that must not be interrupted halfway — a payment on its way
  /// to the server, a write already on the wire — but that nobody has begun
  /// yet while it waits its turn.
  whileQueued,

  /// Neither. On top of [whileQueued], the queue's `remove`, `removeWhere`
  /// and `clear` skip it unless they are given `force: true`, which is
  /// there for a controller tearing itself down rather than for ordinary
  /// decisions.
  never,
}
