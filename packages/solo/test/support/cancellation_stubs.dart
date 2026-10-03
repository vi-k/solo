// What the code of `doc/cancellation.md` takes for granted: the states of
// the application, the api, the device, the player with its token, the
// payment and the journal, and the controller the log lines go through.
// Every call of a stub runs until the test ends it, so the order of what
// happened is the test's to set. `Desk` is what the tests need of a
// controller of the page beside the page's own members.
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
  /// What the stubs and the jobs did, in order.
  final trace = <String>[];
  final _running = <String, _Call>{};

  /// Whether a token handed to a seek can stop it.
  bool hearsTokens = true;

  /// Whether a seek its token stops ends with an error.
  bool stopsByThrowing = false;

  /// Starts [call], which answers with [value] when the test ends it.
  Future<T> start<T>(String call, T value, [CancelToken? token]) {
    trace.add('$call start');
    final done = Completer<T>();
    _running[call] = _Call(
      () {
        trace.add('$call end');
        done.complete(value);
      },
      (error) {
        trace.add('$call failed');
        done.completeError(error);
      },
    );
    if (token != null && hearsTokens) {
      token._stop = () {
        if (_running.remove(call) == null) {
          return;
        }
        trace.add('$call stopped');
        if (stopsByThrowing) {
          done.completeError(const SeekStopped());
        } else {
          done.complete(value);
        }
      };
    }
    return done.future;
  }

  bool isRunning(String call) => _running.containsKey(call);

  /// Ends [call] the way it would end on its own.
  void end(String call) => _running.remove(call)!.end();

  /// Fails [call] with [error].
  void fail(String call, Object error) => _running.remove(call)!.fail(error);
}

Stage stage = Stage();

/// The states of the application.
sealed class AppState {
  const AppState();
}

/// The application is up: the player has a position, and the till shows the
/// receipt of the last payment.
final class Ready extends AppState {
  final Duration position;
  final String? receipt;

  const Ready({this.position = Duration.zero, this.receipt});

  Ready copyWith({Duration? position, String? receipt}) => Ready(
        position: position ?? this.position,
        receipt: receipt ?? this.receipt,
      );

  @override
  String toString() => 'Ready(${position.inSeconds} s, $receipt)';
}

/// The device is gone: a state outside `Ready`.
final class Offline extends AppState {
  const Offline();

  @override
  String toString() => 'Offline';
}

/// The player's own way to stop a seek it has begun.
final class CancelToken {
  void Function()? _stop;

  void cancel() {
    stage.trace.add('token cancelled');
    _stop?.call();
  }
}

/// What a seek ends with when its token stops it by throwing.
final class SeekStopped implements Exception {
  const SeekStopped();

  @override
  String toString() => 'SeekStopped';
}

/// What `device.open` hands over to own.
final class Handle {
  void close() => stage.trace.add('handle closed');
}

final class Api {
  Future<String> load(String id) => stage.start('load $id', 'name of $id');

  Future<void> logout() => stage.start<void>('logout', null);
}

final class Device {
  Future<Handle> open() => stage.start('open', Handle());

  Future<void> flush() => stage.start<void>('flush', null);

  Future<void> write(int chunk) => stage.start<void>('write $chunk', null);
}

final class Player {
  Future<void> seek(Duration position, {CancelToken? cancelToken}) =>
      stage.start<void>('seek ${position.inSeconds}', null, cancelToken);
}

final class Payment {
  Future<String> commit() => stage.start('payment', 'receipt');
}

final class Journal {
  Future<void> write(String entry) => stage.start<void>('journal', null);
}

final api = Api();
final device = Device();
final player = Player();
final payment = Payment();
final journal = Journal();

/// What the tests need of a controller of the page beside the page's own
/// members: what its hooks were told, a fact from outside the queue, and
/// work to put next to the page's.
mixin Desk on Solo<AppState> {
  /// What the `onError` hook of this controller was told.
  final heard = <Object>[];

  /// What this controller was asked to answer for.
  final unanswered = <Object>[];

  /// The state the device reports from outside the queue.
  void reflect(AppState state) => externalSetState(state);

  /// Work that waits out a call named [name], in `Ready`.
  SoloJob<void> work(String name) => run<Ready, void>(
        key: name,
        (ctx) => ctx.join(() => stage.start<void>(name, null)),
      );

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      heard.add(error);

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    unanswered.add(error);
    super.onUnanswered(job, error, stackTrace);
  }
}

/// The controller the log lines go through. The page shows the calls of
/// `send`, not the method.
final class Logs extends Solo<AppState> with OpenSolo<AppState>, Desk {
  /// The jobs `send` has made, in the order of the calls.
  final sent = <SoloJob<void>>[];

  Logs() : super(const Ready());

  SoloJob<void> send(String batch) {
    final job = run<Ready, void>(
      key: batch,
      (ctx) => ctx.join(() => stage.start<void>('send $batch', null)),
    );
    sent.add(job);

    return job;
  }
}

/// A controller of the tests' own, for what the page states of the engine
/// and its code does not show: the bodies are written where they are run.
final class Bench extends Solo<AppState> with OpenSolo<AppState>, Desk {
  Bench() : super(const Ready());
}
