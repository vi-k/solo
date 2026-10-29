---
title: solo
description: One job at a time, exclusive state, cooperative cancellation.
template: splash
editUrl: false
hero:
  tagline: |
    State management for Dart where the work has a lifecycle: one job at a
    time, rules instead of flags, and a cancellation the body cannot walk
    past by forgetting a check.
  actions:
    - text: Quick start
      link: solo/
      icon: right-arrow
    - text: solo and bloc, side by side
      link: solo/vs-bloc/
      variant: minimal
---

## The packages

| Package | What it is |
| --- | --- |
| [solo](solo/) | The controller: a queue with policies, state rules, children, accumulation. Pure Dart. |
| [async_job](async_job/) | The kernel: cancellation, children and cleanup for one operation. Pure Dart, depends only on `meta`. |
| [flutter_solo](flutter_solo/) | The Flutter face: `SoloBuilder`, `ValueListenable`, `select`, `listen`. |
| [solo_lints](solo_lints/) | An analyzer plugin that reports the common mistakes in code on `async_job` and `solo`. |

`solo` re-exports `async_job`, and `flutter_solo` re-exports `solo`, so one
dependency is enough. `solo_lints` is not a dependency: it is named
in `analysis_options.yaml`.
