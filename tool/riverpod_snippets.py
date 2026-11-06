#!/usr/bin/env python3
"""Builds runnable scenarios from packages/solo/doc/riverpod.md.

Every snippet is copied byte-identical out of the markdown and wrapped in a
runnable file: fakes above it, a driver below it. The page says what a solo
controller does under a riverpod provider, and what riverpod does around
it; the drivers hold both with `require`, so a riverpod that starts doing
otherwise turns the run red instead of printing something else.

Usage, from the repository root:

    python3 tool/riverpod_snippets.py [workdir]
    python3 tool/riverpod_snippets.py --list

The default workdir is /tmp/riverpod-check. It creates one package,
riverpod_check, with a path dependency on packages/solo and an override
on packages/async_job. Then:

    dart pub get
    dart analyze --fatal-infos bin/v
    dart run bin/v/bridge.dart   # and so on

The drivers run on virtual time, under the runner of
tool/adapter_snippets.py and for the reason tool/doc_snippets.py gives.

Blocks are addressed by `subsection_blocks` of tool/doc_blocks.py: section,
`###` subsection and the name a block declares. A first attempt and its
answer declare the same provider, and the subsection tells them apart.

Every `dart` block of the page is built: the script stops if one of them
went into no driver.
"""
import os
import sys

import doc_blocks

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = sys.argv[1] if len(sys.argv) > 1 else '/tmp/riverpod-check'
DOC = os.path.join(REPO, 'packages', 'solo', 'doc', 'riverpod.md')

# The version the page names, resolved at its newest on the SDK of the job.
# solo comes from the tree, and so does the async_job under it: solo in the
# tree can depend on an async_job that is not released yet.
PUBSPEC = """name: riverpod_check
publish_to: none

environment:
  sdk: ^3.10.0

dependencies:
  fake_async: ^1.3.1
  riverpod: ^3.5.0
  solo:
    path: {solo}

dev_dependencies:
  lints: ^5.1.1

dependency_overrides:
  async_job:
    path: {async_job}
""".format(
    solo=os.path.join(REPO, 'packages', 'solo'),
    async_job=os.path.join(REPO, 'packages', 'async_job'),
)

snips = doc_blocks.Blocks(doc_blocks.subsection_blocks(open(DOC).read()))
if ROOT == '--list':
    for key in snips:
        poisoned = dict.__getitem__(snips, key) is doc_blocks.POISONED
        print(key, '(declared twice)' if poisoned else '')
    sys.exit(0)


def replaced(source, old, new, count=1):
    """source with old replaced, failing if old is not there count times."""
    assert source.count(old) == count, f'expected {count}x: {old!r}'
    return source.replace(old, new)


CONTROLLER = 'a-controller-under-a-provider'
CAMERA_SECTION = 'a-camera-closed-when-the-scree'
FORM = 'a-form-sent-once'

HEAD = """import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:riverpod/riverpod.dart';
import 'package:solo/solo.dart';
"""

# The drivers of riverpod alone, without a controller.
RIVERPOD_HEAD = HEAD.replace("import 'package:solo/solo.dart';\n", '')

# The drivers of a controller alone, without riverpod.
SOLO_HEAD = HEAD.replace("import 'package:riverpod/riverpod.dart';\n", '')

# The device of the page: opening it takes 50 ms, closing it is at once.
# `alive` holds the devices opened and not closed, `log` what happened to
# each. The drivers act between those marks, never on one: two events on
# the same millisecond of virtual time run in an order real time would not
# keep. What reaches the zone of a screen is in `zone`.
DEVICE = '''
final alive = <int>{};
final log = <String>[];
final zone = <Object>[];
var _opened = 0;

final class Device {
  Device._(this.id);

  final int id;

  static Future<Device> open() async {
    final device = Device._(++_opened);
    log.add('open ${device.id} start');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    alive.add(device.id);
    log.add('open ${device.id} done');
    return device;
  }

  Future<void> close() async {
    alive.remove(id);
    log.add('close $id');
  }
}

Future<void> delay(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

/// Runs [screen] in a zone of its own, with a fresh device log. The zone is
/// not awaited -- a guarded body that fails never completes -- and the
/// driver waits on a completer the body completes in `finally`.
Future<void> guarded(Future<void> Function() screen) {
  log.clear();
  _opened = 0;
  final ended = Completer<void>();
  runZonedGuarded(() async {
    try {
      await screen();
    } finally {
      ended.complete();
    }
  }, (error, _) => zone.add(error));
  return ended.future;
}
'''

# The `main` of every driver; the driver itself is `scenario`. The same
# runner as in tool/adapter_snippets.py, which says why the clock is
# elapsed from outside the fake zone.
RUNNER = '''
Future<void> main() async {
  Object? failure;
  StackTrace? failureTrace;
  var ended = false;
  final clock = FakeAsync()
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
    clock.flushMicrotasks();
    await Future<void>.delayed(Duration.zero);
    if (ended || clock.microtaskCount > 0) {
      continue;
    }
    if (clock.elapsed > const Duration(minutes: 10)) {
      throw StateError('the scenario did not end in ten of its minutes');
    }
    clock.elapse(const Duration(milliseconds: 1));
  }
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureTrace!);
  }
}
'''

# A screen that opens the camera and leaves `milliseconds` in, watching
# the state the way the page says. It prints the outcome of the opening,
# the states the screen saw and the device log.
SCREEN = '''
String shown(CameraState state) => switch (state) {
  Ready(:final device) => 'Ready(${device.id})',
  _ => '${state.runtimeType}',
};

int rebuilds = 0;

Future<Outcome<void>?> leave(int milliseconds) async {
  final seen = <String>[];
  Job<void>? opened;
  rebuilds = 0;
  await guarded(() async {
    final container = ProviderContainer();
    final screen = container.listen(
      camera.select((camera) => camera.currentState),
      (_, state) => seen.add(shown(state)),
      fireImmediately: true,
    );
    // A widget that takes the controller to build from it with SoloBuilder,
    // the way the page says.
    final builder = container.listen(
      camera.select((camera) => camera),
      (_, _) => rebuilds++,
    );
    opened = container.read(camera).open();
    await delay(milliseconds);
    print('screen left at $milliseconds ms');
    builder.close();
    screen.close();
    await delay(200);
    container.dispose();
  });
  print('outcome: ${opened?.outcome}');
  print('states: ${seen.join(', ')}');
  print('device: ${log.join(', ')}');
  return opened?.outcome;
}
'''

# A screen that listens to a provider of the device itself and leaves
# `milliseconds` in, under an observer that keeps what fails. It prints the
# device log.
WATCHER = '''
final failed = <Object>[];

final class Watcher extends ProviderObserver {
  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) => failed.add(error);
}

Future<void> leave(int milliseconds) async {
  failed.clear();
  await guarded(() async {
    final container = ProviderContainer(observers: [Watcher()]);
    final screen = container.listen(camera, (_, _) {});
    await delay(milliseconds);
    print('screen left at $milliseconds ms');
    screen.close();
    await delay(200);
    container.dispose();
  });
  print('device: ${log.join(', ')}');
}
'''

STATES = snips[f'{CONTROLLER}/CameraState']
assert STATES is snips[f'{CONTROLLER}/Ready']
CAMERA = snips[f'{CONTROLLER}/Camera']

ANSWER = snips[f'{CONTROLLER}/removing-the-listener/'
               'final-camera-provider-autodisp']

FILES = {}

# ------------------------------------------------------------- controller
# The screen leaves 10 ms in, while the device opens. Without removeListener
# the controller publishes Closed to a provider already disposed.
FILES['bridge_first'] = (
    HEAD + STATES + CAMERA
    + snips[f'{CONTROLLER}/the-first-attempt/'
            'the-first-attempt-the-controll']
    + DEVICE + SCREEN + '''
Future<void> scenario() async {
  await leave(10);
  require(zone.length == 1, 'one error reaches the zone: $zone');
  final error = '${zone.single}';
  require(
    error.startsWith('Cannot use the Ref of'),
    'the listener calls a disposed Ref: $error',
  );
  // The first sentence, without the provider's hash: it changes per run.
  final sentence = error.substring(0, error.indexOf('.') + 1);
  print('zone: ${sentence.replaceFirst(RegExp('#[0-9a-f]+'), '')}');
}
''' + RUNNER)

FILES['bridge'] = (
    HEAD + STATES + CAMERA + ANSWER + DEVICE + SCREEN + '''
Future<void> scenario() async {
  final outcome = await leave(10);
  require(zone.isEmpty, 'nothing reaches the zone: $zone');
  print('zone: nothing');
  require(outcome is Cancelled, 'the closing cancels the opening: $outcome');
  require(alive.isEmpty, 'the device opened late is closed: $alive');
  require(rebuilds == 0, 'the widget with SoloBuilder is not rebuilt: '
      '$rebuilds');
}
''' + RUNNER)

# ----------------------------------------------------------------- camera
# riverpod alone: the screen leaves 10 ms in, while the device opens, and
# the provider registers its cleanup only after the await.
FILES['camera_naive'] = (
    RIVERPOD_HEAD + snips[f'{CAMERA_SECTION}/the-first-attempt/'
                 'the-first-attempt-the-cleanup-']
    + DEVICE + WATCHER + '''
Future<void> scenario() async {
  await leave(10);
  final names = failed.map((error) => '${error.runtimeType}');
  print('observer: ${names.isEmpty ? 'nothing' : names.join(', ')}');
  require(alive.length == 1, 'the device stays open: $alive');
  require(zone.isEmpty, 'nothing reaches the zone: $zone');
  require(names.isEmpty, 'the late onDispose reaches no observer: $names');
}
''' + RUNNER)

# riverpod's own recipe: a flag set on disposal before the await. The
# screen leaves while the device opens, and after it opened.
FILES['camera_flag'] = (
    RIVERPOD_HEAD + snips[f'{CAMERA_SECTION}/a-flag-before-the-await/'
                 'final-camera-futureprovider-au']
    + DEVICE + WATCHER + '''
Future<void> scenario() async {
  await leave(10);
  require(alive.isEmpty, 'leaving while it opens closes it: $alive');
  await leave(80);
  require(alive.isEmpty, 'leaving after it opened closes it: $alive');
  require(zone.isEmpty, 'nothing reaches the zone: $zone');
}
''' + RUNNER)

# The controller of the first section, left 80 ms in: the opening is over,
# close() has no job to cancel, and nothing closes the device.
FILES['camera_late'] = (
    HEAD + STATES + CAMERA + ANSWER + DEVICE + SCREEN + '''
Future<void> scenario() async {
  final outcome = await leave(80);
  require(outcome is Done, 'the opening was over: $outcome');
  require(alive.length == 1, 'the device stays open: $alive');
  require(zone.isEmpty, 'nothing reaches the zone: $zone');
}
''' + RUNNER)

# The controller with onClose, left while the device opens and after.
FILES['camera_on_close'] = (
    HEAD + STATES + snips[f'{CAMERA_SECTION}/onclose/Camera'] + ANSWER
    + DEVICE + SCREEN + '''
Future<void> scenario() async {
  final early = await leave(10);
  require(early is Cancelled, 'the closing cancels the opening: $early');
  require(alive.isEmpty, 'discard closes the late device: $alive');
  final late = await leave(80);
  require(late is Done, 'the opening was over: $late');
  require(alive.isEmpty, 'onClose closes the open device: $alive');
  require(zone.isEmpty, 'nothing reaches the zone: $zone');
}
''' + RUNNER)

# ------------------------------------------------------------------ price
# The camera with onClose under its provider, as the page leaves it.
# What the page says of `ctx.join` in the camera: it waits for the opening
# even when the job is cancelled meanwhile. A `close()` 10 ms in returns
# with the device opened and closed again; under `ctx.abandonable` it would
# return at once and the device would open after it.
JOIN = '''
Future<void> scenario() async {
  var closed = '';
  Job<void>? opened;
  await guarded(() async {
    final controller = Camera();
    opened = controller.open();
    await delay(10);
    await controller.close();
    closed = log.join(', ');
  });
  require(
    closed == 'open 1 start, open 1 done, close 1',
    'close() waits for the opening: $closed',
  );
  require(opened?.outcome is Cancelled, 'the closing cancels the opening');
  require(zone.isEmpty, 'nothing reaches the zone: $zone');
}
'''

FILES['camera_join'] = (
    # The block declares Ready.device, which this driver leaves alone.
    '// ignore_for_file: unreachable_from_main\n\n'
    + SOLO_HEAD + STATES + CAMERA + DEVICE + JOIN + RUNNER)
FILES['closing_join'] = (
    SOLO_HEAD + STATES + snips[f'{CAMERA_SECTION}/onclose/Camera']
    + DEVICE + JOIN + RUNNER)

CLOSING = HEAD + STATES + snips[f'{CAMERA_SECTION}/onclose/Camera'] + ANSWER

# A read with no listener: the provider makes the controller and disposes
# of it at once, and the opening ends cancelled.
FILES['price_read'] = CLOSING + DEVICE + '''
Future<void> scenario() async {
  Job<void>? opened;
  await guarded(() async {
    final container = ProviderContainer();
    opened = container.read(camera).open();
    await delay(200);
    container.dispose();
  });
  final outcome = opened?.outcome;
  print('read without a listener');
  print('outcome: $outcome');
  print('device: ${log.join(', ')}');
  require(outcome is Cancelled, 'the controller closed at once: $outcome');
  require(alive.isEmpty, 'the device opened late is closed: $alive');
  require(zone.isEmpty, 'nothing reaches the zone: $zone');
}
''' + RUNNER

# The screen stays; the camera is open, and the provider is invalidated.
FILES['price_invalidate'] = CLOSING + DEVICE + '''
String shown(CameraState state) => switch (state) {
  Ready(:final device) => 'Ready(${device.id})',
  _ => '${state.runtimeType}',
};

Future<void> scenario() async {
  final seen = <String>[];
  late Camera first;
  late Camera second;
  await guarded(() async {
    final container = ProviderContainer();
    final screen = container.listen(
      camera.select((camera) => camera.currentState),
      (_, state) => seen.add(shown(state)),
      fireImmediately: true,
    );
    first = container.read(camera);
    unawaited(first.open().done);
    await delay(80);
    print('camera invalidated');
    container.invalidate(camera);
    await delay(200);
    second = container.read(camera);
    screen.close();
    await delay(200);
    container.dispose();
  });
  print('states: ${seen.join(', ')}');
  print('device: ${log.join(', ')}');
  print('the first controller finished: ${first.isFinished}');
  require(first.isFinished, 'invalidate closes the controller');
  require(!identical(first, second), 'the provider made a new controller');
  require(seen.last == 'Closed', 'the screen sees the new one: $seen');
  require(alive.isEmpty, 'onClose closes the device: $alive');
  require(zone.isEmpty, 'nothing reaches the zone: $zone');
}
''' + RUNNER

# ------------------------------------------------------------------- form
MUTATION_HEAD = HEAD.replace(
    "import 'package:riverpod/riverpod.dart';\n",
    "import 'package:riverpod/experimental/mutation.dart';\n"
    "import 'package:riverpod/riverpod.dart';\n")

# The API of the page: it answers in 30 ms with a receipt numbered by its
# call, the number taken before the wait.
SEND = '''
int calls = 0;
int inFlight = 0;
int maxInFlight = 0;

Future<String> send(String text) async {
  final call = ++calls;
  if (++inFlight > maxInFlight) maxInFlight = inFlight;
  await Future<void>.delayed(const Duration(milliseconds: 30));
  inFlight--;
  return 'sent $text #$call';
}

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
'''

MUTATION = snips[f'{FORM}/the-first-attempt/submit']

FORM_STATES = snips[f'{FORM}/policy-droppable/MessageState']
FORM_CONTROLLER = snips[f'{FORM}/policy-droppable/MessageForm']

# What the page quotes from riverpod's own documentation: a mutation run
# twice without the guard sends twice. Should riverpod start restricting
# concurrent calls, this turns red, and the quote goes from the page.
FILES['form_unguarded'] = (
    # The block declares submit, which this driver leaves alone.
    '// ignore_for_file: unreachable_from_main\n\n'
    + MUTATION_HEAD.replace("import 'package:solo/solo.dart';\n", '')
    + MUTATION + SEND + '''
Future<void> scenario() async {
  final container = ProviderContainer();
  final button = container.listen(sendMessage, (_, _) {});
  await Future.wait([
    sendMessage.run(container, (_) => send('hi')),
    sendMessage.run(container, (_) => send('bye')),
  ]);
  print('without the guard: calls: $calls');
  require(calls == 2, 'a mutation does not restrict calls: $calls');
  button.close();
  container.dispose();
}
''' + RUNNER)

# The guard of the page: 'hi', then 'bye' while 'hi' is on its way.
FILES['form_mutation'] = (
    MUTATION_HEAD.replace("import 'package:solo/solo.dart';\n", '')
    + MUTATION + SEND + '''
Future<void> scenario() async {
  final container = ProviderContainer();
  final button = container.listen(sendMessage, (_, _) {});
  final first = submit(container, 'hi');
  final pending = container.read(sendMessage);
  print('right after the first: $pending');
  final second = submit(container, 'bye');
  final firstReceipt = await first;
  final secondReceipt = await second;
  print('first: $firstReceipt');
  print('second: $secondReceipt');
  print('calls: $calls');
  require(pending is MutationPending, 'run is pending at once: $pending');
  require(calls == 1, 'the guard sends once: $calls');
  require(
    firstReceipt == 'sent hi #1' && secondReceipt == null,
    'the second caller gets null: $firstReceipt, $secondReceipt',
  );
  button.close();
  container.dispose();
}
''' + RUNNER)

FILES['form_droppable'] = (
    SOLO_HEAD + FORM_STATES + FORM_CONTROLLER + SEND + '''
Future<void> scenario() async {
  final form = MessageForm();
  final first = form.submit('hi');
  final second = form.submit('bye');
  print('same job: ${identical(first, second)}');
  final firstReceipt = await first.value;
  final secondReceipt = await second.value;
  print('first: $firstReceipt');
  print('second: $secondReceipt');
  print('calls: $calls');
  final state = form.currentState;
  print('state: ${state is Sent ? 'Sent(${state.receipt})' : state}');
  require(identical(first, second), 'droppable hands out the same job');
  require(calls == 1, 'the form sends once: $calls');
  require(
    firstReceipt == 'sent hi #1' && secondReceipt == 'sent hi #1',
    'both callers get the receipt of hi: $firstReceipt, $secondReceipt',
  );
  require(state is Sent && state.receipt == 'sent hi #1', 'state: $state');
  await form.close();
}
''' + RUNNER)

# What the page says of `ctx.join` in the form: a cancelled send holds the
# queue until it is over, and a `submit` that comes meanwhile gets the
# cancelled job back instead of starting a second send. Under
# `ctx.abandonable` the job would end at once, and the next `submit` would
# send while the first is still on its way.
FILES['form_cancelled'] = (
    # The block declares Sent.receipt, which this driver leaves alone.
    '// ignore_for_file: unreachable_from_main\n\n'
    + SOLO_HEAD + FORM_STATES + FORM_CONTROLLER + SEND + '''
Future<void> scenario() async {
  final form = MessageForm();
  final first = form.submit('hi');
  await Future<void>.delayed(const Duration(milliseconds: 10));
  unawaited(first.cancel());
  await Future<void>.delayed(const Duration(milliseconds: 1));
  final second = form.submit('bye');
  await first.done;
  await second.done;
  require(first.outcome is Cancelled, 'the first send is cancelled');
  require(
    maxInFlight == 1,
    'a submit after the cancellation waits for the send: $maxInFlight',
  );
  await form.close();
}
''' + RUNNER)

unbuilt = snips.unbuilt()
assert not unbuilt, f'blocks of the page no driver builds: {unbuilt}'

d = f'{ROOT}/riverpod_check/bin/v'
os.makedirs(d, exist_ok=True)
for key, body in FILES.items():
    open(f'{d}/{key}.dart', 'w').write(body)

open(f'{ROOT}/riverpod_check/pubspec.yaml', 'w').write(PUBSPEC)
# The rules of solo itself: a fragment that passes here would pass inside
# the package.
with open(os.path.join(REPO, 'packages', 'solo',
                       'analysis_options.yaml')) as rules:
    open(f'{ROOT}/riverpod_check/analysis_options.yaml', 'w').write(
        rules.read())
print('wrote', len(FILES), 'files under', ROOT)
