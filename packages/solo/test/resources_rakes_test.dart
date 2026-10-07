@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/page_code.dart';
import 'support/resources_first_attempts.dart' as first;
import 'support/resources_page.dart' as page;
import 'support/resources_stubs.dart';

/// The sentinel of `doc/resources.md`.
///
/// The code of the page stands verbatim in `test/support/resources_*.dart`:
/// the first and second attempts in one file, the versions that work and
/// the block the page opens with in another. The tests below run that code
/// and pin what the prose, the tables and the comments of the page say about
/// it: who closes the resource in the end, and when. What the page states of
/// the engine and its code does not show is pinned on `Bench`, a controller
/// whose bodies are written where they are run.
///
/// Every call of a stub runs until the test ends it, so each trace is the
/// order the test set and no timer decides it.

/// An observer that keeps what `onError` told it.
final class _Watching extends SoloObserver {
  final heard = <Object>[];

  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) =>
      heard.add(error);
}

/// What whoever awaited `value` of a job got, and what had happened by then.
final class _Caller<T> {
  T? value;
  Object? error;
  List<String>? traceThen;

  _Caller(Job<T> job) {
    job.value.then<void>(
      (got) {
        value = got;
        traceThen = List.of(stage.trace);
      },
      onError: (Object thrown) {
        error = thrown;
      },
    );
  }
}

String _page() => File('doc/resources.md').readAsStringSync();

/// The page with every run of whitespace turned into one space, so that a
/// phrase is found wherever its lines were broken.
String _prose() => _page().replaceAll(RegExp(r'\s+'), ' ');

/// The rows of the table under [header], first cell to second.
Map<String, String> _rows(String header) {
  final lines = _page().split('\n');
  final start = lines.indexOf(header);
  if (start < 0) {
    throw StateError('doc/resources.md has no table "$header"');
  }

  return {
    for (final line
        in lines.skip(start + 2).takeWhile((l) => l.startsWith('|')))
      line.split('|')[1].trim(): line.split('|')[2].trim(),
  };
}

/// Holds the page to [phrase]: the test that calls this runs what the phrase
/// says, so a page that stops saying it leaves the test with nothing to
/// stand for.
void _says(String phrase) => expect(
      _prose(),
      contains(phrase),
      reason: 'doc/resources.md no longer says this',
    );

/// Runs [body] under fake time, in a zone of its own, and returns the errors
/// that reached that zone uncaught. Nothing is asserted inside: an `expect`
/// that failed in there would be one more error of the list.
List<String> _zone(void Function(FakeAsync async) body) {
  final errors = <String>[];
  fakeAsync((async) {
    runZonedGuarded(
      () => body(async),
      (error, stackTrace) => errors.add('$error'),
    );
    async.flushTimers();
  });

  return errors;
}

/// Ends [call] of a stub the way it would end on its own, and lets whatever
/// waited for it go on.
void _end(FakeAsync async, String call) {
  stage.end(call);
  async.flushMicrotasks();
}

/// Fails [call] of a stub with [error].
void _fail(FakeAsync async, String call, Object error) {
  stage.fail(call, error);
  async.flushMicrotasks();
}

/// The database the code under test opened.
Database get _db => stage.databases.single;

/// The temporary file the code under test made.
TempFile get _file => stage.files.single;

/// A child that opens the database and hands it to its parent.
SoloJob<Database> _connect(Bench bench, {bool cancellable = true}) =>
    bench.job<AppState, Database>(
      key: 'connect',
      cancellable: cancellable,
      (ctx) => ctx.join(Database.open, discard: (db) => db.close()),
    );

/// The three calls of the table, by the name the page gives them.
const _calls = ['ctx.abandonable', 'ctx.join', 'ctx.run'];

/// A job that takes a database through [call] with [dispose] or [discard],
/// and then waits out a step named `step`.
SoloJob<void> _take(
  Bench bench,
  String call, {
  FutureOr<void> Function(Database db)? dispose,
  FutureOr<void> Function(Database db)? discard,
}) =>
    bench.run<Idle, void>(key: 'take', (ctx) async {
      switch (call) {
        case 'ctx.abandonable':
          await ctx.abandonable(
            Database.open,
            dispose: dispose,
            discard: discard,
          );
        case 'ctx.join':
          await ctx.join(Database.open, dispose: dispose, discard: discard);
        default:
          await ctx.run(_connect(bench), dispose: dispose, discard: discard);
      }
      await ctx.join(() => stage.start<void>('step', null));
    });

/// A job that registers the release of a database through `ctx.onDispose` or
/// `ctx.onDiscard`, and then waits out a step named `step`.
SoloJob<void> _register(Bench bench, String member) =>
    bench.run<Idle, void>(key: 'register', (ctx) async {
      final db = await Database.open();
      if (member == 'ctx.onDispose') {
        ctx.onDispose(db.close);
      } else {
        ctx.onDiscard(db.close);
      }
      await ctx.join(() => stage.start<void>('step', null));
    });

void main() {
  setUp(() => stage = Stage());

  tearDown(() {
    stage.dispose();
    Solo.observer = null;
    Solo.errorHandler = null;
  });

  group('The opening block', () {
    test('nobody cancels: the state has the database, the caller the file', () {
      fakeAsync((async) {
        final opening = page.Opening();
        final job = opening.start();
        final caller = _Caller(job);
        async.flushMicrotasks();
        _end(async, 'open');
        _end(async, 'openTemp');

        final state = opening.currentState;
        expect(state, isA<Ready>());
        expect((state as Ready).db, same(_db));
        expect(_db.closed, isFalse, reason: 'the state owns it from here on');
        expect(caller.value, same(_file));
        expect(_file.deleted, isFalse, reason: 'it left with the result');
        expect(stage.trace, [
          'subscription made',
          'open start',
          'open end',
          'openTemp start',
          'openTemp end',
          'subscription cancelled',
        ]);
      });
    });

    test('cancelled while the database opens: closed on the spot', () {
      fakeAsync((async) {
        final opening = page.Opening();
        final job = opening.start();
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        expect(job.outcome, isNull, reason: 'join stays with the call');

        _end(async, 'open');
        expect('${job.outcome}', 'Cancelled(manual)');
        expect(_db.closes, 1);
        expect(stage.files, isEmpty);
        expect(opening.currentState, isA<Idle>());
        expect(stage.trace, [
          'subscription made',
          'open start',
          'open end',
          'close start',
          'close end',
          'subscription cancelled',
        ]);
      });
    });

    test('cancelled while the file opens: the file goes, then the database',
        () {
      fakeAsync((async) {
        final opening = page.Opening();
        final job = opening.start();
        async.flushMicrotasks();
        _end(async, 'open');
        unawaited(job.cancel());
        async.flushMicrotasks();
        _end(async, 'openTemp');

        expect('${job.outcome}', 'Cancelled(manual)');
        expect(_file.deletes, 1, reason: 'it reaches nobody');
        expect(_db.closes, 1);
        expect(opening.currentState, isA<Idle>());
        expect(stage.trace, [
          'subscription made',
          'open start',
          'open end',
          'openTemp start',
          'openTemp end',
          'delete start',
          'delete end',
          'close start',
          'close end',
          'subscription cancelled',
        ]);
      });
    });

    test('a listener cancelling from inside emit: the state keeps it', () {
      fakeAsync((async) {
        final opening = page.Opening();
        late final Job<TempFile> job;
        opening.addListener(() {
          if (opening.currentState is Ready) {
            unawaited(job.cancel());
          }
        });
        job = opening.start();
        async.flushMicrotasks();
        _end(async, 'open');
        _end(async, 'openTemp');

        expect('${job.outcome}', 'Cancelled(manual)');
        expect(opening.currentState, isA<Ready>());
        expect(_db.closed, isFalse, reason: 'the state owns it');
        expect(_file.deletes, 1, reason: 'the job ended cancelled');
      });
    });
  });

  group('The table', () {
    test('has the five rows these tests run', () {
      expect(_rows('| Member | What it releases, and when |'), {
        '`dispose:` on `ctx.abandonable`, `ctx.join` or `ctx.run`':
            "that call's value, whatever the outcome",
        '`discard:` on `ctx.abandonable`, `ctx.join` or `ctx.run`':
            "that call's value, and only if the job ends cancelled or failed",
        '`ctx.onDispose(callback)`':
            'whatever the callback closes, whatever the outcome',
        '`ctx.onDiscard(callback)`':
            'whatever the callback closes, and only if the job ends cancelled '
                'or failed',
        '`ctx.disown(value)`':
            'nothing — it drops the registration one of those three calls '
                'made for the value',
      });
    });

    for (final call in _calls) {
      group('dispose: on $call releases the value', () {
        test('when the job ends done', () {
          fakeAsync((async) {
            final job = _take(Bench(), call, dispose: (db) => db.close());
            async.flushMicrotasks();
            _end(async, 'open');
            expect(_db.closed, isFalse, reason: 'the body has it');

            _end(async, 'step');
            expect('${job.outcome}', 'Done(null)');
            expect(_db.closes, 1);
          });
        });

        test('when the job ends cancelled', () {
          fakeAsync((async) {
            final job = _take(Bench(), call, dispose: (db) => db.close());
            async.flushMicrotasks();
            _end(async, 'open');
            unawaited(job.cancel());
            _end(async, 'step');

            expect('${job.outcome}', 'Cancelled(manual)');
            expect(_db.closes, 1);
          });
        });

        test('when the job ends failed', () {
          fakeAsync((async) {
            final job = _take(Bench(), call, dispose: (db) => db.close())
              ..ignoreFailure();
            async.flushMicrotasks();
            _end(async, 'open');
            _fail(async, 'step', StateError('the step failed'));

            expect(job.outcome, isA<Failed>());
            expect(_db.closes, 1);
          });
        });
      });

      group('discard: on $call', () {
        test('keeps the value when the job ends done', () {
          fakeAsync((async) {
            final job = _take(Bench(), call, discard: (db) => db.close());
            async.flushMicrotasks();
            _end(async, 'open');
            _end(async, 'step');

            expect('${job.outcome}', 'Done(null)');
            expect(_db.closed, isFalse);
          });
        });

        test('releases the value when the job ends cancelled', () {
          fakeAsync((async) {
            final job = _take(Bench(), call, discard: (db) => db.close());
            async.flushMicrotasks();
            _end(async, 'open');
            unawaited(job.cancel());
            _end(async, 'step');

            expect('${job.outcome}', 'Cancelled(manual)');
            expect(_db.closes, 1);
          });
        });

        test('releases the value when the job ends failed', () {
          fakeAsync((async) {
            final job = _take(Bench(), call, discard: (db) => db.close())
              ..ignoreFailure();
            async.flushMicrotasks();
            _end(async, 'open');
            _fail(async, 'step', StateError('the step failed'));

            expect(job.outcome, isA<Failed>());
            expect(_db.closes, 1);
          });
        });
      });

      test('ctx.disown drops the registration $call made for the value', () {
        fakeAsync((async) {
          final found = <bool>[];
          final bench = Bench();
          final job = bench.run<Idle, void>((ctx) async {
            FutureOr<void> close(Database db) => db.close();
            final db = switch (call) {
              'ctx.abandonable' =>
                await ctx.abandonable(Database.open, dispose: close),
              'ctx.join' => await ctx.join(Database.open, dispose: close),
              _ => await ctx.run(_connect(bench), dispose: close),
            };
            found
              ..add(ctx.disown(db))
              ..add(ctx.disown(db));
          });
          async.flushMicrotasks();
          _end(async, 'open');

          expect(found, [true, false]);
          expect('${job.outcome}', 'Done(null)');
          expect(_db.closed, isFalse, reason: 'disown releases nothing');
        });
      });
    }

    for (final outcome in ['done', 'cancelled', 'failed']) {
      test('ctx.onDispose runs its callback when the job ends $outcome', () {
        fakeAsync((async) {
          final job = _register(Bench(), 'ctx.onDispose')..ignoreFailure();
          async.flushMicrotasks();
          _end(async, 'open');
          if (outcome == 'cancelled') {
            unawaited(job.cancel());
          }
          if (outcome == 'failed') {
            _fail(async, 'step', StateError('the step failed'));
          } else {
            _end(async, 'step');
          }

          expect(_db.closes, 1);
        });
      });
    }

    test('ctx.onDiscard keeps its callback back when the job ends done', () {
      fakeAsync((async) {
        final job = _register(Bench(), 'ctx.onDiscard');
        async.flushMicrotasks();
        _end(async, 'open');
        _end(async, 'step');

        expect(
          '${job.outcome}',
          'Done(null)',
          reason: 'a job that returns nothing ends done all the same',
        );
        expect(_db.closed, isFalse);
      });
    });

    test('ctx.onDiscard runs its callback when the job ends cancelled', () {
      fakeAsync((async) {
        final job = _register(Bench(), 'ctx.onDiscard');
        async.flushMicrotasks();
        _end(async, 'open');
        unawaited(job.cancel());
        _end(async, 'step');

        expect('${job.outcome}', 'Cancelled(manual)');
        expect(_db.closes, 1);
      });
    });

    test('ctx.onDiscard runs its callback when the job ends failed', () {
      fakeAsync((async) {
        final job = _register(Bench(), 'ctx.onDiscard')..ignoreFailure();
        async.flushMicrotasks();
        _end(async, 'open');
        _fail(async, 'step', StateError('the step failed'));

        expect(job.outcome, isA<Failed>());
        expect(_db.closes, 1);
      });
    });
  });

  group('Taking a resource from a call', () {
    group('the first attempt', () {
      test('cancelled while the database opens, it leaves the database open',
          () {
        _says(
          'then `join` throws `Cancelled` in place of the value, and the body '
          'never reaches the line below',
        );
        fakeAsync((async) {
          final loader = first.LoaderRegisteringUnder();
          final job = loader.load();
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          expect(job.outcome, isNull, reason: 'join stays with the call');
          expect(stage.isRunning('open'), isTrue);

          _end(async, 'open');
          expect('${job.outcome}', 'Cancelled(manual)');
          expect(
            stage.trace,
            ['open start', 'open end'],
            reason: 'the body never reached the line below',
          );
          expect(_db.closed, isFalse);

          unawaited(loader.close());
          async.flushMicrotasks();
          expect(_db.closed, isFalse, reason: 'nothing knows it exists');
        });
      });

      test('nobody cancels: the line is reached, and the database is closed',
          () {
        fakeAsync((async) {
          final loader = first.LoaderRegisteringUnder();
          final job = loader.load();
          async.flushMicrotasks();
          _end(async, 'open');
          _end(async, 'readAll');

          expect('${job.outcome}', 'Done(null)');
          expect('${loader.currentState}', 'Loaded([row])');
          expect(_db.closes, 1);
        });
      });

      test('cancelled while the rows are read, it closes the database', () {
        fakeAsync((async) {
          final job = first.LoaderRegisteringUnder().load();
          async.flushMicrotasks();
          _end(async, 'open');
          unawaited(job.cancel());
          _end(async, 'readAll');

          expect('${job.outcome}', 'Cancelled(manual)');
          expect(_db.closes, 1);
        });
      });
    });

    group('the release that travels with the call', () {
      test('closes the database the body never got, before the next job', () {
        _says(
          '`join` awaits that release before it throws, so the next job in the '
          'queue starts with the database already closed',
        );
        fakeAsync((async) {
          stage.endsByItself.remove('close');
          final loader = page.Loader();
          final job = loader.load();
          final next = loader.next();
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          _end(async, 'open');

          expect(stage.isRunning('close'), isTrue);
          expect(
            job.outcome,
            isNull,
            reason: 'join awaits that release before it throws',
          );
          expect(next.outcome, isNull);

          _end(async, 'close');
          expect('${job.outcome}', 'Cancelled(manual)');
          expect(stage.trace, [
            'open start',
            'open end',
            'close start',
            'close end',
            'next job started',
          ]);
        });
      });

      test('closes it on success, once the rows are the state', () {
        fakeAsync((async) {
          final loader = page.Loader();
          final job = loader.load();
          async.flushMicrotasks();
          _end(async, 'open');
          _end(async, 'readAll');

          expect('${job.outcome}', 'Done(null)');
          expect('${loader.currentState}', 'Loaded([row])');
          expect(_db.closes, 1);
        });
      });

      test('closes it on failure', () {
        fakeAsync((async) {
          final loader = page.Loader();
          final job = loader.load()..ignoreFailure();
          async.flushMicrotasks();
          _end(async, 'open');
          _fail(async, 'readAll', StateError('the read failed'));

          expect(job.outcome, isA<Failed>());
          expect(loader.currentState, isA<Idle>());
          expect(_db.closes, 1);
        });
      });

      test('closes it on a cancellation that arrives after the value', () {
        fakeAsync((async) {
          final job = page.Loader().load();
          async.flushMicrotasks();
          _end(async, 'open');
          unawaited(job.cancel());
          _end(async, 'readAll');

          expect('${job.outcome}', 'Cancelled(manual)');
          expect(_db.closes, 1);
        });
      });
    });

    test('a release registered twice closes the same database twice', () {
      _says('would close the same database twice');
      fakeAsync((async) {
        final job = Bench().run<Idle, void>(
          key: 'load',
          (ctx) async {
            final db = await ctx.join(
              Database.open,
              dispose: (db) => db.close(),
            );
            ctx.onDispose(db.close);

            final rows = await ctx.join(db.readAll);
            ctx.emit(Loaded(rows));
          },
        );
        async.flushMicrotasks();
        _end(async, 'open');
        _end(async, 'readAll');

        expect('${job.outcome}', 'Done(null)');
        expect(_db.closes, 2);
      });
    });

    test(
        'abandonable releases a value that did not reach the body as it '
        'arrives', () {
      fakeAsync((async) {
        final job =
            _take(Bench(), 'ctx.abandonable', dispose: (db) => db.close());
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        expect('${job.outcome}', 'Cancelled(manual)');
        expect(stage.isRunning('open'), isTrue);

        _end(async, 'open');
        expect(_db.closes, 1);
      });
    });

    test('the function onDispose returned unregisters without running', () {
      _says('to unregister the callback without running it');
      fakeAsync((async) {
        final job = Bench().run<Idle, void>((ctx) async {
          final removeDisposer = ctx.onDispose(
            () => stage.trace.add('the release it unregistered'),
          );
          ctx.onDispose(() => stage.trace.add('another release'));
          removeDisposer();
        });
        async.flushMicrotasks();

        expect('${job.outcome}', 'Done(null)');
        expect(stage.trace, ['another release']);
      });
    });

    group('under a cancellation an uncancellable section let through', () {
      /// The pair of the opening block, after a step a cancellation waits
      /// out.
      SoloJob<void> pair(Bench bench) => bench.run<Idle, void>((ctx) async {
            await ctx.uncancellable(() => stage.start<void>('step', null));
            final sub = device.events.listen(onEvent);
            ctx.onDispose(sub.cancel);
          });

      test('listen with onDispose under it makes the subscription', () {
        fakeAsync((async) {
          final job = pair(Bench());
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          expect(job.isCancelled, isFalse, reason: 'the section holds it');

          _end(async, 'step');
          expect('${job.outcome}', 'Cancelled(manual)');
          expect(stage.trace, [
            'step start',
            'step end',
            'subscription made',
            'subscription cancelled',
          ]);
        });
      });

      test('the creation that rides on a call never makes it', () {
        _says(
          'the subscription is never made at all, where that pair makes it and '
          'cancels it during cleanup',
        );
        fakeAsync((async) {
          final job = page.Watcher().watch('step');
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          _end(async, 'step');

          expect('${job.outcome}', 'Cancelled(manual)');
          expect(stage.trace, ['step start', 'step end']);
        });
      });
    });

    test('with nobody cancelling, the call makes it and cancels it at the end',
        () {
      fakeAsync((async) {
        final job = page.Watcher().watch('step');
        async.flushMicrotasks();
        _end(async, 'step');

        expect('${job.outcome}', 'Done(null)');
        expect(stage.trace, [
          'step start',
          'step end',
          'subscription made',
          'subscription cancelled',
        ]);
      });
    });

    test(
        'abandonable takes an action that returns without waiting just as well',
        () {
      fakeAsync((async) {
        final job = Bench().run<Idle, void>((ctx) async {
          await ctx.abandonable(
            () => device.events.listen(onEvent),
            dispose: (sub) => sub.cancel(),
          );
        });
        async.flushMicrotasks();

        expect('${job.outcome}', 'Done(null)');
        expect(stage.trace, ['subscription made', 'subscription cancelled']);
      });
    });
  });

  group('Returning a resource to the caller', () {
    group('the first attempt', () {
      test('hands the caller a database closed a moment earlier', () {
        _says(
          "the caller's `await` then completes with a handle that was closed a "
          'moment earlier',
        );
        fakeAsync((async) {
          final job = first.OpenerDisposing().open();
          final caller = _Caller(job);
          async.flushMicrotasks();
          _end(async, 'open');
          _end(async, 'readAll');

          expect(job.outcome, isA<Done<Database>>());
          expect(caller.value, same(_db));
          expect(_db.closes, 1);
          expect(
            caller.traceThen,
            containsAllInOrder(['readAll end', 'close start', 'close end']),
            reason: 'cleanup runs before the outcome is delivered',
          );
        });
      });

      test('cancelled while the database opens, does what it should', () {
        fakeAsync((async) {
          final job = first.OpenerDisposing().open();
          final caller = _Caller(job);
          async.flushMicrotasks();
          unawaited(job.cancel());
          _end(async, 'open');

          expect(caller.error, same(job.outcome));
          expect('${job.outcome}', 'Cancelled(manual)');
          expect(_db.closes, 1);
        });
      });

      test('cancelled while the child reads, does what it should', () {
        fakeAsync((async) {
          final job = first.OpenerDisposing().open();
          final caller = _Caller(job);
          async.flushMicrotasks();
          _end(async, 'open');
          unawaited(job.cancel());
          _end(async, 'readAll');

          expect(caller.error, same(job.outcome));
          expect('${job.outcome}', 'Cancelled(manual)');
          expect(_db.closes, 1);
        });
      });
    });

    group('discard', () {
      test('leaves the database open for the caller on success', () {
        fakeAsync((async) {
          final job = page.Opener().open();
          final caller = _Caller(job);
          async.flushMicrotasks();
          _end(async, 'open');
          _end(async, 'readAll');

          expect(job.outcome, isA<Done<Database>>());
          expect(caller.value, same(_db));
          expect(_db.closed, isFalse);
        });
      });

      test('closes it when a cancellation arrives while the child reads', () {
        _says(
          'the caller receives `Cancelled` instead of the database, and '
          '`discard` closes it',
        );
        fakeAsync((async) {
          final job = page.Opener().open();
          final caller = _Caller(job);
          async.flushMicrotasks();
          _end(async, 'open');
          unawaited(job.cancel());
          async.flushMicrotasks();
          expect(job.outcome, isNull, reason: 'the child waits its read out');

          _end(async, 'readAll');
          expect(
            caller.error,
            same(job.outcome),
            reason: 'the caller receives Cancelled instead of the database',
          );
          expect('${job.outcome}', 'Cancelled(manual)');
          expect(_db.closes, 1);
        });
      });

      test('closes it when the cancellation arrives while it opens', () {
        fakeAsync((async) {
          final job = page.Opener().open();
          async.flushMicrotasks();
          unawaited(job.cancel());
          _end(async, 'open');

          expect('${job.outcome}', 'Cancelled(manual)');
          expect(_db.closes, 1);
        });
      });

      test('closes it when the job fails', () {
        fakeAsync((async) {
          final job = page.Opener().open();
          final caller = _Caller(job);
          async.flushMicrotasks();
          _end(async, 'open');
          _fail(async, 'readAll', StateError('the read failed'));

          expect(job.outcome, isA<Failed>());
          expect(caller.error, isStateError);
          expect(_db.closes, 1);
        });
      });

      test('a job that ended Done has handed it over, read or not', () {
        _says('a caller that never does leaves the database open');
        fakeAsync((async) {
          final opener = page.Opener();
          final job = opener.open();
          async.flushMicrotasks();
          _end(async, 'open');
          _end(async, 'readAll');
          expect(job.outcome, isA<Done<Database>>());

          unawaited(opener.close());
          async.flushMicrotasks();
          expect(opener.isFinished, isTrue);
          expect(
            _db.closed,
            isFalse,
            reason: 'a caller that never reads value leaves it open',
          );
        });
      });
    });

    for (final call in _calls) {
      test('both callbacks on $call are an ArgumentError, before it starts',
          () {
        fakeAsync((async) {
          Object? thrown;
          final bench = Bench();
          final job = bench.run<Idle, void>((ctx) async {
            FutureOr<void> close(Database db) => db.close();
            try {
              switch (call) {
                case 'ctx.abandonable':
                  await ctx.abandonable(
                    Database.open,
                    dispose: close,
                    discard: close,
                  );
                case 'ctx.join':
                  await ctx.join(Database.open, dispose: close, discard: close);
                default:
                  await ctx.run(
                    _connect(bench),
                    dispose: close,
                    discard: close,
                  );
              }
            } on Object catch (error) {
              thrown = error;
            }
          });
          async.flushMicrotasks();

          expect(thrown, isArgumentError);
          expect(stage.trace, isEmpty, reason: 'nothing was started');
          expect('${job.outcome}', 'Done(null)');
        });
      });
    }

    group('a parent that takes the database from a child', () {
      /// The registration on the line under `ctx.run`.
      SoloJob<void> under(Bench bench, SoloJob<Database> child) =>
          bench.run<Idle, void>(key: 'take', (ctx) async {
            final db = await ctx.run(child);
            ctx.onDiscard(db.close);
            await ctx.join(() => stage.start<void>('step', null));
          });

      /// The registration on the call.
      SoloJob<void> onTheCall(Bench bench, SoloJob<Database> child) =>
          bench.run<Idle, void>(key: 'take', (ctx) async {
            await ctx.run(child, discard: (db) => db.close());
            await ctx.join(() => stage.start<void>('step', null));
          });

      test('registering on the line under ctx.run is too late', () {
        _says("`ctx.run` checks the parent once the child's value is in hand");
        fakeAsync((async) {
          final bench = Bench();
          final job = under(bench, _connect(bench, cancellable: false));
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          _end(async, 'open');

          expect('${job.outcome}', 'Cancelled(manual)');
          expect(
            stage.trace,
            ['open start', 'open end'],
            reason: 'the line under the call was never reached',
          );
          expect(_db.closed, isFalse, reason: 'the value went with the throw');
        });
      });

      test('registering on the call closes it', () {
        fakeAsync((async) {
          final bench = Bench();
          final job = onTheCall(bench, _connect(bench, cancellable: false));
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          _end(async, 'open');

          expect('${job.outcome}', 'Cancelled(manual)');
          expect(_db.closes, 1);
        });
      });

      test('the checkpoint of ctx.run asks the state rules of the parent too',
          () {
        fakeAsync((async) {
          var holds = true;
          final bench = Bench();
          final job = bench.run<Idle, void>(
            key: 'take',
            keepWhile: (state) => holds,
            (ctx) async {
              final db = await ctx.run(_connect(bench));
              ctx.onDiscard(db.close);
            },
          );
          async.flushMicrotasks();
          holds = false;
          _end(async, 'open');

          expect('${job.outcome}', 'Cancelled(rules: keepWhile)');
          expect(_db.closed, isFalse);
        });
      });

      test('nobody cancels before the value: the line under registers it', () {
        fakeAsync((async) {
          final bench = Bench();
          final job = under(bench, _connect(bench));
          async.flushMicrotasks();
          _end(async, 'open');
          unawaited(job.cancel());
          _end(async, 'step');

          expect('${job.outcome}', 'Cancelled(manual)');
          expect(_db.closes, 1);
        });
      });
    });
  });

  group('Handing a resource to the state', () {
    group('the first attempt', () {
      test('closes the database the screen is holding', () {
        _says('`dispose` closes the database the screen is holding');
        fakeAsync((async) {
          final handover = first.HandoverKeeping();
          final seen = <bool>[];
          handover.addListener(() {
            final state = handover.currentState;
            if (state is Ready) {
              seen.add(state.db.closed);
            }
          });
          final job = handover.hand();
          async.flushMicrotasks();
          _end(async, 'open');
          _end(async, 'migrate');

          final state = handover.currentState;
          expect('${job.outcome}', 'Done(null)');
          expect(seen, [false], reason: 'the write goes through');
          expect(state, isA<Ready>());
          expect((state as Ready).db, same(_db));
          expect(_db.closes, 1, reason: 'the registration still stood');
        });
      });
    });

    group('the second attempt', () {
      test('cancelled while the migration runs, leaves nobody holding it', () {
        _says('Cancel this job while the migration runs');
        _says(
          'the state never received the database, the cleanup stack no longer '
          'knows about it, and nobody closes it',
        );
        fakeAsync((async) {
          final handover = first.HandoverDisowning();
          final job = handover.hand();
          async.flushMicrotasks();
          _end(async, 'open');
          unawaited(job.cancel());
          async.flushMicrotasks();
          expect(job.isCancelled, isFalse, reason: 'the section holds it back');
          expect(
            '${handover.pending}',
            'SoloPending([hand] in its body, holding Cancelled(manual) back)',
          );

          _end(async, 'migrate');
          expect('${job.outcome}', 'Cancelled(manual)');
          expect(handover.currentState, isA<Idle>());
          expect(_db.closed, isFalse);

          unawaited(handover.close());
          async.flushMicrotasks();
          expect(_db.closed, isFalse, reason: 'nobody closes it');
        });
      });

      test('the state rules stop holding during the migration: the same', () {
        fakeAsync((async) {
          final handover = first.HandoverDisowning();
          final job = handover.hand();
          async.flushMicrotasks();
          _end(async, 'open');
          handover.reflect(const Loaded([]));
          _end(async, 'migrate');

          expect('${job.outcome}', 'Cancelled(rules: is not Idle)');
          expect('${handover.currentState}', 'Loaded([])');
          expect(_db.closed, isFalse);
        });
      });

      test('nobody cancels: the state owns the database', () {
        fakeAsync((async) {
          final handover = first.HandoverDisowning();
          final job = handover.hand();
          async.flushMicrotasks();
          _end(async, 'open');
          _end(async, 'migrate');

          expect('${job.outcome}', 'Done(null)');
          expect(handover.currentState, isA<Ready>());
          expect(_db.closed, isFalse);
        });
      });
    });

    group('check, disown, emit', () {
      test('cancelled while the migration runs: cleanup closes the database',
          () {
        _says(
          '`check` throws first if the job is cancelled or its rules no longer '
          'hold, and the database is still registered: cleanup closes it',
        );
        fakeAsync((async) {
          final handover = page.Handover();
          final job = handover.hand();
          async.flushMicrotasks();
          _end(async, 'open');
          unawaited(job.cancel());
          _end(async, 'migrate');

          expect('${job.outcome}', 'Cancelled(manual)');
          expect(handover.currentState, isA<Idle>());
          expect(_db.closes, 1);
        });
      });

      test('the state rules stop holding: check throws, cleanup closes it', () {
        fakeAsync((async) {
          final handover = page.Handover();
          final job = handover.hand();
          async.flushMicrotasks();
          _end(async, 'open');
          handover.reflect(const Loaded([]));
          _end(async, 'migrate');

          expect('${job.outcome}', 'Cancelled(rules: is not Idle)');
          expect('${handover.currentState}', 'Loaded([])');
          expect(_db.closes, 1);
        });
      });

      test('nobody cancels: the state owns the database', () {
        fakeAsync((async) {
          final handover = page.Handover();
          final job = handover.hand();
          async.flushMicrotasks();
          _end(async, 'open');
          _end(async, 'migrate');

          final state = handover.currentState;
          expect('${job.outcome}', 'Done(null)');
          expect(state, isA<Ready>());
          expect((state as Ready).db, same(_db));
          expect(_db.closed, isFalse);
        });
      });

      test('a listener cancelling from inside emit: the state owns it', () {
        _says('Either way exactly one owner is left');
        fakeAsync((async) {
          final handover = page.Handover();
          late final Job<void> job;
          handover.addListener(() {
            if (handover.currentState is Ready) {
              unawaited(job.cancel());
            }
          });
          job = handover.hand();
          async.flushMicrotasks();
          _end(async, 'open');
          _end(async, 'migrate');

          expect('${job.outcome}', 'Cancelled(manual)');
          expect(handover.currentState, isA<Ready>());
          expect(_db.closed, isFalse, reason: 'exactly one owner is left');
        });
      });

      test('emit throws after the write when a listener cancelled the job', () {
        fakeAsync((async) {
          final bench = Bench();
          late final SoloJob<void> job;
          bench.addListener(() {
            if (bench.currentState is Ready) {
              unawaited(job.cancel());
            }
          });
          job = bench.run<Idle, void>((ctx) async {
            final db = await ctx.join(
              Database.open,
              dispose: (db) => db.close(),
            );
            ctx
              ..check()
              ..disown(db)
              ..emit(Ready(db));
            stage.trace.add('the body went past emit');
          });
          async.flushMicrotasks();
          _end(async, 'open');

          expect('${job.outcome}', 'Cancelled(manual)');
          expect(bench.currentState, isA<Ready>());
          expect(stage.trace, ['open start', 'open end']);
          expect(_db.closed, isFalse);
        });
      });
    });

    group('a registration made with ctx.onDispose', () {
      test('is not found by disown, and its callback still runs', () {
        _says('`disown` returns `false`, and the callback still runs');
        fakeAsync((async) {
          bool? found;
          final bench = Bench();
          final job = bench.run<Idle, void>((ctx) async {
            final db = await Database.open();
            ctx
              ..onDispose(db.close)
              ..check();
            found = ctx.disown(db);
            ctx.emit(Ready(db));
          });
          async.flushMicrotasks();
          _end(async, 'open');

          expect('${job.outcome}', 'Done(null)');
          expect(found, isFalse);
          expect(bench.currentState, isA<Ready>());
          expect(_db.closes, 1, reason: 'closed under the state');
        });
      });

      test('is dropped by the function onDispose returned', () {
        fakeAsync((async) {
          final bench = Bench();
          final job = bench.run<Idle, void>((ctx) async {
            final db = await Database.open();
            final removeDisposer = ctx.onDispose(db.close);
            ctx.check();
            removeDisposer();
            ctx.emit(Ready(db));
          });
          async.flushMicrotasks();
          _end(async, 'open');

          expect('${job.outcome}', 'Done(null)');
          expect(bench.currentState, isA<Ready>());
          expect(_db.closed, isFalse);
        });
      });
    });

    group('after the hand-over', () {
      test('no job releases the database, and neither does close()', () {
        _says(
          'After the hand-over no job releases the database, and neither does '
          '`close()`',
        );
        fakeAsync((async) {
          final handover = page.Handover();
          final job = handover.hand();
          async.flushMicrotasks();
          _end(async, 'open');
          _end(async, 'migrate');
          expect('${job.outcome}', 'Done(null)');

          final next = handover.next();
          async.flushMicrotasks();
          expect('${next.outcome}', 'Done(null)');
          expect(_db.closed, isFalse);

          unawaited(handover.close());
          async.flushMicrotasks();
          expect(handover.isFinished, isTrue);
          expect(_db.closed, isFalse);
        });
      });

      test('a job that closes it and moves the state on, before close()', () {
        fakeAsync((async) {
          final handover = page.Handover()..hand();
          async.flushMicrotasks();
          _end(async, 'open');
          _end(async, 'migrate');

          // What `dispose()` of such a controller would queue.
          final dispose = handover.run<Ready, void>((ctx) async {
            await ctx.join(ctx.state.db.close);
            ctx.emit(const Idle());
          });
          var over = false;
          dispose.done.then((_) => handover.close()).then((_) => over = true);
          async.flushMicrotasks();

          expect('${dispose.outcome}', 'Done(null)');
          expect(over, isTrue);
          expect(handover.currentState, isA<Idle>());
          expect(_db.closes, 1);
        });
      });
    });

    group('the asynchronous hand-over', () {
      test('nobody cancels: the archive has the file, and nothing deletes it',
          () {
        fakeAsync((async) {
          final job = page.Handover().store();
          async.flushMicrotasks();
          _end(async, 'openTemp');

          expect('${job.outcome}', 'Done(null)');
          expect(stage.archived, [same(_file)]);
          expect(_file.deleted, isFalse);
        });
      });

      test('cancelled during the transfer: the section hands it over whole',
          () {
        fakeAsync((async) {
          stage.endsByItself.remove('take');
          final job = page.Handover().store();
          async.flushMicrotasks();
          _end(async, 'openTemp');
          unawaited(job.cancel());
          async.flushMicrotasks();
          expect(job.isCancelled, isFalse, reason: 'the section holds it back');

          _end(async, 'take');
          expect('${job.outcome}', 'Cancelled(manual)');
          expect(stage.archived, [same(_file)]);
          expect(_file.deleted, isFalse);
        });
      });

      test('the state rules are asked where the section opens', () {
        _says('are asked where the section opens, before the transfer starts');
        fakeAsync((async) {
          final handover = page.Handover();
          final job = handover.store(step: 'step');
          async.flushMicrotasks();
          _end(async, 'openTemp');
          handover.reflect(const Loaded([]));
          _end(async, 'step');

          expect('${job.outcome}', 'Cancelled(rules: is not Idle)');
          expect(stage.archived, isEmpty, reason: 'the transfer never starts');
          expect(_file.deletes, 1, reason: 'still registered');
        });
      });

      test('the state rules stop holding during the transfer: still whole', () {
        fakeAsync((async) {
          stage.endsByItself.remove('take');
          final handover = page.Handover();
          final job = handover.store();
          async.flushMicrotasks();
          _end(async, 'openTemp');
          handover.reflect(const Loaded([]));
          async.flushMicrotasks();
          expect(job.isCancelled, isTrue, reason: 'no section holds a rule');
          expect(job.outcome, isNull);

          _end(async, 'take');
          expect('${job.outcome}', 'Cancelled(rules: is not Idle)');
          expect(stage.archived, [same(_file)]);
          expect(_file.deleted, isFalse);
        });
      });

      group('written without the section', () {
        SoloJob<void> split(Bench bench) => bench.run<Idle, void>((ctx) async {
              final file = await ctx.join(
                openTemp,
                dispose: (file) => file.delete(),
              );
              await ctx.join(() => archive.take(file));
              ctx.disown(file);
            });

        test(
            'cancelled during the transfer: cleanup deletes what the '
            'archive is holding', () {
          fakeAsync((async) {
            stage.endsByItself.remove('take');
            final job = split(Bench());
            async.flushMicrotasks();
            _end(async, 'openTemp');
            unawaited(job.cancel());
            _end(async, 'take');

            expect('${job.outcome}', 'Cancelled(manual)');
            expect(stage.archived, [same(_file)]);
            expect(_file.deletes, 1);
          });
        });

        test('nobody cancels: the pair holds together', () {
          fakeAsync((async) {
            final job = split(Bench());
            async.flushMicrotasks();
            _end(async, 'openTemp');

            expect('${job.outcome}', 'Done(null)');
            expect(stage.archived, [same(_file)]);
            expect(_file.deleted, isFalse);
          });
        });
      });
    });
  });

  group('When the release happens', () {
    group('the first attempt', () {
      test('cancelled, lets the next job start while the file still opens', () {
        _says(
          'the next job starts, or `close()` comes back, while `openTemp` is '
          'still running',
        );
        fakeAsync((async) {
          stage.endsByItself.remove('delete');
          final keeper = first.TempAbandoner();
          final job = keeper.write();
          final next = keeper.next();
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();

          expect('${job.outcome}', 'Cancelled(manual)');
          expect('${next.outcome}', 'Done(null)');
          expect(stage.isRunning('openTemp'), isTrue);
          expect(keeper.pending, isNull, reason: 'nobody waits for either');

          _end(async, 'openTemp');
          expect(stage.isRunning('delete'), isTrue);
          _end(async, 'delete');
          expect(stage.trace, [
            'openTemp start',
            'next job started',
            'openTemp end',
            'delete start',
            'delete end',
          ]);
        });
      });

      test('closed, lets close() come back while the file still opens', () {
        fakeAsync((async) {
          final keeper = first.TempAbandoner();
          final job = keeper.write();
          async.flushMicrotasks();
          var back = false;
          keeper.close().then((_) => back = true);
          async.flushMicrotasks();

          expect(back, isTrue);
          expect('${job.outcome}', 'Cancelled(closed)');
          expect(stage.isRunning('openTemp'), isTrue);

          _end(async, 'openTemp');
          expect(_file.deletes, 1, reason: 'the release happens either way');
        });
      });

      test('nobody cancels: the file is deleted when the job ends', () {
        fakeAsync((async) {
          final job = first.TempAbandoner().write();
          async.flushMicrotasks();
          _end(async, 'openTemp');

          expect('${job.outcome}', 'Done(null)');
          expect(_file.deletes, 1);
        });
      });

      test('a late error from the call is told to onError, then the zone', () {
        _says(
          'A late error from the call or from the disposer is told to the '
          "controller's `onError` hook and then handed to `Solo.errorHandler`, "
          'or to the zone when no handler is set',
        );
        late first.TempAbandoner keeper;
        final errors = _zone((async) {
          keeper = first.TempAbandoner();
          final job = keeper.write();
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          _fail(async, 'openTemp', StateError('the disk is full'));
        });

        expect(keeper.heard, [isStateError]);
        expect(errors, ['Bad state: the disk is full']);
      });

      test('a late error from the disposer goes the same way', () {
        late first.TempAbandoner keeper;
        final errors = _zone((async) {
          stage.endsByItself.remove('delete');
          keeper = first.TempAbandoner();
          final job = keeper.write();
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          _end(async, 'openTemp');
          _fail(async, 'delete', StateError('the file is busy'));
        });

        expect(keeper.heard, [isStateError]);
        expect(errors, ['Bad state: the file is busy']);
      });

      test('with Solo.errorHandler set the late error goes there instead', () {
        final handled = <Object>[];
        Solo.errorHandler =
            (solo, job, error, stackTrace) => handled.add(error);
        late first.TempAbandoner keeper;
        final errors = _zone((async) {
          keeper = first.TempAbandoner();
          final job = keeper.write();
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          _fail(async, 'openTemp', StateError('the disk is full'));
        });

        expect(keeper.heard, [isStateError]);
        expect(handled, [isStateError]);
        expect(errors, isEmpty);
      });
    });

    group('the wait that stays with it', () {
      test('cancelled, deletes the file before the next job starts', () {
        _says('The deletion is part of what the queue waits for');
        fakeAsync((async) {
          stage.endsByItself.remove('delete');
          final keeper = page.TempKeeper();
          final job = keeper.write();
          final next = keeper.next();
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();
          expect(job.outcome, isNull, reason: 'join waits for the call');

          _end(async, 'openTemp');
          expect(stage.isRunning('delete'), isTrue);
          expect(job.outcome, isNull, reason: 'and for the release');
          expect(next.outcome, isNull);

          _end(async, 'delete');
          expect('${job.outcome}', 'Cancelled(manual)');
          expect(stage.trace, [
            'openTemp start',
            'openTemp end',
            'delete start',
            'delete end',
            'next job started',
          ]);
        });
      });

      test('closed, deletes the file before close() comes back', () {
        fakeAsync((async) {
          stage.endsByItself.remove('delete');
          final keeper = page.TempKeeper();
          final job = keeper.write();
          async.flushMicrotasks();
          var back = false;
          keeper.close().then((_) => back = true);
          async.flushMicrotasks();
          _end(async, 'openTemp');
          expect(back, isFalse);
          expect(stage.isRunning('delete'), isTrue);

          _end(async, 'delete');
          expect(back, isTrue);
          expect('${job.outcome}', 'Cancelled(closed)');
        });
      });

      test('nobody cancels: the file is deleted when the job ends', () {
        fakeAsync((async) {
          final job = page.TempKeeper().write();
          async.flushMicrotasks();
          _end(async, 'openTemp');

          expect('${job.outcome}', 'Done(null)');
          expect(_file.deletes, 1);
        });
      });
    });
  });

  group('Cleanup order and late results', () {
    test('has the four rows these tests run', () {
      expect(_rows('| Step | What the job does |'), {
        'Children': 'waits for every child to finish',
        'Cleanup stack':
            'runs it last registration first, awaiting each callback',
        'Second pass':
            'runs a `discard` that cancellation has since made necessary',
        'End': 'gets its outcome, runs its state handler, lets the queue '
            'start the next job',
      });
    });

    /// A job with a child that outlives its body, two disposers and a
    /// discard registered last.
    SoloJob<Database> steps(Bench bench) => bench.run<Idle, Database>(
          key: 'steps',
          ifCancelled: (state, cancelled) {
            stage.trace.add('state handler');

            return state;
          },
          (ctx) async {
            ctx
              ..onDispose(() => stage.start<void>('disposer A', null))
              ..onDispose(() => stage.start<void>('disposer B', null));
            final db = await ctx.join(
              Database.open,
              discard: (db) => db.close(),
            );
            final child = bench.job<Idle, void>(
              cancellable: false,
              (child) => child.join(() => stage.start<void>('child', null)),
            );
            unawaited(ctx.run(child).onError((_, __) {}));

            return db;
          },
        );

    test('children first, then the stack, last registration first', () {
      fakeAsync((async) {
        final bench = Bench();
        final job = steps(bench);
        async.flushMicrotasks();
        _end(async, 'open');
        expect(
          '${bench.pending}',
          'SoloPending([steps] waiting for 1 children)',
        );

        _end(async, 'child');
        expect('${bench.pending}', 'SoloPending([steps] in its cleanup)');
        expect(stage.isRunning('disposer B'), isTrue);
        expect(
          stage.isRunning('disposer A'),
          isFalse,
          reason: 'each callback is awaited',
        );

        _end(async, 'disposer B');
        _end(async, 'disposer A');
        expect(job.outcome, isA<Done<Database>>());
        expect(_db.closed, isFalse);
        expect(stage.trace, [
          'open start',
          'open end',
          'child start',
          'child end',
          'disposer B start',
          'disposer B end',
          'disposer A start',
          'disposer A end',
        ]);
      });
    });

    test('a discard made necessary mid-cleanup runs in a second pass', () {
      fakeAsync((async) {
        final bench = Bench();
        final job = steps(bench)..ignoreFailure();
        final next = bench.next();
        async.flushMicrotasks();
        _end(async, 'open');
        _end(async, 'child');
        unawaited(job.cancel());
        async.flushMicrotasks();
        _end(async, 'disposer B');
        _end(async, 'disposer A');

        expect('${job.outcome}', 'Cancelled(manual)');
        expect('${next.outcome}', 'Done(null)');
        expect(stage.trace, [
          'open start',
          'open end',
          'child start',
          'child end',
          'disposer B start',
          'disposer B end',
          'disposer A start',
          'disposer A end',
          'close start',
          'close end',
          'state handler',
          'next job started',
        ]);
      });
    });

    group('the last row', () {
      test('the outcome is fixed before the state handler runs', () {
        _says('The outcome is fixed first');
        fakeAsync((async) {
          Outcome<void>? seen;
          final bench = Bench();
          late final SoloJob<void> job;
          job = bench.run<Idle, void>(
            ifFailed: (state, error, stackTrace) {
              seen = job.outcome;
              stage.trace.add('state handler');

              return const Loaded(['after the failure']);
            },
            (ctx) async {
              ctx.onDispose(() async => stage.trace.add('cleanup'));
              throw StateError('the body failed');
            },
          )..ignoreFailure();
          bench.next();
          async.flushMicrotasks();

          expect(seen, isA<Failed>());
          expect(seen, same(job.outcome));
          expect('${bench.currentState}', 'Loaded([after the failure])');
          expect(
            stage.trace,
            ['cleanup', 'state handler', 'next job started'],
          );
        });
      });

      test('code that awaits done or value resumes after the next job starts',
          () {
        _says('Code that awaits `done` or `value` resumes after that start');
        fakeAsync((async) {
          final bench = Bench();
          final job = bench.run<Idle, int>((ctx) async => 1);
          bench.next();
          Future<void> awaitValue() async {
            await job.value;
            stage.trace.add('value awaited');
          }

          Future<void> awaitDone() async {
            await job.done;
            stage.trace.add('done awaited');
          }

          unawaited(awaitValue());
          unawaited(awaitDone());
          async.flushMicrotasks();

          expect(stage.trace.first, 'next job started');
          expect(
            stage.trace,
            unorderedEquals(
              ['next job started', 'value awaited', 'done awaited'],
            ),
          );
        });
      });
    });

    group('try/finally', () {
      /// A lock held for one step, released before the body goes on.
      SoloJob<void> stepUnderLock(Bench bench) =>
          bench.run<Idle, void>((ctx) async {
            ctx.onDispose(() async => stage.trace.add('registered cleanup'));
            stage.trace.add('lock taken');
            try {
              await ctx.join(() => stage.start<void>('step', null));
            } finally {
              stage.trace.add('lock released');
            }
            stage.trace.add('body went on without the lock');
          });

      test('releases before the body goes on', () {
        fakeAsync((async) {
          final job = stepUnderLock(Bench());
          async.flushMicrotasks();
          _end(async, 'step');

          expect('${job.outcome}', 'Done(null)');
          expect(stage.trace, [
            'lock taken',
            'step start',
            'step end',
            'lock released',
            'body went on without the lock',
            'registered cleanup',
          ]);
        });
      });

      test('runs when a checkpoint throws inside the try', () {
        _says(
          'A checkpoint throwing inside the `try` runs the `finally` like any '
          'other throw',
        );
        fakeAsync((async) {
          final job = stepUnderLock(Bench());
          async.flushMicrotasks();
          unawaited(job.cancel());
          _end(async, 'step');

          expect('${job.outcome}', 'Cancelled(manual)');
          expect(stage.trace, [
            'lock taken',
            'step start',
            'step end',
            'lock released',
            'registered cleanup',
          ]);
        });
      });

      /// One temporary per turn of a loop, released by `finally` or
      /// registered.
      SoloJob<void> turns(Bench bench, {required bool registered}) =>
          bench.run<Idle, void>((ctx) async {
            for (var turn = 1; turn <= 3; turn++) {
              if (registered) {
                ctx.onDispose(() async => stage.trace.add('$turn released'));
                await ctx.join(() => stage.start<void>('turn $turn', null));
              } else {
                try {
                  await ctx.join(() => stage.start<void>('turn $turn', null));
                } finally {
                  stage.trace.add('$turn released');
                }
              }
            }
          });

      test('releases the temporary of each turn of a loop in that turn', () {
        _says('a temporary of one turn of a loop');
        fakeAsync((async) {
          final job = turns(Bench(), registered: false);
          async.flushMicrotasks();
          _end(async, 'turn 1');
          _end(async, 'turn 2');
          _end(async, 'turn 3');

          expect('${job.outcome}', 'Done(null)');
          expect(stage.trace, [
            'turn 1 start',
            'turn 1 end',
            '1 released',
            'turn 2 start',
            'turn 2 end',
            '2 released',
            'turn 3 start',
            'turn 3 end',
            '3 released',
          ]);
        });
      });

      test('registering those releases piles them up to the end of the job',
          () {
        _says('pile up one registration per turn');
        fakeAsync((async) {
          final job = turns(Bench(), registered: true);
          async.flushMicrotasks();
          _end(async, 'turn 1');
          _end(async, 'turn 2');
          _end(async, 'turn 3');

          expect('${job.outcome}', 'Done(null)');
          expect(stage.trace, [
            'turn 1 start',
            'turn 1 end',
            'turn 2 start',
            'turn 2 end',
            'turn 3 start',
            'turn 3 end',
            '3 released',
            '2 released',
            '1 released',
          ]);
        });
      });

      test('does not cover the time while the children finish', () {
        _says(
          'it alone covers the time after the body returns and while its '
          'children finish',
        );
        fakeAsync((async) {
          final bench = Bench();
          final job = bench.run<Idle, void>((ctx) async {
            ctx.onDispose(() async => stage.trace.add('registered release'));
            try {
              final child = bench.job<Idle, void>(
                (child) => child.join(() => stage.start<void>('child', null)),
              );
              unawaited(ctx.run(child).onError((_, __) {}));
            } finally {
              stage.trace.add('finally release');
            }
          });
          async.flushMicrotasks();
          expect(stage.isRunning('child'), isTrue);

          _end(async, 'child');
          expect('${job.outcome}', 'Done(null)');
          expect(stage.trace, [
            'child start',
            'finally release',
            'child end',
            'registered release',
          ]);
        });
      });
    });

    group('an error thrown by cleanup', () {
      SoloJob<void> cleanupThrows(Bench bench, Object error) =>
          bench.run<Idle, void>((ctx) async {
            // ignore: only_throw_errors
            ctx.onDispose(() async => throw error);
          });

      test('is told to onError and to Solo.observer, then goes to the zone',
          () {
        _says(
          "An error thrown by cleanup is told to the controller's `onError` "
          'hook and to `Solo.observer`, and then handed to '
          '`Solo.errorHandler`, or to the zone when no handler is set',
        );
        _says('cleanup that throws leaves a `Done` job `Done`');
        final watching = _Watching();
        Solo.observer = watching;
        late Bench bench;
        late Job<void> job;
        final errors = _zone((async) {
          bench = Bench();
          job = cleanupThrows(bench, StateError('the cleanup failed'));
          async.flushMicrotasks();
        });

        expect(bench.heard, [isStateError]);
        expect(watching.heard, [isStateError]);
        expect(errors, ['Bad state: the cleanup failed']);
        expect('${job.outcome}', 'Done(null)', reason: 'Done stays Done');
      });

      test('goes to Solo.errorHandler instead of the zone when one is set', () {
        final handled = <Object>[];
        Solo.errorHandler =
            (solo, job, error, stackTrace) => handled.add(error);
        late Bench bench;
        final errors = _zone((async) {
          bench = Bench();
          cleanupThrows(bench, StateError('the cleanup failed'));
          async.flushMicrotasks();
        });

        expect(bench.heard, [isStateError]);
        expect(handled, [isStateError]);
        expect(errors, isEmpty);
      });

      test('a Cancelled is told to the same two and goes no further', () {
        _says(
          'A `Cancelled` thrown by cleanup is told to the same two and goes '
          'no further',
        );
        final watching = _Watching();
        Solo.observer = watching;
        late Bench bench;
        late Job<void> job;
        final errors = _zone((async) {
          bench = Bench();
          job = cleanupThrows(bench, const Cancelled('from cleanup'));
          async.flushMicrotasks();
        });

        expect(bench.heard, [isA<Cancelled>()]);
        expect(watching.heard, [isA<Cancelled>()]);
        expect(bench.unanswered, isEmpty);
        expect(errors, isEmpty);
        expect('${job.outcome}', 'Done(null)');
      });

      test('a Cancelled stays out of Solo.errorHandler when one is set', () {
        final handled = <Object>[];
        Solo.errorHandler =
            (solo, job, error, stackTrace) => handled.add(error);
        final errors = _zone((async) {
          cleanupThrows(Bench(), const Cancelled('from cleanup'));
          async.flushMicrotasks();
        });

        expect(handled, isEmpty);
        expect(errors, isEmpty);
      });
    });

    group('a cleanup that waits', () {
      /// A job whose cleanup awaits what [wait] returns for it.
      SoloJob<void> stuck(
        Bench bench,
        Future<Object?> Function(SoloJob<void> self) wait,
      ) {
        late final SoloJob<void> self;

        return self = bench.run<Idle, void>(
          key: 'stuck',
          (ctx) async {
            ctx.onDispose(() async {
              await wait(self);
              stage.trace.add('the cleanup went on');
            });
          },
        );
      }

      final own = <String, Future<Object?> Function(SoloJob<void> self)>{
        'done': (self) => self.done,
        'value': (self) => self.value,
        'cancel()': (self) => self.cancel(),
      };
      for (final MapEntry(key: member, value: wait) in own.entries) {
        test('for $member of its own job never ends, and close() neither', () {
          fakeAsync((async) {
            final bench = Bench();
            final job = stuck(bench, wait);
            async.elapse(const Duration(hours: 1));
            expect(job.outcome, isNull);
            expect(
              '${bench.pending}',
              startsWith('SoloPending([stuck] in its cleanup'),
            );

            var back = false;
            bench.close().then((_) => back = true);
            async.elapse(const Duration(hours: 1));
            expect(back, isFalse);
            expect(job.outcome, isNull);
            expect(stage.trace, isEmpty);
          });
        });
      }

      test('for a later job holds the queue while that job stays queued', () {
        _says('holds the queue for as long as that job stays queued');
        _says('`pending` reports such a job as `in its cleanup`');
        fakeAsync((async) {
          final bench = Bench();
          late final SoloJob<void> later;
          final job = stuck(bench, (self) => later.done);
          later = bench.next();
          async.elapse(const Duration(hours: 1));

          expect(job.outcome, isNull);
          expect(later.isQueued, isTrue);
          expect('${bench.pending}', 'SoloPending([stuck] in its cleanup)');

          expect(bench.queue.remove(later), isTrue);
          async.flushMicrotasks();
          expect('${later.outcome}', 'Cancelled(manual)');
          expect('${job.outcome}', 'Done(null)');
          expect(stage.trace, ['the cleanup went on']);
        });
      });
    });
  });

  group('The page', () {
    test('four sections open with a first attempt, as the introduction says',
        () {
      expect(
        RegExp(r'^### The first attempt$', multiLine: true).allMatches(_page()),
        hasLength(4),
      );
      expect(_prose(), contains('Four sections below open with the version'));
    });

    test('one of them goes on to a second attempt', () {
      expect(
        RegExp(r'^### The second attempt$', multiLine: true)
            .allMatches(_page()),
        hasLength(1),
      );
    });

    test('has no fence the checks do not read', () {
      expect(strayFences('doc/resources.md'), isEmpty);
    });

    // Each version under its own file: an answer turned into its own first
    // attempt would still be found among all of them.
    const answers = 'test/support/resources_page.dart';
    const attempts = 'test/support/resources_first_attempts.dart';
    const holders = {
      '# Resources and cleanup': answers,
      '### The first attempt': attempts,
      '### The second attempt': attempts,
      '### The release travels with the call': answers,
      '### Discard, for a value that leaves': answers,
      '### Check, disown, emit': answers,
      '### The wait that stays with it': answers,
    };
    for (final MapEntry(key: heading, value: holder) in holders.entries) {
      test('the code under "$heading" is a run of lines of $holder', () {
        expect(
          codeMissingFrom('doc/resources.md', holder, under: heading),
          isEmpty,
        );
      });
    }

    test('every piece of code on the page is a run of lines of these files',
        () {
      expect(
        codeMissingFrom('doc/resources.md', answers, alsoIn: [attempts]),
        isEmpty,
      );
    });

    test('every heading with code under it is held to a file', () {
      final withCode = [
        for (final part in _page().split(RegExp('^(?=#)', multiLine: true)))
          if (part.contains('```dart')) part.split('\n').first,
      ];
      expect(withCode.toSet(), holders.keys.toSet());
    });
  });
}
