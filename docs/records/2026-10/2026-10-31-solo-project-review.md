> **Состояние на 2026-10-31:** ревью проведено, у каждой находки стоит
> вердикт с итогом. Принятые сделаны в коммите «fix: settle the public API
> of 1.0.0 after the Fable review», отказы — решения 139–143
> в `docs/settled.md`.
> **Что это:** полное ревью `solo` и `flutter_solo` перед выпуском 1.0.0
> одним ревьюером на Fable: оценки, находки B, C, D и A, читаемость каждой
> страницы.
> **Связанные записи:** `2026-10-31-async-job-project-review.md` (то же
> ревью ядра, там же задание целиком), `2026-10-31-fable-review-wave-report.md`
> (волна правок по обоим), `2026-10-30-one-zero-report.md` (подготовка
> 1.0.0, на которой шло ревью).

# Полное ревью `solo` и `flutter_solo` перед 1.0.0: Fable

## Как это делалось

Вторая половина ревью, о котором `2026-10-31-async-job-project-review.md`:
то же дерево на `f713234c`, ревьюер Fable 5.1 в своём клоне, то же задание
с другой областью. Задание этой половины расходится с заданием ядра в восьми
строках, они — в конце записи.

Как я принимал — так же: находки сверены с деревом, принятые держит новый или
исправленный тест, отказы сверены по чтению. Ревьюер сам отдавал страницы
субагентам и сверял их находки, это он говорит в первом абзаце отчёта.

Ниже — отчёт ревьюера без правок прозы.

Клон на `f713234c`, ветка `main`. Работал только в клоне; отслеживаемые файлы
не менял, коммитов нет. Конфликт правил: `AGENTS.md` велит начинать
с `docs/handoff.md`, обновлять его и коммитить документы с работой; задание
запрещает читать handoff и коммитить — выполнил задание, handoff не читал,
ничего не коммитил. Четыре страницы-ревьюера (субагенты) читали `doc/`
по разделам; их цитаты и находки сверял по тексту страниц и по коду сам,
в отчёт вошло только сверенное, доказательство у каждой находки названо.

## 1. Оценка

**Общая 8/10.** Движок, который делает ровно то, что обещает, и обещание
записано: девять мутаций в ядре и виджетах все пойманы набором, зонды
на привычные ошибки показали ровно то, что говорят dartdoc и страницы. Опускают
оценку не дефекты — их не нашёл, — а цена чтения: документация длинная
и плотная, термины движка опережают свои определения, и три привычные ошибки
агента остаются тихими.

**Код 9/10.** Корректность, порядок событий, реентерабельность слушателей
и хуков, закрытие, очередь, правила — всё, что проверял зондами, сходится
с комментариями в коде, а комментарии объясняют причину каждого сторожа. Набор
тестов держит: мутации в `cancelWith`, `_reevaluate`, `addListener`,
`removeWhere`, `emit`, `SoloSelection`, `SoloSubscriptions`, `SoloSelector`
краснеют. Минус балл за C1 (трасса `Solo.debug` молчит о задаче, которую
правила не пустили на старт) и за B4/B5 (имя `Policy.replace` и сигнатуры
хуков, которые нельзя расширить без мажора).

**Документация 7/10.** Полная, честная, проверенная тестами (страничные тесты
держат текст, стенды — код и трассы), с «первыми попытками» вместо чучел. Но 11
360 строк на два пакета, `vs-bloc.md` — 1974, `jobs.md` — 828, страницы «для
каждого контроллера» на 600–800 строк, термины («answers for», «correction»,
«sealed») до их определения, и несколько неточностей там, где читатель
принимает решение (D1–D5).

**Для ИИ-агентов 7/10.** Агент-пользователь: тип ловит `ctx.run(Job(...))`
и `dispose()`, анализатор — забытый `super.close()` и `await job`, тексты
`ArgumentError` говорят, что сделать. Тихими остаются `await controller.load()`
(только `info`-линт), задача, которую правила отменили на старте (ни строки
в `Solo.debug`), и `Policy.replace`, прочитанный как `restartable`.
Агент-сопровождающий получает полные правила, но платит за них контекстом:
`docs/settled.md` — 1042 строки, которые надо прочесть целиком, `AGENTS.md`
на треть о переносах и архивах.

**`solo` 8/10.** Код 9, документация 7, API перед 1.0 в основном готов; четыре
вещи стоит решить до выпуска (B1–B5), ни одна не блокирует.

**`flutter_solo` 8/10.** Маленький пакет, каждый класс оправдан и защищён
от чужого кода (`removeListener`, который бросает; `addListener`, который
публикует). Минус — неточность README о `cancellable: false` под `close()` (D1)
и README на 704 строки для четырёх классов.

## 2. Сводка

- Дефектов поведения не нашёл: 23 зонда по привычкам, реентерабельности
  и закрытию совпали с dartdoc; девять мутаций — все красные.
- Библиотечный код `solo` и `flutter_solo` не менялся с 0.6.0; единственная
  ломающая правка — `ctx.wait` в ядре, оба `CHANGELOG.md` её называют. Разделы
  «Versions» говорят правду, но молчат о enum'ах и `sealed` (B1).
- Перед 1.0: сказать, что новое значение enum'а или вариант `SoloPending` —
  мажор (B1); сузить `SoloContext.each` до `SoloJob<void>` (B2); решить судьбу
  `package:solo/listeners.dart` в обещании (B3); взвесить имя `Policy.replace`
  (B4) и форму хуков `onError`/`SoloUnansweredHandler` (B5).
- Документация: неточна в двух местах о задаче `cancellable: false` в очереди
  под `close()` (D1), молчит о несовместимости `timeout` с `cancellable: false`
  (D2) и в четырёх местах пропускает `onUnanswered` в маршруте ошибки (D4).
- Для агентов: три тихие ошибки (A1–A3) и одна диагностическая дыра (C1).
- Страницы хуже остальных: `errors.md`, `accumulation-rules.md`, `jobs.md`,
  `state.md` — плотность и термины до определения.

## 3. Перед 1.0

**B1. Enum'ы и `sealed SoloPending` в обещании «Versions».** Место:
`packages/solo/README.md`, раздел «Versions»; `lib/src/pending.dart`, dartdoc
`SoloPending` («a `switch` over them is exhaustive»); `lib/src/policy.dart`,
`close_mode.dart`, `accumulator.dart` (`AccumulationPolicy`), `pending.dart`
(`SoloPhase`). Что не так: таблица «A new class, member or optional parameter —
minor» не говорит, чем считается новое значение `Policy`, `SoloPhase`,
`SoloCloseMode`, `AccumulationPolicy` или четвёртый вариант `SoloPending`.
Исчерпывающий `switch` у пользователя — а `diagnostics.md` и dartdoc
`SoloPending` его прямо советуют — перестаёт компилироваться. Что сломает
правка после выпуска: минорный релиз с новым значением сломает сборки,
и спорить будет не с чем. Что сделать сейчас: одна фраза в «Versions» обоих
README: «A new value of an enum or a new variant of a sealed class is a major
release». Доказательство: по чтению.

Вердикт: принято. Итог: строка «A new value of an enum or a new subclass of a
sealed class — a major release» в таблице «Versions» всех трёх README
и переводов; README `solo` называет `Policy`, `SoloPhase`, `SoloCloseMode`,
`AccumulationPolicy` и `SoloPending` и говорит, что `CancelReason` открыт.
Правило — и в `docs/conventions.md`. Коммит «fix: settle the public API of
1.0.0 after the Fable review», подробности
в `2026-10-31-fable-review-wave-report.md`.

**B2. `SoloContext.each` возвращает `Job<void>`, а `child` — `SoloJob<T>`.**
Место: `packages/solo/lib/src/job_context.dart`, `SoloContext.each`;
`_SoloContext.createEachJob` делает `_SoloJob`. Что не так: ребёнок `each` —
тот же `_SoloJob` с `isQueued`, но интерфейс отдаёт его как `Job<void>`;
сужение типа возврата у интерфейса, который README разрешает реализовать
вручную для мока, после 1.0 — «changed signature», мажор. Что сделать сейчас:
`SoloJob<void> each<T>(...)`. Доказательство: по чтению (`job_context.dart`,
строки интерфейса и `createEachJob`).

Вердикт: принято, слово владельца «Сузить до `SoloJob<void>`». Итог: интерфейс
`SoloContext.each`, `_SoloContext.createEachJob` и `each` возвращают
`SoloJob<void>`; тест «each hands back a SoloJob, as child does»
в `each_child_test.dart`; ломающее изменение названо в `CHANGELOG.md`. Коммит
«fix: settle the public API of 1.0.0 after the Fable review».

**B3. `package:solo/listeners.dart` в обещании.** Место:
`packages/solo/README.md` «Versions» («what `package:solo/solo.dart` and
`package:solo/listeners.dart` export»); `lib/src/listeners.dart`. Что не так:
`Listeners` — шов для `flutter_solo` («what `flutter_solo` notifies through as
well»), а не API контроллера; `reference.md` его не перечисляет. В обещании он
замораживает механику уведомления (`add`/`remove`/`clear`/`notify(report)`)
на всё 1.x. Что сломает правка после выпуска: любое изменение формы `notify`
или порядка — мажор `solo`. Что сделать сейчас: либо назвать в «Versions»
и `reference.md`, для кого библиотека («for a package that builds a delivery
over `Solo`»), либо вывести её из обещания явно. Доказательство: по чтению.

Вердикт: принято по первой ветке и наполовину: раздел «Versions» README `solo`
и перевод говорят, для кого `package:solo/listeners.dart`. В `reference.md`
строки нет: его «Other types» — экспорты `solo.dart`, так держит
`reference_page_test.dart`, решение 140 в `docs/settled.md`. Коммит «fix:
settle the public API of 1.0.0 after the Fable review».

**B4. Имя `Policy.replace`.** Место: `packages/solo/lib/src/policy.dart`. Что
не так: `replace` снимает только очередные дубликаты и не трогает идущую
задачу; идущую снимает `restart`. Читатель из bloc_concurrency (`restartable`)
и Riverpod берёт `replace` за «заменить текущую». Второй `replace` в том же
пакете — `AccumulationPolicy.replace` — значит другое (`join` плюс перенос
в хвост). Зонд: `test/probe_habits_test.dart`, H2 под `Policy.replace` — обе
загрузки дошли до `Done(null)`, состояние `Loaded(2)`, то есть двойная загрузка
вместо замены; под `Policy.restart` первая — `Cancelled(replaced)`. Что сломает
правка после выпуска: переименование — мажор. Что сделать сейчас: решить
осознанно; варианты — `replaceQueued`, или оставить и дать `restart` первым
в dartdoc `replace` («to cancel the running job too, see [restart]»). Dartdoc
сейчас точен, вопрос только в имени.

Вердикт: принято, слово владельца «да». Итог: `Policy.keepLatest`; первый абзац
dartdoc говорит, что в очереди ждёт только последняя задача с ключом, второй
называет `restart` для идущей. `ReplacedCancelReason`, `Cancelled(replaced)`
и `AccumulationPolicy.replace` остались. Коммит «fix: settle the public API of
1.0.0 after the Fable review».

**B5. Хуки с позиционными параметрами нельзя расширить.** Место:
`packages/solo/lib/src/solo.dart`,
`Solo.onError(job, error, stackTrace, {required answer})`, `Solo.onUnanswered`,
`onLog`, `onFinish`; `lib/src/observer.dart`, те же хуки `SoloObserver`
и typedef `SoloUnansweredHandler` (четыре позиционных). Что не так: `onChange`
уже получает объект `SoloTransition`, который можно растить минорами; `onError`
и `onUnanswered` — нет: любой новый параметр ломает каждое переопределение
и каждый обработчик. Что сломает правка после выпуска: добавить, скажем, фазу
или `heldCancellation` в отчёт об ошибке — мажор. Что сделать сейчас: либо
принять ограничение и записать его в «Versions» («hook signatures do not change
until 2.0»), либо завести объект отчёта для `onError` до выпуска.
Доказательство: по чтению.

Вердикт: оставлено, решение 139 в `docs/settled.md`.

Проверено и находкой не стало: `CHANGELOG.md` обоих пакетов — библиотечный код
с `solo-v0.6.0` не менялся (`git diff --stat` по `lib/` трёх пакетов: 2 файла
ядра, `engine.dart` и `job_context.dart`), единственная ломающая правка
`ctx.wait` названа в обоих; документационные пункты сходятся с диффом
(`README.md` 239 строк, `jobs.md` +293, `example/bin/quick_start.dart`,
`diagnostics.md`). Экспорты `solo.dart`, `listeners.dart`, `flutter_solo.dart`,
`listenable.dart` — те, что названы в «Versions». `SoloTransition`
и `SoloPendingJob` с `const`-конструкторами и именованными полями растут
минорами. Пол `async_job: '>=1.0.0 <1.1.0'` и `solo: ^1.0.0` в `flutter_solo`
соответствуют тексту «Versions».

## 4. Находки по коду

**C1. Low. Трасса `Solo.debug` молчит о задаче, которую правила не пустили
на старт.** Место: `packages/solo/lib/src/solo.dart`, `_pump`, ветка
`rejection != null` → `job._drop(Cancelled.by(reason: RulesCancelReason() …))`.
Что не так: очередная задача, снятая политикой, пишет `remove $this: …`; `emit`
вне `W` пишет «the rules cancel … at its next checkpoint»; а дроп на старте
не пишет ничего — читатель видит `enqueue Job(save)` и следом
`queue has no ready jobs` и делает вывод, что очередь пуста. Механика: `_debug`
стоит у броска правила (`rule of $job threw`) и у «ended while the rules were
asked», но не у отказа. Зонд: `test/probe_trace_test.dart` —
`enqueue<Loaded, void>` из `Empty` даёт `solo: enqueue Job(save)`,
`solo: queue has no ready jobs`; строка
`Job(save) finished: Cancelled(rules: is not Loaded)` приходит только
из `Job.debug`. `diagnostics.md` обещает, что `Solo.debug` «traces the queue of
the controller», а дроп — событие очереди. Предлагаю:
`_debug(() => 'drop $job: $rejection')` перед `_drop`.

Вердикт: принято, как предложено: в `_pump` перед `job._drop` строка
`drop $job: $cancelled`; тест «a job the rules turn down at its start is traced
as dropped» в `diagnostics_rakes_test.dart`. Коммит «fix: settle the public API
of 1.0.0 after the Fable review».

Проверено зондами и находкой не стало (`test/probe_mechanics_test.dart`,
`probe_cancel_test.dart`, `probe_habits_test.dart`): `externalSetState`
из слушателя и из `onChange` — переходы доставлены по порядку, ревизии растут
(`0->1@1, 1->2@2`); бросающий слушатель не останавливает остальных и уходит
в `onListenerError`; эмит ребёнка вне `W` родителя — родитель
`Cancelled(rules)`, ребёнок `Cancelled(parent)`, второй `emit` ребёнка
не выполняется, состояние — выданное; бросающий `SoloObserver` — ошибка в зоне,
задача `Done`; `close()` из слушателя во время `emit` — `Cancelled(closed)`,
`isFinished`, без assert'ов; `close()` ждёт идущую `cancellable: false`;
очередная `cancellable: false` под `close()` — `Cancelled(closed)`, под
`cancelAll()` — остаётся и выполняется (решение 50 в `docs/settled.md`); чужая
отмена через `await other.value` приходит со своей причиной
(`Cancelled(manual)`); дедлайн против `uncancellable` держится до конца секции;
`addListener` после `isFinished` — тихий no-op, `externalSetState` —
`StateError`; `emit` из сохранённого контекста —
`StateError('… has already finished, cannot emit')`; `SoloObserver.all`
с дубликатом — `ArgumentError`.

Качество тестов. Мутации (`.review-tmp/mutations.py`, правка — копия — прогон —
восстановление копией, итог `git status` чист): удалить отказ
`!cancellable && rejectable` в `_SoloJob.cancelWith` — 27 падений;
`_reevaluate` родители раньше детей — 5; `addListener` после закрытия
регистрирует — 2; `removeWhere` без удерживаемой задачи — 6; `removeWhere`
по живому списку — 86; `emit` без чекпоинта после записи — 6;
`SoloSelection._onSourceChanged` без сброса `_pickedFrom` — 1;
`SoloSubscriptions.add` берёт отменённую подписку — 1; `SoloSelector` без
`_subscribing` — 1. Каждая мутация поймана по имени нужного теста.

## 5. Находки по документации

**D1. Medium. `cancellable: false` в очереди под `close()`.** Место:
`packages/flutter_solo/README.md`, «The controller's life»: «`close()` cancels
whatever is queued or running. A running body stops at its next context call …;
a job made with `cancellable: false` turns the cancellation down and runs to
its end.» И `packages/solo/doc/reference.md`, «Parameters of a job», строка
`cancellable`: «`false` turns down manual cancellation, the parent's and
closing». Что не так: очередную такую задачу `close()` сбрасывает без вопроса,
бежит до конца только идущая. Читатель, поставивший `cancellable: false`
на очередной платёж и `close()` в `dispose`, потеряет платёж. Dartdoc `job`
(«once the job runs, `close`») и `cancellation.md` «A whole job» («`close()`
drops it from the queue too») точны; расходятся эти два места. Зонд:
`test/probe_cancel_test.dart`, K4 — `rename` с `cancellable: false` в очереди
за `connect`, `close()`: `rename: Cancelled(closed) renamed=0`; `cancelAll()`
вместо `close()`: `rename` дошла до `Done(null)`, `renamed=1`. Предлагаю:
в README — «a *running* job made with `cancellable: false` …; one still queued
is dropped»; в reference — формулировку dartdoc.

Вердикт: принято. Итог: README `flutter_solo` и перевод говорят, что идущая
задача с `cancellable: false` доходит до конца, а ждущая в очереди снимается;
строка `cancellable` в `reference.md` — то же. Сторож README держит обе
половины, новый тест «a queued job made with cancellable: false is dropped»
в `readme_rakes_test.dart` `flutter_solo`. Коммит «fix: settle the public API
of 1.0.0 after the Fable review».

**D2. Low. `timeout` требует `cancellable: true`.** Место:
`packages/solo/doc/reference.md`, строка `timeout`; `doc/cancellation.md`, «A
whole job» и «A deadline of a job» — разделы подряд, ни один не говорит, что
пара недопустима. Что не так: `enqueue(cancellable: false, timeout: …)` бросает
`ArgumentError` на вызове метода, а не в теле. Зонд: `probe_cancel_test.dart`,
K3 — «Invalid argument(s) (timeout): needs a cancellable job, and cancellable:
false refuses the cancellation the deadline makes». Предлагаю: фразу в «A whole
job» и в строку `timeout`.

Вердикт: принято: «A whole job» в `cancellation.md` и строка `timeout`
справочника называют `ArgumentError`. Коммит «fix: settle the public API of
1.0.0 after the Fable review».

**D3. Low. Секция держит и дедлайн.** Место: `doc/cancellation.md`, «One
section for the step»: «Manual cancellation, parent cancellation and closing
are held while an `uncancellable` action runs.» Вступление страницы считает
запросов четыре, с дедлайном. Зонд: `probe_cancel_test.dart`, K2 —
`timeout: 20 ms`, `uncancellable` на 100 ms, `emit` после секции: исход
`Cancelled(timeout)`, состояние `0`, то есть дедлайн лёг только у чекпоинта
после секции. Предлагаю: «and a deadline» в перечень.

Вердикт: принято: «and a deadline» в перечне. Коммит «fix: settle the public
API of 1.0.0 after the Fable review».

**D4. Low. Маршрут ошибки без `onUnanswered`.** Место: `doc/cancellation.md`,
«Ordinary await and context lifetime» («told to the controller's `onError` hook
and then handed to `Solo.unansweredHandler`, or to the zone») и «Cancellation
details» («to the `onError` hook, and on to `Solo.unansweredHandler` or the
zone»); `doc/resources.md`, «When the release happens» и «Cleanup order and
late results», те же слова. Что не так: между `onError` и `unansweredHandler`
стоит `Solo.onUnanswered`, и его переопределение перехватывает ошибку
(`_SoloJobObserver.onUnanswered` → `_solo.onUnanswered` → обработчик);
`errors.md` маршрут даёт верно. Читатель с переопределённым `onUnanswered`
решит, что ошибки cleanup его минуют. Доказательство: по чтению (`solo.dart`,
`_SoloJobObserver.onUnanswered`, `Solo.onUnanswered`). Предлагаю одну формулу
на обеих страницах: «to `onError`, then to `onUnanswered`, which by default
hands it to `Solo.unansweredHandler` or the zone».

Вердикт: принято, формула ревьюера на всех четырёх местах обеих страниц
и в переводах; цитаты сторожей в `resources_rakes_test.dart` подогнаны. Коммит
«fix: settle the public API of 1.0.0 after the Fable review».

**D5. Low. `keepWhile`, спрошенный на старте, идёт тем же путём, что
`canStart`.** Место: `doc/errors.md`, таблица «Where each error goes», строка
«An error of a start rule: `canStart` throws instead of answering». Что не так:
`_rejectStart` после `canStart` зовёт `_rejectKeep`, и бросивший на старте
`keepWhile` даёт тот же `Failed`. Доказательство: по чтению (`job.dart`,
`_rejectStart`). Предлагаю: «`canStart`, or `keepWhile` asked at the start,
throws».

Вердикт: принято. Итог: строка таблицы называет `keepWhile`, спрошенный
на старте; новый случай «a keepWhile asked at the start throws»
в `errors_rakes_test.dart` держит её поведением. Коммит «fix: settle the public
API of 1.0.0 after the Fable review».

**D6. Low. `streams.md` советует отменить ребёнка «чтобы остановить только
подписку», а показанный `track()` возвращает `.value`.** Место:
`doc/streams.md`, «A child that owns the subscription»: «retain the returned
job and call its `cancel()` to stop only this subscription» и через два абзаца
«An uncaught `Cancelled` from the child's `.value` does cancel the parent
through its body». Что не так: в показанном коде отмена ребёнка отменит
и родителя. Доказательство: по чтению. Предлагаю соединить: «to stop the
subscription and keep the job running, await `.done` rather than `.value`, or
catch the `Cancelled`».

Вердикт: принято вместе с B2: страница говорит, что `ctx.each` возвращает
`SoloJob<void>`, и советует телу ждать `.done`, а не `.value`, чтобы остановить
только подписку. Коммит «fix: settle the public API of 1.0.0 after the Fable
review».

**D7. Low. `first: true` названо там, где его нет.** Место: `doc/vs-bloc.md`,
«Ordering updates to shared state» → Solo: «`first: true` puts a job ahead of
what is waiting». `first` есть у `enqueueJob`, у `enqueue`, которым написана
страница, — нет. Доказательство: по чтению (`solo.dart`, сигнатуры `enqueue`
и `enqueueJob`). Предлагаю: «`enqueueJob(…, first: true)`».

Вердикт: принято: «`enqueueJob` with `first: true`». Коммит «fix: settle the
public API of 1.0.0 after the Fable review».

**D8. Low. `with SoloStream` ради стенда.** Место: `doc/vs-bloc.md`,
`PlayerController` («Restarting one operation within a shared queue»)
и `ReportController` («Reacting to an independent external state change») —
единственные два контроллера страницы с миксином, и `.stream` на странице
не читается нигде; миксин нужен драйверу `tool/doc_snippets.py` для трассы.
Читатель из bloc решит, что `Policy.restart` или `externalSetState` требуют
`SoloStream`. Доказательство: по чтению (grep `with SoloStream` и `.stream`
по странице). Предлагаю: слушать в стенде через `addListener` и убрать миксин
из текста, либо одна фраза «the stream is for the trace under the block».

Вердикт: принято по второй ветке: фраза после каждого из двух контроллеров
говорит, что `with SoloStream` даёт стрим, из которого читается трасса. Коммит
«fix: settle the public API of 1.0.0 after the Fable review».

**D9. Low. `jobs.md` говорит о `queue`, `current`, `lastJobWhere` как о вызовах
«on the controller».** Место: `doc/jobs.md`, «Working the queue directly». Все
три `@protected`; снаружи есть только `cancelAll()`. Агент, вызвавший
`controller.queue.clear()` из виджета, получит лишь предупреждение анализатора,
и код будет работать. Доказательство: по чтению (`solo.dart`). Предлагаю фразу:
«All three are protected: a method of the controller works the queue, a caller
sees `cancelAll()`».

Вердикт: принято. Коммит «fix: settle the public API of 1.0.0 after the Fable
review».

**D10. Low. `children.md` использует `_Op.sync`, `_Op.upload`, `_Op.trySync`
без объявления.** Место: `doc/children.md`, вступление (объявлены только `api`,
`analytics`, `Ready`); `jobs.md` объявил `_Op` с другими членами.
Доказательство: по чтению. Предлагаю добавить `_Op` в фразу-объявление.

Вердикт: принято: `_Op` объявлен во вступлении `children.md`. Коммит «fix:
settle the public API of 1.0.0 after the Fable review».

**D11. Low. `accumulation.md` не говорит, почему поле `late final`.** Место:
`doc/accumulation.md`, «Recipes» («Create it once in your controller, then call
its `add(event)`»). `accumulate`/`collect` — методы экземпляра:
`final _q = accumulate(…)` не компилируется, а `accumulate(…).add(t)` внутри
метода компилируется и молча ничего не склеивает (`_candidate` ищет группу
по `identical(group._owner, this)`). Сказано только в конце
`accumulation-rules.md` и в `reference.md`. Доказательство: по чтению
(`accumulator.dart`, поиск кандидата). Предлагаю фразу в «Recipes».

Вердикт: принято: фраза в «Recipes» о поле `late final` и о том, что накопитель
на каждый вызов ничего не группирует. Коммит «fix: settle the public API of
1.0.0 after the Fable review».

**D12. Low. `reference.md` неполон против «Versions».** Место:
`doc/reference.md`, «Other types»: нет `SoloUnansweredHandler`, `SoloPhase`,
полей `SoloPendingJob`, `Listeners` из `package:solo/listeners.dart`, а README
считает всё это публичным API; строка `cancelAll()` без `force:`/`reason:`.
Доказательство: по чтению. Предлагаю строки или оговорку «this page covers
`package:solo/solo.dart`».

Вердикт: принято, кроме `Listeners`: строки `SoloUnansweredHandler`,
`SoloPhase`, поля `SoloPending` и `force`/`reason` у `cancelAll()`.
`Listeners` — решение 140 в `docs/settled.md`. Коммит «fix: settle the public
API of 1.0.0 after the Fable review».

**D13. Low. `camera.md`: где именно отменяет первая попытка.** Место:
`doc/camera.md`, «Opening the camera / The first attempt»: «The body's first
`emit` leaves it, and the job ends `Cancelled` before `hw.open` is ever
called». Собственный `emit` правилами своей задачи не проверяется
(`_reevaluate(except: emitter)`); бросает следующий чекпоинт — `join`.
Доказательство: по чтению (`solo.dart`, `_reevaluate`; `job_context.dart`,
`emit`) и зонд M3 (`probe_mechanics_test.dart`: `emit` вне `W` возвращается,
если никто не отменил задачу внутри записи). Предлагаю: «at the `join` on the
next line, the next checkpoint».

Вердикт: принято: страница называет `join` следующей строки контрольной точкой,
которая отменяет задачу; цитата в `camera_rakes_test.dart` подогнана. Коммит
«fix: settle the public API of 1.0.0 after the Fable review».

**D14. Low. `mixins.md` приписывает сочетанию то, что делает один
`SoloStream`.** Место: `packages/flutter_solo/doc/mixins.md`, «A controller
with both deliveries»: «On a controller with both, an `await for` over the
`stream` holds `close()`». Это свойство `SoloStream` (`SoloPendingStream`).
Доказательство: по чтению (`solo_stream.dart`). Предлагаю: «On any controller
with `SoloStream`».

Вердикт: принято с другой формулой: «With `SoloStream`, with `SoloListenable`
or without it». Коммит «fix: settle the public API of 1.0.0 after the Fable
review».

**D15. Low. `errors.md` про «the zone» во Flutter.** Место: `doc/errors.md`,
вступление: «in the root zone an uncaught error can end the application».
Во Flutter это `PlatformDispatcher.onError`, приложение не падает; страница
не говорит. Доказательство: по чтению. Предлагаю фразу со ссылкой на README
`flutter_solo`, «Outcomes».

Вердикт: принято без ссылки: `check_links.py` не пускает страницу `solo`
ссылаться на `flutter_solo`, поэтому фраза называет README `flutter_solo`
словами. Коммит «fix: settle the public API of 1.0.0 after the Fable review».

## 6. Что сделать для 10/10

**Общая 8 → 10.** (1) Закрыть B1–B5 до выпуска: снимает единственный риск,
который после 1.0 стоит мажора, +0.5. (2) Сократить и разрезать четыре плотные
страницы (раздел 7) и ввести термины до их употребления, +1. (3) Закрыть три
тихие ошибки агента A1–A3 и C1, +0.5.

**Код 9 → 10.** (1) C1 — строка `drop $job: $rejection` в `_pump`, +0.5. (2)
B5 — объект отчёта для `onError`/`onUnanswered` или записанное ограничение,
+0.25. (3) B4 — имя `Policy.replace` решено осознанно, +0.25.

**Документация 7 → 10.** (1) D1–D5 — точность там, где читатель принимает
решение, +0.75. (2) `jobs.md`: рецепты (пауза, таймер, лайки) на отдельную
страницу, базовое — до 400 строк, +0.5. (3) `state.md`: «A delivery of your
own» и трасса вложенной записи — в подраздел для авторов доставки, +0.5. (4)
`errors.md`: первую таблицу — в три абзаца, зоны — под вторую таблицу, `load()`
показать один раз, +0.5. (5) `accumulation-rules.md`: четыре слова (appears /
ready / sealed / started) определить в начале и держать; «Start, cancellation
and errors» разбить подзаголовками, +0.5. (6) Единый абзац «что принадлежит
приложению» на каждой странице `doc/` (`_Op`, `Ready`, `api`, `CancelToken`),
+0.25.

**Для ИИ-агентов 7 → 10.** Пользователь: (1) A1 — фраза
«`await controller.load()` compiles and waits for nothing» в README обоих
пакетов и в `mistakes.md`, +0.5; (2) A2 — раздел «A job the rules turn down
ends `Cancelled`, not `Failed`» в `mistakes.md` плюс C1, +0.5; (3) A3 —
`restart` первым в dartdoc `replace`, +0.25; (4) A4 — `emit` из `catch` как
второй Don't в «Letting cancellation through a catch», +0.25. Сопровождающий:
(5) оглавление `docs/settled.md` по областям с номерами решений в первых
тридцати строках, чтобы агент читал целиком только свою область, +0.5; (6)
в `AGENTS.md` раздел о переносах сжать до правила и команды, остальное —
в `--help` скрипта, +0.25; (7) в `docs/conventions.md` одна строка «правка
публичного члена = `reference.md` + страничный тест + перевод», +0.25.

**`solo` 8 → 10.** B1–B5, C1, D2–D13, страницы из раздела 7.

**`flutter_solo` 8 → 10.** (1) D1, +0.5. (2) README: «Listening without keeping
the callback» и «Methods from a second import» — на страницу `doc/`, README
до ~450 строк, +0.75. (3) D14 и три правки `testing.md` из раздела 7, +0.25.
(4) Строка «equal states are not filtered» — в таблицу способов следить,
а не только в «Notes», +0.5.

## 7. Страницы

| Страница | Читаемость | Почему | Что сделать для 10 |
| --- | --- | --- | --- |
| `solo/README.md` | 8 | Quick start в экран, «The dozen calls», «Why `currentState`», таблицы гидов и рецептов; «Versions» — три абзаца прозы после таблицы | Фраза о `await controller.load()` (A1); «Versions» — таблица плюс два абзаца; B1 |
| `solo/doc/jobs.md` | 6 | 828 строк для первой страницы; базовое кончается на ~400, дальше три рецепта со своими типами; `then`/`shared()` до введения; зоны на первой странице; `camera`, `store`, `CancelToken` не объявлены | Рецепты — отдельно; `then` — в `children.md`; абзац о зонах — фраза и ссылка; объявить заглушки; D9 |
| `solo/doc/state.md` | 6 | Две таблицы об одних правилах на 80 строках; 150 строк о порядке слушателей и контракте `publish` в обязательной странице; «correction», «permission» без ввода; три домена | Одна таблица; «A delivery of your own» — в конец или в diagnostics; определить «correction» один раз; упомянуть строку `Solo.debug` об `emit` вне `W` |
| `solo/doc/children.md` | 7 | «Steps in a row» с дедлоком и строкой `Solo.debug` — лучший раздел; первый блок сразу с двумя детьми; таблица «Three ways to ignore a child» криптична; «adopted», «level», `JobAnswerer` | Первый пример — один `ctx.run`; таблицу — по ситуациям; убрать слова движка; D10; фраза `ctx.runAll` vs `Future.wait` |
| `solo/doc/streams.md` | 7 | 163 строки, две задачи, цитата ошибки; абзац из восьми фактов подряд; D6; `ctx.each` подписывается до возврата — не сказано, а на этом держится «The state first» | Абзац — таблицей; D6; фраза о синхронной подписке; упомянуть `Job.each` ядра как ловушку |
| `solo/doc/cancellation.md` | 7 | Таблица чекпоинтов в начале; сценарии из жизни; «Closing from a job»; 554 строки и шесть тем; хвост «Ordinary await…» — стена перечислений; `job` там значит `ctx.job` | Хвост — таблица по фазам, писать `ctx.job`; D2–D4 |
| `solo/doc/resources.md` | 8 | Лучшая структура: таблица «что освобождает и когда» до первого сценария, нумерованные разборы; «Second pass» без объяснения; D4 | Объяснить «Second pass» одной фразой; D4; пометить переход на фрагменты |
| `solo/doc/errors.md` | 6 | 665 строк; первая таблица — абзацы в ячейках; абзац о зонах между таблицами отвечает на незаданный вопрос; два одинаковых текста ссылок на разные страницы; «without its `isExpectedError`» четыре раза | Первую таблицу — в три абзаца; зоны — под вторую; показать `load()` один раз; D5, D15; разные тексты ссылок |
| `solo/doc/diagnostics.md` | 8 | Короткое вступление, четыре наблюдателя по нарастающей, таблица полей `SoloPendingJob`; «calls nothing on the way either» ни к чему не отсылает; `.timeout` на `close()` без слов, что закрытие идёт дальше | Переписать «either»; фраза «`.timeout` only reports»; C1 |
| `solo/doc/accumulation.md` | 7 | Четыре рецепта одной формы с трассами в миллисекундах; вступление выдаёт `then`/`shared()`/`merge` до первого `add`; порядок аргументов разный; D11 | Правила — под первый рецепт; D11; один порядок аргументов |
| `solo/doc/accumulation-rules.md` | 6 | Таблицы 3×3 и политик хороши; «Choosing when a group is ready» — 600 слов правил с одним числом; шесть слов на четыре события; «Start, cancellation and errors» — семь тем без подзаголовков | Определить четыре слова; подзаголовки; `startAtOnce: false` — временной линией; повторы снять |
| `solo/doc/camera.md` | 7 | Одна история, журнал у каждого решения, финальные фрагменты равны коду примера; 747 строк и тринадцать попыток; абзац о `reopen` с флагом — самый плотный; D13 | Абзац о `reopen` — списком из трёх шагов; вторую половину сжать; D13; `hw.onError` по имени |
| `solo/doc/testing.md` | 8 | Вступление по симптомам провала; деление «await» / `fakeAsync`; «Assertions inside a zone» — тест обещания движка, не пользователю; правило «mark by the microtask» без кода | Код Don't/Do для «held, drained, read `done` afterwards»; сократить «Assertions inside a zone»; `FakeCamera` — в текст или полный URL |
| `solo/doc/mistakes.md` | 8 | Короткая однородная форма, шесть из семи ловит `solo_lints`; первый раздел — две ошибки под одним заголовком; «Steps as children» — четыре метода словами; нет A1, A2 | Разделить первый раздел; две строки кода вместо преамбулы; добавить A1, A2, A4 |
| `solo/doc/reference.md` | 8 | Таблицы по «кто использует», полнота пяти классов держится `dart:mirrors`; D1, D2, D12; ячейки сжаты до непонятности вне контекста | D1, D2, D12; «Other types» разбить на enum'ы и классы |
| `solo/doc/vs-bloc.md` | 7 | Таблица-карта сценариев, честные первые попытки с ссылками на issue bloc, строки «What solo gives»; 1974 строки, второй абзац вступления спотыкает, справочник о `close()` при каждом трансформере внутри истории; D7, D8 | Переписать второй абзац вступления; абзац о трансформерах — в конец раздела Bloc; сценарий 8 сжать; D7, D8; в таблицу соответствий — фильтрация равных состояний и `BlocListener` → `listen` |
| `flutter_solo/README.md` | 7 | Таблица способов следить, «The controller as a `ValueListenable`», честный раздел о `listenable.dart`; 704 строки для четырёх классов; D1 | D1; два раздела — на страницу `doc/`; «equal states are not filtered» в таблицу |
| `flutter_solo/doc/mixins.md` | 8 | Три пункта во вступлении, таблица цепочек, короткое объяснение линеаризации; раздел 1 без трассы, хотя страница обещает; D14 | Трасса в раздел 1; D14; увязать с dartdoc-советом «`SoloStream` first» |
| `flutter_solo/doc/testing.md` | 8 | 108 строк, три правила, первая попытка в две строки; абзац о таймерах склеивает четыре случая; страница кончается самым трудным абзацем без правила; `FakeApi` без связи с `ProfileApi` | Разбить абзац о таймерах; последний абзац открыть правилом «two `pump()`»; «a `ProfileApi` of the test's own» |

Хуже остальных: `errors.md`, `accumulation-rules.md`, `jobs.md`, `state.md`.
Общая причина одна — плотность: термины движка и идиомы («answers for»,
«correction», «sealed», «adopted») раньше определения, по два-три факта
в фразе, справочные абзацы внутри историй. Длина сама по себе не беда
(`vs-bloc.md` на 1974 строки читается лучше `errors.md` на 665), беда — когда
обязательная страница смешивает базовое с продвинутым.

Вердикт: перестройка страниц из этого раздела и из раздела 6 ждёт внешних
читателей, решение 142 в `docs/settled.md`.

## 8. Для ИИ-агентов

**Агент-пользователь 7/10. Агент-сопровождающий 7/10.**

**A1. Medium. `await controller.load()` компилируется и ничего не ждёт.**
Место: `SoloJob` не `Future`; `packages/solo/README.md` пишет `.done` везде,
но не предупреждает; `mistakes.md` раздела нет. Механика: `await`
на не-`Future` разрешён языком. Зонд: `test/probe_lints_test.dart`,
`dart analyze` — `info … await_only_futures` (правило из `lints/core`, его
видят все с `lints`/`flutter_lints`, но это `info`, не ошибка). Предлагаю:
фраза в Quick start README и раздел в `mistakes.md`: «`await controller.load()`
compiles and waits for nothing — write `.done` or `.value`».

Вердикт: принято в README `solo` и переводе, а не разделом `mistakes.md`:
решение 143 в `docs/settled.md`. Коммит «fix: settle the public API of 1.0.0
after the Fable review».

**A2. Medium. Тихая отмена правилами.** Место: `enqueue<Loaded, void>`
из `Empty` → `Cancelled(rules: is not Loaded)`: ни исключения, ни `Failed`,
ни `onError`, ни `unansweredHandler`, ни строки в `Solo.debug` (C1). Агент
из Bloc/Riverpod, где событие либо обработано, либо упало, не найдёт причину.
Зонд: `probe_habits_test.dart`, H1 — `observer.onError: []`, `unanswered: []`,
`debug: [enqueue Job(save), queue has no ready jobs]`. Предлагаю: C1 и раздел
в `mistakes.md` «A job the rules turn down ends `Cancelled`, not `Failed`: read
`outcome`».

Вердикт: принято: абзац README `solo` о том, что отказ правил на старте
кончается `Cancelled` с `RulesCancelReason`, и строка `Solo.debug` по C1.
Раздела в `mistakes.md` нет, решение 143. Коммит «fix: settle the public API of
1.0.0 after the Fable review».

**A3. Low. `Policy.replace` вместо `Policy.restart`.** См. B4: зонд H2 под
`replace` — двойная загрузка, `Loaded(2)`, ничего не сообщено.

Вердикт: закрыто с B4.

**A4. Low. `catch (e) { ctx.emit(Failure(e)); }`.** Привычка Bloc. Зонд:
`probe_habits_test.dart`, H2 и H2b под `Policy.restart` — `catch` берёт
`Cancelled(replaced)`, второй `emit` бросает тот же `Cancelled`, исход
`Cancelled(replaced)`, состояние цело; тело, которое проглотило и вернулось
нормально, всё равно кончается `Cancelled(replaced)`. Поведение верное,
но агент видит «второй бросок из catch» и добавляет второй `catch`;
`mistakes.md` «Letting cancellation through a catch» показывает сброс железа,
а не `emit` из `catch` — самый частый вариант. Предлагаю второй Don't там же
с ответом `ifFailed`.

Вердикт: принято фразой в разделе о `catch` на `mistakes.md`, а не второй парой
Don't/Do: решение 143. Коммит «fix: settle the public API of 1.0.0 after the
Fable review».

**A5. Low. Накопитель, созданный на каждый вызов.** См. D11: компилируется,
молча не склеивает.

Вердикт: закрыто с D11.

Что ловится и говорит, как исправить (зонды `probe_habits_test.dart`,
`probe_lints_test.dart`): `ctx.run(Job(...))` — ошибка компиляции (`Job`
не `ChildJob`); `ctx.run(Job.deferred(...))` — `ArgumentError` «was not created
by this Solo (make it with job(...) or ctx.child of this controller)»;
`Policy.droppable` без ключа — «Policy.droppable requires a job key»;
`controller.dispose()` и `controller.state` — не компилируются; `close()` без
`super` — `must_call_super`; `c.increment().done;` без `await` —
`unawaited_futures`; `emit` из сохранённого контекста — «Job(keep) has already
finished, cannot emit»; `externalSetState` после закрытия — «has finished
closing, cannot set state»; `enqueue` после `close()` — не бросает, возвращает
`Cancelled(closed)`, `Solo.debug` пишет `enqueue Job(load): closed`;
`await load().done` из тела — виснет, `pending` печатает
`SoloPending([loadThenSave] in its body, 1 queued: [load])`, `Solo.debug` —
«enqueue Job(load) while Job(loadThenSave) is running: it starts after
Job(loadThenSave) ends» (решение 54, документировано).

**Ответ для агента-пользователя.** Что нужно для 10: A1, A2 и C1 — три правки,
после которых каждая тихая ошибка из зондов либо не компилируется, либо видна
в трассе, либо названа в `mistakes.md` (+2); B4 (+0.5); `mistakes.md` как
первая страница после README для агента — сейчас он идёт по таблице гидов
и на 828-строчном `jobs.md` теряет половину контекста (+0.5).

**Ответ для агента-сопровождающего.** Хватает ли: да, для верной правки
с первого раза есть всё — `AGENTS.md` (гейт, оверрайды, выпуск),
`docs/conventions.md` (страничные тесты с пометками первых попыток, стенды,
перевод в том же коммите, правило semver), `docs/architecture.md` (инварианты
и карта модулей), `docs/settled.md` (134 решения с причинами). Где ошибётся:
(1) правка dartdoc или страницы без страничного теста, перевода и `reflow.py` —
три файла на одну фразу, и ни один не рядом с правкой; (2) правка
`vs-bloc.md`/`accumulation.md` без `QUOTED`/`SAID` в `tool/doc_snippets.py`
и `check_traces.py` — узнает из CI; (3) правка нижнего пакета без оверрайдов —
`AGENTS.md` говорит, но правило живёт в разделе, который агент прочтёт после
того, как тесты верхнего соврут; (4) новый публичный член без строки
в `reference.md` — поймает `reference_page_test.dart`, но только для пяти
классов (D12). Что лишнее и тратит контекст: в `AGENTS.md` — подробности
переносов (список частиц, тире, кавычки, что делает скрипт с таблицами)
и описание раскладки `floor` на экран, оба уместнее в `--help` скриптов с одной
строкой-ссылкой; в `docs/settled.md` — отсутствие оглавления: агент, правящий
`flutter_solo`, обязан прочесть 1042 строки, из которых его — пять решений. Что
нужно для 10: оглавление settled по областям (+1), сжатие `AGENTS.md` (+0.5),
строка в conventions «правка публичного члена = reference + страничный тест
+ перевод» (+0.5), пункт «оверрайды» выше в `AGENTS.md`, перед гейтом (+0.5),
  памятка в `docs/conventions.md` о `QUOTED`/`SAID` рядом с правилом о стендах
  (+0.5).

Вердикт: советы сопровождающему из этого раздела — решение 141
в `docs/settled.md`.

## 9. Что хорошо и трогать не надо

- Сторожа в коде с причиной в комментарии: `_reportListenerError`,
  `_lastJobWhere` с двойным `_goingOn`, снимок в `removeWhere`,
  `_SoloSelectorState._follow`/`_unfollow`, `SoloSelection.addListener`
  с `_heardWhileSubscribing`. Девять мутаций — девять красных прогонов.
- `emit` как чекпоинт с обеих сторон; эмит вне `W` возвращается и пишет строку
  в `Solo.debug`, где стоит ошибка.
- Тексты исключений, которые говорят, что сделать
  (`make it with job(...) or ctx.child of this controller`;
  `needs a cancellable job,
  and cancellable: false refuses the cancellation the deadline makes`).
- `SoloPending` и его `toString`, который никогда не бросает.
- `currentState` вместо `state` (решение 48): `state` в теле не компилируется.
- Документация с первыми попытками, трассами и страничными тестами, которые
  держат текст; `mistakes.md` с линтами; `reference.md` с `dart:mirrors`.
- «Versions» в обоих README, с явным исключением протокола движка.
- `listenable.dart` вторым импортом с объяснённой причиной.

## 10. ПРОГОН

Все команды — из клона, через `rtk proxy`. Последняя строка вывода дословно.

- `git log --oneline -1` →
  `f713234c chore: prepare async_job, solo and flutter_solo 1.0.0`
- `git status --short` (в начале) → пусто
- `packages/solo`: `dart analyze --fatal-infos` → `No issues found!`
- `packages/flutter_solo`: `dart analyze --fatal-infos` → `No issues found!`
- `packages/solo/example`: `dart analyze --fatal-infos` → `No issues found!`
- `packages/flutter_solo/example`: `dart analyze --fatal-infos` →
  `No issues found!`
- `packages/solo`: `dart test -j 4` → `00:05 +2225: All tests passed!`
- `packages/flutter_solo`: `flutter test` → `00:01 +254: All tests passed!`
- `packages/flutter_solo/example`: `flutter test` →
  `00:00 +6: All tests passed!`
- `packages/solo/example`: `dart test` → `00:00 +112: All tests passed!`
- `packages/solo`:
  `dart format --output=none --set-exit-if-changed lib example/lib example/bin`
  → `Formatted 23 files (0 changed) in 0.04 seconds.` (exit 0)
- `packages/flutter_solo`:
  `dart format --output=none --set-exit-if-changed lib example/lib` →
  `Formatted 8 files (0 changed) in 0.01 seconds.` (exit 0)
- `git tag --list | tail -12` → `solo_lints-v0.1.3`
- `git diff --stat solo-v0.6.0 HEAD -- packages/solo/lib
  packages/flutter_solo/lib packages/async_job/lib` →
  `2 files changed, 4 insertions(+), 26 deletions(-)`
- `git diff --stat solo-v0.6.0 HEAD -- packages/solo packages/flutter_solo` →
  `41 files changed, 1800 insertions(+), 666 deletions(-)`
- `packages/solo`: `dart test test/probe_habits_test.dart -r expanded` — три
  прогона: под `Policy.droppable` (последняя строка
  `H10 finishes: [load: Cancelled(duplicate), load: Done(null)]`), под
  `Policy.replace` (`H10 finishes: [load: Done(null), load: Done(null)]`), под
  `Policy.restart`
  (`H10 finishes: [load: Cancelled(replaced), load: Done(null)]`); первый
  запуск не собрался: `Error: The argument type 'Job<Null>' can't be assigned
  to the parameter type 'ChildJob<dynamic>'` — заменил `Job(...)`
  на `Job.deferred(...)`
- `packages/solo`: `dart analyze test/probe_lints_test.dart` →
  `3 issues found.` (`must_call_super` warning, `await_only_futures` info,
  `unawaited_futures` info)
- `packages/solo`: `dart test test/probe_trace_test.dart -r expanded` →
  `solo: closed`
- `packages/solo`: `dart test test/probe_mechanics_test.dart -r expanded` → `M7
  threw: Invalid argument (observers): Instance of 'Thrower' comes twice and
  would hear every hook twice: Instance(length:2) of '_GrowableList'`
- `packages/solo`: `dart test test/probe_cancel_test.dart -r expanded` → первый
  прогон (K1–K3)
  `K3 threw: Invalid argument(s) (timeout): needs a cancellable job,
  and cancellable: false refuses the cancellation the deadline makes`; второй
  с `-N K4` → `K4 after cancelAll rename: Done(null) renamed=1`
- `python3 -I .review-tmp/mutations.py Mut1 Mut2 Mut3 Mut4a Mut4b Mut8`
  (в `packages/solo`, `dart test -j 4` на каждой) → `all restored`;
  по мутациям: Mut1 exit 1, 27 `[E]`; Mut2 exit 1, 5; Mut3 exit 1, 2; Mut4a
  exit 1, 6; Mut4b exit 1, 86; Mut8 exit 1, 6
- `python3 -I .review-tmp/mutations.py Mut5 Mut6 Mut7`
  (в `packages/flutter_solo`, `flutter test`) → `all restored`; Mut5 exit 1, 1
  `[E]`; Mut6 exit 1, 1; Mut7 exit 1, 1
- `git status --short` (в конце) → `?? .review-tmp/`,
  `?? packages/solo/test/probe_cancel_test.dart`,
  `?? packages/solo/test/probe_habits_test.dart`,
  `?? packages/solo/test/probe_lints_test.dart`,
  `?? packages/solo/test/probe_mechanics_test.dart`,
  `?? packages/solo/test/probe_trace_test.dart`

Не запускал: `dart pub publish --dry-run`, `tool/archive_floor.py`,
`python3 tool/reflow.py --check`, `tool/check_line_width.py`,
`tool/check_links.py`, `tool/check_translations.py`, стенды `snippets`; полный
`dart test` с моими зондами в наборе; зонды под `flutter_solo` (виджеты
проверял чтением и мутациями). Субагент-ревьюер страниц
accumulation/camera/testing/mistakes/reference сообщил о своих двух зондах
из `/tmp` (`collect` с `ifCancelled` из `onStart`; очередная
`cancellable: false` под `close()` и пара `cancellable: false` + `timeout`) —
их результаты совпали с моими K3/K4, но в этот список входят только мои
команды.

## Задание

Задание этой половины — задание `async_job` из записи
`2026-10-31-async-job-project-review.md` с такими строками вместо тамошних:

- заголовок: «Полное независимое ревью пакетов `solo` и `flutter_solo` перед
  выпуском 1.0.0»;
- отчёт и клон — свои;
- область: «**Твоя область — `packages/solo` и `packages/flutter_solo`:**
  у каждого `lib/`, `test/`, `example/`, `README.md`, `doc/*.md`,
  `CHANGELOG.md`, `pubspec.yaml`, `analysis_options.yaml`, `.pubignore`.
  `async_job` читать нужно, чтобы понимать механику, но находки о самом ядре
  вне рамок; находка о том, как `solo` пользуется ядром или как его документы
  пересказывают ядро, — в рамках. `solo_lints` вне рамок.»;
- оценки: к общей, коду, документации и для ИИ-агентов добавлены оценки каждого
  пакета, `solo` и `flutter_solo`, и в главном вопросе, и в пункте 4,
  и в разделе 1 отчёта;
- страницы: читаемость `README.md` и каждой страницы `doc/` пакетов `solo`
  и `flutter_solo`.
