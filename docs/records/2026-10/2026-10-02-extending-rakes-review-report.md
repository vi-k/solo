> **Состояние на 2026-10-02:** все двенадцать находок разобраны; принятые
> закрыты тем же коммитом, что и сама вычитка.
> **Что это:** независимое ревью вычитки `packages/async_job/doc/extending.md`
> до коммита: ревьюер на Opus в своей копии дерева, его текст целиком
> и вердикт в конце каждой находки.
> **Связанные записи:** `2026-10-02-extending-rakes-report.md`.

# Ревью вычитки `packages/async_job/doc/extending.md`, 2026-10-02

Ревьюер работал в копии дерева с незакоммиченной вычиткой, на `149e3af` и шести
изменённых файлах. Номера строк страницы в находках — по странице, какой она
была до правок по этому ревью. Файлы ревьюера —
`.artifacts/2026-10-02-extending-rakes/reviewer/`: зонды R1–R10
в `reviewer_probe_test.dart`, мутации `c…` и `p…` в `mutate_reviewer.py`, `t…`
в `mutate_pages.py`. Зонды я повторил в рабочем дереве, вывод совпал
с приведённым строка в строку.

## Итог

Коммитить в нынешнем виде не советую: на странице три места уровня Medium, где
текст либо неверен, либо ведёт читателя в ловушку (находки 1–3), и одна дыра
сторожа уровня Medium (находка 6). Дефектов ядра не нашёл. Гейт зелёный,
перевод по смыслу совпадает с оригиналом.

## Находки

### 1. Medium. Совет звать `reportToZone` через обёртку теряет ошибку ребёнка другого вида

Страница, строки 81–83: «When that `onUnanswered` has nobody to hand an error
to, `reportToZone` of the job, reached through a wrapper as `start` is, hands
it to the zone the job was created in and keeps a cancellation out of the zone
the way the core does.»

`onUnanswered` получает `Job<Object?>`, обёртка есть только у `MyJob`, значит
читатель напишет `(job as MyJob)._report(...)`. Предыдущий абзац сам говорит,
что ответ доходит до детей, принятых без наблюдателя, а такой ребёнок может
быть обычной `Job.deferred`.

Зонд R5: наблюдатель `ThroughWrapper` на `MyJob`, ошибка в `unattended` у самой
задачи и у ребёнка `Job.deferred`.

```text
R5 ThroughWrapper: zone=[StateError: Bad state: of MyJob, _TypeError: type '_DeferredJob<void>' is not a subtype of type 'MyJob<Object?>' in type cast]
R5 ThroughSuper: zone=[StateError: Bad state: of MyJob, StateError: Bad state: of a plain child]
```

Ошибка ребёнка пропала, в зону ушёл `TypeError`.
`super.onUnanswered(job, error, stackTrace)` делает то же, что `reportToZone`,
для любой задачи ядра (`lib/src/observer.dart`, тело по умолчанию зовёт
`job._toZone`). Именно этому учит раздел, на который страница ссылается:
`doc/observing.md:306`.

Почему у `solo` это не ломается: `packages/solo/lib/src/solo.dart:913` приводит
к `_SoloJob` с комментарием «Every job that reaches this hook is one of this
controller's». Движок страницы таких гарантий не даёт.

Предлагаю: первым назвать `super.onUnanswered(job, error, stackTrace)`,
а `reportToZone` оставить для движка, чей ответ живёт вне наблюдателя,
с оговоркой, что обёртка есть только у его собственных задач. Сторожу добавить
случай из R5.

Вердикт: принято. Ловушку поставила сама вычитка: до неё страница о обёртке
не говорила. Итог: абзац первым называет
`super.onUnanswered(job, error, stackTrace)` и говорит, что ребёнок, принятый
без наблюдателя, может не быть задачей движка; `reportToZone` — для движка, чей
ответ живёт вне наблюдателя, через обёртку и только у своих задач. Сторожа —
`super.onUnanswered sends on the error of a child of another kind`
и `reportToZone hands the error to the zone the job was created in`.

### 2. Medium. Отказ ждущей задачи, написанный по тексту, оставляет задачу ждать вечно

Страница, строки 179–181: «If a job of your queue may turn one down while it
waits, return from `cancelWith` before the call to `super` when `rejectable` is
`true`, as `solo` does.»

В `cancelWith` страницы перед `super` стоит `_queue?._waiting.remove(this);`
(строки 157–160). Зонд R7, три прочтения фразы:

```text
R7 whenRejectable: [second runs, at 15 ms: status=running, second ran to its end, outcome: Done(null)]
R7 whenRejectableAfterRemove: [at 15 ms: status=created, outcome: null]
R7 whileCreated: [second runs, at 15 ms: status=running, outcome: Cancelled(manual)]
```

- `return` прямо перед `super`, то есть после строки с `remove`: задача ушла
  из очереди, не кончена и не стартует никогда. Это та самая беда, от которой
  раздел лечит.
- `if (rejectable) return;` первой строкой без проверки статуса: задача
  отказывает и после старта, отменить её нельзя.
- Работает только `status == JobStatus.created && rejectable` первой строкой.
  Так написан `StubbornJob` сторожа (`test/extending_rakes_test.dart:172–178`),
  так же (через «в очереди») делает `solo`
  (`packages/solo/lib/src/job.dart:104–114`).

`JobStatus` вступление обещает третьим типом (строки 9–10), а дальше страница
его ни разу не использует; здесь ему и место. Тест
`a waiting job turns a cancellation down by returning before super` ловушку
не видит: `StubbornJob` не стоит в очереди.

Предлагаю: «return from `cancelWith` first, before the job leaves the queue,
while `status` is `JobStatus.created` and `rejectable` is `true`», и в стороже
поставить такую задачу в `MyQueue`.

Вердикт: принято, иначе. Вместо прозы страница показывает саму строку —
`if (status == JobStatus.created && !cancellable && rejectable) return;` —
и говорит, что `cancelWith` возвращается первым делом, раньше, чем задача уйдёт
из очереди. Конструктор `MyJob` на странице принимает `super.cancellable`: без
него отказывать было бы некому. Блоков на странице стало семнадцать. Сторож —
`PatientJob` в `MyQueue` страницы,
`a job that refuses first of all waits on in the queue`; мутация, которая
ставит отказ после ухода из очереди, краснит его.

### 3. Medium. «ends with that cancellation whatever `finish` is handed» неверно для поданного `Cancelled`

Страница, строки 312–314: «A job that has accepted a cancellation ends with
that cancellation whatever `finish` is handed, and a value handed in goes
nowhere.»

Зонд R3, задача приняла `cancel()`, затем движок зовёт `finish`:

```text
R3 accepted manual (isCancelled=true isFinished=false), handed Done: Cancelled(manual) heard=[]
R3 accepted manual (isCancelled=true isFinished=false), handed Failed: Cancelled(manual) heard=[engine.onError(MyJob<int>): Bad state: handed in]
R3 accepted manual (isCancelled=true isFinished=false), handed Cancelled: Cancelled(signed out)
```

Поданный `Cancelled` остаётся исходом. Это написано в dartdoc `finish` («A
[Cancelled] handed in stands», `lib/src/job_base.dart:1162`) и сторожится:
мутация c18, которая делает фразу страницы буквально верной, красит
`test/cancel_test.dart: an engine that finishes the job from a cancel
callback`. Фраза стояла и в `HEAD`, но вычитка отвечает за страницу целиком.

Предлагаю: «…ends `Cancelled` whatever `finish` is handed: a value or a failure
handed in gives way to the cancellation the job accepted, and the value goes
nowhere; only another `Cancelled` handed in stands.»

Вердикт: принято. Итог: «ends `Cancelled` whatever `finish` is handed: a `Done`
or a `Failed` gives way to the cancellation the job accepted, a value handed in
goes nowhere, and only another `Cancelled` handed in stands». Сторож прежний,
`cancel_test.dart`.

### 4. Low. Абзац о `finish` молчит про `onCancel` и детей, а пример закрывает соединение именно в `onCancel`

Страница, строки 308–311: «it waits for no children and unwinds no cleanup
stack: no `onDispose` and no `discard` runs, and what the body opened stays
open.»

Зонд R2, `finish(Cancelled)` у идущей задачи с `onCancel`, `onDispose`,
`onDiscard`, `dispose:`, `discard:` и ребёнком:

```text
R2 [outcome at once: Cancelled(signed out); child: null, child ran to its end, body went on after finish, child at the end: Done(null)]
R2 debug: [Job() finished with 4 cleanups pending]
```

Не вызвано ничего, включая `onCancel`, хотя подан `Cancelled`. Ребёнку
не сказано остановиться, он доработал до `Done`. Тело тоже пошло дальше.
Написанное на странице верно, но читатель, чей пример закрывает соединение
в `onCancel`, ответа про него не получает.

Попутно: `onDispose` — имя метода, `discard` — имя вида уборки. `cleanup.md`
называет пару `dispose`/`discard` (строки 23–27).

Про детей сторожа нет: мутация c27 (`finish` руками говорит детям остановиться)
даёт 0 красных и в `async_job` (1048), и в `solo` (830).

Предлагаю: «it waits for no children and stops none, runs no `onCancel`
callback and unwinds no cleanup stack: no `dispose` and no `discard` runs».
Добавить в сторож случай из R2.

Вердикт: принято. Итог: «it waits for no children and stops none, runs no
`onCancel` callback and unwinds no cleanup stack, so no `dispose` and no
`discard` runs». Сторож — `finish by hand stops no child and runs no onCancel`;
c27 краснит его.

### 5. Low. Перечень путей в `cancelWith` читается как полный, и приход двух из трёх никто не сторожит

Страница, строки 147–148: «Every cancellation asked of a job arrives at
`cancelWith`: `cancel()`, the cascade from a parent, `cancelOwnJob` of its
context.»

Зонд R4:

```text
R4 cancel(): [Cancelled(manual) rejectable=true status=running]
R4 cascade: [Cancelled(parent) rejectable=true status=running]
R4 cancelOwnJob: [Cancelled(signed out) rejectable=false status=running]
R4 runAll sibling: [Cancelled(sibling) rejectable=true status=running]
R4 then cancelled: [Cancelled(chain) rejectable=true status=running] -> Cancelled(chain)
R4 held: [Cancelled(manual) rejectable=true status=running, Cancelled(manual) rejectable=true status=running]
R4 the rule: [] -> Cancelled(signed out) hooks=[started, finished]
```

- Само утверждение верно. Но после двоеточия названы три пути, а есть ещё
  остановка ветки `runAll` (`lib/src/run_all.dart:239`) и отмена продолжения
  `then`, которая идёт к источнику (`lib/src/job_then.dart:40`).
- Отмена, придержанная `uncancellable`, приходит в переопределение дважды:
  когда просят и когда секция закрывается. Для `remove` страницы это безвредно,
  для неидемпотентного учёта читателя нет.
- Мутации c21a (каскад идёт мимо переопределения) и c21b (`cancelOwnJob` идёт
  мимо) дают 0 красных в `async_job` и в `solo`. Сторожится только `cancel()` —
  очередью страницы.

Предлагаю: «…: `cancel()`, the cascade from a parent, `cancelOwnJob` of its
context among them», одна фраза о том, что придержанная приходит снова, и тест
на `CountingJob` для каскада и `cancelOwnJob`.

Вердикт: принято частично. Итог: перечень открывается словами «among them»
и не выдаёт себя за полный; тест
`the cascade and cancelOwnJob arrive at cancelWith as well`, c21a и c21b
краснят его. Фраза о придержанной отмене на страницу не встала: в разделе
об очереди секции `uncancellable` нет, и слово без предмета в примере туда
не пишется. Она в dartdoc `cancelWith`: придержанная отмена приходит через
переопределение второй раз, когда секция закрывается.

### 6. Medium (сторож). `under:` зелен впустую, когда заголовка нет; ещё три способа испортить страницу незаметно

`test/support/page_code.dart`, `test/extending_rakes_test.dart:802–817`.
Мутации страницы, прогон всего пакета:

| Мутация | Красных |
| --- | --- |
| p05: заголовок «### Leaving the queue on cancellation» переписан, под ним `add` первой попытки | 0 |
| p01: блок ответа `check()` с забором ` ``` ` вместо ` ```dart `, `super.check()` убран | 0 |
| p02: из ответа выброшен целый кусок `MyQueue? _queue;` | 0 |
| p03: первая строка куска обрезана слева до `(ctx) async {` | 0 |
| p04: подводки «The user cancels…»/«…signs out…» у ответа поменяны местами | 0 |
| p06: `super.check()` убран внутри куска | 2 |
| p07: строка сценария выброшена внутри куска | 2 |
| p08: цитата изменена | 1 |
| p09: `add` первой попытки под заголовком ответа | 1 |

- p05 — главное. `codeMissingFrom(..., under: heading)` для отсутствующего
  заголовка собирает пустой текст и возвращает пустой список
  (`page_code.dart:56–61`). Тест зелен по неверной причине: он ничего
  не проверил. p09 показывает, что с заголовком на месте та же подмена ловится.
  Нужно утверждение, что под заголовком нашёлся хотя бы один блок.
- p01: оба регулярных выражения видят только ` ```dart ` и ` ```text `
  (`page_code.dart:64`, `extending_rakes_test.dart:793`).
  `check_translations.py` ловит это, только если испорчена одна страница: t4 —
  exit 1, t3 (обе страницы одинаково) — exit 0. Нужно требование, что других
  заборов на странице нет.
- p02: проверяется только то, что на странице есть. Выброшенный кусок
  не замечает никто.
- p03: `source[start].endsWith(piece.first)` (`page_code.dart:37`) принимает
  любой хвост первой строки. Послабление сделано для строки теста, которая
  передаёт выражение страницы помощнику; сузить его до этого случая.
- p04: проза подводок не сторожится — это ожидаемо, называю для полноты.

Русская страница: t1 (строка кода убрана только в переводе) и t2 (цитата
изменена только в переводе) дают `check_translations.py` exit 1.

Вердикт: принято, кроме p02 и p04. Итог: `codeMissingFrom` с `under:` бросает
`StateError`, когда под заголовком нет кода, и p05 красный. `strayFences`
в `page_code.dart` и тест `the page has no fence the checks do not read`: p01
красный. Хвост первой строки принимается, только когда перед ним в строке теста
стоит `=>`, `=` или `return`: p03 красный, а единственный законный случай
во всём пакете — `Job<void> opening() => ` в `cancellation_rakes_test.dart` —
проходит. p02 и p04 не взяты: сторож держит правду того, что на странице есть,
а не её полноту и не прозу подводок.

### 7. Low. Утверждения страницы без сторожа

Все верны (проверено чтением кода или зондом), но мутация ядра ничего
не красит.

- Строки 62–63, «`started()` runs … with the job already running». c14 (статус
  `running` ставится после `started()`): 0 красных в `async_job` и в `solo`.
- Строки 81–83, «hands it to the zone the job was created in». c10
  (`reportToZone` шлёт в текущую зону): 0 красных в `async_job`; в `solo` 2
  красных (`test/errors_rakes_test.dart: … the zone of last resort is the one
  the job was created in`,
  `test/zone_test.dart: a rule that throws reaches the zone`). Страницу ядра
  сторожит только пакет над ним.
- Каскад и `cancelOwnJob` в переопределение `cancelWith` — находка 5.
- Дети задачи, законченной руками, — находка 4.

Сторожатся, но не в `extending_rakes_test.dart`: `wait` спрашивает правило
до действия (c13b, `extending_test.dart`), ошибка `finished()` идёт в `onError`
и к ответу (c15, c15b), продолжение объявляет принятый провал (c23), отладочный
канал называет число уборок (c26), `finish` не гоняет уборки (c28), принятая
отмена сильнее `Done`/`Failed` (c29), старт на микротаске (c30), три типа вне
основного импорта (c31), `finish` не зовёт `onCancel` (c32).

Вердикт: принято. Итог: `HookJob.started` сторожа записывает статус задачи,
и c14 краснит `a started that throws is told, and the job runs to its end`;
зону создания держит
`reportToZone hands the error to the zone the job was created in`, c10 красный;
каскад, `cancelOwnJob` и дети — тесты находок 5 и 4. Все пять мутаций, выживших
у ревьюера по ядру, после правок красные в стороже страницы.

### 8. Low. Тесты, которые проверяют не совсем то, что говорит страница, и устаревшие комментарии

- `test/extending_rakes_test.dart:352–376`,
  `a continuation answers to whoever called then`:
  `reason: "the caller's zone"`, но задача и `then` созданы в одной зоне, зоны
  тест не различает. Зонд R6 разводит их: `R6 engine zone: []`,
  `R6 caller zone: [Bad state: unattended in then, Bad state: of the job,
  Bad state: of the job, Bad state: body of then]`. Там же видна фраза «as the
  continuation's own»: `R6 caller heard: [caller.onError(_ThenJob<int,
  void>): Bad state: of the job]`. Утверждение страницы верно.
- `:378–391`, `reportToZone keeps a cancellation out of the zone`: зону
  создания не проверяет (c10).
- `:419–438`, `taking the job out in finished() …`: крутит свой цикл
  (`waiting.first.._launch()`), а не `MyQueue` страницы. Зонд R1 с `MyQueue`
  дословно и уходом в `finished()`:
  `R1 [second: Cancelled(manual), third runs, the queue is empty]`. Обе
  половины сравнения верны; тест показывает другую очередь.
- `:440–461`: задача не в очереди — находка 2.
- `:53`, комментарий «Not on the page: the wrapper its last paragraph on the
  rule speaks of»: последний абзац страницы об обёртке не говорит (строки
  304–307).
- `test/support/extending_first_attempts.dart:72`, «The same queue with a third
  job behind the cancelled one»: после правки третья задача есть и в самом
  `runQueue`.
- Два теста `mustCallSuper holds …` ищут текст аннотации в исходнике. Сам
  анализатор проверен отдельно (`analyzer_probe.sh`): без `// ignore:` —
  `warning - extending_first_attempts.dart:35:8 - … must_call_super`, для
  `cancelWith` без `super` — то же, для `start()` снаружи —
  `invalid_use_of_protected_member`.

Вердикт: принято. Итог: тест продолжения создаёт задачу в одной зоне и зовёт
`then` в другой; уход в `finished()` идёт через `MyQueue` первой попытки
дословно, `first.runQueueLeavingInFinished`; оба комментария поправлены,
и последний абзац страницы теперь говорит об обёртках. Тесты аннотаций
оставлены как есть.

### 9. Low. Глазами читателя

- Строки 163–173: под ответом очереди цитата стоит сразу за однострочным `add`,
  без подводки. У ответа правила подводки добавлены. Вступление обещает «The
  lines under the code are what it prints», а печатает сценарий из предыдущего
  подраздела. Вариант: «The same run now goes on:».
- Строка 308: «`finish` is no way to stop a running job.» — возражение
  на реплику, которой читатель не слышал: `finish` до этого на странице
  не назван. В `HEAD` абзац сперва говорил, что `finish` делает. Вариант:
  «`finish` ends a job with the outcome handed in, and it is no way to stop a
  running one: it waits…».
- Строки 304–307: «cancels the job itself … through `cancelWith` with
  `rejectable: false`». Читатель спросит, как это написать: `cancelWith`
  защищён (нужна обёртка, как у `start` — о `reportToZone` страница это
  говорит, здесь нет), какой `Cancelled` подать, откуда движок знает идущие
  задачи. Третьей попытки не прошу; хватит «through a wrapper, as `start` is»
  и «with the `Cancelled` its rule throws».
- Строка 148: `cancelOwnJob` назван впервые и без пояснения; что это, сказано
  только в строках 181–183 и 306.
- Строка 65: «on to the answer of the observer» стоит абзацем раньше, чем
  страница говорит, что такое ответ.
- Местоимения с двумя хозяевами: строка 14 «which it exports too» (движок или
  библиотека); строка 188 «says whether they are» (jobs или user); строки
  150–151 «keeps the queue that holds it and takes itself out of it there»;
  строка 307 «which passes it».
- Два слова для одного: страница говорит «turn down» (179, 180, 182, 298, 307),
  `cancellation.md` — «refuses» (строки 294, 314), параметр зовётся
  `rejectable`.
- Одно слово для разного: «hold» — анализатор «holds the override to», очередь
  «holds» задачу, секция «holds» отмену, правило «no longer holds», задача
  «holds» ресурс. Рядом стоят «a rule that no longer holds» (243) и «holds the
  rule back» (298).
- Строка 195: «The job downloads rows…» — определённый артикль у задачи,
  которую ещё не показали.
- Соглашение о ссылках (`docs/conventions.md`: раздел другой страницы назван
  заголовком и вместе со страницей):
  `[`onUnanswered`](observing.md#an-observer)`,
  `[unattended work](observing.md#work-the-job-does-not-wait-for)`,
  `[Children](children.md#children)`. Было и в `HEAD`.

Слов нашей кухни в тексте не нашёл. Обещание вступления о строении двух
разделов держится: оба открываются «### The first attempt», ответ под своим
заголовком.

Вердикт: принято; «hold» — частично. Итог по пунктам: цитата очереди получила
подводку «The same run now reaches the third job:»; абзац о `finish` сначала
говорит, что он делает; движок отменяет «with the `Cancelled` its rule throws»
и «through wrappers of its own, as with `start`»; `cancelOwnJob` при первом
упоминании — «the one the engine asks for itself»; ответ наблюдателя при первом
упоминании ведёт в раздел «An observer» страницы о наблюдении; четыре
местоимения развязаны; «turn down» по всей странице стало «refuse»; три ссылки
названы заголовком раздела и страницей. «Hold»: анализатор теперь «requires»,
очередь «keeps», правилу ничто не «stands in the way»; секция по-прежнему
«holds» отмену, как на `cancellation.md`, и «a rule that no longer holds»
осталось.

### 10. Low. Перевод

Смысл совпадает фраза за фразой, комментарии во фрагментах переведены. Тире
в прозе нет, «джоба»/«фьюча» нет (grep пуст), `Job` и `MyJob` женского рода
(«Обычная `Job`», «`MyJob` помнит очередь, которая её держит»). Любая правка
оригинала по находкам 1–5 и 9 идёт с правкой перевода.

Корявое и кальки, с вариантом:

- Строки 181–185, 301, 312: «отказывается от отмены», «отказывают отмене»,
  «отказаться не может» — два управления на одной странице,
  а `docs/ru/async_job/cancellation.md:293, 314` говорит «отклоняет». Вариант:
  везде «отклоняет отмену».
- Строка 185: «такую отмену просит» → «о такой отмене просит» (выше — «отмена,
  о которой просят»).
- Строки 144–145: «Очередь всё ещё держала её, и когда подошла её очередь» —
  «очередь» в двух значениях подряд. Вариант: «и когда до неё дошёл черёд».
- Строка 153: «и там же из неё уходит» → «и в `cancelWith` уходит из этой
  очереди».
- Строка 294: «выход из аккаунта кончает задачу `Cancelled`» → «а после выхода
  из аккаунта задача кончается `Cancelled`».
- Строки 313, 318: «поданным исходом», «что бы ни подали», «поданное значение»
  → «переданным ему исходом», «что бы ни передали», «переданное значение».
- Строка 58: «обращается к задаче сбоку» → «со стороны».
- Строка 9: «говорит, где задача в своей жизни» → «показывает, на каком этапе
  жизни задача».
- Заголовок «### Своя отмена движка» → «### Собственная отмена движка».

Вердикт: принято. Итог: все девять вариантов взяты; правки оригинала
по находкам 1–5 и 9 перенесены в перевод, `check_translations.py` зелёный.
Сканер `humanizer-ru` после правок — 90 из 100, запретов и тире нет.

### 11. Low. Что правка унесла

Верного и нужного не пропало.

- Убранное из раздела очереди «A body that gives itself up does not come
  through it» переехало в раздел правила (строки 296–297) и сторожится
  (`a body that gives itself up does not come through cancelWith`). Хвост «its
  job has left the queue by then» не нужен.
- «It is the one member of the lifecycle…» убрано справедливо: `@mustCallSuper`
  стоит и на `check`, `finish`, `startChild`.
- Осталось старое слово: шапка dartdoc `JobBase`,
  `lib/src/job_base.dart:416–418` — «the subclass opens exactly what it needs
  through private wrappers of its own: `@protected` holds inside a subclass».
  Страница от «opens»/«holds inside» ушла, dartdoc `cancelWith` поправлен,
  шапка класса нет.
- Устаревшие комментарии тестов — в находке 8.

Вердикт: принято. Итог: шапка dartdoc `JobBase` говорит «hands out exactly what
it needs through private wrappers of its own: a `@protected` member is for the
subclass alone».

### 12. Замечание к коммиту

В правке нет `docs/handoff.md` и записи в `docs/records/`; `AGENTS.md` требует
их в одном коммите с работой.

Вердикт: не подтверждено. Копия для ревьюера снята раньше, чем написана запись
и поправлен `docs/handoff.md`; оба идут тем же коммитом.

## Дефекты ядра

Не нашёл. Два наблюдения, оба по контракту: придержанная отмена приходит
в `cancelWith` дважды (R4), и `onUnanswered`, который бросает, отдаёт в текущую
зону свою ошибку вместо исходной (R5; хук наблюдателя, который бросает, так
и описан в `observer.dart`).

## Проверено и держится

Прогоны в копии:

- `packages/async_job`: `dart format --output=none --set-exit-if-changed .` —
  57 файлов, 0 изменено; `dart analyze` — «No issues found!»; `dart test` —
  «+1048: All tests passed!»; `dart doc --dry-run` — «Found 0 warnings and 0
  errors».
- Корень: `reflow.py --check` — «every paragraph is filled to 79 columns»;
  `check_line_width.py` — «no Markdown line over 79 columns»;
  `check_links.py` — «every document link resolves»; `check_translations.py` —
  для пары `extending.md` «headings: 9 in the same order», «code blocks: 16 in
  both files», «no differences»; `check_doc_shape.py` — «every section opens
  with code or a table».
- `packages/solo`: `dart test` — «+830: All tests passed!» (база для мутаций).
- После всех мутаций: формат, анализ и 1048 тестов снова зелёные.

Мутации: 34 по ядру, 9 по странице, 4 по страницам против питоновских проверок,
5 повторены на наборе `solo`. Каждый файл восстановлен копией и сверен
побайтно. Без красных по ядру: c10, c14, c21a, c21b, c27. Без красных
по странице: p01–p05.

Утверждения, верные по зонду или коду и со сторожем:

- Цитаты всех шести прогонов — то, что печатает код (p08;
  `every quote on the page…`).
- `finished()` у задачи, снятой до старта, без `started()` (c01: 4 красных, 2
  в стороже страницы).
- `whenDone` не наблюдает, `done` наблюдает (c06: 13 красных; R8: `whenDone` →
  `zone=[Bad state: lost]`, `done` → `zone=[]`).
- Ошибка `started()`/`finished()` идёт в `onError` и к ответу, задача доходит
  до конца (c15, c15b, c16; R8).
- Ребёнок без наблюдателя берёт родительского, со своим — отвечает через своего
  (c08a: 61, c08b: 10).
- Продолжение `then` не получает наблюдателя движка (c07: 3).
- `reportToZone` не пускает отмену в зону (c09: 3).
- Ядро заканчивает нестартовавшую задачу, что бы ни говорил `cancellable` (c19:
  3).
- `@mustCallSuper` на `cancelWith` и `check()` (c04, c05, зонд анализатора).
- Кто и когда спрашивает `check()`: `wait`, `join`, `uncancellable`
  до действия, `join` после, `run` по значению ребёнка, `runAll` перед
  значениями (c13a–c13f, все красные). `wait` после возврата не спрашивает
  (c11: 4; R9: внутри `uncancellable` после шага тоже не спрашивают).
- Первая попытка правила: `join` отдаёт строки отменённой задаче,
  `uncancellable` начинает шаг, `wait` и `run` бросают отмену сами (c13a, c13c,
  тест `under the first attempt uncancellable begins…`).
- Ответ правила: тело сдаётся, `onCancel` и дети останавливаются, задача
  принимает отмену не раньше выхода из тела, в `cancelWith` она не приходит
  (тесты зелёные; R4 `the rule: []`).
- `rejectable: false` не держат ни `cancellable: false`, ни `uncancellable`
  (c02: 3, c03: 5). Движок отменяет сам: `onCancel` сразу, `wait` рвётся сразу,
  `join` бросает по возврату (R10: `wait` — всё на 10 мс; `join` — «10 ms:
  close the connection, 20 ms: join threw Cancelled(signed out)»).
- `Job.debug = print;` компилируется (R2), канал называет число уборок (c26,
  `debug_test.dart`).
- `engine.dart` экспортирует `async_job.dart` и три типа; в основном импорте их
  нет (c31).
- Обычная `Job` стартует на следующей микротаске (c30: 131).
- Соглашения в изменённых файлах: поля выше конструкторов в коде
  и во фрагментах обеих страниц; комментарии в коде по-английски; ширина
  держится (`dart format`, `check_line_width.py`).
