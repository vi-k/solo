// Section 4 of `doc/vs-bloc.md`, "Leaving a loading state when the work is cancelled": what the page leaves out,
// then the code under its `### Solo` heading, verbatim, then what
// `vs_bloc_rakes_test.dart` adds on top of it. Every piece of the page's
// blocks is a run of lines of this file. The bloc side of the section is
// built and run by the bench, `tool/doc_snippets.py`: this package does not
// depend on bloc.
import 'dart:async';

import 'package:solo/solo.dart';

sealed class RefreshState {
  const RefreshState();
}

final class Initial extends RefreshState {
  const Initial();

  @override
  String toString() => 'Initial';
}

final class Loading extends RefreshState {
  const Loading();

  @override
  String toString() => 'Loading';
}

/// Answers when the test says so, and with what.
class RefreshApi {
  Completer<void> pending = Completer<void>();
  int calls = 0;

  Future<void> refresh() {
    calls++;
    return pending.future;
  }
}

// The code of the page.

final class RefreshController extends Solo<RefreshState> {
  final RefreshApi _api;

  RefreshController(this._api) : super(const Initial());

  Job<void> refresh() => run<RefreshState, void>(
        key: 'refresh',
        policy: Policy.restart,
        onError: (state, error, stackTrace) => const Initial(),
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          await ctx.wait(_api.refresh);
          ctx.emit(const Initial());
        },
      );

  Job<void>? cancelRefresh() {
    final refresh = lastJobWhere((job) => job.key == 'refresh');
    unawaited(refresh?.cancel());
    return refresh;
  }
}

// What the test adds.

/// The refresh of the page with a cleanup that takes time, a job that says
/// what state it started in, and a job of a narrower type with both final
/// state handlers.
final class SlowCleanupRefreshController extends Solo<RefreshState> {
  SlowCleanupRefreshController(this._api) : super(const Initial());

  final RefreshApi _api;
  final seen = <String>[];

  Job<void> refresh() => run<RefreshState, void>(
        key: 'refresh',
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx
            ..onDispose(() async {
              seen.add('cleanup starts in $currentState');
              await Future<void>.delayed(const Duration(milliseconds: 30));
              seen.add('cleanup ends in $currentState');
            })
            ..emit(const Loading());
          await ctx.wait(_api.refresh);
        },
      );

  Job<void> mark() => run<RefreshState, void>(
        key: 'mark',
        (ctx) async => seen.add('the next job starts in ${ctx.state}'),
      );

  Job<void> narrow() => run<Loading, void>(
        key: 'narrow',
        onError: (state, error, stackTrace) {
          seen.add('onError ran');
          return const Initial();
        },
        onCancel: (state, cancelled) {
          seen.add('onCancel ran');
          return const Loading();
        },
        (ctx) => ctx.wait(_api.refresh),
      );

  void outside(RefreshState state) => externalSetState(state);
}
