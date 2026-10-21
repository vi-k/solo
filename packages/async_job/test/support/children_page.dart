// The code of `doc/children.md`, `doc/groups.md` and `doc/chains.md`,
// verbatim: every block of the three pages is a run of lines of this file,
// or of `groups_first_attempts.dart` for a first attempt of the groups page.
// `children_page_test.dart`, `groups_rakes_test.dart` and
// `chains_rakes_test.dart` run it. A block that declares names another block
// declares too lives in a function of its own.
import 'dart:async';

import 'package:async_job/async_job.dart';

import 'children_stubs.dart';
import 'delay.dart';

Job<void> overview() {
  final job = Job<void>((ctx) async {
    // A child: the body starts it, waits for it, and cancels along with it.
    final rows =
        await ctx.run(Job.deferred<int>((c) => c.abandonable(loadRows)));

    // A stream: one event at a time, in a child of its own.
    final saving = ctx.each(events, (c, e) => c.join(() => save(e)));

    // A chain: it starts itself when its source succeeds, and no parent
    // can adopt it, so the body waits for it as for any future.
    final tail = saving.then<void>((c, _) => report(rows));
    await ctx.abandonable(() => tail.value);
  });
  return job;
}

Job<void> children() {
  final parent = Job<void>(key: 'parent', observer: Log(), (ctx) async {
    final child = Job.deferred<int>(key: 'rows', (c) => c.abandonable(load));
    final rows = await ctx.run(child);
    ctx.log('$rows rows');
  });
  return parent;
}

/// The parent of [children] with a child that refuses the cancellation.
Job<void> refusingChild() {
  final parent = Job<void>(key: 'parent', observer: Log(), (ctx) async {
    final child = Job.deferred<int>(
      key: 'rows',
      cancellable: false,
      (c) => c.abandonable(load),
    );
    final rows = await ctx.run(child);
    ctx.log('$rows rows');
  });
  return parent;
}

/// The parent of a child whose body fails once its migration stops.
Job<void> cancelledChildFails() {
  final parent = Job<void>(key: 'parent', observer: Log(), (ctx) async {
    final child = Job.deferred<void>(key: 'migration', (ctx) async {
      final stop = CancelToken();
      ctx.onCancel(stop.cancel);

      await ctx.join(() => database.migrate(stop));
    });
    await ctx.run(child);
  });
  return parent;
}

Job<void> childIgnored() {
  // The first attempt: ignore() drops the failure of the cache.
  final parent = Job<void>(key: 'parent', observer: Log(), (ctx) async {
    final rows = Job.deferred<int>(key: 'rows', (c) => c.abandonable(loadRows));
    final cache =
        Job.deferred<void>(key: 'cache', (c) => c.abandonable(warmCache));
    ctx.run(cache).ignore();
    final count = ctx.run(rows);
    ctx.log('${await count} rows');
  });
  return parent;
}

Job<void> childStarted() {
  final parent = Job<void>(key: 'parent', observer: Log(), (ctx) async {
    final rows = Job.deferred<int>(key: 'rows', (c) => c.abandonable(loadRows));
    final cache =
        Job.deferred<void>(key: 'cache', (c) => c.abandonable(warmCache));
    ctx.start(cache);
    final count = ctx.run(rows);
    ctx.log('${await count} rows');
  });
  return parent;
}

// A block body: at this language version dart format indents an expression
// body six columns deep, and the page would show that.
// ignore: prefer_expression_function_bodies
ChildJob<void> level(int depth) {
  return Job.deferred<void>((ctx) async {
    // Without this await, the whole chain is built on one stack.
    await null;
    if (depth > 0) await ctx.run(level(depth - 1));
  });
}

Job<void> exportWithWait() {
  final parent = Job<void>((ctx) async {
    final rows = Job.deferred<Source>(
      (ctx) => ctx.abandonable(openRows, discard: (source) => source.close()),
    );
    final images = Job.deferred<Source>(
      (ctx) => ctx.abandonable(openImages, discard: (source) => source.close()),
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
        Job.deferred<int>((ctx) => ctx.abandonable(loadRows)),
        Job.deferred<int>((ctx) => ctx.abandonable(loadExtra)),
      ]);
      return values;
    });

ChildJob<Source> warmingBranch() {
  final branch = Job.deferred<Source>((ctx) async {
    final cache =
        await ctx.abandonable(openCache, dispose: (cache) => cache.close());
    final rows =
        await ctx.abandonable(openRows, discard: (source) => source.close());
    await ctx.join(() => cache.warm(rows));

    return rows;
  });
  return branch;
}

/// Groups: a branch that reads under the lock its sibling shares, through
/// a child that holds the lock.
// A block body, for the indentation the page shows.
// ignore: prefer_expression_function_bodies
ChildJob<int> reading() {
  return Job.deferred<int>((ctx) async {
    final locked = Job.deferred<int>((ctx) async {
      await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
      return ctx.abandonable(loadRows);
    });
    return ctx.run(locked);
  });
}

Job<List<int>> readingTwice() {
  final parent = Job<List<int>>((ctx) => ctx.runAll([reading(), reading()]));
  return parent;
}

/// Groups: a branch that gets its source from a child of its own.
ChildJob<Source> openingBranch() {
  final branch = Job.deferred<Source>((ctx) async {
    final opening = Job.deferred<Source>(
      (ctx) => ctx.abandonable(openRows, discard: (source) => source.close()),
    );
    return ctx.run(opening, discard: (source) => source.close());
  });
  return branch;
}

Job<void> refusingBranch() {
  final parent = Job<void>((ctx) async {
    final images = Job.deferred<Source>(
      (ctx) => ctx.abandonable(openImages, discard: (source) => source.close()),
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

Job<void> groupTry(List<ChildJob<Source>> branches) => Job<void>((ctx) async {
      final sources = await ctx.runAll(branches);
      try {
        await ctx.join(() => writeArchive(sources));
      } finally {
        for (final source in sources) {
          source.close();
        }
      }
    });

Job<void> groupRegistered(List<ChildJob<Source>> branches) =>
    Job<void>((ctx) async {
      final sources = await ctx.runAll(branches);
      for (final source in sources) {
        ctx.onDispose(source.close);
      }
      await ctx.join(() => writeArchive(sources));
    });

ChildJob<List<Source>> handedOutCatch(List<ChildJob<Source>> branches) {
  final exported = Job.deferred<List<Source>>((ctx) async {
    final sources = await ctx.runAll(branches);
    try {
      await ctx.join(() => writeArchive(sources));
    } on Object {
      for (final source in sources) {
        source.close();
      }
      rethrow;
    }
    return sources;
  });
  return exported;
}

ChildJob<List<Source>> handedOutDiscard(List<ChildJob<Source>> branches) {
  final exported = Job.deferred<List<Source>>((ctx) async {
    final sources = await ctx.runAll(branches);
    for (final source in sources) {
      ctx.onDiscard(source.close);
    }
    await ctx.join(() => writeArchive(sources));
    return sources;
  });
  return exported;
}

Future<void> chain() async {
  final loaded = Job<String>((ctx) => ctx.join(loadText));
  final parsed = loaded.then<int>((ctx, text) => int.parse(text));
  final saved = parsed.then<void>((ctx, number) => ctx.join(
        () => saveNumber(number),
        // ignore: require_trailing_commas
      ));

  await saved.value;
}

/// Chains: the chain of [chain], cancelled at its last link while the text
/// loads.
Future<void> cancelledChain() async {
  final loaded = Job<String>((ctx) => ctx.join(loadText));
  final parsed = loaded.then<int>((ctx, text) => int.parse(text));
  final saved = parsed.then<void>((ctx, number) => ctx.join(
        () => saveNumber(number),
        // ignore: require_trailing_commas
      ));
  await delay(10);

  // The user left the screen while the text was loading.
  await saved.cancel();
  print('loaded: ${loaded.outcome}');
  print('parsed: ${parsed.outcome}');
  print('saved: ${saved.outcome}');
}

/// Chains, the first attempt: two continuations of one source. The second
/// `then` throws.
void twoContinuations() {
  // The first attempt: the second continuation throws.
  final loaded = Job<String>((ctx) => ctx.join(loadText));
  // ignore: unused_local_variable
  final parsed = loaded.then<int>((ctx, text) => int.parse(text));
  // ignore: unused_local_variable
  final shown = loaded.then<void>((ctx, text) => showText(text));
}

/// Chains: a handle of `shared()` for each branch, and one branch is
/// cancelled while the text loads.
Future<void> twoHandles() async {
  final loaded = Job<String>((ctx) => ctx.join(loadText));
  final parsed = loaded.shared().then<int>((ctx, text) => int.parse(text));
  final shown = loaded.shared().then<void>((ctx, text) => showText(text));
  await delay(10);

  // The number left the screen while the text was loading.
  await parsed.cancel();
  await shown.done;
  print('parsed: ${parsed.outcome}');
  print('loaded: ${loaded.outcome}');
  print('shown: ${shown.outcome}');
}

/// Chains: two jobs that wait for one source, and one of them is cancelled
/// while the text loads.
Future<void> twoWaiting() async {
  final loaded = Job<String>((ctx) => ctx.join(loadText));
  final parsed = Job<int>(
    (ctx) async => int.parse(await ctx.abandonable(() => loaded.value)),
  );
  final shown = Job<void>(
    (ctx) async => showText(await ctx.abandonable(() => loaded.value)),
  );
  await delay(10);

  // The number left the screen while the text was loading.
  await parsed.cancel();
  await shown.done;
  print('parsed: ${parsed.outcome}');
  print('loaded: ${loaded.outcome}');
  print('shown: ${shown.outcome}');
}

/// Chains, the first attempt: the continuation does not wait for a job.
Job<void> storeParsedWithoutWaiting(Job<int> parsed) {
  // ignore: void_checks
  final stored = parsed.then<void>((ctx, number) {
    final saving = Job<void>((ctx) => ctx.join(() => saveNumber(number)));
    return saving;
  });
  return stored;
}

/// Chains: the continuation that waits for a job, by running it as a child.
Job<void> storeParsed(Job<int> parsed) {
  final stored = parsed.then<void>((ctx, number) {
    final saving = Job.deferred<void>(
      (ctx) => ctx.join(() => saveNumber(number)),
    );
    return ctx.run(saving);
  });
  return stored;
}

/// Chains: a source that waits for its own continuation.
Job<String> loadedAwaitingParsed() {
  late final Job<int> parsed;
  final loaded = Job<String>((ctx) async {
    final text = await ctx.join(loadText);
    await parsed.value;
    return text;
  });
  parsed = loaded.then<int>((ctx, text) => int.parse(text));
  return loaded;
}

/// Chains: the continuation receives what its source hands out.
(Job<Source>, Job<void>) archiveOpened() {
  final opened = Job<Source>(
    (ctx) => ctx.abandonable(openRows, discard: (rows) => rows.close()),
  );
  final archived = opened.then<void>((ctx, rows) async {
    ctx.onDispose(rows.close);
    await ctx.join(() => writeArchive([rows]));
  });
  return (opened, archived);
}

/// Chains: two branches of one source share what it hands out, and the
/// code that waits for both closes it.
Future<void> archiveAndWarm(Cache cache) async {
  final opened = Job<Source>(
    (ctx) => ctx.abandonable(openRows, discard: (rows) => rows.close()),
  );
  final archived = opened.shared().then<void>(
        (ctx, rows) => ctx.join(() => writeArchive([rows])),
      );
  final warmed = opened.shared().then<void>(
        (ctx, rows) => ctx.join(() => cache.warm(rows)),
      );
  await [archived.done, warmed.done].wait;
  if (await opened.done case Done(:final value)) value.close();
}

/// The first attempt of the chain, as the page shows it. It does not
/// compile, so it stands here as text, and the test hands it to the
/// analyzer.
const adoptedTail = '''
final child = Job.deferred<int>((ctx) => ctx.abandonable(load));
final tail = child.then<void>((ctx, rows) => report(rows));

final parent = Job<void>((ctx) async {
  ctx.log(await ctx.run(child));
  await ctx.run(tail);
});
''';

/// The version where the source is the only child.
Future<void> reportedRows() async {
  final child = Job.deferred<int>((ctx) => ctx.abandonable(load));
  final tail = child.then<void>((ctx, rows) => report(rows));

  final parent = Job<void>((ctx) async {
    // The source is a child: the parent starts it and waits for it.
    ctx.log(await ctx.run(child));
  });
  parent.done.then((outcome) => stage.trace.add('parent $outcome')).ignore();

  await parent.value; // Done, whatever tail is doing.
  await tail.value; // tail is yours to observe.
}

Job<void> twoChildrenInARow() {
  final parent = Job<void>((ctx) async {
    final rows =
        await ctx.run(Job.deferred<int>((ctx) => ctx.abandonable(load)));
    await ctx.run(Job.deferred<void>((ctx) => ctx.join(() => report(rows))));
  });
  return parent;
}
