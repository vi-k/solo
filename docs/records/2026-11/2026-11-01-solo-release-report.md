> **Состояние на 2026-11-01:** `solo` 1.0.0 опубликован на pub.dev; релизный
> коммит `d6c1049b` и аннотированный тег отправлены в origin.
> **Что это:** снятие оверрайдов `solo` и выполнение разрешённой владельцем
> связки его выпуска 1.0.0.
> **Связанные записи:** `2026-11-01-async-job-release-report.md`,
> `2026-10-30-one-zero-report.md`, `2026-10-31-fable-review-wave-report.md`,
> `2026-10-28-solo-release-report.md`.

# Выпуск solo 1.0.0

Владелец разрешил публикацию отдельным запросом «опубликуй async_job и solo
1.0.0», состоящим только из просьбы опубликовать. `async_job` 1.0.0 вышел
первым своей связкой, `2026-11-01-async-job-release-report.md`; на pub.dev
у `solo` сейчас `latest: 0.6.0`. `flutter_solo` и `solo_lints` не публикуются:
`flutter_solo` ждёт scopo под ядро 1.0, `solo_lints` выходит своей связкой.

## Подготовка

Оверрайды сняты: удалены `packages/solo/pubspec_overrides.yaml`
и `packages/solo/example/pubspec_overrides.yaml`, удаление в индексе
и в коммите `9e90db32`. Оба вели на дерево только `async_job`. Пакет и пример
разрешают `async_job` 1.0.0 с pub.dev, ограничение `'>=1.0.0 <1.1.0'`.
Оверрайды `solo_lints`, `flutter_solo` и примера `flutter_solo` остаются: им
нужен `solo` из дерева до его выпуска. Дерево ядра совпадает с тегом
`async_job-v1.0.0`.

Проверки против опубликованного ядра. В `pubspec.lock` пакета и примера
`async_job` 1.0.0, источник `hosted`, sha256 `30c0a627…a915`. Первый
`dart pub get` упал на устаревшем кэше списка версий, повтор разрешил.

- `packages/solo`: формат — 171 файл, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart test` — +2229, All
  tests passed; `dart doc --dry-run` — 0 предупреждений и 0 ошибок;
- `packages/solo/example`: формат — 13 файлов, 0 изменений, анализ чистый;
  `dart test` — +112; `dart run bin/main.dart` отработал до `closed`;
- `dart pub publish --dry-run` — 0 предупреждений, подсказок об оверрайдах
  больше нет.

Пол на отсоединённой копии `9e90db32`: `tool/archive_floor.py stage` —
`async_job` 120 и `solo` 194 файла, по 0 предупреждений без подсказок;
`solo_lints` 33 и `flutter_solo` 46 файлов, по 0 предупреждений, с оверрайдами
дерева. `tool/archive_floor.py run` на 3.38.1 — «every archive passes its gate
on the floor: 6 roots». `solo` опускает до нижней границы и `async_job`
с pub.dev (`dart pub downgrade async_job meta`) — пакет +2218 при 11
пропущенных, пример +112, оба зелёные; так граница
`async_job: '>=1.0.0 <1.1.0'` проверена по опубликованному архиву. `async_job`
+1889, `solo_lints` +167, `flutter_solo` +255 и его пример +6 тоже зелёные.

## Связка

Перед связкой: `git fetch` выполнен, `origin/main` на `584a6545` и совпадает
с `main`; коммит `9e90db32` уходит в origin вместе с релизным. Тега
`solo-v1.0.0` нет ни локально, ни в origin; на pub.dev `latest: 0.6.0`.

Связка выполнена подряд:

- `d6c1049b` — Release solo 1.0.0;
- аннотированный тег `solo-v1.0.0` указывает на `d6c1049b`;
- `origin/main` и тег отправлены, соответствие подтверждено `ls-remote`:
  `refs/heads/main` и `refs/tags/solo-v1.0.0^{}` дают `d6c1049b`;
- `dart pub publish --force` завершился успешно, сервер подтвердил загрузку:
  «Successfully uploaded https://pub.dev/packages/solo version 1.0.0»;
- API pub.dev вернул `latest: 1.0.0`;
- CI `gate` на `d6c1049b`: `dart`, `flutter`, `floor`, `snippets` и `docs`
  зелёные. `site` на этот push не запускался: его пути push не задел.

Пакет: https://pub.dev/packages/solo/versions/1.0.0

Выпуск завершён. Оверрайды `solo_lints`, `flutter_solo` и примера
`flutter_solo` на дерево остались. `flutter_solo` 1.0.0 выходит после scopo под
ядро 1.0: опубликованный scopo 0.21.2 требует `async_job: ^0.6.0`.
