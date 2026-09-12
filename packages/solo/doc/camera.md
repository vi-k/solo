# Camera example

The following example combines state rules, queue policies and explicit device
cleanup. It uses a separate state hierarchy from the profile example.
`NotDisposed` groups every state in which hardware operations may still be
performed:

```dart
sealed class CameraState {
  const CameraState();
}

sealed class NotDisposed extends CameraState {
  const NotDisposed();
}

final class Initial extends NotDisposed {
  const Initial();
}

final class Preparing extends NotDisposed {
  const Preparing();
}

final class Ready extends NotDisposed {
  final double zoom;
  final bool paused;

  const Ready({this.zoom = 1, this.paused = false});

  Ready copyWith({double? zoom, bool? paused}) =>
      Ready(zoom: zoom ?? this.zoom, paused: paused ?? this.paused);
}

final class Disposed extends CameraState {
  const Disposed();
}
```

`FakeCameraHardware` and `Photo` are supplied by the runnable
[`example/`](../example) package. The controller below shows its main
operations:

```dart
enum CameraKey { init, closeCamera, setZoom, takePhoto, dispose }

final class CameraController extends Solo<CameraState> {
  final FakeCameraHardware hw;

  CameraController(this.hw) : super(const Initial());

  Job<void> init() => run<NotDisposed, void>(
        key: CameraKey.init,
        policy: Policy.droppable,
        canStart: (state) => state is Initial,
        (ctx) async {
          ctx.emit(const Preparing());
          await ctx.join(hw.open);
          ctx.emit(const Ready());
        },
      );

  Job<void> setZoom(double zoom) => run<Ready, void>(
        key: CameraKey.setZoom,
        policy: Policy.replace,
        describe: () => 'zoom: $zoom',
        canStart: (state) => !state.paused,
        (ctx) async {
          await ctx.join(() => hw.setZoom(zoom));
          ctx.emit(ctx.state.copyWith(zoom: zoom));
        },
      );

  Job<Photo> takePhoto() => run<Ready, Photo>(
        key: CameraKey.takePhoto,
        policy: Policy.droppable,
        canStart: (state) => !state.paused,
        (ctx) async {
          final photo = await ctx.join(hw.capture);
          queue.clear();
          ctx.log('captured $photo');
          return photo;
        },
      );

  Job<void> _closeCameraJob() => job<NotDisposed, void>(
        key: CameraKey.closeCamera,
        cancellable: false,
        (ctx) async => hw.close(),
      );

  Job<void> dispose() {
    queue.clear(force: true);
    current?.cancel();
    return run<CameraState, void>(
      key: CameraKey.dispose,
      policy: Policy.droppable,
      cancellable: false,
      (ctx) async {
        if (ctx.state is Disposed) {
          return;
        }
        if (ctx.state is! Initial) {
          await ctx.run(_closeCameraJob());
        }
        ctx.emit(const Disposed());
      },
    );
  }
}
```

`init` starts only from `Initial`, but uses `NotDisposed` as its working type
so it can continue after emitting `Preparing`. `setZoom` replaces queued zoom
requests while allowing the running request to finish.

After taking a photo, `takePhoto` clears cancellable queued commands. This
example treats commands accumulated during capture as belonging to that
capture; clearing prevents them from affecting the next one. The running job is
unaffected by `queue.clear()`.

`dispose()` is an application operation that closes the hardware and publishes
`Disposed`. It clears pending work and requests cancellation of the running job
before queuing its own non-cancellable teardown. The child `_closeCameraJob`
also refuses ordinary cancellation. The controller's `close()` is a separate
lifecycle operation, so await device disposal before closing the controller:

```dart
final camera = CameraController(FakeCameraHardware());
await camera.init().done;

camera.setZoom(2); // no await needed, and no lint about it

final photo = await camera.takePhoto().value;

switch (await camera.dispose().done) {
  case Done():
    print('disposed');
  case Cancelled(:final reason):
    print('cancelled: $reason');
  case Failed(:final error):
    print('failed: $error');
}

await camera.close();
```

The runnable example extends this controller with a `Broken` state, reopening,
pause, resume and focus operations. Its fake hardware responds with delays and
can fail independently. Tests check ordered event journals, and `bin/main.dart`
prints one while the scenario runs:

```sh
cd example
dart pub get
dart run bin/main.dart
dart test
```
