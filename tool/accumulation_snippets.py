#!/usr/bin/env python3
"""Builds runnable scenarios from packages/solo/doc/accumulation.md.

Every snippet is copied byte-identical out of the markdown and wrapped in a
runnable file: fakes above it, a driver below it. That is what keeps the
document honest -- the code in it is the code that ran.

Usage, from the repository root:

    python3 tool/accumulation_snippets.py [workdir]

The default workdir is /tmp/solo-accumulation-check. It creates one package,
accumulation_check, with a path dependency on packages/solo. Then:

    dart pub get
    dart analyze bin/v
    dart run bin/v/settings.dart          # and so on

Timing is what this document is about, so every driver runs under FakeAsync:
a debounce of 200 ms and a throttle of a second are elapsed, not waited for.

What is not built here, and why: the document also carries sketches -- the
`collect`/`accumulate` pair in the opening tour, the timing pair and the
policy pair in the reference -- that name types the document never declares
(`Ready`, `Metric`, `sink`, `store`) or call methods no controller in it
has. They are not code that can run, and the restructure planned in
2026-09-13[13]-accumulation-restructure-plan.md replaces them with examples
that can.
"""
import os
import shutil
import sys

import doc_blocks

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = sys.argv[1] if len(sys.argv) > 1 else '/tmp/solo-accumulation-check'
DOC = os.path.join(REPO, 'packages', 'solo', 'doc', 'accumulation.md')

PUBSPEC = """name: accumulation_check
publish_to: none

environment:
  sdk: ^3.6.0

dependencies:
  solo:
    path: {solo}
  fake_async: ^1.3.1

dev_dependencies:
  lints: ^5.1.1
  test: ^1.25.15

# The bench must see the tree, not pub.dev: solo in the tree can depend on
# an async_job that is not released yet, and without this the snippets run
# against a different engine than the package they document.
dependency_overrides:
  async_job:
    path: {async_job}
""".format(
    solo=os.path.join(REPO, 'packages', 'solo'),
    async_job=os.path.join(REPO, 'packages', 'async_job'),
)

# A snippet is addressed by section and by a name it declares. The addressing
# lives in doc_blocks.py, next to this file, and is shared with the vs-bloc
# bench: `accumulation.md` has unnumbered headings, so its sections are keyed
# by a slug of the heading -- 'recipes/SettingsController'.
snips = doc_blocks.blocks(
    open(DOC).read(), 'dart', doc_blocks.DECLARES['dart'])

FAKE_ASYNC = "import 'package:fake_async/fake_async.dart';\n"
SOLO_IMPORT = "import 'package:solo/solo.dart';"


def with_fake_async(key, dart_async=False):
    """The snippet, with fake_async imported before solo as the lint wants."""
    head = FAKE_ASYNC + SOLO_IMPORT
    if dart_async:
        head = "import 'dart:async';\n\n" + head
    return snips[key].replace(SOLO_IMPORT, head)


REQUIRE = '''
void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
'''

SETTINGS_FAKE = '''
/// Records what reached the API and when, so a driver can count saves
/// instead of trusting the prose that there was only one.
class RecordingSettingsApi implements SettingsApi {
  final saved = <Settings>[];
  int loads = 0;
  Completer<Settings>? loading;

  @override
  Future<void> save(Settings settings) async {
    saved.add(settings);
  }

  @override
  Future<Settings> load() {
    loads += 1;
    return (loading = Completer<Settings>()).future;
  }
}

String describe(Settings settings) =>
    'notifications: ${settings.notifications}, '
    'theme: ${settings.theme}, language: ${settings.language}';

const start = Settings(
  notifications: false,
  theme: 'light',
  language: 'en',
);
'''

# The package's own rules with one taken off, and the reason on the spot.
# `one_member_abstracts` is about over-abstraction inside a library. A
# document's example declares "your API" as a one-method port on purpose --
# something the reader implements. Obeying the rule here would make
# SettingsApi a typedef and `_api.save(next)` a bare `_api(next)`, which
# tells the reader less than the interface does.
OPTIONS = """include: solo_rules.yaml

linter:
  rules:
    one_member_abstracts: false
"""

FILES = {}

# ------------------------------------------------------------------ settings
SETTINGS_FAKE = '''
/// Records what reached the API and when, so a driver can count writes
/// instead of trusting the prose that there was only one. The server takes
/// 100 ms to write, which is what the section's traces are measured against.
class RecordingSettingsApi implements SettingsApi {
  final saved = <Settings>[];
  int loads = 0;
  Completer<Settings>? loading;

  @override
  Future<void> save(Settings settings) {
    saved.add(settings);
    return Future<void>.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<Settings> load() {
    loads += 1;
    return (loading = Completer<Settings>()).future;
  }
}

String describe(Settings settings) =>
    'notifications: ${settings.notifications}, '
    'theme: ${settings.theme}, language: ${settings.language}';

const start = Settings(
  notifications: false,
  theme: 'light',
  language: 'en',
);
'''

# The second attempt is a method, and this is the class it belongs to: the
# first attempt's, with nothing else changed.
RESTARTING_SETTINGS = """
final class RestartingSettingsController extends Solo<Settings> {
  final SettingsApi _api;

  RestartingSettingsController(this._api, Settings initial) : super(initial);

""" + snips['recipes/update'].rstrip('\n') + """
}
"""

TIMING_OUT_FAKE = '''
/// A server that keeps writing after the client has given up: `save`
/// completes its future on a 100 ms timeout, and the write itself lands
/// when the server is done with it. The document's own controller cannot
/// tell the difference -- that is the point of the sentence it guards.
class TimingOutSettingsApi implements SettingsApi {
  int serverTakes = 100;
  int openWrites = 0;
  Settings? stored;

  @override
  Future<void> save(Settings settings) {
    openWrites += 1;
    Future<void>.delayed(Duration(milliseconds: serverTakes), () {
      stored = settings;
      openWrites -= 1;
    });
    return Future<void>.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<Settings> load() async => stored ?? start;
}
'''

SETTINGS_DRIVE = '''
/// The switch, then the theme, then the language, 20 ms apart. One scenario
/// for all three versions.
void drive(
  String name,
  RecordingSettingsApi api,
  SoloJob<void> Function(SettingsPatch) update,
  Settings Function() state,
) {
  fakeAsync((clock) {
    update(const SettingsPatch(notifications: true));
    clock.elapse(const Duration(milliseconds: 20));
    update(const SettingsPatch(theme: 'dark'));
    clock.elapse(const Duration(milliseconds: 20));
    update(const SettingsPatch(language: 'ru'));
    clock.elapse(const Duration(seconds: 2));

    final times = api.saved.length == 1 ? 'time' : 'times';
    print('== $name');
    print('the server was written to ${api.saved.length} $times:');
    for (final written in api.saved) {
      print('  ${describe(written)}');
    }
    print('the screen ends up with ${describe(state())}');
    print('');
  });
}
'''

FILES['settings'] = (
    with_fake_async('recipes/Settings', dart_async=True)
    + snips['recipes/EagerSettingsController']
    + RESTARTING_SETTINGS
    + snips['recipes/SettingsController']
    + snips['recipes/changeSettings']
    + SETTINGS_FAKE
    + TIMING_OUT_FAKE
    + REQUIRE
    + SETTINGS_DRIVE
    + '''
void main() {
  // Every change is a job, and every job writes: three round trips, and the
  // two in the middle publish settings the user never chose.
  final eagerApi = RecordingSettingsApi();
  final eager = EagerSettingsController(eagerApi, start);
  drive('a job per change', eagerApi, eager.update, () => eager.currentState);
  require(eagerApi.saved.length == 3, 'a write for every change');
  require(
    eagerApi.saved[1].theme == 'dark' && eagerApi.saved[1].language == 'en',
    'and the middle one is a state the user never asked for',
  );
  require(
    eager.currentState.notifications &&
        eager.currentState.theme == 'dark' &&
        eager.currentState.language == 'ru',
    'the screen is right at the end',
  );

  // Policy.restart: a job that replaces another overwrites it from a state
  // where that change never happened.
  final restartApi = RecordingSettingsApi();
  final restarting = RestartingSettingsController(restartApi, start);
  drive(
    'Policy.restart',
    restartApi,
    restarting.update,
    () => restarting.currentState,
  );
  require(restartApi.saved.length == 2, 'one write was cancelled before it');
  require(
    !restarting.currentState.notifications &&
        restarting.currentState.theme == 'light',
    'two of the three changes are gone, and nothing failed',
  );

  // The accumulator: merge combines the patches instead of choosing.
  final api = RecordingSettingsApi();
  final settings = SettingsController(api, start);
  drive('the accumulator', api, settings.update, () => settings.currentState);
  require(api.saved.length == 1, 'one group, one write');
  require(
    api.saved.single.notifications &&
        api.saved.single.theme == 'dark' &&
        api.saved.single.language == 'ru',
    'carrying all three changes',
  );

  // The timing of that one group, and the ordinary job beside it.
  fakeAsync((clock) {
    final api = RecordingSettingsApi();
    final controller = SettingsController(api, start);

    final first = controller.update(
      const SettingsPatch(notifications: true),
    );
    final second = controller.update(const SettingsPatch(theme: 'dark'));
    final third = controller.update(const SettingsPatch(language: 'ru'));

    require(identical(first, second), 'the second call joins the first group');
    require(identical(second, third), 'and so does the third');

    clock.elapse(const Duration(milliseconds: 199));
    require(api.saved.isEmpty, 'the debounce has not expired yet');
    require(
      describe(controller.currentState) == describe(start),
      'state holds its initial value until the handler runs',
    );

    clock.elapse(const Duration(milliseconds: 200));
    require(api.saved.length == 1, 'one group, one write');

    // The ordinary job of the same controller, the one the reference leans
    // on: it is not accumulated, and its state comes from the server.
    final reloading = controller.reload();
    clock.flushMicrotasks();
    require(api.loads == 1, 'reload reached the server');
    require(!reloading.isFinished, 'and is waiting for it');
    api.loading!.complete(
      const Settings(notifications: false, theme: 'server', language: 'en'),
    );
    clock.flushMicrotasks();
    require(controller.currentState.theme == 'server', 'reload emitted');

    controller.close();
    clock.flushMicrotasks();
  });

  // The recipe's note about the default, first half: a reload that got to
  // start is gone from the queue, and the next flip joins the group.
  fakeAsync((clock) {
    final api = RecordingSettingsApi();
    final controller = SettingsController(api, start);
    final first = controller.update(
      const SettingsPatch(notifications: true),
    );
    controller.reload();
    clock.flushMicrotasks();
    api.loading!.complete(start);
    clock.elapse(const Duration(milliseconds: 50));
    final second = controller.update(const SettingsPatch(theme: 'dark'));
    require(
      identical(first, second),
      'a reload that started leaves the waiting group at the tail',
    );
    clock.elapse(const Duration(seconds: 1));
    require(api.saved.length == 1, 'so the two flips are one write');
  });

  // The same two flips with the reload still queued behind the group.
  // Under `adjacent` that reload was a boundary and the flips were two
  // writes; under the default it is not, and the answer is the same as
  // above -- which is what makes the recipe's note a note and not a
  // condition on how busy the queue was.
  fakeAsync((clock) {
    final api = RecordingSettingsApi();
    // The reload starts at once and its load is left hanging, so it holds
    // the queue for everything added next.
    final controller = SettingsController(api, start)..reload();
    clock.flushMicrotasks();

    final first = controller.update(
      const SettingsPatch(notifications: true),
    );
    controller.reload(); // this one cannot start, and sits behind the group
    clock.elapse(const Duration(milliseconds: 50));
    final second = controller.update(const SettingsPatch(theme: 'dark'));
    require(
      identical(first, second),
      'a reload still queued does not end the group under join',
    );

    api.loading!.complete(start);
    clock.elapse(const Duration(seconds: 1));
    api.loading!.complete(start);
    clock.elapse(const Duration(seconds: 2));
    require(api.saved.length == 1, 'and the same two flips are one write');
  });

  // The sentence about a client timeout: `join` holds the slot only as far
  // as the future is honest about the write. This API completes on a
  // timeout, so the slot comes back while the server is still writing.
  fakeAsync((clock) {
    final api = TimingOutSettingsApi();
    final controller = SettingsController(api, start);

    api.serverTakes = 800; // the first write is slow on the server
    controller.update(const SettingsPatch(theme: 'dark'));
    clock.elapse(const Duration(milliseconds: 400));
    require(api.openWrites == 1, 'the first write is still going');

    api.serverTakes = 100; // the second one is quick
    controller.update(const SettingsPatch(theme: 'light'));
    // Its group starts at 600 ms and the write lands at 700; look between,
    // while the first write is still open on the server.
    clock.elapse(const Duration(milliseconds: 250));
    require(api.openWrites == 2, 'and the next one went out on top of it');

    clock.elapse(const Duration(seconds: 3));
    require(
      controller.currentState.theme == 'light',
      'the screen holds the last patch',
    );
    require(
      api.stored!.theme == 'dark',
      'and the server holds the older one, for good',
    );
  });

  // The document's own driver, verbatim.
  fakeAsync((clock) {
    final api = RecordingSettingsApi();
    unawaited(changeSettings(api, start));
    clock.elapse(const Duration(seconds: 1));
    require(api.saved.length == 1, 'the document promises a single write');
  });
}
''')

# ------------------------------------------------------------------ commands
# One driver for the whole section: the same three taps solved three ways, and
# a reader compares them by their traces.
PLAYER_FAKE = '''
/// Records what the device was told and when, so the driver counts commands
/// instead of trusting that only one arrived. 100 ms to obey is what the
/// section's traces are measured against. A driver that queues a job of
/// another kind between two commands marks it here too, so the order of
/// all three is one list.
class RecordingDevice implements PlayerDevice {
  final heard = <String>[];
  int Function() now = () => 0;
  Completer<void>? pausing;

  /// The bench's own mark for something that is not a command.
  void note(String what) => heard.add('$what at ${now()} ms');

  @override
  Future<void> resume() {
    heard.add('resume at ${now()} ms');
    return Future<void>.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<void> pause() {
    heard.add('pause at ${now()} ms');
    if (pausing != null) return pausing!.future;
    return Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
'''

# The section's second half: two ordinary jobs with keys of their own, and the
# controller's queue as what removes them. The snippet is a method, so the
# bench puts it in the controller it belongs to.
TRANSPORT = '''
/// The `resume` above, in the controller the section describes. `pause` is
/// its mirror image and is the bench's, not the document's.
final class Transport extends Solo<Playback> {
  final PlayerDevice device;

  Transport(this.device) : super(const Paused());

''' + snips['recipes/resume'].rstrip('\n') + '''

  SoloJob<void> pause() => run<Playback, void>(
        key: Command.pause,
        (ctx) async {
          await ctx.join(device.pause);
          ctx.emit(const Paused());
        },
      );

  /// An ordinary job of another kind, so the claim about where a re-added
  /// command lands has something to land behind. It takes 50 ms, which is
  /// how the driver sees which of the two went first. The bench's, not the
  /// document's.
  bool rang = false;

  SoloJob<void> chime() => run<Playback, void>(
        key: 'chime',
        (ctx) async {
          rang = true;
          await ctx.wait(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        },
      );
}
'''

# Two ordinary jobs of other kinds for the driver to put between two commands.
# `run` is protected, so they are operations of a controller: a subclass of
# the document's `Player`, allowed because the bench is one library.
BUSY_PLAYER = '''
/// [Player] with two ordinary jobs of other kinds, for the driver to put
/// between its commands. The bench's, not the document's.
final class BusyPlayer extends Player {
  final RecordingDevice recorder;

  BusyPlayer(this.recorder) : super(recorder);

  /// Holds the queue for 50 ms, long enough for what follows to be queued
  /// together.
  SoloJob<void> busy() => run<Playback, void>(
        key: 'busy',
        (ctx) => ctx.wait(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        ),
      );

  /// Marks its place in what the device heard.
  SoloJob<void> chime() => run<Playback, void>(
        key: 'chime',
        (ctx) async => recorder.note('chime'),
      );
}
'''

PLAYER_DRIVE = '''
/// Three taps in a row: resume, pause, resume. One scenario for both
/// versions of the button.
void drive(
  String name,
  RecordingDevice device,
  SoloJob<void> Function() resume,
  SoloJob<void> Function() pause,
  Playback Function() state,
) {
  fakeAsync((clock) {
    device.now = () => clock.elapsed.inMilliseconds;
    final first = resume();
    pause();
    final third = resume();

    var settled = -1;
    while (clock.elapsed.inMilliseconds < 800) {
      clock.elapse(const Duration(milliseconds: 25));
      if (settled < 0 && first.isFinished && third.isFinished) {
        settled = clock.elapsed.inMilliseconds;
      }
    }

    print('== $name');
    print('the device heard ${device.heard.length} '
        '${device.heard.length == 1 ? 'command' : 'commands'}:');
    for (final command in device.heard) {
      print('  $command');
    }
    print('the button gave back '
        '${identical(first, third) ? 'one job' : 'a job for every tap'}');
    print('the player settles ${state().runtimeType} at $settled ms');
    print('');
  });
}
'''

FILES['commands'] = (
    with_fake_async('recipes/Command', dart_async=True)
    + snips['recipes/QueuedPlayer']
    + snips['recipes/Player']
    + PLAYER_FAKE
    + TRANSPORT
    + BUSY_PLAYER
    + REQUIRE
    + PLAYER_DRIVE
    + '''
void main() {
  // A job per command: the device is told everything the user tapped, and
  // the stop in the middle is something they hear.
  final queuedDevice = RecordingDevice();
  final queued = QueuedPlayer(queuedDevice);
  drive(
    'a job per command',
    queuedDevice,
    queued.resume,
    queued.pause,
    () => queued.currentState,
  );
  require(queuedDevice.heard.length == 3, 'the device hears every tap');
  require(
    queuedDevice.heard[1].startsWith('pause'),
    'including the stop nobody wanted',
  );
  require(queued.currentState is Playing, 'and it does end up playing');

  // The accumulator: one command, because the merge kept the last one and
  // no job was ever created for the others.
  final device = RecordingDevice();
  final player = Player(device);
  drive(
    'the accumulator',
    device,
    player.resume,
    player.pause,
    () => player.currentState,
  );
  require(device.heard.length == 1, 'the device hears one command');
  require(device.heard.single.startsWith('resume'), 'and it is the last one');
  require(player.currentState is Playing, 'the state follows the device');

  // Where the recipe's rule draws its boundary: a job of another kind
  // between two commands. Under a rule that joined across it the device
  // would hear the pause alone, and the resume the user tapped would never
  // reach it. The busy job is what keeps all three queued long enough for
  // the order to show.
  fakeAsync((clock) {
    final device = RecordingDevice();
    final player = BusyPlayer(device);
    device.now = () => clock.elapsed.inMilliseconds;
    player
      ..busy()
      ..resume()
      ..chime()
      ..pause();
    clock.elapse(const Duration(seconds: 1));

    print('== a job of another kind between two commands');
    print('the device heard ${device.heard}');
    print('');
    require(device.heard.length == 3, 'three things happened, not two');
    require(
      device.heard[0].startsWith('resume'),
      'the resume the user tapped reaches the device',
    );
    require(
      device.heard[1].startsWith('chime'),
      'the job between the commands runs between them',
    );
    require(device.heard[2].startsWith('pause'), 'and the pause follows it');
    require(player.currentState is Paused, 'the player ends up stopped');
    player.close();
    clock.flushMicrotasks();
  });

  // Which of the two the merge keeps. Three alternating taps start and end
  // on the same command, so they cannot tell `incoming` from `accumulated`;
  // two taps can.
  fakeAsync((clock) {
    final device = RecordingDevice();
    final player = Player(device)
      ..resume()
      ..pause();
    clock.elapse(const Duration(milliseconds: 300));
    require(device.heard.length == 1, 'still one command for two taps');
    require(
      device.heard.single.startsWith('pause'),
      'and merge keeps the incoming one, not the one it had',
    );
    require(player.currentState is Paused, 'the player ends up stopped');
    player.close();
    clock.flushMicrotasks();
  });

  // The sentence about what removing and adding gives: the shape of
  // `replace`, with the re-added command at the tail behind whatever was
  // queued between. The held pause is what keeps them queued to see it.
  fakeAsync((clock) {
    final device = RecordingDevice()..pausing = Completer<void>();
    final transport = Transport(device)..pause();
    clock.flushMicrotasks();

    transport
      ..resume() // queued behind the running pause
      ..chime() // and this behind the resume
      ..resume(); // removes the queued resume, appends a new one

    device.pausing!.complete();
    clock.elapse(const Duration(milliseconds: 10));
    require(transport.rang, 'the job queued between the two runs first');
    require(
      device.heard.length == 1,
      'and the re-added command has not, because it went to the tail '
      'instead of keeping the place the removed one had',
    );

    clock.elapse(const Duration(seconds: 2));
    require(device.heard.length == 2, 'it runs after that job, not before');
    require(device.heard.last.startsWith('resume'), 'and it is the resume');
  });

  // Two operations of their own, with a device that holds the pause: the
  // queue never touches the running job, so a pause that has already started
  // runs to its end whatever is removed behind it.
  fakeAsync((clock) {
    final device = RecordingDevice()..pausing = Completer<void>();
    final transport = Transport(device);

    final pausing = transport.pause();
    clock.flushMicrotasks();
    require(device.heard.length == 1, 'the pause is running');
    require(!pausing.isFinished, 'and it is waiting for the device');

    final resuming = transport.resume();
    clock.flushMicrotasks();
    require(!pausing.isFinished, 'removeWhere did not touch the running job');
    require(device.heard.length == 1, 'the resume waits its turn');

    device.pausing!.complete();
    clock.elapse(const Duration(milliseconds: 300));
    require(pausing.outcome is Done, 'the pause ran to its end');
    require(device.heard.length == 2, 'and only then the resume started');
    require(resuming.outcome is Done, 'the resume finished too');
    require(transport.currentState is Playing, 'ending where resume leaves it');

    print('== separate jobs, with a pause already running');
    print('the device heard ${device.heard}');
    print('pause ${pausing.outcome}, resume ${resuming.outcome}, '
        'state ${transport.currentState.runtimeType}');

    transport.close();
    clock.flushMicrotasks();
  });
}
''')

# ---------------------------------------------------------------------- logs
LOG_FAKE = '''
/// Records every batch and how long the server took, so a driver counts
/// requests instead of trusting that there was one. 100 ms per request is
/// what the section's traces are measured against.
class MutableEntry extends LogEntry {
  MutableEntry(this.text) : super('');

  String text;

  @override
  String get message => text;
}

class RecordingLogApi implements LogApi {
  final sent = <List<String>>[];

  @override
  Future<void> send(List<LogEntry> entries) {
    sent.add([for (final entry in entries) entry.message]);
    return Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
'''

LOG_DRIVE = '''
/// Three lines written while one screen transition is handled, then one more
/// half a second later. One scenario for both versions.
int drive(
  String name,
  RecordingLogApi api,
  SoloJob<void> Function(LogEntry) log,
  int Function() counter,
) {
  var burst = 0;
  fakeAsync((clock) {
    for (final message in ['opened', 'loaded', 'shown']) {
      log(LogEntry(message));
    }
    clock.elapse(const Duration(milliseconds: 500));
    burst = api.sent.length;
    log(const LogEntry('tapped'));
    clock.elapse(const Duration(seconds: 3));

    final requests = api.sent.length == 1 ? 'request' : 'requests';
    print('== $name');
    print('the server got ${api.sent.length} $requests:');
    for (final batch in api.sent) {
      print('  $batch');
    }
    print('the three lines of the transition cost $burst of them');
    print('the counter says ${counter()}');
    print('');
  });
  return burst;
}
'''

# The reference's second throttle mode, on the recipe's own controller: one
# changed argument, plus a gate the driver can close, because the sentence
# about a refused start has to have something to refuse. The gate is the
# bench's, and it is open unless a driver shuts it.
LOG_CONTROLLER = snips['recipes/LogController']


def with_trailing(name):
    body = (LOG_CONTROLLER
            .replace('class LogController extends Solo<int> {',
                     f'final class {name} extends Solo<int> {{')
            .replace('LogController(this._api)', f'{name}(this._api)')
            .replace('  final LogApi _api;\n',
                     '  final LogApi _api;\n  bool allowed = true;\n')
            .replace(
                '    timing: AccumulationTiming.throttle('
                'const Duration(seconds: 1)),\n',
                '    canStart: (state) => allowed,\n'
                '    timing: AccumulationTiming.throttle(\n'
                '      const Duration(seconds: 1),\n'
                '      startAtOnce: false,\n'
                '    ),\n'))
    assert f'final class {name} ' in body, name
    assert 'startAtOnce: false' in body, 'the mode has to be in the class'
    assert 'canStart: (state) => allowed' in body, 'and the gate with it'
    assert 'throttle(const' not in body, 'the old throttle has to be gone'
    return body


FILES['logs'] = (
    with_fake_async('recipes/LogEntry', dart_async=True)
    + snips['recipes/EagerLogController']
    + snips['recipes/LogController']
    + with_trailing('TrailingLogController')
    + LOG_FAKE
    + REQUIRE
    + LOG_DRIVE
    + '''
void main() {
  // Every line is a job, and every job sends: four lines, four round trips,
  // and the queue is what makes each one wait for the last.
  final eagerApi = RecordingLogApi();
  final eager = EagerLogController(eagerApi);
  final eagerBurst = drive(
    'a request per entry',
    eagerApi,
    eager.logEvent,
    () => eager.currentState,
  );
  require(eagerApi.sent.length == 4, 'a request for every line');
  require(eagerBurst == 3, 'three of them for one screen transition');
  require(
    eagerApi.sent.every((batch) => batch.length == 1),
    'and every request carries a single entry',
  );

  // collect: the three lines of the transition travel together, and the
  // fourth goes on its own because the interval had already passed.
  final api = RecordingLogApi();
  final logs = LogController(api);
  final burst = drive(
    'collect with throttle',
    api,
    logs.logEvent,
    () => logs.currentState,
  );
  require(burst == 1, 'one request for the whole transition');
  require(api.sent.first.length == 3, 'carrying all three lines');
  require(api.sent.first.first == 'opened', 'in the order they were written');
  require(api.sent.last.single == 'tapped', 'the fourth went on its own');
  require(logs.currentState == 4, 'the counter saw every entry');

  // What starting at once costs an idle accumulator. The same four entries
  // written in one synchronous turn, and then with a single microtask
  // between the first and the rest.
  fakeAsync((clock) {
    final api = RecordingLogApi();
    final logs = LogController(api);
    for (var i = 0; i < 4; i += 1) {
      logs.logEvent(LogEntry('e$i'));
    }
    clock.elapse(const Duration(seconds: 5));
    require(api.sent.length == 1, 'one synchronous turn is one request');
    require(api.sent.single.length == 4, 'carrying every entry');
  });

  fakeAsync((clock) {
    final api = RecordingLogApi();
    final logs = LogController(api)..logEvent(const LogEntry('e0'));
    clock.flushMicrotasks(); // no time passes, only a turn of the loop
    for (var i = 1; i < 4; i += 1) {
      logs.logEvent(LogEntry('e$i'));
    }
    clock.elapse(const Duration(milliseconds: 500));
    require(api.sent.length == 1, 'nothing else has been sent yet');
    require(api.sent.first.length == 1, 'the first entry went on its own');
    require(api.sent.first.single == 'e0', 'and it is the first one');

    clock.elapse(const Duration(seconds: 5));
    require(api.sent.length == 2, 'and the rest waited out the interval');
    require(api.sent.last.length == 3, 'then went together');
  });

  // The sentence under the heading: the snapshot copies the list, not the
  // entries in it. An entry changed while its group waits is sent changed.
  fakeAsync((clock) {
    final api = RecordingLogApi();
    final logs = LogController(api)..logEvent(const LogEntry('opened'));
    clock.elapse(const Duration(milliseconds: 10));

    // This group waits out the throttle interval, and the entry it carries
    // is changed while it waits.
    final entry = MutableEntry('loaded');
    logs.logEvent(entry);
    clock.elapse(const Duration(milliseconds: 10));
    entry.text = 'changed after add';
    clock.elapse(const Duration(seconds: 3));

    require(api.sent.length == 2, 'the second entry went in its own batch');
    require(
      api.sent.last.single == 'changed after add',
      'and it was sent as it was changed, not as it was added',
    );
  });

  // The table's second throttle mode: `startAtOnce: false` counts the
  // interval before the first group too, and an addition inside it still
  // does not extend it.
  fakeAsync((clock) {
    final api = RecordingLogApi();
    final logs = TrailingLogController(api);
    for (final message in ['opened', 'loaded', 'shown']) {
      logs.logEvent(LogEntry(message));
    }
    clock.elapse(const Duration(milliseconds: 500));
    require(api.sent.isEmpty, 'the first group waits out the interval too');

    logs.logEvent(const LogEntry('tapped'));
    clock.elapse(const Duration(milliseconds: 499));
    require(api.sent.isEmpty, 'and the addition did not extend it');
    clock.elapse(const Duration(milliseconds: 1));
    require(api.sent.length == 1, 'the interval ended and the group went');
    require(api.sent.single.length == 4, 'carrying everything written in it');

    print('== the journal recipe with startAtOnce: false');
    print('the server got 1 request: ${api.sent.single}');
    print('');
    logs.close();
    clock.flushMicrotasks();
  });

  // What waiting costs: a single entry on an idle accumulator waits the
  // whole interval, and a draining close has to wait with it.
  fakeAsync((clock) {
    final api = RecordingLogApi();
    final logs = TrailingLogController(api)
      ..logEvent(const LogEntry('alone'));
    var closed = false;
    unawaited(
      logs.close(mode: SoloCloseMode.drain).then((_) => closed = true),
    );
    clock.elapse(const Duration(milliseconds: 999));
    require(api.sent.isEmpty, 'one entry waits the whole interval');
    require(!closed, 'and the close waits with it');

    clock.elapse(const Duration(milliseconds: 1));
    require(api.sent.single.single == 'alone', 'then the entry is sent');
    require(!closed, 'the close still waits for the request it started');

    clock.elapse(const Duration(milliseconds: 100));
    require(closed, 'and is over when the request comes back');
  });

  // The sentence about start rules, in this mode: a refused group spends no
  // interval, and the next one counts its own from where it appears.
  fakeAsync((clock) {
    final api = RecordingLogApi();
    final logs = TrailingLogController(api)
      ..allowed = false
      ..logEvent(const LogEntry('refused'));
    clock.elapse(const Duration(seconds: 1));
    require(api.sent.isEmpty, 'the refused group sent nothing');

    clock.elapse(const Duration(milliseconds: 100));
    logs
      ..allowed = true
      ..logEvent(const LogEntry('next'));
    clock.elapse(const Duration(milliseconds: 999));
    require(api.sent.isEmpty, 'the next group counts its own full interval');
    clock.elapse(const Duration(milliseconds: 1));
    require(api.sent.single.single == 'next', 'and goes when it ends');

    logs.close();
    clock.flushMicrotasks();
  });

  // The throttle is a floor under the rate: entries written inside the
  // interval wait for it, and are sent together when it ends.
  fakeAsync((clock) {
    final api = RecordingLogApi();
    final logs = LogController(api)
      ..logEvent(const LogEntry('one'))
      ..logEvent(const LogEntry('two'))
      ..logEvent(const LogEntry('three'));

    clock.flushMicrotasks();
    require(api.sent.length == 1, 'three calls, one request');
    require(api.sent.single.length == 3, 'and it carries all three entries');

    logs.logEvent(const LogEntry('four'));
    clock.elapse(const Duration(milliseconds: 999));
    require(api.sent.length == 1, 'the throttle interval is not over');

    clock.elapse(const Duration(milliseconds: 200));
    require(api.sent.length == 2, 'the interval ended and the group went');
    require(api.sent.last.single == 'four', 'carrying what arrived inside it');
    require(logs.currentState == 4, 'and the count grew by one');

    logs.close();
    clock.flushMicrotasks();
  });
}
''')

# -------------------------------------------------------------------- search
# The document calls SearchState and SearchApi application types and declares
# neither; a bench cannot leave them undeclared. The API answers 100 ms after
# it is asked, which is what the section's traces are measured against.
SEARCH_TYPES = """import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';

class SearchState {
  final List<String> results;

  const SearchState.idle() : results = const [];

  const SearchState.results(this.results);
}

class SearchApi {
  SearchApi([this.latency = 100]);

  final int latency;
  final asked = <String>[];

  /// Requests sent and not answered yet: what a cancelled job leaves behind
  /// is invisible in [asked] alone.
  int open = 0;

  Future<List<String>> search(String text) {
    asked.add(text);
    open += 1;
    return Future<List<String>>.delayed(
      Duration(milliseconds: latency),
      () {
        open -= 1;
        return ['hits for $text'];
      },
    );
  }
}

"""

# The second attempt is a method, and this is the class it belongs to: the
# first attempt's, with nothing else changed. That is what the document says,
# and grafting it here is how the bench holds it to that.
RESTARTING = """
final class RestartingSearch extends Solo<SearchState> {
  final SearchApi api;

  RestartingSearch(this.api) : super(const SearchState.idle());

""" + snips['recipes/query'].rstrip('\n') + """
}
"""

# The second attempt's own method with the waiting swapped: the sentence about
# `ctx.join` is measured, not reasoned about. Deriving it from the document's
# block means it cannot drift away from the attempt it talks about.
JOINED = snips['recipes/query'].replace('ctx.wait', 'ctx.join')
assert JOINED != snips['recipes/query'], 'the second attempt must use ctx.wait'
assert JOINED.count('ctx.join') == 1, 'one call to swap, no more'

JOINING = """
final class JoiningSearch extends Solo<SearchState> {
  final SearchApi api;

  JoiningSearch(this.api) : super(const SearchState.idle());

""" + JOINED.rstrip('\n') + """
}
"""

# Same scenario as drive, reported as numbers instead of prose: how many
# requests reached the server, and when the last screen appeared.
PROBE = """
(int, int) probeWait(SearchApi api) {
  final search = RestartingSearch(api);
  return probe(api, search.query, () => search.currentState.results);
}

(int, int) probeJoin(SearchApi api) {
  final search = JoiningSearch(api);
  return probe(api, search.query, () => search.currentState.results);
}

(int, int) probe(
  SearchApi api,
  SoloJob<void> Function(String) query,
  List<String> Function() state,
) {
  var settled = 0;
  fakeAsync((clock) {
    var now = 0;
    var last = state().toString();
    void step(int ms) {
      clock.elapse(Duration(milliseconds: ms));
      now += ms;
      final current = state().toString();
      if (current != last) {
        settled = now;
        last = current;
      }
    }

    for (final text in ['s', 'so', 'sol', 'solo']) {
      query(text);
      step(50);
    }
    while (now < 1500) {
      step(25);
    }
  });
  return (api.asked.length, settled);
}
"""

DRIVE = """
/// Types `solo`, one character every 50 ms, and reports every state the
/// screen passes through. One scenario for all three versions.
int drive(
  String name,
  SearchApi api,
  SoloJob<void> Function(String) query,
  List<String> Function() state,
) {
  final shown = <String>[];
  fakeAsync((clock) {
    var now = 0;
    var last = state().toString();
    void step(int ms) {
      clock.elapse(Duration(milliseconds: ms));
      now += ms;
      final current = state().toString();
      if (current != last) {
        shown.add('at $now ms the screen shows $current');
        last = current;
      }
    }

    for (final text in ['s', 'so', 'sol', 'solo']) {
      query(text);
      step(50);
    }
    while (now < 900) {
      step(25);
    }
  });
  final times = api.asked.length == 1 ? 'time' : 'times';
  print('== $name');
  print('the server was asked ${api.asked.length} $times: ${api.asked}');
  shown.forEach(print);
  print('');
  require(
    state().length == 1 && state().single == 'hits for solo',
    'every version ends up showing the answer to the last keystroke',
  );
  return shown.length;
}
"""

FILES['search'] = (
    SEARCH_TYPES
    + snips['recipes/QueuedSearch']
    + RESTARTING
    + JOINING
    + snips['recipes/Search']
    + REQUIRE
    + DRIVE
    + PROBE
    + """
void main() {
  final first = SearchApi();
  final queued = QueuedSearch(first);
  final queuedScreens = drive(
    'a job per keystroke',
    first,
    queued.query,
    () => queued.currentState.results,
  );
  require(first.asked.length == 4, 'a request for every keystroke');
  require(queuedScreens == 4, 'and a screen for every answer on the way');

  final second = SearchApi();
  final restarting = RestartingSearch(second);
  final restartedScreens = drive(
    'Policy.restart',
    second,
    restarting.query,
    () => restarting.currentState.results,
  );
  require(second.asked.length == 4, 'restart cancels jobs, not requests');
  require(restartedScreens == 1, 'but only the last answer reaches the screen');

  final third = SearchApi();
  final search = Search(third);
  final debouncedScreens = drive(
    'accumulate with debounce',
    third,
    search.query,
    () => search.currentState.results,
  );
  require(third.asked.length == 1, 'one group, one request');
  require(debouncedScreens == 1, 'and one screen, the answer to `solo`');

  // The sentence about `ctx.join`: it sends fewer requests than `ctx.wait`
  // against this server and answers later, and the saving is the held slot
  // rather than a property -- against a server faster than the typing it
  // saves nothing at all.
  final waited = probeWait(SearchApi());
  final joined = probeJoin(SearchApi());
  require(
    waited.$1 == 4 && joined.$1 < waited.$1,
    'ctx.join lets fewer requests out than ctx.wait against this server',
  );
  require(joined.$2 > waited.$2, 'and the answer arrives later for it');
  require(
    probeJoin(SearchApi(40)).$1 == probeWait(SearchApi(40)).$1,
    'against a server faster than the typing it saves nothing',
  );

  // "Continuous input can keep an open group waiting indefinitely": typing
  // that never pauses for the window never sends anything, and the request
  // goes out only when it stops. The document's own 300 ms debounce.
  fakeAsync((clock) {
    final api = SearchApi();
    final search = Search(api);
    for (var tap = 0; tap < 50; tap += 1) {
      search.query('q$tap');
      clock.elapse(const Duration(milliseconds: 200));
    }
    require(
      api.asked.isEmpty,
      'ten seconds of typing without a 300 ms pause asked nothing',
    );

    clock.elapse(const Duration(milliseconds: 400));
    require(api.asked.length == 1, 'the pause is what sends it');
    require(api.asked.single == 'q49', 'and it carries the last keystroke');
  });

  // The sentence under the accumulator: what finishes before the next group
  // starts is the job, and a cancelled one leaves its request running.
  fakeAsync((clock) {
    final api = SearchApi(1000);
    final search = Search(api);
    final first = search.query('solo');
    clock.elapse(const Duration(milliseconds: 400));
    require(api.open == 1, 'the group started and its request is on its way');

    unawaited(first.cancel());
    clock.elapse(const Duration(milliseconds: 10));
    require(first.isFinished, 'the job is over');
    require(api.open == 1, 'and the request it sent is not');

    search.query('dart');
    clock.elapse(const Duration(milliseconds: 400));
    require(api.open == 2, 'so the next group sends while the first is open');

    clock.elapse(const Duration(seconds: 3));
    require(api.open == 0, 'both answers arrive in the end');
  });
}
""")

# ------------------------------------------------------------------ policies
# The reference's own three lines, run as written, and then the table they
# belong to: all three rows, on three controllers made out of the document's
# own by changing exactly two things -- the policy, and no debounce, because
# a waiting group is about readiness and the table is about position.
CONTROLLER = snips['recipes/SettingsController']


def with_policy(name, policy):
    body = (CONTROLLER
            .replace('class SettingsController extends Solo<Settings> {',
                     f'final class {name} extends Solo<Settings> {{')
            .replace('SettingsController(this._api, Settings initial)',
                     f'{name}(this._api, Settings initial)')
            .replace(
                "    timing: AccumulationTiming.debounce("
                "const Duration(milliseconds: 200)),\n",
                f'    policy: AccumulationPolicy.{policy},\n'))
    assert f'class {name} ' in body, name
    assert f'AccumulationPolicy.{policy}' in body, policy
    assert 'AccumulationTiming' not in body, 'the debounce has to be gone'
    return body


ORDERED_FAKE = '''
/// Records what reached the server and in which order. Both calls take
/// 100 ms, so nothing is ready ahead of its turn for a reason of its own.
class OrderedSettingsApi implements SettingsApi {
  final order = <String>[];

  @override
  Future<void> save(Settings settings) {
    order.add('save ${settings.theme}/${settings.language}');
    return Future<void>.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<Settings> load() {
    order.add('load');
    return Future<Settings>.delayed(
      const Duration(milliseconds: 100),
      () => start,
    );
  }
}

/// A1, then B, then A2, with the queue already occupied by a job of its own.
/// The same three additions for every row of the table.
List<Object?> threeAdditions(
  OrderedSettingsApi api,
  SoloJob<void> Function() reload,
  SoloJob<void> Function(SettingsPatch) update,
) {
  final busy = reload();
  final a1 = update(const SettingsPatch(theme: 'dark'));
  reload();
  final a2 = update(const SettingsPatch(language: 'ru'));
  return [busy, a1, a2];
}
'''

FILES['policies'] = (
    with_fake_async('recipes/Settings', dart_async=True)
    + snips['recipes/SettingsController']
    + with_policy('AdjacentSettingsController', 'adjacent')
    + with_policy('JoiningSettingsController', 'join')
    + with_policy('ReplacingSettingsController', 'replace')
    + SETTINGS_FAKE
    + ORDERED_FAKE
    + """
void threeCalls(SettingsController settings) {
"""
    + snips['reference/all-three-while-the-current-jo'].rstrip('\n')
    + """
  require(identical(a1, a2), "join: A2 is A1's own job, joined where it is");
}
"""
    + REQUIRE
    + '''
void main() {
  // The reference's three lines, exactly as it prints them, against a
  // controller whose queue is already occupied.
  fakeAsync((clock) {
    final api = RecordingSettingsApi();
    final settings = SettingsController(api, start);

    final busy = settings.reload();
    clock.flushMicrotasks();
    require(!busy.isFinished, 'the first reload holds the queue');

    threeCalls(settings);

    api.loading!.complete(start);
    clock.flushMicrotasks();
    require(busy.outcome is Done, 'the job that held the queue finished');
    require(api.loads == 2, 'B, the second reload, took the slot next');
    api.loading!.complete(start);
    clock.elapse(const Duration(seconds: 1));

    require(api.saved.length == 1, 'one group, one write');
    require(
      api.saved.single.theme == 'dark' && api.saved.single.language == 'ru',
      'carrying what A1 and A2 each put in',
    );
    print("the reference's three lines: loads ${api.loads}, "
        'writes ${api.saved.length} '
        '(${api.saved.single.theme} and ${api.saved.single.language} '
        'together), '
        'state ${describe(settings.currentState)}');
    print('');

    settings.close();
    clock.flushMicrotasks();
  });

  // The table, row by row. What the queue holds is not readable from
  // outside, so what is checked is what it does: the order the server is
  // called in, and the handle A2 came back with.
  print('| policy | the server is called | handle for A2 |');

  // adjacent: [A1, B, A2] -- A1 writes, B loads, A2 writes.
  fakeAsync((clock) {
    final api = OrderedSettingsApi();
    final settings = AdjacentSettingsController(api, start);
    final handles =
        threeAdditions(api, settings.reload, settings.update);
    final a1 = handles[1]! as SoloJob<void>;
    final a2 = handles[2]! as SoloJob<void>;
    clock.elapse(const Duration(seconds: 2));

    require(
      api.order.join(', ') == 'load, save dark/en, load, save light/ru',
      'adjacent: A1 writes, B loads between them, A2 writes -- and A2 builds '
          'on what B left, which is why the theme is back to light',
    );
    require(!identical(a1, a2), 'adjacent: A2 is a new job');
    print('| adjacent | ${api.order.join(', ')} | a new job |');

    settings.close();
    clock.flushMicrotasks();
  });

  // join: [A(A1 + A2), B] -- one write, ahead of B, and A2 is A1's job.
  fakeAsync((clock) {
    final api = OrderedSettingsApi();
    final settings = JoiningSettingsController(api, start);
    final handles =
        threeAdditions(api, settings.reload, settings.update);
    final a1 = handles[1]! as SoloJob<void>;
    final a2 = handles[2]! as SoloJob<void>;
    clock.elapse(const Duration(seconds: 2));

    require(
      api.order.join(', ') == 'load, save dark/ru, load',
      'join: one write, carrying both, and it keeps its place before B',
    );
    require(identical(a1, a2), "join: A2 is A1's existing job");
    print("| join | ${api.order.join(', ')} | A1's existing job |");

    settings.close();
    clock.flushMicrotasks();
  });

  // replace: [B, A(A1 + A2)] -- one write, behind B, on the same job.
  fakeAsync((clock) {
    final api = OrderedSettingsApi();
    final settings = ReplacingSettingsController(api, start);
    final handles =
        threeAdditions(api, settings.reload, settings.update);
    final a1 = handles[1]! as SoloJob<void>;
    final a2 = handles[2]! as SoloJob<void>;
    clock.elapse(const Duration(seconds: 2));

    require(
      api.order.join(', ') == 'load, load, save dark/ru',
      'replace: one write, carrying both, moved behind B',
    );
    require(identical(a1, a2), "replace: A2 is A1's job, moved");
    require(a1.outcome is Done, 'and the caller of A1 is told it was done');
    print("| replace | ${api.order.join(', ')} | "
        "A1's existing job, moved behind B |");

    settings.close();
    clock.flushMicrotasks();
  });
}
''')

for key, body in FILES.items():
    d = f'{ROOT}/accumulation_check/bin/v'
    os.makedirs(d, exist_ok=True)
    open(f'{d}/{key}.dart', 'w').write(body)

open(f'{ROOT}/accumulation_check/pubspec.yaml', 'w').write(PUBSPEC)
shutil.copyfile(
    os.path.join(REPO, 'packages', 'solo', 'analysis_options.yaml'),
    f'{ROOT}/accumulation_check/solo_rules.yaml',
)
open(f'{ROOT}/accumulation_check/analysis_options.yaml', 'w').write(OPTIONS)
print('wrote', len(FILES), 'files under', ROOT)
