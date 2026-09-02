import 'package:solo/solo.dart';

/// Collects an ordered journal of engine events.
final class JournalObserver extends SoloObserver {
  final lines = <String>[];
  final created = <SoloBase<Object>>[];

  /// Returns the lines collected so far and clears the journal.
  List<String> take() {
    final taken = lines.toList();
    lines.clear();
    return taken;
  }

  static String _label(Job<Object?> job) {
    final indent = job.level == 0 ? '' : '${'>' * job.level} ';
    final description = job.describe();
    final key = job.key is Enum ? (job.key! as Enum).name : '${job.key}';
    final name = description.isEmpty ? key : '$key: $description';
    return '$indent[$name]';
  }

  @override
  void onCreate(SoloBase<Object> solo) => created.add(solo);

  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) =>
      lines.add('${_label(job)} started');

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) {
    final outcome = job.outcome;
    final verb =
        outcome is Cancelled && !outcome.started ? 'dropped' : 'finished';
    lines.add('${_label(job)} $verb $outcome');
  }

  @override
  void onError(
    SoloBase<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) =>
      lines.add('${_label(job)} error $error');

  @override
  void onLog(SoloBase<Object> solo, Job<Object?> job, String message) =>
      lines.add('${_label(job)} log $message');

  @override
  void onChange(SoloBase<Object> solo, Object previous, Object current) =>
      lines.add('state: $current');

  @override
  void onClose(SoloBase<Object> solo) => lines.add('closed');
}
