// What the code of `doc/cleanup.md` and `doc/cleanup-rules.md` takes for
// granted: the lock, the database, the cursor and the sink. Each test sets
// the stage first, so a stub can take its time, fail, or wait for a lock
// somebody else holds.
import 'dart:async';

import 'delay.dart';

/// How the stubs behave in the test at hand, and what they saw.
final class Stage {
  final trace = <String>[];

  int openTake = 10;
  Error? openError;
  int migrateTake = 10;
  Exception? migrateError;
  int readTake = 10;
  int commitTake = 10;

  /// Whether the schema of the database is current, as `isCurrent` says.
  bool schemaCurrent = true;

  /// How long a close takes: at once by default.
  int closeTake = 0;

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

  Database([this.name = 'database']);

  /// The database [open] opened last.
  static Database? lastOpened;

  static Future<Database> open() async {
    await delay(stage.openTake);
    if (stage.openError case final error?) {
      throw error;
    }
    stage.trace.add('database opened');
    return lastOpened = Database();
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

  Future<bool> isCurrent() async {
    await delay(5);
    return stage.schemaCurrent;
  }

  Future<void> warmCache() async {
    await delay(10);
    stage.trace.add('cache warmed');
  }

  Future<void> close() async {
    closes += 1;
    if (stage.closeTake > 0) {
      await delay(stage.closeTake);
    }
    stage.trace.add('$name closed');
  }

  @override
  String toString() => name;
}

/// The error of a migration that fails.
final class MigrationFailed implements Exception {
  @override
  String toString() => 'MigrationFailed';
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

/// A transaction that commits in its own time. A rollback after the commit
/// would undo what the commit handed over.
final class Transaction {
  static Future<Transaction> begin() async {
    await delay(1);
    stage.trace.add('transaction begun');
    return Transaction();
  }

  Future<void> commit() async {
    await delay(stage.commitTake);
    stage.trace.add('transaction committed');
  }

  Future<void> rollback() async {
    stage.trace.add('transaction rolled back');
  }
}

/// The cursor of the page: the one of the stage at hand.
Cursor get cursor => stage.cursor;

/// The sink of the page: what the buffer is flushed into.
List<String> get sink => stage.sink;
