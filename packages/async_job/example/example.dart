import 'package:async_job/async_job.dart';

/// The stop signal a database client of its own takes, the kind
/// [JobContext.onCancel] is for. It is not a type of `async_job`.
class CancelToken {
  /// Whether [cancel] has been called.
  bool cancelled = false;

  /// Asks the work holding this token to stop.
  void cancel() => cancelled = true;
}

/// A resource that takes a while to open and must be closed.
class Database {
  /// Opens a database, in a tenth of a second.
  static Future<Database> open() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    print('database opened');
    return Database();
  }

  /// Migrates the schema in three steps, and stops between them once [stop]
  /// is cancelled.
  Future<void> migrate(CancelToken stop) async {
    for (var step = 1; step <= 3; step++) {
      if (stop.cancelled) {
        print('migration stopped');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    print('migrated');
  }

  /// Writes the schema version.
  Future<void> writeVersion() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    print('version written');
  }

  /// The ready flag is written by a job of its own, which the last step of
  /// the body runs as a child. It is made with [Job.deferred], so that
  /// `ctx.run` starts it: a job made with `Job(...)` starts on its own, and
  /// `ctx.run` refuses it.
  Job<void> readyFlag() => Job.deferred((ctx) => ctx.join(_writeReadyFlag));

  Future<void> _writeReadyFlag() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    print('ready flag written');
  }

  /// Closes the database.
  Future<void> close() async => print('database closed');

  @override
  String toString() => 'database';
}

/// The job of the Quick start in README.md.
Job<Database> openDatabase() => Job<Database>((ctx) async {
      // `join` stays with the call: a database half-opened is not left
      // behind, and `discard` closes the one nobody wants any more.
      final database = await ctx.join(
        Database.open,
        discard: (database) => database.close(),
      );

      final stop = CancelToken();
      ctx.onCancel(stop.cancel);

      // Told to stop the moment the job is cancelled, and waited for.
      await ctx.join(() => database.migrate(stop));
      // A cancellation waits for the whole step, and the child it runs is
      // started all the same: no version is left without its flag.
      await ctx.uncancellable(() async {
        await database.writeVersion();
        await ctx.run(database.readyFlag());
      });

      return database;
    });

/// Runs the job of the Quick start four times: once to the end, and then
/// cancelled at each of its steps.
Future<void> main() async {
  print('Nobody changes their mind:');
  final outcome = await openDatabase().done;
  print(outcome);
  if (outcome case Done(value: final database)) {
    // With `Done`, the database is the caller's to close.
    await database.close();
  }

  print('\nSomebody changes their mind while the database opens:');
  await changeOfMind(const Duration(milliseconds: 50));

  print('\nWhile it migrates, the token stops the migration:');
  await changeOfMind(const Duration(milliseconds: 250));

  // The section holds the cancellation: the version and its flag are
  // written, and the body returns the database. The job still ends
  // `Cancelled`, and `discard` closes the database.
  print('\nWhile the version is written, the step ends whole:');
  await changeOfMind(const Duration(milliseconds: 450));
}

/// Starts the job and cancels it once [after] has passed.
Future<void> changeOfMind(Duration after) async {
  final job = openDatabase();
  await Future<void>.delayed(after);
  await job.cancel();
  print(job.outcome);
}
