> **Состояние на 2026-11-19:** выпущено по слову владельца «публикуй»:
> релизные коммиты «Release solo 2.0.1» и «Release flutter_solo 2.0.1»,
> теги `solo-v2.0.1` и `flutter_solo-v2.0.1`, оба пакета на pub.dev.
> **Что это:** подготовка патчей `solo` 2.0.1 и `flutter_solo` 2.0.1 —
> документация после 2.0.0.
> **Связанные записи:** `2026-11-18-solo-2-0-0-release-report.md`,
> `2026-11-18-flutter-solo-2-0-0-release-report.md`,
> `2026-11-18-solo-lanes-astra-review-report.md`,
> `2026-11-18-solo-lints-0-3-0-release-report.md`,
> `2026-11-19-solo-lints-0-3-1-release-report.md`.

# Выпуск solo 2.0.1 и flutter_solo 2.0.1

По слову владельца 2026-11-19 «Готовь solo 2.0.1 и flutter_solo 2.0.1».

## Что в патчах

Только документация, кода пакетов выпуск не меняет, поэтому патч, как `solo`
1.1.1.

- `solo`: README просит `solo_lints: ^0.3.0`, с которым приходят предупреждение
  `lane_outside_constructor` и линт `stale_emit`. В `doc/lanes.md` четыре
  правки после 2.0.0: абзац о `stale_emit` в разделе «A read at the write»;
  лента раздела «A merge», которая после упавшего или отменённого лайка
  не возвращает подтверждённую отметку, покрытую постами перезагрузки;
  исправленное объяснение записей `StudioController` в разделе «W on a record»;
  строка таблицы о `droppable` во время дренажа. Ещё исправлен пункт 2.0.0
  о кадрах стека. Это итоги находок Important 1, Minor 3, Minor 4 и Minor 6
  из `2026-11-18-solo-lanes-astra-review-report.md` (коммит `3e58a87d`) и абзац
  о `stale_emit`, пришедший с правилом (`1cc41ffe`).
- `flutter_solo`: README просит `solo_lints: ^0.3.0`.

Раздел «Unreleased» `solo` называл две правки из шести — README и ленту;
остальные четыре легли в `main` без строки в CHANGELOG и дописаны при
подготовке, с переводом.

Разделы «Unreleased» обоих CHANGELOG и «Не выпущено» их переводов стали
«2.0.1». `flutter_solo` по-прежнему требует `solo: ^2.0.0`: новых членов `solo`
2.0.1 не приносит, и поднимать границу незачем. Ядро не меняется, поэтому
выпуск scopo между пакетами не нужен, и оверрайдов в дереве нет.

## Порядок

Снизу вверх: сначала `solo` 2.0.1, потом `flutter_solo` 2.0.1. Каждая связка —
релизный коммит «Release <пакет> 2.0.1», аннотированный тег `<пакет>-v2.0.1`,
`git push --follow-tags` и `dart pub publish` из чистого дерева пакета.

## Чем проверено

На дереве подготовки, без оверрайдов:

- `solo`: формат — «0 changed», `dart analyze --fatal-infos` — «No issues
  found!», `dart doc --dry-run` — «Found 0 warnings and 0 errors.»,
  `dart test` — +2498; пример — анализ чистый, +112;
- `flutter_solo`: формат — «0 changed», `flutter analyze`
  и `dart analyze --fatal-infos` чистые, `dart doc --dry-run` — «Found 0
  warnings and 0 errors.», `flutter test` — +344;
- `dart pub publish --dry-run` у `solo` и `flutter pub publish --dry-run`
  у `flutter_solo` на закоммиченном дереве — «Package has 0 warnings.»;
- `check_translations.py` — «no differences», `check_links.py`,
  `check_doc_shape.py`, `check_dartdoc.py`, `reflow.py --check`
  и `check_line_width.py` чистые; `build_site.py` — 100 страниц;
- пол Flutter 3.38.1, раскладка архивов — «every archive passes its gate on the
  floor: 7 roots»: `async_job` +1917, `solo` +2484, пример `solo` +112,
  `async_job_lints` +231, `solo_lints` +132, `flutter_solo` +344, пример
  `flutter_solo` +6.

## Связка

Владелец разрешил публикацию 2026-11-19 отдельным запросом «публикуй»,
следующим сообщением после подготовки; запрос покрывает оба пакета. Перед
связками на pub.dev стояли `solo` 2.0.0 и `flutter_solo` 2.0.0, тегов
`solo-v2.0.1` и `flutter_solo-v2.0.1` не было ни локально, ни в origin, `main`
был впереди `origin/main` на подготовку и правку handoff — они уходят в origin
вместе с релизным коммитом `solo`.

Связка `solo`: релизный коммит «Release solo 2.0.1», аннотированный тег
`solo-v2.0.1`, `git push --follow-tags` и `dart pub publish --force` из чистого
дерева `packages/solo`.

Связка `solo` прошла подряд: релизный коммит `540f8607` «Release solo 2.0.1»,
аннотированный тег `solo-v2.0.1` на нём, `git push --follow-tags` —
`origin/main` с `5ae8079f` на `540f8607` вместе с тегом, —
и `dart pub publish --force` из чистого дерева `packages/solo`: «Successfully
uploaded … version 2.0.1». Следом идёт связка `flutter_solo` 2.0.1.

Связка `flutter_solo`: релизный коммит «Release flutter_solo 2.0.1»,
аннотированный тег `flutter_solo-v2.0.1`, `git push --follow-tags`
и `flutter pub publish --force` из чистого дерева `packages/flutter_solo`.
