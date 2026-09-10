"""Builds runnable scenarios from packages/solo/doc/vs-bloc.md.

Every snippet is copied byte-identical out of the markdown and wrapped in a
runnable file: fakes above it, a driver below it. That is what keeps the
document honest -- the code in it is the code that ran.

Usage, from the repository root:

    python3 tool/doc_snippets.py [workdir]      # default: /tmp/solo-doc-check

It creates two packages under the workdir, bloc_check (bloc 9 with
bloc_concurrency) and solo_check (a path dependency on packages/solo), and
writes bin/v/item1..10.dart plus item3_cancel.dart into each. Then:

    dart pub get
    dart analyze bin/v
    dart run bin/v/item1.dart          # and so on, up to item10
    dart run bin/v/item3_cancel.dart   # Loading after cancellation

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
""".format(
    solo=os.path.join(REPO, 'packages', 'solo'),
)

doc = open(DOC).read()
parts = re.split(r'\n## ', doc)
snips = {}
for p in parts[1:]:
    n = p.split('.')[0].strip()
    for j, b in enumerate(re.findall(r'```dart\n(.*?)```', p, re.S)):
        snips[f'{n}_{j + 1}'] = b

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

  Future<int> signal() async {
    trace.add('signal');
    await tick(10);
    return -60;
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
    await tick(40);
    _server.add(note);
  }

  Future<List<Note>> list() async {
    final snapshot = List<Note>.from(_server);
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
  Future<String> send(String text) async {
    await tick(50);
    return 'reply to $text';
  }

  Future<void> markRead() async => tick(10);
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

# --------------------------------------------------------------- item 6 bloc
FILES['bloc/item6'] = (BLOC_IMPORTS + TRACE + BLE + '''
sealed class DeviceEvent {}

class Connect extends DeviceEvent {}

class ReadBattery extends DeviceEvent {}

class ReadSignal extends DeviceEvent {}

class Rename extends DeviceEvent {
  Rename(this.name);
  final String name;
}

class Disconnect extends DeviceEvent {}

class DeviceState {
  const DeviceState({this.online = false, this.battery, this.signal});
  final bool online;
  final int? battery;
  final int? signal;
  DeviceState copyWith({bool? online, int? battery, int? signal}) =>
      DeviceState(
        online: online ?? this.online,
        battery: battery ?? this.battery,
        signal: signal ?? this.signal,
      );
  @override
  String toString() => 'DeviceState($online, b:$battery, s:$signal)';
}

''' + snips['6_1'] + '''
Future<void> main() async {
  final bloc = DeviceBloc(Ble());
  bloc
    ..add(Connect())
    ..add(ReadBattery())
    ..add(ReadSignal())
    ..add(Rename('kitchen'))
    ..add(Disconnect());
  await tick(300);
  print('hardware:    $trace');
  print('state: ${bloc.state}');
  await bloc.close();

  trace.clear();
  final fast = DeviceBloc(Ble());
  fast
    ..add(Connect())
    ..add(ReadBattery())
    ..add(Disconnect())
    ..add(Connect())
    ..add(ReadBattery());
  await tick(300);
  print('reopen fast: $trace');
  await fast.close();
}
''')

# --------------------------------------------------------------- item 6 solo
FILES['solo/item6'] = (SOLO_IMPORTS + TRACE + BLE + '''
sealed class DeviceState {
  const DeviceState();
}

final class Offline extends DeviceState {
  const Offline();
  @override
  String toString() => 'Offline';
}

final class Connected extends DeviceState {
  const Connected({this.battery, this.signal});
  final int? battery;
  final int? signal;
  Connected copyWith({int? battery, int? signal}) => Connected(
        battery: battery ?? this.battery,
        signal: signal ?? this.signal,
      );
  @override
  String toString() => 'Connected(b:$battery, s:$signal)';
}

''' + snips['6_2'] + '''
// The four "ordinary jobs" the snippet refers to.
extension on DeviceController {
  Job<void> connect() => run<DeviceState, void>(
        key: DeviceKey.connect,
        (ctx) async {
          await ctx.wait(_ble.connect);
          ctx.emit(const Connected());
        },
      );

  Job<void> readBattery() => run<Connected, void>(
        key: DeviceKey.readBattery,
        (ctx) async {
          final battery = await ctx.wait(_ble.battery);
          ctx.emit(ctx.state.copyWith(battery: battery));
        },
      );

  Job<void> readSignal() => run<Connected, void>(
        key: DeviceKey.readSignal,
        (ctx) async {
          final signal = await ctx.wait(_ble.signal);
          ctx.emit(ctx.state.copyWith(signal: signal));
        },
      );

  Job<void> rename(String name) => run<Connected, void>(
        key: DeviceKey.rename,
        (ctx) => ctx.wait(() => _ble.rename(name)),
      );
}

Future<void> main() async {
  final device = DeviceController(Ble());
  final connect = device.connect();
  final battery = device.readBattery();
  final signal = device.readSignal();
  final rename = device.rename('kitchen');
  final disconnect = device.disconnect();
  await tick(300);
  print('hardware: $trace');
  print('connect ${connect.outcome}  battery ${battery.outcome}');
  print('signal ${signal.outcome}  rename ${rename.outcome}');
  print('disconnect ${disconnect.outcome}  state ${device.state}');
  await device.close();
}
''')

# --------------------------------------------------------------- item 4 bloc
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

FILES['bloc/item4'] = (BLOC_IMPORTS + TRACE + PLAYER + PLAYER_EVENTS + '\n'
                       + snips['4_1'] + '''
Future<void> main() async {
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

# --------------------------------------------------------------- item 4 solo
FILES['solo/item4'] = (SOLO_IMPORTS + TRACE + PLAYER + '''
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

''' + snips['4_2'] + '''
extension on PlayerController {
  // The other toggle, in the same shape as pause().
  Job<void> play() => run<Ready, void>(
        key: PlayerKey.play,
        (ctx) async {
          await _player.play();
          ctx.emit(ctx.state.copyWith(playing: true));
        },
      );
}

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
  print('state ${player.state}');
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
  print('published: $seen  state ${p2.state}');
  print('stale job ${stale.outcome}');
  await sub.cancel();
  await p2.close();
}
''')

# --------------------------------------------------------------- item 1 bloc
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

FILES['bloc/item1'] = (BLOC_IMPORTS + TRACE + NOTES_API + NOTES_EVENTS + '\n'
                       + snips['1_1'] + '''
/// The same two handlers with a transformer each: two queues, not one.
class SplitNotesBloc extends Bloc<NotesEvent, NotesState> {
  SplitNotesBloc(this._api) : super(const NotesState()) {
    on<UploadNote>((e, emit) async {
      emit(state.copyWith(uploading: true));
      await _api.upload(e.note);
      emit(state.copyWith(notes: [...state.notes, e.note], uploading: false));
    }, transformer: sequential());
    on<RefreshList>((e, emit) async {
      final serverNotes = await _api.list();
      emit(state.copyWith(notes: serverNotes));
    }, transformer: sequential());
  }

  final Api _api;
}

/// The same two queues, with the refresh written in one line: `state` is
/// the receiver, so it is read before the awaited argument.
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

Future<void> main() async {
  final funnel = NotesBloc(Api())
    ..add(UploadNote(Note('n1')))
    ..add(RefreshList());
  await tick(300);
  print('funnel: ${funnel.state}');
  await funnel.close();

  final split = SplitNotesBloc(Api())
    ..add(UploadNote(Note('n1')))
    ..add(RefreshList());
  await tick(300);
  print('a transformer per handler: ${split.state}');
  await split.close();

  final inline = InlineNotesBloc(Api())
    ..add(UploadNote(Note('n1')))
    ..add(RefreshList());
  await tick(300);
  print('the one-line refresh:      ${inline.state}');
  await inline.close();
}
''')

# --------------------------------------------------------------- item 1 solo
FILES['solo/item1'] = (SOLO_IMPORTS + TRACE + NOTES_API + '''
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

''' + snips['1_2'] + '''
Future<void> main() async {
  final notes = NotesController(Api())
    ..upload(Note('n1'))
    ..refresh();
  await tick(300);
  print('final: ${notes.state}');
  await notes.close();
}
''')

# --------------------------------------------------------------- item 9 bloc
FILES['bloc/item9'] = (BLOC_IMPORTS + TRACE + BLE + '''
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

''' + snips['9_1'] + snips['9_2'] + '''
/// The same loop with the `emit.isDone` line left out.
class UnguardedFirmwareBloc extends Bloc<FirmwareEvent, FirmwareState> {
  UnguardedFirmwareBloc(this._ble) : super(Idle()) {
    on<Flash>((e, emit) async {
      var written = 0;
      for (final chunk in e.chunks) {
        await _ble.write(chunk);
        emit(Flashing(++written, e.chunks.length));
      }
    }, transformer: restartable());
  }

  final Ble _ble;
}

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

# --------------------------------------------------------------- item 9 solo
FILES['solo/item9'] = (SOLO_IMPORTS + TRACE + BLE + '''
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

''' + snips['9_3'] + '''
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
  print('restart: written ${ble.written}, state ${firmware.state}');
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

# --------------------------------------------------------------- item 7 bloc
FILES['bloc/item7'] = (BLOC_IMPORTS + TRACE + PAY_API + '''
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

''' + snips['7_1'] + snips['7_2'] + '''
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

Future<void> main() async {
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

# --------------------------------------------------------------- item 7 solo
FILES['solo/item7'] = (SOLO_IMPORTS + TRACE + PAY_API + '''
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

''' + snips['7_3'] + '\n' + snips['7_4'] + '''
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
  print('close mid-payment: ${await inFlight}, state ${closing.state}');

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

# --------------------------------------------------------------- item 5 bloc
FILES['bloc/item5'] = (BLOC_MAP_IMPORTS.replace(
    "import 'package:bloc/bloc.dart';",
    "import 'package:bloc/bloc.dart';\n"
    "import 'package:bloc_concurrency/bloc_concurrency.dart';",
) + TRACE + MAP_API + '\n' + snips['5_1'] + '\n' + snips['5_2'] + '''
Future<void> main() async {
  final cubit = MapCubit(MapApi());
  for (var i = 1; i <= 3; i++) {
    unawaited(cubit.moveTo(Point<double>(i.toDouble(), 0)));
  }
  await tick(300);
  print('drag: $trace  state ${cubit.state}');
  await cubit.close();

  trace.clear();
  final bloc = CommandMapBloc(MapApi());
  for (var i = 1; i <= 3; i++) {
    bloc.moveTo(Point<double>(i.toDouble(), 0));
  }
  bloc.setZoom(4);
  await tick(400);
  print('typed methods, one queue: $trace  state ${bloc.state}');
  await bloc.close();
}
''')

# --------------------------------------------------------------- item 5 solo
FILES['solo/item5'] = (SOLO_MAP_IMPORTS + TRACE + MAP_API + '\n' + snips['5_3'] + '''
Future<void> main() async {
  final map = MapController(MapApi());
  onMapDrag(map, const Point<double>(1, 0));
  await tick(10);
  onMapDrag(map, const Point<double>(2, 0));
  onMapDrag(map, const Point<double>(3, 0));
  map.setZoom(4);
  await tick(300);
  print('drag: $trace  state ${map.state}');
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

''' + snips['3_1'] + '''
/// The same bloc with the guard left out.
class UnguardedChatBloc extends Bloc<ChatEvent, ChatState> {
  UnguardedChatBloc(this._api) : super(const ChatState()) {
    on<SendMessage>((e, emit) async {
      final reply = await _api.send(e.text);
      emit(state.withReply(reply));
    }, transformer: sequential());
  }

  final Api _api;
}

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
  final chat = ChatBloc(Api())..add(const SendMessage('hi'));
  await tick(10);
  final started = DateTime.now();
  await chat.close();
  print('close took ${DateTime.now().difference(started).inMilliseconds}ms, '
      'state ${chat.state}');
  try {
    chat.add(const SendMessage('bye'));
  } on Object catch (error) {
    print('add after close: $error');
  }

  final unguarded = UnguardedChatBloc(Api())..add(const SendMessage('hi'));
  await tick(10);
  await unguarded.close();
  print('one missed guard: state after close ${unguarded.state}');

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
                       + snips['3_2'] + '''
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
  final chat = ChatController(Api());
  final running = chat.send('hi');
  final queued = chat.send('and again');
  await tick(10);
  await onScreenClosed(chat);
  print('running ${running.outcome}  queued ${queued.outcome}');
  print('state after close: ${chat.state}');
  print('send after close: ${chat.send('later').outcome}');

  await runZonedGuarded(
    () async {
      final late = LateChatController(Api())..send('hi');
      await tick(200);
      print('late emit: state ${late.state}');
      await late.close();
    },
    (error, _) => print('late emit raised: $error'),
  );
}
''')

# --------------------------------------------------------------- item 8 bloc
FILES['bloc/item8'] = (BLOC_IMPORTS + TRACE + SENSOR + '''
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

''' + snips['8_1'] + '''
/// The same bloc with item 3's cure applied: one funnel, one queue.
class FunnelSensorBloc extends Bloc<SensorEvent, SensorState> {
  FunnelSensorBloc(this._hw) : super(Ready()) {
    _hw.onError = (error) => add(HardwareFailed(error));
    on<SensorEvent>((e, emit) async {
      switch (e) {
        case HardwareFailed(:final error):
          emit(Broken(error));
        case Calibrate():
          if (state is! Ready) return;
          await _hw.zero();
          if (state is! Ready) return;
          await _hw.sample();
          if (state is! Ready) return;
          emit(Calibrated());
      }
    }, transformer: sequential());
  }

  final Sensor _hw;
}

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

# --------------------------------------------------------------- item 8 solo
FILES['solo/item8'] = (SOLO_IMPORTS + TRACE + SENSOR + '''
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

''' + snips['8_2'] + '''
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
  print('states: $states  final ${sensor.state}');
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
FILES['bloc/item2'] = (BLOC_PLAIN_IMPORTS + TRACE + RECORDER + '\n' + snips['2_1'] + '\n'
                       + snips['2_2'] + '''
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

Future<void> main() async {
  await go(guarded: false);
  await go(guarded: true);
}
''')

# --------------------------------------------------------------- item 2 solo
FILES['solo/item2'] = (SOLO_IMPORTS + TRACE + RECORDER + '\n' + snips['2_3'] + '''
Future<void> main() async {
  SoloBase.observer = TelemetryObserver(Telemetry());
  final recorder = Recorder();
  final journal = Journal();
  final controller = RecorderController(recorder, journal);
  final zone = <String>[];
  await runZonedGuarded(
    () async {
      final outcome = await controller.start().done;
      print('solo: state ${controller.state}, outcome $outcome, '
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

# -------------------------------------------------------------- item 10 bloc
FILES['bloc/item10'] = (BLOC_IMPORTS + TRACE + PREVIEW + '\n' + snips['10_1'] + '\n'
                        + snips['10_2'] + '''
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

# -------------------------------------------------------------- item 10 solo
FILES['solo/item10'] = (SOLO_IMPORTS + TRACE + PREVIEW + '\n' + snips['10_3'] + '''
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
  print('dispose: state ${controller.state}, stale releases '
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

fixed_refresh = snips['3_3'].replace(
    'class RefreshBloc ', 'class GuardedRefreshBloc ',
).replace('RefreshBloc(this._api)', 'GuardedRefreshBloc(this._api)').replace(
    'if (event is CancelRefresh) return;', snips['3_4'].strip(),
)
FILES['bloc/item3_cancel'] = (
    BLOC_IMPORTS + "import 'package:fake_async/fake_async.dart';\n"
    + REFRESH_MODEL + snips['3_3'] + fixed_refresh + '''
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

FILES['solo/item3_cancel'] = (
    SOLO_IMPORTS.replace(
        "import 'package:solo/solo.dart';",
        "import 'package:fake_async/fake_async.dart';\n"
        "import 'package:solo/solo.dart';",
    )
    + REFRESH_MODEL + snips['3_5'] + '''
void main() {
  fakeAsync((clock) {
    final api = RefreshApi();
    final controller = RefreshController(api);
    final job = controller.refresh();
    clock.flushMicrotasks();
    require(controller.state is Loading, 'refresh must start in Loading');
    var cancelled = false;
    job.cancel().then((_) => cancelled = true);
    clock.flushMicrotasks();
    require(cancelled, 'cancel must finish before abandoned API response');
    require(job.outcome is Cancelled, 'job must report cancellation');
    require(controller.state is Initial, 'onCancel must reset state');
    print('onCancel reset: ${controller.state.runtimeType}, ${job.outcome}');
    api.pending.complete();
    clock.flushMicrotasks();
    require(controller.state is Initial, 'late response must preserve state');
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
