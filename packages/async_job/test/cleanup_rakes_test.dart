// `doc/cleanup.md` and `doc/cleanup-rules.md` run here. Their code lives
// in three files, because the versions of one section differ by a word or
// a line: the opening example and the answers in
// `support/cleanup_page.dart`, the first attempts in
// `support/cleanup_first_attempts.dart`, and the second attempt of "A
// resource that travels" in this file. The code under each heading is
// held to the file of that heading, the lines the pages quote are what
// their code prints, and what the pages say about cleanup without code of
// their own is pinned here as well.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

import 'support/cleanup_first_attempts.dart' as first;
import 'support/cleanup_page.dart' as page;
import 'support/cleanup_stubs.dart';
import 'support/delay.dart';
import 'support/error_observer.dart';
import 'support/fake_time.dart';
import 'support/page_code.dart';

/// The second attempt of "A resource that travels", verbatim: a line away
/// from the first attempt and from the answer alike.
DeferredJob<Database> nextLine(ChildJob<Database> connect) {
  final ready = Job.deferred<Database>((ctx) async {
    final database = await ctx.run(connect);
    ctx.onDiscard(database.close);
    // ignore: unnecessary_lambdas
    await ctx.join(() => database.migrate());

    return database;
  });
  return ready;
}

/// `connect` as the page writes it, but refusing the cascade.
DeferredJob<Database> stubborn() => Job.deferred<Database>(
      key: 'connect',
      cancellable: false,
      (ctx) => ctx.abandonable(Database.open, discard: (db) => db.close()),
    );

/// The answer of "A value the job keeps back" without its `disown`.
Future<Database?> closingWithoutDisown(JobContext ctx) async {
  final database = await ctx.join(
    Database.open,
    discard: (database) => database.close(),
  );
  if (!await ctx.join(database.isCurrent)) {
    await database.close();
    return null;
  }
  return database;
}

/// Opens a database at once, under the name the trace will show.
Future<Database> open([String name = 'database']) async {
  stage.trace.add('$name opened');
  return Database(name);
}

/// The line of the debug channel for the first attempt of keeping back.
const keptBackLine = 'Job() ended Done(null) without the value of 1 '
    'conditional cleanup (database): unless it is inside the result, nothing '
    'will dispose of it';

/// The pages this file runs: the choice of the callback, then the rules.
const pages = ['doc/cleanup.md', 'doc/cleanup-rules.md'];

/// What each `text` block of the pages says, in the order of the pages.
const quoted = [
  [
    'lock acquired',
    'database opened',
    'outcome: Done(database)',
  ],
  [
    'lock acquired',
    'database opened',
    'lock released',
    'outcome: Done(database)',
  ],
  [
    'database opened',
    'outcome: Done(null)',
  ],
  [keptBackLine],
  [
    'database opened',
    'database closed',
    'outcome: Done(null)',
  ],
  [
    'database opened',
    'database migration failed',
    'outcome: Failed(MigrationFailed)',
  ],
  [
    'Job(connect) handed its value over: 1 conditional cleanup dropped',
  ],
  [
    'database opened',
    'cancel',
    'outcome: Cancelled(manual)',
  ],
  [
    'database opened',
    'cancel',
    'database closed',
    'outcome: Cancelled(manual)',
  ],
  [
    'cancel',
    'cursor read',
    'cursor closed',
    'cursor closed',
    'outcome: Cancelled(manual)',
  ],
  [
    'cancel',
    'cursor read',
    'cursor closed',
    'outcome: Cancelled(manual)',
  ],
  [
    'cancel',
    'database opened',
    'database closed',
    'outcome: Cancelled(manual)',
  ],
  [
    'database opened',
    'cancel',
    'cache warmed',
    'database closed',
    'outcome: Cancelled(manual)',
  ],
];

/// Cancels [job] the way the user does, and says so in the trace.
void cancel(Job<Object?> job) {
  stage.trace.add('cancel');
  job.cancel().ignore();
}

/// What a scene of the page prints: the trace of the stubs, `cancel` when
/// the user cancels [cancelAt] ms in, and the outcome once the job ends.
List<String> scene(Job<Object?> Function() start, {int? cancelAt}) {
  fakeAsync((async) {
    final job = start();
    job.done.then((outcome) => stage.trace.add('outcome: $outcome')).ignore();
    if (cancelAt != null) {
      async.elapse(Duration(milliseconds: cancelAt));
      cancel(job);
    }
    async.flushTimers();
  });
  return stage.trace;
}

/// The jobs of "A resource that travels", with `ready` cancelled the moment
/// `connect` ends: between its `Done` and the checkpoint `run` makes before
/// it hands the value to the body.
Job<Database> cancelledOnceConnected(
  DeferredJob<Database> Function(ChildJob<Database> connect) version,
) {
  final connect = first.connecting();
  final ready = version(connect);
  connect.done.then((_) => cancel(ready)).ignore();
  return ready..start();
}

/// The members of the context the page says belong to the body and throw
/// `StateError` in a callback of the cleanup stack, as its sentence lists
/// them.
Set<String> bodyMembers() {
  final page =
      File('doc/cleanup.md').readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
  final sentence = RegExp(
    r"((?:`\w+`(?:, | and ))+`\w+`) are the body's and throw `StateError`",
  ).firstMatch(page);
  if (sentence == null) {
    throw StateError('the page names no members of the body');
  }
  return {
    for (final name in RegExp(r'`(\w+)`').allMatches(sentence.group(1)!))
      name.group(1)!,
  };
}

/// Every member of [ctx], each called the way a callback would call it.
Map<String, FutureOr<Object?> Function()> contextMembers(JobContext ctx) => {
      'check': ctx.check,
      'abandonable': () => ctx.abandonable(() async => 1),
      'join': () => ctx.join(() async => 1),
      'pause': ctx.pause,
      'uncancellable': () => ctx.uncancellable(() async => 1),
      'run': () => ctx.run(Job.deferred<int>((ctx) async => 1)),
      'start': () => ctx.start(Job.deferred<int>((ctx) async => 1)),
      'runAll': () => ctx.runAll([Job.deferred<int>((ctx) async => 1)]),
      'each': () => ctx.each(Stream.value(1), (ctx, event) {}).done,
      'onCancel': () => ctx.onCancel(() {}),
      'onDispose': () => ctx.onDispose(() {}),
      'onDiscard': () => ctx.onDiscard(() {}),
      'disown': () => ctx.disown(Object()),
      'unattended': () => ctx.unattended(() {}),
      'log': () => ctx.log('cleanup'),
      'job': () => ctx.job,
    };

/// A value with an equality of its own: two built from one name are equal,
/// and only one of them is the value a call handed over.
@immutable
final class Address {
  final String name;

  const Address(this.name);

  @override
  bool operator ==(Object other) => other is Address && other.name == name;

  @override
  int get hashCode => name.hashCode;
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

void main() {
  late List<String> trace;

  setUp(() {
    stage = Stage();
    trace = stage.trace;
  });

  tearDown(() => Job.debug = null);

  group('Cleanup', () {
    test('a success releases the lock and returns the database open', () {
      fakeAsync((async) {
        final job = Job<Database>(page.opening)..ignoreFailure();
        async.flushTimers();
        expect(job.outcome, isA<Done<Database>>());
        expect(trace, [
          'lock acquired',
          'database opened',
          'database migrated',
          'lock released',
        ]);
      });
    });

    test('a failed migration closes the database, then releases the lock', () {
      fakeAsync((async) {
        stage.migrateError = MigrationFailed();
        final job = Job<Database>(page.opening)..ignoreFailure();
        async.flushTimers();
        expect(job.outcome, isA<Failed>());
        // The stack unwinds from the last registration.
        expect(trace, [
          'lock acquired',
          'database opened',
          'database migration failed',
          'database closed',
          'lock released',
        ]);
      });
    });
  });

  group('Choosing the callback', () {
    test('the first attempt keeps the lock held when the job succeeds', () {
      fakeAsync((async) {
        final job = Job<Database>(first.sameCallback)..ignoreFailure();
        async.flushTimers();
        expect(job.outcome, isA<Done<Database>>());
        expect(trace, ['lock acquired', 'database opened']);
      });
    });

    test('the first attempt releases both when the job is cancelled', () {
      fakeAsync((async) {
        final job = Job<Database>(first.sameCallback)..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
        expect(job.outcome, isA<Cancelled>());
        expect(trace, [
          'lock acquired',
          'database opened',
          'database closed',
          'lock released',
        ]);
      });
    });

    test('the first attempt releases the lock when the job fails', () {
      fakeAsync((async) {
        stage.openError = StateError('no database');
        final job = Job<Database>(first.sameCallback)..ignoreFailure();
        async.flushTimers();
        expect(job.outcome, isA<Failed>());
        expect(trace, ['lock acquired', 'lock released']);
      });
    });

    test('dispose releases the lock of a job that succeeds', () {
      fakeAsync((async) {
        final job = Job<Database>(page.keeping)..ignoreFailure();
        async.flushTimers();
        expect(job.outcome, isA<Done<Database>>());
        expect(trace, ['lock acquired', 'database opened', 'lock released']);
      });
    });

    test('dispose and discard release both when the job is cancelled', () {
      fakeAsync((async) {
        final job = Job<Database>(page.keeping)..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
        expect(job.outcome, isA<Cancelled>());
        expect(trace, [
          'lock acquired',
          'database opened',
          'database closed',
          'lock released',
        ]);
      });
    });

    test('two branches that share the lock hang the group, cancelled or not',
        () {
      fakeAsync((async) {
        stage.exclusive = true;
        final group = Job<List<Database>>(
          (ctx) => ctx.runAll([
            Job.deferred<Database>(page.keeping),
            Job.deferred<Database>(page.keeping),
          ]),
        )..ignoreFailure();
        async.flushTimers();
        expect(group.isFinished, isFalse);
        expect(trace, ['lock acquired', 'lock waits', 'database opened']);

        // The waiting branch is inside `join`, which waits its action
        // out, and the one holding the lock unwinds only after it.
        group.cancel().ignore();
        async.flushTimers();
        expect(group.isFinished, isFalse);
        expect(trace, isNot(contains('lock released')));
      });
    });
  });

  group('A value the job keeps back', () {
    setUp(() => stage.schemaCurrent = false);

    test('the first attempt leaves the database it keeps back open', () {
      fakeAsync((async) {
        final job = Job<Database?>(first.keptBack);
        async.flushTimers();
        expect((job.outcome! as Done<Database?>).value, isNull);
        expect(trace, ['database opened']);
      });
    });

    test('the debug channel names the value, as the page quotes', () {
      final printed = <String>[];
      Job.debug = printed.add;
      fakeAsync((async) {
        Job<Database?>(first.keptBack);
        async.flushTimers();
      });
      expect(
        printed.where((line) => line.contains('conditional cleanup')),
        quoted[3],
      );
    });

    test('a current schema hands the database over open, as before', () {
      stage.schemaCurrent = true;
      fakeAsync((async) {
        final job = Job<Database?>(page.closingKeptBack);
        async.flushTimers();
        expect(job.outcome, isA<Done<Database?>>());
        expect(trace, ['database opened']);
      });
    });

    test('a cancellation during the close closes it once with disown', () {
      for (final (version, closes) in [
        (page.closingKeptBack, 1),
        (closingWithoutDisown, 2),
      ]) {
        stage = Stage()
          ..schemaCurrent = false
          ..closeTake = 10;
        Database? opened;
        fakeAsync((async) {
          final job = Job<Database?>(version)..ignoreFailure();
          // Open at 10, current asked until 15, the close from 15 to 25.
          async.elapse(const Duration(milliseconds: 20));
          expect(stage.trace, ['database opened']);
          job.cancel().ignore();
          async.flushTimers();
          expect(job.outcome, isA<Cancelled>());
          opened = Database.lastOpened;
        });
        expect(opened!.closes, closes);
      }
    });
  });

  group('A resource that travels', () {
    test(
        'a checkpoint of run that throws closes the value before the body '
        'hears it', () {
      stage.closeTake = 10;
      fakeAsync((async) {
        final connect = first.connecting();
        final ready = Job.deferred<void>((ctx) async {
          try {
            await ctx.run(connect, discard: (database) => database.close());
          } on Cancelled {
            stage.trace.add('body heard');
            rethrow;
          }
        });
        connect.done.then((_) => cancel(ready)).ignore();
        ready.start();
        async.flushTimers();
        expect(ready.outcome, isA<Cancelled>());
        expect(trace, [
          'database opened',
          'cancel',
          'database closed',
          'body heard',
        ]);
      });
    });

    test('the first attempt leaves the database open when migration fails', () {
      fakeAsync((async) {
        stage.migrateError = MigrationFailed();
        final connect = first.connecting();
        final ready = first.unregistered(connect)
          ..ignoreFailure()
          ..start();
        async.flushTimers();
        expect(connect.outcome, isA<Done<Database>>());
        expect(ready.outcome, isA<Failed>());
        expect(trace, ['database opened', 'database migration failed']);
      });
    });

    test('the debug channel prints the line the page quotes', () {
      final printed = <String>[];
      Job.debug = printed.add;
      fakeAsync((async) {
        first.unregistered(first.connecting()).start();
        async.flushTimers();
      });
      expect(
        printed.where((line) => line.contains('handed its value over')),
        quoted[6],
      );
    });

    test('the channel names the hand-over when the receiver registered too',
        () {
      final printed = <String>[];
      Job.debug = printed.add;
      fakeAsync((async) {
        page.onArrival(first.connecting()).start();
        async.flushTimers();
      });
      expect(printed, containsAll(quoted[6]));
    });

    test('the second attempt closes the database when migration fails', () {
      fakeAsync((async) {
        stage.migrateError = MigrationFailed();
        final ready = nextLine(first.connecting())
          ..ignoreFailure()
          ..start();
        async.flushTimers();
        expect(ready.outcome, isA<Failed>());
        expect(trace, [
          'database opened',
          'database migration failed',
          'database closed',
        ]);
      });
    });

    // Registered before `ready` starts, so it lands between the `Done` of
    // `connect` and the checkpoint `run` makes before it hands the value
    // to the body.
    void cancelOnceDone(Job<Database> connect, Job<Database> ready) =>
        connect.done.then((_) => ready.cancel().ignore()).ignore();

    for (final (name, version, closes) in [
      ('the second attempt', nextLine, false),
      ('registering on arrival', page.onArrival, true),
    ]) {
      test(
          '$name, cancelled between the Done of connect and the checkpoint '
          'of run', () {
        fakeAsync((async) {
          final connect = first.connecting();
          final ready = version(connect)..ignoreFailure();
          cancelOnceDone(connect, ready);
          ready.start();
          async.flushTimers();
          expect(connect.outcome, isA<Done<Database>>());
          expect(ready.outcome, isA<Cancelled>());
          expect(trace, ['database opened', if (closes) 'database closed']);
        });
      });

      test('$name, cancelled while connect still opens the database', () {
        fakeAsync((async) {
          final connect = first.connecting();
          final ready = version(connect)
            ..ignoreFailure()
            ..start();
          async.elapse(const Duration(milliseconds: 5));
          ready.cancel().ignore();
          async.flushTimers();
          // The cancellation cascades, and `connect` closes it itself.
          expect(
            (connect.outcome! as Cancelled).reason,
            isA<ParentCancelReason>(),
          );
          expect(ready.outcome, isA<Cancelled>());
          expect(trace, ['database opened', 'database closed']);
        });
      });

      test('$name, a connect with cancellable: false, cancelled while it opens',
          () {
        fakeAsync((async) {
          final connect = stubborn();
          final ready = version(connect)
            ..ignoreFailure()
            ..start();
          async.elapse(const Duration(milliseconds: 5));
          ready.cancel().ignore();
          async.flushTimers();
          expect(connect.outcome, isA<Done<Database>>());
          expect(ready.outcome, isA<Cancelled>());
          expect(trace, ['database opened', if (closes) 'database closed']);
        });
      });
    }

    test('registering on arrival closes the database when migration fails', () {
      fakeAsync((async) {
        stage.migrateError = MigrationFailed();
        final ready = page.onArrival(first.connecting())
          ..ignoreFailure()
          ..start();
        async.flushTimers();
        expect(ready.outcome, isA<Failed>());
        expect(trace, [
          'database opened',
          'database migration failed',
          'database closed',
        ]);
      });
    });

    test('registering on arrival hands the database on open on a success', () {
      fakeAsync((async) {
        final ready = page.onArrival(first.connecting())
          ..ignoreFailure()
          ..start();
        async.flushTimers();
        expect(ready.outcome, isA<Done<Database>>());
        expect(trace, ['database opened', 'database migrated']);
      });
    });

    test('the value of connect is the database the receiver closed', () {
      fakeAsync((async) {
        stage.migrateError = MigrationFailed();
        final connect = first.connecting();
        page.onArrival(connect)
          ..ignoreFailure()
          ..start();
        Database? reached;
        connect.value.then((database) => reached = database).ignore();
        async.flushTimers();
        expect(reached?.closes, 1, reason: 'the receiver closed it');

        reached?.close();
        async.flushMicrotasks();
        expect(reached?.closes, 2, reason: 'closing it there closes it again');
      });
    });
  });

  group('Registering without a call', () {
    test('a callback flushes the buffer when the job finishes', () {
      fakeAsync((async) {
        Job<void>(page.flushing).ignoreFailure();
        async.flushTimers();
        expect(stage.sink, ['rows']);
      });
    });

    test('the first attempt closes the cursor once when nothing cancels it',
        () {
      fakeAsync((async) {
        final job = Job<void>(first.unregisteringAfter)..ignoreFailure();
        async.flushTimers();
        expect(job.outcome, isA<Done<void>>());
        expect(stage.cursor.closes, 1);
      });
    });

    test('the first attempt closes the cursor twice on a cancellation', () {
      fakeAsync((async) {
        final job = Job<void>(first.unregisteringAfter)..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
        // `join` waits `readAll` out and throws in place of its value.
        expect(job.outcome, isA<Cancelled>());
        expect(trace, ['cursor read', 'cursor closed', 'cursor closed']);
      });
    });

    test('unregistering inside the action closes it once on a cancellation',
        () {
      fakeAsync((async) {
        final job = Job<void>(page.unregisteringInside)..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
        expect(job.outcome, isA<Cancelled>());
        expect(trace, ['cursor read', 'cursor closed']);
      });
    });

    test('a hand-over in one section is not rolled back on a cancellation', () {
      fakeAsync((async) {
        final job = Job<void>(page.handingOver)..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
        // The section holds the cancellation until `disown` has run.
        expect(job.outcome, isA<Cancelled>());
        expect(trace, ['transaction begun', 'transaction committed']);
      });
    });

    test('a hand-over in one section is not rolled back on success', () {
      fakeAsync((async) {
        final job = Job<void>(page.handingOver)..ignoreFailure();
        async.flushTimers();
        expect(job.outcome, isA<Done<void>>());
        expect(trace, ['transaction begun', 'transaction committed']);
      });
    });

    fakeAsyncTest('the unregister function is safe twice and after cleanup',
        () async {
      late void Function() removeDisposer;
      final job = Job<void>(key: 'twice', (ctx) async {
        removeDisposer = ctx.onDispose(() async => trace.add('disposer ran'));
        removeDisposer();
        removeDisposer();
      })
        ..ignoreFailure();
      await job.done;
      removeDisposer();

      expect(job.outcome, isA<Done<void>>());
      expect(trace, isEmpty);
    });

    fakeAsyncTest('the unregister function is safe after its callback ran',
        () async {
      late void Function() removeDisposer;
      final job = Job<void>(key: 'ran', (ctx) async {
        removeDisposer = ctx.onDispose(() async => trace.add('disposer ran'));
      })
        ..ignoreFailure();
      await job.done;
      removeDisposer();
      removeDisposer();

      expect(job.outcome, isA<Done<void>>());
      expect(trace, ['disposer ran']);
    });

    fakeAsyncTest('disown looks the value up by identity', () async {
      final answers = <bool>[];
      final job = Job<void>(key: 'disown', (ctx) async {
        final address = await ctx.join(
          () => const Address('db'),
          dispose: (address) => trace.add('${address.name} released'),
        );
        // Built at run time: a constant would be the very same one.
        final equal = Address(address.name);
        answers
          ..add(equal == address)
          ..add(ctx.disown(equal))
          ..add(ctx.disown(address))
          ..add(ctx.disown(address));
      })
        ..ignoreFailure();
      await job.done;

      expect(
        answers,
        <bool>[true, false, true, false],
        reason: 'an equal value is not the one the call handed over',
      );
      expect(trace, isEmpty);
    });

    fakeAsyncTest('a number is found by an equal one of its type', () async {
      final answers = <bool>[];
      final job = Job<void>(key: 'disown', (ctx) async {
        final port = await ctx.join(
          () => int.parse('8080'),
          dispose: (port) => trace.add('port $port released'),
        );
        answers
          ..add(ctx.disown(8080))
          ..add(ctx.disown(port));
      })
        ..ignoreFailure();
      await job.done;

      expect(
        answers,
        <bool>[true, false],
        reason: 'a number has no identity apart from its value, as the '
            'dartdoc of disown says',
      );
      expect(trace, isEmpty);
    });
  });

  group('Cleanup order and late results', () {
    fakeAsyncTest('cleanup waits for the children', () async {
      final gate = Gate();
      final job = Job<void>(key: 'parent', (ctx) async {
        ctx.onDispose(() async => trace.add('parent cleanup'));
        unawaited(
          ctx
              .run(
                Job.deferred<void>(key: 'child', (child) async {
                  await child.join(gate.wait);
                  trace.add('child finished');
                }),
              )
              .onError((_, __) {}),
        );
        await pump();
      })
        ..ignoreFailure();
      await pump();
      await gate.release();
      await job.done;

      expect(
        trace,
        containsAllInOrder(<String>['child finished', 'parent cleanup']),
      );
    });

    fakeAsyncTest('callbacks run in reverse order and each is awaited',
        () async {
      final job = Job<void>(key: 'order', (ctx) async {
        ctx
          ..onDispose(() async {
            await pump();
            trace.add('first');
          })
          ..onDispose(() async => trace.add('second'));
      })
        ..ignoreFailure();
      await job.done;

      expect(trace, <String>['second', 'first']);
    });

    fakeAsyncTest('an error in one callback leaves the rest running', () async {
      final errors = <Object>[];
      final job = Job<void>(
        key: 'boom',
        // Answering: the order is the subject, not where the error goes
        // after the observer.
        observer: ErrorObserver.answering(errors),
        (ctx) async {
          ctx
            ..onDispose(() async => trace.add('under it'))
            ..onDispose(() async => throw StateError('cleanup failed'));
        },
      )..ignoreFailure();
      await job.done;

      expect(errors, <Matcher>[isStateError]);
      expect(trace, <String>['under it']);
      expect(job.outcome, isA<Done<void>>());
    });

    fakeAsyncTest('a cancellation into the unwinding stops no callback',
        () async {
      final gate = Gate();
      final job = Job<void>(key: 'unwind', (ctx) async {
        ctx
          ..onDispose(() async => trace.add('under it'))
          ..onDispose(() async {
            trace.add('waiting');
            await gate.wait();
            trace.add('released');
          });
      })
        ..ignoreFailure();
      await pump();
      // It lands while the first callback is awaiting its resource.
      job.cancel().ignore();
      await gate.release();
      await job.done;

      expect(trace, <String>['waiting', 'released', 'under it']);
    });

    // Every member of the context is called, so a list on the page that
    // leaves one out, or names one that works, turns this red.
    fakeAsyncTest(
        'the members the page names, and no others, throw StateError in a '
        'callback', () async {
      final caught = <String, Object>{};
      final job = Job<void>(key: 'late', (ctx) async {
        ctx.onDispose(() async {
          for (final MapEntry(key: name, value: call)
              in contextMembers(ctx).entries) {
            try {
              await call();
            } on Object catch (error) {
              caught[name] = error;
            }
          }
        });
      })
        ..ignoreFailure();
      await job.done;

      expect(caught.keys.toSet(), bodyMembers());
      expect(caught.values, everyElement(isStateError));
    });

    // The one exception the page makes: on a cancelled job `check` throws
    // the job's cancellation, so an action the body walked away from stops
    // on what it waits for. The other members of the body still refuse.
    fakeAsyncTest(
        'on a cancelled job check throws its Cancelled in a callback, and the '
        'other members of the body still throw StateError', () async {
      final caught = <String, Object>{};
      final job = Job<void>(key: 'late', (ctx) async {
        ctx.onDispose(() async {
          for (final MapEntry(key: name, value: call)
              in contextMembers(ctx).entries) {
            try {
              await call();
            } on Object catch (error) {
              caught[name] = error;
            }
          }
        });
        await ctx.pause(const Duration(seconds: 1));
      })
        ..ignoreFailure();
      await delay(1);
      job.cancel().ignore();
      await job.done;

      expect(caught.keys.toSet(), bodyMembers());
      expect(caught.remove('check'), same(job.outcome));
      expect(caught.values, everyElement(isStateError));
      expect(
        File('doc/cleanup.md')
            .readAsStringSync()
            .replaceAll(RegExp(r'\s+'), ' '),
        allOf(
          contains(
            "On a cancelled job `check` throws the job's `Cancelled` instead",
          ),
          contains('a `Cancelled` stops at `onError`'),
        ),
      );
    });

    final waits = <String, Future<Object?> Function(Job<int> job)>{
      'done': (job) => job.done,
      'value': (job) => job.value,
      'cancel()': (job) => job.cancel(),
    };
    for (final MapEntry(key: what, value: waitFor) in waits.entries) {
      test('a callback awaiting $what of its own job keeps it from ending', () {
        fakeAsync((async) {
          var returned = false;
          late Job<int> job;
          job = Job<int>((ctx) async {
            ctx.onDispose(() async {
              await waitFor(job);
              returned = true;
            });
            return 1;
          })
            ..ignoreFailure();
          async.flushTimers();
          expect(job.isFinished, isFalse);
          expect(returned, isFalse);
        });
      });
    }

    fakeAsyncTest('cancellation after the return closes what was returned',
        () async {
      final gate = Gate();
      late Database db;
      final job = Job<Database>(key: 'open', (ctx) async {
        db = await ctx.join(open, discard: (db) => db.close());
        unawaited(
          ctx
              .run(
                Job.deferred<void>(
                  key: 'child',
                  (child) => child.join(gate.wait),
                ),
              )
              .onError((_, __) {}),
        );
        await pump();
        return db;
      })
        ..ignoreFailure();
      unawaited(job.value.onError((_, __) => Database('none')));
      await pump();
      await pump();
      job.cancel().ignore();
      await gate.release();
      await job.done;

      expect(job.outcome, isA<Cancelled>());
      expect(db.closed, isTrue);
    });

    fakeAsyncTest(
        'the second pass runs the discard after the earlier callbacks',
        () async {
      final gate = Gate();
      final job = Job<Database>(key: 'order', (ctx) async {
        ctx
          ..onDispose(() async => trace.add('disposer A'))
          ..onDispose(() async {
            trace.add('disposer B waits');
            await gate.wait();
            trace.add('disposer B done');
          });
        final db = await ctx.join(open, discard: (db) => db.close());
        ctx.onDispose(() async => trace.add('disposer D'));
        return db;
      })
        ..ignoreFailure();
      unawaited(job.value.onError((_, __) => Database('none')));
      await pump();
      await pump();
      job.cancel().ignore();
      await pump();
      await gate.release();
      await job.done;

      expect(
        trace,
        <String>[
          'database opened',
          'disposer D',
          'disposer B waits',
          'disposer B done',
          'disposer A',
          'database closed',
        ],
        reason: 'strict reverse order would close the database before A '
            'and B, registered before the discard; the second pass closes it '
            'after them',
      );
    });

    fakeAsyncTest('a branch whose group handed the values over keeps its value',
        () async {
      final job = Job<void>(key: 'group', (ctx) async {
        final values = await ctx.runAll(<ChildJob<Database>>[
          Job.deferred<Database>(
            key: 'left',
            (branch) => branch.abandonable(
              () => open('left'),
              discard: (db) => db.close(),
            ),
          ),
          Job.deferred<Database>(
            key: 'right',
            (branch) => branch.abandonable(
              () => open('right'),
              discard: (db) => db.close(),
            ),
          ),
        ]);
        trace.add('group handed over ${values.length} values');
      })
        ..ignoreFailure();
      await job.done;

      expect(job.outcome, isA<Done<void>>());
      expect(trace, contains('group handed over 2 values'));
      expect(trace, isNot(contains('left closed')));
      expect(trace, isNot(contains('right closed')));
    });

    fakeAsyncTest('a branch whose group never decided closes what it took',
        () async {
      final gate = Gate();
      final job = Job<void>(key: 'group', (ctx) async {
        await ctx.runAll(<ChildJob<Database>>[
          Job.deferred<Database>(key: 'left', (branch) async {
            final db = await branch.abandonable(
              () => open('left'),
              discard: (db) => db.close(),
            );
            await branch.join(gate.wait);
            return db;
          }),
          Job.deferred<Database>(
            key: 'right',
            (branch) => branch.abandonable(
              () => open('right'),
              discard: (db) => db.close(),
            ),
          ),
        ]);
      })
        ..ignoreFailure();
      await pump();
      job.cancel().ignore();
      await gate.release();
      await job.done;

      expect(job.outcome, isA<Cancelled>());
      expect(trace, contains('left closed'));
      expect(trace, contains('right closed'));
    });

    /// A job that waits for a slot and gives it up on a cancellation at 5
    /// ms, while a child keeps it from unwinding until 30 ms; the slot
    /// comes at 10 ms and takes 40 ms to release. [registered] runs on the
    /// job's context first, [caught] once the body has caught the
    /// cancellation.
    List<String> slotRelease(
      void Function(JobContext ctx, void Function(String what) at) registered, {
      Future<void> Function(JobContext ctx, void Function(String what) at)?
          caught,
    }) {
      final seen = <String>[];
      fakeAsync((async) {
        void at(String what) =>
            seen.add('${async.elapsed.inMilliseconds} ms: $what');
        final job = Job<void>((ctx) async {
          registered(ctx, at);
          ctx
              .run(Job.deferred<void>((c) => c.uncancellable(() => delay(30))))
              .ignore();
          try {
            await ctx.abandonable(
              () => delay(10).then((_) => 'slot'),
              dispose: (slot) async {
                at('the slot release starts');
                await delay(40);
                at('the slot release ends');
              },
            );
          } on Cancelled {
            await caught?.call(ctx, at);
            rethrow;
          }
        })
          ..ignoreFailure();
        job.done.then((_) => at('the job ends')).ignore();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
      });
      return seen;
    }

    test('a value abandonable let go of is released alongside the body', () {
      final seen = slotRelease(
        (ctx, at) {},
        caught: (ctx, at) async {
          await delay(20);
          at('the body ends');
        },
      );
      expect(seen, [
        '10 ms: the slot release starts',
        '25 ms: the body ends',
        '50 ms: the slot release ends',
        '50 ms: the job ends',
      ]);
    });

    test(
        'its release counts as registered when the value came: an earlier '
        'callback waits for it, a later one does not', () {
      final seen = slotRelease(
        (ctx, at) => ctx.onDispose(() => at('the pool closes')),
        caught: (ctx, at) async {
          // Registered at 20 ms, after the slot came.
          await delay(15);
          ctx.onDispose(() => at('a later callback runs'));
        },
      );
      expect(seen, [
        '10 ms: the slot release starts',
        '30 ms: a later callback runs',
        '50 ms: the slot release ends',
        '50 ms: the pool closes',
        '50 ms: the job ends',
      ]);
    });

    /// A group of two branches. The first registers the pool, starts
    /// waiting for a slot that comes at 20 ms and takes 40 ms to release,
    /// and returns; a cancellation of that branch at 10 ms abandons the
    /// wait. [other] is the body of the second branch, which keeps the
    /// group waiting.
    List<String> branchRelease(
      Future<int> Function(JobContext ctx, void Function(String what) at) other,
    ) {
      final seen = <String>[];
      fakeAsync((async) {
        void at(String what) =>
            seen.add('${async.elapsed.inMilliseconds} ms: $what');
        final branch = Job.deferred<int>((ctx) async {
          ctx.onDispose(() => at('the pool closes'));
          ctx.abandonable(
            () => delay(20).then((_) => 'slot'),
            dispose: (slot) async {
              at('the slot release starts');
              await delay(40);
              at('the slot release ends');
            },
          ).ignore();
          return 1;
        });
        Job<List<int>>(
          (ctx) => ctx.runAll([
            branch,
            Job.deferred<int>((ctx) => other(ctx, at)),
          ]),
        ).ignoreFailure();
        branch.done.then((_) => at('the branch ends')).ignore();
        async.elapse(const Duration(milliseconds: 10));
        branch.cancel().ignore();
        async.flushTimers();
      });
      return seen;
    }

    test(
        'a branch waiting for its group before the unwinding: an earlier '
        'callback waits for the release', () {
      final seen = branchRelease((ctx, at) async {
        await ctx.abandonable(() => delay(30));
        at('the other body ends');
        return 2;
      });
      expect(seen, [
        '20 ms: the slot release starts',
        '30 ms: the other body ends',
        '60 ms: the slot release ends',
        '60 ms: the pool closes',
        '60 ms: the branch ends',
      ]);
    });

    test(
        'a branch between the cleanup stack and the second pass has run its '
        'stack and releases at once', () {
      final seen = branchRelease((ctx, at) async {
        ctx.onDispose(() async {
          await delay(50);
          at('the other cleanup ends');
        });
        await ctx.abandonable(() => delay(1));
        return 2;
      });
      expect(seen, [
        '1 ms: the pool closes',
        '20 ms: the slot release starts',
        '51 ms: the other cleanup ends',
        '60 ms: the slot release ends',
        '60 ms: the branch ends',
      ]);
    });

    test('two values abandonable let go of are released side by side', () {
      final seen = <String>[];
      fakeAsync((async) {
        void at(String what) =>
            seen.add('${async.elapsed.inMilliseconds} ms: $what');
        Future<void> release(String slot) async {
          at('$slot release starts');
          await delay(40);
          at('$slot release ends');
        }

        final job = Job<void>((ctx) async {
          ctx
              .run(Job.deferred<void>((c) => c.uncancellable(() => delay(30))))
              .ignore();
          await Future.wait([
            ctx.abandonable(
              () => delay(10).then((_) => 'one'),
              dispose: release,
            ),
            ctx.abandonable(
              () => delay(15).then((_) => 'two'),
              dispose: release,
            ),
          ]);
        })
          ..ignoreFailure();
        job.done.then((_) => at('the job ends')).ignore();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
      });
      expect(seen, [
        '10 ms: one release starts',
        '15 ms: two release starts',
        '50 ms: one release ends',
        '55 ms: two release ends',
        '55 ms: the job ends',
      ]);
    });

    fakeAsyncTest(
        'a value abandoned by abandonable is released after the job ended',
        () async {
      final gate = Gate();
      final job = Job<void>(key: 'abandon', (ctx) async {
        await ctx.abandonable(
          () async {
            await gate.wait();
            return open('late');
          },
          dispose: (db) => db.close(),
        );
      })
        ..ignoreFailure();
      await pump();
      job.cancel().ignore();
      await job.done;
      trace.add('job ended ${job.outcome}');
      await gate.release();
      await pump();

      expect(
        trace,
        containsAllInOrder(<String>[
          'job ended Cancelled(manual)',
          'late opened',
          'late closed',
        ]),
      );
    });

    test('a plain await: a cancellation while it opens closes the database',
        () {
      fakeAsync((async) {
        final job = page.plainAwait()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
        // The body waits `open` out and registers what it opened.
        expect(job.outcome, isA<Cancelled>());
        expect(trace, ['database opened', 'database closed']);
      });
    });

    test('a plain await: a success hands the database over open', () {
      fakeAsync((async) {
        final job = page.plainAwait()..ignoreFailure();
        async.flushTimers();
        expect(job.outcome, isA<Done<Database>>());
        expect(trace, ['database opened']);
      });
    });
  });

  group('The page', () {
    test('quotes what its code prints', () {
      final text = pages.map((doc) => File(doc).readAsStringSync());
      final blocks = RegExp(r'```text\n(.*?)\n```', dotAll: true)
          .allMatches(text.join('\n'))
          .map((match) => match.group(1)!.split('\n'))
          .toList();

      expect(blocks, quoted);
    });

    test('the first attempt of the callback keeps the lock', () {
      expect(scene(() => Job<Database>(first.sameCallback)), quoted[0]);
    });

    test('dispose releases the lock the job keeps', () {
      expect(scene(() => Job<Database>(page.keeping)), quoted[1]);
    });

    test('the first attempt of keeping back leaves the database open', () {
      stage.schemaCurrent = false;
      expect(scene(() => Job<Database?>(first.keptBack)), quoted[2]);
    });

    test('the body that keeps the database back closes it', () {
      stage.schemaCurrent = false;
      expect(scene(() => Job<Database?>(page.closingKeptBack)), quoted[4]);
    });

    test('the first attempt of the hand-over leaks the database', () {
      stage.migrateError = MigrationFailed();
      expect(
        scene(() => first.unregistered(first.connecting())..start()),
        quoted[5],
      );
    });

    test('the second attempt loses the database to the checkpoint of run', () {
      expect(scene(() => cancelledOnceConnected(nextLine)), quoted[7]);
    });

    test('registering on arrival closes the database on that cancellation', () {
      expect(scene(() => cancelledOnceConnected(page.onArrival)), quoted[8]);
    });

    test('the first attempt of unregistering closes the cursor twice', () {
      expect(
        scene(() => Job<void>(first.unregisteringAfter), cancelAt: 5),
        quoted[9],
      );
    });

    test('unregistering inside the action closes the cursor once', () {
      expect(
        scene(() => Job<void>(page.unregisteringInside), cancelAt: 5),
        quoted[10],
      );
    });

    test('a cancellation after the return closes what the body returned', () {
      expect(scene(page.afterTheReturn, cancelAt: 15), quoted[12]);
    });

    test('a plain await closes what it opened once the job is cancelled', () {
      expect(scene(page.plainAwait, cancelAt: 5), quoted[11]);
    });
  });

  for (final doc in pages) {
    test('$doc has no fence the checks do not read', () {
      expect(strayFences(doc), isEmpty);
    });
  }

  // Each version under its own file: a line of the answer turned into the
  // line of an attempt would still be found among all of them.
  const attemptsFile = 'test/support/cleanup_first_attempts.dart';
  const answersFile = 'test/support/cleanup_page.dart';
  final holders = [
    ('doc/cleanup.md', '# Cleanup', answersFile),
    ('doc/cleanup.md', '### The first attempt', attemptsFile),
    ('doc/cleanup.md', '### `dispose` for what the job keeps', answersFile),
    ('doc/cleanup.md', '### Closing what the job keeps back', answersFile),
    ('doc/cleanup-rules.md', '### The first attempt', attemptsFile),
    (
      'doc/cleanup-rules.md',
      '### The second attempt',
      'test/cleanup_rakes_test.dart',
    ),
    ('doc/cleanup-rules.md', '### Registering on arrival', answersFile),
    ('doc/cleanup-rules.md', '## Registering without a call', answersFile),
    (
      'doc/cleanup-rules.md',
      '### Unregistering inside the action',
      answersFile
    ),
    (
      'doc/cleanup-rules.md',
      '### Cancellation after the body returns',
      answersFile,
    ),
    (
      'doc/cleanup-rules.md',
      '### Registering after a plain `await`',
      answersFile,
    ),
  ];
  for (final (doc, heading, holder) in holders) {
    test('the code under "$heading" on $doc is a run of lines of $holder', () {
      expect(codeMissingFrom(doc, holder, under: heading), isEmpty);
    });
  }

  for (final doc in pages) {
    test('every piece of code on $doc is a run of lines of these files', () {
      expect(
        codeMissingFrom(
          doc,
          'test/cleanup_rakes_test.dart',
          alsoIn: [
            'test/support/cleanup_page.dart',
            'test/support/cleanup_first_attempts.dart',
          ],
        ),
        isEmpty,
      );
    });
  }
}

Future<void> pump() => Future<void>.delayed(Duration.zero);
