// The code of `README.md` under "The dozen calls", verbatim: the player and
// the call site, which lives in a function of its own. `readme_rakes_test`
// runs it.
import 'package:solo/solo.dart';

import 'readme_stubs.dart';

enum _Op { play }

final class Player extends Solo<PlayerState> {
  final Api api;
  final Device device;

  Player(this.api, this.device) : super(const Idle()) {
    // A fact from outside the queue: published at once, and the rule of
    // the running job is asked about it.
    device.onDisconnect = () => externalSetState(const Disconnected());
  }

  /// A job on the controller's queue. Root jobs run one at a time, and
  /// this one ends when the track starts: the device plays it on its own.
  Job<Track> play(String id) => run<PlayerState, Track>(
        // Any object is a key. This one keys the operation, not a track.
        key: _Op.play,
        // A new play cancels the one running under the same key.
        policy: Policy.restart,
        // A rule: asked before the start, and on every change of state
        // while the body runs, except one the body makes with `ctx.emit`.
        keepWhile: (state) => state is! Disconnected,
        // The state to publish when the job fails or is cancelled. A
        // cancellation by the rule publishes nothing: `Disconnected` stays.
        ifFailed: (state, error, stackTrace) => const Idle(),
        ifCancelled: (state, cancelled) => const Idle(),
        (ctx) async {
          // The body's way to change state. There is no setter outside.
          ctx.emit(const Loading());
          // Waited out whatever happens: the track playing now stops
          // before another one loads.
          await ctx.join(device.stop);
          // Cancellation ends this wait at once; the request may go on.
          final track = await ctx.abandonable(() => api.fetch(id));
          // Waited out as well. `dispose` closes the download when the
          // job ends, or as soon as the call returns if the job was
          // cancelled meanwhile.
          final download = await ctx.join(
            () => api.download(track),
            dispose: (download) => download.close(),
          );
          // A child job: the device reads the download in, and the stream
          // ends when the track starts. `value` waits for that.
          await ctx.each(device.load(download), (childCtx, percent) {
            childCtx.emit(Buffering(track, percent));
          }).value;
          ctx.emit(Playing(track));
          return track;
        },
      );

  /// Events that share one queued job: only the last volume matters.
  late final _volume = accumulate<PlayerState, double, void>(
    (ctx, value) => ctx.join(() => device.setVolume(value)),
    merge: (previous, incoming) => incoming,
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 50)),
  );

  Job<void> setVolume(double value) => _volume.add(value);

  // The callback is removed before the state is final: after that,
  // `externalSetState` would throw.
  @override
  void onClose() => device.onDisconnect = null;
}

/// The call site of the page.
Future<void> callSite(Api api, Device device) async {
  final player = Player(api, device);

  final job = player.play('t-1');
  switch (await job.done) {
    case Done(:final value):
      print('playing $value');
    case Failed(:final error):
      print('failed: $error');
    case Cancelled(:final reason):
      print('cancelled: $reason');
  }

  player.setVolume(0.4);
  // Stop taking new work now, run what is already queued, then close.
  await player.close(mode: SoloCloseMode.drain);
}
