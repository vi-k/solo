// The code of `doc/cleanup.md` and `doc/cleanup-rules.md` that works,
// verbatim: the opening example and the version each section settles on.
// The first attempts differ from these by a word or a line, so they live
// in a library of their own, `cleanup_first_attempts.dart`, and the second
// attempt of "A resource that travels" in `cleanup_rakes_test.dart`: a
// line of an answer turned into the line of an attempt would still be
// found in a file that held both. A block that leaves `ctx` to its reader
// takes it as a parameter.
import 'package:async_job/async_job.dart';

import 'cleanup_stubs.dart';

Future<Database> opening(JobContext ctx) async {
  // ignore: unused_local_variable
  final lock = await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
  final database = await ctx.join(
    Database.open,
    discard: (database) => database.close(),
  );

  // ignore: unnecessary_lambdas
  await ctx.join(() => database.migrate());

  return database;
}

Future<Database> keeping(JobContext ctx) async {
  // ignore: unused_local_variable
  final lock = await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
  final database = await ctx.join(
    Database.open,
    discard: (database) => database.close(),
  );

  return database;
}

Future<Database?> closingKeptBack(JobContext ctx) async {
  final database = await ctx.join(
    Database.open,
    discard: (database) => database.close(),
  );

  if (!await ctx.join(database.isCurrent)) {
    ctx.disown(database);
    await database.close();
    return null;
  }

  return database;
}

DeferredJob<Database> onArrival(ChildJob<Database> connect) {
  final ready = Job.deferred<Database>((ctx) async {
    final database = await ctx.run(
      connect,
      discard: (database) => database.close(),
    );
    // ignore: unnecessary_lambdas
    await ctx.join(() => database.migrate());

    return database;
  });
  return ready;
}

/// The buffer of the page, with a row written into it.
Future<void> flushing(JobContext ctx) async {
  final buffer = StringBuffer();
  ctx.onDispose(() => sink.add(buffer.toString()));
  buffer.write('rows');
}

Future<void> unregisteringInside(JobContext ctx) async {
  final removeDisposer = ctx.onDispose(cursor.close);
  await ctx.join(() async {
    await cursor.readAll(); // closes the cursor at the end
    removeDisposer();
  });
}

Future<void> handingOver(JobContext ctx) async {
  final transaction = await ctx.join(
    Transaction.begin,
    dispose: (transaction) => transaction.rollback(),
  );
  await ctx.uncancellable(() async {
    await transaction.commit(); // a bare await, not ctx.join
    ctx.disown(transaction);
  });
}

Job<Database> afterTheReturn() {
  final job = Job<Database>((ctx) async {
    final database = await ctx.join(
      Database.open,
      discard: (database) => database.close(),
    );
    // The body does not wait for the cache; the job does.
    ctx.start(Job.deferred<void>((c) => c.join(database.warmCache)));

    return database;
  });
  return job;
}

Job<Database> plainAwait() {
  final job = Job<Database>((ctx) async {
    final database = await Database.open();
    ctx.onDiscard(database.close);

    return database;
  });
  return job;
}
