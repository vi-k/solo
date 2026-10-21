> **Состояние на 2026-10-21:** ревью второй волны сделано, все находки
> приняты, кроме N3 доли r1 (пункт 98 `docs/settled.md`); исправления — тем же
> коммитом, что эта запись.
> **Что это:** два независимых ревью второй волны читаемости на Opus, коммиты
> `d3ddb417..cea4ae19`, с вердиктом и итогом каждой находки.
> **Связанные записи:** `2026-10-21-core-readability-wave-plan.md`,
> `2026-10-21-readability-wave-report.md`,
> `2026-10-21-async-job-project-review.md`, `2026-10-21-solo-project-review.md`
> (L7).

# Ревью второй волны читаемости

Волну смотрели два ревьюера на Opus, каждый в своей копии дерева на `cea4ae19`
(база `58c2d334`), по общему заданию: потеря утверждений, проверка новых
утверждений, читаемость с оценкой страниц, переводы, тесты, проверки. Доля r1 —
`cleanup.md`, `extending.md`, `outcomes.md` ядра; доля r2 — `cancellation.md`,
`time.md`, `groups.md`, `chains.md` ядра и `cancellation.md` `solo`. Отчёты
ниже — как написаны, после каждой находки — вердикт.

## Доля r1

Копия `r1`, detached `cea4ae19`, база `58c2d334`. Коммиты: `d3ddb417`
(`cleanup.md`), `0530653e` (`extending.md`), `1f24f85b` (`outcomes.md`). Тесты
этих страниц волна не меняла.

### 1. Страницы

| Страница | До | После | Почему |
| --- | --- | --- | --- |
| `cleanup.md` | 6 | 7 | Длинных фраз 11 → 0, у таблицы поздних значений правило стоит первым и верно для всех трёх строк. Но абзацы о ветке `runAll` по плану остаются в общем потоке, а при делении фраз потерялись две связки: «but» и двоеточие (L1, L2). |
| `extending.md` | 6 | 7 | Хуки, ответ движка и хвосты `finish` стали списками, правило стоит над ними. Вводная фраза «Deferred start» сжата и перестала говорить, когда брать `Job.deferred` (L3). Страница остаётся тяжёлой, но её читатель — автор движка. |
| `outcomes.md` | 7 | 8 | Хвост «Listening for the cancellation» разложен на два подписанных списка, и правило ищется глазом. При этом один пункт вышел из своей оговорки (H1). |

`metrics.py` той же копией (слов на фразу / фраз длиннее 35 слов): `cleanup.md`
18.9/11 → 16.8/0, `extending.md` 19.6/6 → 18.1/0, `outcomes.md` 17.3/4 →
16.5/0. Это совпадает с «Итогами коммитов» плана.

### 2. Находки

**H1. `outcomes.md`: пункт о `Cancelled` слушателя потерял оговорку
«синхронный» и стал неверен для `async`-слушателя**

`packages/async_job/doc/outcomes.md:405`, перевод
`docs/ru/async_job/outcomes.md:405`.

Было (один абзац, открытый словом «synchronous»):

> A synchronous listener error goes to `onError` and then to the job's creation
> zone, unless the observer catches it in `onUnanswered`, … Without an
> observer, it goes straight to that zone. A thrown `Cancelled` is never
> forwarded to the zone.

Стало (отдельный пункт списка «What becomes of a listener's error:»):

> - A `Cancelled` a listener throws is never forwarded to the zone.

Двумя пунктами ниже стоит «An error of an `async` listener is an uncaught one
of the zone the listener was called in». Прежде «A thrown `Cancelled`» стояло
в абзаце о синхронной ошибке, и оговорка «synchronous» была на нём. Теперь это
самостоятельный пункт про любого слушателя. `async`-слушатель, который делает
`throw Cancelled(...)`, по-английски тоже «throws», а страница сама говорит,
что `async`-функция не бросает только *синхронно*. Зонд в копии
(`scratch-r1/probe/listener_cancelled.dart`, задача без наблюдателя внутри
`runZonedGuarded`, `cancel()` извне):

```text
--- sync Cancelled
--- async Cancelled
zone: Cancelled Cancelled(handler: from async listener)
--- sync Cancelled, observer
onError: Cancelled
```

`Cancelled` из `async`-слушателя доходит до зоны. Пункт в новой форме читается
как обещание, что не дойдёт, и спорит с пунктом об `async`-ошибке. Это ровно
тот дефект, о котором предупреждают «Правила волны»: оговорка охватывала пункт,
а после деления осталась при соседнем. Перевод повторяет то же: «Брошенный
слушателем `Cancelled` в зону не передаётся».

Предлагаю вернуть оговорку в пункт: «A `Cancelled` a synchronous listener
throws is never forwarded to the zone.» / «`Cancelled`, брошенный синхронным
слушателем, в зону не передаётся». Или влить фразу последней в первый пункт,
о синхронной ошибке. Если стоит держать и обратный случай, к пункту
об `async`-ошибке можно добавить «a `Cancelled` included»: ядро этот путь
не фильтрует. Это уже новое утверждение, и ему нужен сторож.

**Вердикт.** Принято: в `58c2d334` фраза «A thrown `Cancelled` is never
forwarded to the zone» стояла в абзаце о синхронной ошибке слушателя,
а отдельный пункт обобщил её на `async`-слушателя, чей `Cancelled` по зонду
доходит до зоны. Итог, тем же коммитом, что эта запись: «A `Cancelled` a
synchronous listener throws is never forwarded to the zone» / «`Cancelled`,
брошенный синхронным слушателем, в зону не передаётся». Сторожа у фразы не было
и нет.

**L1. `cleanup.md`: «but» снято, и пропала оговорка, что значение, пришедшее
после стека, освобождается уже после закрытия пула**

`packages/async_job/doc/cleanup.md:519–521`, перевод
`docs/ru/async_job/cleanup.md:514–515`.

Было: «One that comes after it is released at once too, but the stack has run
by then, the callback that closes the pool included, and only the end of the
branch waits for the release.»

Стало: «One that comes after it is released at once too. The stack has run by
then, the callback that closes the pool included, and only the end of the
branch waits for the release.»

Сам факт на месте. Пропало противопоставление: абзацем выше сказано, что
колбэк, зарегистрированный раньше («the one that closes the pool»), ждёт конца
освобождения. Для ветки, к которой значение пришло после стека, этот порядок
не держится, и это говорило «but». Без связки две фразы читаются как «так же,
как выше», хотя пул уже закрыт. Бриф прямо называет такую перемену: «и» вместо
«но». В переводе то же («тоже освобождается сразу. Стек к тому времени…»).
Предлагаю: «But the stack has run by then, …» / «Но стек к тому времени уже
размотан…».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: «But the stack has
run by then» / «Но стек к тому времени».

**L2. `cleanup.md`: причина отделилась от правила, которое она объясняет**

`packages/async_job/doc/cleanup.md:504–507`.

Было: «The callback does not wait for the unwinding: a child the job is still
waiting for may want the same lock or slot of a pool, and a value held for the
unwinding would keep it from that child for good.»

Стало: «The callback does not wait for the unwinding, and a release that begins
before the job ends keeps the job from ending until the release is over. A
child the job is still waiting for may want the same lock …»

Новое правило верно для всех трёх строк таблицы (H2 ревью плана закрыто).
Но причина про ребёнка, которому нужен тот же замок, теперь идёт сразу после
второй половины правила, о конце задачи, и читается её объяснением.
Объясняет же она первую половину: почему колбэк не ждёт размотки. Предлагаю
поменять порядок: «The callback does not wait for the unwinding: a child … for
good. A release that begins before the job ends keeps the job from ending until
the release is over.» Правило по-прежнему стоит первым, а каждая причина — при
своём утверждении.

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: первой идёт «The
callback does not wait for the unwinding», сразу за ней — причина о ребёнке,
которому нужен тот же замок, и последней — «A release that begins before the
job ends keeps the job from ending until the release is over»; перевод так же.
С предложенным разошлось тем, что «не ждёт размотки» и причина остались двумя
фразами: одной выходило больше 35 слов.

**L3. `extending.md`, «Deferred start»: вводная фраза потеряла «когда брать»
и сузила способы старта до двух**

`packages/async_job/doc/extending.md:558–561`, перевод
`docs/ru/async_job/extending.md:570–573`.

Было: «A regular `Job` schedules its own start on the next microtask. If the
caller needs to choose when work begins, use `Job.deferred(body)` instead. It
returns a `DeferredJob<T>` with a public `start()` method. You can call it
yourself, let a queue start the job, or pass it to a parent with
`ctx.run(child)`, …»

Стало: «Where a plain `Job` starts on the next microtask, `Job.deferred(body)`
returns a `DeferredJob<T>` that waits for its public `start()` or for the
`ctx.run` of a parent, …»

Две перемены. Пропало назначение: «если момент старта выбирает вызывающий». Его
можно вывести из «waits for», но это ответ на вопрос, с которым читатель
открывает раздел. Перечень вариантов («you can… or…») стал формой «waits for X
or Y», а она читается исчерпывающей. Между тем задачу `Job.deferred` запускают
ещё `ctx.start` (так на `cleanup.md`, «Cancellation after the body returns»)
и `ctx.runAll`. Очередь осталась только в комментарии кода и в следующем
абзаце. Предлагаю: «A plain `Job` starts on the next microtask;
`Job.deferred(body)` waits for whoever starts it — you, a queue, or a parent
through `ctx.run` — and returns a `DeferredJob<T>` with a public `start()`.»
Мелочь того же места: «Where …» в значении «whereas» читается как «там, где».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: вступление
«Deferred start» снова говорит, когда брать `Job.deferred` («If the caller
needs to choose when work begins»), и перечень снова начинается с «You can»:
вызвать `start()` самому, отдать очереди, передать родителю через
`ctx.run(child)`. Перевод так же. `ctx.start` и `ctx.runAll` в перечень
не дописаны: его форма «можно» не обещает полноты, как не обещала до волны.

**N1. `cleanup.md`: «Unlike the checkpoint …, a plain `await` is no
checkpoint» — тавтология**

`packages/async_job/doc/cleanup.md:387–390`.

Было: «…and the checkpoint of The second attempt is why it is worth naming: a
plain `await` is no checkpoint, so nothing can throw…»

Стало: «Unlike the checkpoint in The second attempt, a plain `await` is no
checkpoint: …»

Ничего не потеряно: противопоставление и есть причина, по которой раздел нужен.
Но фраза «в отличие от контрольной точки — не контрольная точка» пустая.
Подсказать читателю, что именно там бросало, можно так: «In The second attempt
the checkpoint in `run` throws between the call and the registration; a plain
`await` is no checkpoint: nothing can throw between the call and the line under
it.»

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: «A plain `await`
is no checkpoint, unlike the `ctx.run` of [The second attempt]» / «Обычный
`await`, в отличие от вызова `ctx.run` из раздела …, контрольной точкой
не служит». Контрольная точка второй попытки — `ctx.run`, так её называет
комментарий кода раздела.

**N2. Перевод `extending.md`: «Сколько уборок бросил `finish`»**

`docs/ru/async_job/extending.md:607`. На странице, где «бросает» везде значит
throws, «`finish` бросил уборки» читается как «бросил исключение». Прежнее
«брошено» было двусмысленно так же, но без подлежащего `finish` меньше.
Предлагаю: «Сколько уборок `finish` оставил несделанными, говорит только
отладочный канал…».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: «Сколько уборок
`finish` оставил невыполненными».

**N3. `outcomes.md`: пункт «The job does not wait for the future of such a
callback» стоит в группе «What becomes of a listener's error»**

`packages/async_job/doc/outcomes.md:408–412`. Это факт о вызове слушателя,
а не о его ошибке, и по заголовку групп ему место в первой. Он склеен
с соседней фразой про `async`-колбэк, поэтому вред небольшой. Можно оставить.

**Вердикт.** Не править: ревьюер сам допускает оставить. Фраза склеена
с соседней о синхронном колбэке, и вместе они вводят `async`-колбэк, о чьих
ошибках весь пункт. Решение — пункт 98 `docs/settled.md`.

### 3. Что проверено без находок

1. **Потеря утверждений.** Три страницы сравнены с `58c2d334` целиком,
   по утверждениям каждого изменённого куска. Вне кусков диффа текст тот же.
   - `cleanup.md`, восемь кусков: абзац о замке `runAll`; `ctx.disown` перед
     закрытием («ends the job `Cancelled`» → «may come … and end», факт
     тот же); два случая «closing falls to whoever holds the handle»; плоский
     `await`; «each of them is a checkpoint»; ожидание колбэков и `close()`
     `solo`; перечень членов, которые бросают `StateError` (перечень цел,
     «So» — следствие предыдущей фразы, решение 96); вторая волна `discard`;
     исключение ветки `runAll` (переставлено: исключение → почему группа держит
     ветку → до каких пор; все пять утверждений на месте, абзац последний,
     ссылка со строки 220 ведёт верно); таблица поздних значений (кроме L1–L2
     всё на месте, «In the first case» → «In the first row of the table», «this
     one» → «the callback of a late value»).
   - `extending.md`: хуки (вызов `started()`, `finished()` у снятой задачи,
     маршрут ошибки хука с оговоркой `onUnanswered`, «задача идёт дальше»,
     совет держать хуки короткими, сброс тела в `finished()`); ответ движка
     (наследование наблюдателя, исключение для ребёнка со своим наблюдателем,
     продолжение `then` — решение 8, `super.onUnanswered`, `reportToZone`,
     `throwIfUnattended`); «Finishing a job by hand» (все пять пунктов M5 ревью
     плана на странице, пункт об экземпляре — и для `cancelWith`, и для
     `finish`; оговорка «non-`async` тело, бросившее при запуске веток»;
     `ignoreFailure()` ветки гасит путь непойманного провала). Якорь
     `#finishing-a-job-by-hand` цел, на него ведёт `groups.md:153`.
   - `outcomes.md`: «Following the cause» (две фразы разделены без потерь);
     хвост слушателя — все пятнадцать фактов в двух списках. Обе оговорки плана
     при своих пунктах: «even if the job has finished» — только после начала
     прохода, «unless the observer catches it» — при синхронной ошибке.
     «Unregistering more than once is safe» перенесено к абзацу о функции
     снятия. Шесть фраз о зоне `async`-слушателя все на месте. Потерянная
     оговорка — H1.
   - Переписанные и удалённые фразы сверены по `docs/records/`: «The job does
     not end before the release is over» (`2026-10-02-cleanup-reread-report.md`
     требовал не цеплять её к колбэку — новое правило говорит о задаче и верно
     для всех строк таблицы); «worth naming»
     (`2026-09-28-cleanup-page-report.md`, ссылка на «The second attempt»
     сохранена); правило «`Cancelled` в зону не уходит»
     (`2026-09-08[10]-zone-cancelled-report.md`) — отсюда H1.
2. **Новые утверждения.** Абзац о `creationZone` в «Deferred start»:
   `creationZone` помечен `@protected` (`lib/src/job_base.dart:1200–1201`),
   `_launch` на странице — `creationZone.run(start)`. Верно. Правило над
   таблицей `finish` («Since `finish` unwinds nothing…») верно по третьей
   строке таблицы и решению 34. Правило под таблицей поздних значений верно для
   всех трёх строк. Строка 1 и строка 2 ждут освобождение до конца задачи,
   строка 3 начинается после конца. Оборот «cannot reach» строже кода:
   `@protected` — предупреждение анализатора, а не ошибка компиляции. Но так
   говорит о защищённых членах вся страница.
3. **Читаемость.** Оценки — в таблице. Рубленых фраз почти нет, связки
   обоснованы. Исключения — L1, L2 и N1. Слов без предмета в примере
   не появилось: «the queue» в «Deferred start» есть в коде («from a queue of
   your own»).
4. **Переводы.** Все изменённые абзацы трёх переводов идут абзац в абзац
   и пункт в пункт с оригиналом, смысл тот же. Русский естественный: «Ради
   этого группа и держит ветку», «Отмена чужой задачи проходит…»,
   «До `creationZone` у `Job.deferred` очередь не дотянется». Перевод разделяет
   H1 и L1. Мелочь — N2.
5. **Тесты.** Проверки этих страниц волна не меняла. Сторож `bodyMembers()`
   разбирает перечень после правки: мутация «убрать `start` из перечня
   `cleanup.md`» роняет `cleanup_rakes_test.dart`
   (`+77 -2: Some tests failed.`). Файл восстановлен копией, `git status` копии
   чистый. Дословные «On a cancelled job `check` throws the job's `Cancelled`
   instead» и «a `Cancelled` stops at `onError`» на месте, заголовки карт
   `holders` всех трёх страниц не менялись.

### 4. Проверки

Из корня копии `r1`, все с кодом выхода 0:

| Команда | Последняя строка |
| --- | --- |
| `python3 tool/reflow.py --check` | `every paragraph is filled to 79 columns` |
| `python3 tool/check_line_width.py` | `no Markdown line over 79 columns, no blank line doubled` |
| `python3 tool/check_translations.py` | `no differences` |
| `python3 tool/check_links.py` | `every document link resolves` |
| `python3 tool/check_doc_shape.py` | `every attempt opens its code with its mark` |
| `python3 tool/check_page_code.py` | `3 copies of packages/async_job/test/support/page_code.dart agree with it` |
| `dart test` в `packages/async_job` | `00:08 +1757: All tests passed!` |

## Доля r2

Копия `r2` (detached `cea4ae19`). Мои страницы:

- в `async_job`: `doc/cancellation.md`, `doc/time.md`, `doc/groups.md`,
  `doc/chains.md`;
- в `solo`: `doc/cancellation.md`;
- их переводы в `docs/ru/`.

Коммиты: `29bd6a6a`, `ddc67736`, `cea4ae19`. База сравнения — `58c2d334`.

### 1. Страницы

| Страница | До | После | Почему |
| --- | --- | --- | --- |
| `cancellation.md` ядра | 7 | 8 | Вступление разложено списком «что делают члены контекста». «A `Cancelled` that is not the job's» открывается правилом. Длинных фраз 9 → 0, и рубленых фраз не появилось. |
| `time.md` | 7 | 8 | Судьба таймера и оговорка о секции стали пунктами, а `ArgumentError` — своим абзацем. Вступление всё ещё требует помнить базу с другой страницы, и в нём появилась неточность (L1). |
| `groups.md` | 7 | 7,5 | Таблица «кто закрывает взятое» отвечает на вопрос раздела с одного взгляда. Есть мелочи: ячейка «No registration» (L2), местоимение «it» (L3), совет `.wait` теперь стоит раньше своего довода (N1). |
| `chains.md` | 7 | 7,5 | Вопрос «кто отвечает, если все ручки отменены» теперь закрыт на странице, оговорка таблицы разделена. «handle» на одной странице по-прежнему значит две вещи (L4). |
| `cancellation.md` `solo` | 7 | 7,5 | Длинные фразы разделены естественно, связки несут причину. Сама страница длинная и плотная, её форма не менялась (так и задумано). |

Длинных фраз по `metrics.py` после волны: 0, 0, 0, 0 и 1 (у `solo` это склейка
пунктов списка, как и сказано в плане).

### 2. Находки

High и Medium нет. Ни одно утверждение не потеряно и не искажено. Новые
утверждения верны. Сторожа не ослаблены.

**L1. `time.md`: «stops … once the token is cancelled» — миграция
останавливается не в момент отмены токена.**

`packages/async_job/doc/time.md:12–13`, перевод —
`docs/ru/async_job/time.md:11–12`.

Было: «reads a `CancelToken` before each, …; finding it cancelled, it stops by
throwing `DatabaseStopped`».

Стало: «Before each step the migration reads a `CancelToken`, … and stops by
throwing `DatabaseStopped` once the token is cancelled» (перевод: «когда токен
отменён»).

Заглушка `cancellation_stubs.dart:71–83` читает токен только перед шагом.
Текущий шаг она доделывает, и трасса раздела «A deadline of the job» это
показывает: `step 2` идёт до `migration stopped`. «once» читается как «как
только», то есть как немедленная остановка. Это лёгкий сдвиг: первая половина
фразы, «Before each step», его смягчает.

Ещё одна мелочь в той же фразе. Ссылка «the database of [Stopping the
operation]» ведёт в раздел, где `database.readAll` нет: этот вызов есть только
в коде вступления `cancellation.md`. Сама `cancellation.md` в этом разделе
по-прежнему говорит «finding it cancelled».

Предлагаю: «…and, finding it cancelled, stops by throwing `DatabaseStopped`»
(перевод: «а найдя его отменённым, останавливается, бросая `DatabaseStopped`»).
Ссылку оставить на страницу или на раздел, но не обещать, что `readAll` описан
там.

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: «The code works
with the database of the cancellation page», без ссылки на раздел, где
`readAll` нет; «finding it cancelled, it stops by throwing `DatabaseStopped`» /
«найдя его отменённым, она останавливается». Строки, которые держат тесты
(«reads the rows in 10 ms», «three steps of 10 ms», «every job on this page
runs with that line»), на месте.

**L2. `groups.md`: ячейка «No registration:» спорит с первым столбцом своей
строки.**

`packages/async_job/doc/groups.md:293`, перевод —
`docs/ru/async_job/groups.md:292`.

Было (до приёмки): «Nobody».

Стало: «No registration: the branch refuses the stop and ends `Done`, so the
`discard` does not run. The body closes the value through the branch's job, as
below». В переводе: «Никакая регистрация: …».

В первом столбце той же строки стоит «Any `discard`», то есть регистрация есть.
Ячейку легко прочесть как «регистрации нет». Имелось в виду «ни одна
регистрация не закрывает». «Никакая регистрация:» — ещё и не русская
конструкция. «The body» в ячейке таблицы, которая говорит о группе, не названо:
это тело родителя.

Предлагаю: «No registration closes it: the branch refuses the stop and ends
`Done`, so the `discard` does not run. The parent's body closes the value
through the branch's job, as below». В переводе: «Ни одна регистрация его
не закрывает: … Значение закрывает тело родителя через задачу ветки, как
показано ниже».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: «No registration
closes it: … The parent's body closes the value through the branch's job, as
below» / «Ни одна регистрация его не закрывает: … Значение закрывает тело
родителя через задачу ветки, как показано ниже».

**L3. `groups.md`: «or when it is cancelled» — «it» встаёт к ближайшему
существительному.**

`packages/async_job/doc/groups.md:102–104`.

Было: «…after the archive is written, when the other branch fails or is
cancelled, or when the parent is cancelled in between».

Стало: «The parent may end after the archive is written, when the other branch
fails or is cancelled, or when it is cancelled in between».

Ближайшее существительное — «the other branch», и «it» читается как «другая
ветка отменена». Прежняя фраза называла родителя. В переводе двусмысленности
нет: «его» не может быть «веткой».

Предлагаю вернуть имя: «or when the parent itself is cancelled in between».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: «or when the
parent itself is cancelled in between». Перевод двусмысленности не имел
и не правился.

**L4. `chains.md`: «through the handle» на странице, где «handle» — ручка
`shared()`.**

`packages/async_job/doc/chains.md:273–276`.

Было: одна строка «…`cancellable: false`, or it has finished… | The caller,
through the handle: …».

Стало: две строки и абзац под таблицей. «through the handle» стоит в них
трижды: «The caller, through the handle, the same way», «The caller closes the
rows through the handle the way…».

Тремя разделами выше «handle» — это ручка, которую делает `shared()`
(«`shared()` makes a handle…», «A handle for each branch»). Здесь же это ссылка
на задачу `opened`. Получается одно слово для двух предметов на одной странице.
Перевод их различает: «хэндл» и «ручка». Дефект старый, но волна его
размножила.

Предлагаю писать «through `opened`» или «through the job `opened`»: «The
caller, through `opened`: `(await opened.value).close()`».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: в двух ячейках
и абзаце под таблицей «through `opened`» / «через `opened`»; «handle»
на странице снова значит только ручку `shared()`.

**N1. `groups.md`: совет «…or when one of them waits for another» теперь стоит
раньше своего довода.**

`packages/async_job/doc/groups.md:163–165`.

Абзац «The branches of a group wait for one another… a branch that waits for a
sibling can hang the group» по плану ушёл в конец раздела. Совет взять `.wait`,
«когда одна ветка ждёт другую», теперь приходит без причины: она стоит двумя
абзацами ниже. Это сделано по плану, но читателю можно дать ссылку на месте,
например «…waits for another, as
[Branches that wait for each other](#branches-that-wait-for-each-other) shows».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: к совету дописано
«as in [Branches that wait for each other](#branches-that-wait-for-each-other)»
/ «как в разделе [«Ветки, которые ждут друг друга»]».

**N2. `time.md`: «The core observes nothing as it cancels the timer:» над
таблицей трёх способов.**

`packages/async_job/doc/time.md:198`.

Было: «It cancels the timer however else the job ends, and observes nothing as
it does:».

Стало: отдельная фраза о ядре, а под ней таблица, где две строки из трёх —
не ядро. Смысл тот же. Но связь «ничего не наблюдает, поэтому провал доходит
до зоны» читатель выводит сам, а введение говорит только о третьей строке.

Можно так: «The core observes nothing as it cancels the timer, so a failure
still reaches the zone. The three ways compare:». Это необязательно.

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: «The core observes
nothing as it cancels the timer, so with `timeout` a failure of the job still
reaches the zone:» / «…поэтому с `timeout` провал задачи по-прежнему доходит
до зоны:». Связь названа одной фразой, без второй вводной к таблице.

**N3. `groups.md`: «Their `discard`» в первом столбце второй строки берёт
предмет из соседней строки таблицы.**

`packages/async_job/doc/groups.md:291`, в переводе «Их `discard`».

Строку таблицы читают отдельно. Лучше «The `discard` of `ctx.abandonable` and
`ctx.join`, or `onDiscard`».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: «The `discard` of
`ctx.abandonable` and `ctx.join`, or `onDiscard`» / «`discard`
у `ctx.abandonable` и `ctx.join` или `onDiscard`».

### 3. Что проверено и не дало находок

**1. Потеря утверждений.** Пять страниц я сравнил по утверждениям, старую
версию с новой: `async_job/doc/cancellation.md`, `time.md`, `groups.md`,
`chains.md` и `solo/doc/cancellation.md`. Все утверждения на месте. Где именно:

- `cancellation.md` ядра:
  - перечень бросающих членов и `onCancel` — пункты;
  - самоотмена;
  - порядок колбэка позднего значения;
  - «a section holds back a request, not a cancellation the body throws» —
    теперь общей фразой перед случаем, смысл тот же;
  - «`cancel()` has no stronger form»;
  - сценарий миниатюры — после правила, перед кодом.
- `time.md`:
  - «starts the timer when the body starts…» переехало первым пунктом в «How
    the core runs the timer»;
  - дословная фраза о секции и таймере — пунктом при секции, её оговорка
    относится к этому пункту и раньше относилась к нему же;
  - `ArgumentError` и `cancellable: false` — своим абзацем.
- `groups.md`:
  - ссылка ведёт на `extending.md#finishing-a-job-by-hand`, и факт там есть,
    `extending.md:605–609`;
  - абзацы о взаимном ожидании веток и о передаче значений переехали в конец
    раздела;
  - старый абзац о владении стал первыми двумя строками таблицы;
  - «lives until the group succeeds in full… closes it if the group ends in
    anything else» о `discard` у `ctx.run` стало третьей строкой;
  - «One thing stays open» стало «The last row follows from», код под ней
    тот же.
- `chains.md`: строка «refuses it: `cancellable: false`, or it has finished»
  стала двумя строками. Сравнение с веткой группы ушло в абзац под таблицей.
- `solo`: все четырнадцать фраз только разделены. Оговорки остались при своём:
  «inside a section too», «before the handler starts», «built on top of
  draining, not inside it».

Сверка со старыми вердиктами: искал по `docs/records/` переписанные обороты.
«принявшая остановку» нашлась в `2026-09-26-async-job-project-review.md` (M
о `runAll`), и таблица с ней согласна. Остальные обороты в записях не нашлись.

Ссылки на перенесённые абзацы тоже проверил. `cleanup.md` и `chains.md` ведут
на `groups.md#what-a-group-hands-back`, и последняя строка таблицы с кодом
`cancellable: false` осталась в этом разделе.

**2. Новые утверждения.**

- Абзац `chains.md:126–132` о провале `loaded`, когда обе ветки отменены,
  сходится с:
  - второй строкой таблицы «When a link fails»;
  - кодом `job_shared.dart` (`_detach` в `finished()`,
    `_pendingContinuations`);
  - новым тестом.
- Таблица `groups.md`: каждую строку сверил со старой прозой и с разделом
  «Choosing the callback» на `cleanup.md`. Строки 1–3 верны, строка 4 верна
  по смыслу, но с формулировкой из L2.
- Правило «What the members of the context do on a cancelled job» верно для
  всех трёх пунктов под ним.
- «How the core runs the timer» верно для всех трёх пунктов.

**3. Читаемость.** Оценки — в таблице выше. Рубленых фраз я не нашёл. Связки
«With it», «That type», «Once …» несут предмет. «So» в начале фразы стоит
только там, где фраза — следствие (решение 96).

**4. Переводы.** Все пять переводов идут абзац в абзац с оригиналом, и смысл
тот же. Новые абзацы `chains.md` и таблица `groups.md` звучат естественно,
кроме «Никакая регистрация» (L2). Линтер `humanizer--ru` даёт 0 `ERROR` на всех
пяти файлах.

**5. Тесты.**

Новый тест `chains_rakes_test.dart` («every branch cancelled before loaded
fails…», два случая) я проверил двумя мутациями в копии. Откат — копированием
файла, после него `git status` чистый.

- Мутация из плана: тест отменяет только первую ветку. Результат `+0 -2`, оба
  случая красные: `continued` ждёт пусто, получает `['Bad state: offline']`.
- Мутация ядра: `JobShared.finished()` не делает `_detach()`. Результат
  `+0 -2`, оба случая красные.

Проверка в `solo/test/cancellation_rakes_test.dart:2373` поменялась только
в регистре: «A seek dragged past…». Фраза стала отдельной, факт и строгость
проверки те же.

Других изменённых проверок у моих страниц нет. Дословные цитаты теста `solo`
(строки 591, 1258, 2342, 2401, 2424, 2453, 2480, 2520), регулярки
`cancellation.md` и `time.md` ядра и стыки блоков `chains.md` держатся: наборы
зелёные.

**6. Проверки** — в разделе 4.

### 4. Проверки

Все — из корня копии `r2`, на `cea4ae19`, дерево чистое.

| Команда | Последняя строка |
| --- | --- |
| `python3 tool/reflow.py --check` | `every paragraph is filled to 79 columns` (exit 0) |
| `python3 tool/check_line_width.py` | `no Markdown line over 79 columns, no blank line doubled` |
| `python3 tool/check_translations.py` | `no differences` |
| `python3 tool/check_links.py` | `every document link resolves` |
| `python3 tool/check_doc_shape.py` | `every attempt opens its code with its mark` |
| `python3 tool/check_page_code.py` | `3 copies of packages/async_job/test/support/page_code.dart agree with it` |
| `dart test` в `packages/async_job` | `00:08 +1757: All tests passed!` |
| `dart test` в `packages/solo` | `00:02 +2033: All tests passed!` |
| `dart test` в `packages/solo/example` | `00:00 +112: All tests passed!` |

У всех шести питоновских проверок exit 0.
