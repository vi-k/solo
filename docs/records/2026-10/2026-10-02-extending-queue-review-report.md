> **Состояние на 2026-10-02:** все девять находок разобраны; принятые закрыты
> тем же коммитом, что и перестройка раздела.
> **Что это:** независимое ревью перестроенного раздела «A queue of your own»
> страницы `packages/async_job/doc/extending.md` до коммита: ревьюер на Opus
> в своей копии дерева, его находки и вердикт в конце каждой.
> **Связанные записи:** `2026-10-02-extending-rakes-report.md`,
> `2026-10-02-extending-rakes-review-report.md`.

# Ревью раздела об очереди в `extending.md`, 2026-10-02

Раздел перестроен по чтению владельца — пункт 8 раздела «По чтению владельца»
отчёта `2026-10-02-extending-rakes-report.md`. Ревьюер работал в копии дерева
с незакоммиченной правкой: страница, перевод, сторож
и `test/support/extending_first_attempts.dart`. Отчёт он написал по-английски;
здесь находки пересказаны по-русски, цитаты страницы, ядра и вывода зондов
оставлены как есть. Его файлы —
`.artifacts/2026-10-02-extending-rakes/reviewer2/`: зонды P1–P10
в `review_refusing_probe_test.dart`, Q1–Q3
в `review_refusing_probe2_test.dart`, мутации `r…` в `mutate_reviewer2.py`.

## Итог ревьюера

Главная линия раздела верна: первая попытка честная, трассы правильные
и устойчивые, каждая фраза о ядре сходится с ядром. Находок уровня High нет.
Три находки Medium — дыра в отказывающем переопределении, фраза, выдающая
обещание движка за свойство ядра, и пробел сторожа — и шесть Low. Гейт в копии
зелёный: формат, анализ, `dart test`, пять документных проверок.

О честности первой попытки: очередь такая, какую и пишут, а ошибка — доверие
документированному флагу на ожидании, которого у ядра нет: у `Job` оно длится
одну микрозадачу, в очереди сколько угодно. Проект сам на это наступал —
комментарий в `packages/solo/lib/src/job.dart`: «Left to the core it would not:
a job that has not started is `created`, and `created` is finished without
asking.» Более простого верного ответа ревьюер не нашёл: вариант «стартовать
каждую задачу в `add` и ждать черёда внутри `execute`» обходится без
переопределения, но задача тогда числится работающей, пока ждёт, а его версия
в двенадцать строк дала четвёртой задаче обогнать вторую; переопределение
`cancel()` пропустило бы каскад.

## Находки

### 1. Medium. Переопределение отклоняет отмену у любой `MyJob` в статусе `created`, а не только у ждущей в очереди

Фразы: «`status` is `created` until the queue starts the job» и «`MyJob`
refuses while it waits what it would refuse while it runs, as `solo` does».

`MyJob(cancellable: false)`, переданная в `ctx.run` или `ctx.runAll` родителя,
который уже принял отмену, тоже `created`. Ядро снимает такого ребёнка через
`cancelWith` с `rejectable: true` (`job_context.dart`, `_refuseChild` →
`_cancelChild`). Переопределение страницы возвращается до `super`, и ребёнок
остаётся `created` навсегда.

```text
P4 core alone   : run threw Cancelled(manual); parent=Cancelled(manual); child.outcome=Cancelled(parent) child.isChild=true child.done completed=true
P4 answer's MyJob: run threw Cancelled(manual); parent=Cancelled(manual); child.outcome=null child.isChild=true child.done completed=false
P5 runAll threw Cancelled(manual); a: JobStatus.created null, b: JobStatus.created null
```

Об этом состоянии предупреждают комментарии самого ядра: «a job like that, left
alive, would sit half-adopted: parented, levelled, never started and waited for
by nobody». У `solo` дыры нет, и «as `solo` does» буквально неверно: он смотрит
не на статус, а на то, стоит ли задача в очереди
(`packages/solo/lib/src/job.dart`,
`final queued = _solo._queue._jobs.contains(this);`). High ревьюер не поставил:
сам `ctx.run` бросает в тело, виснет только тот, кто держит ребёнка.

Предложено одно из двух: условие `!isChild` или членство в очереди, как
у `solo`; в обоих случаях — сторож на отказывающего ребёнка отменённого
родителя.

**Вердикт: принято, членством в очереди.** Мутация m9 в рабочем дереве — отказ
по статусу вместо очереди — подтверждает находку: тест на ребёнка краснеет.
`MyJob` снова хранит `_queue`, очередь ставит его в `add`, а `cancelWith`
отклоняет отмену, пока `_queue._waiting` содержит задачу; условие на статус
ушло. `!isChild` закрыл бы ребёнка, но оставил бы задачу, которую никто
не ставил в очередь: отменённая, она висела бы так же. Страница говорит: «Only
a job that waits in the queue refuses. A `MyJob` nobody queued is left to the
core, such as one a cancelled parent turns away from its `ctx.run`». Сторож —
`a job in no queue is left to the core: a parent turns it away`. Подробности —
пункт 8 в `2026-10-02-extending-rakes-report.md`.

### 2. Medium. «A job created with `cancellable: false` is one the user cannot cancel» читается как факт, а ядро говорит другое

`job_base.dart`, ветка `case JobStatus.created:` —
`finish(withStarted(false));` без взгляда на `_cancellable`. Соседняя страница,
`cancellation.md`: «It refuses ordinary cancellation once the body starts, but
can still be cancelled before start.» Dartdoc `Job.cancel`: «before that there
is no body to protect, and a job cancelled then is dropped like any other».
Фраза — обещание этого движка, и сама страница спорит с ней полусотней строк
ниже. Здесь же может вернуться возражение владельца: у ядра есть названная
причина снять ждущую задачу, а страница не говорит, почему движку нужно больше.

Предложено: сказать это требованием движка.

**Вердикт: принято.** Требование теперь говорит от имени движка: «In this
engine a job created with `cancellable: false` is not to be cancelled while it
waits either». Почему движку нужно больше, сказано под первой попыткой словами
самого ревьюера о честности попытки: «A regular `Job` starts on the next
microtask, so there the time before the start is a moment; in a queue it lasts
as long as the jobs ahead take.» Перевод поправлен в тех же местах. Вторую
из этих фраз владелец при чтении снял — пункт 9 раздела «По чтению владельца»
в `2026-10-02-extending-rakes-report.md`: она отвечала ревьюеру, а не читателю.

### 3. Medium. Пробел сторожа: копии `MyQueue` и `runQueue` в файле ответа ни к чему не привязаны

Страница показывает очередь и сценарий один раз, под первой попыткой, и сверка
кода находит их только в `extending_first_attempts.dart`. Копии
в `extending_rakes_test.dart` могут разойтись, а страница говорит «The same
run». Три мутации остались зелёными:

```text
r1 answer run: cancel() not awaited (no longer "the same run"): GREEN
r2 answer run: third job dropped from the answer queue order: GREEN
r10 answer queue: waits with done instead of _whenDone: GREEN
```

Предложено: тест, который сравнивает текст двух объявлений между файлами.

**Вердикт: принято, с поправкой на находку 1.** После неё очереди двух файлов
различаются строкой `add`, поэтому тест
`the answer keeps the run and the loop of the first attempt` сравнивает
`runQueue` целиком и метод `run()` очереди, а строку `add` ответа держит сверка
кода под заголовком ответа. Мутации m10 и m11
в `.artifacts/2026-10-02-extending-rakes/mutate_queue.py` — r1 и r10 ревьюера —
теперь красные.

### 4. Low. Условие `status == JobStatus.created &&` не меняет ни одного исхода

Без него сторож зелёный, зонд P7 на семи случаях даёт те же исходы; разница
только в отладочном канале. Фраза «from then on the core refuses for it» верна,
но объясняет условие, без которого ответ обходится.

**Вердикт: снято находкой 1.** Условия на статус в ответе больше нет.

### 5. Low. Пример с `cancelOwnJob` не может случиться в ветке, которую объясняет

Фраза: «`rejectable` is `false` for a cancellation no job may refuse, such as
the one `cancelOwnJob` asks for, and that one goes on to `super`.» У ждущей
задачи нет контекста: `createContext()` зовётся внутри старта.

```text
P6 two jobs in the queue, first running: contexts built = 1
```

До ждущей задачи отмена с `rejectable: false` доходит только через обёртку
вокруг `cancelWith`.

**Вердикт: принято.** Фраза называет этот путь: «such as one the engine sends
through a wrapper around `cancelWith` to drop a job whatever `cancellable`
says».

### 6. Low. `await second.cancel()` в запуске ответа ждёт, пока вторая задача отработает, а страница этого не говорит

```text
0ms cancel() returned; second: JobStatus.created, isCancelled=false
10ms second runs
10ms await second.cancel() completed; second: Done(null), third: JobStatus.created
```

Порядок строк устойчив: одинаков на настоящих таймерах и под `fakeAsync`
и не зависит от того, когда эта future завершается. Если очередь никто
не запускает, future не завершится никогда.

**Вердикт: принято.** После вывода ответа добавлена фраза: «`cancel()` returns
a future that waits for the job to be over, refused or not, so here it
completes once the second job has run.» Тест
`the refusal is for a cancellation the job may refuse, no other` проверяет, что
future не завершена, пока задача ждёт, и завершена после.

### 7. Low. Вступление: «a queue that counts on `cancellable: false` to hold while a job waits»

«Hold» на этой странице — то, что секция делает с отменой, в противовес отказу:
«they refuse or hold a cancellation asked of the job». `cancellable: false`
отклоняет, а не придерживает.

**Вердикт: принято.** Стало «to protect a job while it waits», в переводе —
«защищает задачу и пока она ждёт».

### 8. Low. Перевод: одно слово в двух противоположных смыслах и две кальки

«Пропускает задачу» значит «обходит», а «Чтобы пропустить отмену» — «дать
пройти», и читается как «не заметить отмену». «Переопределение возвращается
до этого вызова» и «Тот же запуск теперь даёт второй задаче её черёд» — кальки.

**Вердикт: принято.** «Чтобы отмена прошла, переопределение передаёт её
в `super`», «выходит до этого вызова», «В том же запуске вторая задача теперь
выполняется в свой черёд».

### 9. Low. `docs/handoff.md` и шапка отчёта описывают прежний раздел

Число тестов сторожа и фраза о `finished()` в `docs/handoff.md`, шапка
`2026-10-02-extending-rakes-report.md`.

**Вердикт: принято.** Копию для ревьюера я снял до правки этих двух файлов; оба
обновлены тем же коммитом.

## Что ревьюер проверил и счёл верным

Фразы «The core finishes a job that has not started on the spot», «Every
cancellation asked of a job arrives at `cancelWith`», «the analyzer requires
that call to be there», «To refuse one, the override returns before the call».
Дважды отменённая ждущая задача отклоняет оба раза; отклонённая отмена
не воспроизводится при старте — `isCancelled` ложно, исход `Done`. Остальная
страница перестройке не противоречит, ссылок на прежний заголовок нет.
Из шестнадцати его мутаций одиннадцать красные, зелёные — r1, r2, r10 (находка
3), r3 (находка 4) и r24, которая не утверждение страницы.

Не проверял: поведение `solo` для ребёнка читал по исходнику, не запускал;
сборку сайта, стенды и `floor` не гонял; разделы вне очереди читал
на противоречия, с ядром заново не сверял.
