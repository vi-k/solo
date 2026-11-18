> **Состояние на 2026-11-18:** выпущено по слову владельца «публикуй»:
> подготовка `32baaaeb`, релизный коммит «Release async_job 1.0.4»,
> аннотированный тег `async_job-v1.0.4`, `async_job` 1.0.4 на pub.dev.
> **Что это:** подготовка патча `async_job` 1.0.4 — документация после 1.0.3:
> README о линиях `solo`, граница `async_job_lints` в README, срок на вызов,
> который может не вернуться.
> **Связанные записи:** `2026-11-11-async-job-1-0-3-release-report.md`,
> `2026-11-18-core-bounds-probe-report.md`, `2026-11-11-solo-lanes-plan.md`,
> `2026-11-12-queue-key-index-report.md`,
> `2026-11-18-async-job-lints-0-2-1-release-report.md`.

# Выпуск async_job 1.0.4

По слову владельца 2026-11-18 «Готовь патч ядра async_job 1.0.4». Слово понято
как подготовка: разрешение на связку приходит отдельным запросом, состоящим
только из просьбы опубликовать.

## Что в патче

Код `lib/` не менялся, кроме одной строки dartdoc: `git diff async_job-v1.0.3`
по `lib/` — только `Job.key`. Патч — документация:

- README просит `async_job_lints: ^0.2.1` вместо `^0.1.1`. Прежняя граница
  не пускала ни 0.2.0, ни 0.2.1, и на pub.dev страница 1.0.3 вела на плагин
  0.1.x. Сторож `readme_recipe_test.dart` держит у блока только форму `^X.Y.Z`:
  версия плагина живёт в другом пакете, — поэтому устаревшую границу он
  не заметил. Правка подготовки; строка в обоих списках изменений;
- README говорит, что `Solo` выполняет одну корневую задачу за раз,
  а `SoloLanes` — по одной в каждой линии. По плану
  `2026-11-11-solo-lanes-plan.md` она уходит в патч ядра не раньше `solo`
  2.0.0, вышедшего 2026-11-18;
- `doc/time.md`, раздел «A call that may not come back»: `ctx.join` вокруг
  `Future.timeout` — `2026-11-18-core-bounds-probe-report.md`;
- dartdoc `Job.key` добавляет, что `solo` ищет ключи и по `hashCode` —
  `2026-11-12-queue-key-index-report.md`. В «Unreleased» строки об этом
  не было; подготовка её дописала.

## Зависимости и порядок

`solo` 2.0.0 держит ядро в `>=1.0.0 <1.1.0`, scopo 1.0.0 — тоже; патч они
получают сами. Оверрайдов у ядра нет, и ни один пакет дерева его
неопубликованную правку не требует.

## Подготовка

Коммит `32baaaeb` «chore: prepare async_job 1.0.4»:

- `version: 1.0.4` в `packages/async_job/pubspec.yaml`;
- «Unreleased» в `CHANGELOG.md` стал разделом «1.0.4», в переводе
  `docs/ru/async_job/CHANGELOG.md` «Не выпущено» тоже; в оба добавлены строки
  о границе плагина и о `Job.key`;
- `version: ^0.2.1` в блоке плагина README и его перевода.

`check_translations.py` — «no differences».

## Чем проверено

На чистом дереве `32baaaeb`, Flutter 3.50 и Dart 3.14:

- `async_job`: формат — «0 changed», `dart analyze --fatal-infos` — «No issues
  found!», `dart test` — «+1917: All tests passed!», `dart doc --dry-run` —
  «Found 0 warnings and 0 errors.»;
- `dart pub publish --dry-run` в `packages/async_job` — «Publishing async_job
  1.0.4», «Package has 0 warnings.»;
- `check_translations.py` — «no differences», `check_links.py`,
  `check_dartdoc.py`, `check_line_width.py` и `reflow.py --check` чистые,
  `build_site.py` — «wrote 100 pages»;
- раскладка архивов и прогон на полу Flutter 3.38.1 — «every archive passes its
  gate on the floor: 7 roots». Прогон шёл на первой версии коммита подготовки,
  до строки о `Job.key`; поправка меняет только списки изменений.

Гейт CI зелёный на `76544a46` «Release flutter_solo 2.0.0»; от него
до подготовки — только запись о выпуске.

## Состояние

На 2026-11-18: на pub.dev `async_job` 1.0.3. Тега `async_job-v1.0.4` нет
ни локально, ни в origin. Связка — релизный коммит «Release async_job 1.0.4»,
аннотированный тег `async_job-v1.0.4`, `git push --follow-tags`
и `dart pub publish` из чистого дерева `packages/async_job` — только
по отдельному слову владельца.

## Связка

По слову владельца 2026-11-18 «публикуй» — отдельный запрос, состоящий только
из просьбы опубликовать. Перед связкой: `main` чистый, впереди `origin/main`
на 3 коммита и не отстаёт, тега `async_job-v1.0.4` нет ни локально,
ни в origin, на pub.dev `async_job` 1.0.3. Связка — релизный коммит «Release
async_job 1.0.4» с этой записью, аннотированный тег `async_job-v1.0.4` на нём,
`git push --follow-tags` и `dart pub publish` из чистого дерева
`packages/async_job`.
