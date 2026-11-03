# async_job_lints example

A recorder built on async_job: a job opens a device, writes chunks to it,
flushes it in cleanup and resets it when a write fails. The job has three
mistakes, and the plugin reports each of them.

Name the plugin in `analysis_options.yaml` at the root of the package. The
warnings are on as soon as the plugin is named, and `catch_without_check` is a
lint, turned on by name:

```yaml
plugins:
  async_job_lints:
    version: ^0.1.0
    diagnostics:
      catch_without_check: true
```

`lib/recorder.dart`, with the rule that reports each line in a comment:

```dart
import 'package:async_job/async_job.dart';

abstract interface class Device {
  static late Future<Device> Function() open;

  Future<void> write(List<int> chunk);

  Future<void> flush();

  Future<void> reset();

  Future<void> close();
}

Job<void> record(List<List<int>> chunks) => Job<void>((ctx) async {
  final device = await ctx.join(Device.open);
  ctx.onDispose(device.close); // release_on_the_call
  ctx.onDispose(() async {
    await ctx.join(device.flush); // ctx_in_cleanup
  });
  try {
    for (final chunk in chunks) {
      await ctx.join(() => device.write(chunk));
    }
  } on Object { // catch_without_check
    await device.reset();
    rethrow;
  }
});
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
Job<void> record(List<List<int>> chunks) => Job<void>((ctx) async {
  final device = await ctx.join(
    Device.open,
    dispose: (device) => device.close(),
  );
  ctx.onDispose(() async {
    await device.flush();
  });
  try {
    for (final chunk in chunks) {
      await ctx.join(() => device.write(chunk));
    }
  } on Object {
    ctx.check();
    await device.reset();
    rethrow;
  }
});
```

The release goes to the call that brings the device, cleanup waits with a plain
`await`, and the catch asks the job first. The README of the package describes
every rule, and the quick fixes the editor offers for `release_on_the_call` and
`catch_without_check` make the first and the last of these changes.
