# solo_lints

`solo_lints` is an analyzer plugin for code built on
[solo](https://pub.dev/packages/solo) and
[flutter_solo](https://pub.dev/packages/flutter_solo). It reports the mistakes
that compile, run and often pass a first test: a wait in cleanup that never
happens, a resource lost to a cancellation, a catch that resets a working
device, a job that waits for itself, one key for every request, a wait that a
cancellation does not end. Most rules stand for a section of
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
  solo_lints: ^0.1.4
```

The analysis server fetches the plugin itself, so it is not a dependency in
`pubspec.yaml`. Plugins need Dart 3.10 or later. `dart analyze` and the editor
report its diagnostics. Run `dart analyze` on the root of the package or on
single files: on a folder below the root, such as `dart analyze lib`, it shows
none of them. `flutter analyze` reports them on Flutter 3.38, but from Flutter
3.44 on it shows none of them; in a Flutter package, run `dart analyze` for the
plugin. An editor sees a change to the `plugins` section after its analysis
server restarts.

The warnings are on as soon as the plugin is named. The four lints,
`catch_without_check`, `key_per_request`, `ignore_failure_hides_bugs` and
`bare_await`, are turned on by name:

```yaml
plugins:
  solo_lints:
    version: ^0.1.4
    diagnostics:
      catch_without_check: true
      key_per_request: true
      ignore_failure_hides_bugs: true
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
| [`bare_await`](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.md#bare_await) | lint | an `await` in a job body that does not go through the context |

The five rules of the core are described in the README of async_job_lints:
their names in the table lead to their sections there. There `// ignore:` puts
`async_job_lints/` in front of a rule; with this plugin named, it is
`solo_lints/`, as for the three rules below.

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
`on Solo` is the controller too. `bare_await`, which reports the other plain
waits of a body, is quiet on these. See
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
