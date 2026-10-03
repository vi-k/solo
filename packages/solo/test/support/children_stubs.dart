// What the code of `doc/children.md` takes for granted: the states of the
// application, its API, its hardware and its analytics, and the session a
// screen follows. Every call of a stub runs until the test ends it, so the
// order of what happened is the test's to set. `Desk` is what the tests need
// of a controller of the page beside the page's own members.
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

  /// The progress of the upload. Its `onCancel` returns a future of the zone
  /// the test runs in: a subscription with nothing to do on cancel hands out
  /// a future of the root zone, and under fake time awaiting that one never
  /// comes back.
  final progress = StreamController<int>(onCancel: () async {});

  /// The positions the hardware reports.
  final positions = StreamController<int>(onCancel: () async {});

  /// Starts [call], which answers with [value] when the test ends it.
  Future<T> start<T>(String call, T value) {
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

    return done.future;
  }

  bool isRunning(String call) => _running.containsKey(call);

  /// Ends [call] the way it would end on its own.
  void end(String call) => _running.remove(call)!.end();

  /// Fails [call] with [error].
  void fail(String call, Object error) => _running.remove(call)!.fail(error);

  /// Lets go of the sources.
  void dispose() {
    unawaited(progress.close());
    unawaited(positions.close());
  }
}

Stage stage = Stage();

/// The states of the application.
sealed class AppState {
  const AppState();
}

/// The state the jobs of the page work in.
final class Ready extends AppState {
  /// How much of the upload the API has taken.
  final int sent;

  /// The last position the hardware reported.
  final int position;

  /// Where the last upload went.
  final String path;

  /// A fact for the rules of the tests' own jobs.
  final bool paused;

  const Ready({
    this.sent = 0,
    this.position = 0,
    this.path = '',
    this.paused = false,
  });

  Ready copyWith({int? sent, int? position, String? path, bool? paused}) =>
      Ready(
        sent: sent ?? this.sent,
        position: position ?? this.position,
        path: path ?? this.path,
        paused: paused ?? this.paused,
      );

  @override
  String toString() => 'Ready(sent: $sent, position: $position, path: $path'
      '${paused ? ', paused' : ''})';
}

/// A state outside the working type of the page's jobs.
final class Off extends AppState {
  const Off();

  @override
  String toString() => 'Off';
}

final class Api {
  /// Uploads [item] and answers with the path it went to.
  Future<String> push(int item) => stage.start('push $item', 'path/$item');

  /// How much of [item] the API has taken. It closes the stream when the
  /// upload ends; here the test does.
  Stream<int> progress(int item) => stage.progress.stream;
}

final api = Api();

final class Hardware {
  Stream<int> get positions => stage.positions.stream;
}

final hw = Hardware();

final class Analytics {
  Future<void> send(String path) => stage.start<void>('send $path', null);
}

final analytics = Analytics();

/// What the tests need of a controller of the page beside the page's own
/// members: what its hooks were told, a fact from outside the queue, and
/// work to put next to the page's.
mixin Desk on Solo<AppState> {
  /// What the `onError` hook of this controller was told.
  final heard = <String>[];

  /// What this controller was asked to answer for.
  final unanswered = <String>[];

  /// The state something outside the queue reports.
  void reflect(AppState state) => externalSetState(state);

  /// The `save()` the page speaks of: a job of the queue with a step the
  /// test ends.
  SoloJob<void> save() => run<Ready, void>(
        key: 'save',
        (ctx) => ctx.join(() => stage.start<void>('save', null)),
      );

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      heard.add('$job: $error');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    unanswered.add('$job: $error');
    super.onUnanswered(job, error, stackTrace);
  }
}

/// A controller of the tests' own, for what the page states of the engine
/// and its code does not show: the bodies are written where they are run.
final class Bench extends Solo<AppState> with OpenSolo<AppState>, Desk {
  Bench([super.initialState = const Ready()]);
}

/// The state of the screen that follows a session.
final class Screen {
  final bool signedIn;

  const Screen({this.signedIn = false});

  Screen copyWith({bool? signedIn}) =>
      Screen(signedIn: signedIn ?? this.signedIn);

  @override
  String toString() => 'Screen(signedIn: $signedIn)';
}

/// The state of the session.
final class Session {
  final bool signedIn;

  const Session({this.signedIn = false});

  @override
  String toString() => 'Session(signedIn: $signedIn)';
}

/// The controller a screen follows.
final class SessionController extends Solo<Session> with SoloStream<Session> {
  SessionController([super.initialState = const Session()]);

  /// Signs the user in or out, as a job of this controller.
  SoloJob<void> sign({required bool signedIn}) => run<Session, void>(
        key: 'sign',
        (ctx) async => ctx.emit(Session(signedIn: signedIn)),
      );
}
