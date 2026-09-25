import 'package:async_job/async_job.dart';

/// The stop signal a database client of its own takes, the kind
/// [JobContext.onCancel] is for.
class CancelToken {
  bool cancelled = false;

  void cancel() => cancelled = true;
}

/// A resource that takes a while to open and must be closed.
class Database {
  static Future<Database> open() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return Database();
  }

  Future<void> migrate(CancelToken stop) async {}

  Future<void> writeVersion() async {}

  /// The ready flag is written by a job of its own, which the last step of
  /// the body runs as a child.
  Job<void> readyFlag() => Job.deferred((ctx) => ctx.join(_writeReadyFlag));

  Future<void> _writeReadyFlag() async {}

  Future<void> close() async => print('database closed');
}

/// The Quick start of README.md, with a fake [Database] around it.
Future<void> main() async {
  final job = Job<Database>((ctx) async {
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

  // Somebody changed their mind while the database was opening.
  await Future<void>.delayed(const Duration(milliseconds: 10));
  await job.cancel();

  final outcome = await job.done; // Cancelled(manual)
  print(outcome);
}
