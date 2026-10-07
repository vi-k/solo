// The code of `doc/resources.md`, verbatim, less the first and second
// attempts: every piece of those blocks is a run of lines of this file, and
// `resources_rakes_test.dart` runs it. The page shows a body, the methods of
// a controller and a few statements on their own; here each stands in a
// class, and a method the page writes more than once has a class for each
// version.
import 'dart:async';

import 'package:solo/solo.dart';

import 'resources_stubs.dart';
import 'test_solo.dart';

/// The body the page opens with, and the job that runs it.
final class Opening extends Solo<AppState> with OpenSolo<AppState>, Desk {
  Opening() : super(const Idle());

  /// Not on the page: the call that takes the body. The body is an element
  /// of a list, where a closure ends on a line of its own as it does on the
  /// page.
  Job<TempFile> start() {
    final bodies = <Future<TempFile> Function(SoloContext<AppState, Idle> ctx)>[
      (ctx) async {
        // Made here, on the spot: nothing arrives between the two lines.
        final sub = device.events.listen(onEvent);
        ctx.onDispose(sub.cancel);

        // Taken from a call: the release goes on the call, not under it.
        final db = await ctx.join(Database.open, dispose: (db) => db.close());

        // Leaves with the result, so it is released only if the job ends
        // cancelled or failed.
        final file = await ctx.join(openTemp, discard: (file) => file.delete());

        // Handed to the state, which owns it from here on.
        ctx
          ..check()
          ..disown(db)
          ..emit(Ready(db));

        return file;
      }
    ];

    return run<Idle, TempFile>(key: 'opening', bodies.single);
  }
}

/// "The release travels with the call".
final class Loader extends Solo<AppState> with OpenSolo<AppState>, Desk {
  Loader() : super(const Idle());

  Job<void> load() => run<Idle, void>(
        key: 'load',
        (ctx) async {
          final db = await ctx.join(
            Database.open,
            dispose: (db) => db.close(),
          );

          final rows = await ctx.join(db.readAll);
          ctx.emit(Loaded(rows));
        },
      );
}

/// The creation that rides on a call, under the same heading.
final class Watcher extends Solo<AppState> with OpenSolo<AppState>, Desk {
  Watcher() : super(const Idle());

  /// Not on the page: a body around the statement, after a step named
  /// [step] that a cancellation waits out.
  Job<void> watch(String step) => run<Idle, void>(
        key: 'watch',
        (ctx) async {
          await ctx.uncancellable(() => stage.start<void>(step, null));
          // ignore: unused_local_variable
          final sub = await ctx.join(
            () => device.events.listen(onEvent),
            dispose: (sub) => sub.cancel(),
          );
        },
      );
}

/// "Discard, for a value that leaves".
final class Opener extends Solo<AppState> with OpenSolo<AppState>, Desk {
  Opener() : super(const Idle());

  Job<Database> open() => run<Idle, Database>(
        key: 'open',
        (ctx) async {
          final db = await ctx.join(
            Database.open,
            discard: (db) => db.close(),
          );
          await ctx.run(job<Idle, void>((child) => child.join(db.readAll)));
          return db;
        },
      );
}

/// "Check, disown, emit", and the asynchronous hand-over under it.
final class Handover extends Solo<AppState> with OpenSolo<AppState>, Desk {
  Handover() : super(const Idle());

  /// Not on the page: the method and the call that opens the database,
  /// which the page shows in the first attempt.
  Job<void> hand() => run<Idle, void>(
        key: 'hand',
        (ctx) async {
          final db = await ctx.join(
            Database.open,
            dispose: (db) => db.close(),
          );
          await ctx.uncancellable(db.migrate);
          ctx
            ..check()
            ..disown(db)
            ..emit(Ready(db));
        },
      );

  /// Not on the page: the method, the call that makes the file, and a step
  /// named [step] before the section, when the test wants one.
  Job<void> store({String? step}) => run<Idle, void>(
        key: 'store',
        (ctx) async {
          final file = await ctx.join(
            openTemp,
            dispose: (file) => file.delete(),
          );
          if (step != null) {
            await ctx.uncancellable(() => stage.start<void>(step, null));
          }
          await ctx.uncancellable(() async {
            await archive.take(file);
            ctx.disown(file);
          });
        },
      );
}

/// "The wait that stays with it".
final class TempKeeper extends Solo<AppState> with OpenSolo<AppState>, Desk {
  TempKeeper() : super(const Idle());

  /// Not on the page: the method around the statement.
  Job<void> write() => run<Idle, void>(
        key: 'temp',
        (ctx) async {
          // Deleted before the next job starts and before close() comes back.
          await ctx.join(openTemp, dispose: (file) => file.delete());
        },
      );
}
