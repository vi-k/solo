// Section 2 of `doc/vs-bloc.md`, "An observer fails during a state update": what the page leaves out,
// then the code under its `### Solo` heading, verbatim, then what
// `vs_bloc_rakes_test.dart` adds on top of it. Every piece of the page's
// blocks is a run of lines of this file. The bloc side of the section is
// built and run by the bench, `tool/doc_snippets.py`: this package does not
// depend on bloc.
import 'package:solo/solo.dart';

class TelemetryFailure implements Exception {
  @override
  String toString() => 'telemetry unavailable';
}

/// The endpoint is down, so every send throws.
class Telemetry {
  void send(Object? state) => throw TelemetryFailure();
}

/// The controller's own record of what the state did.
class Journal {
  final entries = <String>[];

  void note(String state) => entries.add(state);
}

class Recorder {
  final trace = <String>[];

  Future<void> start() async => trace.add('native start');

  void armMeter() => trace.add('arm meter');
}

sealed class RecorderState {
  const RecorderState();
}

final class Idle extends RecorderState {
  const Idle();

  @override
  String toString() => 'Idle';
}

final class Recording extends RecorderState {
  const Recording();

  @override
  String toString() => 'Recording';
}

// The code of the page.

final class RecorderController extends Solo<RecorderState> {
  final Recorder _recorder;
  final Journal _journal;

  RecorderController(this._recorder, this._journal) : super(const Idle());

  Job<void> start() => run<RecorderState, void>(
        key: 'start',
        (ctx) async {
          await ctx.join(_recorder.start);
          ctx.emit(const Recording());
          _recorder.armMeter();
        },
      );

  @override
  void onChange(SoloTransition<RecorderState> transition) =>
      _journal.note('${transition.current}');
}

final class TelemetryObserver extends SoloObserver {
  final Telemetry _telemetry;

  TelemetryObserver(this._telemetry);

  @override
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) =>
      _telemetry.send(transition.current);
}

// What the test adds.

/// A controller whose own hook is the one that throws.
final class ThrowingHookController extends Solo<RecorderState> {
  ThrowingHookController() : super(const Idle());

  Job<void> start() => run<RecorderState, void>(
        (ctx) async => ctx.emit(const Recording()),
      );

  @override
  void onChange(SoloTransition<RecorderState> transition) =>
      throw StateError('the hook of the controller failed');
}

/// An observer that only watches.
final class WatchingObserver extends SoloObserver {
  final seen = <String>[];

  @override
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) =>
      seen.add('change to ${transition.current}');

  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) =>
      seen.add('error $error');
}
