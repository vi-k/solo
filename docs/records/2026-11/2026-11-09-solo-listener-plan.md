> **Состояние на 2026-11-10:** план написан по одобренному дизайну, прошёл
> независимое ревью Opus и исправлен по нему; одобрен владельцем
> 2026-11-09 словами «одобряю, делай сам». Исполнен целиком в ветке
> `solo-listener`, ревью ветки на Opus пройдено. Шаг 1 «Как ветка входит
> в `main`» сделан 2026-11-10: часть `solo` в `main` к выпуску `solo` 1.1.0
> (`2026-11-10-solo-1-1-0-release-report.md`); остальное — в ветке (голова
> `2bca4c26`) до выпуска `flutter_solo`. Отчёт —
> `2026-11-10-solo-listener-report.md`.
> **Что это:** план работ по `Solo.addChangeListener` в `solo` и виджету
> `SoloListener` во `flutter_solo`: задачи, тесты, документы, порядок коммитов
> в ветке до выпусков; в конце — ревью плана с вердиктами.
> **Связанные записи:** `2026-11-09-solo-listener-async-design.md` (дизайн,
> одобрен владельцем 2026-11-09), `2026-11-09-solo-listener-design.md`
> (прежний дизайн и пробный прототип),
> `2026-11-10-solo-listener-report.md` (исполнение и ревью ветки).

# SoloListener: план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** подписка `solo` на каждое изменение с парой «было → стало» и виджет
`SoloListener`, который запускает на изменение отменяемую реакцию задачей ядра.

**Architecture:** `Solo.publish` после слушателей `addListener` зовёт
слушателей пары из своего приватного списка. `SoloListener` подписан на пару,
на каждое пропущенное `listenWhen` изменение создаёт корневой `Job` ядра
со своим наблюдателем-ответчиком и разбирает ждущие состояния по режиму
`SoloListenerMode`; уход виджета отменяет реакции.

**Tech Stack:** Dart 3.10, Flutter 3.38.1 (пол), `async_job` 1.x без правок,
`solo` 1.0.1 → 1.1.0, `flutter_solo` 1.0.0 → 1.1.0; стенды на Python.

**Spec:** `docs/records/2026-11/2026-11-09-solo-listener-async-design.md`.
Дизайн — источник правды; где план с ним расходится, прав дизайн, а расхождение
записывается решением исполнителя.

## Global Constraints

- **Ветка.** Код и публичные документы идут в ветке `solo-listener` от `main`
  и в `main` не вливаются до коммитов выпуска — ответ владельца на вопрос 1
  дизайна. Это исключение из правила «работай в `main`» `AGENTS.md` для этой
  работы. `push` ветки — только по слову владельца.
- **Записи — в `main`.** `docs/handoff.md`, шапки дизайна и плана, отчёт работы
  коммитятся в `main` отдельными `docs:`-коммитами, а не в ветке: следующая
  сессия читает их из `main`. Запись, которая описывает код ветки, говорит это
  в шапке.
- **Две части ветки.** Задачи 1–2 — часть `solo`, она вливается в `main`
  с выпуском `solo` 1.1.0. Задачи 3–7 — часть `flutter_solo`, она вливается
  с выпуском `flutter_solo` 1.1.0. Коммиты части `solo` идут первыми. Как ветка
  входит в `main` — раздел ниже.
- **Ничто в части `solo` не называет `SoloListener`.** Архив `solo` 1.1.0
  выходит раньше виджета. Поэтому строка `vs-bloc.md` о `BlocListener` и правка
  причин отмены (`ReplacedCancelReason`, `SoloCancelReason`, справочник,
  таблица `cancellation.md`) — в задаче 7, в части `flutter_solo` (решение
  плана, продолжение ответа владельца «строка с выпуском flutter_solo»). Цена:
  на pub.dev dartdoc `ReplacedCancelReason` остаётся прежним до следующего
  выпуска `solo`.
- **Выпуск не в плане.** Версии в `pubspec.yaml` пакетов, коммиты `Release`,
  теги, `dart pub publish` — только по отдельному слову владельца.
- **Пол SDK** — `sdk: ^3.10.0`, Flutter 3.38.1: синтаксис не новее Dart 3.10.
- **`Listeners` не трогать.** `package:solo/listeners.dart` — публичный API,
  смена сигнатуры `add` — мажор. Список пар — свой, неэкспортируемый.
- **Оверрайды.** С задачи 3 у `packages/flutter_solo`
  и `packages/flutter_solo/example` — `pubspec_overrides.yaml` на дерево `solo`
  (первая строка — комментарий «до выпуска `solo` 1.1.0»). На `async_job`
  оверрайда нет, у пакетов линтов и `packages/solo/example` — тоже.
- **Проверки кода перед каждым коммитом** — из папки затронутого пакета:
  `dart format --output=none --set-exit-if-changed .`,
  `dart analyze --fatal-infos`, `dart test` (`flutter test`
  во `packages/flutter_solo` и его `example`), `dart doc --dry-run`;
  у `packages/flutter_solo/example` ещё `flutter analyze`
  и `dart analyze --fatal-infos` (плагин `solo_lints`).
- **Проверки документов** — из корня: `python3 tool/check_translations.py`,
  `python3 tool/reflow.py --check`, `python3 tool/check_line_width.py`,
  `python3 tool/check_links.py`, `python3 tool/check_dartdoc.py`,
  `python3 tool/check_doc_shape.py`. Изменённые абзацы русских переводов
  прогоняются через скилл `humanizer--ru` без шага «Голос», правятся только
  `ERROR` его линтера.
- **Dartdoc — по решению 103 `docs/settled.md`.** Первый абзац — одна фраза,
  второй — договор: что член делает, что бросает, одна главная ловушка. Разбор
  случаев — на странице; последний абзац ведёт на её раздел абсолютным адресом
  `blob/main` с якорем. `check_dartdoc.py`: абзац не длиннее 10 строк, блок
  `///` — 30. Ссылка на раздел появляется тем же коммитом, что и сам раздел:
  `check_links.py` проверяет файл и якорь в дереве.
- **Язык.** Код, комментарии, dartdoc, `CHANGELOG.md`, сообщения коммитов —
  по-английски; Conventional Commits.
- **Имена API** — ровно из дизайна: `addChangeListener`,
  `removeChangeListener`, `SoloListener`, `SoloListenerMode` с `concurrent`,
  `sequential`, `droppable`, `keepLatest`, `restart`; параметры `solo`,
  `listener`, `listenWhen`, `mode = SoloListenerMode.concurrent`, `child`.

## Стенды: команды как в CI

`flutter_solo` (README, `doc/mixins.md`, `doc/testing.md`) — генератор только
пишет пакет, собирает и гоняет его отдельный шаг:

```sh
python3 tool/flutter_snippets.py "$TMPDIR/doc-check"
(cd "$TMPDIR/doc-check/flutter_check" && flutter pub get && flutter analyze \
  && flutter test --concurrency=1 | tee "$TMPDIR/flutter.out")
python3 tool/check_traces.py packages/flutter_solo/doc/mixins.md \
  "$TMPDIR/flutter.out"
```

`solo` (`vs-bloc.md`) — генерация уже проверяет имена `flutter_solo`, которые
называет страница, и списки `QUOTED` и `SAID`; блоки кода этой работой
не меняются, поэтому драйверы не гоняются:

```sh
python3 tool/doc_snippets.py "$TMPDIR/doc-check"
```

Время старта реакций и вывод `state.md` держат тесты пакетов,
а не `check_traces.py`: в README `flutter_solo` блока трассы быть не может
(тест разрешает только `sh` и `yaml` вне `dart`), а `state.md`
к `check_traces.py` не подключён.

## Как ветка входит в `main`

Делается при подготовке выпуска, по слову владельца; здесь — порядок.

1. Часть `solo`: `git rebase main` в ветке, гейт целиком в копии на голове
   ветки, затем в `main` `git merge --ff-only <последний коммит задачи 2>`.
2. После выпуска `solo` 1.1.0 — `git rebase main` остатка ветки. Запись задачи
   7 в `CHANGELOG.md` `solo` и в переводе должна лечь в новый «Unreleased»,
   а не под «1.1.0»: проверить глазами и `check_translations.py`.
3. Часть `flutter_solo` — так же, `--ff-only`, перед выпуском `flutter_solo`.

## Review Focus

Случаи, которых дизайн не называет, но которые встретит пользователь. Тест
на каждый стоит в задаче, которая владеет кодом.

1. **`listener` бросает синхронно** — функция без `async`, бросок до первого
   `await`. Ожидание: ошибка в `FlutterError`, как у асинхронного провала;
   следующие реакции идут. Задача 4.
2. **Контроллер меняется туда и обратно, A → B → A.** Ожидание: одна запись в A
   даёт одну реакцию, а не две; реакции первого A отменены. Задача 4.
3. **Перенос виджета по `GlobalKey`** — `deactivate` и `activate` без
   `dispose`. Ожидание: подписка и идущие реакции живут, отмены нет. Задача 4.
4. **`listenWhen` сам пишет в контроллер.** Ожидание: запись — вложенная,
   приходит следующей парой; ни ошибки, ни потерянного изменения. Задача 3.
5. **Виджет на контроллере, закончившем закрытие** — с первой сборки или после
   смены `solo` на такой. Ожидание: ни ошибки, ни реакции. Задача 4.
6. **Две записи в одном синхронном ходе в `restart`** — реакция на первую ещё
   не стартовала. Ожидание: реакция на вторую. Задача 3.

---

### Task 1: подписка с парой в `solo`

**Files:**
- Create: `packages/solo/lib/src/change_listeners.dart` — список пар,
  не экспортируется ни одной библиотекой пакета.
- Modify: `packages/solo/lib/src/solo.dart` — поле рядом с `_listeners`
  (`:161`), `hasListeners` (`:207`), dartdoc `addListener` (`:212`), новые
  члены после `removeListener` (`:242`), `publish` (`:262–273`), `_finishClose`
  (`:928`), dartdoc класса (`:29`).
- Modify: `packages/solo/doc/reference.md` («What a caller sees», строки обоих
  членов) и `docs/ru/solo/reference.md` — `reference_page_test.dart` сверяет
  члены `Solo` со строками страницы и перевода и без них краснеет; сам тест
  правки не требует.
- Test: `packages/solo/test/change_listeners_test.dart`.

**Interfaces:**
- Produces:
  `void addChangeListener(void Function(S previous, S current) listener)`,
  `void removeChangeListener(void Function(S previous, S current) listener)`
  на `Solo<S>`; слушатели пары зовутся в `publish` после `addListener`.

- [ ] **Step 1: тесты.** Контроллер в тестах —
  `final class _Counter extends Solo<int>` с `_Counter() : super(0);`
  и `void set(int next) => externalSetState(next);`. Группа
  `addChangeListener`, тесты и ожидания:
  - `every change arrives with its pair, in order`: записи 1, 2, 3 →
    `['0>1', '1>2', '2>3']`;
  - `a nested write from a plain listener arrives as the next pair`: слушатель
    `addListener` на `1` пишет `2`; подписан до пары и после; в обоих порядках
    пары `['0>1', '1>2']`;
  - `a nested write from a pair listener arrives as the next pair`: то же,
    пишет слушатель пары;
  - `a return to the old state is two changes`: слушатель на `1` пишет `0` →
    `['0>1', '1>0']` в обоих порядках;
  - `the same object written twice is two changes`: запись `1`, `1` →
    `['0>1', '1>1']`;
  - `pairs come after the plain listeners of the same change`: общий журнал,
    пара подписана первой → `['plain 1', 'pair 0>1']`;
  - `a pair listener sees the plain listener's nested write in currentState` —
    следствие пункта 2 подписки: слушатель `addListener` на `1` пишет `2`,
    слушатель пары на `0>1` читает `currentState` → `2`; в обоих порядках
    подписки;
  - `a listener removed during a pass is not called,
    one added hears the next change`;
  - `removeChangeListener matches with == and removes one registration`: отрыв
    метода дважды снимает; две регистрации одной функции, одно снятие → один
    вызов;
  - `a failing pair listener goes to onListenerError and the rest are called`;
  - `a write during close is heard,
    and after isFinished the listeners are gone`: запись из `onClose` слышна;
    после конца закрытия `addChangeListener` ничего не делает, новая
    регистрация не зовётся;
  - `hasListeners counts a pair listener`: через подкласс, который открывает
    `hasListeners` — оно `@protected`.

- [ ] **Step 2:** `dart test test/change_listeners_test.dart` — не собирается:
  `addChangeListener` не определён.

- [ ] **Step 3: реализация.** `ChangeListeners<S>` в `change_listeners.dart`
  повторяет семантику `Listeners` из `listeners.dart` — снимок на время
  прохода, пропуск снятого во время прохода, снятие самой ранней активной
  регистрации по `==`, `clear`, `isEmpty`, — но для
  `void Function(S previous, S current)`,
  и `notify(previous, current, onError)`. В `Solo`: поле `_changeListeners`
  (nullable), `addChangeListener` ничего не делает при `_finished`; `publish`
  после `listeners.notify` зовёт
  `_changeListeners?.notify(previous, current, _reportListenerError)`;
  `_finishClose` очищает и обнуляет его там же, где `_listeners`;
  `hasListeners` истинно, если непуст хотя бы один из двух.

- [ ] **Step 4: dartdoc** по решению 103. `addChangeListener`: фраза; договор —
  каждое изменение с парой, синхронно, после слушателей `addListener`, значение
  может быть старше `currentState`; отличие от `onChange(SoloTransition)` — там
  задача изменения и защищённый хук, здесь пара для любого, у кого есть
  контроллер; ссылка на «Observing state» `state.md` (якорь `#observing-state`
  уже есть). `removeChangeListener` — как у `removeListener`. `addListener` —
  ссылка на пару для того, кому нужно каждое значение. Класс `Solo` (`:29`)
  и `publish` называют слушателей пары и их порядок. `SoloListener` нигде
  не назван.

- [ ] **Step 5: строки справочника.** `reference.md` и перевод — по строке
  на каждый член в «What a caller sees», по образцу строк `addListener`
  и `removeListener`.

- [ ] **Step 6:** весь набор `packages/solo` зелёный (включая
  `reference_page_test.dart`), анализ, формат и `dart doc --dry-run` чистые;
  проверки документов из Global Constraints зелёные.

- [ ] **Step 7: коммит**
  `feat(solo): add addChangeListener with the previous and the current state`.

### Task 2: документы `solo` о подписке с парой

**Files:**
- Modify: `packages/solo/doc/state.md` («Observing state»),
  `packages/solo/test/support/state_page.dart` (`observing`, `:97–111`),
  `packages/solo/test/state_rakes_test.dart` (группа «Observing state»,
  `:1368`), `packages/solo/README.md` (таблица задач, `:355`),
  `packages/solo/doc/vs-bloc.md` (строка `state`, `stream`),
  `packages/solo/CHANGELOG.md` («Unreleased», «Added»).
- Modify, переводы: `docs/ru/solo/state.md`, `packages/solo/README.ru.md`,
  `docs/ru/solo/vs-bloc.md`, `docs/ru/solo/CHANGELOG.md`.

**Interfaces:**
- Consumes: `addChangeListener` из задачи 1.

- [ ] **Step 1: сторож страницы первым.** В `state_page.dart` в `observing`
  строка с `addChangeListener` рядом с `addListener`; в `state_rakes_test.dart`
  тест группы «Observing state» ждёт её вывод. Прогон: красный, пока блок
  `state.md` не повторяет `observing` дословно.

- [ ] **Step 2: `state.md`.** Блок кода — дословно новый `observing`. Абзац
  о паре: каждое изменение, после `addListener` того же изменения, значение
  может быть старше `currentState`. Список трёх обещаний и абзац о вложенной
  записи называют обе подписки. Если правка тронет диаграмму вложенной записи,
  тест с `hasLength(8)` и классом `_Order` (`state_rakes_test.dart:1499–1509`)
  правится вместе с ней.

- [ ] **Step 3: остальные места.** README — строка рядом с «A stream event
  arrives a microtask late»: «Every change with what it replaced, and a
  listener that reads the state misses one» → `addChangeListener` → ссылка
  на «Observing state»; `vs-bloc.md` — `addChangeListener` рядом
  с `addListener` в строке `state`, `stream`; `CHANGELOG.md` — «Added»
  в «Unreleased».

- [ ] **Step 4: переводы** всех мест, `humanizer--ru` по изменённым абзацам.

- [ ] **Step 5: проверки.** `dart test` `packages/solo` зелёный; проверки
  документов; генерация `doc_snippets.py` по разделу «Стенды».

- [ ] **Step 6: коммит** `docs(solo): describe addChangeListener`. Это
  последний коммит части `solo`.

### Task 3: `SoloListener` — подписка, `listenWhen`, режимы

**Files:**
- Create: `packages/flutter_solo/lib/src/solo_listener.dart`.
- Modify: `packages/flutter_solo/lib/flutter_solo.dart` — экспорт рядом
  с `solo_builder.dart`; `packages/flutter_solo/pubspec.yaml` — `solo: ^1.1.0`.
- Create: `packages/flutter_solo/pubspec_overrides.yaml`,
  `packages/flutter_solo/example/pubspec_overrides.yaml` — `solo` на дерево.
- Test: `packages/flutter_solo/test/solo_listener_test.dart`.

**Interfaces:**
- Consumes: `addChangeListener`, `removeChangeListener` (задача 1).
- Produces: `enum SoloListenerMode { concurrent, sequential, droppable,
  keepLatest, restart }`;
  `final class SoloListener<S extends Object> extends StatefulWidget` с полями
  и конструктором из раздела «Виджет» дизайна; `listener` типа
  `FutureOr<void> Function(JobContext ctx, BuildContext context, S state)`.

Контроллер в тестах — свой `_Counter` в файле теста, как в задаче 1: `super(0)`
и `set` через `externalSetState`; трассы рассчитаны на начальное
0. Реакция пишет в журнал `s<N>` при старте и `e<N>` в конце, где `N` — её
   состояние. «Трасса режимов»: запись 1, через 10 мс 2 и 3 подряд, реакция
   ждёт 100 мс через `ctx.pause`, часы двигаются до конца.

- [ ] **Step 1: тесты.**
  - `no reaction on start`: виджет на контроллере в состоянии 5, `pump` →
    журнал пуст;
  - `a throwing addChangeListener leaves no registration`: по образцу теста
    `SoloBuilder` — контроллер, чей `addChangeListener` регистрирует и бросает;
    слушатель снят;
  - `listenWhen gets the pair of the change`: записи 1, 2 → `listenWhen`
    получил `(0, 1)`, `(1, 2)`;
  - `a skipped change starts no reaction`: `listenWhen: (p, c) => c.isOdd`,
    записи 1, 2, 3 → реакции на 1 и 3;
  - `every change reacts without listenWhen, the same object too`: запись 1, 1
    → две реакции;
  - трасса каждого режима, по тесту на режим: `concurrent` →
    `s1 s2 s3 e1 e2 e3`; `sequential` → `s1 e1 s2 e2 s3 e3`; `droppable` →
    `s1 e1`; `keepLatest` → `s1 e1 s3 e3`; `restart` → `s1 s3 e3`;
  - `restart starts the next reaction when the cancelled one ends`: время
    старта реакции на 3 по часам `testWidgets` — обычный
    `await Future<void>.delayed(...)`
    и `ctx.join(() => Future<void>.delayed(...))`: 100 мс;
    `ctx.abandonable(() => Future<void>.delayed(...))` и `ctx.pause`: 10 мс;
  - Review Focus 6:
    `restart with two writes in one turn reacts to the second only`: `set(1)`
    и `set(2)` в одном ходе → `s2 e2`;
  - `restart cancels with ReplacedCancelReason`: отменённая реакция видит
    `Cancelled` с причиной `ReplacedCancelReason`;
  - `a reaction writing to its own controller`: в `sequential` её запись встаёт
    в очередь за ней (реакции на 1, 2, 3 по очереди при записи `n + 1` до 3);
    в `droppable` отбрасывается; в `restart` отменяет саму реакцию;
  - `a mode change leaves living reactions alone`: `concurrent` с тремя идущими
    → `sequential` — три идущие доходят, следующая запись ждёт их; `sequential`
    с двумя ждущими → `droppable` — ждущие стартуют по одной;
  - `the next change applies the new mode to the waiting ones`: `sequential`,
    идёт 1, ждут 2 и 3, перестроение в `keepLatest`, запись 4 → `s1 e1 s4 e4`;
  - `the listener is read when the reaction starts`: `sequential`, перестроение
    с новым `listener` пока ждёт реакция на 2 → её выполняет новый;
  - `listenWhen and mode are read at notification`;
  - `a nested write from a plain listener reaches listenWhen as the next pair`:
    слушатель `addListener` на 1 пишет 2, подписан до виджета и после → в обоих
    порядках `listenWhen` получил `(0, 1)`, `(1, 2)`, реакции на 1 и 2; возврат
    1 → 0 даёт реакции на 1 и 0;
  - Review Focus 4: `listenWhen writing to the controller` — запись
    из `listenWhen` приходит следующей парой, ошибок нет.

- [ ] **Step 2:** `flutter test test/solo_listener_test.dart` — не собирается.

- [ ] **Step 3: реализация.** Образец подписки — `_SoloBuilderState` (`_follow`
  с защитой, флаг `_disposed`). Состояние держит множество идущих `Job<void>`
  и список ждущих `S`; задачи на ждущие не создаются, следующая стартует
  из `whenFinished` прошлой, когда идущих нет. `listenWhen` и `mode` читаются
  из `widget` в оповещении; новый режим со следующего изменения применяется
  и к ждущим (`keepLatest` и `restart` их заменяют). Реакция —
  `Job<void>((ctx) async => widget.listener(ctx, context, state),
  describe: ..., observer: ...)`: `listener` читается в теле, то есть при
  старте реакции — так замыкание из `build` свежее и для ждущего (решение
  плана: «момент старта» дизайна — начало тела). `restart` — сначала заменить
  ждущих новым состоянием, потом `cancel(const ReplacedCancelReason())` идущих,
  не дожидаясь: `whenFinished` отменённой до старта срабатывает прямо при
  отмене, и при обратном порядке изменение теряется. `build` возвращает
  `child`. `debugFillProperties` — `solo` и `mode`.

- [ ] **Step 4: dartdoc** по решению 103, разложенный по членам, каждый блок
  в пределах 10 и 30 строк `check_dartdoc.py`:
  - класс `SoloListener` — фраза; договор: реакция на каждое изменение, которое
    пропустил `listenWhen`, задачей ядра, на микрозадаче; главная ловушка —
    отмена кооперативная, `ctx.join` и обычный `await` ждут до конца; один блок
    кода — пример с задержкой через `ctx.pause`; ссылка на `SoloBuilder` для
    того, что показывается;
  - `listener` — `ctx` первым, значение изменения, а не текущее состояние,
    читается при старте реакции;
  - `listenWhen` — пара изменения, без него — каждое изменение, бросок —
    в `FlutterError` и пропуск;
  - `mode` — читается при оповещении, новый режим со следующего изменения
    применяется и к ждущим;
  - `SoloListenerMode` и каждое значение — своя трасса; у `sequential`,
    `droppable` и `restart` — что делает запись реакции в свой контроллер.

  Ссылки на раздел README здесь нет: она приходит в задаче 5 вместе с разделом.

- [ ] **Step 5:** проверки кода из Global Constraints для
  `packages/flutter_solo` и `example`; `python3 tool/check_dartdoc.py`,
  `python3 tool/check_links.py`.

- [ ] **Step 6: коммит** `feat(flutter_solo): add SoloListener`, вместе
  с `pubspec.yaml` и оверрайдами.

### Task 4: уход, смена контроллера, ошибки, таймеры

**Files:**
- Modify: `packages/flutter_solo/lib/src/solo_listener.dart`.
- Test: `packages/flutter_solo/test/solo_listener_test.dart`.

**Interfaces:**
- Consumes: виджет задачи 3.

- [ ] **Step 1: тесты.** Где сказано «без перевода часов», тест кончается
  уходом виджета и одним `pump()`.
  - `dispose cancels a running reaction with ManualCancelReason`: реакция ждёт
    `ctx.pause(5 s)`, уход → `Cancelled` с `ManualCancelReason`, код после
    ожидания не идёт; без перевода часов;
  - `dispose before the start calls no reaction`: запись и уход в одном кадре →
    тело не вызвано;
  - `dispose drops the waiting states`: `sequential`, одна идёт, две ждут, уход
    → ни одна ждущая не стартует;
  - `a new controller cancels the reactions of the old one`: идущая отменена,
    ждущая не стартует, запись в старый не слышна, вызова при подписке к новому
    нет;
  - `the reactions of the new controller wait for the cancelled ones`:
    `sequential`, старая реакция ждёт обычным `await` 100 мс → первая реакция
    нового стартует на 100 мс;
  - `droppable drops a change of the new controller while a cancelled reaction
    of the old one runs`: A пишет 1, на 5 мс виджет переходит на B, на 10 мс B
    пишет 7, старая реакция ждёт обычным `await` 100 мс → реакции на 7 нет;
  - Review Focus 2: `A to B and back to A reacts once per write`;
  - Review Focus 5: `a finished controller gives neither error nor reaction` —
    с первой сборки и после смены `solo`;
  - Review Focus 3: `reparenting with a GlobalKey keeps the reactions` —
    подписка жива, идущая реакция не отменена;
  - `closing the controller does not cancel a reaction`: реакция идёт, `close`
    контроллера → реакция доходит до конца; запись из `onClose` даёт реакцию;
  - `a throwing listenWhen goes to FlutterError and starts no reaction`:
    `tester.takeException()` — брошенное, журнал пуст; следующее изменение
    реагирует;
  - `a failed reaction goes to FlutterError and the next one runs`;
  - Review Focus 1: `a listener throwing synchronously goes to FlutterError`;
  - `a failure after the screen left goes to FlutterError`: реакция ждёт
    обычным `await` 50 мс, уход на 10 мс; после ожидания (а) бросает
    `StateError`, (б) зовёт `ScaffoldMessenger.of(context)`; в обоих
    `takeException()` даёт ошибку, тест зелёный;
  - `a cancellation reports nothing`: отменённая реакция без провала —
    `takeException()` пуст;
  - `writes from initState, build and dispose of another widget`: шесть
    случаев — момент × реакция `showSnackBar` или `Navigator.push`; ни одной
    ошибки, снэкбар и маршрут на экране.

- [ ] **Step 2:** прогон — красные те, что требуют нового кода (порядок ухода,
  наблюдатель); записать, какие красные, в отчёт работы.

- [ ] **Step 3: реализация.** Порядок в `dispose` и в `didUpdateWidget`
  с другим `solo` (по идентичности): поднять флаг ухода (при уходе), очистить
  ждущих, снять подписку, потом отменить идущих `ManualCancelReason` —
  `whenFinished` отменённой до старта срабатывает прямо при отмене. Идущие
  отменённые старого контроллера остаются в множестве идущих: в `sequential`,
  `keepLatest` и `restart` реакции нового их ждут, в `droppable` изменение
  нового, пришедшее за это время, отбрасывается (решение плана: очередь одна,
  отменённая реакция — тоже идущая). Наблюдатель — один на состояние виджета,
  `final class _Reporter extends JobObserver with JobAnswerer`, `onUnanswered`
  зовёт `FlutterError.reportError(FlutterErrorDetails( exception: error,
  stack: stackTrace, library: 'flutter_solo',
  context: ErrorDescription('while running a reaction of SoloListener')))`.
  `done` реакции не читается: непрочитанный `Failed` доходит через тот же
  ответчик. `listenWhen` — под `try`, бросок → `FlutterError.reportError`
  с контекстом `'while calling listenWhen of SoloListener'`, изменение
  пропускается.

- [ ] **Step 4: dartdoc** класса — уход и смена контроллера отменяют реакции,
  ждущие сбрасываются; ошибки — в `FlutterError`; поведение `droppable` после
  смены контроллера — в dartdoc `SoloListenerMode.droppable`. Пределы
  `check_dartdoc.py` те же.

- [ ] **Step 5:** набор зелёный, ни один тест не оставляет таймера; проверки
  кода и `check_dartdoc.py`.

- [ ] **Step 6: коммит** `feat(flutter_solo): cancel SoloListener reactions
  with the screen and report their failures`.

### Task 5: README `flutter_solo`

**Files:**
- Modify: `packages/flutter_solo/README.md` — новый раздел после «Listening
  without keeping the callback» (`:375`), «Install» (`:58`), таблица «What the
  screen needs» (`:203`), «Notes» (`:663`, ответ «When do listeners run?»
  `:674`); `packages/flutter_solo/README.ru.md`.
- Modify: `packages/flutter_solo/lib/src/solo_listener.dart` — последний абзац
  dartdoc класса ведёт на новый раздел.
- Modify: `packages/flutter_solo/test/support/readme_widgets.dart`,
  `packages/flutter_solo/test/support/readme_install.dart`,
  `packages/flutter_solo/test/readme_rakes_test.dart` (`hasLength(17)`
  на `:180`, `hasLength(10)` у `arrivesWithOneImport` на `:344`, группа `Notes`
  со сторожами `_says` на `:2386`, `:2392`), `tool/flutter_snippets.py`.
- Modify: `packages/flutter_solo/CHANGELOG.md`,
  `docs/ru/flutter_solo/CHANGELOG.md`.

**Interfaces:**
- Consumes: `SoloListener`, `SoloListenerMode`.

- [ ] **Step 1: код раздела в стенде README первым.** В `readme_widgets.dart` —
  код раздела дословно; в `readme_rakes_test.dart` — сторож раздела:
  - снэкбар о потере соединения: первая попытка — `showSnackBar` в `builder`
    у `SoloBuilder` бросает «The showSnackBar() method cannot be called during
    build» и повторяется на каждой сборке; решение — `SoloListener`, снэкбар
    один на изменение;
  - подсказки к запросу в `restart`: первая попытка — обычный `await`,
    подгрузка на новый запрос стартует после конца старой; второй шаг —
    `ctx.join`, код после него не идёт, старт так же поздний; решение —
    `ctx.pause` для задержки, `ctx.abandonable` для вызова, который можно
    бросить, токен через `ctx.onCancel`; время старта новой подгрузки сторожит
    тест, а не процитированная трасса.

  Прогон: красный, пока README не несёт блоков.

- [ ] **Step 2: раздел README** по форме страниц: требование, первая попытка,
  решения; две ловушки — подразделами одного раздела или двумя разделами,
  решает исполнитель. Первый `dart`-блок под «The first attempt» открывается
  строкой `// The first attempt: …`, в переводе — `// Первая попытка: …`
  (`check_doc_shape.py`). Граница раздела: результат своей операции —
  `job.done`, новость, переживающая экран, — доска `state.md` `solo`. Ни одна
  фраза не обещает, что уход или `restart` останавливает реакцию.

- [ ] **Step 3: другие места README.** «Install» называет `SoloListener` среди
  виджетов; `arrivesWithOneImport` — плюс `SoloListener<Object>`
  и `SoloListenerMode`, его `hasLength` — 12; `ownPart` берёт
  и `SoloListener<Object>`; сторож `_says` — новую фразу. Таблица «What the
  screen needs» — «A reaction to every change, cancelled with the screen» →
  `SoloListener`. «Notes»: строка «A listener or a reaction of `SoloListener`»
  → `FlutterError` при любом контроллере, со сторожем `_says` и прогоном
  маршрута по образцу соседних строк группы `Notes`; ответ «When do listeners
  run?» — фраза о микрозадаче реакций `SoloListener` после двух фраз, которые
  сторож держит подряд («Synchronously, in subscription order, on every state
  change. With `SoloListenable`, `value` and `currentState` are the same
  object.»), со своим сторожем. `hasLength(17)` — новое число Dart-блоков.
  Последний абзац dartdoc класса `SoloListener` — ссылка `blob/main` на новый
  раздел.

- [ ] **Step 4: стенд.** В `tool/flutter_snippets.py` — драйвер каждого блока
  раздела; адресация по подразделу, как у «Listening without keeping the
  callback», если два блока объявляют одно имя.

- [ ] **Step 5: перевод и `CHANGELOG`.** `README.ru.md` — те же места,
  `humanizer--ru`; `CHANGELOG.md` и перевод — «Added» в «Unreleased».

- [ ] **Step 6: проверки.** `flutter test` `packages/flutter_solo`; стенд
  `flutter_solo` по разделу «Стенды»; проверки документов и кода.

- [ ] **Step 7: коммит**
  `docs(flutter_solo): add the SoloListener section to the README`.

### Task 6: страницы тестов и миксинов

**Files:**
- Modify: `packages/flutter_solo/doc/testing.md`,
  `docs/ru/flutter_solo/testing.md`, `packages/flutter_solo/doc/mixins.md`
  (`:8`), `docs/ru/flutter_solo/mixins.md`; при новом блоке кода —
  `test/support/testing_code.dart` или `testing_variants.dart`,
  `test/testing_rakes_test.dart` и `tool/flutter_snippets.py`.

- [ ] **Step 1:** если `testing.md` получает блок кода — сторож
  в `testing_rakes_test.dart` первым: реакция, пережившая виджет, на обычном
  `await Future.delayed` — тест без перевода часов краснеет на «A Timer is
  still pending»; с переводом часов или с `ctx.pause` — зелёный.

- [ ] **Step 2: `testing.md`** — пункт о реакции, пережившей виджет: она держит
  свой таймер; тест двигает часы, или реакция ждёт через `ctx.pause`.
  `mixins.md:8` — фраза «The builders of this package, `SoloBuilder` and
  `SoloSelector`, take any controller» переписывается: `SoloListener` не строит
  виджеты, но тоже берёт любой контроллер. Переводы, `humanizer--ru`.

- [ ] **Step 3: проверки** — как в задаче 5.

- [ ] **Step 4: коммит** `docs(flutter_solo): say what a reaction that outlives
  the widget does to a test`.

### Task 7: места `solo`, которые называют виджет

**Files:**
- Modify: `packages/solo/lib/src/solo_cancel_reason.dart` (dartdoc
  `SoloCancelReason` `:5` и `ReplacedCancelReason` `:43–48`),
  `packages/solo/doc/reference.md` (`:177`), `docs/ru/solo/reference.md`,
  `packages/solo/doc/cancellation.md` (таблица «Cancellation details», `:352`),
  `docs/ru/solo/cancellation.md`, `packages/solo/doc/vs-bloc.md`,
  `docs/ru/solo/vs-bloc.md`, `tool/doc_snippets.py` (`:279`),
  `packages/solo/CHANGELOG.md`, `docs/ru/solo/CHANGELOG.md`.

- [ ] **Step 1: сторож имён первым.** В список имён `flutter_solo`, которые
  называет `vs-bloc.md`, в `tool/doc_snippets.py` —
  `('class SoloListener', 'solo_listener.dart')`; комментарий над списком
  «names three things» → «four». Генерация краснеет, пока строки в `vs-bloc.md`
  нет.

- [ ] **Step 2: `vs-bloc.md`.** Отдельная строка «`BlocListener` for a change
  this screen did not make» → `SoloListener`, с отменой реакции; строка
  «`BlocListener` for an operation's result» остаётся.

- [ ] **Step 3: причины отмены.** Dartdoc `SoloCancelReason` — причины `solo`,
  движков на нём и виджетов `flutter_solo`; `ReplacedCancelReason` — ещё
  и реакция `SoloListener` в `restart`, которую заменила более новая. Имя
  виджета — код-спаном, без квадратных скобок: `SoloListener`
  из `flutter_solo`, не `[SoloListener]`; `solo` от `flutter_solo` не зависит,
  а `comment_references` под `--fatal-infos` краснеет. Строка справочника
  `reference.md:177` и строка таблицы `cancellation.md:352` — так же
  (`cancellation.md` дизайн не называл, решение плана по ревью).

- [ ] **Step 4:** переводы, `humanizer--ru`; `CHANGELOG.md` `solo` и перевод —
  запись в «Unreleased» о dartdoc, таблице и строке `vs-bloc`.

- [ ] **Step 5: проверки.** Проверки кода `packages/solo`; генерация
  `doc_snippets.py` по разделу «Стенды»; проверки документов.

- [ ] **Step 6: коммит**
  `docs: name SoloListener next to BlocListener and ReplacedCancelReason`. Этот
  коммит — часть выпуска `flutter_solo`.

### После задач

- Независимое ревью всей ветки на Opus, по своей копии дерева на ревьюера;
  находки с вердиктами — в отчёт `2026-11-NN-solo-listener-report.md`.
- Гейт целиком в копии на голове ветки: пять заданий CI локально, включая
  `floor` на `~/fvm/versions/3.38.1`.
- В `main`, отдельными `docs:`-коммитами: отчёт; `docs/handoff.md` — ветка
  готова и ждёт выпусков, какой коммит закрывает часть `solo`; шапки дизайна
  и плана — «сделано в ветке `solo-listener`, ждёт выпуска».

## Ревью плана

Независимое ревью Opus 2026-11-09 плана на коммите `713a0fbf`, в своей копии
дерева. Текст ревьюера — дословно, вердикты — мои.

### 1. Важная. Коммит задачи 1 красный: `reference_page_test.dart` требует строк справочника, а они только в задаче 2

**Суть.** Задача 1 добавляет `Solo` два публичных члена. Её шаг 5 требует «весь
набор `packages/solo` зелёный». Но `reference_page_test.dart` читает члены
`Solo` через зеркала и сверяет их со строками `doc/reference.md` и перевода
`docs/ru/solo/reference.md`. Обе строки появляются только в задаче 2. Выходит,
первый коммит части `solo` нарушает гейт, а шаг 5 задачи 1 невыполним. Заодно:
в «Files» задачи 2 `reference_page_test.dart` стоит как «Modify», хотя правка
ему не нужна — члены он берёт из кода.

**Свидетельство.** `packages/solo/test/reference_page_test.dart:216–219`:
`final rows = _rows(_under(text, '## $name')); expect(rows,
unorderedEquals(_members(type).keys));`. Зонд: в `solo.dart` подставлена
спайковая версия из `worktree-solo-listener-spike` (`addChangeListener`
и `removeChangeListener`), затем `dart test -r expanded` в `packages/solo`:

```text
00:00 +278 -1: test/reference_page_test.dart: doc/reference.md lists every member of Solo and nothing else [E]
00:00 +312 -2: test/reference_page_test.dart: ../../docs/ru/solo/reference.md lists every member of Solo and nothing else [E]
00:07 +2243 -2: Some tests failed.
     Which: has too few elements (32 < 34)
```

Других падений нет.

**Что писать в плане.** Строки обоих членов в «What a caller sees»
`doc/reference.md` и в переводе перенести в задачу 1, в её коммит. Якорь
`state.md#observing-state` уже существует. Из «Files» задачи 2 убрать
`reference_page_test.dart` или пометить «правки не нужно, краснеет сам».

Вердикт: принято. Строки теста сверены. Строки справочника и перевода — шаг 5
задачи 1, `reference_page_test.dart` убран из задачи 2.

### 2. Важная. `restart`: если отменить идущую до того, как ждущее записано, изменение теряется, и ни один тест плана этого не ловит

**Суть.** `whenFinished` задачи, отменённой до старта, срабатывает синхронно.
План называет эту ловушку только для `dispose` и `didUpdateWidget` (задача 4,
шаг 3). В `restart` она такая же. Две записи в одном синхронном ходе: реакция
на первую создана, но ещё не стартовала. Если вторая запись сначала отменяет
идущую и только потом кладёт себя в ждущие, то `whenFinished` срабатывает при
пустом списке ждущих, и реакции нет ни на одно из двух изменений. Трасса
режимов плана пишет 2 и 3 через 10 мс, когда реакция на 1 уже идёт, а у идущей
задачи `whenFinished` асинхронный. Поэтому неверный порядок проходит все тесты
задачи 3.

**Свидетельство.** Зонд на виджете прототипа, к которому добавлены наблюдатель
`JobAnswerer` и `ReplacedCancelReason`. `restart`, `c..set(1)..set(2)` в одном
ходе, реакция `ctx.pause(100 ms)`:

```text
P1 [s2@0, e2@99] ex=null      // ждущее записано, потом отмена
P1 [] ex=null                 // отмена, потом ждущее: реакции нет вовсе
```

**Что писать в плане.** В шаг 3 задачи 3: «в `restart` сначала заменить ждущих
новым состоянием, потом отменять идущих: `whenFinished` отменённой до старта
срабатывает прямо при отмене». В шаг 1 добавить тест
`restart with two writes in one turn reacts to the second only` → `s2 e2`.

Вердикт: принято. Порядок — в шаге 3 задачи 3, тест — там же и шестым пунктом
Review Focus.

### 3. Важная. `droppable` после смены контроллера отбрасывает изменение нового, а дизайн говорит «ждут»

**Суть.** Дизайн, пункт 6 «Поведения»: «Реакции нового контроллера в режимах,
кроме `concurrent`, ждут конца отменённых реакций старого: очередь у виджета
одна». План повторяет это в задаче 4, шаг 3: «реакции нового ждут их в режимах,
кроме `concurrent`». При общем множестве идущих `droppable` не ждёт,
а отбрасывает: старая отменённая реакция, которая ждёт обычным `await`,
считается идущей. Первое изменение нового контроллера пропадает. Тест плана
проверяет только `sequential`.

**Свидетельство.** Зонд: `droppable`, A пишет 1, на 5 мс виджет переходит на B,
на 10 мс B пишет 7, старая реакция ждёт `Future.delayed(100 ms)`:

```text
P10 [as1@0, ae1@99] ex=null
```

Реакции на 7 нет. В `sequential` то же построение даёт
`[as1@0, ae1@99, bs7@99, be7@199]`.

**Что писать в плане.** Выбрать одно из двух и записать решением исполнителя
со ссылкой на дизайн.
- (а) Принять: «в `droppable` изменение нового контроллера, пока доходит
  отменённая реакция старого, отбрасывается». Сказать это в dartdoc и поставить
  тест рядом
  с `the reactions of the new controller wait for the cancelled ones`.
- (б) Не считать отменённые реакции старого занятостью для `droppable`.

Вариант (а) проще и соответствует «очередь одна». Но формулировку дизайна
«ждут» тогда надо уточнить, чтобы dartdoc не повторил её дословно.

Вердикт: принят вариант (а), моё решение: очередь одна, и отменённая реакция —
тоже идущая; `droppable` отбрасывает, пока что-то идёт, чьё бы оно ни было. Шаг
3 задачи 4 говорит это решением плана, тест и строка dartdoc
`SoloListenerMode.droppable` — там же; пункт 6 «Поведения» дизайна уточнён.

### 4. Важная. Объём dartdoc `SoloListener` противоречит решению 103 и `check_dartdoc.py`, а ссылка на раздел README возможна только после задачи 5

**Суть.** Шаг 4 задачи 3 кладёт в dartdoc `SoloListener` и `SoloListenerMode`
пример, пункты 2–8, трассу каждого режима, запись реакции в свой контроллер
и кооперативность отмены. `check_dartdoc.py` стоит в гейте (задание `docs`)
и пропускает блок `///` не длиннее 30 строк и абзац не длиннее 10. Решение 103
требует: разбор случаев — на странице, последний абзац ведёт на её раздел
адресом `blob/main`. Задача 1, шаг 4 (пункты 1–4 и отличие от `onChange`)
упирается в то же. Есть и вторая проблема. Ссылка из dartdoc на новый раздел
README проверяется `check_links.py` по дереву, а раздел появляется в задаче 5.
Ссылка, написанная в задаче 3, краснит коммит задачи 3. Шаг 5 задачи 3
не гоняет ни `check_dartdoc.py`, ни `check_links.py`.

**Свидетельство.** `tool/check_dartdoc.py:36–37`: `PARAGRAPH = 10`,
`BLOCK = 30`. `docs/settled.md:1050–1056`: «Первый абзац — одна фраза, второй —
договор… Разбор, который страница уже говорит, из dartdoc уходит; последний
абзац ведёт на раздел страницы своего пакета абсолютным адресом `blob/main`
с якорем». План, строки 292–296.

**Что писать в плане.** Разложить содержимое по членам: класс — одна фраза,
договор и одна главная ловушка (кооперативность отмены); `listener`,
`listenWhen`, `mode` — свои блоки; трасса каждого режима — в dartdoc значения
`SoloListenerMode`. Каждый блок укладывается в 10 и 30 строк, со ссылкой
на решение 103. Ссылку на раздел README добавить в задаче 5, тем же коммитом,
что и раздел. В шаг 5 задач 1, 3 и 7 вписать `python3 tool/check_dartdoc.py`
и `python3 tool/check_links.py`.

Вердикт: принято. Пределы и решение 103 сверены. Dartdoc разложен по членам
в шаге 4 задач 1 и 3, правило — в Global Constraints, ссылка на раздел README —
в задаче 5, проверки — в шагах задач.

### 5. Важная. Команды стендов и проверок неверны или неполны

**Суть.**
- `python3 tool/flutter_snippets.py "$TMPDIR/solo-flutter-check"` только пишет
  пакет `flutter_check`. Драйверы не собираются и не запускаются, так что шаг 6
  задачи 5 и шаг 3 задачи 6 нового раздела не проверяют. С `doc_snippets.py`
  в задачах 2 и 7 так же. Там это терпимо: блоки кода не меняются, а сторожа
  имён, `QUOTED` и `SAID` срабатывают при генерации. Но приписка «(он собирает
  `vs-bloc.md`)» вводит в заблуждение.
- `python3 tool/check_traces.py` без аргументов печатает справку и выходит
  с кодом 2. Ему нужны пары «документ, вывод». Для `state.md` (задача 2, шаг 5)
  он вообще не подключён: диаграмму там держит `hasLength(8)`. В README
  `flutter_solo` блока трассы быть не может: тест разрешает вне `dart` только
  блоки `sh` и `yaml`. Задание `flutter` сверяет трассы только у `mixins.md`.
- В документных проверках нет `python3 tool/check_doc_shape.py` (гейт `docs`,
  «A section starts with code, an attempt with its mark»). Новый раздел README
  с первой попыткой должен открывать первый `dart`-блок под «The first attempt»
  строкой `// The first attempt: …`, а перевод — строкой
  `// Первая попытка: …`.
- Нет `dart doc --dry-run` (шаг «Dartdoc» заданий `dart` и `flutter`)
  и `dart analyze --fatal-infos` примера `flutter_solo` (CI гоняет его ради
  плагина `solo_lints`).

**Свидетельство.** `tool/flutter_snippets.py:9–19`: «It creates one package,
flutter_check… Then: flutter pub get / flutter analyze / flutter test».
`tool/check_traces.py:18–23` и `:59–61`:
`if not argv or len(argv) % 2: … return 2`.
`packages/flutter_solo/test/readme_rakes_test.dart:162`: `strayFences(_doc)`
ждёт ровно блоки `sh` и `yaml`. `.github/workflows/gate.yml`, задание
`flutter`, шаг «The quoted traces are the printed ones»: `python3
tool/check_traces.py packages/flutter_solo/doc/mixins.md
"$RUNNER_TEMP/flutter.out"`. `tool/check_doc_shape.py:32–37, 44–47`.

**Что писать в плане.** Задачи 5 и 6, проверки стенда — как в CI:

```sh
python3 tool/flutter_snippets.py "$TMPDIR/doc-check"
(cd "$TMPDIR/doc-check/flutter_check" && flutter pub get && flutter analyze && flutter test --concurrency=1 | tee "$TMPDIR/flutter.out")
python3 tool/check_traces.py packages/flutter_solo/doc/mixins.md "$TMPDIR/flutter.out"
```

Для `doc_snippets.py` написать «генерация проверяет имена, `QUOTED` и `SAID`;
блоки не менялись». Вызов `check_traces.py` для `state.md` убрать.
В «Документы» Global Constraints добавить `check_doc_shape.py`, в проверки
кода — `dart doc --dry-run` и `dart analyze --fatal-infos`
в `packages/flutter_solo/example`. Задаче 5 сказать, что время старта сторожит
тест, а не процитированная трасса.

Вердикт: принято. Шаги CI сверены по `gate.yml`. Новый раздел плана «Стенды:
команды как в CI», `check_doc_shape.py`, `dart doc --dry-run` и анализ
примера — в Global Constraints, метка первой попытки — в шаге 2 задачи 5.

### 6. Важная. Как ветка доходит до `main`: `--ff-only` после сдвига `main`, конфликт `CHANGELOG` и где живёт handoff

**Суть.**
- План вливает часть `solo` командой `--ff-only` по её последнему коммиту. Это
  сработает, только если `main` не сдвинулся. Ветка живёт до двух выпусков,
  параллельные сессии в `main` пишут, так что сдвиг почти неизбежен. Шаг
  «перебазировать ветку на `main`» не назван.
- Часть `flutter_solo` попадает в `main` после коммитов выпуска `solo`
  (`Release solo 1.1.0`, переименование «Unreleased» в «1.1.0»). Задача 7
  дописывает в «Unreleased» `CHANGELOG.md` `solo` и в перевод, а ветка в этот
  момент держит там запись задачи 2. При перебазировании будет конфликт. Хуже
  того, трёхсторонняя склейка может молча уложить запись задачи 7 под заголовок
  «1.1.0».
- «После задач» правит `docs/handoff.md` («ветка готова и ждёт выпусков»). Если
  это коммит ветки, `main` его не видит до выпуска. А `AGENTS.md` требует,
  чтобы handoff в рабочем дереве был источником правды для следующей сессии.
  То же с отчётом `2026-11-NN-solo-listener-report.md` и шапками дизайна
  и плана.

**Свидетельство.** План, строки 39–42: «Коммиты части `solo` идут первыми,
чтобы её можно было влить `--ff-only` по её последнему коммиту». Строки
487–488: «`CHANGELOG.md` `solo` и перевод — запись в «Unreleased»». Строки
504–506. `packages/solo/CHANGELOG.md:1`: `## Unreleased` уже несёт записи.

**Что писать в плане.** Раздел «Как ветка входит в `main`»:
1. Перед вливанием части `solo` — `git rebase main` ветки и прогон гейта, затем
   `git merge --ff-only <последний коммит задачи 2>`.
2. После выпуска `solo` — перебазировать остаток ветки на `main`. Запись задачи
   7 в `CHANGELOG` `solo` должна лечь в новый «Unreleased», а не в «1.1.0».
   Проверить глазами и через `check_translations.py`.
3. Handoff, шапки записей и отчёт коммитить в `main` отдельными
   `docs:`-коммитами и не держать в ветке. Если отчёт описывает код, которого
   в `main` нет, сказать это в его шапке.

Вердикт: принято. Раздел «Как ветка входит в `main`» и правило «Записи —
в `main`» в Global Constraints; «После задач» коммитит записи в `main`.

### 7. Мелкая. `ctx.abandonable` принимает функцию, а не `Future`

**Суть.** В задаче 3, тест `restart starts the next reaction…`, написано
`ctx.abandonable(Future.delayed(...))`. Так не скомпилируется. Рядом
`ctx.join(() => Future.delayed(...))` написан верно.

**Свидетельство.** `packages/async_job/lib/src/job_context.dart:69–70`:
`Future<T> abandonable<T>(FutureOr<T> Function() action, {`.

**Что писать в плане.** `ctx.abandonable(() => Future<void>.delayed(...))`.

Вердикт: принято, сигнатура сверена; исправлено.

### 8. Мелкая. `[SoloListener]` в dartdoc `solo` не разрешится

**Суть.** Задача 7, шаг 3 называет `SoloListener` в dartdoc
`ReplacedCancelReason` и `SoloCancelReason`. `solo` не зависит
от `flutter_solo`, и ссылка в квадратных скобках даст info
`comment_references`. А `dart analyze --fatal-infos` на info падает.

**Свидетельство.** `packages/solo/analysis_options.yaml:50`:
`comment_references: true`.

**Что писать в плане.** «Имя виджета в dartdoc `solo` — код-спаном
«`SoloListener`» из `flutter_solo`, не `[SoloListener]`».

Вердикт: принято, правило сверено; шаг 3 задачи 7.

### 9. Мелкая. Таблица причин на `cancellation.md` тоже говорит, что `ReplacedCancelReason` только от очереди

**Суть.** Ни дизайн, ни план не называют строку таблицы «Cancellation details»
в `packages/solo/doc/cancellation.md`. На эту страницу ведёт строка
справочника, которую правит задача 7. После задачи 7 dartdoc и справочник
скажут про `SoloListener`, а страница — нет.

**Свидетельство.** `packages/solo/doc/cancellation.md:352`: «|
`ReplacedCancelReason` | `Policy.keepLatest` or `Policy.restart` put a newer
job with the same key in its place | `Cancelled(replaced)` |».

**Что писать в плане.** Добавить в задачу 7 эту строку и перевод
`docs/ru/solo/cancellation.md`. Расхождение с дизайном записать решением
исполнителя.

Вердикт: принято, строка сверена. Задача 7 правит её с переводом;
в «Документацию» дизайна строка добавлена.

### 10. Мелкая. Смена `mode` на `keepLatest` или `restart` выбрасывает ждущих прежнего режима

**Суть.** Дизайн: «Смена `mode` при живых реакциях их не трогает: идущие идут,
ждущие разбираются по одной, новый режим действует со следующего оповещения».
При чтении `mode` в оповещении первое же изменение в `keepLatest` или `restart`
очищает ждущих, накопленных в `sequential`. Тест плана проверяет только переход
`sequential` → `droppable`, где ждущие остаются.

**Свидетельство.** Зонд: `sequential`, идёт 1, ждут 2 и 3, перестроение
в `keepLatest`, запись 4:

```text
P8 [s1, e1, s4, e4] ex=null
```

**Что писать в плане.** Тест «`sequential` с двумя ждущими → `keepLatest`,
запись 4 → `s1 e1 s4 e4`» и фраза в dartdoc `mode`: «новый режим со следующего
изменения применяется и к ждущим».

Вердикт: принято. Тест и фраза — в задаче 3; пункт 5 «Поведения» дизайна
уточнён.

### 11. Мелкая. Неточности в тестах и путях

- Задача 1: тест назван
  `a plain listener sees the pair's nested write in currentState`, а описывает
  обратное: пишет слушатель `addListener`, читает слушатель пары. Правильное
  имя:
  `a pair listener sees the plain listener's nested write in currentState`.
  Пункт 2 подписки дизайна требует «при любом порядке подписки», значит, тест
  в двух порядках.
- Задача 3: «`_Counter` из задачи 1» — это приватный класс тестового файла
  `solo`. Во `flutter_solo` его нужно объявить заново, с `super(0)`: трассы
  рассчитаны на начальное 0.
- Задача 5: новая строка Notes «A listener or a reaction of `SoloListener`»
  и дополнение ответа «When do listeners run?» без сторожа в группе `Notes`
  `readme_rakes_test.dart`. Соседние строки сторожатся `_says` с прогоном
  маршрута (`:2386`, `:2392`). Сторож `_says` с фразой «Synchronously, in
  subscription order, on every state change. With `SoloListenable`, `value` and
  `currentState` are the same object.» требует, чтобы эти две фразы стояли
  подряд. Новую фразу о микрозадаче ставить после них.
- Задача 6: фраза `mixins.md:8` начинается словами «The builders of this
  package». `SoloListener` не строит виджеты, так что формулировку надо менять,
  а не просто дописывать имя.
- Номера строк в задаче 1: `_listeners` — `:161` (на `:160` стоит
  `_closedListeners`), dartdoc `addListener` — `:212`. Остальные (`:207`,
  `:242`, `:262–273`, `:928`, `:29`) верны.
- Дизайн, пункт 1 «Поведения»: защита от бросающего `addChangeListener`.
  В плане она есть в реализации, но теста нет. По образцу тестов `SoloBuilder`
  добавить «контроллер, чей `addChangeListener` регистрирует и бросает, —
  слушатель снят».

Вердикт: принято все шесть, исправлено в задачах 1, 3, 5 и 6.

### Что подтвердилось

- **Покрытие дизайна.** Подписка (пункты 1–4), «Поведение» 1–9, «Документация»,
  «Сторожа и стенды» и «Выпуск» разложены по задачам. Нет только того, что
  названо в находках 3, 9, 10 и 11. Ограничение `solo: ^1.1.0` и оверрайды
  стоят в коммите кода виджета.
- **Часть `solo` не называет `SoloListener`.** Задача 1, шаг 4 говорит это
  прямо. Задача 2 трогает только подписку. Строка `vs-bloc` и dartdoc причин
  отмены — в задаче 7.
- **Оверрайды и `floor`.** Зонд: `solo: ^1.1.0` и `pubspec_overrides.yaml`
  у `packages/flutter_solo` и примера. `dart pub publish --dry-run` разрешает
  `solo 1.0.1 from path ../solo (overridden …)` и даёт только hint «Non-dev
  dependencies are overridden». Второе предупреждение — о грязном дереве самого
  зонда. Файл `example/pubspec_overrides.yaml` входит в список архива, значит,
  `archive_floor.py stage` копирует его в раскладку, и пути ведут на соседнюю
  раскладку. `hosted_dependencies` исключает переопределённый `solo` из сверки
  с нижней границей. `tool/flutter_snippets.py` держит свои оверрайды
  на дерево. Пакеты линтов и `packages/solo/example` оверрайдов не требуют.
- **Числа и места.** `hasLength(17)` — `readme_rakes_test.dart:180`.
  `hasLength(10)` у `arrivesWithOneImport` — `:344`, после добавления
  `SoloListener<Object>` и `SoloListenerMode` будет 12.
  `state_page.dart:97–111` (`observing`), `state_rakes_test.dart:1368`
  и `:1507` (`hasLength(8)`), README `solo:355`. README `flutter_solo`: `:58`,
  `:203`, `:375`, `:663`, `:674`. `solo_cancel_reason.dart:5` и `:43–48`,
  `reference.md:177`, `doc_snippets.py:279` — всё верно. Сторож имён
  `doc_snippets.py` краснеет при генерации, как и сказано в задаче 7.
- **Ожидания тестов** на прототипе с наблюдателем
  `JobObserver with JobAnswerer` и `ReplacedCancelReason`.
  - Время старта в `restart`: обычный `await` и `ctx.join` — 100 мс,
    `ctx.abandonable` и `ctx.pause` — 10 мс.
  - Трассы: `restart` с `pause` — `s1 s3 e3`; `sequential`, когда реакция сама
    пишет, — `s1 e1 s2 e2 s3 e3`; `restart`, когда реакция сама пишет, — каждая
    отменяется `replaced`, без ошибок.
  - Синхронный бросок `listener` уходит в `takeException`, следующая реакция
    идёт (Review Focus 1). Запись из `listenWhen` приходит следующей парой
    `0>1`, `1>2`, реакции на 1 и 2 (Review Focus 4). Контроллер, закончивший
    закрытие, с первой сборки не даёт ни ошибки, ни реакции (Review Focus 5).
  - Новый контроллер в `sequential` стартует после отменённой реакции старого —
    на 100 мс.
- **Тело `(ctx) async => widget.listener(ctx, context, state)`** проходит
  `dart analyze --fatal-infos` под правилами пакета.
- **Решения плана.** «`listener` читается в начале тела» совпадает с «в момент
  старта» дизайна: тело стартует на микрозадаче после создания задачи, и для
  ждущего это момент его старта. Перенос dartdoc причин отмены в задачу 7
  продолжает ответ владельца по `vs-bloc` и дизайну не противоречит. Цена
  переноса: на pub.dev dartdoc `ReplacedCancelReason` останется старым
  до следующего выпуска `solo`, и сказать это стоит в «Unreleased».
- **Review Focus.** Пять случаев разумны и проверяемы. Упущены случаи
  из находок 2 (две записи в одном ходе в `restart`), 3 (`droppable` при смене
  контроллера) и 10 (смена `mode` на `keepLatest`/`restart` при ждущих).

### Вердикт ревьюера

Конструкция плана верна. Задачи покрывают дизайн, ожидания трасс и времени
сходятся с зондами, оверрайды и `floor` переживают коммит задачи 3. Исполнять
можно после правок по находкам 1–6. Находка 1 краснит первый же коммит. Находка
2 — ошибка, которую тесты плана не поймают. Находка 3 — расхождение с дизайном,
нужно решение. Находки 4–6 — гейт и порядок вливания. Находки 7–11 правятся
в тексте. Владелец нужен только для находки 3, если исполнитель выберет вариант
(б) или формулировка дизайна «ждут» должна остаться.

Вердикт: правки по находкам 1–11 внесены этим же коммитом; по находке 3 выбран
вариант (а), владелец не нужен. Цена переноса причин отмены названа в Global
Constraints.

### Что ревьюер запускал

- `git merge --ff-only main` — копия на `713a0fbf`.
- `dart pub publish --dry-run` в `packages/flutter_solo` с `solo: ^1.1.0`
  и оверрайдами у пакета и примера. Exit 65: одно предупреждение о грязном
  дереве зонда и hint об оверрайдах. Список архива включает
  `example/pubspec_overrides.yaml`.
- `dart test -r expanded` в `packages/solo` со спайковым `solo.dart`
  из `worktree-solo-listener-spike`: `+2243 -2`, оба падения —
  `reference_page_test.dart` (страница и перевод).
- `flutter test test/rv_probe_test.dart` в `packages/flutter_solo` — свои зонды
  P1–P10 на виджете прототипа, доработанном под план (наблюдатель
  `JobAnswerer`, `ReplacedCancelReason`, `listener` читается в теле),
  с временным оверрайдом `solo` на дерево: 12 из 12 зелёные, трассы приведены
  выше. P1 с обратным порядком (отмена до записи ждущего) — отдельным прогоном,
  `P1 []`. P10 — отдельным прогоном.
- `dart analyze --fatal-infos test/rv_widget.dart` — только длина двух строк
  зонда.
- Полный `archive_floor.py run` не гонял: `stage` на грязном дереве падает.
  Вывод о `floor` сделан по коду скрипта, по составу архива из dry-run
  и по тому, что в октябре оверрайды `flutter_solo` и примера жили при этом
  задании.
- Зонды и временные `pubspec_overrides.yaml` удалены, `solo.dart`
  и `pubspec.yaml` восстановлены копией, `flutter pub get` перезапущен.
  `git status --porcelain` пуст, ничего не закоммичено.
