// The code of `doc/accumulation.md`, verbatim, less the first and second
// attempts: every piece of those blocks is a run of lines of this file, and
// `accumulation_rakes_test.dart` runs it. A block the page shows as a method
// or as a few statements stands in a class or a function of this file, and
// what this file adds to the page says so.
import 'package:solo/solo.dart';

class SearchState {
  final List<String> results;

  const SearchState.idle() : results = const [];

  const SearchState.results(this.results);
}

// ignore: one_member_abstracts
abstract interface class SearchApi {
  Future<List<String>> search(String text);
}

final class Search extends Solo<SearchState> {
  final SearchApi api;
  late final _queries = accumulate<SearchState, String, void>(
    (ctx, text) async {
      final results = await ctx.abandonable(() => api.search(text));
      ctx.emit(SearchState.results(results));
    },
    merge: (accumulated, incoming) => incoming,
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 300)),
    policy: AccumulationPolicy.join,
    key: 'query',
  );

  Search(this.api) : super(const SearchState.idle());

  Job<void> query(String text) => _queries.add(text);
}

class Settings {
  final bool notifications;
  final String theme;
  final String language;

  const Settings({
    required this.notifications,
    required this.theme,
    required this.language,
  });
}

class SettingsPatch {
  final bool? notifications;
  final String? theme;
  final String? language;

  const SettingsPatch({
    this.notifications,
    this.theme,
    this.language,
  });

  SettingsPatch merge(SettingsPatch incoming) => SettingsPatch(
        notifications: incoming.notifications ?? notifications,
        theme: incoming.theme ?? theme,
        language: incoming.language ?? language,
      );

  Settings apply(Settings current) => Settings(
        notifications: notifications ?? current.notifications,
        theme: theme ?? current.theme,
        language: language ?? current.language,
      );
}

abstract interface class SettingsApi {
  Future<void> save(Settings settings);

  Future<Settings> load();
}

final class SettingsController extends Solo<Settings> {
  final SettingsApi _api;
  late final _updates = accumulate<Settings, SettingsPatch, void>(
    (ctx, patch) async {
      final next = patch.apply(ctx.state);
      await ctx.join(() => _api.save(next));
      ctx.emit(next);
    },
    merge: (accumulated, incoming) => accumulated.merge(incoming),
    key: 'settings',
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 200)),
  );

  SettingsController(this._api, Settings initial) : super(initial);

  Job<void> update(SettingsPatch patch) => _updates.add(patch);

  Job<void> reload() => run<Settings, void>(
        key: 'reload',
        (ctx) async => ctx.emit(await ctx.abandonable(_api.load)),
      );
}

Future<void> changeSettings(SettingsApi api, Settings initial) async {
  final controller = SettingsController(api, initial);
  try {
    final first = controller.update(
      const SettingsPatch(notifications: true),
    );
    final second = controller.update(const SettingsPatch(theme: 'dark'));
    final third = controller.update(const SettingsPatch(language: 'ru'));

    print(identical(first, second) && identical(second, third));
    print(await first.done);
  } finally {
    await controller.close();
  }
}

class LogEntry {
  final String message;

  const LogEntry(this.message);
}

// ignore: one_member_abstracts
abstract interface class LogApi {
  Future<void> send(List<LogEntry> entries);
}

final class LogController extends Solo<int> {
  final LogApi _api;
  late final _logs = collect<int, LogEntry, void>(
    (ctx, entries) async {
      await ctx.join(() => _api.send(entries));
      ctx.emit(ctx.state + entries.length);
    },
    key: 'logs',
    policy: AccumulationPolicy.join,
    timing: AccumulationTiming.throttle(const Duration(seconds: 1)),
  );

  LogController(this._api) : super(0);

  Job<void> logEvent(LogEntry entry) => _logs.add(entry);
}

enum Command { resume, pause }

sealed class Playback {
  const Playback();
}

final class Playing extends Playback {
  const Playing();
}

final class Paused extends Playback {
  const Paused();
}

abstract interface class PlayerDevice {
  Future<void> resume();

  Future<void> pause();
}

final class Player extends Solo<Playback> {
  final PlayerDevice device;

  late final _transport = accumulate<Playback, Command, void>(
    key: 'transport',
    policy: AccumulationPolicy.adjacent,
    merge: (accumulated, incoming) => incoming,
    (ctx, command) async {
      switch (command) {
        case Command.resume:
          await ctx.join(device.resume);
          ctx.emit(const Playing());
        case Command.pause:
          await ctx.join(device.pause);
          ctx.emit(const Paused());
      }
    },
  );

  Player(this.device) : super(const Paused());

  Job<void> resume() => _transport.add(Command.resume);

  Job<void> pause() => _transport.add(Command.pause);
}

/// Not on the page: [Player] with a job of another kind for a test to put
/// between two commands, and one that keeps the queue busy before them. A
/// subclass, because the page's class is final and this is its library.
final class BusyPlayer extends Player {
  final void Function(String what) note;

  BusyPlayer(super.device, this.note);

  Job<void> busy() => run<Playback, void>(
        key: 'busy',
        (ctx) => ctx.abandonable(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        ),
      );

  Job<void> chime() => run<Playback, void>(
        key: 'chime',
        (ctx) async => note('chime'),
      );
}

/// "When they are separate jobs after all": the page shows `resume`, and
/// the class around it, its mirror image `pause` and the two jobs of other
/// kinds are this file's.
final class Transport extends Solo<Playback> {
  final PlayerDevice device;

  Transport(this.device) : super(const Paused());

  Job<void> resume() {
    queue.removeWhere(
      (job) => job.key == Command.resume || job.key == Command.pause,
    );

    return run<Playback, void>(key: Command.resume, (ctx) async {
      await ctx.join(device.resume);
      ctx.emit(const Playing());
    });
  }

  /// Not on the page.
  Job<void> pause({bool cancellable = true}) => run<Playback, void>(
        key: Command.pause,
        cancellable: cancellable,
        (ctx) async {
          await ctx.join(device.pause);
          ctx.emit(const Paused());
        },
      );

  /// Not on the page: a job of another kind, 50 ms long.
  Job<void> chime() => run<Playback, void>(
        key: 'chime',
        (ctx) => ctx.join(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        ),
      );

  /// Not on the page: what the queue holds, by key.
  List<Object?> get queued => [for (final job in queue.jobs) job.key];

  /// Not on the page: the queue's own removal, with `force`.
  int removePauses({required bool force}) => queue.removeWhere(
        (job) => job.key == Command.pause,
        force: force,
      );
}

/// "Choosing where events join": the three lines of the page, and the two
/// handles they made.
List<Job<void>> threeCalls(SettingsController settings) {
  // Three calls in a row: the queue takes nothing between them. Where A2
  // lands is the policy's decision.
  final a1 = settings.update(const SettingsPatch(theme: 'dark'));
  settings.reload(); // B, an ordinary job of its own
  final a2 = settings.update(const SettingsPatch(language: 'ru'));

  return [a1, a2];
}

/// "Start, cancellation and errors": the block of the page, as written.
Future<void> oneHandle(LogController logs) async {
  final group = logs.logEvent(const LogEntry('checkout opened'));
  final same = logs.logEvent(const LogEntry('cart shown'));

  // Everyone who added to this group holds the same handle...
  print(identical(group, same));

  // ...so cancelling it cancels the whole group, and each of them reads the
  // same outcome.
  await group.cancel();
  switch (await same.done) {
    case Done():
      print('sent');
    case Failed(:final error):
      print('failed: $error');
    case Cancelled(:final reason):
      print('cancelled: $reason');
  }
}
