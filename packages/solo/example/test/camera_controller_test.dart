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
      expect(journal.take(), [
        '[takePhoto] finished Cancelled(manual)',
        '[dispose] started',
        '> [closeCamera] started',
        '> [closeCamera] finished Done(null)',
        'state: Disposed()',
        '[dispose] finished Done(null)',
      ]);
      expect(shot.outcome, isA<Cancelled>());
      expect(hw.log, contains('capture: begin'));
      expect(
        hw.log,
        isNot(contains('capture: end')),
        reason: 'the shot is still in flight; guard stopped waiting',
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
      expect(journal.take(), [
        'state: Broken(Bad state: overheat)',
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
