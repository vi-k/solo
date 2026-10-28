import 'package:async_job/async_job.dart';

// README: begin
Future<void> main() async {
  final job = Job<void>((ctx) async {
    // Checked before the call and again before the value comes back,
    // and the database is closed whichever way the job ends.
    final db = await ctx.join(Database.open, dispose: (db) => db.close());
    use(await ctx.join(db.readAll));
  });

  // Somebody left the screen while the read was in flight.
  await Future<void>.delayed(const Duration(milliseconds: 50));

  // Waits for the body, its children and its cleanup.
  await job.cancel();
  print(job.outcome); // Cancelled(manual)
}
// README: end

/// The database of "Quick start" in README.md: it prints when it opens and
/// when it closes.
class Database {
  /// Opens a database, in a fiftieth of a second.
  static Future<Database> open() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    print('database opened');
    return Database();
  }

  /// Reads the rows, in a tenth of a second.
  Future<List<String>> readAll() => Future<List<String>>.delayed(
    const Duration(milliseconds: 100),
    () => const ['row'],
  );

  /// Closes the database.
  Future<void> close() async => print('database closed');
}

/// What the job does with the rows; the cancellation keeps them from it.
void use(List<String> rows) => print('read ${rows.length} rows');
