// The first and the second attempts of `doc/cancellation.md`, verbatim:
// every piece of the code under a "The first attempt" or "The second
// attempt" heading is a run of lines of this file, and
// `cancellation_rakes_test.dart` runs it. The page shows each as a method or
// a few statements on their own; here each version stands in a class or a
// function.
import 'dart:async';

import 'package:solo/solo.dart';

import 'cancellation_stubs.dart';
import 'test_solo.dart';

/// The first attempt of "Stopping the underlying operation": the waiting
/// method that ends at once.
final class AbandoningPlayer extends Solo<AppState>
    with OpenSolo<AppState>, Desk {
  final _player = player;

  AbandoningPlayer() : super(const Ready());

  Job<void> seek(Duration position) => run<Ready, void>(
        key: 'seek',
        policy: Policy.restart,
        (ctx) async {
          // Ends the moment the next seek cancels this one.
          await ctx.abandonable(() => _player.seek(position));
          ctx.emit(ctx.state.copyWith(position: position));
        },
      );
}

/// The second attempt of the same section: the waiting method that waits
/// the call out.
final class JoiningPlayer extends Solo<AppState> with OpenSolo<AppState>, Desk {
  final _player = player;

  JoiningPlayer() : super(const Ready());

  Job<void> seek(Duration position) => run<Ready, void>(
        key: 'seek',
        policy: Policy.restart,
        (ctx) async {
          // Waited out, so the device never runs two seeks at once.
          await ctx.join(() => _player.seek(position));
          ctx.emit(ctx.state.copyWith(position: position));
        },
      );
}

/// The first attempt of "Ordinary await and context lifetime": each wait is
/// the one the other place needed.
final class InvertedUploader extends Solo<AppState>
    with OpenSolo<AppState>, Desk {
  InvertedUploader() : super(const Ready());

  Job<void> upload(List<int> chunks) => run<Ready, void>((ctx) async {
        ctx.onDispose(() async {
          // The flush must finish before the queue moves on.
          // ignore: unnecessary_lambdas
          await ctx.join(() => device.flush());
        });
        for (final chunk in chunks) {
          await device.write(chunk);
        }
      });
}

/// The first attempt of "Cancelling and closing a controller", in the two
/// moments its comment tells apart: the screen sends its batches...
void sendThree(Logs logs, String first, String second, String third) {
  logs.send(first);
  // ignore: cascade_invocations
  logs.send(second);
  logs.send(third);
}

/// ...and goes away.
Future<void> closeTheScreen(Logs logs) async {
  // The first batch is on its way when the screen goes away.
  await logs.close();
}

/// The first attempt of "Closing from a job": the job closes its own
/// controller.
final class SelfClosingSession extends Solo<AppState>
    with OpenSolo<AppState>, Desk {
  SelfClosingSession() : super(const Ready());

  Job<void> logout() => run<Ready, void>((ctx) async {
        await ctx.join(api.logout);
        await close();
      });
}

/// The second attempt of the same subsection: the job first, the closing
/// after it.
final class ClosingSession extends Solo<AppState>
    with OpenSolo<AppState>, Desk {
  ClosingSession() : super(const Ready());

  Future<void> logout() async {
    await run<Ready, void>((ctx) => ctx.join(api.logout)).done;
    await close();
  }
}
