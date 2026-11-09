> **Состояние на 2026-11-09:** `solo_lints` 0.2.0 опубликован на pub.dev;
> релизный коммит `57bdb950` и аннотированный тег отправлены в origin.
> **Что это:** подготовка и связка минорного выпуска `solo_lints` 0.2.0,
> который приносит пользователям правила `async_job_lints` 0.2.0.
> **Связанные записи:** `2026-11-09-async-job-lints-0-2-0-release-report.md`,
> `2026-11-09-done-lints-report.md`, `2026-11-04-solo-lints-release-report.md`.

# Выпуск solo_lints 0.2.0

По второму слову владельца 2026-11-09 «публикуй» — отдельный запрос, состоящий
только из просьбы опубликовать. Им закрыт выпуск `solo_lints` 0.2.0, который
запись `2026-11-09-async-job-lints-0-2-0-release-report.md` и прошлое сообщение
владельцу называли следующей связкой.

## Что в выпуске

Зависимость `async_job_lints: ^0.2.0` вместо `^0.1.0`. С ней приходят два
предупреждения ядра о результате задачи, `discarded_outcome`
и `outcome_after_await`, включённые, как только плагин назван. `dart analyze`
падает на коде, который раньше проходил, поэтому выпуск минорный. Своих правил
`solo_lints` не меняет.

## Подготовка

Коммит `a783f833` «chore: prepare solo_lints 0.2.0»:

- `version: 0.2.0`, `async_job_lints: ^0.2.0`;
- снят `packages/solo_lints/pubspec_overrides.yaml` — оверрайд
  на `async_job_lints` из дерева, живший до выхода 0.2.0; удаление в индексе;
- README, перевод и `example/example.md` просят `^0.2.0` — сторож
  `test/readme_version_test.dart` требует версию пакета в README;
- раздел «Unreleased» `packages/solo_lints/CHANGELOG.md` стал `## 0.2.0`, «the
  next release is a minor one» — «the release is a minor one»; перевод — тем же
  коммитом.

README `solo` и `flutter_solo` и их примеры по-прежнему просят
`solo_lints: ^0.1.3`: сторож `test/readme_rakes_test.dart` обоих пакетов
требует, чтобы README называл ту версию, с которой анализируется пример,
а пример на `^0.2.0` до публикации не разрешился бы. Они поднимаются отдельной
правкой после выхода и дойдут до pub.dev со следующими выпусками `solo`
и `flutter_solo`.

## Чем проверено

- `packages/solo_lints` против опубликованных пакетов (`async_job_lints` 0.2.0,
  `async_job` 1.0.2, `solo` 1.0.1 из `pubspec.lock`): формат — 17 файлов, 0
  изменений; `dart analyze --fatal-infos` — без замечаний; `dart test` — +96,
  All tests passed; пример — без замечаний;
- сверка переводов, `reflow.py`, `check_line_width.py`, `check_links.py` —
  чисто;
- `dart pub publish --dry-run` на чистом дереве коммита подготовки — 0
  предупреждений, архив 23 KB.

Пол на том же чистом дереве: `tool/archive_floor.py stage` прошёл по всем пяти
пакетам без предупреждений и без подсказки об оверрайдах.
`tool/archive_floor.py run` на 3.38.1 — «every archive passes its gate on the
floor: 7 roots». `solo_lints` из архива разрешил `async_job_lints` 0.2.0
с pub.dev; `downgrade` его прямых зависимостей и `analyze lib` — ok, набор —
+71: `test/mistakes_page_test.dart` читает `packages/solo/doc/` и исключён
`.pubignore`.

## Связка

Перед связкой: тега `solo_lints-v0.2.0` нет ни локально, ни в origin;
на pub.dev `latest: 0.1.5`. Связка: релизный коммит «Release solo_lints 0.2.0»
с этой записью и handoff, аннотированный тег `solo_lints-v0.2.0` на нём,
`git push --follow-tags`, `dart pub publish` из чистого дерева.

Связка выполнена: релизный коммит `57bdb950` «Release solo_lints 0.2.0»,
аннотированный тег `solo_lints-v0.2.0` на нём, `git push --follow-tags`
отправил `main` (`000ed9a7..57bdb950`) и тег. `dart pub publish` из чистого
дерева: «Successfully uploaded https://pub.dev/packages/solo_lints version
0.2.0». API pub.dev отдаёт версию 0.2.0 с датой 2026-11-09T13:26:09Z.
