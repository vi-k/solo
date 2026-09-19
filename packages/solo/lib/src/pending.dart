import 'package:async_job/async_job.dart';
import 'package:meta/meta.dart';

/// What a job the controller is waiting for is doing, as far as the
/// engine knows.
enum SoloPhase {
  /// The body has not come back yet, whatever it is waiting on: a
  /// checkpoint of its context, a bare `await`, an external call. The
  /// engine knows the body is still out, not what holds it.
  body,

  /// The body is over and the job is waiting for its children.
  children,

  /// The body and its children are over: the job is releasing what the
  /// body opened, and then it ends.
  cleanup,
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
  /// asked, or an open section is holding one back; see
  /// [heldCancellation].
  final Cancelled? cancellation;

  /// The cancellation an open `JobContext.uncancellable` section is holding
  /// back, or `null`. The job is not marked with it until the section
  /// closes, so [cancellation] is `null` meanwhile.
  final Cancelled? heldCancellation;

  /// How many children the job is still waiting for.
  final int children;

  /// Whether a `JobContext.uncancellable` section is open. A cancellation
  /// that arrives now is held until it closes; an open section alone does
  /// not mean one has, and [heldCancellation] is what says so.
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
    required this.heldCancellation,
    required this.children,
    required this.inUncancellableSection,
    required this.refusesCancellation,
    required this.closing,
  });

  /// Whether a cancellation is on this job and waiting to land: it is
  /// marked with [cancellation], or an open section holds
  /// [heldCancellation].
  ///
  /// Not the same as "somebody asked". A job created with
  /// `cancellable: false` turns a rejectable cancellation down instead of
  /// keeping it, so nothing is pending on it however many times it was
  /// asked — [refusesCancellation] is the half of that story the engine
  /// can tell.
  bool get cancellationPending =>
      cancellation != null || heldCancellation != null;

  @override
  String toString() {
    final description = job.describe();
    final name =
        description.isEmpty ? '${job.key}' : '${job.key}: $description';
    final what = switch (phase) {
      SoloPhase.body => 'in its body',
      SoloPhase.children => 'waiting for $children children',
      SoloPhase.cleanup => 'in its cleanup',
    };
    final notes = [
      if (closing) 'closing',
      if (cancellation != null) 'cancelled by $cancellation',
      if (heldCancellation != null)
        'holding $heldCancellation back'
      else if (inUncancellableSection)
        'in an uncancellable section',
      if (refusesCancellation) 'created cancellable: false',
    ];

    return 'SoloPending([$name] $what${notes.isEmpty ? '' : ', '
        '${notes.join(', ')}'})';
  }
}
