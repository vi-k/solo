# solo_lints example

A recorder built on solo: a job opens a device, writes chunks to it, flushes it
in cleanup and resets it when a write fails. The job has three mistakes, and
the plugin reports each of them.

Name the plugin in `analysis_options.yaml` at the root of the package. The
warnings are on as soon as the plugin is named, and `catch_without_check` is a
lint, turned on by name:

```yaml
plugins:
  solo_lints:
    version: ^0.2.0
    diagnostics:
      catch_without_check: true
```

`lib/recorder.dart`, with the rule that reports each line in a comment:

```dart
import 'package:solo/solo.dart';

abstract interface class Device {
  Future<void> write(List<int> chunk);

  Future<void> flush();

  Future<void> reset();

  Future<void> close();
}

sealed class RecorderState {}

final class Idle extends RecorderState {}

final class Broken extends RecorderState {
  Broken(this.error);

  final Object error;
}

final class Recorder extends Solo<RecorderState> {
  Recorder(this._open) : super(Idle());

  final Future<Device> Function() _open;

  Job<void> record(List<List<int>> chunks) =>
      enqueue<RecorderState, void>((ctx) async {
        final device = await ctx.join(_open);
        ctx.onDispose(device.close); // release_on_the_call
        ctx.onDispose(() async {
          await ctx.join(device.flush); // ctx_in_cleanup
        });
        try {
          for (final chunk in chunks) {
            await ctx.join(() => device.write(chunk));
          }
        } on Object catch (error) { // catch_without_check
          await device.reset();
          ctx.emit(Broken(error));
          rethrow;
        }
      });
}
```

`dart analyze` and the editor report the three lines:

- `release_on_the_call`: a cancellation during the open throws before the next
  line, and the open device is never closed.
- `ctx_in_cleanup`: cleanup runs after the body, where `join` throws, so the
  device is never flushed.
- `catch_without_check`: the catch takes a cancellation too, and a cancelled
  recording resets a device that nothing broke.

The same `record` with the three fixed, on which the plugin reports nothing:

```dart
  Job<void> record(List<List<int>> chunks) =>
      enqueue<RecorderState, void>((ctx) async {
        final device = await ctx.join(
          _open,
          dispose: (device) => device.close(),
        );
        ctx.onDispose(() async {
          await device.flush();
        });
        try {
          for (final chunk in chunks) {
            await ctx.join(() => device.write(chunk));
          }
        } on Object catch (error) {
          ctx.check();
          await device.reset();
          ctx.emit(Broken(error));
          rethrow;
        }
      });
```

The release goes to the call that brings the device, cleanup waits with a plain
`await`, and the catch asks the job first. The README of the package describes
every rule, and the quick fixes the editor offers for `release_on_the_call` and
`catch_without_check` make the first and the last of these changes.
