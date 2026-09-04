"""Builds one runnable file per snippet of packages/solo/doc/vs-bloc.md.

Every snippet is copied byte-identical out of the markdown and wrapped in a
runnable file: fakes above it, a driver below it. That is what keeps the
document honest -- the code in it is the code that ran.

Usage, from the repository root:

    python3 tool/doc_snippets.py [workdir]      # default: /tmp/solo-doc-check

It creates two packages under the workdir, bloc_check (bloc 9 with
bloc_concurrency) and solo_check (a path dependency on packages/solo), and
writes bin/v/item1..8.dart into each. Then, in each of them:

    dart pub get
    dart analyze bin/v
    dart run bin/v/item1.dart          # and so on, up to item8

The traces the document quotes come from those runs. Timings in the fakes
are wall-clock and leave a margin; the drivers are not FakeAsync.
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
"""

SOLO_PUBSPEC = """name: solo_check
publish_to: none

environment:
  sdk: ^3.6.0

dependencies:
  solo:
    path: {solo}

dev_dependencies:
  fake_async: ^1.3.1
  lints: ^5.1.1
  test: ^1.25.15
""".format(solo=os.path.join(REPO, 'packages', 'solo'))

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
class Track {
  const Track();
}

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

  // Not traced: the item's traces are about the drag.
  Future<void> follow(Track track, {CancelToken? cancelToken}) async {
    for (var i = 0; i < 4; i++) {
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

# --------------------------------------------------------------- item 1 bloc
FILES['bloc/item1'] = (BLOC_IMPORTS + TRACE + BLE + '''
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

''' + snips['1_1'] + '''
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

# --------------------------------------------------------------- item 1 solo
FILES['solo/item1'] = (SOLO_IMPORTS + TRACE + BLE + '''
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

''' + snips['1_2'] + '''
// The four "ordinary jobs" the snippet refers to.
extension on DeviceController {
  Job<void> connect() => run<DeviceState, void>(
        key: DeviceKey.connect,
        (ctx) async {
          await ctx.guard(_ble.connect);
          ctx.emit(const Connected());
        },
      );

  Job<void> readBattery() => run<Connected, void>(
        key: DeviceKey.readBattery,
        (ctx) async {
          final battery = await ctx.guard(_ble.battery);
          ctx.emit(ctx.state.copyWith(battery: battery));
        },
      );

  Job<void> readSignal() => run<Connected, void>(
        key: DeviceKey.readSignal,
        (ctx) async {
          final signal = await ctx.guard(_ble.signal);
          ctx.emit(ctx.state.copyWith(signal: signal));
        },
      );

  Job<void> rename(String name) => run<Connected, void>(
        key: DeviceKey.rename,
        (ctx) => ctx.guard(() => _ble.rename(name)),
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

# --------------------------------------------------------------- item 2 bloc
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

FILES['bloc/item2'] = (BLOC_IMPORTS + TRACE + PLAYER + PLAYER_EVENTS + '\n'
                       + snips['2_1'] + '''
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
}
''')

# --------------------------------------------------------------- item 2 solo
FILES['solo/item2'] = (SOLO_IMPORTS + TRACE + PLAYER + '''
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

''' + snips['2_2'] + '''
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

# --------------------------------------------------------------- item 3 bloc
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

FILES['bloc/item3'] = (BLOC_IMPORTS + TRACE + NOTES_API + NOTES_EVENTS + '\n'
                       + snips['3_1'] + '''
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

# --------------------------------------------------------------- item 3 solo
FILES['solo/item3'] = (SOLO_IMPORTS + TRACE + NOTES_API + '''
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

''' + snips['3_2'] + '''
Future<void> main() async {
  final notes = NotesController(Api())
    ..upload(Note('n1'))
    ..refresh();
  await tick(300);
  print('final: ${notes.state}');
  await notes.close();
}
''')

# --------------------------------------------------------------- item 4 bloc
FILES['bloc/item4'] = (BLOC_IMPORTS + TRACE + BLE + '''
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

''' + snips['4_1'] + snips['4_2'] + '''
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

# --------------------------------------------------------------- item 4 solo
FILES['solo/item4'] = (SOLO_IMPORTS + TRACE + BLE + '''
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

''' + snips['4_3'] + '''
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

# --------------------------------------------------------------- item 5 bloc
FILES['bloc/item5'] = (BLOC_IMPORTS + TRACE + PAY_API + '''
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

''' + snips['5_1'] + snips['5_2'] + '''
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

# --------------------------------------------------------------- item 5 solo
FILES['solo/item5'] = (SOLO_IMPORTS + TRACE + PAY_API + '''
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

''' + snips['5_3'] + '\n' + snips['5_4'] + '''
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
  final receipts = await Future.wait([
    payAndAnswer(checkout, const Order('A')),
    payAndAnswer(checkout, const Order('A')),
    payAndAnswer(checkout, const Order('B')),
  ]);
  print('api.pay calls: ${api.calls}, $receipts');
  await checkout.close();

  final closingApi = Api();
  final closing = CheckoutController(closingApi);
  final inFlight = payAndAnswer(closing, const Order('C'));
  await tick(10);
  await closing.close();
  print('close mid-payment: ${await inFlight}, state ${closing.state}');

  final pendingApi = Api();
  final pending = CheckoutController(pendingApi);
  final charging = pending.pay(const Order('A'));
  await tick(10);
  final queued = pending.pay(const Order('B'));
  print('drop the queued one:   ${pending.cancelPending(const Order('B'))}');
  print('drop the charging one: ${pending.cancelPending(const Order('A'))}');
  await tick(100);
  print('  A ${charging.outcome}, B ${queued.outcome}, '
      'api.pay calls ${pendingApi.calls}');
  await pending.close();

  final closed = CheckoutController(Api());
  await closed.close();
  try {
    await payAndAnswer(closed, const Order('D'));
  } on Object catch (error) {
    print('pay after close: $error');
  }
}
''')

# --------------------------------------------------------------- item 6 bloc
FILES['bloc/item6'] = (BLOC_MAP_IMPORTS + TRACE + MAP_API + '\n' + snips['6_1'] + '''
Future<void> main() async {
  final cubit = MapCubit(MapApi());
  for (var i = 1; i <= 3; i++) {
    unawaited(cubit.moveTo(Point<double>(i.toDouble(), 0)));
  }
  await tick(300);
  print('drag: $trace  state ${cubit.state}');
  await cubit.close();
}
''')

# --------------------------------------------------------------- item 6 solo
FILES['solo/item6'] = (SOLO_MAP_IMPORTS + TRACE + MAP_API + '\n' + snips['6_2'] + '''
Future<void> main() async {
  final map = MapController(MapApi());
  onMapDrag(map, const Point<double>(1, 0));
  await tick(10);
  onMapDrag(map, const Point<double>(2, 0));
  onMapDrag(map, const Point<double>(3, 0));
  map
    ..setZoom(4)
    ..follow(const Track());
  await tick(300);
  print('drag: $trace  state ${map.state}');
  await map.close();
}
''')

# --------------------------------------------------------------- item 7 bloc
FILES['bloc/item7'] = (BLOC_IMPORTS + TRACE + CHAT_API + '''
sealed class ChatEvent {
  const ChatEvent();
}

class SendMessage extends ChatEvent {
  const SendMessage(this.text);
  final String text;
}

class MarkRead extends ChatEvent {
  const MarkRead();
}

''' + snips['7_1'] + '''
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

# --------------------------------------------------------------- item 7 solo
FILES['solo/item7'] = (SOLO_IMPORTS + TRACE + CHAT_API + '\n' + snips['7_1']
                       .replace('x', 'x') if False else
                       SOLO_IMPORTS + TRACE + CHAT_API + '\n' + snips['7_2'] + '''
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

for key, body in FILES.items():
    kind, name = key.split('/')
    d = f'{ROOT}/{kind}_check/bin/v'
    os.makedirs(d, exist_ok=True)
    open(f'{d}/{name}.dart', 'w').write(body)
print('wrote', len(FILES), 'files under', ROOT)
