import 'package:async_job/async_job.dart';
import 'package:meta/meta.dart';

/// What a job the controller is waiting for is doing, as far as the
/// engine knows.
enum SoloPhase {
  /// The body has not come back yet.
  body,

  /// The body is over and the job is waiting for its children.
  children,

  /// The job is releasing what the body opened.
  cleanup,

  /// The engine has nothing to say. A job holds on for reasons of its own
  /// as well — a bare `await` on something that takes its time, an
  /// external call the body is inside — and those are not the engine's to
  /// see. Not a guess dressed as an answer.
  unknown,
}

/// What is holding the controller right now: a snapshot for whoever is
/// looking at a `close` that has not come back.
///
/// It says what the engine knows and stops there. A long cancellation
/// does not prove a forgotten `JobContext.wait`: the same wait happens
/// while a resource is being released or inside a section the body asked
/// not to be interrupted in, and it happens for reasons outside the
/// engine altogether.
@immutable
final class SoloPending {
  /// The job the controller is waiting for.
  final Job<Object?> job;

  /// What that job is doing.
  final SoloPhase phase;

  /// The cancellation the job is marked with, or `null` — either nobody
  /// asked, or the job is holding one back; see [inUncancellableSection].
  final Cancelled? cancellation;

  /// How many children the job is still waiting for.
  final int children;

  /// Whether a `JobContext.uncancellable` section is open: a cancellation
  /// that arrived is held until it closes.
  final bool inUncancellableSection;

  /// Whether the job was created with `cancellable: false` and turns down
  /// every cancellation it may turn down.
  final bool refusesCancellation;

  /// Whether `close` has been called on the controller.
  final bool closing;

  /// Creates a snapshot; the engine makes these, a domain reads them.
  const SoloPending({
    required this.job,
    required this.phase,
    required this.cancellation,
    required this.children,
    required this.inUncancellableSection,
    required this.refusesCancellation,
    required this.closing,
  });

  /// Whether a cancellation is on this job and waiting to land: it is
  /// marked with [cancellation], or an open section is holding one back.
  ///
  /// Not the same as "somebody asked". A job created with
  /// `cancellable: false` turns a rejectable cancellation down instead of
  /// keeping it, so nothing is pending on it however many times it was
  /// asked — [refusesCancellation] is the half of that story the engine
  /// can tell.
  bool get cancellationPending =>
      cancellation != null || inUncancellableSection;

  @override
  String toString() {
    final description = job.describe();
    final name =
        description.isEmpty ? '${job.key}' : '${job.key}: $description';
    final what = switch (phase) {
      SoloPhase.body => 'in its body',
      SoloPhase.children => 'waiting for $children children',
      SoloPhase.cleanup => 'in its cleanup',
      SoloPhase.unknown => 'in a phase the engine cannot name',
    };
    final notes = [
      if (closing) 'closing',
      if (cancellation != null) 'cancelled by $cancellation',
      if (inUncancellableSection) 'holding a cancellation back',
      if (refusesCancellation) 'created cancellable: false',
    ];

    return 'SoloPending([$name] $what${notes.isEmpty ? '' : ', '
        '${notes.join(', ')}'})';
  }
}
