@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

/// The first attempts of `doc/resources.md`, and what each one costs.
///
/// The page opens four of its sections with the version the vocabulary of
/// the API leads to, and states what that version does instead of what it
/// was meant to do. Nothing else guards those statements: the page has no
/// bench, so an outcome quoted there rots silently. Every order and every
/// owner the page names — who closes the resource, and when — is pinned
/// here, next to the version the page then shows.

/// A resource that says when it was closed, and how often.
final class Database {
  final String name;
  final List<String> trace;
  int closes = 0;

  Database(this.name, this.trace);

  bool get closed => closes > 0;

  Future<List<String>> readAll() async => const <String>['row'];

  Future<void> close() async {
    closes += 1;
    trace.add('$name closed');
  }
}

/// An opener the test finishes by hand.
final class Opener {
  final List<String> trace;
  final _pending = <String, Completer<Database>>{};
  final opened = <Database>[];

  Opener(this.trace);

  Future<Database> open([String name = 'db']) {
    trace.add('$name opening');
    return (_pending[name] = Completer<Database>()).future;
  }

  Future<Database> finish([String name = 'db']) async {
    final db = Database(name, trace);
    opened.add(db);
    trace.add('$name opened');
    _pending.remove(name)!.complete(db);
    await pump();
    return db;
  }
}

/// A step the test lets through when it wants to.
final class Gate {
  final _open = Completer<void>();

  Future<void> wait() => _open.future;

  Future<void> release() async {
    _open.complete();
    await pump();
  }
}

final class Archive {
  final List<String> trace;

  Archive(this.trace);

  Future<void> take(Database db) async => trace.add('archive took ${db.name}');
}

sealed class Screen {}

final class Idle implements Screen {}

final class Loaded implements Screen {
  final List<String> rows;

  Loaded(this.rows);
}

final class Ready implements Screen {
  final Database db;

  Ready(this.db);
}

final class Files extends Solo<Screen> {
  final Opener opener;
  final Gate gate;
  final List<String> trace;
  final StreamController<int> events;
  late final Archive archive = Archive(trace);

  Files(this.opener, this.gate, this.trace, this.events) : super(Idle());

  /// Writes a state the jobs of this file do not work on.
  void loseTheScreen() => externalSetState(Loaded(const <String>[]));

  // --- Taking a resource from a call -------------------------------------

  /// The first attempt: the registration on the line under the call.
  SoloJob<void> loadRegisteringUnder() => run<Idle, void>(
        key: 'load',
        (ctx) async {
          final db = await ctx.join(opener.open);
          ctx.onDispose(db.close);
          trace.add('body has the database');

          final rows = await ctx.join(db.readAll);
          ctx.emit(Loaded(rows));
        },
      );

  /// The release that travels with the call.
  SoloJob<void> load() => run<Idle, void>(
        key: 'load',
        (ctx) async {
          final db = await ctx.join(
            opener.open,
            dispose: (db) => db.close(),
          );
          trace.add('body has the database');

          final rows = await ctx.join(db.readAll);
          ctx.emit(Loaded(rows));
        },
      );

  /// The same release registered twice: on the call and under it.
  SoloJob<void> loadRegisteringTwice() => run<Idle, void>(
        key: 'load',
        (ctx) async {
          final db = await ctx.join(
            opener.open,
            dispose: (db) => db.close(),
          );
          ctx.onDispose(db.close);
          await ctx.join(db.readAll);
        },
      );

  /// A job that only reports that it started.
  SoloJob<void> next() => run<Idle, void>(
        key: 'next',
        (ctx) async => trace.add('next job started'),
      );

  /// A subscription made on the spot, with the release under it.
  SoloJob<void> watchByPair(Gate held) => run<Idle, void>(
        key: 'watch',
        (ctx) async {
          await ctx.uncancellable(held.wait);
          final sub = events.stream.listen((_) {});
          ctx.onDispose(sub.cancel);
          trace.add('subscription made');
          ctx.check();
        },
      );

  /// The same creation, riding on a call of its own.
  SoloJob<void> watchByJoin(Gate held) => run<Idle, void>(
        key: 'watch',
        (ctx) async {
          await ctx.uncancellable(held.wait);
          await ctx.join(
            () {
              trace.add('subscription made');
              return events.stream.listen((_) {});
            },
            dispose: (sub) => sub.cancel(),
          );
          ctx.check();
        },
      );

  // --- Returning a resource to the caller --------------------------------

  /// The first attempt: the result registered with `dispose`.
  SoloJob<Database> openWithDispose() => run<Idle, Database>(
        key: 'open',
        (ctx) async {
          final db = await ctx.join(
            opener.open,
            dispose: (db) => db.close(),
          );
          await ctx.run(job<Idle, void>((child) => child.join(db.readAll)));
          return db;
        },
      );

  /// The result registered with `discard`.
  SoloJob<Database> openWithDiscard() => run<Idle, Database>(
        key: 'open',
        (ctx) async {
          final db = await ctx.join(
            opener.open,
            discard: (db) => db.close(),
          );
          await ctx.run(job<Idle, void>((child) => child.join(db.readAll)));
          return db;
        },
      );

  /// The page's shape: the child stands between the value and the return.
  SoloJob<Database> openAwaitingChild() => run<Idle, Database>(
        key: 'open',
        (ctx) async {
          final db = await ctx.join(
            opener.open,
            discard: (db) => db.close(),
          );
          await ctx.run(job<Idle, void>((child) => child.join(gate.wait)));
          trace.add('body returns the database');
          return db;
        },
      );

  /// A child that refuses the cascade, so it ends its own way.
  SoloJob<Database> _stubbornChild() => job<Idle, Database>(
        cancellable: false,
        (ctx) async {
          final db = await ctx.wait(
            opener.open,
            discard: (db) => db.close(),
          );
          await ctx.join(gate.wait);
          return db;
        },
      );

  /// The registration written under `ctx.run`.
  SoloJob<void> takeChildRegisteringUnder() => run<Idle, void>(
        key: 'take',
        (ctx) async {
          final db = await ctx.run(_stubbornChild());
          ctx.onDiscard(db.close);
          trace.add('parent registered the database');
        },
      );

  /// The registration handed to `ctx.run`.
  SoloJob<void> takeChildRegisteringOnCall() => run<Idle, void>(
        key: 'take',
        (ctx) async {
          await ctx.run(_stubbornChild(), discard: (db) => db.close());
          trace.add('parent registered the database');
        },
      );

  /// The result handed over while a child keeps the job running.
  SoloJob<Database> openWithDiscardAndChild() => run<Idle, Database>(
        key: 'open',
        (ctx) async {
          final db = await ctx.join(
            opener.open,
            discard: (db) => db.close(),
          );
          unawaited(
            ctx
                .run(job<Idle, void>((child) => child.join(gate.wait)))
                .onError((_, __) {}),
          );
          await pump();
          return db;
        },
      );

  // --- Handing a resource to the state -----------------------------------

  /// The first attempt: the write with the registration still standing.
  SoloJob<void> handOverKeepingRegistration() => run<Idle, void>(
        key: 'hand',
        (ctx) async {
          final db = await ctx.join(
            opener.open,
            dispose: (db) => db.close(),
          );
          ctx.emit(Ready(db));
        },
      );

  /// The second attempt: the registration dropped, nothing checked.
  SoloJob<void> handOverDisowningFirst() => run<Idle, void>(
        key: 'hand',
        (ctx) async {
          final db = await ctx.join(
            opener.open,
            dispose: (db) => db.close(),
          );
          await ctx.uncancellable(gate.wait);
          ctx
            ..disown(db)
            ..emit(Ready(db));
          trace.add('body went past emit');
        },
      );

  /// The cascade the page ends on.
  SoloJob<void> handOverChecked() => run<Idle, void>(
        key: 'hand',
        (ctx) async {
          final db = await ctx.join(
            opener.open,
            dispose: (db) => db.close(),
          );
          await ctx.uncancellable(gate.wait);
          ctx
            ..check()
            ..disown(db)
            ..emit(Ready(db));
          trace.add('body went past emit');
        },
      );

  /// The same cascade, with no protected step before it.
  SoloJob<void> handOverWatched() => run<Idle, void>(
        key: 'hand',
        (ctx) async {
          final db = await ctx.join(
            opener.open,
            dispose: (db) => db.close(),
          );
          ctx
            ..check()
            ..disown(db)
            ..emit(Ready(db));
          trace.add('body went past emit');
        },
      );

  /// An asynchronous hand-over with a checkpoint before `disown`.
  SoloJob<void> archiveThroughCheckpoint() => run<Idle, void>(
        key: 'archive',
        (ctx) async {
          final db = await ctx.join(
            opener.open,
            dispose: (db) => db.close(),
          );
          await ctx.join(() async {
            await gate.wait();
            await archive.take(db);
          });
          ctx.disown(db);
          trace.add('registration dropped');
        },
      );

  /// The protected section with a waiting method inside it.
  SoloJob<void> archiveProtectedByJoin() => run<Idle, void>(
        key: 'archive',
        (ctx) async {
          final db = await ctx.join(
            opener.open,
            dispose: (db) => db.close(),
          );
          await ctx.uncancellable(() async {
            await gate.wait();
            await ctx.join(() => archive.take(db));
            ctx.disown(db);
          });
          trace.add('registration dropped');
        },
      );

  /// The same hand-over inside one protected section.
  SoloJob<void> archiveProtected() => run<Idle, void>(
        key: 'archive',
        (ctx) async {
          final db = await ctx.join(
            opener.open,
            dispose: (db) => db.close(),
          );
          await ctx.uncancellable(() async {
            await gate.wait();
            await archive.take(db);
            ctx.disown(db);
          });
          trace.add('registration dropped');
        },
      );

  // --- When the release happens ------------------------------------------

  /// A temporary file that appears once the gate lets it.
  Future<Database> _openTemp() async {
    await gate.wait();
    trace.add('temp opened');
    return Database('temp', trace);
  }

  /// The first attempt: the wait that lets go of the call.
  SoloJob<void> tempByWait() => run<Idle, void>(
        key: 'temp',
        (ctx) async {
          await ctx.wait(_openTemp, dispose: (db) => db.close());
          trace.add('body went on');
        },
      );

  /// The wait that stays with it.
  SoloJob<void> tempByJoin() => run<Idle, void>(
        key: 'temp',
        (ctx) async {
          await ctx.join(_openTemp, dispose: (db) => db.close());
          trace.add('body went on');
        },
      );

  // --- Cleanup order and late results ------------------------------------

  /// A discard on top of the stack, needed only after the body returned.
  SoloJob<Database> discardOnTop() => run<Idle, Database>(
        key: 'order',
        (ctx) async {
          ctx
            ..onDispose(() async => trace.add('disposer A'))
            ..onDispose(() async {
              trace.add('disposer B waits');
              await gate.wait();
              trace.add('disposer B done');
            });
          final db = await ctx.join(
            opener.open,
            discard: (db) => db.close(),
          );
          return db;
        },
      );

  /// Cleanup that throws an error of its own.
  SoloJob<void> cleanupThrows() => run<Idle, void>(
        key: 'boom',
        (ctx) async {
          ctx.onDispose(() async => throw StateError('cleanup failed'));
        },
      );

  /// Cleanup that throws a cancellation.
  SoloJob<void> cleanupCancels() => run<Idle, void>(
        key: 'quiet',
        (ctx) async {
          ctx.onDispose(() async => throw const Cancelled());
        },
      );
}

void main() {
  late List<String> trace;
  late Opener opener;
  late Gate gate;
  late Files files;
  late StreamController<int> events;

  setUp(() {
    trace = <String>[];
    opener = Opener(trace);
    gate = Gate();
    events = StreamController<int>.broadcast();
    files = Files(opener, gate, trace, events);
  });

  tearDown(() async {
    Solo.errorHandler = null;
    Solo.observer = null;
    await events.close();
  });

  group('Taking a resource from a call', () {
    test('the first attempt never reaches its registration', () async {
      final job = files.loadRegisteringUnder();
      await pump();
      unawaited(job.cancel());
      await pump();
      final db = await opener.finish();
      await job.done;

      expect(trace, isNot(contains('body has the database')));
      expect(db.closed, isFalse);
      expect(job.outcome, isA<Cancelled>());
    });

    test('dispose on the call closes what never reached the body', () async {
      final job = files.load();
      await pump();
      unawaited(job.cancel());
      await pump();
      final db = await opener.finish();
      await job.done;

      expect(trace, isNot(contains('body has the database')));
      expect(db.closed, isTrue);
    });

    test('the release on the call still runs on the success path', () async {
      final job = files.load();
      await pump();
      final db = await opener.finish();
      await job.done;

      final state = files.currentState;
      expect(state, isA<Loaded>());
      expect((state as Loaded).rows, <String>['row']);
      expect(job.outcome, isA<Done<void>>());
      expect(db.closed, isTrue);
    });

    test('join closes it before the next job starts', () async {
      final job = files.load();
      final next = files.next();
      await pump();
      unawaited(job.cancel());
      await pump();
      await opener.finish();
      await next.done;

      expect(
        trace,
        containsAllInOrder(<String>['db closed', 'next job started']),
      );
    });

    test('a call makes nothing under a standing cancellation', () async {
      final held = Gate();
      final pair = files.watchByPair(held);
      await pump();
      unawaited(pair.cancel());
      await held.release();
      await pair.done;
      final afterPair = List<String>.of(trace);

      trace.clear();
      final second = Gate();
      final wrapped = files.watchByJoin(second);
      await pump();
      unawaited(wrapped.cancel());
      await second.release();
      await wrapped.done;

      expect(afterPair, <String>['subscription made']);
      expect(trace, isEmpty);
    });

    test('a release registered twice runs twice', () async {
      final job = files.loadRegisteringTwice();
      await pump();
      final db = await opener.finish();
      await job.done;

      expect(db.closes, 2);
    });
  });

  group('Returning a resource to the caller', () {
    test('dispose closes the result before the caller has it', () async {
      final job = files.openWithDispose();
      await pump();
      await opener.finish();
      final db = await job.value;

      expect(db.closed, isTrue);
    });

    test('discard leaves the result open on the success path', () async {
      final job = files.openWithDiscard();
      await pump();
      await opener.finish();
      final db = await job.value;

      expect(db.closed, isFalse);
      expect(job.outcome, isA<Done<Database>>());
    });

    test('a cancellation during the child wait keeps the value in', () async {
      final job = files.openAwaitingChild();
      unawaited(job.value.onError((_, __) => Database('none', trace)));
      await pump();
      final db = await opener.finish();
      await pump();
      unawaited(job.cancel());
      await gate.release();
      await job.done;

      expect(trace, isNot(contains('body returns the database')));
      expect(job.outcome, isA<Cancelled>());
      expect(db.closed, isTrue);
    });

    test('the registration under run is never reached', () async {
      final job = files.takeChildRegisteringUnder();
      await pump();
      final db = await opener.finish();
      unawaited(job.cancel());
      await gate.release();
      await job.done;

      expect(job.outcome, isA<Cancelled>());
      expect(trace, isNot(contains('parent registered the database')));
      expect(db.closed, isFalse);
    });

    test('the registration handed to run closes it', () async {
      final job = files.takeChildRegisteringOnCall();
      await pump();
      final db = await opener.finish();
      unawaited(job.cancel());
      await gate.release();
      await job.done;

      expect(job.outcome, isA<Cancelled>());
      expect(db.closed, isTrue);
    });

    test('discard closes the result the caller never got', () async {
      final job = files.openWithDiscardAndChild();
      unawaited(job.value.onError((_, __) => Database('none', trace)));
      await pump();
      final db = await opener.finish();
      await pump();
      unawaited(job.cancel());
      await gate.release();
      await job.done;

      expect(job.outcome, isA<Cancelled>());
      expect(db.closed, isTrue);
    });
  });

  group('Handing a resource to the state', () {
    test("the first attempt closes the state's database", () async {
      final job = files.handOverKeepingRegistration();
      await pump();
      final db = await opener.finish();
      await job.done;

      final state = files.currentState;
      expect(state, isA<Ready>());
      expect((state as Ready).db, same(db));
      expect(db.closed, isTrue);
    });

    test('disown before the checkpoint leaves nobody holding it', () async {
      final job = files.handOverDisowningFirst();
      await pump();
      final db = await opener.finish();
      unawaited(job.cancel());
      await gate.release();
      await job.done;

      expect(trace, isNot(contains('body went past emit')));
      expect(files.currentState, isA<Idle>());
      expect(db.closed, isFalse);
    });

    test('check before disown keeps cleanup holding it', () async {
      final job = files.handOverChecked();
      await pump();
      final db = await opener.finish();
      unawaited(job.cancel());
      await gate.release();
      await job.done;

      expect(trace, isNot(contains('body went past emit')));
      expect(files.currentState, isA<Idle>());
      expect(db.closed, isTrue);
    });

    test('a listener cancelling from emit leaves the state owning it',
        () async {
      late final SoloJob<void> job;
      files.addListener(() {
        if (files.currentState is Ready) {
          unawaited(job.cancel());
        }
      });
      job = files.handOverWatched();
      await pump();
      final db = await opener.finish();
      await job.done;

      expect(trace, isNot(contains('body went past emit')));
      expect(job.outcome, isA<Cancelled>());
      expect(files.currentState, isA<Ready>());
      expect(db.closed, isFalse);
    });

    test('a checkpoint between the transfer and disown loses the file',
        () async {
      final job = files.archiveThroughCheckpoint();
      await pump();
      await opener.finish();
      unawaited(job.cancel());
      await gate.release();
      await job.done;

      expect(trace, isNot(contains('registration dropped')));
      expect(
        trace,
        containsAllInOrder(<String>['archive took db', 'db closed']),
      );
    });

    test('a rule that stops holding throws before the transfer', () async {
      final job = files.archiveProtectedByJoin();
      await pump();
      final db = await opener.finish();
      files.loseTheScreen();
      await gate.release();
      await job.done;

      expect(job.outcome, isA<Cancelled>());
      expect(trace, isNot(contains('archive took db')));
      expect(trace, isNot(contains('registration dropped')));
      expect(db.closed, isTrue);
    });

    test('the protected section hands it over whole', () async {
      final job = files.archiveProtected();
      await pump();
      final db = await opener.finish();
      unawaited(job.cancel());
      await gate.release();
      await job.done;

      expect(trace, contains('registration dropped'));
      expect(job.outcome, isA<Cancelled>());
      expect(db.closed, isFalse);
    });
  });

  group('When the release happens', () {
    test('wait releases after the next job has started', () async {
      final job = files.tempByWait();
      final next = files.next();
      await pump();
      unawaited(job.cancel());
      await job.done;
      await gate.release();
      await next.done;

      expect(
        trace,
        containsAllInOrder(<String>['next job started', 'temp closed']),
      );
    });

    test('join releases before the next job starts', () async {
      final job = files.tempByJoin();
      final next = files.next();
      await pump();
      unawaited(job.cancel());
      await pump();
      await gate.release();
      await next.done;

      expect(
        trace,
        containsAllInOrder(<String>['temp closed', 'next job started']),
      );
      expect(trace, isNot(contains('body went on')));
    });
  });

  group('Cleanup order and late results', () {
    test('a discard needed mid-cleanup runs after the disposers', () async {
      final job = files.discardOnTop();
      unawaited(job.value.onError((_, __) => Database('none', trace)));
      await pump();
      final db = await opener.finish();
      await pump();
      unawaited(job.cancel());
      await pump();
      await gate.release();
      await job.done;

      expect(
        trace,
        containsAllInOrder(<String>[
          'disposer B done',
          'disposer A',
          'db closed',
        ]),
      );
      expect(db.closed, isTrue);
    });

    test('a cleanup error reaches the hook and leaves the outcome', () async {
      final seen = <Object>[];
      Solo.errorHandler = (solo, job, error, stackTrace) => seen.add(error);
      final job = files.cleanupThrows();
      await job.done;

      expect(seen, <Matcher>[isStateError]);
      expect(job.outcome, isA<Done<void>>());
    });

    test('a Cancelled from cleanup reaches the hook too', () async {
      final seen = <Object>[];
      Solo.errorHandler = (solo, job, error, stackTrace) => seen.add(error);
      final job = files.cleanupCancels();
      await job.done;

      expect(seen, <Matcher>[isA<Cancelled>()]);
    });

    test('a Cancelled from cleanup never reaches the zone', () async {
      final quietZone = <Object>[];
      final quiet = Completer<void>();
      unawaited(
        runZonedGuarded(
          () async {
            await files.cleanupCancels().done;
            quiet.complete();
          },
          (error, stackTrace) => quietZone.add(error),
        ),
      );
      await quiet.future;
      await pump();

      final loudZone = <Object>[];
      final loud = Completer<void>();
      unawaited(
        runZonedGuarded(
          () async {
            await files.cleanupThrows().done;
            loud.complete();
          },
          (error, stackTrace) => loudZone.add(error),
        ),
      );
      await loud.future;
      await pump();

      expect(quietZone, isEmpty);
      expect(loudZone, <Matcher>[isStateError]);
    });
  });
}

Future<void> pump() => Future<void>.delayed(Duration.zero);
