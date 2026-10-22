> **Состояние на 2026-10-23:** связка выпуска `solo` 0.3.0 выполняется
> релизным коммитом; итог публикации дописывается следующим коммитом.
> **Что это:** снятие оверрайдов `solo` и выполнение разрешённой владельцем
> связки выпуска `solo`.
> **Связанные записи:** `2026-10-23-async-job-release-report.md`,
> `2026-10-22-release-check-report.md`,
> `2026-09-11[2]-solo-release-report.md`.

# Выпуск solo 0.3.0

Владелец разрешил публикацию отдельным запросом «публикуй solo», состоящим
только из просьбы опубликовать. Публикуется `solo` 0.3.0 из `main` поверх
`8e9de566`, после выпуска `async_job` 0.3.0. На pub.dev сейчас `latest: 0.2.0`.

## Подготовка

Оверрайды сняты: удалены `packages/solo/pubspec_overrides.yaml`
и `packages/solo/example/pubspec_overrides.yaml`, удаление добавлено в индекс.
Пакет и пример разрешают `async_job` 0.3.0 с pub.dev. Оверрайды `flutter_solo`
и его примера остаются: им нужен `solo` из дерева до его выпуска. Стенды
`tool/doc_snippets.py` и `tool/accumulation_snippets.py` по-прежнему ведут
`async_job` на дерево; дерево ядра совпадает с тегом `async_job-v0.3.0`.

Проверки против опубликованного ядра. В `pubspec.lock` пакета и примера
`async_job` 0.3.0, источник `hosted`, sha256 `3f32d2bc…01fe`.

- `packages/solo`: формат — 155 файлов, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart test` — +2070, All
  tests passed; `dart doc --dry-run` — 0 предупреждений и 0 ошибок;
- `packages/solo/example`: формат — 12 файлов, 0 изменений; анализ чистый;
  `dart test` — +112; `dart run bin/main.dart` отработал до `closed`;
- `dart pub publish --dry-run` — 0 предупреждений, подсказок об оверрайдах
  больше нет.

Пол 3.27.0 локально не перезапускался: он прошёл
в `2026-10-22-release-check-report.md` на том же коде, а нижняя граница
`async_job: ^0.3.0` совпадает с опубликованной версией. Задание `floor` CI
проверит раскладку после push.
