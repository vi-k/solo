// Section 5 of `doc/vs-bloc.md`, "Restarting one operation within a shared queue": what the page leaves out,
// then the code under its `### Solo` heading, verbatim, then what
// `vs_bloc_rakes_test.dart` adds on top of it. Every piece of the page's
// blocks is a run of lines of this file. The bloc side of the section is
// built and run by the bench, `tool/doc_snippets.py`: this package does not
// depend on bloc.
import 'package:solo/solo.dart';

import 'vs_bloc_stubs.dart';

sealed class PlayerState {}

final class Ready extends PlayerState {
  Ready({this.playing = false, this.position = Duration.zero});

  final bool playing;
  final Duration position;

  Ready copyWith({bool? playing, Duration? position}) => Ready(
        playing: playing ?? this.playing,
        position: position ?? this.position,
      );

  @override
  String toString() => 'Ready(${position.inMilliseconds}ms)';
}

class Player {
  Player({this.failsWhenStopped = false});

  /// A seek told to stop throws instead of returning.
  final bool failsWhenStopped;
  final trace = <String>[];

  Future<void> play() async {
    trace.add('play start');
    await tick(30);
    trace.add('play end');
  }

  Future<void> pause() async {
    trace.add('pause start');
    await tick(30);
    trace.add('pause end');
  }

  // The native seek watches the token: told to stop, it stops and returns
  // instead of running to the requested position.
  Future<void> seek(Duration position, {CancelToken? cancelToken}) async {
    final ms = position.inMilliseconds;
    trace.add('seek $ms start');
    for (var step = 0; step < 3; step++) {
      await tick(10);
      if (cancelToken?.cancelled ?? false) {
        trace.add('seek $ms stopped');
        if (failsWhenStopped) {
          throw StateError('seek $ms interrupted');
        }
        return;
      }
    }
    trace.add('seek $ms end');
  }
}

// The code of the page.

enum PlayerKey { play, pause, seek }

final class PlayerController extends Solo<PlayerState> with SoloStream {
  final Player _player;

  PlayerController(this._player) : super(Ready());

  Job<void> play() => run<Ready, void>(
        key: PlayerKey.play,
        (ctx) async {
          await ctx.join(_player.play);
          ctx.emit(ctx.state.copyWith(playing: true));
        },
      );

  Job<void> pause() => run<Ready, void>(
        key: PlayerKey.pause,
        (ctx) async {
          await ctx.join(_player.pause);
          ctx.emit(ctx.state.copyWith(playing: false));
        },
      );

  Job<void> seek(Duration position) => run<Ready, void>(
        key: PlayerKey.seek,
        policy: Policy.restart,
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          await ctx.join(() => _player.seek(position, cancelToken: token));
          ctx.emit(ctx.state.copyWith(position: position));
        },
      );
}

// What the test adds.

/// The seek of the page with what `ctx.join` threw written down.
final class CatchingPlayerController extends Solo<PlayerState> {
  CatchingPlayerController(this._player) : super(Ready());

  final Player _player;
  final met = <String>[];

  Job<void> seek(Duration position) => run<Ready, void>(
        key: PlayerKey.seek,
        policy: Policy.restart,
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          try {
            await ctx.join(() => _player.seek(position, cancelToken: token));
          } on Object catch (error) {
            met.add('join threw ${error.runtimeType}: $error');
            rethrow;
          }
          ctx.emit(ctx.state.copyWith(position: position));
        },
      );
}
