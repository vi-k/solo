---
title: solo
description: Cancellation, child tasks and cleanup for asynchronous Dart, and a controller that runs one job at a time.
template: splash
editUrl: false
hero:
  tagline: |
    Cancellation, child tasks and cleanup for asynchronous Dart, and a
    controller built on them that runs one job at a time over its state.
  actions:
    - text: Cancel async work
      link: async_job/
      icon: right-arrow
    - text: State with a lifecycle
      link: solo/
      icon: right-arrow
      variant: secondary
---

## Two ways in

**Cancelling async work.** A `Future` in Dart cannot be cancelled.
[async_job](async_job/) adds cancellation, child tasks and cleanup to
asynchronous code: a cancelled job stops at its next checkpoint, runs its
cleanup and ends after its children. It needs no controller and no Flutter: it
runs on a server, in a CLI, or under a riverpod provider or a bloc handler, as
[With riverpod and bloc](async_job/riverpod-and-bloc/) shows.

**State with a lifecycle.** [solo](solo/) is a controller over one immutable
state that runs jobs over it one at a time, with policies for a second call and
rules for the states a job may run in; `flutter_solo` brings it to widgets.
[solo and bloc, side by side](solo/vs-bloc/) puts eleven controller scenarios
in both packages.

## The packages

| Package | What it is |
| --- | --- |
| [async_job](async_job/) | Cancellation, child tasks and cleanup for one asynchronous operation. Pure Dart, depends only on `meta`. |
| [solo](solo/) | The controller over `async_job`: a queue with policies, state rules, children, accumulation. Pure Dart. |
| [flutter_solo](flutter_solo/) | The Flutter face of `solo`: `SoloBuilder`, `ValueListenable`, `select`, `listen`. |
| [solo_lints](solo_lints/) | An analyzer plugin that reports the common mistakes in code on `async_job` and `solo`. |

`solo` re-exports `async_job`, and `flutter_solo` re-exports `solo`, so one
dependency is enough: `async_job` when cancellation is all you need, `solo` or
`flutter_solo` when you need a controller. `solo_lints` is not a dependency: it
is named in `analysis_options.yaml`.
