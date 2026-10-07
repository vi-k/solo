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
/// looking at a `close` that has not come back, taken by `Solo.pending`.
///
/// One of three, and a `switch` over them is exhaustive:
///
/// * [SoloPendingJob] — a job the controller is waiting for: its body,
///   its children or its cleanup;
/// * [SoloPendingQueue] — a drain with no job running, and the queue it
///   has still to run;
/// * [SoloPendingStream] — the engine has closed, and the stream of
///   `SoloStream` waits for a subscription to take its done event.
///
/// ```dart
/// final line = switch (controller.pending) {
///   SoloPendingJob(:final job, :final phase) => '${job.key} in $phase',
///   SoloPendingQueue(:final jobs) => '${jobs.length} queued',
///   SoloPendingStream() => 'a subscriber',
///   null => 'nothing',
/// };
/// ```
///
/// Every one of them prints as `SoloPending(...)`: a log line is read by
/// eye, and the name of the variant adds nothing to it.
@immutable
sealed class SoloPending {
  /// Lets the three variants be constant.
  const SoloPending();
}

/// A job the controller is waiting for, and what it is doing as far as the
/// engine knows.
///
/// It says what the engine knows and stops there. A long cancellation
/// does not prove a forgotten `JobContext.abandonable`: the same wait happens
/// while a resource is being released or inside a section the body asked
/// not to be interrupted in, and it happens for reasons outside the
/// engine altogether.
final class SoloPendingJob extends SoloPending {
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
  /// closes, so [cancellation] is `null` meanwhile. A rule of the job is not
  /// held: it marks the job at once, and the cancellation held until then
  /// is dropped, so this goes back to `null`.
  final Cancelled? heldCancellation;

  /// How many children the job is still waiting for.
  final int children;

  /// Whether a `JobContext.uncancellable` section is open. A cancellation
  /// that arrives now is held until it closes; an open section alone does
  /// not mean one has, and [heldCancellation] is what says so.
  final bool inUncancellableSection;

  /// Whether the job accepts a cancellation it may refuse, as it was
  /// created. One created with `cancellable: false` turns every such
  /// cancellation down.
  final bool cancellable;

  /// Whether `close` has been called on the controller.
  final bool closing;

  /// Whether that `close` is a drain: the job is not asked to stop, it
  /// runs to its end by the usual rules, and the queue behind it runs
  /// next. [closing] is true as well.
  final bool draining;

  /// Creates a snapshot; the engine makes these, a domain reads them.
  const SoloPendingJob({
    required this.job,
    required this.phase,
    required this.cancellation,
    required this.heldCancellation,
    required this.children,
    required this.inUncancellableSection,
    required this.cancellable,
    required this.closing,
    required this.draining,
  });

  /// Whether a cancellation is on this job and waiting to land: it is
  /// marked with [cancellation], or an open section holds
  /// [heldCancellation].
  ///
  /// Not the same as "somebody asked". A job created with
  /// `cancellable: false` turns a rejectable cancellation down instead of
  /// keeping it, so nothing is pending on it however many times it was
  /// asked — [cancellable] is the half of that story the engine
  /// can tell.
  bool get cancellationPending =>
      cancellation != null || heldCancellation != null;

  @override
  String toString() {
    final what = switch (phase) {
      SoloPhase.body => 'in its body',
      SoloPhase.children => 'waiting for $children children',
      SoloPhase.cleanup => 'in its cleanup',
    };
    final notes = [
      if (draining) 'draining' else if (closing) 'closing',
      if (cancellation != null) 'cancelled by $cancellation',
      if (heldCancellation != null)
        'holding $heldCancellation back'
      else if (inUncancellableSection)
        'in an uncancellable section',
      if (!cancellable) 'created cancellable: false',
    ];

    return 'SoloPending(${_name(job)} $what${notes.isEmpty ? '' : ', '
        '${notes.join(', ')}'})';
  }
}

/// A drain with no job running: the queue it has still to run holds the
/// `close`.
///
/// Only a drain makes one. Without `close` a queued group waiting for its
/// window holds nothing — the controller is idle, and `Solo.pending` is
/// `null` — and a plain `close` drops the queue at once.
///
/// Once a microtask has passed with no job running, every job in [jobs] is
/// a group of `collect` or `accumulate` its timing still holds back: the
/// engine goes past such a group to a ready job behind it, and starts that
/// one. A ready job is seen here only synchronously — right after
/// `close(mode: SoloCloseMode.drain)`, or from a hook before the engine
/// comes back to the queue.
final class SoloPendingQueue extends SoloPending {
  /// The jobs the drain has still to run, in queue order. Taken when the
  /// snapshot is: the queue moving on does not change it.
  ///
  /// A job whose start rules are being asked right now is first: it is off
  /// the queue and not started yet, so a rule that closes the controller
  /// with a drain and reads this finds its own job. A job its rules have
  /// ended, turned down or cancelled, is not in here: the drain will never
  /// run it.
  final List<Job<Object?>> jobs;

  /// Creates a snapshot; the engine makes these, a domain reads them.
  const SoloPendingQueue(this.jobs);

  @override
  String toString() => 'SoloPending(draining, ${jobs.length} queued: '
      '${jobs.map(_name).join(', ')})';
}

/// The engine has closed, and the stream of `SoloStream` waits for a
/// subscription to take its done event: one left paused holds `close`
/// until it is resumed or cancelled.
///
/// A broadcast stream says neither how many subscriptions it has nor which
/// of them is paused, so this says only that the stream is waiting.
final class SoloPendingStream extends SoloPending {
  /// Creates the snapshot; the engine makes it, a domain reads it.
  const SoloPendingStream();

  @override
  String toString() =>
      'SoloPending(stream: a subscription has not taken its done event)';
}

String _name(Job<Object?> job) {
  final description = job.describe();
  return description.isEmpty ? '[${job.key}]' : '[${job.key}: $description]';
}
