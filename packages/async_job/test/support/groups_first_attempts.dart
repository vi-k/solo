// The first attempts of `doc/groups.md`, verbatim. The test checks the code
// under every "The first attempt" heading of the page against this file
// alone, so an answer pasted in place of an attempt does not pass. The lock
// attempt declares `reading` as the answer in `children_page.dart` does, which
// is one more reason for a library of its own.
import 'package:async_job/async_job.dart';

import 'children_stubs.dart';

/// The first attempt: the lock waits for the group, and the group for it.
// A block body, for the indentation the page shows.
// ignore: prefer_expression_function_bodies
ChildJob<int> reading() {
  return Job.deferred<int>((ctx) async {
    await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
    return ctx.abandonable(loadRows);
  });
}

Job<List<int>> readingTwice() {
  final parent = Job<List<int>>((ctx) => ctx.runAll([reading(), reading()]));
  return parent;
}

Job<void> exportWithFutureWait() {
  final parent = Job<void>((ctx) async {
    final rows = Job.deferred<Source>(
      (ctx) => ctx.abandonable(openRows, discard: (source) => source.close()),
    );
    final images = Job.deferred<Source>(
      (ctx) => ctx.abandonable(openImages, discard: (source) => source.close()),
    );

    final sources = await Future.wait([ctx.run(rows), ctx.run(images)]);
    await ctx.join(() => writeArchive(sources));
  });
  return parent;
}

/// The first attempt with `eagerError: true`; the body says when it wakes
/// and when it returns.
Job<void> exportWithEagerError() {
  final parent = Job<void>((ctx) async {
    final rows = Job.deferred<Source>(
      (ctx) => ctx.abandonable(openRows, discard: (source) => source.close()),
    );
    final images = Job.deferred<Source>(
      (ctx) => ctx.abandonable(openImages, discard: (source) => source.close()),
    );

    try {
      final sources = await Future.wait([
        ctx.run(rows),
        ctx.run(images),
      ], eagerError: true);
      await ctx.join(() => writeArchive(sources));
    } on Object {
      stage.trace.add('the body wakes');
    }
    stage.trace.add('the body returns');
  });
  return parent;
}

Job<void> groupFirstAttempt(List<ChildJob<Source>> branches) =>
    Job<void>((ctx) async {
      final sources = await ctx.runAll(branches);
      await ctx.join(() => writeArchive(sources));
      for (final source in sources) {
        source.close();
      }
    });
