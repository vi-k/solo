# solo example

A fake camera controller: hardware that answers late and may break on its
own, and a controller that keeps the state honest. It shows a sealed state
hierarchy, working types, job keys and policies, cooperative cancellation
and an observer that prints every job.

Run it from this directory:

```sh
dart pub get
dart run bin/main.dart
```

The output is one line per job and per state change, printed by the
observer in `bin/main.dart`:

```text
[init] started
state: Preparing()
state: Ready(zoom: 1.0, focusPoint: null, paused: false)
[init] finished Done(null)
[setZoom: zoom: 2.0] started
...
```

The controller itself is in `lib/src/camera_controller.dart`, its state in
`lib/src/camera_state.dart`, and the tests in
`test/camera_controller_test.dart` show how to drive it with `fake_async`.
