// What the code of `doc/observing.md` takes for granted: the database, the
// operations it waits for, the token that stops them and the analytics it
// sends. Each test sets the
// stage first, so the same open can succeed or fail.
import 'delay.dart';

/// How the stubs behave in the test at hand.
final class Stage {
  /// Whether `Database.open` fails.
  bool databaseLocked = false;

  /// What `migrate` throws.
  Object migrationError = StateError('migration failed');
}

/// The stage of the test at hand.
Stage stage = Stage();

/// Loads a number in 10 ms.
Future<int> load() async {
  await delay(10);
  return 3;
}

/// Opens in 20 ms, or fails then when the stage locks it.
final class Database {
  /// Opens the database.
  static Future<Database> open() async {
    await delay(20);
    if (stage.databaseLocked) {
      throw StateError('database locked');
    }
    return Database();
  }

  /// Closes the database.
  Future<void> close() async {}

  /// Migrates the database in 40 ms, and stops at 20 ms with
  /// [DatabaseStopped] if [stop] has been cancelled by then.
  Future<void> migrate(CancelToken stop) async {
    await delay(20);
    if (stop.isCancelled) {
      throw const DatabaseStopped();
    }
    await delay(20);
  }
}

/// The database the migration runs on.
final database = Database();

/// The database client's own stop signal.
final class CancelToken {
  var _cancelled = false;

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Tells the operation that holds the token to stop.
  void cancel() => _cancelled = true;
}

/// How the migration stops when its token is cancelled.
final class DatabaseStopped implements Exception {
  /// Creates the error.
  const DatabaseStopped();

  @override
  String toString() => 'DatabaseStopped';
}

/// Migrates the database and fails with the error of the stage.
Future<void> migrate() async {
  await delay(10);
  // ignore: only_throw_errors
  throw stage.migrationError;
}

/// The database errors an observer of the page knows.
final class DatabaseException implements Exception {
  /// Creates the error.
  const DatabaseException();

  @override
  String toString() => 'DatabaseException';
}

/// Fails with a database error at 20 ms.
Future<void> saveDraft() async {
  await delay(20);
  throw const DatabaseException();
}

/// Fails with another error at 10 ms.
Future<void> sendAnalytics() async {
  await delay(10);
  throw StateError('analytics offline');
}

/// Analytics that is offline.
final class Analytics {
  /// Fails to send [event] at 10 ms.
  Future<void> send(String event) async {
    await delay(10);
    throw StateError('analytics offline');
  }
}

/// The analytics of the page.
final analytics = Analytics();

/// The error of the page that a body throws in place of what it caught.
final class AppException implements Exception {
  final Object cause;

  const AppException(this.cause);

  @override
  String toString() => 'AppException($cause)';
}
