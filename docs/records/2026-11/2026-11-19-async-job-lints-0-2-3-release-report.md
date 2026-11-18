> **Состояние на 2026-11-19:** выпущено по слову владельца «публикуй»:
> релизный коммит «Release async_job_lints 0.2.3», тег
> `async_job_lints-v0.2.3`, `dart pub publish`. Следом — выпуск
> `solo_lints` со снятием оверрайда и границей `^0.2.3`.
> **Что это:** подготовка патча `async_job_lints` 0.2.3 — правки распознавания
> тела задачи по находкам повторного ревью ветки `solo-lanes`.
> **Связанные записи:** `2026-11-18-solo-lanes-astra-review-report.md`,
> `2026-11-18-async-job-lints-0-2-2-release-report.md`,
> `2026-11-18-solo-lints-0-3-0-release-report.md`.

# Выпуск async_job_lints 0.2.3

По слову владельца 2026-11-19 «Готовь async_job_lints 0.2.3».

## Что в выпуске

Раздел «0.2.3» `CHANGELOG.md` и перевода — коммит `cdada4c3`, Important 2 и 5
повторного ревью:

- `queuedBodyOf` относит ребёнка, сделанного на контексте задачи другого
  контроллера, к тому контроллеру: `await_own_queue` и `stale_emit`
  из `solo_lints` больше не сообщают о `close()` и `emit` в ребёнке задачи,
  которую `SoloLanes` передаёт `Solo`;
- вызов на `super` свой для контроллера, как и на `this`: `await super.close()`
  в теле задачи ждёт своей очереди, а тело из `super.enqueue(...)` поставлено
  здесь.

Правила самого пакета, `bare_await` и `discarded_outcome`, зовут изменённые
функции только затем, чтобы промолчать там, где о том же ожидании сообщает
плагин поверх. Новых правил нет; исправление меняет, где диагностики стоят,
поэтому патч, как и 0.2.2.

## Зависимости и порядок

`solo_lints` 0.3.0 просит `async_job_lints: ^0.2.2`, и патч доходит до его
пользователей сам. Тестам `solo_lints` в дереве нужен 0.2.3: новые тесты
о ребёнке чужого контроллера и о `super` на 0.2.2 красные. Поэтому
`packages/solo_lints/pubspec_overrides.yaml` ведёт на `async_job_lints`
из дерева, первая строка — «Until async_job_lints 0.2.3 is published.». После
публикации следующий выпуск `solo_lints` снимает оверрайд и поднимает границу
до `^0.2.3`; снять его раньше нельзя — тесты `solo_lints` покраснеют против
0.2.2.

## Подготовка

- `version: 0.2.3` в `packages/async_job_lints/pubspec.yaml`;
- «Unreleased» в `CHANGELOG.md` стал «0.2.3», «Не выпущено» в переводе тоже;
- README, перевод и `example/example.md` просят `^0.2.3`: этого требуют сторожа
  `readme_version_test.dart` и `example_page_test.dart`.

`check_translations.py` — «no differences».

## Чем проверено

На дереве подготовки:

- `async_job_lints`: формат — «0 changed», `dart analyze --fatal-infos` — «No
  issues found!», `dart doc --dry-run` — «Found 0 warnings and 0 errors.»,
  `dart test` — +231;
- `solo_lints` против `async_job_lints` из дерева: формат — «0 changed», анализ
  чистый, `dart test` — +163.
- `dart pub publish --dry-run` в `packages/async_job_lints` — «Publishing
  async_job_lints 0.2.3», «Package has 0 warnings.»;
- `tool/plugin_probe.py` — «ok» на обоих наборах плагинов;
  `check_translations.py`, `check_links.py`, `check_dartdoc.py`,
  `check_line_width.py` и `reflow.py --check` чистые, `build_site.py` — «wrote
  100 pages»;
- раскладка архивов и прогон на полу Flutter 3.38.1 — «every archive passes its
  gate on the floor: 7 roots»; из архива `async_job` +1917, `solo` +2484,
  `async_job_lints` +231, `solo_lints` +132 с оверрайдом дерева.

## Состояние

2026-11-19 по слову владельца «публикуй» — связка: релизный коммит «Release
async_job_lints 0.2.3», аннотированный тег `async_job_lints-v0.2.3`,
`git push --follow-tags` и `dart pub publish --force` из чистого дерева
`packages/async_job_lints`. Перед связкой на pub.dev стояла 0.2.2, тега 0.2.3
не было ни локально, ни в origin.
