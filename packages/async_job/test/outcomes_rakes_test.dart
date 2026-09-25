@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

/// The first attempts of `doc/outcomes.md`, and what each one costs.
///
/// Three sections of the page open with the version the vocabulary of the
/// API leads to and show what that version prints. The page has no bench,
/// so the code is repeated here as it stands there, and the last test holds
/// the lines the page quotes to the lines these tests print: a quote that
/// drifts from its code turns this file red, not only a broken engine.

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
    'status: sync failed: Bad state: disk full',
    'zone: Bad state: disk full',
  ],
  ['status: sync failed: Bad state: disk full'],
  ['cancelled: handler'],
  ['request failed: Bad state: token expired'],
];

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
        final printed = <String>[];
        final report = startReport();
        () async {
          try {
            printed.add('report: ${await report.value}');
          } on Object catch (error) {
            printed.add('failed: $error');
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
        final printed = <String>[];
        final report = startReport();
        () async {
          final message = switch (await report.done) {
            Done(:final value) => 'report: $value',
            Failed(:final error) => 'failed: $error',
            Cancelled(:final reason) => 'cancelled: $reason',
          };
          printed.add(message);
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
      final printed = <String>[];
      final caught = zoneOf((async) {
        final sync = Job<void>(upload);
        printed.add('status: ${status(sync)}');
        async.flushTimers();
        printed.add('status: ${status(sync)}');
      });

      expect(printed.first, 'status: syncing');
      expect([printed.last, ...caught], quoted[2]);
    });

    test('ignore keeps the zone quiet while the status line reads it', () {
      final printed = <String>[];
      final caught = zoneOf((async) {
        final sync = Job<void>(upload)..ignore();
        async.flushTimers();
        printed.add('status: ${status(sync)}');
      });

      expect([...printed, ...caught], quoted[3]);
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
      final caught = zoneOf((async) {
        final sync = Job<void>(cancellable: false, upload)
          ..whenCancelled((_) {});
        async.elapse(const Duration(milliseconds: 5));
        sync.cancel().ignore();
        async.flushTimers();
      });

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
    ({Job<String> report, Job<String> fetch, RequestCancelReason? heard})
        requestFails(FakeAsync async) {
      late Job<String> fetch;
      final report = Job<String>((ctx) async {
        fetch = Job.deferred<String>((ctx) async {
          await ctx.wait(() => delay(50));
          return 'data';
        });
        return 'report of ${await ctx.run(fetch)}';
      })
        ..ignore();
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
        final (:report, :fetch, heard: _) = requestFails(async);
        final message = switch (report.outcome!) {
          Done(:final value) => 'report: $value',
          Failed(:final error) => 'failed: $error',
          Cancelled(reason: RequestCancelReason(:final error)) =>
            'request failed: $error',
          Cancelled(:final reason) => 'cancelled: $reason',
        };

        expect([message], quoted[4]);
        final reason = (report.outcome! as Cancelled).reason;
        expect(reason, isA<HandlerCancelReason>());
        expect((reason as HandlerCancelReason).cause, same(fetch.outcome));
      });
    });

    test('origin follows the cause down to the request', () {
      fakeAsync((async) {
        final (:report, fetch: _, heard: _) = requestFails(async);
        final message = switch (report.outcome!) {
          Done(:final value) => 'report: $value',
          Failed(:final error) => 'failed: $error',
          final Cancelled cancelled => switch (origin(cancelled)) {
              RequestCancelReason(:final error) => 'request failed: $error',
              final reason => 'cancelled: $reason',
            },
        };

        expect([message], quoted[5]);
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
    test('the listener runs at acceptance, the outcome after the body', () {
      fakeAsync((async) {
        final printed = <String>[];
        String at() => '${async.elapsed.inMilliseconds} ms';
        final report = Job<void>((ctx) async {
          await ctx.run(
            Job.deferred<void>(cancellable: false, (ctx) => delay(50)),
          );
        });
        final unregister = report.whenCancelled((cancelled) {
          printed.add('${at()} cancelling: ${cancelled.reason}');
        });
        () async {
          await report.done;
          printed.add('${at()} done');
          unregister();
        }();
        async.elapse(const Duration(milliseconds: 10));
        report.cancel().ignore();
        async.flushTimers();

        expect(printed, ['10 ms cancelling: manual', '50 ms done']);
      });
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
}
