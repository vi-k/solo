> **Состояние на 2026-11-18:** подготовлено в ветке `lanes-part-b`, не влито
> в `main` и не выпущено: часть B ветки `solo-lanes` перебазирована на `main`,
> оверрайды на `solo` сняты, коммит подготовки «chore: prepare async_job_lints
> 0.2.1». Полный гейт на нём зелёный. Тега `async_job_lints-v0.2.1` нет,
> на pub.dev `async_job_lints` 0.2.0. Дальше — вливание `lanes-part-b`
> в `main` и связка по отдельному слову владельца.
> **Что это:** подготовка патча `async_job_lints` 0.2.1 — правила ядра узнают
> `SoloController` и линии `SoloLanes` из `solo` 2.0 — и то, как часть B ветки
> линий вошла в эту подготовку.
> **Связанные записи:** `2026-11-11-solo-lanes-report.md`,
> `2026-11-11-solo-lanes-plan.md`, `2026-11-10-solo-lanes-design.md`,
> `2026-11-18-solo-2-0-0-release-report.md`,
> `2026-11-09-async-job-lints-0-2-0-release-report.md`,
> `2026-11-10-solo-1-1-0-release-report.md`.

# Выпуск async_job_lints 0.2.1

По слову владельца 2026-11-18 «Готовь часть B и выпуск async_job_lints 0.2.1».
Слово понято как подготовка: разрешение на связку приходит отдельным запросом,
состоящим только из просьбы опубликовать. В `main` ничего не влито: часть B
и подготовка лежат в ветке `lanes-part-b`, вливает контроллер после ревью.

## Что в выпуске

Часть B ветки `solo-lanes`, со стороны `async_job_lints`; раздел «0.2.1»
`CHANGELOG.md` и перевода:

- правила знают `solo` 2.0: `SoloController`, базу `Solo` и `SoloLanes`,
  и `SoloLane`, линию `SoloLanes`; `outcome_after_await` берёт `job` линии
  так же, как `job` у `Solo`;
- `plugin_api.dart` экспортирует `isSoloController`, `isSoloLane`,
  `queueLaneOf` и `QueueLane`, `queueCallOf` и `queuedBodyOf` — для правил
  плагина поверх; `isSoloMember` с `Solo` берёт и одноимённый член `SoloLane`;
- `registerAsyncJobLints` принимает `ownLaneReportedElsewhere`: с ним
  `bare_await` и `discarded_outcome` оставляют ожидание своей линии плагину
  поверх, без него — как у `solo_lints` 0.2.0 — сообщают о нём, как о любом
  другом;
- своя линия — только поле, в которое каждая запись в классе — `lane(...)`
  в теле конструктора, и оставляется ожидание только из тела, поставленного
  в эту линию; для своей очереди `Solo` оба правила отвечают как в 0.2.0.

README и перевод говорят, какой `done` ждёт и что сообщает об ожидании своей
очереди. Новых правил нет.

## Почему патч

0.2.0 узнаёт члены очереди по классу, который их объявил, и `close`
с `cancelAll` — по владельцу метода через `isSolo`. С `solo` 2.0 у `Solo`
появилась база `SoloController`, а у `SoloLanes` — линии. 0.2.0 не видит членов
линии: `outcome_after_await`, `key_per_request` и `ignore_failure_hides_bugs`
поверх него не узнают `enqueue`, `job` и прочие у `SoloLane`. `ownQueueCall`
теряет `close` и `cancelAll` контроллера, в который подмешан `SoloStream`: они
переехали в базу. Линий он не различает вовсе.

Выпуск 0.2.1 исправляет распознавание и ничего не добавляет к ответам для
`Solo`: сужение `bare_await` и `discarded_outcome` до тела, поставленного
в линию, касается только линий `SoloLanes`, а для своей очереди `Solo` оба
правила отвечают как в 0.2.0. Новых диагностик на коде, который 0.2.0 проходил,
нет, поэтому патч. Он доходит до пользователя сам: `solo_lints` 0.2.0 держит
`async_job_lints: ^0.2.0`, и это ограничение пускает 0.2.1.

## Зависимости и порядок

`async_job_lints` во время работы от ядра и `solo` не зависит; его тесты идут
против опубликованного `solo` 2.0.0, оверрайдов у пакета больше нет.

Следом — `solo_lints` 0.2.1: он требует `async_job_lints: ^0.2.1`, учит
`await_own_queue` линиям и включает `ownLaneReportedElsewhere`. Выходит
по своему отдельному слову владельца после публикации 0.2.1. Оверрайд
`packages/solo_lints/pubspec_overrides.yaml` на `async_job_lints` живёт
до выпуска 0.2.1, первая строка так и говорит; снимается после него, при
подготовке `solo_lints` 0.2.1. Часть C — патч `async_job_lints` 0.2.2 и минор
`solo_lints` 0.3.0 — после них.

## Как часть B вошла в подготовку

По шагу 2 раздела «Как ветка входит в `main`» плана
`2026-11-11-solo-lanes-plan.md`. Прежняя голова ветки сохранена веткой
`solo-lanes-before-rebase-2` (`0134aa5a`). `git rebase main` всей ветки, частей
B и C вместе, прошёл без конфликтов git. Абзац «A read at the write» страницы
`lanes.md` и её перевода, где ждали конфликта, слился сам: абзац `main`
о строке `Solo.debug` идёт первым, за ним абзац части C о `stale_emit`. Ни один
коммит частей B и C не пишет под «2.0.0» `CHANGELOG.md` `solo` и перевода и под
«0.2.0» обоих линтов: каждый коммит сверен с `main` по этим разделам. Записи
линтов лежат в «Unreleased» («Не выпущено»), у `solo` записей в этих частях
нет.

Часть B — десять коммитов, хеши после перебазирования:

| Было | Стало | Коммит |
| --- | --- | --- |
| `3090db39` | `b921de08` | fix(async_job_lints): recognise SoloController and SoloLane |
| `916d3500` | `97aba61b` | fix(solo_lints): tell the lanes apart in await_own_queue |
| `bb14817c` | `87e68c15` | fix(async_job_lints): leave a wait only from a body queued here |
| `699ea783` | `3cda9e04` | fix(solo_lints): share the queued body with the core rules |
| `578104d7` | `6e4638a7` | fix(async_job_lints): keep the answers of 0.2.0 for a Solo |
| `2942c49f` | `5d24e969` | test(solo_lints): a lane the controller takes is not its own |
| `f8f699fc` | `0a0ab155` | docs(async_job_lints): say which done waits |
| `71851f67` | `00ab4bd0` | docs(solo_lints): a lane declared in another file is not seen |
| `e6b97376` | `787eaae0` | fix(async_job_lints): a lane field is own only when every write… |
| `ba876dd7` | `2a7f4a55` | test(async_job_lints): pin a method of two lanes and a field… |

Поверх части B — два коммита этой подготовки и коммит с этой записью; на них
ветка `lanes-part-b`.

Часть C — девять коммитов, перебазированы на `lanes-part-b` в ветке
`solo-lanes`. Её хеши зависят от коммита с этой записью, который лежит под ней,
поэтому здесь их нет: соответствие — по темам коммитов, новые хеши —
`git log lanes-part-b..solo-lanes`.

| Было | Коммит |
| --- | --- |
| `7e4e07c5` | feat(async_job_lints): export the recognizers of a lane and its controller |
| `8cad947f` | feat(solo_lints): add stale_emit and lane_outside_constructor |
| `8bfba8fb` | fix(async_job_lints): take super.lane(...) as a declaration |
| `db91a0e1` | fix(solo_lints): count a wait where the job suspends in stale_emit |
| `69528c97` | fix(solo_lints): name the stale_emit code explicitly |
| `f846472a` | fix(solo_lints): stale_emit follows self-assignments and branches… |
| `de8eba0c` | fix(solo_lints): stale_emit follows the fields of a record literal |
| `bb54551d` | docs(solo): name stale_emit where lanes.md shows the stale copy |
| `0134aa5a` | docs(solo): read the stale_emit paragraph of the Russian lanes… |

Перенос части C на `lanes-part-b` потребовал двух правок, обе вклеены в свои
коммиты:

- запись `7e4e07c5` в `CHANGELOG.md` `async_job_lints` и переводе легла бы
  в конец раздела «0.2.1» — урок `2026-11-10-solo-1-1-0-release-report.md`. Она
  перенесена в новый раздел «Unreleased» («Не выпущено») над «0.2.1».
  `8bfba8fb` переписывает тот же пункт и дал конфликт; разрешён его текстом
  в новом разделе, слово в слово, с началом «Next patch, 0.2.2, which
  `solo_lints` 0.3.0 requires». Ни один коммит C не пишет под «0.2.1»;
- таблица `packages/solo_lints/test/mistakes_page_test.dart` держала раздел «A
  copy read before the wait, in a lane» с `null`: в `main` правила `stale_emit`
  нет. На голове C тест покраснел: `stale_emit` сообщает о блоке «Don't do
  this» и молчит о «Do this». Строка получила `stale_emit` в коммите
  `8cad947f`, который добавляет правило, как и предсказывал handoff.

## Подготовка

Коммит «chore: drop the overrides on solo» поверх части B:

- `packages/async_job_lints/pubspec_overrides.yaml` удалён и добавлен в индекс:
  в нём был один `solo`;
- `packages/solo_lints/pubspec_overrides.yaml` держит только `async_job_lints`,
  первая строка — «Until async_job_lints 0.2.1 is published.»;
- dev-зависимости обоих линтов на `solo` — `^2.0.0`, их подняла часть B.

Коммит «chore: prepare async_job_lints 0.2.1»:

- `version: 0.2.1` в `packages/async_job_lints/pubspec.yaml`;
- «Unreleased» в `CHANGELOG.md` стал «0.2.1», в переводе
  `docs/ru/async_job_lints/CHANGELOG.md` «Не выпущено» — тоже;
  `check_translations.py` — «no differences»;
- README, перевод и `example/example.md` просят `^0.2.1` вместо `^0.2.0`:
  сторож `test/readme_version_test.dart` требует версию пакета в обоих блоках
  README, `test/example_page_test.dart` — в блоке примера.

README ядра просит `async_job_lints` `version: ^0.1.1` и остался как был: это
страница пакета `async_job`, она уходит на pub.dev только с выпуском ядра.
Граница `^0.1.1` не пускает ни 0.2.0, ни 0.2.1; решение о ней — за выпуском
ядра.

## Чем проверено

Полный гейт, пять заданий CI, на чистом дереве коммита подготовки `b0f90137`
в отдельной копии без ветки, `pub get` перед форматом; Flutter 3.50.0 и Dart
3.14.0. Каждое задание кончилось чистым `git status --porcelain`.

- `dart`: формат без изменений (100, 190, 28 и 17 файлов),
  `dart analyze --fatal-infos` — «No issues found!» на всех пяти,
  `dart doc --dry-run` — 0 предупреждений; `async_job` +1917, `solo` +2496,
  пример `solo` +112, `async_job_lints` +230, `solo_lints` +124, все «All tests
  passed!»; `tool/plugin_probe.py` — «ok» на всех четырёх наборах плагинов;
- `flutter`: формат и анализ чистые, `flutter_solo` +344, его пример +6,
  `camera_example` +291, стенд `flutter_solo` +59, трассы `mixins.md` — «8
  quoted traces, 0 not printed»; раскладка архивов прошла;
- `floor` на Flutter 3.38.1 (Dart 3.10.0) — «every archive passes its gate on
  the floor: 7 roots»; из архива `async_job_lints` +230, `solo_lints` +93;
  приложение на Flutter 3.44.0 — `flutter pub downgrade`, +291,
  в `pubspec.lock` `camera` 0.12.2 и `camera_android_camerax` 0.7.6+1;
- `snippets`: шесть пакетов стендов, анализ — «No issues found!», 68 драйверов,
  «every quoted trace is what the bench prints»;
- `docs`: все питоновские проверки и их сторожа (20, 8, 15, 54, 41 и 27
  тестов), «no differences», «every document link resolves», сборка сайта —
  «wrote 100 pages under site/src/content/docs».

`dart pub publish --dry-run` в `packages/async_job_lints` на том же чистом
дереве, последние строки:

```text
Publishing async_job_lints 0.2.1 to https://pub.dev:
Total compressed archive size: 52 KB.
Package has 0 warnings.
```

`dart test` `solo_lints` на голове части C — +158, «All tests passed!».

Запись, handoff и шапка `2026-11-11-solo-lanes-report.md` легли поверх
подготовки отдельным коммитом «docs: record the preparation of async_job_lints
0.2.1»; пакеты он не трогает. На нём `reflow.py --check`,
`check_line_width.py`, `check_links.py` и `check_translations.py` чистые.

## Состояние

На 2026-11-18: на pub.dev `async_job_lints` 0.2.0, `solo_lints` 0.2.0, `solo`
2.0.0. Тега `async_job_lints-v0.2.1` нет ни локально, ни в origin. `main`
не тронут: впереди `origin/main` на один коммит, запись о выпуске `solo` 2.0.0.
Связка — релизный коммит «Release async_job_lints 0.2.1», аннотированный тег
`async_job_lints-v0.2.1`, `git push --follow-tags` и `dart pub publish`
из чистого дерева `packages/async_job_lints` — только по отдельному слову
владельца, после вливания `lanes-part-b` в `main`.
