> **Состояние на 2026-10-28:** `solo` 0.6.0 опубликован на pub.dev;
> релизный коммит `87eef859` и аннотированный тег отправлены в origin.
> **Что это:** снятие оверрайдов `solo` и подготовка его выпуска 0.6.0.
> **Связанные записи:** `2026-10-28-async-job-release-report.md`,
> `2026-10-28-release-prep-report.md`, `2026-10-27-solo-release-report.md`.

# Выпуск solo 0.6.0

По слову владельца 2026-10-28 «готовь solo». На pub.dev сейчас `latest: 0.5.0`;
`async_job` 0.6.0 опубликован тем же днём,
`2026-10-28-async-job-release-report.md`.

## Подготовка

Оверрайды сняты: удалены `packages/solo/pubspec_overrides.yaml`
и `packages/solo/example/pubspec_overrides.yaml`, удаление в индексе
и в коммите `59360e9e`. Пакет и пример разрешают `async_job` 0.6.0 с pub.dev.
Оверрайды `solo_lints`, `flutter_solo` и примера `flutter_solo` остаются: им
нужен `solo` из дерева до его выпуска. Стенды `tool/doc_snippets.py`
и `tool/accumulation_snippets.py` по-прежнему ведут `async_job` на дерево;
дерево ядра совпадает с тегом `async_job-v0.6.0`.

Проверки против опубликованного ядра. В `pubspec.lock` пакета и примера
`async_job` 0.6.0, источник `hosted`, sha256 `317e8d8a…d464`.

- `packages/solo`: формат — 166 файлов, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart test` — +2209, All
  tests passed; `dart doc --dry-run` — 0 предупреждений и 0 ошибок;
- `packages/solo/example`: формат и анализ чистые; `dart test` — +112;
  `dart run bin/main.dart` отработал до `closed`;
- `dart pub publish --dry-run` — 0 предупреждений, подсказок об оверрайдах
  больше нет.

Пол на копии `59360e9e`, отсоединённой: `tool/archive_floor.py stage` —
`async_job` 119 и `solo` 189 файлов, по 0 предупреждений без подсказок;
`solo_lints` 30 и `flutter_solo` 46 файлов, по 0 предупреждений, с оверрайдами
дерева. `tool/archive_floor.py run` на 3.38.1 — «every archive passes its gate
on the floor: 6 roots». `solo` опускает до нижней границы и `async_job`
с pub.dev (`dart pub downgrade async_job meta`) — пакет +2198 при 11
пропущенных, пример +112, оба зелёные; так граница `async_job: ^0.6.0`
проверена по-настоящему. `async_job` +1885, `solo_lints` +122, `flutter_solo`
+254 и его пример +6 тоже зелёные.

## Связка

Владелец разрешил публикацию отдельным запросом «публикуй solo 0.6.0»,
состоящим только из просьбы опубликовать. Перед связкой: `git fetch` выполнен,
`origin/main` на `c560ff63` и вперёд от `main` не ушёл; коммиты `99947c6d`,
`59360e9e` и `fc8c2174` не пушились и уходят в origin вместе с релизным, CI
на них идёт уже после push. Тега `solo-v0.6.0` нет ни локально, ни в origin,
оверрайдов у пакета и примера нет, `dart pub publish --dry-run` — 0
предупреждений; на pub.dev `latest: 0.5.0`.

Связка выполнена подряд:

- `87eef859` — Release solo 0.6.0;
- аннотированный тег `solo-v0.6.0` указывает на `87eef859`;
- `origin/main` и тег отправлены, соответствие подтверждено `ls-remote`:
  `refs/heads/main` и `refs/tags/solo-v0.6.0^{}` дают `87eef859`;
- `dart pub publish --force` завершился успешно, сервер подтвердил загрузку:
  «Successfully uploaded https://pub.dev/packages/solo version 0.6.0»;
- API pub.dev вернул `latest: 0.6.0`;
- CI `gate` на `87eef859`: `dart`, `flutter`, `floor`, `snippets` и `docs`
  зелёные. `site` на этот push не запускался: его пути push не задел.

Пакет: https://pub.dev/packages/solo/versions/0.6.0

Выпуск завершён. scopo 0.21.0 под ядро 0.6.0 вышел тем же днём
(`async_job: ^0.6.0`); подготовка `flutter_solo` —
`2026-10-28-flutter-solo-release-report.md`. Оверрайды `solo_lints` на дерево
остались.
