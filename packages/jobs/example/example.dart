import 'package:jobs/jobs.dart';

/// A resource that takes a while to open and must be closed.
class Database {
  static Future<Database> open() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return Database();
  }

  bool isOpen = true;

  Future<void> migrate() async {}

  Future<void> markReady() async {}

  Future<void> close() async {
    isOpen = false;
    print('database closed');
  }
}

/// The Quick start of README.md, with a fake [Database] around it.
Future<void> main() async {
  final job = Job<Database>(
    // The value the body returns after a cancellation has already arrived
    // still gets released.
    ifCancelled: (database) => database.close(),
    (ctx) async {
      // `join` stays with the call: an open database is not abandoned
      // halfway, and its `ifCancelled` closes what the wait no longer
      // needs.
      final database = await ctx.join(
        Database.open,
        ifCancelled: (database) => database.close(),
      );
      await ctx.wait(database.migrate);
      await ctx.uncancellable(database.markReady);

      return database;
    },
  );

  // Somebody changed their mind while the database was opening.
  await Future<void>.delayed(const Duration(milliseconds: 10));
  job.cancel().ignore();

  final outcome = await job.done;
  print(outcome); // Cancelled(manual)
}
