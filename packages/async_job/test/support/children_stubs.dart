// What the code of `doc/children.md` takes for granted: the sources, the
// operations and the stream it reads. Each test sets the stage first, so
// one stub can open in time, fail or give the branch up.
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
  int warmTake = 30;
  Object? warmError;

  bool lockHeld = false;
  final lockQueue = <Completer<void>>[];

  // ignore: close_sinks
  final messages = StreamController<String>();
}

Stage stage = Stage();

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

  void close() => stage.trace.add('$name closed');
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

Future<int> load() async => 21;

Future<void> report(int rows) async {
  await delay(80);
  stage.trace.add('reported $rows');
}

Stream<String> get events => stage.messages.stream;

Stream<String> get messages => stage.messages.stream;

Future<void> save(String event) async => stage.trace.add('saved $event');

/// The store a message is saved to in two steps.
final class Store {
  Future<void> saveBody(String message) => _step('$message: body');

  Future<void> saveAttachments(String message) =>
      _step('$message: attachments');

  Future<void> _step(String what) async {
    stage.trace.add('$what begins');
    await delay(stage.stepTake);
    stage.trace.add('$what saved');
  }
}

final store = Store();

Future<String> loadText() async => '21';

Future<void> saveNumber(int number) async =>
    stage.trace.add('saved number $number');

/// What a branch throws to give itself up.
Cancelled givenUp() => Cancelled.by(
      reason: const ManualCancelReason(),
      started: true,
      stackTrace: StackTrace.current,
    );
