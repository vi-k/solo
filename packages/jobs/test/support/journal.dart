import 'package:jobs/jobs.dart';

/// Collects an ordered journal of what happens to a job.
///
/// The format is the one `solo` uses for its own journal, so both suites
/// read the same way: `finished` and `dropped` carry no colon.
final class JobJournal implements JobObserver {
  final lines = <String>[];

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
  void onLog(Job<Object?> job, String message) =>
      lines.add('${_label(job)} log $message');
}
