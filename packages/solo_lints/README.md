# solo_lints

`solo_lints` is an analyzer plugin for code built on
[solo](https://pub.dev/packages/solo) and
[flutter_solo](https://pub.dev/packages/flutter_solo). It reports the mistakes
that compile, run and often pass a first test: a wait in cleanup that never
happens, a resource lost to a cancellation, a catch that resets a working
device, a job that waits for itself, one key for every request, a wait that a
cancellation does not end, an outcome awaited and dropped, a write over what
another lane wrote, a lane declared too late. Most rules stand for a section of
[Common mistakes](https://github.com/vi-k/solo/blob/main/packages/solo/doc/mistakes.md),
the page of solo that shows each mistake and the right way side by side.

The rules of the core, async_job, come from
[async_job_lints](https://pub.dev/packages/async_job_lints), and this plugin
includes them: code on solo needs only `solo_lints`. Name one of the two
plugins, not both: the analysis server resolves the versions of all plugins
together, and when they disagree, no plugin runs.

Also on the [documentation site](https://docs.yet-another.dev/solo_lints/),
with search.

## Install

Name the plugin in `analysis_options.yaml` at the root of the package or the
workspace:

```yaml
plugins:
  solo_lints: ^0.4.0
```

The analysis server fetches the plugin itself, so it is not a dependency in
`pubspec.yaml`. Plugins need Dart 3.10 or later. `dart analyze` and the editor
report its diagnostics. Run `dart analyze` on the root of the package or on
single files: on a folder below the root, such as `dart analyze lib`, it shows
none of them. `flutter analyze` reports them on Flutter 3.38, but from Flutter
3.44 on it shows none of them; in a Flutter package, run `dart analyze` for the
plugin. An editor sees a change to the `plugins` section after its analysis
server restarts.

The warnings are on as soon as the plugin is named. The five lints,
`catch_without_check`, `key_per_request`, `ignore_failure_hides_bugs`,
`stale_emit` and `bare_await`, are turned on by name:

```yaml
plugins:
  solo_lints:
    version: ^0.4.0
    diagnostics:
      catch_without_check: true
      key_per_request: true
      ignore_failure_hides_bugs: true
      stale_emit: true
      bare_await: true
```

A rule takes a severity in place of `true`: `error`, `warning` or `info`.
`key_per_request: warning` turns the lint on as a warning, and `dart analyze`
then fails on it, as on any warning. `false` turns a warning off.

A diagnostic is silenced with the name of the plugin in front of the rule:
`// ignore: solo_lints/ctx_in_cleanup` on the line above it, or
`// ignore_for_file: solo_lints/ctx_in_cleanup` for the whole file.

The quick fixes are offered in the editor. `dart fix` does not apply them: it
applies the fixes of the analyzer itself, not those of plugins.

On Dart 3.12, `dart analyze` in a package that names a plugin prints each
diagnostic of the analyzer itself twice. Dart 3.13 prints it once.

## Rules

| Rule | Kind | Reports |
| --- | --- | --- |
| [`ctx_in_cleanup`](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.md#ctx_in_cleanup) | warning | a waiting member of the context called in cleanup |
| [`release_on_the_call`](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.md#release_on_the_call) | warning | a release registered on the line under the call that brings the resource |
| [`catch_without_check`](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.md#catch_without_check) | lint | a broad catch in a body that acts before asking the job |
| [`sync_fake_async`](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.md#sync_fake_async) | warning | an `async` callback of `fakeAsync` |
| `await_own_queue` | warning | a job that waits for a job of its own controller's queue |
| `key_per_request` | lint | one key for a `Policy.droppable` job whose body reads an argument |
| `ignore_failure_hides_bugs` | lint | `ignoreFailure()` on a job that names its expected errors |
| `stale_emit` | lint | an `emit` in a job of `SoloLanes` of a value read from the state before an `await` |
| `lane_outside_constructor` | warning | `lane(...)` or `pool(...)` of `SoloLanes` called outside the constructor body |
| [`bare_await`](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.md#bare_await) | lint | an `await` in a job body that does not go through the context |
| [`discarded_outcome`](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.md#discarded_outcome) | warning | an outcome of `done` that is awaited and dropped |
| [`outcome_after_await`](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.md#outcome_after_await) | warning | the first read of a job's result that comes after a wait |

The seven rules of the core are described in the README of async_job_lints:
their names in the table lead to their sections there. There `// ignore:` puts
`async_job_lints/` in front of a rule; with this plugin named, it is
`solo_lints/`, as for the five rules below.

### await_own_queue

```dart
Job<void> syncAndRecord(int item) =>
    enqueue<Ready, void>(key: _Op.syncAndRecord, (ctx) async {
      final path = await sync(item).value; // await_own_queue
      await recordPath(path).value; // await_own_queue
    });
```

`sync(item)` queues a job behind the one that waits for it, and nothing moves
until `close()` cancels both. Run the job through `ctx.run(_sync(item))`
instead. The rule takes a method of the same controller that brings a
`SoloJob`, by its declared type or by what it returns when it is declared in
the same file, and `close()` and `cancelAll()`. It looks at the body of a
`SoloContext` job queued on this controller, what the body returns included, at
the actions that body waits for through `join`, `abandonable` and
`uncancellable`, and at its cleanup, which the queue waits for as well. A mixin
`on Solo` is the controller too, and for `close()` and `cancelAll()`, which
wait for every lane, so is any `SoloController`. In a `SoloLanes` the deadlock
is within one lane: the rule reports a body queued by `_likes.enqueue(...)`
that waits for a job of `_likes`, queued there directly or by a method whose
body queues it there, and names the lane. A pool declared by `pool(...)` is
reported the same way, with a message of its own: a job of the same key never
starts while the waiting one runs, and a job of another key waits for a free
place, so with every place taken by such waits no job of the pool starts. A
test with an idle pool passes and the code hangs under load, so the rule
reports a wait for the own pool whatever the key, as
[A pool of places](https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#a-pool-of-places)
shows. A job of another lane or pool runs on its own pump, and where the lane
is not seen, as with a lane from a getter, a lane the controller takes rather
than declares by `lane(...)` or `pool(...)` in its constructor body, a lane
declared in another file (a superclass there or another part of the library), a
job from a field or a parameter, a body of a child or a handler of an
accumulator, the rule is quiet. `bare_await`, which reports the other plain
waits of a body, is quiet on the waits this rule reports. See
[Steps as children](https://github.com/vi-k/solo/blob/main/packages/solo/doc/mistakes.md#steps-as-children).

### key_per_request

```dart
Job<Profile> load(String id) => enqueue<Ready, Profile>(
  key: _Op.load, // key_per_request
  policy: Policy.droppable,
  (ctx) => ctx.abandonable(() => api.load(id)),
);
```

A policy compares keys, not arguments. With one key for every `load(id)`,
`Policy.droppable` takes `load('grace')`, called while `load('ada')` runs, for
a duplicate and hands its caller Ada's profile. Put the argument into the key:
`key: (_Op.load, id)`. The rule takes `enqueue` of `Solo` with
`Policy.droppable` and `enqueueJob` of a `job` with that policy, when the key
reads no parameter of the enclosing method or function and the body reads one.
A key that reads a local variable or a parameter of a closure is left alone. It
is a lint rather than a warning because one key is sometimes meant, when the
result does not depend on the argument. See
[A key for each request](https://github.com/vi-k/solo/blob/main/packages/solo/doc/mistakes.md#a-key-for-each-request).

The quick fix replaces the key `K` with the record `(K, a, b)` of the
parameters the body reads. It is offered when each of them compares by value: a
`String`, a number, a `bool`, an enum, or one of those that can be `null`.

### ignore_failure_hides_bugs

```dart
SoloJob<Profile> load() => enqueue<Ready, Profile>(
  (ctx) => api.load(),
  isExpectedError: (e) => e is ApiException,
);

profiles.load().ignoreFailure(); // ignore_failure_hides_bugs
```

`isExpectedError` already keeps the errors it names quiet and lets the bugs
through to the zone, and `ignoreFailure()` hides those as well. Drop
`ignoreFailure()`: the expected errors stay quiet, and a bug is still reported.
The rule takes `ignoreFailure()` on a job that comes from `job` or `enqueue`
with `isExpectedError`, or from the `add` of a `collect` or `accumulate` field
with one, also through a method or function of the same library whose body is
`=>` or a single `return`, when nobody uses the job afterwards: the call
itself, or a cascade whose value is dropped, as the `onPressed` of a button is.
The page of common mistakes has no section for this one. It is a lint rather
than a warning because a job whose outcome nobody needs, with the reporting
left to the hooks, may call `ignoreFailure()` on purpose: see
[Answering for every failure](https://github.com/vi-k/solo/blob/main/packages/solo/doc/mistakes.md#answering-for-every-failure).

### stale_emit

```dart
Job<void> setLiked(String postId, {required bool liked}) =>
    _likes.enqueue<Feed, void>((ctx) async {
      final feed = ctx.state;
      ctx.emit(feed.mark(postId, Mark(liked)));
      await ctx.join(() => api.setLiked(postId, liked: liked));
      ctx.emit(feed.mark(postId, Mark(liked, ++_confirmations))); // stale_emit
    });
```

In a `SoloLanes` the other lanes write while a job waits, and the second `emit`
writes the copy read before the wait over what they wrote: the posts a reload
published in the meantime are gone. Read the state where the job writes:
`ctx.emit(ctx.state.mark(postId, Mark(liked, ++_confirmations)))`.

The rule takes `ctx.emit` in a job body that runs in a lane: a body given to a
lane or a pool, whichever it is, or a body queued on a `SoloLanes` around it, a
child's included. It reports the write when the value is built on `ctx.state`
or `ctx.stateAs<T>()`, through member calls, property and index reads,
cascades, casts and `!`, in any branch of `?:`, `??` and a switch expression,
in each field of a record literal, directly or through local variables of the
same body, and an `await` or `await for` of the body, or of an action the write
is in, comes between the read and the write in the text of the job: a wait in
one branch counts for a write in another, except a branch whose block ends with
`return` or `throw`, which the job leaves before a write after it. An
assignment in a function declared in the body, a function expression or a local
function, does not refresh the copy: the function may never run. The message
names the variable the read went to. A write in the action of
`await ctx.join(...)` runs before the job suspends and is not reported. A read
in the `emit` itself,
`ctx.emit(ctx.state.withPosts(await ctx.abandonable(fetchPosts)))`, gets its
own message: await into a local variable before the `emit`, and read
`ctx.state` in the `emit` after it.

A `Solo` has no other lane, and the rule is quiet there. It is a heuristic, and
a lint rather than a warning: a copy written back on purpose looks the same to
it, and so does a part read before the wait and applied to the fresh state
after it: `final pending = ctx.state.pending;` before the wait and
`ctx.emit(pending.applyTo(ctx.state))` after it are reported, so read
`ctx.state.pending` after the wait as well. It does not see the answer of a
server written whole, `ctx.emit(await ctx.abandonable(api.fetchFeed))`, which
loses what the other lanes wrote just as well, nor a body passed as a method
tear-off, `_likes.enqueue(_like)`, nor a value a parent read and its child
writes, nor a read and a write in different turns of a loop. See
[A write that keeps the other lane's work](https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#a-write-that-keeps-the-other-lanes-work).

### lane_outside_constructor

```dart
late final _reload = lane('reload'); // lane_outside_constructor

FeedController(this.api) : super(const Feed());
```

`SoloLanes` seals its set of lanes a microtask after the constructor, and a
lane in a `late final` field is declared on the first read of the field, in the
first call of a method, where `lane` throws a `StateError`. Declare the lanes
in the constructor body, `_reload = lane('reload');`, into a field
`late final SoloLane<Feed> _reload;`. A pool is sealed with the lanes:
`pool(...)` is reported the same way, with a message of its own, and goes into
the constructor body too, `_likes = pool('likes', concurrency: 4);`, into a
field `late final SoloPool<Feed> _likes;`. The rule takes `lane(...)` and
`pool(...)` of `SoloLanes` anywhere but right in a constructor body on `this`
or `super`: a field initializer, a method, a getter, a function declared in the
constructor body. A lambda is such a function, though `map` runs it at once:
`_lanes = names.map((name) => lane(name)).toList();` is reported, and a
collection for, `_lanes = [for (final name in names) lane(name)];`, declares
the same lanes right in the body. A method the constructor calls is reported
too, though the call there works: `await_own_queue` does not see a lane or a
pool declared there either. See
[Declaring lanes](https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#declaring-lanes).

## Versions

The plugin works on Dart 3.10 and later, with `analyzer` from 12.1 to 14. A
Dart SDK that needs `analyzer` 15 does not load this version, and its rules
stay silent until a release lifts the bound.

The rules know the types of solo by their names and the library they come from,
without depending on the package. On a version of solo where a name has
changed, a rule stays silent rather than reports code that is right. The rules
of the core are those of async_job_lints, and its
[CHANGELOG](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/CHANGELOG.md)
lists their changes.
