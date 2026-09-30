@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/page_code.dart';
import 'support/probe_job.dart';

/// The first attempts of `doc/outcomes.md`, and what each one costs.
///
/// Four sections of the page open with the version the vocabulary of the
/// API leads to and show what that version prints. The page has no bench,
/// so the code is repeated here as it stands there. The last two tests hold
/// the page to this file: the lines it quotes to the lines these tests
/// print, and every line of its code to a line of this file. A quote or a
/// fragment that drifts turns this file red, not only a broken engine.

final class RequestCancelReason extends CancelReason {
  final Object error;
  final StackTrace stackTrace;

  const RequestCancelReason(this.error, this.stackTrace);

  @override
  String get name => 'request';
}

/// What each `text` block of the page says, in the order of the page.
const quoted = [
  ['failed: Cancelled(manual)'],
  ['cancelled: manual'],
  [
    'zone: Bad state: disk full',
    'status: sync failed: Bad state: disk full',
  ],
  ['status: sync failed: Bad state: disk full'],
  ['cancelled: handler'],
  ['request failed: Bad state: token expired'],
  ['step finished', 'cleanup', 'cancelling: manual'],
  ['cancelling: manual', 'step finished', 'cleanup'],
];

/// What the page's code prints, in the order it prints it.
final printed = <String>[];

/// The page prints; here that goes to [printed].
void print(Object? line) => printed.add('$line');

/// The data `fetch` brings, and the report made of it.
final class Data {
  const Data();
}

final class Report {
  final Data data;

  const Report(this.data);

  @override
  String toString() => 'Report($data)';
}

Future<Data> download(JobContext ctx) async {
  await ctx.wait(() => delay(50));
  return const Data();
}

/// The observer of a job whose failure nobody waits for: it hears it.
final class HearingObserver extends JobObserver {
  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('onError: $error');
}

/// The report job of the page: its body takes 50 ms.
Job<String> startReport() => Job<String>((ctx) async {
      await ctx.wait(() => delay(50));
      return 'Q3';
    });

CancelReason origin(Cancelled cancelled) => switch (cancelled.reason) {
      HandlerCancelReason(:final cause?) ||
      ParentCancelReason(:final cause?) ||
      ChainCancelReason(:final cause) =>
        origin(cause),
      final reason => reason,
    };

final class FinishObserver extends JobObserver {
  final List<String> seen;

  FinishObserver(this.seen);

  @override
  void onFinish(Job<Object?> job) => seen.add('onFinish ${job.outcome}');
}

/// Runs [body] in a zone of its own and returns what reached that zone.
///
/// The assertions stay outside: an `expect` inside the guarded zone would
/// land in the very handler that collects.
List<String> zoneOf(void Function(FakeAsync async) body) {
  final caught = <String>[];
  runZonedGuarded(
    () => fakeAsync(body),
    (error, stackTrace) => caught.add('zone: $error'),
  );
  return caught;
}

void main() {
  group('Reading the result', () {
    test('value in a try prints a cancellation as a failure', () {
      fakeAsync((async) {
        printed.clear();
        final report = startReport();
        () async {
          try {
            print('report: ${await report.value}');
          } on Object catch (error) {
            print('failed: $error');
          }
        }();
        async.elapse(const Duration(milliseconds: 10));
        report.cancel().ignore();
        async.flushTimers();

        expect(printed, quoted[0]);
      });
    });

    test('on Exception takes the cancellation too', () {
      fakeAsync((async) {
        Object? caught;
        final report = startReport();
        () async {
          try {
            await report.value;
          } on Exception catch (error) {
            caught = error;
          }
        }();
        async.elapse(const Duration(milliseconds: 10));
        report.cancel().ignore();
        async.flushTimers();

        expect(caught, same(report.outcome));
      });
    });

    test('a switch over done gives the cancellation its own line', () {
      fakeAsync((async) {
        printed.clear();
        final report = startReport();
        () async {
          final message = switch (await report.done) {
            Done(:final value) => 'report: $value',
            Failed(:final error) => 'failed: $error',
            Cancelled(:final reason) => 'cancelled: $reason',
          };
          print(message);
        }();
        async.elapse(const Duration(milliseconds: 10));
        report.cancel().ignore();
        async.flushTimers();

        expect(printed, quoted[1]);
      });
    });
  });

  group('A failure nobody waits for', () {
    Future<void> upload(JobContext ctx) async {
      await ctx.wait(() => delay(10));
      throw StateError('disk full');
    }

    String status(Job<void> sync) => switch (sync.outcome) {
          null => 'syncing',
          Done() => 'synced',
          Failed(:final error) => 'sync failed: $error',
          Cancelled() => 'sync cancelled',
        };

    test('reading outcome leaves the failure to the zone', () {
      printed.clear();
      runZonedGuarded(
        () => fakeAsync((async) {
          final sync = Job<void>(upload);

          void draw() {
            // Wherever the status line is drawn:
            final status = switch (sync.outcome) {
              null => 'syncing',
              Done() => 'synced',
              Failed(:final error) => 'sync failed: $error',
              Cancelled() => 'sync cancelled',
            };
            print('status: $status');
          }

          draw();
          async.flushTimers();
          draw();
        }),
        (error, stackTrace) => print('zone: $error'),
      );

      expect(printed, ['status: syncing', ...quoted[2]]);
    });

    test('ignore keeps the zone quiet while the status line reads it', () {
      printed.clear();
      runZonedGuarded(
        () => fakeAsync((async) {
          final sync = Job<void>(upload)..ignore();
          async.flushTimers();
          print('status: ${status(sync)}');
        }),
        (error, stackTrace) => print('zone: $error'),
      );

      expect(printed, quoted[3]);
    });

    test('onError of the observer hears the failure and does not observe it',
        () {
      printed.clear();
      runZonedGuarded(
        () => fakeAsync((async) {
          Job<void>(observer: HearingObserver(), upload);
          async.flushTimers();
        }),
        (error, stackTrace) => print('zone: $error'),
      );

      expect(printed, [
        'onError: Bad state: disk full',
        'zone: Bad state: disk full',
      ]);
    });

    test('onFinish reading the outcome does not observe it', () {
      final seen = <String>[];
      final caught = zoneOf((async) {
        Job<void>(observer: FinishObserver(seen), upload);
        async.flushTimers();
      });

      expect(seen, ['onFinish Failed(Bad state: disk full)']);
      expect(caught, ['zone: Bad state: disk full']);
    });

    test('awaiting cancel and registering with whenCancelled do not either',
        () {
      var cancelReturned = false;
      final caught = zoneOf((async) {
        final sync = Job<void>(cancellable: false, upload)
          ..whenCancelled((_) {});
        async.elapse(const Duration(milliseconds: 5));
        // Awaited for real: the future of `cancel` completes, and the
        // failure still goes to the zone.
        sync.cancel().then((_) => cancelReturned = true).ignore();
        async.flushTimers();
      });

      expect(cancelReturned, isTrue);
      expect(caught, ['zone: Bad state: disk full']);
    });

    for (final (name, touch) in <(String, void Function(Job<void>))>[
      ('done', (sync) => sync.done.ignore()),
      ('value', (sync) => sync.value.ignore()),
    ]) {
      test('accessing $name observes the failure', () {
        final caught = zoneOf((async) {
          touch(Job<void>(upload));
          async.flushTimers();
        });

        expect(caught, isEmpty);
      });
    }

    test('value left unhandled throws the error, as any future does', () {
      final caught = zoneOf((async) {
        // The waiting code takes the future and handles nothing.
        unawaited(Job<void>(upload).value);
        async.flushTimers();
      });

      expect(caught, ['zone: Bad state: disk full']);
    });

    test('waiting does not observe a failure a cancellation covered', () {
      // The upload fails 10 ms in while a child of the job still runs, and
      // the cancellation 20 ms in arrives before the job has ended.
      Future<void> uploadWithChild(JobContext ctx) async {
        ctx
            .run(Job.deferred<void>((ctx) => ctx.wait(() => delay(50))))
            .ignore();
        await upload(ctx);
      }

      final seen = <String>[];
      final waited = zoneOf((async) {
        final sync = Job<void>(uploadWithChild);
        unawaited(sync.done.then((outcome) => seen.add('done: $outcome')));
        async.elapse(const Duration(milliseconds: 20));
        sync.cancel().ignore();
        async.flushTimers();
        seen.add('status: ${status(sync)}');
      });
      expect(seen, ['done: Cancelled(manual)', 'status: sync cancelled']);
      expect(waited, ['zone: Bad state: disk full']);

      final ignored = zoneOf((async) {
        final sync = Job<void>(uploadWithChild)..ignore();
        async.elapse(const Duration(milliseconds: 20));
        sync.cancel().ignore();
        async.flushTimers();
      });
      expect(ignored, isEmpty, reason: 'ignore keeps it out of the zone');
    });
  });

  group('Why a job was cancelled', () {
    Future<void> refreshToken() async => throw StateError('token expired');

    /// `report` and its child `fetch`, cancelled the way the page does it.
    ({Job<Report> report, Job<Data> fetch, RequestCancelReason? heard})
        requestFails(FakeAsync async) {
      final fetch = Job.deferred<Data>(download);
      final report = Job<Report>((ctx) async {
        final data = await ctx.run(fetch);
        return Report(data);
      });
      // ignore: cascade_invocations -- the page's code ends above
      report.ignore();
      async.elapse(const Duration(milliseconds: 5));
      RequestCancelReason? heard;
      fetch.whenCancelled(
        (cancelled) => heard = cancelled.reason as RequestCancelReason,
      );
      () async {
        try {
          await refreshToken();
        } on Object catch (error, stackTrace) {
          await fetch.cancel(reason: RequestCancelReason(error, stackTrace));
        }
      }();
      async.flushTimers();
      return (report: report, fetch: fetch, heard: heard);
    }

    test('the listener and the outcome of fetch share the instance', () {
      fakeAsync((async) {
        final (report: _, :fetch, :heard) = requestFails(async);

        expect(heard, isNotNull);
        expect((fetch.outcome! as Cancelled).reason, same(heard));
      });
    });

    test('a case for the reason of report misses the request', () {
      fakeAsync((async) {
        printed.clear();
        final (:report, :fetch, heard: _) = requestFails(async);
        () async {
          final message = switch (await report.done) {
            Done(:final value) => 'report: $value',
            Failed(:final error) => 'failed: $error',
            Cancelled(reason: RequestCancelReason(:final error)) =>
              'request failed: $error',
            Cancelled(:final reason) => 'cancelled: $reason',
          };
          print(message);
        }();
        async.flushMicrotasks();

        expect(printed, quoted[4]);
        final reason = (report.outcome! as Cancelled).reason;
        expect(reason, isA<HandlerCancelReason>());
        expect((reason as HandlerCancelReason).cause, same(fetch.outcome));
      });
    });

    test('origin follows the cause down to the request', () {
      fakeAsync((async) {
        printed.clear();
        final (:report, fetch: _, heard: _) = requestFails(async);
        () async {
          final message = switch (await report.done) {
            Done(:final value) => 'report: $value',
            Failed(:final error) => 'failed: $error',
            final Cancelled cancelled => switch (origin(cancelled)) {
                RequestCancelReason(:final error) => 'request failed: $error',
                final reason => 'cancelled: $reason',
              },
          };
          print(message);
        }();
        async.flushMicrotasks();

        expect(printed, quoted[5]);
      });
    });

    test('origin follows a cascade from the parent', () {
      fakeAsync((async) {
        late Job<void> child;
        final parent = Job<void>((ctx) async {
          child = Job.deferred<void>((ctx) => ctx.wait(() => delay(50)));
          ctx.run(child).ignore();
          await ctx.wait(() => delay(50));
        })
          ..ignore();
        async.elapse(const Duration(milliseconds: 5));
        final reason = RequestCancelReason('offline', StackTrace.current);
        parent.cancel(reason: reason).ignore();
        async.flushTimers();

        final cancelled = child.outcome! as Cancelled;
        expect(cancelled.reason, isA<ParentCancelReason>());
        expect(origin(cancelled), same(reason));
      });
    });

    test('origin follows a chain of then', () {
      fakeAsync((async) {
        final source = startReport()..ignore();
        final tail = source.then<int>((ctx, value) => value.length)..ignore();
        async.elapse(const Duration(milliseconds: 5));
        final reason = RequestCancelReason('offline', StackTrace.current);
        tail.cancel(reason: reason).ignore();
        async.flushTimers();

        final cancelled = source.outcome! as Cancelled;
        expect(cancelled.reason, isA<ChainCancelReason>());
        expect(origin(cancelled), same(reason));
      });
    });

    test('origin stops where a body threw Cancelled itself', () {
      fakeAsync((async) {
        final job = Job<void>((ctx) async => throw const Cancelled('why'))
          ..ignore();
        async.flushTimers();

        final reason = origin(job.outcome! as Cancelled);
        expect(reason, isA<HandlerCancelReason>());
        expect((reason as HandlerCancelReason).cause, isNull);
      });
    });

    test('origin stops at the reason a group gives the other branch', () {
      fakeAsync((async) {
        final error = StateError('boom');
        final failing = Job.deferred<int>((ctx) async {
          await ctx.wait(() => delay(10));
          throw error;
        });
        final neighbour = Job.deferred<int>((ctx) async {
          await ctx.wait(() => delay(100));
          return 2;
        });
        Job<List<int>>((ctx) => ctx.runAll([failing, neighbour])).ignore();
        async.flushTimers();

        final reason = origin(neighbour.outcome! as Cancelled);
        expect(reason, isA<SiblingCancelReason>());
        expect((reason as SiblingCancelReason).cause, same(error));
      });
    });

    test('a group that refused a job gives the others its ArgumentError', () {
      fakeAsync((async) {
        final first = Job.deferred<int>((ctx) async {
          await ctx.wait(() => delay(50));
          return 1;
        });
        // Refused by its engine, at the adoption: the core asks everything
        // else before the first branch starts.
        final refused = UnadoptableJob<int>((ctx) async => 2);
        Job<List<int>>((ctx) => ctx.runAll([first, refused])).ignore();
        async.flushTimers();

        final reason = origin(first.outcome! as Cancelled);
        expect(reason, isA<SiblingCancelReason>());
        expect((reason as SiblingCancelReason).cause, isA<ArgumentError>());
      });
    });

    test('awaiting value of a job it does not own passes the reason as is', () {
      fakeAsync((async) {
        final other = startReport()..ignore();
        final job = Job<String>((ctx) async => other.value)..ignore();
        async.elapse(const Duration(milliseconds: 5));
        other.cancel().ignore();
        async.flushTimers();

        expect('${job.outcome}', 'Cancelled(manual)');
        expect((job.outcome! as Cancelled).reason, isA<ManualCancelReason>());
      });
    });

    test('the stack trace of the reason is not the one of the cancellation',
        () {
      fakeAsync((async) {
        final job = startReport()..ignore();
        async.elapse(const Duration(milliseconds: 5));
        final failedAt = StackTrace.current;
        job.cancel(reason: RequestCancelReason('offline', failedAt)).ignore();
        async.flushTimers();

        final cancelled = job.outcome! as Cancelled;
        expect(cancelled.stackTrace, isNotNull);
        expect(cancelled.stackTrace, isNot(same(failedAt)));
        expect(
          (cancelled.reason as RequestCancelReason).stackTrace,
          same(failedAt),
        );
      });
    });
  });

  group('Reacting before the outcome', () {
    test('done hears of the cancellation after the step and the cleanup', () {
      fakeAsync((async) {
        printed.clear();
        final report = Job<void>((ctx) async {
          ctx.onDispose(() => print('cleanup'));
          await ctx.run(
            Job.deferred<void>(cancellable: false, (ctx) async {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              print('step finished');
            }),
          );
        });
        () async {
          if (await report.done case Cancelled(:final reason)) {
            print('cancelling: $reason');
          }
        }();
        async.elapse(const Duration(milliseconds: 10));
        report.cancel().ignore();

        expect(printed, isEmpty, reason: 'accepted, and the screen is silent');
        async.flushTimers();
        expect(printed, quoted[6]);
      });
    });

    test('awaiting cancel is no quicker than awaiting done', () {
      fakeAsync((async) {
        printed.clear();
        final report = Job<void>((ctx) async {
          ctx.onDispose(() => print('cleanup'));
          await ctx.run(
            Job.deferred<void>(cancellable: false, (ctx) async {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              print('step finished');
            }),
          );
        });
        async.elapse(const Duration(milliseconds: 10));
        () async {
          await report.cancel();
          print('cancel returned at ${async.elapsed.inMilliseconds} ms');
        }();
        () async {
          await report.done;
          print('done at ${async.elapsed.inMilliseconds} ms');
        }();
        async.flushTimers();

        expect(printed, [
          'step finished',
          'cleanup',
          'cancel returned at 50 ms',
          'done at 50 ms',
        ]);
      });
    });

    test('the listener runs at acceptance, the outcome after the body', () {
      fakeAsync((async) {
        printed.clear();
        final report = Job<void>((ctx) async {
          ctx.onDispose(() => print('cleanup'));
          await ctx.run(
            Job.deferred<void>(cancellable: false, (ctx) async {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              print('step finished');
            }),
          );
        });
        () async {
// Runs when the cancellation is accepted; the job may still be finishing.
          final unregister = report.whenCancelled((cancelled) {
            print('cancelling: ${cancelled.reason}');
          });

          await report.done;
          // Safe after completion; call earlier to stop listening sooner.
          unregister();
        }();
        async.elapse(const Duration(milliseconds: 10));
        report.cancel().ignore();

        expect(printed, ['cancelling: manual'], reason: 'at acceptance');
        expect(report.isFinished, isFalse);
        async.flushTimers();
        expect(printed, quoted[7]);
      });
    });

    test('a listener registered inside the call runs ahead of the waiting', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = Job<void>((ctx) => ctx.wait(() => delay(50)))..ignore();
        job
          ..whenCancelled((_) {
            seen.add('first');
            job.whenCancelled((_) => seen.add('third, made inside the first'));
          })
          ..whenCancelled((_) => seen.add('second'));
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();

        expect(seen, ['first', 'third, made inside the first', 'second']);
      });
    });

    for (final path in ['a section held it', 'the body gave itself up']) {
      test('an async listener fails in the zone of the body when $path',
          () async {
        final zones = <String>[];
        late Job<void> job;
        // A job that starts itself runs its body in the zone it was
        // created in.
        runZonedGuarded(
          () => job = Job<void>((ctx) async {
            if (path == 'a section held it') {
              await ctx.uncancellable(() => delay(20));
              await ctx.wait(() => delay(50));
            } else {
              await delay(5);
              throw const Cancelled('why');
            }
          })
            ..ignore(),
          (error, stackTrace) => zones.add('creation: $error'),
        );
        job.whenCancelled((cancelled) async {
          throw StateError('save failed');
        });
        await delay(2);
        if (path == 'a section held it') {
          runZonedGuarded(
            () => job.cancel().ignore(),
            (error, stackTrace) => zones.add('cancel: $error'),
          );
        }
        await job.done;
        await delay(5);

        expect(zones, ['creation: Bad state: save failed']);
      });
    }

    test('an async listener fails there before its first await too', () async {
      final zones = <String>[];
      late Job<void> job;
      runZonedGuarded(
        () => job = Job<void>(
          (ctx) => ctx.wait(() => delay(50)),
          observer: HearingObserver(),
        )..ignore(),
        (error, stackTrace) => zones.add('creation: $error'),
      );
      job.whenCancelled((cancelled) async {
        throw StateError('save failed');
      });
      await delay(5);
      printed.clear();
      runZonedGuarded(
        () => job.cancel().ignore(),
        (error, stackTrace) => zones.add('cancel: $error'),
      );
      await job.done;
      await delay(5);

      expect(zones, ['cancel: Bad state: save failed']);
      expect(printed, isEmpty, reason: 'onError hears nothing');
    });

    test('an async listener fails in the zone of the code that cancelled',
        () async {
      final zones = <String>[];
      late Job<void> job;
      runZonedGuarded(
        () => job = Job<void>((ctx) => ctx.wait(() => delay(50)))..ignore(),
        (error, stackTrace) => zones.add('creation: $error'),
      );
      runZonedGuarded(
        () => job.whenCancelled((cancelled) async {
          await delay(1);
          throw StateError('save failed');
        }),
        (error, stackTrace) => zones.add('registration: $error'),
      );
      await delay(5);
      runZonedGuarded(
        () => job.cancel().ignore(),
        (error, stackTrace) => zones.add('cancel: $error'),
      );
      await job.done;
      await delay(5);

      expect(zones, ['cancel: Bad state: save failed']);
    });
  });

  test('the page quotes the lines these tests print', () {
    final page = File('doc/outcomes.md').readAsStringSync();
    final blocks = RegExp(r'```text\n(.*?)\n```', dotAll: true)
        .allMatches(page)
        .map((match) => match.group(1)!.split('\n'))
        .toList();

    expect(blocks, quoted);
  });

  test('every piece of code on the page is a run of lines of this file', () {
    expect(
      codeMissingFrom('doc/outcomes.md', 'test/outcomes_rakes_test.dart'),
      isEmpty,
    );
  });
}
