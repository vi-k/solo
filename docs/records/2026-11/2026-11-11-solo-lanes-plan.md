> **Состояние на 2026-11-11:** план написан по дизайну, одобренному
> владельцем 2026-11-11 («да, одобряю, пиши план»); ждёт независимого ревью
> и одобрения владельцем. Кода нет.
> **Что это:** план работ по линиям: база `SoloController`, `Solo`
> и `SoloLanes`, `solo` 2.0.0 и `flutter_solo` 2.0.0, линты, документы,
> переводы и сторожа, порядок коммитов в ветке до выпусков; в конце — ревью
> плана с вердиктами.
> **Связанные записи:** `2026-11-10-solo-lanes-design.md` (дизайн, одобрен
> владельцем 2026-11-11), `2026-11-11-solo-lanes-design-review-report.md`,
> `2026-11-11-solo-lanes-design-review-report-2.md`.

# Линии: план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** несколько явных очередей корневых задач над одним состоянием
контроллера — `SoloLanes` и его линии, — при неизменном `Solo`, с выпусками
`solo` 2.0.0 и `flutter_solo` 2.0.0 и линтами, которые знают базу и линии.

**Architecture:** общее из `Solo` уходит в абстрактную базу
`SoloController<S>`; очередь, текущая задача и окно стартовых правил уходят
в закрытое ядро линии, которых у `Solo` одно, скрытое, а у `SoloLanes` —
столько, сколько объявил конструктор. Насос один на контроллер и обходит ядра
в порядке создания; закрытие и `cancelAll` идут по всем ядрам. Сначала база без
линий, затем ядро без новых возможностей, затем линии — каждый шаг под прежним
набором тестов.

**Tech Stack:** Dart 3.10, Flutter 3.38.1 (пол); `async_job` 1.x без правок
кода; `solo` 1.1.1 → 2.0.0, `flutter_solo` 1.1.0 → 2.0.0, `async_job_lints`
и `solo_lints` 0.2.0 → 0.2.x (распознавание), `solo_lints` → 0.3.0 (новые
правила); стенды на Python.

**Spec:** `docs/records/2026-11/2026-11-10-solo-lanes-design.md`. Дизайн —
источник правды; где план с ним расходится, прав дизайн, а расхождение
записывается решением исполнителя. Номера строк ниже — на `0ab1b9aa`.

## Global Constraints

- **Ветка.** Код и публичные документы идут в ветке `solo-lanes` от `main`
  и в `main` не вливаются до коммитов выпуска. Это исключение из правила
  «работай в `main`» `AGENTS.md` для этой работы, моё решение: `main` остаётся
  годным для патчей 1.x — `async_job` 1.0.3 с документацией уже ждёт слова
  владельца. `push` ветки — только по слову владельца.
- **Записи — в `main`.** `docs/handoff.md`, шапки дизайна и плана, отчёт работы
  коммитятся в `main` отдельными `docs:`-коммитами: следующая сессия читает их
  из `main`. Запись, которая описывает код ветки, говорит это в шапке.
- **Три части ветки.** Часть A — задачи 1–9: `solo` 2.0.0 и `flutter_solo`
  2.0.0. Часть B — задача 10: патчи 0.2.x обоих пакетов линтов с распознаванием
  базы и линии. Часть C — задача 11: минор `solo_lints` 0.3.0 с новыми
  правилами. Коммиты идут в этом порядке; как ветка входит в `main` — раздел
  ниже.
- **Выпуск не в плане.** Поле `version` в `pubspec.yaml` пакетов, коммиты
  `Release`, теги, `dart pub publish` — только по отдельному слову владельца.
  Ограничения зависимостей между пакетами план правит (`solo: ^2.0.0`
  у `flutter_solo` и в dev-зависимостях линтов): без них дерево не говорит
  о мажоре.
- **Пол SDK** — `sdk: ^3.10.0`, Flutter 3.38.1: синтаксис не новее Dart 3.10.
- **Оверрайды.** С задачи 2 у `packages/flutter_solo`
  и `packages/flutter_solo/example` — `pubspec_overrides.yaml` на дерево
  `solo`, первая строка — `# Until solo 2.0.0 is published.`. С задачи 10
  у `packages/async_job_lints` и `packages/solo_lints` — на дерево `solo`
  и `async_job`, у `solo_lints` ещё на `async_job_lints`; первая строка —
  `# Until solo 2.0.0 and the lint patches are published.`. До задачи 10 пакеты
  линтов разрешаются против опубликованного `solo` 1.1.1 и зелёные без правок.
  `packages/solo/example` зависит от `solo` путём и оверрайда не требует;
  `async_job` код не меняет, оверрайда на него у `solo` нет.
- **`Solo` не меняется.** Порядок событий, число микрозадач в насосе,
  в `close`, в `cancelAll` и в осушении, отладочные строки слово в слово, пути
  виртуальных вызовов (`enqueue` → `enqueueJob(job(...))`, накопитель →
  `enqueueJob`, `ctx.child` → `job`), `lane == null` у его задач — критерии
  приёмки дизайна. Прежний набор `packages/solo/test` правится только в задаче
  2 и только в типах; сторожа задачи 1 не правятся вовсе.
- **Проверки кода перед каждым коммитом** — из папки каждого затронутого
  пакета: `dart format --output=none --set-exit-if-changed .`,
  `dart analyze --fatal-infos`, `dart test` (`flutter test`
  во `packages/flutter_solo` и его `example`), `dart doc --dry-run`
  у публикуемых пакетов; у `packages/solo/example` —
  `dart analyze --fatal-infos` и `dart test`; у `packages/flutter_solo/example`
  ещё `flutter analyze`. В копии дерева сначала `pub get` (формат без
  `package_config` переписывает пакет в tall-стиль). У пакетов линтов ещё
  `python3 tool/plugin_probe.py` из корня.
- **Проверки документов** — из корня: `python3 tool/check_translations.py`,
  `python3 tool/reflow.py --check`, `python3 tool/check_line_width.py`,
  `python3 tool/check_links.py`, `python3 tool/check_dartdoc.py`,
  `python3 tool/check_doc_shape.py`, `python3 tool/check_page_code.py`, сборка
  сайта `python3 tool/build_site.py` с его сторожем
  `python3 -m unittest tool/build_site_test.py`. Изменённые абзацы русских
  переводов прогоняются через скилл `humanizer--ru` без шага «Голос», правятся
  только `ERROR` его линтера.
- **Dartdoc — по решению 103 `docs/settled.md`.** Первый абзац — одна фраза,
  второй — договор: что член делает, что бросает, одна главная ловушка. Разбор
  случаев — на странице; последний абзац ведёт на её раздел абсолютным адресом
  `blob/main` с якорем. `check_dartdoc.py`: абзац не длиннее 10 строк, блок
  `///` — 30. Ссылка на раздел появляется тем же коммитом, что и раздел.
- **Язык.** Код, комментарии, dartdoc, `CHANGELOG.md`, сообщения коммитов —
  по-английски; Conventional Commits; хвост коммита —
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Имена API** — ровно из дизайна: `SoloController<S>`, `Solo<S>`,
  `SoloLanes<S>`, `SoloLane<S>`, `SoloLaneId`, `SoloPendingLanes`;
  `@protected SoloLane<S> lane(String name)`,
  `@protected List<SoloLane<S>> get lanes`; `SoloJob.lane` типа `SoloLaneId?`.
- **Решения плана** — то, что дизайн оставил строителю или не назвал;
  исполнитель их не пересматривает молча:
  1. `SoloLane<S>` получает `SoloLaneId get id`: без него контроллер не сравнит
     `job.lane` со своей линией. Дизайн перечисляет члены линии без него; это
     дополнение, а не замена.
  2. Микрозадачу печати набора планирует конструктор `SoloLanes`,
     а не `SoloController`: у `Solo` печатать нечего, и лишняя микрозадача при
     создании ему не нужна.
  3. Отладочные строки `SoloLanes`, которые говорят о линии (`start`, `drop`,
     `remove`, `starts after`, `duplicate of`,
     `ended while the rules were asked`, `queue has no ready jobs`), начинаются
     с `<имя линии>: `. Шаг пустой простаивающей линии молчит; строка
     `queue has no ready jobs` печатается для линии, у которой в очереди есть
     задачи, но ни одна не готова. Строки контроллера (`close`,
     `close: draining`, `close: the drain gives way`, `closed`) прежние.
     У `Solo` всё прежнее.
  4. Поле снимка — `SoloPendingLanes.lanes` типа
     `List<({SoloLaneId lane, SoloPending pending})>`.
  5. Ядро линии — закрытый класс `_SoloLaneCore<S>` в новой части
     `lib/src/lane.dart`; `SoloLane<S>` — его публичное лицо
     (`_SoloLane<S> implements SoloLane<S>`), `SoloLaneId` создаётся ядром.
  6. `ownQueueCall` в `async_job_lints` сохраняет сигнатуру
     `MethodInvocation? ownQueueCall(Expression waited)`: её зовёт
     опубликованный `solo_lints` 0.2.0 через
     `package:async_job_lints/plugin_api.dart`, и патч, сменивший её, сломал бы
     ему загрузку. Три ответа дизайна живут в новой функции рядом;
     `ownQueueCall` отдаёт вызов только при ответе «своя».
  7. Новые правила называются `stale_emit` и `lane_outside_constructor`.

## Стенды: команды как в CI

Страницы `solo` держат тесты пакета: `*_rakes_test.dart` и `*_page_test.dart`
сверяют блоки страницы с кодом `test/support/` (`codeMissingFrom`,
`test/support/page_code.dart`). Они идут в `dart test` `packages/solo`.

Страницы под питоновскими стендами (`vs-bloc.md`, `accumulation.md`
с `accumulation-rules.md`, `riverpod.md`, `bloc.md`, `riverpod-and-bloc.md`
ядра) — задание `snippets` `.github/workflows/gate.yml`, шаги этого задания
дословно. Минимум для `vs-bloc.md`:

```sh
python3 tool/doc_snippets.py "$TMPDIR/doc-check"
```

и следом сборка и прогон драйверов, как в задании,
с `python3 tool/check_traces.py` по выводу.

`flutter_solo` (README, `doc/mixins.md`, `doc/testing.md`):

```sh
python3 tool/flutter_snippets.py "$TMPDIR/doc-check"
(cd "$TMPDIR/doc-check/flutter_check" && flutter pub get && flutter analyze \
  && flutter test --concurrency=1 | tee "$TMPDIR/flutter.out")
python3 tool/check_traces.py packages/flutter_solo/doc/mixins.md \
  "$TMPDIR/flutter.out"
```

## Как ветка входит в `main`

Делается при подготовке выпусков, по слову владельца; здесь — порядок.

1. Часть A: `git rebase main` в ветке, гейт целиком в копии на голове части A
   (пять заданий CI, `floor` на `~/fvm/versions/3.38.1`), затем в `main`
   `git merge --ff-only <последний коммит задачи 9>`. Выпуски `solo` 2.0.0
   и `flutter_solo` 2.0.0 — по слову владельца, снизу вверх. scopo не задет: он
   зависит от `async_job`, а не от `solo`.
2. После выпуска `solo` 2.0.0 — `git rebase main` остатка; оверрайды пакетов
   линтов на `solo` снимаются, на `async_job_lints` у `solo_lints` остаётся
   до его выпуска. Часть B — `--ff-only`, выпуски `async_job_lints` 0.2.x,
   затем `solo_lints` 0.2.x, тем же заходом, что `solo` 2.0.0: пропуск
   `await_own_queue` (дизайн, «Линты») кончается с их публикацией.
3. Часть C — так же, минор `solo_lints` 0.3.0; конфигурации примеров поднимают
   `solo_lints` до `^0.3.0` коммитом выпуска.

## Review Focus

Случаи, которых дизайн не называет, но которые встретит пользователь. Тест
на каждый стоит в задаче, которая владеет кодом.

1. **`SoloLanes` без единой линии.** Ожидание: `close()` кончается
   на микрозадаче, `pending == null`, `cancelAll()` кончается сразу,
   `isFinished` после закрытия — как у простаивающего `Solo`. Задача 4.
2. **Синхронный бросок тела линии A в проходе.** Ожидание: задача A кончается
   `Failed`, шаг линии B в том же проходе стартует свою задачу, насос не держит
   законченную задачу текущей ни в одной линии. Задача 4.
3. **Наблюдатель, который бросает в `onStart` задачи линии A.** Ожидание:
   ошибка идёт туда же, куда сегодня (`callHook`), задача линии B стартует
   в том же проходе. Задача 4.
4. **`lane` после `enqueue` в том же теле конструктора.** Ожидание:
   `StateError` от `lane`, поставленная задача остаётся в своей линии
   и стартует. Задача 4.
5. **Две линии кончаются в одной микротаске во время `close`.** Ожидание:
   `onClose` и `observer.onClose` — ровно по разу и после конца обеих,
   `close()` — один future. Задача 6.

---

### Task 1: сторожа старого движка

Дизайн («Цена», «Критерии приёмки»): то, что прежний набор держит не целиком,
встаёт тестами на старом движке до переделки насоса. Тесты характеризующие —
на `main` они зелёные сразу. Поэтому шаг «увидеть красное» здесь — мутация:
на каждый тест названа правка движка, которая его роняет; исполнитель вносит её
в копию файла, видит красное и возвращает файл копией, а не `git checkout`
(незакоммиченное ушло бы вместе с мутацией).

**Files:**
- Test: `packages/solo/test/engine_pins_test.dart`.

**Interfaces:**
- Produces: сторожа, которые задачи 2–7 не правят.

Счёт микрозадач — лестницей: `void ladder(List<String> log, int n)` ставит
`scheduleMicrotask`, пишет `tick <i>` и ставит следующую до `n`. Ожидаемый
журнал каждого такого теста — то, что печатает движок на `main`: исполнитель
снимает его первым прогоном и вписывает в тест буквально, с комментарием, что
это снимок 1.x. Отладочные строки — через `Solo.debug = log.add`, сброс
в `tearDown`.

- [ ] **Step 1: тесты.**
  - `an idle close finishes on a microtask of its own`: `close()` и лестница
    из 3 в одной синхронной части; журнал `onClose` и тиков. Мутация:
    в `_stopWork` при пустом `_current` звать `_finishClose` прямо — красный.
  - `a busy close finishes straight from the end of the job`: задача ждёт
    `Completer`; `close()`; в `onFinish` хука контроллера — лестница из 3;
    завершение `Completer`; журнал `finish`, `onClose`, тиков. Мутация:
    в `.then` текущей задачи `scheduleMicrotask(() => _finishClose(...))` —
    красный.
  - `a drain ends in the pump's microtask with no "queue has no ready jobs"
    line`: две задачи, `close(mode: SoloCloseMode.drain)`; отладочные строки
    целиком и место `onClose` относительно лестницы, запущенной в `onFinish`
    второй задачи. Мутация: печатать строку до проверки осушения — красный.
  - `a rejectable cancel of a cancellable: false job in its start rules is
    turned down`: `canStart` задачи `cancellable: false` зовёт `cancel()` у неё
    самой; задача стартует; строка `remove <job>: not cancellable` — слово
    в слово. Мутация: убрать ветку `_inTransition` в `cancelWith` — красный.
  - `a job put from a finish handler of a job close dropped is cancelled
    closed`: `whenFinished` снятой `close` задачи ставит новую; новая кончается
    `Cancelled` с `ClosedCancelReason`. Мутация: ставить закрытие после очистки
    очереди (`_closing` присвоить позже) — красный.
  - `a job put from a finish handler of a job cancelAll dropped survives and
    starts`: то же для `cancelAll`; новая задача стартует. Мутация: очищать
    очередь второй раз после отмены текущей — красный.
  - `enqueue goes through the virtual enqueueJob and job`: подкласс
    переопределяет `job` и `enqueueJob`, пишет журнал и зовёт `super`;
    `enqueue(...)` → журнал `job`, `enqueueJob`. Мутация: `enqueue` ставит
    задачу в обход виртуального `enqueueJob` — красный.
  - `an accumulator puts its groups through the virtual enqueueJob`: тот же
    подкласс, `collect(...)`, две записи → журнал `enqueueJob` на группу.
  - `ctx.child makes the child through the virtual job`: тело зовёт
    `ctx.child(...)` → журнал `job`.
  - `the debug lines of a busy pass are word for word`: очередь из трёх задач
    с ключами, политиками `droppable`, `keepLatest`, `restart`, одна отклонена
    `canStart`, одна бросает в правиле; журнал `Solo.debug` целиком, снимок
    с `main`.

  Хуки — собственные хуки контроллера, а не `SoloObserver`: типы наблюдателя
  меняет задача 2, а сторожа не правятся.

- [ ] **Step 2: красное.** Каждая мутация из шага 1 вносится по одной в копию
  `lib/src/solo.dart` или `lib/src/job.dart`,
  `dart test test/engine_pins_test.dart` — красный на своём тесте; файл
  возвращается копией. Тест, который мутация не роняет, переписывается, пока
  не уронит.

- [ ] **Step 3:** весь набор `packages/solo` зелёный; формат, анализ.

- [ ] **Step 4: коммит** `test(solo): pin the engine before the lanes work`.

### Task 2: база `SoloController`

Шаг первый дизайна: база, типы хуков, миксины, виджеты — без линий и без правки
насоса.

**Files:**
- Modify: `packages/solo/lib/src/solo.dart` — новый
  `abstract class SoloController<S extends Object>` с закрытым генеративным
  конструктором `SoloController._(S initialState)`; в него уходят поля и члены,
  которые дизайн («Иерархия») относит к базе, вместе с `_closing`, `_draining`,
  таймерами, `_running`, публикацией, `_setState`, `_reevaluate`,
  `_finishClose`, хуками и `_debug`. Очередь, `_current`, `_inTransition`,
  насос пока остаются в `Solo`, а база обращается к ним через закрытые
  абстрактные члены, которые `Solo` реализует (`_stopWork`, `_clearQueues`,
  `_busyJobs` и т. п. — имена на усмотрение исполнителя).
  `abstract class Solo<S extends Object> extends SoloController<S>`
  с конструктором `Solo(S initialState) : super._(initialState)`; члены очереди
  объявлены в `Solo`; `close` и `cancelAll` переопределены пересылкой в `super`
  с теми же dartdoc и сигнатурами. Статики `observer`, `unansweredHandler`,
  `debug` остаются на `Solo`; база читает их оттуда.
- Modify: `packages/solo/lib/src/observer.dart` — `Solo<Object>` →
  `SoloController<Object>` во всех хуках, в `SoloUnansweredHandler`
  и в реализации для нескольких наблюдателей (`:64-176`); dartdoc `onCreate`
  (`:57-63`) — «from the constructor of [SoloController]».
- Modify: `packages/solo/lib/src/solo_stream.dart` —
  `mixin SoloStream<S extends Object> on SoloController<S>`.
- Modify: `packages/solo/lib/src/job.dart`, `job_context.dart`,
  `accumulator.dart`, `queue.dart` — только там, где тип поля `_solo` или вызов
  требуют базы; поведение не меняется.
- Modify: `packages/flutter_solo/lib/src/solo_builder.dart:32`,
  `solo_selector.dart:39`, `solo_listener.dart:90`, `solo_selection.dart:100`,
  `solo_listenable.dart:33` — `SoloController<S>`.
- Modify: `packages/flutter_solo/pubspec.yaml` — `solo: ^2.0.0`; Create:
  оверрайды `packages/flutter_solo` и `packages/flutter_solo/example`.
- Modify: тесты `packages/solo/test` и `packages/flutter_solo/test` — только
  там, где `Solo<Object>` стоит в переопределении хука наблюдателя или
  в обработчике без ответа (из 113 вхождений в 36 файлах); `test/support/` тех
  страниц, чьи блоки меняются.
- Modify: `packages/solo/doc/diagnostics.md` (11 вхождений `Solo<Object>`),
  `testing.md` (3), `vs-bloc.md` (2), `errors.md` (1), `mistakes.md` (1) и их
  переводы в `docs/ru/solo/`; стенды этих блоков.
- Modify: `packages/solo/doc/reference.md` и перевод — раздел
  `## SoloController` с членами базы, раздел `## Solo` — с членами очереди
  и пересылками; `packages/solo/test/reference_page_test.dart` — `_classes`
  получает `'SoloController': SoloController`.
- Modify: `docs/conventions.md` — «Модификаторы классов»: `SoloController`
  с закрытым конструктором и почему не `sealed`; «Именование»: «контроллер —
  `Solo<S>` или `SoloLanes<S>`» (имя `SoloLanes` появляется здесь заранее
  и объясняется в задаче 5).
- Test: `packages/solo/test/controller_base_test.dart`.

**Interfaces:**
- Produces: `SoloController<S>` с членами базы;
  `Solo<S> extends SoloController<S>`; хуки `SoloObserver`
  и `SoloUnansweredHandler` на `SoloController<Object>`; миксины
  `on SoloController<S>`; поля `solo` виджетов типа `SoloController<S>`.

- [ ] **Step 1: тесты.**
  - `an observer gets the controller as SoloController`: наблюдатель
    с `onCreate(SoloController<Object> c)` видит созданный `Solo`;
  - `close and cancelAll are declared by Solo`: через `dart:mirrors` —
    `reflectClass(Solo).declarations` содержит `close`, `cancelAll`, `enqueue`,
    `enqueueJob`, `job`, `collect`, `accumulate`, `queue`, `current`,
    `lastJobWhere` (опора опубликованных линтов, дизайн «Иерархия»);
  - `SoloStream mixes into a SoloController`: класс
    `extends Solo<int> with SoloStream<int>` присваивается
    `SoloController<int>`;
  - `the base cannot be extended outside the library`: файл
    `test/support/compile_errors.dart` получает случай
    `class X extends SoloController<int>` с ожидаемой ошибкой — по образцу
    соседних случаев этого файла.

  Виджеты `flutter_solo` на контроллере, который не `Solo`, проверяет задача 7:
  до `SoloLanes` такого контроллера нет.

- [ ] **Step 2:** `dart test test/controller_base_test.dart` — не собирается:
  `SoloController` не определён.

- [ ] **Step 3: реализация** по списку файлов. Тело каждого перенесённого члена
  переносится без правок; dartdoc остаётся на члене, а не дублируется в `Solo`,
  кроме `close` и `cancelAll`, где пересылка в `Solo` получает `{@macro}`
  от базы.

- [ ] **Step 4: типы в тестах, примерах и страницах** по списку файлов.
  Страницы и стенды правятся вместе: `dart test` пакета, задание `snippets` для
  `vs-bloc.md`.

- [ ] **Step 5:** наборы `packages/solo`, `packages/solo/example`,
  `packages/flutter_solo`, `packages/flutter_solo/example` зелёные, сторожа
  задачи 1 — без правок; проверки кода и документов.

- [ ] **Step 6: коммит** `refactor(solo)!: extract the SoloController base`,
  в теле — `BREAKING CHANGE:` о хуках наблюдателя, обработчике без ответа
  и миксинах.

### Task 3: ядро линии под `Solo`

Переделка насоса без новых возможностей: очередь, текущая задача и окно
стартовых правил уходят в ядро; у `Solo` оно одно. Проверка — прежний набор
и сторожа задачи 1 без правок.

**Files:**
- Create: `packages/solo/lib/src/lane.dart` (`part of 'solo.dart'`) —
  `final class _SoloLaneCore<S extends Object>`:
  `SoloController<S> controller`, `SoloLaneId? id` (`null` у ядра `Solo`),
  `String? name`, `_SoloQueue<S> queue`, `_SoloJob<S, S, Object?>? current`,
  `_SoloJob<S, S, Object?>? inTransition`; и `final class SoloLaneId` —
  `final String name`, закрытый конструктор, `toString` → `name`.
- Modify: `solo.dart` — база держит `final _cores = <_SoloLaneCore<S>>[]`;
  `Solo` в конструкторе добавляет одно ядро без `id`; `_queue`, `_current`,
  `_inTransition` `Solo` становятся пересылками к нему. Насос: `_pump()` —
  проход по `_cores` в порядке создания, в каждом `_step(core)` с телом
  сегодняшнего `_pump` (`solo.dart:1347-1424`); шаг возвращает, продолжать ли
  проход: после отменяющего `close` — нет. Конец осушения: ветка «нечего взять»
  проверяет `_draining` и пустоту всех ядер (очередь, `current`,
  `inTransition`) и тогда зовёт `_finishClose` прямо. Закрытие (`_stopWork`):
  окна и очереди всех ядер роняются до первой отмены текущей; затем отмена
  текущим всех занятых ядер; счётчик незакончивших: `.then` каждой уменьшает
  его, последняя зовёт `_finishClose` прямо; ноль занятых —
  `scheduleMicrotask`. `cancelAll`: общий снимок очередей и окон всех ядер,
  очистка по снимку, снимок текущих задач после очистки, рассылка; одна
  занятая — её `cancel(...)` как есть, несколько — `Future.wait(...)` с типом
  `Future<void>`, ни одной — `Future<void>.value()`.
- Modify: `queue.dart` — `_SoloQueue<S>` держит ядро вместо `Solo<S>` (`:53`,
  `:62`); `clear` получает форму, которая берёт готовый снимок.
- Modify: `job.dart` — `_SoloJob` получает `_SoloLaneCore<S>? _destination`
  (ядро, которое её сделало) и `_SoloLaneCore<S>? _execution`; `isQueued`,
  `adoptedBy`, `cancelWith` (`:85-145`) смотрят `_destination`; `_destination`
  ставит фабрика `job`, `_execution` — `enqueueJob` первым делом и `adoptedBy`
  (ядро исполнения родителя).
- Modify: `accumulator.dart` — все обращения к очереди, текущей задаче
  и `enqueueJob` контроллера (`:49-265`, список в дизайне, «Очередь
  и политики») идут через ядро накопителя; пробуждение throttle смотрит
  `current` своего ядра и планирует насос контроллера.
- Modify: `job_context.dart` — `ctx.child` (`:191`) делает ребёнка
  с назначением, равным ядру исполнения задачи контекста; у `Solo` по-прежнему
  через виртуальный `Solo.job`.
- Test: новых нет — это переделка под зелёным набором: прежний набор и сторожа
  задачи 1 и есть её тест.

**Interfaces:**
- Consumes: `SoloController<S>` (задача 2).
- Produces: `_SoloLaneCore<S>`, `SoloLaneId` (класс пока не экспортируется),
  `_SoloJob._destination`, `_SoloJob._execution`,
  `bool _step(_SoloLaneCore<S> core)`; ядро, через которое накопитель
  и контекст ставят задачи.

- [ ] **Step 1: зелёное до начала.** Набор `packages/solo` и сторожа задачи 1
  зелёные на голове задачи 2.

- [ ] **Step 2: реализация** по списку файлов; сторожа задачи 1 и прежний
  набор — после каждого файла.

- [ ] **Step 3:** весь набор `packages/solo` и `packages/flutter_solo` зелёный
  без правок тестов; сторожа задачи 1 без правок; проверки кода.

- [ ] **Step 4: коммит** `refactor(solo): run the queue as a lane core`.

### Task 4: `SoloLanes`, линия и печать набора

**Files:**
- Modify: `lane.dart` — `abstract interface class SoloLane<S extends Object>`
  с членами из дизайна («Иерархия») и `id`; сигнатуры `enqueue`, `enqueueJob`,
  `job`, `collect`, `accumulate`, `queue`, `current`, `lastJobWhere` — те же,
  что у `Solo` 2.0 (параметры, типы, умолчания); `SoloPending? get pending`;
  `String get name`; `SoloLaneId get id`.
  `final class _SoloLane<S extends Object> implements SoloLane<S>` поверх ядра.
- Modify: `solo.dart` —
  `abstract class SoloLanes<S extends Object> extends SoloController<S>`,
  конструктор `SoloLanes(S initialState) : super._(initialState)` планирует
  микрозадачу печати; `lane(name)` и `lanes` (`@protected`); `bool _sealed`,
  который ставят микрозадача, первый `enqueueJob` любой линии при любом исходе
  (до первой ветки `enqueueJob`) и `close`. `lane` бросает `StateError` при
  повторе имени и после печати; текст ошибки называет причину и ведёт на раздел
  страницы о линиях. Отказ чужой задаче: задача другой линии или другого
  контроллера — тот же `ArgumentError`, что сегодня (`_notCreatedHere`),
  с текстом «was not created by this lane».
- Modify: `job.dart` — `SoloJob` получает `SoloLaneId? get lane`
  (`_execution ?.id`), dartdoc — `null` у задач `Solo` и у задачи без линии
  исполнения.
- Modify: `packages/solo/lib/solo.dart` — экспорт `SoloLanes`, `SoloLane`,
  `SoloLaneId` (через `src/solo.dart`).
- Modify: `packages/solo/doc/reference.md` и перевод — разделы `## SoloLanes`,
  `## SoloLane`; `reference_page_test.dart` — оба в `_classes`. Таблица
  параметров фабрик читается по-прежнему из `Solo`.
- Test: `packages/solo/test/lanes_test.dart`.

**Interfaces:**
- Consumes: ядро и `_step` (задача 3).
- Produces: публичные `SoloLanes<S>`, `SoloLane<S>`, `SoloLaneId`,
  `SoloJob.lane`.

Контроллер тестов — `final class _Two extends SoloLanes<({int a, int b})>`
с линиями `first` и `second`, созданными в конструкторе, и методами, которые
открывают линии тесту.

- [ ] **Step 1: тесты.**
  - группа `lane`: `a lane per name, in the order of creation` (`lanes`
    в порядке строк конструктора); `a second lane of one name throws`;
    `lane after the constructor's microtask throws`;
    `lane after the first enqueueJob throws`, по тесту на каждый исход
    постановки (поставлена, `Cancelled(closed)`, дубликат `droppable`);
    `lane after close throws`;
    `a late final lane read after the constructor throws` — поле
    `late final _x = lane('x')`, первое чтение в методе после
    `await Future.microtask(() {})` → `StateError`;
    `a lane read in the constructor before any job is made` — то же поле,
    прочитанное в теле конструктора, — линия есть;
    `the same name in two controllers is two lanes`;
    `lane after enqueue in the same constructor body throws and the job runs`
    (Review Focus 4);
  - группа `one job at a time in each lane`: две задачи одной линии идут
    по одной; задачи двух линий стартуют в одном проходе; `first: true` ставит
    в голову своей линии; `droppable`, `keepLatest`, `restart` ищут ключ только
    в своей линии — `restart` линии `first` не трогает текущую задачу `second`;
  - группа `the order of a pass`: задача, поставленная синхронной частью линии
    `first` в `second`, стартует в том же проходе; поставленная линией `second`
    в `first` — в следующем (асимметрия дизайна); `canStart` линии `second`
    видит то, что синхронно записал старт `first`;
  - группа `refusals`: задача `first.job(...)`, отданная `second.enqueueJob`, —
    `ArgumentError`, задача не ставится; задача другого контроллера — так же;
  - группа `SoloJob.lane`: у корня — линия постановки, у задачи, которую
    постановка сразу кончила, — тоже (`onFinish` видит линию); у задачи
    `Solo` — `null`; у ребёнка — линия исполнения родителя; `ctx.child`,
    отданный задаче другой линии, исполняется в её линии;
  - `a SoloLanes with no lanes closes like an idle Solo` (Review Focus 1);
  - `a synchronous throw in one lane does not stop the other's start` (Review
    Focus 2);
  - `an observer that throws in onStart does not stop the other lane` (Review
    Focus 3);
  - группа `debug lines`: строки линии с префиксом имени, пустая линия молчит,
    строки `Solo` в той же программе — без префикса (решение плана 3).

- [ ] **Step 2:** `dart test test/lanes_test.dart` — не собирается: `SoloLanes`
  не определён.

- [ ] **Step 3: реализация** по списку файлов.

- [ ] **Step 4: dartdoc** по решению 103. `SoloLanes`: фраза; договор — линии
  объявляются в конструкторе, одна задача за раз в каждой линии, запись одной
  линии переоценивает правила другой; ловушка — запись снимка целиком теряет
  чужое. `lane`: договор — `StateError` при повторе и после печати,
  `late final` запрещён прямо. `SoloLane`: члены публичны, защиту даёт закрытое
  поле. `SoloLaneId`, `SoloJob.lane`. Последний абзац каждого ведёт на раздел
  `packages/solo/doc/lanes.md` — ссылка появляется в задаче 8, а до неё абзаца
  нет (`check_links.py` проверяет якорь в дереве).

- [ ] **Step 5:** набор `packages/solo` зелёный, сторожа задачи 1 без правок;
  проверки кода и документов.

- [ ] **Step 6: коммит**
  `feat(solo): add SoloLanes with lanes declared in the constructor`.

### Task 5: правила, накопитель и ожидание между линиями

**Files:**
- Modify: `accumulator.dart`, `job.dart`, `solo.dart` — только если тесты ниже
  найдут, чего не сделала задача 3.
- Test: `packages/solo/test/lanes_rules_test.dart`,
  `packages/solo/test/lanes_accumulation_test.dart`.

**Interfaces:**
- Consumes: `SoloLanes`, `SoloLane` (задача 4).

- [ ] **Step 1: тесты правил.** Состояние — запись Dart
  `({Camera camera, int notices})` с `sealed class Camera`, `Off`, `Ready`:
  - `a write of one lane cancels the other's job by W`: задача линии `b`
    с `W = ({Ready camera, int notices})`; линия `a` пишет камеру `Off` →
    задача `b` кончается `Cancelled` с `RulesCancelReason`;
  - `a write cancels by keepWhile, past cancellable: false`;
  - `a job cancelled by the other lane's write loses ifCancelled`;
  - `a write that keeps W cancels nobody`;
  - `an epoch in the state cancels the other lane at the change and at the
    start`: рецепт эпохи из дизайна — задача, поставленная до смены
    и стартующая после, отменяется на старте; идущая — в момент смены;
  - `a child's write of a new epoch cancels its own root`;
  - `a read at the write keeps the other lane's field`: две линии пишут
    `copyWith` разных полей через `ctx.state` → оба поля на месте; и первая
    попытка — копия до `join` — теряет поле соседа (как в дизайне, «Как
    теряется чужое»);
  - `the job of a lane holds the lane until its join ends`: после отмены
    правилами `close()` ждёт конца `join` (дизайн, «Эпоха в состоянии»).

- [ ] **Step 2: тесты накопителя и ожидания.**
  - `a lane's accumulator puts every group in its lane`;
  - `two groups of one accumulator never run at once`;
  - `a throttle window wakes its group while the other lane is busy`: пока
    линия `b` занята долгой задачей, окно throttle накопителя линии `a`
    кончается и группа стартует;
  - `adjacent looks at the tail of its own lane`;
  - `a droppable call during a drain gets back the job that holds its key,
    in each lane`;
  - `a job of one lane awaits a job of the other`: кончается;
  - `waiting for one's own lane hangs`: тест с `fakeAsync` — после `elapse`
    задача не кончилась (как сегодняшний тест ожидания своей очереди).

- [ ] **Step 3:** красные — правка кода по находке; каждая правка ведётся
  тестом, который её требует. Тест, зелёный сразу, проверяется мутацией, как
  в задаче 1: какая правка задачи 3 или 4 его роняет — пишется в комментарии
  к группе.

- [ ] **Step 4:** набор зелёный; проверки кода.

- [ ] **Step 5: коммит**
  `test(solo): hold lanes to the rules, the accumulator and waiting` (или
  `feat(solo): …`, если понадобился код).

### Task 6: закрытие, `cancelAll` и `SoloPendingLanes`

**Files:**
- Modify: `packages/solo/lib/src/pending.dart` —
  `final class SoloPendingLanes extends SoloPending` с полем `lanes` (решение
  плана 4); `toString` — `SoloPending(<имя>: <снимок>, …)`, не бросает; dartdoc
  обещает в поле `pending` только `SoloPendingJob` и `SoloPendingQueue`.
  Dartdoc `SoloPendingJob.queued` (`:115-118`) — «within its lane» для
  `SoloLanes`. Dartdoc `sealed class SoloPending` и обзор вариантов (`:1-48`) —
  четыре варианта.
- Modify: `solo.dart` — `pending` базы: `Solo` отдаёт прежнее, `SoloLanes` —
  `SoloPendingLanes` по занятым линиям в порядке создания или `null`;
  `SoloLane.pending` — снимок своей линии по правилам `Solo.pending`. Dartdoc
  `Solo.debug` (`:106-111`) — вечное ожидание «within one lane».
- Modify: `solo_stream.dart` — `pending` (`:69`) спрашивает `super.pending`,
  как сегодня; проверить, что ступень работает и над `SoloLanes`.
- Modify: `packages/solo/doc/reference.md` и перевод, если сторож требует
  строк.
- Test: `packages/solo/test/lanes_close_test.dart`,
  `packages/solo/test/lanes_pending_test.dart`.

**Interfaces:**
- Consumes: ядра и закрытие (задача 3), `SoloLanes` (задача 4).
- Produces: `SoloPendingLanes` с `lanes`.

- [ ] **Step 1: тесты закрытия.**
  - `close cancels the current jobs of every lane before it waits`: обе линии
    заняты; `close()`; обе задачи видят отмену в одной синхронной части;
  - `close finishes when the last lane ends`: линии кончаются в разных
    микрозадачах; `onClose` — после второй;
  - `two lanes that end in one microtask close once` (Review Focus 5);
  - `a cancelling close from a rule ends the pass after its lane`: правило
    задачи линии `a` зовёт `close()`; задача линии `b` в этом проходе
    не стартует и кончается `Cancelled(closed)`; строки `a` — прежние строки
    шага;
  - `close(drain) from a rule lets the pass go on`;
  - `cancelAll from a rule lets the pass go on,
    and a cancellable: false job survives in its queue`;
  - `a drain ends when every lane is empty`;
    `a drain of an idle SoloLanes ends on a microtask`;
  - `a job put into another lane from a finish handler during cancelAll
    survives`, в обоих порядках линий (снимки на момент вызова);
  - `cancelAll with one busy lane returns that job's cancel`:
    `identical`-проверка невозможна на `Future`, поэтому — по порядку событий:
    future `cancelAll` кончается в той же микрозадаче, что `job.cancel()` той
    задачи;
  - `cancelAll with two busy lanes completes after both`;
  - `a job put into another lane during a drain is cancelled closed`.

- [ ] **Step 2: тесты снимка.**
  - `pending is null with every lane idle`;
  - `one busy lane is still SoloPendingLanes`;
  - `pending lists busy lanes in the order of creation`;
  - `SoloPendingLanes prints as SoloPending and never throws` — с ключом, чей
    `toString` бросает;
  - `a SoloStream over SoloLanes says SoloPendingStream after the lanes`;
  - `Solo.pending keeps its variants`: исчерпывающий `switch` в тесте
    по `SoloPendingJob`, `SoloPendingQueue`, `SoloPendingStream`
    и `SoloPendingLanes`.

- [ ] **Step 3: реализация.**

- [ ] **Step 4:** набор зелёный; сторожа задачи 1 без правок; проверки кода
  и документов.

- [ ] **Step 5: коммит** `feat(solo): close, cancel and report every lane`.

### Task 7: `flutter_solo` над `SoloLanes`

**Files:**
- Modify: `packages/flutter_solo/lib/flutter_solo.dart:1-3` — dartdoc
  библиотеки без «exclusive ownership»: «one job at a time, in each lane».
- Test: `packages/flutter_solo/test/solo_lanes_widgets_test.dart`.

**Interfaces:**
- Consumes: `SoloLanes` (задача 4), поля `SoloController<S>` (задача 2).

- [ ] **Step 1: тесты.** Контроллер — `SoloLanes<int>` с двумя линиями
  и `SoloListenable`:
  - `SoloBuilder rebuilds on a write of either lane`;
  - `SoloSelector and SoloSelection.from take a SoloLanes`;
  - `SoloListener reacts to the writes of both lanes`;
  - `a SoloLanes with SoloListenable is a ValueListenable`.

- [ ] **Step 2:** прогон — зелёный сразу, если задача 2 сделала типы верно;
  красный — правка по находке. Мутация для проверки теста: вернуть одному полю
  тип `Solo<S>` — тест не собирается.

- [ ] **Step 3:** наборы `packages/flutter_solo` и его примера зелёные;
  проверки кода.

- [ ] **Step 4: коммит**
  `test(flutter_solo): take a SoloLanes in every widget`.

### Task 8: страница о линиях

**Files:**
- Create: `packages/solo/doc/lanes.md`; `docs/ru/solo/lanes.md`.
- Create: `packages/solo/test/lanes_rakes_test.dart`,
  `packages/solo/test/support/lanes_page.dart`,
  `packages/solo/test/support/lanes_first_attempts.dart`,
  `packages/solo/test/support/lanes_stubs.dart` — по образцу
  `state_rakes_test.dart` и его `support/` (`codeMissingFrom` с `alsoIn` для
  первых попыток).
- Modify: `tool/check_translations.py` — пара `lanes.md`;
  `site/astro.config.mjs` — `page('solo/lanes', 'Lanes', 'Линии')` в теме
  `solo` рядом с `state`; при надобности `tool/build_site.py`.
- Modify: dartdoc из задачи 4 — последние абзацы со ссылками на разделы.

**Interfaces:**
- Consumes: всё API задач 4–6.

Форма — «требование → первая попытка → ответ» (скилл `doc-reader`). Разделы
и их первые попытки:

1. **Two queues over one state** — требование `Station` из дизайна; первая
   попытка — два контроллера и `externalSetState` (рецепт раунда 6); ответ —
   `Station` на `SoloLanes`.
2. **A write that keeps the other lane's work** — первая попытка: копия
   до `join` (дизайн, «Как теряется чужое»); ответ — чтение в момент записи.
3. **A snapshot from the server** — первая попытка: `emit` ответа целиком;
   ответ — склейка; рецепт ленты с лайками из дизайна, `settled(seen)`.
4. **Work that a new epoch makes stale** — ответ сразу (ловушки, к которой
   ведёт словарь API, нет): эпоха в состоянии и `keepWhile`, отмена
   и освобождение линии — разные гарантии.
5. **Rules by type on a record state** — `W` на записи Dart и почему класс
   с полями его теряет.
6. **Declaring lanes** — `lane` в конструкторе; первая попытка — `late final`
   поле и `StateError`; ответ — присваивание в теле конструктора.
7. **The table of cases** — асимметрия прохода, отмена сквозь
   `cancellable: false` записью соседа, ожидание между линиями и своей линии,
   закрытие и осушение по всем линиям, отказ продолжению в другой линии при
   осушении, корректор лайка после `settled`.

Каждый блок кода страницы стоит в `support/` и прогоняется тестом; трассы
и состояния под блоками — то, что печатает тест.

- [ ] **Step 1: сторож первым.** `lanes_rakes_test.dart` с тестами каждого
  раздела и проверкой `codeMissingFrom('doc/lanes.md', ...)` — красный:
  страницы нет.
- [ ] **Step 2: страница** — блоки дословно из `support/`; прогон зелёный.
- [ ] **Step 3: dartdoc** задачи 4 — ссылки на разделы.
- [ ] **Step 4: перевод**, `humanizer--ru` по всем абзацам, сайт.
- [ ] **Step 5: проверки** кода `packages/solo` и все проверки документов,
  сборка сайта.
- [ ] **Step 6: коммит** `docs(solo): add the lanes page`.

### Task 9: тексты проекта, `CHANGELOG` и переводы

Всё из раздела дизайна «Что меняется в правилах и текстах проекта», по пунктам;
здесь — разбиение и проверки.

**Files:**
- Modify, `solo`: `packages/solo/README.md` (первая строка, политики,
  «Versions»), `doc/vs-bloc.md` (таблица соответствий и три фразы),
  `doc/jobs.md` (ссылка рецепта лайков на `lanes.md`), `doc/mistakes.md`,
  `doc/errors.md`, `doc/state.md` и `doc/diagnostics.md` (`AppController`
  и `Logged` миксином `on SoloController<S>`, `SoloPendingLanes`, наблюдатель
  при нескольких корнях, `onCreate` без линий), `doc/streams.md`,
  `lib/solo.dart:1`, `pubspec.yaml:3` (описание).
- Modify, `flutter_solo`: `README.md:3` и фраза «One root job of a controller
  at a time», `doc/mixins.md:207` (`AppController` миксином), `pubspec.yaml:3`.
- Modify, `async_job`: `packages/async_job/README.md` — «runs one root job at a
  time…» о `Solo` и линиях; запись в его «Unreleased».
- Modify: `docs/architecture.md` (инварианты 1, 6, 7, «Понятия», карта
  модулей), `docs/settled.md` (решения 46, 50, 54, 84 — по разделу дизайна
  «Решения `docs/settled.md`»), `docs/conventions.md` (модификаторы
  `SoloLanes`, `SoloLane`, `SoloLaneId`, `SoloPendingLanes`).
- Modify: `site/site.json:5`, `site/content/index.md` (строки 9 и 30),
  `site/astro.config.mjs:162`.
- Modify: `packages/solo/CHANGELOG.md` и `packages/flutter_solo/CHANGELOG.md` —
  раздел «Unreleased»: «Breaking» по списку «Что ломается в 2.0» с миграцией
  (обновить плагины линтов), «Added» — `SoloController`, `SoloLanes`,
  `SoloLane`, `SoloLaneId`, `SoloJob.lane`, `SoloPendingLanes`.
- Modify: переводы всего перечисленного (`README.ru.md` обоих пакетов,
  `docs/ru/<пакет>/…`, `docs/ru/<пакет>/CHANGELOG.md`).
- Modify: стенды и `support/` страниц, чьи блоки меняются; сторож имён
  `flutter_solo` в `tool/doc_snippets.py` при правке `vs-bloc.md`.

- [ ] **Step 1: сторожа первыми.** Где правка меняет блок кода страницы —
  сначала `support/` и тест, красный, потом страница.
- [ ] **Step 2: тексты** по списку; каждое «по одной» уточняется до «у `Solo`;
  у `SoloLanes` — в каждой линии», а не вычёркивается.
- [ ] **Step 3: проверка полноты.** `rtk proxy grep -rn`
  по `packages/*/README.md`, `packages/*/doc`, `packages/*/lib`,
  `docs/architecture.md`, `site/` на `one at a time`, `exclusive`, `one queue`,
  `no concurrent`, `Solo<Object>`; каждое оставшееся вхождение — либо о `Solo`
  и верно, либо правится.
- [ ] **Step 4: переводы**, `humanizer--ru` по изменённым абзацам.
- [ ] **Step 5: проверки.** Все проверки кода `solo`, `flutter_solo`,
  `async_job` (README ядра под сторожами его пакета) и примеров; все проверки
  документов; задание `snippets`; стенд `flutter_snippets.py`.
- [ ] **Step 6: коммиты** по пакету: `docs(solo): …`, `docs(flutter_solo): …`,
  `docs(async_job): …`, `docs: …` для `docs/` и сайта. Последний коммит части
  A.

### Task 10: линты знают базу и линию (патчи 0.2.x)

**Files:**
- Modify: `packages/async_job_lints/lib/src/context.dart` — `isSoloController`
  (`SoloController` и подтипы), `isSoloLane`; `isSoloMember` узнаёт члены
  `SoloLane` для правил, которые узнают члены `Solo` по имени; новая
  `QueueLane queueLaneOf(Expression waited)`
  с `enum QueueLane { own, other, unknown }` — сравнивает линию, в которую
  ставит ожидаемый вызов (найдена в теле метода всегда, и при объявленном
  `SoloJob`: проверка `isSoloJob(call.staticType)` на `:343` больше
  не возвращается раньше поиска линии), с линией тела, которое ждёт (цель
  вызова, которому отдано тело: поле `SoloLane` своего класса);
  `ownQueueCall` — прежняя сигнатура, вызов только при `own`; `close`
  и `cancelAll` — по владельцу через `isSoloController`. Экспорт новых имён
  из `plugin_api.dart`.
- Modify: `async_job_lints/lib/src/rules/bare_await.dart:93`,
  `discarded_outcome.dart:66` — молчат только при `own` (через `ownQueueCall`,
  без правки, если её смысл сузился верно — проверяет тест).
- Modify: правила, которые узнают члены `Solo` по имени (`key_per_request`,
  `ignore_failure_hides_bugs`, `outcome_after_await`) — те же члены `SoloLane`.
- Modify: `packages/solo_lints/lib/src/rules/await_own_queue.dart` —
  `_queuedHere` (`:105-114`) узнаёт тело, отданное линии своего контроллера,
  и запоминает линию; владелец — `isSoloController`; сообщение называет линию.
- Modify: `pubspec.yaml` обоих — dev-зависимость `solo: ^2.0.0`; оверрайды
  (Global Constraints).
- Modify: `CHANGELOG.md` обоих и переводы — «Unreleased», «Fixed»/«Added».
- Test: `bare_await_test.dart`, `discarded_outcome_test.dart`,
  `key_per_request_test.dart`, `ignore_failure_hides_bugs_test.dart`,
  `outcome_after_await_test.dart`, `await_own_queue_test.dart` — случаи
  `SoloLanes`.

**Interfaces:**
- Consumes: `SoloController`, `SoloLanes`, `SoloLane` из `solo` (дерево).
- Produces: `isSoloController`, `isSoloLane`, `queueLaneOf`, `QueueLane`
  в `plugin_api.dart`.

- [ ] **Step 1: тесты.**
  - `await_own_queue`: `await _likes.enqueue(...).done` в теле задачи
    `_likes` — отчёт; в теле задачи `_reload` — нет; метод, объявленный
    `SoloJob<void> like()`, который ставит в `_likes`, ожидаемый из тела
    `_likes` — отчёт; задача из параметра — тишина; `close` контроллера
    `SoloLanes` и контроллера со `SoloStream` из тела — отчёт;
  - `bare_await`: `await reload().done` из тела линии `_likes`, где `reload()`
    ставит в `_reload`, — отчёт `bare_await` (иначе молчали бы все три правила,
    дизайн «Линты»); то же в своей линии — тишина (`await_own_queue` говорит);
  - `discarded_outcome` — те же два случая;
  - `key_per_request`, `ignore_failure_hides_bugs`, `outcome_after_await` —
    по случаю на член `SoloLane`, который правило узнаёт у `Solo`;
  - прежние случаи `Solo` — без правок.

- [ ] **Step 2:** прогон — красные новые случаи.

- [ ] **Step 3: реализация.**

- [ ] **Step 4: совместимость.** Опубликованный `solo_lints` 0.2.0 против
  нового `async_job_lints`: в копии `solo_lints` 0.2.0 из `~/.pub-cache` (или
  `dart pub unpack solo_lints:0.2.0`) с оверрайдом на дерево
  `async_job_lints` — `dart analyze` и его тесты зелёные. Это доказывает, что
  патч не ломает загрузку старого плагина.

- [ ] **Step 5:** наборы обоих пакетов, `python3 tool/plugin_probe.py`;
  проверки кода и документов.

- [ ] **Step 6: коммиты**
  `fix(async_job_lints): recognise SoloController and SoloLane`,
  `fix(solo_lints): tell the lanes apart in await_own_queue`.

### Task 11: правила `stale_emit` и `lane_outside_constructor` (миноры)

**Files:**
- Create: `packages/solo_lints/lib/src/rules/stale_emit.dart`,
  `lane_outside_constructor.dart`; регистрация в плагине; `test/` к каждому;
  страница правил в README `solo_lints` и перевод; `CHANGELOG.md` и перевод.
- Modify: `packages/solo_lints/pubspec.yaml` — `async_job_lints: ^0.2.N`, где
  N — патч задачи 10: правилам нужны `isSoloController` и `isSoloLane`.

**Interfaces:**
- Consumes: `isSoloController`, `isSoloLane` (задача 10).

- [ ] **Step 1: тесты `stale_emit`.** В теле задачи, отданной линии
  `SoloLanes`:
  `final feed = ctx.state; await ctx.join(...); ctx.emit(feed.confirm(post));`
  — отчёт на `emit`; `ctx.emit(ctx.state .confirm(post))` после `await` —
  тишина; значение, прочитанное после последнего `await`, — тишина; то же
  в задаче `Solo` — тишина (у `Solo` соседней линии нет);
  `ctx.emit(await ctx.abandonable(api.fetchFeed))` — тишина (эвристика его
  не ловит, дизайн это называет).
- [ ] **Step 2: тесты `lane_outside_constructor`.** `lane('x')` в теле
  конструктора — тишина; в инициализаторе `late final` поля — отчёт; в методе —
  отчёт; у класса не `SoloLanes` — тишина.
- [ ] **Step 3:** прогон — красные.
- [ ] **Step 4: реализация**, сообщения и `correction` — по образцу
  `await_own_queue`.
- [ ] **Step 5:** набор, `plugin_probe.py`, проверки документов.
- [ ] **Step 6: коммит**
  `feat(solo_lints): add stale_emit and lane_outside_constructor`.

### После задач

- Независимое ревью всей ветки на Opus, по своей копии дерева на ревьюера;
  находки с вердиктами — в отчёт `2026-11-NN-solo-lanes-report.md`.
- Гейт целиком в копии на голове каждой части: пять заданий CI локально,
  включая `floor` на `~/fvm/versions/3.38.1`.
- В `main`, отдельными `docs:`-коммитами: отчёт; `docs/handoff.md` — ветка
  готова и ждёт выпусков, какие коммиты закрывают части A, B и C; шапки дизайна
  и плана — «сделано в ветке `solo-lanes`, ждёт выпуска».

## Ревью плана

Ещё не проведено.
