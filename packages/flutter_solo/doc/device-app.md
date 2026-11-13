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

The code on this page is the app's code. A trace is what the app does to the
camera under `flutter test`, where a fake camera platform stands in for the
phone. A call on the camera is a line, or two for a call that takes time, where
it starts and where it ends; a change of the state is a line too. Opening the
camera:

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
waits in the same queue, behind the opening.

A tap of the flash reads the mode from the state, where the job before it put
it once the platform had answered. The first attempt's flash button reads
`value.flashMode`, which the plugin's controller also sets only after the
answer, but nothing makes the next tap wait for it. On an iPhone 13 mini, taps
one frame apart, quicker than a finger taps, read the same mode, and one of
three taps was lost every time; taps 150 ms apart reached the flash in order.
