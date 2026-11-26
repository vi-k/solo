> **Состояние на 2026-11-27:** выпускается по слову владельца «опубликуй
> async_job 1.0.6»: подготовка `019b0cf3`, проверки пройдены; связка ниже.
> **Что это:** выпуск патча `async_job` 1.0.6 — правка `ctx.abandonable` для
> держателя брошенного вызова и два абзаца документации.
> **Связанные записи:** `2026-11-26-async-job-1-0-5-release-report.md`,
> `2026-11-26-core-explorer-domain-report.md`.

# Выпуск async_job 1.0.6

По слову владельца 2026-11-27 «опубликуй async_job 1.0.6» — отдельный запрос,
состоящий только из просьбы опубликовать.

## Что в патче

Одна правка `lib/` после 1.0.5 — `e501fe10`, ветка `_race`
в `job_context.dart`. Если значение приходит после отмены, которой вызов
не услышал, — движок кончил задачу руками в каскаде отмены или исключение
бросил сырой колбэк отмены, зарегистрированный раньше вызова, — отмену получает
и держатель будущего, от которого ушло тело, а не уже освобождённое значение.
Значение уходит в `_releaseAbandoned`, и ещё живая задача ждёт его
освобождения, ждёт ли тело вызов или ушло от него. Разбор и тесты — разделы
«Разбор M10 и M13» и «Правка M10» `2026-11-26-core-explorer-domain-report.md`.

Документация, без правок кода:

- `b5a094ba` — абзац в «Finishing a job by hand» страницы `extending.md`:
  ручной `finish` не останавливает размотку, которая уже идёт; решение 166
  `docs/settled.md`;
- `16a61064` — абзац под таблицей «A value that comes late» `cleanup-rules.md`:
  после конца задачи держатель брошенного вызова получает значение уже
  освобождённым; решение 167.

Публичный API не тронут, раздела «Engine protocol» нет — по правилу
`docs/conventions.md` это патч.

## Зависимости и порядок

`solo` держит ядро в `>=1.0.0 <1.1.0`, `async_job_lints` и `solo_lints` —
в `^1.0.0`, scopo — в пределах минора; патч они получают сами. У самого ядра
оверрайдов нет. Семь оверрайдов пакетов выше ядра вернул `81075e43`, первая
строка каждого — «Until async_job 1.0.6 is published.»; в архив ядра они
не входят и снимаются после публикации своим коммитом. Нижнюю границу никто
не поднимает.

## Подготовка

Коммит `019b0cf3` «chore: prepare async_job 1.0.6»:

- `version: 1.0.6` в `packages/async_job/pubspec.yaml`;
- «Unreleased» в `CHANGELOG.md` стал разделом «1.0.6», с разделом
  «Documentation» о двух абзацах; в переводе `docs/ru/async_job/CHANGELOG.md`
  так же.

## Чем проверено

На дереве `019b0cf3`, Dart 3.14.0:

- `async_job`: формат — «0 changed», `dart analyze --fatal-infos` — «No issues
  found!», `dart test` — «+1936: All tests passed!», `dart doc --dry-run` —
  «Found 0 warnings and 0 errors.»; на полу Dart 3.10.0 тот же набор — «+1936:
  All tests passed!» на `e501fe10`;
- `solo` против ядра из дерева — «+2499: All tests passed!» на `e501fe10`;
- `dart pub publish --dry-run` в `packages/async_job` — «Publishing async_job
  1.0.6», «Package has 0 warnings.», `tool/` в списке нет;
- `check_translations.py` — «no differences», `check_links.py`,
  `check_dartdoc.py`, `check_line_width.py` и `reflow.py --check` чистые,
  `build_site.py` — «wrote 100 pages»;
- раскладка архивов и прогон на полу Flutter 3.38.1 — «every archive passes its
  gate on the floor: 7 roots»; пакеты выше ядра в раскладке идут с оверрайдами
  дерева, то есть против ядра 1.0.6.

CI `gate` и `site` по `79fbb087`, где уже лежат правка и её тесты, зелёные.

## Связка

Перед связкой: `main` впереди `origin/main` на коммиты от `16a61064`
и не отстаёт, тега `async_job-v1.0.6` нет ни локально, ни в origin, на pub.dev
`async_job` 1.0.5. Связка — релизный коммит «Release async_job 1.0.6» с этой
записью, аннотированный тег `async_job-v1.0.6` на нём, `git push --follow-tags`
и `dart pub publish` из чистого дерева `packages/async_job`. После неё —
коммит, снимающий семь оверрайдов, и проверки пакетов выше ядра против
опубликованного 1.0.6.
