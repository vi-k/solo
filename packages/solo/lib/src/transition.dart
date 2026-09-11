import 'package:async_job/async_job.dart';
import 'package:meta/meta.dart';

/// One state change, with who made it.
///
/// What a journal of `previous → current` alone cannot answer is which
/// operation the change belonged to, and that cannot be worked out from
/// the outside: a controller has children as well as a root job, and an
/// `externalSetState` belongs to no job at all. [job] is that answer, and
/// [revision] puts the changes in order — a hook may change the state
/// again from inside this one, and the nested change carries a higher
/// number.
@immutable
final class SoloTransition<S extends Object> {
  /// The state before the change.
  final S previous;

  /// The state after it.
  final S current;

  /// The job whose `emit` made the change, or `null` for an
  /// `externalSetState`. A child of the running job is that child, not the
  /// root it belongs to.
  final Job<Object?>? job;

  /// How many changes this controller has made, this one included.
  ///
  /// It only ever grows, and it grows by one per change, so two
  /// transitions of one controller are ordered by it even when the second
  /// happened from inside a hook of the first.
  final int revision;

  /// Creates a transition; the engine makes these, a domain reads them.
  const SoloTransition({
    required this.previous,
    required this.current,
    required this.job,
    required this.revision,
  });

  /// Whether the change came from outside the jobs, through
  /// `externalSetState`.
  bool get isExternal => job == null;

  @override
  String toString() {
    final source = job == null ? 'external' : '$job';

    return 'SoloTransition(#$revision, $source: $previous -> $current)';
  }
}
