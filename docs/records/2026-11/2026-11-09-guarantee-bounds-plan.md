> **Состояние на 2026-11-09:** план пересмотрен по независимому ревью Opus
> (11 находок, все приняты, вердикты в разделе «Ревью плана») и реализован:
> `7035e8ab`, `819f3ee4`, правки по ревью работы `e7208ad4`; влит в `main`.
> Отчёт — `2026-11-09-guarantee-bounds-report.md`.
> **Что это:** план третьей волны — абзацы `jobs.md`, `cancellation.md`
> и `state.md` `solo` и `outcomes.md` ядра о границах гарантий, со сторожами.
> **Связанные записи:** `2026-11-09-guarantee-bounds-design.md`.

# Границы гарантий solo: план

Дизайн — `2026-11-09-guarantee-bounds-design.md`. Слово владельца 2026-11-09
на три вопроса дизайна: «1. без раздела 2. да 3. да» — раздела `mistakes.md`
нет, абзац `outcomes.md` ядра идёт в этой волне, `state.md` без первой попытки.

## Общие условия

- Только документация и тесты; `lib/` не меняется.
- Английский оригинал и русский перевод — в одном коммите; переводы
  в `docs/ru/solo/` и `docs/ru/async_job/`, ссылки перевода — на русские якоря
  тех же разделов.
- Записи в «Unreleased»: у `packages/solo/CHANGELOG.md` — пункт плоского
  списка, подраздела там нет; у `packages/async_job/CHANGELOG.md` — пункт
  в «Documentation». С переводами.
- Сверка прозы на старой странице не находит новой фразы: сторож краснеет без
  абзаца. Поведенческие сторожа держат механику, которой абзац учит, и зелены
  сразу; что они умеют краснеть, проверяется мутацией ожидания.
- Проверки: `python3 tool/reflow.py --check`, `tool/check_line_width.py`,
  `tool/check_translations.py`, `tool/check_links.py`, `tool/build_site.py`;
  линтер `humanizer--ru` (только `ERROR`) на изменённых абзацах переводов;
  ширина записей — руками.
- Гейт пакетов `solo` и `async_job` из их папок: `dart format`,
  `dart analyze --fatal-infos`, `dart test` целиком.

## Задача 1. `jobs.md`: что `Cancelled` не говорит

**Где.** `packages/solo/doc/jobs.md`, «Jobs and results», сразу после абзаца «A
failed job does not stop the queue… none of them says that anything failed.».

**Текст** (два абзаца):

> Nor does `Cancelled` say that nothing happened. An outcome tells how the job
> ended, not what its work did outside the controller. `Cancelled` with
> `started: false` means the body never ran. With `started: true` it says
> nothing about an action the body was waiting for: the action `ctx.join`
> waited for has ended, whether it went through or failed, and the outcome
> does not tell which; the action `ctx.abandonable` let go of may go through
> after the outcome; and `Policy.restart` cancels a job in the middle of its
> action, and the job that replaces it makes the call again. A caller that
> repeats a payment because it ended `Cancelled` may pay twice.
>
> A job whose outcome has to tell what its action did refuses cancellation:
> `cancellable: false`, the whole state type as its working type and no
> `keepWhile`, as [A whole job](cancellation.md#a-whole-job) on the
> cancellation page puts it. Once such a job has started, no request and no
> rule of its working type cancels it: it ends `Done` or `Failed`, unless its
> own body gives up — a `stateAs` that finds another state, or a `Cancelled`
> it throws or lets out of a child. Such a job turns down `Policy.restart` as
> well: the newer call waits for it, then runs and makes the call again.
> Otherwise the record of the work is what the job writes inside an
> `uncancellable` section, such as a receipt in the state, as
> [One section for the step](cancellation.md#one-section-for-the-step) shows.
> The record holds only in a job its rules cannot cancel: a section does not
> hold the rules back, and a payment the rules cut short leaves no receipt.
> Across restarts of the app, only an idempotent API of the service tells a
> second request from the first.

**Сторож** — `packages/solo/test/jobs_rakes_test.dart`, новая группа
`'What Cancelled does not say'`, контроллер с `OpenSolo` в самом тесте,
`fakeAsync` и `Completer` на каждое действие:

- `'join: an action that fails after the cancellation leaves Cancelled'` —
  исход `Cancelled(manual)`, `started: true`, ошибка действия не в исходе;
- `'join: an action that goes through leaves Cancelled'` — до конца действия
  `outcome == null`, потом `Cancelled(manual)`, платёж записан;
- `'abandonable: the action goes through after the outcome'` — исход есть
  раньше записи платежа;
- `'restart: the job that replaces it pays again'` — два платежа, первый исход
  `Cancelled(replaced)`;
- `'a section does not hold the rules back'` — секция с платежом, `keepWhile`,
  `externalSetState` вне правил во время платежа: `Cancelled`
  с `RulesCancelReason`, платёж прошёл, квитанции нет;
- `'cancellable: false over the whole state type ends Done'` — во время платежа
  `cancel()`, `close()`, `cancelAll(force: true)`, `externalSetState` и отмена
  родителя (задача ребёнком через `ctx.run`): `Done`, квитанция в состоянии;
- `'cancellable: false: a body that gives up still ends Cancelled'` — `stateAs`
  после платежа находит другое состояние: `Cancelled(rules: …)`,
  `started: true`;
- `'cancellable: false under restart: the newer call pays again'` — оба `Done`,
  два платежа;
- `'says what Cancelled does not say'` — сверка прозы:
  `Nor does \`Cancelled\` say that nothing happened.`,
  `the outcome does not tell which`,
  `no request and no rule of its working type cancels it`,
  `a section does not hold the rules back`.

## Задача 2. `cancellation.md` solo: исход ответа

**Где.** `packages/solo/doc/cancellation.md`, «One section for the step»,
последним абзацем подраздела — после абзаца о `ctx.heldCancellation`, который
кончается ссылкой ядра «why a step keeps its result whatever it says».

**Текст:**

> The job still ends `Cancelled`, with the reason the section held, though the
> payment has gone through: the receipt in the state says so, not the outcome.
> [Jobs and results](jobs.md#jobs-and-results) on the jobs page tells what an
> outcome does not say.

**Сторож.** Механику уже держат
`one section: the receipt reaches the state, the entry is written`
(`Cancelled(manual)`)
и `closing is held as well, and close() waits for the step`
(`Cancelled(closed)`). Новое — сверка прозы в `cancellation_rakes_test.dart`:
`the receipt in the state says so, not the outcome`.

## Задача 3. `state.md`: что делает `emit` вне `W`

**Где.** `packages/solo/doc/state.md`, «Reading and updating state», абзац
«`ctx.emit(next)` allows a job…», его список и абзац «So put such a transition
last…».

**Текст.** Список:

> - `ctx.abandonable`, `ctx.join` or `ctx.uncancellable` ends the job
>   `Cancelled` before its action starts, and `ctx.pause` before its timer;
> - `ctx.each` ends the job instead of starting a child the same rules would
>   refuse.

Абзац «So put such a transition last…» остаётся как есть, сразу за списком.
После него новый абзац:

> A job that does not end there is cancelled by its own rules, so its
> `ifFailed` and `ifCancelled` do not run, as
> [Handler eligibility and errors](#handler-eligibility-and-errors) has it,
> and the state stays what the emit wrote. A load whose working type is
> `Initial` and that writes `Loading` before it waits leaves the controller at
> `Loading` for good, and the next call of it is refused at its start: the
> state is no longer `Initial`. A job that goes on in the states it writes
> takes all of them as its working type, and `canStart` says where it may
> start, as `switchOn` above does;
> [Opening the camera](camera.md#opening-the-camera) on the camera page
> follows the mistake through, with its trace. With
> [`Solo.debug`](diagnostics.md#logs) set, such an emit is named as it writes,
> in a line that ends
> `which is not Initial: the rules cancel Job(load) at its next checkpoint`.

Блока ```text нет: тест диаграммы `the diagram of the page is the order a
nested change gets` берёт первый такой блок страницы, а у состояний профиля нет
`toString`, и строка целиком печатает `Instance of 'Loading'`.

**Сторож** — `packages/solo/test/state_rakes_test.dart`, группа раздела:

- `'a load narrowed to Initial is left at Loading and refused next'` —
  контроллер `Solo<stubs.ProfileState>` в тесте с методом `load()`,
  `enqueue<Initial, String>(key: 'load', …)` с `ifFailed`, `ifCancelled`,
  `emit(Loading)`, `ctx.abandonable(api…)`: `Cancelled(rules: …)`
  со `started: true`, состояние `Loading`, обработчики не позваны, второй
  вызов — `started: false`; строка `Solo.debug` кончается процитированным
  хвостом (`Solo.debug = lines.add`, сброс в `addTearDown`);
- `'after an emit outside W pause ends the job before its timer'` —
  `ctx.pause(const Duration(seconds: 1))` после `emit` вне `W`: после
  `flushMicrotasks` исход уже есть, `async.pendingTimers` пуст;
- `abandonable`, `join` и `uncancellable` уже держит
  `after an emit outside W a read or a wait ends the job`, `each` — свой тест;
- сверка прозы через `_page().replaceAll(RegExp(r'\s+'), ' ')`:
  `the state stays what the emit wrote`,
  `takes all of them as its working type`, хвост строки `Solo.debug`.

## Задача 4. `outcomes.md` ядра: исход задачи, а не её действий

**Где.** `packages/async_job/doc/outcomes.md`, «Reading the result», после
абзаца «`done` hands the outcome over… to acknowledge that choice.».

**Текст:**

> An outcome is the job's, not that of the work it waited for. `Cancelled`
> holds a `started` flag, and with `started: false` the body never ran. With
> `started: true` the outcome says nothing about what the actions of the body
> did outside the job: an action `ctx.join` waited out has ended, whether it
> went through or failed, and the job ends `Cancelled` all the same. A step
> that has to be kept whatever the outcome keeps its result inside the section
> that holds the cancellation back, as
> [Holding the cancellation back](cancellation.md#holding-the-cancellation-back)
> on the cancellation page shows.

**Сторож** — `packages/async_job/test/outcomes_rakes_test.dart`, группа
`'Reading the result'`, свой помощник `_prose()`:

- `'Cancelled with started: true after a joined action that went through'` —
  `Job` с `ctx.join` над действием на `Completer`, отмена во время действия:
  до конца действия `outcome == null`, потом `Cancelled(manual)`,
  `started == true`, действие выполнено;
- `'Cancelled with started: false: the body never ran'` —
  `Job.deferred<void>(…)`, отменённый до старта, тело не позвано,
  `started == false`;
- сверка прозы: `An outcome is the job's, not that of the work it waited for.`,
  `the job ends \`Cancelled\` all the same`.

## Задача 5. Переводы, списки изменений, документы

- Переводы четырёх правок: `docs/ru/solo/jobs.md`,
  `docs/ru/solo/cancellation.md`, `docs/ru/solo/state.md`,
  `docs/ru/async_job/outcomes.md`; код-спаны — как в оригинале.
- «Unreleased»: `solo` — `jobs.md` о том, чего `Cancelled` не говорит,
  `cancellation.md` об исходе секции, `state.md` об `emit` вне `W`; ядро —
  `outcomes.md` об исходе задачи. С переводами.
- Запись бэклога «Ловушка рабочего типа…» снимается; шапки дизайна и плана —
  реализовано; отчёт `2026-11-09-guarantee-bounds-report.md` — что сделано,
  ревью работы с вердиктами, проверки; `docs/handoff.md`.

## Порядок коммитов

1. Задачи 1–3 вместе с переводами и записью «Unreleased» `solo` — один коммит
   `docs(solo): …`; сторожа в нём же.
2. Задача 4 с переводом и записью ядра — `docs(async_job): …`.
3. Бэклог, шапки, отчёт, handoff — после ревью работы.

Дерево зелёное на каждом коммите: сторож и абзац идут вместе.

## Ревью работы

Независимое ревью Opus всей ветки после задачи 4, в своей копии: верность
каждого утверждения абзацев прогоном, сторожа умеют краснеть, переводы говорят
то же.

## Ревью плана

Независимое ревью Opus 2026-11-09 на `12833b5c`, в своей копии. Прогоном
ревьюер подтвердил: последствия `emit` вне `W` для профиля, `pause`
и `uncancellable` после него, `join`, `abandonable` и `restart` над платежом,
секцию против правил, `cancellable: false` против `cancel`, `close`,
`cancelAll(force: true)`, `externalSetState` и отмены родителя, оба утверждения
ядра. Чтением — якоря на обоих языках, «A whole job», охват `check_traces.py`
и `strayFences`, разделы «Unreleased». Ссылки находок Claude сверил своими
командами.

**1. Important.** Строка `Solo.debug` в плане неверна: состояния профиля без
`toString`, и `emit` печатает `Instance of 'Loading'`; сторож на равенство
не позеленел бы. Предложено цитировать хвост код-спаном и сослаться на «Logs».

Вердикт: принято. Задача 3 цитирует хвост, ссылка на `diagnostics.md#logs`,
сторож — `endsWith`.

**2. Important.** Новый блок ```text стал бы первым на странице, и тест
диаграммы, берущий первый блок, покраснел бы.

Вердикт: принято. Блока нет (находка 1); причина записана в задаче 3.

**3. Important.** «Once such a job has started, it ends `Done` or `Failed`»
неверно: `stateAs`, отмена ребёнка, выпущенная телом, и `Cancelled`, брошенный
телом, кончают задачу `Cancelled` со `started: true`.

Вердикт: принято. Текст задачи 1 — предложенный ревьюером; два новых сторожа
и расширенный третий.

**4. Minor.** Читатель может решить, что `cancellable: false` спасает
от двойного платежа под `Policy.restart`; не спасает.

Вердикт: принято. Фраза о `restart` во втором абзаце задачи 1 и сторож.

**5. Minor.** «has ended, gone through or failed» читается как три исхода.

Вердикт: принято. «has ended, whether it went through or failed» в задачах 1
и 4.

**6. Minor.** Тяжёлая фраза о записи работы в задаче 1.

Вердикт: принято. Две фразы, предложенные ревьюером.

**7. Minor.** «`ctx.pause` before its timer» без сторожа: существующий тест
сбрасывает таймеры.

Вердикт: принято. Отдельный тест в задаче 3.

**8. Minor.** Новый абзац между списком и «So put such a transition last…»
отрывает «So» от опоры; `ctx.run` и `ctx.runAll` после такого `emit` сначала
запускают ребёнка.

Вердикт: принято в части порядка: новый абзац встаёт после «So put…». Список
`run` и `runAll` не дополняется: он о методах, которые кончают задачу до своего
действия, а `run` и `runAll` сначала запускают ребёнка и к ним не относятся.

**9. Minor.** Два абзаца задачи 1 рвут нить об ошибках раздела.

Вердикт: оставлено, как допускает и ревьюер: «Nor» держится за «none of them
says that anything failed».

**10. Minor.** Абзац задачи 2 лучше ставить последним в подразделе, после
ссылки ядра о том же.

Вердикт: принято.

**11. Minor.** У `solo` нет подраздела «Documentation»; опечатка в пути;
не названы проверки `reflow --check`, `check_line_width.py`, `build_site.py`;
в `state_rakes_test.dart` нет `OpenSolo` и `_prose()`,
в `outcomes_rakes_test.dart` нет `_prose()`; сторожу задачи 4 нужна проверка
`outcome == null` до конца действия.

Вердикт: принято. Всё исправлено в разделах выше.
