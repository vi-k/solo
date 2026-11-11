> **Состояние на 2026-11-11:** план написан по дизайну, одобренному
> владельцем 2026-11-11 («да, одобряю, пиши план»), прошёл независимое ревью
> Opus и исправлен по нему (раздел «Ревью плана»); ждёт одобрения владельцем
> и выбора способа исполнения. Кода нет.
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
набором тестов и стендов.

**Tech Stack:** Dart 3.10, Flutter 3.38.1 (пол); `async_job` 1.x без правок
кода; `solo` 1.1.1 → 2.0.0, `flutter_solo` 1.1.0 → 2.0.0, `async_job_lints`
и `solo_lints` 0.2.0 → 0.2.x (распознавание), `solo_lints` → 0.3.0 (новые
правила); стенды на Python.

**Spec:** `docs/records/2026-11/2026-11-10-solo-lanes-design.md`. Дизайн —
источник правды; где план с ним расходится, прав дизайн, а расхождение
записывается решением исполнителя. Номера строк ниже — на `0ab1b9aa`.

## Global Constraints

- **Ветка.** Код и публичные документы идут в ветке `solo-lanes` от `main`,
  в своей копии дерева (`git worktree`): параллельные сессии делят основную
  копию. В `main` ветка не вливается до коммитов выпуска. Это исключение
  из правила «работай в `main`» `AGENTS.md` для этой работы, моё решение:
  `main` остаётся годным для патчей 1.x — `async_job` 1.0.3 с документацией уже
  ждёт слова владельца. `push` ветки — только по слову владельца.
- **Записи — в `main`.** `docs/handoff.md`, шапки дизайна и плана, отчёт работы
  коммитятся в `main` отдельными `docs:`-коммитами: следующая сессия читает их
  из `main`. Запись, которая описывает код ветки, говорит это в шапке. Хэши
  коммитов ветки записи называют только после вливания: `git rebase main` перед
  вливанием их переписывает; до того — имя ветки и заголовок коммита.
- **Три части ветки.** Часть A — задачи 1–9: `solo` 2.0.0 и `flutter_solo`
  2.0.0. Часть B — задача 10: патчи 0.2.x обоих пакетов линтов с распознаванием
  базы и линии. Часть C — задача 11: минор `solo_lints` 0.3.0 с новыми
  правилами. Коммиты идут в этом порядке; как ветка входит в `main` — раздел
  ниже.
- **Выпуск не в плане.** Поле `version` в `pubspec.yaml` пакетов, коммиты
  `Release`, теги, `dart pub publish` — только по отдельному слову владельца.
  Ограничения зависимостей между пакетами план правит (`solo: ^2.0.0`
  у `flutter_solo` и в dev-зависимостях линтов, `async_job_lints: ^0.2.N`
  у `solo_lints`): без них дерево не говорит о том, что выходит.
- **Пол SDK** — `sdk: ^3.10.0`, Flutter 3.38.1: синтаксис не новее Dart 3.10.
- **Оверрайды.** С задачи 2 у `packages/flutter_solo`
  и `packages/flutter_solo/example` — `pubspec_overrides.yaml` на дерево
  `solo`, первая строка — `# Until solo 2.0.0 is published.`. С задачи 10
  у `packages/async_job_lints` и `packages/solo_lints` — на дерево `solo`,
  у `solo_lints` ещё на `async_job_lints`; первая строка —
  `# Until solo 2.0.0 and the lint patches are published.`. На `async_job`
  оверрайда нет ни у кого: его код не меняется, и дерево `solo` разрешается
  против опубликованного. До задачи 10 пакеты линтов разрешаются против
  опубликованного `solo` 1.1.1 и зелёные без правок. `packages/solo/example`
  зависит от `solo` путём и оверрайда не требует.
- **`Solo` не меняется.** Порядок событий, число микрозадач в насосе,
  в `close`, в `cancelAll` и в осушении, отладочные строки слово в слово, пути
  виртуальных вызовов (`enqueue` → `enqueueJob(job(...))`, накопитель →
  `enqueueJob`, `ctx.child` → `job`), `lane == null` у его задач — критерии
  приёмки дизайна.
- **Какие тесты правятся.** Тесты поведения движка в `packages/solo/test`
  правятся только в задаче 2 и только в типах. Сторожа задачи 1 не правятся
  никогда. Страничные сторожа — `reference_page_test.dart`,
  `*_rakes_test.dart`, `*_page_test.dart` и `test/support/` — правятся вместе
  со своей страницей в той задаче, которая меняет страницу.
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
- **Решения `docs/settled.md`** правятся тем же коммитом, что и код, который их
  меняет (дизайн, «Решения `docs/settled.md`»): 46, 50 и 84 — в задаче 4, 54 —
  в задаче 10.
- **Язык.** Код, комментарии, dartdoc, `CHANGELOG.md`, сообщения коммитов —
  по-английски; Conventional Commits; хвост коммита —
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Имена API** — ровно из дизайна: `SoloController<S>`, `Solo<S>`,
  `SoloLanes<S>`, `SoloLane<S>`, `SoloLaneId`, `SoloPendingLanes`;
  `@protected SoloLane<S> lane(String name)`,
  `@protected List<SoloLane<S>> get lanes` (неизменяемый список);
  `SoloJob.lane` типа `SoloLaneId?`.
- **Решения плана** — то, что дизайн оставил строителю или не назвал;
  исполнитель их не пересматривает молча:
  1. `SoloLane<S>` получает `SoloLaneId get id`: без него контроллер не сравнит
     `job.lane` со своей линией. Дизайн перечисляет члены линии без него; это
     дополнение, а не замена.
  2. Микрозадачу печати набора планирует конструктор `SoloLanes`,
     а не `SoloController`: у `Solo` печатать нечего, и лишняя микрозадача при
     создании ему не нужна.
  3. Отладочные строки. У `Solo` все прежние. У `SoloLanes` префикс
     `<имя линии>: ` получают строки о постановке и шаге линии: `enqueue X`,
     `enqueue X first`, `enqueue X: closed`, `enqueue X: duplicate of Y…`
     (`solo.dart:588`, `:606`, `:624`, `:643`), `restart: …` (`:674`),
     `rule of X threw` (`:1382`), `start X: ended while the rules were asked`
     (`:1396`), `drop X` (`:1409`), `queue has no ready jobs` (`:1362`),
     `remove X: …` (`job.dart:137`, `:144`), `move X to the tail`
     (`accumulator.dart:202`). Без префикса остаются строки о задаче
     и состоянии — `X emit:` (`job_context.dart:285`), `X expected …`
     (`solo.dart:1500`), `state: …`, `externalSetState: …` — и строки
     контроллера: `close`, `close: draining`, `close: the drain gives way`,
     `closed`. `queue has no ready jobs` у линии печатается там же, где
     у `Solo`, кроме одного случая: шаг простаивающей линии, которая ничего
     не взяла из пустой очереди, молчит — иначе каждый проход печатал бы её
     за каждую пустую линию. Шаг, который снял задачи (`drop`) и кончился
     пустой очередью, печатает её, как `Solo`.
  4. Поле снимка — `SoloPendingLanes.lanes` типа
     `List<({SoloLaneId lane, SoloPending pending})>`.
  5. Ядро линии — закрытый класс `_SoloLaneCore<S>` в новой части
     `lib/src/lane.dart`; `SoloLane<S>` — его публичное лицо
     (`_SoloLane<S> implements SoloLane<S>`), `SoloLaneId` создаётся ядром
     линии `SoloLanes`; у ядра `Solo` идентификатора нет.
  6. `ownQueueCall` в `async_job_lints` сохраняет сигнатуру
     `MethodInvocation? ownQueueCall(Expression waited)`: её зовёт
     опубликованный `solo_lints` 0.2.0 через
     `package:async_job_lints/plugin_api.dart`, и патч, сменивший её, сломал бы
     ему загрузку. Три ответа дизайна живут в новой функции рядом.
  7. Новые правила называются `stale_emit` и `lane_outside_constructor`.
     `stale_emit` — с умолчательной серьёзностью, как `key_per_request`: это
     эвристика. `lane_outside_constructor` — `WARNING`, как `await_own_queue`:
     вызов после печати бросает.
  8. Конец осушения проверяет контроллер, а не шаг линии: шаг, который ничего
     не взял, при осушении и пустых ядрах кончает проход без строки, а `_pump`
     после прохода — один раз — проверяет «осушение и все ядра пусты» и зовёт
     `_finishClose`. Так кончается осушение `SoloLanes` без единой линии, и две
     пустые линии не зовут `_finishClose` дважды. У `Solo` это та же
     микрозадача насоса и те же строки.
  9. Молчание `bare_await` и `discarded_outcome` об ожидании своей линии
     включает новый параметр регистрации `ownLaneReportedElsewhere` (умолчание
     `false`) рядом с `ownQueueReportedElsewhere`. Опубликованный `solo_lints`
     0.2.0 его не передаёт, и с пропатченным `async_job_lints` `bare_await`
     продолжает говорить об ожидании линии, о котором старый `await_own_queue`
     молчит.

## Стенды: команды как в CI

Страницы `solo` держат тесты пакета: `*_rakes_test.dart` и `*_page_test.dart`
сверяют блоки страницы с кодом `test/support/` (`codeMissingFrom`,
`test/support/page_code.dart`). Они идут в `dart test` `packages/solo`.

**Полный прогон стендов** — то, что задачи ниже называют этими словами:

1. Задание `snippets` `.github/workflows/gate.yml` целиком, его шаги дословно:
   пять стендов (`tool/doc_snippets.py`, `tool/accumulation_snippets.py`,
   `tool/adapter_snippets.py`, `tool/riverpod_snippets.py`,
   `tool/bloc_snippets.py`), сборка шести пакетов, все драйверы
   и `tool/check_traces.py` по их выводу. Драйверы переопределяют хуки
   наблюдателя (`tool/doc_snippets.py:1842`), а трассы `accumulation.md`,
   `accumulation-rules.md` и `vs-bloc.md` — самые точные свидетели порядка
   событий и отладочных строк.
2. Стенд `flutter_solo`:

```sh
python3 tool/flutter_snippets.py "$TMPDIR/doc-check"
(cd "$TMPDIR/doc-check/flutter_check" && flutter pub get && flutter analyze \
  && flutter test --concurrency=1 | tee "$TMPDIR/flutter.out")
python3 tool/check_traces.py packages/flutter_solo/doc/mixins.md \
  "$TMPDIR/flutter.out"
```

Полный прогон обязателен в задачах 2, 3, 4, 6 и 9.

## Как ветка входит в `main`

Делается при подготовке выпусков, по слову владельца; здесь — порядок.

1. Часть A: `git rebase main` в ветке, гейт целиком в копии на голове части A
   (пять заданий CI, `floor` на `~/fvm/versions/3.38.1`), затем в `main`
   `git merge --ff-only <последний коммит задачи 9>`. Выпуски `solo` 2.0.0
   и `flutter_solo` 2.0.0 — по слову владельца, снизу вверх. scopo не задет: он
   зависит от `async_job`, а не от `solo`. Правка README `async_job` из задачи
   9 называет `SoloLanes` и поэтому выходит в выпуске ядра не раньше `solo`
   2.0.0: если владелец выпустит ждущий 1.0.3 до вливания части A, правка
   уходит в следующий патч ядра.
2. После выпуска `solo` 2.0.0 — `git rebase main` остатка; оверрайды пакетов
   линтов на `solo` снимаются, на `async_job_lints` у `solo_lints` остаётся
   до выпуска `async_job_lints`. Часть B — `--ff-only`, выпуски
   `async_job_lints` 0.2.x, затем `solo_lints` 0.2.x, тем же заходом, что
   `solo` 2.0.0: пропуск `await_own_queue` (дизайн, «Линты») кончается с их
   публикацией. Оверрайд `solo_lints` на `async_job_lints` снимается после
   выпуска `async_job_lints`.
3. Часть C — так же, минор `solo_lints` 0.3.0; конфигурации примеров и блоки
   README, которые их цитируют, поднимают `solo_lints` до `^0.3.0` коммитом
   подготовки выпуска, с переводами.

## Review Focus

Случаи, которых дизайн не называет, но которые встретит пользователь. Тест
на каждый стоит в задаче, которая владеет кодом.

1. **`SoloLanes` без единой линии.** Ожидание: `close()`
   и `close(mode: SoloCloseMode.drain)` кончаются на микрозадаче,
   `pending == null`, `cancelAll()` кончается сразу, `isFinished` после
   закрытия — как у простаивающего `Solo`. Задачи 4 и 6.
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
- Produces: сторожа, которые задачи 2–11 не правят.

Счёт микрозадач — лестницей: `void ladder(List<String> log, int n)` ставит
`scheduleMicrotask`, пишет `tick <i>` и ставит следующую до `n`. Лестница
запускается синхронно сразу после вызова, который тест меряет, в той же
синхронной части. Ожидаемый журнал каждого такого теста — то, что печатает
движок на `main`: исполнитель снимает его первым прогоном и вписывает в тест
буквально, с комментарием, что это снимок 1.x. Отладочные строки — через
`Solo.debug = log.add`, сброс в `tearDown`. Хуки — собственные хуки
контроллера, а не `SoloObserver`: типы наблюдателя меняет задача 2, а сторожа
не правятся.

- [ ] **Step 1: тесты.**
  - `an idle close finishes on a microtask of its own`: `close()`, следом
    лестница из 3; журнал `onClose` и тиков. Мутация: в `_stopWork` при пустом
    `_current` звать `_finishClose` прямо — красный (`onClose` встаёт раньше
    `tick 0`).
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
    `Cancelled` с `ClosedCancelReason`. Мутация: присвоить `_closing` после
    `_stopWork` — красный.
  - `a job put from a finish handler of a job cancelAll dropped survives and
    starts`: то же для `cancelAll`; новая задача стартует. Мутация: очищать
    очередь второй раз после отмены текущей — красный.
  - `enqueue goes through the virtual enqueueJob and job`: подкласс
    переопределяет `job` и `enqueueJob`, пишет журнал и зовёт `super`;
    `enqueue(...)` → журнал `job`, `enqueueJob`. Мутация: `enqueue` ставит
    задачу в обход виртуального `enqueueJob` — красный.
  - `an accumulator puts its groups through the virtual enqueueJob`: тот же
    подкласс, `collect(...)`, две записи → журнал `enqueueJob` на группу.
    Мутация: накопитель ставит группу закрытым путём мимо `enqueueJob` —
    красный.
  - `ctx.child makes the child through the virtual job`: тело зовёт
    `ctx.child(...)` → журнал `job`. Мутация: `ctx.child` создаёт `_SoloJob`
    прямо, мимо `job` — красный.
  - `the debug lines of a busy pass are word for word`: очередь из трёх задач
    с ключами, политиками `droppable`, `keepLatest`, `restart`, одна отклонена
    `canStart`, одна бросает в правиле; журнал `Solo.debug` целиком, снимок
    с `main`. Мутация: убрать строку `drop` — красный.

- [ ] **Step 2: красное.** Каждая мутация из шага 1 вносится по одной в копию
  `lib/src/solo.dart`, `lib/src/job.dart`, `lib/src/accumulator.dart` или
  `lib/src/job_context.dart`, `dart test test/engine_pins_test.dart` — красный
  на своём тесте; файл возвращается копией. Тест, который мутация не роняет,
  переписывается, пока не уронит.

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
  абстрактные члены, которые `Solo` реализует (имена на усмотрение
  исполнителя).
  `abstract class Solo<S extends Object> extends SoloController<S>`
  с конструктором `Solo(S initialState) : super._(initialState)`; члены очереди
  объявлены в `Solo`; `close` и `cancelAll` переопределены пересылкой в `super`
  с теми же сигнатурами и dartdoc через `{@macro}` базы. Статики `observer`,
  `unansweredHandler`, `debug` остаются на `Solo`; база читает их оттуда.
- Modify: `packages/solo/lib/src/observer.dart` — `Solo<Object>` →
  `SoloController<Object>` во всех хуках, в `SoloUnansweredHandler`
  и в реализации для нескольких наблюдателей (`:64-176`); dartdoc `onCreate`
  (`:57-63`) — «from the constructor of [SoloController]».
- Modify: `packages/solo/lib/src/solo_stream.dart` —
  `mixin SoloStream<S extends Object> on SoloController<S>`.
- Modify: `packages/solo/lib/src/job.dart`, `job_context.dart`,
  `accumulator.dart`, `queue.dart` — только там, где тип поля `_solo` или вызов
  требуют базы; поведение не меняется.
- Modify, `flutter_solo`: поля `solo` — `solo_builder.dart:32`,
  `solo_selector.dart:39`, `solo_listener.dart:90`; параметр
  `SoloSelection.from` — `solo_selection.dart:101`; внутренние
  `solo_listener.dart:201` (`_letGo`) и `solo_selection.dart:317` (`_solo`);
  `DiagnosticsProperty<Solo<S>>` — `solo_builder.dart:55`,
  `solo_listener.dart:141`, `solo_selector.dart:89`; миксин
  `solo_listenable.dart:33` — всё на `SoloController<S>`.
- Modify: `packages/flutter_solo/pubspec.yaml` — `solo: ^2.0.0`; Create:
  оверрайды `packages/flutter_solo` и `packages/flutter_solo/example`.
- Modify: тесты и примеры — там, где `Solo<Object>` стоит в переопределении
  хука наблюдателя или в обработчике без ответа (из 113 вхождений в 36 файлах
  вне `lib/`), в том числе `packages/solo/example/bin/main.dart` (6),
  `packages/solo/example/test/support/journal.dart` (8),
  `packages/flutter_solo/test/readme_scopo_test.dart:80`; `test/support/` тех
  страниц, чьи блоки меняются.
- Modify: `packages/solo/doc/diagnostics.md` (11 вхождений `Solo<Object>`),
  `testing.md` (3), `vs-bloc.md` (2), `errors.md` (1), `mistakes.md` (1) и их
  переводы в `docs/ru/solo/`; драйверы стендов с `Solo<Object>`
  (`tool/doc_snippets.py:1842`, `tool/flutter_snippets.py:1266`).
- Modify: `packages/solo/doc/reference.md` и перевод — раздел
  `## SoloController` с подразделами «What a caller sees», «What the subclass
  uses», «What the subclass overrides» для членов базы; раздел `## Solo` —
  те же подразделы только для членов, объявленных в `Solo` (очередь, пересылки
  `close` и `cancelAll`), с фразой, что остальное — от базы.
  `packages/solo/test/reference_page_test.dart` — `_classes` получает
  `'SoloController': SoloController`, группа «the tables of Solo» становится
  группой на класс и сверяет подразделы каждого из двух классов с его
  `_members` (объявленные члены): сторож остаётся точным, а не идёт по цепочке
  суперклассов.
- Modify: `docs/conventions.md` — «Модификаторы классов»: `SoloController`
  с закрытым конструктором и почему не `sealed`; «Именование»: «контроллер —
  `Solo<S>` или `SoloLanes<S>`» (имя `SoloLanes` появляется здесь заранее
  и объясняется в задаче 4).
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
  - `the base cannot be extended outside the library`: помощник `compileErrors`
    из `test/support/compile_errors.dart` на библиотеке
    с `class X extends SoloController<int>` — непустой список ошибок
    о конструкторе.

  Виджеты `flutter_solo` и `SoloStream` на контроллере, который не `Solo`,
  проверяют задачи 4 и 7: до `SoloLanes` такого контроллера нет.

- [ ] **Step 2:** `dart test test/controller_base_test.dart` — не собирается:
  `SoloController` не определён.

- [ ] **Step 3: реализация** по списку файлов. Тело каждого перенесённого члена
  переносится без правок; dartdoc остаётся на члене.

- [ ] **Step 4: типы в тестах, примерах, страницах и стендах** по списку
  файлов; страницы и их сторожа — вместе.

- [ ] **Step 5:** наборы `packages/solo`, `packages/solo/example`,
  `packages/flutter_solo`, `packages/flutter_solo/example` зелёные, сторожа
  задачи 1 — без правок; полный прогон стендов; проверки кода и документов.

- [ ] **Step 6: коммит** `refactor(solo)!: extract the SoloController base`,
  в теле — `BREAKING CHANGE:` о хуках наблюдателя, обработчике без ответа,
  миксинах и полях виджетов.

### Task 3: ядро линии под `Solo`

Переделка насоса без новых возможностей: очередь, текущая задача и окно
стартовых правил уходят в ядро; у `Solo` оно одно. Проверка — прежний набор,
сторожа задачи 1 и стенды без правок.

**Files:**
- Create: `packages/solo/lib/src/lane.dart` (`part of 'solo.dart'`) —
  `final class _SoloLaneCore<S extends Object>`:
  `SoloController<S> controller`, `String? name` (`null` у ядра `Solo`),
  `_SoloQueue<S> queue`, `_SoloJob<S, S, Object?>? current`,
  `_SoloJob<S, S, Object?>? inTransition`. Публичных классов в части пока нет:
  публичный класс части экспортируется сразу (`lib/solo.dart` —
  `export 'src/solo.dart';` без `show`), и сторож экспорта
  `reference_page_test.dart` краснеет.
- Modify: `solo.dart` — база держит `final _cores = <_SoloLaneCore<S>>[]`;
  `Solo` в конструкторе добавляет одно ядро; `_queue`, `_current`,
  `_inTransition` `Solo` становятся пересылками к нему. Насос: `_pump()` —
  проход по `_cores` в порядке создания, в каждом `bool _step(core)` с телом
  сегодняшнего `_pump` (`solo.dart:1347-1424`); шаг возвращает, продолжать ли
  проход: после отменяющего `close` — нет. Конец осушения — решение плана 8:
  ветка «нечего взять» при `_draining` и пустых ядрах кончает проход без
  строки, `_pump` после прохода один раз проверяет условие и зовёт
  `_finishClose`. Закрытие (`_stopWork`): окна и очереди всех ядер роняются
  до первой отмены текущей; затем отмена текущим всех занятых ядер; счётчик
  незакончивших: `.then` каждой уменьшает его, последняя зовёт `_finishClose`
  прямо; ноль занятых — `scheduleMicrotask`. `cancelAll`: общий снимок очередей
  и окон всех ядер, очистка по снимку, снимок текущих задач после очистки,
  рассылка; одна занятая — её `cancel(...)` как есть, несколько —
  `Future.wait(...)` с типом `Future<void>`, ни одной — `Future<void>.value()`.
- Modify: `queue.dart` — `_SoloQueue<S>` держит ядро вместо `Solo<S>` (`:53`,
  `:62`); `clear` получает форму, которая берёт готовый снимок.
- Modify: `job.dart` — `_SoloJob` получает обязательный параметр конструктора
  `_SoloLaneCore<S> destination` (ядро, которое её сделало): место создания,
  которое его забыло, не соберётся — и фабрика `job`, и `accumulator.dart:140`.
  Поле `_SoloLaneCore<S>? _execution` ставят `enqueueJob` — после своих отказов
  (чужая задача, повторная постановка), но до любого исхода постановки, —
  и `adoptedBy` (ядро исполнения родителя). `isQueued`, `cancelWith` (`:85`,
  `:129-145`) смотрят `_destination`; `adoptedBy` (`:96`) проверяет
  принадлежность по-прежнему контроллеру, а не ядру: `ctx.child`, отданный
  задаче другой линии (решение 114), остаётся законным.
- Modify: `accumulator.dart` — чтения очереди и текущей задачи (`:49-265`,
  список в дизайне, «Очередь и политики») идут через ядро накопителя;
  пробуждение throttle смотрит `current` своего ядра и планирует насос
  контроллера. Постановка групп у ядра `Solo` по-прежнему идёт через
  виртуальный `Solo.enqueueJob` контроллера (сторож задачи 1), у линии — через
  `enqueueJob` линии (задача 4).
- Modify: `job_context.dart` — `ctx.child` (`:191`) делает ребёнка
  с назначением, равным ядру исполнения задачи контекста; у `Solo` по-прежнему
  через виртуальный `Solo.job`.
- Test: новых нет — это переделка под зелёным набором: прежний набор, сторожа
  задачи 1 и трассы стендов и есть её тест.

**Interfaces:**
- Consumes: `SoloController<S>` (задача 2).
- Produces: `_SoloLaneCore<S>`, `_SoloJob._destination`, `_SoloJob._execution`,
  `bool _step(_SoloLaneCore<S> core)`; ядро, через которое накопитель
  и контекст читают очередь.

- [ ] **Step 1: зелёное до начала.** Набор `packages/solo`, сторожа задачи 1
  и полный прогон стендов зелёные на голове задачи 2.

- [ ] **Step 2: реализация** по списку файлов; сторожа задачи 1 и прежний
  набор — после каждого файла.

- [ ] **Step 3:** весь набор `packages/solo` и `packages/flutter_solo` зелёный
  без правок тестов; сторожа задачи 1 без правок; полный прогон стендов без
  правок трасс; проверки кода.

- [ ] **Step 4: коммит** `refactor(solo): run the queue as a lane core`.

### Task 4: `SoloLanes`, линия и печать набора

**Files:**
- Modify: `lane.dart` — `final class SoloLaneId` (`final String name`, закрытый
  конструктор, `toString` → `name`), его создаёт ядро линии `SoloLanes`;
  `abstract interface class SoloLane<S extends Object>` с членами из дизайна
  («Иерархия») и `id`; сигнатуры `enqueue`, `enqueueJob`, `job`, `collect`,
  `accumulate`, `queue`, `current`, `lastJobWhere` — те же, что у `Solo` 2.0
  (параметры, типы, умолчания); `SoloPending? get pending`; `String get name`;
  `SoloLaneId get id`.
  `final class _SoloLane<S extends Object> implements SoloLane<S>` поверх ядра.
  Накопитель линии ставит группы через `enqueueJob` линии.
- Modify: `solo.dart` —
  `abstract class SoloLanes<S extends Object> extends SoloController<S>`,
  конструктор `SoloLanes(S initialState) : super._(initialState)` планирует
  микрозадачу печати; `lane(name)` и `lanes` (`@protected`, `lanes` —
  `List.unmodifiable`); `bool _sealed`, который ставят микрозадача, первый
  `enqueueJob` любой линии при любом исходе (до первой ветки `enqueueJob`)
  и `close`. `lane` бросает `StateError` при повторе имени и после печати;
  текст ошибки называет причину и ведёт на раздел страницы о линиях (задача 8).
  Отказ чужой задаче в `enqueueJob` линии: задача другой линии или другого
  контроллера — `ArgumentError` с текстом «was not created by this lane»;
  у `Solo` текст `_notCreatedHere` прежний.
- Modify: `job.dart` — `SoloJob` получает `SoloLaneId? get lane`
  (`_execution ?.id`), dartdoc — `null` у задач `Solo` и у задачи без линии
  исполнения.
- Modify: `observer.dart` — dartdoc `onCreate`: у `SoloLanes` наблюдатель видит
  контроллер ещё без линий (дизайн, «Наблюдение»).
- Modify: `packages/solo/doc/reference.md` и перевод — разделы `## SoloLanes`,
  `## SoloLane`; `reference_page_test.dart` — оба в `_classes`, `SoloLaneId` —
  в ожидаемых экспортах сторожа «names every type solo exports beside the
  core». Таблица параметров фабрик читается по-прежнему из `Solo`.
- Modify: `docs/settled.md` — решения 46 (у `SoloLanes` защищён `lane`, члены
  линии публичны, защиту даёт закрытое поле), 50 (политика правит очередью
  своей линии), 84 (посылка для объявленных линий) — по разделу дизайна
  «Решения `docs/settled.md`».
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
    в порядке строк конструктора, список неизменяемый);
    `a second lane of one name throws`;
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
    `ArgumentError`, задача не ставится и её линия исполнения не меняется;
    задача другого контроллера — так же; ребёнок, уже усыновлённый, отданный
    `enqueueJob`, — прежний отказ, линия исполнения прежняя;
  - группа `SoloJob.lane`: у корня — линия постановки, у задачи, которую
    постановка сразу кончила, — тоже (`onFinish` видит линию); у задачи
    `Solo` — `null`; у ребёнка — линия исполнения родителя; `ctx.child`,
    отданный задаче другой линии, исполняется в её линии;
  - `a SoloLanes with no lanes closes like an idle Solo` (Review Focus 1);
  - `a synchronous throw in one lane does not stop the other's start` (Review
    Focus 2);
  - `an observer that throws in onStart does not stop the other lane` (Review
    Focus 3);
  - `SoloStream mixes into a SoloLanes`: класс
    `extends SoloLanes<int> with SoloStream<int>` слышит записи обеих линий
    в стриме;
  - группа `debug lines`: каждая строка из решения плана 3 — с префиксом или
    без, как там сказано; пустая простаивающая линия молчит; строки `Solo`
    в той же программе — без префикса.

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
  полный прогон стендов; проверки кода и документов.

- [ ] **Step 6: коммит**
  `feat(solo): add SoloLanes with lanes declared in the constructor`.

### Task 5: правила, накопитель и ожидание между линиями

**Files:**
- Modify: `accumulator.dart`, `job.dart`, `solo.dart` — только если тесты ниже
  найдут, чего не сделали задачи 3 и 4.
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
  строк; `SoloPendingLanes` — в ожидаемых экспортах сторожа.
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
  - `a plain close over a drain of two busy lanes cancels both and closes
    once`;
  - `a lane job that fails during close is still answered for`: задача линии
    бросает после отмены закрытием; `onUnanswered` приходит, как у `Solo`;
  - `a cancelling close from a rule ends the pass after its lane`: правило
    задачи линии `a` зовёт `close()`; задача линии `b` в этом проходе
    не стартует и кончается `Cancelled(closed)`; строки шага `a` — те же, что
    у `Solo`, с префиксом линии;
  - `close(drain) from a rule lets the pass go on`;
  - `cancelAll from a rule lets the pass go on,
    and a cancellable: false job survives in its queue`;
  - `a drain ends when every lane is empty`;
    `a drain of an idle SoloLanes with one lane ends on a microtask`;
    `a drain of a SoloLanes with no lanes ends on a microtask` (Review Focus
    1); `a drain of two empty lanes closes once` — `onClose` по разу, без
    `assert` в `_finishClose`;
  - `a job put into another lane from a finish handler during cancelAll
    survives`, в обоих порядках линий (снимки на момент вызова);
  - `cancelAll with one busy lane returns that job's cancel`: по порядку
    событий — future `cancelAll` кончается в той же микрозадаче, что
    `job.cancel()` той задачи;
  - `cancelAll with two busy lanes completes after both`;
  - `a job put into another lane during a drain is cancelled closed`.

- [ ] **Step 2: тесты снимка.**
  - `pending is null with every lane idle`;
  - `one busy lane is still SoloPendingLanes`;
  - `pending lists busy lanes in the order of creation`;
  - `SoloPendingLanes prints as SoloPending and never throws` — с ключом, чей
    `toString` бросает;
  - `a SoloStream over SoloLanes says SoloPendingStream after the lanes`;
  - `a Solo never says SoloPendingLanes`: `Solo` занятый, осушаемый с очередью
    и простаивающий — `pending` `SoloPendingJob`, `SoloPendingQueue` и `null`
    соответственно.

- [ ] **Step 3: реализация.**

- [ ] **Step 4:** набор зелёный; сторожа задачи 1 без правок; полный прогон
  стендов; проверки кода и документов.

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
- Modify: `tool/check_translations.py` — пара `lanes.md` в `PAIRS`;
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
  «Versions»), `doc/vs-bloc.md` (таблица соответствий, три фразы дизайна
  и `:93` — «use children or separate controllers for independent concurrent
  work» получает линии: это ответ на первую слабость в списке Sol),
  `doc/jobs.md` (ссылка рецепта лайков на `lanes.md`), `doc/mistakes.md`,
  `doc/errors.md`, `doc/state.md` и `doc/diagnostics.md` (`AppController`
  и `Logged` миксином `on SoloController<S>`, `SoloPendingLanes`, наблюдатель
  при нескольких корнях, `onCreate` без линий — на странице наблюдателя),
  `doc/streams.md`, `lib/solo.dart:1`, `pubspec.yaml:3` (описание).
- Modify, `flutter_solo`: `README.md:3` и фраза «One root job of a controller
  at a time», `doc/mixins.md:207` (`AppController` миксином), `pubspec.yaml:3`.
- Modify, `async_job`: `packages/async_job/README.md` — «runs one root job at a
  time…» о `Solo` и линиях; запись в его «Unreleased» (порядок выпуска — раздел
  «Как ветка входит в `main`», пункт 1).
- Modify: `docs/architecture.md` (инварианты 1, 6, 7, «Понятия», карта
  модулей), `docs/conventions.md` (модификаторы `SoloLanes`, `SoloLane`,
  `SoloLaneId`, `SoloPendingLanes`).
- Modify: `site/site.json:5`, `site/content/index.md` (строки 9 и 30),
  `site/astro.config.mjs:162`.
- Modify: `packages/solo/CHANGELOG.md` — раздел «Unreleased»: «Breaking
  changes» по списку «Что ломается в 2.0» с миграцией (обновить плагины
  линтов), «Added» — `SoloController`, `SoloLanes`, `SoloLane`, `SoloLaneId`,
  `SoloJob.lane`, `SoloPendingLanes`. `packages/flutter_solo/CHANGELOG.md` —
  «Breaking changes» о полях виджетов и `SoloListenable`, ссылка на запись
  `solo` 2.0.0 вместо повтора её «Added».
- Modify: переводы всего перечисленного (`README.ru.md` обоих пакетов,
  `docs/ru/<пакет>/…`, `docs/ru/<пакет>/CHANGELOG.md`).
- Modify: стенды и `support/` страниц, чьи блоки меняются; сторож имён
  `flutter_solo` в `tool/doc_snippets.py` при правке `vs-bloc.md`.
- Запись `2026-11-07-bloc-vs-solo-debate-report.md` — история и хранится как
  написана; в её шапку — «пересмотрено позже» со ссылкой на дизайн линий. Это
  `main`, отдельным `docs:`-коммитом.

- [ ] **Step 1: сторожа первыми.** Где правка меняет блок кода страницы —
  сначала `support/` и тест, красный, потом страница.
- [ ] **Step 2: тексты** по списку; каждое «по одной» уточняется до «у `Solo`;
  у `SoloLanes` — в каждой линии», а не вычёркивается.
- [ ] **Step 3: проверка полноты.** `rtk proxy grep -rn`
  по `packages/*/README.md`, `packages/*/doc`, `packages/*/lib`,
  `docs/architecture.md`, `site/` на `one at a time`, `exclusive`, `one queue`,
  `no concurrent`, `separate controllers`, `Solo<Object>`; каждое оставшееся
  вхождение — либо о `Solo` и верно, либо правится.
- [ ] **Step 4: переводы**, `humanizer--ru` по изменённым абзацам.
- [ ] **Step 5: проверки.** Все проверки кода `solo`, `flutter_solo`,
  `async_job` (README ядра под сторожами его пакета) и примеров; все проверки
  документов; полный прогон стендов.
- [ ] **Step 6: коммиты** по пакету: `docs(solo): …`, `docs(flutter_solo): …`,
  `docs(async_job): …`, `docs: …` для `docs/` и сайта. Последний коммит части
  A.

### Task 10: линты знают базу и линию (патчи 0.2.x)

**Files:**
- Modify: `packages/async_job_lints/lib/src/context.dart`:
  - `isSoloController` (`SoloController` и подтипы), `isSoloLane`;
    `isSoloMember` узнаёт члены `SoloLane` для правил, которые узнают члены
    `Solo` по имени;
  - новая `QueueLane queueLaneOf(Expression waited)`
    с `enum QueueLane { own, other, unknown }`. Ожидаемый вызов — на `this`
    (как сегодня) или на поле `SoloLane` своего класса (сегодня `:329` такую
    цель отвергает). Линия вызова: цель-поле, или линия, в которую ставит метод
    на `this`, — найденная в его теле всегда, и при объявленном `SoloJob`
    (ранний возврат на `isSoloJob(call.staticType)`, `:343`, остаётся только
    для контроллера `Solo`, иначе он регрессирует). Линия ждущего тела: цель
    вызова, которому отдано тело (поле `SoloLane`). Обе известны и равны —
    `own`, известны и разные — `other`, иначе — `unknown`. У `Solo` ответ, как
    сегодня, `own`. Тела детей (`ctx.child`) и обработчиков `collect`
    и `accumulate` — `unknown`. `close` и `cancelAll` — `own`, по владельцу
    через `isSoloController`;
  - `ownQueueCall` — прежняя сигнатура: вызов при `own` у `Solo`
    и у `close`/`cancelAll`; ожидание линии `SoloLanes` — только при
    `ownLaneReportedElsewhere` (решение плана 9). Экспорт новых имён
    из `plugin_api.dart`; `registerAsyncJobLints` получает
    `ownLaneReportedElsewhere`.
- Modify: `async_job_lints/lib/src/rules/bare_await.dart:93`,
  `discarded_outcome.dart:66` — молчат об ожидании линии только при
  `ownLaneReportedElsewhere` и ответе `own`.
- Modify: правила, которые узнают члены `Solo` по имени (`key_per_request`,
  `ignore_failure_hides_bugs`, `outcome_after_await`) — те же члены `SoloLane`.
- Modify: `packages/solo_lints/lib/src/rules/await_own_queue.dart` —
  `_queuedHere` (`:105-114`) узнаёт тело, отданное линии своего контроллера;
  отчёт — при `queueLaneOf == own`; владелец — `isSoloController`; сообщение
  называет линию. `solo_lints.dart:27` передаёт
  `ownLaneReportedElsewhere: true`.
- Modify: `packages/solo_lints/pubspec.yaml:23` — `async_job_lints: ^0.2.N`,
  где N — патч этой задачи: без нового API патч `solo_lints` на полу
  (`pub downgrade` до 0.2.0) не собирается. Dev-зависимость `solo: ^2.0.0`
  у обоих; оверрайды (Global Constraints).
- Modify: `docs/settled.md` — решение 54 (дедлок своей линии, `await_own_queue`
  называет его, где линия видна).
- Modify: `CHANGELOG.md` обоих и переводы — «Unreleased».
- Test: `bare_await_test.dart`, `discarded_outcome_test.dart`,
  `key_per_request_test.dart`, `ignore_failure_hides_bugs_test.dart`,
  `outcome_after_await_test.dart`, `await_own_queue_test.dart` — случаи
  `SoloLanes`; `plugin_test.dart` обоих — новый параметр регистрации.

**Interfaces:**
- Consumes: `SoloController`, `SoloLanes`, `SoloLane` из `solo` (дерево).
- Produces: `isSoloController`, `isSoloLane`, `queueLaneOf`, `QueueLane`,
  параметр `ownLaneReportedElsewhere` в `plugin_api.dart`.

- [ ] **Step 1: тесты.**
  - `await_own_queue`: `await _likes.enqueue(...).done` в теле задачи
    `_likes` — отчёт; в теле задачи `_reload` — нет; метод, объявленный
    `SoloJob<void> like()`, который ставит в `_likes`, ожидаемый из тела
    `_likes` — отчёт; задача из параметра — тишина; `close` контроллера
    `SoloLanes` и контроллера со `SoloStream` из тела — отчёт;
  - `bare_await`: `await reload().done` из тела линии `_likes`, где `reload()`
    ставит в `_reload`, — отчёт `bare_await`; то же в своей линии
    с `ownLaneReportedElsewhere: true` — тишина (`await_own_queue` говорит),
    с `false` — отчёт;
  - `discarded_outcome` — те же случаи;
  - `key_per_request`, `ignore_failure_hides_bugs`, `outcome_after_await` —
    по случаю на член `SoloLane`, который правило узнаёт у `Solo`;
  - прежние случаи `Solo` — без правок.

- [ ] **Step 2:** прогон — красные новые случаи.

- [ ] **Step 3: реализация.**

- [ ] **Step 4: совместимость.** Опубликованный `solo_lints` 0.2.0 против
  нового `async_job_lints`: копия `solo_lints` 0.2.0
  (`dart pub unpack solo_lints:0.2.0` в `$TMPDIR`) с оверрайдом на дерево
  `async_job_lints` — `dart analyze` и его тесты зелёные, и на файле
  с `await _likes.enqueue(...).done` из тела `_likes` `bare_await` говорит. Это
  доказывает, что патч не ломает загрузку старого плагина и не делает дедлок
  линии безмолвным.

- [ ] **Step 5:** наборы обоих пакетов, `python3 tool/plugin_probe.py`; `floor`
  по раскладке пакетов линтов; проверки кода и документов.

- [ ] **Step 6: коммиты**
  `fix(async_job_lints): recognise SoloController and SoloLane`,
  `fix(solo_lints): tell the lanes apart in await_own_queue`.

### Task 11: правила `stale_emit` и `lane_outside_constructor` (минор)

**Files:**
- Create: `packages/solo_lints/lib/src/rules/stale_emit.dart`,
  `lane_outside_constructor.dart`; регистрация в плагине; `test/` к каждому;
  страница правил в README `solo_lints` и перевод; `CHANGELOG.md` и перевод.
- Modify: `packages/solo_lints/pubspec.yaml` — только если правилам нужно
  больше, чем дала задача 10.

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
- [ ] **Step 4: реализация**, серьёзность — решение плана 7, сообщения
  и `correction` — по образцу `await_own_queue`.
- [ ] **Step 5:** набор, `plugin_probe.py`, проверки документов.
- [ ] **Step 6: коммит**
  `feat(solo_lints): add stale_emit and lane_outside_constructor`.

### После задач

- Независимое ревью всей ветки на Opus, по своей копии дерева на ревьюера;
  находки с вердиктами — в отчёт `2026-11-NN-solo-lanes-report.md`.
- Гейт целиком в копии на голове каждой части: пять заданий CI локально,
  включая `floor` на `~/fvm/versions/3.38.1`.
- В `main`, отдельными `docs:`-коммитами: отчёт; `docs/handoff.md` — ветка
  готова и ждёт выпусков, какие коммиты закрывают части A, B и C (по имени
  ветки и заголовкам, хэши — после вливания); шапки дизайна и плана — «сделано
  в ветке `solo-lanes`, ждёт выпуска».

## Ревью плана

Независимое ревью Opus 2026-11-11 плана на коммите `469f4482`, в своей копии
дерева. Текст ревьюера — дословно, кроме мест, где он называл путь своей копии
дерева и временные каталоги зондов: они заменены описанием, потому что записи
на временное не ссылаются. Ссылки `plan:N` — строки плана на `469f4482`,
до этой правки. Вердикты — мои.

Ревью плана `docs/records/2026-11/2026-11-11-solo-lanes-plan.md` (HEAD
469f4482) против дизайна
`docs/records/2026-11/2026-11-10-solo-lanes-design.md`. Ссылки вида `plan:N` —
строки плана, `design:N` — строки дизайна.

### 1. Важная. Задача 3 не может быть зелёной: `SoloLaneId` экспортируется сразу

Задача 3 создаёт `final class SoloLaneId` в новой части `lib/src/lane.dart`
(plan:376-381) и пишет «класс пока не экспортируется» (plan:416).
Но `lib/solo.dart` содержит `export 'src/solo.dart';` без `show`/`hide`,
а часть входит в библиотеку `src/solo.dart`. Значит, публичный класс части
экспортируется в тот же момент. В задаче 3 тесты не правятся (plan:411,
427-428), а `reference_page_test.dart` («names every type solo exports beside
the core») краснеет. Я проверил это зондом: копия `async_job`/`solo`
во временном каталоге, часть `lane.dart` с публичным `SoloLaneId`, прогон
`dart test test/reference_page_test.dart` дал
`Expected: empty / Actual: ['SoloLaneId']`, `Some tests failed`. Кроме того,
`public_member_api_docs` (`analysis_options.yaml:193`) потребует dartdoc,
а `check_links`/`check_dartdoc` его увидят. «Экспорт через src/solo.dart»
в задаче 4 при этом ничего не делает. Что править: ввести `SoloLaneId` в задаче
4 вместе с разделом справочника. Другой вариант: в задаче 3 держать id закрытым
(`_SoloLaneId`) или временно добавить `hide SoloLaneId` в `lib/solo.dart`
и снять его в задаче 4.

Вердикт Claude: принято, первый вариант. Я проверил: `lib/solo.dart`
экспортирует `src/solo.dart` без `show`. Ядру `Solo` идентификатор не нужен,
поэтому в задаче 3 публичных классов в части нет, а `SoloLaneId` появляется
в задаче 4 вместе с разделом справочника и ожиданием сторожа. Итог: внесено
тем же коммитом — задача 3, «Files», `lane.dart` без публичных классов
с причиной; задача 4 создаёт `SoloLaneId`; решение плана 5 — идентификатор
создаёт ядро линии `SoloLanes`, у ядра `Solo` его нет.

### 2. Важная. Ограничение «прежний набор правится только в задаче 2 и только в типах» невыполнимо

plan:74-75 запрещает трогать старые тесты где-либо, кроме смены типов в задаче 2. Но в `reference_page_test.dart` `_members` читает `reflectClass(type).declarations`, то есть только объявленные члены. Группа «the tables of Solo» сверяет подразделы `## Solo` («What a caller sees», «What the subclass uses», «What the subclass overrides») с членами `Solo`. После задачи 2 хуки, `currentState`, слушатели и `externalSetState` объявлены в базе. Подраздел «What the subclass overrides» под `Solo` станет пустым, или тест придётся обобщать на цепочку суперклассов. Это структурная правка теста, а не правка типов, и строка «`_classes` получает `'SoloController'`» (plan:317-318) её не покрывает. Старые тесты правят и другие задачи: задача 4 (`_classes`, plan:457), задачи 6 и 9 (страничные сторожа `*_rakes_test`, `test/support/` при правке страниц). Что править: переформулировать ограничение. Тесты поведения движка не правятся вовсе. Страничные сторожа (`reference_page_test`, `*_rakes_test`, `*_page_test`, `support/`) правятся вместе со своими страницами в той задаче, которая меняет страницу. Задаче 2 явно расписать, как `reference_page_test` делит члены между `## SoloController` и `## Solo`.

Вердикт Claude: принято. Одна оговорка: тесты поведения движка в задаче 2
всё же правятся — в типах хуков наблюдателя, иначе они не соберутся. Итог:
внесено тем же коммитом — Global Constraints, пункт «Какие тесты правятся»:
тесты движка только в задаче 2 и только в типах, сторожа задачи 1 никогда,
страничные сторожа вместе со своей страницей. Задача 2 расписывает разделы
`## SoloController` и `## Solo` справочника и группу сторожа на класс, которая
сверяет подразделы с объявленными членами каждого класса.

### 3. Важная. Формулировка задачи 3 о накопителе противоречит критерию виртуальных вызовов

plan:404-407: «все обращения к очереди, текущей задаче и `enqueueJob`
контроллера … идут через ядро накопителя». А plan:72-73 и сторож задачи 1
требуют, чтобы накопитель `Solo` звал виртуальный `Solo.enqueueJob`.
Пользователь его переопределяет, и это часть «`Solo` не меняется». Исполнитель,
который буквально уведёт `enqueueJob` в ядро, сломает переопределение, и сторож
задачи 1 поймает это только после правки. Что править: явно написать, что
очередь и `current` идут через ядро, а постановка у ядра `Solo` идёт через
виртуальные `enqueueJob`/`job` контроллера; у линии — через члены линии. Рядом
есть похожая дыра: `_destination` «ставит фабрика `job`» (plan:401-402),
но `_SoloJob` создаётся ещё в `accumulator.dart:140` (`_job`). Надёжнее сделать
`_destination` обязательным параметром конструктора `_SoloJob`: тогда
пропущенное место не соберётся.

Вердикт Claude: принято целиком. Итог: внесено тем же коммитом — задача 3:
накопитель читает очередь и текущую задачу через ядро, а группы ставит через
виртуальный `Solo.enqueueJob` у ядра `Solo` и через `enqueueJob` линии
у `SoloLanes`; `ctx.child` у `Solo` идёт через виртуальный `Solo.job`;
`_destination` — обязательный параметр конструктора `_SoloJob`, с названными
местами создания. Сторожа задачи 1 получили тесты на накопитель и `ctx.child`.

### 4. Важная. Патч `solo_lints` в задаче 10 использует новый API `async_job_lints`, не поднимая нижнюю границу

Задача 10 правит `await_own_queue.dart`: владелец определяется через
`isSoloController`, линия через `queueLaneOf` (plan:797-799). Оба имени новые
(plan:810). При этом `packages/solo_lints/pubspec.yaml:23` остаётся
`async_job_lints: ^0.2.0`, а поднимает его только задача 11 (plan:850-851). Под
оверрайдами всё зелёное. Но после их снятия `floor` делает `pub downgrade`
до 0.2.0, где этих имён нет, и красный. Опубликованный `solo_lints` 0.2.x
с границей `^0.2.0` у пользователя с залоченным `async_job_lints` 0.2.0
не загрузится. Что править: в задаче 10 поднять ограничение до `^0.2.N` (N —
патч этой же задачи), а в задаче 11 оставить только то, что нужно новым
правилам.

Вердикт Claude: принято. Итог: внесено тем же коммитом — задача 10 поднимает
`async_job_lints: ^0.2.N` в `packages/solo_lints/pubspec.yaml`, где N — патч
этой задачи, с причиной; задача 11 правит `pubspec.yaml`, только если новым
правилам нужно больше; Global Constraints, «Выпуск не в плане», называет это
ограничение среди тех, что план правит.

### 5. Важная. Проверки задач 2–6 не включают стенды трасс

Раздел «Стенды» (plan:134-160) описан хорошо, но задачи его не вызывают. Задача
2, Step 4 (plan:358-359), гоняет «задание `snippets` для `vs-bloc.md`», хотя
меняет типы хуков, которые используют драйверы других стендов.
В `tool/doc_snippets.py:1842` драйвер переопределяет `onStart(Solo<Object> …)`,
в `tool/flutter_snippets.py:1266` тоже есть такое место. Ещё задача 2 меняет
миксины `on SoloController`, которые собирает flutter-стенд. Задача 3
(plan:427-428) — главный риск для «`Solo` не меняется»: переписан насос,
`close`, `cancelAll`, накопитель. Её проверка — только наборы пакетов, без
`check_traces.py`. Трассы `accumulation.md`/`accumulation-rules.md`
и `vs-bloc.md` — самые точные свидетели порядка событий и отладочных строк.
Задачи 4–6 (plan:643-644) тоже обходятся без стендов. Что править: в задачах 2,
3 и 6 (и в 4, раз она трогает печать) гонять задание `snippets` целиком — шесть
пакетов, все драйверы, `check_traces.py` — и flutter-стенд из plan:152-160.

Вердикт Claude: принято. Я проверил оба места `Solo<Object>` в драйверах. Итог:
внесено тем же коммитом — раздел «Стенды» определяет «полный прогон стендов»:
задание `snippets` целиком с `check_traces.py` и стенд `flutter_solo`; он
обязателен в задачах 2, 3, 4, 6 и 9. Драйверы с `Solo<Object>` стоят в списке
файлов задачи 2.

### 6. Важная. Конец осушения в шаге линии расходится с дизайном и не заканчивается на `SoloLanes` без линий

В дизайне (design:525-527) сказано: «на простаивающем контроллере его будит
контроллер, а не шаг линии». План (plan:387-389) ставит конец осушения в ветку
шага «нечего взять». У `SoloLanes` без единой линии (законный случай, Review
Focus 1, plan:184-186) шагов нет. `close(mode: SoloCloseMode.drain)` тогда
не кончится никогда. Review Focus 1 называет только простой `close()`. Тест
`a drain of an idle SoloLanes ends on a microtask` (plan:620) не говорит,
сколько у контроллера линий, и с одной пустой линией проходит. Вторая сторона
того же: при двух пустых линиях обе ветки «нечего взять» в одном проходе увидят
«все ядра пусты» и обе позовут `_finishClose`. Дизайн сам напоминает
(design:515-517), что `_finishClose` стережёт только completer
(`assert(!_finished)`). План не говорит, что шаг после конца осушения прерывает
проход. Что править: проверку конца осушения вынести на уровень контроллера —
после прохода по `_cores` или в `close` при нуле занятых ядер, — либо явно
остановить проход после `_finishClose`. Добавить тест «drain of a SoloLanes
with no lanes» и тест двух пустых линий при осушении.

Вердикт Claude: принято, первый вариант — проверка после прохода. Итог: внесено
тем же коммитом — решение плана 8: шаг, который ничего не взял, при осушении
и пустых ядрах кончает проход без строки, а `_pump` после прохода один раз
проверяет условие и зовёт `_finishClose`; у `Solo` это та же микрозадача насоса
и те же строки, что держит сторож осушения задачи 1. Задача 3 ссылается
на решение; Review Focus 1 называет и осушение; задачи 4 и 6 получили тесты
осушения без линий и двух пустых линий.

### 7. Мелкая. Окно тишины: опубликованный `solo_lints` 0.2.0 плюс пропатченный `async_job_lints`

После патча `ownQueueCall` отдаёт ожидание своей линии (plan:789),
и `bare_await`/`discarded_outcome` на нём молчат (plan:792-794, 821), передавая
слово `await_own_queue`. Но в опубликованном `solo_lints` 0.2.0 `_queuedHere`
(`await_own_queue.dart:105-114`) тело, отданное `_likes.enqueue`, не узнаёт.
Взаимная блокировка в своей линии становится полностью безмолвной. До патча
о ней хотя бы говорил `bare_await`. Пользователь получает патч
`async_job_lints` сам (`AGENTS.md`: «патч доходит сам»), а `solo_lints` у него
может остаться на 0.2.0 по lock-файлу. Step 4 задачи 10 (plan:831-835)
доказывает только загрузку старого плагина, а не то, что он не потерял отчёт.
Что править: новый параметр регистрации, например `ownLaneReportedElsewhere`
(по умолчанию `false`), рядом с существующим `ownQueueReportedElsewhere`.
Пропатченный `bare_await` молчит на линиях только у плагина, который о линиях
знает. Либо явно записать окно как принятую цену.

Вердикт Claude: принято, параметр регистрации. Я проверил: `bare_await.dart`
и `discarded_outcome.dart` молчат через `ownQueueCall`,
а `ownQueueReportedElsewhere` уже есть в `plugin_api.dart`. Итог: внесено
тем же коммитом — решение плана 9; задача 10: `ownQueueCall` отдаёт ожидание
линии только при `ownLaneReportedElsewhere`, `solo_lints.dart` передаёт `true`,
тесты `bare_await` на оба значения; Step 4 проверяет, что `bare_await`
со старым `solo_lints` 0.2.0 об ожидании линии говорит.

### 8. Мелкая. `queueLaneOf` описан недостаточно

(a) Сегодня `ownQueueCall` отвергает цель, отличную от `this`
(`context.dart:329`), а тест `await _likes.enqueue(...).done` (plan:814)
требует цели-поля линии. Об этом нужна отдельная строка. (b) У простого `Solo`
(и у метода, объявленного в другом файле) ответ должен остаться «своя», как
сегодня. Если убрать ранний возврат на `:343` для всех контроллеров
(plan:786-787), получится регрессия `Solo`. Тест «прежние случаи `Solo` без
правок» (plan:825) это поймает, но исполнителю лучше знать заранее. (c) Для тел
детей (`ctx.child`) и обработчиков `collect` не сказано, какой ответ —
вероятно, `unknown`.

Вердикт Claude: принято, все три пункта. Итог: внесено тем же коммитом — задача
10, `queueLaneOf`: цель — `this` или поле `SoloLane` своего класса, с отсылкой
к `:329`; ранний возврат на `isSoloJob` остаётся для контроллера `Solo`;
у `Solo` ответ, как сегодня, `own`; тела детей и обработчиков `collect`
и `accumulate` — `unknown`.

### 9. Мелкая. Решения `docs/settled.md` правятся не в той задаче

Задача 9 правит решения 46, 50, 54 и 84 одним документным коммитом в конце
(plan:746-747). Дизайн (design:940): «Правятся тем же коммитом, что и код,
который их меняет». То же требует `AGENTS.md`. Решения 46 и 50 относятся
к задачам 4/6, решение 54 — к задаче 10. Что править: разнести их по этим
задачам.

Вердикт Claude: принято. Решение 50 (политика правит очередью своей линии)
меняет код задачи 4, где линии получают свои очереди, а не задачи 6; туда же
ушло и 84. Итог: внесено тем же коммитом — Global Constraints, пункт «Решения
`docs/settled.md`»: 46, 50 и 84 — в задаче 4, 54 — в задаче 10; обе задачи
называют `docs/settled.md` в своих файлах, задача 9 его больше не правит.

### 10. Мелкая. Решение плана 3 (префикс линии в отладке) не совпадает с реальными строками

plan:113-119 перечисляет `start`, `drop`, `remove`, `starts after`,
`duplicate of`, `ended while the rules were asked`, `queue has no ready jobs`.
Реальные места: `enqueue X`, `enqueue X first`, `enqueue X: closed`
(`solo.dart:588`, `:643`), `enqueue X: duplicate of Y` (`:606`, `:624`; «starts
after» — хвост этих строк, а не отдельная строка), `restart: …` (`:674`),
`rule of X threw` (`:1382`), `start X: ended while…` (`:1396`), `drop X`
(`:1409`), `queue has no ready jobs` (`:1362`), `remove X: …` (`job.dart:137`,
`:144`), `move X to the tail` (`accumulator.dart:202`), `X emit:`
(`job_context.dart:285`), `X expected …` (`solo.dart:1500`). Отдельной строки
`start` нет, а `enqueue`, `restart`, `rule of … threw`, `move … to the tail`
в списке не названы. Неясно, печатает ли линия `queue has no ready jobs` после
шага, который снял последнюю задачу: `Solo` сегодня печатает `drop X`, а затем
эту строку. Ещё дизайн после отменяющего `close` говорит о «тех же строках»,
а план их префиксует. Что править: перечислить все строки по месту в коде
с ответом, получает ли каждая префикс.

Вердикт Claude: принято. Я сверил строки `_debug(() =>` во всех файлах
`lib/src` своей командой. Итог: внесено тем же коммитом — решение плана 3
перечисляет строки по месту в коде: префикс линии у строк постановки и шага
линии, без префикса — строки задачи и состояния и строки контроллера
о закрытии; `queue has no ready jobs` — как у `Solo`, кроме шага простаивающей
линии, которая ничего не взяла; шаг, который снял задачи и кончился пустой
очередью, её печатает. «Те же строки» дизайна после отменяющего `close`
в задаче 6 прочитаны как «те же, с префиксом линии»: у `Solo` строки
не меняются вовсе.

### 11. Мелкая. Неверный факт о `test/support/compile_errors.dart`

plan:341-344 велит добавить случай «по образцу соседних случаев этого файла».
На деле это помощник `compileErrors(code)` с копией в `async_job` («A change to
one goes to the other»), а не файл случаев. Случай
`class X extends SoloController<int>` должен жить в `controller_base_test.dart`
и звать помощника.

Вердикт Claude: принято, проверено по файлу. Итог: внесено тем же коммитом —
задача 2, тест `the base cannot be extended outside the library`
в `controller_base_test.dart` зовёт помощника `compileErrors`.

### 12. Мелкая. Тесты, которые ничего не доказывают

`SoloStream mixes into a SoloController` (plan:338-340) верен уже потому, что
класс — `Solo`. Доказательство нужно на `SoloLanes` (задача 4 или 7).
`Solo.pending keeps its variants` (plan:637-639) — исчерпывающий `switch`
в тесте; он проверяет sealed-иерархию, а не то, что `Solo` отдаёт прежние
варианты. Сторожа задачи 1 для накопителя, `ctx.child` и отладки не называют
мутации, которую ловят, в отличие от сторожа осушения (plan:233-236). У сторожа
простаивающего `close` мутация не поймается, если `close()` вызван до лестницы
микрозадач: порядок вызова или синхронная запись после `close()` должны быть
оговорены.

Вердикт Claude: принято. Итог: внесено тем же коммитом — тест `SoloStream`
переехал в задачу 4 на `SoloLanes`; тест `pending` задачи 6 заменён
на `a Solo never says SoloPendingLanes` с тремя состояниями `Solo`; у сторожей
задачи 1 на накопитель, `ctx.child` и отладку названы мутации; общий абзац
задачи 1 говорит, что лестница запускается синхронно сразу после вызова,
который тест меряет, и у простаивающего `close` она идёт после `close()`.

### 13. Мелкая. Нет задач на то, что дизайн требует

- Простой `close()` поверх осушения двух занятых линий — путь счётчика
  (design:523-524).
- «Ожидание закрытием … `onUnanswered` приходит, как сегодня» (design:521-522)
  для задачи линии, упавшей во время `close`.
- Фраза в dartdoc `onCreate` о том, что наблюдатель видит `SoloLanes` ещё без
  линий (design:604). Задача 2 правит `onCreate` только на «constructor of
  [SoloController]».
- «Ответ на первую слабость в списке Sol — ссылка на линии» (design:813; запись
  `2026-11-07-bloc-vs-solo-debate-report.md`).

Вердикт Claude: принято, все четыре. По четвёртому я искал в публичных
документах: место, где ответ на эту слабость нужен, — `vs-bloc.md:93`, фраза
«use children or separate controllers for independent concurrent work». Итог:
внесено тем же коммитом — задача 6 получила тесты простого `close()` поверх
осушения двух занятых линий и `onUnanswered` для задачи линии, упавшей при
закрытии; задача 4 правит dartdoc `onCreate`; задача 9 правит `vs-bloc.md:93`
с указанием, что это ответ на первую слабость в списке Sol.

### 14. Мелкая. Порядок `_execution` и проверок владения

«`_execution` ставит `enqueueJob` первым делом» (plan:402) должно идти после
отказов (`ArgumentError` чужой задаче, `StateError`). Иначе повторная
постановка усыновлённого ребёнка перепишет его линию до отказа. Проверку
принадлежности линии (plan:448-450) нельзя опускать в `startChild`/`adoptedBy`.
Там проверка должна остаться на уровне контроллера, иначе `ctx.child` между
линиями (решение 114) сломается. Текст «was not created by this lane» — только
для линий: у `Solo` прежний текст `_notCreatedHere` (сторожа задачи 1 и тесты
сообщений).

Вердикт Claude: принято. Итог: внесено тем же коммитом — задача 3: `_execution`
ставит `enqueueJob` после своих отказов, но до любого исхода постановки;
`adoptedBy` проверяет принадлежность контроллеру, а не ядру, со ссылкой
на решение 114; задача 4: текст «was not created by this lane» — только
у линий, у `Solo` прежний `_notCreatedHere`; тест отказа проверяет, что линия
исполнения не меняется.

### 15. Мелкая. Пропуски в списке файлов задачи 2

Не названы:
- `packages/solo/example` (`bin/main.dart` — 6 вхождений,
  `test/support/journal.dart` — 8);
- `packages/flutter_solo/test/readme_scopo_test.dart:80`;
- внутренние `Solo<S>` в `solo_listener.dart:201` и `solo_selection.dart:317`;
- `DiagnosticsProperty<Solo<S>>` в `solo_builder.dart:55`,
  `solo_listener.dart:141`, `solo_selector.dart:89`.

Ссылка «объясняется в задаче 5» (plan:322) должна вести на задачу 4:
`SoloLanes` появляется там.

Вердикт Claude: принято, все места проверены своей командой. Итог: внесено
тем же коммитом — список файлов задачи 2 называет каждое место; ссылка ведёт
на задачу 4.

### 16. Мелкая. Ветка, записи и порядок выпусков

Записи идут в `main`, код — в `solo-lanes` (plan:42-49). `git rebase main`
(plan:166, 171) переписывает хэши, на которые сошлются handoff и отчёт. Об этом
стоит сказать или ссылаться на коммиты ветки только после вливания. План
не говорит, что ветка живёт в своей копии (worktree): параллельные сессии делят
дерево. Правка README `async_job` из части A выходит через `async_job` 1.0.3
из `main` раньше `solo` 2.0. Порядок этих выпусков не записан. В части B
(plan:171-173) не сказано, снимаются ли оверрайды пакетов линтов
на `async_job`.

Вердикт Claude: принято. Одно уточнение: правка README `async_job` идёт
в ветке, а не в `main`, поэтому через ждущий 1.0.3 она не выйдет; но после
вливания части A она окажется в `main` и попала бы в следующий патч ядра
до `solo` 2.0.0, если бы порядок не был записан. Итог: внесено тем же
коммитом — Global Constraints: ветка в своей копии дерева, хэши ветки записи
называют только после вливания; «Оверрайды»: на `async_job` их нет ни у кого;
«Как ветка входит в `main`», пункт 1: правка README ядра выходит не раньше
`solo` 2.0.0.

### 17. Мелкая. Задача 11 и `CHANGELOG`

Задача 11 не говорит, `stale_emit` — это warning или lint. От этого зависят
конфигурации примеров и блоки README, которые сторожа сверяют
с `analysis_options` примера. Подъём до `^0.3.0` (plan:176-177) затрагивает
блоки README `solo` и `flutter_solo` и их переводы (conventions), а план
называет только конфигурации. В задаче 9 (plan:752) заголовок раздела —
«Breaking changes», как в существующих `CHANGELOG`, а не «Breaking».
`CHANGELOG` `flutter_solo` лучше отсылать к списку `solo`, а не повторять
«Added». Геттер `lanes` (plan:444) должен отдавать неизменяемый список: этого
в плане нет.

Вердикт Claude: принято. Итог: внесено тем же коммитом — решение плана 7:
`stale_emit` с умолчательной серьёзностью, как `key_per_request`, потому что
это эвристика, `lane_outside_constructor` — `WARNING`, как `await_own_queue`;
«Как ветка входит в `main`», пункт 3: подъём до `^0.3.0` правит и блоки README
с переводами; задача 9: «Breaking changes», `CHANGELOG` `flutter_solo`
ссылается на запись `solo`; Global Constraints и задача 4: `lanes` —
неизменяемый список.

### Что подтвердилось

- Ссылки на строки кода верны: `solo.dart` (`_schedulePump` 1336, `_pump`
  1347-1424, 964, 975, `cancelAll` 1017-1029, 587-597, 626-634, `pending` 774,
  106-111, 170-172, 1170, 1257-1290), `accumulator.dart` (126-265), `job.dart`
  (10-248), `queue.dart` (53/54, 62, 113), `job_context.dart:191`,
  `context.dart` (79-83, 315-349), `bare_await.dart:93`,
  `discarded_outcome.dart:66`, `await_own_queue.dart:105-114`, места
  `flutter_solo`, `observer.dart:57-176`, а также `mixins.md:207`,
  `state.md:318`, `site.json`, `astro.config.mjs:162`.
- Счёт «113 вхождений `Solo<Object>` в 36 файлах» верен; в md 11/3/2/1/1.
- Тесты, на которые опирается задача 1, существуют
  (`start_rules_test.dart:402`, `drain_test.dart:275`). Описанные мутации
  сторожей закрытия и осушения их действительно краснят.
- `check_translations.py` — явный список `PAIRS`, пара для страницы о линиях
  нужна. `check_links.py` сканирует `packages/*/lib/**/*.dart`, так что слова
  плана о ссылках из dartdoc верны.
- Стенды `doc_snippets`, `flutter_snippets`, `accumulation`, `riverpod`, `bloc`
  идут на дерево через path и оверрайды (`flutter_snippets` оверрайдит
  и `solo`, и `async_job`).
- Решение 6 (сохранить сигнатуру `ownQueueCall`) обосновано: `solo_lints` 0.2.0
  зовёт её через `plugin_api.dart` и регистрирует
  `ownQueueReportedElsewhere: true`.
- Решение 2 (микрозадача печати в конструкторе `SoloLanes`) — названное
  отступление, и оно разумно.
- Пункты Review Focus привязаны к задачам.
- `stage`/`floor` работают с ограничением на неопубликованный мажор под
  оверрайдами. Dry-run копии с `async_job: ^2.0.0` и путевым оверрайдом дал
  только hint. `example/pubspec_overrides.yaml` при этом попадает в архив,
  корневой оверрайд — нет.
- У веточного режима до выпуска есть прецедент (`solo-listener`).

### Вердикт ревьюера

План подробный, ссылки на код точные, и в большинстве мест он ведёт исполнителя
туда, куда обещает дизайн. Исполнять его как есть нельзя. Находки 1 и 2
гарантируют красный коммит или нарушение собственного ограничения плана уже
в задачах 2–3. Находки 3 и 6 ведут к коду, который расходится с дизайном:
виртуальные вызовы `Solo` и осушение `SoloLanes` без линий. Находка 4 даёт
патч, который ломается на полу. Находка 5 оставляет главную переделку, задачу
3, без самых точных свидетелей — трасс. После правок 1–6 план готов
к исполнению. Остальное — уточнения, которые снимут вопросы исполнителя
по ходу.

### Что ревьюер запускал

- `git merge --ff-only 469f4482` в своей копии дерева. Ничего не коммитил,
  отслеживаемые файлы не правил.
- Чтение плана, дизайна, handoff, исходников `solo`, `flutter_solo`,
  `async_job_lints`, `solo_lints`, `tool/*.py`; поиск через `rtk proxy grep`.
- В `packages/solo`: `dart pub get`,
  `dart test test/reference_page_test.dart` — +22, зелёный.
- Зонд во временном каталоге с копиями `async_job` и `solo`:
  `pubspec_overrides.yaml` у `solo` и `solo/example`,
  `dart pub publish --dry-run` — 0 warnings, 1 hint; то же
  с `async_job: ^2.0.0` при путевом оверрайде — только hint.
- Зонд во временном каталоге: часть `lane.dart` с публичным `SoloLaneId`,
  `dart test test/reference_page_test.dart` — красный,
  `Actual: ['SoloLaneId']`.
- Окружение: Dart 3.13.0 локально, `~/fvm/versions/3.38.1` на месте,
  в `~/.pub-cache` есть `solo_lints-0.2.0`.

Итог ревью: все семнадцать находок приняты и внесены тем же коммитом, что
и этот раздел. Решения плана 8 и 9 появились из находок 6 и 7.
