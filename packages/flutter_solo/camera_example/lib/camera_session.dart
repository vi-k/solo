import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_solo/flutter_solo.dart';

import 'camera_lights.dart';
import 'camera_state.dart';

/// The controller of the camera screen: it owns the plugin's
/// [CameraController], and its commands run one at a time.
///
/// A picture or a video goes up through [onCaptured], to a screen that
/// outlives this one.
final class CameraSession extends Solo<CameraState> {
  /// Takes every picture and video the camera makes.
  final void Function(XFile file) onCaptured;

  CameraSession({required this.onCaptured}) : super(const Closed());

  /// What the cameras of the phone can light, as the platform said at the
  /// last [open]: the screen shows the buttons of the flash and the torch
  /// by it.
  CameraLights get lights => _lights;
  CameraLights _lights = CameraLights.none;

  /// The camera [suspend] let go, for [resume] to open again.
  CameraDescription? _suspended;

  /// The errors the platform reports for the open camera.
  StreamSubscription<CameraErrorEvent>? _errors;

  /// Asks the platform what the cameras of the device can light, and
  /// opens the first of them; with a camera open already it does nothing.
  Job<void> open() => enqueue<CameraState, void>((ctx) async {
    if (ctx.state is Ready) return;
    ctx.emit(const Opening());
    final cameras = await ctx.join(availableCameras);
    if (cameras.isEmpty) {
      ctx.emit(const NoCamera());
      return;
    }
    _lights = await ctx.join(() => CameraLights.ask(cameras));
    await _initialize(ctx, cameras.first);
  });

  /// Takes a picture and hands it to [onCaptured]; a tap during a shot
  /// gets the shot that is under way.
  Job<XFile?> takePicture() => enqueue<Ready, XFile?>(
    key: _Op.takePicture,
    policy: Policy.droppable,
    (ctx) async {
      final file = await ctx.join(ctx.state.camera.takePicture);
      onCaptured(file);
      return file;
    },
  );

  /// Moves the flash to its next mode: off, auto, always, and off again.
  ///
  /// The platform has one setting for the flash and the torch: while the
  /// torch is on, the mode waits in the state, and [toggleTorch] sets it
  /// when it puts the torch out. On a camera without a flash the mode
  /// waits as well, and a switch sets it on a camera with one.
  Job<void> cycleFlash() => enqueue<Ready, void>((ctx) async {
    final Ready(:camera, :flash, :recording, :torch) = ctx.state;
    final next = switch (flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    if (!torch && lights.flash(camera.description)) {
      await ctx.join(() => camera.setFlashMode(next));
    }
    ctx.emit(
      Ready(camera: camera, flash: next, recording: recording, torch: torch),
    );
  });

  /// The torch the latest tap asked for, and its job, until that job ends.
  ({bool on, Job<void> job})? _torchAsked;

  /// Turns the torch on or off: a tap asks for the opposite of the tap
  /// before it, or of the torch when no tap waits.
  ///
  /// Only the latest tap waits in the queue, and its job calls nothing
  /// when the torch is already where the tap asks: taps faster than the
  /// camera neither blink the torch nor flash it.
  Job<void> toggleTorch() {
    final lit = switch (currentState) {
      Ready(:final torch) => torch,
      _ => false,
    };
    final on = !(_torchAsked?.on ?? lit);
    final job = enqueue<Ready, void>(
      key: _Op.torch,
      policy: Policy.keepLatest,
      (ctx) async {
        final Ready(:camera, :flash, :recording, :torch) = ctx.state;
        if (on == torch || !lights.torch(camera.description)) return;
        await ctx.join(() => camera.setFlashMode(on ? FlashMode.torch : flash));
        ctx.emit(
          Ready(camera: camera, flash: flash, recording: recording, torch: on),
        );
      },
    );
    _torchAsked = (on: on, job: job);
    job.whenFinished((_) {
      if (identical(_torchAsked?.job, job)) _torchAsked = null;
    });
    return job;
  }

  /// Moves to the next camera of the device.
  ///
  /// Without a recording the plugin releases the camera before it opens the
  /// next one, so a switch that fails is [Broken], as a failed opening is.
  /// The camera it opens starts with a flash mode of its own, while the
  /// controller keeps the one it had, so the switch sets the mode of the
  /// button again on a camera with a flash. A lit torch goes out before
  /// the switch, while its camera is open (see [release]), and lights again
  /// on a camera with one, during a recording too: neither plugin lights
  /// the torch of the next camera. During a recording the camera it had
  /// goes on recording, and a failure stays the error of the job.
  Job<void> switchCamera() => enqueue<Ready, void>((ctx) async {
    final cameras = await ctx.join(availableCameras);
    final Ready(:camera, :flash, :recording, :torch) = ctx.state;
    final at = cameras.indexWhere((c) => c.name == camera.description.name);
    final next = cameras[(at + 1) % cameras.length];
    if (torch) {
      await ctx.join(() => camera.setFlashMode(flash));
      ctx.emit(Ready(camera: camera, flash: flash, recording: recording));
    }
    try {
      await ctx.join(() => camera.setDescription(next));
    } on CameraException catch (error) {
      if (recording) rethrow;
      ctx.emit(Broken(error));
      _letGo(camera);
      return;
    }
    _watch(camera);
    if (torch && lights.torch(next)) {
      await ctx.join(() => camera.setFlashMode(FlashMode.torch));
      ctx.emit(
        Ready(camera: camera, flash: flash, recording: recording, torch: true),
      );
    } else if (!recording && lights.flash(next)) {
      await ctx.join(() => camera.setFlashMode(flash));
    }
  });

  /// Whether the latest start or stop asked for a recording, until its job
  /// ends; `null` when none is pending. The record button shows it while
  /// the platform starts or stops the recording.
  ///
  /// It is not disposed: a job that [close] drops still ends and resets it.
  ValueListenable<bool?> get recordingAsked => _recordingAsked;
  final _recordingAsked = ValueNotifier<bool?>(null);

  /// The job of the latest start or stop, until it ends.
  Job<Object?>? _recordingJob;

  /// Starts a video; a start that finds a recording on does nothing.
  Job<void> startRecording() => _ask(
    true,
    enqueue<Ready, void>((ctx) async {
      final Ready(:camera, :flash, :recording, :torch) = ctx.state;
      if (recording) return;
      await ctx.join(camera.startVideoRecording);
      ctx.emit(
        Ready(camera: camera, flash: flash, recording: true, torch: torch),
      );
    }),
  );

  /// Stops the video and hands it to [onCaptured]; with no recording it
  /// gives `null`.
  ///
  /// A stop that fails leaves the plugin's controller recording for good,
  /// so the camera is [Broken] and let go. A stop the loss of the camera
  /// cuts short still hands its video on, through `discard`.
  Job<XFile?> stopRecording() => _ask(
    false,
    enqueue<Ready, XFile?>((ctx) async {
      final Ready(:camera, :flash, :recording, :torch) = ctx.state;
      if (!recording) return null;
      final XFile file;
      try {
        file = await ctx.join(camera.stopVideoRecording, discard: onCaptured);
      } on CameraException catch (error) {
        ctx.emit(Broken(error));
        _letGo(camera);
        return null;
      }
      ctx.emit(
        Ready(camera: camera, flash: flash, recording: false, torch: torch),
      );
      onCaptured(file);
      return file;
    }),
  );

  /// Keeps [on] in [recordingAsked] until [job] ends, unless a later start
  /// or stop takes its place.
  J _ask<J extends Job<Object?>>(bool on, J job) {
    _recordingJob = job;
    _recordingAsked.value = on;
    job.whenFinished((_) {
      if (!identical(_recordingJob, job)) return;
      _recordingJob = null;
      _recordingAsked.value = null;
    });
    return job;
  }

  /// Stops a recording and hands it to [onCaptured], then frees the camera
  /// on the platform: the app has left the screen.
  ///
  /// The state is [Closed] before the release starts: a preview built on a
  /// controller being disposed throws. The stop is that of [release], and
  /// a lit torch goes out after it, as in [release]. An error the stop
  /// does not catch still lets the camera go, and is the error of the job.
  /// The job turns a [close] down once it runs, so a [close] during the
  /// stop waits for the release.
  Job<void> suspend() =>
      enqueue<CameraState, void>(cancellable: false, (ctx) async {
        if (ctx.state case Ready(
          :final camera,
          :final flash,
          :final recording,
          :final torch,
        )) {
          _suspended = camera.description;
          try {
            final stopped =
                !recording ||
                await ctx.join(() => stopBeforeRelease(camera, onCaptured));
            if (stopped && torch && currentState is Ready) {
              await ctx.join(() => camera.setFlashMode(flash));
            }
          } finally {
            ctx.emit(const Closed());
            await ctx.join(camera.dispose);
          }
        }
      });

  /// Opens the camera that [suspend] let go: the app is back on the screen.
  Job<void> resume() => enqueue<CameraState, void>((ctx) async {
    final description = _suspended;
    if (description == null) return;
    _suspended = null;
    ctx.emit(const Opening());
    await _initialize(ctx, description);
  });

  /// Stops a recording and hands it to [onCaptured], then frees the camera
  /// on the platform; the job ends once the platform has.
  ///
  /// The owner awaits it before [close]: a release started from `onClose`
  /// would not be waited for.
  ///
  /// A lit torch goes out after the stop, while its camera is open:
  /// `camera_android_camerax` keeps the torch on for the platform rather
  /// than for a camera, and would take the next camera's torch as lit. A
  /// camera the platform lost goes without that, and so does one whose
  /// stop ran out of time. The steps are one call to `join`, as in
  /// [_letGo].
  Job<void> release() => enqueue<CameraState, void>((ctx) async {
    if (ctx.state case Ready(
      :final camera,
      :final flash,
      :final recording,
      :final torch,
    )) {
      await ctx.join(() async {
        try {
          final stopped =
              !recording || await stopBeforeRelease(camera, onCaptured);
          if (stopped && torch && currentState is Ready) {
            await camera.setFlashMode(flash);
          }
        } finally {
          await camera.dispose();
        }
      });
    }
    ctx.emit(const Closed());
  });

  @override
  void onClose() => unawaited(_errors?.cancel());

  /// Creates the camera of [description] on the platform and opens it.
  ///
  /// A permission the app does not have is [Denied], and any other failure
  /// is [Broken]. A camera the platform has created is let go; a create
  /// that failed leaves the plugin's controller on [_noCamera], with
  /// nothing to let go.
  Future<void> _initialize(
    SoloContext<CameraState, CameraState> ctx,
    CameraDescription description,
  ) async {
    final camera = CameraController(description, ResolutionPreset.medium);
    try {
      await ctx.join(camera.initialize);
    } on CameraException catch (error) {
      final code = error.code;
      ctx.emit(_denials.contains(code) ? Denied(code) : Broken(error));
      if (camera.cameraId != _noCamera) {
        _letGo(camera);
      }
      return;
    }
    _watch(camera);
    ctx.emit(
      Ready(camera: camera, flash: camera.value.flashMode, recording: false),
    );
  }

  /// Follows the errors of [camera] in place of those of the camera before
  /// it: the id changes with every opening and with a switch without a
  /// recording.
  void _watch(CameraController camera) {
    unawaited(_errors?.cancel());
    _errors = CameraPlatform.instance
        .onCameraError(camera.cameraId)
        .listen((event) => _lose(event.description));
  }

  /// The platform says the open camera failed: the state shows it at once,
  /// and the camera is let go.
  void _lose(String description) {
    if (currentState case Ready(:final camera)) {
      externalSetState(Broken(description));
      _letGo(camera, lost: true);
    }
  }

  /// Frees [camera], which the state no longer holds, in a job of its own
  /// ahead of everything waiting in the queue: a [release] that waits there
  /// finds no camera in [Broken] and would end before this one.
  ///
  /// A [lost] camera that records stops first, and its video goes to
  /// [onCaptured]: released under a recording, the Galaxy's camera went on
  /// recording sound into the file. The stop and the release are one call
  /// to `join`, so a [close] during the stop waits for the release, and a
  /// stop that throws still lets the camera go.
  void _letGo(CameraController camera, {bool lost = false}) => enqueueJob(
    job<CameraState, void>(
      (ctx) => ctx.join(() async {
        try {
          if (lost && camera.value.isRecordingVideo) {
            await stopBeforeRelease(camera, onCaptured);
          }
        } finally {
          await camera.dispose();
        }
      }),
    ),
    first: true,
  );
}

/// The keys of the commands whose policy looks at them.
enum _Op { takePicture, torch }

/// The `cameraId` of the plugin's controller until the platform has
/// created its camera: `CameraController.kUninitializedCameraId`, which the
/// plugin keeps for its own tests.
const _noCamera = -1;

/// The codes of the plugin's `CameraException` for a permission the app
/// does not have, as its README lists them.
const _denials = {
  'CameraAccessDenied',
  'CameraAccessDeniedWithoutPrompt',
  'CameraAccessRestricted',
  'AudioAccessDenied',
  'AudioAccessDeniedWithoutPrompt',
  'AudioAccessRestricted',
};
