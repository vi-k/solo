// What the code of `doc/children.md`, `doc/groups.md` and `doc/chains.md`
// takes for granted: the sources, the operations and the stream it reads.
// Each test sets the stage first, so one stub can open in time, fail or make
// the branch cancel itself.
import 'dart:async';

import 'package:async_job/async_job.dart';

import 'delay.dart';

/// How the stubs behave in the test at hand, and what they saw.
final class Stage {
  final trace = <String>[];

  int rowsTake = 5;
  Object? rowsError;
  int imagesTake = 10;
  Object? imagesError;
  int archiveTake = 50;
  Object? archiveError;
  int stepTake = 20;
  Object? stepError;
  int warmTake = 30;
  Object? warmError;

  /// The name of the source whose `close` throws.
  String? closeFails;

  /// How long `load` takes; none by default.
  int loadTake = 0;

  /// How long `loadText` takes; none by default.
  int textTake = 0;

  bool lockHeld = false;
  final lockQueue = <Completer<void>>[];

  // An `onCancel` with a future of the zone it is called in: `await for`
  // awaits the cancellation of its subscription, and the future a controller
  // without one hands back belongs to the root zone, which fake time never
  // reaches.
  // ignore: close_sinks
  final messages = StreamController<String>(onCancel: () async {});
}

Stage stage = Stage();

/// The observer of `doc/observing.md`: it prints what a body logs and how a
/// job ended.
final class Log extends JobObserver {
  @override
  void onFinish(Job<Object?> job) => print('$job: ${job.outcome}');

  @override
  void onLog(Job<Object?> job, Object? message) {
    final data = message is Object? Function() ? message() : message;
    print('$job: $data');
  }
}

/// One lock for the whole stage: a second taker waits for the release.
final class Lock {
  static Future<Lock> acquire() async {
    while (stage.lockHeld) {
      final turn = Completer<void>();
      stage.lockQueue.add(turn);
      stage.trace.add('lock waits');
      await turn.future;
    }
    stage.lockHeld = true;
    stage.trace.add('lock acquired');
    return Lock();
  }

  void release() {
    stage.lockHeld = false;
    stage.trace.add('lock released');
    if (stage.lockQueue.isNotEmpty) stage.lockQueue.removeAt(0).complete();
  }
}

/// A resource a branch opens; closing it is written to the trace.
final class Source {
  final String name;

  Source(this.name);

  void close() {
    if (stage.closeFails == name) {
      stage.trace.add('$name close failed');
      throw StateError('$name close failed');
    }
    stage.trace.add('$name closed');
  }
}

/// A cache a branch keeps for itself.
final class Cache {
  void close() => stage.trace.add('cache closed');

  Future<void> warm(Source rows) async => stage.trace.add('cache warmed');
}

Future<Source> _open(String name, int take, Object? error) async {
  await delay(take);
  if (error != null) {
    // ignore: only_throw_errors
    throw error;
  }
  return Source(name);
}

Future<Source> openRows() => _open('rows', stage.rowsTake, stage.rowsError);

Future<Source> openImages() =>
    _open('images', stage.imagesTake, stage.imagesError);

Future<void> writeArchive(List<Source> sources) async {
  await delay(stage.archiveTake);
  if (stage.archiveError case final error?) {
    // ignore: only_throw_errors
    throw error;
  }
  stage.trace.add('archive of ${sources.length}');
}

Future<Cache> openCache() async => Cache();

Future<int> loadRows() async => 21;

Future<int> loadExtra() async => 1;

Future<void> warmCache() async {
  await delay(stage.warmTake);
  if (stage.warmError case final error?) {
    // ignore: only_throw_errors
    throw error;
  }
  stage.trace.add('cache warm');
}

Future<int> load() async {
  if (stage.loadTake > 0) await delay(stage.loadTake);
  return 21;
}

Future<void> report(int rows) async {
  await delay(80);
  stage.trace.add('reported $rows');
}

Stream<String> get events => stage.messages.stream;

Stream<String> get messages => stage.messages.stream;

Future<void> save(String event) async => stage.trace.add('saved $event');

/// A source whose connection takes time to shut down.
final class Feed {
  final _disconnected = Completer<void>();
  var _disconnecting = false;
  // ignore: close_sinks
  late final _controller = StreamController<String>(onCancel: close);

  Stream<String> get messages => _controller.stream;

  /// Shuts the connection down; completes when it is down.
  Future<void> close() {
    if (!_disconnecting) {
      _disconnecting = true;
      delay(30).then((_) {
        stage.trace.add('feed disconnected');
        _disconnected.complete();
      });
    }
    return _disconnected.future;
  }
}

/// What a message is written through; closing it is written to the trace.
final class Draft {
  final String message;

  Draft(this.message);

  Future<void> write() async {
    stage.trace.add('$message: writing');
    await delay(stage.stepTake);
    stage.trace.add('$message: written');
  }

  void close() => stage.trace.add('$message: draft closed');
}

/// The store a message is saved to in two steps.
final class Store {
  Future<Draft> openDraft(String message) async {
    stage.trace.add('$message: draft opened');
    return Draft(message);
  }

  Future<void> saveBody(String message) => _step('$message: body');

  Future<void> saveAttachments(String message) =>
      _step('$message: attachments');

  Future<void> _step(String what) async {
    stage.trace.add('$what begins');
    await delay(stage.stepTake);
    if (stage.stepError case final error?) {
      // ignore: only_throw_errors
      throw error;
    }
    stage.trace.add('$what saved');
  }
}

final store = Store();

Future<String> loadText() async {
  if (stage.textTake > 0) await delay(stage.textTake);
  return '21';
}

Future<void> saveNumber(int number) async =>
    stage.trace.add('saved number $number');

/// What a branch throws to cancel itself.
Cancelled selfCancel() => Cancelled.by(
      reason: const ManualCancelReason(),
      stackTrace: StackTrace.current,
    );

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

/// The database a child migrates.
final class Database {
  /// Three steps of 10 ms; the token is read before every one.
  Future<void> migrate(CancelToken stop) async {
    for (var step = 1; step <= 3; step++) {
      if (stop.cancelled) throw const DatabaseStopped();
      await delay(10);
    }
  }
}

final database = Database();
