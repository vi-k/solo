> **Состояние на 2026-10-21:** план прошёл ревью на Opus, все тридцать
> находок приняты, вердикты — в «Ревью плана» в конце; правок страниц ещё
> нет.
> **Что это:** план волны читаемости по советам пятого полного ревью: шесть
> страниц с самыми низкими оценками читаемости, с переводами.
> **Связанные записи:** `2026-10-21-async-job-project-review-2.md`
> и `2026-10-21-solo-project-review-2.md` (оценки и советы, раздел
> «Страницы»), `2026-10-21-readability-wave-plan.md` и
> `2026-10-21-core-readability-wave-plan.md` (прошлые волны по тем же
> страницам).

# Волна читаемости по пятому ревью

Владелец 2026-10-21 ответил «да» на четвёртый вопрос обеих записей пятого
ревью: брать советы по страницам до выпуска. Вход — раздел 6 сырых отчётов
Astra и Sol 6.1 в `.artifacts/2026-10-21-full-review-2/out/`. По каждой
странице разбор сделал отдельный агент на Opus: прочитал страницу, перевод,
сторожей в тестах и `docs/settled.md` и предложил правки с черновиком
английского текста. Ниже — шесть разборов как есть, сверху — общее.

## Что входит

| Страница | Astra | Sol | Главное |
| --- | --- | --- | --- |
| `errors.md` ядра | 7,5 | 8 | схема пяти мест во вступлении; одиннадцать исключений — тремя группами по причине |
| `groups.md` ядра | 8 | 8,5 | карта выбора формы; стадии успешного `runAll` с двумя барьерами таблицей |
| `extending.md` ядра | 8 | 8,5 | карта разделов; `MyContext` в целом движке и его прогон; где спрашивается `check()` |
| `errors.md` `solo` | 8,8 | 7,5 | схема трёх маршрутов перед большой таблицей; прямые фразы вместо условных |
| `testing.md` `solo` | 9,2 | 7,5 | вход по симптому и импорты; заглушки последнего рецепта — показать или сослаться |
| `mixins.md` `flutter_solo` | 8,5 | 8,5 | вступление тремя ответами; таблица цепочек с победившим `onListenerError` |

## Общее для всех шести

**Схемы — таблицами Markdown, не блоками ```text.** Это ограничение нашли
четыре разбора из шести независимо: блок ```text каждая страница считает
трассой (`tool/check_traces.py`, `pageQuotes`, `_quoted()`, `quotedOutputs()`
в тестах страниц, счёт блоков), а `tool/check_translations.py` требует, чтобы
строки такого блока совпадали на обоих языках, и схема осталась бы
английской в переводе.

**Подзаголовок без кода.** `tool/check_doc_shape.py` ждёт в первых десяти
строках прозы раздела код, таблицу или подраздел; поэтому новых `###` без кода
нет, деление — вводными строками и таблицами.

**Отклонено по `docs/settled.md`:** замена слов «hears / answers for»
на `errors.md` `solo` (решение 16, словарь ядра); пример с `Expando`
на `errors.md` ядра (решение 18, находка L5 закрыта). Форма «первая попытка →
доказательство → ответ» не трогается ни на одной странице.

**Зонды до правок.** Утверждения, которых на странице не было и которые
не держит ни один тест, проверяются до того, как войти в текст; не сошлось —
в текст не идёт:

- `groups.md`: при успехе группы `discard` ветки не вызывается;
- `extending.md`: `pause` и `join` спрашивают `check()` движка;
- `errors.md` `solo`: непрочитанный провал `job.value` уходит в зону один раз,
  мимо `onUnanswered`;
- `testing.md` `solo`: счётчик `refused` фейка считает только отменённые
  вызовы, `answer()` его не трогает.

**Размер.** Ни одна страница не растёт больше чем на 7 %; `errors.md` ядра
остаётся при своём размере.

## Порядок работ

Одна страница — один коммит `docs(<пакет>): …`, с переводом, сторожами
и зондами. Исполнитель на страницу — агент по этому плану; приёмка моя: дифф
глазами, зонды заново своей командой, `dart test` пакета и проверки документов
(`reflow.py --check`, `check_line_width.py`, `check_links.py`,
`check_translations.py`, `check_doc_shape.py`, `check_traces.py`, стенды
`snippets` там, где страница в них есть). Изменённые абзацы перевода — через
линтер `humanizer--ru`, только `ERROR`. После шести коммитов — ревью всей волны
на Opus в копии на HEAD.

## Страница 1. `errors.md` ядра

Страница 585 строк. Заголовки не меняются нигде: якоря, на которые ведут
`observing.md`, `chains.md`, `extending.md`, `testing.md`, `children.md`,
`cancellation.md`, `outcomes.md`, README и CHANGELOG, остаются. Новых блоков
`text` нет: тест «every quote on the page is what its code prints» собирает
*все* блоки `text` через `pageQuotes`, а вступление обещает, что строки под
кодом — то, что код печатает. Поэтому схема сделана таблицей Markdown.

### 1. Советы ревьюеров

| Совет | Решение | Почему |
| --- | --- | --- |
| Astra: сгруппировать исключения по причинам (+1); Sol: перестроить исключения в несколько коротких маршрутов (+0,8) | взять | 11 пунктов «What the table does not show» — три причины; правка 3 |
| Sol: общий путь ошибки одной схемой во вступлении (+0,6) | взять | таблица из пяти мест вместо двух определений; правка 1 |
| Astra: сложные отрицательные условия переписать прямыми (+0,5); Sol: повтор условных формулировок | взять | пункты без «If…», пять фраз переписаны; правки 2, 3, 4, 6, 7 |
| Astra: входные маршруты по задачам читателя (+0,5) | переделать | не отдельный список ссылок (Sol жалуется на переходы), а столбец «Section» схемы; указатель на рецепт остаётся |
| Sol: многочисленные переходы | взять частично | убираются 4 ссылки внутри прозы (правки 2, 5, 6, 7), схема даёт 4 ссылки в одном месте |
| Astra: связать наблюдение с ответственностью вызывающего в рецепте (+0,5) | взять | одна фраза; правка 8 |
| Sol: законченный безопасный пример учёта ошибок, D4 (+0,6) | отклонить | D4 = L5 ревью `2026-10-21-async-job-project-review-2.md`, закрыт: оговорка про `Expando` уже на странице, пункт 18 `docs/settled.md`. Пример счётчика — длина без снижения того, что держит читатель |

### 2. Правки

**1. Вступление, абзац «A `JobObserver` hears…» и список «the zone is…»,
«the answer is…» (строки 3–12).** Заменить схемой. Абзац «An app that only
wants every error reported once…» и таблица строк трасс остаются.

```
A `JobObserver` hears the errors that no outcome carries, as
[Observing](observing.md) shows. This page follows an error from the job to
whoever answers for it. An error the job catches passes these places in order
and goes no further than the first one that keeps it. A cancellation goes no
further than `onError`.

| Place | What it does with the error | Section |
| --- | --- | --- |
| `onError` | an observer hears it and moves it nowhere | [An observer](#an-observer) |
| The outcome | keeps a failure that a `Failed` carries, once somebody observes that outcome | [An observer](#an-observer) |
| The filter | keeps an error that `Job.isCancellationError` names, once the job has accepted a cancellation | [Errors of a cancellation](#errors-of-a-cancellation) |
| The answer | `onUnanswered` of an observer that mixes in `JobAnswerer` keeps the error, or sends it on to the zone | [Answering for errors](#answering-for-errors) |
| The zone | the zone the job was created in gets the error as an uncaught error there | [Where errors go](#where-errors-go) |

A job without an observer that answers has the zone for its answer.
```

«Place», а не «step»: «a step of `ctx.uncancellable`» на странице уже есть,
одно слово — один предмет. «Place» совпадает с рецептом («Two places that do
not overlap»).

**2. «Errors of a cancellation», абзац «The job stays as it was…», фразы
«An error it names still reaches `onError` and goes no further: neither
`onUnanswered` nor the zone hears it. The filter changes no outcome either.»**
→ `An error it names stops at onError, and the outcome stays as it was.`
(с бэктиками у `onError`). Хвост абзаца с часовым «if nobody observes that
outcome, it goes on to the answer» не трогать.

**3. «Where each error goes».** Вводный абзац:

```
The table shows which places of the introduction each error passes, with an
observer and without one. Rarer ways, such as those of `ctx.runAll` and of
engines, are in [Rare routes](#rare-routes) below.
```

Строку «What the table does not show:» и 11 пунктов (строки 178–229) заменить
тремя группами. Пункт «If somebody observed the outcome…» уходит целиком: он
повторяет первую строку таблицы и абзац «A failure the outcome carries…»
раздела «An observer», а его «closes the way itself» — строка «The answer»
схемы.

```
**What keeps an error out of the answer.**

- `ignoreFailure()` on a job stops the failure of its body at `onError`. It
  lets go of that job's failures alone: a child whose body failed answers for
  its failure itself, whatever its parent calls.
- `Job.isCancellationError`, once the job has accepted a cancellation, stops
  an error it names at `onError` wherever the error came from: the body, a
  step of `ctx.uncancellable`, a child the job waited for, cleanup. That holds
  in the rows of both tables that end with the answer: those of the body of a
  cancelled job and those from outside the body.
- The outcome keeps only the failure it carries. A job that ends `Cancelled`
  carries the cancellation, so the failure of its body goes to `onUnanswered`
  or the zone even when the outcome is observed, and so does the failure of a
  branch of `ctx.runAll` whose group threw another error.

**What Dart hands to the zone past the job.** A context call the body does not
await throws into a future that nobody awaits. Dart, not the job, hands that
error to the zone the body runs in, and `onError`, the filter and the answer
never see it:

- The error of such a call goes there with an observer or without one. For a
  job made with `Job.deferred`, the zone the body runs in is the zone it was
  started from.
- While the body runs, a cancellation of the job makes a `ctx.abandonable`
  called without `await` throw `Cancelled` into its future, and Dart hands the
  job's own cancellation to that zone like any other error.
- `ctx.abandonable` is the one exception once the body has ended: an action
  that fails then takes the way of the late error in the table, to `onError`
  and on to the answer. A call of `ctx.abandonable` without `await` reaches the
  zone the body runs in, with its error or with the job's cancellation, only
  while the body runs.

The filter does not see the error of an `async` callback of `ctx.onCancel`
either: Dart hands it to the zone past the job, as
[A stop that takes time](cancellation.md#a-stop-that-takes-time) shows.

**One error, several calls.**

- An app that reports in both `onError` and its zone hears twice an error that
  reaches both. The table shows one way from the job to the zone: the answer,
  when nobody answers for the error, or `onUnanswered` sends it on or throws.
  An engine that ends a job `Failed` on purpose adds a second, past the answer:
  the last row of [Rare routes](#rare-routes).
- One failure that is the outcome of several jobs reaches `onError` once on
  each of them. (дальше дословно: «A child of `ctx.run` fails, … given one
  observer.»)
- An observer that counts failures tells the second call from a new error by
  `identical`, … (дальше дословно до «…counts it at every call.»)
```

**4. «An observer», абзац «A failure the outcome carries goes on to the answer
only if nobody observes the outcome, a microtask after the job ends, and…».**
Первую фразу → `A failure the outcome carries goes on to the answer a
microtask after the job ends, unless somebody has observed the outcome by
then, and an observer that answers gets it in onUnanswered.` Остальное как
есть.

**5. «Limits of the filter», третий пункт «The filter does not see an error
that Dart hands to the zone itself…» (строки 298–304).** Удалить: его
содержание теперь во второй группе правки 3, ссылка на `cancellation.md` —
там же; обратная ссылка на «Where each error goes» уходит.

**6. «Rare routes», вводный абзац.** Убрать фразу «The columns are those of
[Where each error goes](#where-each-error-goes).» — столбцы названы в самой
таблице.

**7. «Answering for errors», первый абзац.** Первые три фразы («The errors that
no outcome carries go on… Watching alone does not change where an error goes.»)
→ `An observer written only to watch, like Reporter, gives no answer, so the
errors that reach the answer go to the zone.` (бэктики у `Reporter`).
Фраза «An observer that answers for these errors itself mixes in…» остаётся,
`these` → `them`. «Several failures in one error», фразы «An uncaught
`Cancelled` is not a failure, and nobody is asked about it, … Nor is anybody
asked about an error that the app named in [Errors of a cancellation]…, once
the job has accepted a cancellation.» →

```
Nobody is asked about an uncaught `Cancelled`, alone or inside a
`ParallelWaitError`, since a cancellation is no failure, nor, once the job has
accepted a cancellation, about an error `Job.isCancellationError` names.
```

**8. «Reporting each error once», последний абзац, после первой фразы.**
Вставить: `Code that reads done or value takes the failure on: Reports stays
silent about it, so that code reports the failure if it needs a report.`
(бэктики у `done`, `value`, `Reports`).

### 3. Сторожа

- `errors_rakes_test.dart`, «the page holds an unawaited abandonable to the
  zone in the body»: фраза `If the job is cancelled while the body runs,
  \`ctx.abandonable\`` исчезает → заменить на `a cancellation of the job makes
  a \`ctx.abandonable\` called without \`await\``; русскую `Если задачу
  отменяют, пока идёт тело, \`ctx.abandonable\`` — на соответствующий кусок
  нового перевода. Фразы `or with the job's cancellation, only while the body
  runs` и `on purpose adds a second, past the answer` сохранены дословно —
  русские тоже держать дословно.
- «the page sends an unobserved failure to the answer»: все четыре фразы
  (строка таблицы, «if nobody observes that outcome…», «then the zone past the
  answer…», «failure by failure») не тронуты.
- `quotes`/«give way to one:», `pageQuotes`, `strayFences`: блоков не
  прибавилось и не убыло.
- `codeMissingFrom` по разделам: блоки ```dart не меняются; в удалённом пункте
  «Limits» код был только спаном (проверить, что `codeMissingFrom` берёт лишь
  огороженные блоки).
- `check_translations.py`: абзацы, жирные вводы и пункты списков считаются по
  разделам — перевод зеркалит число абзацев и пунктов каждой группы.
  `check_doc_shape.py`: заголовков нет новых, ввод «Where each error goes»
  — три строки до таблицы.

### 4. Новые утверждения и чем их проверить

| Утверждение | Проверка |
| --- | --- |
| Порядок мест схемы: `onError` → исход → фильтр → ответ → зона | `a failure the job ends with: onError, then the answer if unobserved`; `the filter keeps the stop at onError and asks nobody to answer`; `done, value, then and ignoreFailure() observe the outcome` |
| «A cancellation goes no further than `onError`» (о пойманных задачей) | `a Cancelled thrown outside the body: onError or nobody`; `the job's own cancellation out of work left behind: nobody`; `nobody is asked about a cancellation, alone or in an envelope`. Исключение движка — последняя строка «Rare routes», она не отмена, а `Failed`; сверить формулировку зондом, если реализатор усомнится |
| «unless somebody has observed the outcome by then» | `outcomes_rakes_test.dart`: `the failure waits one microtask after the finish for an observer`; `unanswered_test.dart`: `ignoreFailure from a listener of done comes too late` |
| Невзятый вызов контекста: `onError` его не слышит | `a join the body did not await: the zone, past the observer`; `any call the body did not await: the zone, cancellation included` (у `Answerer` печатается `onError`, строки нет) |
| Ошибку `async`-колбэка `ctx.onCancel` фильтр не видит | `the filter does not see what Dart hands to the zone itself` (было на странице, перенесено) |
| Читающий `done`/`value` — `Reports` молчит | `Reporting each error once` → `each error is reported once, by one of the two places` (задача `read`) |

Остальное — перестановка уже написанного.

### 5. Объём

Добавляет около 75 строк, убирает около 74: схема +11 при −10 вступления,
группы +60 при −52 старого списка, «Limits» −7, «Rare routes» −2, «Answering»
−3, рецепт +2. Страница остаётся ~585 строк. Перевод — теми же правками;
изменённые абзацы `docs/ru/async_job/errors.md` прогнать через
`humanizer--ru` (только `ERROR`), затем `python3 tool/reflow.py`,
`--check`, `check_line_width.py`, `check_translations.py`, `dart test
test/errors_rakes_test.dart` в `packages/async_job`.

## Страница 2. `groups.md` ядра

Перевод: `docs/ru/async_job/groups.md`. Заголовки, код и блоки `text`
не меняются; меняются вступление, хвост «When one failure makes the rest
pointless» и три таблицы.

### Ограничения, которые решают форму

- Схема барьеров блоком ```text не годится. Тест `the page quotes what the
  export and the lock scenes report` (`groups_rakes_test.dart`) требует
  `expect(quotedOutputs(), [registered, hung, locked])`: на странице ровно три
  блока `text`. `check_translations.py` требует, чтобы строки блоков совпадали
  на двух языках, а подписи схемы переводятся. Поэтому вся схема — таблица
  Markdown: перевод сверяется только числом строк.
- Решение 71: вход для торопливого стоит в начале страницы, а не в начале
  раздела. Решение 86: карта не выдаёт исход первой попытки. Формы карта
  называет только там, где их уже называет вступление (`.wait`, `runAll`).
- Решение 27: зависание и оба выхода остаются в «Branches that wait for each
  other». Таблица стадий ядро не трогает и выхода не подсказывает.
- Якоря и заголовки не меняются: на них ведут `cleanup.md`, `chains.md`
  и `children.md` с переводами.

### Советы ревьюеров

| Совет | Решение | Почему |
| --- | --- | --- |
| Astra: исправить D1 | уже сделано | L1, `groups_rakes_test.dart`, тест про `eagerError` |
| Astra: карта выбора формы; Sol: выбор формы по сценарию в начале | беру | правка 1; абзац «Use … when» под таблицей уходит в карту |
| Astra: разделить судьбу значений при успехе и при частичном провале | беру в другой форме | правка 2: фраза об успехе над таблицей форм, а таблица — только о провале |
| Astra: стадии успешного `runAll`; Sol: порядок двух барьеров схемой | беру одной таблицей | правка 3: таблица заменяет два абзаца прозы |
| Sol: короче клетки, исключения под таблицу | беру | правки 2, 4, 5: все три широкие таблицы |

Отвергнутых советов нет. Схема блоком `text` заменена таблицей по причине
из первого раздела.

### Правка 1. Вступление: карта

Место: после первого абзаца («A group is several children…»), перед «The
lines under the code are what the code reports».

```markdown
Where to start, by what the branches need:

| When | Read |
| --- | --- |
| Every branch runs to its end, whatever the others do: `[ctx.run(a), ctx.run(b)].wait` | [Waiting for several children](#waiting-for-several-children) |
| A result is of no use without every part: `ctx.runAll` | [When one failure makes the rest pointless](#when-one-failure-makes-the-rest-pointless) |
| Branches share a lock or a pool, or one waits for another | [Branches that wait for each other](#branches-that-wait-for-each-other) |
| A branch returns a resource for the caller | [What a group hands back](#what-a-group-hands-back) |
| The body has to close the list `ctx.runAll` returned | [The list a group returns](#the-list-a-group-returns) |
```

Русские якоря: `#ожидание-нескольких-детей`,
`#когда-один-провал-делает-остальное-бессмысленным`,
`#ветки-которые-ждут-друг-друга`, `#что-группа-отдаёт-обратно`,
`#список-который-вернула-группа`. Все уже встречаются в `docs/ru/async_job/`.

Заодно убрать абзац «Use `[ctx.run(a), ctx.run(b)].wait` when the branches do
not depend…» (строки 166–169): он повторяет карту. Так снимается и N1 прошлой
волны: совет больше не стоит раньше своего довода.

### Правка 2. Таблица форм: успех отдельно, провал отдельно

Место: «When one failure makes the rest pointless», таблица «| Form | Waits for
|…» (строки 159–164). Вместо неё:

```markdown
When every branch succeeds, every form hands the body the values in the order
of the branches. The forms differ when a branch fails:

| Form | Stops the others | The body wakes | Values of the branches that succeeded |
| --- | --- | --- | --- |
| `Future.wait` | no | after the last branch ends | dropped before the body sees them |
| `Future.wait(eagerError: true)` | no, unless the first error is a branch's `Cancelled` | at the first error | dropped |
| `[...].wait` | no | after the last branch ends | in `ParallelWaitError.values` |
| `ctx.runAll` | yes, with `SiblingCancelReason` | after the last branch ends | never reach the body: the group cancels their branches |

Under `eagerError: true` the job still waits for its children, and a
`Cancelled` that comes first cancels the job itself, as above. A branch of
`ctx.runAll` created with `cancellable: false` refuses the stop and ends `Done`
with its value; [What a group hands back](#what-a-group-hands-back) shows who
closes it.
```

Успех у всех форм одинаков, поэтому столбец «на успехе» ничего бы
не различал: он стал фразой над таблицей. Столбец «Waits for» с клеткой
`runAll` «on success …; on failure …» распался: провал — в «The body wakes»,
успех — в таблицу стадий из правки 3.

### Правка 3. Стадии успешного `runAll` и два барьера

Место: тот же раздел, два абзаца «The branches of a group wait for one
another…» и «On success `ctx.runAll` hands the values over…» (строки 178–191).
Абзац «None of the forms closes what the branches returned…» стоит перед ними
и остаётся. Вместо двух абзацев:

```markdown
A successful `ctx.runAll` holds its branches at two barriers, and no branch
passes a barrier until every branch has reached it:

| Stage | What each branch does |
| --- | --- |
| Body | returns a value and waits for its children |
| First barrier | waits for the bodies and children of the others |
| Cleanup | runs its cleanup stack; a `discard` waits for the decision |
| Second barrier | waits for the cleanup of the others |
| Hand-over | `runAll` returns the values; then the branch ends `Done` |

The body of the parent gets the values before the branches end. A cleanup a
branch registers while it waits at the second barrier, from a timer or an
event of its own, runs after that, under the parent, which waits for its
children as always.

The first barrier holds the `dispose` callbacks of a branch too. So a branch
that waits for a sibling, or for what a sibling releases in its cleanup, hangs
the group; [Branches that wait for each other](#branches-that-wait-for-each-other)
shows how. A body that ends without a value ends the wait instead: the group
cancels the other branches, and `ctx.runAll` waits for every branch to end. By
the time the error arrives, everything the branches took is closed.
```

### Правка 4. «What a group hands back»: короткие клетки

Место: таблица «| The branch registers the release with |…» (строки 292–297).
Первый столбец и шапка остаются, кроме слов «a resource the branch keeps for
itself» и «hands out», которые короче. Клетки:

```markdown
| `dispose` of `ctx.abandonable` and `ctx.join`, or `onDispose`: the branch keeps the resource | closed when the branch ends | closed when the branch ends |
| `discard` of `ctx.abandonable` and `ctx.join`, or `onDiscard`: the branch hands it out | reaches the caller open | closed by the branch, which accepts the stop, before the group returns |
| `discard` of `ctx.run(child, discard: ...)`: from a child of the branch | reaches the caller open | closed by the branch, as in the row above |
| any `discard`, in a branch created with `cancellable: false` | reaches the caller open | open: the branch refuses the stop and ends `Done` |
```

Из клеток ничего не теряется. «By the time the parent catches the error, it is
closed» теперь говорит конец правки 3. «The registration is the branch's own»
есть в абзаце под кодом («That registration is the branch's own, the third
row…»). «The parent's body closes the value through the branch's job» есть
в абзаце «The last row follows from…» и в коде под ним. Оговорка «ветка,
принявшая остановку» остаётся в клетке: её требовал M4 прошлой волны. Слова
«No registration» не возвращаются: это L2 прошлой волны.

### Правка 5. «What `runAll` does not promise»: исключения под таблицу

Место: таблица (строки 452–456). Клетки:

```markdown
| A branch the group stops stops its work | Only its waiting stops |
| The children of the branch that failed are cancelled | They play out: a failure never passes down to children, and the group waits for them |
| A branch whose body returned a value has its outcome | Not until the group decides: until then its `outcome` is `null` |
```

Под таблицей, перед «Once the group has handed the list over…»:

```markdown
A stopped branch that waits through `ctx.abandonable` ends, and the operation
behind it plays on. To stop the work itself, hand the cancellation to it with
`ctx.onCancel` and wait for it with `ctx.join`. A branch created with
`cancellable: false` refuses the stop, and the group waits for it.

Until the group decides, a branch whose body returned a value has
`isCancelled` at `false`, and it can still end `Cancelled`: when another
branch ends without a value, the group cancels it with `SiblingCancelReason`,
and `isCancelled` becomes `true`.
```

Фраза «Three things one might expect do not happen» остаётся: строк в таблице
по-прежнему три.

### Сторожа

- `codeMissingFrom` (оба теста в конце `groups_rakes_test.dart`): блоки `dart`
  не меняются, правок нет.
- `quotedOutputs()` и тест `the page quotes what the export and the lock
  scenes report`: новых блоков `text` нет, правок нет. Если исполнитель всё же
  захочет схему в ```text, придётся фильтровать трассы в `quotedOutputs()`,
  а `check_translations.py` потребует английских подписей в русской копии.
  Не делать.
- `strayFences`: новых ограждений нет.
- Проверок фраз (`_says`, `contains`) у этой страницы нет, это показал
  `git grep`. Комментарии `parallel_wait_test.dart:1162` и
  `run_all_test.dart:724` пересказывают обещания страницы, не цитируя их;
  смысл не меняется.
- `check_translations.py`: в русской копии столько же строк в каждой таблице,
  столько же абзацев под каждым заголовком и тот же порядок. Новые абзацы —
  в те же места.
- `check_doc_shape.py`: вступление свободно, разделы по-прежнему начинаются
  с кода или таблицы. `check_links.py`: новые якоря — существующие заголовки.

### Новые утверждения и их проверка

1. На успехе каждая форма отдаёт значения в порядке веток. Для `runAll` —
   тест `the values come back in the order of the list`. Для `Future.wait`
   и `.wait` это семантика SDK; отдельного теста не нужно.
2. Без `eagerError` тело просыпается после конца последней ветки. Тест
   `eagerError moves when the body wakes, and nothing else`
   (`parallel_wait_test.dart`): исполнитель проверяет, что для `.wait`
   и простого `Future.wait` он утверждает `wokeEarly == false`.
3. Значения удавшихся веток `runAll` при провале до тела не доходят, ветки
   отменены. Тесты `the decision of the group is what runs the conditional
   cleanup` и `a failing branch stops its siblings before it ends itself`.
4. Таблица стадий: тесты `a branch is held before it unwinds, and let go on
   every path`, `a branch unwinds once every body is over, or one ended
   without a value`, `the second barrier catches what the first one would have
   missed` и `on success the group does not wait for the tails of its
   branches` (тело получает список раньше конца веток).
5. «Cleanup: a `discard` waits for the decision». На провале `discard` из тела
   ветки бежит: тест `the decision of the group is what runs the conditional
   cleanup`. Что на успехе он не бежит вовсе, ни на стеке, ни после передачи
   значений, — **проверить зондом**: ветка с `ctx.onDiscard` в теле и группа,
   которая удалась; счётчик `discard` после `flushTimers` равен 0. Если
   найдётся готовый тест (смотреть `a resource a branch took for the caller is
   closed by the branch`), сослаться на него.
6. Всё остальное в новых клетках и абзацах уже есть на странице, только
   переставлено.

### Объём

Сейчас 460 строк. Добавляется около 52: карта 10, фраза и пояснения
к таблице форм 9, таблица стадий с двумя абзацами 22, абзацы под «does not
promise» 11. Уходит около 20: абзац «Use … when» 5, два абзаца о барьерах 15.
Таблицы 4 и 5 по числу строк не меняются. Итог — около +32 строк, ~7%,
в пределах бюджета: две таблицы заменяют прозу.

### Порядок для исполнителя

Правки 1–5 в английском, затем те же места в русской копии. Перевод — с теми
же якорями и тем же числом строк в таблицах. Перевод прогнать через
`humanizer--ru`, шаг «Голос» пропустить. Потом `python3 tool/reflow.py
--check`, `python3 tool/check_line_width.py`, `python3
tool/check_translations.py`, `python3 tool/check_doc_shape.py`, `python3
tool/check_links.py`; в `packages/async_job` — `dart test` на
`groups_rakes_test.dart`, `run_all_test.dart` и `parallel_wait_test.dart`.

## Страница 3. `extending.md` ядра

Перевод: `docs/ru/async_job/extending.md`. Сторожа страницы:
`packages/async_job/test/extending_rakes_test.dart` (тест цитат
`every quote on the page is what its code prints`, карта `holders`
с `codeMissingFrom` по заголовкам, `every piece of code…`, `strayFences`).
Проверок фраз (`_says`, `contains` по тексту страницы) у страницы нет:
`extending_test.dart` страницу не читает. Плюс `tool/check_doc_shape.py`
(LEAD = 10 строк прозы до кода или таблицы под заголовком),
`check_translations.py`, `check_links.py`.

### 1. Советы ревьюеров

| Совет | Решение | Почему |
| --- | --- | --- |
| Astra: D3 / Sol: D3 | уже сделано | L3, L4 закрыты: `add` отказывает, `finished()` чистит `_queue` |
| Astra: входная карта разделов | взять | пять разделов разной природы; вступление (под `#`) от LEAD свободно, решение 71 велит вход в начале страницы |
| Astra: разделить ограничения `finish` | переделать | вводными строками над тремя списками, без подзаголовков: подраздел из одних пунктов краснеет в `check_doc_shape.py`; пункт об экземпляре `Cancelled` остаётся про `finish` и `cancelWith` (M5 прошлой волны) |
| Astra: запуск целого движка с двумя задачами | переделать | запуск трёх задач уже есть под «Refusing…»; новый берём как доказательство «One loop»: две задачи и два вызова `run()`, у раздела трассы нет |
| Sol: минимальный `MyContext` в полном примере | взять | блок «The whole engine» не компилируется сам по себе: нет `MyContext` |
| Sol: моменты проверки и отмены — таблицей | переделать | две таблицы: где спрашивается `check()` (начало «A rule of your own») и сравнение правила с `_stop` (конец «Not waiting…»); таблица из двух строк и два абзаца уходят |

С `docs/settled.md` не спорит ни одна правка (71, 34, 86 проверены). Форма
«попытка → доказательство → ответ» не меняется: новых попыток нет, разделы
не переставляются.

### 2. Правки

#### П1. Карта во вступлении

Место: между абзацем «The three live in `package:async_job/engine.dart`…»
и «The lines under the code are what it prints…». Новый текст:

```markdown
The page builds one engine, a queue of jobs with a rule:

- [A job of your own](#a-job-of-your-own): the job, its context and the
  protected API the engine reaches them through.
- [A queue of your own](#a-queue-of-your-own): jobs run one at a time, a
  `cancellable: false` job keeps its turn, and
  [The whole engine](#the-whole-engine) puts the code together.
- [A rule of your own](#a-rule-of-your-own): the jobs stop when the user
  signs out.
- [Deferred start](#deferred-start): a plain `Job` that starts when the
  caller chooses, with no engine.
- [Finishing a job by hand](#finishing-a-job-by-hand): what `finish` skips
  that a cancellation does.
```

Исхода первых попыток карта не выдаёт (по духу решения 86): «keeps its
turn» — требование, которое раздел и так ставит первой фразой.

#### П2. «The whole engine»: `MyContext` в блоке

В конец блока `dart`, после `MyQueue`, пустой строкой:

```dart
final class MyContext extends JobContextBase {
  MyContext(super.owner);
}
```

Абзац «`MyContext` stays as [A job of your own]… gives it a rule.» заменить:

> The next section, [A rule of your own](#a-rule-of-your-own), gives this
> `MyContext` the rule of the engine.

#### П3. «The whole engine»: движок в работе

Сразу после абзаца из П2:

> At work, the engine takes two jobs, and `run()` is called twice. The second
> call gets the loop of the first, and the jobs run one after the other:

```dart
final queue = MyQueue();
for (final name in ['photo', 'video']) {
  queue.add(MyJob<void>((ctx) async {
    print('$name starts');
    await ctx.abandonable(upload);
    print('$name ends');
  }));
}
await Future.wait([queue.run(), queue.run()]);
```

```text
photo starts
photo ends
video starts
video ends
```

Переносы блока — как их поставит `dart format` в драйвере (см. §3).

#### П4. «A rule of your own»: где спрашивается `check()`

Абзац «`check()` is the checkpoint of the context. While the body runs,
`abandonable`, … A rule of the engine goes there. A job of the engine
downloads rows…» заменить на:

> `check()` is the checkpoint of the context, and a rule of the engine goes
> there. While the body runs, these calls ask it:
>
> | Call | Asks `check()` |
> | --- | --- |
> | `abandonable`, `pause`, `uncancellable` | before the action |
> | `join` | before the action and again after it |
> | `run` | once the child's value has arrived |
> | `runAll` | before it hands the values back |
>
> A job of the engine downloads rows over a connection and saves them:

#### П5. «A cancellation of the engine's own»: таблица уходит в П6

Хвост абзаца «A sign-out now ends the job…» с фразы «Nobody asked the job…»,
таблицу «What | Against the rule's cancellation» и абзац «The job accepts the
rule's cancellation as the body lets it out…» заменить одной фразой
в конце того же абзаца:

> Nobody asked the job for this cancellation, so it does not come through
> `cancelWith`: `cancellable: false` does not refuse it, and
> `ctx.uncancellable` does not hold it, since `check()` throws inside the
> call that asked the rule, here `join`.

Абзац «The rule is asked where `check()` is asked and nowhere else…»
остаётся: он завязка следующего раздела. Факт про `try`/`catch` переезжает
в строку таблицы П6.

#### П6. «Not waiting for the checkpoint»: сравнение двух остановок

Последний абзац «The job accepts the cancellation inside the sign-out: …
it passes `false` itself.» заменить на:

> The two ways the engine stops a job at a sign-out:
>
> | | The rule in `check()` | `_stop` from `onSignOut` |
> | --- | --- | --- |
> | The job accepts the cancellation | as the body lets it out of a call that asked the rule | inside the sign-out |
> | `onCancel` callbacks run | then | inside the sign-out, and `abandonable` throws at once |
> | A body that catches it and goes on | is not cancelled | ends `Cancelled` all the same |
> | `cancellable: false` | does not refuse it | does not refuse it: `rejectable: false` |
> | `ctx.uncancellable` | does not hold it | does not hold it |
>
> A wrapper around `cancelOwnJob` of the context stops the job the way
> `_stop` does: it passes `rejectable: false` itself.

#### П7. «Finishing a job by hand»: три группы

Таблица и фраза «Since `finish` unwinds nothing…» остаются. Пункт об
отладочном канале становится второй фразой этого абзаца:

> Since `finish` unwinds nothing, an engine that finishes a running job by
> hand releases what the job holds first. Only the debug channel, switched on
> with `Job.debug = print;`, says how many cleanups `finish` left behind.

Остальные четыре пункта — под тремя вводными строками, текст пунктов как
есть, кроме отмеченного:

> On any job finished by hand:
>
> - (пункт «A job that has accepted a cancellation…» без изменений)
> - A failure of the body, thrown before `finish` or after, is in no outcome
>   unless it is the very one handed in. (дальше без изменений: «`onError`
>   hears… stops it at `onError`.»)
>
> On a branch of `runAll`:
>
> - (пункт «A `Done` handed to a branch of `runAll`…» без изменений)
>
> On the `Cancelled` handed in, to `finish` or to `cancelWith`:
>
> - (пункт «A `Cancelled` handed to `cancelWith` or to `finish` belongs to
>   one job…» без изменений)

Из второго пункта уходит «When an engine finishes a running job by hand,» —
это говорит вводная строка. Пункт об экземпляре не сужать до `finish`.

### 3. Сторожа

- `extending_rakes_test.dart`, новый драйвер рядом с `runQueue`:
  `Future<void> runWholeEngine() async { … }` с телом из П3 строка в строку
  (после `dart format`; переносы страницы берутся из отформатированного
  драйвера). `upload` уже есть в `support/extending_stubs.dart`.
- Тест `every quote on the page…`: в `prints` после
  `printed(() => runQueue().ignore())` вставить
  `printed(() => runWholeEngine().ignore())` — цитаты сверяются по порядку.
- Карта `holders`: кусок `MyContext` из П2 есть только в
  `support/extending_plain.dart`, а в `extending_rakes_test.dart` у
  `MyContext` правило — проверка «The whole engine» покраснеет. Не добавлять
  `extending_plain.dart` в `alsoIn` целиком (тогда `finished()` блока мог бы
  уехать в версию без `_queue` и остаться зелёным). Вместо этого вынуть
  заголовок из `holders` и дать ему свой тест: `codeMissingFrom(…, under:
  '### The whole engine')` с `alsoIn: [stubs]` равен ровно одному куску —
  трём строкам `MyContext`, — а тот же вызов с `extending_plain.dart`
  в `alsoIn` пуст.
- `every piece of code on the page…`: `plain` там уже есть — зелёный.
- `check_doc_shape.py`: подзаголовков не добавляется; таблица П4 стоит
  в пределах LEAD у «A rule of your own».
- `check_links.py`: якоря карты П1 и П2 — английские; в переводе — якоря
  русских заголовков, как в уже существующих ссылках перевода.
- `check_translations.py`: перевод получает те же блоки кода (комментарии
  можно по-русски), ту же трассу П3 и те же таблицы. Изменённые абзацы
  перевода — через `humanizer--ru` (без шага «Голос»). Заливка
  `python3 tool/reflow.py` и `check_line_width.py`.

### 4. Утверждения, которых на странице не было

- Два вызова `run()` — одна петля, задачи по очереди (П3): тест
  `a second run waits for the loop that runs: one job at a time`; трассу
  держит тест цитат с новым драйвером.
- `pause` спрашивает `check()` до действия (П4): на странице уже есть, но
  тест в `extending_test.dart` (`$name asks check() before the action runs`)
  перебирает только `abandonable`, `join`, `uncancellable` — найти тест
  `pause` в других файлах или добавить `pause` в тот же перебор
  («проверить зондом»).
- `join` спрашивает и после действия (П4): уже на странице; держит
  `a sign-out during a wait is noticed only at the next call that asks`
  косвенно — исполнителю найти прямой тест или дописать.
- `_stop`: тело, поймавшее отмену, кончается `Cancelled` (П6): тест
  `the engine stops a running job itself, through $through` (ловит
  `Cancelled` внутри `uncancellable` и всё равно `Cancelled(signed out)`).
- `_stop`: `onCancel` внутри выхода и `abandonable` бросает сразу (П6):
  `the job accepts that cancellation inside the sign-out`.
- Правило: пойманное и продолженное не отменяет (П6):
  `a body that catches the rule and goes on is not cancelled`;
  `cancellable: false` и `uncancellable`: `nor does cancellable: false`,
  `an uncancellable section does not hold the rule back`.

### 5. Объём

Добавляется около 60 строк (П1 ≈ 13, П2 ≈ 6, П3 ≈ 22, П4 ≈ 9, П6 ≈ 11,
П7 ≈ 6), уходит около 20 (П4 3, П5 9, П6 4, П7 2 и строка-пункт). Итог
≈ +40 строк на 651, около 6%: в пределах 10%.

## Страница 4. `errors.md` `solo`

Перевод: `docs/ru/solo/errors.md`. Сторож:
`packages/solo/test/errors_rakes_test.dart`
(фразы через `_says`/`_row`, блоки кода через `holders`/`codeMissingFrom`,
блоки ```text через `_quoted()`, ожидается ровно `[2, 1]`).

### 1. Советы ревьюеров: решения

| Совет | Решение | Почему |
| --- | --- | --- |
| Astra + Sol: короткая схема двух маршрутов перед большой таблицей | Взять, таблицей Markdown | ```text сдвинул бы `_quoted()` (тест ждёт `[2, 1]`), а `check_translations.py` требует одинаковых строк блоков — схема осталась бы английской в переводе |
| Astra: вместо «hears / answers for» — observe/report/forward | Переделать: термины оставить, определить их один раз схемой | Это словарь API: решение 16 в `docs/settled.md` («`onError` оповещает, `onUnanswered` отвечает»), `JobAnswerer`, вся страница ядра; на них ~30 фраз сторожа. Схема называет действия: report, observe, hand on |
| Astra: разбить многосоставные фразы | Взять точечно (правки В, Г, Е) | Только фразы с двумя «so»/двоеточием и цепочкой, не трогая закреплённые без нужды |
| Sol: `lets that failure go too` → прямое объяснение | Взять (правка Д) | Тест 'the same with ignoreFailure() on the job' показывает ровно это: хук сообщил, дальше ничего |
| Sol: путь обычных future под своим подзаголовком | Переделать: третья строка схемы, абзац остаётся на месте | `###` без кода роняет `tool/check_doc_shape.py` (проза, затем `##`); блок кода ради проверки — лишний держатель в `holders` и длина. Строка схемы даёт тот же вход и стоит впереди |

### 2. Правки

#### А. «Where each error goes», первый абзац («Every error of a job goes two ways…»)

Абзац (8 строк) заменить вводом, схемой и коротким абзацем:

```markdown
An error of a job can go two ways at once, and a future the job hands out
adds a third way, Dart's own:

| Route | Who takes the error, in order | Where it ends |
| --- | --- | --- |
| Report | `onError` of the controller and `onError` of a `SoloObserver` | In the hooks. They report it and return, and the error still goes on along the answer route |
| Answer | Whoever observes the outcome, then `onUnanswered` of the controller, whose default body hands it to `Solo.unansweredHandler` | At the first of them that is there; with none, in the creation zone |
| Dart's | Whoever holds the future of `job.value` or `ctx.run(child)` | Where that future is handled; unhandled, in the zone, like any future error |

The table below names, for each kind of error, who hears it on the first
route and who answers for it on the second. An error that no outcome carries
enters the answer route at `onUnanswered`. `onError` in the table stands for
both hooks: the two hear the same errors. The current zone is the zone the
hook is called in. For what happens in a job, that is the zone the job was
created in; for a change made by `externalSetState`, the zone of its caller.
```

Последнее предложение не трогать: его держит `_says` в тесте 'a hook of a job
throws into the zone the job was created in'.

#### Б. Абзац под большой таблицей («An error can reach both `onError` and the zone…»)

Заменить целиком (8 строк → 5):

```markdown
An error can reach both `onError` and the zone. An application that reports in
both places hears it twice.
[Handled and unhandled failures](#handled-and-unhandled-failures) shows how a
caller observes the outcome, and
[Answering for an error](#answering-for-an-error) shows the override, the
handler and `Job.isCancellationError`.
```

Что ушло: «is the application's to close…» — это теперь столбец «Where it
ends» строки Answer; «to begin with» — строка схемы.

#### В. Последний абзац раздела («Dart has a way of its own to the zone…»)

Первое предложение связать со схемой, остальное оставить (все фразы
закреплены):

```markdown
Dart's way, the third row of the scheme, is not the engine's. An unhandled
error of `job.value` …   (дальше без изменений)
```

Закреплённая фраза «Dart has a way of its own to the zone, and the engine does
not stand on it» уходит — тест 'the value of a cancelled job, taken and not
handled' перевести на новую.

#### Г. «Answering for an error», абзац «A handler or an override can throw…»

Разбить предложение с двумя «so»:

```markdown
… A `Cancelled` the hook throws stays out. The error itself, thrown back by the
hook, stays out too, so that error reaches the zone once. A hook that reported
the error before it threw has it reported twice.
```

Фраза на странице не закреплена; поведение держат тесты
`packages/solo/test/zone_test.dart`: 'a handler that throws a cancellation
leaves the error alone', 'a handler that throws the error back hands it to the
zone once'. Смысл не меняется, новых утверждений нет.

#### Д. «Observing the outcome», последний абзац («That caller cannot catch one failure…»)

Последнее предложение «`ignoreFailure()` lets that failure go too.»
заменить:

```markdown
`ignoreFailure()` drops this failure as well: `onError` still reports it, and
it goes no further.
```

Русский уже прямой («`ignoreFailure()` гасит и его») — привести к новому
английскому: «`ignoreFailure()` гасит и этот провал: `onError` о нём
по-прежнему сообщает, а дальше он не идёт.»

#### Е. «Background work», абзац «`ctx.unattended(action)` starts work…»

Предложение с «with nothing to answer» заменить:

```markdown
`ctx.unattended(action)` starts work that the job neither waits for nor
cancels. Its errors stay with the job, even after the job finishes. They take
the first two routes of [Where each error goes](#where-each-error-goes):
`onError` hears them, and the answer route takes them from `onUnanswered` on.
Use it for work with a lifetime of its own.
```

### 3. Сторожа

- 'an abandoned call that fails once its job has completed' (~стр. 1325):
  `_says('The way to the creation zone through `onUnanswered` is the
  application's to close…')` → `_says` строки Answer целиком (через
  `errorsPage.says('| Answer | … |')`).
- 'the same with ignoreFailure() on the job' (~1299): фраза правки Д.
- 'the value of a cancelled job, taken and not handled' (~1430): фраза
  «Dart's way, the third row of the scheme, is not the engine's».
- тест о `ctx.unattended` (~3281): фраза правки Е до «from `onUnanswered` on».
- Добавить `_says` строк схемы в тесты, которые их уже доказывают: Report — в
  тест с «It answers for nothing, and overriding it moves no error anywhere»
  (~432); Dart's — в 'job.ignoreFailure() on a job whose value is already
  taken' (~1474).
- Не затронуты: заголовок большой таблицы (тест ~1516 ищет его `indexOf`),
  `_quoted()` (новых ```text нет), `holders` (новых заголовков с кодом нет),
  якорь `#where-each-error-goes` (на него ссылается README `flutter_solo`).
- `check_doc_shape.py`: раздел открывается одной строкой прозы и таблицей.
- `check_translations.py`: в переводе та же таблица из трёх строк и то же число
  абзацев. Изменённые русские абзацы — через `humanizer--ru` (шаг «Голос»
  пропустить, смотреть только `ERROR`).

### 4. Новые утверждения и их проверка

1. Хуки сообщают и возвращаются, ошибка идёт дальше по маршруту ответа — тест
   с «overriding it moves no error anywhere» (~432).
2. Ответ останавливается на первом, кто есть: наблюдатель исхода — тесты
   'the line of the page: load() and ignoreFailure()' и соседний про `done` /
   `value`; переопределение — тест с «The override above answers for them»
   (~454, «the handler is not asked»); обработчик — 'each controller decides
   whether the handler hears its jobs'; зона — 'the lines of the page: a
   report, then the zone'.
3. Ошибка без исхода входит в маршрут ответа на `onUnanswered` — тесты списка
   «These are the errors that no outcome carries» (~520–552).
4. Третий маршрут и то, что `job.ignoreFailure()` его не закрывает — тесты
   ~1429–1510.
5. Правка Д — 'the same with ignoreFailure() on the job' (crashes есть,
   handled и зона пусты).
6. Строка Answer, «Whoever observes the outcome» как первый шаг, и строка
   Dart's: `Failed`, у которого взяли `job.value` и не обработали, уходит
   в зону один раз, а `onUnanswered` его не получает — **проверить зондом**
   (существующие тесты гоняют это только для `Cancelled`). Если зонд скажет
   иначе, строку Dart's оставить, а связь с Answer в прозу не писать.
7. «The two hear the same errors» — уже на странице, без изменений.

### 5. Размер

Страница 557 строк. А: −8, +12 (ввод 2, таблица 5, абзац 6, пустые). Б: −8,
+6. В: ±0. Г: ±0. Д: +0…1. Е: ±0. Итого около +3 строк прозы (<1%), при этом
два длинных абзаца-определения заменены схемой.

## Страница 5. `testing.md` `solo`

Перевод: `docs/ru/solo/testing.md`. Сторож:
`packages/solo/test/testing_rakes_test.dart` и опоры
`test/support/testing_*.dart`: `page`, `page_fixtures`, `first_attempts`,
`first_attempt_timeout`, `stubs`.
Страница — 711 строк.

### Что нашёл

- `FakeCamera`, `CancelToken`, `OpenCancelled`,
  `CameraState`/`Idle`/`Connected`
  живут только в `test/support/testing_stubs.dart`, рядом с подменой `test`
  (`PageTest test(...)`). Ни на одной странице их нет: у `camera.md` другой
  фейк (`FakeCameraHardware` из `example/`, `open()` без токена), `CancelToken`
  на `jobs.md`, `cancellation.md`, `vs-bloc.md` везде назван «токен API
  устройства, не тип пакета» и нигде не показан. Ссылаться на пример камеры
  нельзя — там другое устройство; ссылаться на `testing_stubs.dart` плохо —
  читатель упрётся в подмену `test`.
- `CameraController` вокруг `connect` есть в `testing_page.dart:171`, но между
  `connect` и `}` стоит служебный `next()`, поэтому класс целиком на страницу
  не выносится как «run of lines».
- Опубликованный тест таймаута уже имеет усиленного двойника в сторожe:
  `the deadline stops the device at five seconds, and not before`
  (4999 мс: `no outcome, refused 0`; 5000 мс: `Cancelled(timeout)`,
  `refused 1`).
- `isOpen` у `FakeCamera` не читает никто.
- «Assertions inside a zone» стоит седьмым, хотя в списке правил он четвёртый
  среди ждущих; запрета на перестановку в `docs/settled.md` нет (L15
  `2026-10-04-solo-testing-reread-report.md` — только о фразе; п. 97 — о форме
  правил, перестановку не трогает).
- `dart pub add dev:foo` есть в `dart pub add --help` на 3.27.0/Dart 3.6 —
  проверено.

### Решения по советам

| Совет | Решение | Почему |
|---|---|---|
| Sol: рецепт Timeouts на фикстурах, которых нет на странице; дать ссылку | **Переформулировать**: класс контроллера — на страницу; фейк — одной фразой + ссылка на новый чистый файл | Код фейка SDK (≈50 строк с токеном) — не то, чему учит страница; `camera.md` так же описывает свой фейк прозой и ссылается на код |
| Sol: собрать imports и dev dependencies у входа | **Взять** прозой с код-спанами | Блок `yaml` — «stray fence»; блок `dart` с импортами не совпадает ни с одним файлом подряд (`hide test`) |
| Sol: усилить опубликованный тест проверкой остановки устройства и момента до дедлайна | **Взять** | +4 строки кода; факт уже держит тест сторожа |
| Astra: маршрут по симптомам | **Переформулировать**: таблица «что делает тест → раздел» после двух списков правил | Список правил ключён по роду теста, читатель с красным тестом приходит с симптомом; каждый симптом уже сказан в разделе — новых утверждений нет. Не повтор п. 86 (карта vs-bloc не выдаёт исход): здесь правила сверху уже дают ответ, п. 97 |
| Astra: сгладить переходы обычный тест / `fakeAsync` | **Взять перестановкой**: «Assertions inside a zone» — четвёртым разделом, сразу после «A failure nobody read» | Убирает два перехода из трёх (ждущий → fakeAsync → ждущий → fakeAsync); порядок страницы совпадает со списком правил; раздел о зоне продолжает конец «A failure nobody read» («It goes to the zone…») |

### Правки по местам

#### 1. Вход: таблица симптомов

Место: после второго списка (после пункта «[Timeouts](#timeouts): …»), перед
абзацем «The examples below use `package:test`…». Новый абзац и таблица:

> A test that already misbehaves finds its section by what it does:

```text
| The test | Section |
|---|---|
| fails, and the state it prints is `Initial` | [Awaiting a job](#awaiting-a-job), [Closing the controller](#closing-the-controller) |
| is red with an error none of its expectations raised | [A failure nobody read](#a-failure-nobody-read), [Timeouts](#timeouts) |
| fails after it has already completed | [A failure nobody read](#a-failure-nobody-read) |
| hangs until its own timeout | [Assertions inside a zone](#assertions-inside-a-zone), [Awaiting inside fakeAsync](#awaiting-inside-fakeasync) |
| passes, having checked nothing | [Assertions inside a zone](#assertions-inside-a-zone), [Awaiting inside fakeAsync](#awaiting-inside-fakeasync) |
| fails on an order it did not expect | [The order of what happened](#the-order-of-what-happened) |
| leaves its observer to the next test | [What one test leaves for the next](#what-one-test-leaves-for-the-next) |
```

(Ячейки в порядке страницы после перестановки п. 3. Строки таблицы ширину
не проверяют, `check_line_width.py` их пропускает.)

Откуда каждый симптом (новых фактов нет): `Initial` — «The test fails, and the
state it prints is `Initial`» и «`close()` cancels, and the state the
expectation sees is `Initial`»; красный без своей проверки — «The expectation
holds and the test is red anyway» и «left alone, it reaches the zone of the
test and turns the test red»; после конца — «This test failed after it had
already completed»; висит — «The test hangs until the test's own timeout kills
it» и «the test would end on a timeout»; зелёный впустую — «The test passes,
and it would pass with no failure reaching the zone at all» и «the test ends at
once and green»; порядок — «The journal comes out in another order»;
наблюдатель — «stays installed for the next one».

#### 2. Вход: импорты и dev-зависимости

Место: тот же промежуток, новый абзац после таблицы; следующий абзац
переписан так, чтобы `_says('all but the last drive the `load` of the
controller')` не менялся.

> A test file of the page imports `dart:async`,
> `package:fake_async/fake_async.dart`, `package:solo/solo.dart` and
> `package:test/test.dart`; `dart pub add dev:test dev:fake_async` adds the two
> packages of tests as dev dependencies.
>
> Of the examples below, all but the last drive the `load` of the controller
> from [Quick start](…) in the package README:

Было: «The examples below use `package:test`, and all but the last drive…».

#### 3. Перестановка: «Assertions inside a zone» — четвёртым

Раздел целиком (заголовок `## Assertions inside a zone` до `## Timeouts`)
переезжает между «A failure nobody read» и «The order of what happened». Текст
раздела не меняется. Якоря те же, входящие ссылки (`mistakes.md`,
`flutter_solo/doc/testing.md`) ведут на якоря и не ломаются.

Абзац «Two kinds of test run through the page…», последняя фраза:

- было: «The first three sections below await; `fakeAsync` starts with the
  fourth, and the seventh, on assertions inside a zone, awaits again.»
- стало: «The first four sections below await; `fakeAsync` starts with the
  fifth.»

«The order of what happened», первый абзац, фраза «Timing and ordering are
tested with `package:fake_async`, and what happened is collected by an
observer — one for every controller in the process.» → 

> From this section on the tests run under `fakeAsync`: the test moves the
> clock and runs the microtasks itself, so it can stop between two calls. What
> happened is collected by an observer — one for every controller in the
> process.

(Хвост «collected by an observer — one for every controller in the process»
держит `_says` теста `one observer hears every controller of the process` —
сохранён дословно.)

#### 4. «Timeouts» → «A deadline of the job»: класс вокруг `connect`

Первый абзац, хвост «`hw` is the device, `CancelToken` is the token of its API
and not a type of this package, and `Idle` and `Connected` are the states:» →

> The controller keeps the device in `hw`; `CancelToken` is the token of the
> device's API, not a type of this package, and `Idle` and `Connected` are the
> states:

Блок кода — `connect` в своём классе (+5 строк):

```dart
final class CameraController extends Solo<CameraState> {
  final FakeCamera hw;

  CameraController(this.hw) : super(const Idle());

  Job<void> connect() => run<Idle, void>(
        key: 'connect',
        timeout: const Duration(seconds: 5),
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          await ctx.join(() => hw.open(cancelToken: token));
          ctx.emit(const Connected());
        },
      );
}
```

#### 5. Там же: фейк одной фразой и ссылка

Длинный абзац «Five seconds after the body starts…» кончается теперь
на «…takes the field apart.» Его последняя фраза («The five seconds cost the
test nothing; its `FakeCamera` is …, so the deadline is what ends the call:»)
уходит в новый абзац:

> The five seconds cost the test nothing: its `FakeCamera` is a device that
> never answers on its own. `open` waits until the test calls `answer()`, and
> a cancelled token fails the waiting call with `OpenCancelled` and counts it
> in `refused`. The fake is in full in
> [`test/support/testing_camera.dart`](../test/support/testing_camera.dart),
> with stand-ins for the `CancelToken` and `OpenCancelled` of a device's SDK.
> The test looks a millisecond before the deadline and at it:

Русская ссылка — по образцу `docs/ru/solo/camera.md:7`:
`../../../packages/solo/test/support/testing_camera.dart`.

#### 6. Там же: усиленный опубликованный тест

```dart
test('connect gives up after five seconds', () {
  Job.isCancellationError = (error) => error is OpenCancelled;
  addTearDown(() => Job.isCancellationError = null);

  fakeAsync((async) {
    final hw = FakeCamera();
    final camera = CameraController(hw);

    final job = camera.connect();
    async.elapse(const Duration(milliseconds: 4999));
    expect(job.outcome, isNull);

    async.elapse(const Duration(milliseconds: 1));
    expect('${job.outcome}', 'Cancelled(timeout)');
    expect(hw.refused, 1);
    expect(camera.currentState, isA<Idle>());

    camera.close();
    async.flushTimers();
  });
});
```

Абзац под тестом, в начало:

> A millisecond before the deadline the job has no outcome, and the device is
> still waiting; at the deadline the token is cancelled, and `refused` counts
> the call the device let go.

Дальше без изменений: «`connect()` gives `run` no state handlers…».

### Сторожа и опоры

1. `testing_stubs.dart`: `CameraState`, `Idle`, `Connected`, `CancelToken`,
   `OpenCancelled`, `FakeCamera` переезжают в новый
   `test/support/testing_camera.dart` (без `isOpen`, его никто не читает;
   шапка — для читателя, по-английски: что это фейк устройства и токен с
   ошибкой SDK). В `testing_stubs.dart` остаются `PageTest` и `test`. Импорты
   `testing_page.dart`, `testing_rakes_test.dart` — поправить.
2. `testing_page.dart`: убрать `next()` из `CameraController` (иначе блок п. 4
   не «run of lines»); в `testing_rakes_test.dart` завести
   `final class _QueuedCamera extends page.CameraController` с `next()`
   и перевести на него тест `the next job waits for the device to stop`.
   `connectGivesUp` переписать как в п. 6.
3. `holders`: `'### A deadline of the job'` остаётся на `answers`; файл
   `testing_camera.dart` на страницу кодом не выходит.
4. Тест `the three sections that await come first, fakeAsync is the fourth`
   → `the four sections that await come first, fakeAsync starts with the
   fifth`: первые четыре раздела без `fakeAsync((` и с `await `;
   `sections[3]` начинается с `## Assertions inside a zone`;
   `_says('The first four sections below await; `fakeAsync` starts with the
   fifth.')`. Тест правил (`the rules on top name every section…`) пройдёт
   как есть; можно ужесточить: правила по порядку совпадают с разделами.
5. Тест `the fake camera never answers on its own`: `_says` фразы
   «its `FakeCamera` is a device that never answers on its own» — фраза
   сохранена. Добавить `_says('a cancelled token fails the waiting call with
   `OpenCancelled` and counts it in `refused`')` — проверяет зонд из п. 7.
6. Тест `the deadline stops the device at five seconds, and not before`:
   добавить `_says('A millisecond before the deadline the job has no outcome,
   and the device is still waiting')` и `_says('`refused` counts the call the
   device let go')`. Факты он уже проверяет (`no outcome, refused 0`;
   `Cancelled(timeout)`, `refused 1`).
7. Новые проверки:
   - `refused` растёт ровно при отмене токена ожидающего вызова, а `answer()`
     его не трогает — **проверить зондом** (код `FakeCamera` это делает, теста
     на `refused` после `answer()` нет);
   - импорты: новый тест в группе `The page` — директивы `import` файла
     `testing_page.dart` вместе с `testing_camera.dart` (без относительных)
     совпадают с четырьмя, названными на странице; `_says` абзаца п. 2;
   - `dart pub add dev:test dev:fake_async` — синтаксис `dev:` проверен
     `dart pub add --help` на Dart 3.6; сторожа не нужно;
   - «From this section on the tests run under `fakeAsync`» — держит тест
     п. 4 (`sections.skip(4)` — `fakeAsync((` или сброс наблюдателя);
   - таблица симптомов — новых фактов нет (см. п. 1); якоря держит
     `tool/check_links.py`.
8. Трассы (`text`-блоки) и `tool/check_traces.py` не затронуты: трассы
   не меняются, раздел о порядке не двигается.
9. `has no fence the checks do not read`: новых ограждений нет (таблица —
   не блок).

### Перевод

`docs/ru/solo/testing.md`: те же правки, кодовые блоки п. 4 и п. 6 —
построчно как в оригинале (`check_translations.py` сверяет некомментарные
строки), таблица — столько же строк. Абзацы: +1 на входе (таблица со своей
вводной), +1 (импорты), +1 в «A deadline of the job» (фейк), остальное —
правка внутри абзацев. Изменённые абзацы — через `humanizer--ru` (только
`ERROR`, шаг «Голос» пропустить), `python3 tool/reflow.py`,
`python3 tool/check_translations.py`, `python3 tool/check_line_width.py`.

### Размер

Добавляет ≈ 38 строк, убирает ≈ 4: таблица с вводной +11, импорты +5, мост
в «The order of what happened» +1, класс вокруг `connect` +5, абзац о фейке
+7 (фраза из старого абзаца ушла, −2), тест +4, фраза под тестом +2,
вступительная фраза о порядке −1. Итог ≈ 711 → 745, +4,8%. Перестановка
раздела длины не меняет.

## Страница 6. `mixins.md` `flutter_solo`

Перевод: `docs/ru/flutter_solo/mixins.md`. Сторож: `packages/flutter_solo/test/
mixins_rakes_test.dart`; стенд `tool/flutter_snippets.py`; CI-задание `flutter`
гоняет `tool/check_traces.py` по этой странице.

### Главное ограничение: схемы — только таблицами Markdown

Новый блок ```` ```text ```` на этой странице ломает три вещи сразу:
`check_traces.py` считает его трассой и краснеет (стенд схему не печатает);
тест `its blocks are dart and text, seven and six` ждёт ровно 6 блоков `text`;
тесты раздела о базе берут трассы по индексу `_quotes()[4]` и `[5]`, и схема
перед ними сдвинет индексы. Голый ```` ``` ```` ловит `strayFences`. Поэтому
обе схемы ниже — таблицы. Заголовки не меняются: на якоря ссылаются
`CHANGELOG.md` обоих языков и `tool/build_site_test.py`.

### Советы ревьюеров

1. Схема цепочки `leaf → mixin → base → Solo` с победившим `onListenerError`
   (Astra +1,0, Sol +0,7) — **беру, в другой форме**: цепочка одной фразой
   в доказательстве первой попытки (правка 2) и итоговая таблица четырёх
   листьев в конце раздела (правка 3). Целиком в первую попытку таблица
   не встаёт: выдала бы ответ до доказательства.
2. Вступление — краткие ответы для двух доставок, экрана на стриме и общей
   базы (Astra +0,5) — **беру**: три пункта списка, по одному на раздел.
3. Сократить повторный перечень тем во вступлении (Sol +0,3) — **беру вместе
   с п. 2**: фраза «This page is about what sits around…» уходит, перечень
   становится этим списком.
4. Таблица `snapshot.data` против `currentState` (Sol +0,5) — **беру
   урезанной**: две строки «что это» и «первый кадр/после `close()`» вместо
   двух фраз во второй попытке; строку «дали другую сессию» не ставлю — это
   изъян, который раздел показывает трассой сразу ниже, таблица выдала бы
   его заранее.

### Правка 1. Вступление (строки 3–21)

Первый абзац: оставить первые три фразы до «with the mixin or without it.»,
фразу «This page is about what sits around `SoloListenable` — … cannot go.»
заменить одной: «This page answers three questions around the mixin:».
Второй абзац («The short answer for that base class: …») заменить списком
(третий пункт вбирает его целиком, охраняемые фразы дословно):

```markdown
- [A controller with both deliveries](#a-controller-with-both-deliveries):
  `SoloListenable` combines with `SoloStream` of `solo`, in either order. One
  change then has two error routes, and `close()` waits for every subscriber
  of `stream`.
- [A screen built on the stream](#a-screen-built-on-the-stream):
  `StreamBuilder` over `stream` shows nothing until the next change, and with
  `initialData` it keeps the old session's data when handed another. A builder
  that takes the controller, `SoloBuilder` or `ValueListenableBuilder`, shows
  the state of the session it is given from the first frame.
- [A base class without Flutter](#a-base-class-without-flutter): such a base
  cannot mix `SoloListenable` in, so the base keeps its report of a listener's
  failure in `reportListenerError`, a method no mixin overrides. Between the
  base and the app's controllers, the leaves, the app puts a class of its own,
  `ListenableController`. It mixes `SoloListenable` in and overrides
  `onListenerError` to call that method, and a leaf extends it without mixing
  `SoloListenable` in again. Where a mixin sits decides whose
  `onListenerError` runs.
```

Абзац «The lines under a block of code are what a run of it shows…» — без
изменений. Якоря перевода: `#контроллер-с-обеими-доставками`,
`#экран-на-стриме`, `#базовый-класс-без-flutter`.

### Правка 2. «A base class without Flutter» → «The first attempt», абзац «Where the mixin sits decides…» (строки 237–242)

Вставить вторую фразу с цепочкой; остальное без изменений:

> Where the mixin sits decides whose `onListenerError` reports a listener's
> failure. A call of the hook starts at the leaf and goes down its chain,
> `ProfileController`, then `SoloListenable`, then `AppController`, then
> `Solo`, and the first `onListenerError` on the way is the one that runs. A
> mixin sits above the class written before `with`, here above
> `AppController`, so its override wins, with a report through
> `FlutterError`, and the base's override never runs. The analyzer says
> nothing about it. Nor does `super` reach the base from the leaf: `super`
> there is the mixin, and an override that only calls it is one the analyzer
> calls unnecessary.

Стрелки в прозе не ставлю: на страницах их нет, а `reflow.py` может начать
строку с `→`.

### Правка 3. «A report under another name», после последнего абзаца («A class sits above the mixins…»)

Абзац оставить как есть (в нём четыре охраняемые фразы). После него — итог:

```markdown
The four leaves of this section side by side, each chain from the leaf down,
with the `onListenerError` that runs in bold:

| `ProfileController` | Chain from the leaf down | Report |
| --- | --- | --- |
| `extends AppController with SoloListenable` | `ProfileController` → **`SoloListenable`** → `AppController` → `Solo` | `FlutterError` |
| the same, with an override of its own | **`ProfileController`** → `SoloListenable` → `AppController` → `Solo` | `AppLog` |
| `extends ListenableController` | `ProfileController` → **`ListenableController`** → `SoloListenable` → `AppController` → `Solo` | `AppLog` |
| `extends ListenableController with SoloListenable` | `ProfileController` → **`SoloListenable`** → `ListenableController` → `SoloListenable` → `AppController` → `Solo` | `FlutterError` |
```

Строки таблицы шире 79 — `check_line_width.py` строки таблиц пропускает.

### Правка 4. «A screen built on the stream» → «The second attempt», абзац «The data of a snapshot and `currentState` differ…» (строки 142–147)

Первые две фразы заменить таблицей; хвост абзаца становится отдельным абзацем:

```markdown
The data of a snapshot and `currentState` differ in where they come from:

| | `snapshot.data` | `currentState` |
| --- | --- | --- |
| What it is | what `stream` delivered to this subscriber, or `initialData` until it delivers something | the state the controller is in now |
| Without `initialData` | `null` on the first frame, and still `null` after `close()` if no change came | the state the session is in, before and after `close()` |

`initialData` hands the subscriber that state at the moment it subscribes, so
the snapshot has data from the first frame, and `requireData` reads it with no
`null` case to write. The fault shows when the badge is handed another session:
```

### Сторожа

- Число блоков (7 `dart`, 6 `text`), `codeMissingFrom`, `check_traces.py`,
  `tool/flutter_snippets.py` — не затронуты: новых огороженных блоков нет.
- `_says` — все фразы сохраняются дословно: две из вступления (теперь в третьем
  пункте списка; `_prose()` вырезает только код, список для неё — проза),
  «so its override wins, …» во второй правке, четыре фразы последнего абзаца.
  После правки прогнать `flutter test test/mixins_rakes_test.dart`.
- Добавить `_says('the first `onListenerError` on the way is the one that
  runs')` в тест `the first attempt reports past the base`.
- Добавить тест `the table of chains is what the four leaves report`: читает
  последнюю ячейку четырёх строк таблицы правки 3 и сверяет с `_reached` для
  `first.DrivenProfile`, `answer.DrivenProfile`, `shared.DrivenProfile`,
  `_Twice` (`FlutterError` ↔ `_quotes()[4]`, `AppLog` ↔ `_quotes()[5]`).
- `check_translations.py`: перевод повторяет форму — во вступлении абзац,
  список из трёх пунктов, абзац; две таблицы с тем же числом строк; лишний
  абзац во второй попытке (таблица разрезала один абзац на два).

### Проверка утверждений

Новых фактов о поведении нет; каждое утверждение уже держит тест:

- порядок миксинов безразличен — `the order of the two mixins makes no
  difference`; два маршрута ошибок — `one change has two error routes`;
  `close()` ждёт подписчиков — `an await for over the stream holds close()…`;
- `StreamBuilder` без `initialData` ждёт изменения — `the first attempt opens
  with nothing`; с `initialData` держит старые данные — `the second attempt
  keeps the data of the old stream`; `SoloBuilder`/`ValueListenableBuilder` —
  `a builder over the controller needs nothing passed`, `and
  ValueListenableBuilder shows the same three lines`;
- таблица правки 4: `null` при `SignedIn` в том же билдере — `while
  currentState holds the state in the same builder`; после `close()` —
  `closing makes the wait endless` (`currentState` остаётся `SignedIn`);
- цепочка и «первый `onListenerError` по пути»: `onListenerError` объявлен
  в `Solo` (`packages/solo/lib/src/solo.dart:251`, по умолчанию — зона,
  `errors_rakes_test.dart`: `a listener that throws: onListenerError, by
  default the zone`), переопределён в `SoloListenable`
  (`packages/flutter_solo/lib/src/solo_listenable.dart:61`, `FlutterError`);
- строки таблицы правки 3: `the first attempt reports past the base`, `the
  report under another name reaches the log`, `the override of the class
  between runs in every leaf`, `mixed in again on a leaf, the mixin silences
  the override`.

### Объём

Сейчас 323 строки. Правка 1: −19, +24; правка 2: +3; правка 3: +10; правка 4:
−3, +9. Итого около +24 строк, ~7 %. Перевод растёт так же. После правок:
`python3 tool/reflow.py --check`, `python3 tool/check_line_width.py`,
`python3 tool/check_translations.py`, `python3 tool/check_links.py`.

## Ревью плана

Ревью на Opus, 2026-10-21, по копии на `a4b77a05`; зонды ревьюер запускал в ней
и удалил. Текст ревью ниже как есть, после каждой находки — вердикт. Все
тридцать приняты, 22-я частично. Правки страниц идут уже с ними; черновики выше
остаются как были, вердикт старше черновика.


Копия: `/Users/user/.claude/jobs/b7a261de/tmp/rev-plan5`, отвязанное дерево
на a4b77a05. План не правился, страницы тоже. Зонды лежали в `test/zz_probe_*`
пакетов копии и после прогона удалены. Ссылка вида «план:N» означает строку
`docs/records/2026-10/2026-10-21-fifth-review-readability-plan.md`.

Исходное состояние зелёное: `check_translations.py` расхождений не видит,
`check_doc_shape.py` проходит, `check_links.py` все ссылки находит.

### Зонды до правок (четыре утверждения плана)

1. Ядро, `groups.md`, утверждение 5: `discard` на успешной группе (план:485).
   Вывод: `a dispose`, `values [1, 2]`, `parent Done(null)`. Ни один `discard`
   не запускался. **Подтверждено.** Но формулировка в черновике неудачная, см.
   находку 10.
2. Ядро, `extending.md`, таблица `check()`. Вывод зонда:
   - `abandonable`: check, затем действие;
   - `join`: check, действие, check;
   - `pause`: check только перед ожиданием;
   - `uncancellable`: check, затем действие;
   - `run` и `runAll`: сначала действие ребёнка, потом check;
   - `start`, `each`, `log`, `unattended`: check нет вовсе.

   **Таблица П4 верна и полна.** Действующий тест `extending_test.dart:382`
   проверяет только `abandonable`, `join` и `uncancellable`.
3. `solo`, `errors.md`, утверждение 6: `Failed`, у которого взяли `job.value`,
   но ошибку не обработали. Вывод:
   - зона `[boom]`, `onError [fails: boom]`, `onUnanswered []`;
   - с заданным `Solo.unansweredHandler`: зона `[boom]`, handler `[]`;
   - контроль (никто не читает): `onUnanswered [fails: boom]`.

   **Подтверждено.**
4. `solo`, `testing.md`, счётчик `refused`. Вывод:
   - после `answer()`: 0; отмена после ответа: 0;
   - отмена во время ожидания: 1; повторная отмена того же токена: 1;
   - `open` с уже отменённым токеном: 2 (тоже считается).

   Усиленный тест п. 6: на 4999 мс `outcome == null` и `refused 0`; на 5000 мс
   `Cancelled(timeout)`, `refused 1`, состояние `Idle`. **Подтверждено.**

Зонды сверх четырёх, по сомнительным фразам черновиков:

- Непрождённый (unawaited) `ctx.run` ребёнка, который падает, при наблюдателе.
  Вывод: `onError child: Bad state: child failed`, затем
  `zone: Bad state: child failed`. Это опровергает фразу черновика, см. находку
  5.
- Движок завершает задачу `Failed(Cancelled)`. Вывод:
  `onError: Cancelled(handler: by engine)`, затем
  `zone: Cancelled(...) (Cancelled)`. Это опровергает фразу черновика, см.
  находку 4.
- Отменённая задача с упавшим телом и `ignoreFailure`: только
  `onError j: DbStopped`, то есть `ignoreFailure` останавливает ошибку. Та же
  задача, прочитанная через `done`: `onError`, `onUnanswered j: DbStopped`,
  `outcome: Cancelled(manual)`. См. находку 6.
- Наследование от `page.CameraController` в тестовом файле. Вывод
  `dart analyze`: `error - The class 'CameraController' can't be extended
  outside of its library because it's a final class. -
  invalid_use_of_type_outside_library`. См. находку 23.
- `dart pub add --help` на полу 3.27.0 документирует `dev:`. **Подтверждено.**
- `jargon.py` по английским черновикам: «no kitchen words outside code».

### Находки

#### Общее

**1. Medium, механика. Черновики кода в записи испорчены заливкой.** Где
в плане:
- П3 `extending.md` (план:585–594): строки драйвера склеены в прозу, а трасса
  `photo starts photo ends video starts video ends` стоит в одной строке;
- `testing.md` п. 4 (план:1037–1046):
  `final class CameraController … { final FakeCamera hw;` в одной строке, тело
  `connect` склеено;
- `testing.md` п. 6 (план:1068–1089): начало теста склеено.

Похоже, запись прогнали через `reflow.py`, и он залил содержимое блоков.
Исполнитель, который скопирует трассу как есть, получит красный
`extending_rakes_test.dart:1301–1326`: тест сравнивает строки блока с `prints`.
Скопированный код будет неформатированным, и гейт `dart format` покраснеет.

Как чинить: восстановить блоки в записи. Прямо написать, что источник правды
о переносах — вывод `dart format` по драйверу или по `testing_page.dart`,
а не запись. Для трассы — четыре строки.

Вердикт: принято. Испортила моя заливка при сборке записи: `reflow.py` путается
в оградах из четырёх кавычек, а в разборе `errors.md` ядра строка прозы
начиналась с трёх кавычек и открывала блок. Запись пересобрана из исходных
разборов без заливки, строка исправлена, блоки П3 и пп. 4 и 6 `testing.md`
целы. Переносы кода на странице — по выводу `dart format` опоры, не по записи.

**2. Medium, механика. Таблица симптомов `testing.md` стоит внутри ```text
(план:957–967).** Если исполнитель перенесёт ограду вместе с таблицей,
на странице появится лишний `text`-блок. Это противоречит собственному
правилу плана «Схемы — таблицами Markdown, не блоками ```text» (план:33).
Сдвинется счёт блоков и `_quotes()` в `testing_rakes_test.dart`.

Как чинить: показать таблицу в записи без ограды, например цитатой `>`, или
четырьмя ` ```` `. Пометить, что на странице она идёт без ограды.

Вердикт: принято. На странице симптомы встают в пункты правил (находка 25),
отдельной таблицы и ограды нет.

**3. Low, механика. Общий раздел приписывает `check_traces.py` всем страницам
(план:35, 69).** В CI он гоняется только по `flutter_solo/doc/mixins.md`,
`vs-bloc.md` и `accumulation.md`. Страницы ядра и `solo` errors/testing держат
свои тесты: `pageQuotes`, `quotedOutputs`, `_quoted()`, `_quotes()`. Вывод
плана («text не добавлять») от этого не меняется, но исполнитель `extending.md`
может зря искать вывод стенда для `check_traces.py`.

Как чинить: в общем разделе назвать, какой сторож у какой страницы.

Мелочь: в записи два заголовка `## 1.` (план:74 и 83). Раздел страницы и его
первый подраздел на одном уровне — оглавление сайта и якоря их перепутают.

Вердикт: принято. Сторож каждой страницы назван в её разделе; общий раздел
говорит о блоках `text` в целом. Два заголовка `## 1.` ушли при пересборке:
разделы страниц теперь «Страница N».

#### 1. `errors.md` ядра

**4. Medium, верность. «A cancellation goes no further than `onError`»
(план:105–106) неверно.** Последняя строка «Rare routes» самой страницы
(`packages/async_job/doc/errors.md:306–318`) говорит обратное: движок, который
нарочно завершает задачу `Failed` с `Cancelled`, отдаёт его в зону мимо ответа.
Это же решение 25 в `docs/settled.md`. Зонд:
`onError: Cancelled(handler: by engine)`, затем `zone: Cancelled(...)`. Таблица
проверок плана (план:260) держит фразу только на пойманных задачей отменах,
а читатель вступления этого сужения не видит.

Как чинить: «A cancellation the job catches goes no further than `onError`»
плюс «unless an engine ends the job `Failed` with it» — или убрать фразу вовсе:
вступление и без неё говорит, куда идёт ошибка.

Вердикт: принято. Фраза сужается до отмены, которую задача поймала: «A
cancellation the job catches goes no further than `onError`», и называет
исключение — движок, который сам кончает задачу `Failed` с `Cancelled`,
со ссылкой на «Rare routes».

Итог: сделано коммитом страницы
`docs(async_job): lay out the places of an error in errors.md`, во вступлении:
«A cancellation the job catches goes no further than `onError`, unless an
engine ends the job `Failed` with it, as the last row of Rare routes shows».

**5. Medium, верность. Вводка второй группы: «`onError`, the filter and the
answer never see it» (план:160–163).** Для `ctx.run`, `ctx.runAll` и детей это
ложь. Зонд: непрождённый `ctx.run` упавшего ребёнка даёт
`onError child: Bad state: child failed`, а уже потом зону. `onError` ребёнка
ошибку слышит. Не видит её только маршрут самой задачи-родителя.

Как чинить: «and the job's own `onError`, filter and answer never see it», или
убрать придаточное — следующие пункты и так говорят, куда идёт ошибка.

Вердикт: принято. Придаточное убирается: следующие пункты и так говорят, куда
идёт ошибка.

Итог: сделано тем же коммитом страницы. Вводка второй группы кончается фразой
«Dart, not the job, hands that error to the zone the body runs in». Сверх
предложенного переписан абзац под группой: без придаточного «The filter does
not see … either» повисало, а утверждение, что фильтр не видит отданного Dart,
план переносил сюда из «Limits of the filter». Теперь: «The filter sees none of
the errors Dart hands to the zone, and the error of an `async` callback of
`ctx.onCancel` is one of them»; держит его прежний тест
`the filter does not see what Dart hands to the zone itself`.

**6. Low, верность. `ignoreFailure` и «even when the outcome is observed».**
Пункт 1 первой группы говорит, что `ignoreFailure` останавливает ошибку тела
отменённой задачи (зонд подтверждает). Пункт 3 той же группы говорит, что эта
ошибка идёт дальше «even when the outcome is observed». По определению самой
страницы `ignoreFailure` наблюдает исход, так что пункты спорят.

Как чинить: в пункте 3 «even when somebody reads `done` or `value`» вместо
«observed».

Вердикт: принято: «even when somebody reads `done` or `value`».

Итог: сделано тем же коммитом страницы. Держит фразу новый тест
`reading done or value leaves the failure of the body to the answer`
в `errors_rakes_test.dart`: у отменённой задачи с упавшим телом и чтение
`done`, и чтение `value` дают `onError`, `cancel`, `onUnanswered`.

**7. Low, нагрузка. Правка 2: «stays as it was» дважды в одном абзаце.** Как
чинить: второй раз заменить или слить предложения.

Вердикт: принято.

Итог: сделано тем же коммитом страницы: «An error it names stops at `onError`
and changes no outcome».

**8. Low/Medium, нагрузка. Правка 7.** Склейка «Nobody is asked … nor, once …,
about …» читается тяжелее двух прежних предложений. Правка заодно убирает
локальное определение у якоря «Answering for errors», на который ссылаются
другие страницы. Кто придёт по ссылке, встретит «the errors that reach the
answer» без определения.

Как чинить: оставить два предложения. В первом сохранить короткое определение,
хотя бы ссылкой на таблицу «Where each error goes».

Вердикт: принято. Два предложения, короткое определение у якоря «Answering for
errors» остаётся.

Итог: сделано тем же коммитом страницы. В «Answering for errors» осталось
определение у якоря, вторая фраза сокращена, «Watching alone…» убрана.
В «Several failures» два предложения, а вместо ссылки на раздел названо поле
`Job.isCancellationError`.

**9. Low, нагрузка. Правка 8 повторяет строку таблицы «Reporting each error
once» в рецепте.** На странице уже есть строка «A failure whose outcome
somebody observed | nobody: the code that observed it has it»
(`packages/async_job/doc/errors.md:571–577`).

Как чинить: убрать из рецепта или дополнить саму строку таблицы.

Вердикт: принято. Фраза в рецепт не идёт: строка таблицы «Reporting each error
once» уже говорит это.

Итог: фразы в рецепте нет, правка 8 не делалась.

Сторожа `_says` плана для этой страницы сверены
с `packages/async_job/test/errors_rakes_test.dart`:
- 474–500: четыре фразы EN и четыре RU, план их сохраняет;
- 1207–1230: план заменяет «If the job is cancelled while the body runs,
  `ctx.abandonable`» и правит тест; русские эквиваленты учтены;
- 1383–1384: вводка «give way to one:» сохраняется.

Пропусков, от которых CI покраснеет, не нашёл.

#### 2. `groups.md` ядра

**10. Low, верность. Таблица стадий: «Cleanup | … a `discard` waits for the
decision» (план:382, 485).** На успехе решение принято заранее, и `discard`
не запускается вовсе. Зонд: `a dispose`, `values [1, 2]`, `parent Done(null)`,
ни одного `discard`. Фраза «ждёт решения» наводит на мысль, что на успехе он
когда-то выполнится.

Как чинить: «a `discard` is set aside; on success it never runs».

Вердикт: принято: «a `discard` is set aside; on success it never runs». Держит
тест на успешную группу, который зонд и показал, — новым тестом
в `groups_rakes_test.dart`.

Итог: сделано коммитом страницы
`docs(async_job): map the forms of a group in groups.md`. Клетка вышла
с запятой вместо второй точки с запятой: «runs its cleanup stack; a `discard`
is set aside, and on success it never runs». Держит её новый тест
`on success no discard of a branch ever runs` в `groups_rakes_test.dart`:
у обеих веток стоят `onDispose`, `onDiscard` и `discard` у `abandonable`,
а трасса — только два `dispose` и значения.

**11. Low, нагрузка. Строки 1 и 2 карты (Правка 1, план:313–338) повторяют
вводный абзац страницы.** Как чинить: сократить абзац до одной фразы или убрать
из карты то, что абзац уже говорит.

Вердикт: принято. Вводный абзац сокращается до одной фразы, карта говорит
остальное.

Итог: сделано тем же коммитом страницы: вступление — одна фраза, а то, что
`ctx.runAll` отменяет ещё идущие ветки, переехало во вторую строку карты.

**12. Low. «hangs the group» вместо прежнего «can hang».** Допустимо по решению
27 (страница говорит, что делает код, а не что может). Отмечаю, чтобы
исполнитель не вернул «can».

Вердикт: принято к сведению: остаётся «hangs».

Итог: так и осталось, «hangs» без «can».

**13. Low, объём. Рост около 7%, у самого предела плана.** Если находку 11
принять, рост уйдёт ниже предела.

Вердикт: принято: с находкой 11 рост ниже предела.

Итог: страница выросла с 460 до 491 строки, на 6,7 %, перевод — с 458 до 489.

Механика: якоря таблиц форм и «hands back» стоят на месте, русские заголовки
сверены. Таблицы вместо `text` с решением 86 не спорят.

#### 3. `extending.md` ядра

**14. Medium, механика. Черновик П3 испорчен (см. находку 1).** Кроме того,
`prints` в `extending_rakes_test.dart:1301–1326` сравнивает список
`text`-блоков страницы по порядку, а их сейчас семь (187, 269, 443, 465, 507,
541, 571). Новый драйвер должен встать в `prints` после `runQueue()`. План
говорит это неявно, а нужно прямо.

Вердикт: принято. Новый драйвер встаёт в `prints` сразу после `runQueue()`,
трасса — четыре строки.

**15. Low, нагрузка. Порядок П2/П3: указатель на следующий раздел стоит перед
демонстрацией.** Читатель уходит по ссылке, не увидев, ради чего.

Как чинить: сначала демонстрация, указатель после.

Вердикт: принято: сначала прогон, потом указатель.

**16. Low. П3 дублирует объяснение «One loop».** Но это единственная трасса,
которая отличает одну петлю от двух. Оставить.

Вердикт: принято: трасса остаётся.

**17. Low, нагрузка. П7: списки из одного пункта под вводной строкой.** Шесть
лишних строк ради малого выигрыша. Можно оставить прозой.

Вердикт: принято: П7 — три вводные фразы в прозе, без списков из одного пункта.

Сверено: план `holders` с двумя утверждениями корректен.
- `MyContext` с правилом лежит в `extending_rakes_test.dart:115`, простой —
  в `support/extending_plain.dart:37–39`.
- `### The whole engine` ведёт на rakes с `alsoIn: [stubs]`.
- Тест всех файлов (1352–1366) включает `extending_plain.dart`.

Таблица `check()` верна (зонд 2). Повтор теста для `abandonable(discard:)`
не нужен: `run_all_test.dart:1416–1466` уже покрывает полный успех.

#### 4. `errors.md` `solo`

**18. Medium, верность. Строка Report большой таблицы (план:767): «Where it
ends: In the hooks. They report it and return, and the error still goes on
along the answer route».** Клетка спорит сама с собой: «кончается в хуках»,
но «идёт дальше».

Как чинить: «nowhere: the hooks report and return; the error goes on along the
answer route».

Вердикт: принято, в формулировке ревьюера.

Итог: сделано коммитом страницы
`docs(solo): make the error routes of errors.md readable`. Клетка вышла чуть
иначе: «Nowhere: the hooks hear it and return, and the error goes on along the
answer route» — глагол «hear», а не «report», ради находки 22. Строку держит
`_says` в тесте `overriding it moves no error anywhere`.

**19. Medium, верность. Строка Answer (план:768): «At the first of them that is
there».** Это неточно. Тело `onUnanswered` по умолчанию «есть» всегда,
а в строке не названы ни переопределение, ни `Solo.unansweredHandler`.

Как чинить: «at whoever observes the outcome; otherwise an override of
`onUnanswered` or `Solo.unansweredHandler`; with neither, the creation zone».
Утверждение 6 (наблюдатель исхода, затем зона) зонд подтвердил, поэтому
отдельно упомянуть: `value`, взятое без обработки, уводит ошибку в зону,
а не в `onUnanswered`.

Вердикт: принято, в формулировке ревьюера, с фразой о `value` без обработки.

Итог: сделано тем же коммитом страницы. Клетка ответа — формулировка ревьюера,
второй столбец — «Whoever observes the outcome, then `onUnanswered` of the
controller». Фраза о `value` встала в абзац под схемой; держит её новый тест
`the value of a failed job, taken and not handled` в `errors_rakes_test.dart`,
в двух вариантах — без обработчика и с ним: хук слышит ошибку, `onUnanswered`
и обработчик пусты, в зону она уходит один раз.

**20. Low/Medium, нагрузка. «Dart's way, the third row of the scheme»
(план:804, 861).** Слово «scheme» на странице не введено, а ссылка по номеру
строки ломается от первой перестановки. Фразу ещё и держит `_says`, так что
номер строки застынет в тесте.

Как чинить: «Dart's route in the table above».

Вердикт: принято: «Dart's route in the table above».

Итог: сделано тем же коммитом страницы, `_says` переведён на новую фразу.

**21. Low.** Вводка «the table below names … who answers for it on the second
route» не подходит строкам Dart, хуков и слушателей. Правка Е заменяет
конкретную фразу отсылкой назад «the first two routes». Как чинить: вернуть
конкретику и сократить её.

Вердикт: принято: конкретика возвращается короче.

Итог: сделано тем же коммитом страницы: вводка большой таблицы говорит «who
hears it and who answers for it» без отсылки к путям, а фраза
о `ctx.unattended` снова конкретна — «`onError` hears them, and `onUnanswered`
answers for them; with no override and no handler, they end in the creation
zone».

**22. Medium, согласованность. Две страницы errors описывают один механизм
разными моделями.** Ядро: «places in order», глагол «keeps». `solo`: «two ways
at once», «routes», «takes».

Как чинить: в `solo` взять ту же модель мест. Report описать как слушание
(hears), а не как маршрут. Различие hears/answers по решению 16 план сохраняет
верно.

Вердикт: принято частично. Модель «двух путей» на `errors.md` `solo` прошла
прошлые волны и остаётся; строка Report схемы говорит о слушании — хуки слышат
и ничего не двигают, как `onError` ядра, — и одна фраза называет зону: та, где
создан контроллер. Перестраивать страницу `solo` под «места по порядку» ядра
в этой волне не будем.

Итог: сделано тем же коммитом страницы, кроме зоны. Модель двух путей осталась,
строка Report говорит о слушании. Фраза «зона, где создан контроллер» неверна:
и dartdoc `Solo` и `JobBase`, и тесты `errors_rakes_test.dart` говорят о зоне,
где создана задача, — в тесте
`with no handler set: the zone the job was created in` зона контроллера ошибки
не получает. Определение во вступлении страницы, «the zone the job was created
in», осталось как было, а новая строка ответа на него опирается. Тот же пункт
«Согласованность терминов» выше читать с этой поправкой.

Сторожа `_says`: план правит 1325, 1299, 1429, 3280 и обновляет тесты, 1688
сохраняется. Тест таблицы (1516) находит заголовок большой таблицы через
`indexOf` — новые колонки должны оставить первую строку узнаваемой; план шапку
меняет, тест поправить. `_quoted` ждёт `[2, 1]`, план `text` не добавляет.

#### 5. `testing.md` `solo`

**23. High, механика. `final class _QueuedCamera extends page.CameraController`
(план:1109) не скомпилируется.** `CameraController` объявлен `final class`
в `packages/solo/test/support/testing_page.dart:171`, и блок страницы держит
его `final`. Вне библиотеки от него не наследуются. Зонд: `error - The class
'CameraController' can't be extended outside of its library because it's a
final class. - invalid_use_of_type_outside_library`. Расширение (extension)
не спасёт: `run` помечен `@protected`, и `dart analyze` даст предупреждение.

Как чинить: объявить публичный `QueuedCamera` с `next()` внутри
`testing_page.dart` (та же библиотека, наследование разрешено) — или оставить
`next()` в `CameraController`, а на странице показать только `connect`, выбрав
блок через `codeMissingFrom(… under:)`.

Вердикт: принято, первый вариант: публичный `QueuedCamera` с `next()` объявлен
в `testing_page.dart`, в той же библиотеке, что `CameraController`.

**24. Medium, верность/нагрузка. `final FakeCamera hw;` в опубликованном
контроллере (план:1038).** Код страницы показывает, как писать
продакшен-контроллер, а он привязан к фейку из тестов.

Как чинить: тип-интерфейс вроде `CameraHardware`, который фейк реализует; либо
по-прежнему показывать один `connect` без поля.

Вердикт: принято. Поле получает тип устройства `Camera` — интерфейс с тем, что
вызывает `connect`; `FakeCamera` его реализует. Страница называет `Camera`
в той же фразе, что описывает фейк.

**25. Medium, нагрузка. Таблица симптомов (п. 1) — второй указатель на те же
восемь разделов.** Вместе с абзацем об импортах вступление вырастает примерно
до 55 строк до первого кода. Это противоречит решению 71: рецепт для
торопящегося — коротко и наверху.

Как чинить: вписать симптом в пункт правила (`- [Timeouts](#timeouts): a test
red with an error none of its expectations raised …`) или оставить таблицу,
но убрать список правил. Тест правил (1726) ловит только строки `- [..](#..): `
до первого `## `; при слиянии он останется зелёным.

Вердикт: принято: симптом вписывается в пункт правила, отдельной таблицы нет.

**26. Low/Medium, верность. «From this section on the tests run under
`fakeAsync`» (план:1017).** Это неверно для «What one test leaves for the
next»: по решению 97 её первая попытка часов не запускает. Фраза ещё
и повторяет абзац страницы 82–87.

Как чинить: «The sections on time run under `fakeAsync`» с перечнем, или
убрать. Тест `sections[6]` (1711) после перестановки п. 3 проверить по новому
порядку.

Вердикт: принято: «The sections on time run under `fakeAsync`» с перечнем; тест
`sections[6]` сверяется по новому порядку.

**27. Low.** «`answer()`» в прозе называет метод фейка, которого страница
не показывает: у слова нет предмета в примере. «The two packages of tests»
звучит коряво — «`package:test` and `fake_async`».

Вердикт: принято: `answer()` в прозе не называется, «`package:test` and
`fake_async`».

Сверено: тест камеры ждёт семь `false`, затем `true`. Список `_says` (259,
1787, 919, 1517 сохраняются, 1723 меняется и тест правится) с планом сходится.
Остальной перенос в `testing_stubs.dart` согласован; импорты
`testing_page.dart` (`dart:async`, `fake_async`, `solo`, `package:test`
с `hide test`) план перечисляет верно.

#### 6. `mixins.md` `flutter_solo`

**28. Medium/High, форма. Пункт 2 вступления выдаёт исходы обеих попыток
раздела о стриме (план:1213–1216).** «Shows nothing until the next change»
и «keeps the old session's data when handed another» — ровно то, что раздел
показывает как результат первой и второй попыток. Загадка раздела пропадает.
Это дух решения 86 (карта не выдаёт исход первой попытки). План спорит сам
с собой: совет 4 отвергает строку «handed another session» именно по этой
причине.

Как чинить: назвать, о чём раздел, без результата: «a badge over `stream` that
must show the state from its first frame».

Вердикт: принято: пункт называет, о чём раздел, без исхода — «a badge over
`stream` that must show the state from its first frame».

Итог: сделано коммитом страницы
`docs(flutter_solo): open mixins.md with what it covers`. Вводка стала «This
page is about three things around the mixin:» вместо «answers three questions»:
второй пункт ни на какой вопрос больше не отвечает.

**29. Low, нагрузка. Правка 2: новая фраза о цепочке повторяет следующую.** Как
чинить: слить в одну.

Вердикт: принято: одна фраза.

Итог: сделано тем же коммитом страницы иначе: цепочка влита в прежнюю фразу «A
mixin sits above the class written before `with`», а следующая фраза осталась,
потому что её держит `_says`. Повтора нет, но предложений два.

**30. Low, нагрузка. Вторая строка таблицы снимков («Without initialData»)
повторяет доказательство первой попытки внутри второй и добавляет шесть
строк.** Как чинить: убрать строку или оставить прозу.

Вердикт: принято: строка уходит, в таблице снимков одна строка — или проза,
если таблица из одной строки не нужна; решает исполнитель по тексту.

Итог: таблица снимков не заводилась вовсе, правка 4 не делалась: без строки
«Without initialData» в ней осталась бы одна строка, а её говорит прежняя
проза.

Сверено: таблица цепочек (Правка 3) верна, предложение по тесту годится.
Ограничения раздела плана (план:1165–1180) точны: шесть `text`-блоков,
`_quotes()[4]` и `[5]`, `strayFences`, якоря из `CHANGELOG.md`
и `tool/build_site_test.py`. Фразы вступления 640 и 642 в `_says` сохраняются.

### Согласованность терминов между страницами

- hears/answers: держится на всех шести; по решению 16 менять не надо.
- observe: в ядре `errors.md` пункт 3 первой группы употребляет его шире
  определения страницы (находка 6).
- zone: ядро говорит «the zone the body runs in», `solo` — «the creation zone».
  Это разные зоны по смыслу, и обе верны, но в правках `solo` стоит одна фраза,
  что это зона, где создан контроллер.
- Модель пути ошибки расходится между двумя errors (находка 22).

### Вердикты по страницам

**`packages/async_job/doc/errors.md` — делать с правками.** Две фразы
вступления и вводки неверны (находки 4 и 5, обе опровергнуты зондами), их надо
исправить до правки страницы. Остальное — мелочь нагрузки (6–9). Механика
сторожей в плане верна.

**`packages/async_job/doc/groups.md` — делать с правками.** Утверждение 5
верно, но формулировку «waits for the decision» стоит поправить (10). Карту
ужать (11), чтобы рост ушёл от предела плана.

**`packages/async_job/doc/extending.md` — делать с правками.** Таблица
`check()` проверена зондом и полна, план `holders` верен. Восстановить черновик
П3 и трассу в четыре строки (1, 14), поставить демонстрацию перед указателем
(15).

**`packages/solo/doc/errors.md` — делать с правками.** Утверждение 6 верно. Две
клетки большой таблицы надо переписать (18, 19), «third row of the scheme»
заменить (20). Модель мест согласовать с ядром (22).

**`packages/solo/doc/testing.md` — переделать часть с камерой, остальное
с правками.** Наследование `_QueuedCamera` от `final class` не скомпилируется
(23, проверено `dart analyze`). Поле `FakeCamera` в публичном коде (24)
и таблица симптомов, раздувающая вступление (25), требуют решения
до исполнения. Фраза о `fakeAsync` неверна для раздела решения 97 (26).
Черновики п. 4 и п. 6 восстановить (1), таблицу вынуть из ```text (2).

**`packages/flutter_solo/doc/mixins.md` — делать с правками.** Пункт 2
вступления выдаёт исходы попыток (28): переписать, не называя результата.
Остальное мелочь (29, 30). Таблица цепочек и тест к ней годятся.
