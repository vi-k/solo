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
FILES['settings'] = (
    with_fake_async('recipes/Settings', dart_async=True)
    + SETTINGS_FAKE
    + snips['recipes/changeSettings']
    + REQUIRE
    + '''
void main() {
  // What the document says: three calls share one job, its handler saves one
  // snapshot with all three changes, and state still holds its initial value
  // until the handler runs.
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
    require(api.saved.isEmpty, 'debounce has not expired yet');
    require(
      describe(controller.currentState) == describe(start),
      'state holds its initial value until the handler runs',
    );
    print('at 199 ms: saves ${api.saved.length}, '
        'state ${describe(controller.currentState)}');

    clock.elapse(const Duration(milliseconds: 200));
    require(api.saved.length == 1, 'one group, one save');
    require(
      describe(api.saved.single) ==
          'notifications: true, theme: dark, language: ru',
      'merge keeps a field from each of the three patches',
    );
    print('at 399 ms: saves ${api.saved.length}, '
        'state ${describe(controller.currentState)}');
    print('one handle for three calls: ${identical(first, third)}');
    print('outcome ${first.outcome}');

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
    print('after reload: state ${describe(controller.currentState)}');

    controller.close();
    clock.flushMicrotasks();
  });

  // The document's own driver, verbatim. Three outcomes are printed for what
  // the prose calls one job, and all three are the same.
  fakeAsync((clock) {
    final api = RecordingSettingsApi();
    unawaited(changeSettings(api, start));
    clock.elapse(const Duration(seconds: 1));
    require(api.saved.length == 1, 'the document promises a single save');
    print('the API was called ${api.saved.length} time with '
        '${describe(api.saved.single)}');
  });
}
''')

# ------------------------------------------------------------------ commands
# One driver for the whole section: its two halves are the same three
# commands solved twice, and a reader compares them by their traces.
PLAYER_FAKE = '''
/// Records what the device was actually told to do, so the driver counts
/// commands instead of trusting that only one arrived.
class RecordingDevice implements PlayerDevice {
  final calls = <String>[];
  Completer<void>? pausing;

  @override
  Future<void> resume() async {
    calls.add('resume');
  }

  @override
  Future<void> pause() {
    calls.add('pause');
    return (pausing = Completer<void>()).future;
  }
}
'''

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
}
'''

FILES['commands'] = (
    with_fake_async('recipes/Player', dart_async=True)
    + PLAYER_FAKE
    + TRANSPORT
    + REQUIRE
    + '''
void main() {
  // One command with a value. What the document says: resume, pause, resume
  // in a row leave one job in the queue, all three return the same handle,
  // and the device is told to resume once -- nothing was queued and
  // cancelled on the way.
  fakeAsync((clock) {
    final device = RecordingDevice();
    final player = Player(device);

    final first = player.resume();
    final second = player.pause();
    final third = player.resume();

    require(identical(first, second), 'the pause joins the open group');
    require(identical(second, third), 'and so does the second resume');

    clock.flushMicrotasks();
    require(device.calls.length == 1, 'the device hears one command');
    require(device.calls.single == 'resume', 'and it is the last one');
    require(player.currentState is Playing, 'the state follows the device');
    require(first.outcome is Done, 'the one job finished, none was cancelled');

    print('accumulated: device heard ${device.calls}, '
        'state ${player.currentState.runtimeType}, '
        'one handle ${identical(first, third)}, outcome ${first.outcome}');

    player.close();
    clock.flushMicrotasks();
  });

  // Two operations of their own, with a fresh device: ordinary jobs with
  // keys, and the controller's queue as what removes them. What the document
  // says: the queue never touches the running job, so a pause that has
  // already started runs to its end whatever is removed behind it.
  fakeAsync((clock) {
    final device = RecordingDevice();
    final transport = Transport(device);

    final pausing = transport.pause();
    clock.flushMicrotasks();
    require(device.calls.single == 'pause', 'the pause is running');
    require(!pausing.isFinished, 'and it is waiting for the device');

    final resuming = transport.resume();
    clock.flushMicrotasks();
    require(!pausing.isFinished, 'removeWhere did not touch the running job');
    require(device.calls.length == 1, 'the resume waits its turn');

    device.pausing!.complete();
    clock.flushMicrotasks();
    require(pausing.outcome is Done, 'the pause ran to its end');
    require(device.calls.length == 2, 'and only then the resume started');
    require(resuming.outcome is Done, 'the resume finished too');
    require(transport.currentState is Playing, 'ending where resume leaves it');

    print('separate jobs: device heard ${device.calls}, '
        'pause ${pausing.outcome}, resume ${resuming.outcome}, '
        'state ${transport.currentState.runtimeType}');

    transport.close();
    clock.flushMicrotasks();
  });
}
''')

# ---------------------------------------------------------------------- logs
LOG_FAKE = '''
/// Records every batch, so the driver counts requests and their contents.
class RecordingLogApi implements LogApi {
  final sent = <List<String>>[];

  @override
  Future<void> send(List<LogEntry> entries) async {
    sent.add([for (final entry in entries) entry.message]);
  }
}
'''

FILES['logs'] = (
    with_fake_async('recipes/LogController')
    + LOG_FAKE
    + REQUIRE
    + '''
void main() {
  // What the document says: three calls before execution send one list of
  // three entries; the first group is ready immediately, later groups start
  // at least a second apart, and entries arriving inside that interval are
  // kept for the next group.
  fakeAsync((clock) {
    final api = RecordingLogApi();
    final logs = LogController(api)
      ..logEvent(const LogEntry('one'))
      ..logEvent(const LogEntry('two'))
      ..logEvent(const LogEntry('three'));

    clock.flushMicrotasks();
    require(api.sent.length == 1, 'three calls, one request');
    require(api.sent.single.length == 3, 'and it carries all three entries');
    require(logs.currentState == 3, 'state counts what was sent');
    print('first group: ${api.sent.single}, state ${logs.currentState}');

    logs.logEvent(const LogEntry('four'));
    clock.elapse(const Duration(milliseconds: 999));
    require(api.sent.length == 1, 'the throttle interval is not over');
    print('at 999 ms: requests ${api.sent.length}, '
        'state ${logs.currentState}');

    clock.elapse(const Duration(milliseconds: 2));
    require(api.sent.length == 2, 'the interval ended and the group went');
    require(api.sent.last.single == 'four', 'carrying what arrived inside it');
    require(logs.currentState == 4, 'and the count grew by one');
    print('second group: ${api.sent.last}, state ${logs.currentState}');

    logs.close();
    clock.flushMicrotasks();
  });
}
''')

# -------------------------------------------------------------------- search
# The document calls SearchState and SearchApi application types and declares
# neither; a bench cannot leave them undeclared. The API answers 100 ms after
# it is asked, which is what the section's traces are measured against.
SEARCH_TYPES = """import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';

class SearchState {
  final List<String> results;

  const SearchState.idle() : results = const [];

  const SearchState.results(this.results);
}

class SearchApi {
  final asked = <String>[];

  Future<List<String>> search(String text) {
    asked.add(text);
    return Future<List<String>>.delayed(
      const Duration(milliseconds: 100),
      () => ['hits for $text'],
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
    + snips['recipes/Search']
    + REQUIRE
    + DRIVE
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
}
""")

# ------------------------------------------------------------------ policies
# The reference's own three lines, run as written. They are statements, not a
# declaration, so the bench gives them the controller they talk to and checks,
# right under them, the row of the table they belong to: with B between the
# two additions, A2 is a job of its own and not A1's.
FILES['policies'] = (
    with_fake_async('recipes/Settings', dart_async=True)
    + SETTINGS_FAKE
    + """
void threeCalls(SettingsController settings) {
"""
    + snips['reference/all-three-while-the-current-jo'].rstrip('\n')
    + """
  require(!identical(a1, a2), "adjacent: A2 is a job of its own, not A1's");
}
"""
    + REQUIRE
    + '''
void main() {
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

    // What `adjacent` costs here: B stood between the two additions, so they
    // are two groups and the server is written to twice.
    require(api.saved.length == 2, 'two groups, two writes');
    require(api.saved.first.theme == 'dark', 'A1 went first, with its field');
    require(api.saved.last.language == 'ru', 'A2 followed, with its own');
    print("the reference's three lines: loads ${api.loads}, "
        'writes ${api.saved.length} '
        '(${api.saved.first.theme}, then ${api.saved.last.language}), '
        'state ${describe(settings.currentState)}');

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
