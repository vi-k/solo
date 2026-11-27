> **Состояние на 2026-11-27:** выпущен по слову владельца «опубликуй
> async_job_lints 0.2.4»: релизный коммит «Release async_job_lints 0.2.4»,
> аннотированный тег `async_job_lints-v0.2.4`, `git push --follow-tags`,
> `dart pub publish`. Следом — связка `solo_lints` 0.4.0.
> **Что это:** подготовка патча `async_job_lints` 0.2.4 — распознавание пулов
> `SoloLanes` и четыре новых экспорта для плагина поверх.
> **Связанные записи:** `2026-11-27-solo-2-1-0-release-report.md`,
> `2026-11-27-solo-lints-0-4-0-release-report.md`,
> `2026-11-27-solo-pool-report.md`,
> `2026-11-19-async-job-lints-0-2-3-release-report.md`,
> `2026-11-18-async-job-lints-0-2-2-release-report.md`,
> `2026-11-27-pool-releases-prep-review-report.md`.

# Выпуск async_job_lints 0.2.4

По слову владельца 2026-11-27 «готовь выпуск async_job_lints, solo 2.1.0
и solo_lints». Слово понято как подготовка: разрешение на связку приходит
отдельным запросом, состоящим только из просьбы опубликовать.

## Что в выпуске

Раздел «0.2.4» `CHANGELOG.md` — задача 7 плана пула:

- `plugin_api.dart` экспортирует `isSoloQueueOwner`, `isSoloPool`,
  `declaresQueueOwner` и `isPoolField`;
- поле `SoloPool`, объявленное `pool(...)` в теле конструктора, — поле своей
  очереди для `queueLaneOf`: `bare_await` и `discarded_outcome` оставляют
  ожидание своего пула плагину поверх, как ожидание своей линии;
- `isSoloMember` принимает член пула за член `Solo`, как член линии;
- README говорит об ожидании своего пула в разделах `bare_await`
  и `discarded_outcome`.

## Почему патч

Новые экспорты и распознавание пула, которого в опубликованном `solo` ещё нет.
С тега `async_job_lints-v0.2.3` в тестах пакета не убрано ни строки, только
добавлены новые: на коде без пула правила сообщают то же, что 0.2.3. Новые
распознаватели для плагина поверх выходили патчем и раньше — 0.2.2 под
`solo_lints` 0.3.0 (`2026-11-18-async-job-lints-0-2-2-release-report.md`).

## Зависимости и порядок

Тесты пакета о пуле идут против `solo` 2.1.0: `dev_dependencies` просят
`solo: ^2.1.0`, а до выхода 2.1.0
`packages/async_job_lints/pubspec_overrides.yaml` ведёт на `solo` из дерева.
Снять оверрайд можно только после публикации: против 2.0.1 тесты пула
не соберутся.

`solo_lints` 0.4.0 просит `async_job_lints: ^0.2.4` и выходит следом.
Пользователь `solo_lints` 0.3.1 получит 0.2.4 и сам, через `^0.2.3`, и с ним
0.3.1 видит пулы: ожидание своего пула — его `await_own_queue` с сообщением
о линии, а не `bare_await` или `discarded_outcome`, `key_per_request`
и `ignore_failure_hides_bugs` принимают члены пула как члены линии, ложное
`outcome_after_await` о `job` пула уходит. Это сказано в разделе 0.2.4
`CHANGELOG.md`. Патч остаётся патчем, решение 172 `docs/settled.md`: для 0.3.1
это исправление, а новое предупреждение на коде, который проходил, бывает
только у кода с пулом, написанного против `solo` 2.1.0 до выхода 0.2.4.
До этого выхода опубликованные 0.2.3 и 0.3.1 на коде с пулом ложно
предупреждают, поэтому связка 0.2.4 идёт сразу за `solo`.

Подготовка живёт в ветке `pool-lints-release`, а не в `main`: README и пример
просят `^0.2.4`, и после пуша связки `solo` сайт показал бы эту версию раньше
pub.dev. Держит ветка только версии и заголовок раздела: тексты о пуле в README
и списке изменений уже в `main` и выйдут на сайт с пушем связки `solo`, решение
173 `docs/settled.md`.

## Подготовка

Коммит «chore: prepare async_job_lints 0.2.4», вместе с этой записью:

- `version: 0.2.4` и `solo: ^2.1.0` в `dev_dependencies`
  `packages/async_job_lints/pubspec.yaml`;
- «Unreleased» в `CHANGELOG.md` стал «0.2.4», «Не выпущено» в переводе тоже;
- README, перевод и `example/example.md` просят `^0.2.4` в обоих блоках README:
  этого требуют сторожа `readme_version_test.dart` и `example_page_test.dart`.

## Чем проверено

На дереве подготовки, против `solo` 2.1.0 из дерева: формат — «0 changed»,
`dart analyze --fatal-infos` — «No issues found!», `dart doc --dry-run` —
«Found 0 warnings and 0 errors.», `dart test` — +234; `tool/plugin_probe.py` —
«ok» на всех четырёх наборах. `check_translations.py` — «no differences»,
`check_links.py`, `check_line_width.py` и `reflow.py --check` чистые.

## После выхода solo 2.1.0

`solo` 2.1.0 вышел 2026-11-27. Коммит «chore: drop the overrides on solo»
удалил `packages/async_job_lints/pubspec_overrides.yaml` и снял его с индекса,
за ним на `main` встал коммит этой подготовки; коммит `solo_lints` остался
в ветке `pool-lints-release` до своей очереди.

Против `solo` 2.1.0 с pub.dev — в `pubspec.lock` «source: hosted», «version:
"2.1.0"»: формат — «0 changed», `dart analyze --fatal-infos` — «No issues
found!», `dart doc --dry-run` — «Found 0 warnings and 0 errors.», `dart test` —
+234; `tool/plugin_probe.py` — «ok» на всех четырёх наборах; раскладка архивов
и прогон на полу Flutter 3.38.1 — «every archive passes its gate on the floor:
7 roots»; `dart pub publish --dry-run` — «Package has 0 warnings.». Сайт
покажет 0.2.4 с пушем связки.

На 2026-11-27: на pub.dev `async_job_lints` 0.2.3; тега
`async_job_lints-v0.2.4` нет ни локально, ни в origin.

## Связка

Владелец разрешил публикацию 2026-11-27 отдельным запросом «опубликуй
async_job_lints 0.2.4», следующим сообщением после выхода `solo` 2.1.0. Перед
связкой на pub.dev стоял `async_job_lints` 0.2.3, тега `async_job_lints-v0.2.4`
не было ни локально, ни в origin, `main` был впереди `origin/main` на три
коммита — снятие оверрайдов на `solo`, эту подготовку и заметку о CI после
выхода `solo` — и не отставал от него. Пробная публикация на `38de299a` против
`solo` 2.1.0 с pub.dev — «Package has 0 warnings.».

Связка: релизный коммит «Release async_job_lints 0.2.4», аннотированный тег
`async_job_lints-v0.2.4`, `git push --follow-tags` и `dart pub publish --force`
из чистого дерева `packages/async_job_lints`.
