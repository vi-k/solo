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

# The versions the pages name, resolved at their newest on the SDK of the
# job: bloc 9.2.1 is the first whose `isClosed` is true while close() runs
# the queue out, and the closing section stands on it. async_job is an
# override, since solo from the tree asks for a released one.
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

# The chat of the closing section, the API of tool/doc_snippets.py with
# its delay named: a message takes `sendMs` to answer. `offline` makes
# every call fail when its time is up.
CHAT_API = '''
const sendMs = 50;

class Api {
  Api({this.offline = false});

  final bool offline;

  /// Reads reported to the server. A reply the user never saw must not be
  /// one of them.
  int reads = 0;

  /// Messages the server was asked to deliver, and the ones it answered.
  final sent = <String>[];
  final answered = <String>[];

  Future<String> send(String text) async {
    sent.add(text);
    await delay(sendMs);
    if (offline) throw StateError('send: offline');
    answered.add(text);
    return 'reply to $text';
  }

  Future<void> markRead() async {
    reads++;
    await delay(10);
  }
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
CLOSING = 'closing-and-cancelling-in-flig'

# "hi" in flight, "bye" queued, close() 10 ms in. One line, the same shape
# for both answers: how long close() took, what the server was asked to
# send, the reply published and the reads reported. States published after
# close() began are counted apart.
CHAT_SCENARIO = '''
const closeAtMs = 10;

Future<void> scenario() async {
  final api = Api();
  final afterClose = <ChatState>[];
  var closing = false;
  await guarded(() async {
    final bloc = chatBloc(api);
    final states = bloc.stream.listen((state) {
      if (closing) afterClose.add(state);
    });
    bloc
      ..add(const SendMessage('hi'))
      ..add(const SendMessage('bye'));
    await delay(closeAtMs);
    closing = true;
    final started = nowMs();
    await bloc.close();
    tookMs = nowMs() - started;
    await delay(2 * sendMs);
    await states.cancel();
    print('$name: close took ${tookMs}ms, sent ${api.sent}, '
        'reply ${bloc.state.reply}, reads ${api.reads}');
  });
  require(zone.isEmpty, '$name: nothing may reach the zone: $zone');
  check(api, afterClose);
}

late int tookMs;

/// What the guard of bloc alone keeps: the queued message is still sent,
/// and no reply reaches the state or the server.
void requireGuarded(Api api, List<ChatState> afterClose) {
  require('${api.sent}' == '[hi, bye]',
      '$name: the queued message must still be sent');
  require(afterClose.isEmpty,
      '$name: no state may follow close(): $afterClose');
  require(api.reads == 0, '$name: no read may be reported');
}
'''

# The bloc of a driver from its api.
CHAT_BLOC = 'ChatBloc chatBloc(Api api) => ChatBloc(api);\n'

# close() waits for the call in flight and then for the queued one.
CHAT_ALONE = '''
const name = 'with bloc alone';

void check(Api api, List<ChatState> afterClose) {
  requireGuarded(api, afterClose);
  require(tookMs == sendMs - closeAtMs + sendMs,
      'bloc alone: close must wait for both calls');
}
'''

# A call that fails: it reaches the zone.
FAILING = '''
Future<void> scenario() async {
  await guarded(() async {
    final bloc = ChatBloc(Api(offline: true))..add(const SendMessage('hi'));
    await delay(2 * sendMs);
    print('$name, the call fails: the zone $zone, reply ${bloc.state.reply}');
    await bloc.close();
  });
  require('$zone' == '[Bad state: send: offline]',
      '$name: the failure must reach the zone');
}
'''

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
SOLO_ALONE = f'{CLOSING}/with-bloc-alone'
SOLO_UNDER = f'{CLOSING}/with-a-controller-under-the-bl'

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

# The controller of the closing section is the one of vs-bloc.md: a reader
# who comes from there knows the code.
SOLO_CHAT = solo[f'{SOLO_UNDER}/ChatController']
vs_bloc = doc_blocks.subsection_blocks(open(VS_BLOC).read())
assert SOLO_CHAT.rstrip('\n') in vs_bloc[
    'closing-and-cancelling-in-flig/solo/ChatController'], (
    'the ChatController of the bloc page is not the one of vs-bloc.md')

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

# ---------------------------------------------------------------- closing
SOLO_EVENTS = solo[f'{CLOSING}/ChatEvent']
assert SOLO_EVENTS is solo[f'{CLOSING}/ChatState']

FILES['solo_closing_bloc'] = (
    BLOC_HEAD + HELPERS + CHAT_API + SOLO_EVENTS + solo[f'{SOLO_ALONE}/ChatBloc']
    + CHAT_BLOC + CHAT_ALONE + CHAT_SCENARIO + RUNNER)

SOLO_CHAT_BLOC = solo[f'{SOLO_UNDER}/ChatBloc']
CONTROLLER_BLOC = (
    'ChatBloc chatBloc(Api api) => ChatBloc(StreamedChat(api));\n')

# The controller closed first: "hi" is cancelled at ctx.abandonable, and
# "bye", held by sequential(), reaches a closed controller and ends with no
# call.
FILES['solo_closing_controller'] = (
    SOLO_HEAD + HELPERS + CHAT_API + SOLO_EVENTS + SOLO_CHAT + SOLO_CHAT_BLOC
    + CONTROLLER_BLOC + '''
const name = 'with a controller';

void check(Api api, List<ChatState> afterClose) {
  require('${api.sent}' == '[hi]', '$name: "bye" must not be sent');
  require(afterClose.isEmpty,
      '$name: no state may follow close(): $afterClose');
  require(api.reads == 0, '$name: no read may be reported');
  require(tookMs == 0, '$name: close must not wait for the call');
}
''' + CHAT_SCENARIO + RUNNER)

# The other order: super.close() first runs the queue of sequential()
# through an open controller, and both replies are published and read.
CLOSE_ORDER = '''    await _chat.close();
    return super.close();
'''
assert SOLO_CHAT_BLOC.count(CLOSE_ORDER) == 1, 'the close of the page moved'
FILES['solo_closing_bloc_first'] = (
    SOLO_HEAD + HELPERS + CHAT_API + SOLO_EVENTS + SOLO_CHAT
    + SOLO_CHAT_BLOC.replace(CLOSE_ORDER, '''    await super.close();
    return _chat.close();
''') + CONTROLLER_BLOC + '''
const name = 'with super.close() first';

void check(Api api, List<ChatState> afterClose) {
  require('${api.sent}' == '[hi, bye]',
      '$name: the queue of bloc must run through the controller');
  require(afterClose.length == 2,
      '$name: both replies must be published: $afterClose');
}
''' + CHAT_SCENARIO + RUNNER)

# A call that fails: `settle` throws the Failed outcome again, and it
# reaches the zone as the failure of bloc alone does.
FILES['solo_closing_controller_failed'] = (
    SOLO_HEAD + HELPERS + CHAT_API + SOLO_EVENTS + SOLO_CHAT + SOLO_CHAT_BLOC
    + CONTROLLER_BLOC + "\nconst name = 'with a controller';\n"
    + FAILING.replace('ChatBloc(Api(offline: true))',
                      'chatBloc(Api(offline: true))')
    + RUNNER)
assert 'chatBloc(Api(offline: true))' in FILES[
    'solo_closing_controller_failed']

# Without sequential() the queue of the controller holds the order of the
# messages, and the order of close() decides nothing: both orders send
# "hi" alone.
SEQUENTIAL_SEND = '''    on<SendMessage>(
      (e, emit) => settle(_chat.send(e.text)),
      transformer: sequential(),
    );
'''
assert SOLO_CHAT_BLOC.count(SEQUENTIAL_SEND) == 1, 'the send of the page moved'
DEFAULT_CHAT_BLOC = SOLO_CHAT_BLOC.replace(
    SEQUENTIAL_SEND,
    '    on<SendMessage>((e, emit) => settle(_chat.send(e.text)));\n')
DEFAULT_CHECK = '''
void check(Api api, List<ChatState> afterClose) {
  require('${api.sent}' == '[hi]', '$name: "bye" must not be sent');
  require(afterClose.isEmpty,
      '$name: no state may follow close(): $afterClose');
  require(api.reads == 0, '$name: no read may be reported');
}
'''
FILES['solo_closing_default'] = (
    SOLO_PLAIN_HEAD + HELPERS + CHAT_API + SOLO_EVENTS + SOLO_CHAT
    + DEFAULT_CHAT_BLOC + CONTROLLER_BLOC
    + "\nconst name = 'the default registration';\n" + DEFAULT_CHECK
    + CHAT_SCENARIO + RUNNER)
FILES['solo_closing_default_bloc_first'] = (
    SOLO_PLAIN_HEAD + HELPERS + CHAT_API + SOLO_EVENTS + SOLO_CHAT
    + DEFAULT_CHAT_BLOC.replace(CLOSE_ORDER, '''    await super.close();
    return _chat.close();
''') + CONTROLLER_BLOC
    + "\nconst name = 'the default registration, super.close() first';\n"
    + DEFAULT_CHECK + CHAT_SCENARIO + RUNNER)

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

# --------------------------------------------------------------- ordering
ORDERING = section('Ordering updates to shared state')

# The upload takes 40 ms and the list 60; the list is read when the call
# starts, so an answer in flight is what the server held then.
NOTES = '''
class Note {
  Note(this.id);

  final String id;

  @override
  String toString() => id;
}

class Api {
  final _server = <Note>[Note('n0')];

  /// What each call of [list] read, as it read it.
  final reads = <List<Note>>[];

  Future<void> upload(Note note) async {
    await delay(40);
    _server.add(note);
  }

  Future<List<Note>> list() async {
    final snapshot = List<Note>.of(_server);
    reads.add(snapshot);
    await delay(60);
    return snapshot;
  }
}

sealed class NotesEvent {}

class UploadNote extends NotesEvent {
  UploadNote(this.note);

  final Note note;
}

class RefreshList extends NotesEvent {}

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
'''

# The screen adds an upload and a refresh one right after the other.
NOTING = '''
Future<void> scenario() async {
  final api = Api();
  await guarded(() async {
    final bloc = notesBloc(api)
      ..add(UploadNote(Note('n1')))
      ..add(RefreshList());
    await delay(300);
    print('$name: the list read ${api.reads.single}, ${bloc.state}');
    require('${api.reads}' == '[[n0, n1]]',
        '$name: the list must be read after the upload');
    require('${bloc.state}' == 'NotesState([n0, n1], uploading: false)',
        '$name: the note must stay');
    await bloc.close();
  });
  require(zone.isEmpty, '$name: nothing may reach the zone: $zone');
}
'''

FILES['solo_ordering_bloc'] = (
    BLOC_HEAD + HELPERS + NOTES
    + from_vs_bloc(f'{ORDERING}/{ALONE_SUB}/NotesBloc', ORDERING, 'bloc')
    + '''
const name = 'with bloc alone';

NotesBloc notesBloc(Api api) => NotesBloc(api);
''' + NOTING + RUNNER)

FILES['solo_ordering_controller'] = (
    SOLO_PLAIN_HEAD + HELPERS + NOTES
    + from_vs_bloc(f'{ORDERING}/{UNDER_SUB}/NotesController', ORDERING,
                   'solo')
    + solo[f'{ORDERING}/{UNDER_SUB}/NotesBloc'] + '''
const name = 'with a controller';

NotesBloc notesBloc(Api api) => NotesBloc(StreamedNotes(api));
''' + NOTING + RUNNER)

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

# ---------------------------------------------------------------- external
EXTERNAL = section('Reacting to an independent external state change')

# A build takes 50 ms from data on the device; a revoked session cannot
# stop it.
REPORTS = '''
class Range {
  const Range(this.days);

  final int days;
}

class Report {
  const Report(this.days);

  final int days;

  @override
  String toString() => 'Report($days days)';
}

class Reports {
  int built = 0;

  Future<Report> build(Range range) async {
    await delay(50);
    built++;
    return Report(range.days);
  }
}

class Auth {
  void Function(String reason)? onRevoked;

  void revoke(String reason) => onRevoked?.call(reason);
}

sealed class ReportEvent {}

class BuildReport extends ReportEvent {
  BuildReport(this.range);

  final Range range;
}

class SessionRevoked extends ReportEvent {
  SessionRevoked(this.reason);

  final String reason;
}
'''

BLOC_REPORT_STATE = '''
sealed class ReportState {}

class SignedIn extends ReportState {
  @override
  String toString() => 'SignedIn';
}

class Ready extends ReportState {
  Ready(this.report);

  final Report report;

  @override
  String toString() => 'Ready($report)';
}

class SignedOut extends ReportState {
  SignedOut(this.reason);

  final String reason;

  @override
  String toString() => 'SignedOut($reason)';
}
'''

SOLO_REPORT_STATE = '''
sealed class ReportState {
  const ReportState();
}

final class SignedIn extends ReportState {
  const SignedIn();

  @override
  String toString() => 'SignedIn';
}

final class Ready extends ReportState {
  const Ready(this.report);

  final Report report;

  @override
  String toString() => 'Ready($report)';
}

final class SignedOut extends ReportState {
  const SignedOut(this.reason);

  final String reason;

  @override
  String toString() => 'SignedOut($reason)';
}
'''

# Two builds asked for; the session is revoked 20 ms into the first.
REVOKING = '''
Future<void> scenario() async {
  final reports = Reports();
  final auth = Auth();
  final states = <ReportState>[];
  await guarded(() async {
    final bloc = reportBloc(reports, auth);
    final listening = bloc.stream.listen(states.add);
    bloc
      ..add(BuildReport(const Range(30)))
      ..add(BuildReport(const Range(30)));
    await delay(20);
    auth.revoke('signed out elsewhere');
    await delay(200);
    await checkJobs();
    await listening.cancel();
    await bloc.close();
  });
  print('$name: states $states, built ${reports.built}, the zone $zone');
  require('$states' == '[SignedOut(signed out elsewhere)]',
      '$name: no report may follow the revocation: $states');
  require(reports.built == 1, '$name: the second build must not run');
  require(zone.isEmpty, '$name: nothing may reach the zone: $zone');
}
'''

FILES['solo_external_bloc'] = (
    BLOC_HEAD + HELPERS + REPORTS + BLOC_REPORT_STATE
    + from_vs_bloc(f'{EXTERNAL}/{ALONE_SUB}/ReportBloc', EXTERNAL, 'bloc')
    + '''
const name = 'with bloc alone';

ReportBloc reportBloc(Reports reports, Auth auth) => ReportBloc(reports, auth);

Future<void> checkJobs() async {}
''' + REVOKING + RUNNER)

FILES['solo_external_controller'] = (
    SOLO_PLAIN_HEAD + HELPERS + REPORTS + SOLO_REPORT_STATE
    + from_vs_bloc(f'{EXTERNAL}/{UNDER_SUB}/ReportController', EXTERNAL,
                   'solo')
    + solo[f'{EXTERNAL}/{UNDER_SUB}/ReportBloc'] + '''
const name = 'with a controller';

/// The jobs the handlers of the bloc wait for.
final jobs = <Job<void>>[];

final class RecordedReport extends ReportController {
  RecordedReport(super.reports, super.auth);

  @override
  Job<void> build(Range range) {
    final job = super.build(range);
    jobs.add(job);
    return job;
  }
}

ReportBloc reportBloc(Reports reports, Auth auth) =>
    ReportBloc(RecordedReport(reports, auth));

/// Both builds end Cancelled by the rule of the controller.
Future<void> checkJobs() async {
  require(jobs.length == 2, '$name: both builds must reach the controller');
  for (final job in jobs) {
    final outcome = await job.done;
    require('$outcome' == 'Cancelled(rules: is not SignedIn)',
        '$name: a build must end by the rule: $outcome');
  }
}
''' + REVOKING + RUNNER)

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
