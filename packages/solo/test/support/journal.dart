import 'package:solo/solo.dart';

/// Collects an ordered journal of engine events.
final class JournalObserver extends SoloObserver {
  final lines = <String>[];
  final created = <Solo<Object>>[];

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
  void onCreate(Solo<Object> solo) => created.add(solo);

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      lines.add('${_label(job)} started');

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) {
    final outcome = job.outcome;
    final verb =
        outcome is Cancelled && !outcome.started ? 'dropped' : 'finished';
    lines.add('${_label(job)} $verb $outcome');
  }

  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) =>
      lines.add('${_label(job)} error $error');

  @override
  void onLog(Solo<Object> solo, Job<Object?> job, Object? message) =>
      lines.add('${_label(job)} log $message');

  @override
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) =>
      lines.add('state: ${transition.current}');

  @override
  void onClose(Solo<Object> solo) => lines.add('closed');

  /// Answers for an error with nowhere else to go, so the journal above is
  /// the only place it shows up; see `Solo.errorHandler`.
  void answerForErrors(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) {}
}
