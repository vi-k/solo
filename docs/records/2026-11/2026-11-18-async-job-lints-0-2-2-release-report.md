> **Состояние на 2026-11-18:** подготовлено, не выпущено: часть C ветки линий
> перебазирована на `main`, поверх неё коммит подготовки `d803f9e2` «chore:
> prepare async_job_lints 0.2.2», проверки пройдены. Связка — по отдельному
> слову владельца; следом `solo_lints` 0.3.0.
> **Что это:** подготовка патча `async_job_lints` 0.2.2 — экспорт
> распознавателей линий для правил плагина поверх — и то, как часть C ветки
> линий легла на `main` после выпусков частей A и B.
> **Связанные записи:** `2026-11-11-solo-lanes-report.md`,
> `2026-11-11-solo-lanes-plan.md`,
> `2026-11-18-async-job-lints-0-2-1-release-report.md`,
> `2026-11-18-solo-lints-0-2-1-release-report.md`,
> `2026-11-12-solo-lanes-branch-review-report.md`,
> `2026-11-18-async-job-1-0-4-release-report.md`.

# Выпуск async_job_lints 0.2.2

По слову владельца 2026-11-18 «Готовь часть C». Слово понято как подготовка:
разрешение на связку приходит отдельным запросом, состоящим только из просьбы
опубликовать.

## Что в выпуске

Раздел «0.2.2» `CHANGELOG.md` и перевода:

- `plugin_api.dart` экспортирует `isSoloLanes`, `controllerAround`,
  `declaresLane`, `callsOn` и `readsState` — для правил плагина поверх
  о линиях; их требует `solo_lints` 0.3.0;
- `declaresLane` говорит, объявляет ли `lane(...)` на `this` или `super` линию
  там, где это позволяет `SoloLanes`, — прямо в теле конструктора;
- `queueLaneOf` берёт поле линии из того же места: поле, присвоенное
  из `super.lane(...)`, теперь своё для контроллера, как и поле из `lane(...)`.

Новых правил и новых диагностик для пользователя нет, поэтому патч.

## Зависимости и порядок

`async_job_lints` во время работы от ядра и `solo` не зависит, его тесты идут
против опубликованных `async_job` и `solo` 2.0.0: в `pubspec.lock` ядро 1.0.3,
патч 1.0.4 меняет одну документацию. Оверрайдов у пакета нет.

Следом — `solo_lints` 0.3.0: правила `stale_emit` и `lane_outside_constructor`,
`async_job_lints: ^0.2.2`. Минор: предупреждение `lane_outside_constructor`
включено, как только плагин назван, и `dart analyze` падает на коде, который
раньше проходил. Его подготовка — после публикации 0.2.2: до неё
`packages/solo_lints/pubspec_overrides.yaml` ведёт на `async_job_lints`
из дерева, первая строка — «Until async_job_lints 0.2.2 is published.», а снять
оверрайд, пока 0.2.2 нет на pub.dev, нельзя — `solo_lints` не разрешится.
Версия `solo_lints` в дереве — 0.2.1, его записи части C лежат в «Unreleased»
(«Не выпущено»).

## Как часть C легла на main

Прежняя голова ветки сохранена веткой `solo-lanes-before-rebase-3`
(`5296a432`). Ветка лежала на `c5ee937a` — голове `lanes-part-b`; с тех пор
в `main` вышли `solo_lints` 0.2.1, `flutter_solo` 2.0.0 и `async_job` 1.0.4.
`git rebase main` дал три конфликта, все в `solo_lints`:

- `pubspec.yaml`: подготовка `solo_lints` 0.2.1 подняла версию, часть C
  переписала описание. Взяты оба: версия 0.2.1 из `main`, описание части C;
- `CHANGELOG.md` и перевод: подготовка 0.2.1 переименовала «Unreleased»
  в «0.2.1», и строки части C о двух новых правилах легли бы в выпущенный
  раздел. Они перенесены в новый «Unreleased» («Не выпущено») над «0.2.1»
  в коммите, который добавляет правила, и следующий коммит, дописавший к ним
  фразу об `async_job_lints` 0.2.2, разрешён его текстом в том же разделе.
  Раздел «0.2.1» обоих файлов совпадает с `main` до символа, сверено сравнением
  хвоста файла; так же сверены «0.2.1» `async_job_lints` и перевода.

Оверрайд `solo_lints` на `async_job_lints` подготовка 0.2.1 сняла, а часть C
требует неопубликованный 0.2.2, поэтому он возвращён отдельным коммитом поверх
части C.

| Было | Стало | Коммит |
| --- | --- | --- |
| `71fbe645` | `8c765a3b` | feat(async_job_lints): export the recognizers of a lane… |
| `2c19221c` | `2c07298d` | feat(solo_lints): add stale_emit and lane_outside_constructor |
| `b0a7bacc` | `76a8e88b` | fix(async_job_lints): take super.lane(...) as a declaration |
| `41116e13` | `84dbf37e` | fix(solo_lints): count a wait where the job suspends… |
| `859aa26b` | `a4f8801c` | fix(solo_lints): name the stale_emit code explicitly |
| `2634b0b0` | `4376a51f` | fix(solo_lints): stale_emit follows self-assignments… |
| `9c50ecab` | `3e410143` | fix(solo_lints): stale_emit follows the fields of a record… |
| `5658b9ff` | `1cc41ffe` | docs(solo): name stale_emit where lanes.md shows the stale copy |
| `5296a432` | `30b95aed` | docs(solo): read the stale_emit paragraph of the Russian… |
| — | `41c822d6` | chore: override async_job_lints in solo_lints |

## Подготовка

Коммит `d803f9e2` «chore: prepare async_job_lints 0.2.2»:

- `version: 0.2.2` в `packages/async_job_lints/pubspec.yaml`;
- «Unreleased» в `CHANGELOG.md` стал «0.2.2», в переводе «Не выпущено» тоже;
  начало пункта «Next patch, 0.2.2, which `solo_lints` 0.3.0 requires» —
  о будущем выпуске — переписано: пункт начинается с того, что экспортирует
  `plugin_api.dart`, а `solo_lints` 0.3.0 назван в конце первой фразы;
- README, перевод и `example/example.md` просят `^0.2.2` вместо `^0.2.1`:
  сторож `test/readme_version_test.dart` требует версию пакета в обоих блоках
  README, `test/example_page_test.dart` — в блоке примера.

Последний пункт подготовка сначала пропустила: граница `^0.2.1` пускает 0.2.2,
и README казался верным. Тесты в дереве прошли, потому что шли до подъёма
версии; покраснел пол — оба сторожа в архиве `async_job_lints`. Правка вклеена
в коммит подготовки.

`check_translations.py` — «no differences».

## Чем проверено

На чистом дереве `d803f9e2`, Flutter 3.50 и Dart 3.14:

- `async_job_lints` и `solo_lints`: формат — «0 changed»,
  `dart analyze --fatal-infos` — «No issues found!», `dart doc --dry-run` —
  «Found 0 warnings and 0 errors.», `dart test` — +231 и +158, «All tests
  passed!»; `solo_lints` разрешает `async_job_lints` из дерева;
- `tool/plugin_probe.py` — «ok» на обоих наборах плагинов;
- `dart pub publish --dry-run` в `packages/async_job_lints` — «Publishing
  async_job_lints 0.2.2», «Package has 0 warnings.»;
- `check_translations.py` — «no differences», `check_links.py`,
  `check_dartdoc.py`, `check_line_width.py` и `reflow.py --check` чистые,
  `build_site.py` — «wrote 100 pages»;
- раскладка архивов и прогон на полу Flutter 3.38.1 — «every archive passes its
  gate on the floor: 7 roots»; из архива `async_job` +1917, `solo` +2482,
  `async_job_lints` +231, `solo_lints` +127 с оверрайдом дерева.

Первый прогон пола, ещё до правки README, покраснел на `async_job_lints` — те
два сторожа — и на `async_job`, вывод которого обрезал `tail`. Второй прогон
того же дерева с полным логом прошёл `async_job` целиком, +1917; третий,
на `d803f9e2`, — тоже. Разбор — раздел «Красные тесты ядра».

## Красные тесты ядра

На вопрос владельца «а что с нерешенным?» тесты ядра гонялись подряд на той же
машине, под средней нагрузкой 25–35 на 14 ядрах от параллельных сессий. Ядро
не менялось: дерево `async_job` — выпуск 1.0.4.

| Прогон | Пол, Dart 3.10.0 | Стабильный, Dart 3.14.0 |
| --- | --- | --- |
| весь набор, 30 раз | 5 красных | 1 красный |
| `start_depth`, один тест, 60 раз | 10 красных | 4 красных |
| тест изолята, один, 60 раз | 0 | 0 |

Красные во всём наборе — три теста:

- `let_go_together_test.dart`, оба теста: секундомер 3414 и 4386 мс при границе
  3000. Граница стоит по реальному времени между 0,4 с без дефекта и 6–40
        с с ним, и нагрузка машины её переходит;
- `cancellation_rakes_test.dart`, «the cancellation kills the isolate in the
  middle of a step»: изолят сборки сказал «step 2» после «cancel». Шаг сборки —
  50 мс, и основной изолят под нагрузкой не успел за них услышать «step 1»
  и убить сборку. Один тест 120 раз не покраснел ни разу;
- `start_depth_test.dart`, «the end of a group cut short is tried once, a
  failed branch or not»: в зоне ошибка ветки `StateError` вместо
  `StackOverflowError`, во всех 14 случаях одна и та же.

Последний разобран зондом: копия теста в раскладке архива, записывающая порядок
событий, 40 прогонов на полу.

```text
37  body over | delay(10) over | release  ZONE [Stack Overflow]  passed
 3  delay(10) over | release | body over  ZONE [Bad state: of the branch]
```

Тест требует, чтобы владелец подобрал оборванную группу, пока ветка `unheard`
ещё ждёт: тогда `_concludeTorn` слушает её второй раз, зона бросает
`StackOverflowError`, и тест видит, что конец группы пробуется один раз.
Порядок держат таймеры: тело корня ждёт `delay(1)`, тест отпускает `unheard`
после `delay(10)`. Когда от постановки одного таймера до другого проходит
больше 9 мс, `release` идёт первым. `unheard` кончается раньше, чем владелец
пришёл, `_concludeTorn` её выбрасывает и не слушает, и группа отдаёт в зону
ошибку `failing`, за которую отвечает. Для такого порядка это верный ответ
ядра, а проверка теста им не достигается. Дефект теста, а не ядра.

По слову владельца «Почини тест start_depth» тест отпускает `unheard` после
второго прослушивания группы — его делает владелец, когда подбирает группу, —
а не после `delay(10)`; коммит «test(async_job): let the branch go once the
owner takes the group up». Ожидание ограничено пятью секундами: без кадра
`_hear` зона ничего не считает, и проверка ниже говорит почему. Проверено:

- с паузой тела корня 50 мс вместо 1 мс прежняя версия теста красная, новая
  зелёная;
- мутация ядра — `_concludeTornChildren` не снимает группу с цепочки перед
  `_concludeTorn` — роняет новую версию: в зоне `StackOverflowError` и следом
  ошибка ветки;
- новая версия 100 раз на стабильном SDK и 100 раз на полу из раскладки
  архива — 0 красных, при нагрузке уже 5–9; весь набор `async_job` +1917
  на обоих.

`let_go_together` и тест изолята оставлены как были.

В CI из последних ста прогонов гейта красных шесть, и ни в одном не упал шаг
пола или тесты ядра.



На 2026-11-18: на pub.dev `async_job_lints` 0.2.1, `solo_lints` 0.2.1. Тега
`async_job_lints-v0.2.2` нет ни локально, ни в origin. Связка — релизный коммит
«Release async_job_lints 0.2.2», аннотированный тег `async_job_lints-v0.2.2`,
`git push --follow-tags` и `dart pub publish` из чистого дерева
`packages/async_job_lints` — только по отдельному слову владельца.
