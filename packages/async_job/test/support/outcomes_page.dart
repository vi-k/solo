// The code of `doc/outcomes.md` as the page answers it, verbatim: the code a
// section opens with and the version that works. Every such block of the
// page is a run of lines of this file, and `outcomes_rakes_test.dart` runs
// it. The first attempts live in `outcomes_first_attempts.dart`: there a
// line of an answer turned into the line of a first attempt would be found.
import 'package:async_job/async_job.dart';

import 'outcomes_stubs.dart';

/// Reading the result: a `switch` over `done`.
Future<void> printReport(Job<Report> report) async {
  final message = switch (await report.done) {
    Done(:final value) => 'report: $value',
    Failed(:final error) => 'failed: $error',
    Cancelled(:final reason) => 'cancelled: $reason',
  };
  print(message);
}

/// A failure nobody waits for: the core is told it is handled.
Job<void> startSync() {
  final sync = Job<void>(upload)..ignore();
  return sync;
}

final class RequestCancelReason extends CancelReason {
  final Object error;
  final StackTrace stackTrace;

  const RequestCancelReason(this.error, this.stackTrace);

  @override
  String get name => 'request';
}

/// `report` and its child `fetch`.
({Job<Data> fetch, Job<Report> report}) startReport() {
  final fetch = Job.deferred<Data>(download);
  final report = Job<Report>((ctx) async {
    final data = await ctx.run(fetch);
    return Report(data);
  });
  return (fetch: fetch, report: report);
}

/// The request that refreshes the token cancels `fetch` when it fails.
Future<void> refresh(Job<Data> fetch) async {
  try {
    await refreshToken();
  } on Object catch (error, stackTrace) {
    await fetch.cancel(reason: RequestCancelReason(error, stackTrace));
  }
}

CancelReason origin(Cancelled cancelled) => switch (cancelled.reason) {
      HandlerCancelReason(:final cause?) ||
      ParentCancelReason(:final cause?) ||
      ChainCancelReason(:final cause) =>
        origin(cause),
      final reason => reason,
    };

/// Following the cause: what the code that started `report` prints.
Future<void> tellTheRequest(Job<Report> report) async {
  final message = switch (await report.done) {
    Done(:final value) => 'report: $value',
    Failed(:final error) => 'failed: $error',
    final Cancelled cancelled => switch (origin(cancelled)) {
        RequestCancelReason(:final error) => 'request failed: $error',
        final reason => 'cancelled: $reason',
      },
  };
  print(message);
}

/// Reacting before the outcome: a step a cancellation cannot interrupt,
/// and the cleanup after it.
Job<void> startSteppedReport() {
  final report = Job<void>((ctx) async {
    ctx.onDispose(() => print('cleanup'));
    await ctx.run(
      Job.deferred<void>(cancellable: false, (ctx) async {
        await ctx.pause(const Duration(milliseconds: 50));
        print('step finished');
      }),
    );
  });
  return report;
}

/// Listening for the cancellation: the screen says it at once.
Future<void> showCancelling(Job<void> report) async {
  // Runs when the cancellation is accepted; the job may still be finishing.
  final unregister = report.whenCancelled((cancelled) {
    print('cancelling: ${cancelled.reason}');
  });

  await report.done;
  // Safe after completion; call earlier to stop listening sooner.
  unregister();
}
