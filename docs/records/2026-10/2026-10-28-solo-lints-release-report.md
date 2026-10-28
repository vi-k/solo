> **Состояние на 2026-10-28:** связка выпуска `solo_lints` 0.1.0 идёт; итог —
> в разделе «Связка» следующим коммитом.
> **Что это:** снятие оверрайдов `solo_lints` и первый выпуск пакета, 0.1.0.
> **Связанные записи:** `2026-10-28-solo-lints-report.md`,
> `2026-10-28-solo-lints-wave-2-report.md`,
> `2026-10-28-solo-release-report.md`,
> `2026-10-28-release-prep-report.md`.

# Выпуск solo_lints 0.1.0

По слову владельца 2026-10-28 «готовь solo_lints», затем отдельным запросом
«публикуй solo_lints 0.1.0», состоящим только из просьбы опубликовать. Это
первый выпуск: имени `solo_lints` на pub.dev нет, API отвечает 404. `async_job`
0.6.0 и `solo` 0.6.0, под имена которых подогнаны правила, вышли тем же днём.

## Подготовка

Оверрайды сняты: удалён `packages/solo_lints/pubspec_overrides.yaml`, удаление
в индексе и в коммите `87188b74`. Оба оверрайда вели `async_job` и `solo`
на дерево; теперь тесты разрешают их с pub.dev. Других `pubspec_overrides.yaml`
в дереве не осталось.

Версия 0.1.0, заголовок `## 0.1.0` списка изменений и границы
`async_job: ^0.6.0` и `solo: ^0.6.0` в dev-зависимостях поставлены раньше:
первая волна и общая подготовка, `2026-10-28-solo-lints-report.md`
и `2026-10-28-release-prep-report.md`.

## Чем проверено

Проверки задания `dart` для пакета, повторённые локально на Dart 3.13.0.
В `pubspec.lock` `async_job` 0.6.0 (sha256 `317e8d8a…d464`) и `solo` 0.6.0
(`8dfc849e…d5de`), оба с pub.dev.

- `packages/solo_lints`: формат — 26 файлов, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart doc --dry-run` — 0
  предупреждений и 0 ошибок; `dart test` — +147, All tests passed;
- `dart pub publish --dry-run` на `87188b74` — 0 предупреждений.

Пол на копии `87188b74`, отсоединённой: `tool/archive_floor.py stage` —
`async_job` 119, `solo` 189, `solo_lints` 30 и `flutter_solo` 45 файлов, все
по 0 предупреждений, оверрайдов в раскладке больше нет.
`tool/archive_floor.py run` на 3.38.1 — «every archive passes its gate on the
floor: 6 roots». `solo_lints` опускает `analysis_server_plugin`, `analyzer`
и `analyzer_plugin` до нижних границ — +122 в архиве, где нет
`test/mistakes_page_test.dart`; `async_job` +1885, `solo` +2198 при 11
пропущенных, его пример +112, `flutter_solo` +254, его пример +6.

## Связка

Связка идёт подряд: коммит `Release solo_lints 0.1.0`, аннотированный тег
`solo_lints-v0.1.0`, push, `dart pub publish`. Итог — в этом разделе следующим
коммитом.
