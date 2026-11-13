# A device app

A camera app with two screens. The home screen shows the last picture or video.
The camera screen has a preview and buttons for a picture, a video, the flash
and a switch between the cameras. The camera is the `camera` plugin, and the
screen owns it through `CameraSession`, a `Solo<CameraState>`. Every command
takes time on the phone, the phone can take the camera away, and a camera has
to be let go before the next screen opens it.

The sections on the situations of the app open with a first attempt: the
version the plugin's README and its example lead to. A section shows what that
code does on a phone and ends on the app's code.

The app is
[`camera_example`](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/camera_example)
in the repository of this package, and it runs on Android and iOS:

```sh
git clone https://github.com/vi-k/solo.git
cd solo/packages/flutter_solo/camera_example
flutter run
```

The answers on this page are the app's code; a first attempt is marked by a
line of its own, `// The first attempt:` and what goes wrong. A trace is what
the app does to the camera under `flutter test`, where a fake camera platform
stands in for the phone. A call on the camera is a line, or two for a call that
takes time, where it starts and where it ends; a change of the state is a line
too. Opening the camera:

```text
state Opening
create back #1
initialize #1 start
initialize #1 end
state Ready
```

## Rapid taps

A user taps faster than the camera answers. Each tap of the flash moves it one
mode on, in the order of the taps, and the flash ends where the last tap put
it. A tap of the shutter during a shot adds nothing: there is one picture. A
switch to another camera during a shot waits for the shot to end.

### The first attempt

The plugin's example calls the controller from each button, and it keeps a
second shot out with `isTakingPicture`:

```dart
// The first attempt: a switch during a shot loses the shot.
Future<void> cycleFlash() async {
  final next = switch (camera.value.flashMode) {
    FlashMode.off => FlashMode.auto,
    FlashMode.auto => FlashMode.always,
    _ => FlashMode.off,
  };
  try {
    await camera.setFlashMode(next);
  } on CameraException catch (e) {
    show(e);
  }
}

Future<void> shoot() async {
  // A capture is already pending, do nothing.
  if (camera.value.isTakingPicture) return;
  try {
    widget.onCaptured(await camera.takePicture());
  } on CameraException catch (e) {
    show(e);
  }
}

Future<void> switchCamera() async {
  final next = widget.cameras.firstWhere(
    (c) => c.name != camera.value.description.name,
  );
  try {
    await camera.setDescription(next);
  } on CameraException catch (e) {
    show(e);
  }
}
```

The guard holds the shutter to the requirement. Nothing holds a switch:
`setDescription` releases the camera the controller has and opens the next one,
and a picture in progress does not stop it. A tap of the shutter, then one of
the switch:

```text
capture #1 start
dispose #1 start
capture #1 failed
dispose #1 end
create front #2
initialize #2 start
initialize #2 end
```

On a Galaxy A55 the release loses the picture, and the fake platform does the
same: the platform reports
`Image capture failed due to the camera being closed.`, `takePicture` throws,
and the screen shows `ImageCaptureException:
androidx.camera.core.ImageCaptureException: Camera is closed.` The next camera
opens and works. An iPhone 13 mini releases the camera only once the shot is
over, and the picture comes through: the same code keeps the picture on one
phone and loses it on the other.

The flash button picks the next mode from `value.flashMode`, which the plugin's
controller sets only once `setFlashMode` has answered. Taps faster than that
answer read the same mode and ask for it twice, and one tap is lost: on an
iPhone 13 mini, three such taps from `auto` leave the flash at `off` rather
than back at `auto`.

### One queue for the buttons

Every command of `CameraSession` is a job in the one queue of its `Solo`, which
runs one job at a time:

```dart
Job<XFile?> takePicture() => enqueue<Ready, XFile?>(
  key: _Op.takePicture,
  policy: Policy.droppable,
  (ctx) async {
    final file = await ctx.join(ctx.state.camera.takePicture);
    onCaptured(file);
    return file;
  },
);

Job<void> cycleFlash() => enqueue<Ready, void>((ctx) async {
  final Ready(:camera, :flash, :recording) = ctx.state;
  final next = switch (flash) {
    FlashMode.off => FlashMode.auto,
    FlashMode.auto => FlashMode.always,
    _ => FlashMode.off,
  };
  await ctx.join(() => camera.setFlashMode(next));
  ctx.emit(Ready(camera: camera, flash: next, recording: recording));
});

Job<void> switchCamera() => enqueue<Ready, void>((ctx) async {
  final cameras = await ctx.join(availableCameras);
  final camera = ctx.state.camera;
  final at = cameras.indexWhere((c) => c.name == camera.description.name);
  final next = cameras[(at + 1) % cameras.length];
  await ctx.join(() => camera.setDescription(next));
});

enum _Op { takePicture }
```

`Policy.droppable` hands a second tap of the shutter the job of the first one
while that job is queued or running, so one picture reaches `onCaptured`. The
flash and the switch keep the default, `Policy.sequential`: every tap is a job
of its own and waits for the one before it. A switch tapped during a shot
starts once the shot is over, and `setDescription` releases a camera with
nothing in progress. Two taps of the shutter, then one of the switch:

```text
capture #1 start
capture #1 end
dispose #1 start
dispose #1 end
create front #2
initialize #2 start
initialize #2 end
```

The second tap of the shutter leaves no line. A tap made while the camera opens
waits in the same queue, behind the opening. A tap of the flash waits there for
the tap before it and reads the mode from the state, where that tap put it.

## A switch during a recording

A user switches to the other camera while a video records. The recording goes
on from the other camera, and the stop gives one file. A tap of stop during the
switch waits for the switch to end.

### The first attempt

`setDescription` of the plugin's controller looks at `value.isRecordingVideo`.
During a recording it hands the next camera to the recording; otherwise it
releases the camera and opens the next one. On Android the plugin wants the
recording started with `enablePersistentRecording`, and `startVideoRecording`
turns it on by default. The buttons call the controller, and record and stop
check the flag first:

```dart
// The first attempt: a switch while the recording starts loses the recording.
Future<void> record() async {
  // A recording is already started, do nothing.
  if (camera.value.isRecordingVideo) return;
  try {
    await camera.startVideoRecording();
  } on CameraException catch (e) {
    show(e);
  }
}

Future<void> switchCamera() async {
  final next = widget.cameras.firstWhere(
    (c) => c.name != camera.value.description.name,
  );
  try {
    await camera.setDescription(next);
  } on CameraException catch (e) {
    show(e);
  }
}

Future<void> stop() async {
  if (!camera.value.isRecordingVideo) return;
  try {
    widget.onCaptured(await camera.stopVideoRecording());
  } on CameraException catch (e) {
    show(e);
  }
}
```

The controller sets `isRecordingVideo` only once `startVideoRecording` has
answered. A switch tapped before that takes the other way: it releases the
camera under the recording that is starting and opens the next one. The start
ends after that, and the controller, on the new camera by then, sets the flag.
A tap of record, of the switch while the recording starts, then of stop:

```text
record #1 start
dispose #1 start
dispose #1 end
create front #2
initialize #2 start
initialize #2 end
stop #2 start
```

On an iPhone 13 mini a recording can take more than a second and a half to
start, and a switch tapped in that time loses the recording; the fake platform
follows the iPhone here. The flag says a recording is on, stop asks the
platform for it, and the platform has none: the screen shows
`Error -1008: Video is not recording!` Once the recording has started, a switch
carries it over to the other camera on an iPhone 13 mini and on a Galaxy A55
alike, and a stop tapped during that switch ends after it, with one file.

### The recording in the queue

The start and the stop of a recording are jobs in the queue of the buttons:

```dart
Job<void> startRecording() => enqueue<Ready, void>((ctx) async {
  final Ready(:camera, :flash, :recording) = ctx.state;
  if (recording) return;
  await ctx.join(camera.startVideoRecording);
  ctx.emit(Ready(camera: camera, flash: flash, recording: true));
});

Job<XFile?> stopRecording() => enqueue<Ready, XFile?>((ctx) async {
  final Ready(:camera, :flash, :recording) = ctx.state;
  if (!recording) return null;
  final file = await ctx.join(camera.stopVideoRecording);
  ctx.emit(Ready(camera: camera, flash: flash, recording: false));
  onCaptured(file);
  return file;
});
```

A switch tapped while the recording starts waits behind the start, as a switch
during a shot waits behind the shot. When the switch runs, the recording is on,
and `setDescription` hands the next camera to it. A tap of stop during the
switch waits behind the switch. A job reads whether a recording is on from the
state, which the job before it has left, so a second tap of record or of stop
does nothing. A tap of record, of the switch while the recording starts, then
of stop during the switch, with the fake platform on the iPhone's rules:

```text
record #1 start
record #1 started
state Ready
switch #1 front start
switch #1 front end
stop #1 start
record #1 end
state Ready
```
