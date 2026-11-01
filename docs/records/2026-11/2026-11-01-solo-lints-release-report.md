> **Состояние на 2026-11-01:** `solo_lints` 0.1.4 подготовлен коммитом
> «chore: prepare solo_lints 0.1.4» и ждёт отдельного слова владельца
> о публикации.
> **Что это:** подготовка патча `solo_lints` 0.1.4 под `async_job` и `solo`
> 1.0.0.
> **Связанные записи:** `2026-11-01-solo-release-report.md`,
> `2026-11-01-async-job-release-report.md`,
> `2026-10-29-solo-lints-release-report-3.md`.

# Выпуск solo_lints 0.1.4

По слову владельца 2026-11-01 «готовь solo_lints 0.1.4». Перед этим владелец
спросил, выпускать ли плагин как 1.0.0; я советовал патч. README опубликованных
`async_job` и `solo` 1.0.0 просят `solo_lints: ^0.1.3`, и это ограничение
пропускает только 0.1.x: минорный или мажорный выпуск плагина оставил бы их
блок установки на старой версии до следующих выпусков ядра и `solo`. Кроме
того, плагин стоит на `analysis_server_plugin` 0.3 и `analyzer_plugin` 0.14,
а что для правил ломающая правка — новое предупреждение, переименованный код, —
ни README, ни `docs/settled.md` не определяют. На pub.dev сейчас
`latest: 0.1.3`.

## Подготовка

Код правил с 0.1.1 не менялся. Правки:

- `version: 0.1.4`; dev-зависимости `async_job` и `solo` подняты с `^0.6.0`
  до `^1.0.0`;
- `packages/solo_lints/pubspec_overrides.yaml` удалён, удаление в индексе:
  тесты идут против опубликованных `async_job` и `solo` 1.0.0;
- README и перевод: блоки установки просят `^0.1.4` — сторож
  `test/readme_version_test.dart` требует версию пакета. В опубликованном
  README 0.1.3 там стоит `^0.1.1`;
- README и перевод больше не называют `wait` среди членов контекста в пяти
  перечнях правил `ctx_in_cleanup`, `release_on_the_call`,
  `catch_without_check`, `await_own_queue` и `bare_await`: в ядре 1.0
  `ctx.wait` нет. Правила его по-прежнему знают, решение 42 `docs/settled.md`,
  и раздел «Versions» теперь говорит это одной фразой;
- раздел `## 0.1.4` в `packages/solo_lints/CHANGELOG.md` и переводе.

README `async_job`, `solo` и `flutter_solo` и примеры остаются на `^0.1.3`: оно
пускает 0.1.4. Перевод README прошёл линтер `humanizer--ru`: 0 ошибок.

## Чем проверено

Против опубликованных пакетов: в `pubspec.lock` `async_job` 1.0.0 и `solo`
1.0.0, источник `hosted`.

- `packages/solo_lints`: формат — 29 файлов, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart test` — +192, All tests
  passed;
- `dart pub publish --dry-run` на чистом дереве — 0 предупреждений;
- `check_translations.py`, `reflow.py --check`, `check_line_width.py` —
  зелёные.

Пол на отсоединённой копии коммита подготовки: `tool/archive_floor.py stage` —
`solo_lints` 33 файла, 0 предупреждений и уже без подсказок об оверрайдах;
`async_job` 120 и `solo` 194 файла тоже без подсказок.
`tool/archive_floor.py run` на 3.38.1 — «every archive passes its gate on the
floor: 6 roots». `solo_lints` опускает `analysis_server_plugin`, `analyzer`
и `analyzer_plugin` до нижних границ, его набор из архива — +167 против
опубликованных `async_job` и `solo` 1.0.0; тест `mistakes_page_test.dart`
в архив не входит.

## Связка

Публикация — только по отдельному слову владельца: коммит
`Release solo_lints 0.1.4`, аннотированный тег `solo_lints-v0.1.4`, push
и `dart pub publish`.
