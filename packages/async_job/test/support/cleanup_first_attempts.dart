// The first attempts of `doc/cleanup.md`, verbatim. Each differs from the
// version that works by a word or a line, so they live apart from the
// answers in `cleanup_page.dart`: a line of an answer turned into the line
// of its first attempt would still be found in a file that held both.
// `connect` of "A resource that travels" stands here, because the page
// shows it in the first attempt; the later versions of `ready` take it.
import 'package:async_job/async_job.dart';

import 'cleanup_stubs.dart';

Future<Database> sameCallback(JobContext ctx) async {
  // ignore: unused_local_variable
  final lock = await ctx.join(Lock.acquire, discard: (lock) => lock.release());
  final database = await ctx.join(
    Database.open,
    discard: (database) => database.close(),
  );

  return database;
}

DeferredJob<Database> connecting() {
  final connect = Job.deferred<Database>(
    key: 'connect',
    (ctx) => ctx.wait(Database.open, discard: (db) => db.close()),
  );
  return connect;
}

DeferredJob<Database> unregistered(Job<Database> connect) {
  final ready = Job.deferred<Database>((ctx) async {
    final database = await ctx.run(connect);
    // ignore: unnecessary_lambdas
    await ctx.join(() => database.migrate());

    return database;
  });
  return ready;
}

Future<void> unregisteringAfter(JobContext ctx) async {
  final removeDisposer = ctx.onDispose(cursor.close);
  // ignore: unnecessary_lambdas
  await ctx.join(() => cursor.readAll()); // closes it at the end
  removeDisposer();
}
