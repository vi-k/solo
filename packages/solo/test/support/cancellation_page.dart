// The code of `doc/cancellation.md`, verbatim, less the first and second
// attempts: every piece of those blocks is a run of lines of this file, and
// `cancellation_rakes_test.dart` runs it. The page shows the methods of
// controllers and a few statements on their own; here each stands in a class
// or a function, and a method the page writes more than once has a class for
// each version.
import 'dart:async';

import 'package:solo/solo.dart';

import 'cancellation_stubs.dart';
import 'test_solo.dart';

/// "The token": the cancellation reaches the call.
final class TokenPlayer extends Solo<AppState> with OpenSolo<AppState>, Desk {
  final _player = player;

  TokenPlayer() : super(const Ready());

  Job<void> seek(Duration position) => run<Ready, void>(
        key: 'seek',
        policy: Policy.restart,
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          // Wait for the device to stop before another seek starts.
          await ctx.join(() => _player.seek(position, cancelToken: token));
          ctx.emit(ctx.state.copyWith(position: position));
        },
      );
}

/// "A deadline of a job": the seek of "The token" with a deadline, and a
/// state for the deadline of its own.
final class DeadlinePlayer extends Solo<AppState>
    with OpenSolo<AppState>, Desk {
  final _player = player;

  DeadlinePlayer() : super(const Ready());

  Job<void> seek(Duration position) => run<Ready, void>(
        key: 'seek',
        policy: Policy.restart,
        timeout: const Duration(seconds: 2),
        ifCancelled: (state, cancelled) =>
            cancelled.reason is TimeoutCancelReason ? const Offline() : state,
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          await ctx.join(() => _player.seek(position, cancelToken: token));
          ctx.emit(ctx.state.copyWith(position: position));
        },
      );
}

/// "One section for the step" and "A whole job".
final class Till extends Solo<AppState> with OpenSolo<AppState>, Desk {
  Till() : super(const Ready());

  Job<void> commit(String entry) => run<Ready, void>((ctx) async {
        await ctx.uncancellable(() async {
          final receipt = await payment.commit();
          ctx.emit(ctx.state.copyWith(receipt: receipt));
          await journal.write(entry);
        });
        // ...the rest of the job, which cancellation can still stop.
      });

  // A job that turns down every request it is allowed to turn down.
  Job<void> flush() => run<Ready, void>(
        cancellable: false,
        (ctx) => device.flush(),
      );
}

/// "Each wait in its place".
final class Uploader extends Solo<AppState> with OpenSolo<AppState>, Desk {
  Uploader() : super(const Ready());

  Job<void> upload(List<int> chunks) => run<Ready, void>((ctx) async {
        ctx.onDispose(() async {
          // Cleanup runs after the body, where the waiting methods are
          // gone: a plain await is the wait that works here.
          await device.flush();
        });
        for (final chunk in chunks) {
          // Checks before the write and after it.
          await ctx.join(() => device.write(chunk));
        }
      });
}

// --- Cancellation details ------------------------------------------------

final class OutOfRange extends CancelReason {
  final Duration position;

  const OutOfRange(this.position);

  @override
  String get name => 'out of range';
}

/// The first statement under "Cancellation details".
Future<void> cancelFromOutside(Job<Object?> job, Duration position) async {
  // From outside the job:
  await job.cancel(reason: OutOfRange(position));
}

/// The second statement, in the body of a seek that knows how far it may
/// go.
final class BoundedPlayer extends Solo<AppState> with OpenSolo<AppState>, Desk {
  /// Not on the page: the end of the track.
  static const end = Duration(minutes: 3);

  BoundedPlayer() : super(const Ready());

  Job<void> seek(Duration position) => run<Ready, void>((ctx) async {
        if (position > end) {
          // From inside its body:
          throw Cancelled.by(reason: OutOfRange(position), started: true);
        }
        await ctx.join(() => player.seek(position));
      });
}

/// The third statement.
void readOutcome(Job<Object?> job) {
  // And on the way out:
  switch (job.outcome) {
    case Cancelled(reason: OutOfRange(:final position)):
      print('out of range at $position');
    case Cancelled(:final reason, :final started):
      print('cancelled by ${reason.name}, started: $started');
    case _:
  }
}

// --- Three ways to stop --------------------------------------------------

Future<void> stopByCancellingAll(Logs logs) async {
  // Clear the queue and cancel the running job; the controller stays open.
  await logs.cancelAll();
}

Future<void> stopByClosing(Logs logs) async {
  // The same, and nothing new is accepted afterwards.
  await logs.close();
}

Future<void> stopByDraining(Logs logs) async {
  // Or run what is already queued first, and close after it.
  await logs.close(mode: SoloCloseMode.drain);
}

/// "Queue the job and drain".
final class DrainingSession extends Solo<AppState>
    with OpenSolo<AppState>, Desk {
  DrainingSession() : super(const Ready());

  Future<void> logout() async {
    run<Ready, void>((ctx) => ctx.join(api.logout)).ignoreFailure();
    await close(mode: SoloCloseMode.drain);
  }
}
