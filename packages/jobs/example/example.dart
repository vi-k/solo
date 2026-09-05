import 'package:jobs/jobs.dart';

/// A resource that takes a while to open and must be closed.
class Database {
  static Future<Database> open() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return Database();
  }

  bool isOpen = true;

  Future<void> migrate() async {}

  Future<void> close() async {
    isOpen = false;
    print('database closed');
  }
}

Future<void> main() async {
  // The body never awaits anything by itself: every call goes through the
  // context, and the member says what a cancellation does to it.
  final job = Job<Database>(
    key: 'open',
    // The value the body returns after a cancellation has already arrived
    // still gets released.
    ifCancelled: (database) => database.close(),
    (ctx) async {
      // `join` stays with the call: an open database is not abandoned
      // halfway.
      final database = await ctx.join(
        Database.open,
        ifCancelled: (database) => database.close(),
      );
      await ctx.wait(database.migrate);

      return database;
    },
  );

  // Somebody changed their mind while the database was opening.
  await Future<void>.delayed(const Duration(milliseconds: 10));
  job.cancel().ignore();

  final outcome = await job.done;
  print(outcome); // Cancelled(manual)
}
