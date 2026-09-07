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
    // The body returned a database after the cancellation had already
    // arrived: close it instead of dropping it.
    ifCancelled: (database) => database.close(),
    (ctx) async {
      // `join` stays with the call: a database half-opened is not left
      // behind, and `discard` closes the one nobody wants any more.
      final database = await ctx.join(
        Database.open,
        discard: (database) => database.close(),
      );

      // From here the body owns it, so it closes it on the way out.
      try {
        await ctx.join(database.migrate);
        await ctx.uncancellable(database.markReady);
      } on Cancelled {
        await database.close();
        rethrow;
      }

      return database;
    },
  );

  // Somebody changed their mind while the database was opening.
  await Future<void>.delayed(const Duration(milliseconds: 10));
  await job.cancel();

  final outcome = await job.done; // Cancelled(manual)
  print(outcome);
}
