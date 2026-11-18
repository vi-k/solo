// The code of `doc/time.md`, verbatim: the n-th block of the page is the n-th
// region of this file, between `// #docregion` and `// #enddocregion`, and
// `time_rakes_test.dart` runs it. Around a region stands what the page leaves
// to the reader: the job the block goes into.
import 'dart:async';

import 'package:async_job/async_job.dart';

import 'cancellation_stubs.dart';

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

/// The limit of "A deadline", the page's "given 15 ms".
const limit = Duration(milliseconds: 15);

/// The first attempt of "A deadline": a timer that cancels the job of "A
/// token through `onCancel`", on the cancellation page, once the limit has
/// run out.
Job<Database> timerOnTheJob() {
  // #docregion
  const limit = Duration(milliseconds: 15);

  final job = Job<Database>(observer: printing, (ctx) async {
    final database = await ctx.join(
      Database.open,
      discard: (database) => database.close(),
    );
    final stop = CancelToken();
    ctx.onCancel(stop.cancel);

    await ctx.join(() => database.migrate(stop));

    return database;
  });
  Timer(limit, job.cancel);
  // #enddocregion
  return job;
}

/// The job of the first attempt, without its timer.
Job<Database> migration() => Job<Database>(observer: printing, (ctx) async {
  final database = await ctx.join(
    Database.open,
    discard: (database) => database.close(),
  );
  final stop = CancelToken();
  ctx.onCancel(stop.cancel);

  await ctx.join(() => database.migrate(stop));

  return database;
});

/// The second attempt: the timer is cancelled when the job ends.
Job<Database> timerCancelledAtTheEnd() {
  final job = migration();
  // #docregion
  final timer = Timer(limit, job.cancel);
  job.done.whenComplete(timer.cancel);
  // #enddocregion
  return job;
}

/// "A deadline of the job": the same job with `timeout`.
Job<Database> deadlineOfTheJob() {
  // #docregion
  final job = Job<Database>(observer: printing, timeout: limit, (ctx) async {
    final database = await ctx.join(
      Database.open,
      discard: (database) => database.close(),
    );
    final stop = CancelToken();
    ctx.onCancel(stop.cancel);

    await ctx.join(() => database.migrate(stop));

    return database;
  });
  // #enddocregion
  return job;
}

/// "A deadline for one step": the thumbnail is a child with a deadline, and
/// the page goes out without it when the deadline runs out.
Job<String> thumbnailWithADeadline() =>
    Job<String>(observer: printing, pageWithAThumbnail);

/// The body of [thumbnailWithADeadline], for a job a test makes itself.
Future<String> pageWithAThumbnail(JobContext ctx) async {
  // #docregion
  final thumbnail = ctx.child<String>(
    renderThumbnail,
    key: 'thumbnail',
    timeout: const Duration(milliseconds: 15),
  );
  try {
    return 'page with ${await ctx.run(thumbnail)}';
  } on Cancelled catch (cancelled) {
    ctx.check();
    if (cancelled.reason case TimeoutCancelReason(:final timeout)) {
      return 'page without a thumbnail after ${timeout.inMilliseconds} ms';
    } else {
      rethrow;
    }
  }
  // #enddocregion
}

/// The bound of "A call that may not come back", the page's "after 15 ms".
const stopBound = Duration(milliseconds: 15);

/// The first attempt of "A call that may not come back": the stop of the
/// device in a `join`, before its release.
Job<void> stopInAJoin() => Job<void>(observer: printing, (ctx) async {
  // #docregion
  ctx.onDispose(device.release);
  await ctx.join(device.stop);
  // #enddocregion
});

/// The second attempt: the stop in a child with a deadline.
Job<void> stopInAChild() => Job<void>(observer: printing, (ctx) async {
  // #docregion
  ctx.onDispose(device.release);
  await ctx.run(
    ctx.child(
      (ctx) => ctx.abandonable(device.stop),
      key: 'stop',
      timeout: const Duration(milliseconds: 15),
    ),
  );
  // #enddocregion
});

/// The second attempt with `join` in the child, which the page names: the
/// deadline of the child waits for the stop as well.
Job<void> stopJoinedInAChild() => Job<void>(observer: printing, (ctx) async {
  ctx.onDispose(device.release);
  await ctx.run(
    ctx.child((ctx) => ctx.join(device.stop), key: 'stop', timeout: stopBound),
  );
});

/// The body of "A timeout inside `join`", for a job a test makes itself.
Future<void> stopWithATimeout(JobContext ctx) async {
  // #docregion
  ctx.onDispose(device.release);
  try {
    await ctx.join(
      () => device.stop().timeout(const Duration(milliseconds: 15)),
    );
  } on TimeoutException {
    ctx.log('the device did not answer');
  }
  // #enddocregion
}

/// "A timeout inside `join`": the stop is waited for whole, for 15 ms at
/// most.
Job<void> stopInATimedJoin() => Job<void>(observer: printing, stopWithATimeout);

/// The answer without its `try`, which the page names: the
/// `TimeoutException` ends the job.
Job<void> stopInATimedJoinUnmapped() =>
    Job<void>(observer: printing, (ctx) async {
      ctx.onDispose(device.release);
      await ctx.join(() => device.stop().timeout(stopBound));
    });

/// The body of the second attempt in an uncancellable section, which the
/// page names, for a job a test makes itself.
Future<void> stopInAHeldChild(JobContext ctx) async {
  ctx.onDispose(device.release);
  await ctx.uncancellable(
    () => ctx.run(
      ctx.child(
        (ctx) => ctx.abandonable(device.stop),
        key: 'stop',
        timeout: stopBound,
      ),
    ),
  );
}

/// The second attempt in an uncancellable section.
Job<void> stopInAHeldChildJob() =>
    Job<void>(observer: printing, stopInAHeldChild);
