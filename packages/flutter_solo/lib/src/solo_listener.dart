import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:solo/solo.dart';

import 'solo_builder.dart';

/// What a change does while an earlier reaction of a [SoloListener] runs.
///
/// Each value shows the trace of the same writes: 1, then 2 and 3 together
/// 10 ms later, every reaction waiting 100 ms. `s1` is the start of the
/// reaction to 1, and `e1` is its end.
enum SoloListenerMode {
  /// Starts the reaction at once, next to the running ones:
  /// `s1 s2 s3 e1 e2 e3`.
  concurrent,

  /// Puts the change in the queue of the widget, so that the reactions run
  /// one at a time: `s1 e1 s2 e2 s3 e3`.
  ///
  /// A reaction that writes to its own controller queues the reaction to
  /// that write after itself.
  sequential,

  /// Drops the change: `s1 e1`.
  ///
  /// A write of a reaction to its own controller is dropped as well. After
  /// [SoloListener.solo] is replaced, a reaction of the old controller runs
  /// until its cancellation takes, and a change of the new one that comes
  /// meanwhile is dropped.
  droppable,

  /// Keeps the latest of the waiting changes and drops the rest:
  /// `s1 e1 s3 e3`.
  keepLatest,

  /// Keeps the latest change, as [keepLatest] does, and cancels the running
  /// reactions with [ReplacedCancelReason] without waiting for them:
  /// `s1 s3 e3`.
  ///
  /// The next reaction starts when the cancelled one ends: at once out of
  /// `ctx.pause` or `ctx.abandonable`, and only at the end of the wait out of
  /// `ctx.join` or a plain `await`. A reaction that writes to its own
  /// controller cancels itself.
  restart,
}

/// Runs a reaction, a job of the core, on every change of [solo] that
/// [listenWhen] lets through.
///
/// The reaction gets the state of its change, not [Solo.currentState], and
/// starts on a microtask after the change: outside of a build, so it may show
/// a snack bar or push a route. The state the widget subscribes at starts no
/// reaction, and [mode] says what a change does while a reaction runs. A
/// failure goes to `FlutterError`, and the screen is drawn by [SoloBuilder]:
/// this widget builds [child] as it is.
///
/// Leaving the tree, or a new [solo], cancels the reactions and drops the
/// waiting changes. The cancellation is cooperative: a reaction waiting in
/// `ctx.join` or in a plain `await` waits to the end, and `context` may be
/// gone by then. `ctx.pause` ends at once:
///
/// ```dart
/// SoloListener<Feed>(
///   solo: feed,
///   listenWhen: (previous, current) => current is FeedFailed,
///   mode: SoloListenerMode.restart,
///   listener: (ctx, context, state) async {
///     await ctx.pause(const Duration(seconds: 5));
///     feed.reload();
///   },
///   child: const FeedView(),
/// )
/// ```
///
/// See [Reacting to a change](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.md#reacting-to-a-change)
/// in the package README.
final class SoloListener<S extends Object> extends StatefulWidget {
  /// The controller whose changes start the reactions.
  ///
  /// Replaced by another one, compared by identity, it takes the reactions
  /// to its changes along: the running ones are cancelled and the waiting
  /// ones dropped. The reactions to the new one wait for the cancelled ones
  /// to end, and the state of the new one at that moment starts no reaction.
  final Solo<S> solo;

  /// The reaction, called with the context of its job first, then the
  /// context of the widget and the state of the change.
  ///
  /// The state is the one the change wrote, and [Solo.currentState] may have
  /// moved on by the time the reaction starts. Read when the reaction starts,
  /// so a reaction that waited runs the closure of the latest build. A
  /// reaction that fails goes to `FlutterError`, and the next ones still run.
  final FutureOr<void> Function(JobContext ctx, BuildContext context, S state)
  listener;

  /// Whether a change starts a reaction, given its previous and its current
  /// state.
  ///
  /// Called synchronously, inside the change. Without it every change
  /// reacts, the same object written again included; equal states are
  /// skipped with `(previous, current) => previous != current`. Read at every
  /// change, so a rebuild with another one counts from the next change. One
  /// that throws goes to `FlutterError`, and the change starts no reaction.
  final bool Function(S previous, S current)? listenWhen;

  /// What a change does while an earlier reaction runs; see
  /// [SoloListenerMode].
  ///
  /// Read at every change. A new mode leaves the running reactions alone and
  /// applies to the waiting changes from the next change on:
  /// [SoloListenerMode.keepLatest] and [SoloListenerMode.restart] replace
  /// them.
  final SoloListenerMode mode;

  /// The subtree this widget builds, as it is.
  final Widget child;

  /// Creates a widget that reacts to the changes of [solo].
  const SoloListener({
    required this.solo,
    required this.listener,
    required this.child,
    this.listenWhen,
    this.mode = SoloListenerMode.concurrent,
    super.key,
  });

  @override
  State<SoloListener<S>> createState() => _SoloListenerState<S>();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<Solo<S>>('solo', solo))
      ..add(EnumProperty<SoloListenerMode>('mode', mode));
  }
}

final class _SoloListenerState<S extends Object>
    extends State<SoloListener<S>> {
  /// The reactions that have been made and have not finished, a cancelled
  /// one included.
  final _running = <Job<void>>{};

  /// The states whose reactions wait for the running ones, oldest first.
  final _waiting = <S>[];

  /// Answers for the reactions: what the core asks an answer for goes to
  /// `FlutterError`, whether the controller is a `SoloListenable` or not.
  final _reporter = _Reporter();

  /// Puts the listener on the controller of the widget; see
  /// `_SoloBuilderState` for why a throwing controller is let go of here.
  void _follow() {
    try {
      widget.solo.addChangeListener(_changed);
    } on Object catch (_) {
      widget.solo.removeChangeListener(_changed);
      rethrow;
    }
  }

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(covariant SoloListener<S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.solo, oldWidget.solo)) {
      _letGo(oldWidget.solo);
      _follow();
    }
  }

  /// Set first thing in `dispose`, as in `_SoloBuilderState`.
  var _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _letGo(widget.solo);
    super.dispose();
  }

  /// Drops the reactions to the changes of [solo] and its subscription.
  ///
  /// The waiting states go first: a job cancelled before its start finishes
  /// inside `cancel`, and a waiting state would start from there. The
  /// cancelled ones stay running until they end, and the reactions to the
  /// next controller wait for them, or are dropped in `droppable`.
  void _letGo(Solo<S> solo) {
    _waiting.clear();
    solo.removeChangeListener(_changed);
    for (final job in _running.toList()) {
      unawaited(job.cancel());
    }
  }

  void _changed(S previous, S current) {
    if (_disposed) {
      return;
    }
    final listenWhen = widget.listenWhen;
    if (listenWhen != null) {
      final bool reacts;
      try {
        reacts = listenWhen(previous, current);
      } on Object catch (error, stackTrace) {
        _report(error, stackTrace, 'while calling listenWhen of SoloListener');
        return;
      }
      if (!reacts) {
        return;
      }
    }
    if (_running.isEmpty) {
      _start(current);
      return;
    }
    switch (widget.mode) {
      case SoloListenerMode.concurrent:
        _start(current);
      case SoloListenerMode.sequential:
        _waiting.add(current);
      case SoloListenerMode.droppable:
        break;
      case SoloListenerMode.keepLatest:
        _waiting
          ..clear()
          ..add(current);
      case SoloListenerMode.restart:
        // The waiting state first: a job cancelled before its start finishes
        // inside `cancel`, and the next one starts from there.
        _waiting
          ..clear()
          ..add(current);
        for (final job in _running.toList()) {
          unawaited(job.cancel(reason: const ReplacedCancelReason()));
        }
    }
  }

  void _start(S state) {
    final job = Job<void>(
      // Read at the start: a closure from the latest `build`.
      (ctx) async => widget.listener(ctx, context, state),
      describe: () => 'SoloListener<$S> reacting to $state',
      observer: _reporter,
    );
    _running.add(job);
    job.whenFinished((_) => _finished(job));
  }

  void _finished(Job<void> job) {
    _running.remove(job);
    if (_disposed || _running.isNotEmpty || _waiting.isEmpty) {
      return;
    }
    _start(_waiting.removeAt(0));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Hands an error of a [SoloListener] to `FlutterError`.
void _report(Object error, StackTrace stackTrace, String context) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'flutter_solo',
      context: ErrorDescription(context),
    ),
  );
}

/// Answers for whatever a reaction leaves unanswered: a failure, the late
/// failure of a reaction that took its cancellation, and the rest the core
/// asks an answer for. A cancellation never comes here.
final class _Reporter extends JobObserver with JobAnswerer {
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      _report(error, stackTrace, 'while running a reaction of SoloListener');
}
