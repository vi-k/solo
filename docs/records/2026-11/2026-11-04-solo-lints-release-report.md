> **Состояние на 2026-11-04:** релизный коммит «Release solo_lints 0.1.5»
> готов, публикация идёт следом той же связкой.
> **Что это:** подготовка патча `solo_lints` 0.1.5, который зависит
> от опубликованного `async_job_lints` 0.1.0.
> **Связанные записи:** `2026-11-04-async-job-lints-release-report.md`,
> `2026-11-03-lints-split-report.md`,
> `2026-11-01-solo-lints-release-report.md`.

# Выпуск solo_lints 0.1.5

По слову владельца 2026-11-04 «готовь solo_lints». Второй шаг порядка выпусков
из `docs/handoff.md`, после `async_job_lints` 0.1.0. Версия — патч, как решено
дизайном `2026-11-03-lints-split-design.md`: README опубликованных `solo`
и `flutter_solo` просят `solo_lints: ^0.1.3`, и это ограничение пропускает
только 0.1.x.

## Подготовка

Код правил с раздела линтов не менялся. Правки:

- `version: 0.1.5`;
- `packages/solo_lints/pubspec_overrides.yaml` удалён, удаление в индексе:
  пакет и его тесты идут против опубликованного `async_job_lints` 0.1.0;
- README, перевод и `example/example.md` просят `^0.1.5` — сторож
  `test/readme_version_test.dart` требует версию пакета в README;
- раздел «Unreleased» `packages/solo_lints/CHANGELOG.md` стал `## 0.1.5`,
  с пунктом о блоках README; перевод — тем же коммитом.

README `solo` и `flutter_solo` остаются на `^0.1.3`: оно пускает 0.1.5. Перевод
списка изменений прошёл линтер `humanizer--ru`: 0 ошибок; сверка переводов
чиста.

## Чем проверено

Против опубликованных пакетов: в `pubspec.lock` `async_job_lints` 0.1.0,
`async_job` и `solo` 1.0.0, источник `hosted`.

- `packages/solo_lints`: формат — 17 файлов, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart test` — +96, All tests
  passed;
- `dart pub publish --dry-run` на чистом дереве коммита подготовки —
  предупреждений нет.

Пол на том же чистом дереве: `tool/archive_floor.py stage` — у `solo_lints`
в архиве 22 файла, 0 предупреждений и без подсказки об оверрайдах; `async_job`
120, `solo` 195, `async_job_lints` 30 и `flutter_solo` 45 файлов тоже без
предупреждений. `tool/archive_floor.py run` на 3.38.1 — «every archive passes
its gate on the floor: 7 roots». `solo_lints` опускает
`analysis_server_plugin`, `analyzer`, `analyzer_plugin` и `async_job_lints`
до нижних границ, его набор из архива — +71 против опубликованных пакетов; тест
`mistakes_page_test.dart` в архив не входит.

## Связка

Владелец разрешил публикацию отдельным запросом «опубликуй solo_lints 0.1.5»,
состоящим только из просьбы опубликовать. Перед связкой: `git fetch` выполнен,
`origin/main` на `d74c0bf2`, релизном коммите `async_job_lints` 0.1.0. `main`
впереди на три коммита — Node 26 для сборки сайта, подготовка и записи, — они
уходят в origin вместе с релизным. Тега `solo_lints-v0.1.5` нет ни локально,
ни в origin; на pub.dev `latest: 0.1.4`.
