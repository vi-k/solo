> **Состояние на 2026-11-18:** подготовлено, не выпущено: коммит подготовки
> `2af90fad` «chore: prepare solo_lints 0.2.1», проверки пройдены. Связка —
> по отдельному слову владельца.
> **Что это:** подготовка патча `solo_lints` 0.2.1 — `await_own_queue` узнаёт
> линии `SoloLanes` из `solo` 2.0, пакет требует `async_job_lints` 0.2.1.
> **Связанные записи:** `2026-11-18-async-job-lints-0-2-1-release-report.md`,
> `2026-11-18-solo-2-0-0-release-report.md`, `2026-11-11-solo-lanes-report.md`,
> `2026-11-11-solo-lanes-plan.md`,
> `2026-11-09-solo-lints-0-2-0-release-report.md`.

# Выпуск solo_lints 0.2.1

По слову владельца 2026-11-18 «Готовь выпуск solo_lints 0.2.1». Слово понято
как подготовка: разрешение на связку приходит отдельным запросом, состоящим
только из просьбы опубликовать.

## Что в выпуске

Раздел «Unreleased» `CHANGELOG.md`, пришедший с частью B ветки линий
(`2026-11-18-async-job-lints-0-2-1-release-report.md`, раздел «Как часть B
вошла в подготовку»):

- `await_own_queue` знает линии `SoloLanes`: сообщает о задаче, которая
  из тела, поставленного в линию, ждёт задачу той же линии, и называет линию.
  Ожидание другой линии и ожидание там, где линии не видно, остаются
  `bare_await`. О `close` и `cancelAll` правило сообщает у любого контроллера,
  у `SoloLanes` и контроллера со `SoloStream` тоже;
- `discarded_outcome` оставляет ожидание своей линии `await_own_queue`;
- `key_per_request` и `ignore_failure_hides_bugs` берут `enqueue`,
  `enqueueJob`, `job`, `collect` и `accumulate` линии так же, как у `Solo`;
- требует `async_job_lints` 0.2.1.

## Почему патч

`solo_lints` 0.2.0 с `async_job_lints` 0.2.1 линий не различает: без
`ownLaneReportedElsewhere` правила ядра сообщают об ожидании своей линии, как
о любом другом, а `await_own_queue` линий не видит. 0.2.1 переносит это
ожидание из `bare_await` в `await_own_queue`, который называет дедлок, и учит
остальные правила членам линии. Ответы для своей очереди `Solo` прежние. Так
выпуск и разложен планом `2026-11-11-solo-lanes-plan.md`: часть B — патчи обоих
пакетов линтов.

Патч доходит до пользователя сам: README `solo` и `flutter_solo` и их примеры
просят `solo_lints: ^0.2.0`, и это ограничение пускает 0.2.1. Поэтому их строки
не поднимаются.

## Зависимости и порядок

`solo_lints` во время работы зависит только от `async_job_lints: ^0.2.1`,
вышедшего 2026-11-18; тесты идут против опубликованных `async_job` и `solo`
2.0.0. Оверрайдов у пакета больше нет.

После этого выпуска остаётся часть C ветки линий — патч `async_job_lints` 0.2.2
и минор `solo_lints` 0.3.0. Ветка `solo-lanes` лежит поверх `c5ee937a`, где
у `solo_lints` ещё жил оверрайд на `async_job_lints`; при её перебазировании
на `main` оверрайд надо вернуть, потому что `solo_lints` 0.3.0 требует
неопубликованный `async_job_lints` 0.2.2.

## Подготовка

Коммит `2af90fad` «chore: prepare solo_lints 0.2.1»:

- `version: 0.2.1` в `packages/solo_lints/pubspec.yaml`;
- снят `packages/solo_lints/pubspec_overrides.yaml` — оверрайд
  на `async_job_lints` из дерева, живший до выхода 0.2.1; удаление в индексе;
- «Unreleased» в `CHANGELOG.md` стал разделом «0.2.1», в переводе
  `docs/ru/solo_lints/CHANGELOG.md` «Не выпущено» тоже;
- README, перевод и `example/example.md` просят `^0.2.1` вместо `^0.2.0` —
  сторожа `readme_version_test.dart` и `example_page_test.dart`.

## Чем проверено

На чистом дереве `2af90fad`, Flutter 3.50 и Dart 3.14:

- `solo_lints` после `dart pub get` разрешился против опубликованного
  `async_job_lints` 0.2.1 («+ async_job_lints 0.2.1»); формат — «0 changed»,
  `dart analyze --fatal-infos` — «No issues found!», `dart test` — «+124: All
  tests passed!»;
- `tool/plugin_probe.py` — «ok» на всех четырёх наборах: каждый плагин отдельно
  и оба в двух порядках;
- `dart pub publish --dry-run` в `packages/solo_lints` — «Publishing solo_lints
  0.2.1», «Package has 0 warnings.»;
- `check_translations.py` — «no differences», `check_links.py`,
  `check_dartdoc.py`, `check_line_width.py` и `reflow.py --check` чистые;
- раскладка архивов — «solo_lints: 22 files», без оверрайдов дерева; прогон
  на полу Flutter 3.38.1 — «every archive passes its gate on the floor: 7
  roots».

Гейт CI зелёный на `b01a0dcb` «Release async_job_lints 0.2.1»; от него
до подготовки — только запись о выпуске. Подготовка меняет только `solo_lints`:
версию, оверрайд, заголовки списков изменений и строки README.

## Состояние

На 2026-11-18: на pub.dev `solo_lints` 0.2.0, `async_job_lints` 0.2.1. Тега
`solo_lints-v0.2.1` нет ни локально, ни в origin. Связка — релизный коммит
«Release solo_lints 0.2.1», аннотированный тег `solo_lints-v0.2.1`,
`git push --follow-tags` и `dart pub publish` из чистого дерева
`packages/solo_lints` — только по отдельному слову владельца.
