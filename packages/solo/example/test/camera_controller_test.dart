@Timeout(Duration(seconds: 5))
library;

import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:solo_example/solo_example.dart';
import 'package:test/test.dart';

import 'support/journal.dart';

void runCamera(
  void Function(
    CameraController camera,
    FakeCameraHardware hw,
    JournalObserver journal,
    FakeAsync async,
  ) body,
) {
  fakeAsync((async) {
    final journal = JournalObserver();
    SoloBase.observer = journal;
    final hw = FakeCameraHardware();
    final camera = CameraController(hw);
    try {
      body(camera, hw, journal, async);
    } finally {
      camera.close();
      async.flushTimers();
      SoloBase.observer = null;
    }
  });
}

void main() {
  test('zoom, focus, shutter, and then dispose in the middle of the shot', () {
    runCamera((camera, hw, journal, async) {
      camera.init();
      async.elapse(const Duration(milliseconds: 10));
      expect(journal.take(), [
        '[init] started',
        'state: Preparing()',
        'state: Ready(zoom: 1.0, focusPoint: null, paused: false)',
        '[init] finished Done(null)',
      ]);

      camera
        ..setZoom(2)
        ..setFocusPoint(const Point(0.5, 0.5));
      final shot = camera.takePhoto();
      async.elapse(const Duration(milliseconds: 35));
      expect(journal.take(), [
        '[setZoom: zoom: 2.0] started',
        'state: Ready(zoom: 2.0, focusPoint: null, paused: false)',
        '[setZoom: zoom: 2.0] finished Done(null)',
        '[setFocusPoint: Point(0.5, 0.5)] started',
        'state: Ready(zoom: 2.0, focusPoint: Point(0.5, 0.5), paused: false)',
        '[setFocusPoint: Point(0.5, 0.5)] finished Done(null)',
        '[takePhoto] started',
      ]);

      camera.dispose();
      async.elapse(const Duration(milliseconds: 10));
      expect(
        journal.take(),
        isEmpty,
        reason: 'the shot is not abandoned: join waits for the capture',
      );

      async.elapse(const Duration(milliseconds: 20));
      expect(journal.take(), [
        '[takePhoto] finished Cancelled(manual)',
        '[dispose] started',
        '> [closeCamera] started',
        '> [closeCamera] finished Done(null)',
        'state: Disposed()',
        '[dispose] finished Done(null)',
      ]);
      expect(shot.outcome, isA<Cancelled>());
      expect(
        hw.log,
        contains('capture: end'),
        reason: 'the camera finished the shot before the job gave up',
      );
    });
  });

  test('a hardware failure breaks the camera and reopen recovers it', () {
    runCamera((camera, hw, journal, async) {
      camera.init();
      async.elapse(const Duration(milliseconds: 10));
      camera.setZoom(3);
      async.elapse(const Duration(milliseconds: 5));
      journal.take();

      hw.fail(StateError('overheat'));
      async.flushMicrotasks();
      expect(
        journal.take(),
        ['state: Broken(Bad state: overheat)'],
        reason: 'join is still waiting for the zoom command to come back',
      );

      async.elapse(const Duration(milliseconds: 5));
      expect(journal.take(), [
        '[setZoom: zoom: 3.0] finished Cancelled(rules: is not Ready)',
      ]);

      camera.reopen();
      async.elapse(const Duration(milliseconds: 30));
      expect(journal.take(), [
        '[reopen] started',
        '> [closeCamera] started',
        '> [closeCamera] finished Done(null)',
        'state: Preparing()',
        'state: Ready(zoom: 1.0, focusPoint: null, paused: false)',
        '[reopen] finished Done(null)',
      ]);
    });
  });

  test('a paused camera drops a shot before it starts', () {
    runCamera((camera, hw, journal, async) {
      camera.init();
      async.elapse(const Duration(milliseconds: 10));
      camera.pause();
      final shot = camera.takePhoto();
      async.flushMicrotasks();
      expect((shot.outcome! as Cancelled).description, 'canStart');
      camera.resume();
      async.flushMicrotasks();
      expect(camera.state, const Ready(), reason: 'resume cleared paused');
    });
  });

  test('a failure while reopening leaves the camera broken', () {
    runCamera((camera, hw, journal, async) {
      camera.init();
      async.elapse(const Duration(milliseconds: 10));
      journal.take();

      hw.failures['open'] = StateError('no device');
      // `ignore`: nobody waits for this job, and its failure is already
      // told through the state and the observer.
      final reopen = camera.reopen()..ignore();
      async.elapse(const Duration(milliseconds: 30));
      expect(journal.take(), [
        '[reopen] started',
        '> [closeCamera] started',
        '> [closeCamera] finished Done(null)',
        'state: Preparing()',
        'state: Broken(Bad state: no device)',
        '[reopen] error Bad state: no device',
        '[reopen] finished Failed(Bad state: no device)',
      ]);
      expect(reopen.outcome, isA<Failed>());
      expect(hw.log, contains('open: failed'));
    });
  });

  test('resetFocusPoint restores automatic focus', () {
    runCamera((camera, hw, journal, async) {
      camera
        ..init()
        ..setFocusPoint(const Point(0.5, 0.5));
      async.elapse(const Duration(milliseconds: 20));
      expect(camera.state, const Ready(focusPoint: Point(0.5, 0.5)));
      journal.take();

      camera.resetFocusPoint();
      async.elapse(const Duration(milliseconds: 10));
      expect(journal.take(), [
        '[resetFocusPoint] started',
        'state: Ready(zoom: 1.0, focusPoint: null, paused: false)',
        '[resetFocusPoint] finished Done(null)',
      ]);
      expect(camera.state, const Ready(), reason: 'copyWith cannot clear it');
      expect(hw.log, contains('focus null: begin'));
    });
  });

  test('a focus request replaces the queued focus jobs of both kinds', () {
    runCamera((camera, hw, journal, async) {
      camera.init();
      async.elapse(const Duration(milliseconds: 10));
      journal.take();

      // The zoom holds the controller; the three focus requests queue up
      // behind it, and each one drops the focus job left by the previous.
      camera
        ..setZoom(2)
        ..setFocusPoint(const Point(0.1, 0.1))
        ..resetFocusPoint()
        ..setFocusPoint(const Point(0.9, 0.9));
      async.elapse(const Duration(milliseconds: 20));
      expect(journal.take(), [
        '[setFocusPoint: Point(0.1, 0.1)] dropped Cancelled(manual)',
        '[resetFocusPoint] dropped Cancelled(manual)',
        '[setZoom: zoom: 2.0] started',
        'state: Ready(zoom: 2.0, focusPoint: null, paused: false)',
        '[setZoom: zoom: 2.0] finished Done(null)',
        '[setFocusPoint: Point(0.9, 0.9)] started',
        'state: Ready(zoom: 2.0, focusPoint: Point(0.9, 0.9), paused: false)',
        '[setFocusPoint: Point(0.9, 0.9)] finished Done(null)',
      ]);
      expect(
        hw.log.where((line) => line.startsWith('focus')),
        ['focus Point(0.9, 0.9): begin', 'focus Point(0.9, 0.9): end'],
        reason: 'only the surviving request reached the hardware',
      );
    });
  });

  test('a shot returns the photo through value', () {
    runCamera((camera, hw, journal, async) {
      camera.init();
      async.elapse(const Duration(milliseconds: 10));
      Photo? photo;
      camera.takePhoto().value.then((p) => photo = p);
      async.elapse(const Duration(milliseconds: 30));
      expect(photo, const Photo(1));
      expect(journal.lines, contains('[takePhoto] log captured Photo#1'));
    });
  });
}
