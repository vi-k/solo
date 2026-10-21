> **Состояние на 2026-10-21:** ревью волны сделано, все находки приняты,
> три — частично; исправления — тем же коммитом, что эта запись; остаток —
> длинные фразы `cancellation.md` `solo` (A-L2).
> **Что это:** два независимых ревью волны читаемости 0.3.0 на Opus,
> коммиты `69351204..3937026c`, с вердиктом и итогом каждой находки.
> **Связанные записи:** `2026-10-21-readability-wave-plan.md`,
> `2026-10-21-solo-project-review.md` (L7),
> `2026-10-21-async-job-project-review.md` (M1, M2).

# Ревью волны читаемости 0.3.0

Волну смотрели два ревьюера на Opus, каждый в своей копии дерева на `3937026c`
(база `918f9c73`), по общему заданию: потеря утверждений, читаемость с оценкой
страниц, переводы, тесты страниц, проверки. Страницы поделены на две доли.
Отчёты ниже — как написаны, после каждой находки — вердикт.

## Доля A

Копия `/Users/user/.claude/jobs/b7a261de/tmp/wave/review` (detached
`3937026c`), база `918f9c73`. Доля: README и `doc/errors.md` `async_job`
с переводами, ссылка `observing.md` на «Rare routes» с переводом; `errors.md`,
`cancellation.md`, `state.md`, `jobs.md` `solo` с переводами; строки CHANGELOG
ядра и `solo`, тронутые волной, с переводами.

### 1. Страницы

| Страница | До | После | Почему |
| --- | --- | --- | --- |
| README `async_job` | 8 | 8.5 | «Four words» дал вход словарю, хвост Quick start короче; ячейки таблицы длинные, а у «Observe a failure» нет срока (L3) |
| `errors.md` `async_job` | 5 | 6.5 | Таблица приложения в шесть строк и отдельные «Rare routes» — то, что просил M1; но под таблицей одиннадцать пунктов «If…» подряд, разного веса, и половина держится за соседний пункт местоимением (L1) |
| `errors.md` `solo` | 6 | 7.5 | Таблица маршрутов первой, под ней ссылки на разделы, фразы короче; длина страницы прежняя |
| `cancellation.md` `solo` | 7 | 7 | Изменён один абзац; 14 фраз длиннее 35 слов, одна в 57 слов, причина L7 на странице осталась (L2) |
| `state.md` `solo` | 7 | 7.5 | Таблица `publish` стала пунктами, три пути ошибки — своим списком; читается легче |
| `jobs.md` `solo` | 7 | 7.5 | Длинных фраз 10 → 0, фраза о микрозадаче отдельным абзацем; кое-где деление дало «So» в начале фразы (N2) |

### 2. Находки

**H1. `errors.md` ядра: снята оговорка «только пока тело идёт» с отмены,
которую несёт `ctx.abandonable` без `await`.**
`packages/async_job/doc/errors.md:184-192`,
`docs/ru/async_job/errors.md:184-193`.

Было (`918f9c73`, строки 192-203), два абзаца подряд:

> The job's own cancellation goes there too: when the job is cancelled,
> `ctx.abandonable` called without `await` throws `Cancelled` into its future,
> and Dart hands it to the zone like any other error. …
>
> For `ctx.abandonable` called without `await`, this holds only while the body
> runs. If its action fails after the body has ended, the error goes the way of
> the late error …

«This» охватывало весь предыдущий абзац: и ошибку, и собственную отмену. Стало:

> - If the job is cancelled, `ctx.abandonable` called without `await` throws
>   `Cancelled` into its future, and Dart hands it to that zone like any other
>   error: the job's own cancellation goes there too. …
> - If the action of `ctx.abandonable` called without `await` fails after the
>   body has ended, … `onError` hears it, and then it goes on to the answer: the
>   zone the body runs in gets that error only while the body runs.

Второй пункт теперь говорит об отмене без условия, а оговорка третьего пункта
привязана к «that error» — провалу действия. Новый текст утверждает: отмена,
принятая после конца тела, тоже уходит в зону. Это неверно. Ровно это
исправлено в 0.3.0 (`CHANGELOG.md` ядра: «A call of `ctx.abandonable` the body
did not await no longer sends the job's cancellation to the zone when the job
accepts it after the body has ended»). Поведение держит тест
`a wait left behind, the job's cancellation after the body: nobody`
(`errors_rakes_test.dart:1172`), и его же комментарий, поправленный волной,
говорит: «The page holds `abandonable` to the zone only until the body ends».
Страница этого больше не держит. Оговорка пришла правкой по L-находке
`2026-09-26-async-job-project-review.md` (вердикт: «`wait` пока тело идёт,
собственная отмена тоже, уходит в зону») и по пункту 24
`2026-09-25-observing-rakes-report.md` («всё это так, только пока тело идёт»).
Ни один `_says` её не держал ни до волны, ни после, поэтому набор зелёный.
Русский пункт 3 («зона, где идёт тело, получает эту ошибку, только пока тело
идёт») потерял то же.

Попутно и мягче: старая строка таблицы говорила «An error of a context call the
body did not await, the job's own cancellation included» — то есть про любой
вызов контекста. Теперь собственная отмена названа только при
`ctx.abandonable`: в пункте 2 пример стал условием.

Предлагаю: во втором пункте — «If the job is cancelled while the body runs, …»
(перевод: «Если задачу отменяют, пока тело идёт, …»). Последнюю фразу третьего
пункта сказать о вызове, а не об «that error»: «a call of `ctx.abandonable`
without `await` reaches the zone the body runs in, error or cancellation, only
while the body runs». Добавить `_says` на эту оговорку на обоих языках
в `the page sends …` или рядом с тестом на строке 1172.

**Вердикт.** Принято: по `918f9c73`, строки 192–203, оговорка «только пока тело
идёт» охватывала и отмену, а волна оставила её при провале действия. Итог,
тем же коммитом, что эта запись: второй пункт начинается с «If the job is
cancelled while the body runs», последняя фраза третьего сказана о вызове, как
предложено: «A call of `ctx.abandonable` without `await` reaches the zone the
body runs in, with its error or with the job's cancellation, only while the
body runs»; перевод так же. Обе фразы на двух языках держит новый тест
`the page holds an unawaited abandonable to the zone in the body`
в `errors_rakes_test.dart` ядра. Мягкую часть не правили: зонд с `ctx.join`
и `ctx.uncancellable` без `await` под отменой дал `Cancelled(manual)` и пустую
зону. Значит, старая ячейка «the job's own cancellation included» обобщала
лишнее, и собственная отмена при одном `ctx.abandonable` — правда,
а не сужение.

**M1. `errors.md` ядра: «The tables show one way from the job to the zone»
теперь спорит со строкой движка.** `packages/async_job/doc/errors.md:209-215`,
`docs/ru/async_job/errors.md` (пункт «Если приложение сообщает об ошибках
и в `onError`, и в зоне…»).

Было (строки 205-210): «The table shows one way from the job to the zone: the
answer, when nobody answers for the error, or `onUnanswered` sends it on or
throws. … An observer that answers (`with JobAnswerer`) closes the way itself».
Тогда случай движка стоял отдельным абзацем вне таблицы («it goes to the zone
past the answer»), и «the table» его не охватывала.

Стало: «The tables show one way from the job to the zone: the answer…».
Во множественное число попала и таблица «Rare routes», а её строка движка
(строка 314) говорит «`onError`, then the zone past the answer if nobody
observed the outcome» — второй путь в зону, мимо ответа. Читатель, который
поверил пункту и поставил `JobAnswerer`, чтобы закрыть путь, получит провал
движка в зоне. В переводе то же: «Таблицы показывают один путь».

Предлагаю вернуть единственное число и назвать таблицу: «The table above shows
one way…» / «Таблица выше показывает один путь…». Либо дописать в пункт
исключение: «past the answer only the failure an engine makes of a
cancellation, as [Rare routes](#rare-routes) shows».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: «The table above
shows one way from the job to the zone», и в тот же пункт дописан второй путь:
«An engine that ends a job `Failed` on purpose adds a second, past the answer:
the last row of [Rare routes](#rare-routes)». Перевод: «Таблица выше показывает
один путь…». Фразу держит тот же новый тест, что и H1.

**L1. `errors.md` ядра: пункты «If…» держатся за соседний пункт местоимением.**
`packages/async_job/doc/errors.md:184-215` и перевод.

Абзацы исключений нарезали на пункты, а ссылки между фразами остались прежними,
и теперь их антецеденты лежат в соседнем пункте:

- пункт 2: «Dart hands it to **that zone**» — зона названа в пункте 1 («the
  zone the body runs in»). При этом во вступлении «the zone» — зона создания,
  так что читатель, который начал со второго пункта, подставит не ту зону.
  Перевод: «отдаёт его **этой зоне**»;
- пункт 6: «**such a failure** goes no further» — «such» отсылает к пункту 5
  (провал тела отменённой задачи и ветки `runAll`). В отрыве от пункта 5 это
  читается как «любой провал тела»;
- пункты 9-10: «**that way** … **the way** … closes **the way** itself» — путь
  назван в пункте 9.

План обещал пункт «если…, то…» как самостоятельную единицу. Список сканируют
по «If», и каждый пункт должен читаться сам. Предлагаю назвать предмет
в каждом: «to the zone the body runs in», «a failure of the body of a cancelled
job, or of such a branch», «the way through the answer». Пункты 9 и 10
по смыслу — одна мысль о пути через ответ; их можно слить в один.

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: во втором пункте
«to the zone the body runs in» (вместе с H1), в пункте об `ignoreFailure()` —
«the failure of its body goes no further», в пункте об исходе — «is off the way
through the answer: it takes that way only if nobody observed the outcome».
Пункты 9 и 10 не слиты, в этом правка разошлась с предложенным: один о двойном
отчёте приложения, другой о том, когда путь через ответ закрыт, и теперь каждый
называет путь сам.

**L2. `cancellation.md` `solo`: причина L7 на странице осталась.**
`packages/solo/doc/cancellation.md`. План сузил работу до абзаца
о `whenCancelled`, и она сделана. Но L7 ставил странице 7 за «длинные фразы
с вложенными уточнениями». `metrics.py` насчитывает их 13 до волны и 14 после
(четырнадцатая — склейка пунктов нового списка, то есть артефакт скрипта).
Остались, например, фраза в 57 слов «Its working type — the first type argument
of `run`, … — and its `keepWhile` cancel it when the state stops fitting them,
inside a section too: if …» и фраза в 44 слова о `timeout` и ветвлении
по причине. Это не дефект правки. Но вердикт L7 не должен называть страницу
закрытой: записать её в остаток вместе с непрошедшими страницами ядра.

**Вердикт.** Принято как остаток, а не как правка: план сузил страницу
до абзаца о `whenCancelled` нарочно. Итог: страница сверх этого не правилась;
в вердикте L7 `2026-10-21-solo-project-review.md` она записана в остаток
с тринадцатью настоящими длинными фразами (четырнадцатая у `metrics.py` —
склейка пунктов списка).

**L3. README ядра: «Observe a failure» без срока.**
`packages/async_job/README.md:252` и `README.ru.md:253`. Ячейка перечисляет,
что считается наблюдением, но не говорит когда. На `outcomes.md` это отдельная
строка таблицы: «Reads `done` or `value` after the microtask that follows the
end | too late: the failure has been answered for». Прежде Quick start вёл
прямо на `outcomes.md`; теперь он ведёт на «Four words», и определение, которое
читатель получает первым, — без срока. Предлагаю «… before the microtask that
follows the job's end; …» / «…до микрозадачи после конца задачи…».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: ячейка кончает
перечень сроком «by the microtask after the job ends» / «не позже микрозадачи
после конца задачи». С предложенным «before» разошлось словом: `outcomes.md`
говорит, что ответ даётся на этой микрозадаче, а «by» читается тем же сроком
и не спорит с таблицей там.

**N1. `errors.md` `solo`: «называет так» повисло после деления абзаца.**
`docs/ru/solo/errors.md`, абзац «Раздел [«Токен»](cancellation.md#токен)
страницы об отмене называет так остановку плеера.» Раньше «так» стояло в одном
абзаце с «называет такие ошибки в поле `Job.isCancellationError`». Теперь это
начало нового абзаца, и «так» не к чему отнести. В оригинале («names the stop
of a player») связь тоже ослабла. Предлагаю: «…names the stop of a player in
`Job.isCancellationError`» / «…называет в `Job.isCancellationError` остановку
плеера».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись:
«[The token](cancellation.md#the-token) on the cancellation page names in
`Job.isCancellationError` the error a player throws as it stops» / «…называет
в `Job.isCancellationError` ошибку, которую плеер бросает, останавливаясь».
Предмет назван ошибкой, а не остановкой: в поле лежит ошибка.

**N2. `jobs.md` `solo`: деление через «. So».** `So` в начале фразы: 1 → 4 («So
a plain `then`…», «So can one…», «So the record…»). Механической связкой это
ещё не стало, но в «A key is any object, compared with `==`. So the record
`(_Op.load, id)`…» запятая читалась лучше, а фраза была короче 35 слов. Перевод
повторяет («. Поэтому запись…»). Можно вернуть.

**Вердикт.** Принято частично. Итог, тем же коммитом, что эта запись: «A key is
any object, compared with `==`: the record `(_Op.load, id)` gives…» / «…через
`==`: запись…». «So a plain `then`…» и «So can one…» оставлены: обе фразы —
следствие предыдущей, и связка там несёт причину. Решение 96 `docs/settled.md`.

**N3. Перевод `cancellation.md` `solo`: «когда … пока».** Пункт «в свой черёд,
после слушателей, зарегистрированных раньше, когда его регистрируют, пока
отмена ещё передаётся детям» — два союза времени подряд. Лучше: «если его
регистрируют, пока отмена ещё идёт к детям».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: «если его
регистрируют, пока отмена ещё передаётся детям». «Передаётся» оставлено: так
этот шаг назван и ниже в том же переводе.

**N4. `errors.md` ядра, третий пункт.** «the zone the body runs in gets that
error only while the body runs»: «that error» — провал после конца тела,
и фраза сама себе противоречит. Уйдёт вместе с правкой H1.

**Вердикт.** Принято, ушло вместе с H1. Итог: фраза о «that error» заменена
фразой о вызове, см. итог H1.

### 3. Что проверено и не дало находок

**Потеря утверждений.** Сравнил по утверждениям, абзац за абзацем, — скриптом,
который выдаёт абзацы, которых нет в другой версии, и затем глазами по каждой
паре:

- README `async_job` и `README.ru.md`: таблица «Four words» сверена
  с источниками. Принятие отмены совпадает с `cancellation.md:40-44`,
  наблюдение — с таблицей `outcomes.md:116-125` (кроме срока, L3), ответ
  и зона — со вступлением `errors.md`. Хвост Quick start ничего не потерял:
  `outcome` назван в таблице, ссылка на `outcomes.md` есть в ячейке;
- `errors.md` ядра и перевод: все 11 строк старой таблицы и 7 абзацев
  исключений найдены — шесть строк в таблице приложения, пять в «Rare routes»,
  абзацы в пунктах. Потеря одна — H1. Абзац об `identical` и `Expando` в «Where
  each error goes» (решение 18), рецепт «Reporting each error once» на месте
  (17), фильтр меняет маршрут, а не исход (19), отмену в зону отдаёт Dart (25).
  Четыре пункта «Limits of the filter» совпадают со старыми абзацами. Новая
  ячейка движка «With an observer: `onError`» держится тестом
  `errors_rakes_test.dart:451`, ячейка без наблюдателя — `zone_test.dart:637`;
- `observing.md` и перевод: строка о `toString` ребёнка переехала в «Rare
  routes», ссылка ведёт туда. Остальные три ссылки на `#where-each-error-goes`
  (`chains.md:157` — поздняя ошибка `abandonable`, `extending.md:93`,
  `testing.md:118` — ошибки без исхода) ведут на строки, которые остались под
  якорем;
- `errors.md` `solo` и перевод: 17 переписанных абзацев, у каждого есть пара
  в новой версии, смысл тот же. Таблица маршрутов не изменилась ни в одной
  ячейке. «Next section» на прежнем месте верен. Решения 55 (три отчёта) и 56
  (таймер переживает `close()`) на месте;
- `cancellation.md`: абзац `whenCancelled` — все пять утверждений в списке
  и двух абзацах, слова «three» нет;
- `state.md`: четыре ячейки таблицы `publish` разложены по пункту и списку
  путей без потерь. Ссылка dartdoc `solo_stream.dart:17` «A failure should stay
  in `publish`» находит жирное начало пункта. Решение 95 не тронуто;
- `jobs.md`: 9 переписанных абзацев. Фраза решения 78 «the error has been
  answered for by then» на месте (`jobs.md:60`, перевод — «уже ответили»);
- CHANGELOG ядра: двенадцать страниц совпадают с `doc/` (12 файлов)
  и с порядком «Guides», перевод совпадает. Строка `solo` о `vs-bloc.md` — одна
  фраза (решение 75), перевод совпадает; саму страницу смотрит второй ревьюер.

**Читаемость.** Оценки — в таблице 1. Связки посчитал скриптом по началу фраз
(`So`, `Then`, `Besides`, `And`, `But`): прирост только у `jobs.md` (N2)
и на одну у `errors.md` обоих пакетов. «Besides» нет нигде. Слов без предмета
в примере не нашёл, кроме местоимений из L1 и N1.

**Переводы.** Все изменённые абзацы шести страниц и README сверены
с оригиналом: деления абзацев совпадают (`check_translations.py` зелёный),
смысл тот же — перевод повторяет и дефекты H1 и M1. Кальки, кроме N3, не нашёл.

**Тесты страниц.** `errors_rakes_test.dart` `solo`: десять переписанных `_says`
держат тот же факт новой фразой. Один стал строже: 2404 теперь держит и «so the
crash reporter hears each one». Новый тест
`opens with the table of where each error goes` мутацией проверен в копии
(откат копией файла, `cmp` подтвердил): страница `918f9c73` и раздел,
переставленный под «Reporting an error», роняют его — «Expected: 'Where each
error goes' Actual: 'Reporting an error'». `errors_rakes_test.dart` ядра:
`_says` движка переписан на новую ячейку на обоих языках, поведенческий тест
усилен проверкой `onError` первым. У `cancellation.md`, `state.md`, `jobs.md`
прозу держали только тесты поведения. Ни одна переписанная фраза не была
сторожем, и ни один `_says` не ослаблен. Оговорку H1 сторож не держал
и до волны.

### 4. Проверки

Из корня копии:

| Команда | Последняя строка |
| --- | --- |
| `python3 tool/reflow.py --check` | `every paragraph is filled to 79 columns` |
| `python3 tool/check_line_width.py` | `no Markdown line over 79 columns, no blank line doubled` |
| `python3 tool/check_translations.py` | `no differences` |
| `python3 tool/check_links.py` | `every document link resolves` |
| `python3 tool/check_doc_shape.py` | `every attempt opens its code with its mark` |
| `python3 tool/check_page_code.py` | `3 copies of packages/async_job/test/support/page_code.dart agree with it` |
| `dart pub get && dart test` в `packages/async_job` | `00:08 +1754: All tests passed!` |
| `dart pub get && dart test` в `packages/solo` | `00:02 +2033: All tests passed!` |

Все — код выхода 0. Копия после мутаций чистая (`git status --short` пуст).

## Доля B

Копия: `review2`, detached `3937026c`, база `918f9c73`. Доля: `vs-bloc.md`,
`accumulation.md`, `testing.md`, `reference.md` `solo` с переводами, строка
CHANGELOG `solo` о `vs-bloc.md` с переводом, `mixins.md` `flutter_solo`
с переводом, коммит `6d7c79e2` (`tool/flutter_snippets.py`).

### 1. Страницы

| Страница | До | После | Почему |
| --- | --- | --- | --- |
| `vs-bloc.md` | 6 | 7 | Строка «What solo gives» под каждым сценарием даёт торопливому итог раздела, и все одиннадцать верны разделу «Solo»; длина и 26 длинных фраз остались, как велит решение 86. |
| `accumulation.md` | 7 | 7,5 | Таблица «Recipes» на первом экране, деления фраз чистые; но два общих абзаца о типах и группе теперь стоят внутри «Recipes» между таблицей и её пояснением, и три новых фразы начинаются с «So». |
| `testing.md` `solo` | 7 | 8 | Восемь правил со ссылками сверху — сильный вход; портит его фраза ниже «The three sections below await», которая спорит с «Four are for a test that awaits». |
| `reference.md` | 8 | 8,5 | Ячейки читаются одной фразой; у `ctx.state` и `ctx.each` с хвостом ушло последствие — что отказ правил отменяет задачу. |
| `mixins.md` | 7 | 8 | Короткий ответ о базовом классе во вступлении точен и ведёт на разбор; одно деление поставило «So» к не той половине фразы. |

### 2. Находки

**M1. `mixins.md`: «So» связало `await for` не с той причиной.**
`packages/flutter_solo/doc/mixins.md:63`, перевод
`docs/ru/flutter_solo/mixins.md:63`.

Было: «And `await close()` waits until every subscriber of `stream` has taken
its done event, where a controller with `SoloListenable` alone waits for none
of its listeners: an `await for` over the `stream` holds `close()` while its
body is still awaiting.»

Стало: «…where a controller with `SoloListenable` alone waits for none of its
listeners. So an `await for` over the `stream` holds `close()` while its body
is still awaiting.» В переводе — «…не ждёт никого из своих слушателей. Поэтому
`await for` по `stream` держит `close()`…».

Почему дефект: двоеточие раскрывало всю цену — `close()` ждёт подписчиков
стрима. «So» цепляется к ближайшей фразе, и выходит, что `await for` держит
`close()` потому, что контроллер с одним `SoloListenable` никого не ждёт.
Причина обратная. Само поведение названо верно, поэтому это не H, но ложная
причинная связь — та самая тихая перемена, которую ищет пункт 1 брифа.

Предлагаю: вернуть двоеточие или разделить по смыслу: «…has taken its done
event; a controller with `SoloListenable` alone waits for none of its
listeners. An `await for` over the `stream` therefore holds `close()` while its
body is still awaiting» — либо поставить фразу об `await for` сразу после
первой половины, до «where…». Перевод — так же. `_says`
в `mixins_rakes_test.dart:315` держит подстроку без «So» и пройдёт с любой
из форм.

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: «…waits for none
of its listeners. On a controller with both, an `await for` over the `stream`
holds `close()`…» / «У контроллера с обеими доставками `await for` по `stream`
держит…». С предложенным разошлось формой: вместо «therefore» фраза названа
условием, при котором `await for` держит `close()`, и причинной связки
с соседней фразой больше нет.

**M2. Новый тест `Listenable.merge` не держит «either».**
`tool/flutter_snippets.py:1626`, тест
`one builder over two profiles follows either of them`; README `flutter_solo`,
«The controller as a `ValueListenable`»: «A widget over two profiles rebuilds
when either of them changes».

Тест грузит сначала `left`, потом `right`, и проверяет `waiting`, затем
`both loaded`. Первая проверка ничего не доказывает: без перестройки текст
и так `waiting`. Мутация в сгенерированном драйвере
`readme_listenable_test.dart`: `Listenable.merge([left, right])` →
`Listenable.merge([right])` — тест **зелёный** (`+1: All tests passed!`).
Обратная мутация `[left]` его роняет. Значит, сторож держит «перестраивается
на изменение второго», а не «на изменение любого», и имя теста обещает больше,
чем он проверяет.

Предлагаю: прогнать тот же сценарий в обоих порядках — `right` первым, затем
`left` — либо считать перестройки билдера после каждой загрузки (`builder`
вызвался после `left.load()`). Тогда обе мутации краснеют.

Импорт `listenable.dart` из «Install» драйвер берёт честно: блок проверяется
на то, что в нём одни импорты и все они из блока «Methods from a second
import».

**Вердикт.** Принято, мутация повторена. Итог, тем же коммитом, что эта запись:
тест в `tool/flutter_snippets.py` идёт циклом по двум порядкам,
`left loaded first` и `right loaded first`. Мутации `Listenable.merge([right])`
и `Listenable.merge([left])` теперь роняют каждая свой прогон; стенд — `+47`.

**M3. `testing.md`: «четыре ждут» сверху и «три ждут» ниже.**
`packages/solo/doc/testing.md:5` и `:87`; перевод `docs/ru/solo/testing.md:5`
и `:86`.

Новое: «Four are for a test that awaits its job or the controller's `close`» —
и в эту четвёрку входит «Assertions inside a zone», седьмой раздел. Старое,
оставшееся на месте: «The three sections below await; `fakeAsync` starts with
the fourth.» Читатель, только что прочитавший «четыре», видит «три» и не знает,
какой счёт верен. Оба верны в своём смысле — первая фраза о родах, вторая
о порядке страницы, — но страница этого не говорит, а список ещё и стоит
не в порядке страницы: седьмой раздел — четвёртым пунктом первой группы.

Почему M: до волны фраза была неточной молча; волна поставила рядом с ней
противоречащий счёт.

Предлагаю: убрать фразу «The three sections below await…» — список сверху её
заменяет, — или переписать: «The first three sections await, and `fakeAsync`
starts with the fourth; the lists above say which kind each section is.» Тест
`the three sections that await come first, fakeAsync is the fourth`
(`testing_rakes_test.dart:1713`) держит эту фразу через `_says`; правится
вместе с ней. Заодно стоит назвать в списке, что «What one test leaves for the
next» сам `fakeAsync` не запускает — новый тест это признаёт комментарием («The
one that runs no clock…»), а страница нет.

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: фраза ниже говорит
о порядке страницы и называет седьмой раздел: «The first three sections below
await; `fakeAsync` starts with the fourth, and the seventh, on assertions
inside a zone, awaits again.» Перевод так же. Тест
`the three sections that await come first, fakeAsync is the fourth` держит
новую фразу и проверяет, что седьмой раздел — «Assertions inside a zone»
и `fakeAsync` в нём нет. Пометку о том, что «What one test leaves for the next»
часов не запускает, на страницу не ставили: раздел о сбросе наблюдателя тех
тестов, что идут под `fakeAsync`, и в эту группу входит по читателю,
а не по коду. Решение 97 `docs/settled.md`.

**L1. `reference.md`: ячейки `ctx.state` и `ctx.each` потеряли последствие.**
`packages/solo/doc/reference.md:112`, `:115`; перевод
`docs/ru/solo/reference.md:113`, `:116`.

`ctx.state` было: «The state as `W`; a checkpoint, and a state the rules of the
job refuse cancels it». Стало: «The state as `W`, read at a checkpoint that
checks the rules of the job». Ушло «отказ правил отменяет задачу»; «checks»
не говорит, что будет при отказе, а соседняя ячейка `ctx.stateAs` своё
последствие («a mismatch cancels the job») сохранила.

`ctx.each` было: «…; a checkpoint, and a state the rules of the job refuse
cancels the job instead of starting the child». Стало: «Starts a child that
hands the events of a stream to `onData` one at a time, with the child's
`SoloContext`». Ушло целиком: что это контрольная точка и что отказ правил
отменяет задачу вместо запуска ребёнка.

Оба утверждения живут на страницах по ссылке (`state.md:102–104`,
`streams.md:72–75`), так что правило волны соблюдено. Но приёмка коммита 6
вернула хвосты шести ячеек именно потому, что «справочник читают по ячейке»,
а эти два не вернула. Предлагаю: «The state as `W`, read at a checkpoint where
a state the job's rules refuse cancels it»; для `each` — «…with the child's
`SoloContext`, after a checkpoint that cancels the job instead when its rules
refuse the state».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: `ctx.state` —
«read at a checkpoint where a state the rules of the job refuse cancels the
job»; `ctx.each` дописан хвостом «at a checkpoint where a state the rules of
the job refuse cancels the job instead»; перевод так же.

**L2. `reference.md`: `accumulator.add` — «throws» стало «only».**
`packages/solo/doc/reference.md:155`; перевод `docs/ru/solo/reference.md:158`.

Было: «…returns the group's job: everyone who added to it holds the same
handle, and each continues it through `shared()`: a plain `then` on it throws».
Стало: «…returns the group's job, which every caller continues only through
`shared()`». Ушли «один хэндл у всех» и то, что простой `then` бросает; «only»
читается как совет, а не как `StateError` с первого вызова (решение 91,
`2026-10-20-droppable-then-report.md` — строка ячейки пришла оттуда).
На `accumulation.md:883` это сказано. Предлагаю: «…returns the group's job, one
handle for every caller, where a plain `then` throws and `shared()` continues
it».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: «returns the
group's job, one handle for every caller, each of whom continues it through
`shared()` because a plain `then` on it throws»; перевод так же. Ячейка держит
обе части решения 91.

**L3. `vs-bloc.md`: «its error» цепляется к индикатору.**
`packages/solo/doc/vs-bloc.md:482`; перевод `docs/ru/solo/vs-bloc.md:484`.

«…the state reaches `Recording`, the meter is armed, and its error goes to the
zone and nowhere else.» Ближайшее существительное — «the meter»; в переводе
«индикатор включается, а его ошибка уходит в зону» — «его» и вовсе читается как
индикатор. Скилл `doc-reader`: оговорка в конце фразы цепляется к ближайшему.
Предлагаю «the observer's error» / «ошибка наблюдателя». `_says`
на `vs_bloc_rakes_test.dart:606` правится вместе.

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: «and the
observer's error goes to the zone and nowhere else» / «а ошибка наблюдателя
уходит в зону»; `_says` в `vs_bloc_rakes_test.dart` правлен вместе с фразой.

**L4. `accumulation.md`: общие абзацы внутри «Recipes» и механические «So».**
`packages/solo/doc/accumulation.md:19–29`, `:283`, `:645`, `:675`, `:712`.

Абзацы о трёх аргументах типа и о группе переехали под таблицу, как велит план,
но встали между таблицей и её пояснением «Under each version of a controller is
what the scenario above it leads to…», которое относится к таблице и рецептам.
Теперь пояснение отделено от того, что поясняет. Предлагаю поставить «Under
each version…» сразу под таблицей, а два общих абзаца — после него.

Три деления дали фразы, открытые «So»: «So a job that replaces another…» (283),
«So the device never hears the `resume`…» (645), «So the place
`AccumulationPolicy.join` keeps…» (675). По одному терпимо, но это ровно
шаблон, против которого предупреждает бриф; два из трёх читаются лучше без «So»
или с «therefore» внутри. На 712 «It is also the reason…» стоит после фразы
с подлежащим «the request», и «It» читается как запрос, а не как «That wait»;
предлагаю «That wait is also the reason…».

**Вердикт.** Принято частично. Итог, тем же коммитом, что эта запись: «Under
each version…» стоит сразу под таблицей «Recipes», два общих абзаца — после
него; на 712 — «The same wait is the reason the log collector takes a throttle
instead». Три «So» оставлены: каждая фраза — следствие предыдущей, и без связки
причина теряется; на странице их три на девятьсот строк. Решение 96
`docs/settled.md`.

**N1. Итог раздела без `cancellable: false`.** `vs-bloc.md`, строка итога
«Awaiting a particular request» называет ключ и `Policy.droppable`,
но не `cancellable: false`, о котором вторая половина раздела. Читатель,
который возьмёт итог как рецепт, напишет оплату, которую экран может отменить.
Можно дописать «…and `cancellable: false` keeps a started charge».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: строка итога
дописана «`cancellable: false` turns down a cancel from a screen» /
«`cancellable: false` отклоняет отмену с экрана»; `_says` правлен вместе.

**N2. Вступление `vs-bloc.md` не знает о строке итога.** Совет «a reader who
already knows the trap can skip to the bloc heading and `### Solo`» можно
дополнить «or to its closing line, What solo gives». Не дефект.

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: «…can skip to the
bloc heading and `### Solo`, or to the line that closes the section, **What
solo gives**» / «…или к строке, которой раздел кончается, **Что даёт solo**».
Сторожа у фразы нет и не было.

**N3. Новые утверждения без сторожа.** Тексты восьми правил `testing.md` (после
двоеточия) и короткий ответ во вступлении `mixins.md` не держит ни один
`_says`: тест правил держит заголовки, якоря и роды, а не сами правила. Правило
волны требует держать прежние факты, новых оно не касается, но вход для
торопливого — первое, что устаревает.

**Вердикт.** Принято для `mixins.md`, для `testing.md` — нет. Итог, тем же
коммитом, что эта запись: короткий ответ во вступлении `mixins.md` держат два
новых `_says` в тесте `the override of the class between runs in every leaf`.
Тексты восьми правил `testing.md` сторожа не получили: каждое правило
пересказывает свой раздел, а тест формы держит заголовок, якорь и род каждого;
дословный `_says` на восемь пересказов держал бы слова, а не факты. Решение 97
`docs/settled.md`.

**N4. Перевод, мелочи.** `docs/ru/solo/vs-bloc.md`, последняя строка итога:
«не ожидая устаревшее декодирование» — после «не ожидая» естественнее
родительный, «устаревшего декодирования». `docs/ru/solo/testing.md`, пункт
«Таймауты»: «`Future.timeout` кончает ожидание» — «прекращает».

**Вердикт.** Принято. Итог, тем же коммитом, что эта запись: «не ожидая
устаревшего декодирования» в обоих местах, «`Future.timeout` прекращает
ожидание».

### 3. Проверено без находок

1. **Потеря утверждений.** Сравнил по утверждениям целиком дифф
   `918f9c73..3937026c` страниц `vs-bloc.md` (только одиннадцать добавленных
   строк, остальное не тронуто; каждая строка итога сверена с разделом «Solo»
   своего сценария — расхождений с прозой и трассами нет), `accumulation.md`
   (все деления, два списка, перенос вступления; M9 о группе — определение
   по-прежнему раньше первого употребления), `testing.md` (все деления; восемь
   правил сверены с разделами — каждое верно своему разделу), `reference.md`
   (все ячейки; кроме L1 и L2 потерь нет, `keepWhile` сохранил «on state
   updates while the body runs»), `mixins.md` (все деления, короткий ответ
   сверен с «A base class without Flutter»), строку CHANGELOG `solo` и её
   перевод (раздел «Documentation» «Unreleased»). Помимо M1 и L1–L3 перемен
   смысла не нашёл.
2. **Читаемость.** Оценки в таблице раздела 1. `metrics.py` по моим страницам
   подтверждает итоги плана: фраз длиннее 35 слов `accumulation.md` 20 → 4,
   `testing.md` 15 → 2, `mixins.md` 6 → 0, `reference.md` 2 → 0, `vs-bloc.md`
   26 → 26. Слов без предмета в примере, кроме L3 и «It» в L4, не нашёл.
3. **Переводы.** Абзац в абзац во всех пяти переводах; новые абзацы (строки
   «Что даёт solo», правила `testing.md`, короткий ответ `mixins.md`, ячейки
   справочника) — по-русски без кальки, термины те же, что в окружающем
   переводе («трансформер некуда передать», «чистка»). Кроме M1, L3 и N4 — без
   замечаний.
4. **Тесты страниц.** Изменённые `_says` в `accumulation_rakes_test.dart`
   (восемь) и `testing_rakes_test.dart` (один) держат те же факты новыми
   словами, ни один не ослаблен. В `vs_bloc_rakes_test.dart` только добавления:
   каждая строка итога разобрана на `_says` в тестах, которые прогоняют то, что
   она говорит. Тест формы `vs-bloc.md` краснеет на удалённой строке;
   в переводе он только считает строки, и строку, перенесённую в чужой раздел,
   пропускает (мутация: зелёный), но `check_translations.py` на той же мутации
   краснеет («the prose differs in shape at block 35»), так что дыры в гейте
   нет. Тест правил `testing.md` держит заголовки, якоря, порядок внутри рода
   и род по коду раздела. Мутации делал в копии, откат — копией файла, дерево
   после них чистое.
5. **`6d7c79e2`.** Стенд собирается, анализ чист, драйвер `Listenable.merge`
   и импорт «Install» взяты; кроме M2 — без замечаний.

### 4. Проверки

Из корня копии `review2`:

| Команда | Последняя строка |
| --- | --- |
| `python3 tool/reflow.py --check` | `every paragraph is filled to 79 columns` |
| `python3 tool/check_line_width.py` | `no Markdown line over 79 columns, no blank line doubled` |
| `python3 tool/check_translations.py` | `no differences` |
| `python3 tool/check_links.py` | `every document link resolves` |
| `python3 tool/check_doc_shape.py` | `every attempt opens its code with its mark` |
| `python3 tool/check_page_code.py` | `3 copies of packages/async_job/test/support/page_code.dart agree with it` |
| `dart test` в `packages/solo` | `00:02 +2033: All tests passed!` |
| `dart test` в `packages/async_job` | `00:08 +1754: All tests passed!` |
| `flutter test` в `packages/flutter_solo` | `00:01 +233: All tests passed!` |
| `python3 tool/flutter_snippets.py <scratch>/fbench`, `flutter analyze` | `No issues found! (ran in 1.4s)` |
| то же, `flutter test --concurrency=1` | `00:03 +46: All tests passed!` |
| `tool/check_traces.py` по `mixins.md` | `every quoted trace is what the bench prints` |
| `doc_snippets.py` и `accumulation_snippets.py`, `dart analyze bin/v` в трёх пакетах, все драйверы | `No issues found!` ×3, ни один драйвер не упал |
| `tool/check_traces.py` по `vs-bloc.md` и `accumulation.md` | `every quoted trace is what the bench prints` |
