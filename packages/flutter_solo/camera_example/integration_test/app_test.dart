import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
// Deprecated from Flutter 3.47 for package:material_ui, whose releases
// since 0.0.2 need Flutter 3.44; the floor is Flutter 3.38.1.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo_camera_example/camera_app.dart';
import 'package:flutter_solo_camera_example/camera_bloc.dart';
import 'package:flutter_solo_camera_example/camera_screen.dart';
import 'package:flutter_solo_camera_example/camera_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/probe.dart';

/// The app of `doc/device-app.md` on a real camera: what the page says
/// the answers do, checked on the phone.
///
/// Each case runs `CameraApp` through its buttons, with
/// `RecordingCameraPlatform` over the phone's platform, and expects on
/// the journal of the calls and on what the app shows; the journal of the
/// run is also kept in `app-journal.txt` in the temporary folder of the
/// app, where the host reads it after the run. Every case runs twice, once
/// for each controller the switch of the home screen picks: its name ends
/// in `(solo)` or `(bloc)`, and the journal has the states of either.
///
/// The cases of the background drive the lifecycle through the binding:
/// a test on an iPhone cannot press Home, so this simulates the states
/// the phones report, and the platform underneath stays in the
/// foreground. With `--dart-define=realBackground=true` two more cases
/// leave for real: a line `ACTION home` or `ACTION home-and-back` asks
/// `integration_test/support/answer_actions.py` on the host to bring
/// another app to the front and this one back.
///
/// Run from the app's folder:
/// `flutter test integration_test/app_test.dart -d <device> --no-uninstall`;
/// `--no-uninstall` keeps the files of the run, and on an iPhone the
/// permissions, on the phone. An iPhone that Flutter sees only over Wi-Fi
/// needs `flutter run -d <device> -t integration_test/app_test.dart`,
/// which `flutter test` cannot replace there; the run prints
/// `All tests passed!` or `Some tests failed.` and stays up.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final phone = CameraPlatform.instance;
  const realBackground = bool.fromEnvironment('realBackground');
  const permissions = bool.fromEnvironment('probePermissions');
  final file = File('${Directory.systemTemp.path}/app-journal.txt');
  late ProbeJournal journal;
  late RecordingCameraPlatform platform;
  late String controller;
  late List<CameraDescription> cameras;
  var lifecycle = AppLifecycleState.resumed;

  setUpAll(() {
    if (file.existsSync()) file.deleteSync();
  });

  tearDown(() async {
    await platform.stopWatching();
    CameraPlatform.instance = phone;
  });

  /// The journal without the times: the lines the cases expect.
  List<String> trace() => [
    for (final line in journal.lines) line.replaceFirst(_time, ''),
  ];

  /// The time of the first line [text] of the journal, or of the [last]
  /// one, in milliseconds.
  int at(String text, {bool last = false}) {
    bool same(String line) => line.replaceFirst(_time, '') == text;
    final line = last
        ? journal.lines.lastWhere(same)
        : journal.lines.firstWhere(same);
    return int.parse(_time.firstMatch(line)!.group(1)!);
  }

  /// The ids of the cameras created so far, in order.
  List<int> created() => [
    for (final line in trace())
      if (line.startsWith('created #')) int.parse(line.substring(9)),
  ];

  /// Lets [time] pass on the phone, with frames while the app has them.
  ///
  /// A hidden app gets no frames, so a pump would wait for good; then the
  /// time passes without them.
  Future<void> settle(WidgetTester tester, Duration time) async {
    final end = DateTime.now().add(time);
    do {
      if (lifecycle == AppLifecycleState.resumed ||
          lifecycle == AppLifecycleState.inactive) {
        await tester.pump(const Duration(milliseconds: 50));
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    } while (DateTime.now().isBefore(end));
  }

  /// Lets time pass until [done], and fails after [timeout].
  Future<void> until(
    WidgetTester tester,
    String what,
    bool Function() done, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final end = DateTime.now().add(timeout);
    while (!done()) {
      if (DateTime.now().isAfter(end)) {
        journal.note('timeout $what');
        fail('$what: not in $timeout\n${trace().join('\n')}');
      }
      await settle(tester, const Duration(milliseconds: 50));
    }
  }

  /// The view of the camera screen, on either controller.
  final view = find.byWidgetPredicate(
    (widget) => widget is CameraView || widget is BlocCameraView,
  );

  /// The state of the controller of the camera screen on the screen.
  CameraState state(WidgetTester tester) {
    final element = tester.element(view);
    return switch (element.widget) {
      CameraView(:final session) => session.currentState,
      _ => element.read<CameraBloc>().state,
    };
  }

  bool shown(String key) => find.byKey(Key(key)).evaluate().isNotEmpty;

  bool recording(WidgetTester tester) =>
      view.evaluate().isNotEmpty &&
      switch (state(tester)) {
        Ready(:final recording) => recording,
        _ => false,
      };

  /// Taps the button of [key] and pumps one frame.
  Future<void> tap(WidgetTester tester, String key) async {
    journal.note('tap $key');
    await tester.tap(find.byKey(Key(key)).last);
    await tester.pump();
  }

  /// Taps the button of [key] without a frame: the tap lands before the
  /// platform has answered a call that is under way.
  Future<void> press(WidgetTester tester, String key) async {
    journal.note('tap $key');
    await tester.tap(find.byKey(Key(key)).last);
  }

  /// Turns the event loop, without a frame, until the journal has [line]:
  /// a call has reached the platform, and the next tap lands while it
  /// runs.
  Future<void> reach(String line) async {
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (!trace().contains(line)) {
      if (DateTime.now().isAfter(end)) fail('$line: not reached');
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Starts a case: the app on the screen, the lifecycle in the journal,
  /// and the controller of the case picked on the switch.
  Future<void> start(WidgetTester tester) async {
    final listener = AppLifecycleListener(
      onStateChange: (state) {
        lifecycle = state;
        journal.note('lifecycle ${state.name}');
      },
    );
    addTearDown(listener.dispose);
    await tester.pumpWidget(const CameraApp());
    await tap(tester, 'controller-$controller');
    await settle(tester, const Duration(milliseconds: 300));
  }

  /// Opens the camera screen and waits for its buttons.
  Future<void> openCamera(WidgetTester tester) async {
    await tap(tester, 'open-camera');
    await until(tester, 'shutter', () => shown('shutter'));
    expect(
      find.byType(controller == 'bloc' ? BlocCameraView : CameraView),
      findsOneWidget,
      reason: 'the camera screen runs on another controller',
    );
  }

  /// The file the home screen shows, whether it is on top or under the
  /// camera screen.
  File? lastShot() {
    final images = find
        .byKey(const Key('last-shot'), skipOffstage: false)
        .evaluate();
    if (images.isEmpty) return null;
    final image = (images.single.widget as Image).image as FileImage;
    return image.file;
  }

  /// Expects the home screen to show [file], or a file, not empty.
  void expectShot({File? not}) {
    final shot = lastShot();
    expect(shot, isNotNull, reason: 'the home screen shows no file');
    expect(shot!.path, isNot(not?.path));
    final size = shot.lengthSync();
    journal.note('home shows ${shot.path} $size bytes');
    expect(size, greaterThan(0));
  }

  /// The videos written since [since], each with its size.
  ///
  /// The Android side of the plugin writes its files to `cache`, beside
  /// `code_cache`, the temporary folder of the app; elsewhere the video
  /// the home screen shows stands for them.
  List<String> videosSince(DateTime since) {
    final cache = Directory('${Directory.systemTemp.parent.path}/cache');
    final files = cache.existsSync()
        ? cache.listSync().whereType<File>()
        : [?lastShot()];
    return [
      for (final file in files)
        if (file.path.endsWith('.mp4') &&
            file.lastModifiedSync().isAfter(since))
          '${file.path} ${file.lengthSync()} bytes',
    ];
  }

  /// Goes back to the home screen and waits for the camera to be
  /// released.
  Future<void> goBack(WidgetTester tester) async {
    journal.note('back');
    await tester.pageBack();
    await tester.pump();
    final last = created().last;
    await until(
      tester,
      'release of #$last',
      () => view.evaluate().isEmpty && trace().contains('dispose #$last end'),
    );
    await settle(tester, const Duration(milliseconds: 300));
  }

  /// Waits for the host to take the app to the background and back.
  Future<void> leaveForReal(WidgetTester tester, String action) async {
    journal.note('ACTION $action');
    // A return at once can pass `paused` between two looks, so the
    // journal is read rather than the state of the moment.
    Iterable<String> after(String line) =>
        trace().skipWhile((l) => l != line).skip(1);
    await until(
      tester,
      'paused',
      () => after('ACTION $action').contains('lifecycle paused'),
      timeout: const Duration(seconds: 30),
    );
    await until(
      tester,
      'resumed',
      () => after(
        'ACTION $action',
      ).skipWhile((l) => l != 'lifecycle paused').contains('lifecycle resumed'),
      timeout: const Duration(seconds: 30),
    );
  }

  /// Registers the case [name] once for each controller of the switch.
  ///
  /// A case of [permission] runs only with
  /// `--dart-define=probePermissions=true`, and the others only without
  /// it: the host takes the permissions away for that run. Its create may
  /// throw the denial. [skip] skips either kind.
  void phoneTest(
    String name,
    Future<void> Function(WidgetTester tester) body, {
    bool skip = false,
    bool permission = false,
  }) {
    final skipped = skip || (permission ? !permissions : permissions);
    for (final picked in const ['solo', 'bloc']) {
      testWidgets('$name ($picked)', (tester) async {
        controller = picked;
        journal = ProbeJournal(file: file);
        journal.note('test $name ($picked)');
        platform = RecordingCameraPlatform(phone, journal);
        CameraPlatform.instance = platform;
        Solo.observer = SessionNotes(journal);
        Bloc.observer = BlocNotes(journal);
        cameras = await availableCameras();
        journal.note(
          'cameras ${cameras.map((c) => '${c.name} ${c.lensDirection.name}')}',
        );
        await start(tester);
        await body(tester);
        expect(
          trace().where(
            (line) =>
                line.contains(' threw ') &&
                !(permission && line.startsWith('create ')),
          ),
          isEmpty,
          reason: 'a call of the platform threw',
        );
      }, skip: skipped);
    }
  }

  group('rapid taps', () {
    phoneTest('flash taps apply in order, and the last one wins', (
      tester,
    ) async {
      await openCamera(tester);
      final id = created().single;
      expect((state(tester) as Ready).flash, FlashMode.auto);
      // The platform answers the flash in a few milliseconds, sooner than
      // a frame: the three taps go in before its first answer.
      await press(tester, 'flash');
      await press(tester, 'flash');
      await press(tester, 'flash');
      await until(
        tester,
        'three flashes',
        () => trace().contains('flash #$id auto end'),
      );
      await settle(tester, const Duration(milliseconds: 300));

      // An iPhone 13 mini answers in 1 to 12 ms, after the three taps. A
      // Galaxy A55 answers in 1 to 3 ms, before the next tap of the test
      // lands, so there the case checks the order alone, as the first
      // attempt would pass it too.
      journal.note(
        'flash taps ${at('tap flash', last: true) - at('tap flash')} ms, '
        'always end ${at('flash #$id always end') - at('tap flash')} ms',
      );
      if (!Platform.isAndroid) {
        expect(
          trace(),
          containsAllInOrder([
            'tap flash',
            'tap flash',
            'tap flash',
            'flash #$id always end',
          ]),
        );
      }
      expect(
        trace(),
        containsAllInOrder([
          'flash #$id always start',
          'flash #$id always end',
          'flash #$id off start',
          'flash #$id off end',
          'flash #$id auto start',
          'flash #$id auto end',
        ]),
      );
      final ready = state(tester) as Ready;
      expect(ready.flash, FlashMode.auto);
      expect(ready.camera.value.flashMode, FlashMode.auto);
      expect(find.byIcon(Icons.flash_auto), findsOneWidget);
      await goBack(tester);
    });

    phoneTest('a shot during a shot is dropped', (tester) async {
      await openCamera(tester);
      final id = created().single;
      await press(tester, 'shutter');
      await reach('capture #$id start');
      await press(tester, 'shutter');
      await until(
        tester,
        'the shot',
        () => trace().contains('capture #$id end'),
      );
      await settle(tester, const Duration(seconds: 1));

      expect(
        trace(),
        containsAllInOrder([
          'capture #$id start',
          'tap shutter',
          'capture #$id end',
        ]),
      );
      expect(trace().where((line) => line.startsWith('capture ')), [
        'capture #$id start',
        'capture #$id end',
      ]);
      await goBack(tester);
      expectShot();
    });

    phoneTest('a switch during a shot waits for the shot', (tester) async {
      await openCamera(tester);
      final first = created().single;
      final next = cameras[1 % cameras.length].lensDirection.name;
      await press(tester, 'shutter');
      await reach('capture #$first start');
      await press(tester, 'switch');
      await until(tester, 'the next camera', () => created().length == 2);
      final second = created().last;
      await until(
        tester,
        'the next camera open',
        () => trace().contains('initialize #$second end') && shown('shutter'),
      );

      expect(
        trace(),
        containsAllInOrder([
          'capture #$first start',
          'tap switch',
          'capture #$first end',
          'dispose #$first start',
          'dispose #$first end',
          'create $next start',
          'initialize #$second end',
        ]),
      );
      journal.note(
        'switch tapped ${at('tap switch') - at('capture #$first start')} ms '
        'into the shot of '
        '${at('capture #$first end') - at('capture #$first start')} ms',
      );
      expectShot();
      await goBack(tester);
    });
  });

  group('rapid taps of the torch', () {
    /// The lines of the calls of the flash and the torch on camera [id].
    List<String> flashes(int id) => [
      for (final line in trace())
        if (line.startsWith('flash #$id ')) line,
    ];

    bool lit(WidgetTester tester) => (state(tester) as Ready).torch;

    phoneTest('off and on while the torch lights: one call', (tester) async {
      await openCamera(tester);
      final id = created().single;
      expect(shown('torch'), isTrue, reason: 'the first camera has no torch');
      expect(lit(tester), isFalse);
      await press(tester, 'torch');
      await reach('flash #$id torch start');
      await press(tester, 'torch');
      await press(tester, 'torch');
      await until(
        tester,
        'the torch',
        () => trace().contains('flash #$id torch end'),
      );
      await settle(tester, const Duration(milliseconds: 500));

      expect(
        trace(),
        containsAllInOrder([
          'flash #$id torch start',
          'tap torch',
          'tap torch',
          'flash #$id torch end',
        ]),
      );
      expect(flashes(id), ['flash #$id torch start', 'flash #$id torch end']);
      expect(lit(tester), isTrue);
      expect(find.byIcon(Icons.flashlight_on), findsOneWidget);
      journal.note(
        'torch lit in '
        '${at('flash #$id torch end') - at('flash #$id torch start')} ms',
      );
      await tap(tester, 'torch');
      await until(tester, 'the torch out', () => !lit(tester));
      await goBack(tester);
    });

    phoneTest('on and off during a shot: no call', (tester) async {
      await openCamera(tester);
      final id = created().single;
      expect(shown('torch'), isTrue, reason: 'the first camera has no torch');
      await press(tester, 'shutter');
      await reach('capture #$id start');
      await press(tester, 'torch');
      await press(tester, 'torch');
      await until(
        tester,
        'the shot',
        () => trace().contains('capture #$id end'),
      );
      await settle(tester, const Duration(seconds: 1));

      expect(
        trace(),
        containsAllInOrder([
          'capture #$id start',
          'tap torch',
          'tap torch',
          'capture #$id end',
        ]),
      );
      expect(flashes(id), isEmpty);
      expect(lit(tester), isFalse);
      expect(find.byIcon(Icons.flashlight_off), findsOneWidget);
      await goBack(tester);
      expectShot();
    });
  });

  group('a switch during a recording', () {
    phoneTest('a switch while the recording starts waits for the start', (
      tester,
    ) async {
      await openCamera(tester);
      final id = created().single;
      final next = cameras[1 % cameras.length].lensDirection.name;
      await press(tester, 'record');
      await reach('record #$id start');
      await press(tester, 'switch');
      await until(
        tester,
        'the switch',
        () => trace().contains('switch $next end'),
      );
      expect(recording(tester), isTrue);
      await settle(tester, const Duration(seconds: 2));
      await tap(tester, 'record');
      await until(
        tester,
        'the stop',
        () => trace().contains('stop #$id end') && !recording(tester),
      );

      expect(
        trace(),
        containsAllInOrder([
          'record #$id start',
          'tap switch',
          'record #$id end',
          'state Ready recording true',
          'switch $next start',
          'switch $next end',
          'stop #$id start',
          'stop #$id end',
          'state Ready recording false',
        ]),
      );
      expect(created(), [id], reason: 'the switch opened a camera');
      expect(trace(), isNot(contains('dispose #$id start')));
      journal.note(
        'record start ${at('record #$id end') - at('record #$id start')} ms',
      );
      await goBack(tester);
      expectShot();
    });

    phoneTest('a stop during a switch waits for the switch', (tester) async {
      await openCamera(tester);
      final id = created().single;
      final next = cameras[1 % cameras.length].lensDirection.name;
      await tap(tester, 'record');
      await until(tester, 'the recording', () => recording(tester));
      await settle(tester, const Duration(milliseconds: 1500));
      await press(tester, 'switch');
      await reach('switch $next start');
      await press(tester, 'record');
      await until(
        tester,
        'the stop',
        () => trace().contains('stop #$id end') && !recording(tester),
      );

      expect(
        trace(),
        containsAllInOrder([
          'record #$id end',
          'switch $next start',
          'tap record',
          'switch $next end',
          'stop #$id start',
          'stop #$id end',
        ]),
      );
      expect(created(), [id], reason: 'the switch opened a camera');
      journal.note(
        'record start ${at('record #$id end') - at('record #$id start')} ms',
      );
      await goBack(tester);
      expectShot();
    });
  });

  group('leaving the screen', () {
    phoneTest('the shot reaches home, and the next screen waits', (
      tester,
    ) async {
      await openCamera(tester);
      final first = created().single;
      await press(tester, 'shutter');
      await reach('capture #$first start');
      journal.note('back');
      await tester.pageBack();
      // The home screen takes taps once the pop has started, a frame or
      // two after the tap of back; one frame at a time, the tap comes as
      // soon as it can.
      final home = find.byKey(const Key('open-camera')).hitTestable();
      for (var frame = 0; home.evaluate().isEmpty; frame++) {
        if (frame == 60) fail('the home screen takes no taps');
        await tester.pump();
      }
      await tap(tester, 'open-camera');
      await until(tester, 'the next camera', () => created().length == 2);
      final second = created().last;
      await until(tester, 'the next shutter', () => shown('shutter'));

      // The page says: back during the shot, the next screen opened
      // before the release has ended, and its camera after the release.
      expect(
        trace(),
        containsAllInOrder([
          'capture #$first start',
          'back',
          'capture #$first end',
        ]),
      );
      expect(
        trace(),
        containsAllInOrder([
          'back',
          'tap open-camera',
          'dispose #$first end',
          'state Opening',
        ]),
      );
      expect(
        trace(),
        containsAllInOrder([
          'capture #$first start',
          'capture #$first end',
          'dispose #$first start',
          'dispose #$first end',
          'state Closed',
          'state Opening',
          'create back start',
          'initialize #$second end',
          'state Ready recording false',
        ]),
      );
      final opened = at('tap open-camera', last: true);
      journal.note(
        'release ${at('dispose #$first start') - at('capture #$first end')} '
        'ms after the shot; open tapped '
        '${at('dispose #$first end') - opened} ms before the release ended',
      );
      expectShot();
      final firstShot = lastShot()!;

      // The camera of the second screen works: a shot on it comes.
      await tap(tester, 'shutter');
      await until(
        tester,
        'the shot on the next camera',
        () => trace().contains('capture #$second end'),
      );
      await goBack(tester);
      expectShot(not: firstShot);
    });

    phoneTest('back during a recording stops it, and the video reaches home', (
      tester,
    ) async {
      await openCamera(tester);
      final first = created().single;
      final since = DateTime.now();
      await tap(tester, 'record');
      await until(tester, 'the recording', () => recording(tester));
      await settle(tester, const Duration(milliseconds: 1500));
      await goBack(tester);
      // What the platform left on disk is written down before the
      // expectations: released under a recording, the Galaxy's camera went
      // on recording sound into the file.
      final released = videosSince(since);
      await settle(tester, const Duration(seconds: 5));
      final later = videosSince(since);
      journal.note('videos on disk $released, 5 s later $later');

      expect(
        trace(),
        containsAllInOrder([
          'back',
          'stop #$first start',
          'stop #$first end',
          'dispose #$first start',
          'dispose #$first end',
        ]),
      );
      journal.note(
        'stop on leaving '
        '${at('stop #$first end') - at('stop #$first start')} ms',
      );
      final video = lastShot();
      expect(video, isNotNull, reason: 'the recording did not reach home');
      expect(video!.path, endsWith('.mp4'));
      expect(later, released, reason: 'a file grows after the release');
    });
  });

  group('going to the background', () {
    /// What leaving and coming back give on both phones.
    const away = [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];
    const back = [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ];

    /// Records, leaves through [leave] and comes back, and expects what
    /// the page says: the recording reaches home, the camera is released
    /// while away and opens again after the release.
    Future<void> recordAndLeave(
      WidgetTester tester,
      Future<void> Function(int id) leave,
    ) async {
      await openCamera(tester);
      final first = created().single;
      await tap(tester, 'record');
      await until(tester, 'the recording', () => recording(tester));
      await settle(tester, const Duration(milliseconds: 1500));
      await leave(first);
      await until(tester, 'the camera again', () => created().length == 2);
      final second = created().last;
      await until(tester, 'the shutter again', () => shown('shutter'));

      expect(
        trace(),
        containsAllInOrder([
          'record #$first end',
          'state Ready recording true',
          'lifecycle hidden',
          'stop #$first start',
          'stop #$first end',
          'state Closed',
          'dispose #$first start',
          'dispose #$first end',
          'state Opening',
          'create back start',
          'initialize #$second end',
          'state Ready recording false',
        ]),
      );
      journal.note(
        'record start '
        '${at('record #$first end') - at('record #$first start')} ms',
      );
      await goBack(tester);
      expectShot();
    }

    // The lifecycle is simulated: the binding reports the states the
    // phones gave for Home and back, while the app stays in front.
    phoneTest('back after the release (simulated lifecycle)', (tester) {
      return recordAndLeave(tester, (id) async {
        away.forEach(binding.handleAppLifecycleStateChanged);
        await until(
          tester,
          'the release',
          () => trace().contains('dispose #$id end'),
        );
        await settle(tester, const Duration(seconds: 1));
        back.forEach(binding.handleAppLifecycleStateChanged);
      });
    });

    phoneTest('back at once (simulated lifecycle)', (tester) {
      return recordAndLeave(tester, (id) async {
        [...away, ...back].forEach(binding.handleAppLifecycleStateChanged);
      });
    });

    phoneTest(
      'home and back after seconds (real)',
      (tester) => recordAndLeave(tester, (_) => leaveForReal(tester, 'home')),
      skip: !realBackground,
    );

    phoneTest(
      'home and back at once (real)',
      (tester) =>
          recordAndLeave(tester, (_) => leaveForReal(tester, 'home-and-back')),
      skip: !realBackground,
    );
  });

  group('the flash after a switch', () {
    // The pictures before and after the switches are named in the journal;
    // the host reads the flash they were taken with from their EXIF.
    phoneTest('a switch there and back keeps the mode of the button', (
      tester,
    ) async {
      await openCamera(tester);
      await tap(tester, 'flash');
      final first = created().single;
      await until(
        tester,
        'the flash',
        () => trace().contains('flash #$first always end'),
      );
      await tap(tester, 'shutter');
      await until(
        tester,
        'the shot with the flash',
        () => trace().contains('capture #$first end'),
      );
      await settle(tester, const Duration(milliseconds: 300));
      journal.note('picture before the switch ${lastShot()!.path}');
      for (var i = 1; i <= cameras.length; i++) {
        await tap(tester, 'switch');
        await until(
          tester,
          'switch $i',
          () => created().length == i + 1 && shown('shutter'),
        );
        final id = created().last;
        await until(
          tester,
          'the flash of camera #$id',
          () => trace().contains('flash #$id always end'),
        );
        expect(
          trace(),
          containsAllInOrder(['initialize #$id end', 'flash #$id always end']),
        );
        await settle(tester, const Duration(seconds: 1));
      }
      final last = created().last;
      final ready = state(tester) as Ready;
      expect(ready.camera.description.name, cameras.first.name);
      expect(ready.flash, FlashMode.always);
      expect(ready.camera.value.flashMode, FlashMode.always);
      expect(find.byIcon(Icons.flash_on), findsOneWidget);
      await tap(tester, 'shutter');
      await until(
        tester,
        'the shot after the switches',
        () => trace().contains('capture #$last end'),
      );
      await settle(tester, const Duration(milliseconds: 300));
      journal.note('picture after the switches ${lastShot()!.path}');
      await goBack(tester);
    });
  });

  group('the torch across a switch', () {
    // The lamp itself cannot be seen from the test: the host reads it from
    // the log of the phone, where CameraX on a Galaxy A55 writes every
    // request of the torch. The torch is lit on the first camera alone: the
    // second back camera of a Galaxy A55 has no flash unit.
    phoneTest('a lit torch around the cameras, and lit again at the end', (
      tester,
    ) async {
      await openCamera(tester);
      Ready ready() => state(tester) as Ready;
      Future<void> light() async {
        await tap(tester, 'torch');
        await until(tester, 'the torch', () => ready().torch);
        await settle(tester, const Duration(milliseconds: 500));
      }

      await light();
      for (var i = 1; i <= cameras.length; i++) {
        final before = created().last;
        final wasLit = ready().torch;
        await tap(tester, 'switch');
        await until(
          tester,
          'switch $i',
          () => created().length == i + 1 && shown('shutter'),
        );
        final id = created().last;
        final next = cameras[i % cameras.length];
        final lit = wasLit && hasTorch(next);
        await until(
          tester,
          'the flash of camera #$id',
          () => trace().contains(
            'flash #$id ${lit ? 'torch' : ready().flash.name} end',
          ),
        );
        await settle(tester, const Duration(milliseconds: 500));
        expect(ready().camera.description.name, next.name);
        if (wasLit) {
          // Put out to the mode of the button while the camera is open.
          expect(
            trace(),
            containsAllInOrder([
              'tap switch',
              'flash #$before ${ready().flash.name} end',
              'dispose #$before start',
            ]),
          );
        }
        expect(ready().torch, lit);
        expect(shown('torch'), hasTorch(next));
        journal.note(
          'camera #$id ${next.lensDirection.name} torch ${ready().torch}',
        );
      }
      // Back on the first camera, the torch lights again: a flag of the
      // plugin left up would skip the call.
      final last = created().last;
      await light();
      expect(
        trace(),
        containsAllInOrder([
          'flash #$last torch start',
          'flash #$last torch end',
        ]),
      );
      await tap(tester, 'torch');
      await until(tester, 'the torch out', () => !ready().torch);
      await goBack(tester);
    });
  });

  group('losing the camera', () {
    // The phone's camera app comes to the front and takes the camera, and
    // this app comes back after a few seconds. A Galaxy A55 reports that
    // as an error of the camera; an iPhone 13 mini sends the app to the
    // background and reports none, so the cases run on Android.
    final away = !realBackground || !Platform.isAndroid;

    /// Waits for the camera app to take camera [id] and expects what the
    /// page says: the error, `Broken` at once, the camera let go, and
    /// Retry on the screen once the app is back.
    Future<void> lose(WidgetTester tester, int id) async {
      await leaveForReal(tester, 'other-camera');
      await until(tester, 'retry', () => shown('retry'));
      final errors = trace().where((l) => l.startsWith('event error #$id '));
      expect(errors, isNotEmpty, reason: 'no error of camera #$id');
      expect(
        trace(),
        containsAllInOrder([
          'ACTION other-camera',
          errors.first,
          'state Broken',
          'dispose #$id start',
          'dispose #$id end',
        ]),
      );
      expect(state(tester), isA<Broken>());
    }

    /// Taps Retry and expects the camera open again and a shot on it.
    Future<void> retry(WidgetTester tester) async {
      final before = created().length;
      await tap(tester, 'retry');
      await until(
        tester,
        'the camera again',
        () => created().length == before + 1 && shown('shutter'),
      );
      final id = created().last;
      expect(
        trace(),
        containsAllInOrder([
          'tap retry',
          'state Opening',
          'create back start',
          'initialize #$id end',
          'state Ready recording false',
        ]),
      );
      await tap(tester, 'shutter');
      await until(
        tester,
        'the shot on the camera again',
        () => trace().contains('capture #$id end'),
      );
    }

    phoneTest('another app takes the camera, and Retry opens it (real)', (
      tester,
    ) async {
      await openCamera(tester);
      // A switch first: the journal follows the errors of every camera the
      // case has created, and shows which of them one error reaches.
      await tap(tester, 'switch');
      await until(
        tester,
        'the next camera',
        () => created().length == 2 && shown('shutter'),
      );
      await settle(tester, const Duration(milliseconds: 500));
      await lose(tester, created().last);
      journal.note(
        'errors ${trace().where((l) => l.startsWith('event error #')).toList()}',
      );
      await retry(tester);
      await goBack(tester);
      expectShot();
    }, skip: away);

    phoneTest('another app takes the camera during a recording (real)', (
      tester,
    ) async {
      await openCamera(tester);
      final first = created().single;
      await tap(tester, 'record');
      await until(tester, 'the recording', () => recording(tester));
      await settle(tester, const Duration(milliseconds: 1500));
      await lose(tester, first);
      // The recording stops on the lost camera before the release, and the
      // video reaches the home screen.
      expect(
        trace(),
        containsAllInOrder([
          'state Broken',
          'stop #$first start',
          'stop #$first end',
          'dispose #$first start',
        ]),
      );
      journal.note(
        'stop of the lost camera '
        '${at('stop #$first end') - at('stop #$first start')} ms',
      );
      final video = lastShot();
      expect(video, isNotNull, reason: 'the recording did not reach home');
      expect(video!.path, endsWith('.mp4'));
      // Released without a stop, the camera went on recording sound into
      // the file; stopped, the file stays as it is.
      final size = video.lengthSync();
      await settle(tester, const Duration(seconds: 5));
      journal.note(
        'video ${video.path} $size bytes, ${video.lengthSync()} bytes 5 s '
        'later',
      );
      expect(video.lengthSync(), size, reason: 'the file grows');
      await retry(tester);
      await goBack(tester);
      expectShot(not: video);
    }, skip: away);
  });

  group('a denied permission', () {
    // The host takes the permissions of the camera and the microphone away
    // before the run, answers `ACTION deny` by denying each dialog, and
    // `ACTION forget-denials` by letting the next request show the dialog
    // again; on a Galaxy A55 the second denial is for good. On an iPhone
    // the first one is, and the host answers neither action there, so the
    // case runs on Android.
    phoneTest(
      'denied, denied for good, and Retry asks no more (real)',
      (tester) async {
        journal.note('ACTION forget-denials');
        await settle(tester, const Duration(seconds: 3));
        int denials() => trace().where((l) => l == 'state Denied').length;
        for (var round = 1; round <= 3; round++) {
          // The third opening shows no dialog, and there is nothing to deny.
          if (round < 3) journal.note('ACTION deny');
          await tap(tester, round == 1 ? 'open-camera' : 'retry');
          await until(
            tester,
            'denial $round',
            () => denials() == round && shown('retry'),
            timeout: const Duration(seconds: 40),
          );
          final asked = at(
            round == 1 ? 'tap open-camera' : 'tap retry',
            last: true,
          );
          final took = at('state Denied', last: true) - asked;
          // A request that shows no dialog still passes through the screen of
          // the permissions, so `inactive` comes either way. A dialog waits
          // for the host, which takes seconds to find the button; a denial
          // without one comes in about 200 ms.
          final dialog = took > 1000;
          journal.note(
            'denial $round ${(state(tester) as Denied).code} dialog $dialog '
            'in $took ms',
          );
          expect((state(tester) as Denied).code, 'CameraAccessDenied');
          expect(find.text('Allow the app to use the camera.'), findsOneWidget);
          expect(dialog, round < 3, reason: 'the dialog of round $round');
          expect(created(), isEmpty);
        }
        journal.note('back');
        await tester.pageBack();
        await until(
          tester,
          'the screen closed',
          () =>
              view.evaluate().isEmpty &&
              trace().skipWhile((l) => l != 'back').contains('state Closed'),
        );
      },
      permission: true,
      skip: !Platform.isAndroid,
    );
  });

  group('measures', () {
    // Not a claim of the page: how long a recording takes to start, for
    // the report of the phones.
    phoneTest('the start of five recordings', (tester) async {
      await openCamera(tester);
      final id = created().single;
      for (var i = 0; i < 5; i++) {
        await tap(tester, 'record');
        await until(tester, 'recording $i', () => recording(tester));
        await settle(tester, const Duration(seconds: 1));
        await tap(tester, 'record');
        await until(tester, 'stop $i', () => !recording(tester));
        await settle(tester, const Duration(milliseconds: 500));
      }
      final starts = [
        for (final line in journal.lines)
          if (line.endsWith('record #$id start') ||
              line.endsWith('record #$id end'))
            int.parse(_time.firstMatch(line)!.group(1)!),
      ];
      final durations = [
        for (var i = 0; i + 1 < starts.length; i += 2)
          starts[i + 1] - starts[i],
      ];
      journal.note('record starts $durations ms');
      await goBack(tester);
      expectShot();
    });
  });
}

/// The time at the start of a line of the journal.
final _time = RegExp(r'^\+(\d+) ms ');
