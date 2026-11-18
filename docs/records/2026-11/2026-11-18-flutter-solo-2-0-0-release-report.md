> **Состояние на 2026-11-18:** подготовлено, не выпущено: коммит подготовки
> `b2000190` «chore: prepare flutter_solo 2.0.0», проверки пройдены. Связка —
> по отдельному слову владельца.
> **Что это:** подготовка мажорного выпуска `flutter_solo` 2.0.0 — виджеты
> принимают `SoloController`, `SoloListenable` подмешивается и в `SoloLanes`.
> **Связанные записи:** `2026-11-18-solo-2-0-0-release-report.md`,
> `2026-11-11-solo-lanes-report.md`, `2026-11-11-solo-lanes-plan.md`,
> `2026-11-13-device-app-plan.md`,
> `2026-11-10-flutter-solo-1-1-0-release-report.md`.

# Выпуск flutter_solo 2.0.0

По слову владельца 2026-11-18 «Готовь выпуск flutter_solo 2.0.0». Слово понято
как подготовка: разрешение на связку приходит отдельным запросом, состоящим
только из просьбы опубликовать.

## Что в выпуске

Раздел «Unreleased» `CHANGELOG.md`: часть A ветки линий для `flutter_solo`
и страница приложения устройства.

- Пакет реэкспортирует `solo`, и с выпуском приходят `SoloLanes`
  и `SoloController` из `solo` 2.0.0.
- Ломающие изменения: поле `solo` у `SoloBuilder`, `SoloSelector`
  и `SoloListener` и контроллер, который берёт `SoloSelection.from`, — теперь
  `SoloController<S>`, а не `Solo<S>`; `SoloListenable` — миксин
  на `SoloController`, а не подтип `Solo`. Поэтому выпуск мажорный, по таблице
  версионирования README.
- Документация: README и dartdoc библиотеки об очередях `Solo` и линий, раздел
  «A base for both kinds» в `doc/mixins.md` и новая страница
  `doc/device-app.md` о приложении камеры (`2026-11-13-device-app-plan.md`).

## Зависимости и порядок

`flutter_solo` требует `solo: ^2.0.0`; `solo` 2.0.0 вышел 2026-11-18
(`2026-11-18-solo-2-0-0-release-report.md`) и держит ядро в `>=1.0.0 <1.1.0`.
scopo 1.0.0 на pub.dev, dev-зависимость пакета и зависимость приложения
`camera_example`, держит то же ядро, поэтому ждать scopo не нужно.

README просит `solo_lints: ^0.2.0`, и это ограничение пускает вышедший
`solo_lints` 0.2.1, который знает линии; строка не поднимается. Версию пакета
README не называет.

Приложение `camera_example` в архив не входит (`.pubignore`). Его код с прогона
на телефонах 2026-11-17 не менялся; подготовка меняет у него только оверрайд.

## Подготовка

Коммит `b2000190` «chore: prepare flutter_solo 2.0.0»:

- `version: 2.0.0` в `packages/flutter_solo/pubspec.yaml`;
- сняты три оверрайда на `solo` из дерева, живших до выхода 2.0.0, —
  `pubspec_overrides.yaml` у `packages/flutter_solo`, у его `example`
  и у `camera_example`; удаления в индексе. Пример и приложение зависят
  от `flutter_solo` путём `../`, и оверрайд на него не нужен;
- «Unreleased» в `CHANGELOG.md` стал разделом «2.0.0», в переводе
  `docs/ru/flutter_solo/CHANGELOG.md` «Не выпущено» тоже;
  `check_translations.py` — «no differences».

После неё в дереве не остаётся ни одного `pubspec_overrides.yaml`.

## Чем проверено

На чистом дереве `b2000190`, Flutter 3.50 и Dart 3.14:

- `flutter_solo`, его пример и `camera_example` после `flutter pub get`
  разрешились против опубликованного `solo` 2.0.0 (в `package_config.json` всех
  трёх — `solo-2.0.0` из кэша pub.dev);
- `flutter_solo`: формат — «0 changed», `flutter analyze`
  и `dart analyze --fatal-infos` — «No issues found!», `flutter test` — «+344:
  All tests passed!», `dart doc --dry-run` — «Found 0 warnings and 0 errors.»;
- пример: формат и анализ чистые, `flutter test` — «+6: All tests passed!»;
- `camera_example`: формат `lib test integration_test` и оба анализа чистые,
  `flutter test` — «+291: All tests passed!»;
- стенд `tool/flutter_snippets.py`: анализ чистый, «+59: All tests passed!»,
  `check_traces.py` по `doc/mixins.md` — «every quoted trace is what the bench
  prints»;
- `dart pub publish --dry-run` в `packages/flutter_solo` — «Publishing
  flutter_solo 2.0.0», «Package has 0 warnings.»;
- раскладка архивов — «flutter_solo: 52 files», без оверрайдов дерева; прогон
  на полу Flutter 3.38.1 — «every archive passes its gate on the floor: 7
  roots»;
- пол приложения на Flutter 3.44.0: `flutter pub downgrade`, `flutter test` —
  «+291: All tests passed!», в `pubspec.lock` `camera` 0.12.2
  и `camera_android_camerax` 0.7.6+1;
- `check_translations.py` — «no differences».

Гейт CI зелёный на `3e279d43` «Release solo_lints 0.2.1»; от него
до подготовки — только запись о выпуске.

## Состояние

На 2026-11-18: на pub.dev `flutter_solo` 1.1.0, `solo` 2.0.0, `solo_lints`
0.2.1, scopo 1.0.0. Тега `flutter_solo-v2.0.0` нет ни локально, ни в origin.
Связка — релизный коммит «Release flutter_solo 2.0.0», аннотированный тег
`flutter_solo-v2.0.0`, `git push --follow-tags` и `dart pub publish` из чистого
дерева `packages/flutter_solo` — только по отдельному слову владельца.
