// What `accumulation_rakes_test.dart` puts under the code of
// `doc/accumulation.md`, and none of it is on the page: servers and a device
// that record what they were asked and when, and a controller for what the
// page says of the engine without showing code.
import 'package:solo/solo.dart';

import 'accumulation_page.dart';
import 'test_solo.dart';

/// Milliseconds of fake time since the test began; the test sets it.
int Function() now = () => 0;

Duration ms(int milliseconds) => Duration(milliseconds: milliseconds);

/// Answers [latency] ms after it is asked.
final class FakeSearchApi implements SearchApi {
  FakeSearchApi([this.latency = 100]);

  final int latency;
  final asked = <String>[];
  final askedAt = <int>[];

  /// Requests sent and not answered yet.
  int open = 0;

  @override
  Future<List<String>> search(String text) {
    asked.add(text);
    askedAt.add(now());
    open += 1;
    return Future<List<String>>.delayed(ms(latency), () {
      open -= 1;
      return ['hits for $text'];
    });
  }
}

String describe(Settings settings) =>
    'notifications: ${settings.notifications}, '
    'theme: ${settings.theme}, language: ${settings.language}';

/// Writes in [latency] ms. With [timeout] the future of `save` completes
/// that early, and the server goes on writing.
final class FakeSettingsApi implements SettingsApi {
  FakeSettingsApi({this.latency = 100, this.timeout});

  final int latency;
  final int? timeout;

  /// What `save` was called with, and when.
  final sent = <String>[];
  final sentAt = <int>[];

  /// What the server has finished writing, and when.
  final landedAt = <int>[];
  Settings stored =
      const Settings(notifications: false, theme: 'light', language: 'en');

  /// Writes the server has not finished.
  int writing = 0;
  int loads = 0;
  Object? failure;

  @override
  Future<void> save(Settings settings) {
    sent.add(describe(settings));
    sentAt.add(now());
    final failure = this.failure;
    if (failure != null) {
      return Future<void>.delayed(
        ms(latency),
        () => Error.throwWithStackTrace(failure, StackTrace.current),
      );
    }
    writing += 1;
    final written = Future<void>.delayed(ms(latency), () {
      writing -= 1;
      stored = settings;
      landedAt.add(now());
    });
    final timeout = this.timeout;

    return timeout == null ? written : Future<void>.delayed(ms(timeout));
  }

  @override
  Future<Settings> load() {
    loads += 1;
    return Future<Settings>.delayed(ms(latency), () => stored);
  }
}

/// Takes [latency] ms for a request.
final class FakeLogApi implements LogApi {
  FakeLogApi({this.latency = 100});

  final int latency;
  final sent = <List<String>>[];
  final sentAt = <int>[];

  /// The lists `send` was handed, as they were.
  final lists = <List<LogEntry>>[];
  Object? failure;

  @override
  Future<void> send(List<LogEntry> entries) {
    sent.add([for (final entry in entries) entry.message]);
    sentAt.add(now());
    lists.add(entries);
    final failure = this.failure;
    return Future<void>.delayed(ms(latency), () {
      if (failure != null) {
        Error.throwWithStackTrace(failure, StackTrace.current);
      }
    });
  }
}

/// A log entry a test can change after it was added.
class MutableEntry extends LogEntry {
  MutableEntry(this.text) : super('');

  String text;

  @override
  String get message => text;
}

/// A patch that counts the calls of its `merge`.
class CountingPatch extends SettingsPatch {
  CountingPatch(this.merged, {super.notifications});

  final List<String> merged;

  @override
  SettingsPatch merge(SettingsPatch incoming) {
    merged.add('merge at ${now()} ms');
    return super.merge(incoming);
  }
}

/// Takes [latency] ms to obey.
final class FakeDevice implements PlayerDevice {
  FakeDevice({this.latency = 100});

  final int latency;
  final heard = <String>[];

  /// A mark of the test for something that is not a command.
  void note(String what) => heard.add('$what at ${now()} ms');

  @override
  Future<void> resume() {
    note('resume');
    return Future<void>.delayed(ms(latency));
  }

  @override
  Future<void> pause() {
    note('pause');
    return Future<void>.delayed(ms(latency));
  }
}

/// The page's `Player` with the default policy in place of `adjacent`: "here
/// that would drop the `resume` the user tapped". A copy, the policy and the
/// two jobs of other kinds apart.
final class JoiningPlayer extends Solo<Playback> {
  final FakeDevice device;

  late final _transport = accumulate<Playback, Command, void>(
    key: 'transport',
    policy: AccumulationPolicy.join,
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

  JoiningPlayer(this.device) : super(const Paused());

  SoloJob<void> resume() => _transport.add(Command.resume);

  SoloJob<void> pause() => _transport.add(Command.pause);

  SoloJob<void> busy() => run<Playback, void>(
        key: 'busy',
        (ctx) => ctx.wait(() => Future<void>.delayed(ms(50))),
      );

  SoloJob<void> chime() => run<Playback, void>(
        key: 'chime',
        (ctx) async => device.note('chime'),
      );
}

/// The two commands as ordinary jobs under one of the queue's own
/// policies, with keys of their own or with one key for both.
/// "`Policy.replace` does not help" and "give both commands one key and
/// `Policy.restart`" are said of these.
final class KeyedPlayer extends Solo<Playback> {
  final PlayerDevice device;
  final Policy policy;
  final bool oneKey;

  KeyedPlayer(this.device, this.policy, {required this.oneKey})
      : super(const Paused());

  SoloJob<void> resume() => run<Playback, void>(
        key: oneKey ? 'transport' : Command.resume,
        policy: policy,
        (ctx) async {
          await ctx.join(device.resume);
          ctx.emit(const Playing());
        },
      );

  SoloJob<void> pause() => run<Playback, void>(
        key: oneKey ? 'transport' : Command.pause,
        policy: policy,
        (ctx) async {
          await ctx.join(device.pause);
          ctx.emit(const Paused());
        },
      );
}

/// A controller for what the page says of the engine: accumulators that
/// write down when their handlers started and with what, and ordinary jobs
/// that do the same.
final class Bench extends Solo<int> with OpenSolo<int> {
  Bench() : super(0);

  /// `name[events] at N ms` for a handler, `name at N ms` for a job.
  final ran = <String>[];

  /// A `collect` accumulator whose handler takes [work] ms.
  SoloAccumulator<String, void> collector(
    String name, {
    AccumulationPolicy policy = AccumulationPolicy.join,
    AccumulationTiming? timing,
    int work = 0,
    bool Function(int state)? canStart,
    bool cancellable = true,
    Object? key,
  }) =>
      collect<int, String, void>(
        (ctx, events) async {
          ran.add('$name$events at ${now()} ms');
          if (work > 0) {
            await ctx.join(() => Future<void>.delayed(ms(work)));
          }
        },
        key: key ?? name,
        policy: policy,
        timing: timing,
        canStart: canStart,
        cancellable: cancellable,
      );

  /// An ordinary job that takes [work] ms.
  SoloJob<void> busy(String name, int work, {Object? key}) => run<int, void>(
        key: key ?? name,
        (ctx) async {
          ran.add('$name at ${now()} ms');
          await ctx.join(() => Future<void>.delayed(ms(work)));
        },
      );

  /// The keys of the queued jobs, in order.
  List<Object?> get queued => [for (final job in queue.jobs) job.key];
}

/// A controller whose accumulators name no policy, so the engine's own
/// default decides: [Bench] cannot show it, because `OpenSolo` restates the
/// default in its own signature.
final class Defaults extends Solo<int> {
  Defaults() : super(0);

  late final SoloAccumulator<String, void> items = collect<int, String, void>(
    (ctx, events) async {},
    key: 'A',
  );

  late final SoloAccumulator<String, void> last = accumulate<int, String, void>(
    (ctx, value) async {},
    merge: (accumulated, incoming) => incoming,
    key: 'A',
  );

  SoloJob<void> busy(String name, int work) => run<int, void>(
        key: name,
        (ctx) => ctx.join(() => Future<void>.delayed(ms(work))),
      );

  /// The keys of the queued jobs, in order.
  List<Object?> get queued => [for (final job in queue.jobs) job.key];
}

/// A [Bench] that cancels the next job from `onStart`.
final class CancelsOnStart extends Solo<int> with OpenSolo<int> {
  CancelsOnStart() : super(0);

  final ran = <String>[];
  bool cancelNext = false;

  @override
  void onStart(Job<Object?> job) {
    if (cancelNext) {
      cancelNext = false;
      job.cancel().ignore();
    }
  }

  SoloAccumulator<String, void> collector(
    String name, {
    AccumulationTiming? timing,
  }) =>
      collect<int, String, void>(
        (ctx, events) async => ran.add('$name$events at ${now()} ms'),
        key: name,
        timing: timing,
      );
}

/// Adds to its own accumulator from `canStart` and from `onStart`.
final class AddsFromHooks extends Solo<int> {
  AddsFromHooks() : super(0);

  final ran = <String>[];
  var _added = 0;

  late final SoloAccumulator<String, void> items = collect<int, String, void>(
    (ctx, events) async => ran.add('$events'),
    key: 'items',
    canStart: (state) {
      if (_added == 0) {
        _added = 1;
        items.add('from canStart');
      }

      return true;
    },
  );

  @override
  void onStart(Job<Object?> job) {
    if (_added == 1) {
      _added = 2;
      items.add('from onStart');
    }
  }
}

sealed class Screen {
  const Screen();
}

final class Off extends Screen {
  const Off();
}

final class On extends Screen {
  const On(this.count);

  final int count;
}

/// An accumulator whose handler works on `On` alone.
final class Typed extends Solo<Screen> {
  Typed() : super(const Off());

  final ran = <String>[];

  late final SoloAccumulator<String, void> items = collect<On, String, void>(
    (ctx, events) async {
      ran.add('$events on ${ctx.state.count}');
      ctx.emit(On(ctx.state.count + events.length));
    },
  );

  SoloJob<void> turnOn() =>
      run<Screen, void>((ctx) async => ctx.emit(const On(0)));
}

/// Hears every start and finish.
final class Hears extends SoloObserver {
  final lines = <String>[];

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} started at ${now()} ms');

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} finished ${job.outcome} at ${now()} ms');
}
