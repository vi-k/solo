> **Состояние на 2026-11-18:** выпущено по слову владельца «публикуй»: релизный
> коммит «Release solo_lints 0.3.0», тег `solo_lints-v0.3.0`,
> `dart pub publish`. Часть C ветки линий выпущена целиком; дальше — подъём
> `solo_lints: ^0.3.0` в README и примерах `solo` и `flutter_solo`.
> **Что это:** подготовка минора `solo_lints` 0.3.0 — правила `stale_emit`
> и `lane_outside_constructor` для линий `SoloLanes`, пакет требует
> `async_job_lints` 0.2.2.
> **Связанные записи:** `2026-11-18-async-job-lints-0-2-2-release-report.md`,
> `2026-11-18-solo-lints-0-2-1-release-report.md`,
> `2026-11-11-solo-lanes-report.md`, `2026-11-11-solo-lanes-plan.md`,
> `2026-11-09-solo-lints-0-2-0-release-report.md`.

# Выпуск solo_lints 0.3.0

По слову владельца 2026-11-18 «Готовь solo_lints 0.3.0». Слово понято как
подготовка: разрешение на связку приходит отдельным запросом, состоящим только
из просьбы опубликовать.

## Что в выпуске

Раздел «Unreleased» `CHANGELOG.md`, пришедший с частью C ветки линий:

- `stale_emit`, линт: `ctx.emit` в задаче `SoloLanes`, который пишет значение,
  построенное на состоянии, прочитанном до `await`; эвристика;
- `lane_outside_constructor`, предупреждение: `lane(...)` вне тела
  конструктора, где он бросает после запечатывания набора линий;
- README описывает оба правила;
- требует `async_job_lints` 0.2.2, который экспортирует нужные им
  распознаватели.

## Почему минор

Предупреждение `lane_outside_constructor` включено, как только плагин назван,
поэтому `dart analyze` краснеет на коде, который проходил с 0.2.1. Так выпуск
и разложен планом `2026-11-11-solo-lanes-plan.md`: часть C — патч
`async_job_lints` 0.2.2 и минор `solo_lints` 0.3.0.

## Зависимости и порядок

`solo_lints` во время работы зависит только от `async_job_lints: ^0.2.2`,
вышедшего 2026-11-18; тесты идут против опубликованных `async_job` и `solo`
2.0.0. Оверрайдов у пакета больше нет, во всём дереве тоже.

README `solo` и `flutter_solo`, их переводы и примеры просят
`solo_lints: ^0.2.0`, и это ограничение 0.3.0 не пускает. Сторож
`test/readme_rakes_test.dart` обоих пакетов требует, чтобы README называл ту
версию, с которой анализируется пример, а пример на `^0.3.0` до публикации
не разрешился бы. Строки поднимаются отдельной правкой после выхода и дойдут
до pub.dev со следующими выпусками `solo` и `flutter_solo` — как после
`solo_lints` 0.2.0 (`2026-11-09-solo-lints-0-2-0-release-report.md`).

## Подготовка

Коммит «chore: prepare solo_lints 0.3.0»:

- `version: 0.3.0` в `packages/solo_lints/pubspec.yaml`;
- снят `packages/solo_lints/pubspec_overrides.yaml` — оверрайд
  на `async_job_lints` из дерева, живший до выхода 0.2.2; удаление в индексе;
- «Unreleased» в `CHANGELOG.md` стал разделом «0.3.0», в переводе
  `docs/ru/solo_lints/CHANGELOG.md` «Не выпущено» тоже; фраза «the release is a
  minor one» уже была в прошедшем виде;
- README, перевод и `example/example.md` просят `^0.3.0` вместо `^0.2.1` —
  сторожа `readme_version_test.dart` и `example_page_test.dart`.

## Чем проверено

На чистом дереве коммита подготовки, Flutter 3.50 и Dart 3.14:

- `solo_lints` после `dart pub get` разрешился против опубликованного
  `async_job_lints` 0.2.2 («+ async_job_lints 0.2.2», в `pubspec.lock` —
  `source: hosted`); формат — «0 changed», `dart analyze --fatal-infos` — «No
  issues found!», `dart test` — «+158: All tests passed!»;
- `tool/plugin_probe.py` — «ok» на всех четырёх наборах: каждый плагин отдельно
  и оба в двух порядках;
- `dart pub publish --dry-run` в `packages/solo_lints` — «Publishing solo_lints
  0.3.0», «Package has 0 warnings.»;
- `check_translations.py` — «no differences», `check_links.py`,
  `check_dartdoc.py`, `check_line_width.py` и `reflow.py --check` чистые;
- раскладка архивов — «solo_lints: 26 files», оверрайдов в дереве нет; прогон
  на полу Flutter 3.38.1 — «every archive passes its gate on the floor: 7
  roots». `solo_lints` там после `dart pub downgrade` стоит на опубликованном
  `async_job_lints` и проходит `dart test` с +127: архив без
  `mistakes_page_test.dart`, который `.pubignore` исключает, потому что тот
  читает `packages/solo/doc/`.

Подготовка меняет только `solo_lints`: версию, оверрайд, заголовки списков
изменений и строки README.

## Состояние

На 2026-11-18 до связки: на pub.dev `solo_lints` 0.2.1, `async_job_lints`
0.2.2, тега `solo_lints-v0.3.0` нет ни локально, ни в origin.

## Связка

По слову владельца 2026-11-18 «публикуй» — отдельный запрос, состоящий только
из просьбы опубликовать. Перед связкой: `main` чистый, впереди `origin/main`
на 3 коммита и не отстаёт; гейт CI зелёный на `111d027f` «Release
async_job_lints 0.2.2», от него до связки — подготовка `solo_lints` и записи.
На дереве `main` пакет прошёл формат, `dart analyze --fatal-infos`, `dart test`
(+158) и `dart pub publish --dry-run` без предупреждений. Связка — релизный
коммит «Release solo_lints 0.3.0» с этой записью, аннотированный тег
`solo_lints-v0.3.0` на нём, `git push --follow-tags` и `dart pub publish`
из чистого дерева `packages/solo_lints`.

Связка прошла подряд: релизный коммит `7ab7dd87` «Release solo_lints 0.3.0»,
аннотированный тег `solo_lints-v0.3.0` на нём, `git push --follow-tags` —
`origin/main` с `111d027f` на `7ab7dd87` вместе с тегом, —
и `dart pub publish --force` из чистого дерева `packages/solo_lints`:
«Successfully uploaded https://pub.dev/packages/solo_lints version 0.3.0». API
pub.dev отдаёт версию 0.3.0 с датой публикации 2026-11-18T15:42:24Z.
