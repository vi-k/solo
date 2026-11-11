// `SoloLanes`: the start and keep rules across lanes. A write of one lane is
// judged by the rules of the jobs of the other, the epoch recipe of the
// design works, and a job holds its lane until its `join` ends.
//
// Every group below names the mutation that holds it, in the code of the
// lane pump and of the rules; each was seen red in a saved copy of the
// library.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

sealed class Camera {
  const Camera();
}

final class Off extends Camera {
  const Off();
}

final class Ready extends Camera {
  const Ready();
}

typedef Board = ({Camera camera, int notices});
typedef ReadyBoard = ({Ready camera, int notices});

const _ready = (camera: Ready(), notices: 0);

/// The camera on one lane, the notices on the other.
final class _Rig extends SoloLanes<Board> {
  late final SoloLane<Board> camera;
  late final SoloLane<Board> notices;

  _Rig([super.initialState = _ready]) {
    camera = lane('camera');
    notices = lane('notices');
  }
}

/// An epoch in the state, written by one lane and kept by the other.
typedef Feed = ({int epoch, int marks});

final class _Epochs extends SoloLanes<Feed> {
  late final SoloLane<Feed> account;
  late final SoloLane<Feed> likes;

  _Epochs() : super((epoch: 0, marks: 0)) {
    account = lane('account');
    likes = lane('likes');
  }

  /// The recipe of the design: the epoch is read when the job is made, not
  /// when it starts.
  SoloJob<void> like(
    Future<void> Function(SoloContext<Feed, Feed> ctx) body, {
    Object? key,
  }) {
    final epoch = currentState.epoch;
    return likes.enqueue<Feed, void>(
      key: key,
      keepWhile: (feed) => feed.epoch == epoch,
      body,
    );
  }

  void signIn() => account.enqueue<Feed, void>(
    key: 'sign in',
    (ctx) async => ctx.emit((epoch: ctx.state.epoch + 1, marks: 0)),
  );
}

Matcher _byRules() => isA<Cancelled>().having(
  (c) => c.reason,
  'reason',
  isA<RulesCancelReason>(),
);

void main() {
  // Held by: `_reevaluate` (`solo.dart`) skipping the running jobs of lanes
  // other than the writer's (`if (except != null && job.lane != except.lane)
  // continue;`): the first three tests go red. The last of the group is held
  // by `ifCancelled` losing its right at the cancellation (the revocation
  // removed in `_reevaluate` and in `_checkCorrectionState`).
  group('a write of one lane is judged by the rules of the other', () {
    test("a write of one lane cancels the other's job by W", () {
      fakeAsync((async) {
        final rig = _Rig();
        final gate = Completer<void>();
        final job = rig.notices.enqueue<ReadyBoard, void>(
          key: 'needs ready',
          (ctx) => gate.future,
        );
        async.flushMicrotasks();
        expect(job.isRunning, isTrue);

        rig.camera.enqueue<Board, void>(
          key: 'switch off',
          (ctx) async => ctx.emit((camera: const Off(), notices: 0)),
        );
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();

        expect(job.outcome, _byRules());
        rig.close();
        async.flushMicrotasks();
      });
    });

    test('a write cancels by keepWhile, past cancellable: false', () {
      fakeAsync((async) {
        final rig = _Rig();
        final gate = Completer<void>();
        final command = rig.notices.enqueue<Board, void>(
          key: 'command',
          cancellable: false,
          keepWhile: (state) => state.camera is Ready,
          (ctx) => gate.future,
        );
        async.flushMicrotasks();

        rig.camera.enqueue<Board, void>(
          key: 'switch off',
          (ctx) async => ctx.emit((camera: const Off(), notices: 0)),
        );
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();

        expect(command.outcome, _byRules());
        rig.close();
        async.flushMicrotasks();
      });
    });

    test("a job cancelled by the other lane's write loses ifCancelled", () {
      fakeAsync((async) {
        final rig = _Rig();
        final gate = Completer<void>();
        var corrected = false;
        final job = rig.notices.enqueue<ReadyBoard, void>(
          key: 'notice',
          ifCancelled: (state, cancelled) {
            corrected = true;
            return (camera: state.camera, notices: -1);
          },
          (ctx) => gate.future,
        );
        async.flushMicrotasks();

        rig.camera.enqueue<Board, void>(
          key: 'switch off',
          (ctx) async => ctx.emit((camera: const Off(), notices: 5)),
        );
        async.flushMicrotasks();
        // The camera is back in Ready before the job ends: only the
        // revocation at the first write keeps the correction away.
        rig.camera.enqueue<Board, void>(
          key: 'switch on',
          (ctx) async => ctx.emit((camera: const Ready(), notices: 5)),
        );
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();

        expect(job.outcome, _byRules());
        expect(corrected, isFalse);
        expect(rig.currentState.notices, 5);
        rig.close();
        async.flushMicrotasks();
      });
    });

    test('a write that keeps W cancels nobody', () {
      fakeAsync((async) {
        final rig = _Rig();
        final gate = Completer<void>();
        final job = rig.notices.enqueue<ReadyBoard, void>(
          key: 'notice',
          (ctx) => gate.future,
        );
        async.flushMicrotasks();

        rig.camera.enqueue<Board, void>(
          key: 'again',
          (ctx) async => ctx.emit((camera: const Ready(), notices: 3)),
        );
        async.flushMicrotasks();

        expect(job.isRunning, isTrue);
        expect(job.isCancelled, isFalse);
        gate.complete();
        async.flushMicrotasks();
        expect(job.outcome, isA<Done<void>>());
        rig.close();
        async.flushMicrotasks();
      });
    });
  });

  // Held by: `_rejectStart` (`job.dart`) not asking the keep rules again,
  // for the start; `_reevaluate` skipping the lanes of other writers, for
  // the change; `_reevaluate` skipping the parent of the emitting job
  // (`identical(job, except._parentJob)`), for the child's write.
  group('an epoch in the state', () {
    test('cancels the other lane at the change and at the start', () {
      fakeAsync((async) {
        final epochs = _Epochs();
        final gate = Completer<void>();
        var secondRan = false;
        final running = epochs.like(key: 'running', (ctx) => gate.future);
        // Queued before the change, started after it.
        final queued = epochs.like(
          key: 'queued',
          (ctx) async => secondRan = true,
        );
        async.flushMicrotasks();
        expect(running.isRunning, isTrue);
        expect(queued.isQueued, isTrue);

        epochs.signIn();
        async.flushMicrotasks();

        // Cancelled at the change, not at the next write; it holds its lane
        // until the body ends.
        expect(running.isCancelled, isTrue);
        expect(queued.isQueued, isTrue);
        gate.complete();
        async.flushMicrotasks();
        expect(running.outcome, _byRules());
        expect(queued.outcome, _byRules());
        expect(secondRan, isFalse, reason: 'cancelled at the start');

        final fresh = epochs.like(key: 'fresh', (ctx) async {});
        async.flushMicrotasks();
        expect(fresh.outcome, isA<Done<void>>());
        epochs.close();
        async.flushMicrotasks();
      });
    });

    test("a child's write of a new epoch cancels its own root", () {
      fakeAsync((async) {
        final epochs = _Epochs();
        final gate = Completer<void>();
        var reached = false;
        final epoch = epochs.currentState.epoch;
        final root = epochs.account.enqueue<Feed, void>(
          key: 'root',
          keepWhile: (feed) => feed.epoch == epoch,
          (ctx) async {
            await ctx.run(
              ctx.child<void>((child) async {
                child.emit((epoch: child.state.epoch + 1, marks: 0));
                await gate.future;
              }),
            );
            reached = true;
          },
        );
        async.flushMicrotasks();

        // Cancelled by the write itself, while the child is still running.
        expect(root.isCancelled, isTrue);
        gate.complete();
        async.flushMicrotasks();
        expect(root.outcome, _byRules());
        expect(reached, isFalse);
        expect(epochs.currentState.epoch, 1);
        epochs.close();
        async.flushMicrotasks();
      });
    });

    test('a write that leaves the epoch cancels nobody', () {
      fakeAsync((async) {
        final epochs = _Epochs();
        final gate = Completer<void>();
        final running = epochs.like(key: 'running', (ctx) => gate.future);
        async.flushMicrotasks();

        epochs.account.enqueue<Feed, void>(
          key: 'mark',
          (ctx) async => ctx.emit((epoch: ctx.state.epoch, marks: 1)),
        );
        async.flushMicrotasks();

        expect(running.isRunning, isTrue);
        expect(running.isCancelled, isFalse);
        gate.complete();
        async.flushMicrotasks();
        expect(running.outcome, isA<Done<void>>());
        epochs.close();
        async.flushMicrotasks();
      });
    });
  });

  // These two hold the recipe, not the engine: a copy taken before the wait
  // is the design's first attempt. No mutation of the lane code turns them
  // red alone; the cross-lane write they stand on is held by the first
  // group.
  group('a write that reads at the write', () {
    test("a read at the write keeps the other lane's field", () {
      fakeAsync((async) {
        final rig = _Rig((camera: const Off(), notices: 0));
        final cameraGate = Completer<void>();
        final noticeGate = Completer<void>();
        rig.camera.enqueue<Board, void>(key: 'camera', (ctx) async {
          await cameraGate.future;
          ctx.emit((camera: const Ready(), notices: ctx.state.notices));
        });
        rig.notices.enqueue<Board, void>(key: 'notices', (ctx) async {
          await noticeGate.future;
          ctx.emit((camera: ctx.state.camera, notices: ctx.state.notices + 1));
        });
        async.flushMicrotasks();

        cameraGate.complete();
        async.flushMicrotasks();
        noticeGate.complete();
        async.flushMicrotasks();

        expect(rig.currentState.camera, isA<Ready>());
        expect(rig.currentState.notices, 1);
        rig.close();
        async.flushMicrotasks();
      });
    });

    test("the first attempt, a copy before join, loses the neighbour's "
        'field', () {
      fakeAsync((async) {
        final rig = _Rig((camera: const Off(), notices: 0));
        final gate = Completer<void>();
        rig.notices.enqueue<Board, void>(key: 'notices', (ctx) async {
          final before = ctx.state;
          await ctx.join(() => gate.future);
          ctx.emit((camera: before.camera, notices: before.notices + 1));
        });
        async.flushMicrotasks();
        rig.camera.enqueue<Board, void>(
          key: 'camera',
          (ctx) async =>
              ctx.emit((camera: const Ready(), notices: ctx.state.notices)),
        );
        async.flushMicrotasks();
        expect(rig.currentState.camera, isA<Ready>());

        gate.complete();
        async.flushMicrotasks();

        // The copy brings the camera of the moment before the wait back.
        expect(rig.currentState.camera, isA<Off>());
        expect(rig.currentState.notices, 1);
        rig.close();
        async.flushMicrotasks();
      });
    });
  });

  // Held by: `_reevaluate` freeing the lane of the job it has just cancelled
  // (`core.current = null` and a pump after the cancellation): the queued
  // job starts and `close` does not wait for the join.
  group('a cancelled job holds its lane', () {
    test('the job of a lane holds the lane until its join ends', () {
      fakeAsync((async) {
        final epochs = _Epochs();
        final action = Completer<void>();
        var secondStarted = false;
        final first = epochs.like(key: 'first', (ctx) async {
          await ctx.join(() => action.future);
          ctx.emit((epoch: ctx.state.epoch, marks: 99));
        });
        async.flushMicrotasks();
        epochs.likes.enqueue<Feed, void>(
          key: 'second',
          (ctx) async => secondStarted = true,
        );

        epochs.signIn();
        async.flushMicrotasks();
        var closed = false;
        epochs.close().then((_) => closed = true);
        async.flushMicrotasks();

        expect(first.isCancelled, isTrue);
        expect(first.outcome, isNull, reason: 'the join is still in flight');
        expect(secondStarted, isFalse);
        expect(closed, isFalse, reason: 'close waits for the join');

        action.complete();
        async.flushMicrotasks();

        expect(first.outcome, _byRules());
        expect(epochs.currentState.marks, 0, reason: 'the write is lost');
        expect(secondStarted, isFalse);
        expect(closed, isTrue);
      });
    });
  });
}
