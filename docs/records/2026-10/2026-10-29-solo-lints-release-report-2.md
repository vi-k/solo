> **Состояние на 2026-10-29:** связка выпуска `solo_lints` 0.1.2 идёт:
> релизный коммит этой записи, тег, push и `dart pub publish`.
> **Что это:** выпуск `solo_lints` 0.1.2 — README больше не говорит, что
> диагностики плагина показывает `flutter analyze`.
> **Связанные записи:** `2026-10-29-solo-lints-release-report.md`,
> `2026-10-29-example-lints-report.md`.

# Выпуск solo_lints 0.1.2

По отдельному запросу владельца 2026-10-29 «публикуй solo_lints 0.1.2»,
состоящему только из просьбы опубликовать. На pub.dev до выпуска последняя
версия — 0.1.1.

Выпуск патчевый и состоит из одной правки README и перевода: начиная с Flutter
3.44 `flutter analyze` диагностик плагина не показывает, и во Flutter-пакете
плагин проверяют через `dart analyze`. Как это нашлось —
`2026-10-29-example-lints-report.md`. Код плагина с 0.1.1 не менялся.

## Подготовка

Коммит `b32bfe73`: `version: 0.1.2` в `pubspec.yaml`, раздел «Unreleased»
списка изменений и «Не выпущено» перевода стали `## 0.1.2`. Версия в README
плагина, в README трёх пакетов и в примерах остаётся `^0.1.1`: она пускает
и 0.1.2.

Оверрайдов в дереве нет; тесты `solo_lints` идут против опубликованных
`async_job` и `solo` 0.6.0.

## Чем проверено

На `b32bfe73`, Dart 3.13.0:

- `packages/solo_lints`: формат — 28 файлов, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart test` — +191, All tests
  passed;
- `dart pub publish --dry-run` — 0 предупреждений;
- `check_translations.py`, `reflow.py --check`, `check_line_width.py` —
  зелёные.

Пол прогнан на `c99ae07c`: раскладка всех четырёх пакетов по 0 предупреждений,
«every archive passes its gate on the floor: 6 roots», `solo_lints` +166
на нижних границах зависимостей. После него менялись только документы, версия
и список изменений. CI `gate` на `cc97601c` — все пять заданий зелёные.

## Связка

Перед связкой: `git fetch` выполнен, `origin/main` на `cc97601c`, ветка впереди
на `b32bfe73`; тега `solo_lints-v0.1.2` нет ни локально, ни в origin; API
pub.dev — `latest: 0.1.1`.

Связка идёт: коммит `Release solo_lints 0.1.2` с этой записью, аннотированный
тег `solo_lints-v0.1.2`, `git push --follow-tags`, `dart pub publish`. Итог
допишется следующим коммитом.
