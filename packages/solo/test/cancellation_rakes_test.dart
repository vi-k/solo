@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

/// The first attempts of `doc/cancellation.md`, and what each one costs.
///
/// The page opens four of its sections with the version the vocabulary of
/// the API leads to, and states what that version does instead of what it
/// was meant to do. Nothing else guards those statements: the page has no
/// bench, so an outcome quoted there rots silently. Every order and every
/// outcome the page names about a first attempt is pinned here, next to
/// the version the page then shows.

/// A device whose every call runs until the test ends it.
///
/// The trace is the device's side of the story: which calls started,
/// which ran to their end, and which a token stopped.
final class Device {
  /// Whether a token passed to [start] can stop the call.
  final bool hearsTokens;
  final trace = <String>[];
  final _running = <String, Completer<void>>{};

  Device({this.hearsTokens = true});

  Future<void> start(String call, [CancelToken? token]) {
    trace.add('$call start');
    final done = _running[call] = Completer<void>();
    if (hearsTokens) {
      token?.onCancel = () => _finish(call, 'stopped');
    }
    return done.future;
  }

  /// Ends [call] the way the device would on its own.
  Future<void> end(String call) async {
    _finish(call, 'end');
    await pump();
  }

  /// Fails [call] with [error].
  Future<void> fail(String call, Object error) async {
    final done = _running.remove(call)!;
    trace.add('$call failed');
    done.completeError(error);
    await pump();
  }

  bool isRunning(String call) => _running.containsKey(call);

  void _finish(String call, String how) {
    final done = _running.remove(call);
    if (done == null) {
      return;
    }
    trace.add('$call $how');
    done.complete();
  }
}

/// The player API's own cancellation, the way the page's player takes it.
final class CancelToken {
  void Function()? onCancel;

  void cancel() => onCancel?.call();
}

// --- Stopping the underlying operation ------------------------------------

final class Player extends Solo<int> {
  final Device device;

  Player(this.device) : super(0);

  /// The first attempt: the waiting method that ends at once.
  Job<void> seekByWait(int position) => run<int, void>(
        key: 'seek',
        policy: Policy.restart,
        (ctx) async {
          await ctx.wait(() => device.start('seek $position'));
          ctx.emit(position);
        },
      );

  /// The second attempt: the waiting method that waits the call out.
  Job<void> seekByJoin(int position) => run<int, void>(
        key: 'seek',
        policy: Policy.restart,
        (ctx) async {
          await ctx.join(() => device.start('seek $position'));
          ctx.emit(position);
        },
      );

  /// The page's version: the cancellation reaches the call.
  Job<void> seekWithToken(int position) => run<int, void>(
        key: 'seek',
        policy: Policy.restart,
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          await ctx.join(() => device.start('seek $position', token));
          ctx.emit(position);
        },
      );
}

// --- Protecting a step or a whole job -------------------------------------

final class Till extends Solo<String> {
  final Device device;

  Till(this.device) : super('ready');

  /// The first attempt: each call waited out on its own.
  ///
  /// The mark between the calls is the test's alone: the second join would
  /// refuse the job as well, and only the mark tells which of the two threw.
  Job<void> commitByJoins() => run<String, void>((ctx) async {
        await ctx.join(() => device.start('payment'));
        device.trace.add('between');
        ctx.emit('paid');
        await ctx.join(() => device.start('journal'));
      });

  /// Plain awaits around the same emit.
  Job<void> commitByAwaits() => run<String, void>((ctx) async {
        await device.start('payment');
        ctx.emit('paid');
        await device.start('journal');
      });

  /// The second attempt: one join around the whole step.
  Job<void> commitInOneJoin() => run<String, void>((ctx) async {
        await ctx.join(() async {
          await device.start('payment');
          ctx.emit('paid');
          await device.start('journal');
        });
      });

  /// The page's version.
  Job<void> commitInSection() => run<String, void>((ctx) async {
        ctx.onCancel(() => device.trace.add('onCancel'));
        await ctx.uncancellable(() async {
          await device.start('payment');
          ctx.emit('paid');
          await device.start('journal');
        });
      });

  /// A section, then ordinary code, then a checkpoint, each marked.
  Job<String> commitThenCheck() => run<String, String>((ctx) async {
        final receipt = await ctx.uncancellable(() async {
          await device.start('payment');
          return 'receipt';
        });
        device.trace.add('after the section: $receipt');
        ctx.check();
        device.trace.add('after the check');
        return receipt;
      });
}

// --- Ordinary await and context lifetime ----------------------------------

final class Uploader extends Solo<String> {
  final Device device;
  final errors = <Object>[];

  Uploader(this.device) : super('ready');

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      errors.add(error);

  /// The first attempt: each wait is the one the other place needed.
  Job<void> uploadInverted(int chunks) => run<String, void>((ctx) async {
        ctx.onDispose(() async {
          await ctx.join(() => device.start('flush'));
        });
        for (var chunk = 1; chunk <= chunks; chunk++) {
          await device.start('write $chunk');
        }
      });

  /// The page's version.
  Job<void> upload(int chunks) => run<String, void>((ctx) async {
        ctx.onDispose(() async {
          await device.start('flush');
        });
        for (var chunk = 1; chunk <= chunks; chunk++) {
          await ctx.join(() => device.start('write $chunk'));
        }
      });

  /// A plain await, then a waiting method with nothing between them.
  Job<void> writeAfterAPlainAwait() => run<String, void>((ctx) async {
        await device.start('warm up');
        await ctx.join(() => device.start('write'));
      });
}

// --- Cancelling and closing a controller ----------------------------------

final class Outbox extends Solo<String> {
  final Device device;

  Outbox(this.device) : super('open');

  Job<void> send(int batch) =>
      run<String, void>((ctx) => ctx.join(() => device.start('send $batch')));
}

final class Session extends Solo<String> {
  final Device device;

  Session(this.device) : super('signed in');

  /// The first attempt: the job closes its own controller.
  Job<void> logoutFromTheJob() => run<String, void>((ctx) async {
        await ctx.join(() => device.start('logout'));
        await close();
      });

  /// The same, clearing the controller instead of closing it.
  Job<void> logoutCancellingAll() => run<String, void>((ctx) async {
        await ctx.join(() => device.start('logout'));
        await cancelAll();
      });

  /// The same, with the closing moved into the job's cleanup.
  Job<void> logoutClosingInCleanup() => run<String, void>((ctx) async {
        ctx.onDispose(close);
        await ctx.join(() => device.start('logout'));
      });

  /// The page's version: the job first, the closing after it.
  Future<void> logout() async {
    await run<String, void>((ctx) => ctx.join(() => device.start('logout')))
        .done;
    await close();
  }

  /// A probe: the job queued, the closing draining the queue behind it.
  Future<void> logoutByDraining() async {
    run<String, void>((ctx) => ctx.join(() => device.start('logout')));
    await close(mode: SoloCloseMode.drain);
  }

  /// A probe: work queued before the logout.
  Job<void> sync() =>
      run<String, void>((ctx) => ctx.join(() => device.start('sync')));
}

void main() {
  group('a seek that the next one replaces', () {
    test('by wait, every seek runs on the device at once', () async {
      final device = Device();
      final player = Player(device);
      final first = player.seekByWait(1);
      await pump();
      player.seekByWait(2);
      await pump();
      final last = player.seekByWait(3);
      await pump();

      expect(
        device.trace,
        ['seek 1 start', 'seek 2 start', 'seek 3 start'],
        reason: 'the wait ends at the cancellation and the call goes on',
      );
      expect(
        first.outcome,
        isA<Cancelled>(),
        reason: 'the job is over while its seek still runs',
      );

      // The device may finish them in any order; here the last seek
      // comes back first.
      await device.end('seek 3');
      await device.end('seek 2');
      await device.end('seek 1');
      expect(last.outcome, isA<Done<void>>());
      expect(
        player.currentState,
        3,
        reason: 'only the last job reaches emit, whatever the device did',
      );
    });

    test('by join, the seek dragged past runs to its end first', () async {
      final device = Device();
      final player = Player(device);
      final first = player.seekByJoin(1);
      await pump();
      final second = player.seekByJoin(2);
      await pump();
      final last = player.seekByJoin(3);
      await pump();

      expect(device.trace, ['seek 1 start']);
      expect(
        device.isRunning('seek 1'),
        isTrue,
        reason: 'nothing tells the device the seek is obsolete',
      );
      expect(
        second.outcome,
        isA<Cancelled>().having((c) => c.started, 'started', isFalse),
        reason: 'the policy took the queued one out',
      );

      await device.end('seek 1');
      expect(
        device.trace,
        ['seek 1 start', 'seek 1 end', 'seek 3 start'],
        reason: 'the last seek starts only when the first is over',
      );
      expect(
        first.outcome,
        isA<Cancelled>(),
        reason: 'and the one that ran to its end is cancelled all the same',
      );

      await device.end('seek 3');
      expect(last.outcome, isA<Done<void>>());
      expect(player.currentState, 3);
    });

    test('with a token, each seek stops before the next one starts', () async {
      final device = Device();
      final player = Player(device);
      final first = player.seekWithToken(1);
      await pump();
      player.seekWithToken(2);
      await pump();
      final last = player.seekWithToken(3);
      await pump();

      expect(device.trace, [
        'seek 1 start',
        'seek 1 stopped',
        'seek 2 start',
        'seek 2 stopped',
        'seek 3 start',
      ]);
      expect(first.outcome, isA<Cancelled>());

      await device.end('seek 3');
      expect(last.outcome, isA<Done<void>>());
      expect(player.currentState, 3);
    });

    test('a token the device ignores leaves the second attempt', () async {
      final device = Device(hearsTokens: false);
      final player = Player(device);
      final first = player.seekWithToken(1);
      await pump();
      player.seekWithToken(2);
      await pump();
      final last = player.seekWithToken(3);
      await pump();

      expect(
        device.trace,
        ['seek 1 start'],
        reason: 'the token reached nothing',
      );
      await device.end('seek 1');
      expect(
        device.trace,
        ['seek 1 start', 'seek 1 end', 'seek 3 start'],
        reason: 'the same order as the join without a token',
      );
      expect(first.outcome, isA<Cancelled>());

      await device.end('seek 3');
      expect(last.outcome, isA<Done<void>>());
    });
  });

  group('a payment and its journal entry', () {
    test('two joins take the payment and never write the entry', () async {
      final device = Device();
      final till = Till(device);
      final job = till.commitByJoins();
      await pump();
      unawaited(job.cancel());
      await pump();

      await device.end('payment');
      expect(
        device.trace,
        ['payment start', 'payment end'],
        reason: 'the first join throws after the payment it waited for',
      );
      expect(till.currentState, 'ready', reason: 'no receipt either');
      expect(job.outcome, isA<Cancelled>());
    });

    test('an emit between plain awaits throws and loses the entry', () async {
      final device = Device();
      final till = Till(device);
      final job = till.commitByAwaits();
      await pump();
      unawaited(job.cancel());
      await pump();

      await device.end('payment');
      expect(device.trace, ['payment start', 'payment end']);
      expect(till.currentState, 'ready', reason: 'the emit did not write');
      expect(job.outcome, isA<Cancelled>());
    });

    test('one join around the step: the emit inside throws, no entry',
        () async {
      final device = Device();
      final till = Till(device);
      final job = till.commitInOneJoin();
      await pump();
      unawaited(job.cancel());
      await pump();

      await device.end('payment');
      expect(
        device.trace,
        ['payment start', 'payment end'],
        reason: 'the job is marked at once, and the step runs on marked',
      );
      expect(till.currentState, 'ready', reason: 'the emit did not write');
      expect(job.outcome, isA<Cancelled>());
    });

    test('a section writes the entry, and an emit inside goes through',
        () async {
      final device = Device();
      final till = Till(device);
      final job = till.commitInSection();
      await pump();
      unawaited(job.cancel());
      await pump();
      expect(
        device.trace,
        ['payment start'],
        reason: 'the request is held: no callback yet',
      );

      await device.end('payment');
      expect(till.currentState, 'paid');
      await device.end('journal');
      expect(
        device.trace,
        [
          'payment start',
          'payment end',
          'journal start',
          'journal end',
          'onCancel',
        ],
        reason: 'the held request lands when the section closes',
      );
      expect(job.outcome, isA<Cancelled>());
    });
  });

  group('a join whose call fails', () {
    test('throws the error of its call after a cancellation, not Cancelled',
        () async {
      final device = Device();
      final uploader = Uploader(device);
      Object? seen;
      final job = uploader.run<String, void>((ctx) async {
        try {
          await ctx.join(() => device.start('write'));
        } on Object catch (error) {
          seen = error;
          rethrow;
        }
      });
      await pump();
      unawaited(job.cancel());
      await pump();

      await device.fail('write', StateError('the device said no'));
      expect(seen, isA<StateError>(), reason: 'the failure is not hidden');
      expect(job.outcome, isA<Cancelled>(), reason: 'the outcome still is');
    });
  });

  group('the end of a section', () {
    test('returns the result, and the next checkpoint throws', () async {
      final device = Device();
      final till = Till(device);
      final job = till.commitThenCheck();
      await pump();
      unawaited(job.cancel());
      await pump();

      await device.end('payment');
      expect(
        device.trace,
        ['payment start', 'payment end', 'after the section: receipt'],
        reason: 'the section hands back its value, and the code after it runs',
      );
      expect(job.outcome, isA<Cancelled>(), reason: 'the check threw');
    });
  });

  group('an upload and its flush', () {
    test('the first attempt writes every chunk and never flushes', () async {
      final device = Device();
      final uploader = Uploader(device);
      final job = uploader.uploadInverted(4);
      await pump();
      await device.end('write 1');

      var closed = false;
      unawaited(uploader.close().then((_) => closed = true));
      await pump();
      await device.end('write 2');
      await device.end('write 3');
      expect(closed, isFalse, reason: 'close waits for every chunk left');
      await device.end('write 4');

      expect(device.trace, [
        'write 1 start',
        'write 1 end',
        'write 2 start',
        'write 2 end',
        'write 3 start',
        'write 3 end',
        'write 4 start',
        'write 4 end',
      ]);
      expect(closed, isTrue);
      expect(job.outcome, isA<Cancelled>());
      expect(
        uploader.errors,
        [
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('disposing, cannot join'),
          ),
        ],
        reason: 'the join in the cleanup throws, and the flush never starts',
      );
    });

    test('a join in cleanup throws on a job that ended Done too', () async {
      final device = Device();
      final uploader = Uploader(device);
      final job = uploader.uploadInverted(1);
      await pump();
      await device.end('write 1');

      expect(job.outcome, isA<Done<void>>());
      expect(device.trace, ['write 1 start', 'write 1 end']);
      expect(uploader.errors, [isA<StateError>()]);
    });

    test('the page version stops after the chunk in flight and flushes',
        () async {
      final device = Device();
      final uploader = Uploader(device);
      final job = uploader.upload(4);
      await pump();
      await device.end('write 1');

      var closed = false;
      unawaited(uploader.close().then((_) => closed = true));
      await pump();
      await device.end('write 2');
      expect(closed, isFalse, reason: 'the cleanup is still flushing');
      await device.end('flush');

      expect(device.trace, [
        'write 1 start',
        'write 1 end',
        'write 2 start',
        'write 2 end',
        'flush start',
        'flush end',
      ]);
      expect(closed, isTrue);
      expect(job.outcome, isA<Cancelled>());
      expect(uploader.errors, isEmpty);
    });

    test('a join checks before its call as well as after it', () async {
      final device = Device();
      final uploader = Uploader(device);
      final job = uploader.writeAfterAPlainAwait();
      await pump();
      unawaited(job.cancel());
      await pump();

      await device.end('warm up');
      expect(
        device.trace,
        ['warm up start', 'warm up end'],
        reason: 'the gap after a plain await is covered by the next join',
      );
      expect(job.outcome, isA<Cancelled>());
    });
  });

  group('closing with work in the queue', () {
    test('close drops the queue, and the send in flight says Cancelled',
        () async {
      final device = Device();
      final outbox = Outbox(device);
      final sends = [outbox.send(1), outbox.send(2), outbox.send(3)];
      await pump();

      var closed = false;
      unawaited(outbox.close().then((_) => closed = true));
      await pump();
      expect(
        sends[1].outcome,
        isA<Cancelled>().having((c) => c.started, 'started', isFalse),
      );
      expect(
        sends[2].outcome,
        isA<Cancelled>().having((c) => c.started, 'started', isFalse),
      );

      await device.end('send 1');
      expect(closed, isTrue);
      expect(
        device.trace,
        ['send 1 start', 'send 1 end'],
        reason: 'the first batch did go out',
      );
      expect(
        sends[0].outcome,
        isA<Cancelled>().having(
          (c) => c.reason,
          'reason',
          isA<ClosedCancelReason>(),
        ),
        reason: 'and its outcome says it was cancelled',
      );
    });

    test('a drain sends every batch already queued', () async {
      final device = Device();
      final outbox = Outbox(device);
      final sends = [outbox.send(1), outbox.send(2), outbox.send(3)];
      await pump();

      var closed = false;
      unawaited(
        outbox.close(mode: SoloCloseMode.drain).then((_) => closed = true),
      );
      await pump();
      await device.end('send 1');
      await device.end('send 2');
      expect(closed, isFalse);
      await device.end('send 3');

      expect(closed, isTrue);
      expect(device.trace, [
        'send 1 start',
        'send 1 end',
        'send 2 start',
        'send 2 end',
        'send 3 start',
        'send 3 end',
      ]);
      for (final send in sends) {
        expect(send.outcome, isA<Done<void>>());
      }
    });
  });

  group('closing from inside a job', () {
    test('the first attempt never comes back', () async {
      final device = Device();
      final session = Session(device);
      final job = session.logoutFromTheJob();
      await pump();
      await device.end('logout');
      for (var i = 0; i < 10; i++) {
        await pump();
      }

      expect(device.trace, ['logout start', 'logout end']);
      expect(
        job.isFinished,
        isFalse,
        reason: 'close waits for this job, and this job waits for close',
      );
    });

    test('cancelAll from the body never comes back either', () async {
      final device = Device();
      final session = Session(device);
      final job = session.logoutCancellingAll();
      await pump();
      await device.end('logout');
      for (var i = 0; i < 10; i++) {
        await pump();
      }

      expect(job.isFinished, isFalse);
    });

    test('close awaited from the cleanup never comes back either', () async {
      final device = Device();
      final session = Session(device);
      final job = session.logoutClosingInCleanup();
      await pump();
      await device.end('logout');
      for (var i = 0; i < 10; i++) {
        await pump();
      }

      expect(job.outcome, isNull, reason: 'the cleanup is still waiting');
    });

    test('a drain closes once the queued logout is over', () async {
      final device = Device();
      final session = Session(device);
      final sync = session.sync();
      var done = false;
      unawaited(session.logoutByDraining().then((_) => done = true));
      await pump();
      await device.end('sync');
      await pump();
      expect(done, isFalse);
      await device.end('logout');

      expect(done, isTrue);
      expect(session.isClosed, isTrue);
      expect(session.currentState, 'signed in');
      expect(device.trace, [
        'sync start',
        'sync end',
        'logout start',
        'logout end',
      ]);
      expect(sync.outcome, isA<Done<void>>());
    });

    test('a drain turns down work submitted while it runs', () async {
      final device = Device();
      final session = Session(device);
      unawaited(session.logoutByDraining());
      await pump();
      final submitted = session.sync();
      await device.end('logout');
      await pump();

      expect(submitted.outcome, isA<Cancelled>());
      expect(device.trace, ['logout start', 'logout end']);
    });

    test('the page version starts it and cancels it in flight', () async {
      final device = Device();
      final session = Session(device);
      unawaited(session.logout());
      await pump();
      final submitted = session.sync();
      await device.end('logout');
      await pump();

      expect(device.trace, ['logout start', 'logout end', 'sync start']);
      expect(submitted.outcome, isNull, reason: 'the call is in flight');
      await device.end('sync');
      await pump();
      expect(submitted.outcome, isA<Cancelled>());
    });

    test('the page version logs out and closes', () async {
      final device = Device();
      final session = Session(device);
      var done = false;
      unawaited(session.logout().then((_) => done = true));
      await pump();
      await device.end('logout');

      expect(done, isTrue);
      expect(session.isClosed, isTrue);
      expect(
        session.currentState,
        'signed in',
        reason: 'closing publishes no state of its own',
      );
    });
  });
}

Future<void> pump() => Future<void>.delayed(Duration.zero);
