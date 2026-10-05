// `doc/outcomes.md` runs here. Its code stands verbatim in the libraries
// under `support/`: `outcomes_page.dart` holds the code a section opens
// with and the version that works, `outcomes_first_attempts.dart` the
// version the API leads to, which each section opens with, and
// `outcomes_stubs.dart` what that code takes for granted. Every piece of
// code on the page is a run of lines of the file its heading belongs to,
// and every quote under it is what that code prints: a piece or a quote
// that drifts turns this file red, not only a broken core. The other tests
// pin what the page says beyond its code.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/outcomes_first_attempts.dart' as first;
import 'support/outcomes_page.dart' as page;
import 'support/outcomes_stubs.dart';
import 'support/page_code.dart';
import 'support/probe_job.dart';

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

/// What the code of a test prints, and what reaches its zone uncaught.
final journal = <String>[];

/// Runs [body] on fake time and returns what it left in the [journal].
///
/// The assertions stay outside: an `expect` inside the guarded zone would
/// land in the very handler that collects.
List<String> printed(void Function(FakeAsync async) body) {
  journal.clear();
  runZonedGuarded(
    () => fakeAsync(body),
    (error, stackTrace) => journal.add('zone: $error'),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => journal.add(line),
    ),
  );
  return [...journal];
}

/// Hears the errors of its job and answers for none of them.
final class Hearing extends JobObserver {
  final List<String> heard;

  Hearing(this.heard);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      heard.add('onError: $error');
}

/// Hears the errors of its job and answers for the ones nobody else does.
final class Answering extends JobObserver with JobAnswerer {
  final List<String> heard;

  Answering(this.heard);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      heard.add('onError: $error');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      heard.add('onUnanswered: $error');
}

/// Calls [hook] when its job finishes.
final class Finishing extends JobObserver {
  final void Function(Job<Object?> job) hook;

  Finishing(this.hook);

  @override
  void onFinish(Job<Object?> job) => hook(job);
}

/// A body that gives itself up 5 ms in.
Future<void> givingUp(JobContext ctx) async {
  await delay(5);
  throw const Cancelled('why');
}

void main() {
  group('Reading the result', () {
    test('value in a try prints a cancellation as a failure', () {
      final lines = printed((async) {
        final report = userReport();
        unawaited(first.printReport(report));
        async.elapse(const Duration(milliseconds: 10));
        report.cancel().ignore();
        async.flushTimers();
      });

      expect(lines, quoted[0]);
    });

    test('value throws the Cancelled itself, and on Exception takes it', () {
      Object? caught;
      late Job<Report> report;
      printed((async) {
        report = userReport();
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
      });

      expect(caught, same(report.outcome));
    });

    test('a switch over done gives the cancellation its own line', () {
      final lines = printed((async) {
        final report = userReport();
        unawaited(page.printReport(report));
        async.elapse(const Duration(milliseconds: 10));
        report.cancel().ignore();
        async.flushTimers();
      });

      expect(lines, quoted[1]);
    });
  });

  group('A failure nobody waits for', () {
    test('reading outcome leaves the failure to the zone', () {
      final lines = printed((async) {
        final sync = first.startSync();
        first.drawStatus(sync);
        async.flushTimers();
        first.drawStatus(sync);
      });

      expect(lines, ['status: syncing', ...quoted[2]]);
    });

    test('ignore keeps the zone quiet while the status line reads it', () {
      final lines = printed((async) {
        final sync = page.startSync();
        async.flushTimers();
        first.drawStatus(sync);
      });

      expect(lines, quoted[3]);
    });

    test('onError of the observer hears the failure and does not observe it',
        () {
      final lines = printed((async) {
        Job<void>(observer: Hearing(journal), upload);
        async.flushTimers();
      });

      expect(lines, [
        'onError: Bad state: disk full',
        'zone: Bad state: disk full',
      ]);
    });

    test('onFinish reading the outcome does not observe it', () {
      final lines = printed((async) {
        Job<void>(
          observer: Finishing((job) => print('onFinish ${job.outcome}')),
          upload,
        );
        async.flushTimers();
      });

      expect(lines, [
        'onFinish Failed(Bad state: disk full)',
        'zone: Bad state: disk full',
      ]);
    });

    test('awaiting cancel and registering with whenCancelled do not either',
        () {
      var cancelReturned = false;
      final lines = printed((async) {
        final sync = Job<void>(cancellable: false, upload)
          ..whenCancelled((_) {});
        async.elapse(const Duration(milliseconds: 5));
        // Awaited for real: the future of `cancel` completes, and the
        // failure still goes to the zone.
        sync.cancel().then((_) => cancelReturned = true).ignore();
        async.flushTimers();
      });

      expect(cancelReturned, isTrue);
      expect(lines, ['zone: Bad state: disk full']);
    });

    test('the failure waits one microtask after the finish for an observer',
        () {
      List<String> observedAfter(int microtasks) => printed((async) {
            late Job<void> sync;
            void observe(int left) {
              if (left == 0) {
                sync.done.ignore();
              } else {
                scheduleMicrotask(() => observe(left - 1));
              }
            }

            sync = Job<void>(
              observer: Finishing((_) => observe(microtasks)),
              upload,
            );
            async.flushTimers();
          });

      expect(observedAfter(1), isEmpty, reason: 'in time');
      expect(observedAfter(2), ['zone: Bad state: disk full'], reason: 'late');
    });

    for (final (name, touch) in <(String, void Function(Job<void>))>[
      ('done', (sync) => sync.done.ignore()),
      ('value', (sync) => sync.value.ignore()),
    ]) {
      test('accessing $name observes the failure', () {
        final lines = printed((async) {
          touch(Job<void>(upload));
          async.flushTimers();
        });

        expect(lines, isEmpty);
      });
    }

    test('value left unhandled throws the error, as any future does', () {
      final lines = printed((async) {
        // The waiting code takes the future and handles nothing.
        unawaited(Job<void>(upload).value);
        async.flushTimers();
      });

      expect(lines, ['zone: Bad state: disk full']);
    });

    test('forwarding through then observes it; the continuation answers', () {
      final unobserved = printed((async) {
        Job<void>(upload).then<int>((ctx, _) => 1);
        async.flushTimers();
      });
      final ignored = printed((async) {
        Job<void>(upload).then<int>((ctx, _) => 1).ignore();
        async.flushTimers();
      });

      expect(
        unobserved,
        ['zone: Bad state: disk full'],
        reason: "once, the continuation's",
      );
      expect(ignored, isEmpty);
    });

    group('waiting does not observe a failure a cancellation covers', () {
      // The upload fails 10 ms in while a child of the job still runs, and
      // the cancellation 20 ms in arrives before the job has ended.
      Future<void> uploadWithChild(JobContext ctx) async {
        ctx
            .run(Job.deferred<void>((ctx) => ctx.abandonable(() => delay(50))))
            .ignore();
        await upload(ctx);
      }

      List<String> covered({
        required bool ignored,
        JobObserver? Function()? observer,
      }) =>
          printed((async) {
            final sync = Job<void>(observer: observer?.call(), uploadWithChild);
            if (ignored) {
              sync.ignore();
            } else {
              sync.done.then((outcome) => print('done: $outcome')).ignore();
            }
            async.elapse(const Duration(milliseconds: 20));
            sync.cancel().ignore();
            async.flushTimers();
            first.drawStatus(sync);
          });

      test('the waiting code gets the cancellation, the zone the error', () {
        expect(covered(ignored: false), [
          'zone: Bad state: disk full',
          'done: Cancelled(manual)',
          'status: sync cancelled',
        ]);
      });

      test('ignore keeps it out of the zone', () {
        expect(covered(ignored: true), ['status: sync cancelled']);
      });

      test('and then only the onError of an observer hears it', () {
        for (final observer in [
          () => Hearing(journal),
          () => Answering(journal),
        ]) {
          expect(covered(ignored: true, observer: observer), [
            'onError: Bad state: disk full',
            'status: sync cancelled',
          ]);
        }
      });
    });
  });

  group('Why a job was cancelled', () {
    /// The page's `report` and `fetch`, with [show] for the code that
    /// started `report`; 5 ms in, the request fails and cancels `fetch` the
    /// way the page does it.
    ({Job<Data> fetch, Job<Report> report}) requestFails(
      FakeAsync async,
      Future<void> Function(Job<Report> report) show,
    ) {
      final jobs = page.startReport();
      unawaited(show(jobs.report));
      async.elapse(const Duration(milliseconds: 5));
      unawaited(page.refresh(jobs.fetch));
      async.flushTimers();
      return jobs;
    }

    test('a case for the reason of report misses the request', () {
      late ({Job<Data> fetch, Job<Report> report}) jobs;
      final lines = printed((async) {
        jobs = requestFails(async, first.tellTheRequest);
      });

      expect(lines, quoted[4]);
      final reason = (jobs.report.outcome! as Cancelled).reason;
      expect(reason, isA<HandlerCancelReason>());
      expect((reason as HandlerCancelReason).cause, same(jobs.fetch.outcome));
    });

    test('origin follows the cause down to the request', () {
      final lines = printed((async) {
        requestFails(async, page.tellTheRequest);
      });

      expect(lines, quoted[5]);
    });

    test('the outcome of fetch holds the very reason passed to cancel', () {
      fakeAsync((async) {
        final (:fetch, :report) = page.startReport();
        report.ignore();
        async.elapse(const Duration(milliseconds: 5));
        final reason = page.RequestCancelReason('offline', StackTrace.current);
        fetch.cancel(reason: reason).ignore();
        async.flushTimers();

        expect((fetch.outcome! as Cancelled).reason, same(reason));
      });
    });

    test('origin follows a cascade from the parent', () {
      fakeAsync((async) {
        late Job<void> child;
        final parent = Job<void>((ctx) async {
          child = Job.deferred<void>((ctx) => ctx.abandonable(() => delay(50)));
          ctx.run(child).ignore();
          await ctx.abandonable(() => delay(50));
        })
          ..ignore();
        async.elapse(const Duration(milliseconds: 5));
        final reason = page.RequestCancelReason('offline', StackTrace.current);
        parent.cancel(reason: reason).ignore();
        async.flushTimers();

        final cancelled = child.outcome! as Cancelled;
        expect(cancelled.reason, isA<ParentCancelReason>());
        expect(page.origin(cancelled), same(reason));
      });
    });

    test('origin follows a chain of then', () {
      fakeAsync((async) {
        final source = userReport()..ignore();
        final tail = source.then<int>((ctx, report) => 1)..ignore();
        async.elapse(const Duration(milliseconds: 5));
        final reason = page.RequestCancelReason('offline', StackTrace.current);
        tail.cancel(reason: reason).ignore();
        async.flushTimers();

        final cancelled = source.outcome! as Cancelled;
        expect(cancelled.reason, isA<ChainCancelReason>());
        expect(page.origin(cancelled), same(reason));
      });
    });

    test('origin stops where a body threw Cancelled itself', () {
      fakeAsync((async) {
        final job = Job<void>((ctx) async => throw const Cancelled('why'))
          ..ignore();
        async.flushTimers();

        final reason = page.origin(job.outcome! as Cancelled);
        expect(reason, isA<HandlerCancelReason>());
        expect((reason as HandlerCancelReason).cause, isNull);
      });
    });

    test('origin stops at the reason a group gives the other branch', () {
      fakeAsync((async) {
        final error = StateError('boom');
        final failing = Job.deferred<int>((ctx) async {
          await ctx.abandonable(() => delay(10));
          throw error;
        });
        final neighbour = Job.deferred<int>((ctx) async {
          await ctx.abandonable(() => delay(100));
          return 2;
        });
        Job<List<int>>((ctx) => ctx.runAll([failing, neighbour])).ignore();
        async.flushTimers();

        final reason = page.origin(neighbour.outcome! as Cancelled);
        expect(reason, isA<SiblingCancelReason>());
        expect((reason as SiblingCancelReason).cause, same(error));
      });
    });

    test('a group that refused a job gives the others its ArgumentError', () {
      fakeAsync((async) {
        final first = Job.deferred<int>((ctx) async {
          await ctx.abandonable(() => delay(50));
          return 1;
        });
        // Refused by its engine, at the adoption: the core asks everything
        // else before the first branch starts.
        final refused = UnadoptableJob<int>((ctx) async => 2);
        Job<List<int>>((ctx) => ctx.runAll([first, refused])).ignore();
        async.flushTimers();

        final reason = page.origin(first.outcome! as Cancelled);
        expect(reason, isA<SiblingCancelReason>());
        expect((reason as SiblingCancelReason).cause, isA<ArgumentError>());
      });
    });

    test('awaiting value of a job it does not own passes the reason as is', () {
      final quote = RegExp(r'outcome\s+reads\s+`([^`]+)`\s+for\s+a\s+job')
          .firstMatch(File('doc/outcomes.md').readAsStringSync())!
          .group(1);
      fakeAsync((async) {
        final other = userReport()..ignore();
        final job = Job<Report>((ctx) async => other.value)..ignore();
        async.elapse(const Duration(milliseconds: 5));
        other.cancel().ignore();
        async.flushTimers();

        expect('${job.outcome}', quote);
        expect((job.outcome! as Cancelled).reason, isA<ManualCancelReason>());
      });
    });

    test('started tells a body that ran from one cancelled before its start',
        () {
      fakeAsync((async) {
        final waiting = Job.deferred<void>((ctx) async {});
        final running = Job<void>((ctx) => ctx.abandonable(() => delay(50)))
          ..ignore();
        async.elapse(const Duration(milliseconds: 5));
        waiting.cancel().ignore();
        running.cancel().ignore();
        async.flushTimers();

        expect((waiting.outcome! as Cancelled).started, isFalse);
        expect((running.outcome! as Cancelled).started, isTrue);
      });
    });

    test('a body that throws Cancelled.by keeps the reason it names', () {
      fakeAsync((async) {
        final reason = page.RequestCancelReason('offline', StackTrace.current);
        final job = Job<void>(
          (ctx) async => throw Cancelled.by(reason: reason, started: true),
        )..ignore();
        async.flushTimers();

        expect((job.outcome! as Cancelled).reason, same(reason));
      });
    });

    test('the stack trace of the reason is not the one of the cancellation',
        () {
      fakeAsync((async) {
        final job = userReport()..ignore();
        async.elapse(const Duration(milliseconds: 5));
        final failedAt = StackTrace.current;
        job
            .cancel(reason: page.RequestCancelReason('offline', failedAt))
            .ignore();
        async.flushTimers();

        final cancelled = job.outcome! as Cancelled;
        expect(cancelled.stackTrace, isNotNull);
        expect(cancelled.stackTrace, isNot(same(failedAt)));
        expect(
          (cancelled.reason as page.RequestCancelReason).stackTrace,
          same(failedAt),
        );
      });
    });
  });

  group('Reacting before the outcome', () {
    test('done hears of the cancellation after the step and the cleanup', () {
      late List<String> atCancel;
      final lines = printed((async) {
        final report = page.startSteppedReport();
        unawaited(first.showCancelling(report));
        async.elapse(const Duration(milliseconds: 10));
        report.cancel().ignore();
        atCancel = [...journal];
        async.flushTimers();
      });

      expect(atCancel, isEmpty, reason: 'accepted, and the screen is silent');
      expect(lines, quoted[6]);
    });

    test('awaiting cancel is no quicker than awaiting done', () {
      final lines = printed((async) {
        final report = page.startSteppedReport();
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
      });

      expect(lines, [
        'step finished',
        'cleanup',
        'cancel returned at 50 ms',
        'done at 50 ms',
      ]);
    });

    test('isCancelled turns true the moment the cancellation is accepted', () {
      late bool before;
      late bool after;
      late bool finished;
      printed((async) {
        final report = page.startSteppedReport()..ignore();
        async.elapse(const Duration(milliseconds: 10));
        before = report.isCancelled;
        report.cancel().ignore();
        after = report.isCancelled;
        finished = report.isFinished;
        async.flushTimers();
      });

      expect(before, isFalse);
      expect(after, isTrue);
      expect(finished, isFalse, reason: 'the step still runs');
    });

    test('the listener runs at acceptance, the outcome after the body', () {
      late List<String> atCancel;
      late bool finished;
      final lines = printed((async) {
        final report = page.startSteppedReport();
        unawaited(page.showCancelling(report));
        async.elapse(const Duration(milliseconds: 10));
        report.cancel().ignore();
        atCancel = [...journal];
        finished = report.isFinished;
        async.flushTimers();
      });

      expect(atCancel, ['cancelling: manual'], reason: 'at acceptance');
      expect(finished, isFalse);
      expect(lines, quoted[7]);
    });

    test('an external cancellation: after the cascade and onCancel, once', () {
      fakeAsync((async) {
        final order = <String>[];
        final job = Job<void>((ctx) async {
          ctx
            ..onCancel(() => order.add('own onCancel'))
            ..run(
              Job.deferred<void>((child) async {
                child.onCancel(() => order.add('child onCancel'));
                await child.abandonable(() => delay(100));
              }),
            ).ignore();
          // Throws the Cancelled the job accepted; the listener has heard
          // it already and does not hear it again.
          await ctx.abandonable(() => delay(100));
        })
          ..ignore()
          ..whenCancelled((cancelled) => order.add('listener'));
        async.elapse(const Duration(milliseconds: 10));
        job.cancel().ignore();
        order.add('cancel() returned, finished: ${job.isFinished}');
        async.flushTimers();

        expect(order, [
          'child onCancel',
          'own onCancel',
          'listener',
          'cancel() returned, finished: false',
        ]);
      });
    });

    test('a job cancelled before its start: when it is cancelled', () {
      final order = <String>[];
      final job = Job.deferred<void>((ctx) async {})
        ..whenCancelled(
          (cancelled) => order.add('listener, started: ${cancelled.started}'),
        );
      job.cancel().ignore();
      order.add('cancel() returned');

      expect(order, ['listener, started: false', 'cancel() returned']);
    });

    test('a body that throws Cancelled itself: as the body ends', () {
      fakeAsync((async) {
        final order = <String>[];
        Job<void>((ctx) async {
          ctx
            ..onCancel(() => order.add('own onCancel'))
            ..run(
              Job.deferred<void>((child) async {
                child
                  ..onCancel(() => order.add('child onCancel'))
                  ..onDispose(() => order.add('child ended'));
                await child.join(() => delay(30));
              }),
            ).ignore();
          await delay(5);
          throw const Cancelled('why');
        })
          ..whenCancelled((cancelled) => order.add('listener'))
          ..done.then((outcome) => order.add('$outcome')).ignore();
        async.flushTimers();

        expect(order, [
          'child onCancel',
          'own onCancel',
          'listener',
          'child ended',
          'Cancelled(handler: why)',
        ]);
      });
    });

    test("a body that lets a child's cancellation through: as the body ends",
        () {
      fakeAsync((async) {
        final order = <String>[];
        final fetch = Job.deferred<int>((ctx) async {
          await ctx.abandonable(() => delay(50));
          return 1;
        });
        Job<int>((ctx) async {
          ctx
            ..onCancel(() => order.add('own onCancel'))
            ..run(
              Job.deferred<void>((other) async {
                other
                  ..onCancel(() => order.add('other child onCancel'))
                  ..onDispose(() => order.add('other child ended'));
                await other.join(() => delay(30));
              }),
            ).ignore();
          return ctx.run(fetch);
        })
          ..whenCancelled((cancelled) => order.add('listener'))
          ..done.then((outcome) => order.add('$outcome')).ignore();
        async.elapse(const Duration(milliseconds: 5));
        fetch.cancel().ignore();
        order.add('fetch cancelled');
        async.flushTimers();

        expect(order, [
          'fetch cancelled',
          'other child onCancel',
          'own onCancel',
          'listener',
          'other child ended',
          'Cancelled(handler: child null: Cancelled(manual))',
        ]);
      });
    });

    test(
        'a body that lets through the cancellation of a job it does not own: '
        'as the body ends', () {
      fakeAsync((async) {
        final order = <String>[];
        final shared = Job<int>((ctx) async {
          await ctx.abandonable(() => delay(50));
          return 1;
        })
          ..ignore();
        Job<int>((ctx) async {
          ctx
            ..onCancel(() => order.add('own onCancel'))
            ..run(
              Job.deferred<void>((child) async {
                child
                  ..onCancel(() => order.add('child onCancel'))
                  ..onDispose(() => order.add('child ended'));
                await child.join(() => delay(30));
              }),
            ).ignore();
          return shared.value;
        })
          ..whenCancelled((cancelled) => order.add('listener'))
          ..done.then((outcome) => order.add('$outcome')).ignore();
        async.elapse(const Duration(milliseconds: 5));
        shared.cancel().ignore();
        order.add('shared cancelled');
        async.flushTimers();

        expect(order, [
          'shared cancelled',
          'child onCancel',
          'own onCancel',
          'listener',
          'child ended',
          'Cancelled(manual)',
        ]);
      });
    });

    test('a listener registered inside the call runs ahead of the waiting', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = Job<void>((ctx) => ctx.abandonable(() => delay(50)))
          ..ignore();
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

    test('until the pass begins, a registration joins it after the others', () {
      fakeAsync((async) {
        final heard = <String>[];
        late Job<void> job;
        job = Job<void>((ctx) async {
          ctx
            ..onCancel(() => job.whenCancelled((_) => heard.add('onCancel')))
            ..run(
              Job.deferred<void>((child) async {
                child.onCancel(
                  () => job.whenCancelled((_) => heard.add('cascade')),
                );
                await child.abandonable(() => delay(100));
              }),
            ).ignore();
          await ctx.abandonable(() => delay(100));
        })
          ..ignore()
          ..whenCancelled((_) => heard.add('before'));
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();

        expect(heard, ['before', 'cascade', 'onCancel']);
      });
    });

    test('only an accepted cancellation starts the pass', () {
      fakeAsync((async) {
        final heard = <String>[];
        final refusing = Job<void>(
          cancellable: false,
          (ctx) => ctx.abandonable(() => delay(20)),
        )..whenCancelled((_) => heard.add('refused'));
        final held = Job<void>((ctx) async {
          await ctx.uncancellable(() => delay(20));
          await ctx.abandonable(() => delay(50));
        })
          ..ignore()
          ..whenCancelled(
            (_) => heard.add('held, at ${async.elapsed.inMilliseconds} ms'),
          );
        final done = Job<void>((ctx) => ctx.abandonable(() => delay(10)))
          ..whenCancelled((_) => heard.add('done'));
        async.elapse(const Duration(milliseconds: 5));
        refusing.cancel().ignore();
        held.cancel().ignore();
        heard.add('cancelled at 5 ms');
        async.elapse(const Duration(milliseconds: 30));
        done.whenCancelled((_) => heard.add('registered on a finished job'));
        async.flushTimers();

        expect(heard, ['cancelled at 5 ms', 'held, at 20 ms']);
        expect(refusing.outcome, isA<Done<void>>());
        expect(done.outcome, isA<Done<void>>());
      });
    });

    test('the pass runs from a snapshot; unregistering twice is safe', () {
      final heard = <String>[];
      late void Function() unregisterSecond;
      final job = Job.deferred<void>((ctx) async {})
        ..whenCancelled((_) {
          heard.add('first');
          unregisterSecond();
        });
      unregisterSecond = job.whenCancelled((_) => heard.add('second'));
      final unregisterThird = job.whenCancelled((_) => heard.add('third'));
      unregisterThird();
      unregisterThird();
      job.cancel().ignore();

      expect(heard, ['first', 'second']);
    });

    /// What the observer of a job, and the zones around it, hear when the
    /// job's first listener is [listener]: the job is created in one zone
    /// and cancelled from another.
    List<String> listenerFails(
      JobObserver? Function(List<String> heard) observer,
      void Function(Cancelled cancelled) listener,
    ) {
      final heard = <String>[];
      fakeAsync((async) {
        late Job<void> job;
        runZonedGuarded(
          () => job = Job<void>(
            observer: observer(heard),
            (ctx) => ctx.abandonable(() => delay(50)),
          )..ignore(),
          (error, stackTrace) => heard.add('creation zone: $error'),
        );
        job
          ..whenCancelled(listener)
          ..whenCancelled((_) => heard.add('the next listener ran'));
        async.elapse(const Duration(milliseconds: 5));
        runZonedGuarded(
          () => job.cancel().ignore(),
          (error, stackTrace) => heard.add('cancel zone: $error'),
        );
        async.flushTimers();
        heard.add('${job.outcome}');
      });
      return heard;
    }

    test(
        'a synchronous listener error goes to onError, then to the creation '
        'zone', () {
      expect(listenerFails(Hearing.new, (_) => throw StateError('sync')), [
        'onError: Bad state: sync',
        'creation zone: Bad state: sync',
        'the next listener ran',
        'Cancelled(manual)',
      ]);
    });

    test('an observer that answers for it keeps it out of the zone', () {
      expect(listenerFails(Answering.new, (_) => throw StateError('sync')), [
        'onError: Bad state: sync',
        'onUnanswered: Bad state: sync',
        'the next listener ran',
        'Cancelled(manual)',
      ]);
    });

    test('without an observer, it goes straight to the creation zone', () {
      expect(listenerFails((_) => null, (_) => throw StateError('sync')), [
        'creation zone: Bad state: sync',
        'the next listener ran',
        'Cancelled(manual)',
      ]);
    });

    test('a Cancelled a listener throws never reaches the zone', () {
      expect(
        listenerFails((_) => null, (_) => throw const Cancelled('listener')),
        ['the next listener ran', 'Cancelled(manual)'],
      );
    });

    for (final path in ['a section held it', 'the body gave itself up']) {
      test('an async listener fails in the zone of the body when $path',
          () async {
        final zones = <String>[];
        late Job<void> job;
        // A job made with `Job(...)` runs its body in the zone it was
        // created in.
        runZonedGuarded(
          () => job = Job<void>((ctx) async {
            if (path == 'a section held it') {
              await ctx.uncancellable(() => delay(20));
              await ctx.abandonable(() => delay(50));
            } else {
              await givingUp(ctx);
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

    test('a deferred job runs its body in the zone it was started from',
        () async {
      final zones = <String>[];
      late DeferredJob<void> job;
      runZonedGuarded(
        () => job = Job.deferred<void>(givingUp)
          ..ignore()
          ..whenCancelled((cancelled) async {
            throw StateError('save failed');
          }),
        (error, stackTrace) => zones.add('creation: $error'),
      );
      runZonedGuarded(
        () => job.start(),
        (error, stackTrace) => zones.add('start: $error'),
      );
      await job.done;
      await delay(5);

      expect(zones, ['start: Bad state: save failed']);
    });

    for (final how in ['made', 'started']) {
      test(
          'a job $how inside unattended work runs its body in the zone that '
          'work was started from', () async {
        final heard = <String>[];
        // Made in the zone of the test, which is neither of the two below.
        final deferred = Job.deferred<void>(givingUp);
        late Job<void> inner;
        final handedOver = Completer<void>();
        runZonedGuarded(
          () => Job<void>(observer: Hearing(heard), (ctx) async {
            ctx.unattended(() {
              runZonedGuarded(
                () {
                  if (how == 'made') {
                    inner = Job<void>(givingUp);
                  } else {
                    inner = deferred..start();
                  }
                  inner
                    ..ignore()
                    ..whenCancelled((cancelled) async {
                      throw StateError('save failed');
                    });
                },
                (error, stackTrace) => heard.add('inside the work: $error'),
              );
              handedOver.complete();
            });
            await ctx.abandonable(() => delay(30));
          }).ignore(),
          (error, stackTrace) => heard.add('where it started: $error'),
        );
        await handedOver.future;
        await inner.done;
        await delay(40);

        expect(heard, ['where it started: Bad state: save failed']);
      });
    }

    test(
        'a deferred job made inside unattended work and started outside it '
        'runs its body in the zone it was started from', () async {
      final heard = <String>[];
      late DeferredJob<void> inner;
      final handedOver = Completer<void>();
      runZonedGuarded(
        () => Job<void>(observer: Hearing(heard), (ctx) async {
          ctx.unattended(() {
            runZonedGuarded(
              () => inner = Job.deferred<void>(givingUp)
                ..ignore()
                ..whenCancelled((cancelled) async {
                  throw StateError('save failed');
                }),
              (error, stackTrace) => heard.add('inside the work: $error'),
            );
            handedOver.complete();
          });
          await ctx.abandonable(() => delay(30));
        }).ignore(),
        (error, stackTrace) => heard.add('where the work started: $error'),
      );
      await handedOver.future;
      runZonedGuarded(
        () => inner.start(),
        (error, stackTrace) => heard.add('start: $error'),
      );
      await inner.done;
      await delay(40);

      expect(heard, ['start: Bad state: save failed']);
    });

    test('an async listener fails there before its first await too', () async {
      final zones = <String>[];
      final heard = <String>[];
      late Job<void> job;
      runZonedGuarded(
        () => job = Job<void>(
          (ctx) => ctx.abandonable(() => delay(50)),
          observer: Hearing(heard),
        )..ignore(),
        (error, stackTrace) => zones.add('creation: $error'),
      );
      job.whenCancelled((cancelled) async {
        throw StateError('save failed');
      });
      await delay(5);
      runZonedGuarded(
        () => job.cancel().ignore(),
        (error, stackTrace) => zones.add('cancel: $error'),
      );
      await job.done;
      await delay(5);

      expect(zones, ['cancel: Bad state: save failed']);
      expect(heard, isEmpty, reason: 'onError hears nothing');
    });

    test('an async listener fails in the zone of the code that cancelled',
        () async {
      final zones = <String>[];
      late Job<void> job;
      runZonedGuarded(
        () => job = Job<void>((ctx) => ctx.abandonable(() => delay(50)))
          ..ignore(),
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
    final text = File('doc/outcomes.md').readAsStringSync();
    final blocks = RegExp(r'```text\n(.*?)\n```', dotAll: true)
        .allMatches(text)
        .map((match) => match.group(1)!.split('\n'))
        .toList();

    expect(blocks, quoted);
  });

  test('the page has no fence the checks do not read', () {
    expect(strayFences('doc/outcomes.md'), isEmpty);
  });

  // Each version under its own file: a line of an answer turned into the
  // line of a first attempt would still be found among all of them.
  final holders = {
    '### The first attempt': 'test/support/outcomes_first_attempts.dart',
    '### A switch over `done`': 'test/support/outcomes_page.dart',
    '### Telling the core it is handled': 'test/support/outcomes_page.dart',
    '## Why a job was cancelled': 'test/support/outcomes_page.dart',
    '### Following the cause': 'test/support/outcomes_page.dart',
    '## Reacting before the outcome': 'test/support/outcomes_page.dart',
    '### Listening for the cancellation': 'test/support/outcomes_page.dart',
  };
  for (final MapEntry(key: heading, value: holder) in holders.entries) {
    test('the code under "$heading" is a run of lines of $holder', () {
      expect(
        codeMissingFrom('doc/outcomes.md', holder, under: heading),
        isEmpty,
      );
    });
  }

  test('every piece of code on the page is a run of lines of these files', () {
    expect(
      codeMissingFrom(
        'doc/outcomes.md',
        'test/support/outcomes_page.dart',
        alsoIn: ['test/support/outcomes_first_attempts.dart'],
      ),
      isEmpty,
    );
  });
}
