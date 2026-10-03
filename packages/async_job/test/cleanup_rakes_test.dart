// `doc/cleanup.md` runs here. Its code lives in three files, because the
// versions of one section differ by a word or a line: the opening example
// and the answers in `support/cleanup_page.dart`, the first attempts in
// `support/cleanup_first_attempts.dart`, and the second attempt of "A
// resource that travels" in this file. The code under each heading is
// held to the file of that heading, the line the page quotes is what its
// code prints, and what the page says about cleanup without code of its
// own is pinned here as well.
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
DeferredJob<Database> nextLine(Job<Database> connect) {
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
      (ctx) => ctx.wait(Database.open, discard: (db) => db.close()),
    );

/// Opens a database at once, under the name the trace will show.
Future<Database> open([String name = 'db']) async {
  stage.trace.add('$name opened');
  return Database(name);
}

/// The lines of the `text` blocks of the page, in its order.
List<String> quotedLines() => [
      for (final block in RegExp(r'```text\n(.*?)\n```', dotAll: true)
          .allMatches(File('doc/cleanup.md').readAsStringSync()))
        ...block.group(1)!.split('\n'),
    ];

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
        final job = Job<Database>(page.opening)..ignore();
        async.flushTimers();
        expect(job.outcome, isA<Done<Database>>());
        expect(trace, [
          'lock acquired',
          'db opened',
          'db migrated',
          'lock released',
        ]);
      });
    });

    test('a failed migration closes the database, then releases the lock', () {
      fakeAsync((async) {
        stage.migrateError = StateError('migration');
        final job = Job<Database>(page.opening)..ignore();
        async.flushTimers();
        expect(job.outcome, isA<Failed>());
        // The stack unwinds from the last registration.
        expect(trace, [
          'lock acquired',
          'db opened',
          'db migration failed',
          'db closed',
          'lock released',
        ]);
      });
    });
  });

  group('Choosing the callback', () {
    test('the first attempt keeps the lock held when the job succeeds', () {
      fakeAsync((async) {
        final job = Job<Database>(first.sameCallback)..ignore();
        async.flushTimers();
        expect(job.outcome, isA<Done<Database>>());
        expect(trace, ['lock acquired', 'db opened']);
      });
    });

    test('the first attempt releases both when the job is cancelled', () {
      fakeAsync((async) {
        final job = Job<Database>(first.sameCallback)..ignore();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
        expect(job.outcome, isA<Cancelled>());
        expect(trace, [
          'lock acquired',
          'db opened',
          'db closed',
          'lock released',
        ]);
      });
    });

    test('the first attempt releases the lock when the job fails', () {
      fakeAsync((async) {
        stage.openError = StateError('no database');
        final job = Job<Database>(first.sameCallback)..ignore();
        async.flushTimers();
        expect(job.outcome, isA<Failed>());
        expect(trace, ['lock acquired', 'lock released']);
      });
    });

    test('dispose releases the lock of a job that succeeds', () {
      fakeAsync((async) {
        final job = Job<Database>(page.keeping)..ignore();
        async.flushTimers();
        expect(job.outcome, isA<Done<Database>>());
        expect(trace, ['lock acquired', 'db opened', 'lock released']);
      });
    });

    test('dispose and discard release both when the job is cancelled', () {
      fakeAsync((async) {
        final job = Job<Database>(page.keeping)..ignore();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
        expect(job.outcome, isA<Cancelled>());
        expect(trace, [
          'lock acquired',
          'db opened',
          'db closed',
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
        )..ignore();
        async.flushTimers();
        expect(group.isFinished, isFalse);
        expect(trace, ['lock acquired', 'lock waits', 'db opened']);

        // The waiting branch is inside `join`, which waits its action
        // out, and the one holding the lock unwinds only after it.
        group.cancel().ignore();
        async.flushTimers();
        expect(group.isFinished, isFalse);
        expect(trace, isNot(contains('lock released')));
      });
    });
  });

  group('A resource that travels', () {
    test('the first attempt leaves the database open when migration fails', () {
      fakeAsync((async) {
        stage.migrateError = StateError('migration');
        final connect = first.connecting();
        final ready = first.unregistered(connect)
          ..ignore()
          ..start();
        async.flushTimers();
        expect(connect.outcome, isA<Done<Database>>());
        expect(ready.outcome, isA<Failed>());
        expect(trace, ['db opened', 'db migration failed']);
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
        quotedLines(),
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
      expect(printed, containsAll(quotedLines()));
    });

    test('the second attempt closes the database when migration fails', () {
      fakeAsync((async) {
        stage.migrateError = StateError('migration');
        final ready = nextLine(first.connecting())
          ..ignore()
          ..start();
        async.flushTimers();
        expect(ready.outcome, isA<Failed>());
        expect(trace, ['db opened', 'db migration failed', 'db closed']);
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
          final ready = version(connect)..ignore();
          cancelOnceDone(connect, ready);
          ready.start();
          async.flushTimers();
          expect(connect.outcome, isA<Done<Database>>());
          expect(ready.outcome, isA<Cancelled>());
          expect(trace, ['db opened', if (closes) 'db closed']);
        });
      });

      test('$name, cancelled while connect still opens the database', () {
        fakeAsync((async) {
          final connect = first.connecting();
          final ready = version(connect)
            ..ignore()
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
          expect(trace, ['db opened', 'db closed']);
        });
      });

      test('$name, a connect with cancellable: false, cancelled while it opens',
          () {
        fakeAsync((async) {
          final connect = stubborn();
          final ready = version(connect)
            ..ignore()
            ..start();
          async.elapse(const Duration(milliseconds: 5));
          ready.cancel().ignore();
          async.flushTimers();
          expect(connect.outcome, isA<Done<Database>>());
          expect(ready.outcome, isA<Cancelled>());
          expect(trace, ['db opened', if (closes) 'db closed']);
        });
      });
    }

    test('registering on arrival closes the database when migration fails', () {
      fakeAsync((async) {
        stage.migrateError = StateError('migration');
        final ready = page.onArrival(first.connecting())
          ..ignore()
          ..start();
        async.flushTimers();
        expect(ready.outcome, isA<Failed>());
        expect(trace, ['db opened', 'db migration failed', 'db closed']);
      });
    });

    test('registering on arrival hands the database on open on a success', () {
      fakeAsync((async) {
        final ready = page.onArrival(first.connecting())
          ..ignore()
          ..start();
        async.flushTimers();
        expect(ready.outcome, isA<Done<Database>>());
        expect(trace, ['db opened', 'db migrated']);
      });
    });

    test('the value of connect is the database the receiver closed', () {
      fakeAsync((async) {
        stage.migrateError = StateError('migration');
        final connect = first.connecting();
        page.onArrival(connect)
          ..ignore()
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
        Job<void>(page.flushing).ignore();
        async.flushTimers();
        expect(stage.sink, ['rows']);
      });
    });

    test('the first attempt closes the cursor once when nothing cancels it',
        () {
      fakeAsync((async) {
        final job = Job<void>(first.unregisteringAfter)..ignore();
        async.flushTimers();
        expect(job.outcome, isA<Done<void>>());
        expect(stage.cursor.closes, 1);
      });
    });

    test('the first attempt closes the cursor twice on a cancellation', () {
      fakeAsync((async) {
        final job = Job<void>(first.unregisteringAfter)..ignore();
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
        final job = Job<void>(page.unregisteringInside)..ignore();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
        expect(job.outcome, isA<Cancelled>());
        expect(trace, ['cursor read', 'cursor closed']);
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
        ..ignore();
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
        ..ignore();
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
        ..ignore();
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
        ..ignore();
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
        ..ignore();
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
        ..ignore();
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
      )..ignore();
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
        ..ignore();
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
          final members = <String, FutureOr<Object?> Function()>{
            'check': ctx.check,
            'wait': () => ctx.wait(() async => 1),
            'join': () => ctx.join(() async => 1),
            'pause': ctx.pause,
            'uncancellable': () => ctx.uncancellable(() async => 1),
            'run': () => ctx.run(Job.deferred<int>((ctx) async => 1)),
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
          for (final MapEntry(key: name, value: call) in members.entries) {
            try {
              await call();
            } on Object catch (error) {
              caught[name] = error;
            }
          }
        });
      })
        ..ignore();
      await job.done;

      expect(caught.keys.toSet(), bodyMembers());
      expect(caught.values, everyElement(isStateError));
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
            ..ignore();
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
        ..ignore();
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
        ..ignore();
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
          'db opened',
          'disposer D',
          'disposer B waits',
          'disposer B done',
          'disposer A',
          'db closed',
        ],
        reason: 'strict reverse order would close the database before A '
            'and B, registered before the discard; the second pass closes it '
            'after them',
      );
    });

    fakeAsyncTest('a branch whose group handed the values over keeps its value',
        () async {
      final job = Job<void>(key: 'group', (ctx) async {
        final values = await ctx.runAll(<Job<Database>>[
          Job.deferred<Database>(
            key: 'left',
            (branch) =>
                branch.wait(() => open('left'), discard: (db) => db.close()),
          ),
          Job.deferred<Database>(
            key: 'right',
            (branch) =>
                branch.wait(() => open('right'), discard: (db) => db.close()),
          ),
        ]);
        trace.add('group handed over ${values.length} values');
      })
        ..ignore();
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
        await ctx.runAll(<Job<Database>>[
          Job.deferred<Database>(key: 'left', (branch) async {
            final db = await branch.wait(
              () => open('left'),
              discard: (db) => db.close(),
            );
            await branch.join(gate.wait);
            return db;
          }),
          Job.deferred<Database>(
            key: 'right',
            (branch) =>
                branch.wait(() => open('right'), discard: (db) => db.close()),
          ),
        ]);
      })
        ..ignore();
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
            await ctx.wait(
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
          ..ignore();
        job.done.then((_) => at('the job ends')).ignore();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
      });
      return seen;
    }

    test('a value wait abandoned is released alongside the body', () {
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
          ctx.wait(
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
        ).ignore();
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
        await ctx.wait(() => delay(30));
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
        await ctx.wait(() => delay(1));
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

    test('two values wait abandoned are released side by side', () {
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
            ctx.wait(() => delay(10).then((_) => 'one'), dispose: release),
            ctx.wait(() => delay(15).then((_) => 'two'), dispose: release),
          ]);
        })
          ..ignore();
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

    fakeAsyncTest('a value abandoned by wait is released after the job ended',
        () async {
      final gate = Gate();
      final job = Job<void>(key: 'abandon', (ctx) async {
        await ctx.wait(
          () async {
            await gate.wait();
            return open('late');
          },
          dispose: (db) => db.close(),
        );
      })
        ..ignore();
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
        final job = page.plainAwait()..ignore();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
        // The body waits `open` out and registers what it opened.
        expect(job.outcome, isA<Cancelled>());
        expect(trace, ['db opened', 'db closed']);
      });
    });

    test('a plain await: a success hands the database over open', () {
      fakeAsync((async) {
        final job = page.plainAwait()..ignore();
        async.flushTimers();
        expect(job.outcome, isA<Done<Database>>());
        expect(trace, ['db opened']);
      });
    });
  });

  test('the page has no fence the checks do not read', () {
    expect(strayFences('doc/cleanup.md'), isEmpty);
  });

  // Each version under its own file: a line of the answer turned into the
  // line of an attempt would still be found among all of them.
  final holders = {
    '# Cleanup': 'test/support/cleanup_page.dart',
    '### The first attempt': 'test/support/cleanup_first_attempts.dart',
    '### `dispose` for what the job keeps': 'test/support/cleanup_page.dart',
    '### The second attempt': 'test/cleanup_rakes_test.dart',
    '### Registering on arrival': 'test/support/cleanup_page.dart',
    '## Registering without a call': 'test/support/cleanup_page.dart',
    '### Unregistering inside the action': 'test/support/cleanup_page.dart',
    '## Cleanup order and late results': 'test/support/cleanup_page.dart',
  };
  for (final MapEntry(key: heading, value: holder) in holders.entries) {
    test('the code under "$heading" is a run of lines of $holder', () {
      final pieces = codeMissingFrom('doc/cleanup.md', holder, under: heading);
      expect(pieces, isEmpty);
    });
  }

  test('every piece of code on the page is a run of lines of these files', () {
    expect(
      codeMissingFrom(
        'doc/cleanup.md',
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

Future<void> pump() => Future<void>.delayed(Duration.zero);
