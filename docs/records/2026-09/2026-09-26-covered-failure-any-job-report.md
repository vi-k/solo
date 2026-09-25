# Покрытый провал у любой задачи: сделано

> **Состояние на 2026-09-26:** сделано в `main`, ждёт ревью сделанного;
> не отправлено.
> **Что это:** отчёт о правке по плану
> `2026-09-25-covered-failure-any-job-plan.md`: провал тела, после которого
> пришла отмена, отвечается у любой задачи, кто бы ни читал исход,
> а `Job.ignore` его глушит.
> **Связанные записи:** `2026-09-25-covered-failure-any-job-plan.md`,
> `2026-09-25-covered-failure-any-job-plan-review.md`,
> `2026-09-25-covered-child-failure-plan.md` (вопрос 4),
> `2026-09-25-covered-child-failure-report.md`,
> `2026-09-25-observing-rakes-report.md` (пункт 6 «По чтению владельца»).

## Что стало

Провал тела, который потом покрыла отмена, — ошибка без исхода у любой задачи,
чей исход решает ядро: у корня, у ребёнка `ctx.each`, у продолжения `then`,
у ребёнка `ctx.run` и ветки `ctx.runAll`. Читатель исхода — `value`, `done`,
`ctx.run`, группа — получает отмену, и ответа это не снимает. `onError` слышит
провал там, где тело его бросило, `onUnanswered` наблюдателя задачи отвечает,
по умолчанию в зону; без наблюдателя провал идёт в зону. Провал, поданный
движком через `finish` поверх отметки, идёт через `notifyError` и у корня:
раньше корень отдавал его в зону сам, мимо наблюдателя и фильтра отмены,
и `Failed`, собранный вокруг `Cancelled`, туда доезжал.

`Job.ignore` глушит покрытый провал и провал ветки `ctx.runAll`, который группа
не бросила: `onError` его слышит, ответа нет. Провал, которого `onError` ещё
не слышал, — поданный движком — при `ignore()` объявляется один раз. Ответ
синхронный, после `finished` и `onFinish`, поэтому `ignore()` успевает, если
вызван до конца задачи или из `onFinish` и `whenCancelled`; из слушателя `done`
уже нет.

**Ядро.**

- `JobBase._takenByParent` снят вместе со строками в `_awaitChild`
  и `_RunAllGroup.run`. Новый признак `_ignored` ставит только `ignore()`;
  `_observed` остаётся за непокрытым `Failed`.
- `_reportCovered(Failed, {required bool announced})` без ветвления по хозяину
  исхода: при `_ignored` — `notifyObserver`, если провал ещё не объявлен, иначе
  `announced` — `_handleUnanswered`, нет — `notifyError`. Микрозадача
  с проверкой `_observed` ушла. Вызовы прежние: `_execute` и продолжение
  `then` — `announced: true`, `finish` — `announced: false`.
- `_RunAllGroup._conclude` смотрит на `_ignored` ветки: провал тела — ничего,
  поданный движком — `notifyObserver`.
- Dartdoc: `Job.ignore` целиком (что снимает чтение исхода, что глушит
  `ignore`, срок вызова), `JobObserver.onError` и `onUnanswered`, `Failed`,
  `JobContext.run` и `runAll`, `notifyObserver`, `_handleUnanswered`,
  `_toZone`, `_reportCovered` (почему при `ignore()` провал движка слышит
  `onError`, оговорка о задаче, которую движок кончил руками), `_ignored`;
  комментарии в `_execute`, группе, `_conclude` и `job_then.dart`.

**`solo`.** Код не менялся. Покрытый провал корня и ребёнка `each` приходит
в `Solo.onUnanswered`, дальше — `Solo.errorHandler` или зона, и тогда, когда
`value` ждали. Раньше корень, чей исход никто не читал, отдавал такой провал
в зону мимо `Solo.errorHandler`, а прочитанный исход его терял. Dartdoc
`Solo.onUnanswered` называет случай и `Job.ignore`.

## Сторожа

`packages/async_job/test/unanswered_test.dart` — 48 тестов вместо 34:

- группа «a failure a cancellation covered is answered for, whoever reads it»
  (была «…, when a parent took the outcome»): корень, которого никто не читает;
  корень, чей `value` ждут, — читатель получает `Cancelled(manual)`; корень,
  чей `done` ждут; ребёнок `each`, которого никто не читает; ребёнок `each`,
  чьё `value` ждёт тело; продолжение, которое его наблюдатель отменил
  из `onError`, пока слышал провал источника, а `value` продолжения ждут;
  провал, поданный движком поверх отметки корня; `ctx.run(child).ignore()`;
  `ignore()` из слушателя `done` уже не успевает. Тест о `Failed`, собранном
  вокруг `Cancelled`, проходит теперь и ребёнка `ctx.run`, и корень. Тест
  «ignore on the child does not silence it» ушёл;
- новая группа «ignore silences a failure no outcome carries», через
  `expectOnlyTold`: корень; корень, чей `value` прочитан до `ignore()`; ребёнок
  `ctx.run`; ветка `runAll`, покрытая отменой; ветка, чей провал тела группа
  не бросила; ветка, которую движок кончил `Failed` руками, а группа
  не бросила; продолжение; `ignore()` из `whenCancelled`; провал, поданный
  движком поверх отметки, — один `onError`;
- группа «a failure of the body no parent took is never asked about» стала «…
  no cancellation covered …» и потеряла тест о покрытом провале; группа «a job
  no parent took keeps the rule of its outcome» ушла, её случаи — в первой
  группе;
- `expectOnlyTold` получил `alsoTold`, как у `expectAnswered`.

`packages/async_job/test/zone_test.dart`: «a listener one microtask late still
counts for a covered error too» стал обратным — «a reader a microtask after
finish does not keep a covered error back»; «a covered error waits for the same
window…» стал «ignore from onFinish still silences a covered error»; «an error
a late cancellation covers goes where an uncovered one goes» стал «… is told
once and answered», его причина и причина в «an observer that cancels from
onError does not hide the failure» говорят об ответе.

`packages/async_job/test/observing_rakes_test.dart` — 38 тестов вместо 37: два
теста строки таблицы берут `Answering(passedOn: true)` и ждут `onError`,
`onUnanswered` и зону с чтением исхода и без; «a child of run the same way»
сторожит ту же строку у ребёнка `ctx.run`; «ignore closes the second way for a
failure no outcome carries» — сторож абзаца под таблицей.

`packages/async_job/test/outcomes_rakes_test.dart` — 22 вместо 21: «waiting
does not observe a failure a cancellation covered» держит новый абзац страницы.

`packages/solo/test/zone_test.dart` — четыре новых: корень, которого никто
не читает, и корень, чей `value` ждут, доходят до `Solo.errorHandler`; ребёнок
`each`, чьё `value` ждёт тело, тоже; ребёнок `ctx.run` с `ignore()` слышен
одному `onError`. Группа стала «a failure a cancellation covered», тесты
ребёнка `ctx.run` называют его.

Все новые и развёрнутые тесты, кроме тех, что держат неизменное, красные
на ядре `HEAD`: 14 в `unanswered_test.dart`, по одному в `outcomes_rakes_test`
и `zone_test`, три в `observing_rakes_test`, четыре в `solo`. Зелёными
на `HEAD` остаются корень с `ignore()`, корень с `ignore()` после чтения
`value`, продолжение с `ignore()`, `ignore()` из `whenCancelled`
и `ctx.run(child).ignore()`: там поведение не меняется.

## Мутации

Тринадцать, по всему набору `async_job` после всех сторожей: девять из плана,
три из ревью плана и `value` отдельно от `done`. Откат копией файла со сверкой
хэша (`hash ok` после каждой), счёт по меткам `[E]`:

| Мутация | Красных |
| --- | --- |
| `ignore()` не ставит `_ignored` | 13 |
| `done` ставит `_ignored` | 15 |
| `value` ставит `_ignored` | 12 |
| `_reportCovered` не смотрит на `_ignored` | 11 |
| при `_ignored` поданный движком провал не объявляется | 1 |
| при `_ignored` провал тела объявляется снова | 7 |
| вернуть проверку `_observed` в микрозадаче | 21 |
| ответ микрозадачей, с проверкой `_ignored` в ней | 4 |
| всегда `_handleUnanswered` | 3 |
| всегда `notifyError` | 20 |
| продолжение `then` передаёт `announced: false` | 2 |
| `_conclude` не смотрит на `_ignored` | 3 |
| в `_conclude` при `_ignored` поданный движком провал не объявляется | 1 |

Пойманы все. «Ответ микрозадачей» ловят сторож порядка прошлой работы («the
answer comes before the parent hears the cancellation»), «ignore from a
listener of done comes too late» и два теста строки таблицы страницы: ответ
встаёт после строки исхода. Ровно это и покупала бы микрозадача — `ignore()`
из слушателя `done` — ценой порядка.

«`done` ставит `_ignored`» краснит и тесты группы `runAll`
в `run_all_test.dart` и `extending_test.dart`: группа читает `done` каждой
ветки, и невыбранный провал замолкал бы. «Продолжение `then` передаёт
`announced: false`» больше не эквивалентна: провал слышен в `onError` дважды.

Набор `solo` под «проверкой `_observed` в микрозадаче» — 5 красных: корень, чей
`value` ждут, ребёнок `each`, чьё `value` ждёт тело, и три теста ребёнка
`ctx.run`. Под «`_reportCovered` не смотрит на `_ignored`» — один, ребёнок
`ctx.run` с `ignore()`.

## Документы

- `packages/async_job/doc/observing.md` и перевод: строки таблицы «The body's,
  and a cancellation arrives…» и «The same, in a child of `ctx.run`…» слились
  в одну — `onError`, затем `onUnanswered`, по умолчанию зона; без наблюдателя
  зона. Абзац о двойном слухе: второй путь для двух провалов тела, которых
  исход не несёт, закрывает и `job.ignore()`. Пункт 6 «По чтению владельца»
  в `2026-09-25-observing-rakes-report.md`.
- `packages/async_job/doc/outcomes.md` и перевод, раздел «Telling the engine it
  is handled»: новый абзац — ожидание не наблюдает провала, который потом
  покрыла отмена, и в зону его не пускает `ignore()`.
- `packages/async_job/doc/children.md`, `packages/solo/doc/children.md`
  и переводы: `child.ignore()` глушит покрытый провал ребёнка `ctx.run`,
  `ctx.run(child).ignore()` — нет.
- `packages/solo/doc/errors.md` и перевод: перечень «Answering for an error»
  говорит о провале тела любой задачи; «Observing the outcome» — какую ошибку
  вызывающий `await job.value` не перехватит и что её глушит.
- `packages/async_job/CHANGELOG.md`: запись `Fix` о покрытом провале переписана
  целиком — любая задача, чтение исхода больше не держит провал вне зоны,
  провал движка поверх отметки, `ignore` и срок его вызова.
- `packages/solo/CHANGELOG.md`, запись `Breaking` о `Solo.onUnanswered`:
  перечень говорит о провале тела любой задачи и о том, что покрытый провал
  корня и ребёнка `ctx.each` доходит до `Solo.errorHandler`, даже когда `value`
  ждали; `job.ignore()` его глушит.
- `docs/architecture.md`: определение «Наблюдение исхода» — `ignore()` больше
  наблюдения; маршрут покрытого провала, синхронный ответ и срок `ignore()`,
  задача, которую движок кончил руками; оговорка о `Failed`, собранном вокруг
  отмены, — у любой задачи.
- Шапки `2026-09-25-covered-child-failure-plan.md`
  и `2026-09-25-covered-child-failure-report.md`: правило пересмотрено этой
  работой.

## Отступления от плана

- Запись `CHANGELOG` `flutter_solo` не тронута, как и в прошлой работе: его
  унаследованные записи несут только ломающие изменения нижних пакетов (вердикт
  находки 3 ревью плана).
- `solo/doc/testing.md`, `flutter_solo/README.md` и хвост `then`
  в `children.md` не правились: они о провале, который несёт исход (вердикт
  находки 4).
- Сторож «`ignore()` из `onFinish` ещё успевает» — переименованный тест
  `zone_test.dart`, а не новый в `unanswered_test.dart`: тот тест держит ровно
  это.
- Сверх плана: корень, чей `value` прочитан до `ignore()` (фраза dartdoc
  `Job.ignore`, которую ревью плана назвало неверной), сторожа страниц
  в `observing_rakes_test` и `outcomes_rakes_test` и тест `solo` о ребёнке
  с `ignore()` — у каждой новой фразы страниц свой сторож.
- Мутация «`done` и `value` ставят `_ignored`» разбита на две: у каждого
  геттера свои сторожа.
- Ветке, которую движок кончает руками, нужна третья ветка, которая держит
  группу, пока обе не кончились: без неё группа решает раньше, чем движок
  подаст провал второй, и обе кончаются `Done`.

## Проверки

- `async_job`: формат, анализ, `dart doc --dry-run` чистые; 622 теста (606
  до правки: в `unanswered_test.dart` 48 вместо 34, по одному новому
  в `observing_rakes_test.dart` и `outcomes_rakes_test.dart`).
- `solo`: то же; 799 тестов (795 и четыре новых); пример — 47.
- `flutter_solo`: анализ чист, 85; пример — 4.
- Документы: ширина, заливка, форма, переводы, ссылки; сторожа трёх скриптов
  и сборки сайта; сайт — 42 страницы.
- Стенды: `doc_snippets.py` и `accumulation_snippets.py` собираются
  и анализируются чисто, драйверы доходят до конца, цитаты трасс сходятся;
  `flutter_snippets.py` — 29 тестов, трассы сходятся.
- `jargon.py` по тронутым страницам обеих версий: два подозреваемых, оба стояли
  и до правки. `bare_names.py` в изменённых строках находит только «future» —
  так её пишут и соседние абзацы.

## Ревью сделанного

Ждёт.

## Открытое

Для владельца: поле в `Cancelled`, которое несло бы покрытый провал читателю
исхода, — отдельной работой.

Вне этой работы: движок домена кончает задачу руками, пока упавшее первым тело
ждёт детей, — провал слышит один `onError`; dartdoc `_reportCovered`
и `docs/architecture.md` это называют.
