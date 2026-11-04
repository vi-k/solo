#!/usr/bin/env python3
"""Builds runnable scenarios from the bloc pages of async_job and solo.

Every snippet is copied byte-identical out of the markdown and wrapped in a
runnable file: fakes above it, a driver below it. The page of async_job
says what a job in a bloc handler takes off the code and what stays with
bloc; the drivers hold both with `require`, so a bloc that starts closing
otherwise turns the run red instead of printing something else.

Usage, from the repository root:

    python3 tool/bloc_snippets.py [workdir]
    python3 tool/bloc_snippets.py --list

The default workdir is /tmp/bloc-pages-check. It creates one package,
bloc_pages_check, with async_job and solo from the tree. Then:

    dart pub get
    dart analyze --fatal-infos bin/v
    dart run --enable-asserts bin/v/core_closing_job.dart   # and so on

Asserts are on: bloc says through them that a handler emitted after it was
done, and a run without them would let that pass.

The drivers of the core page are named `core_*` and build files with no
`package:solo` in them: the page is complete without solo, and the script
stops if one of its drivers imports it.

The drivers run on virtual time, under the runner of
tool/adapter_snippets.py with the clock of tool/doc_snippets.py: a close
is held to its length in milliseconds, and real time would make that
number drift.

Blocks are addressed by `subsection_blocks` of tool/doc_blocks.py: section,
`###` subsection and the name a block declares. The answer of bloc alone
and the answer with a job declare the same bloc, and the subsection tells
them apart.

Every `dart` block of a page is built: the script stops if one of them
went into no driver.
"""
import os
import sys

import doc_blocks

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = sys.argv[1] if len(sys.argv) > 1 else '/tmp/bloc-pages-check'
CORE = os.path.join(REPO, 'packages', 'async_job', 'doc', 'bloc.md')
NEIGHBOUR = os.path.join(REPO, 'packages', 'async_job', 'doc',
                         'riverpod-and-bloc.md')

# The majors the pages name, resolved at their newest on the SDK of the
# job. async_job is a dependency of its own, since the core drivers import
# it, and an override as well, since solo from the tree asks for a released
# one.
PUBSPEC = """name: bloc_pages_check
publish_to: none

environment:
  sdk: ^3.10.0

dependencies:
  async_job:
    path: {async_job}
  bloc: ^9.0.0
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

core = doc_blocks.Blocks(doc_blocks.subsection_blocks(open(CORE).read()))
if ROOT == '--list':
    for page, blocks in (('core', core),):
        for key in blocks:
            poisoned = dict.__getitem__(blocks, key) is doc_blocks.POISONED
            print(page, key, '(declared twice)' if poisoned else '')
    sys.exit(0)

BRIDGE = 'the-bridge'
CLOSING = 'closing-and-cancelling-in-flig'
ALONE = f'{CLOSING}/with-bloc-alone'
WITH_JOB = f'{CLOSING}/with-a-job-in-the-handler'

# `watch` is the neighbour's, taken apart there: the page repeats it, and
# the copy has to stay the same bytes. It declares no name doc_blocks sees
# -- `watch<T>(` has its type parameters before the parenthesis -- so it is
# addressed by its first line, and found in the neighbour inside the block
# of `SearchBloc`.
WATCH = core[f'{BRIDGE}/the-value-of-job-as-a-stream-c']
assert WATCH.startswith('/// The value of [job] as a stream.')
neighbour = doc_blocks.subsection_blocks(open(NEIGHBOUR).read())
assert WATCH.rstrip('\n') in neighbour[
    'a-handler-that-restarts/a-stream-that-cancels-the-job/SearchBloc'], (
    'the watch of the bloc page is not the one of riverpod-and-bloc.md')

# Every driver carries the helpers and the clock whether it uses them or
# not, so the analyzer is told that they are shared.
CORE_HEAD = """// ignore_for_file: unreachable_from_main
import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:fake_async/fake_async.dart';
"""

# The drivers of bloc alone, without a job.
BLOC_HEAD = CORE_HEAD.replace("import 'package:async_job/async_job.dart';\n",
                              '')

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

# ----------------------------------------------------------------- bridge
# A job that takes 100 ms unless it is cancelled, under the bridge.
WORK = '''
final outcomes = <Job<int>>[];

Job<int> work(int n) {
  final job = Job<int>((ctx) async {
    await ctx.abandonable(() => delay(100));
    return n;
  });
  outcomes.add(job);
  return job;
}

final class Load {
  const Load(this.n);

  final int n;
}

final class Loader extends Bloc<Load, int> {
  Loader(EventTransformer<Load>? transformer) : super(0) {
    on<Load>((event, emit) async {
      await emit.forEach(
        watch(work(event.n)),
        onData: (n) => n,
        onError: (_, _) => state,
      );
    }, transformer: transformer);
  }
}
'''

# Every transformer but sequential() cancels the subscriptions of forEach on
# close(), and restartable() the one of the handler it replaces: the job is
# cancelled with no line of the page's own.
FILES['core_bridge_cancelled'] = (CORE_HEAD + HELPERS + WATCH + WORK + '''
Future<void> scenario() async {
  for (final (name, transformer) in [
    ('concurrent', null),
    ('droppable', droppable<Load>()),
    ('restartable', restartable<Load>()),
  ]) {
    outcomes.clear();
    final bloc = Loader(transformer)..add(const Load(1));
    await delay(10);
    final closing = nowMs();
    await bloc.close();
    final took = nowMs() - closing;
    final outcome = await outcomes.single.done;
    print('$name: close took ${took}ms, the job $outcome');
    require(took == 0, '$name close must not wait for the job');
    require(outcome is Cancelled, '$name close must cancel the job');
  }

  outcomes.clear();
  final bloc = Loader(restartable<Load>())..add(const Load(1));
  await delay(10);
  bloc.add(const Load(2));
  await delay(150);
  final first = await outcomes.first.done;
  print('restartable, a second load: the first job $first, state '
      '${bloc.state}');
  require(first is Cancelled, 'restartable must cancel the replaced job');
  require(bloc.state == 2, 'the second job must be the one published');
  await bloc.close();
}
''' + RUNNER)

# sequential() cancels nothing on close(): it waits for the running
# handler and runs the queued event, and both jobs run to their end.
FILES['core_bridge_sequential'] = (CORE_HEAD + HELPERS + WATCH + WORK + '''
Future<void> scenario() async {
  final bloc = Loader(sequential<Load>())
    ..add(const Load(1))
    ..add(const Load(2));
  await delay(10);
  final closing = nowMs();
  await bloc.close();
  final took = nowMs() - closing;
  final ended = [for (final job in outcomes) await job.done];
  print('sequential: close took ${took}ms, the jobs $ended');
  require(ended.every((outcome) => outcome is Done),
      'sequential close must let every job end');
  require(took == 190, 'sequential close must run the queue out');
}
''' + RUNNER)

# The job in a field, cancelled from close() under sequential(), and the
# handler awaiting its value: the Cancelled it throws reaches the zone.
FILES['core_bridge_value'] = (CORE_HEAD + HELPERS + '''
final class ValueLoader extends Bloc<int, int> {
  ValueLoader() : super(0) {
    on<int>((n, emit) async {
      final job = _loading = Job<int>((ctx) async {
        await ctx.abandonable(() => delay(100));
        return n;
      });
      emit(await job.value);
    }, transformer: sequential());
  }

  Job<int>? _loading;

  @override
  Future<void> close() async {
    await _loading?.cancel();
    return super.close();
  }
}

Future<void> scenario() async {
  await guarded(() async {
    final bloc = ValueLoader()..add(1);
    await delay(10);
    await bloc.close();
    await delay(10);
  });
  print('job.value under close: the zone $zone');
  require(zone.length == 1 && zone.single is Cancelled,
      'a cancelled job.value must throw Cancelled to the zone');
}
''' + RUNNER)

# ---------------------------------------------------------------- closing
EVENTS = core[f'{CLOSING}/ChatEvent']
assert EVENTS is core[f'{CLOSING}/ChatState']

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
    final bloc = ChatBloc(api);
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
  require('${api.sent}' == '[hi, bye]',
      '$name: the queued message must still be sent');
  require(afterClose.isEmpty,
      '$name: no state may follow close(): $afterClose');
  require(api.reads == 0, '$name: no read may be reported');
  check();
}

late int tookMs;
'''

FILES['core_closing_bloc'] = (
    BLOC_HEAD + HELPERS + CHAT_API + EVENTS + core[f'{ALONE}/ChatBloc'] + '''
const name = 'with bloc alone';

/// close() waits for the call in flight and then for the queued one.
void check() {
  require(tookMs == sendMs - closeAtMs + sendMs,
      'bloc alone: close must wait for both calls');
}
''' + CHAT_SCENARIO + RUNNER)

FILES['core_closing_job'] = (
    CORE_HEAD + HELPERS + CHAT_API + EVENTS + core[f'{WITH_JOB}/ChatBloc']
    + '''
const name = 'with a job';

/// close() skips what is left of the call in flight, and waits for the
/// queued one: shorter than bloc alone by the rest of "hi".
void check() {
  require(tookMs == sendMs,
      'with a job: close must wait only for the queued call');
}
''' + CHAT_SCENARIO + RUNNER)

# A call that fails: the answer with a job throws it again from the
# handler, so it reaches the zone as the bloc alone's own failure does.
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

FILES['core_closing_bloc_failed'] = (
    BLOC_HEAD + HELPERS + CHAT_API + EVENTS + core[f'{ALONE}/ChatBloc']
    + "\nconst name = 'with bloc alone';\n" + FAILING + RUNNER)

FILES['core_closing_job_failed'] = (
    CORE_HEAD + HELPERS + CHAT_API + EVENTS + core[f'{WITH_JOB}/ChatBloc']
    + "\nconst name = 'with a job';\n" + FAILING + RUNNER)

# ------------------------------------------------------------------ write
WRITE = 'finishing-an-in-flight-write-b'
WRITE_ALONE = f'{WRITE}/with-bloc-alone'
WRITE_JOB = f'{WRITE}/with-a-job-in-the-handler'

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
    await settle();
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

# The page's watch under another name, and a watch over it that records
# every job a handler hands it: the drivers read the outcomes of jobs the
# page's code keeps to itself.
assert 'Stream<T> watch<T>(Job<T> job) {' in WATCH
RECORDING = WATCH.replace('Stream<T> watch<T>(Job<T> job) {',
                          'Stream<T> _watched<T>(Job<T> job) {') + '''
final watched = <Job<Object?>>[];

Stream<T> watch<T>(Job<T> job) {
  watched.add(job);
  return _watched(job);
}

/// Each of [count] events has its job, and every job ends at Done or
/// Cancelled: a Failed one is an error the watch of a replaced handler had
/// nobody left to hand to. A handler restartable() lets in after it
/// cancels another starts when that cancellation is done, and its job with
/// it, so the jobs are counted before they are awaited.
Future<void> requireEnded(int count) async {
  for (var waited = 0; watched.length < count; waited++) {
    require(waited < 1000, 'only ${watched.length} of $count jobs started');
    await delay(1);
  }
  for (final job in watched) {
    final outcome = await job.done;
    require(outcome is Done || outcome is Cancelled,
        'a job must not fail: $outcome');
  }
}
'''

FILES['core_write_bloc'] = (
    BLOC_HEAD + HELPERS + FIRMWARE + core[f'{WRITE_ALONE}/LockedFirmwareBloc']
    + '''
Bloc<Flash, FirmwareState> firmwareBloc(Ble ble) => LockedFirmwareBloc(ble);

Future<void> settle() => delay(200);
''' + FLASHING + RUNNER)

FILES['core_write_job'] = (
    CORE_HEAD + HELPERS + RECORDING + FIRMWARE
    + core[f'{WRITE_JOB}/FirmwareBloc'] + '''
Bloc<Flash, FirmwareState> firmwareBloc(Ble ble) => FirmwareBloc(ble);

Future<void> settle() async {
  await requireEnded(3);
  watched.clear();
}
''' + FLASHING + RUNNER)

# --------------------------------------------------------------- resource
RESOURCE = 'releasing-a-resource-returned-'
RESOURCE_ALONE = f'{RESOURCE}/with-bloc-alone'
RESOURCE_JOB = f'{RESOURCE}/with-a-job-in-the-handler'

# The decoder of the vs-bloc probe: clip 1 takes 50 ms, clip 2 takes 20,
# so the second answers first. One trace for the calls and the buffers.
PREVIEW = '''
final trace = <String>[];

class Clip {
  const Clip(this.id);

  final int id;
}

/// A native PCM buffer. Releasing it is not optional.
class Buffer {
  Buffer(this.clip);

  final Clip clip;
  int releases = 0;

  int waveform() {
    trace.add('sample ${clip.id}');
    return clip.id;
  }

  Future<void> release() async {
    releases++;
    trace.add('release ${clip.id}');
  }
}

class Decoder {
  final buffers = <Buffer>[];

  Future<Buffer> open(Clip clip) async {
    trace.add('open ${clip.id}');
    await delay(clip.id == 1 ? 50 : 20);
    final buffer = Buffer(clip);
    buffers.add(buffer);
    trace.add('ready ${clip.id}');
    return buffer;
  }
}

final class OpenPreview {
  const OpenPreview(this.clip);

  final Clip clip;
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
  const Preview(this.waveform);

  final int waveform;

  @override
  String toString() => 'Preview($waveform)';
}
'''

# Clip 2 opened 5 ms after clip 1; then the same with close() 10 ms in,
# while both decode. Each buffer is released once, the current one too.
PREVIEWING = '''
Future<void> scenario() async {
  for (final closing in [false, true]) {
    trace.clear();
    final decoder = Decoder();
    final bloc = previewBloc(decoder)..add(const OpenPreview(Clip(1)));
    await delay(5);
    bloc.add(const OpenPreview(Clip(2)));
    if (closing) {
      await delay(5);
      await bloc.close();
      trace.add('closed');
    }
    await settle();
    final releases = [for (final buffer in decoder.buffers) buffer.releases];
    if (closing) {
      print('close while both decode: $trace');
      require('$trace' ==
          '[open 1, open 2, closed, ready 2, release 2, ready 1, release 1]',
          'close: $trace');
    } else {
      print('a second clip while the first decodes: $trace, '
          'state ${bloc.state}');
      require('$trace' ==
          '[open 1, open 2, ready 2, sample 2, release 2, ready 1, release 1]',
          'a second clip: $trace');
      require('${bloc.state}' == 'Preview(2)', 'the current clip must show');
      await bloc.close();
    }
    require('$releases' == '[1, 1]',
        'every buffer must be released once: $releases');
  }
  require(zone.isEmpty, 'nothing may reach the zone: $zone');
}
'''

FILES['core_resource_bloc'] = (
    BLOC_HEAD + HELPERS + PREVIEW + core[f'{RESOURCE_ALONE}/GuardedPreviewBloc']
    + '''
Bloc<OpenPreview, PreviewState> previewBloc(Decoder decoder) =>
    GuardedPreviewBloc(decoder);

Future<void> settle() => delay(100);
''' + PREVIEWING + RUNNER)

FILES['core_resource_job'] = (
    CORE_HEAD + HELPERS + RECORDING + PREVIEW
    + core[f'{RESOURCE_JOB}/PreviewBloc'] + '''
Bloc<OpenPreview, PreviewState> previewBloc(Decoder decoder) =>
    PreviewBloc(decoder);

/// The jobs end before the late buffer arrives: it is released when it
/// does, after the jobs.
Future<void> settle() async {
  await requireEnded(2);
  watched.clear();
  await delay(100);
}
''' + PREVIEWING + RUNNER)

for key, body in FILES.items():
    if key.startswith('core_'):
        assert 'package:solo' not in body, f'{key} imports solo'

unbuilt = core.unbuilt()
assert not unbuilt, f'blocks of the core page no driver builds: {unbuilt}'

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
