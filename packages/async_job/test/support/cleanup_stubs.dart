// What the code of `doc/cleanup.md` takes for granted: the lock, the
// database, the cursor and the sink. Each test sets the stage first, so a
// stub can take its time, fail, or wait for a lock somebody else holds.
import 'dart:async';

import 'delay.dart';

/// How the stubs behave in the test at hand, and what they saw.
final class Stage {
  final trace = <String>[];

  int openTake = 10;
  Error? openError;
  int migrateTake = 10;
  Error? migrateError;
  int readTake = 10;

  /// Whether there is one lock for everybody: a second `acquire` waits
  /// until the holder releases it.
  bool exclusive = false;
  bool _held = false;
  final _waiting = <Completer<void>>[];

  final sink = <String>[];
  final cursor = Cursor();
}

Stage stage = Stage();

/// A lock, taken in a millisecond.
final class Lock {
  static Future<Lock> acquire() async {
    await delay(1);
    while (stage.exclusive && stage._held) {
      final turn = Completer<void>();
      stage._waiting.add(turn);
      stage.trace.add('lock waits');
      await turn.future;
    }
    stage
      .._held = true
      ..trace.add('lock acquired');
    return Lock();
  }

  Future<void> release() async {
    stage
      ..trace.add('lock released')
      .._held = false;
    if (stage._waiting.isNotEmpty) {
      stage._waiting.removeAt(0).complete();
    }
  }
}

/// A database that opens and migrates in its own time and counts how many
/// times it was closed.
final class Database {
  final String name;
  int closes = 0;

  Database([this.name = 'db']);

  static Future<Database> open() async {
    await delay(stage.openTake);
    if (stage.openError case final error?) {
      throw error;
    }
    stage.trace.add('db opened');
    return Database();
  }

  bool get closed => closes > 0;

  Future<void> migrate() async {
    await delay(stage.migrateTake);
    if (stage.migrateError case final error?) {
      stage.trace.add('$name migration failed');
      throw error;
    }
    stage.trace.add('$name migrated');
  }

  Future<void> close() async {
    closes += 1;
    stage.trace.add('$name closed');
  }
}

/// A cursor that `readAll` closes once it has read everything.
final class Cursor {
  int closes = 0;

  Future<void> readAll() async {
    await delay(stage.readTake);
    stage.trace.add('cursor read');
    await close();
  }

  Future<void> close() async {
    closes += 1;
    stage.trace.add('cursor closed');
  }
}

/// The cursor of the page: the one of the stage at hand.
Cursor get cursor => stage.cursor;

/// The sink of the page: what the buffer is flushed into.
List<String> get sink => stage.sink;
