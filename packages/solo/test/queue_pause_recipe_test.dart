@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/jobs_page.dart';
import 'support/jobs_stubs.dart';

/// The pause of `doc/jobs.md` that works: a gate that goes in first and
/// clears its field from its own handle.
///
/// The code is the page's own, verbatim in `support/jobs_page.dart`. Every
/// row of the page's table of cases and every paragraph under it is pinned
/// here, and most of them are promises about the queue rather than about
/// the gate: a change to the queue cannot quietly turn the recipe into a
/// lie. The two attempts the page shows before it are in
/// `jobs_rakes_test.dart`.

/// Hears every job that starts.
final class _Starts extends SoloObserver {
  final heard = <String>[];

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) => heard.add('$job');
}

void main() {
  setUp(() => stage = Stage());

  tearDown(() => Solo.observer = null);

  group('the cases', () {
    test('pause(), then three jobs: they wait, and no outcome is reached', () {
      fakeAsync((async) {
        final camera = CameraController()..pause();
        async.flushMicrotasks();
        final jobs = [camera.work('a'), camera.work('b'), camera.work('c')];
        async.elapse(const Duration(seconds: 1));

        expect(camera.isPaused, isTrue);
        expect(camera.runningKey, '_Op.pause', reason: 'the gate holds');
        expect(camera.waiting, ['a', 'b', 'c']);
        expect([for (final job in jobs) job.outcome], [null, null, null]);
        expect(stage.trace, isEmpty);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('pause() with three already queued: they wait too', () {
      fakeAsync((async) {
        final camera = CameraController();
        final running = camera.work('running');
        async.flushMicrotasks();
        final jobs = [camera.work('a'), camera.work('b'), camera.work('c')];
        camera.pause();

        // Ahead of everything but the running job.
        expect(camera.waiting, ['_Op.pause', 'a', 'b', 'c']);
        expect(camera.runningKey, 'running');

        async.elapse(const Duration(seconds: 1));
        expect('${running.outcome}', 'Done(null)', reason: 'it went on');
        expect(camera.runningKey, '_Op.pause');
        expect([for (final job in jobs) job.outcome], [null, null, null]);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('resume(): they run, in the order they were submitted', () {
      fakeAsync((async) {
        final camera = CameraController()
          ..work('queued before')
          ..pause()
          ..work('a')
          ..work('b');
        async.elapse(const Duration(seconds: 1));
        expect(stage.trace, isEmpty);

        camera.resume();
        expect(camera.isPaused, isFalse);
        async.flushTimers();
        expect(stage.trace, [
          'queued before starts',
          'queued before ends',
          'a starts',
          'a ends',
          'b starts',
          'b ends',
        ]);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('queue.clear() while the gate runs: the pause stands', () {
      fakeAsync((async) {
        final camera = CameraController()
          ..pause()
          ..work('a')
          ..work('b');
        async.flushMicrotasks();

        expect(camera.queue.clear(), 2);
        expect(camera.waiting, isEmpty);
        expect(camera.runningKey, '_Op.pause', reason: 'not a queued job');
        expect(camera.isPaused, isTrue);

        final job = camera.work('c');
        async.elapse(const Duration(seconds: 1));
        expect(job.outcome, isNull, reason: 'the new job waits again');
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('queue.clear() while the gate waits its turn: the gate goes too', () {
      fakeAsync((async) {
        final camera = CameraController()..work('running');
        async.flushMicrotasks();
        camera
          ..pause()
          ..work('a');
        expect(camera.isPaused, isTrue);

        expect(camera.queue.clear(), 2, reason: 'the gate and the job');
        expect(camera.isPaused, isFalse, reason: 'the handle cleared it');

        // And `pause()` works again: the next gate holds the queue.
        camera.pause();
        final job = camera.work('b');
        async.elapse(const Duration(seconds: 1));
        expect(camera.runningKey, '_Op.pause');
        expect(job.outcome, isNull);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('close() while paused comes back without a resume', () {
      fakeAsync((async) {
        final camera = CameraController()..pause();
        final job = camera.work('a');
        async.flushMicrotasks();
        final gate = camera.current!;

        var closed = false;
        unawaited(camera.close().then((_) => closed = true));
        // On microtasks alone: the wait of the gate ends as it is cancelled.
        async.flushMicrotasks();

        expect(closed, isTrue);
        expect('${gate.outcome}', 'Cancelled(closed)');
        expect('${job.outcome}', 'Cancelled(closed)');
        expect(camera.isPaused, isFalse);
      });
    });

    test('a draining close while paused waits for the resume', () {
      fakeAsync((async) {
        final camera = CameraController()..pause();
        final job = camera.work('a');
        async.flushMicrotasks();

        var closed = false;
        unawaited(
          camera.close(mode: SoloCloseMode.drain).then((_) => closed = true),
        );
        async.elapse(const Duration(seconds: 10));
        expect(closed, isFalse, reason: 'the gate is not cancelled');
        expect(camera.isPaused, isTrue);
        expect(job.outcome, isNull);

        // The drain runs what is queued, once the gate lets it.
        camera.resume();
        async.flushTimers();
        expect(closed, isTrue);
        expect('${job.outcome}', 'Done(null)');
      });
    });

    test('close() while the gate waits its turn clears the field as well', () {
      fakeAsync((async) {
        final camera = CameraController()..work('running');
        async.flushMicrotasks();
        camera.pause();
        camera.close().ignore();
        async.flushTimers();

        expect(camera.isFinished, isTrue);
        expect(camera.isPaused, isFalse);
      });
    });

    for (final waiting in [false, true]) {
      test(
          'cancelAll() while the gate '
          '${waiting ? 'waits its turn' : 'runs'}: the queue moves on', () {
        fakeAsync((async) {
          final camera = CameraController();
          if (waiting) {
            camera.work('running');
            async.flushMicrotasks();
          }
          camera
            ..pause()
            ..work('a');
          async.flushMicrotasks();

          camera.cancelAll().ignore();
          async.flushMicrotasks();
          expect(camera.runningKey, isNull, reason: 'the gate went too');
          expect(camera.waiting, isEmpty);
          expect(camera.isPaused, isFalse, reason: 'nobody opened it');

          // The queue moves on...
          final job = camera.work('b');
          async.flushTimers();
          expect('${job.outcome}', 'Done(null)');

          // ...and `pause()` works again.
          camera.pause();
          async.flushMicrotasks();
          expect(camera.runningKey, '_Op.pause');
          expect(camera.isPaused, isTrue);
          camera.close().ignore();
          async.flushTimers();
        });
      });
    }

    test('the state leaves Ready while paused: the pause stands', () {
      fakeAsync((async) {
        final camera = CameraController()..pause();
        final job = camera.work('in any state');
        async.flushMicrotasks();

        camera.externalSetState(const Disconnected());
        async.elapse(const Duration(seconds: 1));
        expect(camera.runningKey, '_Op.pause');
        expect(camera.isPaused, isTrue);
        expect(job.outcome, isNull);

        camera.resume();
        async.flushTimers();
        expect('${job.outcome}', 'Done(null)');
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('a gate whose turn comes outside Ready begins the pause all the same',
        () {
      fakeAsync((async) {
        final camera = CameraController()..work('running');
        async.flushMicrotasks();
        camera
          ..pause()
          ..externalSetState(const Disconnected());
        final job = camera.work('in any state');
        async.elapse(const Duration(seconds: 1));

        expect(camera.runningKey, '_Op.pause');
        expect(camera.isPaused, isTrue);
        expect(job.outcome, isNull);
        camera.close().ignore();
        async.flushTimers();
      });
    });
  });

  group('the handle of the gate', () {
    test('on a closed controller pause() is told on the spot', () {
      fakeAsync((async) {
        final camera = CameraController();
        camera.close().ignore();
        async.flushTimers();

        camera.pause();
        expect(camera.isPaused, isFalse, reason: 'cleared inside the call');
      });
    });

    test('the end of the old gate does not clear the field of a newer one', () {
      fakeAsync((async) {
        final camera = CameraController()..pause();
        async.flushMicrotasks();
        final old = camera.current!;
        camera
          ..resume()
          ..pause();
        // The old gate is on its way out and is cancelled there; the field
        // holds the newer gate by now.
        old.cancel().ignore();
        final job = camera.work('a');
        async.elapse(const Duration(seconds: 1));

        expect('${old.outcome}', 'Cancelled(manual)');
        expect(camera.runningKey, '_Op.pause', reason: 'the newer gate');
        expect(camera.isPaused, isTrue, reason: 'and the field says so');

        // So `resume()` still opens it: the queue is not left held with
        // nobody knowing.
        camera.resume();
        async.flushTimers();
        expect('${job.outcome}', 'Done(null)');
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('resume() and pause() in one turn: the new gate holds', () {
      fakeAsync((async) {
        final camera = CameraController()..pause();
        final job = camera.work('a');
        async.flushMicrotasks();
        camera
          ..resume()
          ..pause();
        async.elapse(const Duration(seconds: 1));

        expect(job.outcome, isNull);
        expect(camera.isPaused, isTrue);
        camera.resume();
        async.flushTimers();
        expect('${job.outcome}', 'Done(null)');
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('it ends with the pause: Done on a resume', () {
      fakeAsync((async) {
        final camera = CameraController()..pause();
        async.flushMicrotasks();
        final gate = camera.current!;

        async.elapse(const Duration(seconds: 1));
        expect(gate.outcome, isNull, reason: 'the pause is on');

        camera.resume();
        async.flushTimers();
        expect('${gate.outcome}', 'Done(null)');
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('it ends with the pause: Cancelled(closed) on a close', () {
      fakeAsync((async) {
        final camera = CameraController()..pause();
        async.flushMicrotasks();
        final gate = camera.current!;
        camera.close().ignore();
        async.flushTimers();

        expect('${gate.outcome}', 'Cancelled(closed)');
      });
    });
  });

  group('what the engine knows of it', () {
    test('the observer sees an ordinary job start', () {
      fakeAsync((async) {
        final starts = _Starts();
        Solo.observer = starts;
        final camera = CameraController()..pause();
        async.flushMicrotasks();

        expect(starts.heard, ['Job(_Op.pause)']);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('pending answers with the gate rather than with work', () {
      fakeAsync((async) {
        final camera = CameraController()
          ..pause()
          ..work('a');
        async.flushMicrotasks();

        expect(
          camera.pending,
          isA<SoloPendingJob>()
              .having((pending) => pending.job, 'job', same(camera.current))
              .having((pending) => '${pending.job.key}', 'key', '_Op.pause'),
        );
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('isPaused is where the controller keeps it', () {
      fakeAsync((async) {
        final camera = CameraController();
        expect(camera.isPaused, isFalse);
        camera.pause();
        expect(camera.isPaused, isTrue, reason: 'from the call itself');
        camera.resume();
        expect(camera.isPaused, isFalse);
        camera.close().ignore();
        async.flushTimers();
      });
    });
  });

  test('canStart is not a pause: the job is cancelled when its turn comes', () {
    fakeAsync((async) {
      final camera = CameraController()..work('running');
      async.flushMicrotasks();
      final jobs = [
        for (final name in ['a', 'b'])
          camera.run<Ready, void>(
            key: name,
            canStart: (state) => false,
            (ctx) async => stage.trace.add('$name runs'),
          ),
      ];

      expect([for (final job in jobs) job.outcome], [null, null]);
      expect(camera.waiting, ['a', 'b'], reason: 'queued until their turn');

      async.flushTimers();
      expect(
        [for (final job in jobs) '${job.outcome}'],
        ['Cancelled(rules: canStart)', 'Cancelled(rules: canStart)'],
      );
      expect(camera.waiting, isEmpty, reason: 'the queue emptied');
      expect(stage.trace, ['running starts', 'running ends']);
      camera.close().ignore();
      async.flushTimers();
    });
  });
}
