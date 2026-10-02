// The code of `doc/children.md`, verbatim: every block of the page is a run
// of lines of this file, and `children_rakes_test.dart` runs it. A block
// that declares names another block declares too lives in a function of
// its own.
import 'dart:async';

import 'package:async_job/async_job.dart';

import 'children_stubs.dart';

Job<void> overview() {
  final job = Job<void>((ctx) async {
    // A child: the body starts it, waits for it, and cancels along with it.
    final rows = await ctx.run(Job.deferred<int>((c) => c.wait(loadRows)));

    // A stream: one event at a time, in a child of its own.
    final saving = ctx.each(events, (c, e) => c.join(() => save(e)));

    // A chain: it starts itself when its source succeeds, and no parent
    // can adopt it.
    // ignore: unused_local_variable
    final tail = saving.then<void>((c, _) => report(rows));
  });
  return job;
}

Job<void> children() {
  final parent = Job<void>((ctx) async {
    final child = Job.deferred<int>((ctx) => ctx.wait(load));
    final rows = await ctx.run(child);
    ctx.log('$rows rows');
  });
  return parent;
}

Job<void> childNotAwaited() {
  final parent = Job<void>((ctx) async {
    final rows = ctx.run(Job.deferred<int>((c) => c.wait(loadRows)));
    final child = Job.deferred<void>((c) => c.wait(warmCache));
    ctx.run(child).ignore();
    ctx.log('${await rows} rows');
  });
  return parent;
}

// A block body: at this language version dart format indents an expression
// body six columns deep, and the page would show that.
// ignore: prefer_expression_function_bodies
Job<void> level(int depth) {
  return Job.deferred<void>((ctx) async {
    // Without this await, the whole chain is built on one stack.
    await null;
    if (depth > 0) await ctx.run(level(depth - 1));
  });
}

Job<void> exportWithFutureWait() {
  final parent = Job<void>((ctx) async {
    final rows = Job.deferred<Source>(
      (ctx) => ctx.wait(openRows, discard: (source) => source.close()),
    );
    final images = Job.deferred<Source>(
      (ctx) => ctx.wait(openImages, discard: (source) => source.close()),
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
      (ctx) => ctx.wait(openRows, discard: (source) => source.close()),
    );
    final images = Job.deferred<Source>(
      (ctx) => ctx.wait(openImages, discard: (source) => source.close()),
    );

    try {
      final sources = await Future.wait(
        [ctx.run(rows), ctx.run(images)],
        eagerError: true,
      );
      await ctx.join(() => writeArchive(sources));
    } on Object {
      stage.trace.add('the body wakes');
    }
    stage.trace.add('the body returns');
  });
  return parent;
}

Job<void> exportWithWait() {
  final parent = Job<void>((ctx) async {
    final rows = Job.deferred<Source>(
      (ctx) => ctx.wait(openRows, discard: (source) => source.close()),
    );
    final images = Job.deferred<Source>(
      (ctx) => ctx.wait(openImages, discard: (source) => source.close()),
    );

    final sources = await [
      ctx.run(rows, dispose: (source) => source.close()),
      ctx.run(images, dispose: (source) => source.close()),
    ].wait;
    await ctx.join(() => writeArchive(sources));
  });
  return parent;
}

Job<List<int>> loadAll() => Job<List<int>>((ctx) async {
      final values = await ctx.runAll([
        Job.deferred<int>((ctx) => ctx.wait(loadRows)),
        Job.deferred<int>((ctx) => ctx.wait(loadExtra)),
      ]);
      return values;
    });

Job<Source> warmingBranch() {
  final branch = Job.deferred<Source>((ctx) async {
    final cache = await ctx.wait(openCache, dispose: (cache) => cache.close());
    final rows = await ctx.wait(openRows, discard: (source) => source.close());
    await ctx.join(() => cache.warm(rows));

    return rows;
  });
  return branch;
}

Job<Source> lockedBranch() {
  final branch = Job.deferred<Source>((ctx) async {
    final locked = Job.deferred<Source>((ctx) async {
      await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
      return ctx.wait(openRows, discard: (source) => source.close());
    });

    return ctx.run(locked, discard: (source) => source.close());
  });
  return branch;
}

Job<void> refusingBranch() {
  final parent = Job<void>((ctx) async {
    final images = Job.deferred<Source>(
      (ctx) => ctx.wait(openImages, discard: (source) => source.close()),
    );
    final rows = Job.deferred<Source>(cancellable: false, (ctx) => openRows());
    try {
      await ctx.runAll([rows, images]);
    } on Object {
      if (rows.outcome case Done(:final value)) value.close();
      rethrow;
    }
  });
  return parent;
}

Job<void> groupFirstAttempt(List<Job<Source>> branches) =>
    Job<void>((ctx) async {
      final sources = await ctx.runAll(branches);
      await ctx.join(loadManifest);
      await ctx.wait(
        () => sources,
        dispose: (values) {
          for (final source in values) {
            source.close();
          }
        },
      );
      stage.trace.add('registered');
    });

Job<void> groupNextLine(List<Job<Source>> branches) => Job<void>((ctx) async {
      final sources = await ctx.runAll(branches);
      ctx.onDispose(() {
        for (final source in sources) {
          source.close();
        }
      });
      stage.trace.add('registered');
      await ctx.join(loadManifest);
    });

Future<void> saveMessages(
  Stream<String> messages,
  Future<void> Function(String message) save,
) async {
  final job = Job<void>((ctx) async {
    // ignore: prefer_expression_function_bodies
    final processing = ctx.each(messages, (childCtx, message) {
      return childCtx.join(() => save(message));
    });
    await processing.value;
  });

  await job.value;
}

Future<void> watchTicks() async {
  final job = Job<void>((ctx) async {
    final ticks = ctx.each(
      Stream<int>.periodic(const Duration(seconds: 1), (index) => index + 1),
      (childCtx, tick) => print('Tick $tick'),
    );

    await ctx.wait(
      () => Future<void>.delayed(const Duration(milliseconds: 2500)),
    );
    await ticks.cancel();
    print('Parent continues');
  });

  await job.value;
}

Job<void> savingInSteps() => Job<void>((ctx) async {
      final processing = ctx.each(messages, (childCtx, message) async {
        await store.saveBody(message);
        await store.saveAttachments(message);
      });
      ctx.onDispose(() => stage.trace.add('parent cleanup'));
      await processing.value;
    });

Job<void> savingWithCheckpoints() => Job<void>((ctx) async {
      final processing = ctx.each(messages, (childCtx, message) async {
        await childCtx.join(() => store.saveBody(message));
        await childCtx.join(() => store.saveAttachments(message));
      });
      ctx.onDispose(() => stage.trace.add('parent cleanup'));
      await processing.value;
    });

Future<void> chain() async {
  final loaded = Job<String>((ctx) => ctx.join(loadText));
  final parsed = loaded.then<int>((ctx, text) => int.parse(text));
  final saved = parsed.then<void>((ctx, number) => ctx.join(
        () => saveNumber(number),
        // ignore: require_trailing_commas
      ));

  await saved.value;
}

/// The first attempt of the chain, and the version where the source is the
/// only child; [adoptTheTail] picks the first.
Future<void> reportedRows({required bool adoptTheTail}) async {
  final child = Job.deferred<int>((ctx) => ctx.wait(load));
  final tail = child.then<void>((ctx, rows) => report(rows));

  if (adoptTheTail) {
    final parent = Job<void>((ctx) async {
      ctx.log(await ctx.run(child));
      await ctx.run(tail);
    });
    await parent.value;
  } else {
    final parent = Job<void>((ctx) async {
      // The source is a child: the parent starts it and waits for it.
      ctx.log(await ctx.run(child));
    });
    parent.done.then((outcome) => stage.trace.add('parent $outcome')).ignore();

    await parent.value; // Done, whatever the continuation is doing.
    await tail.value; // The continuation is yours to observe.
  }
}

Job<void> twoChildrenInARow() {
  final parent = Job<void>((ctx) async {
    final rows = await ctx.run(Job.deferred<int>((ctx) => ctx.wait(load)));
    await ctx.run(Job.deferred<void>((ctx) => ctx.join(() => report(rows))));
  });
  return parent;
}
