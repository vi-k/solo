# A device app

A camera app with two screens. The home screen shows the last picture or video.
The camera screen has a preview and buttons for a picture, a video, the flash
and a switch between the cameras. The camera is the `camera` plugin, and the
screen owns it through `CameraSession`, a `Solo<CameraState>`. Every command
takes time on the phone, the phone can take the camera away, and a camera has
to be let go before the next screen opens it.

The sections on the situations of the app open with a first attempt: the
version the plugin's README and its example lead to. A section shows what that
code does on a phone and ends on the app's code. Two sections close the page:
the tests of the app, and the same camera screen on bloc.

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

## Losing the camera

Another app takes the camera, or the camera fails. The screen shows the failure
and a button to retry, and a retry opens the camera again.

### The first attempt

The plugin's example listens to its controller and, once the controller's
`value` holds an error, shows `Camera error` with the description of the error.
The example shows it in a snack bar; here the text stays on the screen as a
`Text`, so the screen says at any moment what the listener last showed:

```dart
// The first attempt: the first error stays, and the second is not seen.
@override
void initState() {
  super.initState();
  camera.addListener(() {
    if (mounted) setState(() {});
    if (camera.value.hasError) {
      show('Camera error ${camera.value.errorDescription}');
    }
  });
  camera.initialize().catchError(show);
}
```

The plugin's controller listens to the errors of its camera through
`onCameraError(cameraId).first`. It puts the first error into
`value.errorDescription`, never clears it, and hears no error after it. Every
later change of `value`, after a picture or a tap of the flash, finds the old
error there, and the example's listener shows it again. The screen has no state
for a camera that is lost and no way to open it again.

On a Galaxy A55 the phone's own camera app, opened full screen, takes the
camera: the app gets the error
`The camera was already in use, possibly by a higher-priority camera client.`
and no closing event. Back in the app, the camera works again by itself. An
iPhone 13 mini reports no error: its camera app sends this app to the
background, and back from there the camera works. A line `camera #1 error` is
an error the platform reports. The camera taken away, a picture, and a second
error of the same camera, with the fake platform on the Galaxy's rules:

```text
camera #1 error
capture #1 start
capture #1 end
camera #1 error
```

The picture comes through, and the screen still says
`Camera error The camera was already in use,
possibly by a higher-priority camera client.` The second error leaves no mark:
the controller stopped listening after the first.

### A failure in the state

`CameraSession` follows the errors of its camera through a subscription of its
own. It is a field of the controller rather than a job: a job that follows a
stream holds the queue for as long as the stream is open. The id of the camera
changes with every opening and with a switch without a recording, so `_watch`
drops the subscription of the camera before and makes a new one, and `onClose`
cancels the last:

```dart
StreamSubscription<CameraErrorEvent>? _errors;

@override
void onClose() => unawaited(_errors?.cancel());

void _watch(CameraController camera) {
  unawaited(_errors?.cancel());
  _errors = CameraPlatform.instance
      .onCameraError(camera.cameraId)
      .listen((event) => _lose(event.description));
}

void _lose(String description) {
  if (currentState case Ready(:final camera)) {
    externalSetState(Broken(description));
    _letGo(camera);
  }
}

void _letGo(CameraController camera) => enqueueJob(
  job<CameraState, void>((ctx) => ctx.join(camera.dispose)),
  first: true,
);
```

The session takes every error of its camera for a lost camera. This is its own
choice, not something the plugin says: an error carries only its description,
and the plugin reports into the same stream errors of a single operation and
errors it calls recoverable. On Android a picture that failed reports
`The camera framework failed to fulfill the image capture request.`, and
CameraX reports an error it says it will recover from; on iOS a recording that
cannot add its audio output reports
`Unable to add Audio input/output to session capture`. The cost is that a
single failed picture ends in `Broken` as well, and the user taps Retry.

`_lose` writes the failure into the state at once with `externalSetState`,
rather than in a job that would wait behind the command under way. The commands
of the buttons need `Ready`, and those waiting in the queue do not start on a
lost camera. `_letGo` releases the camera in a job of its own at the front of
the queue: a `release()` of a screen that leaves may already wait there, finds
no camera in `Broken` and would end before the lost one is released. An error
that finds the state other than `Ready` changes nothing: a second error of the
same camera is not a second failure. The camera that a Galaxy A55 would give
back by itself is released too: an error does not say whether the loss lasts,
and Retry opens the camera when the user is back.

The session does not listen to `onCameraClosing`. A Galaxy A55 sends a closing
event when a recording starts, at a switch during a recording and after a stop,
and the camera stays open all the while; a camera taken away comes as an error.

`open()` does nothing when the camera is `Ready`. A camera opens in
`_initialize`, the end of `open()`, which watches it once it has opened; a
switch watches the camera again, since without a recording it gets a new id:

```dart
Job<void> open() => enqueue<CameraState, void>((ctx) async {
  if (ctx.state is Ready) return;
  ctx.emit(const Opening());
  final cameras = await ctx.join(availableCameras);
  if (cameras.isEmpty) {
    ctx.emit(const NoCamera());
    return;
  }
  await _initialize(ctx, cameras.first);
});

Future<void> _initialize(
  SoloContext<CameraState, CameraState> ctx,
  CameraDescription description,
) async {
  final camera = CameraController(description, ResolutionPreset.medium);
  try {
    await ctx.join(camera.initialize);
  } on CameraException catch (error) {
    ctx.emit(Broken(error));
    _letGo(camera);
    return;
  }
  _watch(camera);
  ctx.emit(
    Ready(camera: camera, flash: camera.value.flashMode, recording: false),
  );
}

Job<void> switchCamera() => enqueue<Ready, void>((ctx) async {
  final cameras = await ctx.join(availableCameras);
  final Ready(:camera, :recording) = ctx.state;
  final at = cameras.indexWhere((c) => c.name == camera.description.name);
  final next = cameras[(at + 1) % cameras.length];
  try {
    await ctx.join(() => camera.setDescription(next));
  } on CameraException catch (error) {
    if (recording) rethrow;
    ctx.emit(Broken(error));
    _letGo(camera);
    return;
  }
  _watch(camera);
});
```

A camera that fails to open is `Broken` as well, and `_letGo` releases what the
plugin's controller has created on the platform. A switch without a recording
is an opening too: the plugin releases the camera before it opens the next one,
so a switch that fails is `Broken` the same way. During a recording the plugin
does not release the camera, the camera goes on recording, and a failure stays
the error of the job with the state `Ready`. A stop that fails is the last way
to `Broken`:

```dart
Job<XFile?> stopRecording() => enqueue<Ready, XFile?>((ctx) async {
  final Ready(:camera, :flash, :recording) = ctx.state;
  if (!recording) return null;
  final XFile file;
  try {
    file = await ctx.join(camera.stopVideoRecording);
  } on CameraException catch (error) {
    ctx.emit(Broken(error));
    _letGo(camera);
    return null;
  }
  ctx.emit(Ready(camera: camera, flash: flash, recording: false));
  onCaptured(file);
  return file;
});
```

The plugin's controller turns `isRecordingVideo` off only after a stop that has
succeeded. After a failed one it believes it records for good: a new recording
throws, and a switch takes the way of a recording. `stopRecording` needs
`Ready`, and once it has emitted `Broken` its own calls through `ctx` give up
with `Cancelled`, so the release goes to a job of its own here too.

The screen shows `Broken` with a button that calls `open()`:

```dart
Broken(:final error) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('The camera failed: $error'),
      TextButton(
        key: const Key('retry'),
        onPressed: widget.session.open,
        child: const Text('Retry'),
      ),
    ],
  ),
),
```

Two taps of Retry made before the frame that takes the button away queue two
openings, and the second finds the camera open. The camera taken away and two
taps of Retry, with the fake platform on the Galaxy's rules:

```text
camera #1 error
state Broken
dispose #1 start
dispose #1 end
state Opening
create back #2
initialize #2 start
initialize #2 end
state Ready
```

`state Broken` comes right after the error, and the release follows it. The
opening starts once the lost camera is released, and the second tap leaves no
line.

## A denied permission

The user denies the app the camera or the microphone. The screen says which of
the two to allow. After a plain denial a Retry button asks again; when the
phone no longer asks, the screen says to allow it in Settings, and when the
policy of the device forbids it, the screen says that.

### The first attempt

The plugin asks for the permissions itself, while it creates the camera, and
`initialize` throws a `CameraException` whose code says what was denied. The
plugin's README lists six codes, from `CameraAccessDenied` to
`AudioAccessRestricted`, and its example catches them around `initialize` with
a message for each in a snack bar. Here the message stays on the screen as a
`Text`, and the screen disposes its controller when it leaves:

```dart
// The first attempt: one message, and nothing that asks again.
@override
void dispose() {
  camera.dispose();
  super.dispose();
}

Future<void> open() async {
  try {
    await camera.initialize();
  } on CameraException catch (e) {
    switch (e.code) {
      case 'CameraAccessDenied':
        show('You have denied camera access.');
      case 'CameraAccessDeniedWithoutPrompt':
        // iOS only
        show('Please go to Settings app to enable camera access.');
      case 'CameraAccessRestricted':
        // iOS only
        show('Camera access is restricted.');
      case 'AudioAccessDenied':
        show('You have denied audio access.');
      case 'AudioAccessDeniedWithoutPrompt':
        // iOS only
        show('Please go to Settings app to enable audio access.');
      case 'AudioAccessRestricted':
        // iOS only
        show('Audio access is restricted.');
      default:
        show(e);
    }
  }
}
```

The README marks the codes with `WithoutPrompt` and `Restricted` as iOS only
for now. The Android side of the plugin, `camera_android_camerax`, has
`CameraAccessDenied` and `AudioAccessDenied` for a denial, and
`CameraPermissionsRequestOngoing` for a request made while another is under
way. A Galaxy A55 asks a second time with a choice to deny and not ask again;
after that an opening shows no dialog and fails in about 200 ms with the same
`CameraAccessDenied`. On an iPhone 13 mini the first denial is
`CameraAccessDenied`, and the next opening fails without a dialog with
`CameraAccessDeniedWithoutPrompt`. A denied microphone on the iPhone is
`AudioAccessDenied`. A create that fails is the line `create back failed`. The
screen opened twice, the second time after "deny and don't ask again", with the
fake platform on the Galaxy's rules:

```text
create back failed
dispose #-1 start
dispose #-1 end
create back failed
dispose #-1 start
dispose #-1 end
```

Both openings say `You have denied camera access.`, and the screen has nothing
that asks again: the way back to the dialog is to leave the screen and open it
again. After "don't ask again" the Galaxy asks no more, and the message does
not send the user to Settings. On an iPhone 13 mini the second opening says
`Please go to Settings app to enable camera access.` Leaving the screen
disposes the controller, and the controller sends the platform `dispose` for
the camera `-1`: no camera was created, so the controller still has the id it
starts with, and its `dispose` calls the platform once `initialize` has
started.

### A denial the screen explains

`_initialize`, the end of `open()` and of `resume()`, tells a denial from a
failure by the code of the exception: the six codes of the README are `Denied`,
with the code, and any other is `Broken`. It lets the camera go only when the
platform has created one. The plugin's controller keeps the `cameraId` of `-1`
until `createCameraWithSettings` gives it an id, and a denial comes from there:

```dart
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

const _noCamera = -1;

const _denials = {
  'CameraAccessDenied',
  'CameraAccessDeniedWithoutPrompt',
  'CameraAccessRestricted',
  'AudioAccessDenied',
  'AudioAccessDeniedWithoutPrompt',
  'AudioAccessRestricted',
};
```

The plugin names `-1` `kUninitializedCameraId` and keeps the name for its own
tests, so the session has a constant of its own. A controller that was denied
is not disposed: its `dispose` is what would send the platform `dispose` for
`-1`. What it leaves is its listener of the orientation of the device, which it
starts before it creates the camera, one for each denied opening.

The screen shows `Denied` with what to allow and where, and with Retry for a
plain denial. Retry calls `open()`, as for `Broken`, and the plugin asks again
while it creates the camera:

```dart
Denied(:final code) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(_denial(code)),
      if (code.endsWith('Denied'))
        TextButton(
          key: const Key('retry'),
          onPressed: widget.session.open,
          child: const Text('Retry'),
        ),
    ],
  ),
),

String _denial(String code) {
  final device = code.startsWith('Audio') ? 'microphone' : 'camera';
  if (code.endsWith('WithoutPrompt')) {
    return 'Allow the app to use the $device in Settings.';
  }
  if (code.endsWith('Restricted')) {
    return 'The policy of this device does not let the app use the $device.';
  }
  return 'Allow the app to use the $device.';
}
```

A denial, a tap of Retry once the iPhone asks no more, and the screen left,
with the fake platform on the iPhone's rules:

```text
state Opening
create back failed
state Denied
state Opening
create back failed
state Denied
state Closed
```

The first `Denied` is `CameraAccessDenied` and says
`Allow the app to use the camera.` with Retry; the second is
`CameraAccessDeniedWithoutPrompt` and says
`Allow the app to use the camera in Settings.` with no button. The trace has no
`dispose` line: no camera was created, and the release of the screen finds
none. On an iPhone 13 mini the switch in Settings restarts the app.

On a Galaxy A55 Retry is the second opening, which shows the dialog again, and
a denial there is `CameraAccessDenied` again. After "deny and don't ask again"
Retry asks nothing: the opening fails without a dialog with the same code, and
the screen comes back with the same text and the same button. The Android side
of the plugin has no other code for this denial, so on Android the screen does
not send the user to Settings. `CameraAccessRestricted` and
`AudioAccessRestricted` come from the README: neither phone was put under a
policy that forbids the camera.

## Testing the app

The tests of the app run under `flutter test`, on `FakeCameraPlatform`: a
`CameraPlatform` of the tests with durations in place of the hardware. A call
that takes time on a phone writes a line where it starts and one where it ends,
and it ends when the test has moved the clock that far:

```dart
/// How long an opening takes.
Duration openTime = const Duration(milliseconds: 100);

/// How long a picture takes: from 0.5 to 3.4 s on the Galaxy, from 0.2
/// to 0.6 s on the iPhone.
Duration captureTime = const Duration(milliseconds: 300);

/// How long a switch of the camera during a recording takes.
Duration switchTime = const Duration(milliseconds: 150);

/// How long releasing a camera takes.
Duration disposeTime = const Duration(milliseconds: 50);

/// How long starting a recording takes: about a second on the Galaxy,
/// from 0.2 to 2.5 seconds on the iPhone.
Duration recordStartTime = const Duration(seconds: 1);

/// How long stopping a recording takes.
Duration stopTime = const Duration(milliseconds: 100);
```

Where two calls meet, the fake does what the phones did, and `phone` picks
between the Galaxy's rules and the iPhone's. On the Galaxy's a `dispose` under
a picture loses the picture, with the line `capture #N failed`; on the iPhone's
the `dispose` waits for the picture. `failOpen`, `failStop`, `failSwitch` and
`failCreate` make such a call fail while they are set, and `failFromOutside`
sends an error of the camera, as the platform does when another app takes it.

The tests keep the three rules of
[Testing](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/doc/testing.md):
the test moves the clock, with `pump` and the durations of the fake; it reads
`done` before it pumps, as
[Waiting for the job](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/doc/testing.md#waiting-for-the-job)
explains; and it releases and closes the controller in its body, as
[Moving the clock](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/doc/testing.md#moving-the-clock)
explains. Every test ends with `finish`:

```dart
Future<void> finish(WidgetTester tester, CameraDriver controller) async {
  final released = controller.release();
  await tester.pump(platform.disposeTime);
  await released;
}
```

`controller` is a `CameraDriver`, an interface of the tests with a method for
each command. For `CameraSession` its `release` reads `done` on the spot, while
`finish` has not pumped yet:

```dart
Future<void> release() async {
  // The release ends while the test pumps, where `expect` may not run.
  final released = await session.release().done;
  if (released is! Done<void>) throw StateError('release: $released');
  await session.close();
}
```

The same cases run against the bloc of the next section through a driver of its
own. One test for each situation of the page follows.

Rapid taps: a switch during a shot waits for the shot, on the Galaxy's rules,
where a `dispose` under the shot would lose it:

```dart
testWidgets('a switch during a shot waits for it', (tester) async {
  final controller = make(captured.add);
  controller.open();
  await tester.pump(platform.openTime);
  controller
    ..takePicture()
    ..switchCamera();
  await tester.pump(platform.captureTime);
  await tester.pump(platform.disposeTime);
  await tester.pump(platform.openTime);

  expect(
    platform.log,
    containsAllInOrder([
      'capture #1 end',
      'dispose #1 start',
      'dispose #1 end',
      'create front #2',
      'initialize #2 end',
    ]),
  );
  expect(platform.log, isNot(contains('capture #1 failed')));
  expect(captured, hasLength(1));
  await finish(tester, controller);
});
```

A switch during a recording: one video, from both cameras:

```dart
testWidgets('recording goes on across a switch', (tester) async {
  final controller = make(captured.add);
  controller.open();
  await tester.pump(platform.openTime);
  controller
    ..startRecording()
    ..switchCamera()
    ..stopRecording();
  await tester.pump(platform.recordStartTime);
  await tester.pump(platform.switchTime);
  await tester.pump(platform.stopTime);

  expect(
    platform.log,
    containsAllInOrder([
      'record #1 start',
      'switch #1 front end',
      'record #1 end',
    ]),
  );
  expect(captured.map((file) => file.path), ['/fake/video-1.mp4']);
  expect((controller.currentState as Ready).recording, isFalse);
  await finish(tester, controller);
});
```

Leaving the screen runs the whole app through its buttons. A camera screen
opened again while the one before it is still leaving opens the camera after
the release:

```dart
testWidgets('a new camera screen waits for the old one', (tester) async {
  await openCamera(tester);
  await until(tester, find.byKey(const Key('shutter')));
  await tester.pageBack();
  await tester.pump();
  await tester.tap(find.byKey(const Key('open-camera')));
  await tester.pumpAndSettle();
  await tester.pump(platform.disposeTime);
  await until(tester, find.byKey(const Key('shutter')));

  expect(
    platform.log,
    containsAllInOrder(['dispose #1 end', 'create back #2']),
  );
  expect(platform.openCameras, 1);
  expect(platform.hasPicture(2), isTrue);
  await goBack(tester);
  expect(platform.openCameras, 0);
});
```

Going to the background: the app reports its lifecycle through the binding of
the test, and the recording reaches `onCaptured` before the release:

```dart
testWidgets('recording is kept when the app leaves', (tester) async {
  final controller = await openShown(tester);
  controller.startRecording();
  await tester.pump(platform.recordStartTime);
  lifecycle(tester, leave);
  await tester.pump(platform.stopTime);
  await tester.pump(platform.disposeTime);

  expect(captured, hasLength(1));
  expect(captured.single.path, '/fake/video-1.mp4');
  expect(platform.openCameras, 0);
  expect(controller.currentState, isA<Closed>());
  expect(
    platform.log,
    containsAllInOrder(['record #1 end', 'dispose #1 start']),
  );
  lifecycle(tester, back);
  await tester.pump(platform.openTime);
  await tester.pumpWidget(const SizedBox());
  await finish(tester, controller);
});
```

Losing the camera: the error comes after the frame it is sent in, so `fail`
pumps twice, and the screen shows the failure before the camera is let go:

```dart
testWidgets('a camera taken away shows the failure', (tester) async {
  final controller = await openShown(tester);
  // The Galaxy reports a camera taken by another app as an error, with
  // no closing event.
  await fail(tester, 1, FakeCameraPlatform.takenOnAndroid);

  expect(
    controller.currentState,
    isA<Broken>().having(
      (s) => s.error,
      'error',
      FakeCameraPlatform.takenOnAndroid,
    ),
  );
  expect(retry, findsOneWidget);
  await tester.pump(platform.disposeTime);
  expect(platform.log, contains('dispose #1 end'));
  expect(platform.openCameras, 0);
  await tester.pumpWidget(const SizedBox());
  await finish(tester, controller);
});
```

A denied permission: a denial, Retry, and a denial the iPhone no longer asks
about, with no camera created and none released:

```dart
testWidgets('retry asks again, and the next answer shows (iPhone)', (
  tester,
) async {
  platform
    ..phone = FakePhone.iphone
    ..failCreate = FakeCameraPlatform.deniedOnIphone;
  final controller = await openShown(tester);
  await tester.pump();
  platform.failCreate = FakeCameraPlatform.deniedWithoutPromptOnIphone;
  await tester.tap(retry);
  await tester.pump();
  await tester.pump();

  expect(
    controller.currentState,
    isA<Denied>().having(
      (s) => s.code,
      'code',
      'CameraAccessDeniedWithoutPrompt',
    ),
  );
  expect(find.textContaining('Settings'), findsOneWidget);
  expect(retry, findsNothing);
  expect(platform.log, ['create back failed', 'create back failed']);
  await tester.pumpWidget(const SizedBox());
  await finish(tester, controller);
});
```

## The same screen on bloc

`CameraBloc` is the controller of the camera screen on bloc: the same states,
an event for each command of `CameraSession`, and `BlocCameraScreen` with
`BlocProvider` and `BlocBuilder` over the same buttons. It passes the cases of
the previous section on the same fake platform, the run of the app through its
buttons among them. The code is
[`bloc_camera.dart`](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/camera_example/test/support/bloc_camera.dart)
in the tests of the app.

The commands share one handler with `sequential()` of `bloc_concurrency`: a
switch waits for the shot under way, and a stop for the switch. A failure the
platform reports has a handler of its own, with the default transformer, which
runs it at once:

```dart
CameraBloc({required this.onCaptured}) : super(const Closed()) {
  // One handler for every command: a switch waits for the shot under way,
  // a stop for the switch, and a release for whatever runs.
  on<CameraCommand>(_run, transformer: sequential());
  // A failure has a handler of its own, with the concurrent transformer:
  // it shows at once, not after the command under way.
  on<CameraLost>(_lose);
}
```

`droppable()` on a handler of its own would drop a second tap of the shutter,
and the switch would no longer wait for the shot. In the shared handler a
transformer sees a tap only when the command before it is over, and by then the
second tap is in the queue. The bloc drops it in `add`:

```dart
/// A [TakePicture] waits in the queue or runs: a tap during a shot is
/// dropped. The flag is set in [add], since a transformer sees an event
/// only when the one before it is over.
bool _shooting = false;

@override
void add(CameraEvent event) {
  if (event is TakePicture) {
    if (_shooting) return;
    _shooting = true;
  }
  super.add(event);
}
```

A loss changes the state while a command waits on the camera. A command on a
ready camera keeps the state it started from and looks at it again after every
`await`:

```dart
Future<void> _startRecording(Emitter<CameraState> emit) async {
  final ready = state;
  if (ready is! Ready || ready.recording) return;
  await ready.camera.startVideoRecording();
  if (state != ready) return;
  emit(Ready(camera: ready.camera, flash: ready.flash, recording: true));
}
```

The command under way may still use the lost camera, so `_lose` puts `LetGo` in
the queue after it. A `Release` already waiting there runs first, and it finds
the camera in `_camera`, which holds it after the state no longer does:

```dart
/// The camera the platform holds for this bloc, lost or not: a [Release]
/// that runs after a loss still finds it, before the [LetGo] of the loss.
CameraController? _camera;

void _lose(CameraLost event, Emitter<CameraState> emit) {
  if (state is! Ready) return;
  emit(Broken(event.description));
  add(const LetGo());
}

Future<void> _letGo() async {
  final camera = _camera;
  _camera = null;
  await camera?.dispose();
}
```

The owner waits for the release through a `Completer` in the event. `close()`
stops the errors of the platform first: an error after it would add an event to
a closed bloc, and `add` throws there:

```dart
Future<void> release() {
  final release = Release(Completer());
  add(release);
  return release.done.future;
}

@override
Future<void> close() {
  unawaited(_errors?.cancel());
  return super.close();
}

case Release(:final done):
  try {
    await _letGo();
    emit(const Closed());
    done.complete();
  } catch (error, stackTrace) {
    done.completeError(error, stackTrace);
  }
```

`BlocProvider` closes the bloc it made without waiting, and it knows nothing of
the screen before it. `BlocCameraScreen` owns the bloc through the same
`AsyncDataScope` as `CameraScreen`, with its `scopeKey` and its timeouts, and
hands it down with `BlocProvider.value`. The scope waits for the release and
not for `close()`: the camera is free once the release ends, and under the fake
clock of `testWidgets` the `close()` of this bloc does not return:

```dart
disposeData: (bloc) async {
  try {
    await bloc.release();
  } finally {
    // Not awaited: the camera is free by now, and under the fake clock
    // of a widget test `close` does not return.
    unawaited(bloc.close());
  }
},
```

What each situation takes, on bloc and on solo:

| Situation | bloc | solo | What the tests needed |
| --- | --- | --- | --- |
| Rapid taps | `on<CameraCommand>` with `sequential()`; `_shooting`, set in `add` | the queue of `Solo`; `Policy.droppable` on the key of `takePicture` | nothing more |
| A switch during a recording | the same handler | the same queue | nothing more |
| Leaving the screen | `Release` with a `Completer`; `AsyncDataScope` with a `scopeKey`; `BlocProvider.value` | `release()`; `AsyncDataScope` with a `scopeKey` | bloc: `close()` not awaited |
| Going to the background | `Suspend` and `Resume` in the queue | `suspend()` and `resume()` in the queue | for a failed stop, bloc: the bloc made in `runZonedGuarded`; solo: `Solo.unansweredHandler` |
| Losing the camera | `on<CameraLost>` of its own; `if (state != ready) return;` 8 times; `LetGo` in the queue; `_camera`; `close()` that cancels `_errors` | `externalSetState`; commands on `Ready` with `ctx.join`; `_letGo` with `first: true`; `onClose` that cancels `_errors` | for a failed switch during a recording, bloc: the bloc made in `runZonedGuarded`; solo: `Solo.unansweredHandler` |
| A denied permission | `_initialize`, which awaits `dispose` itself | `_initialize`, with `_letGo` | nothing more |

The bloc's tests are the cases of the previous section and one of their own: an
error of the camera after `close()` changes nothing.
