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

## The three packages

| Package | What it is |
| --- | --- |
| [solo](solo/) | The controller: a queue with policies, state rules, children, accumulation. Pure Dart. |
| [async_job](async_job/) | The kernel: cancellation, children and cleanup for one operation. Pure Dart, depends only on `meta`. |
| [flutter_solo](flutter_solo/) | The Flutter face: `ValueListenable`, `select`, `listen`. |

`solo` re-exports `async_job`, and `flutter_solo` re-exports `solo`, so one
dependency is enough.
