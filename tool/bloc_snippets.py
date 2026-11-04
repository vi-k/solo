#!/usr/bin/env python3
"""Builds runnable scenarios from the bloc page of solo.

Every snippet is copied byte-identical out of the markdown and wrapped in a
runnable file: fakes above it, a driver below it. The page says what a
controller under a bloc takes off the code and what stays with bloc; the
drivers hold both with `require`, so a bloc that starts closing otherwise
turns the run red instead of printing something else.

Usage, from the repository root:

    python3 tool/bloc_snippets.py [workdir]
    python3 tool/bloc_snippets.py --list

The default workdir is /tmp/bloc-pages-check. It creates one package,
bloc_pages_check, with async_job and solo from the tree. Then:

    dart pub get
    dart analyze --fatal-infos bin/v
    dart run --enable-asserts bin/v/solo_bridge_states.dart   # and so on

Asserts are on: bloc says through them that a handler emitted after it was
done, and a run without them would let that pass.

The drivers run on virtual time, under the runner of
tool/adapter_snippets.py with the clock of tool/doc_snippets.py: a close
is held to its length in milliseconds, and real time would make that
number drift.

Blocks are addressed by `subsection_blocks` of tool/doc_blocks.py: section,
`###` subsection and the name a block declares. The answer of bloc alone
and the answer with a controller declare the same bloc, and the subsection
tells them apart.

Every `dart` block of a page is built: the script stops if one of them
went into no driver.
"""
import os
import sys

import doc_blocks

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = sys.argv[1] if len(sys.argv) > 1 else '/tmp/bloc-pages-check'
SOLO = os.path.join(REPO, 'packages', 'solo', 'doc', 'bloc.md')
VS_BLOC = os.path.join(REPO, 'packages', 'solo', 'doc', 'vs-bloc.md')

# The versions the page names, resolved at their newest on the SDK of the
# job: bloc 9.2.1 is the first whose `isClosed` is true while close() runs
# the queue out, and the closing row of the table of the page stands on
# it. async_job is an override, since solo from the tree asks for a
# released one.
PUBSPEC = """name: bloc_pages_check
publish_to: none

environment:
  sdk: ^3.10.0

dependencies:
  bloc: ^9.2.1
  bloc_concurrency: ^0.3.0
  fake_async: ^1.3.1
  solo:
    path: {solo}

dev_dependencies:
  lints: ^5.1.1

dependency_overrides:
  async_job:
    path: {async_job}
""".format(
    async_job=os.path.join(REPO, 'packages', 'async_job'),
    solo=os.path.join(REPO, 'packages', 'solo'),
)

# The rules of async_job itself: a fragment that passes here would pass
# inside the package.
OPTIONS = 'include: async_job_rules.yaml\n'

solo = doc_blocks.Blocks(doc_blocks.subsection_blocks(open(SOLO).read()))
if ROOT == '--list':
    for key in solo:
        poisoned = dict.__getitem__(solo, key) is doc_blocks.POISONED
        print(key, '(declared twice)' if poisoned else '')
    sys.exit(0)

# Every driver carries the helpers and the clock whether it uses them or
# not, so the analyzer is told that they are shared.
BLOC_HEAD = """// ignore_for_file: unreachable_from_main
import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:fake_async/fake_async.dart';
"""

# What every driver needs: a delay, a check that fails the run and a zone
# of its own. The zone is not awaited -- a guarded body that fails never
# completes -- and the driver waits on a completer the body completes in
# `finally`. What reaches the zone is in `zone`.
HELPERS = '''
final zone = <Object>[];

Future<void> delay(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> guarded(Future<void> Function() body) {
  final ended = Completer<void>();
  runZonedGuarded(() async {
    try {
      await body();
    } finally {
      ended.complete();
    }
  }, (error, _) => zone.add(error));
  return ended.future;
}
'''

# The `main` of every driver; the driver itself is `scenario`. The runner of
# tool/adapter_snippets.py, which says why the clock is elapsed from outside
# the fake zone, with `nowMs()` of tool/doc_snippets.py over it.
RUNNER = '''
late FakeAsync _clock;

/// Milliseconds of the scenario's own clock.
int nowMs() => _clock.elapsed.inMilliseconds;

Future<void> main() async {
  Object? failure;
  StackTrace? failureTrace;
  var ended = false;
  _clock = FakeAsync()
    ..run((clock) {
      Future<void>.sync(scenario).then<void>(
        (_) {
          ended = true;
        },
        onError: (Object error, StackTrace stackTrace) {
          failure = error;
          failureTrace = stackTrace;
          ended = true;
        },
      );
    });
  while (!ended) {
    _clock.flushMicrotasks();
    await Future<void>.delayed(Duration.zero);
    if (ended || _clock.microtaskCount > 0) {
      continue;
    }
    if (_clock.elapsed > const Duration(minutes: 10)) {
      throw StateError('the scenario did not end in ten of its minutes');
    }
    _clock.elapse(const Duration(milliseconds: 1));
  }
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureTrace!);
  }
}
'''

FILES = {}

# ------------------------------------------------- fakes of the sections
# The device of tool/doc_snippets.py, its write of 20 ms, with the wire
# counted: how many writes are in flight at once, and at most.
FIRMWARE = '''
class Chunk {
  const Chunk(this.index);

  final int index;
}

class Ble {
  final written = <int>[];
  int inFlight = 0;
  int maxInFlight = 0;

  // A BLE write cannot be told to stop: the chunk handed to the stack
  // lands, and the only way to keep the wire clear is to wait for it.
  Future<void> write(Chunk chunk) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await delay(20);
    written.add(chunk.index);
    inFlight--;
  }
}

final class Flash {
  const Flash(this.chunks);

  final List<Chunk> chunks;
}

sealed class FirmwareState {
  const FirmwareState();
}

final class Idle extends FirmwareState {
  const Idle();

  @override
  String toString() => 'Idle';
}

final class Flashing extends FirmwareState {
  const Flashing(this.written, this.total);

  final int written;
  final int total;

  @override
  String toString() => '$written/$total';
}
'''

# Three uploads of four chunks, the second 30 ms after the first and the
# third 5 ms or no time after the second: the second is replaced while it
# waits for the first one's write. One line, the same for both answers.
FLASHING = '''
Future<void> scenario() async {
  for (final gaps in [
    [0, 30, 5],
    [0, 30, 0],
  ]) {
    final ble = Ble();
    final bloc = firmwareBloc(ble);
    final states = <FirmwareState>[];
    final listening = bloc.stream.listen(states.add);
    for (final (upload, gap) in gaps.indexed) {
      if (gap > 0) await delay(gap);
      bloc.add(Flash([for (var i = 0; i < 4; i++) Chunk(100 * upload + i)]));
    }
    await waitOut();
    require(ble.inFlight == 0, 'every write must have ended');
    print('uploads at 0, 30 and ${30 + gaps[2]} ms: written '
        '${ble.written}, ${ble.maxInFlight} write at a time at most, '
        'states $states');
    require(ble.maxInFlight == 1, 'two writes overlapped');
    require('${ble.written}' == '[0, 1, 200, 201, 202, 203]',
        'the replaced uploads must stop and the last one write it all');
    require('$states' == '[1/4, 1/4, 2/4, 3/4, 4/4]',
        'no state of a replaced upload may follow the new one: $states');
    await listening.cancel();
    await bloc.close();
  }
  require(zone.isEmpty, 'nothing may reach the zone: $zone');
}
'''


# ============================================================= solo page
SOLO_BRIDGES = 'the-bridges'

SOLO_HEAD = BLOC_HEAD.replace(
    "import 'package:fake_async/fake_async.dart';\n",
    "import 'package:fake_async/fake_async.dart';\n"
    "import 'package:solo/solo.dart';\n")
assert 'package:solo' in SOLO_HEAD

# The bridge uses no transformer of bloc_concurrency.
SOLO_PLAIN_HEAD = SOLO_HEAD.replace(
    "import 'package:bloc_concurrency/bloc_concurrency.dart';\n", '')

# `follow` and `settle` of The bridges: every bloc of the page with a
# controller under it uses them, and every driver of such a bloc has them.
# The block is addressed by `settle`: `follow<S extends Object>(` has its
# type parameters before the parenthesis.
SOLO_BRIDGE_FUNCTIONS = solo[f'{SOLO_BRIDGES}/settle']
assert 'Future<void> follow<S extends Object>(' in SOLO_BRIDGE_FUNCTIONS
SOLO_HEAD += SOLO_BRIDGE_FUNCTIONS
SOLO_PLAIN_HEAD += SOLO_BRIDGE_FUNCTIONS

vs_bloc = doc_blocks.subsection_blocks(open(VS_BLOC).read())

# ------------------------------------------------------------ the bridges
# The controller counts to 2, is reset twice -- the second reset publishes
# the state it already has -- and counts to 3; the bloc is closed 35 ms
# in, after the first step of the last count.
FILES['solo_bridge_states'] = (
    SOLO_PLAIN_HEAD + HELPERS + solo[f'{SOLO_BRIDGES}/Counter']
    + solo[f'{SOLO_BRIDGES}/CounterBloc'] + '''
Future<void> scenario() async {
  final published = <int>[];
  final states = <int>[];
  late Counter counter;
  late CounterBloc bloc;
  late int tookMs;
  await guarded(() async {
    counter = Counter();
    final listened = counter.stream.listen(published.add);
    bloc = CounterBloc(counter);
    final followed = bloc.stream.listen(states.add);
    bloc
      ..add(const CountTo(2))
      ..add(const Reset())
      ..add(const Reset())
      ..add(const CountTo(3));
    await delay(35);
    final started = nowMs();
    await bloc.close();
    tookMs = nowMs() - started;
    await delay(50);
    await followed.cancel();
    await listened.cancel();
  });
  print('controller $published');
  print('bloc       $states');
  print('close took ${tookMs}ms, bloc.state ${bloc.state}, '
      'counter.isClosed ${counter.isClosed}, bloc.isClosed ${bloc.isClosed}');
  require('$published' == '[1, 2, 0, 0, 1]',
      'the controller must publish every state: $published');
  require('$states' == '[1, 2, 0, 1]',
      'the bloc must follow the controller but for the equal state: $states');
  require(bloc.state == 1, 'the bloc must end at the last state');
  require(counter.isClosed, 'close() of the bloc must close the controller');
  require(bloc.isClosed, 'the bloc must be closed');
  require(tookMs == 0, 'close must not wait for the count: ${tookMs}ms');
  require(zone.isEmpty, 'nothing may reach the zone: $zone');
}
''' + RUNNER)

# The controller publishes 5 after the constructor of the bloc read its
# state and before the handler of _Started subscribed: the bloc starts at
# 0 and has to reach 5 all the same.
FILES['solo_bridge_late'] = (
    SOLO_PLAIN_HEAD + HELPERS + solo[f'{SOLO_BRIDGES}/Counter']
    + solo[f'{SOLO_BRIDGES}/CounterBloc'] + '''
final class PresetCounter extends Counter {
  Job<void> preset(int value) =>
      enqueue<int, void>((ctx) async => ctx.emit(value));
}

Future<void> scenario() async {
  final states = <int>[];
  late int initial;
  late int current;
  late int followed;
  await guarded(() async {
    final counter = PresetCounter();
    final presetting = counter.preset(5);
    final bloc = CounterBloc(counter);
    initial = bloc.state;
    final listening = bloc.stream.listen(states.add);
    await presetting.done;
    await delay(5);
    current = counter.currentState;
    followed = bloc.state;
    await listening.cancel();
    await bloc.close();
  });
  print('a state published while the bloc is created: the bloc starts at '
      '$initial, counter.currentState $current, bloc.state $followed');
  require(initial == 0, 'the constructor must read the state before 5');
  require(current == 5, 'the controller must publish 5');
  require(followed == 5, 'the bloc must reach the state of the controller');
  require('$states' == '[5]', 'the bloc must publish 5 once: $states');
  require(zone.isEmpty, 'nothing may reach the zone: $zone');
}
''' + RUNNER)

# A job that fails: `settle` throws the Failed outcome again, and it goes
# to the zone as any error of a handler.
FILES['solo_bridge_failed'] = (
    SOLO_PLAIN_HEAD + HELPERS + solo[f'{SOLO_BRIDGES}/Counter']
    + solo[f'{SOLO_BRIDGES}/CounterBloc'] + '''
final class BrokenCounter extends Counter {
  @override
  Job<void> countTo(int target) => enqueue<int, void>((ctx) async {
    throw StateError('count: broken');
  });
}

Future<void> scenario() async {
  await guarded(() async {
    final bloc = CounterBloc(BrokenCounter())..add(const CountTo(1));
    await delay(20);
    await bloc.close();
  });
  print('a job that fails: the zone $zone');
  require('$zone' == '[Bad state: count: broken]',
      'the failure of the job must reach the zone: $zone');
}
''' + RUNNER)

# A handler that emits by itself parts the bloc from the controller until
# the next state of the controller; the observer sees every state of the
# controller on _Started.
FILES['solo_bridge_emit'] = (
    SOLO_PLAIN_HEAD + HELPERS + solo[f'{SOLO_BRIDGES}/Counter']
    + solo[f'{SOLO_BRIDGES}/CounterBloc'] + '''
final class Clear extends CounterEvent {
  const Clear();
}

class ClearingBloc extends CounterBloc {
  ClearingBloc(super.counter) {
    on<Clear>((e, emit) => emit(0));
  }
}

String nameOf(Object? event) => switch (event) {
  Clear() => 'Clear',
  CountTo() => 'CountTo',
  Reset() => 'Reset',
  _Started() => '_Started',
  _ => '$event',
};

final class Transitions extends BlocObserver {
  final seen = <String>[];

  @override
  void onTransition(
    Bloc<dynamic, dynamic> bloc,
    Transition<dynamic, dynamic> transition,
  ) {
    super.onTransition(bloc, transition);
    seen.add('${nameOf(transition.event)}: '
        '${transition.currentState}->${transition.nextState}');
  }
}

Future<void> scenario() async {
  final transitions = Transitions();
  Bloc.observer = transitions;
  late String cleared;
  late String counted;
  await guarded(() async {
    final counter = Counter();
    final bloc = ClearingBloc(counter)..add(const CountTo(2));
    await delay(30);
    bloc.add(const Clear());
    await delay(5);
    cleared = 'bloc.state ${bloc.state}, controller ${counter.currentState}';
    bloc.add(const CountTo(3));
    await delay(30);
    counted = 'bloc.state ${bloc.state}, controller ${counter.currentState}';
    await bloc.close();
  });
  print('after Clear: $cleared');
  print('after CountTo(3): $counted');
  print('transitions: ${transitions.seen}');
  require(cleared == 'bloc.state 0, controller 2',
      'the handler of Clear must part the bloc from the controller: $cleared');
  require(counted == 'bloc.state 3, controller 3',
      'the next state of the controller must replace it: $counted');
  require('${transitions.seen}' ==
      '[_Started: 0->1, _Started: 1->2, Clear: 2->0, _Started: 0->3]',
      'every state of the controller comes on _Started: ${transitions.seen}');
  require(zone.isEmpty, 'nothing may reach the zone: $zone');
}
''' + RUNNER)

# `seed` of blocTest emits into the bloc right after `build`
# (bloc_test-10.0.0/lib/src/bloc_test.dart:202), and follow replaces it.
FILES['solo_bridge_seed'] = (
    SOLO_PLAIN_HEAD + HELPERS + solo[f'{SOLO_BRIDGES}/Counter']
    + solo[f'{SOLO_BRIDGES}/CounterBloc'] + '''
Future<void> scenario() async {
  late String seeded;
  await guarded(() async {
    final counter = Counter();
    // What blocTest does with `seed: () => 9`.
    final bloc = CounterBloc(counter)
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      ..emit(9);
    await delay(5);
    seeded = 'bloc.state ${bloc.state}, controller ${counter.currentState}';
    await bloc.close();
  });
  print('seeded 9: $seeded');
  require(seeded == 'bloc.state 0, controller 0',
      'follow must replace the seed with the state of the controller');
  require(zone.isEmpty, 'nothing may reach the zone: $zone');
}
''' + RUNNER)

# A bloc without the override of close() leaves the controller open, and
# the count goes on.
CLOSE_OVERRIDE = '''
  @override
  Future<void> close() async {
    await _counter.close();
    return super.close();
  }
'''
assert solo[f'{SOLO_BRIDGES}/CounterBloc'].count(CLOSE_OVERRIDE) == 1
FILES['solo_bridge_unclosed'] = (
    SOLO_PLAIN_HEAD + HELPERS + solo[f'{SOLO_BRIDGES}/Counter']
    + solo[f'{SOLO_BRIDGES}/CounterBloc'].replace(CLOSE_OVERRIDE, '') + '''
Future<void> scenario() async {
  late String after;
  await guarded(() async {
    final counter = Counter();
    final bloc = CounterBloc(counter)..add(const CountTo(5));
    await delay(15);
    await bloc.close();
    await delay(60);
    after = 'controller ${counter.currentState}, '
        'counter.isClosed ${counter.isClosed}';
    await counter.close();
  });
  print('closed without its controller, 60 ms later: $after');
  require(after == 'controller 5, counter.isClosed false',
      'the count must go on after the bloc is closed: $after');
  require(zone.isEmpty, 'nothing may reach the zone: $zone');
}
''' + RUNNER)

# The rest of the solo page takes the Bloc answer and the controller of a
# section of vs-bloc.md as they are there, and the generator holds them to
# it: a reader who comes from there knows the code. The fakes are the ones
# of tool/doc_snippets.py, with its delays; the bloc answers and the
# controllers have fakes of their own there, as here.
def from_vs_bloc(key, section, subsection):
    block = solo[key]
    name = key.rsplit('/', 1)[1]
    assert block.rstrip('\n') in vs_bloc[f'{section}/{subsection}/{name}'], (
        f'the {name} of the bloc page is not the one of vs-bloc.md')
    return block


def section(title):
    return doc_blocks.slug(title)


ALONE_SUB = 'with-bloc-alone'
UNDER_SUB = 'with-a-controller-under-the-bl'

# The calls a fake device received, in order.
TRACE = '''
final trace = <String>[];

/// A device SDK's own cancel token: the call watches it and returns.
class CancelToken {
  bool cancelled = false;

  void cancel() => cancelled = true;
}

/// The plain list of calls the device received, from a start/end trace.
List<String> callsOf(List<String> trace) => [
  for (final entry in trace)
    if (entry.endsWith(' start')) entry.substring(0, entry.length - 6),
];
'''

# ------------------------------------------------------------- restarting
RESTARTING = section('Restarting one operation within a shared queue')

# play and pause take 30 ms, a seek three steps of 10 and watches its
# token between them.
PLAYER = TRACE + '''
class Player {
  Future<void> play() async {
    trace.add('play start');
    await delay(30);
    trace.add('play end');
  }

  Future<void> pause() async {
    trace.add('pause start');
    await delay(30);
    trace.add('pause end');
  }

  Future<void> seek(Duration position, {CancelToken? cancelToken}) async {
    final ms = position.inMilliseconds;
    trace.add('seek $ms start');
    for (var step = 0; step < 3; step++) {
      await delay(10);
      if (cancelToken?.cancelled ?? false) {
        trace.add('seek $ms stopped');
        return;
      }
    }
    trace.add('seek $ms end');
  }
}

sealed class PlayerCommand {}

class Play extends PlayerCommand {}

class Pause extends PlayerCommand {}

class Seek extends PlayerCommand {
  Seek(this.position);

  final Duration position;
}
'''

# The state of the bloc answer, and the one of the controller.
BLOC_PLAYER_STATE = '''
class PlayerState {
  const PlayerState({this.position = Duration.zero});

  final Duration position;

  @override
  String toString() => 'PlayerState(${position.inMilliseconds}ms)';
}
'''

SOLO_PLAYER_STATE = '''
sealed class PlayerState {}

final class Ready extends PlayerState {
  Ready({this.playing = false, this.position = Duration.zero});

  final bool playing;
  final Duration position;

  Ready copyWith({bool? playing, Duration? position}) => Ready(
    playing: playing ?? this.playing,
    position: position ?? this.position,
  );

  @override
  String toString() => 'Ready(${position.inMilliseconds}ms)';
}
'''

# A drag through 1, 2, 3 and one that comes back to 1, each between play
# and pause; then a seek to 3 15 ms after a seek to 1, while it runs.
SEEKING = '''
Future<void> scenario() async {
  await guarded(() async {
    for (final positions in [
      [1, 2, 3],
      [1, 2, 1],
    ]) {
      trace.clear();
      final bloc = playerBloc()..add(Play());
      for (final position in positions) {
        bloc.add(Seek(Duration(milliseconds: position)));
      }
      bloc.add(Pause());
      await delay(300);
      final calls = callsOf(trace);
      print('$name, seeks ${positions.join(', ')}: $calls');
      require('$calls' == drags[positions.last == 3 ? 0 : 1],
          '$name, seeks $positions: $calls');
      requireFollowed(bloc);
      await bloc.close();
    }
    trace.clear();
    final seeking = playerBloc()..add(Seek(const Duration(milliseconds: 1)));
    await delay(15);
    seeking.add(Seek(const Duration(milliseconds: 3)));
    await delay(300);
    print('$name, seek 3 15 ms after seek 1: $trace');
    require('$trace' ==
        '[seek 1 start, seek 1 stopped, seek 3 start, seek 3 end]',
        '$name: the seek in flight must stop first: $trace');
    requireFollowed(seeking);
    await seeking.close();
  });
  require(zone.isEmpty, '$name: nothing may reach the zone: $zone');
}
'''

FILES['solo_restarting_bloc'] = (
    BLOC_HEAD + HELPERS + PLAYER + BLOC_PLAYER_STATE
    + from_vs_bloc(f'{RESTARTING}/{ALONE_SUB}/PlayerBloc', RESTARTING,
                   'bloc')
    + '''
const name = 'with bloc alone';

/// The newest position is compared by value, and a drag that comes back
/// lets the first seek to 1 through.
const drags = ['[play, seek 3, pause]', '[play, seek 1, seek 1, pause]'];

PlayerBloc playerBloc() => PlayerBloc(Player());

void requireFollowed(PlayerBloc bloc) {}
''' + SEEKING + RUNNER)

# The bloc of bloc alone that keeps the newest Seek itself and compares it
# with identical: a drag that comes back to 1 seeks to 1 once.
PLAYER_BLOC = from_vs_bloc(f'{RESTARTING}/{ALONE_SUB}/PlayerBloc', RESTARTING,
                           'bloc')
KEPT_EVENT = PLAYER_BLOC
for old, new in [
    ('  Duration? _newestSeek;\n', '  Seek? _newestSeek;\n'),
    ('          if (position != _newestSeek) return;\n',
     '          if (!identical(command, _newestSeek)) return;\n'),
    ('      _newestSeek = event.position;\n', '      _newestSeek = event;\n'),
]:
    assert KEPT_EVENT.count(old) == 1, old
    KEPT_EVENT = KEPT_EVENT.replace(old, new)
FILES['solo_restarting_bloc_identical'] = (
    BLOC_HEAD + HELPERS + PLAYER + BLOC_PLAYER_STATE + KEPT_EVENT + '''
const name = 'with bloc alone, the newest Seek kept';

const drags = ['[play, seek 3, pause]', '[play, seek 1, pause]'];

PlayerBloc playerBloc() => PlayerBloc(Player());

void requireFollowed(PlayerBloc bloc) {}
''' + SEEKING + RUNNER)

FILES['solo_restarting_controller'] = (
    SOLO_PLAIN_HEAD + HELPERS + PLAYER + SOLO_PLAYER_STATE
    + from_vs_bloc(f'{RESTARTING}/{UNDER_SUB}/PlayerController', RESTARTING,
                   'solo')
    + solo[f'{RESTARTING}/{UNDER_SUB}/PlayerBloc'] + '''
const name = 'with a controller';

const drags = ['[play, seek 3, pause]', '[play, seek 1, pause]'];

late PlayerController controller;

PlayerBloc playerBloc() =>
    PlayerBloc(controller = PlayerController(Player()));

/// The bridge of states: the bloc ends at the state of its controller.
void requireFollowed(PlayerBloc bloc) => require(
    bloc.state == controller.currentState,
    '$name: the bloc must follow the controller: ${bloc.state}');
''' + SEEKING + RUNNER)

# ---------------------------------------------------------------- removing
REMOVING = section('Removing selected pending work')

# connect takes 30 ms, the rest 10, and the device refuses anybody it is
# not connected to.
DEVICE = '''
final trace = <String>[];

class Ble {
  var _connected = false;

  void _requireConnected(String call) {
    if (!_connected) throw StateError('$call: not connected');
  }

  Future<void> connect() async {
    trace.add('connect');
    await delay(30);
    _connected = true;
  }

  Future<int> battery() async {
    _requireConnected('battery');
    trace.add('battery');
    await delay(10);
    return 100;
  }

  Future<void> rename(String name) async {
    _requireConnected('rename');
    trace.add('rename $name');
    await delay(10);
  }

  Future<void> disconnect() async {
    trace.add('disconnect');
    await delay(10);
    _connected = false;
  }
}

sealed class DeviceEvent {
  const DeviceEvent();
}

class Connect extends DeviceEvent {}

// Const so that one canonical instance can be added by two screens.
class ReadBattery extends DeviceEvent {
  const ReadBattery();
}

class Rename extends DeviceEvent {
  Rename(this.name);

  final String name;
}

class Disconnect extends DeviceEvent {}
'''

BLOC_DEVICE_STATE = '''
class DeviceState {
  const DeviceState({this.online = false, this.battery});

  final bool online;
  final int? battery;

  DeviceState copyWith({bool? online, int? battery}) => DeviceState(
    online: online ?? this.online,
    battery: battery ?? this.battery,
  );
}
'''

SOLO_DEVICE_STATE = '''
sealed class DeviceState {
  const DeviceState();
}

final class Offline extends DeviceState {
  const Offline();
}

final class Connected extends DeviceState {
  const Connected({this.battery});

  final int? battery;

  Connected copyWith({int? battery}) =>
      Connected(battery: battery ?? this.battery);
}
'''

# The screen leaves: the four commands of the section. A screen that opens
# again asks for the battery through the same const event. And a read the
# refresh timer adds behind the disconnect.
LEAVING = '''
Future<void> scenario() async {
  final runs = {
    'leaving': [Connect(), const ReadBattery(), Rename('kitchen'),
        Disconnect()],
    'a shared const read': [Connect(), const ReadBattery(), Rename('kitchen'),
        Disconnect(), Connect(), const ReadBattery()],
    'a read after disconnect': [Connect(), Disconnect(), const ReadBattery()],
  };
  for (final MapEntry(key: label, value: events) in runs.entries) {
    trace.clear();
    zone.clear();
    await guarded(() async {
      final bloc = deviceBloc(Ble());
      events.forEach(bloc.add);
      await delay(300);
      requireFollowed(bloc);
      await bloc.close();
    });
    final last = label == 'a read after disconnect';
    require(last || zone.isEmpty, '$name, $label: the zone $zone');
    final failed = last ? ', the zone $zone' : '';
    print('$name, $label: $trace$failed');
    require('$trace$failed' == expected[label],
        '$name, $label: $trace$failed');
  }
}
'''

FILES['solo_removing_bloc'] = (
    BLOC_HEAD + HELPERS + DEVICE + BLOC_DEVICE_STATE
    + from_vs_bloc(f'{REMOVING}/{ALONE_SUB}/DeviceBloc', REMOVING, 'bloc')
    + '''
const name = 'with bloc alone';

/// The shared const read overwrites the stamp of the queued one, and the
/// read behind the disconnect reaches a device that is gone.
const expected = {
  'leaving': '[connect, rename kitchen, disconnect]',
  'a shared const read':
      '[connect, battery, rename kitchen, disconnect, connect, battery]',
  'a read after disconnect':
      '[connect, disconnect], the zone [Bad state: battery: not connected]',
};

DeviceBloc deviceBloc(Ble ble) => DeviceBloc(ble);

void requireFollowed(DeviceBloc bloc) {}
''' + LEAVING + RUNNER)

# A check of state.online before the read turns away the read behind the
# disconnect; the shared const read still reaches the device.
STAMP_CHECK = '          if (_stampOf[e] != _screen) return;\n'
DEVICE_BLOC = solo[f'{REMOVING}/{ALONE_SUB}/DeviceBloc']
assert DEVICE_BLOC.count(STAMP_CHECK) == 1
FILES['solo_removing_bloc_online'] = (
    BLOC_HEAD + HELPERS + DEVICE + BLOC_DEVICE_STATE
    + DEVICE_BLOC.replace(
        STAMP_CHECK,
        '          if (_stampOf[e] != _screen || !state.online) return;\n')
    + '''
const name = 'with bloc alone and a check of state.online';

const expected = {
  'leaving': '[connect, rename kitchen, disconnect]',
  'a shared const read':
      '[connect, battery, rename kitchen, disconnect, connect, battery]',
  'a read after disconnect': '[connect, disconnect], the zone []',
};

DeviceBloc deviceBloc(Ble ble) => DeviceBloc(ble);

void requireFollowed(DeviceBloc bloc) {}
''' + LEAVING + RUNNER)

# The bridges of the answer share its block with the bloc, and the first
# attempt is built on them.
DEVICE_CONTROLLER = (
    from_vs_bloc(f'{REMOVING}/{UNDER_SUB}/DeviceController', REMOVING,
                 'solo')
    + solo[f'{REMOVING}/{UNDER_SUB}/StreamedDevice'])
assert DEVICE_CONTROLLER.endswith(solo[f'{REMOVING}/{UNDER_SUB}/DeviceBloc'])

FILES['solo_removing_sequential'] = (
    SOLO_HEAD + HELPERS + DEVICE + SOLO_DEVICE_STATE + DEVICE_CONTROLLER
    + solo[f'{REMOVING}/the-first-attempt/SequentialDeviceBloc'] + '''
const name = 'one sequential registration';

/// The commands wait in the queue of bloc, and disconnect finds nothing
/// to remove; the rule of the read still turns it down behind it.
const expected = {
  'leaving': '[connect, battery, rename kitchen, disconnect]',
  'a shared const read':
      '[connect, battery, rename kitchen, disconnect, connect, battery]',
  'a read after disconnect': '[connect, disconnect], the zone []',
};

late StreamedDevice controller;

SequentialDeviceBloc deviceBloc(Ble ble) =>
    SequentialDeviceBloc(controller = StreamedDevice(ble));

/// The bridge of states: the bloc ends at the state of its controller.
void requireFollowed(Bloc<DeviceEvent, DeviceState> bloc) => require(
    bloc.state == controller.currentState,
    '$name: the bloc must follow the controller: ${bloc.state}');
''' + LEAVING + RUNNER)

FILES['solo_removing_controller'] = (
    SOLO_PLAIN_HEAD + HELPERS + DEVICE + SOLO_DEVICE_STATE + DEVICE_CONTROLLER
    + '''
const name = 'a registration per command';

const expected = {
  'leaving': '[connect, rename kitchen, disconnect]',
  'a shared const read':
      '[connect, rename kitchen, disconnect, connect, battery]',
  'a read after disconnect': '[connect, disconnect], the zone []',
};

late StreamedDevice controller;

DeviceBloc deviceBloc(Ble ble) => DeviceBloc(controller = StreamedDevice(ble));

/// The bridge of states: the bloc ends at the state of its controller.
void requireFollowed(Bloc<DeviceEvent, DeviceState> bloc) => require(
    bloc.state == controller.currentState,
    '$name: the bloc must follow the controller: ${bloc.state}');
''' + LEAVING + RUNNER)

# ------------------------------------------------------------------ write
WRITE = section('Finishing an in-flight write before restarting')

# The device of FIRMWARE with the events of vs-bloc.md.
FIRMWARE_EVENTS = FIRMWARE.split('final class Flash {')[0] + '''
sealed class FirmwareEvent {}

class Flash extends FirmwareEvent {
  Flash(this.chunks);

  final List<Chunk> chunks;
}
'''

BLOC_FIRMWARE_STATE = '''
sealed class FirmwareState {}

class Idle extends FirmwareState {
  @override
  String toString() => 'Idle';
}

class Flashing extends FirmwareState {
  Flashing(this.written, this.total);

  final int written;
  final int total;

  @override
  String toString() => '$written/$total';
}
'''

SOLO_FIRMWARE_STATE = '''
sealed class FirmwareState {
  const FirmwareState();
}

sealed class NotBroken extends FirmwareState {
  const NotBroken();
}

final class Idle extends NotBroken {
  const Idle();

  @override
  String toString() => 'Idle';
}

final class Flashing extends NotBroken {
  Flashing(this.written, this.total);

  final int written;
  final int total;

  @override
  String toString() => '$written/$total';
}
'''

FILES['solo_write_bloc'] = (
    BLOC_HEAD + HELPERS + FIRMWARE_EVENTS + BLOC_FIRMWARE_STATE
    + from_vs_bloc(f'{WRITE}/{ALONE_SUB}/LockedFirmwareBloc', WRITE, 'bloc')
    + '''
Bloc<FirmwareEvent, FirmwareState> firmwareBloc(Ble ble) =>
    LockedFirmwareBloc(ble);

Future<void> waitOut() => delay(200);
''' + FLASHING + RUNNER)

FILES['solo_write_controller'] = (
    SOLO_PLAIN_HEAD + HELPERS + FIRMWARE_EVENTS + SOLO_FIRMWARE_STATE
    + from_vs_bloc(f'{WRITE}/{UNDER_SUB}/FirmwareController', WRITE, 'solo')
    + solo[f'{WRITE}/{UNDER_SUB}/FirmwareBloc'] + '''
/// The jobs the handler of the bloc waits for.
final jobs = <Job<void>>[];

final class RecordedFirmware extends StreamedFirmware {
  RecordedFirmware(super.ble);

  @override
  Job<void> flash(List<Chunk> chunks) {
    final job = super.flash(chunks);
    jobs.add(job);
    return job;
  }
}

Bloc<FirmwareEvent, FirmwareState> firmwareBloc(Ble ble) =>
    FirmwareBloc(RecordedFirmware(ble));

/// The replaced uploads end Cancelled(replaced), and the last one is done
/// once its handler is.
Future<void> waitOut() async {
  await delay(200);
  require(jobs.length == 3, 'every upload must reach the controller');
  for (final (index, job) in jobs.indexed) {
    final outcome = await job.done;
    final expected = index == 2 ? 'Done(null)' : 'Cancelled(replaced)';
    require('$outcome' == expected,
        'upload $index must end $expected: $outcome');
  }
  jobs.clear();
}
''' + FLASHING + RUNNER)

unbuilt = solo.unbuilt()
assert not unbuilt, f'blocks of the solo page no driver builds: {unbuilt}'

d = f'{ROOT}/bloc_pages_check/bin/v'
os.makedirs(d, exist_ok=True)
for key, body in FILES.items():
    open(f'{d}/{key}.dart', 'w').write(body)

open(f'{ROOT}/bloc_pages_check/pubspec.yaml', 'w').write(PUBSPEC)
with open(os.path.join(REPO, 'packages', 'async_job',
                       'analysis_options.yaml')) as rules:
    open(f'{ROOT}/bloc_pages_check/async_job_rules.yaml', 'w').write(
        rules.read())
open(f'{ROOT}/bloc_pages_check/analysis_options.yaml', 'w').write(OPTIONS)
print('wrote', len(FILES), 'files under', ROOT)
