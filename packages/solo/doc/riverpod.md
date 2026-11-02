# solo under riverpod

An app built on riverpod keeps riverpod: the graph of providers, the cache, the
`AsyncValue` a screen switches on. This page is about what goes under a
provider when the work there has an order to keep and a resource to close. A
`solo` controller lives in a provider: the provider makes it, the screen reads
its state through it, and the provider's disposal closes it. The code runs
against riverpod 3 in pure Dart: `flutter_riverpod` hands out the same `Ref`.

Each section opens with the version riverpod's own documentation leads to and
shows what that code does. The states and traces under the fragments are what
the code prints when it runs.

## A controller under a provider

The controller is a camera. `open()` publishes `Opening`, opens the device and
publishes `Ready` with it:

```dart
sealed class CameraState {
  const CameraState();
}

final class Closed extends CameraState {
  const Closed();
}

final class Opening extends CameraState {
  const Opening();
}

final class Ready extends CameraState {
  const Ready(this.device);

  final Device device;
}
```

```dart
final class Camera extends Solo<CameraState> {
  Camera() : super(const Closed());

  Job<void> open() => enqueue<CameraState, void>(
    key: #camera,
    policy: Policy.restart,
    ifCancelled: (state, cancelled) => const Closed(),
    (ctx) async {
      ctx.emit(const Opening());
      final device = await ctx.join(
        Device.open,
        discard: (device) => device.close(),
      );
      ctx.emit(Ready(device));
    },
  );
}
```

`Device` stands for the platform's camera: opening it takes 50 ms, and
`close()` releases it. `ctx.join` waits for the opening even when the job is
cancelled meanwhile, and its `discard` closes a device that arrives for a job
that did not end `Done`. `ifCancelled` puts the camera back to `Closed` when
the job is cancelled — by the next `open()`, under `Policy.restart`, or by the
controller's `close()`. The traces show the device by its number: `Ready(1)`
holds the first one opened.

The provider makes the controller and closes it on disposal. The screen needs
the state as well, and the controller calls its listeners on every change.
`ref.notifyListeners` is what riverpod gives a provider whose object changes in
place, so the controller's listener is that call.

### The first attempt

```dart
// The first attempt: the controller calls a Ref already disposed.
final camera = Provider.autoDispose<Camera>((ref) {
  final controller = Camera()..addListener(ref.notifyListeners);
  ref.onDispose(() => unawaited(controller.close()));
  return controller;
});
```

The screen opens the camera and leaves 10 ms later, while the device is still
opening:

```text
screen left
zone: Cannot use the Ref of Provider<Camera> after it has been disposed.
```

The screen was the provider's last listener, so riverpod disposes the provider,
and `onDispose` closes the controller. `close()` cancels the opening, and its
`ifCancelled` publishes `Closed`. The controller's listener is still
`ref.notifyListeners` of a `Ref` disposed a moment ago; the call throws, and
the controller hands a listener's error to the zone.

### Removing the listener

```dart
final camera = Provider.autoDispose<Camera>((ref) {
  final controller = Camera()..addListener(ref.notifyListeners);
  ref.onDispose(() {
    controller.removeListener(ref.notifyListeners);
    unawaited(controller.close());
  });
  return controller;
});

// The screen: ref.watch(camera.select((camera) => camera.currentState))
```

The same screen leaves 10 ms in. `outcome` is that of the job `open()`
returned, `states` are what the screen saw, and `device` is what happened to
the device:

```text
screen left
outcome: Cancelled(closed)
states: Closed, Opening
device: open 1 start, open 1 done, close 1
```

The listener goes before the controller closes, and the `Closed` of the
cancellation reaches no one: the screen is gone with the provider.
`removeListener` compares with `==`, and two tear-offs of `ref.notifyListeners`
are equal, so naming the method twice removes what the first line added.

The screen reads the state with `select`: the provider itself changes nothing
but notifies, and `select` hands the screen each new `currentState`. A
`StreamProvider` over the stream of `SoloStream` would not do: the stream
carries changes, not the state the camera is in when the screen subscribes. In
Flutter the screen can also take the controller with `ref.watch(camera)` and
build from it with `SoloBuilder` of
[`flutter_solo`](https://pub.dev/packages/flutter_solo).
