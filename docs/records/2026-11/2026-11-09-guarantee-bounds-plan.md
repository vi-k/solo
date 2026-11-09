> **Состояние на 2026-11-09:** план, ждёт независимого ревью Opus; ничего
> не реализовано.
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
- Записи в «Unreleased» — `packages/solo/CHANGELOG.md`
  и `packages/async_job/CHANGELOG.md`, с переводами.
- Сторож пишется первым и краснеет на дереве без абзаца: сверка фразы на старой
  странице не находит её.
- Ширина 79, `python3 tool/reflow.py`; `tool/check_translations.py`,
  `check_links.py`, линтер `humanizer--ru` (только `ERROR`) на изменённых
  абзацах переводов.
- Гейт пакетов `solo` и `async_job`: `dart format`,
  `dart analyze --fatal-infos`, `dart test`; пакеты выше не затронуты, но набор
  `solo` гоняется целиком.

## Задача 1. `jobs.md`: что `Cancelled` не говорит

**Где.** `packages/solo/doc/jobs.md`, «Jobs and results», сразу после абзаца «A
failed job does not stop the queue… none of them says that anything failed.».

**Текст** (два абзаца):

> Nor does `Cancelled` say that nothing happened. An outcome tells how the job
> ended, not what its work did outside the controller. `Cancelled` with
> `started: false` means the body never ran. With `started: true` it says
> nothing about an action the body was waiting for: the action of `ctx.join`
> has ended, gone through or failed, and the outcome does not tell which; the
> action `ctx.abandonable` let go of may go through after the outcome; and
> `Policy.restart` cancels a job in the middle of its action, and the job that
> replaces it makes the call again. A caller that repeats a payment because it
> ended `Cancelled` may pay twice.
>
> A job whose outcome has to tell what its action did refuses cancellation:
> `cancellable: false`, the whole state type as its working type and no
> `keepWhile`, as [A whole job](cancellation.md#a-whole-job) on the
> cancellation page puts it. Once such a job has started, it ends `Done` or
> `Failed`. Otherwise what the work did is what the job recorded inside an
> `uncancellable` section, a receipt in the state, as
> [One section for the step](cancellation.md#one-section-for-the-step) shows,
> and only in a job its rules cannot cancel: a section does not hold the rules
> back. Across restarts of the app, only an idempotent API of the service
> tells a second request from the first.

**Сторож** — `packages/solo/test/jobs_rakes_test.dart`, новая группа
`'What Cancelled does not say'`, контроллер `_Till extends Solo<String>`
в самом тесте, `fakeAsync` и `Completer` на каждое действие:

- `'join: an action that fails after the cancellation leaves Cancelled'` —
  исход `Cancelled(manual)`, `started: true`, ошибка действия не в исходе;
- `'join: an action that goes through leaves Cancelled'` — `Cancelled(manual)`,
  платёж записан;
- `'abandonable: the action goes through after the outcome'` — исход есть
  раньше записи платежа;
- `'restart: the job that replaces it pays again'` — два платежа, первый исход
  `Cancelled(replaced)`;
- `'a section does not hold the rules back'` — `W = 'idle'`-подобный узкий тип
  через `keepWhile`, `externalSetState` во время платежа: `Cancelled`
  с `RulesCancelReason`, платёж прошёл, квитанции нет;
- `'cancellable: false over the whole state type ends Done'` — `cancel()`,
  `close()` и `externalSetState` во время платежа: `Done`, квитанция
  в состоянии;
- `'says what Cancelled does not say'` — сверка прозы:
  `Nor does \`Cancelled\` say that nothing happened.`,
  `the outcome does not tell which`,
  `Once such a job has started, it ends \`Done\` or \`Failed\`.`,
  `a section does not hold the rules back`.

Каждый тест краснеет без своей фразы или при иной механике; поведенческие
зелены сразу (они держат механику, которой абзац учит) — проверка, что они
умеют краснеть, мутацией ожидания.

## Задача 2. `cancellation.md` solo: исход ответа

**Где.** `packages/solo/doc/cancellation.md`, «One section for the step»,
в конец абзаца «When the outermost section finishes, the job accepts the
request it held. … Sections can nest.» — после «Sections can nest.» отдельным
абзацем:

> The job still ends `Cancelled`, with the reason the section held, though the
> payment has gone through: the receipt in the state says so, not the outcome.
> [Jobs and results](jobs.md#jobs-and-results) on the jobs page tells what an
> outcome does not say.

**Сторож.** Механику уже держат
`one section: the receipt reaches the state, the entry is written`
(`Cancelled(manual)`)
и `closing is held as well, and close() waits for the step`
(`Cancelled(closed)`). Новое — сверка прозы в `cancellation_rakes_test.dart`,
в группе раздела: `the receipt in the state says so, not the outcome`.

## Задача 3. `state.md`: что делает `emit` вне `W`

**Где.** `packages/solo/doc/state.md`, «Reading and updating state», абзац
«`ctx.emit(next)` allows a job…», его список и абзац «So put such a transition
last…».

**Текст.** Список:

> - `ctx.abandonable`, `ctx.join` or `ctx.uncancellable` ends the job
>   `Cancelled` before its action starts, and `ctx.pause` before its timer;
> - `ctx.each` ends the job instead of starting a child the same rules would
>   refuse.

После списка новый абзац:

> The job's own rules cancel it, so its `ifFailed` and `ifCancelled` do not
> run, as [Handler eligibility and errors](#handler-eligibility-and-errors)
> has it, and the state stays what the emit wrote. A load whose working type
> is `Initial` and that writes `Loading` before it waits leaves the controller
> at `Loading` for good, and the next call of it is refused at its start: the
> state is no longer `Initial`. `Solo.debug` names such an emit as it writes:
>
> ```text
> Job(load) emit: Loading, which is not Initial: the rules cancel Job(load) at its next checkpoint
> ```

Абзац «So put such a transition last…» остаётся и получает в конец:

> A job that goes on in the states it writes takes all of them as its working
> type, and `canStart` says where it may start, as `switchOn` above does.
> [Opening the camera](camera.md#opening-the-camera) on the camera page
> follows the mistake through, with its trace.

Строка `Solo.debug` длиннее 79 и в код-спан не ложится, поэтому стоит
блоком ```text; блок держит тест ниже, сравнивая его с выводом. Если у
`state_rakes_test.dart` есть сторож вида «has no fence the checks do not
read» или список цитат блоков, новый блок вносится туда; если строка шире 79
в блоке не проходит `check_line_width.py`, блок переносится по `: ` так, как
это делают цитаты трасс, и тест сравнивает со склеенной строкой.

**Сторож** — `packages/solo/test/state_rakes_test.dart`, группа раздела:

- `'a load narrowed to Initial is left at Loading and refused next'` —
  контроллер `Solo<stubs.ProfileState>` в тесте, `enqueue<Initial, String>`
  с `ifFailed`, `ifCancelled`, `emit(Loading)`, `ctx.abandonable(api…)`:
  `Cancelled(rules: …)` со `started: true`, состояние `Loading`, обработчики
  не позваны, второй вызов — `started: false`; строка `Solo.debug` равна
  процитированной (`Solo.debug = lines.add`, сброс в `addTearDown`);
- список абзаца новым не держится: `abandonable`, `join`, `uncancellable`
  и `pause` — ключи `giveUp` теста
  `after an emit outside W a read or a wait ends the job`, а `each` держал свой
  тест и до правки;
- сверка прозы: `the state stays what the emit wrote`,
  `takes all of them as its working type` и строка `Solo.debug`.

## Задача 4. `outcomes.md` ядра: исход задачи, а не её действий

**Где.** `packages/async_job/doc/outcomes.md`, «Reading the result», после
абзаца «`done` hands the outcome over… to acknowledge that choice.».

**Текст:**

> An outcome is the job's, not that of the work it waited for. `Cancelled`
> holds a `started` flag, and with `started: false` the body never ran. With
> `started: true` the outcome says nothing about what the actions of the body
> did outside the job: an action `ctx.join` waited out has ended, gone through
> or failed, and the job ends `Cancelled` all the same. A step that has to be
> kept whatever the outcome keeps its result inside the section that holds the
> cancellation back, as
> [Holding the cancellation back](cancellation.md#holding-the-cancellation-back)
> on the cancellation page shows.

**Сторож** — `packages/async_job/test/outcomes_rakes_test.dart`, группа
`'Reading the result'`:

- `'Cancelled with started: true after a joined action that went through'` —
  `Job` с `ctx.join` над действием на `Completer`, отмена во время действия:
  исход `Cancelled(manual)`, `started == true`, действие выполнено;
- `'Cancelled with started: false: the body never ran'` — `Job.deferred`,
  отменённый до старта, тело не позвано, `started == false`;
- сверка прозы: `An outcome is the job's, not that of the work it waited for.`,
  `the job ends \`Cancelled\` all the same`.

## Задача 5. Переводы, списки изменений, документы

- Переводы четырёх правок: `docs/ru/solo/jobs.md`,
  `docs/ru/solo/ cancellation.md`, `docs/ru/solo/state.md`,
  `docs/ru/async_job/outcomes.md`; код-спаны и строка `Solo.debug` — как
  в оригинале.
- «Unreleased» / «Documentation»: `solo` — `jobs.md` о том, чего `Cancelled`
  не говорит, `cancellation.md` об исходе секции, `state.md` об `emit` вне `W`;
  ядро — `outcomes.md` об исходе задачи. С переводами.
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
