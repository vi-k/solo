# With riverpod and bloc

A job fits under a riverpod provider or a bloc handler without changing the
state layer. The provider or the handler knows when the work is no longer
wanted; it cancels the job, and the job stops at its next checkpoint and runs
its cleanup. The code below runs against riverpod 3, bloc 9 with
`bloc_concurrency`, http 1.5 and dio 5, in pure Dart: `flutter_riverpod` and
`flutter_bloc` hand out the same `Ref` and `Emitter`.

| The job runs in | It is cancelled by | Section |
| --- | --- | --- |
| A `FutureProvider.autoDispose` | `ref.onDispose(job.cancel)` | [A provider that is gone](#a-provider-that-is-gone) |
| A method of an `AsyncNotifier` | The next call and `ref.onDispose`, through a field | [A notifier that starts again](#a-notifier-that-starts-again) |
| A bloc handler | `emit.forEach(watch(job), …)` | [A handler that restarts](#a-handler-that-restarts) |
| A body that sends an HTTP request | The client's own token, cancelled in `ctx.onCancel` | [A request to abort](#a-request-to-abort) |

## A provider that is gone

The screen shows rows a job reads from a database. The job opens it, reads
three pages of 20 ms each and closes it whichever way it ends:

```dart
Job<List<String>> readRows(String query) => Job((ctx) async {
  final db = await ctx.join(
    () => Database.open(query),
    dispose: (db) => db.close(),
  );
  return [
    for (var page = 1; page <= 3; page++)
      await ctx.join(() => db.readPage(page)),
  ];
});
```

`Database` is the one of the README's quick start, reading by pages; it prints
when it opens, reads a page and closes. The provider is `autoDispose`: when the
screen goes, so does its last listener, and riverpod disposes the provider. The
reads should stop there and the database close. In the traces below the screen
goes during the first page.

### The first attempt

The provider returns the job's value:

```dart
// The first attempt: the job reads on after the provider is gone.
final rows = FutureProvider.autoDispose.family<List<String>, String>(
  (ref, query) => readRows(query).value,
);
```

```text
database opened for dart
screen left
dart: page 1 read
dart: page 2 read
dart: page 3 read
database for dart closed
```

riverpod drops the future it was given, and nothing tells the job: it reads
every page for nobody.

### The second attempt

`ref.onCancel` sounds like the place to cancel:

```dart
// The second attempt: a paused screen cancels the job, and a new one starts.
final rows = FutureProvider.autoDispose.family<List<String>, String>((
  ref,
  query,
) {
  final job = readRows(query);
  ref.onCancel(job.cancel);
  return job.value;
});
```

```text
database opened for dart
screen covered
dart: page 1 read
database for dart closed
screen shown
database opened for dart
dart: page 1 read
dart: page 2 read
dart: page 3 read
database for dart closed
```

When the screen leaves, this works. But riverpod 3 calls `onCancel` when the
last listener is paused as well as when it is removed, and Flutter pauses the
listeners of a screen that an opaque route covers. The job ends `Cancelled`,
and `Cancelled` is an `Exception`: riverpod takes it for a failure and retries
the provider once the screen is shown again, so the reads start over from the
first page. With retries turned off, the screen comes back to the error
instead.

### Cancelling on disposal

`onDispose` runs when the state the job serves is thrown away: when the
provider is disposed and when it rebuilds, but not on a pause:

```dart
final rows = FutureProvider.autoDispose.family<List<String>, String>((
  ref,
  query,
) {
  final job = readRows(query);
  ref.onDispose(job.cancel);
  return job.value;
});
```

```text
database opened for dart
screen left
dart: page 1 read
database for dart closed
```

The disposal cancels the job, `join` waits for the page already being read, and
the database closes. A screen that asks for another query watches another
provider of the family, and the one it stops watching is disposed the same way.

The cancellation does not reach the zone, but a `ProviderObserver` still hears
it: `providerDidFail` receives the `Cancelled(manual)` of the disposed
provider. An observer that sends failures to crash reports passes it over:

```dart
final class CrashReports extends ProviderObserver {
  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    if (error is Cancelled) return;
    report(error, stackTrace);
  }
}
```

A `Cancelled` the job ends with on its own, by its own deadline for one, is a
failure to riverpod as well, and the provider retries it like any other.

## A notifier that starts again

A notifier that runs a job from a method keeps the current one in a field. The
next call cancels it before starting another. The disposal, which riverpod runs
before a rebuild as well, cancels the one in flight and clears the field:

```dart
final class Search extends AsyncNotifier<List<String>> {
  Job<List<String>>? _current;

  @override
  List<String> build() {
    ref.onDispose(() {
      unawaited(_current?.cancel());
      _current = null;
    });
    return const [];
  }

  Future<void> search(String query) async {
    unawaited(_current?.cancel());
    final job = _current = readRows(query);
    state = const AsyncLoading();

    final outcome = await job.done;
    // A newer search, a rebuild or the disposal owns the state now.
    if (!identical(job, _current)) return;
    state = switch (outcome) {
      Done(:final value) => AsyncData(value),
      Failed(:final error, :final stackTrace) => AsyncError(error, stackTrace),
      Cancelled() => AsyncError(outcome, StackTrace.current),
    };
  }
}

final search = AsyncNotifierProvider.autoDispose<Search, List<String>>(
  Search.new,
);
```

```text
database opened for d
search: da
database opened for da
d: page 1 read
database for d closed
da: page 1 read
da: page 2 read
da: page 3 read
database for da closed
state: [da: page 1, da: page 2, da: page 3]
```

The check before writing the state matters as much as the cancellation. The
cancelled search still ends, and without the check its `Cancelled` would land
on top of the search that replaced it. A rebuild, after `ref.invalidate` for
one, keeps the notifier and its field, and `ref.mounted` is true again by then:
only the cleared field tells the old search that the state is no longer its.

## A handler that restarts

The search runs on every key, and a bloc with `restartable()` from
`bloc_concurrency` keeps only the latest: a new query should stop the search
before it, and `close()` the one in flight. The events and the state:

```dart
final class Searched {
  const Searched(this.query);

  final String query;
}

final class SearchState {
  const SearchState(this.rows, [this.error]);

  final List<String> rows;
  final Object? error;
}
```

### The first attempt

The handler awaits the job's value:

```dart
// The first attempt: restartable() drops the handler, not the job.
final class SearchBloc extends Bloc<Searched, SearchState> {
  SearchBloc() : super(const SearchState([])) {
    on<Searched>((event, emit) async {
      final rows = await readRows(event.query).value;
      if (!emit.isDone) emit(SearchState(rows));
    }, transformer: restartable());
  }
}
```

```text
database opened for a
a: page 1 read
database opened for ab
a: page 2 read
ab: page 1 read
a: page 3 read
database for a closed
```

```text
bloc closed
abc: page 2 read
abc: page 3 read
database for abc closed
```

`restartable()` stops listening to the old handler and `close()` stops all of
them, but a handler is a `Future` and nothing cancels it. The search for `a`
reads to its end beside the one for `ab`, and the one for `abc` reads on after
the bloc is closed.

### A stream that cancels the job

An `Emitter` has no callback for its cancellation, but it cancels the
subscriptions of its `forEach` and `onEach` at once: `restartable()` and
`close()` both reach them. So the job goes into a stream whose cancellation
cancels the job:

```dart
/// The value of [job] as a stream. Cancelling the subscription cancels the
/// job.
///
/// Listen to it at once: the value is read in `onListen`, and a stream
/// nobody listens to leaves the job unwatched, its failure unobserved.
Stream<T> watch<T>(Job<T> job) {
  late final StreamController<T> controller;
  controller = StreamController<T>(
    onListen: () {
      job.value
          .then(controller.add, onError: controller.addError)
          .whenComplete(controller.close);
    },
    onCancel: job.cancel,
  );
  return controller.stream;
}

final class SearchBloc extends Bloc<Searched, SearchState> {
  SearchBloc() : super(const SearchState([])) {
    on<Searched>((event, emit) async {
      await emit.forEach(
        watch(readRows(event.query)),
        onData: SearchState.new,
        onError: (error, stackTrace) => SearchState(const [], error),
      );
    }, transformer: restartable());
  }
}
```

```text
database opened for a
a: page 1 read
database opened for ab
a: page 2 read
database for a closed
```

```text
bloc closed
abc: page 2 read
database for abc closed
```

The search for `a` stops at the page it was reading, and `close()` stops the
one for `abc` the same way. Neither waits for that cleanup: the emitter does
not wait for `job.cancel()`, and `restartable()` starts the new handler before
it even cancels the old one, so the database for `ab` opens before the one for
`a` closes, and `close()` returns before the database for `abc` closes. A
resource that can be open only once needs the new search to wait for the old
one.

`close()` cancels the running handlers under `concurrent()`, the default, and
under `droppable()` and `restartable()`, so `watch` is worth it without
`restartable()` too. Under `sequential()` it first waits for the running
handler and the queued events, and there is nothing left to cancel. `onError:`
is there for a job that ends `Cancelled` on its own, by its deadline for one:
`forEach` hands it the error, and without `onError:` bloc passes the error to
`onError` of the bloc and on to the zone.

`watch` is page code, not part of `async_job`: copy it.

## A request to abort

A job fetches a report from a server that takes 300 ms to answer. When the job
is cancelled, the request should stop: the connection closes, and the server
stops working on an answer nobody will read.

### The first attempt

The body waits for the request through `join`, as in the quick start:

```dart
// The first attempt: the cancellation waits for the whole response.
final job = Job<String>((ctx) async {
  final response = await ctx.join(() => client.get(url));
  return response.body;
});
```

```text
cancel
server: sending the body
outcome: Cancelled(manual)
```

`join` waits for the action it has started, and nothing tells the request to
stop: the cancellation ends only once the whole response is in.
`ctx.abandonable` would end the job at once, but the request would go on, and
the response would arrive to nobody, as
[Stopping the operation](cancellation.md#stopping-the-operation) shows.

### The client's token

Both clients take a stop signal of their own, and `ctx.onCancel` fires it
together with the cancellation, as
[A token through `onCancel`](cancellation.md#a-token-through-oncancel) does for
a database:

```dart
// http 1.5 and later: a request with an abort trigger.
final job = Job<String>((ctx) async {
  final abort = Completer<void>();
  ctx.onCancel(abort.complete);

  final response = await ctx.join(() async {
    final request = http.AbortableRequest(
      'GET',
      url,
      abortTrigger: abort.future,
    );
    return http.Response.fromStream(await client.send(request));
  });
  return response.body;
});
```

```dart
// dio: a CancelToken.
final job = Job<String>((ctx) async {
  final token = CancelToken();
  ctx.onCancel(token.cancel);

  final response = await ctx.join(
    () => dio.getUri<String>(url, cancelToken: token),
  );
  return response.data!;
});
```

```text
cancel
server: client hung up
outcome: Cancelled(manual)
```

Both print the same: the client closes the connection, and the server never
sends the body. A `Client` of http that does not support `abortTrigger` ignores
it, and the request then runs to its end as it does under the first attempt.

The aborted request still throws: `RequestAbortedException` from http,
`DioException` of the type `cancel` from dio. `join` passes it on, and it
reaches the zone as an uncaught error, as does any failure of the body that no
outcome carries. One line in `main` names the two as the stop of a client:

```dart
Job.isCancellationError = (error) =>
    error is http.RequestAbortedException ||
    error is DioException && error.type == DioExceptionType.cancel;
```

An error it names reaches the observer and stops there.
[Errors of a cancellation](errors.md#errors-of-a-cancellation) takes the filter
apart.
