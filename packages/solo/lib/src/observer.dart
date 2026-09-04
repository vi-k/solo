import 'solo_base.dart';

/// Cross-cutting hooks for every controller: analytics, error reporting, a
/// single log. Set [SoloBase.observer] once at startup.
///
/// The engine calls the observer before the controller's own hook, and
/// independently of it: a subclass that forgets `super` does not switch the
/// observer off. A hook that throws hands its error to the current zone and
/// changes nothing else — the engine goes on, and the controller's own hook
/// is still called.
abstract class SoloObserver {
  /// A controller was created.
  void onCreate(SoloBase<Object> solo) {}

  /// A job body is about to run.
  void onStart(SoloBase<Object> solo, Job<Object?> job) {}

  /// A job has an outcome, including jobs dropped before start.
  void onFinish(SoloBase<Object> solo, Job<Object?> job) {}

  /// A job body threw a non-[Cancelled] error, even after cancellation.
  ///
  /// Called for every such error, including the ones that end as
  /// [Cancelled] and are therefore never handed to the zone: a body that
  /// throws after cancellation, or an action abandoned by
  /// `JobContext.guard` that fails later. Those are this hook's business
  /// alone. See [Failed] for the errors that also reach the zone.
  void onError(
    SoloBase<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) {}

  /// The state changed, from a job or from `externalSetState`.
  void onChange(SoloBase<Object> solo, Object previous, Object current) {}

  /// A job called [JobContext.log].
  void onLog(SoloBase<Object> solo, Job<Object?> job, String message) {}

  /// The controller finished closing.
  void onClose(SoloBase<Object> solo) {}
}
