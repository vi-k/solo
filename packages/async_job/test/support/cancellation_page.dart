// The code of `doc/cancellation.md`, verbatim: the n-th block of the page is
// the n-th region of this file, between `// #docregion` and
// `// #enddocregion`, and `cancellation_rakes_test.dart` runs it. Around a
// region stands what the page leaves to the reader: the job the block goes
// into.
import 'package:async_job/async_job.dart';

import 'cancellation_stubs.dart';

/// The opening example. The read takes 0-10 ms, the migration 10-40, the
/// section 40-60.
Job<void> opening() {
  // #docregion
  final job = Job<void>((ctx) async {
    // The database client's own stop signal, cancelled with the job.
    final stop = CancelToken();
    ctx.onCancel(stop.cancel);

    // The wait ends at once; the read goes on, and its value is dropped.
    final rows = await ctx.abandonable(database.readAll);

    // Waited for until the migration ends or stops at the token, and
    // only then does the job give up.
    await ctx.join(() => database.migrate(stop));

    // The cancellation waits for the whole step, and the child it
    // runs is not cancelled; the next checkpoint throws it.
    await ctx.uncancellable(() async {
      await database.writeVersion();
      await ctx.run(database.readyFlag());
    });

    // Nothing to wrap between the steps of a calculation.
    ctx.check();
    use(rows);
  });
  // #enddocregion
  return job;
}

/// The first attempt of "Stopping the operation".
Job<Database> waitForTheMigration() {
  // #docregion
  final job = Job<Database>(observer: printing, (ctx) async {
    final database = await ctx.join(
      Database.open,
      discard: (database) => database.close(),
    );
    final stop = CancelToken();

    await ctx.abandonable(() => database.migrate(stop));

    return database;
  });
  // #enddocregion
  return job;
}

/// The second attempt: the job of the first, with `join` in place of
/// `abandonable`.
Job<Database> joinTheMigration() {
  final job = Job<Database>(observer: printing, (ctx) async {
    final database = await ctx.join(
      Database.open,
      discard: (database) => database.close(),
    );
    final stop = CancelToken();

    // #docregion
    await ctx.join(() => database.migrate(stop));
    // #enddocregion

    return database;
  });
  return job;
}

/// "A token through `onCancel`": the job of the first attempt, with the
/// token wired and `join` in place of `abandonable`.
Job<Database> stopTheMigration() {
  final job = Job<Database>(observer: printing, (ctx) async {
    final database = await ctx.join(
      Database.open,
      discard: (database) => database.close(),
    );
    // #docregion
    final stop = CancelToken();
    ctx.onCancel(stop.cancel);

    await ctx.join(() => database.migrate(stop));
    // #enddocregion

    return database;
  });
  return job;
}

/// A stop that takes time, run as work the job does not wait for.
Job<void> stopTheDevice() {
  final job = Job<void>(observer: printing, (ctx) async {
    ctx.onDispose(device.release);
    // #docregion
    // ignore: cascade_invocations
    ctx.onCancel(() => ctx.unattended(device.stop));
    // #enddocregion
    // The job records until it is cancelled and walks away from the
    // recording: nothing here waits for the stop.
    await ctx.abandonable(device.record);
  });
  return job;
}

/// The job that ends only after the device has stopped.
Job<void> waitForTheDevice() {
  final job = Job<void>(observer: printing, (ctx) async {
    ctx.onDispose(device.release);
    // #docregion
    // ignore: cascade_invocations
    ctx.onCancel(() => ctx.unattended(device.stop));
    await ctx.join(device.record);
    // #enddocregion
  });
  return job;
}

/// The first attempt of "A step that must finish".
Job<void> twoJoins() {
  final job = Job<void>(observer: printing, (ctx) async {
    // #docregion
    await ctx.join(database.writeVersion);
    await ctx.join(database.writeReadyFlag);
    // #enddocregion
  });
  return job;
}

/// "One `join` for the step".
Job<void> oneJoinForTheStep() {
  final job = Job<void>(observer: printing, (ctx) async {
    // #docregion
    await ctx.join(() async {
      await database.writeVersion();
      await database.writeReadyFlag();
    });
    // #enddocregion
  });
  return job;
}

/// The first attempt of "A step that runs a child".
Job<void> oneJoinWithAChild() {
  final job = Job<void>(observer: printing, (ctx) async {
    // #docregion
    await ctx.join(() async {
      await database.writeVersion();
      await ctx.run(database.readyFlag());
    });
    // #enddocregion
  });
  return job;
}

/// "Holding the cancellation back".
Job<void> holdTheCancellationBack() {
  final job = Job<void>(observer: printing, (ctx) async {
    // #docregion
    await ctx.uncancellable(() async {
      await database.writeVersion();
      await ctx.run(database.readyFlag());
    });
    // #enddocregion
  });
  return job;
}

/// The first attempt of "Catching errors of the operation", with the token
/// wired through `onCancel` as in "Stopping the operation".
Job<void> catchCancelledFirst() {
  final job = Job<void>(observer: printing, (ctx) async {
    final stop = CancelToken();
    ctx.onCancel(stop.cancel);

    // #docregion
    try {
      await ctx.join(() => database.migrate(stop));
    } on Cancelled {
      rethrow;
    } on Exception catch (error) {
      ctx.log('migration failed: $error');
    }
    await ctx.join(() async {
      await database.writeVersion();
      await database.writeReadyFlag();
    });
    // #enddocregion
  });
  return job;
}

/// "Asking the job": the job of the first attempt, with this `try` in
/// place of its own.
Job<void> askTheJob() {
  final job = Job<void>(observer: printing, (ctx) async {
    final stop = CancelToken();
    ctx.onCancel(stop.cancel);

    // #docregion
    try {
      await ctx.join(() => database.migrate(stop));
    } on Exception catch (error) {
      ctx.check();
      // ignore: cascade_invocations
      ctx.log('migration failed: $error');
    }
    // #enddocregion
    await ctx.join(() async {
      await database.writeVersion();
      await database.writeReadyFlag();
    });
  });
  return job;
}

/// A page with an optional thumbnail, which tells a thumbnail that was
/// cancelled from one that failed.
Job<String> pageWithAThumbnail() {
  final job = Job<String>(observer: printing, (ctx) async {
    // #docregion
    final thumbnail = Job.deferred<String>(renderThumbnail);
    try {
      return 'page with ${await ctx.run(thumbnail)}';
    } on Exception catch (error) {
      ctx.check();
      if (error is! Cancelled) ctx.log('thumbnail failed: $error');
      return 'page without a thumbnail';
    }
    // #enddocregion
  });
  return job;
}

/// The first attempt of "Letting time pass": a read every second, with a
/// plain delay between two reads.
Job<void> plainDelay() {
  // #docregion
  final job = Job<void>((ctx) async {
    while (true) {
      use(await ctx.abandonable(database.readAll));
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  });
  // #enddocregion
  return job;
}

/// The second attempt: the job of the first, with the delay under
/// `abandonable`.
Job<void> delayUnderAbandonable() {
  final job = Job<void>((ctx) async {
    while (true) {
      use(await ctx.abandonable(database.readAll));
      // #docregion
      await ctx.abandonable(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      // #enddocregion
    }
  });
  return job;
}

/// "A pause of the job": the same job, with `ctx.pause` in that place.
Job<void> pauseOfTheJob() {
  final job = Job<void>((ctx) async {
    while (true) {
      use(await ctx.abandonable(database.readAll));
      // #docregion
      await ctx.pause(const Duration(seconds: 1));
      // #enddocregion
    }
  });
  return job;
}
