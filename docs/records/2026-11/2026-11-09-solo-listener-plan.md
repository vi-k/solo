> **Состояние на 2026-11-09:** план написан по одобренному дизайну; ждёт
> независимого ревью и одобрения владельца; кода в пакетах нет.
> **Что это:** план работ по `Solo.addChangeListener` в `solo` и виджету
> `SoloListener` во `flutter_solo`: задачи, тесты, документы, порядок коммитов
> в ветке до выпусков.
> **Связанные записи:** `2026-11-09-solo-listener-async-design.md` (дизайн,
> одобрен владельцем 2026-11-09), `2026-11-09-solo-listener-design.md`
> (прежний дизайн и пробный прототип).

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

- **Ветка.** Работа идёт в ветке `solo-listener` от `main` и в `main`
  не вливается до коммитов выпуска — ответ владельца на вопрос 1 дизайна. Это
  исключение из правила «работай в `main`» `AGENTS.md` для этой работы. `push`
  ветки — только по слову владельца.
- **Две части ветки.** Задачи 1–2 — часть `solo`, она вливается в `main`
  с выпуском `solo` 1.1.0. Задачи 3–7 — часть `flutter_solo`, она вливается
  с выпуском `flutter_solo` 1.1.0. Коммиты части `solo` идут первыми, чтобы её
  можно было влить `--ff-only` по её последнему коммиту.
- **Ничто в части `solo` не называет `SoloListener`.** Архив `solo` 1.1.0
  выходит раньше виджета. Поэтому строка `vs-bloc.md` о `BlocListener` и правка
  dartdoc `ReplacedCancelReason` и `SoloCancelReason` со строкой справочника —
  в задаче 7, в части `flutter_solo` (решение плана, продолжение ответа
  владельца «строка с выпуском flutter_solo»).
- **Выпуск не в плане.** Версии в `pubspec.yaml` пакетов, коммиты `Release`,
  теги, `dart pub publish` — только по отдельному слову владельца.
- **Пол SDK** — `sdk: ^3.10.0`, Flutter 3.38.1: синтаксис не новее Dart 3.10.
- **`Listeners` не трогать.** `package:solo/listeners.dart` — публичный API,
  смена сигнатуры `add` — мажор. Список пар — свой, неэкспортируемый.
- **Оверрайды.** С задачи 3 у `packages/flutter_solo`
  и `packages/flutter_solo/example` — `pubspec_overrides.yaml` на дерево `solo`
  (первая строка — комментарий «до выпуска `solo` 1.1.0»). На `async_job`
  оверрайда нет, у пакетов линтов и `packages/solo/example` — тоже.
- **Проверки перед каждым коммитом кода** — из папки затронутого пакета:
  `dart format --output=none --set-exit-if-changed .`,
  `dart analyze --fatal-infos`, `dart test` (`flutter test`
  во `packages/flutter_solo`).
- **Документы.** Правка английского оригинала идёт с правкой перевода в том же
  коммите. Из корня: `python3 tool/check_translations.py`,
  `python3 tool/reflow.py --check`, `python3 tool/check_line_width.py`,
  `python3 tool/check_links.py`, `python3 tool/check_dartdoc.py`. Изменённые
  абзацы русских переводов прогоняются через скилл `humanizer--ru` без шага
  «Голос», правятся только `ERROR` его линтера.
- **Язык.** Код, комментарии, dartdoc, `CHANGELOG.md`, сообщения коммитов —
  по-английски; Conventional Commits.
- **Имена API** — ровно из дизайна: `addChangeListener`,
  `removeChangeListener`, `SoloListener`, `SoloListenerMode` с `concurrent`,
  `sequential`, `droppable`, `keepLatest`, `restart`; параметры `solo`,
  `listener`, `listenWhen`, `mode = SoloListenerMode.concurrent`, `child`.

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

---

### Task 1: подписка с парой в `solo`

**Files:**
- Create: `packages/solo/lib/src/change_listeners.dart` — список пар,
  не экспортируется ни одной библиотекой пакета.
- Modify: `packages/solo/lib/src/solo.dart` — поле рядом с `_listeners`
  (`:160`), `hasListeners` (`:207`), dartdoc `addListener` (`:213`), новые
  члены после `removeListener` (`:242`), `publish` (`:262–273`), `_finishClose`
  (`:928`), dartdoc класса (`:29`).
- Test: `packages/solo/test/change_listeners_test.dart`.

**Interfaces:**
- Produces:
  `void addChangeListener(void Function(S previous, S current) listener)`,
  `void removeChangeListener(void Function(S previous, S current) listener)`
  на `Solo<S>`; слушатели пары зовутся в `publish` после `addListener`.

- [ ] **Step 1: тесты.** Контроллер в тестах —
  `final class _Counter extends Solo<int>`
  с `void set(int next) => externalSetState(next);`. Группа
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
  - `a plain listener sees the pair's nested write in currentState` — следствие
    пункта 2 подписки: слушатель `addListener` на `1` пишет `2`, слушатель пары
    на `0>1` читает `currentState` → `2`;
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

- [ ] **Step 4: dartdoc.** `addChangeListener`, `removeChangeListener` — пункты
  1–4 подписки дизайна своими словами и отличие от `onChange(SoloTransition)`:
  там задача изменения и защищённый хук, здесь пара для любого, у кого есть
  контроллер. `addListener` — ссылка на пару для того, кому нужно каждое
  значение. Класс `Solo` (`:29`) и `publish` называют слушателей пары и их
  порядок. `SoloListener` нигде не назван.

- [ ] **Step 5:** весь набор `packages/solo` зелёный,
  `dart analyze --fatal-infos` чистый, `dart format` без изменений,
  `python3 tool/check_dartdoc.py` из корня зелёный.

- [ ] **Step 6: коммит**
  `feat(solo): add addChangeListener with the previous and the current state`.

### Task 2: документы `solo` о подписке с парой

**Files:**
- Modify: `packages/solo/doc/state.md` («Observing state»),
  `packages/solo/test/support/state_page.dart` (`observing`, `:97–111`),
  `packages/solo/test/state_rakes_test.dart` (группа «Observing state»,
  `:1368`), `packages/solo/doc/reference.md` («What a caller sees»),
  `packages/solo/test/reference_page_test.dart`, `packages/solo/README.md`
  (таблица задач, `:355`), `packages/solo/doc/vs-bloc.md` (строка `state`,
  `stream`), `packages/solo/CHANGELOG.md` («Unreleased», «Added»).
- Modify, переводы: `docs/ru/solo/state.md`, `docs/ru/solo/reference.md`,
  `packages/solo/README.ru.md`, `docs/ru/solo/vs-bloc.md`,
  `docs/ru/solo/CHANGELOG.md`.

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

- [ ] **Step 3: остальные места.** `reference.md` — строки обоих членов,
  `reference_page_test.dart` ждёт их; README — строка рядом с «A stream event
  arrives a microtask late»: «Every change with what it replaced, and a
  listener that reads the state misses one» → `addChangeListener` → ссылка
  на «Observing state»; `vs-bloc.md` — `addChangeListener` рядом
  с `addListener` в строке `state`, `stream`; `CHANGELOG.md` — «Added»
  в «Unreleased».

- [ ] **Step 4: переводы** всех пяти мест, `humanizer--ru` по изменённым
  абзацам.

- [ ] **Step 5: проверки.** `dart test` `packages/solo` зелёный; из корня —
  проверки документов из Global Constraints и стенд
  `python3 tool/doc_snippets.py "$TMPDIR/solo-doc-check"` (он собирает
  `vs-bloc.md`); `python3 tool/check_traces.py`, если блок `state.md` цитирует
  вывод.

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

Контроллер в тестах — `_Counter` из задачи 1. Реакция пишет в журнал `s<N>` при
старте и `e<N>` в конце, где `N` — её состояние. «Трасса режимов»: запись 1,
через 10 мс 2 и 3 подряд, реакция ждёт 100 мс через `ctx.pause`, часы двигаются
до конца.

- [ ] **Step 1: тесты.**
  - `no reaction on start`: виджет на контроллере в состоянии 5, `pump` →
    журнал пуст;
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
    старта реакции на 3 по часам `testWidgets` — обычный `await Future.delayed`
    и `ctx.join(() => Future.delayed(...))`: 100 мс;
    `ctx.abandonable(Future.delayed(...))` и `ctx.pause`: 10 мс;
  - `restart cancels with ReplacedCancelReason`: отменённая реакция видит
    `Cancelled` с причиной `ReplacedCancelReason`;
  - `a reaction writing to its own controller`: в `sequential` её запись встаёт
    в очередь за ней (реакции на 1, 2, 3 по очереди при записи `n + 1` до 3);
    в `droppable` отбрасывается; в `restart` отменяет саму реакцию;
  - `a mode change leaves living reactions alone`: `concurrent` с тремя идущими
    → `sequential` — три идущие доходят, следующая запись ждёт их; `sequential`
    с двумя ждущими → `droppable` — ждущие стартуют по одной;
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
  из `widget` в оповещении. Реакция —
  `Job<void>((ctx) async => widget.listener(ctx, context, state),
  describe: ..., observer: ...)`: `listener` читается в теле, то есть при
  старте реакции — так замыкание из `build` свежее и для ждущего (решение
  плана: «момент старта» дизайна — начало тела). `restart` — `keepLatest` плюс
  `cancel(const ReplacedCancelReason())` идущих, не дожидаясь. `build`
  возвращает `child`. `debugFillProperties` — `solo` и `mode`.

- [ ] **Step 4: dartdoc** `SoloListener` и `SoloListenerMode`: пример
  с задержкой через `ctx.pause`, пункты 2–8 «Поведения» своими словами, каждый
  режим с его трассой, запись реакции в свой контроллер по режимам,
  кооперативность отмены (`ctx.join` и обычный `await` ждут до конца), ссылка
  на `SoloBuilder` для того, что показывается.

- [ ] **Step 5:** набор `packages/flutter_solo` зелёный, анализ и формат
  чистые; `packages/flutter_solo/example` — `flutter analyze` и его тесты.

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
  отменённые старого контроллера остаются в множестве идущих, и реакции нового
  ждут их в режимах, кроме `concurrent`. Наблюдатель — один на состояние
  виджета, `final class _Reporter extends JobObserver with JobAnswerer`,
  `onUnanswered` зовёт
  `FlutterError.reportError(FlutterErrorDetails( exception: error,
  stack: stackTrace, library: 'flutter_solo',
  context: ErrorDescription('while running a reaction of SoloListener')))`.
  `done` реакции не читается: непрочитанный `Failed` доходит через тот же
  ответчик. `listenWhen` — под `try`, бросок → `FlutterError.reportError`
  с контекстом `'while calling listenWhen of SoloListener'`, изменение
  пропускается.

- [ ] **Step 4:** набор зелёный; ни один тест не оставляет таймера.

- [ ] **Step 5: коммит** `feat(flutter_solo): cancel SoloListener reactions
  with the screen and report their failures`.

### Task 5: README `flutter_solo`

**Files:**
- Modify: `packages/flutter_solo/README.md` — новый раздел после «Listening
  without keeping the callback» (`:375`), «Install» (`:58`), таблица «What the
  screen needs» (`:203`), «Notes» (`:663`);
  `packages/flutter_solo/README.ru.md`.
- Modify: `packages/flutter_solo/test/support/readme_widgets.dart`,
  `packages/flutter_solo/test/support/readme_install.dart`,
  `packages/flutter_solo/test/readme_rakes_test.dart` (`hasLength(17)`
  на `:180`, `hasLength(10)` у `arrivesWithOneImport` на `:344`),
  `tool/flutter_snippets.py`.
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
    бросить, токен через `ctx.onCancel`; сторож меряет время старта новой
    подгрузки.

  Прогон: красный, пока README не несёт блоков.

- [ ] **Step 2: раздел README** по форме страниц: требование, первая попытка,
  решения; две ловушки — подразделами одного раздела или двумя разделами,
  решает исполнитель. Граница раздела: результат своей операции — `job.done`,
  новость, переживающая экран, — доска `state.md` `solo`. Ни одна фраза
  не обещает, что уход или `restart` останавливает реакцию.

- [ ] **Step 3: другие места README.** «Install» называет `SoloListener` среди
  виджетов; `arrivesWithOneImport` — плюс `SoloListener<Object>`
  и `SoloListenerMode`, его `hasLength` — 12; `ownPart` берёт
  и `SoloListener<Object>`; сторож `_says` — новую фразу. Таблица «What the
  screen needs» — «A reaction to every change, cancelled with the screen» →
  `SoloListener`. «Notes»: строка «A listener or a reaction of `SoloListener`»
  → `FlutterError` (при любом контроллере); ответ «When do listeners run?» —
  реакции `SoloListener` идут на микрозадаче. `hasLength(17)` — новое число
  Dart-блоков.

- [ ] **Step 4: стенд.** В `tool/flutter_snippets.py` — драйвер каждого блока
  раздела; адресация по подразделу, как у «Listening without keeping the
  callback», если два блока объявляют одно имя.

- [ ] **Step 5: перевод и `CHANGELOG`.** `README.ru.md` — те же места,
  `humanizer--ru`; `CHANGELOG.md` и перевод — «Added» в «Unreleased».

- [ ] **Step 6: проверки.** `flutter test` `packages/flutter_solo`; из корня
  `python3 tool/flutter_snippets.py "$TMPDIR/solo-flutter-check"`
  и `python3 tool/check_traces.py`, документные проверки.

- [ ] **Step 7: коммит**
  `docs(flutter_solo): add the SoloListener section to the README`.

### Task 6: страницы тестов и миксинов

**Files:**
- Modify: `packages/flutter_solo/doc/testing.md`,
  `docs/ru/flutter_solo/testing.md`, `packages/flutter_solo/doc/mixins.md`,
  `docs/ru/flutter_solo/mixins.md`; при новом блоке кода —
  `test/support/testing_code.dart` или `testing_variants.dart`,
  `test/testing_rakes_test.dart` и `tool/flutter_snippets.py`.

- [ ] **Step 1:** если `testing.md` получает блок кода — сторож
  в `testing_rakes_test.dart` первым: реакция, пережившая виджет, на обычном
  `await Future.delayed` — тест без перевода часов краснеет на «A Timer is
  still pending»; с переводом часов или с `ctx.pause` — зелёный.

- [ ] **Step 2: `testing.md`** — пункт о реакции, пережившей виджет: она держит
  свой таймер; тест двигает часы, или реакция ждёт через `ctx.pause`.
  `mixins.md` — фраза «The builders of this package, `SoloBuilder` and
  `SoloSelector`, take any controller» называет и `SoloListener`. Переводы,
  `humanizer--ru`.

- [ ] **Step 3: проверки** — как в задаче 5.

- [ ] **Step 4: коммит** `docs(flutter_solo): say what a reaction that outlives
  the widget does to a test`.

### Task 7: места `solo`, которые называют виджет

**Files:**
- Modify: `packages/solo/lib/src/solo_cancel_reason.dart` (dartdoc
  `SoloCancelReason` `:5` и `ReplacedCancelReason` `:43–48`),
  `packages/solo/doc/reference.md` (`:177`), `docs/ru/solo/reference.md`,
  `packages/solo/doc/vs-bloc.md`, `docs/ru/solo/vs-bloc.md`,
  `tool/doc_snippets.py` (`:279`), `packages/solo/CHANGELOG.md`,
  `docs/ru/solo/CHANGELOG.md`.

- [ ] **Step 1: сторож имён первым.** В список имён `flutter_solo`, которые
  называет `vs-bloc.md`, в `tool/doc_snippets.py` —
  `('class SoloListener', 'solo_listener.dart')`; комментарий над списком
  «names three things» → «four». Стенд краснеет, пока строки в `vs-bloc.md`
  нет.

- [ ] **Step 2: `vs-bloc.md`.** Отдельная строка «`BlocListener` for a change
  this screen did not make» → `SoloListener`, с отменой реакции; строка
  «`BlocListener` for an operation's result» остаётся.

- [ ] **Step 3: причины отмены.** Dartdoc `SoloCancelReason` — причины `solo`,
  движков на нём и виджетов `flutter_solo`; `ReplacedCancelReason` — ещё
  и реакция `SoloListener` в `restart`, которую заменила более новая. Строка
  справочника `reference.md` — так же.

- [ ] **Step 4:** переводы, `humanizer--ru`; `CHANGELOG.md` `solo` и перевод —
  запись в «Unreleased» о dartdoc и строке `vs-bloc`.

- [ ] **Step 5: проверки.** `dart test` и анализ `packages/solo`;
  `python3 tool/doc_snippets.py "$TMPDIR/solo-doc-check"`;
  `python3 tool/check_dartdoc.py`; документные проверки.

- [ ] **Step 6: коммит**
  `docs: name SoloListener next to BlocListener and ReplacedCancelReason`. Этот
  коммит — часть выпуска `flutter_solo`.

### После задач

- Независимое ревью всей ветки на Opus, по своей копии дерева на ревьюера;
  находки с вердиктами — в отчёт `2026-11-NN-solo-listener-report.md`.
- Гейт целиком в копии на голове ветки: пять заданий CI локально, включая
  `floor` на `~/fvm/versions/3.38.1`.
- `docs/handoff.md`: ветка готова и ждёт выпусков; какой коммит закрывает часть
  `solo`.
- Шапки дизайна и плана — «сделано в ветке `solo-listener`, ждёт выпуска».
