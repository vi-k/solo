# solo

Monorepo for `async_job`, which adds cancellation, child tasks and
resource cleanup to asynchronous Dart code, and for the `solo` state
management packages built on it.

| Package | Description |
|---|---|
| [`packages/async_job`](packages/async_job) | Core: one operation, its children, its cleanup and its cancellation. Pure Dart. |
| [`packages/solo`](packages/solo) | Engine on the core: one job at a time, exclusive state ownership, cooperative cancellation. Pure Dart. |
| [`packages/flutter_solo`](packages/flutter_solo) | Flutter integration: `ValueListenable` face for `Solo`. |
| [`packages/solo_lints`](packages/solo_lints) | Analyzer plugin: warnings for the common mistakes of `async_job` and `solo`. |

Documentation: **[docs.yet-another.dev](https://docs.yet-another.dev)**. It is built
from these packages' own Markdown by
[`tool/build_site.py`](tool/build_site.py); see [`site/`](site).

Development notes for agents and the owner live in `AGENTS.md` and `docs/`.
