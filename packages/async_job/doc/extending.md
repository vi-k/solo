# Building on the core

If your library needs its own state, queue or scheduling rules, extend
`JobBase<T>` and `JobContextBase`. The base classes handle the job lifetime
described above, while your subclasses add the library's behavior. Their
protected API provides access to job status, pending cancellation, children,
start and completion. Cancellation has a flag controlling whether the job may
refuse it. Override `started()` and `finished()` to handle lifecycle events.

For example, a custom job can create its own context type and expose a method
for its coordinator to start it:

```dart
final class MyJob<T> extends JobBase<T> {
  final Future<T> Function(MyContext ctx) _body;

  MyJob(this._body, {super.key, super.observer});

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<T> execute(covariant MyContext ctx) => _body(ctx);

  // `start` is protected: the engine opens its own door to it.
  void launch() => start();
}

final class MyContext extends JobContextBase {
  MyContext(super.owner);
}

final job = MyJob<int>((ctx) => ctx.wait(load))..launch();
```

`wait`, `join` and `uncancellable` begin by calling `check()`. Override it to
apply additional checks to all three methods.

Protected methods are accessible within subclasses. If a separate coordinator
needs to call one, expose a wrapper on your subclass, as `launch()` does above.

When adding your own error handling, use `reportToZone` to forward an error to
the job's creation zone if there is no recipient. For a context method that
must not be called from unattended work, use `throwIfUnattended` to enforce
that restriction.

`solo` uses these extension points. The full protected API is documented in the
[JobBase](https://pub.dev/documentation/async_job/latest/async_job/JobBase-class.html)
reference.

## Deferred start

A regular `Job` schedules its own start on the next microtask. If the caller
needs to choose when work begins, use `Job.deferred(body)` instead. It returns
a `DeferredJob<T>` with a public `start()` method. You can call it yourself,
let a queue start the job, or pass it to a parent with `ctx.run(child)`, as in
the children example.

```dart
final job = Job.deferred<void>((ctx) => ctx.wait(work));
// ... later, or from a queue of your own
job.start();
```
