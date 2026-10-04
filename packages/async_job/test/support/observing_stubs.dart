// What the code of `doc/observing.md` takes for granted: the database, the
// operations it waits for and the analytics it sends. Each test sets the
// stage first, so the same open can succeed or fail.
import 'delay.dart';

/// How the stubs behave in the test at hand.
final class Stage {
  /// Whether `Database.open` fails.
  bool databaseLocked = false;

  /// What `migrate` throws.
  Object migrationError = StateError('migration failed');

  /// What `showError` was given.
  final List<Object> shown = [];
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
}

/// Shows [error] to the user for 30 ms.
Future<void> showError(Object error) {
  stage.shown.add(error);
  return delay(30);
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
