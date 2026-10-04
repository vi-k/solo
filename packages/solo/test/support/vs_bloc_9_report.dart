// Section 9 of `doc/vs-bloc.md`, "Reacting to an independent external state change": what the page leaves out,
// then the code under its `### Solo` heading, verbatim, then what
// `vs_bloc_rakes_test.dart` adds on top of it. Every piece of the page's
// blocks is a run of lines of this file. The bloc side of the section is
// built and run by the bench, `tool/doc_snippets.py`: this package does not
// depend on bloc.
import 'package:solo/solo.dart';

import 'vs_bloc_stubs.dart';

class Range {
  const Range(this.days);

  final int days;
}

class Report {
  const Report(this.days);

  final int days;

  @override
  String toString() => 'Report($days days)';
}

/// Builds from data already on the device. A revoked session is news from
/// another service, so it cannot stop a build already under way: there is
/// nothing here for it to refuse.
class Reports {
  int built = 0;

  Future<Report> build(Range range) async {
    await tick(50);
    built++;
    return Report(range.days);
  }
}

class Auth {
  void Function(String reason)? onRevoked;

  void revoke(String reason) => onRevoked?.call(reason);
}

sealed class ReportState {
  const ReportState();
}

final class SignedIn extends ReportState {
  const SignedIn();

  @override
  String toString() => 'SignedIn';
}

final class Ready extends ReportState {
  const Ready(this.report);

  final Report report;

  @override
  String toString() => 'Ready($report)';
}

final class SignedOut extends ReportState {
  const SignedOut(this.reason);

  final String reason;

  @override
  String toString() => 'SignedOut($reason)';
}

// The code of the page.

final class ReportController extends Solo<ReportState> with SoloStream {
  final Reports _reports;

  ReportController(this._reports, Auth auth) : super(const SignedIn()) {
    auth.onRevoked = (reason) {
      if (!isFinished) externalSetState(SignedOut(reason));
    };
  }

  Job<void> build(Range range) => run<SignedIn, void>(
        key: 'report',
        (ctx) async {
          final report = await ctx.join(() => _reports.build(range));
          ctx.emit(Ready(report));
        },
      );
}

// What the test adds.

/// The revocation published by an ordinary job: "Published by an ordinary
/// job, `SignedOut` would queue behind the build".
final class QueuedRevocationController extends Solo<ReportState>
    with SoloStream {
  QueuedRevocationController(this._reports, Auth auth)
      : super(const SignedIn()) {
    auth.onRevoked = (reason) {
      run<ReportState, void>((ctx) async => ctx.emit(SignedOut(reason)));
    };
  }

  final Reports _reports;

  Job<void> build(Range range) => run<SignedIn, void>(
        key: 'report',
        (ctx) async {
          final report = await ctx.join(() => _reports.build(range));
          ctx.emit(Ready(report));
        },
      );
}

/// The build of the page with one more read after its own `emit`, and with
/// final state handlers: what the page says of a later checkpoint and of
/// handlers an external update disables.
final class HandledReportController extends Solo<ReportState> {
  HandledReportController(this._reports, Auth auth) : super(const SignedIn()) {
    auth.onRevoked = (reason) {
      if (!isFinished) externalSetState(SignedOut(reason));
    };
  }

  final Reports _reports;

  /// The final state handlers that ran.
  final handlers = <String>[];

  Job<void> build(Range range, {bool readsAfterEmit = false}) =>
      run<SignedIn, void>(
        key: 'report',
        onError: (state, error, stackTrace) {
          handlers.add('onError');
          return const SignedIn();
        },
        onCancel: (state, cancelled) {
          handlers.add('onCancel');
          return const SignedIn();
        },
        (ctx) async {
          final report = await ctx.join(() => _reports.build(range));
          ctx.emit(Ready(report));
          if (readsAfterEmit) {
            ctx.check();
          }
        },
      );

  /// A job the handlers do stand for: cancelled by hand, nothing external.
  Job<void> stall() => run<SignedIn, void>(
        key: 'stall',
        onCancel: (state, cancelled) {
          handlers.add('onCancel');
          return const SignedIn();
        },
        (ctx) => ctx.wait(() => tick(1000)),
      );
}

/// The controller of the page without its guard, with an `onClose` that
/// says when it came and a job that says how far the build had got.
final class UnguardedReportController extends Solo<ReportState> {
  UnguardedReportController(this._reports, Auth auth)
      : super(const SignedIn()) {
    auth.onRevoked = (reason) => externalSetState(SignedOut(reason));
  }

  final Reports _reports;
  final seen = <String>[];

  Job<void> build(Range range) => run<SignedIn, void>(
        key: 'report',
        (ctx) async {
          final report = await ctx.join(() => _reports.build(range));
          ctx.emit(Ready(report));
        },
      );

  Job<void> mark() => run<ReportState, void>(
        key: 'mark',
        (ctx) async =>
            seen.add('the next root job starts with ${_reports.built} built'),
      );

  @override
  void onFinish(Job<Object?> job) => seen.add('${job.key} is over');

  @override
  void onClose() => seen.add('onClose, isFinished $isFinished');
}
