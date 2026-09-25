import 'package:async_job/async_job.dart';

/// Collects an ordered journal of what happens to a job.
///
/// The format is the one `solo` uses for its own journal, so both suites
/// read the same way: `finished` and `dropped` carry no colon.
///
/// It watches and answers for nothing unless [answers] says so: by default
/// an error no outcome carries goes on to the zone the job was created in,
/// as it would with no observer.
final class JobJournal extends JobObserver {
  final lines = <String>[];

  /// Whether the journal answers for the errors it records, keeping them
  /// out of the zone. For a test whose subject is not where they go.
  final bool answers;

  JobJournal({this.answers = false});

  /// Returns the lines collected so far and clears the journal.
  List<String> take() {
    final taken = lines.toList();
    lines.clear();
    return taken;
  }

  static String _label(Job<Object?> job) {
    final indent = job.level == 0 ? '' : '${'>' * job.level} ';
    final description = job.describe();
    final name =
        description.isEmpty ? '${job.key}' : '${job.key}: $description';
    return '$indent[$name]';
  }

  @override
  void onStart(Job<Object?> job) => lines.add('${_label(job)} started');

  @override
  void onFinish(Job<Object?> job) {
    final outcome = job.outcome;
    final verb =
        outcome is Cancelled && !outcome.started ? 'dropped' : 'finished';
    lines.add('${_label(job)} $verb $outcome');
  }

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      lines.add('${_label(job)} error $error');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    if (!answers) {
      super.onUnanswered(job, error, stackTrace);
    }
  }

  @override
  void onLog(Job<Object?> job, Object? message) =>
      lines.add('${_label(job)} log $message');
}
