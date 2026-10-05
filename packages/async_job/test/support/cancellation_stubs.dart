// What the code of `doc/cancellation.md` takes for granted: the database and
// its stop signal, the device, the thumbnail and the observer of the page's
// jobs. Each test sets the stage first, so one stub can fail or be
// cancelled; what the stubs say goes to [printed].
import 'dart:async';

import 'package:async_job/async_job.dart';

import 'delay.dart';

/// What the database, the device, the observer and the code around the
/// jobs print, in the order it happens.
final printed = <String>[];

/// Prints [line] to [printed].
void say(String line) => printed.add(line);

/// How the stubs behave in the test at hand.
final class Stage {
  /// Whether the migration fails on its own, before its first step.
  bool migrationFails = false;

  /// Whether [Device.stop] fails instead of stopping the device.
  bool stopFails = false;

  /// What [renderThumbnail] does instead of taking its 20 ms.
  Thumbnail thumbnail = Thumbnail.renders;
}

/// The stage of the test at hand.
Stage stage = Stage();

/// How long a step of the migration takes: the page's "three steps of
/// 10 ms".
const stepMs = 10;

/// The stop signal of the database client, the kind `onCancel` is for.
final class CancelToken {
  bool cancelled = false;

  void cancel() => cancelled = true;
}

/// How the database client stops when its token is cancelled.
final class DatabaseStopped implements Exception {
  const DatabaseStopped();

  @override
  String toString() => 'DatabaseStopped';
}

final class Database {
  bool closed = false;

  /// The jobs [readyFlag] has made, for a test to see what became of them.
  final flagJobs = <Job<void>>[];

  static Future<Database> open() async => Database();

  /// A read of 10 ms, the kind a job may walk away from.
  Future<List<String>> readAll() async {
    await delay(10);
    say('rows read');
    return ['row'];
  }

  /// Three steps of [stepMs] each; the token is read before every one.
  Future<void> migrate(CancelToken stop) async {
    if (stage.migrationFails) {
      throw const FormatException('bad schema');
    }
    for (var step = 1; step <= 3; step++) {
      if (stop.cancelled) {
        say('migration stopped');
        throw const DatabaseStopped();
      }
      await delay(stepMs);
      say(closed ? 'step $step on a closed database' : 'step $step');
    }
  }

  /// The first write of marking the database ready, 10 ms.
  Future<void> writeVersion() async {
    await delay(10);
    say('version written');
  }

  /// The second write, 10 ms.
  Future<void> writeReadyFlag() async {
    await delay(10);
    say('ready flag written');
  }

  /// The second write as a job of its own, for a step that runs it as a
  /// child.
  Job<void> readyFlag() {
    final job = Job.deferred((ctx) => ctx.join(writeReadyFlag));
    flagJobs.add(job);
    return job;
  }

  Future<void> close() async {
    closed = true;
    say('database closed');
  }
}

/// The database of the sections that do not open one.
Database database = Database();

/// A device that records until it has stopped; a stop takes 10 ms.
final class Device {
  // Made by the first recording, inside the job: a future made outside the
  // zone of `fakeAsync` would complete where its timers never run.
  Completer<void>? _stopped;

  /// Records until the device has stopped.
  Future<void> record() => (_stopped ??= Completer<void>()).future;

  Future<void> stop() async {
    await delay(10);
    if (stage.stopFails) {
      throw StateError('device did not stop');
    }
    say('device stopped');
    _stopped?.complete();
  }

  void release() => say('device released');
}

/// The device of the page.
Device device = Device();

/// An observer that prints what reaches it.
final class PrintingObserver extends JobObserver {
  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      say('onError: $error');

  @override
  void onLog(Job<Object?> job, Object? message) => say('log: $message');
}

/// The observer of every job the page shows after its legend.
final printing = PrintingObserver();

void use(List<String> rows) => say('rows used');

/// What [renderThumbnail] does instead of taking its 20 ms: nothing, fail,
/// or be cancelled 5 ms in, directly and not through its parent.
enum Thumbnail { renders, fails, isCancelled }

Future<String> renderThumbnail(JobContext ctx) async {
  switch (stage.thumbnail) {
    case Thumbnail.renders:
      break;
    case Thumbnail.fails:
      throw const FormatException('bad image');
    case Thumbnail.isCancelled:
      Timer(const Duration(milliseconds: 5), ctx.job.cancel);
  }
  await ctx.abandonable(() => delay(20));
  return 'thumbnail';
}
