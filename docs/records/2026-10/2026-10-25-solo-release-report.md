> **Состояние на 2026-10-25:** подготовка сделана: оверрайды `solo` сняты
> (`806d6227`), проверки против опубликованного `async_job` 0.4.0 зелёные.
> Связка выпуска `solo` 0.4.0 ждёт отдельного слова владельца.
> **Что это:** снятие оверрайдов `solo` и подготовка его выпуска 0.4.0.
> **Связанные записи:** `2026-10-25-async-job-release-report.md`,
> `2026-10-25-release-prep-report.md`, `2026-10-23-solo-release-report.md`.

# Выпуск solo 0.4.0

По слову владельца 2026-10-25 «готовь выпуск solo». На pub.dev сейчас
`latest: 0.3.0`; `async_job` 0.4.0 опубликован тем же днём,
`2026-10-25-async-job-release-report.md`.

## Подготовка

Оверрайды сняты: удалены `packages/solo/pubspec_overrides.yaml`
и `packages/solo/example/pubspec_overrides.yaml`, удаление в индексе
и в коммите `806d6227`. Пакет и пример разрешают `async_job` 0.4.0 с pub.dev.
Оверрайды `flutter_solo` и его примера остаются: им нужен `solo` из дерева
до его выпуска. Стенды `tool/doc_snippets.py` и `tool/accumulation_snippets.py`
по-прежнему ведут `async_job` на дерево; дерево ядра совпадает с тегом
`async_job-v0.4.0`.

Проверки против опубликованного ядра. В `pubspec.lock` пакета и примера
`async_job` 0.4.0, источник `hosted`, sha256 `a71e876e…950d`.

- `packages/solo`: формат — 155 файлов, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart test` — +2070, All
  tests passed; `dart doc --dry-run` — 0 предупреждений и 0 ошибок;
- `packages/solo/example`: анализ чистый; `dart test` — +112;
  `dart run bin/main.dart` отработал до `closed`;
- `dart pub publish --dry-run` — 0 предупреждений, подсказок об оверрайдах
  больше нет.

Пол на копии `806d6227`, `git worktree add --detach`:
`tool/archive_floor.py stage` — `async_job` и `solo` по 0 предупреждений без
подсказок. `tool/archive_floor.py run` на 3.27.0: `solo` теперь опускает
до нижней границы и `async_job` с pub.dev
(`dart pub downgrade async_job meta`) — пакет +2059 при 11 пропущенных, пример
+112, оба зелёные; так граница `async_job: ^0.4.0` проверена по-настоящему.
`async_job` +1858 и пример `flutter_solo` +6 зелёные; `flutter_solo` красный
одним `readme_scopo_test.dart`: scopo 0.18.0 переопределяет `onError`
по-старому. Выпуска `solo` это не касается.

CI `gate` на `32d1ca8e`: `dart`, `snippets` и `docs` зелёные, `flutter` красный
одним `readme_scopo_test.dart` (242 прошли, файл не загрузился — scopo 0.18.0),
`floor` за ним пропущен.

## Связка

Владелец разрешил публикацию отдельным запросом «опубликуй solo 0.4.0»,
состоящим только из просьбы опубликовать. Перед связкой: `git fetch` выполнен,
`main` совпадает с `origin/main` на `32d1ca8e`, тега `solo-v0.4.0` нет
ни локально, ни в origin, дерево чистое, оверрайдов у пакета и примера нет,
`dart pub publish --dry-run` — 0 предупреждений; на pub.dev `latest: 0.3.0`.
Связка выполняется подряд: коммит `Release solo 0.4.0`, аннотированный тег
`solo-v0.4.0`, push, `dart pub publish`.
