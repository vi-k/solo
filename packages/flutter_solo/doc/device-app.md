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

The trace has no `dispose` line: the switch releases no camera, and the
recording goes on from the front one. The stop starts once the switch has ended
and gives one file.

## Leaving the screen

A user leaves the camera screen while a picture is being taken, and may open it
again at once. The picture reaches the home screen. The camera screen opened
again opens the camera only once the screen before it has let the camera go.

### The first attempt

The plugin's README releases the controller in `dispose` of the `State`, and
the screen hands a picture up through `onCaptured`, to the home screen, which
outlives the camera screen:

```dart
// The first attempt: leaving loses the shot; coming back opens two cameras.
@override
void dispose() {
  camera.dispose();
  super.dispose();
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
```

`dispose` of the `State` comes once the route of the screen has gone, at the
end of the transition of `pop`, and `camera.dispose()` releases the camera
whatever the controller is doing. Nothing waits for that release: a camera
screen pushed again creates its controller on its first frame, while the screen
before it still holds the camera. A tap of the shutter, then of back, and the
camera screen opened again at once, with a picture longer than the transition
and the fake platform on the Galaxy's rules:

```text
capture #1 start
create back #2
initialize #2 start
initialize #2 end
dispose #1 start
capture #1 failed
dispose #1 end
```

The second camera is created before the first one is released, and the release
comes in the middle of the picture. On a Galaxy A55 the release ends the
picture, and the fake platform does the same. The plugin's `takePicture` then
writes the `value` of a controller that is disposed by then, and a debug build
throws `A CameraController was used after being disposed.` rather than the
`CameraException` the screen catches. The picture does not reach the home
screen. The second camera, created while the first one was open, shows an empty
preview, and its own release throws `IllegalStateException`. An iPhone 13 mini
finishes the picture before it releases the camera, though a picture that
outlasts the transition throws the same error in a debug build. Its plugin
holds one camera at a time, and the release of the first camera closes the
second: the preview freezes, and a picture on it never comes.

### A release the next screen waits for

`release()` of `CameraSession` is a command in the queue of the buttons:

```dart
Job<void> release() => enqueue<CameraState, void>((ctx) async {
  if (ctx.state case Ready(:final camera)) {
    await ctx.join(camera.dispose);
  }
  ctx.emit(const Closed());
});
```

It starts once the command before it is over, a picture included, and ends once
the platform has released the camera. A release that comes while the camera
opens waits for the opening and releases the camera it opened.

`CameraScreen` owns the session through an `AsyncDataScope` of
[scopo](https://pub.dev/packages/scopo). The scope makes the session when the
screen comes in. When the screen leaves, the scope runs `disposeData`, which
awaits the release and closes the session after it: `close()` of a `Solo` does
not wait for what `onClose` starts. `scopeKey` puts the scopes of all camera
screens in one queue, which the `AsyncScopeCoordinator` above the navigator
keeps. A scope with the key starts once the scope before it on the key has
finished `disposeData`:

```dart
class CameraApp extends StatelessWidget {
  const CameraApp({super.key});

  @override
  Widget build(BuildContext context) => const AsyncScopeCoordinator(
    child: MaterialApp(title: 'Camera', home: HomeScreen()),
  );
}
```

The wait for the key and the wait for `disposeData` are bounded, 3 s each by
default. When either expires, scopo goes on as if the wait had ended, and the
new screen opens the camera while the old one still holds it: the break of the
first attempt, only later. A picture on a Galaxy A55 takes up to 3.4 s, a
recording on an iPhone 13 mini up to 2.5 s to start, and the release waits for
either, so the screen sets both bounds to `releaseTimeout`, ten seconds, with
room to spare:

```dart
static const releaseTimeout = Duration(seconds: 10);

@override
Widget build(BuildContext context) => AsyncDataScope<CameraSession>(
  scopeKey: CameraScreen,
  scopeKeyTimeout: releaseTimeout,
  disposeScopeTimeout: releaseTimeout,
  initData: (context, ctx) async =>
      CameraSession(onCaptured: onCaptured)..open(),
  disposeData: (session) async {
    try {
      await session.release().value;
    } finally {
      await session.close();
    }
  },
  progressBuilder: (context, progress) => const SizedBox.expand(),
  errorBuilder: (context, error, stackTrace, progress) =>
      Center(child: Text('$error')),
  builder: (context, session) => CameraView(session: session),
);
```

The same taps: the shutter, back, and the camera screen opened again at once:

```text
capture #1 start
capture #1 end
dispose #1 start
dispose #1 end
state Closed
state Opening
create back #2
initialize #2 start
initialize #2 end
state Ready
```

The release starts once the picture has ended, and the picture goes up to the
home screen. The second session opens its camera after the first one has
released its camera and closed: `state Closed` of the first comes before
`state Opening` of the second. Until then the scope of the new screen waits for
the key and builds `progressBuilder`, an empty screen.

## Going to the background

A user goes to the home screen of the phone while a video records, and may come
back at once. The recording is kept and reaches the home screen. The camera is
let go while the app is away, and coming back opens it again, only once it has
been let go.

### The first attempt

The plugin's README leaves the lifecycle of the app to the app. Its section
"Handling Lifecycle states" releases the controller on `inactive` and makes a
new one for the same camera on `resumed`. The stop button checks that a
recording is on:

```dart
// The first attempt: leaving during a recording loses the recording.
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  final CameraController? cameraController = controller;

  // App state changed before we got the chance to initialize.
  if (cameraController == null || !cameraController.value.isInitialized) {
    return;
  }

  if (state == AppLifecycleState.inactive) {
    cameraController.dispose();
  } else if (state == AppLifecycleState.resumed) {
    _initializeCameraController(cameraController.description);
  }
}

Future<void> stop() async {
  final camera = controller;
  if (camera == null || !camera.value.isRecordingVideo) return;
  try {
    widget.onCaptured(await camera.stopVideoRecording());
  } on CameraException catch (e) {
    show(e);
  }
}
```

On a Galaxy A55 and on an iPhone 13 mini alike, leaving for the home screen of
the phone gives `inactive`, `hidden` and `paused`, and coming back gives
`hidden`, `inactive` and `resumed`. `dispose()` on the first `inactive`
releases the camera under the recording, and nothing asks for the file. The
controller made on `resumed` has no recording, so a tap of stop does nothing. A
tap of record, the home screen of the phone and back, then a tap of stop, with
the fake platform on the rules of either phone, which agree here:

```text
record #1 start
record #1 started
dispose #1 start
dispose #1 end
create back #2
initialize #2 start
initialize #2 end
```

The trace has no `stop` line: the recording does not reach the home screen. On
both phones the recording is lost, and the camera opened on `resumed` works.

### A suspend in the queue

`suspend()` and `resume()` of `CameraSession` are commands in the queue of the
buttons. `suspend()` stops a recording and hands the file to `onCaptured`
before it releases the camera, and it keeps the camera it let go; `resume()`
opens that camera again with `_initialize`, the end of `open()`, which creates
the controller and initializes it:

```dart
Job<void> suspend() => enqueue<CameraState, void>((ctx) async {
  if (ctx.state case Ready(:final camera, :final recording)) {
    _suspended = camera.description;
    try {
      if (recording) onCaptured(await ctx.join(camera.stopVideoRecording));
    } finally {
      ctx.emit(const Closed());
      await ctx.join(camera.dispose);
    }
  }
});

Job<void> resume() => enqueue<CameraState, void>((ctx) async {
  final description = _suspended;
  if (description == null) return;
  _suspended = null;
  ctx.emit(const Opening());
  await _initialize(ctx, description);
});
```

`suspend()` emits `Closed` before the release starts, and the screen takes the
preview down: a preview built on a controller that is being released throws
`buildPreview() was called on a disposed CameraController.` So here `Closed`
comes a moment before the camera is free, while `release()` emits it once the
camera is free: in `suspend()` it says the preview is down, and the camera is
free once `suspend()` has ended. A stop that fails still releases the camera,
from `finally`, and its failure is the error of `suspend()`. A `resume()` that
comes before the release has ended waits behind it in the queue.

`CameraView`, the part of the screen that shows the session, listens to the
lifecycle of the app for as long as it is there:

```dart
@override
void initState() {
  super.initState();
  _lifecycle = AppLifecycleListener(
    onHide: () => widget.session.suspend(),
    onShow: () => widget.session.resume(),
  );
}

@override
void dispose() {
  _lifecycle.dispose();
  super.dispose();
}
```

`onHide` comes when the app goes from `inactive` to `hidden`, and `onShow` on
the way back, from `hidden` to `inactive`. The screen does not release the
camera on `inactive`: on both phones a permission dialog gives `inactive` and
`resumed` and nothing else, and the plugin asks for the permission while it
opens the camera. A dialog that comes while the camera opens releases nothing,
and the camera opens.

A tap of record, the home screen of the phone and back at once, with the fake
platform on the rules of either phone, which agree here:

```text
record #1 start
record #1 started
state Ready
stop #1 start
record #1 end
state Closed
dispose #1 start
dispose #1 end
state Opening
create back #2
initialize #2 start
initialize #2 end
state Ready
```

The stop comes before the release, and the recording goes up to the home
screen. The camera opens again once the release has ended: `dispose #1 end`
comes before `create back #2`. On a Galaxy A55 the stop on `hidden` gives the
file, and a return at once comes in the middle of the stop and opens the camera
after the release, in the same order.
