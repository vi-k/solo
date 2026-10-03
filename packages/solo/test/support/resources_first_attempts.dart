// The first and the second attempts of `doc/resources.md`, verbatim: every
// piece of the code under a "The first attempt" or "The second attempt"
// heading is a run of lines of this file, and `resources_rakes_test.dart`
// runs it. The page shows each as a method or a few statements on their
// own; here each version stands in a class.
import 'package:solo/solo.dart';

import 'resources_stubs.dart';
import 'test_solo.dart';

/// The first attempt of "Taking a resource from a call": the registration on
/// the line under the call.
final class LoaderRegisteringUnder extends Solo<AppState>
    with OpenSolo<AppState>, Desk {
  LoaderRegisteringUnder() : super(const Idle());

  SoloJob<void> load() => run<Idle, void>(
        key: 'load',
        (ctx) async {
          final db = await ctx.join(Database.open);
          ctx.onDispose(db.close);

          final rows = await ctx.join(db.readAll);
          ctx.emit(Loaded(rows));
        },
      );
}

/// The first attempt of "Returning a resource to the caller": the result
/// registered with `dispose`.
final class OpenerDisposing extends Solo<AppState>
    with OpenSolo<AppState>, Desk {
  OpenerDisposing() : super(const Idle());

  SoloJob<Database> open() => run<Idle, Database>(
        key: 'open',
        (ctx) async {
          final db = await ctx.join(
            Database.open,
            dispose: (db) => db.close(),
          );
          await ctx.run(job<Idle, void>((child) => child.join(db.readAll)));
          return db;
        },
      );
}

/// The first attempt of "Handing a resource to the state": the write with
/// the registration still standing.
final class HandoverKeeping extends Solo<AppState>
    with OpenSolo<AppState>, Desk {
  HandoverKeeping() : super(const Idle());

  /// Not on the page: the method around the statements.
  SoloJob<void> hand() => run<Idle, void>(
        key: 'hand',
        (ctx) async {
          final db = await ctx.join(
            Database.open,
            dispose: (db) => db.close(),
          );
          await ctx.uncancellable(db.migrate);
          ctx.emit(Ready(db));
        },
      );
}

/// The second attempt of the same section: the registration dropped, and
/// nothing checked.
final class HandoverDisowning extends Solo<AppState>
    with OpenSolo<AppState>, Desk {
  HandoverDisowning() : super(const Idle());

  /// Not on the page: the method and the call that opens the database,
  /// which the page shows in the first attempt.
  SoloJob<void> hand() => run<Idle, void>(
        key: 'hand',
        (ctx) async {
          final db = await ctx.join(
            Database.open,
            dispose: (db) => db.close(),
          );
          await ctx.uncancellable(db.migrate);
          ctx
            ..disown(db)
            ..emit(Ready(db));
        },
      );
}

/// The first attempt of "When the release happens": the wait that lets go
/// of the call.
final class TempWaiter extends Solo<AppState> with OpenSolo<AppState>, Desk {
  TempWaiter() : super(const Idle());

  /// Not on the page: the method around the statement.
  SoloJob<void> write() => run<Idle, void>(
        key: 'temp',
        (ctx) async {
          // Deleted whatever happens: dispose runs on every outcome.
          await ctx.wait(openTemp, dispose: (file) => file.delete());
        },
      );
}
