> **Состояние на 2026-10-24:** семь находок из двенадцати исправлены тем же
> заходом — D1, D2, D4, D5, D6, D7 и D10, итоги в вердиктах; D8 оставлена как
> есть, пункт 108 `docs/settled.md`. D3, D9, D11 и D12 и советы для 10 ждут
> решения владельца — вопросы в конце записи.
> **Что это:** второе перечитывание восьми страниц после деления длинных
> страниц, на этот раз Fable: оценка каждой страницы, шаги до 10, пары как
> целое, швы и ссылки. Двенадцать находок: 1 Medium, 11 Low.
> **Связанные записи:** `2026-10-24-split-pages-reread-review.md` (первое
> перечитывание, Astra и Sol), `2026-10-23-split-long-pages-plan.md` (само
> деление), `2026-10-22-async-job-project-review.md` (вопрос 2, прежние оценки
> Fable).

# Перечитывание разделённых страниц: Fable

## Как это делалось

По слову владельца 2026-10-24 «ревью через Fable». Я понял его как то же
перечитывание, что у Astra и Sol, и так и сказал владельцу. Клон `main`
на `d3f7ef08` с разрешёнными зависимостями во всех пяти корнях —
`.artifacts/2026-10-24-fable-reread/tree`. Задание —
`.artifacts/2026-10-24-fable-reread/briefs/brief.md`, то же, что у Astra и Sol,
со старыми версиями страниц из `git show 93539d68:<путь>` и решениями 105–107.

| Ревьюер | Модель и вызов | Время |
| --- | --- | --- |
| Fable | `claude-fable-5-1`, субагент `general-purpose` | 1276 с, 45 вызовов инструментов |

Отслеживаемых файлов Fable не тронул. Инструмент записи файлов харнесс ему
не дал, поэтому четыре зонда он писал через оболочку. Полных наборов, стенда
и сборки сайта не запускал и сказал это сам. Отчёт —
`.artifacts/2026-10-24-fable-reread/out/fable.md`.

Зонды я прогнал в своей копии на `d3f7ef08`, вывод совпал с отчётом. Решающий
для D6:

```text
queued jobs after the additions: 3
a2 is a group of its own: true
starts: [R starts@0, A[a1]@1500, B@1500, A[a2]@2500]
```

Копии зондов — `.artifacts/2026-10-24-fable-reread/mine/probes/`.

## Страницы

| Страница | Fable | Astra | Sol | Fable до деления |
| --- | --- | --- | --- | --- |
| `async_job/doc/extending.md` | 8 | 8,5 | 9 | 6 |
| `async_job/doc/engine.md` | 9 | 8 | 8 | — |
| `async_job/doc/cleanup.md` | 8 | 8,5 | 9 | 6 |
| `async_job/doc/cleanup-rules.md` | 8 | 8,5 | 8,5 | — |
| `async_job/doc/errors.md` | 9 | 8,5 | 9 | 6 |
| `async_job/doc/error-rules.md` | 8 | 8 | 8 | — |
| `solo/doc/accumulation.md` | 8 | 8,5 | 8,5 | 6 |
| `solo/doc/accumulation-rules.md` | 7 | 8 | 8,5 | — |

Astra и Sol читали `9bcd71d6`, до волны советов, Fable — `d3f7ef08`, после неё.
Против своих прежних оценок Fable поднял первые страницы на 2–3 балла. Числа
трёх ревьюеров разошлись не больше чем на балл, а один прогон — один бросок,
поэтому главное в таблице то же: деление не повредило ни одной странице. Хуже
всех у Fable `accumulation-rules.md` и хвост `cleanup-rules.md`: страницы
правил, где проза идёт абзацами, а не списком или таблицей. `engine.md`
и `errors.md` у него лучшие.

## Пары

Деление помогло всем четырём парам, и швы верны по содержанию.

- **`extending.md` и `engine.md`.** Граница настоящая — задача против очереди.
  Вторая страница читается без первой, если принять четыре имени на веру.
  Помогло сильнее всех.
- **`cleanup.md` и `cleanup-rules.md`.** Правила «что можно колбэку» переехали
  в ответ первой страницы — по сути верно, но ответ потяжелел, и с ними пришёл
  абзац-шов D3. Обратная ссылка грубая (D4), один повтор в одну фразу (D8).
- **`errors.md` и `error-rules.md`.** Единственная скрытая зависимость — места
  из вступления первой страницы, которые на второй не названы (D5). Помогло
  умеренно: первая страница всё ещё самая длинная из первых страниц ядра.
- **`accumulation.md` и `accumulation-rules.md`.** Вторая страница — бывший
  «Reference» почти дословно, обе правки волны советов к лучшему, кроме
  пересечения D6. Не сделано: правила внутри рецепта настроек (D9).

Повторов решений из `docs/settled.md` Fable не поднимал.

## Находки

### D1. Low: проза «Guides» считает четыре страницы, а строк пять

`packages/solo/README.md`, «Guides»: «The next four come when a controller
needs what they cover: resources, children, streams, accumulation». После
деления строк накопления две — добавились «Accumulation rules». «Diagnostics»
абзац не называл и до деления.

Вердикт: принято, дефект деления. Исправлено: «The next five…: resources,
children, streams, accumulation and its rules. Diagnostics, errors and testing
are for a controller about to ship». Перевод `packages/solo/README.ru.md`
тем же коммитом.

### D2. Medium: пункт `discard` в README ядра ведёт не туда

`packages/async_job/README.md`, «Quick start»: пункт о `discard` говорит, что
база закрывается при `Failed` или `Cancelled` и остаётся открытой при
`Done(database)`, и ведёт на «Cleanup order and late results»
на `cleanup-rules.md`. Объясняет это таблица в «`dispose` for what the job
keeps» на `cleanup.md`; до деления ссылка хотя бы вела на ту же страницу.

Вердикт: принято, дефект деления. Исправлено, как предложено: ссылка
на `doc/cleanup.md#dispose-for-what-the-job-keeps` с названием раздела. Перевод
`packages/async_job/README.ru.md` так же.

### D3. Low: абзац «Two releases do not wait for the stack» непонятен на первой странице

`packages/async_job/doc/cleanup.md`, «`dispose` for what the job keeps». Абзац
отсылает к контрольной точке, бросающей на только что пришедшем значении,
и к позднему значению — оба понятия вводит только `cleanup-rules.md`. Fable
предлагает перенести абзац туда, под таблицу шагов «Cleanup order and late
results». Утверждение абзаца верно, зонд `probe_cleanup_arrival.dart` это
показывает.

Вердикт: не принято без владельца. Этот абзац добавлен по D1 записи
`2026-10-24-split-pages-reread-review.md`: Astra и Sol нашли, что без него
первая страница обещает, что отмена не прерывает никакой уборки. Перенос вернёт
неполное обещание, оставить — шум для новичка. Вопрос 1 ниже.

### D4. Low: обратная ссылка на правила колбэка ведёт на верх раздела

`packages/async_job/doc/cleanup-rules.md`, «Cleanup order and late results»:
«What a callback may do while it runs is at the end of Choosing the callback»
ведёт на `cleanup.md#choosing-the-callback`, а абзацы о колбэках стоят в конце
H3 «`dispose` for what the job keeps», через первую попытку, трассу и таблицу.

Вердикт: принято, дефект деления. Исправлено, как предложено: ссылка
на `cleanup.md#dispose-for-what-the-job-keeps` с названием раздела. Перевод
`docs/ru/async_job/cleanup-rules.md` так же.

### D5. Low: «места» таблицы правил ошибок не названы на её странице

`packages/async_job/doc/error-rules.md`, «Where each error goes», первая фраза:
«The table shows which places of the introduction of Errors each error passes».
Сами места на странице не названы, а приходят на неё по ссылкам из `chains.md`,
`testing.md`, `extending.md` и dartdoc `observer.dart` и `job_base.dart`.

Вердикт: принято. Исправлено одной фразой перед прежней: ошибка проходит места
из вступления «Errors» по порядку — `onError`, исход, фильтр
`Job.isCancellationError`, ответ и зону. Перевод
`docs/ru/async_job/error-rules.md` тем же коммитом. Заодно доделан совет 7
записи `2026-10-24-split-pages-reread-review.md`: на этой странице оставались
«Rarer ways» и «These are the ways of a branch», в переводе — три «пути»;
теперь «routes» и «маршруты».

### D6. Low: пункты 2 и 3 списка `startAtOnce: false` пересекаются

`packages/solo/doc/accumulation-rules.md`, «Choosing when a group is ready».
Когда вторая группа накопителя появляется за чужой задачей, пока первая ждёт,
верны оба условия: «an interval still running» и «another group of its own
queued». Пункт 2 обещает готовность по концу идущего интервала, пункт 3 — целый
интервал от старта другой группы. Зонд `probe_throttle_adjacent.dart`
показывает, что прав пункт 3: `A[a2]@2500`, через секунду после старта `A[a1]`,
а не по концу интервала, начатого в 0. Пересечение внесла моя правка по совету
3 записи `2026-10-24-split-pages-reread-review.md`.

Вердикт: принято. Исправлено, как предложено: пункт 2 начинается с «Nothing of
its own queued or running, and an interval still running from the previous
start». Перевод `docs/ru/solo/accumulation-rules.md` так же. Тесты этот пункт
не цитируют.

### D7. Low: `printer` на `engine.md` появляется из ниоткуда

`packages/async_job/doc/engine.md`, «A rule of your own»:
`MyJob<void>(observer: printer, …)`. На страницах `printer` не определён, он
живёт в `test/support/extending_stubs.dart`. Было и до деления.

Вердикт: принято. Исправлено во вступлении: «The job's observer, `printer`,
prints what reaches it». Перевод `docs/ru/async_job/engine.md` так же.

### D8. Low: фраза о `ctx.disown` стоит на обеих страницах уборки

`cleanup.md`, «Closing what the job keeps back», и `cleanup-rules.md`,
«Registering without a call»: `ctx.disown` ищет значение по идентичности
и возвращает, нашёл ли, поэтому передавать надо тот самый экземпляр. Fable сам
считает повтор оправданным.

Вердикт: оставить. Первая страница вводит `disown` и без правила дала бы
неверный вызов, вторая говорит о том же вызове в своём договоре. Пункт 108
`docs/settled.md`.

### D9. Low: правила внутри рецепта «Settings…»

`packages/solo/doc/accumulation.md`, рецепт «Settings saved on every flip of a
switch»: абзацы об одном писателе, клиентском таймауте и дедлайне `timeout` —
правила, а не рецепт. Fable предлагает оставить фразу со ссылкой, а разбор
перенести в «Start, cancellation and errors» на `accumulation-rules.md`.

Вердикт: редакционный шаг, вопрос 2 ниже.

### D10. Low: список «Limits of the filter» разорван блоком кода

`packages/async_job/doc/error-rules.md`: первый пункт кончается блоком кода
в нулевой колонке, и список продолжается после него — второй пункт читается как
новый список.

Вердикт: принято. Исправлено первым вариантом Fable: три абзаца вместо пунктов,
код — между первым и вторым. Перевод `docs/ru/async_job/error-rules.md` так же.

### D11. Low: абзацы после списка `startAtOnce: false` идут россыпью

`packages/solo/doc/accumulation-rules.md`, «Choosing when a group is ready»:
старт до `onStart`, отказ правил не тратит интервал, слот до 500 мс,
`queue.jobs`, `Duration.zero`, общий `timing`, порядок таймеров — без зачинов.
Fable предлагает список с жирными зачинами, как «What keeps an error out of the
answer», без подзаголовков (решение 106).

Вердикт: редакционный шаг, вопрос 3 ниже.

### D12. Low: оговорка о движке во второй фразе `errors.md`

`packages/async_job/doc/errors.md`, вступление: «A cancellation the job catches
goes no further than `onError`, unless an engine ends the job `Failed` with
it». Редкий случай второй страницы стоит до таблицы мест. Fable предлагает
оговорку убрать.

Вердикт: вопрос 4 ниже. Оговорка пришла коммитом `5c88338c` вместе с таблицей
мест, и без неё фраза неверна: такая отмена доходит до зоны.

## Что хорошо и трогать не надо

Устройство `engine.md` — попытка, трасса, нумерованный разбор, исправление,
таблица, сборка «The whole engine»; вход `cleanup.md` с кодом и таблицей пяти
членов; таблица пяти мест и «Reporting each error once» на `errors.md`;
вступления вторых страниц, которые называют, чей код продолжают; новый абзац
о `then`, `shared()` и `merge` в «Recipes»; «`replace` moves a group's job to
the tail»; строки «Guides» обоих README.

## Вопросы владельцу

1. **D3.** Абзац «Two releases do not wait for the stack» на `cleanup.md`:
   оставить, перенести на `cleanup-rules.md` или сжать до одной фразы
   со ссылками. Я за последнее: обещание первой страницы остаётся честным,
   а понятий второй страницы в нём не будет.
2. **D9.** Правила рецепта «Settings…» перенести на `accumulation-rules.md`,
   оставив фразу со ссылкой. Я за: это продолжение решения 105.
3. **D11.** Россыпь абзацев на `accumulation-rules.md` собрать в список
   с жирными зачинами. Я за: Fable оценивает шаг в +1,5, это самая слабая
   страница.
4. **D12.** Оговорку о движке во вступлении `errors.md` оставить. Я за то,
   чтобы оставить: без неё фраза неверна.
5. **Прочие советы для 10** — в таблице отчёта Fable, по +0,5 каждый.
   `extending.md`: сказать у кода, что `_launch` и `_untilFinished` зовёт
   очередь с `engine.md`; фразу о `creationZone` в `ctx.unattended` — в два
   предложения; абзац «Two narrow cases are in the dartdoc…» — списком.
   `engine.md`: у `account.onSignOut` оговорить, что движок обходит все свои
   задачи. `cleanup.md`: абзац о ветке `runAll` и зависании сжать до ссылки
   на `groups.md`. `cleanup-rules.md`: строка «тело ушло от вызова без отмены»
   в таблице поздних значений; заметку об `unawaited` — к коду. `errors.md`:
   «когда исход считается наблюдённым» — списком. `error-rules.md`: последнюю
   строку «Rare routes» — на две. `accumulation.md`: фразу о `merge`
   в «Settings…» — до ссылки. `accumulation-rules.md`: договор `merge` —
   списком из пяти пунктов.
