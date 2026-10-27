> **Состояние на 2026-10-27:** ревью плана на Opus разобрано, план исправлен
> по вердиктам; шаги 1–3 сделаны, дальше шаг 4.
> **Что это:** план работ по `ctx.child` — шаги, коммиты, проверки.
> **Связанные записи:** `2026-10-27-ctx-child-design.md` — дизайн и оба его
> ревью; номера тестов и находок ниже — оттуда.

# План: `ctx.child`

Работа идёт в своей копии, ветка `worktree-ctx-child`, и вливается в `main`
перемоткой после ревью работы на Opus и codex. Каждый шаг кончается коммитом
и прогоном проверок затронутых пакетов: `dart format`,
`dart analyze --fatal-infos`, `dart test` (`flutter test` для `flutter_solo`).
Шаг, который трогает dartdoc или документы, гоняет и питоновские проверки
задания `docs`: `check_dartdoc.py`, `check_translations.py`,
`reflow.py --check`, `check_line_width.py`, `check_links.py`. Изменённые абзацы
переводов идут через humanizer--ru до коммита шага, `docs/handoff.md`
обновляется после каждого шага (находка П7).

## 1. Оверрайды

`chore:` — оверрайды на `async_job` из дерева (находка О4):

- `packages/solo/pubspec_overrides.yaml`,
  `packages/solo/example/pubspec_overrides.yaml` — новые,
  `async_job: path: ../async_job` и `../../async_job`;
- `packages/flutter_solo/pubspec_overrides.yaml` и его пример — `async_job`
  рядом с `solo`.

Первая строка каждого — «Use local async_job until 0.5.0 is published.»
(у `flutter_solo` — общая строка для обоих пакетов). Пример `flutter_solo`
держит комментарий о том, почему файл нужен отдельно, — так же, как сейчас.

Проверка: `dart pub get` в четырёх корнях, `package_config.json` указывает
на `packages/async_job`; полные наборы `solo` и `flutter_solo` зелёные ещё
до правки ядра — оверрайд ничего не меняет, пока ядро прежнее.

## 2. Ядро

`feat(async_job)!: add ctx.child, a child the engine accepts`:

- `JobContext.child` с `@useResult` и dartdoc: фабрика, ничего не запускает
  и не проверяет; правила — от контекста, который сделал ребёнка, родитель —
  тот, кто запустил; незапущенный ребёнок принадлежит держателю, срок до старта
  не идёт, `done` ждёт; реализация по умолчанию — ребёнок ядра, и движок
  со своим контекстом или правилами переопределяет `child`;
- dartdoc класса `JobContext`: `child` в обоих списках исключений — после
  принятой отмены и после конца задачи;
- `JobContextBase.child` — `Job.deferred<T>(body, key:, describe:, timeout:)`;
- `createEachJob` по умолчанию — `child<void>(body, key:, describe:)`, dartdoc:
  переопределять его нужно, только если ребёнку `each` нужно что-то сверх
  `child` или проверка перед ним;
- dartdoc `Job.deferred`: шаг со сроком — `ctx.child(step, timeout: …)`;
- `test/child_factory_test.dart` — тесты 1–7 дизайна;
- `test/extending_test.dart` — тест 8: три движка (переопределённый `child`,
  прежний `createEachJob`, правило в `check()` без `child`).

Проверка ядра; затем `solo` и `flutter_solo` целиком против нового ядра до шага
3 — должны быть зелёными, кроме сторожей документов: README ядра
(`readme_recipe_test.dart`) краснеет здесь же и чинится в этом коммите (находка
П1): строка `ctx.child(body)` в таблицах `README.md` и `README.ru.md`,
а в стороже — `@useResult` пропускается при чтении членов, `child` стоит
в `calls` и в списке членов с пустой третьей колонкой. Шаг 4 правит остальные
страницы. Красный `reference.md` `solo` чинится в шаге 3.

## 3. `solo`

`feat(solo)!: add SoloContext.child for code that holds only a context`:

- `SoloContext.child` с `@override`, `@useResult` и dartdoc: ребёнок того же
  контроллера с `W` и `keepWhile` создателя; запущенный другой задачей
  контроллера, проверяет правила создателя;
- `_SoloContext.child` — `_solo.job<W, T>(…, keepWhile: _job._keepWhile)`;
- `_SoloContext.createEachJob` — проверка правил, затем `child<void>`;
- абзац dartdoc `SoloContext` о детях `run`, `start`, `runAll` — «made by
  `job(...)` of the same controller or by `ctx.child`»;
- dartdoc `run`, `start` и `runAll` `SoloContext`: ребёнок сделан `job(...)`
  или `ctx.child` (находка П6);
- текст отказа `_own` в `solo.dart` называет `ctx.child`; его цитаты
  в `children_test.dart`, `children_rakes_test.dart`, `start_test.dart`,
  `doc/children.md` и `docs/ru/solo/children.md` — в том же коммите, потому что
  сторожа сверяют их с выводом (находка П2);
- `doc/reference.md` и `docs/ru/solo/reference.md` — строка `child`, а в строке
  `ctx.run(child)` — «или `ctx.child`» (находка П6);
- тесты 9, 13 и 17, общий код на `JobContext`, —
  `test/child_shared_code_test.dart`: без `SoloContext.child` этот файл
  собирается, и мутант показывает отказ контроллера (находка П11); остальные
  тесты 10–18 — `test/child_factory_test.dart`, с ними нулевой срок `solo`
  и незапущенный ребёнок без таймера (находка П12);
- тест 18 — `compileWarnings` рядом с `compileErrors` в обеих копиях
  `test/support/compile_errors.dart` (находка П5).

## 4. Документы ядра

`docs(async_job): show ctx.child where a child is made`:

- `README.md` / `README.ru.md` — абзац «What the cells leave out»
  о `ctx.child`: строка таблицы уже стоит с шага 2;
- `doc/children.md` и `docs/ru/async_job/children.md`, «Running a child»: абзац
  о `ctx.child` для кода, который движка не знает, и о незапущенном ребёнке;
  `test/support/children_page.dart`, если блок кода меняется;
- `doc/time.md` и перевод, «A deadline for one step»: пример на `ctx.child`;
  `test/support/time_page.dart`, `time_rakes_test.dart`; трасса прежняя;
- `doc/extending.md`, `doc/engine.md` («A rule of your own») и переводы: движок
  со своим контекстом или правилами переопределяет `child` с `@useResult`;
  `each` берёт ребёнка оттуда же. `MyContext` страницы `child`
  не переопределяет, и абзац говорит это прямо: ребёнок `ctx.child` у него —
  ребёнок ядра, правило в нём не спрашивается (находка П4). Если правка тронет
  код страницы — сторожа `extending_rakes_test.dart` и support-файлы
  `extending_*.dart`;
- dartdoc `ChildJob` в `job.dart`, строка гида «Children» и абзац о `ChildJob`
  README ядра и перевода: рядом с `Job.deferred` назван `ctx.child` (находка
  П10);
- `CHANGELOG.md` и `docs/ru/async_job/CHANGELOG.md`: Breaking — новый член
  `JobContext` и `JobContextBase`, расширение с именем `child` уступает ему;
  Added — `ctx.child`.

## 5. Документы `solo` и проекта

`docs(solo): show ctx.child on the children page`:

- `doc/children.md` и перевод: где сказано, что ребёнка делает `job(...)`, —
  `ctx.child` для общего кода, с правилами создателя; эти фразы держат сторожа
  `_says` в `children_rakes_test.dart`, и они правятся тем же коммитом (находка
  П3);
- `doc/streams.md` и перевод: «with `job(...)` where it writes `Job.deferred`»
  называет и `ctx.child` (находка П10);
- `CHANGELOG.md` и `docs/ru/solo/CHANGELOG.md`: Breaking — `SoloContext.child`,
  отсылка на ядро;
- `docs/architecture.md` — абзац о `createEachJob` и новый `child`, срок шага
  на `ctx.child` (находка П10);
- `docs/handoff.md`.

Переводы — humanizer--ru по изменённым абзацам, только `ERROR` линтера.

## 6. Проверки и ревью работы

- Мутации из дизайна, по одной, откат копией: снять `child` из `SoloContext`
  и `_SoloContext` — 9; без `keepWhile` — 11; без `timeout` — 2 и 13;
  `createEachJob` мимо `child` — 8; без `@useResult` на `SoloContext.child`
  и на `JobContext.child` — 18 (находка П11).
- Все пакеты и оба примера; `python3 tool/reflow.py --check`,
  `check_line_width.py`, `check_translations.py`, `check_links.py`,
  `check_doc_shape.py`, `check_dartdoc.py`, `check_page_code.py`,
  `python3 -m unittest tool/build_site_test.py`, `tool/build_site.py`; стенды
  `tool/doc_snippets.py` и `tool/accumulation_snippets.py`;
  `tool/flutter_snippets.py` с `tool/check_traces.py`; `dart doc --dry-run`
  в трёх пакетах (находка П13); `tool/archive_floor.py` на полу 3.27.0 —
  в отдельной копии на коммите.
- Ревью работы: Opus и codex (`gpt-6-astra`, `xhigh`), каждому своя копия;
  разбор находок с вердиктами — в отчёте `2026-10-27-ctx-child-report.md`.
- Вливание в `main` перемоткой; push — по слову владельца.

## Что за рамками

- Выпуск: `async_job` 0.5.0, `solo`, scopo, `flutter_solo` — каждый отдельной
  просьбой владельца.
- Сообщение сессии HisBible — после вливания, о том, что `ctx.child` в `main`
  и выйдет с `async_job` 0.5.0.
- Сообщение сессии scopo — в день выпуска ядра: scopo нужен выпуск под
  `async_job` 0.5.0, прежде чем выйдет `flutter_solo` (находка П14).
- Рецепт паузы с пробуждением на страницах.

## Ревью плана: Opus

Субагент-ревьюер на Opus, своя копия дерева на `6d72f2a4`. Отчёт пришёл
сообщением и перенесён сюда; находки — П1–П14, в отчёте они шли как P1-1…P3-14
с уровнем важности.

### Прогон

1. `git log` и `git show` по `806d6227`, `37da782f`, `13e1658a`, `6d72f2a4`;
   `git log` по `lib` и `pubspec.yaml` ядра от тега `async_job-v0.4.0` ничего
   не вывел: после тега 0.4.0 в `lib` ядра правок нет.
2. `python3 tool/archive_floor.py stage <каталог>` —
   `Package has 0 warnings and 1 hint.` В раскладке лежит
   `flutter_solo/example/pubspec_overrides.yaml`: оверрайд примера попадает
   в архив.
3. Оверрайды `solo` и его примера в виде шага 1, `dart pub get` в примере —
   `Changed 53 dependencies!`, в `package_config` у `async_job` —
   `"rootUri": "../../../async_job"`.
4. `dart pub publish --dry-run` в `solo` с этими оверрайдами —
   `Package has 0 warnings and 1 hint.`, в списке архива
   `pubspec_overrides.yaml` под `example`.
5. Зонд `@useResult` в ядре, `dart analyze` — `3 issues found.`:
   `unused_result` дал только вызов через интерфейс; через базовый класс
   и подкласс предупреждения нет.
6. Прототип шага 2 по плану: `child` с `@useResult` в `JobContext`
   и `JobContextBase`, строки таблиц обоих README, `'child'` в `calls`.
   `dart test test/readme_recipe_test.dart -r expanded` —
   `00:00 +48 -3: Some tests failed.`, первая ошибка —
   `Bad state: no member read from "  @useResult"`.
7. Тот же прототип, парсер пропускает `@useResult` — `00:00 +50 -1`, красный
   остался один: «the members that do not run on leave the cell empty»,
   `at location [1] is 'child' instead of 'onCancel'`.
8. `solo` против ядра прототипа: `reference_page_test.dart`, `start_test.dart`,
   `children_test.dart` — `00:01 +56: All tests passed!`;
   `dart analyze --fatal-infos lib` — `No issues found!`.
9. Откат копиями, `dart pub get` в `solo`, `git status --short` — пусто.

### Находки

#### П1. Шаг 2: `readme_recipe_test.dart` красный по трём причинам, а план называет только строку таблицы

Одной строки таблицы мало. `contextMembers()` читает объявления `JobContext`
построчно: `@Deprecated` пропускает, а на `@useResult` бросает `StateError`,
и падают оба теста группы «the context at a glance», что бы ни стояло в README.
В `calls` нужен вызов `child`: строка 1126 сверяет ключи `calls` с членами
контекста. Тест «the members that do not run on leave the cell empty» держит
точный список членов с пустой третьей колонкой, и у `child`, фабрики, она
пустая. Строка таблицы нужна и в `README.ru.md` в том же шаге: тесты обходят
оба README. Счёт «2 красных» в обоих ревью дизайна поэтому неполон: видимо,
прототипы стояли без `@useResult` на отдельной строке. Доказательство — прогоны
6 и 7; парсер — `readme_recipe_test.dart:278-306`.

**Вердикт.** Принято. Сделано в `3c708ed6`, как предложено: парсер пропускает
`@useResult`, `child` стоит в `calls` и в списке пустых ячеек, строка — в обоих
README. Шаг 2 плана называет все три правки.

#### П2. Шаг 3: `start_test.dart` цитирует текст отказа `_own`, а план его не называет

Новый `_notCreatedHere` роняет `start_test.dart:104-105`. Полный поиск даёт
ровно пять цитат: `start_test.dart`, `children_rakes_test.dart:225`,
`children_test.dart:17`, `doc/children.md:252`, `docs/ru/solo/children.md:247`.

**Вердикт.** Принято. Все пять цитат правятся коммитом шага 3; файл добавлен
в шаг 3 плана.

#### П3. Шаг 5: проза, которую велено править, закреплена сторожами `_says` в `children_rakes_test.dart`

Ровно эти фразы держит `_says`: `children_rakes_test.dart:1462-1464` («Where
those pages make a child with `Job.deferred`, a controller makes it with
`job(...)`…», `doc/children.md:53-55`) и `:1851-1852` («Inside a controller's
body `ctx.run` takes jobs of that controller, the ones `job(...)` makes and
nobody has queued», `doc/children.md:239-240`). Правка прозы краснит набор.

**Вердикт.** Принято: шаг 5 плана называет сторожа, и они правятся тем же
коммитом.

#### П4. Шаг 4: для `extending.md` и `engine.md` не решено, переопределяет ли `child` сам движок страницы, и не названы сторожа

В разделе «A rule of your own» `engine.md` `MyContext` держит правило
в `check()`, и фраза «такой движок переопределяет `child`» рядом с движком,
который этого не делает, противоречит странице. Если же `MyContext` получит
переопределение, затронуты код страницы под `extending_rakes_test.dart`,
support-файлы `extending_plain.dart`, `extending_first_attempts.dart`,
`extending_stubs.dart` и сторож таблицы «### The whole engine»
(`extending_rakes_test.dart:1390-1460`, сейчас «`MyContext` | the constructor
alone»).

**Вердикт.** Принято: `MyContext` `child` не переопределяет, и абзац страницы
говорит это прямо — ребёнок `ctx.child` у такого движка остаётся ребёнком ядра,
правило в нём не спрашивается. Сторожа названы в шаге 4 на случай, если правка
тронет код страницы.

#### П5. Шаг 3, тест 18: существующий помощник анализатора отдаёт только ошибки

`compileErrors` берёт только строки `ERROR|`, а `unused_result` —
предупреждение (прогон 5). У файла есть копия в ядре с правилом «A change to
one goes to the other», без автоматической сверки. Отсылка «как в сторожах
dartdoc» не указывает ни на один существующий файл.

**Вердикт.** Принято: `compileWarnings` рядом с `compileErrors`, одной правкой
в обеих копиях `test/support/compile_errors.dart`; копии отличаются только
первой строкой, как и прежде.

#### П6. Шаг 3: неполны dartdoc членов `SoloContext` и строка `ctx.run` в справочнике

Правка класса не трогает dartdoc `run`, `start` и `runAll`
(`job_context.dart:53`, `56`, `70`, `82`): они говорят «made by `job(...)` of
this controller». Строка `ctx.run(child)` справочника и её перевод останутся
без `ctx.child`.

**Вердикт.** Принято: dartdoc трёх членов и строка `ctx.run(child)` в обоих
справочниках называют `ctx.child` в коммите шага 3.

#### П7. Проверки и сопутствующее стоят не на тех шагах

Питоновские проверки задания `docs` стоят только в шаге 6, а шаги 2 и 3
добавляют публичный dartdoc, на который `check_dartdoc.py` ставит пределы,
и правят переводы. humanizer--ru указан только в шаге 5, хотя переводы меняются
в шагах 2–5. `docs/handoff.md` обновляется только в шаге 5, хотя AGENTS.md
велит после каждого шага.

**Вердикт.** Принято: вступление плана ставит эти проверки, humanizer--ru
и handoff на каждый шаг. На шаге 2 `check_dartdoc.py` действительно поймал
dartdoc `JobContext.child` длиной 32 строки при пределе 30, до коммита.

#### П8. Решения «не делать» из ревью дизайна не попали в `docs/settled.md`

Вердикты дизайна закрыли отказом запрет передачи ребёнка (О2), `cancellable:`,
удаление `createEachJob`, проверки при создании; коммит `13e1658a` тронул
только запись дизайна.

**Вердикт.** Принято: пункты 112–115 `docs/settled.md` тем же коммитом, что
и разбор этого ревью. Рецепт паузы в них не входит: он не отвергнут, а вынесен
за рамки этой работы.

#### П9. `@useResult` стоит только на `JobContext.child`, а не на `JobContextBase.child`

Переопределение аннотацию не наследует (прогон 5): тело движка со своим типом
контекста предупреждения не получит.

**Вердикт.** Уже сделано в `3c708ed6`: аннотация стоит
на `JobContextBase.child` и на переопределении в `extending_test.dart`.

#### П10. Ещё места, где ребёнка делает только `Job.deferred`, — вне плана

Dartdoc `ChildJob` (`job.dart:478`, «[Job.deferred] makes one»); тексты отказов
ядра (`job_context.dart:1325`, «a child is made with Job.deferred», и `:1363`)
с цитатами в `observing_rakes_test.dart:283` и `lifecycle_test.dart:82`; README
ядра, `:248` и строка гида `:290`, с переводом;
`docs/architecture.md: 573-574`, срок шага на `Job.deferred`;
`solo/doc/streams.md:105` с переводом; `async_job/doc/cancellation.md:498`,
тот же `thumbnail` на `Job.deferred`.

**Вердикт.** Принято частично. Dartdoc `ChildJob`, README ядра с переводом —
в шаге 4; `architecture.md` и `streams.md` с переводом — в шаге 5. Тексты
отказов ядра остаются: в ядре ребёнок `Job.deferred` верен, а `ctx.child` там
и есть `Job.deferred`. `cancellation.md` остаётся: раздел об отмене, не о сроке
шага.

#### П11. Мутация «снять `child` из `SoloContext` и `_SoloContext`» не покажет красный тест 9 как `ArgumentError`

Тесты 10, 11 и 18 зовут `ctx.child` с телом на `SoloContext`: без
переопределения файл не соберётся, и мутант покажет ошибку загрузки. Мутанта
на снятый `@useResult` у `JobContext.child` в списке нет.

**Вердикт.** Принято. Тесты 9, 13 и 17 — в `child_shared_code_test.dart`;
мутант краснит там шесть тестов отказом
`was not created by this Solo (… or with ctx.child): "Job(step)"`. Мутант без
`@useResult` на `JobContext.child` краснит тест 18.

#### П12. Сценарии из ревью codex, которых нет ни в дизайне, ни в плане

Синхронный `ArgumentError` при нулевом и отрицательном сроке в обоих движках;
таймер незапущенного ребёнка `solo`; наблюдатель фактического родителя при
передаче.

**Вердикт.** Принято: тест нулевого срока в `solo`, `pendingTimers` пуст
у незапущенного ребёнка со сроком, и тест 6 ядра сверяет журналы создателя
и запустившей задачи.

#### П13. Шаг 6: чего в списке не хватает и что лишнее

Нет `dart doc --dry-run` (`gate.yml:133-136`, `:200-201`) и стенда
`tool/flutter_snippets.py` с `check_traces.py`. `check_page_code.py` лишний,
но вреда от него нет.

**Вердикт.** Принято: оба добавлены в шаг 6, `check_page_code.py` оставлен.

#### П14. Шаг 1 и сопутствующее

Полные наборы до правки ядра избыточны: после `async_job-v0.4.0` в `lib` ядра
нет коммитов. Прежние коммиты оверрайдов шли типом `build`, а план ставит
`chore:`. План не говорит, когда обновлять шапки записей. Сообщения сессии
scopo в день выпуска ядра нет даже в «Что за рамками».

**Вердикт.** Принято. Шаг 1 уже сделан коммитом `694f4a22` типа `build:`;
полные наборы прогнаны, вреда нет. Шапки записей обновляются с каждым коммитом
шага; сообщение scopo стоит в «Что за рамками».

### Оверрайды: проверено, находок нет

Пути верны: `solo` → `../async_job`, его пример → `../../async_job`,
`flutter_solo` → `../async_job`, его пример → `../../async_job`. `stage`
копирует корневой оверрайд пакета (`archive_floor.py:255-257`), оверрайд
примера `dart pub publish` кладёт в архив сам (прогоны 2 и 4), dry-run с ним
даёт подсказку, а не предупреждение; в `hosted_dependencies` перекрытый
`async_job` пропускается, и `downgrade` его не трогает. Задание `dart` гоняет
`pub get` в `solo` и примере, генераторы стендов ставят `async_job` из дерева
(`doc_snippets.py:82`, `accumulation_snippets.py:58`,
`flutter_snippets.py:108`). scopo 0.19.0 требует `async_job: ^0.4.0`, оверрайд
это обходит; `_ScopeInitContext extends JobContextBase`, своего `child` у него
нет. На шаге 2 `reference_page_test.dart` зелёный: `SoloContext` ещё
не объявляет `child` (прогон 8).

### Что из тестов дизайна не размещено

Все 18 размещены; 16 — существующий набор `each`. Пробелы — помощник для теста
18 (П5), раскладка по файлам ради мутации (П11) и сценарии codex (П12).
