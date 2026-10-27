> **Состояние на 2026-10-27:** подготовка сделана и в `main`, публикация
> не начиналась: связка `solo` 0.5.0 ждёт отдельного слова владельца.
> **Что это:** снятие оверрайдов `solo` и подготовка его выпуска 0.5.0.
> **Связанные записи:** `2026-10-27-async-job-release-report.md`,
> `2026-10-27-release-prep-report.md`, `2026-10-25-solo-release-report.md`.

# Выпуск solo 0.5.0

По слову владельца 2026-10-27 «готовь solo». На pub.dev сейчас `latest: 0.4.0`;
`async_job` 0.5.0 опубликован тем же днём,
`2026-10-27-async-job-release-report.md`.

## Подготовка

Оверрайды сняты: удалены `packages/solo/pubspec_overrides.yaml`
и `packages/solo/example/pubspec_overrides.yaml`, удаление в индексе
и в коммите `aa2df801`. Пакет и пример разрешают `async_job` 0.5.0 с pub.dev.
Оверрайды `flutter_solo` и его примера остаются: им нужен `solo` из дерева
до его выпуска. Стенды `tool/doc_snippets.py` и `tool/accumulation_snippets.py`
по-прежнему ведут `async_job` на дерево; дерево ядра совпадает с тегом
`async_job-v0.5.0`.

Проверки против опубликованного ядра. В `pubspec.lock` пакета и примера
`async_job` 0.5.0, источник `hosted`, sha256 `ff612a2b…3692`.

- `packages/solo`: формат — 163 файла, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart test` — +2133, All
  tests passed; `dart doc --dry-run` — 0 предупреждений и 0 ошибок;
- `packages/solo/example`: формат и анализ чистые; `dart test` — +112;
  `dart run bin/main.dart` отработал до `closed`;
- `dart pub publish --dry-run` — 0 предупреждений, подсказок об оверрайдах
  больше нет.

Пол на копии `aa2df801`, отсоединённой: `tool/archive_floor.py stage` —
`async_job` 119 и `solo` 186 файлов, по 0 предупреждений без подсказок.
`tool/archive_floor.py run` на 3.27.0: `solo` опускает до нижней границы
и `async_job` с pub.dev (`dart pub downgrade async_job meta`) — пакет +2122 при
11 пропущенных, пример +112, оба зелёные; так граница `async_job: ^0.5.0`
проверена по-настоящему. `async_job` +1885, `flutter_solo` +249 и его пример +6
тоже зелёные.

Сессии scopo 2026-10-27 по слову владельца написано, что ядро 0.5.0 вышло: что
ломается, что scopo 0.19.0 собирается против 0.5.0 (тесты `flutter_solo`
с `readme_scopo_test.dart` зелёные на оверрайдах), но граница
`async_job: ^0.4.0` его не пропустит, и порядок дальше.

## Связка

Владелец разрешает публикацию отдельным запросом, состоящим только из просьбы
опубликовать. Связка: коммит `Release solo 0.5.0`, аннотированный тег
`solo-v0.5.0`, push, `dart pub publish`.
