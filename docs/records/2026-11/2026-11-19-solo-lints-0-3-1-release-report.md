> **Состояние на 2026-11-19:** выпущено по слову владельца «публикуй»:
> релизный коммит «Release solo_lints 0.3.1», тег `solo_lints-v0.3.1`,
> `dart pub publish`.
> **Что это:** подготовка патча `solo_lints` 0.3.1 — граница
> `async_job_lints: ^0.2.3` и снятый оверрайд.
> **Связанные записи:** `2026-11-19-async-job-lints-0-2-3-release-report.md`,
> `2026-11-18-solo-lanes-astra-review-report.md`,
> `2026-11-18-solo-lints-0-3-0-release-report.md`.

# Выпуск solo_lints 0.3.1

По слову владельца 2026-11-19 «Готовь solo_lints», сразу после публикации
`async_job_lints` 0.2.3.

## Что в выпуске

`async_job_lints` 0.2.3 исправил распознавание тела задачи: ребёнок задачи
чужого контроллера идёт в том контроллере, а вызов на `super` свой, как
на `this`. Правила `await_own_queue` и `stale_emit` спрашивают его об этом,
и тесты `solo_lints` на ребёнка и на `super` проходят только с ним.
Пользователь `solo_lints` 0.3.0 получает исправление и так: `^0.2.2` пускает
0.2.3. Выпуск поднимает нижнюю границу до `^0.2.3`, чтобы исправление
не зависело от того, что разрешит `pub`. Новых правил нет, поэтому патч.

## Подготовка

- `packages/solo_lints/pubspec_overrides.yaml` удалён и снят с индекса
  (`git rm`): `dart pub publish` ругается на файл, которого нет в дереве;
- `version: 0.3.1` и `async_job_lints: ^0.2.3` в `pubspec.yaml`;
- раздел «0.3.1» в `CHANGELOG.md` и переводе;
- README, перевод и `example/example.md` просят `^0.3.1`: этого требуют сторожа
  `readme_version_test.dart` и `example_page_test.dart`. README и примеры
  `solo` и `flutter_solo` остаются на `^0.3.0`: патч доходит сам.

`check_translations.py` — «no differences».

## Чем проверено

На дереве подготовки, без оверрайда:

- `solo_lints` разрешает `async_job_lints` 0.2.3 с pub.dev; формат — «0
  changed», `dart analyze --fatal-infos` — «No issues found!»,
  `dart doc --dry-run` — «Found 0 warnings and 0 errors.», `dart test` — +163;
- `dart pub publish --dry-run` — «Publishing solo_lints 0.3.1», «Package has 0
  warnings.»;
- `tool/plugin_probe.py` — оба плагина и их пары «ok»; `tool/build_site.py` —
  100 страниц;
- пол Flutter 3.38.1, раскладка архивов без оверрайдов — «every archive passes
  its gate on the floor: 7 roots»: `async_job` +1917, `solo` +2484,
  `async_job_lints` +231, `solo_lints` +132 после `pub downgrade`
  до `async_job_lints` 0.2.3 с pub.dev, `flutter_solo` +344.

## Состояние

2026-11-19 по слову владельца «публикуй» — связка: релизный коммит «Release
solo_lints 0.3.1», аннотированный тег `solo_lints-v0.3.1`,
`git push --follow-tags` и `dart pub publish --force` из чистого дерева
`packages/solo_lints`. Перед связкой на pub.dev стояла 0.3.0, тега 0.3.1
не было ни локально, ни в origin.
