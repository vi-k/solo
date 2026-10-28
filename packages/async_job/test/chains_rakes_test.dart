@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/children_page.dart' as page;
import 'support/children_stubs.dart' as stubs;
import 'support/compile_errors.dart';
import 'support/delay.dart';
import 'support/page_code.dart';

/// The first attempts of `doc/chains.md`, and what each one costs.
///
/// The sections of the page open with the version the vocabulary of the API
/// leads to and say what that version does instead of what it was meant to
/// do. Nothing else guards those statements: the page has no bench, so an
/// outcome or an order quoted there rots silently. Every claim the page
/// makes about a first attempt is pinned here, next to the version it then
/// shows.

void main() {
  group('Chains', () {
    test(
      "two children in a row: the parent's cancellation reaches the second",
      () {
        fakeAsync((async) {
          late ChildJob<void> second;
          final parent = Job<void>((ctx) async {
            final rows = await ctx.run(Job.deferred<int>((ctx) async => 21));
            second = Job.deferred<void>(
              (ctx) => ctx.join(() => delay(80 + rows)),
            );
            await ctx.run(second);
          })..ignoreFailure();

          async.elapse(const Duration(milliseconds: 10));
          parent.cancel().ignore();
          async.flushTimers();

          expect(
            (second.outcome! as Cancelled).reason,
            isA<ParentCancelReason>(),
          );
        });
      },
    );

    test("the parent's cancellation reaches a continuation still waiting "
        'for its source', () {
      fakeAsync((async) {
        final head = Job.deferred<int>((ctx) async {
          await ctx.abandonable(() => delay(50));
          return 1;
        });
        final tail = head.then<void>((ctx, rows) async {})..ignoreFailure();
        final parent = Job<void>((ctx) async {
          await ctx.run(head);
        })..ignoreFailure();

        async.elapse(const Duration(milliseconds: 10));
        parent.cancel().ignore();
        async.flushTimers();

        expect((tail.outcome! as Cancelled).reason, isA<ChainCancelReason>());
      });
    });

    test("the parent's cancellation does not reach a continuation already "
        'running', () {
      fakeAsync((async) {
        final head = Job.deferred<int>((ctx) async => 1);
        final tail = head.then<void>((ctx, rows) async {
          await ctx.abandonable(() => delay(80));
        });
        final parent = Job<void>((ctx) async {
          await ctx.run(head);
          await ctx.abandonable(() => delay(50));
        })..ignoreFailure();

        async.elapse(const Duration(milliseconds: 10));
        expect(tail.isRunning, isTrue);
        parent.cancel().ignore();
        async.flushTimers();

        expect(parent.outcome, isA<Cancelled>());
        expect(tail.outcome, isA<Done<void>>());
      });
    });

    test('cancelling a finished link leaves the running one alone', () {
      fakeAsync((async) {
        final loaded = Job<String>((ctx) async => '1');
        final parsed = loaded.then<int>((ctx, text) async {
          await ctx.abandonable(() => delay(50));
          return int.parse(text);
        });
        final saved = parsed.then<int>((ctx, number) async {
          await ctx.abandonable(() => delay(50));
          return number;
        });

        async.elapse(const Duration(milliseconds: 10));
        expect('${loaded.outcome}', 'Done(1)');
        expect(parsed.isFinished, isFalse);
        loaded.cancel().ignore();
        async.flushMicrotasks();
        expect(parsed.isCancelled, isFalse);
        expect(saved.isCancelled, isFalse);

        async.elapse(const Duration(milliseconds: 50));
        expect('${parsed.outcome}', 'Done(1)');
        expect(saved.isFinished, isFalse);
        loaded.cancel().ignore();
        parsed.cancel().ignore();
        async.flushMicrotasks();
        expect(saved.isCancelled, isFalse);

        async.flushTimers();
        expect('${saved.outcome}', 'Done(1)');
      });
    });

    test('the parent ends Done while the continuation is still running', () {
      fakeAsync((async) {
        final trace = <String>[];
        final head = Job.deferred<int>((ctx) async => 1);
        final tail = head.then<void>((ctx, rows) async {
          trace.add('the tail starts');
          await ctx.abandonable(() => delay(80));
          trace.add('the tail ends');
        });
        final parent = Job<void>((ctx) async {
          await ctx.run(head);
        })..ignoreFailure();

        async.elapse(const Duration(milliseconds: 20));

        // The parent waits for its children, not for what hangs off them.
        expect(parent.outcome, isA<Done<void>>());
        expect(trace, ['the tail starts']);

        async.flushTimers();
        expect(trace, ['the tail starts', 'the tail ends']);
        expect(tail.outcome, isA<Done<void>>());
      });
    });

    test('a parent still running stops a running continuation through '
        'onCancel', () {
      fakeAsync((async) {
        final head = Job.deferred<int>((ctx) async => 1);
        final tail = head.then<void>((ctx, rows) async {
          await ctx.abandonable(() => delay(80));
        })..ignoreFailure();
        final parent = Job<void>((ctx) async {
          ctx.onCancel(() => tail.cancel().ignore());
          await ctx.run(head);
          await ctx.abandonable(() => delay(50));
        })..ignoreFailure();

        async.elapse(const Duration(milliseconds: 10));
        expect(tail.isRunning, isTrue);
        parent.cancel().ignore();
        async.flushTimers();

        expect(tail.outcome, isA<Cancelled>());
      });
    });

    test('a running job the callback returns is not waited for', () {
      fakeAsync((async) {
        final saving = Job<void>(
          (ctx) => ctx.pause(const Duration(seconds: 1)),
        );
        final parsed = Job<int>((ctx) async => 21);
        // The page says this compiles under `then<void>`.
        final stored = parsed.then<void>((ctx, number) => saving);

        async.elapse(const Duration(milliseconds: 1));

        expect(stored.outcome, isA<Done<void>>());
        expect(saving.isFinished, isFalse);
        async.flushTimers();
      });
    });

    test('a deferred job the callback returns never starts, and the '
        'continuation fails', () {
      fakeAsync((async) {
        var ran = false;
        final saving = Job.deferred<void>((ctx) async {
          ran = true;
        });
        final parsed = Job<int>((ctx) async => 21);
        final stored = parsed.then<void>((ctx, number) => saving);
        Outcome<void>? outcome;
        stored.done.then((done) => outcome = done).ignore();

        async.flushTimers();

        expect(
          outcome,
          isA<Failed>().having(
            (failed) => failed.error,
            'error',
            isA<ArgumentError>(),
          ),
        );
        expect(ran, isFalse);
        expect(saving.isFinished, isFalse);
        saving.cancel().ignore();
        async.flushTimers();
      });
    });

    test('a continuation waits for the job it runs as its child', () {
      fakeAsync((async) {
        stubs.stage = stubs.Stage();
        final parsed = Job<int>((ctx) async => 21);
        final stored = page.storeParsed(parsed);
        stored.done
            .then((outcome) => stubs.stage.trace.add('stored $outcome'))
            .ignore();

        async.flushTimers();

        expect(stubs.stage.trace, ['saved number 21', 'stored Done(null)']);
      });
    });

    test('then does not start a deferred source, whatever the length', () {
      fakeAsync((async) {
        var ran = false;
        final source = Job.deferred<int>((ctx) async {
          ran = true;
          return 1;
        });
        final last = source
            .then<int>((ctx, value) => value + 1)
            .then<int>((ctx, value) => value + 1);

        async.flushTimers();
        expect(ran, isFalse);
        expect(last.isFinished, isFalse);

        source.start();
        async.flushTimers();
        expect(last.outcome, isA<Done<int>>().having((d) => d.value, 'v', 3));
      });
    });

    test(
      'a continuation made in a body is a root the body does not wait for',
      () {
        fakeAsync((async) {
          late final Job<void> tail;
          final parent = Job<void>((ctx) async {
            final rows = Job.deferred<int>((ctx) async => 1);
            tail = rows.then<void>((ctx, value) => ctx.join(() => delay(50)))
              ..ignoreFailure();
            await ctx.run(rows);
          });

          async.elapse(const Duration(milliseconds: 10));

          expect(parent.outcome, isA<Done<void>>());
          expect(tail.isChild, isFalse);
          expect(tail.isRunning, isTrue);
          async.flushTimers();
          expect(tail.outcome, isA<Done<void>>());
        });
      },
    );

    test('the continuation closes the source it receives', () {
      fakeAsync((async) {
        stubs.stage = stubs.Stage();
        final (opened, archived) = page.archiveOpened();

        async.flushTimers();

        expect(opened.outcome, isA<Done<stubs.Source>>());
        expect(archived.outcome, isA<Done<void>>());
        expect(stubs.stage.trace, ['archive of 1', 'rows closed']);
      });
    });

    test(
      'two branches of shared() that each close the rows close them twice',
      () {
        fakeAsync((async) {
          stubs.stage = stubs.Stage();
          final opened = Job<stubs.Source>(
            (ctx) => ctx.abandonable(
              stubs.openRows,
              discard: (rows) => rows.close(),
            ),
          );
          final received = <stubs.Source>[];
          for (var branch = 0; branch < 2; branch++) {
            opened.shared().then<void>((ctx, rows) {
              received.add(rows);
              ctx.onDispose(rows.close);
            });
          }

          async.flushTimers();

          expect(identical(received.first, received.last), isTrue);
          expect(stubs.stage.trace, ['rows closed', 'rows closed']);
        });
      },
    );

    test('the code that waits for both branches closes the rows once', () {
      fakeAsync((async) {
        stubs.stage = stubs.Stage();
        var finished = false;
        unawaited(
          page.archiveAndWarm(stubs.Cache()).then((_) => finished = true),
        );

        async.flushTimers();

        expect(finished, isTrue);
        expect(
          stubs.stage.trace,
          unorderedEquals(['archive of 1', 'cache warmed', 'rows closed']),
        );
        expect(stubs.stage.trace.last, 'rows closed');
      });
    });

    test('cancelled while it waited, the continuation never runs, and the '
        'discard of the source closes what arrives', () {
      fakeAsync((async) {
        stubs.stage = stubs.Stage()..rowsTake = 50;
        final (opened, archived) = page.archiveOpened();
        opened.ignoreFailure();

        async.elapse(const Duration(milliseconds: 10));
        archived.cancel().ignore();
        async.flushMicrotasks();
        expect(archived.outcome, isA<Cancelled>());
        expect(opened.outcome, isA<Cancelled>());
        expect(stubs.stage.trace, isEmpty);

        async.flushTimers();
        expect(stubs.stage.trace, ['rows closed']);
      });
    });

    test('a source that refuses the cancellation ends Done with the source '
        'open, and the handle closes it', () {
      fakeAsync((async) {
        stubs.stage = stubs.Stage()..rowsTake = 50;
        final opened = Job<stubs.Source>(
          cancellable: false,
          (ctx) => ctx.abandonable(
            stubs.openRows,
            discard: (source) => source.close(),
          ),
        );
        final archived = opened.then<void>((ctx, rows) async {
          ctx.onDispose(rows.close);
        });

        async.elapse(const Duration(milliseconds: 10));
        archived.cancel().ignore();
        async.flushTimers();

        expect(opened.outcome, isA<Done<stubs.Source>>());
        expect(archived.outcome, isA<Cancelled>());
        expect(stubs.stage.trace, isEmpty);

        opened.value.then((source) => source.close()).ignore();
        async.flushMicrotasks();
        expect(stubs.stage.trace, ['rows closed']);
      });
    });

    test('a source whose body awaits its continuation never finishes', () {
      fakeAsync((async) {
        final loaded = page.loadedAwaitingParsed();

        async.flushTimers();
        expect(loaded.isFinished, isFalse);

        var back = false;
        loaded.cancel().then((_) => back = true).ignore();
        async.flushTimers();
        expect(back, isFalse);
        expect(loaded.isFinished, isFalse);
      });
    });

    test('the same with done in place of value', () {
      fakeAsync((async) {
        late final Job<int> tail;
        final source = Job<int>((ctx) async {
          await tail.done;
          return 1;
        });
        tail = source.then<int>((ctx, value) => value)..ignoreFailure();

        async.flushTimers();
        expect(source.isFinished, isFalse);
        expect(tail.isFinished, isFalse);

        var back = false;
        source.cancel().then((_) => back = true).ignore();
        async.flushTimers();
        expect(back, isFalse);
      });
    });

    test('a source whose cleanup awaits its continuation never finishes, '
        'and cancel() does not return', () {
      fakeAsync((async) {
        late final Job<int> tail;
        final source = Job<int>((ctx) async {
          ctx.onDispose(() => tail.done);
          return 1;
        });
        tail = source.then<int>((ctx, value) => value)..ignoreFailure();

        async.flushTimers();
        expect(source.isFinished, isFalse);
        expect(tail.isFinished, isFalse);

        var back = false;
        source.cancel().then((_) => back = true).ignore();
        async.flushTimers();
        expect(back, isFalse);
        expect(source.isFinished, isFalse);
      });
    });
  });

  group('The code of the page', () {
    setUp(() => stubs.stage = stubs.Stage());

    List<String> trace() => stubs.stage.trace;

    test('the chain saves the parsed number', () {
      fakeAsync((async) {
        page.chain();
        async.flushTimers();
        expect(trace(), ['saved number 21']);
      });
    });

    test('the page quotes what the cancelled chain prints', () {
      final printed = <String>[];
      runZoned(
        () => fakeAsync((async) {
          stubs.stage.textTake = 30;
          page.cancelledChain();
          async.flushTimers();
        }),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );
      expect(printed, [
        'loaded: Cancelled(chain)',
        'parsed: Cancelled(chain)',
        'saved: Cancelled(manual)',
      ]);
      final text = File('doc/chains.md').readAsStringSync();
      final quoted = RegExp(
        r"print\('saved: \$\{saved.outcome\}'\);\n```\n\n```text\n(.*?)\n```",
        dotAll: true,
      );
      expect(quoted.firstMatch(text)!.group(1)!.split('\n'), printed);
      expect(trace(), isEmpty, reason: 'nothing was saved');
    });

    List<String> printedBy(Future<void> Function() code) {
      final printed = <String>[];
      runZoned(
        () => fakeAsync((async) {
          stubs.stage.textTake = 30;
          code();
          async.flushTimers();
        }),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );
      return printed;
    }

    /// The output blocks that follow a block ending with the print of
    /// `shown`, in the order of the page.
    List<List<String>> shownQuotes() => [
      for (final match in RegExp(
        r"print\('shown: \$\{shown.outcome\}'\);\n```\n\n```text\n"
        r'(.*?)\n```',
        dotAll: true,
      ).allMatches(File('doc/chains.md').readAsStringSync()))
        match.group(1)!.split('\n'),
    ];

    test('two continuations: the second then throws, as the page quotes', () {
      fakeAsync((async) {
        stubs.stage.textTake = 30;
        final text = File('doc/chains.md').readAsStringSync();
        final quoted = RegExp(
          r'showText\(text\)\);\n```\n\n```text\n(.*?)\n```',
          dotAll: true,
        );
        expect(
          page.twoContinuations,
          throwsA(
            isA<StateError>().having(
              (error) => '$error',
              'text',
              quoted.firstMatch(text)!.group(1),
            ),
          ),
        );
        async.flushTimers();
        expect(trace(), isEmpty, reason: 'nothing was shown');
      });
    });

    test('a handle for each branch: cancelling one leaves the source and '
        'the other', () {
      final printed = printedBy(page.twoHandles);
      expect(printed, [
        'parsed: Cancelled(manual)',
        'loaded: Done(21)',
        'shown: Done(null)',
      ]);
      expect(shownQuotes().first, printed);
      expect(trace(), ['shown 21']);
    });

    for (final answerer in [false, true]) {
      test('every branch cancelled before loaded fails: loaded answers for '
          'it, answerer: $answerer', () {
        // The source is made in one zone and continued in another, so the
        // zone that gets the failure says who answered for it.
        final made = <String>[];
        final continued = <String>[];
        final answers = _Answers();
        fakeAsync((async) {
          late Job<String> loaded;
          runZonedGuarded(
            () => loaded = Job<String>(
              key: 'loaded',
              observer: answerer ? answers : null,
              (ctx) => ctx.join(() async {
                await delay(30);
                throw StateError('offline');
              }),
            ),
            (error, stackTrace) => made.add('$error'),
          );
          late List<Job<Object?>> branches;
          runZonedGuarded(
            () => branches = [
              loaded.shared().then<int>((ctx, text) => int.parse(text)),
              loaded.shared().then<void>((ctx, text) => stubs.showText(text)),
            ],
            (error, stackTrace) => continued.add('$error'),
          );
          async.elapse(const Duration(milliseconds: 10));
          for (final branch in branches) {
            branch.cancel().ignore();
          }
          async.flushTimers();
          expect('${loaded.outcome}', 'Failed(Bad state: offline)');
        });
        expect(continued, isEmpty);
        expect(made, answerer ? isEmpty : ['Bad state: offline']);
        expect(
          answers.answered,
          answerer ? ['Job(loaded): Bad state: offline'] : isEmpty,
        );
      });
    }

    test(
      'two jobs that wait: cancelling one leaves the source and the other',
      () {
        final printed = printedBy(page.twoWaiting);
        expect(printed, [
          'parsed: Cancelled(manual)',
          'loaded: Done(21)',
          'shown: Done(null)',
        ]);
        expect(shownQuotes(), hasLength(2));
        expect(shownQuotes().last, printed);
        expect(trace(), ['shown 21']);
      },
    );

    test('a source that fails after one job left: that job hears it late, '
        'the other as its failure', () {
      final zone = <String>[];
      final heard = <String>[];
      runZonedGuarded(
        () => fakeAsync((async) {
          final observer = _Heard(heard);
          final loaded = Job<String>(
            (ctx) => ctx.join(() async {
              await delay(30);
              throw StateError('offline');
            }),
          );
          final parsed = Job<int>(
            observer: observer,
            (ctx) async => int.parse(await ctx.abandonable(() => loaded.value)),
          );
          final shown = Job<void>(
            (ctx) async =>
                stubs.showText(await ctx.abandonable(() => loaded.value)),
          );
          // The screen that stays reads the outcome of its job.
          unawaited(shown.done);
          async.elapse(const Duration(milliseconds: 10));
          parsed.cancel().ignore();
          async.flushTimers();
          expect('${shown.outcome}', 'Failed(Bad state: offline)');
          expect('${parsed.outcome}', 'Cancelled(manual)');
        }),
        (error, stackTrace) => zone.add('$error'),
      );
      expect(heard, ['Bad state: offline']);
      expect(zone, ['Bad state: offline']);
    });

    (Job<String>, Job<int>, Job<void>) slowChain({bool cancellable = true}) {
      final loaded = Job<String>(
        cancellable: cancellable,
        (ctx) => ctx.join(() async {
          await delay(30);
          return '21';
        }),
      );
      final parsed = loaded.then<int>((ctx, text) => int.parse(text));
      final saved = parsed.then<void>((ctx, number) async {});
      return (loaded, parsed, saved);
    }

    for (final (cancel, expected) in [
      (0, ['manual', 'chain', 'chain']),
      (1, ['chain', 'manual', 'chain']),
      (2, ['chain', 'chain', 'manual']),
    ]) {
      test(
        'the cancel table: cancelling link $cancel while the text loads',
        () {
          fakeAsync((async) {
            final (loaded, parsed, saved) = slowChain();
            async.elapse(const Duration(milliseconds: 10));
            [loaded, parsed, saved][cancel].cancel().ignore();
            async.flushTimers();
            expect([
              for (final job in [loaded, parsed, saved])
                (job.outcome! as Cancelled).reason.name,
            ], expected);
          });
        },
      );
    }

    test('the cancel table: parsed, made on a handle of loaded', () {
      fakeAsync((async) {
        final loaded = Job<String>(
          (ctx) => ctx.join(() async {
            await delay(30);
            return '21';
          }),
        );
        final handle = loaded.shared();
        final parsed = handle.then<int>((ctx, text) => int.parse(text));
        final saved = parsed.then<void>((ctx, number) async {});
        final shown = loaded.shared().then<void>((ctx, text) {});
        async.elapse(const Duration(milliseconds: 10));
        parsed.cancel().ignore();
        async.flushMicrotasks();
        expect(handle.outcome, isA<Cancelled>(), reason: 'at once');
        expect(loaded.isFinished, isFalse, reason: 'and loaded is not asked');
        async.flushTimers();
        expect(
          [
            for (final job in [handle, parsed, saved])
              (job.outcome! as Cancelled).reason.name,
          ],
          ['chain', 'manual', 'chain'],
        );
        expect('${loaded.outcome}', 'Done(21)');
        expect('${shown.outcome}', 'Done(null)');
      });
    });

    test('a loaded that refuses stops the cancellation there', () {
      fakeAsync((async) {
        final (loaded, parsed, saved) = slowChain(cancellable: false);
        async.elapse(const Duration(milliseconds: 10));
        loaded.cancel().ignore();
        async.flushTimers();
        expect(loaded.outcome, isA<Done<String>>());
        expect(parsed.outcome, isA<Done<int>>());
        expect(saved.outcome, isA<Done<void>>());
      });
    });

    test(
      'a continuation of a wider type takes a deferred job for its value',
      () {
        fakeAsync((async) {
          final saving = Job.deferred<void>((ctx) async {});
          final parsed = Job<int>((ctx) async => 21);
          final stored = parsed.then<Object>((ctx, number) => saving);
          async.flushTimers();
          expect(
            stored.outcome,
            isA<Done<Object>>().having((done) => done.value, 'value', saving),
          );
          expect(saving.isFinished, isFalse);
          saving.cancel().ignore();
          async.flushTimers();
        });
      },
    );

    test('the first attempt: the continuation takes the job for its value', () {
      fakeAsync((async) {
        final parsed = Job<int>((ctx) async => 21);
        final stored = page.storeParsedWithoutWaiting(parsed);
        async.flushTimers();
        expect(
          stored.outcome,
          isA<Done<void>>().having(
            (done) => done.value,
            'value',
            isA<Job<void>>(),
          ),
        );
        expect(trace(), ['saved number 21']);
      });
    });

    test(
      'ctx.run does not take the continuation: the error the page quotes',
      () async {
        final errors = await compileErrors('''
import 'package:async_job/async_job.dart';

Future<int> load() async => 21;
Future<void> report(int rows) async {}

void attempt() {
${page.adoptedTail}
}
''');
        final text = File('doc/chains.md').readAsStringSync();
        final quoted = RegExp(
          r'does not compile:\n\n```text\n(.*?)\n```',
          dotAll: true,
        );
        expect(errors, [quoted.firstMatch(text)!.group(1)]);
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test('no link of a chain is a child', () {
      fakeAsync((async) {
        final child = Job.deferred<int>((ctx) async => 1);
        final tail = child.then<int>((ctx, rows) async => rows);
        final next = tail.then<int>((ctx, rows) async => rows);
        expect(child, isA<ChildJob<int>>());
        expect(tail, isNot(isA<ChildJob<int>>()));
        expect(next, isNot(isA<ChildJob<int>>()));
        async.flushTimers();
      });
    });

    test('a cancelled continuation cancels its running source and the parent, '
        'as the page quotes', () {
      fakeAsync((async) {
        stubs.stage.loadTake = 50;
        final child = Job.deferred<int>((ctx) => ctx.abandonable(stubs.load));
        final tail = child.then<void>((ctx, rows) => stubs.report(rows))
          ..ignoreFailure();
        final parent = Job<void>((ctx) async {
          ctx.log(await ctx.run(child));
        })..ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));
        tail.cancel().ignore();
        async.flushTimers();
        final text = File('doc/chains.md').readAsStringSync();
        final quoted = RegExp(
          r'with `HandlerCancelReason`:\n\n```text\n(.*?)\n```',
          dotAll: true,
        );
        expect(
          'parent: ${parent.outcome}, child: ${child.outcome}',
          quoted.firstMatch(text)!.group(1),
        );
        expect(trace(), isEmpty, reason: 'the report never ran');
      });
    });

    test('with the source the only child, the parent ends first', () {
      fakeAsync((async) {
        page.reportedRows();
        async.flushTimers();
        expect(trace(), ['parent Done(null)', 'reported 21']);
      });
    });

    test('two children in a row: the parent waits for both', () {
      fakeAsync((async) {
        final parent = page.twoChildrenInARow();
        parent.done.then((outcome) => stubs.stage.trace.add('parent $outcome'));
        async.flushTimers();
        expect(trace(), ['reported 21', 'parent Done(null)']);
      });
    });
  });

  test('every piece of code on chains.md is a run of lines of these files', () {
    expect(
      codeMissingFrom('doc/chains.md', 'test/support/children_page.dart'),
      isEmpty,
    );
    expect(strayFences('doc/chains.md'), isEmpty);
  });
}

/// Writes down each error `onError` hears.
final class _Heard extends JobObserver {
  _Heard(this.heard);

  final List<String> heard;

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => heard.add('$error');
}

/// Answers for every failure it is asked about and keeps the list.
final class _Answers extends JobObserver with JobAnswerer {
  final answered = <String>[];

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      answered.add('$job: $error');
}
