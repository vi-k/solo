import 'package:jobs/jobs.dart';

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

  Future<void> markReady(CancelToken stop) async {}

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
    // Not told to stop at all: the token stays untouched until this is over.
    await ctx.uncancellable(() => database.markReady(stop));

    return database;
  });

  // Somebody changed their mind while the database was opening.
  await Future<void>.delayed(const Duration(milliseconds: 10));
  await job.cancel();

  final outcome = await job.done; // Cancelled(manual)
  print(outcome);
}
