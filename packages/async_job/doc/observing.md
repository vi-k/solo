# Observing

A job's outcome says how the job ended. A `JobObserver` hears the rest: when
the job starts and ends, what its body logs, and the errors that no outcome
carries. Where those errors go, and how an observer answers for them, is the
subject of [Errors](errors.md).

## Observer

A job loads a number. Its observer prints how the job ended and what the body
logged:

```dart
import 'package:async_job/async_job.dart';

final class Log extends JobObserver {
  @override
  void onFinish(Job<Object?> job) => print('$job: ${job.outcome}');

  @override
  void onLog(Job<Object?> job, Object? message) {
    final data = message is Object? Function() ? message() : message;
    print('$job: $data');
  }
}

final job = Job<int>(
  key: 'load',
  observer: Log(),
  (ctx) async {
    ctx.log('loading');
    return ctx.abandonable(load);
  },
);
```

```text
Job(load): loading
Job(load): Done(3)
```

The hooks of an observer, and when the job calls them:

| Hook | When it runs |
| --- | --- |
| `onStart` | the body starts; only for a job that starts |
| `onFinish` | the job has its outcome; for every job, even one cancelled before it started |
| `onError` | the job catches an error, except its own cancellation |
| `onLog` | the body calls `ctx.log(message)` |
| `onUnanswered` | of an observer that mixes in `JobAnswerer`: a failure no outcome carries, after `onError`, and a `Failed` nobody observes, a microtask after the job ends; see [Answering for errors](errors.md#answering-for-errors) |

The four hooks of `JobObserver` do nothing by default, so an observer overrides
only the hooks it needs. `onUnanswered` is the exception: by default it hands
the failure to the zone, as if no `JobAnswerer` were there. A class that
already extends another class mixes the observer in with `with JobObserver`, or
`with JobObserver, JobAnswerer`, and overrides the hooks the same way.

Whoever runs the job passes the observer when creating it. The children the job
runs inherit it unless they have their own. A continuation made with `then`
takes only the observer passed to `then`.

If a hook throws, its error goes to the current zone, and nothing else changes:
the job ends as it would have, and the other hooks are still called. A
`Cancelled` thrown by a hook does not reach the zone and does not cancel the
job. To cancel the job from a hook, call `job.cancel()`; the job is cancelled
as it would be from anywhere else. One hook adds a step: an `onUnanswered` that
throws first hands the zone the error it was asked to answer for, as
[Answering for errors](errors.md#answering-for-errors) shows.

### A job's name

When you create a job, you can give it a `key` and a `describe` callback. They
make the job's string form, the name that the lines of an observer print:

| Given | String form |
| --- | --- |
| A `key` | `Job($key)` |
| A `key` and a `describe` that returns a description that is not empty | `Job($key: $description)` |
| Such a `describe` and no `key` | `Job($description)` |
| Neither | `Job()` |

Use `key` to identify the job in logs or in the scheduling rules of a library,
such as the queue policies of `solo`. `describe` adds details to it.

A `key` whose `toString` throws, or a `describe` that throws, prints as a mark
in its place: `Job(load: <describe threw StateError>)`. The core names jobs in
its own error messages, and a broken name does not replace the message. The
error of the name itself is still reported, in two places. When the core names
a child in its parent's cancellation, the error goes the way of an error from
outside the body, as the table in [Rare routes](errors.md#rare-routes) shows.
When a line of [the debug channel](errors.md#the-debug-channel) names the job,
the error goes to the current zone, as the error of a hook does.

### Timing a cancellation

A cancelled job should end soon. One that goes on is busy with work the user
has already given up on. An observer finds such jobs by timing how long each
one runs past its cancellation:

```dart
final class SlowCancellations extends JobObserver {
  final _since = Expando<Stopwatch>('cancellation');

  @override
  void onStart(Job<Object?> job) =>
      job.whenCancelled((_) => _since[job] = Stopwatch()..start());

  @override
  void onFinish(Job<Object?> job) {
    final watch = _since[job];
    if (watch != null) {
      print('$job ran ${watch.elapsedMilliseconds} ms past its cancellation');
    }
  }
}
```

`Job.whenCancelled`, registered in `onStart`, fires when the job accepts a
cancellation. `onFinish` runs when the outcome arrives. The time between them
is how long the job ran past its cancellation, children and cleanup included.
Three things decide the count:

- A body that waits on something slow with a bare `await` adds the rest of that
  wait to the count. The same call through `ctx.abandonable` shows 0 ms.
- The count starts when the job accepts the cancellation, not at `cancel()`: no
  hook hears that a cancellation was asked for. `ctx.uncancellable` holds a
  cancellation back, and the job accepts it when the section ends: a 100 ms
  section cancelled 10 ms in shows 0 ms, while the caller of `cancel` waited 90
  ms.
- A body that cancels itself, by throwing `Cancelled` or by letting a child's
  cancellation out, accepts the cancellation as it throws, and the count starts
  there.

## A message for the log

A body migrates the database. When the migration fails, it logs the `error` it
caught. Someone debugging the app gives the job an observer. A release build
gives it none, and there the message should cost nothing.

### The first attempt

`log` takes a message, and a string is one:

```dart
// The first attempt: the string is built for nobody.
ctx.log('migration failed: $error');
```

Without an observer, `ctx.log` does nothing, but the string is already built:
Dart evaluates the argument before the call, so `error.toString()` runs for
nobody.

### Formatting left to the observer

```dart
ctx.log(() => 'migration failed: $error');
```

A callback puts off building the message. `ctx.log` passes the callback on
unchanged, like any other object, so without an observer nothing is built. With
an observer, calling the callback is that observer's convention: the `Log`
above calls a callback and prints what it returns, while an observer that
prints each message as it came would print the closure itself. Passing `error`
alone also leaves the formatting to the observer, and needs no convention.
