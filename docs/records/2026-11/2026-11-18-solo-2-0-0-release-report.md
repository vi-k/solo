> **Состояние на 2026-11-18:** выпущено по слову владельца «публикуй»:
> релизный коммит «Release solo 2.0.0», аннотированный тег `solo-v2.0.0`,
> `solo` 2.0.0 на pub.dev. Дальше — часть B ветки `solo-lanes` с патчами
> линтов.
> **Что это:** подготовка мажорного выпуска `solo` 2.0.0 — линии
> `SoloLanes` и база `SoloController`.
> **Связанные записи:** `2026-11-11-solo-lanes-report.md`,
> `2026-11-11-solo-lanes-plan.md`, `2026-11-10-solo-lanes-design.md`,
> `2026-11-12-solo-lanes-branch-review-report.md`,
> `2026-11-10-solo-1-1-1-release-report.md`.

# Выпуск solo 2.0.0

По слову владельца 2026-11-18 «Готовь выпуск solo 2.0.0». Слово понято как
подготовка: разрешение на связку приходит отдельным запросом, состоящим только
из просьбы опубликовать.

## Что в выпуске

Часть A ветки `solo-lanes`, влитая в `main` 2026-11-12 (`be51ca4d`), и всё, что
после неё легло в «Unreleased» `solo`:

- `SoloController<S>` — общая база `Solo` и `SoloLanes`;
- `SoloLanes<S>` с линиями `SoloLane<S>` и `SoloLaneId`, `SoloJob.lane`, снимок
  `SoloPendingLanes` и `SoloPendingLane`;
- строка `Solo.debug` о записи поверх другой линии;
- очередь без обхода при постановке, удалении и запуске, политики с ключом
  и накопитель по индексу;
- тексты `[no key]` и `cannot emit`;
- документация: страница `doc/lanes.md`, правки README, `doc/state.md`,
  `doc/mistakes.md`, `doc/jobs.md` и других страниц, включая две правки
  по второму спору — `2026-11-12-bloc-vs-solo-second-debate-report.md`.

Ломающие изменения названы в «2.0.0» `CHANGELOG.md`: хуки `SoloObserver`
и `SoloUnansweredHandler` принимают `SoloController<Object>`, у `SoloPending`
новый подкласс, у `SoloJob` новый член, `SoloStream` — миксин
на `SoloController`, `queue.jobs` больше не `List`. Поэтому выпуск мажорный,
по таблице версионирования README.

## Зависимости и порядок

`solo` держит ядро в `>=1.0.0 <1.1.0` и нового ядра не требует: «Unreleased»
`async_job` — только документация, README ядра называет `SoloLanes` и уходит
в патч ядра не раньше этого выпуска. Оверрайдов у `solo` и его примера нет.

`flutter_solo` в дереве уже просит `solo: ^2.0.0` и выходит после этого
выпуска, своей просьбой владельца. scopo не задет: он зависит от `async_job`,
а не от `solo`.

Опубликованные `async_job_lints` 0.2.0 и `solo_lints` 0.2.0 не знают
`SoloController`: с ними `await_own_queue` молчит на `close` контроллера
с `SoloStream`. «2.0.0» `CHANGELOG.md` говорит обновить плагины вместе
с выпуском. Поэтому по шагу 2 раздела «Как ветка входит в `main`» плана
`2026-11-11-solo-lanes-plan.md` сразу после публикации остаток ветки
`solo-lanes` перебазируется на `main`, часть B вливается, и патчи
`async_job_lints` 0.2.1 и `solo_lints` 0.2.1 выходят тем же заходом — каждый
своей просьбой владельца.

## Подготовка

Коммит `0b54b340` «chore: prepare solo 2.0.0»:

- `version: 2.0.0` в `packages/solo/pubspec.yaml`;
- «Unreleased» в `CHANGELOG.md` стал разделом «2.0.0», в переводе
  `docs/ru/solo/CHANGELOG.md` «Не выпущено» тоже; `check_translations.py` — «no
  differences».

README версию не называет: установка — `dart pub add solo`.

## Чем проверено

На чистом дереве `0b54b340`, Flutter 3.50 и Dart 3.14:

- `solo`: формат без изменений, `dart analyze --fatal-infos` чистый,
  `dart test` +2496;
- пример `solo`: формат и анализ чистые, `dart test` +112;
- `dart pub publish --dry-run` в `packages/solo` — «Publishing solo 2.0.0»,
  «Package has 0 warnings»;
- `check_translations.py`, `check_links.py`, `check_dartdoc.py`,
  `check_line_width.py`, `reflow.py --check` и `build_site.py` чистые;
- раскладка архивов и прогон на полу Flutter 3.38.1 — «every archive passes its
  gate on the floor: 7 roots».

Полный гейт CI зелёный на `4c0afa83`, родителе подготовки; подготовка меняет
только версию и заголовки списков изменений.

На 2026-11-18: на pub.dev `solo` 1.1.1; тега `solo-v2.0.0` нет ни локально,
ни в origin.

## Связка

По слову владельца 2026-11-18 «публикуй» — отдельный запрос, состоящий только
из просьбы опубликовать. Перед связкой: `main` чистый, впереди `origin/main`
на 2 коммита и не отстаёт, тега `solo-v2.0.0` нет ни локально, ни в origin,
на pub.dev `solo` 1.1.1. Связка — релизный коммит «Release solo 2.0.0» с этой
записью, аннотированный тег `solo-v2.0.0` на нём, `git push --follow-tags`
и `dart pub publish` из чистого дерева `packages/solo`.
