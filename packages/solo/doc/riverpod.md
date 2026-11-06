# solo under riverpod

An app built on riverpod keeps riverpod: the graph of providers, the cache, the
`AsyncValue` a screen switches on. This page is about what goes under a
provider when the work there has an order to keep and a resource to close. A
`solo` controller lives in a provider: the provider makes it, the screen reads
its state through it, and the provider's disposal closes it. The code runs
against riverpod 3.5 in pure Dart: `flutter_riverpod` hands out the same `Ref`.

Where riverpod leaves the work to the app, this page and its neighbours take it
apart:

| The trap in riverpod | What answers it | Where |
| --- | --- | --- |
| A `Ref` used after an `await` in a method of a notifier, a field checked against the current call | A method of a controller holds no `Ref`, and the `emit` of a cancelled job never reaches the state | [A notifier that starts again](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/riverpod-and-bloc.md#a-notifier-that-starts-again) |
| A provider disposed while its work runs | `ref.onDispose(job.cancel)` | [A provider that is gone](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/riverpod-and-bloc.md#a-provider-that-is-gone) |
| A debounce made of a flag and a throw after the disposal | `ctx.pause` in a job under the provider; in `solo`, `accumulate` with `debounce` | [A pause of the job](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/time.md#a-pause-of-the-job), [A search that fires on every keystroke](accumulation.md#a-search-that-fires-on-every-keystroke) |
| The state of a controller on the screen | `ref.notifyListeners` and `select` | [A controller under a provider](#a-controller-under-a-provider) |
| A resource taken before its cleanup is registered | `discard` where it is taken, `onClose` for what the controller keeps | [A camera closed when the screen goes](#a-camera-closed-when-the-screen-goes) |
| A form sent twice | `Policy.droppable` | [A form sent once](#a-form-sent-once) |

The debounce of riverpod's [guide](https://riverpod.dev/docs/how_to/cancel)
throws `Exception('Cancelled')` after the disposal. An app that wants to tell
that cancellation from a failure by its type throws a class of its own;
`async_job` gives every piece of code that type already: `Cancelled`.

Each section opens with the version riverpod's own API leads to and shows what
that code does. The states and traces under the fragments are what the code
prints when it runs.

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
opening. `outcome` is that of the job `open()` returned, `states` are what the
screen saw, and `device` is what happened to the device:

```text
screen left at 10 ms
outcome: Cancelled(closed)
states: Closed, Opening
device: open 1 start, open 1 done, close 1
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

The same screen leaves 10 ms in:

```text
screen left at 10 ms
outcome: Cancelled(closed)
states: Closed, Opening
device: open 1 start, open 1 done, close 1
zone: nothing
```

The listener goes before the controller closes, and the `Closed` of the
cancellation reaches no one: the screen is gone with the provider.
`removeListener` compares with `==`, and two tear-offs of `ref.notifyListeners`
are equal, so naming the method twice removes what the first line added.

The screen reads the state with `select`: the provider itself changes nothing
but notifies, and `select` hands the screen each new `currentState`. A
`StreamProvider` over the stream of `SoloStream` would not do: the stream
carries changes, not the state the camera is in when the screen subscribes. In
Flutter the screen can also take the controller with
`ref.watch(camera.select((camera) => camera))` and build from it with
`SoloBuilder` of [`flutter_solo`](https://pub.dev/packages/flutter_solo). The
`select` matters: the bridge notifies the listeners of `camera` on every change
of state, and a widget with `ref.watch(camera)` would rebuild with each of
them.

## A camera closed when the screen goes

The screen opens the camera when it appears and closes it when it goes,
whichever moment that is: while the device is still opening or after it opened.
Without the controller, riverpod holds the device in a provider of its own and
closes it in `onDispose`.

### The first attempt

```dart
// The first attempt: the cleanup is registered after the await.
final camera = FutureProvider.autoDispose<Device>((ref) async {
  final device = await Device.open();
  ref.onDispose(device.close);
  return device;
});
```

The screen leaves 10 ms in, while the device opens; an observer of the
container prints what fails:

```text
screen left at 10 ms
device: open 1 start, open 1 done
observer: nothing
```

The device stays open. riverpod disposes the provider when the screen leaves,
and the `onDispose` that would close the device is not registered yet: the line
that registers it waits behind the `await`. When the opening ends, the provider
is gone, and that line throws `UnmountedRefException`. Since riverpod 3.5.0 a
`ProviderObserver` does not hear a provider that fails after its disposal, and
nothing reports the open device; before 3.5.0 `providerDidFail` received the
exception, as a `Ref` used after its disposal.

### A flag before the await

riverpod's guide to [cancelling](https://riverpod.dev/docs/how_to/cancel) has
the provider note its disposal before the first `await` and check after it:

```dart
final camera = FutureProvider.autoDispose<Device>((ref) async {
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final device = await Device.open();
  if (disposed) {
    await device.close();
    throw StateError('the screen left while the camera opened');
  }
  ref.onDispose(device.close);
  return device;
});
```

The screen leaves 10 ms in, and then, with a fresh provider, 80 ms in:

```text
screen left at 10 ms
device: open 1 start, open 1 done, close 1
screen left at 80 ms
device: open 1 start, open 1 done, close 1
```

This works: the device is closed on either side of the opening. The cleanup
lives in two places, the check after the `await` and the `onDispose` that
follows it, and the order is the author's to keep: the flag is registered
before the `await`.

### Leaving after the camera opened

Under the controller of the first section, leaving while the device opens
closes it: `discard` takes the device that arrives for a cancelled job. The
same screen leaving 80 ms in, after the opening:

```text
screen left at 80 ms
outcome: Done(null)
states: Closed, Opening, Ready(1)
device: open 1 start, open 1 done
```

The device stays open. `close()` cancels the controller's jobs, and by then the
opening has ended `Done`: there is nothing left to cancel. The device in
`Ready` is the controller's now, not a job's, and `close()` does not close it.

### onClose

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

  @override
  void onClose() {
    if (currentState case Ready(:final device)) {
      unawaited(device.close());
    }
  }
}
```

The screen leaves 10 ms in, and then, with a fresh provider, 80 ms in:

```text
screen left at 10 ms
outcome: Cancelled(closed)
states: Closed, Opening
device: open 1 start, open 1 done, close 1
screen left at 80 ms
outcome: Done(null)
states: Closed, Opening, Ready(1)
device: open 1 start, open 1 done, close 1
```

`onClose` runs once, when every job of the controller is over, and closes the
device the state holds. Leaving during the opening goes as before: the job ends
`Cancelled`, `ifCancelled` publishes `Closed`, and `discard` closes the device.
Neither a flag nor the order of the registrations is left to the author:
`discard` at the place the device is taken holds the race between the leave and
the opening, and `onClose` holds what the controller keeps after that. A
controller whose closing is a job of its own, one that waits for the hardware,
is in [Disposing of the camera](camera.md#disposing-of-the-camera).

## A form sent once

The form sends a message to the server, and a second tap while the message is
on its way must not send it again. `send` stands for the API: it answers in 30
ms with a receipt numbered by its call.

### The first attempt

riverpod 3 has mutations for the submission of a form, still experimental, in
`package:riverpod/experimental/mutation.dart`. Their documentation swaps the
button for a progress indicator while the mutation is `MutationPending`. A
caller that does not go through that button reads the same state before it runs
the mutation:

```dart
// The first attempt: each caller checks the mutation before it runs.
final sendMessage = Mutation<String>();

Future<String?> submit(ProviderContainer container, String text) async {
  if (container.read(sendMessage) is MutationPending) return null;
  return sendMessage.run(container, (_) => send(text));
}
```

In Flutter the same lines take the `WidgetRef` of the screen. The screen sends
`'hi'`, and then `'bye'` while `'hi'` is on its way:

```text
right after the first: MutationPending<String>()
first: sent hi #1
second: null
calls: 1
```

The guard works: `run` puts the mutation into `MutationPending` before it
returns, and the second call finds it there. What sets it apart from the answer
below is narrow. The second caller gets `null`, not the receipt of the message
that went. And the guard lives in each caller, not in the mutation. Its
documentation says: "Currently, mutations do not restrict concurrent calls in
any capacity." A caller without the check sends the message a second time.

### Policy.droppable

The form is a controller, under a provider the way the camera is in the first
section:

```dart
sealed class MessageState {
  const MessageState();
}

final class Editing extends MessageState {
  const Editing();
}

final class Sent extends MessageState {
  const Sent(this.receipt);

  final String receipt;
}
```

```dart
final class MessageForm extends Solo<MessageState> {
  MessageForm() : super(const Editing());

  Job<String> submit(String text) => enqueue<MessageState, String>(
    key: #submit,
    policy: Policy.droppable,
    (ctx) async {
      final receipt = await ctx.join(() => send(text));
      ctx.emit(Sent(receipt));
      return receipt;
    },
  );
}
```

The same `'hi'` and `'bye'`, each awaiting the `value` of the job its `submit`
returned:

```text
same job: true
first: sent hi #1
second: sent hi #1
calls: 1
state: Sent(sent hi #1)
```

A call that comes while a job of its key runs gets that job back under
`Policy.droppable`, and the API is called once. Both callers await the `value`
of one job and get the receipt. A caller that goes on with `then` takes the job
through `shared()` instead, as [Queue and policies](jobs.md#queue-and-policies)
explains. The send goes through `ctx.join`: a message is work that has to
finish before the queue moves on. Under `ctx.abandonable` a cancelled send
would go on after its job ended, and the next `submit` would start a second one
while the first is still on its way.

The price of `droppable` is the other side of the same rule: a second call with
other arguments gets the first job as well. The `'bye'` typed while `'hi'` was
on its way is never sent, and its caller gets the receipt of `'hi'`.

## What you take on

The controller adds a layer. The provider holds the controller, the controller
holds the state, and the state is a type of the controller, not an
`AsyncValue`. The bridge of the first section is code of the app, one per
controller, and the `removeListener` in its `onDispose` is not optional.

The provider decides how long the controller lives. A `ref.read` of an
`autoDispose` provider with no listener makes a controller and disposes of it
right away, and the job it was asked for ends `Cancelled`:

```text
read without a listener
outcome: Cancelled(closed)
device: open 1 start, open 1 done, close 1
```

A rebuild of the provider closes the controller and cancels its jobs:
`ref.invalidate`, or a change in a provider the bridge reads with `ref.watch`.
Here the screen stays while the camera is open, and the provider is
invalidated; the screen gets a new controller, in `Closed`:

```text
camera invalidated
states: Closed, Opening, Ready(1), Closed
device: open 1 start, open 1 done, close 1
the first controller finished: true
```

riverpod does not retry a failed job of the controller: its retry is for a
provider that fails to build, and the provider of a controller does not fail. A
retry is written in the body of the job, as
[Retrying a failed call](errors.md#retrying-a-failed-call) shows.

`Policy.droppable` loses the arguments of a second call, as the form shows. And
`solo` is one more dependency with a model of its own: a queue, keys, policies,
state rules.

`solo` is not needed for one operation under a provider: that is a job of
`async_job`, as
[With riverpod and bloc](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/riverpod-and-bloc.md)
shows. Nor for a request riverpod keeps per argument with a provider family:
riverpod alone does that.
