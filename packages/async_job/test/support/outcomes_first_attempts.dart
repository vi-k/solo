// The first attempts of `doc/outcomes.md`, verbatim: the version the API
// leads to, which each section opens with. Every such block of the page is
// a run of lines of this file. They live apart from the answers in
// `outcomes_page.dart`, so a line of an answer turned into the line of a
// first attempt is not found among them.
import 'package:async_job/async_job.dart';

import 'outcomes_page.dart' show RequestCancelReason;
import 'outcomes_stubs.dart';

/// Reading the result: `value` in a `try`.
Future<void> printReport(Job<Report> report) async {
  try {
    print('report: ${await report.value}');
  } on Object catch (error) {
    print('failed: $error');
  }
}

/// A failure nobody waits for: nothing awaits `sync`.
Job<void> startSync() {
  final sync = Job<void>(upload);
  return sync;
}

/// The status line, drawn whenever it is drawn.
void drawStatus(Job<void> sync) {
  // Wherever the status line is drawn:
  final status = switch (sync.outcome) {
    null => 'syncing',
    Done() => 'synced',
    Failed(:final error) => 'sync failed: $error',
    Cancelled() => 'sync cancelled',
  };
  print('status: $status');
}

/// Why a job was cancelled: the `switch` over `done` gets a case for the
/// reason.
Future<void> tellTheRequest(Job<Report> report) async {
  final message = switch (await report.done) {
    Done(:final value) => 'report: $value',
    Failed(:final error) => 'failed: $error',
    Cancelled(reason: RequestCancelReason(:final error)) =>
      'request failed: $error',
    Cancelled(:final reason) => 'cancelled: $reason',
  };
  print(message);
}

/// Reacting before the outcome: the outcome says whether the job was
/// cancelled.
Future<void> showCancelling(Job<void> report) async {
  if (await report.done case Cancelled(:final reason)) {
    print('cancelling: $reason');
  }
}
