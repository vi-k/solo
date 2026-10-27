@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/state_camera_stubs.dart' as camera;
import 'support/state_notice_first_attempts.dart' as first;
import 'support/state_notice_page.dart' as page;
import 'support/state_notice_second_attempts.dart' as second;

/// The recipe "A notice the screen accepts" of `doc/state.md`.
///
/// The code of the section stands verbatim in
/// `test/support/state_notice_*.dart`: the first attempt and the second
/// each in a file with states of their own, the answer in a third. The
/// tests below run that code and pin what the prose and the table of the
/// section say about it. A photo takes the device 100 milliseconds, and the
/// recording runs until the device ends its frames.

String _ended(Job<Object?> job) => switch (job.outcome) {
      final Cancelled cancelled => '$cancelled, started: ${cancelled.started}',
      final outcome => '$outcome',
    };

const _ms = Duration(milliseconds: 1);

void main() {
  setUp(() => camera.stage = camera.Stage());

  group('The first attempt', () {
    test('the notice turns down a recording and the next shot', () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = first.Camera(device)..shoot();
        final record = cam.record();
        final next = cam.shoot();
        async.elapse(_ms * 200);

        expect(cam.currentState, isA<first.Saved>());
        expect((cam.currentState as first.Saved).photo, 1);
        for (final job in [record, next]) {
          expect(_ended(job), 'Cancelled(rules: is not Ready), started: false');
          expect((job.outcome! as Cancelled).reason, isA<RulesCancelReason>());
        }
        expect(
          camera.stage.trace,
          ['photo 1 begins', 'photo 1 stored'],
          reason: 'the commands are lost rather than kept waiting',
        );

        cam.accept();
        async.elapse(_ms * 200);
        expect(camera.stage.trace, hasLength(2));
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('accept brings the camera back without its zoom', () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = first.Camera(device)..zoomTo(3);
        async.flushMicrotasks();
        expect((cam.currentState as first.Ready).zoom, 3);

        cam.shoot();
        async.elapse(_ms * 200);
        cam.accept();
        async.flushMicrotasks();
        expect((cam.currentState as first.Ready).zoom, 1);
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('written and taken back at once, the notice lasts one change', () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = first.Camera(device);
        final heard = <String>[];
        cam.addListener(() => heard.add('${cam.currentState.runtimeType}'));
        cam.shootAndPass();
        final record = cam.record();
        async.elapse(_ms * 200);

        expect(heard, ['Saved', 'Ready'], reason: 'the listener hears it');
        expect(
          cam.currentState,
          isA<first.Ready>(),
          reason: 'what is read later is Ready',
        );
        expect(record.isFinished, isFalse, reason: 'the camera is not held');
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });
  });

  group('The second attempt', () {
    int? notice(second.Camera cam) => (cam.currentState as second.Ready).notice;

    test('the acceptance waits for the recording to end', () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = second.Camera(device)..shoot();
        final record = cam.record();
        async.elapse(_ms * 1000);
        expect(notice(cam), 1);

        cam.accept();
        async.elapse(_ms * 1000);
        expect(notice(cam), 1, reason: 'the recording runs');
        expect(record.isFinished, isFalse);

        device.endFrames();
        async.flushMicrotasks();
        expect(record.isFinished, isTrue);
        expect(notice(cam), isNull);
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('first: true gets ahead of the waiting jobs, not the running one', () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = second.Camera(device)
          ..shoot()
          ..record();
        async.elapse(_ms * 1000);

        final zoom = cam.zoomTo(3);
        cam.acceptFirst();
        async.elapse(_ms * 1000);
        expect(notice(cam), 1);

        device.endFrames();
        async.flushMicrotasks();
        expect(notice(cam), isNull);
        expect(zoom.isFinished, isFalse, reason: 'the zoom waits behind it');
        async.elapse(_ms * 100);
        expect(_ended(zoom), 'Done(null)');
        expect(notice(cam), isNull);
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('externalSetState clears the field at once', () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = second.Camera(device)
          ..shoot()
          ..record();
        async.elapse(_ms * 1000);

        cam.acceptAtOnce();
        expect(notice(cam), isNull);
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('a Disconnected written over the field wipes the notice', () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = second.Camera(device)..shoot();
        async.elapse(_ms * 200);
        expect(notice(cam), 1);

        cam
          ..reflect(const second.Disconnected())
          ..reflect(const second.Ready());
        expect(notice(cam), isNull);
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('a copy read before a wait brings a closed notice back', () {
      fakeAsync((async) {
        final device = camera.Device();
        final cam = second.Camera(device)..shoot();
        final zoom = cam.zoomTo(3);
        async.elapse(_ms * 120);
        expect(notice(cam), 1);

        cam.acceptAtOnce();
        expect(notice(cam), isNull);
        async.elapse(_ms * 100);
        expect(zoom.isFinished, isTrue);
        expect(notice(cam), 1);
        cam.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });
  });

  group('A board of its own', () {
    test('a shot, then a recording: both run, the notice is on the board', () {
      fakeAsync((async) {
        final device = camera.Device();
        final board = page.Notices();
        final cam = page.Camera(device, board)..shoot();
        final record = cam.record();
        async.elapse(_ms * 200);

        expect(board.currentState.notice?.photo, 1);
        device.frame(1);
        async.flushMicrotasks();
        expect(camera.stage.trace.last, 'store 1 ends');
        expect(record.isFinished, isFalse);
        cam.close().ignore();
        board.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('accept during the recording empties the board a microtask later', () {
      fakeAsync((async) {
        final device = camera.Device();
        final board = page.Notices();
        final cam = page.Camera(device, board)..shoot();
        final record = cam.record();
        async.elapse(_ms * 1000);

        final shown = board.currentState.notice!;
        final screens = [0, 0];
        board
          ..addListener(() => screens[0]++)
          ..addListener(() => screens[1]++)
          ..accept(shown);
        expect(board.currentState.notice, same(shown));
        page.Notice? afterOne = shown;
        scheduleMicrotask(() => afterOne = board.currentState.notice);
        async.flushMicrotasks();
        expect(afterOne, isNull, reason: 'one microtask is enough');
        expect(screens, [1, 1], reason: 'both screens hear it');
        expect(record.isFinished, isFalse);
        cam.close().ignore();
        board.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('a notice posted while the one before is accepted stays', () {
      fakeAsync((async) {
        final board = page.Notices();
        final seven = page.Notice(7);
        board.post(seven);
        async.flushMicrotasks();

        final eight = page.Notice(8);
        board
          ..post(eight)
          ..accept(seven);
        async.flushMicrotasks();
        expect(board.currentState.notice, same(eight));

        // Without an address the acceptance wipes what nobody saw.
        board
          ..post(page.Notice(9))
          ..acceptAny();
        async.flushMicrotasks();
        expect(board.currentState.notice, isNull);
        board.close().ignore();
        async.flushTimers();
      });
    });

    test('two shots, nobody closes: the second notice replaces the first', () {
      fakeAsync((async) {
        final device = camera.Device();
        final board = page.Notices();
        final cam = page.Camera(device, board)
          ..shoot()
          ..shoot();
        async.elapse(_ms * 300);
        expect(board.currentState.notice?.photo, 2);
        cam.close().ignore();
        board.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('a cancelled shot posts nothing, though the photo is stored', () {
      fakeAsync((async) {
        final device = camera.Device();
        final board = page.Notices();
        final cam = page.Camera(device, board);
        final shot = cam.shoot();
        async.elapse(_ms * 50);
        shot.cancel().ignore();
        async.elapse(_ms * 10);
        expect(shot.isFinished, isFalse, reason: 'join waits for the photo');
        async.elapse(_ms * 90);

        expect(_ended(shot), startsWith('Cancelled('));
        expect(camera.stage.trace, ['photo 1 begins', 'photo 1 stored']);
        expect(board.currentState.notice, isNull);
        cam.close().ignore();
        board.close().ignore();
        device.dispose();
        async.flushTimers();
      });
    });

    test('the board closed before a draining camera loses the notice', () {
      fakeAsync((async) {
        final device = camera.Device();
        final board = page.Notices();
        final cam = page.Camera(device, board);
        final shot = cam.shoot();
        async.elapse(_ms * 50);
        board.close().ignore();
        cam.close(mode: SoloCloseMode.drain).ignore();
        async.flushTimers();

        expect(_ended(shot), 'Done(null)');
        expect(board.currentState.notice, isNull);
        device.dispose();
      });
    });

    test('the board closed with the camera, not after it, loses the notice',
        () {
      fakeAsync((async) {
        final device = camera.Device();
        final board = page.Notices();
        final cam = page.Camera(device, board);
        final shot = cam.shoot();
        async.elapse(_ms * 50);
        cam.close(mode: SoloCloseMode.drain).ignore();
        board.close().ignore();
        async.flushTimers();

        expect(_ended(shot), 'Done(null)');
        expect(board.currentState.notice, isNull);
        device.dispose();
      });
    });

    test('a closed board turns down post and accept, and keeps its notice', () {
      fakeAsync((async) {
        final board = page.Notices();
        final seven = page.Notice(7);
        board.post(seven);
        async.flushMicrotasks();
        board.close().ignore();
        async.flushTimers();

        final post = board.post(page.Notice(8));
        final accept = board.accept(seven);
        async.flushMicrotasks();
        expect(_ended(post), 'Cancelled(closed), started: false');
        expect(_ended(accept), 'Cancelled(closed), started: false');
        expect(board.currentState.notice, same(seven));
      });
    });

    test('the camera closed first leaves the notice on the board', () {
      fakeAsync((async) {
        final device = camera.Device();
        final board = page.Notices();
        final cam = page.Camera(device, board);
        final shot = cam.shoot();
        async.elapse(_ms * 50);
        cam
            .close(mode: SoloCloseMode.drain)
            .then((_) => board.close())
            .ignore();
        async.flushTimers();

        expect(_ended(shot), 'Done(null)');
        expect(board.isFinished, isTrue);
        expect(board.currentState.notice?.photo, 1);
        device.dispose();
      });
    });
  });
}
