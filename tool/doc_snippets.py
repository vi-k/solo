"""Builds runnable scenarios from packages/solo/doc/vs-bloc.md.

Every snippet is copied byte-identical out of the markdown and wrapped in a
runnable file: fakes above it, a driver below it. That is what keeps the
document honest -- the code in it is the code that ran.

Usage, from the repository root:

    python3 tool/doc_snippets.py [workdir]      # default: /tmp/solo-doc-check

It creates two packages under the workdir, bloc_check (bloc 9 with
bloc_concurrency) and solo_check (a path dependency on packages/solo), and
writes bin/v/item1..11.dart into each. Then:

    dart pub get
    dart analyze bin/v
    dart run bin/v/item1.dart          # and so on, up to item11

The traces the document quotes come from those runs. The main ten drivers
use wall-clock fakes with timing margins. The Loading cancellation driver
uses FakeAsync and completers, checking each state transition explicitly.
"""
import os
import re
import shutil
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = sys.argv[1] if len(sys.argv) > 1 else '/tmp/solo-doc-check'
DOC = os.path.join(REPO, 'packages', 'solo', 'doc', 'vs-bloc.md')

BLOC_PUBSPEC = """name: bloc_check
publish_to: none

environment:
  sdk: ^3.6.0

dependencies:
  bloc: ^9.0.0
  bloc_concurrency: ^0.3.0
  fake_async: ^1.3.1
"""

SOLO_PUBSPEC = """name: solo_check
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

# What a snippet declares at column 0: a type, or a top-level function.
DECLARES = re.compile(
    r'^(?:(?:final|abstract|sealed|base|interface) )*'
    r'(?:class|enum|mixin|extension|typedef)\s+(\w+)'
    r'|^[A-Za-z_][\w<>,?\[\] ]*\s(\w+)\s*\(', re.M)

doc = open(DOC).read()
parts = re.split(r'\n## ', doc)

# A snippet is addressed by section and by a name it declares -- '1/NotesBloc'
# -- so that inserting a block into a section does not renumber the rest.
# A block declaring several names answers to each of them. A name declared
# twice in one section answers to neither: the entry is poisoned, and a use
# of it fails here instead of quietly building the wrong file. A block that
# declares nothing is addressed by its first line instead, slugified:
# '3/if-event-is-cancelrefresh'. Nothing here is addressed by position.
snips = {}
for p in parts[1:]:
    n = p.split('.')[0].strip()
    for j, b in enumerate(re.findall(r'```dart\n(.*?)```', p, re.S)):
        slug = re.sub(r'[^a-z0-9]+', '-', b.split('\n')[0].lower()).strip('-')
        names = [a or c for a, c in DECLARES.findall(b)] or [slug[:30]]
        for name in names:
            key = f'{n}/{name}'
            snips[key] = None if key in snips else b

TRACE = '''
final trace = <String>[];

Future<void> tick(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

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

BLE = '''
class Chunk {
  const Chunk(this.index);
  final int index;
}

class Ble {
  final written = <int>[];

  Future<void> connect() async {
    trace.add('connect');
    await tick(30);
  }

  Future<int> battery() async {
    trace.add('battery');
    await tick(10);
    return 100;
  }

  Future<void> rename(String name) async {
    trace.add('rename $name');
    await tick(10);
  }

  Future<void> disconnect() async {
    trace.add('disconnect');
    await tick(10);
  }

  // A BLE write cannot be told to stop: the chunk handed to the stack
  // lands, and the only way to keep the wire clear is to wait for it.
  Future<void> write(Chunk chunk) async {
    trace.add('write ${chunk.index} start');
    await tick(20);
    written.add(chunk.index);
    trace.add('write ${chunk.index} end');
  }
}
'''

PLAYER = '''
class Player {
  Future<void> play() async {
    trace.add('play start');
    await tick(30);
    trace.add('play end');
  }

  Future<void> pause() async {
    trace.add('pause start');
    await tick(30);
    trace.add('pause end');
  }

  // The native seek watches the token: told to stop, it stops and
  // returns instead of running to the requested position.
  Future<void> seek(Duration position, {CancelToken? cancelToken}) async {
    final ms = position.inMilliseconds;
    trace.add('seek $ms start');
    for (var step = 0; step < 3; step++) {
      await tick(10);
      if (cancelToken?.cancelled ?? false) {
        trace.add('seek $ms stopped');
        return;
      }
    }
    trace.add('seek $ms end');
  }
}
'''

# The fake records the two moments the section turns on: when the server
# takes the note, and what `list` saw when it read. The snapshot is taken
# before the wait on purpose -- that is a response in flight.
NOTES_API = '''
class Note {
  Note(this.id);
  final String id;
  @override
  String toString() => id;
}

class Api {
  final _server = <Note>[Note('n0')];

  Future<void> upload(Note note) async {
    trace.add('upload $note starts');
    await tick(40);
    _server.add(note);
    trace.add('server receives $note and holds $_server');
  }

  Future<List<Note>> list() async {
    final snapshot = List<Note>.from(_server);
    trace.add('list reads $snapshot');
    await tick(60);
    return snapshot;
  }
}
'''

PAY_API = '''
class Order {
  const Order(this.id);
  final String id;
}

class Receipt {
  const Receipt(this.orderId);
  final String orderId;
  String get id => 'R-$orderId';
  @override
  String toString() => 'Receipt(for $orderId)';
}

class Api {
  int calls = 0;

  Future<Receipt> pay(Order order) async {
    calls++;
    await tick(30);
    return Receipt(order.id);
  }
}

'''

MAP_API = '''
class MapApi {
  Future<void> moveTo(Point<double> point, {CancelToken? cancelToken}) async {
    final n = point.x.toInt();
    trace.add('moveTo $n start');
    // Native calls do not all take the same time.
    for (var left = 80 - 20 * n; left > 0; left -= 10) {
      await tick(10);
      if (cancelToken?.cancelled ?? false) {
        trace.add('moveTo $n stopped');
        return;
      }
    }
    trace.add('moveTo $n end');
  }

  Future<void> setZoom(double value, {CancelToken? cancelToken}) async {
    for (var left = 20; left > 0; left -= 10) {
      await tick(10);
      if (cancelToken?.cancelled ?? false) {
        return;
      }
    }
  }
}

class MapState {
  const MapState({this.center = const Point<double>(0, 0), this.zoom = 1});
  final Point<double> center;
  final double zoom;
  MapState copyWith({Point<double>? center, double? zoom}) =>
      MapState(center: center ?? this.center, zoom: zoom ?? this.zoom);
  @override
  String toString() => 'MapState(${center.x.toInt()}, z${zoom.toInt()})';
}
'''

CHAT_API = '''
class Api {
  /// Reads reported to the server. The point of the scenario is that a
  /// reply the user never saw must not be one of them.
  int reads = 0;

  Future<String> send(String text) async {
    await tick(50);
    return 'reply to $text';
  }

  Future<void> markRead() async {
    reads++;
    await tick(10);
  }
}

class ChatState {
  const ChatState([this.reply]);
  final String? reply;
  ChatState withReply(String reply) => ChatState(reply);
  @override
  String toString() => 'ChatState($reply)';
}
'''

SENSOR = '''
class Sensor {
  void Function(Object error)? onError;
  int zeroed = 0;
  int sampled = 0;

  Future<void> zero() async {
    await tick(20);
    zeroed++;
  }

  Future<void> sample() async {
    await tick(20);
    sampled++;
  }

  void fail(Object error) => onError?.call(error);
}
'''

BLOC_IMPORTS = """import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
"""

BLOC_PLAIN_IMPORTS = """import 'dart:async';

import 'package:bloc/bloc.dart';
"""

BLOC_MAP_IMPORTS = """import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';
"""

SOLO_IMPORTS = """// ignore_for_file: unreachable_from_main
import 'dart:async';

import 'package:solo/solo.dart';
"""

SOLO_MAP_IMPORTS = """// ignore_for_file: unreachable_from_main
import 'dart:async';
import 'dart:math';

import 'package:solo/solo.dart';
"""

FILES = {}

# --------------------------------------------------------------- item 7 bloc
FILES['bloc/item7'] = (BLOC_IMPORTS + TRACE + BLE + '''
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

class DeviceState {
  const DeviceState({this.online = false, this.battery});
  final bool online;
  final int? battery;
  DeviceState copyWith({bool? online, int? battery}) => DeviceState(
        online: online ?? this.online,
        battery: battery ?? this.battery,
      );
  @override
  String toString() => 'DeviceState($online, b:$battery)';
}

''' + snips['7/DeviceBloc'] + '\n' + snips['7/FlagDeviceBloc'] + '''
// The document quotes the flag and the generation among the device calls,
// because the moment they are written is the whole point. They are recorded
// here and not in the snippets: the code in the document is the code that
// runs, and it does not log.
class TracedFlagDeviceBloc extends FlagDeviceBloc {
  TracedFlagDeviceBloc(super.ble);
  bool _seen = false;

  @override
  void onEvent(DeviceEvent event) {
    super.onEvent(event);
    if (_leaving != _seen) {
      _seen = _leaving;
      trace.add('_leaving = $_leaving');
    }
  }
}

class TracedDeviceBloc extends DeviceBloc {
  TracedDeviceBloc(super.ble);
  int _seen = 0;

  @override
  void onEvent(DeviceEvent event) {
    super.onEvent(event);
    if (_screen != _seen) {
      _seen = _screen;
      trace.add('_screen = $_screen');
    }
  }
}

Future<void> run(Bloc<DeviceEvent, DeviceState> bloc, String label) async {
  trace.clear();
  bloc
    ..add(Connect())
    ..add(ReadBattery())
    ..add(Rename('kitchen'))
    ..add(Disconnect());
  await tick(300);
  print('$label leaving:     $trace');
  trace.clear();
  await bloc.close();
}

Future<void> runReopen(
  Bloc<DeviceEvent, DeviceState> bloc,
  String label,
) async {
  trace.clear();
  bloc
    ..add(Connect())
    ..add(ReadBattery())
    ..add(Rename('kitchen'))
    ..add(Disconnect())
    ..add(Connect());
  await tick(300);
  print('$label reopen fast: $trace');
  await bloc.close();
}

Future<void> main() async {
  await run(TracedFlagDeviceBloc(Ble()), 'a flag,');
  await runReopen(TracedFlagDeviceBloc(Ble()), 'a flag,');

  trace.clear();
  final bloc = TracedDeviceBloc(Ble());
  bloc
    ..add(Connect())
    ..add(ReadBattery())
    ..add(Rename('kitchen'))
    ..add(Disconnect());
  await tick(300);
  print('hardware:    $trace');
  print('state: ${bloc.state}');
  await bloc.close();

  await runReopen(TracedDeviceBloc(Ble()), 'a stamp,');

  // The screen that comes back asks for the battery through the same
  // canonical value, so its add overwrites the stamp the queued read got.
  trace.clear();
  final shared = TracedDeviceBloc(Ble());
  const read = ReadBattery();
  shared
    ..add(Connect())
    ..add(read)
    ..add(Rename('kitchen'))
    ..add(Disconnect())
    ..add(Connect())
    ..add(read);
  await tick(300);
  print('shared event: $trace');
  await shared.close();
}
''')

# --------------------------------------------------------------- item 7 solo
FILES['solo/item7'] = (SOLO_IMPORTS + TRACE + BLE + '''
sealed class DeviceState {
  const DeviceState();
}

final class Offline extends DeviceState {
  const Offline();
  @override
  String toString() => 'Offline';
}

final class Connected extends DeviceState {
  const Connected({this.battery});
  final int? battery;
  Connected copyWith({int? battery}) =>
      Connected(battery: battery ?? this.battery);
  @override
  String toString() => 'Connected(b:$battery)';
}

''' + snips['7/DeviceController'] + '''
Future<void> main() async {
  final device = DeviceController(Ble());
  final connect = device.connect();
  final battery = device.readBattery();
  final rename = device.rename('kitchen');
  final disconnect = device.disconnect();
  await tick(300);
  print('hardware: $trace');
  print('connect ${connect.outcome}  battery ${battery.outcome}');
  print('rename ${rename.outcome}');
  print('disconnect ${disconnect.outcome}  state ${device.currentState}');
  await device.close();

  // `removeWhere` is about the queue. A read that has already started is
  // not in it, so disconnect removes nothing and waits for it.
  trace.clear();
  final started = DeviceController(Ble());
  await started.connect().done;
  final reading = started.readBattery();
  await tick(5);
  final leave = started.disconnect();
  await tick(100);
  print('read already running: $trace, battery ${reading.outcome}, '
      'disconnect ${leave.outcome}');
  if (reading.outcome is! Done) {
    throw StateError('a running read must survive removeWhere');
  }
  await started.close();

  // `run<Offline, void>` is what makes connect a connect. The rule is
  // checked when the job starts and not when it is made, so a connect
  // queued behind a disconnect still runs.
  final second = DeviceController(Ble());
  await second.connect().done;
  final refused = second.connect();
  await tick(50);
  final off = second.disconnect();
  final back = second.connect();
  await tick(100);
  print('refused ${refused.outcome}  off ${off.outcome}  back '
      '${back.outcome}  state ${second.currentState}');
  if (refused.outcome is! Cancelled || back.outcome is! Done) {
    throw StateError('the state rule must refuse only the second connect');
  }
  await second.close();
}
''')

# --------------------------------------------------------------- item 5 bloc
PLAYER_EVENTS = '''
sealed class PlayerCommand {}

class Play extends PlayerCommand {}

class Pause extends PlayerCommand {}

class Seek extends PlayerCommand {
  Seek(this.position);
  final Duration position;
}

class PlayerState {
  const PlayerState({this.position = Duration.zero});
  final Duration position;
  @override
  String toString() => 'PlayerState(${position.inMilliseconds}ms)';
}
'''

FILES['bloc/item5'] = (BLOC_IMPORTS + TRACE + PLAYER + PLAYER_EVENTS + '\n'
                       + snips['5/PlayerBloc'] + '\n'
                       + snips['5/SplitPlayerBloc'] + '\n'
                       + snips['5/SerialPlayerBloc'] + '''
Future<void> main() async {
  final split = SplitPlayerBloc(Player());
  split
    ..add(Play())
    ..add(Seek(const Duration(milliseconds: 1)))
    ..add(Seek(const Duration(milliseconds: 2)))
    ..add(Seek(const Duration(milliseconds: 3)))
    ..add(Pause());
  await tick(300);
  print('a registration each: ${callsOf(trace)}');
  print('  full:  $trace');
  print('  state ${split.state}');
  await split.close();
  trace.clear();

  final serial = SerialPlayerBloc(Player());
  serial
    ..add(Play())
    ..add(Seek(const Duration(milliseconds: 1)))
    ..add(Seek(const Duration(milliseconds: 2)))
    ..add(Seek(const Duration(milliseconds: 3)))
    ..add(Pause());
  await tick(300);
  print('one queue, no replacement: ${callsOf(trace)}');
  print('  full:  $trace');
  print('  state ${serial.state}');
  await serial.close();
  trace.clear();

  final bloc = PlayerBloc(Player());
  bloc
    ..add(Play())
    ..add(Seek(const Duration(milliseconds: 1)))
    ..add(Seek(const Duration(milliseconds: 2)))
    ..add(Seek(const Duration(milliseconds: 3)))
    ..add(Pause());
  await tick(300);
  print('drag calls: ${callsOf(trace)}');
  print('drag full:  $trace');
  print('state ${bloc.state}');
  await bloc.close();

  trace.clear();
  final b2 = PlayerBloc(Player());
  final seen = <PlayerState>[];
  final sub = b2.stream.listen(seen.add);
  b2.add(Seek(const Duration(milliseconds: 1)));
  await tick(15);
  b2.add(Seek(const Duration(milliseconds: 3)));
  await tick(300);
  print('in-flight: $trace');
  print('published: $seen  state ${b2.state}');
  await sub.cancel();
  await b2.close();

  // A drag that comes back to a position it already had: the field holds
  // the position, not which event is newest.
  trace.clear();
  final b3 = PlayerBloc(Player());
  b3
    ..add(Play())
    ..add(Seek(const Duration(milliseconds: 1)))
    ..add(Seek(const Duration(milliseconds: 2)))
    ..add(Seek(const Duration(milliseconds: 1)))
    ..add(Pause());
  await tick(300);
  print('returning drag: ${callsOf(trace)}');
  await b3.close();
}
''')

# --------------------------------------------------------------- item 5 solo
FILES['solo/item5'] = (SOLO_IMPORTS + TRACE + PLAYER + '''
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

''' + snips['5/PlayerController'] + '''
Future<void> main() async {
  final player = PlayerController(Player())
    ..play()
    ..seek(const Duration(milliseconds: 1))
    ..seek(const Duration(milliseconds: 2))
    ..seek(const Duration(milliseconds: 3))
    ..pause();
  await tick(300);
  print('drag calls: ${callsOf(trace)}');
  print('drag full:  $trace');
  print('state ${player.currentState}');
  await player.close();

  trace.clear();
  final p2 = PlayerController(Player());
  final seen = <PlayerState>[];
  final sub = p2.stream.listen(seen.add);
  final stale = p2.seek(const Duration(milliseconds: 1));
  await tick(15);
  p2.seek(const Duration(milliseconds: 3));
  await tick(300);
  print('in-flight: $trace');
  print('published: $seen  state ${p2.currentState}');
  print('stale job ${stale.outcome}');
  await sub.cancel();
  await p2.close();
}
''')

# --------------------------------------------------------------- item 1 bloc
# The notes and, only when the write changed it, the flag: a trace of the
# fields a publication left alone reads as if it had set them.
NOTES_EMITTED = '''
String emitted(NotesState previous, NotesState next) =>
    'emits ${next.notes}'
    '${next.uploading == previous.uploading ? '' : ', '
        'uploading: ${next.uploading}'}';
'''

NOTES_EVENTS = '''
sealed class NotesEvent {}

class UploadNote extends NotesEvent {
  UploadNote(this.note);
  final Note note;
}

class RefreshList extends NotesEvent {}

class NotesState {
  const NotesState({this.notes = const [], this.uploading = false});
  final List<Note> notes;
  final bool uploading;
  NotesState copyWith({List<Note>? notes, bool? uploading}) => NotesState(
        notes: notes ?? this.notes,
        uploading: uploading ?? this.uploading,
      );
  @override
  String toString() => 'NotesState($notes, uploading: $uploading)';
}
'''

FILES['bloc/item1'] = (BLOC_IMPORTS + TRACE + NOTES_API + NOTES_EVENTS
                       + NOTES_EMITTED + '\n'
                       + snips['1/SplitNotesBloc'] + '\n'
                       + snips['1/ConcurrentNotesBloc'] + '\n'
                       + snips['1/NotesBloc'] + '''
/// The third way, the one the document keeps in prose: the same two
/// registrations, with the refresh written in one line. `state` is the
/// receiver, so it is read before the awaited argument.
class InlineNotesBloc extends Bloc<NotesEvent, NotesState> {
  final Api _api;

  InlineNotesBloc(this._api) : super(const NotesState()) {
    on<UploadNote>((e, emit) async {
      emit(state.copyWith(uploading: true));
      await _api.upload(e.note);
      emit(state.copyWith(notes: [...state.notes, e.note], uploading: false));
    }, transformer: sequential());
    on<RefreshList>((e, emit) async {
      emit(state.copyWith(notes: await _api.list()));
    }, transformer: sequential());
  }
}

/// Every publication, in the order it happened and with the event that
/// made it. `onTransition` runs inside `emit`, so these entries interleave
/// with the API's own truthfully.
mixin TracedNotes on Bloc<NotesEvent, NotesState> {
  @override
  void onTransition(Transition<NotesEvent, NotesState> transition) {
    trace.add(
      '${transition.event.runtimeType} '
      '${emitted(transition.currentState, transition.nextState)}',
    );
    super.onTransition(transition);
  }
}

class TracedSplit extends SplitNotesBloc with TracedNotes {
  TracedSplit(Api api) : super(api);
}

class TracedConcurrent extends ConcurrentNotesBloc with TracedNotes {
  TracedConcurrent(Api api) : super(api);
}

class TracedInline extends InlineNotesBloc with TracedNotes {
  TracedInline(Api api) : super(api);
}

class TracedFunnel extends NotesBloc with TracedNotes {
  TracedFunnel(Api api) : super(api);
}

Future<void> run(Bloc<NotesEvent, NotesState> bloc, String label) async {
  trace.clear();
  bloc
    ..add(UploadNote(Note('n1')))
    ..add(RefreshList());
  await tick(300);
  print('$label ${bloc.state}');
  for (final entry in trace) {
    print('    $entry');
  }
  await bloc.close();
}

Future<void> main() async {
  await run(TracedSplit(Api()), 'a transformer per handler:  ');
  await run(TracedConcurrent(Api()), 'one handler, no transformer:');
  await run(TracedInline(Api()), 'the one-line refresh:       ');
  await run(TracedFunnel(Api()), 'one handler, sequential:    ');
}
''')

# --------------------------------------------------------------- item 1 solo
FILES['solo/item1'] = (SOLO_IMPORTS + TRACE + NOTES_API + NOTES_EMITTED + '''
final class NotesState {
  const NotesState({this.notes = const [], this.uploading = false});
  final List<Note> notes;
  final bool uploading;
  NotesState copyWith({List<Note>? notes, bool? uploading}) => NotesState(
        notes: notes ?? this.notes,
        uploading: uploading ?? this.uploading,
      );
  @override
  String toString() => 'NotesState($notes, uploading: $uploading)';
}

''' + snips['1/NotesController'] + '''
/// The same trace as the bloc bench: `onChange` runs inside the change,
/// and the transition names the job that made it.
final class TracedNotesController extends NotesController {
  TracedNotesController(super.api);

  @override
  void onChange(SoloTransition<NotesState> transition) {
    trace.add(
      '${transition.job?.key} '
      '${emitted(transition.previous, transition.current)}',
    );
  }
}

Future<void> main() async {
  final notes = TracedNotesController(Api())
    ..upload(Note('n1'))
    ..refresh();
  await tick(300);
  print('final: ${notes.currentState}');
  for (final entry in trace) {
    print('    $entry');
  }
  await notes.close();
}
''')

# --------------------------------------------------------------- item 10 bloc
FILES['bloc/item10'] = (BLOC_IMPORTS + TRACE + BLE + '''
sealed class FirmwareEvent {}

class Flash extends FirmwareEvent {
  Flash(this.chunks);
  final List<Chunk> chunks;
}

class HardwareFailed extends FirmwareEvent {
  HardwareFailed(this.error);
  final Object error;
}

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
  String toString() => 'Flashing($written/$total)';
}

class Broken extends FirmwareState {
  Broken(this.error);
  final Object error;
  @override
  String toString() => 'Broken($error)';
}

''' + snips['10/UnguardedFirmwareBloc'] + snips['10/FirmwareBloc']
                       + snips['10/LockedFirmwareBloc'] + '''
/// The same loop, with the failure arriving as a state instead of a restart.
class GuardedFirmwareBloc extends Bloc<FirmwareEvent, FirmwareState> {
  GuardedFirmwareBloc(this._ble) : super(Idle()) {
    on<HardwareFailed>((e, emit) => emit(Broken(e.error)));
    on<Flash>((e, emit) async {
      var written = 0;
      for (final chunk in e.chunks) {
        await _ble.write(chunk);
        if (emit.isDone) return;
        emit(Flashing(++written, e.chunks.length));
      }
    }, transformer: restartable());
  }

  final Ble _ble;
}

Future<void> main() async {
  final ble = Ble();
  final bloc = FirmwareBloc(ble);
  bloc.add(Flash([for (var i = 0; i < 6; i++) Chunk(i)]));
  await tick(30);
  bloc.add(Flash([for (var i = 100; i < 106; i++) Chunk(i)]));
  await tick(300);
  print('restart: written ${ble.written}, state ${bloc.state}');
  print('restart trace: ${trace.take(6).toList()}');
  await bloc.close();

  trace.clear();
  final ble1 = Ble();
  final unguarded = UnguardedFirmwareBloc(ble1);
  unguarded.add(Flash([for (var i = 0; i < 6; i++) Chunk(i)]));
  await tick(30);
  unguarded.add(Flash([for (var i = 100; i < 106; i++) Chunk(i)]));
  await tick(300);
  print('without the line: written ${ble1.written}');
  await unguarded.close();

  final ble2 = Ble();
  final guarded = GuardedFirmwareBloc(ble2);
  guarded.add(Flash([for (var i = 0; i < 6; i++) Chunk(i)]));
  await tick(30);
  guarded.add(HardwareFailed('cable unplugged'));
  await tick(300);
  print('Broken as a state: written ${ble2.written}, '
      'state ${guarded.state}');
  await guarded.close();

  trace.clear();
  final ble3 = Ble();
  final locked = LockedFirmwareBloc(ble3);
  locked.add(Flash([for (var i = 0; i < 6; i++) Chunk(i)]));
  await tick(30);
  locked.add(Flash([for (var i = 100; i < 106; i++) Chunk(i)]));
  await tick(400);
  print('wire under a lock: written ${ble3.written}');
  print('locked trace: ${trace.take(6).toList()}');
  await locked.close();
}
''')

# --------------------------------------------------------------- item 10 solo
FILES['solo/item10'] = (SOLO_IMPORTS + TRACE + BLE + '''
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
  String toString() => 'Flashing($written/$total)';
}

final class Broken extends FirmwareState {
  Broken(this.error);
  final Object error;
  @override
  String toString() => 'Broken($error)';
}

''' + snips['10/FirmwareController'] + '''
extension on FirmwareController {
  // ignore: invalid_use_of_protected_member
  void hardwareFailed(Object error) => externalSetState(Broken(error));
}

Future<void> main() async {
  final ble = Ble();
  final firmware = FirmwareController(ble);
  final first = firmware.flash([for (var i = 0; i < 6; i++) Chunk(i)]);
  await tick(30);
  final second = firmware.flash([for (var i = 100; i < 106; i++) Chunk(i)]);
  await tick(300);
  print('restart: written ${ble.written}, state ${firmware.currentState}');
  print('restart trace: ${trace.take(6).toList()}');
  print('first ${first.outcome}  second ${second.outcome}');
  await firmware.close();

  trace.clear();
  final ble2 = Ble();
  final f2 = FirmwareController(ble2);
  final job = f2.flash([for (var i = 0; i < 6; i++) Chunk(i)]);
  await tick(50);
  f2.hardwareFailed('cable unplugged');
  await tick(300);
  print('Broken from outside: written ${ble2.written}, ${job.outcome}');
  print('Broken trace: $trace');
  await f2.close();
}
''')

# --------------------------------------------------------------- item 8 bloc
FILES['bloc/item8'] = (BLOC_IMPORTS + TRACE + PAY_API + '''
sealed class CheckoutEvent {}

sealed class CheckoutState {}

class Cart extends CheckoutState {}

class Paying extends CheckoutState {}

class Paid extends CheckoutState {
  Paid(this.receipt);
  final Receipt receipt;
}

class PaymentFailed extends CheckoutState {
  PaymentFailed(this.error);
  final Object error;
}

''' + snips['8/Pay'] + snips['8/CheckoutBloc'] + snips['8/CheckoutCubit'] + '''
/// The cubit the paragraph before the snippet describes: a method you can
/// await, and nothing around it.
class PlainCheckoutCubit extends Cubit<CheckoutState> {
  PlainCheckoutCubit(this._api) : super(Cart());

  final Api _api;

  Future<Receipt> pay(Order order) async {
    emit(Paying());
    final receipt = await _api.pay(order);
    emit(Paid(receipt));
    return receipt;
  }
}

/// What a caller got, or that it is still waiting long after the charge.
Future<String> answered(Future<Receipt> result) => result.then(
      (receipt) => '$receipt',
      onError: (Object error) => '$error',
    ).timeout(
      const Duration(milliseconds: 200),
      onTimeout: () => 'never answered',
    );

Future<void> main() async {
  final droppableApi = Api();
  final droppable = DroppableCheckoutBloc(droppableApi);
  final dropped = await Future.wait([
    answered(droppable.pay(const Order('A'))),
    answered(droppable.pay(const Order('A'))),
    answered(droppable.pay(const Order('B'))),
  ]);
  print('droppable: api.pay calls ${droppableApi.calls}, $dropped');
  await droppable.close();

  final api = Api();
  final bloc = CheckoutBloc(api);
  // Three calls for two orders: one order twice, then a different one.
  final receipts = await Future.wait([
    bloc.pay(const Order('A')),
    bloc.pay(const Order('A')),
    bloc.pay(const Order('B')),
  ]);
  print('bloc: api.pay calls ${api.calls}, $receipts');
  await bloc.close();

  final closed = CheckoutBloc(Api());
  await closed.close();
  try {
    await closed.pay(const Order('C'));
  } on Object catch (error) {
    print('bloc pay after close: $error');
  }

  final plainApi = Api();
  final plain = PlainCheckoutCubit(plainApi);
  await Future.wait([
    plain.pay(const Order('A')),
    plain.pay(const Order('A')),
  ]);
  print('plain cubit: api.pay calls ${plainApi.calls}');
  await plain.close();

  final cubitApi = Api();
  final cubit = CheckoutCubit(cubitApi);
  final cubitReceipts = await Future.wait([
    cubit.pay(const Order('A')),
    cubit.pay(const Order('A')),
    cubit.pay(const Order('B')),
  ]);
  print('queued cubit: api.pay calls ${cubitApi.calls}, $cubitReceipts');
  await cubit.close();

  final closingApi = Api();
  final closing = CheckoutCubit(closingApi);
  final pending = closing.pay(const Order('C'));
  await tick(10);
  await closing.close();
  try {
    print('cubit close mid-payment: ${await pending}');
  } on Object catch (error) {
    print('cubit close mid-payment: $error');
  }
  await tick(60);
  print('  api.pay calls after that: ${closingApi.calls}');
}
''')

# --------------------------------------------------------------- item 8 solo
FILES['solo/item8'] = (SOLO_IMPORTS + TRACE + PAY_API + '''
sealed class CheckoutState {
  const CheckoutState();
}

final class Cart extends CheckoutState {
  const Cart();
  @override
  String toString() => 'Cart';
}

final class Paying extends CheckoutState {
  const Paying();
  @override
  String toString() => 'Paying';
}

final class Paid extends CheckoutState {
  const Paid(this.receipt);
  final Receipt receipt;
  @override
  String toString() => 'Paid($receipt)';
}

''' + snips['8/CheckoutController'] + '\n' + snips['8/handlePayRequest'] + '''
Future<void> main() async {
  final dedupe = CheckoutController(Api());
  final callA = dedupe.pay(const Order('Z'));
  final callB = dedupe.pay(const Order('Z'));
  print('second call, same handle: ${identical(callA, callB)}');
  await tick(100);
  await dedupe.close();

  final api = Api();
  final checkout = CheckoutController(api);
  // Three calls for two orders: one order twice, then a different one.
  final replies = await Future.wait([
    handlePayRequest(checkout, const Order('A')),
    handlePayRequest(checkout, const Order('A')),
    handlePayRequest(checkout, const Order('B')),
  ]);
  print('api.pay calls: ${api.calls}, $replies');
  await checkout.close();

  final closingApi = Api();
  final closing = CheckoutController(closingApi);
  final inFlight = handlePayRequest(closing, const Order('C'));
  await tick(10);
  await closing.close();
  print('close mid-payment: ${await inFlight}, '
      'state ${closing.currentState}');

  final pendingApi = Api();
  final pending = CheckoutController(pendingApi);
  final charging = pending.pay(const Order('A'));
  await tick(10);
  final queued = pending.pay(const Order('B'));
  unawaited(queued.cancel());
  unawaited(charging.cancel());
  print('queued cancelled: ${queued.outcome}');
  print('charge spared:    ${charging.isCancelled == false}');
  await tick(100);
  print('  A ${charging.outcome}, B ${queued.outcome}, '
      'api.pay calls ${pendingApi.calls}');
  await pending.close();

  final closed = CheckoutController(Api());
  await closed.close();
  final reply = await handlePayRequest(closed, const Order('D'));
  print('pay after close: $reply');
}
''')

# --------------------------------------------------------------- item 6 bloc
FILES['bloc/item6'] = (BLOC_MAP_IMPORTS.replace(
    "import 'package:bloc/bloc.dart';",
    "import 'package:bloc/bloc.dart';\n"
    "import 'package:bloc_concurrency/bloc_concurrency.dart';",
) + TRACE + MAP_API + '\n' + snips['6/MapCubit'] + '\n' + snips['6/CommandMapBloc'] + '''
final seenEvents = <String>[];

class _SeenEvents extends BlocObserver {
  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    seenEvents.add(event.runtimeType.toString());
  }
}

class _NoObserver extends BlocObserver {
  const _NoObserver();
}

Future<void> main() async {
  final cubit = MapCubit(MapApi());
  for (var i = 1; i <= 3; i++) {
    unawaited(cubit.moveTo(Point<double>(i.toDouble(), 0)));
  }
  await tick(300);
  print('drag: $trace  state ${cubit.state}');
  await cubit.close();

  trace.clear();
  // What an observer of this bloc is given for each command.
  Bloc.observer = _SeenEvents();
  final bloc = CommandMapBloc(MapApi());
  for (var i = 1; i <= 3; i++) {
    bloc.moveTo(Point<double>(i.toDouble(), 0));
  }
  bloc.setZoom(4);
  await tick(400);
  print('typed methods, one queue: $trace  state ${bloc.state}');
  print('an observer sees: $seenEvents');
  Bloc.observer = const _NoObserver();
  await bloc.close();
}
''')

# --------------------------------------------------------------- item 6 solo
FILES['solo/item6'] = (SOLO_MAP_IMPORTS + TRACE + MAP_API + '\n' + snips['6/MapController'] + '''
Future<void> main() async {
  final map = MapController(MapApi());
  onMapDrag(map, const Point<double>(1, 0));
  await tick(10);
  onMapDrag(map, const Point<double>(2, 0));
  onMapDrag(map, const Point<double>(3, 0));
  map.setZoom(4);
  await tick(300);
  print('drag: $trace  state ${map.currentState}');
  await map.close();
}
''')

# --------------------------------------------------------------- item 3 bloc
FILES['bloc/item3'] = (BLOC_IMPORTS + TRACE + CHAT_API + '''
sealed class ChatEvent {
  const ChatEvent();
}

class SendMessage extends ChatEvent {
  const SendMessage(this.text);
  final String text;
}

class MarkReplyRead extends ChatEvent {
  const MarkReplyRead();
}

''' + snips['3/ChatBloc'] + '\n' + snips['3/UnguardedChatBloc'] + '''

/// A future started inside the handler and left unawaited.
class LateChatBloc extends Bloc<ChatEvent, ChatState> {
  LateChatBloc(this._api) : super(const ChatState()) {
    on<SendMessage>((e, emit) async {
      unawaited(_api.send(e.text).then((reply) {
        emit(state.withReply(reply));
      }));
    }, transformer: sequential());
  }

  final Api _api;
}

Future<void> main() async {
  final api = Api();
  final chat = ChatBloc(api)..add(const SendMessage('hi'));
  await tick(10);
  final started = DateTime.now();
  await chat.close();
  print('close took ${DateTime.now().difference(started).inMilliseconds}ms, '
      'state ${chat.state}, reads reported ${api.reads}');
  try {
    chat.add(const SendMessage('bye'));
  } on Object catch (error) {
    print('add after close: $error');
  }

  await runZonedGuarded(() async {
    final api = Api();
    final unguarded = UnguardedChatBloc(api)..add(const SendMessage('hi'));
    await tick(10);
    final closing = DateTime.now();
    await unguarded.close();
    print('no guard: close took '
        '${DateTime.now().difference(closing).inMilliseconds}ms, '
        'state ${unguarded.state}, reads reported ${api.reads}');
  }, (error, _) {
    print('no guard, the follow-up add: $error');
  });

  await runZonedGuarded(() async {
    final late = LateChatBloc(Api())..add(const SendMessage('hi'));
    await tick(200);
    print('late emit: state ${late.state}');
    await late.close();
  }, (error, _) {
    final first = '$error'.split('\\n').where((l) => l.isNotEmpty).first;
    print('late emit raised: $first');
  });
}
''')

# --------------------------------------------------------------- item 3 solo
FILES['solo/item3'] = (SOLO_IMPORTS + TRACE + CHAT_API + '\n'
                       + snips['3/ChatController'] + '''
/// A future started inside a job and left unawaited.
final class LateChatController extends Solo<ChatState> {
  LateChatController(this._api) : super(const ChatState());

  final Api _api;

  Job<void> send(String text) => run<ChatState, void>(
        key: 'send',
        (ctx) async {
          unawaited(
            _api
                .send(text)
                .then((reply) => ctx.emit(ctx.state.withReply(reply))),
          );
        },
      );
}

Future<void> main() async {
  final api = Api();
  final chat = ChatController(api);
  final running = chat.send('hi');
  final queued = chat.send('and again');
  await tick(10);
  await onScreenClosed(chat);
  print('running ${running.outcome}  queued ${queued.outcome}');
  print('state after close: ${chat.currentState}, '
      'reads reported ${api.reads}');
  print('send after close: ${chat.send('later').outcome}');

  await runZonedGuarded(
    () async {
      final late = LateChatController(Api())..send('hi');
      await tick(200);
      print('late emit: state ${late.currentState}');
      await late.close();
    },
    (error, _) => print('late emit raised: $error'),
  );
}
''')

# --------------------------------------------------------------- item 9 bloc
FILES['bloc/item9'] = (BLOC_IMPORTS + TRACE + SENSOR + '''
sealed class SensorEvent {}

class Calibrate extends SensorEvent {}

class HardwareFailed extends SensorEvent {
  HardwareFailed(this.error);
  final Object error;
}

sealed class SensorState {}

class Ready extends SensorState {
  @override
  String toString() => 'Ready';
}

class Calibrated extends SensorState {
  @override
  String toString() => 'Calibrated';
}

class Broken extends SensorState {
  Broken(this.error);
  final Object error;
  @override
  String toString() => 'Broken($error)';
}

''' + snips['9/SensorBloc'] + '\n' + snips['9/FunnelSensorBloc'] + '''

Future<void> main() async {
  final hw = Sensor();
  final bloc = SensorBloc(hw);
  final states = <SensorState>[];
  final sub = bloc.stream.listen(states.add);
  bloc.add(Calibrate());
  await tick(25);
  hw.fail('cable unplugged');
  await tick(300);
  print('separate handlers: $states  final ${bloc.state}');
  print('zeroed=${hw.zeroed} sampled=${hw.sampled}');
  await sub.cancel();
  await bloc.close();

  final hw2 = Sensor();
  final funnel = FunnelSensorBloc(hw2);
  final states2 = <SensorState>[];
  final sub2 = funnel.stream.listen(states2.add);
  funnel.add(Calibrate());
  await tick(25);
  hw2.fail('cable unplugged');
  await tick(300);
  print('one funnel: $states2  final ${funnel.state}');
  await sub2.cancel();
  await funnel.close();
}
''')

# --------------------------------------------------------------- item 9 solo
FILES['solo/item9'] = (SOLO_IMPORTS + TRACE + SENSOR + '''
sealed class SensorState {
  const SensorState();
}

final class Ready extends SensorState {
  const Ready();
  @override
  String toString() => 'Ready';
}

final class Calibrated extends SensorState {
  const Calibrated();
  @override
  String toString() => 'Calibrated';
}

final class Broken extends SensorState {
  const Broken(this.error);
  final Object error;
  @override
  String toString() => 'Broken($error)';
}

''' + snips['9/SensorController'] + '''
Future<void> main() async {
  final hw = Sensor();
  final sensor = SensorController(hw);
  final states = <SensorState>[];
  final sub = sensor.stream.listen(states.add);
  final job = sensor.calibrate();
  await tick(25);
  hw.fail('cable unplugged');
  await tick(300);
  print('outcome: ${job.outcome}');
  print('states: $states  final ${sensor.currentState}');
  print('zeroed=${hw.zeroed} sampled=${hw.sampled}');
  await sub.cancel();
  await sensor.close();
}
''')

os.makedirs(f'{ROOT}/bloc_check', exist_ok=True)
os.makedirs(f'{ROOT}/solo_check', exist_ok=True)
open(f'{ROOT}/bloc_check/pubspec.yaml', 'w').write(BLOC_PUBSPEC)
open(f'{ROOT}/solo_check/pubspec.yaml', 'w').write(SOLO_PUBSPEC)
# The solo bench analyzes under the package's own lints, so a snippet that
# passes here passes in the package too.
shutil.copyfile(
    os.path.join(REPO, 'packages', 'solo', 'analysis_options.yaml'),
    f'{ROOT}/solo_check/analysis_options.yaml',
)

RECORDER = """
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

/// Where a guarded observer writes what telemetry could not take.
class Log {
  final entries = <String>[];

  void write(Object error, StackTrace stackTrace) => entries.add('$error');
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

class StartRecording {}
"""

# --------------------------------------------------------------- item 2 bloc
FILES['bloc/item2'] = (BLOC_PLAIN_IMPORTS + TRACE + RECORDER + '\n' + snips['2/RecorderBloc'] + '\n'
                       + snips['2/GuardedTelemetryObserver'] + '''
/// The same bloc with every hook that looks like a place to handle the
/// error overridden, to show that none of them is one: `emit` calls
/// `onError` on its way out and rethrows regardless.
class HandledRecorderBloc extends RecorderBloc {
  HandledRecorderBloc(super.recorder, super.journal);

  final reported = <String>[];

  @override
  void onError(Object error, StackTrace stackTrace) {
    reported.add('$error');
    super.onError(error, stackTrace);
  }
}

/// The journal written before the observer is called, against the note in
/// `onChange`'s own dartdoc: "`super.onChange` should always be called
/// first."
class JournalFirstRecorderBloc extends Bloc<StartRecording, RecorderState> {
  final Recorder _recorder;
  final Journal _journal;

  JournalFirstRecorderBloc(this._recorder, this._journal)
      : super(const Idle()) {
    on<StartRecording>((e, emit) async {
      await _recorder.start();
      emit(const Recording());
      _recorder.armMeter();
    });
  }

  @override
  void onChange(Change<RecorderState> change) {
    _journal.note('${change.nextState}');
    super.onChange(change);
  }
}

/// The same body as a cubit method, to show the caller's side of it.
class RecorderCubit extends Cubit<RecorderState> {
  final Recorder _recorder;

  RecorderCubit(this._recorder) : super(const Idle());

  Future<void> start() async {
    await _recorder.start();
    emit(const Recording());
    _recorder.armMeter();
  }
}

Future<void> go({required bool guarded}) async {
  final telemetry = Telemetry();
  final fallback = Log();
  Bloc.observer = guarded
      ? GuardedTelemetryObserver(telemetry, fallback)
      : TelemetryObserver(telemetry);

  final label = guarded ? 'guarded' : 'raw';
  // The bloc is built inside the zone: its event subscription is made in
  // the constructor, and a handler error surfaces in the zone that was
  // current then.
  final zone = <String>[];
  await runZonedGuarded(
    () async {
      final recorder = Recorder();
      final journal = Journal();
      final bloc = RecorderBloc(recorder, journal);
      bloc.add(StartRecording());
      await tick(20);
      print('$label bloc: state ${bloc.state}, journal ${journal.entries}, '
          'trace ${recorder.trace}, fallback ${fallback.entries}');
      await bloc.close();

      final native = Recorder();
      final cubit = RecorderCubit(native);
      Object? caught;
      try {
        await cubit.start();
      } on Object catch (error) {
        caught = error;
      }
      print('$label cubit: state ${cubit.state}, caller error $caught, '
          'trace ${native.trace}');
      await cubit.close();
    },
    (error, _) => zone.add('$error'),
  );
  print('$label zone: $zone');
}

/// What an overridden `onError` buys, with the observer still throwing.
Future<void> handled() async {
  Bloc.observer = TelemetryObserver(Telemetry());
  final zone = <String>[];
  await runZonedGuarded(
    () async {
      final recorder = Recorder();
      final journal = Journal();
      final bloc = HandledRecorderBloc(recorder, journal);
      bloc.add(StartRecording());
      await tick(20);
      print('onError overridden: state ${bloc.state}, '
          'trace ${recorder.trace}, reported ${bloc.reported}');
      await bloc.close();
    },
    (error, _) => zone.add('$error'),
  );
  print('onError overridden, still escaped to the zone: $zone');
}

/// What the local hook gets by going before `super`, and what it does not.
Future<void> journalFirst() async {
  Bloc.observer = TelemetryObserver(Telemetry());
  final zone = <String>[];
  await runZonedGuarded(
    () async {
      final recorder = Recorder();
      final journal = Journal();
      final bloc = JournalFirstRecorderBloc(recorder, journal);
      bloc.add(StartRecording());
      await tick(20);
      print('journal before super: state ${bloc.state}, '
          'journal ${journal.entries}, trace ${recorder.trace}');
      await bloc.close();
    },
    (error, _) => zone.add('$error'),
  );
  print('journal before super, zone: $zone');
}

Future<void> main() async {
  await go(guarded: false);
  await go(guarded: true);
  await handled();
  await journalFirst();
}
''')

# --------------------------------------------------------------- item 2 solo
FILES['solo/item2'] = (SOLO_IMPORTS + TRACE + RECORDER + '\n' + snips['2/RecorderController'] + '''
Future<void> main() async {
  SoloBase.observer = TelemetryObserver(Telemetry());
  final recorder = Recorder();
  final journal = Journal();
  final controller = RecorderController(recorder, journal);
  final zone = <String>[];
  await runZonedGuarded(
    () async {
      final outcome = await controller.start().done;
      print('solo: state ${controller.currentState}, outcome $outcome, '
          'journal ${journal.entries}, trace ${recorder.trace}');
    },
    (error, _) => zone.add('$error'),
  );
  print('zone: $zone');
  await controller.close();
}
''')

PREVIEW = """
class Clip {
  final int id;

  const Clip(this.id);

  @override
  String toString() => 'clip $id';
}

/// A native PCM buffer. Releasing it is not optional.
class Buffer {
  final Clip clip;
  final List<String> trace;
  final released = Completer<void>();
  int releases = 0;

  Buffer(this.clip, this.trace);

  int waveform() {
    trace.add('sample ${clip.id}');
    return clip.id;
  }

  Future<void> release() async {
    releases++;
    trace.add('release ${clip.id}');
    released.complete();
  }
}

/// A decoder whose answers the driver hands out one at a time.
class Decoder {
  final trace = <String>[];
  final asked = <int, Completer<void>>{};
  final answers = <int, Completer<Buffer>>{};

  Future<Buffer> open(Clip clip) {
    trace.add('open ${clip.id}');
    (asked[clip.id] ??= Completer<void>()).complete();
    return (answers[clip.id] ??= Completer<Buffer>()).future;
  }

  Future<void> whenAsked(int id) => (asked[id] ??= Completer<void>()).future;

  Buffer deliver(Clip clip) {
    final buffer = Buffer(clip, trace);
    trace.add('ready ${clip.id}');
    (answers[clip.id] ??= Completer<Buffer>()).complete(buffer);
    return buffer;
  }
}

sealed class PreviewState {
  const PreviewState();
}

final class NoPreview extends PreviewState {
  const NoPreview();

  @override
  String toString() => 'NoPreview';
}

final class Preview extends PreviewState {
  final int waveform;

  const Preview(this.waveform);

  @override
  String toString() => 'Preview($waveform)';
}

class OpenPreview {
  final Clip clip;
  final done = Completer<void>();

  OpenPreview(this.clip);
}
"""

# -------------------------------------------------------------- item 11 bloc
FILES['bloc/item11'] = (BLOC_IMPORTS + TRACE + PREVIEW + '\n' + snips['11/PreviewBloc'] + '\n'
                        + snips['11/GuardedPreviewBloc'] + '''
/// Completes an event's future when its handler is done, so the driver can
/// watch a handler the document's snippet knows nothing about.
mixin Finishing on Bloc<OpenPreview, PreviewState> {
  @override
  void onDone(OpenPreview event, [Object? error, StackTrace? stackTrace]) {
    super.onDone(event, error, stackTrace);
    event.done.complete();
  }
}

class WatchedPreviewBloc extends PreviewBloc with Finishing {
  WatchedPreviewBloc(super.decoder);
}

class WatchedGuardedPreviewBloc extends GuardedPreviewBloc with Finishing {
  WatchedGuardedPreviewBloc(super.decoder);
}

Future<void> go(
  String label,
  Decoder decoder,
  Bloc<OpenPreview, PreviewState> bloc,
) async {
  const first = Clip(1);
  const second = Clip(2);
  final stale = OpenPreview(first);
  bloc.add(stale);
  await decoder.whenAsked(1);
  final current = OpenPreview(second);
  bloc.add(current);
  await decoder.whenAsked(2);
  final currentBuffer = decoder.deliver(second);
  await current.done.future;
  final staleBuffer = decoder.deliver(first);
  await stale.done.future;
  await tick(10);
  print('$label: state ${bloc.state}, stale releases '
      '${staleBuffer.releases}, current releases ${currentBuffer.releases}');
  print('$label trace: ${decoder.trace}');
  await bloc.close();
}

Future<void> main() async {
  final plain = Decoder();
  await go('guard only', plain, WatchedPreviewBloc(plain));
  final guarded = Decoder();
  await go('finally', guarded, WatchedGuardedPreviewBloc(guarded));
}
''')

# -------------------------------------------------------------- item 11 solo
FILES['solo/item11'] = (SOLO_IMPORTS + TRACE + PREVIEW + '\n' + snips['11/PreviewController'] + '''
Future<void> main() async {
  final decoder = Decoder();
  final controller = PreviewController(decoder);
  const first = Clip(1);
  const second = Clip(2);

  final stale = controller.open(first);
  await decoder.whenAsked(1);
  final current = controller.open(second);
  final staleOutcome = await stale.done;
  await decoder.whenAsked(2);
  final currentBuffer = decoder.deliver(second);
  final currentOutcome = await current.done;
  await controller.close();
  print('before the late value: stale $staleOutcome, current '
      '$currentOutcome, closed ${controller.isClosed}');

  final staleBuffer = decoder.deliver(first);
  await staleBuffer.released.future;
  print('dispose: state ${controller.currentState}, stale releases '
      '${staleBuffer.releases}, current releases ${currentBuffer.releases}');
  print('trace: ${decoder.trace}');
}
''')

REFRESH_MODEL = '''
sealed class RefreshState {
  const RefreshState();
}

final class Initial extends RefreshState {
  const Initial();
}

final class Loading extends RefreshState {
  const Loading();
}

sealed class RefreshEvent {}
final class StartRefresh extends RefreshEvent {}
final class CancelRefresh extends RefreshEvent {}

class RefreshApi {
  final pending = Completer<void>();
  Future<void> refresh() => pending.future;
}

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
'''

# --------------------------------------------------------------- item 4
fixed_refresh = snips['4/RefreshBloc'].replace(
    'class RefreshBloc ', 'class GuardedRefreshBloc ',
).replace('RefreshBloc(this._api)', 'GuardedRefreshBloc(this._api)').replace(
    'if (event is CancelRefresh) return;', snips['4/if-event-is-cancelrefresh'].strip(),
)
FILES['bloc/item4'] = (
    BLOC_IMPORTS + "import 'package:fake_async/fake_async.dart';\n"
    + REFRESH_MODEL + snips['4/RefreshBloc'] + fixed_refresh + '''
void main() {
  fakeAsync((clock) {
    final api = RefreshApi();
    final bloc = RefreshBloc(api);
    bloc.add(StartRefresh());
    clock.flushMicrotasks();
    require(bloc.state is Loading, 'refresh must start in Loading');
    bloc.add(CancelRefresh());
    clock.flushMicrotasks();
    require(bloc.state is Loading, 'cancel without emit leaves Loading');
    api.pending.complete();
    clock.flushMicrotasks();
    require(bloc.state is Loading, 'cancelled finally must not update state');
    print('finally reset: ${bloc.state.runtimeType} after API completion');
    bloc.close();
    clock.flushMicrotasks();

    final fixedApi = RefreshApi();
    final fixed = GuardedRefreshBloc(fixedApi);
    fixed.add(StartRefresh());
    clock.flushMicrotasks();
    require(fixed.state is Loading, 'guarded refresh must start in Loading');
    fixed.add(CancelRefresh());
    clock.flushMicrotasks();
    require(fixed.state is Initial, 'cancel handler must reset immediately');
    fixedApi.pending.complete();
    clock.flushMicrotasks();
    require(fixed.state is Initial, 'late finally must preserve Initial');
    print('cancel handler reset: ${fixed.state.runtimeType}');
    fixed.close();
    clock.flushMicrotasks();
  });
}
''')

FILES['solo/item4'] = (
    SOLO_IMPORTS.replace(
        "import 'package:solo/solo.dart';",
        "import 'package:fake_async/fake_async.dart';\n"
        "import 'package:solo/solo.dart';",
    )
    + REFRESH_MODEL + snips['4/RefreshController'] + '''
void main() {
  fakeAsync((clock) {
    final api = RefreshApi();
    final controller = RefreshController(api);
    final job = controller.refresh();
    clock.flushMicrotasks();
    require(
      controller.currentState is Loading,
      'refresh must start in Loading',
    );
    // The screen holds nothing: the controller finds its own job, and
    // hands back the very one it cancels.
    final same = controller.cancelRefresh();
    require(identical(same, job), 'cancelRefresh returns the job it cancels');
    var cancelled = false;
    same?.done.then((_) => cancelled = true);
    clock.flushMicrotasks();
    require(cancelled, 'cancel must finish before abandoned API response');
    require(job.outcome is Cancelled, 'job must report cancellation');
    require(controller.currentState is Initial, 'onCancel must reset state');
    print('cancelRefresh: ${controller.currentState.runtimeType}, '
        'and the job it handed back says ${same?.outcome}');
    api.pending.complete();
    clock.flushMicrotasks();
    require(
      controller.currentState is Initial,
      'late response must preserve state',
    );
    controller.close();
    clock.flushMicrotasks();
  });

  // Which of the two the lookup takes. A queued refresh exists only after
  // a second call, and `Policy.restart` has cancelled the running one by
  // then, so preferring the queue is what stops the refresh that would
  // otherwise start.
  fakeAsync((clock) {
    final controller = RefreshController(RefreshApi());
    final first = controller.refresh();
    clock.flushMicrotasks();
    final second = controller.refresh();
    final found = controller.cancelRefresh();
    require(identical(found, second), 'the queued refresh comes first');
    require(first.isCancelled, 'restart cancelled the running one already');
    clock.flushMicrotasks();
    print('restart, then cancel: first ${first.outcome}, '
        'second ${second.outcome}, '
        'state ${controller.currentState.runtimeType}');
    controller.close();
    clock.flushMicrotasks();
  });
}
''')

for key, body in FILES.items():
    kind, name = key.split('/')
    d = f'{ROOT}/{kind}_check/bin/v'
    os.makedirs(d, exist_ok=True)
    open(f'{d}/{name}.dart', 'w').write(body)
print('wrote', len(FILES), 'files under', ROOT)
