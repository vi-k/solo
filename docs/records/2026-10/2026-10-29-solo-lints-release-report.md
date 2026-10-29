> **Состояние на 2026-10-29:** связка выпуска `solo_lints` 0.1.1 идёт; итог —
> в разделе «Связка» следующим коммитом.
> **Что это:** выпуск `solo_lints` 0.1.1 — правило `bare_await` и абзацы
> README об уровне правил, `dart fix` и двойных диагнозах Dart 3.12.
> **Связанные записи:** `2026-10-29-bare-await-design.md`,
> `2026-10-29-bare-await-report.md`, `2026-10-28-solo-lints-release-report.md`.

# Выпуск solo_lints 0.1.1

По отдельному запросу владельца 2026-10-29 «публикуй solo_lints 0.1.1»,
состоящему только из просьбы опубликовать. Версию 0.1.1 владелец назвал сам;
на pub.dev до выпуска одна версия, 0.1.0.

## Подготовка

Коммит `a886493a`: `version: 0.1.1` в `pubspec.yaml`, раздел «Unreleased»
списка изменений и «Не выпущено» перевода стали `## 0.1.1`, README и его
перевод ставят `solo_lints: ^0.1.1` — первую версию с `bare_await`, который
README описывает.

Оверрайдов в дереве нет. После выпуска 0.6.0 код нижних пакетов не менялся:
в `async_job` правлена только страница `doc/cleanup-rules.md`, поэтому тесты
`solo_lints` идут против опубликованных `async_job` и `solo` 0.6.0, как и при
0.1.0.

## Чем проверено

На `a886493a`, Dart 3.13.0:

- `packages/solo_lints`: формат — 28 файлов, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart doc --dry-run` — 0
  предупреждений и 0 ошибок; `dart test` — +191, All tests passed;
- `dart pub publish --dry-run` — 0 предупреждений;
- `check_translations.py`, `reflow.py --check`, `check_line_width.py`,
  `check_links.py`, `check_dartdoc.py` и `build_site_test.py` — зелёные.

Пол прогнан на `3083654b`, последнем коммите кода правила: раскладка всех
четырёх пакетов по 0 предупреждений, «every archive passes its gate on the
floor: 6 roots», а полный набор `solo_lints` на analyzer 12.1.0
и analyzer_testing 0.2.5 — +191. После него менялись только версия, список
изменений и README; подробности — `2026-10-29-bare-await-report.md`.

## Связка

Связка идёт подряд: коммит `Release solo_lints 0.1.1`, аннотированный тег
`solo_lints-v0.1.1`, push, `dart pub publish`. Итог — в этом разделе следующим
коммитом.
