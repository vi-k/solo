// What the code of `doc/resources.md` takes for granted: the states of the
// application, the database, the device with its events, the temporary file
// and the archive. Every call of a stub runs until the test ends it, unless
// its name is in `Stage.endsByItself`, so the order of what happened is the
// test's to set. `Desk` is what the tests need of a controller of the page
// beside the page's own members.
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
  final endsByItself = <String>{'close', 'delete', 'take'};

  /// The databases `Database.open` has made, in order.
  final databases = <Database>[];

  /// The files `openTemp` has made, in order.
  final files = <TempFile>[];

  /// What the archive was handed, in order.
  final archived = <TempFile>[];

  /// The events of the device. Its `onCancel` returns a future of the zone
  /// the test runs in: a subscription with nothing to do on cancel hands out
  /// a future of the root zone, and under fake time awaiting that one never
  /// comes back.
  late final StreamController<int> events = StreamController<int>(
    onListen: () => trace.add('subscription made'),
    onCancel: () async => trace.add('subscription cancelled'),
  );

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

  /// Lets go of the device.
  void dispose() => unawaited(events.close());
}

Stage stage = Stage();

/// The states of the application.
sealed class AppState {
  const AppState();
}

/// Nothing is loaded and nothing is open.
final class Idle extends AppState {
  const Idle();

  @override
  String toString() => 'Idle';
}

/// The rows are on the screen.
final class Loaded extends AppState {
  final List<String> rows;

  const Loaded(this.rows);

  @override
  String toString() => 'Loaded($rows)';
}

/// The screen holds the database itself.
final class Ready extends AppState {
  final Database db;

  const Ready(this.db);

  @override
  String toString() => 'Ready';
}

/// A database that says how often it was closed.
final class Database {
  int closes = 0;

  bool get closed => closes > 0;

  static Future<Database> open() {
    final db = Database();
    stage.databases.add(db);

    return stage.start('open', db);
  }

  Future<List<String>> readAll() => stage.start('readAll', const ['row']);

  Future<void> migrate() => stage.start<void>('migrate', null);

  Future<void> close() {
    closes += 1;

    return stage.start<void>('close', null);
  }
}

/// A temporary file that says how often it was deleted.
final class TempFile {
  int deletes = 0;

  bool get deleted => deletes > 0;

  Future<void> delete() {
    deletes += 1;

    return stage.start<void>('delete', null);
  }
}

Future<TempFile> openTemp() {
  final file = TempFile();
  stage.files.add(file);

  return stage.start('openTemp', file);
}

final class Device {
  Stream<int> get events => stage.events.stream;
}

final device = Device();

void onEvent(int event) => stage.trace.add('event $event');

final class Archive {
  Future<void> take(TempFile file) {
    stage.archived.add(file);

    return stage.start<void>('take', null);
  }
}

final archive = Archive();

/// What the tests need of a controller of the page beside the page's own
/// members: what its hooks were told, a fact from outside the queue, and
/// work to put next to the page's.
mixin Desk on Solo<AppState> {
  /// What the `onError` hook of this controller was told.
  final heard = <Object>[];

  /// What this controller was asked to answer for.
  final unanswered = <Object>[];

  /// The state something outside the queue reports.
  void reflect(AppState state) => externalSetState(state);

  /// Work that only says that it started, in any state.
  SoloJob<void> next() => run<AppState, void>(
        key: 'next',
        (ctx) async => stage.trace.add('next job started'),
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

/// A controller of the tests' own, for what the page states of the engine
/// and its code does not show: the bodies are written where they are run.
final class Bench extends Solo<AppState> with OpenSolo<AppState>, Desk {
  Bench([super.initialState = const Idle()]);
}
