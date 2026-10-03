// The first attempts of `doc/state.md`, verbatim: every piece of the code
// under a "The first attempt" heading is a run of lines of this file, and
// `state_rakes_test.dart` runs it. The class the page adds to the profile
// states in its last first attempt stands in `state_profile_stubs.dart`,
// next to the states it extends. The page shows the constructor of `Camera`
// and the load with a `try` on their own; here each stands in its class.
import 'dart:async';

import 'package:solo/solo.dart';

import 'state_camera_stubs.dart';
import 'state_profile_stubs.dart' hide Disconnected;

final class Camera extends Solo<CameraState> {
  final Device device;
  late final StreamSubscription<bool> _link;

  /// How many times the rule of [waitForAnswer] was asked.
  int ruleAsked = 0;

  Camera(this.device) : super(const Ready()) {
    _link = device.connection.listen((connected) {
      if (!connected) {
        // The fact goes in like any other work, ahead of everything waiting.
        add(
          job<Ready, void>(
            key: 'disconnect',
            (ctx) async => ctx.emit(const Disconnected()),
          ),
          first: true,
        );
      }
    });
  }

  Job<void> record() => run<CameraState, void>(
        key: 'record',
        (ctx) async {
          final state = ctx.state;
          if (state is! Ready || state.free == 0 || state.paused) return;
          await for (final frame in device.frames) {
            await store(frame);
          }
        },
      );

  /// Not on the page: a fact of the device, the way a source of the
  /// application reports one.
  void reflect(CameraState state) => externalSetState(state);

  /// Not on the page: a job whose rule requires the connection, waiting for
  /// an answer the device gives only when the test says so.
  Job<void> waitForAnswer() => run<CameraState, void>(
        key: 'answer',
        keepWhile: (state) {
          ruleAsked++;
          return state is! Disconnected;
        },
        (ctx) => ctx.wait(() => device.answer.future),
      );

  /// Not on the page: work that waits its turn.
  Job<void> later() => run<CameraState, void>(key: 'later', (ctx) async {});

  /// Not on the page: the keys of what waits in the queue, in order.
  List<Object?> get queued => [for (final job in queue.jobs) job.key];

  @override
  void onClose() => unawaited(_link.cancel());
}

final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  /// Not on the page: a fact from outside, the way the device reports one.
  void reflect(ProfileState state) => externalSetState(state);

  /// The first attempt of "State after failure or cancellation".
  Job<String> loadWithCatch() => run<ProfileState, String>(
        (ctx) async {
          ctx.emit(const Loading());
          try {
            final name = await ctx.wait(api.fetchName);
            ctx.emit(Loaded(name));
            return name;
          } on Object {
            ctx.emit(const Initial());
            rethrow;
          }
        },
      );

  /// The first attempt of "Preserving an incompatible external state".
  Job<String> load() => run<ProfileState, String>(
        key: 'load',
        policy: Policy.droppable,
        onError: (state, error, stackTrace) => Failure(error),
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.wait(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );
}
