> **Состояние на 2026-10-28:** оверрайды `solo` сняты, проверки против
> опубликованного ядра зелёные. Публикация не начиналась: связка ждёт
> отдельного слова владельца.
> **Что это:** снятие оверрайдов `solo` и подготовка его выпуска 0.6.0.
> **Связанные записи:** `2026-10-28-async-job-release-report.md`,
> `2026-10-28-release-prep-report.md`, `2026-10-27-solo-release-report.md`.

# Выпуск solo 0.6.0

По слову владельца 2026-10-28 «готовь solo». На pub.dev сейчас `latest: 0.5.0`;
`async_job` 0.6.0 опубликован тем же днём,
`2026-10-28-async-job-release-report.md`.

## Подготовка

Оверрайды сняты: удалены `packages/solo/pubspec_overrides.yaml`
и `packages/solo/example/pubspec_overrides.yaml`, удаление в индексе
и в коммите `59360e9e`. Пакет и пример разрешают `async_job` 0.6.0 с pub.dev.
Оверрайды `solo_lints`, `flutter_solo` и примера `flutter_solo` остаются: им
нужен `solo` из дерева до его выпуска. Стенды `tool/doc_snippets.py`
и `tool/accumulation_snippets.py` по-прежнему ведут `async_job` на дерево;
дерево ядра совпадает с тегом `async_job-v0.6.0`.

Проверки против опубликованного ядра. В `pubspec.lock` пакета и примера
`async_job` 0.6.0, источник `hosted`, sha256 `317e8d8a…d464`.

- `packages/solo`: формат — 166 файлов, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart test` — +2209, All
  tests passed; `dart doc --dry-run` — 0 предупреждений и 0 ошибок;
- `packages/solo/example`: формат и анализ чистые; `dart test` — +112;
  `dart run bin/main.dart` отработал до `closed`;
- `dart pub publish --dry-run` — 0 предупреждений, подсказок об оверрайдах
  больше нет.

Пол на копии `59360e9e`, отсоединённой: `tool/archive_floor.py stage` —
`async_job` 119 и `solo` 189 файлов, по 0 предупреждений без подсказок;
`solo_lints` 30 и `flutter_solo` 46 файлов, по 0 предупреждений, с оверрайдами
дерева. `tool/archive_floor.py run` на 3.38.1 — «every archive passes its gate
on the floor: 6 roots». `solo` опускает до нижней границы и `async_job`
с pub.dev (`dart pub downgrade async_job meta`) — пакет +2198 при 11
пропущенных, пример +112, оба зелёные; так граница `async_job: ^0.6.0`
проверена по-настоящему. `async_job` +1885, `solo_lints` +122, `flutter_solo`
+254 и его пример +6 тоже зелёные.

## Связка

Связка `solo` 0.6.0 — по отдельному запросу владельца, состоящему только
из просьбы опубликовать: коммит `Release solo 0.6.0`, аннотированный тег
`solo-v0.6.0`, push, `dart pub publish`.
