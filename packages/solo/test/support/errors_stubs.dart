// What the code of `doc/errors.md` takes for granted: the profile of the
// quick start, the crash reporter, Sentry, the log, the camera, the slots,
// the analytics and the logger. Every call of a stub runs until the test
// ends it, unless its name is in `Stage.endsByItself`, so the order of what
// happened is the test's to set. `Desk` is what the tests need of a
// controller beside the page's own members, and `Bench` is a controller
// whose bodies are written where they are run.
import 'dart:async';

import 'package:solo/solo.dart';

import 'test_solo.dart';

/// One call of a stub that has not ended yet.
final class _Call {
  final void Function() end;
  final void Function(Object error) fail;

  _Call(this.end, this.fail);
}

/// How the stubs behave in the test at hand, and what they did.
final class Stage {
  /// What the stubs did, in order.
  final trace = <String>[];
  final _running = <String, _Call>{};

  /// The calls that end by themselves, a microtask after they start. A test
  /// takes a name out to hold that call until it ends it.
  final endsByItself = <String>{'reset'};

  /// What `reportCrash` was handed, in order.
  final crashes = <String>[];

  /// What `Sentry.captureException` was handed, in order.
  final sentry = <String>[];

  /// What `log` wrote, in order.
  final lines = <String>[];

  /// What the logger wrote at `Level.FINE`, in order.
  final fine = <Object?>[];

  /// The level the logger listens at.
  Level level = Level.FINE;

  /// How many times `device.describe()` ran.
  int described = 0;

  /// Starts [call], which answers with [value] when the test ends it.
  Future<T> start<T>(String call, T value) {
    trace.add('$call start');
    if (endsByItself.contains(call)) {
      return Future<T>.microtask(() {
        trace.add('$call end');

        return value;
      });
    }
    final done = Completer<T>();
    _running[call] = _Call(
      () {
        trace.add('$call end');
        done.complete(value);
      },
      (error) {
        trace.add('$call failed');
        done.completeError(error, StackTrace.current);
      },
    );

    return done.future;
  }

  bool isRunning(String call) => _running.containsKey(call);

  /// Ends [call] the way it would end on its own.
  void end(String call) => _running.remove(call)!.end();

  /// Fails [call] with [error].
  void fail(String call, Object error) => _running.remove(call)!.fail(error);
}

Stage stage = Stage();

// --- The profile of the quick start ---------------------------------------

sealed class ProfileState {
  const ProfileState();
}

final class Initial extends ProfileState {
  const Initial();

  @override
  String toString() => 'Initial';
}

final class Loading extends ProfileState {
  const Loading();

  @override
  String toString() => 'Loading';
}

final class Loaded extends ProfileState {
  final String name;

  const Loaded(this.name);

  @override
  String toString() => 'Loaded($name)';
}

final class Failure extends ProfileState {
  final Object error;

  const Failure(this.error);

  @override
  String toString() => 'Failure($error)';
}

/// The API of the quick start, answering when the test says so.
class ProfileApi {
  Future<String> fetchName() => stage.start('fetchName', 'Ada Lovelace');
}

/// The crash reporter of the application.
void reportCrash(Object error, StackTrace stackTrace) =>
    stage.crashes.add(text(error));

/// What the handler of the page reports to.
// ignore: avoid_classes_with_only_static_members
abstract final class Sentry {
  static Future<void> captureException(
    Object throwable, {
    StackTrace? stackTrace,
  }) async =>
      stage.sentry.add(text(throwable));
}

/// The log of the application.
void log(String line) => stage.lines.add(line);

// --- The camera -----------------------------------------------------------

sealed class CameraState {
  const CameraState();
}

final class Closed extends CameraState {
  const Closed();

  @override
  String toString() => 'Closed';
}

final class Broken extends CameraState {
  final Object error;

  const Broken(this.error);

  @override
  String toString() => 'Broken(${text(error)})';
}

/// A token of the camera's own API, not a type of the package.
final class StopToken {
  bool stopped = false;

  void stop() => stopped = true;
}

/// What an opening throws when it stops at its token.
final class OpenStopped implements Exception {
  @override
  String toString() => 'OpenStopped';
}

final class Hardware {
  Future<void> open() => stage.start<void>('open', null);

  Future<void> setZoom(double zoom) => stage.start<void>('setZoom', null);

  Future<void> reset() => stage.start<void>('reset', null);

  /// An opening that reads [token] once the test ends the call, and stops
  /// by throwing.
  Future<void> openWith(StopToken token) async {
    await stage.start<void>('open', null);
    if (token.stopped) {
      stage.trace.add('open stopped');
      throw OpenStopped();
    }
  }
}

// --- The slots ------------------------------------------------------------

final class Slots {
  final int free;

  const Slots(this.free);

  @override
  String toString() => 'Slots($free)';
}

// --- Analytics, the device and the logger ---------------------------------

final class Analytics {
  Future<void> send(String event) => stage.start<void>('send', null);
}

final analytics = Analytics();

final class Device {
  String describe() {
    stage.described++;

    return 'the back camera';
  }
}

final device = Device();

/// The levels of the application's logger.
final class Level {
  final String name;
  final int value;

  const Level(this.name, this.value);

  // ignore: constant_identifier_names
  static const FINE = Level('FINE', 500);
  // ignore: constant_identifier_names
  static const INFO = Level('INFO', 800);
}

final class Logger {
  bool isLoggable(Level value) => value.value >= stage.level.value;

  void fine(Object? message) {
    if (isLoggable(Level.FINE)) {
      stage.fine.add(message);
    }
  }
}

final logger = Logger();

// --- What the tests need beside the page ----------------------------------

/// An error the way the tests compare it: without the prefix of its class.
String text(Object error) => error is ParallelWaitError
    ? 'ParallelWaitError'
    : '$error'.replaceFirst('Bad state: ', '');

/// What the tests need of a controller beside the page's own members: what
/// its two error hooks were told, and a fact from outside the queue.
mixin Desk<S extends Object> on Solo<S> {
  /// What the `onError` hook of this controller was told.
  final heard = <String>[];

  /// What this controller was asked to answer for.
  final unanswered = <String>[];

  /// The state something outside the queue reports.
  void reflect(S state) => externalSetState(state);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      heard.add('${job.key}: ${text(error)}');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    unanswered.add('${job.key}: ${text(error)}');
    super.onUnanswered(job, error, stackTrace);
  }
}

/// A controller of the tests' own, for what the page states of the engine
/// and its code does not show: the bodies are written where they are run.
final class Bench extends Solo<int> with OpenSolo<int>, Desk<int> {
  Bench([super.initialState = 0]);
}

/// [Bench] with a stream.
final class StreamBench extends Solo<int>
    with SoloStream<int>, OpenSolo<int>, Desk<int> {
  StreamBench([super.initialState = 0]);
}
