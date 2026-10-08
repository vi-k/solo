@Timeout(Duration(seconds: 10))
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:solo_example/solo_example.dart';
import 'package:test/test.dart';

import '../bin/main.dart' as program;
import 'support/camera_attempts.dart';
import 'support/camera_attempts_listener.dart' as listener;
import 'support/camera_page.dart';
import 'support/journal.dart';
import 'support/page_code.dart';

/// The code of `doc/camera.md`, run as the page writes it, and what the
/// page says about it.
///
/// The first and second attempts stand verbatim in
/// `support/camera_attempts.dart` and `support/camera_attempts_listener.dart`,
/// the answers that are not yet the example's code in
/// `support/camera_page.dart`, and the last fragment of each method is
/// [CameraController] itself. Every journal the page quotes is read from the
/// page and compared with a real run, and every sentence a test checks is
/// held to the page through [_says]: a page that stops saying it turns the
/// test red. The group at the end holds the code of the page to those files
/// line for line.

/// What the page says of versions it does not show, and what a test has to
/// see from inside a body. None of this is the page's code.
final class Variants extends Solo<CameraState>
    with CameraParts, CheckedDisposal {
  @override
  final FakeCameraHardware hw;

  /// What the `emit` inside the catch threw, when it threw.
  Object? emitThrew;

  Variants(this.hw) : super(const Initial());

  /// "A working type wide enough" without its `canStart`.
  Job<void> initWithoutCanStart() => run<NotDisposed, void>(
        key: CameraKey.init,
        policy: Policy.droppable,
        (ctx) async {
          ctx.emit(const Preparing());
          await ctx.join(hw.open);
          ctx.emit(const Ready());
        },
      );

  /// The catch of "An opening that fails", telling what its `emit` did.
  Job<void> initWatchingTheCatch() => run<NotDisposed, void>(
        key: CameraKey.init,
        (ctx) async {
          ctx.emit(const Preparing());
          try {
            await ctx.join(hw.open);
          } on Object catch (error) {
            try {
              ctx.emit(Broken(error));
            } on Object catch (thrown) {
              emitThrew = thrown;
              rethrow;
            }
            rethrow;
          }
          ctx.emit(const Ready());
        },
      );

  /// The shot without its clear.
  Job<Photo> takePhotoKeepingQueue() => run<Ready, Photo>(
        key: CameraKey.takePhoto,
        policy: Policy.droppable,
        canStart: (state) => !state.paused,
        (ctx) async {
          final photo = await ctx.join(hw.capture);
          ctx.log('captured $photo');
          return photo;
        },
      );

  /// The disposal of "Checking in the body" with the clear forced.
  Job<void> disposeForced() {
    queue.clear(force: true);
    return dispose();
  }

  /// A job like the disposal, to stand in the queue.
  Job<void> queueLikeADisposal() => run<CameraState, void>(
        key: CameraKey.dispose,
        cancellable: false,
        (ctx) async {},
      );

  /// What waits in the queue, by key.
  List<String> get queued => [
        for (final job in queue.jobs) (job.key! as Enum).name,
      ];

  /// `queue.clear`, for a test to call.
  int clearQueue({bool force = false}) => queue.clear(force: force);

  /// `queue.removeWhere` over every job, for a test to call.
  int removeEverything({bool force = false}) =>
      queue.removeWhere((job) => true, force: force);
}

/// The second attempt of "A failure after the disposal", counting the calls
/// of its `onClose`.
final class CountingClose extends listener.ClosingCameraController {
  /// How many times the engine called `onClose`.
  int closes = 0;

  CountingClose(super.hw);

  @override
  void onClose() {
    closes++;
    super.onClose();
  }
}

/// Runs [body] under a fake clock with a journal, and closes what it made.
void camera<C extends Solo<CameraState>>(
  C Function(FakeCameraHardware hw) create,
  void Function(
    C camera,
    FakeCameraHardware hw,
    JournalObserver journal,
    FakeAsync async,
  ) body, {
  FakeCameraHardware? hardware,
}) {
  fakeAsync((async) {
    final journal = JournalObserver();
    Solo.observer = journal;
    final hw = hardware ?? FakeCameraHardware();
    final camera = create(hw);
    try {
      body(camera, hw, journal, async);
    } finally {
      camera.close().ignore();
      async.flushTimers();
      Solo.observer = null;
    }
  });
}

/// Runs [body] under a fake clock with a journal, in a zone of its own, and
/// returns what reached that zone uncaught and what was printed there.
///
/// Nothing may be asserted inside: a failed `expect` would go to the zone's
/// handler instead of the test. The body tells what it saw through its
/// closure, and the test asserts once this has returned.
({List<Object> zone, List<String> printed}) alone(
  void Function(FakeAsync async, JournalObserver journal) body,
) {
  final zone = <Object>[];
  final printed = <String>[];
  runZonedGuarded(
    () => fakeAsync((async) {
      final journal = JournalObserver();
      Solo.observer = journal;
      try {
        body(async, journal);
      } finally {
        for (final solo in journal.created) {
          solo.close().ignore();
        }
        async.flushTimers();
        Solo.observer = null;
      }
    }),
    (error, stackTrace) => zone.add(error),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => printed.add(line),
    ),
  );
  return (zone: zone, printed: printed);
}

/// Opens [open] and clears what the opening wrote.
void opened(
  Job<void> Function() open,
  FakeCameraHardware hw,
  JournalObserver journal,
  FakeAsync async,
) {
  open().ignoreFailure();
  async.elapse(const Duration(milliseconds: 10));
  journal.take();
  hw.log.clear();
}

/// The `init` of [camera], whichever version it is: the example and the
/// versions of the page share no interface.
Job<void> Function() _init(Solo<CameraState> camera) => switch (camera) {
      CameraController() => camera.init,
      CameraParts() => camera.init,
      _ => throw ArgumentError.value(camera),
    };

/// The `setZoom` of [camera], whichever version it is.
Job<void> Function(double zoom) _setZoom(Solo<CameraState> camera) =>
    switch (camera) {
      CameraController() => camera.setZoom,
      CameraParts() => camera.setZoom,
      _ => throw ArgumentError.value(camera),
    };

/// The `takePhoto` of [camera], whichever version it is.
Job<Photo> Function() _takePhoto(Solo<CameraState> camera) => switch (camera) {
      CameraController() => camera.takePhoto,
      CameraParts() => camera.takePhoto,
      _ => throw ArgumentError.value(camera),
    };

/// The `dispose` of [camera], whichever version it is.
Job<void> Function() _dispose(Solo<CameraState> camera) => switch (camera) {
      CameraController() => camera.dispose,
      CheckedDisposal() => camera.dispose,
      QueuedDisposal() => camera.dispose,
      _ => throw ArgumentError.value(camera),
    };

/// A constructor of a version.
typedef _Create = Solo<CameraState> Function(FakeCameraHardware hw);

const _page = '../doc/camera.md';
const _intro = '# Camera example';
const _opening = '## Opening the camera';
const _failing = '## An opening that fails';
const _zoom = '## Only the last zoom';
const _shot = '## Commands that arrive during a shot';
const _disposing = '## Disposing of the camera';
const _closing = '## Closing the controller';
const _failure = '## A failure after the disposal';
const _running = '## Running the example';
const _first = '### The first attempt';
const _second = '### The second attempt';

/// The page cut at its headings.
List<String> _parts() =>
    File(_page).readAsStringSync().split(RegExp('^(?=#)', multiLine: true));

/// The part of the page under [heading] of [section], up to the next
/// heading; the part under [section] itself when no heading is named.
String _part(String section, [String? heading]) {
  var inside = false;
  for (final part in _parts()) {
    final first = part.split('\n').first;
    if (!first.startsWith('###')) {
      inside = first == section;
      if (inside && heading == null) {
        return part;
      }
    } else if (inside && first == heading) {
      return part;
    }
  }
  throw StateError('$_page has no "$heading" under "$section"');
}

/// The journals [part] quotes, each as its lines.
List<List<String>> _quoted(String part) => [
      for (final match
          in RegExp(r'```text\n(.*?)\n```', dotAll: true).allMatches(part))
        match.group(1)!.split('\n'),
    ];

/// Holds [part] to [sentence]: its prose, the breaks of its lines aside.
void _says(String part, String sentence) => expect(
      part
          .replaceAll(RegExp('```.*?```', dotAll: true), ' ')
          .replaceAll(RegExp(r'\s+'), ' '),
      contains(sentence),
    );

/// A copy of [file] without its comments, for the checks that compare code
/// line by line: the page shows the example's code "comments aside".
String _withoutComments(String file, Directory into) {
  final code = [
    for (final line in File(file).readAsLinesSync())
      if (!line.trim().startsWith('//')) line,
  ];
  final copy = File('${into.path}/${file.split('/').last}')
    ..writeAsStringSync(code.join('\n'));
  return copy.path;
}

/// A copy of the example's states as the page shows them, and the first
/// line of every member the copy leaves out: the page shows the classes
/// without their comments, their annotations and what they override.
({String path, List<String> added}) _statesOfThePage(Directory into) {
  final kept = <String>[];
  final added = <String>[];
  var skipping = false;
  var named = false;
  for (final line in File('lib/src/camera_state.dart').readAsLinesSync()) {
    final text = line.trim();
    if (skipping) {
      if (!named) {
        added.add(text);
        named = true;
      }
      skipping = !text.endsWith(';');
    } else if (text == '@override') {
      skipping = true;
      named = false;
    } else if (!text.startsWith('//') && text != '@immutable') {
      kept.add(line);
    }
  }
  final copy = File('${into.path}/camera_state.dart')
    ..writeAsStringSync(kept.join('\n'));
  return (path: copy.path, added: added);
}

void main() {
  tearDown(() => Solo.observer = null);

  group('the states', () {
    test('the page shows the states of the example', () {
      final scratch = Directory.systemTemp.createTempSync('camera_page');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final states = _statesOfThePage(scratch);

      expect(codeMissingFrom(_page, states.path, under: _intro), isEmpty);
      // What the example has and the page leaves out.
      expect(states.added, [
        "String toString() => 'Initial()';",
        "String toString() => 'Preparing()';",
        'bool operator ==(Object other) =>',
        'int get hashCode => Object.hash(zoom, focusPoint, paused);',
        'String toString() =>',
        r"String toString() => 'Broken($error)';",
        "String toString() => 'Disposed()';",
      ]);
    });

    test('every state prints itself, and Ready is compared by its fields', () {
      final intro = _part(_intro);
      _says(
        intro,
        'In the example every state also prints itself, and that text is '
        'what the journals below show; two `Ready` states with the same '
        'fields are equal there as well.',
      );

      final error = StateError('x');
      expect(
        [
          '${const Initial()}',
          '${const Preparing()}',
          '${const Ready()}',
          '${Broken(error)}',
          '${const Disposed()}',
        ],
        [
          'Initial()',
          'Preparing()',
          'Ready(zoom: 1.0, focusPoint: null, paused: false)',
          'Broken(Bad state: x)',
          'Disposed()',
        ],
      );
      final zoom = [2.0];
      expect(Ready(zoom: zoom.single), Ready(zoom: zoom.single));
      expect(Ready(zoom: zoom.single), isNot(const Ready()));
    });

    test('NotDisposed groups every state but Disposed', () {
      _says(
        _part(_intro),
        '`NotDisposed` groups every state in which the hardware can still '
        'be talked to, and `Disposed` is the one where it cannot.',
      );

      final states = <CameraState>[
        const Initial(),
        const Preparing(),
        const Ready(),
        Broken(StateError('x')),
        const Disposed(),
      ];
      expect(states.whereType<NotDisposed>(), hasLength(4));
      expect(states.last, isNot(isA<NotDisposed>()));
    });

    test('copyWith cannot clear focusPoint', () {
      _says(
        _part(_intro),
        'A `null` passed to `copyWith` keeps the old value, so `copyWith` '
        'cannot clear `focusPoint`, where `null` means automatic focus.',
      );
      const ready = Ready(zoom: 2, focusPoint: Point(0.5, 0.5));

      // The null is what the test passes on purpose.
      // ignore: avoid_redundant_argument_values
      expect(ready.copyWith(focusPoint: null), ready);
    });

    test('resetFocusPoint publishes a fresh Ready with the current zoom', () {
      _says(
        _part(_intro),
        "The example's `resetFocusPoint` publishes a fresh `Ready` that "
        'keeps the current zoom.',
      );
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);
        camera.setZoom(2).ignoreFailure();
        camera.setFocusPoint(const Point(0.5, 0.5)).ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));
        expect(
          camera.currentState,
          const Ready(zoom: 2, focusPoint: Point(0.5, 0.5)),
        );

        camera.resetFocusPoint().ignoreFailure();
        async.elapse(const Duration(milliseconds: 10));

        expect(camera.currentState, const Ready(zoom: 2));
      });
    });
  });

  group('the hardware and the journals', () {
    test('the controller keeps the hardware in hw', () {
      _says(
        _part(_intro),
        'The hardware is `FakeCameraHardware` from the example, and the '
        'controller keeps it in its field `hw`.',
      );
      camera(CameraController.new, (camera, hw, journal, async) {
        expect(camera.hw, same(hw));
      });
    });

    test('an operation takes ten milliseconds and a capture thirty', () {
      _says(
        _part(_intro),
        'Every operation takes ten milliseconds and a capture thirty, and '
        'a capture returns a `Photo`.',
      );
      fakeAsync((async) {
        final hw = FakeCameraHardware();
        final over = <String>[];
        Object? photo;
        hw.open().then((_) => over.add('open')).ignore();
        hw.close().then((_) => over.add('close')).ignore();
        hw.setZoom(2).then((_) => over.add('zoom')).ignore();
        hw.setFocusPoint(null).then((_) => over.add('focus')).ignore();
        hw.capture().then((value) => photo = value).ignore();

        async.elapse(const Duration(milliseconds: 9));
        expect(over, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(over, ['open', 'close', 'zoom', 'focus']);
        async.elapse(const Duration(milliseconds: 19));
        expect(photo, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(photo, const Photo(1));
      });
    });

    test('failures makes a named operation fail after its delay', () {
      _says(
        _part(_intro),
        '`failures` makes a named operation fail after its delay',
      );
      fakeAsync((async) {
        final hw = FakeCameraHardware()
          ..failures['zoom'] = StateError('lens stuck');
        Object? thrown;
        hw.setZoom(2).onError<Object>((error, _) {
          thrown = error;
        }).ignore();

        async.elapse(const Duration(milliseconds: 9));
        expect(thrown, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(thrown, isA<StateError>());
        // The other operations go on working.
        var opened = false;
        hw.open().then((_) => opened = true).ignore();
        async.elapse(const Duration(milliseconds: 10));
        expect(opened, isTrue);
      });
    });

    test('fail reports through onError, from outside any job', () {
      _says(
        _part(_intro),
        '`fail` reports a failure from outside any job by calling '
        '`onError`, the callback the controller sets',
      );
      final hw = FakeCameraHardware();
      final error = StateError('cable pulled');

      // Nobody listens: nothing happens.
      hw.fail(error);
      final reported = <Object>[];
      hw
        ..onError = reported.add
        ..fail(error);

      expect(reported, [same(error)]);
      camera(CameraController.new, (camera, hw, journal, async) {
        expect(hw.onError, isNotNull);
        hw.fail(error);
        expect(journal.take(), ['state: Broken(Bad state: cable pulled)']);
      });
    });

    test('log records where each operation begins and ends', () {
      _says(
        _part(_intro),
        '`log` records where each operation begins and ends.',
      );
      fakeAsync((async) {
        final hw = FakeCameraHardware()
          ..failures['zoom'] = StateError('lens stuck');
        hw.open().ignore();
        async.elapse(const Duration(milliseconds: 5));
        expect(hw.log, ['open: begin']);
        async.elapse(const Duration(milliseconds: 5));
        hw.setZoom(2).ignore();
        async.elapse(const Duration(milliseconds: 10));

        expect(hw.log, [
          'open: begin',
          'open: end',
          'zoom 2.0: begin',
          'zoom 2.0: failed',
        ]);
      });
    });

    test('a job goes by its key and its describe text, a child by >', () {
      final intro = _part(_intro);
      _says(
        intro,
        'a job `started`, `finished` with its outcome or `dropped` before '
        'it started, an `error` it reported, a `log` line, every change of '
        '`state:`, and `closed` once the controller has closed.',
      );
      _says(
        intro,
        "A job goes by its key, a value of the example's `CameraKey` enum, "
        'followed by its `describe` text where it has one: '
        "`[setZoom: zoom: 2.0]`. A child job's lines begin with `>`.",
      );
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        camera.setZoom(2).ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        final waiting = camera.setZoom(3)..ignoreFailure();
        waiting.cancel().ignore();
        async.elapse(const Duration(milliseconds: 5));
        camera.takePhoto().ignoreFailure();
        async.elapse(const Duration(milliseconds: 30));
        hw.failures['capture'] = StateError('shutter stuck');
        camera.takePhoto().ignoreFailure();
        async.elapse(const Duration(milliseconds: 30));
        camera.reopen().ignoreFailure();
        async.elapse(const Duration(milliseconds: 30));
        camera.close().ignore();
        async.flushTimers();

        expect(journal.take(), [
          '[setZoom: zoom: 2.0] started',
          '[setZoom: zoom: 3.0] dropped Cancelled(manual)',
          'state: Ready(zoom: 2.0, focusPoint: null, paused: false)',
          '[setZoom: zoom: 2.0] finished Done(null)',
          '[takePhoto] started',
          '[takePhoto] log captured Photo#1',
          '[takePhoto] finished Done(Photo#1)',
          '[takePhoto] started',
          '[takePhoto] error Bad state: shutter stuck',
          '[takePhoto] finished Failed(Bad state: shutter stuck)',
          '[reopen] started',
          '> [closeCamera] started',
          '> [closeCamera] finished Done(null)',
          'state: Preparing()',
          'state: Ready(zoom: 2.0, focusPoint: null, paused: false)',
          '[reopen] finished Done(null)',
          'closed',
        ]);
      });
    });

    test('the program of the example prints the journal a test takes', () {
      _says(
        _part(_intro),
        "The journals below are what the example's observer prints for "
        'this code',
      );
      final printed = alone((async, journal) {
        unawaited(program.main());
        async.flushTimers();
      }).printed;

      late List<String> taken;
      camera(CameraController.new, (camera, hw, journal, async) {
        camera.init().ignoreFailure();
        async.elapse(const Duration(milliseconds: 10));
        camera
          ..setZoom(2).ignoreFailure()
          ..setFocusPoint(const Point(0.5, 0.5)).ignoreFailure()
          ..takePhoto().ignoreFailure();
        async.elapse(const Duration(milliseconds: 35));
        camera.dispose().ignoreFailure();
        async.flushTimers();
        camera.close().ignore();
        async.flushTimers();
        taken = journal.take();
      });

      expect(taken, hasLength(18));
      expect(
        printed.where((line) => !line.startsWith('shot: ')),
        taken,
      );
    });
  });

  group('opening the camera', () {
    test('init publishes Preparing, opens the hardware, publishes Ready', () {
      _says(
        _part(_opening),
        '`init` publishes `Preparing`, opens the hardware and publishes '
        '`Ready`. It may start only from `Initial`.',
      );
      for (final create in <_Create>[
        WideInit.new,
        CameraController.new,
      ]) {
        camera(create, (camera, hw, journal, async) {
          _init(camera)().ignoreFailure();
          async.elapse(const Duration(milliseconds: 5));
          expect(hw.log, ['open: begin']);
          async.elapse(const Duration(milliseconds: 5));

          expect(journal.take(), [
            '[init] started',
            'state: Preparing()',
            'state: Ready(zoom: 1.0, focusPoint: null, paused: false)',
            '[init] finished Done(null)',
          ]);
          expect(hw.log, ['open: begin', 'open: end']);
        });
      }
    });

    test('a working type of Initial is broken by its own first emit', () {
      final attempt = _part(_opening, _first);
      _says(
        attempt,
        "The body's first `emit` leaves it, and the job ends `Cancelled` "
        'before `hw.open` is ever called: the hardware log stays empty.',
      );
      _says(
        attempt,
        'The controller is left in `Preparing`, and the next `init()` is '
        'dropped at its start for the same reason — the camera can no '
        'longer be opened at all.',
      );
      camera(NarrowInit.new, (camera, hw, journal, async) {
        final job = camera.init()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));

        expect(journal.take(), _quoted(attempt).single);
        expect(job.outcome, isA<Cancelled>());
        expect(hw.log, isEmpty);
        expect(camera.currentState, isA<Preparing>());

        camera.init().ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));

        expect(journal.take(), [
          '[init] dropped Cancelled(rules: is not Initial)',
        ]);
        expect(hw.log, isEmpty);
        expect(camera.currentState, isA<Preparing>());
      });
    });

    test('without canStart a second init opens the hardware again', () {
      _says(
        _part(_opening, '### A working type wide enough'),
        'Without it, a second `init()` on a camera that is already open '
        'runs again and opens the hardware a second time.',
      );
      camera(Variants.new, (camera, hw, journal, async) {
        camera.initWithoutCanStart().ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));
        camera.initWithoutCanStart().ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));

        expect(hw.log.where((line) => line == 'open: begin'), hasLength(2));
        expect(camera.currentState, isA<Ready>());
      });
    });

    test('canStart turns a second init away before it starts', () {
      final answer = _part(_opening, '### A working type wide enough');
      _says(answer, 'With it, the call ends before it starts:');
      for (final create in <_Create>[
        WideInit.new,
        CameraController.new,
      ]) {
        camera(create, (camera, hw, journal, async) {
          final open = _init(camera);
          opened(open, hw, journal, async);

          final second = open()..ignoreFailure();
          async.elapse(const Duration(milliseconds: 20));

          expect(journal.take(), _quoted(answer).single);
          expect(second.outcome, isA<Cancelled>());
          expect(hw.log, isEmpty);
          expect(camera.currentState, isA<Ready>());
        });
      }
    });

    test('a second init while the first runs gets the first one', () {
      _says(
        _part(_opening, '### A working type wide enough'),
        'A second `init()` made while the first one still runs never gets '
        'that far: `Policy.droppable` hands it the job already in flight, '
        'and the hardware is opened once.',
      );
      for (final create in <_Create>[
        WideInit.new,
        CameraController.new,
      ]) {
        camera(create, (camera, hw, journal, async) {
          final open = _init(camera);
          final first = open()..ignoreFailure();
          async.elapse(const Duration(milliseconds: 5));
          final second = open()..ignoreFailure();
          async.elapse(const Duration(milliseconds: 20));

          expect(identical(first, second), isTrue);
          expect(first.outcome, isA<Done<void>>());
          expect(hw.log.where((line) => line == 'open: begin'), hasLength(1));
          expect(
            journal.take(),
            isNot(contains('[init] dropped Cancelled(rules: canStart)')),
          );
        });
      }
    });
  });

  group('an opening that fails', () {
    test('a catch lands a failure in Broken', () {
      _says(
        _part(_failing, _first),
        'A failure lands where it should: the catch publishes `Broken`, '
        'and the job ends `Failed`.',
      );
      final hw = FakeCameraHardware()
        ..failures['open'] = StateError('camera in use');
      camera(CatchingInit.new, hardware: hw, (camera, hw, journal, async) {
        final job = camera.init()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));

        expect(job.outcome, isA<Failed>());
        expect(camera.currentState, isA<Broken>());
        expect(
          journal.take(),
          contains('state: Broken(Bad state: camera in use)'),
        );
      });
    });

    test('a catch leaves a cancelled opening in Preparing', () {
      final attempt = _part(_failing, _first);
      _says(
        attempt,
        'A cancellation passes through the same catch, and there the '
        '`emit` does not publish.',
      );
      _says(
        attempt,
        '`join` has waited for the opening, so the hardware is open, and '
        'the state says it is still opening.',
      );
      camera(CatchingInit.new, (camera, hw, journal, async) {
        final job = camera.init()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.elapse(const Duration(milliseconds: 20));

        expect(journal.take(), _quoted(attempt).single);
        expect(hw.log, ['open: begin', 'open: end']);
        expect(camera.currentState, isA<Preparing>());
      });
    });

    test('on a cancelled job the emit in the catch throws Cancelled', () {
      _says(
        _part(_failing, _first),
        'On a job that is already cancelled it is a checkpoint, and it '
        'throws `Cancelled` instead:',
      );
      camera(Variants.new, (camera, hw, journal, async) {
        final job = camera.initWatchingTheCatch()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.elapse(const Duration(milliseconds: 20));

        expect(camera.emitThrew, isA<Cancelled>());
        expect(camera.currentState, isA<Preparing>());
      });
    });

    test('neither way of opening the camera starts from Preparing', () {
      _says(
        _part(_failing, _first),
        'Neither way of opening the camera starts from `Preparing`: `init` '
        "wants `Initial`, and `reopen`, the example's way back, wants "
        '`Ready` or `Broken`.',
      );
      camera(CatchingInit.new, (camera, hw, journal, async) {
        final job = camera.init()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.elapse(const Duration(milliseconds: 20));
        journal.take();
        hw.log.clear();

        camera
          ..init().ignoreFailure()
          ..reopen().ignoreFailure();
        async.elapse(const Duration(milliseconds: 40));

        expect(journal.take(), [
          '[init] dropped Cancelled(rules: canStart)',
          '[reopen] dropped Cancelled(rules: canStart)',
        ]);
        expect(hw.log, isEmpty);
        expect(camera.currentState, isA<Preparing>());
      });
    });

    test('the reopen of the example wants Ready or Broken', () {
      camera(CameraController.new, (camera, hw, journal, async) {
        final early = camera.reopen()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 40));
        expect('${early.outcome}', 'Cancelled(rules: canStart)');

        opened(camera.init, hw, journal, async);
        final fromReady = camera.reopen()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 40));
        expect(fromReady.outcome, isA<Done<void>>());

        hw.fail(StateError('cable pulled'));
        expect(camera.currentState, isA<Broken>());
        final fromBroken = camera.reopen()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 40));
        expect(fromBroken.outcome, isA<Done<void>>());
        expect(camera.currentState, const Ready());
      });
    });

    test('the handlers land a failure in Broken', () {
      final answer = _part(_failing, '### The handlers of run');
      _says(
        answer,
        'A failure and a cancellation both land in `Broken`, and `reopen` '
        'starts from there:',
      );
      final hw = FakeCameraHardware()
        ..failures['open'] = StateError('camera in use');
      camera(CameraController.new, hardware: hw, (camera, hw, journal, async) {
        final job = camera.init()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));

        expect(journal.take(), _quoted(answer).first);
        expect(job.outcome, isA<Failed>());

        // The other app lets go of the camera.
        hw.failures.remove('open');
        final rescue = camera.reopen()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 40));

        expect(rescue.outcome, isA<Done<void>>());
        expect(camera.currentState, const Ready());
      });
    });

    test('the handlers land a cancelled opening in Broken', () {
      final answer = _part(_failing, '### The handlers of run');
      _says(
        answer,
        'The handlers compute the state after the body is over, so a '
        'cancellation reaches its own handler instead of a refused `emit`.',
      );
      expect(_quoted(answer), hasLength(2));
      camera(CameraController.new, (camera, hw, journal, async) {
        final job = camera.init()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.elapse(const Duration(milliseconds: 20));

        expect(journal.take(), _quoted(answer).last);
        expect(hw.log, ['open: begin', 'open: end']);

        final rescue = camera.reopen()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 40));

        expect(rescue.outcome, isA<Done<void>>());
        expect(camera.currentState, isA<Ready>());
      });
    });

    test('a job dropped before its start reaches neither handler', () {
      _says(
        _part(_failing, '### The handlers of run'),
        'A job dropped before its start reaches neither handler, so the '
        'second `init()` of the section above still ends in its one '
        '`dropped` line.',
      );
      camera(CameraController.new, (camera, hw, journal, async) {
        // Cancelled while it waits: no handler, and the camera can still be
        // opened.
        final early = camera.init()..ignoreFailure();
        early.cancel().ignore();
        async.elapse(const Duration(milliseconds: 20));
        expect(journal.take(), ['[init] dropped Cancelled(manual)']);
        expect(camera.currentState, isA<Initial>());

        opened(camera.init, hw, journal, async);
        camera.init().ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));

        expect(journal.take(), ['[init] dropped Cancelled(rules: canStart)']);
        expect(camera.currentState, const Ready());
      });
    });

    test('reopen has the same two handlers', () {
      _says(
        _part(_failing, '### The handlers of run'),
        '`reopen` has the same two handlers.',
      );
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        final cancelled = camera.reopen()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 15));
        cancelled.cancel().ignore();
        async.elapse(const Duration(milliseconds: 40));

        expect(cancelled.outcome, isA<Cancelled>());
        expect('${camera.currentState}', 'Broken(Cancelled(manual))');

        hw.failures['open'] = StateError('camera in use');
        final failed = camera.reopen()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 40));

        expect(failed.outcome, isA<Failed>());
        expect('${camera.currentState}', 'Broken(Bad state: camera in use)');
      });
    });
  });

  group('only the last zoom', () {
    const state = 'Ready(zoom: 4.0, focusPoint: null, paused: false)';

    test('without a policy every zoom reaches the hardware', () {
      final attempt = _part(_zoom, _first);
      _says(
        attempt,
        'Three calls in one turn, `setZoom(2)`, `setZoom(3)` and '
        '`setZoom(4)`, end on `$state`, and so does the version below: by '
        'the state the two cannot be told apart. The hardware can. Every '
        'request waits in the queue and reaches the lens:',
      );
      camera(QueuedZoom.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        camera
          ..setZoom(2).ignoreFailure()
          ..setZoom(3).ignoreFailure()
          ..setZoom(4).ignoreFailure();
        async.elapse(const Duration(milliseconds: 50));

        expect('${camera.currentState}', state);
        expect(hw.log, _quoted(attempt).single);
      });
    });

    test('replace keeps only the last queued zoom', () {
      final answer = _part(_zoom, '### Policy.replace');
      _says(
        answer,
        '`replace` drops the queued job with the same key before it queues '
        'the new one, so the same three calls reach the hardware once:',
      );
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        camera
          ..setZoom(2).ignoreFailure()
          ..setZoom(3).ignoreFailure()
          ..setZoom(4).ignoreFailure();
        async.elapse(const Duration(milliseconds: 50));

        expect(journal.take(), _quoted(answer).single);
        expect('${camera.currentState}', state);
        expect(hw.log, ['zoom 4.0: begin', 'zoom 4.0: end']);
      });
    });

    test('replace queues the new zoom behind what already waits', () {
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        camera.setZoom(2).ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        camera
          ..setZoom(3).ignoreFailure()
          ..setFocusPoint(const Point(0.5, 0.5)).ignoreFailure()
          ..setZoom(4).ignoreFailure();
        async.elapse(const Duration(milliseconds: 60));

        // Not in the place of the zoom it dropped: behind the focus.
        expect(hw.log, [
          'zoom 2.0: begin',
          'zoom 2.0: end',
          'focus Point(0.5, 0.5): begin',
          'focus Point(0.5, 0.5): end',
          'zoom 4.0: begin',
          'zoom 4.0: end',
        ]);
      });
    });

    test('replace lets the running zoom finish', () {
      _says(
        _part(_zoom, '### Policy.replace'),
        'The job that is already running is left to finish. When '
        '`setZoom(3)` and `setZoom(4)` arrive while the zoom to 2 is in '
        'flight, the lens still goes to 2, the request for 3 is dropped, '
        'and then it goes to 4.',
      );
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        final running = camera.setZoom(2)..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        camera
          ..setZoom(3).ignoreFailure()
          ..setZoom(4).ignoreFailure();
        async.elapse(const Duration(milliseconds: 50));

        expect(running.outcome, isA<Done<void>>());
        expect(
          journal.take(),
          contains('[setZoom: zoom: 3.0] dropped Cancelled(replaced)'),
        );
        expect(hw.log, [
          'zoom 2.0: begin',
          'zoom 2.0: end',
          'zoom 4.0: begin',
          'zoom 4.0: end',
        ]);
      });
    });

    test('a paused camera does not take the command', () {
      _says(
        _part(_zoom, '### Policy.replace'),
        '`canStart` keeps a paused camera from taking the command at all.',
      );
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);
        camera.pause().ignoreFailure();
        async.elapse(const Duration(milliseconds: 10));
        journal.take();

        camera.setZoom(2).ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));

        expect(journal.take(), [
          '[setZoom: zoom: 2.0] dropped Cancelled(rules: canStart)',
        ]);
        expect(hw.log, isEmpty);
      });
    });
  });

  group('commands that arrive during a shot', () {
    test('the shot drops what was queued during it', () {
      final section = _part(_shot);
      _says(
        section,
        'A capture takes three times as long as the other operations, and '
        'the commands asked for meanwhile wait in the queue.',
      );
      _says(
        section,
        'once the photo is taken, `queue.clear()` drops them. A zoom '
        'requested five milliseconds into the capture:',
      );
      _says(
        section,
        '`queue.clear()` leaves the running job alone, and the running job '
        'here is the shot itself.',
      );
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        final shot = camera.takePhoto()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        camera.setZoom(3).ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));
        // Still waiting: the shot has not cleared the queue yet.
        expect(journal.take(), ['[takePhoto] started']);
        async.elapse(const Duration(milliseconds: 40));

        expect(
          ['[takePhoto] started', ...journal.take()],
          _quoted(section).single,
        );
        expect(shot.outcome, isA<Done<Photo>>());
        expect(hw.log, ['capture: begin', 'capture: end']);
      });
    });

    test('without the clear the zoom runs once the shot is over', () {
      _says(
        _part(_shot),
        'Without the clear that zoom runs once the shot is over.',
      );
      camera(Variants.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        camera.takePhotoKeepingQueue().ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        camera.setZoom(3).ignoreFailure();
        async.elapse(const Duration(milliseconds: 60));

        expect(hw.log, [
          'capture: begin',
          'capture: end',
          'zoom 3.0: begin',
          'zoom 3.0: end',
        ]);
      });
    });

    test('the clear of the shot leaves a queued disposal', () {
      _says(
        _part(_shot),
        'It also leaves the jobs that are not cancellable, and this '
        'controller queues only one kind of those: a disposal.',
      );
      camera(QueuedDisposal.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        camera.takePhoto().ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        camera.setZoom(3).ignoreFailure();
        final disposal = camera.dispose()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 60));

        expect(
          journal.take(),
          contains('[setZoom: zoom: 3.0] dropped Cancelled(manual)'),
        );
        expect(disposal.outcome, isA<Done<void>>());
        expect(camera.currentState, isA<Disposed>());
      });
    });
  });

  group('disposing of the camera', () {
    test('dispose closes the hardware whatever the camera was doing', () {
      _says(
        _part(_disposing),
        '`dispose()` closes the hardware and publishes `Disposed`, whatever '
        'the camera was doing when it was called.',
      );
      // While it opens: the opening is cancelled and lands in Broken first.
      camera(CameraController.new, (camera, hw, journal, async) {
        final opening = camera.init()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        final disposal = camera.dispose()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 40));

        expect('${opening.outcome}', 'Cancelled(manual)');
        expect(disposal.outcome, isA<Done<void>>());
        expect(hw.log, [
          'open: begin',
          'open: end',
          'close: begin',
          'close: end',
        ]);
        expect(camera.currentState, isA<Disposed>());
      });
      // Never opened: nothing to close.
      camera(CameraController.new, (camera, hw, journal, async) {
        final disposal = camera.dispose()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));

        expect(disposal.outcome, isA<Done<void>>());
        expect(hw.log, isEmpty);
        expect(camera.currentState, isA<Disposed>());
      });
      // Broken by its hardware.
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);
        hw.fail(StateError('cable pulled'));
        final disposal = camera.dispose()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));

        expect(disposal.outcome, isA<Done<void>>());
        expect(hw.log, ['close: begin', 'close: end']);
        expect(camera.currentState, isA<Disposed>());
      });
    });

    test('a queued disposal waits for everything in front of it', () {
      final attempt = _part(_disposing, _first);
      _says(
        attempt,
        'Called with a zoom in flight and a shot waiting behind it, this '
        'disposal takes its place at the end of the queue:',
      );
      _says(
        attempt,
        'Everything in front of it still runs, and the camera takes a photo '
        'after it was told to shut down.',
      );
      camera(QueuedDisposal.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        camera.setZoom(2).ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        camera
          ..takePhoto().ignoreFailure()
          ..dispose().ignoreFailure();
        async.elapse(const Duration(milliseconds: 100));

        expect(journal.take(), _quoted(attempt).single);
        expect(hw.log, [
          'zoom 2.0: begin',
          'zoom 2.0: end',
          'capture: begin',
          'capture: end',
          'close: begin',
          'close: end',
        ]);
      });
    });

    test('a started disposal turns a cancel away', () {
      _says(
        _part(_disposing, _first),
        'Its `cancellable: false` is right: the job may not be cancelled '
        'once started, and neither may its child that closes the hardware, '
        'so the device is never left half closed.',
      );
      for (final create in <_Create>[
        QueuedDisposal.new,
        CameraController.new,
      ]) {
        camera(create, (camera, hw, journal, async) {
          final open = _init(camera);
          final dispose = _dispose(camera);
          opened(open, hw, journal, async);

          final job = dispose()..ignoreFailure();
          async.elapse(const Duration(milliseconds: 5));
          job.cancel().ignore();
          async.elapse(const Duration(milliseconds: 20));

          expect(job.outcome, isA<Done<void>>());
          expect(hw.log, ['close: begin', 'close: end']);
          expect(camera.currentState, isA<Disposed>());
        });
      }
    });

    test('the child that closes the hardware runs to its end', () {
      // Under a parent that takes the cancellation: the reopen is
      // cancelled while its child closes the hardware.
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        final job = camera.reopen()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.elapse(const Duration(milliseconds: 40));

        expect(journal.take(), [
          '[reopen] started',
          '> [closeCamera] started',
          '> [closeCamera] finished Done(null)',
          'state: Broken(Cancelled(manual))',
          '[reopen] finished Cancelled(manual)',
        ]);
        expect(hw.log, ['close: begin', 'close: end']);
      });
    });

    test('a queued disposal turns a cancel away', () {
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        camera.takePhoto().ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        final job = camera.dispose()..ignoreFailure();
        job.cancel().ignore();
        async.elapse(const Duration(milliseconds: 60));

        expect(job.outcome, isA<Done<void>>());
        expect(hw.log, [
          'capture: begin',
          'capture: end',
          'close: begin',
          'close: end',
        ]);
        expect(camera.currentState, isA<Disposed>());
      });
    });

    test('the second attempt clears the way', () {
      final attempt = _part(_disposing, _second);
      _says(
        attempt,
        '`queue.clear()` drops what has not started, and the shot never '
        'reaches the hardware. `current?.cancel()` asks the running zoom '
        'to stop, and the lens moves to 2 all the same',
      );
      _says(
        attempt,
        'What the cancellation saves is the rest of the body: the zoom '
        'publishes no state for a camera about to close, and the disposal '
        'starts as soon as the hardware is free.',
      );
      for (final create in <_Create>[
        ClearingDisposal.new,
        CheckingInTheBody.new,
        CameraController.new,
      ]) {
        camera(create, (camera, hw, journal, async) {
          opened(_init(camera), hw, journal, async);

          _setZoom(camera)(2).ignoreFailure();
          async.elapse(const Duration(milliseconds: 5));
          _takePhoto(camera)().ignoreFailure();
          _dispose(camera)().ignoreFailure();
          async.elapse(const Duration(milliseconds: 4));
          // The zoom is waited out before the disposal starts.
          expect(journal.lines, isNot(contains('[dispose] started')));
          expect(hw.log, ['zoom 2.0: begin']);
          async.elapse(const Duration(milliseconds: 96));

          expect(
            journal.take(),
            _quoted(attempt).first,
            reason: '${camera.runtimeType}',
          );
          expect(hw.log, [
            'zoom 2.0: begin',
            'zoom 2.0: end',
            'close: begin',
            'close: end',
          ]);
        });
      }
    });

    test('the second attempt drops a dispose after the disposal is over', () {
      final attempt = _part(_disposing, _second);
      _says(
        attempt,
        'The fault is in a call made after the disposal is over. It queues '
        'a job of its own, and `canStart` drops that job before it starts:',
      );
      _says(
        attempt,
        'The camera is disposed, and its caller is told the disposal was '
        'cancelled.',
      );
      expect(_quoted(attempt), hasLength(2));
      camera(ClearingDisposal.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);
        final first = camera.dispose()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));
        expect(first.outcome, isA<Done<void>>());
        expect(camera.currentState, isA<Disposed>());
        journal.take();

        final again = camera.dispose()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));

        expect(journal.take(), _quoted(attempt).last);
        expect('${again.outcome}', 'Cancelled(rules: canStart)');
      });
    });

    test('checked in the body, a dispose after the disposal ends Done', () {
      final answer = _part(_disposing, '### Checking in the body');
      _says(
        answer,
        'The same call now starts, finds the camera disposed and ends '
        '`Done`; the hardware log stays empty.',
      );
      for (final create in <_Create>[
        CheckingInTheBody.new,
        CameraController.new,
      ]) {
        camera(create, (camera, hw, journal, async) {
          final open = _init(camera);
          final dispose = _dispose(camera);
          opened(open, hw, journal, async);
          dispose().ignoreFailure();
          async.elapse(const Duration(milliseconds: 20));
          journal.take();
          hw.log.clear();

          final again = dispose()..ignoreFailure();
          async.elapse(const Duration(milliseconds: 20));

          expect(journal.take(), _quoted(answer).single);
          expect(again.outcome, isA<Done<void>>());
          expect(hw.log, isEmpty);
        });
      }
    });

    test('a second dispose gets the first one back', () {
      _says(
        _part(_disposing, '### Checking in the body'),
        'The clear is not forced. A disposal that is still in the queue '
        'survives it, because it is not cancellable, and `Policy.droppable` '
        'hands it to the second call: two `dispose()` calls in a row get '
        'the same job, and both callers see `Done`.',
      );
      for (final create in <_Create>[
        CheckingInTheBody.new,
        CameraController.new,
      ]) {
        camera(create, (camera, hw, journal, async) {
          final open = _init(camera);
          final dispose = _dispose(camera);
          opened(open, hw, journal, async);

          final first = dispose()..ignoreFailure();
          final second = dispose()..ignoreFailure();
          async.elapse(const Duration(milliseconds: 40));

          expect(identical(first, second), isTrue);
          expect(first.outcome, isA<Done<void>>());
          expect(hw.log, ['close: begin', 'close: end']);
        });
      }
    });

    test('a forced clear drops the earlier disposal', () {
      _says(
        _part(_disposing, '### Checking in the body'),
        '`queue.clear(force: true)` would drop that job instead, and its '
        'caller would get `Cancelled(manual)` for a camera that was '
        'disposed after all.',
      );
      camera(Variants.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        final first = camera.disposeForced()..ignoreFailure();
        final second = camera.disposeForced()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 40));

        expect(identical(first, second), isFalse);
        expect('${first.outcome}', 'Cancelled(manual)');
        expect(second.outcome, isA<Done<void>>());
        expect(camera.currentState, isA<Disposed>());
      });
    });
  });

  group('closing the controller', () {
    test('close in the same turn drops a disposal', () {
      final attempt = _part(_closing, _first);
      _says(
        attempt,
        'A job still in the queue never starts: `close()` ends it with '
        '`Cancelled(closed)`, cancellable or not, and whoever awaits it '
        'gets that outcome at once',
      );
      _says(
        attempt,
        '`dispose()` queued its job and `close()` came in the same turn, so '
        'the disposal ended in the queue. The hardware log has no `close` '
        'in it. The camera stays open, the state still says `Ready`, and '
        'the controller that could close the camera is closed itself.',
      );
      late List<String> lines;
      late List<String> hardware;
      late CameraState state;
      var over = false;
      final seen = alone((async, journal) {
        final hw = FakeCameraHardware();
        final camera = CameraController(hw);
        opened(camera.init, hw, journal, async);

        closingInTheSameTurn(camera).then((_) => over = true).ignore();
        async.flushTimers();
        lines = journal.take();
        hardware = hw.log.toList();
        state = camera.currentState;
      });

      expect(seen.zone, isEmpty);
      expect(over, isTrue);
      expect(lines, _quoted(attempt).single);
      expect(hardware, isEmpty);
      expect(state, isA<Ready>());
    });

    test('whoever awaits a job dropped by close gets the outcome at once', () {
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        final job = camera.dispose();
        Outcome<void>? awaited;
        job.done.then((outcome) => awaited = outcome).ignore();
        camera.close().ignore();
        async.flushMicrotasks();

        expect('$awaited', 'Cancelled(closed)');
        expect(job.outcome, isA<Cancelled>());
      });
    });

    test('close waits for a disposal that has started', () {
      _says(
        _part(_closing, _first),
        '`close()` goes by where a job is, not by its flag. It waits for '
        'the running job, and a job that is not cancellable runs to its '
        'end.',
      );
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        final job = camera.dispose()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        var closed = false;
        camera.close().then((_) => closed = true).ignore();
        async.flushMicrotasks();
        expect(closed, isFalse);
        async.flushTimers();

        expect(closed, isTrue);
        expect(job.outcome, isA<Done<void>>());
        expect(hw.log, ['close: begin', 'close: end']);
        expect(camera.currentState, isA<Disposed>());
      });
    });

    test('a drain runs the queued disposal', () {
      _says(
        _part(_closing, _second),
        '`SoloCloseMode.drain` runs the queue before closing, and the '
        'disposal with it: the hardware closes and the state becomes '
        '`Disposed`.',
      );
      late List<String> lines;
      late List<String> hardware;
      late CameraState state;
      final seen = alone((async, journal) {
        final hw = FakeCameraHardware();
        final camera = CameraController(hw);
        opened(camera.init, hw, journal, async);

        unawaited(closingWithADrain(camera));
        async.flushTimers();
        lines = journal.take();
        hardware = hw.log.toList();
        state = camera.currentState;
      });

      expect(seen.zone, isEmpty);
      expect(lines, [
        '[dispose] started',
        '> [closeCamera] started',
        '> [closeCamera] finished Done(null)',
        'state: Disposed()',
        '[dispose] finished Done(null)',
        'closed',
      ]);
      expect(hardware, ['close: begin', 'close: end']);
      expect(state, isA<Disposed>());
    });

    test('a drain closes the controller over a failed disposal', () {
      final attempt = _part(_closing, _second);
      _says(attempt, 'The fault shows when the hardware fails to close:');
      _says(
        attempt,
        'The disposal failed and the camera is still open, but the '
        'controller closed right after it, and a second `dispose()` comes '
        'back `Cancelled(closed)`. Nobody reads the outcome of the first '
        'one, so its failure goes to the zone as an unhandled error',
      );
      late List<String> lines;
      late List<String> hardware;
      late CameraState state;
      late String again;
      final seen = alone((async, journal) {
        final hw = FakeCameraHardware();
        final camera = CameraController(hw);
        opened(camera.init, hw, journal, async);
        hw.failures['close'] = StateError('close timed out');

        unawaited(closingWithADrain(camera));
        async.flushTimers();
        lines = journal.take();
        hardware = hw.log.toList();
        state = camera.currentState;

        hw.failures.remove('close');
        final second = camera.dispose();
        async.flushTimers();
        again = '${second.outcome}';
      });

      expect(lines, _quoted(attempt).single);
      expect(hardware, ['close: begin', 'close: failed']);
      expect(state, isA<Ready>());
      expect(again, 'Cancelled(closed)');
      expect(seen.zone, [isA<StateError>()]);
      expect('${seen.zone.single}', 'Bad state: close timed out');
    });

    test('the page runs from init to close', () {
      final answer = _part(_closing, '### Awaiting the disposal');
      _says(
        answer,
        '`close()` stands in the `Done` case: the disposal is over before '
        'it is called, and `close()` finds nothing to cancel.',
      );
      late CameraController made;
      late List<String> lines;
      var over = false;
      final seen = alone((async, journal) {
        awaitingTheDisposal().then((_) => over = true).ignore();
        made = journal.created.single as CameraController;
        async.flushTimers();
        lines = journal.take();
      });

      expect(seen.zone, isEmpty);
      expect(over, isTrue);
      expect(seen.printed, ['disposed']);
      expect(lines, [
        '[init] started',
        'state: Preparing()',
        'state: Ready(zoom: 1.0, focusPoint: null, paused: false)',
        '[init] finished Done(null)',
        '[dispose] started',
        '> [closeCamera] started',
        '> [closeCamera] finished Done(null)',
        'state: Disposed()',
        '[dispose] finished Done(null)',
        'closed',
      ]);
      // The `closed` line was taken before this test closed anything.
      expect(made.currentState, isA<Disposed>());
    });

    test('a close that fails leaves the controller open for a second try', () {
      final answer = _part(_closing, '### Awaiting the disposal');
      _says(
        answer,
        '`Failed` is the case that needs handling: a close that fails is '
        'not a disposal. `ctx.run` throws what the child threw, the body '
        'never reaches `emit(Disposed())`, and the state stays where it '
        'was. The code above leaves the controller open in that case, so a '
        'second `dispose()` can try again.',
      );
      late CameraController made;
      late bool closed;
      late CameraState state;
      late String again;
      late CameraState after;
      var over = false;
      final seen = alone((async, journal) {
        awaitingTheDisposal().then((_) => over = true).ignore();
        made = journal.created.single as CameraController;
        made.hw.failures['close'] = StateError('close timed out');
        async.flushTimers();
        closed = made.isClosed;
        state = made.currentState;

        made.hw.failures.remove('close');
        final second = made.dispose()..ignoreFailure();
        async.flushTimers();
        again = '${second.outcome}';
        after = made.currentState;
      });

      expect(seen.zone, isEmpty);
      expect(over, isTrue);
      expect(seen.printed, ['failed: Bad state: close timed out']);
      expect(closed, isFalse);
      expect(state, const Ready());
      expect(again, 'Done(null)');
      expect(after, isA<Disposed>());
    });

    test('Cancelled comes back when the controller was closed first', () {
      _says(
        _part(_closing, '### Awaiting the disposal'),
        'It does come back when `close()` gets there first, as in the first '
        'attempt, or when the controller was closed before `dispose()` was '
        'called.',
      );
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);
        camera.close().ignore();
        async.flushTimers();

        final job = camera.dispose()..ignoreFailure();
        async.flushTimers();

        expect('${job.outcome}', 'Cancelled(closed)');
      });
    });

    test('a queued disposal is taken out only by close or by force', () {
      _says(
        _part(_closing, '### Awaiting the disposal'),
        'A disposal that has started turns every cancellation down; a '
        'queued one is taken out only by `close()` or by a forced removal '
        'such as `queue.clear(force: true)`',
      );
      camera(Variants.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);
        // A shot that keeps the queue, so the disposal waits behind it.
        camera.takePhotoKeepingQueue().ignoreFailure();
        async.elapse(const Duration(milliseconds: 5));
        final disposal = camera.queueLikeADisposal()..ignoreFailure();
        expect(camera.queued, ['dispose']);

        disposal.cancel().ignore();
        expect(camera.clearQueue(), 0);
        expect(camera.removeEverything(), 0);
        camera.cancelAll().ignore();
        expect(camera.queued, ['dispose']);

        expect(camera.removeEverything(force: true), 1);
        expect('${disposal.outcome}', 'Cancelled(manual)');
      });
      for (final remove in <void Function(Variants)>[
        (camera) => camera.clearQueue(force: true),
        (camera) => camera.cancelAll(force: true).ignore(),
        (camera) => camera.close().ignore(),
      ]) {
        camera(Variants.new, (camera, hw, journal, async) {
          opened(camera.init, hw, journal, async);
          camera.takePhotoKeepingQueue().ignoreFailure();
          async.elapse(const Duration(milliseconds: 5));
          final disposal = camera.queueLikeADisposal()..ignoreFailure();

          remove(camera);

          expect(disposal.outcome, isA<Cancelled>());
        });
      }
    });
  });

  group('a failure after the disposal', () {
    test('the hardware reports on its own, and queues no job', () {
      _says(
        _part(_failure),
        'The hardware reports a failure on its own, and the controller '
        'turns the report into `Broken`.',
      );
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        hw.fail(StateError('cable pulled'));
        async.flushTimers();

        // The state changes inside the call, and nothing is queued: the
        // caller is the only one who submits work.
        expect(journal.take(), ['state: Broken(Bad state: cable pulled)']);
      });
    });

    test('a listener never taken off replaces Disposed', () {
      final attempt = _part(_failure, _first);
      _says(attempt, 'The listener is set and never taken off.');
      _says(
        attempt,
        'The disposal decided the final state, and the next report of the '
        'hardware replaced it.',
      );
      camera(listener.CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        camera.dispose().ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));
        hw.fail(StateError('cable pulled'));
        async.flushMicrotasks();

        expect(journal.take(), _quoted(attempt).single);
      });
    });

    test('after close that listener throws into the hardware', () {
      _says(
        _part(_failure, _first),
        'After `close()` the same report does not change the state: the '
        'state of a closed controller is final, so `externalSetState` '
        "throws a `StateError`, and it throws into the hardware's own "
        'callback.',
      );
      camera(listener.CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);
        camera.dispose().ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));
        camera.close().ignore();
        async.flushTimers();

        expect(
          () => hw.fail(StateError('cable pulled')),
          throwsA(isA<StateError>()),
        );
        expect(camera.currentState, isA<Disposed>());
      });
    });

    test('onClose takes the listener off a closed controller', () {
      final attempt = _part(_failure, _second);
      _says(
        attempt,
        'A report that comes after `close()` now finds no listener, and '
        'nothing throws.',
      );
      camera(listener.ClosingCameraController.new,
          (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);
        camera.dispose().ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));
        expect(hw.onError, isNotNull);
        camera.close().ignore();
        async.flushTimers();

        expect(hw.onError, isNull);
        hw.fail(StateError('cable pulled'));
        expect(camera.currentState, isA<Disposed>());
      });
    });

    test('onClose is called once, when the last job is over', () {
      _says(
        _part(_failure, _second),
        'the engine calls it once, when the last job is over and the '
        'controller is about to finish closing.',
      );
      camera(CountingClose.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        // A drain: the disposal still runs after the call of `close`.
        camera.dispose().ignoreFailure();
        camera.close(mode: SoloCloseMode.drain).ignore();
        async.elapse(const Duration(milliseconds: 5));
        expect(camera.closes, 0);
        expect(hw.onError, isNotNull);
        hw.fail(StateError('cable pulled'));
        expect(camera.currentState, isA<Broken>());
        // Called again and again: the hook is not.
        camera.close(mode: SoloCloseMode.drain).ignore();
        async.flushTimers();
        camera.close().ignore();
        async.flushTimers();

        expect(camera.closes, 1);
        expect(hw.onError, isNull);
        expect(camera.currentState, isA<Disposed>());
        // The last job was over by then: `closed` is the last line.
        expect(journal.take().last, 'closed');
      });
    });

    test('onClose leaves the report before close in place', () {
      final attempt = _part(_failure, _second);
      _says(
        attempt,
        'The report in the journal above came before `close()`, and this '
        'version prints the same journal',
      );
      camera(listener.ClosingCameraController.new,
          (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        camera.dispose().ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));
        hw.fail(StateError('cable pulled'));
        async.flushMicrotasks();

        expect(journal.take(), _quoted(_part(_failure, _first)).single);
      });
    });

    test('a detached listener leaves Disposed alone', () {
      _says(
        _part(_failure, '### Detaching the source first'),
        'The listener goes before anything else, so the disposal decides '
        'the final state alone, and a failure reported after it has nobody '
        'to tell. The camera stays `Disposed`.',
      );
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);

        camera.dispose().ignoreFailure();
        // Inside the call, before the job has started.
        expect(hw.onError, isNull);
        async.elapse(const Duration(milliseconds: 5));
        hw.fail(StateError('cable pulled'));
        async.elapse(const Duration(milliseconds: 15));
        hw.fail(StateError('cable pulled'));
        async.flushMicrotasks();

        expect(journal.take(), [
          '[dispose] started',
          '> [closeCamera] started',
          '> [closeCamera] finished Done(null)',
          'state: Disposed()',
          '[dispose] finished Done(null)',
        ]);

        camera.close().ignore();
        async.flushTimers();
        hw.fail(StateError('cable pulled'));
        expect(camera.currentState, isA<Disposed>());
      });
    });

    test('a disposal that fails leaves the listener off', () {
      _says(
        _part(_failure, '### Detaching the source first'),
        'A disposal that fails leaves the listener off as well: until a '
        'second `dispose()` succeeds, the controller does not hear its '
        'hardware.',
      );
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);
        hw.failures['close'] = StateError('close timed out');

        final job = camera.dispose()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));
        expect(job.outcome, isA<Failed>());
        journal.take();

        hw.fail(StateError('cable pulled'));

        expect(journal.take(), isEmpty);
        expect(camera.currentState, const Ready());

        hw.failures.remove('close');
        final again = camera.dispose()..ignoreFailure();
        async.elapse(const Duration(milliseconds: 20));
        expect(again.outcome, isA<Done<void>>());
        expect(camera.currentState, isA<Disposed>());
      });
    });

    test('onClose stays for a controller closed without a disposal', () {
      _says(
        _part(_failure, '### Detaching the source first'),
        '`onClose` stays in the example for a controller that is closed '
        'without a disposal.',
      );
      // Opened and closed.
      camera(CameraController.new, (camera, hw, journal, async) {
        opened(camera.init, hw, journal, async);
        camera.close().ignore();
        async.flushTimers();

        hw.fail(StateError('cable pulled'));
        expect(camera.currentState, const Ready());
      });
      // Never opened.
      camera(CameraController.new, (camera, hw, journal, async) {
        camera.close().ignore();
        async.flushTimers();

        hw.fail(StateError('cable pulled'));
        expect(camera.currentState, isA<Initial>());
      });
    });
  });

  group('running the example', () {
    test('the program disposes of the camera in the middle of a shot', () {
      _says(
        _part(_running),
        '`bin/main.dart` opens the camera, zooms, sets a focus point, '
        'starts a shot and disposes of the camera in the middle of it, '
        'printing the journal as it goes.',
      );
      final seen = alone((async, journal) {
        unawaited(program.main());
        async.flushTimers();
      });

      expect(seen.zone, isEmpty);
      expect(seen.printed, [
        '[init] started',
        'state: Preparing()',
        'state: Ready(zoom: 1.0, focusPoint: null, paused: false)',
        '[init] finished Done(null)',
        '[setZoom: zoom: 2.0] started',
        'state: Ready(zoom: 2.0, focusPoint: null, paused: false)',
        '[setZoom: zoom: 2.0] finished Done(null)',
        '[setFocusPoint: Point(0.5, 0.5)] started',
        'state: Ready(zoom: 2.0, focusPoint: Point(0.5, 0.5), paused: false)',
        '[setFocusPoint: Point(0.5, 0.5)] finished Done(null)',
        '[takePhoto] started',
        '[takePhoto] finished Cancelled(manual)',
        '[dispose] started',
        '> [closeCamera] started',
        '> [closeCamera] finished Done(null)',
        'state: Disposed()',
        '[dispose] finished Done(null)',
        'shot: Cancelled(manual)',
        'closed',
      ]);
    });

    test('the tests of the example exercise what the page leaves out', () {
      _says(
        _part(_running),
        'The example also has `reopen`, `pause`, `resume` and the focus '
        'operations, and its tests exercise each of them.',
      );
      final tests = File('test/camera_controller_test.dart').readAsStringSync();
      for (final call in [
        '.reopen()',
        '.pause()',
        '.resume()',
        '.setFocusPoint(',
        '.resetFocusPoint()',
      ]) {
        expect(tests, contains(call));
      }
    });

    test('the commands of the section name what the example has', () {
      final commands = RegExp(r'```sh\n(.*?)\n```', dotAll: true)
          .firstMatch(_part(_running))!
          .group(1)!
          .split('\n');

      expect(commands, [
        'cd example',
        'dart pub get',
        'dart run bin/main.dart',
        'dart test',
      ]);
      expect(Directory.current.path, endsWith('example'));
      expect(File('pubspec.yaml').existsSync(), isTrue);
      expect(File('bin/main.dart').existsSync(), isTrue);
      expect(Directory('test').existsSync(), isTrue);
    });
  });

  group('the neighbours', () {
    // The part of a page of `doc/` under [heading], up to the next heading.
    String under(String page, String heading) => File('../doc/$page')
        .readAsStringSync()
        .split(RegExp('^(?=#)', multiLine: true))
        .firstWhere((part) => part.split('\n').first == heading)
        .replaceAll(RegExp(r'\s+'), ' ');

    test('the cancellation page has its table of waiting methods on top', () {
      _says(
        _part(_disposing, _second),
        'the table at the top of the page [Cancellation](cancellation.md) '
        'has each waiting method.',
      );
      final top = under('cancellation.md', '# Cancellation');

      expect(top, contains('| `ctx.join(action)` | Waits for the operation'));
      expect(top, contains('| `ctx.abandonable(action)` |'));
    });

    test('the state page has the trap the catch falls into', () {
      _says(
        _part(_failing, _first),
        'on the state page, with a device behind the spinner.',
      );
      final section =
          File('../doc/state.md').readAsStringSync().split('\n## ').firstWhere(
                (part) =>
                    part.startsWith('State after failure or cancellation'),
              );

      expect(section, contains('### The first attempt'));
      expect(section, contains('spinner'));
      expect(section, contains('throws instead of writing'));
    });

    test('the cancellation page says what close does with a queued job', () {
      _says(
        _part(_closing, _first),
        'on the cancellation page describes.',
      );
      final section = File('../doc/cancellation.md')
          .readAsStringSync()
          .split('\n## ')
          .firstWhere(
            (part) => part.startsWith('Cancelling and closing a controller'),
          )
          .replaceAll(RegExp(r'\s+'), ' ');

      expect(
        section,
        contains('cancels every queued job with `Cancelled(closed)`'),
      );
    });

    test('the errors page says where a failure nobody read goes', () {
      _says(
        _part(_closing, _second),
        'on the errors page describes. The failure arrives where nothing '
        'can act on it.',
      );
      final section = File('../doc/errors.md')
          .readAsStringSync()
          .split('\n## ')
          .firstWhere(
            (part) => part.startsWith('Handled and unhandled failures'),
          )
          .replaceAll(RegExp(r'\s+'), ' ');

      expect(
        section,
        contains("A `Failed` that nobody observed goes to the job's creation "
            'zone'),
      );
      expect(section, contains('leaves reporting to the hooks'));
    });

    test('the state page stops a source in onClose', () {
      _says(
        _part(_failure, _second),
        '`onClose` is where [externalSetState](state.md#externalsetstate) '
        'on the state page stops a source',
      );
      final section = under('state.md', '### externalSetState');

      expect(section, contains('The subscription is cancelled in `onClose`'));
      expect(section, contains('void onClose() => unawaited(_link.cancel());'));
    });

    test('the pages that point here find the disposal awaited before close',
        () {
      for (final page in ['cancellation.md', 'resources.md']) {
        expect(
          File('../doc/$page').readAsStringSync(),
          contains('(camera.md#awaiting-the-disposal)'),
          reason: page,
        );
      }
      final answer = _part(_closing, '### Awaiting the disposal');
      final disposal = answer.indexOf('await camera.dispose().done');
      final close = answer.indexOf('await camera.close()');

      expect(disposal, isNot(-1));
      expect(close, greaterThan(disposal));
      // The cancellation page says of the example that its only place to
      // submit work is the caller: the listener of the hardware changes
      // the state and queues nothing.
      expect(
        File('../doc/cancellation.md')
            .readAsStringSync()
            .replaceAll(RegExp(r'\s+'), ' '),
        contains('the only place that submits work is the caller'),
      );
      expect(
        File('lib/src/camera_controller.dart').readAsStringSync(),
        contains('hw.onError = (error) => externalSetState(Broken(error));'),
      );
    });
  });

  group('the page', () {
    test('the last fragment of each method is its code in the example', () {
      _says(
        _part(_intro),
        'the last fragment of each method below is its code in '
        '`example/lib/src/camera_controller.dart`, comments aside.',
      );
      final page = File(_page).readAsStringSync();
      final source = _normalize(
        File('lib/src/camera_controller.dart').readAsStringSync(),
      );

      final last = <String, String>{};
      for (final block in RegExp(r'```dart\n(.*?)```', dotAll: true)
          .allMatches(page)
          .map((match) => match.group(1)!)) {
        final heads = _head.allMatches(block).toList();
        for (var i = 0; i < heads.length; i++) {
          final end = i + 1 < heads.length ? heads[i + 1].start : block.length;
          final head = heads[i];
          last[head.group(1) ?? head.group(2) ?? head.group(3)!] =
              block.substring(head.start, end);
        }
      }

      expect(last.keys.toSet(), {
        'CameraController',
        'init',
        'setZoom',
        'takePhoto',
        '_closeCameraJob',
        'dispose',
        'onClose',
      });
      for (final MapEntry(key: name, value: fragment) in last.entries) {
        expect(
          source,
          contains(_normalize(fragment)),
          reason: 'the last fragment of $name differs from the example',
        );
      }
    });

    test('the parts the versions stand on are the code of the example', () {
      final scratch = Directory.systemTemp.createTempSync('camera_page');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final example = _normalize(
        File('lib/src/camera_controller.dart').readAsStringSync(),
      );
      final support = File('test/support/camera_page.dart').readAsStringSync();
      final parts = support.substring(
        support.indexOf('mixin CameraParts'),
        support.indexOf('/// "A working type wide enough"'),
      );
      final methods = [
        for (final piece in parts.split(RegExp(r'\n\s*\n')))
          if (piece.trimLeft().startsWith('Job<'))
            // Up to the end of the method: the last one is followed by the
            // brace that closes the mixin.
            piece.substring(0, piece.lastIndexOf(');') + 2),
      ];

      expect(methods, hasLength(5));
      for (final method in methods) {
        expect(example, contains(_normalize(method)));
      }
    });

    test('each section with a first attempt states its task before it', () {
      final withAttempt = <String>[];
      String? section;
      String? task;
      for (final part in _parts()) {
        final lines = part.split('\n');
        if (lines.first.startsWith('## ')) {
          section = lines.first;
          task = lines.skip(1).join('\n').trim();
        } else if (lines.first == _first) {
          withAttempt.add(section!);
          expect(task, isNotEmpty, reason: section);
          expect(task, isNot(contains('```')), reason: section);
        }
      }

      expect(withAttempt, [
        _opening,
        _failing,
        _zoom,
        _disposing,
        _closing,
        _failure,
      ]);
    });

    test('the section on the shot opens with the answer', () {
      _says(
        _part(_intro),
        'The section on commands that arrive during a shot has nothing to '
        'trip over and opens with the answer.',
      );
      final section = _part(_shot);

      expect(
        section.split('\n').skip(1).join('\n').trim(),
        startsWith('```dart'),
      );
      expect(() => _part(_shot, _first), throwsStateError);
    });

    test('a second attempt follows a first one, and an answer follows it', () {
      _says(
        _part(_intro),
        'Where the version that repairs it still falls short, it stands as '
        'a second attempt. The version the example uses follows under its '
        'own heading.',
      );
      final headings = [
        for (final part in _parts()) part.split('\n').first,
      ];
      var seconds = 0;
      for (var i = 0; i < headings.length; i++) {
        if (headings[i] == _second) {
          seconds++;
          expect(headings[i - 1], _first);
          expect(headings[i + 1], startsWith('### '));
          expect(headings[i + 1], isNot(_second));
        }
      }

      expect(seconds, 3);
    });

    test('has no fence the checks do not read, but for the commands', () {
      expect(strayFences(_page), ['```sh']);
    });

    group('the code', () {
      late Directory scratch;
      late String example;
      late String states;
      const page = 'test/support/camera_page.dart';
      const attempts = 'test/support/camera_attempts.dart';
      const listeners = 'test/support/camera_attempts_listener.dart';

      setUp(() {
        scratch = Directory.systemTemp.createTempSync('camera_page');
        example = _withoutComments('lib/src/camera_controller.dart', scratch);
        states = _statesOfThePage(scratch).path;
      });
      tearDown(() => scratch.deleteSync(recursive: true));

      // Each version under its own file: an answer turned into its own
      // first attempt would still be found among all of them.
      const holders = {
        _intro: 'the states of the example',
        _first: attempts,
        _second: attempts,
        '### A working type wide enough': page,
        '### The handlers of run': 'the example',
        '### Policy.replace': 'the example',
        _shot: 'the example',
        '### Checking in the body': page,
        '### Awaiting the disposal': page,
        '### Detaching the source first': 'the example',
      };
      for (final MapEntry(key: heading, value: holder) in holders.entries) {
        test('under "$heading" it is a run of lines of $holder', () {
          final (file, also) = switch (holder) {
            'the states of the example' => (states, const <String>[]),
            'the example' => (example, const <String>[]),
            attempts => (attempts, const [listeners]),
            _ => (holder, const <String>[]),
          };
          expect(
            codeMissingFrom(_page, file, alsoIn: also, under: heading),
            isEmpty,
          );
        });
      }

      test('every piece of it is a run of lines of these files', () {
        expect(
          codeMissingFrom(
            _page,
            page,
            alsoIn: [attempts, listeners, example, states],
          ),
          isEmpty,
        );
      });

      test('every heading with code under it is held to a file', () {
        final withCode = [
          for (final part in _parts())
            if (part.contains('```dart')) part.split('\n').first,
        ];
        expect(withCode.toSet(), holders.keys.toSet());
      });
    });
  });
}

/// The first line of a method or of the constructor, at the start of a line.
final _head = RegExp(
  r'^(?:Job<\w+> (\w+)\(|(CameraController)\(this|void (onClose)\()',
  multiLine: true,
);

/// The code without comments, indentation and empty lines.
String _normalize(String code) => code
    .split('\n')
    .map((line) => line.replaceFirst(RegExp('//.*'), '').trim())
    .where((line) => line.isNotEmpty)
    .join('\n');
