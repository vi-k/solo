# Покрытый провал отвечается у любой задачи

> **Состояние на 2026-09-26:** выполнен в `main`, отчёт —
> `2026-09-26-covered-failure-any-job-report.md`; не отправлено. Ревью плана —
> `2026-09-25-covered-failure-any-job-plan-review.md`, девять находок приняты
> и внесены; ревью сделанного ждёт.
> **Что это:** план открытого вопроса 4
> `2026-09-25-covered-child-failure-plan.md`: провал тела, который потом
> покрыла отмена, отвечается у любой задачи — у корня, у ребёнка `ctx.each`,
> у продолжения `then`, — а не только у ребёнка `ctx.run` и ветки `ctx.runAll`;
> `Job.ignore` его глушит.
> **Связанные записи:** `2026-09-25-covered-failure-any-job-plan-review.md`,
> `2026-09-25-covered-child-failure-plan.md` (вопрос 4),
> `2026-09-25-covered-child-failure-report.md`,
> `2026-09-25-covered-child-failure-work-review.md`,
> `2026-09-25-observing-rakes-report.md` (страница под чтением владельца).

## Зачем

Открытый вопрос 4 прошлого плана. Корневая задача, чей `value` или `done`
кто-то ждёт, и ребёнок `ctx.each`, чьё `value` ждёт тело, теряют провал,
который потом покрыла отмена. Читатель исхода получил отмену, а не ошибку,
но правило «в зону, если исход никто не смотрел» считает ошибку полученной.
С наблюдателем её слышит только `onError`, без наблюдателя — никто.

У корня `solo` тот же провал, когда исход никто не читает, идёт прямо в зону,
мимо `Solo.errorHandler`: путь ненаблюдённого исхода не спрашивает
`onUnanswered`.

Решение владельца 2026-09-25: покрытый провал отвечается у любой задачи, как
у ребёнка `ctx.run`, — `onError`, затем `onUnanswered`, по умолчанию зона;
`Job.ignore` его глушит. Кто читал исход, неважно: читатель получил отмену.

## Зонд

`packages/async_job/test/zz_probe_q4_test.dart`
и `packages/solo/test/zz_probe_solo_test.dart`, не для коммита. Тело падает
на 5 мс, пока жив его ребёнок на 50 мс; отмена приходит на 10 мс. Наблюдатель
записывает оба хука и зовёт `super`. Черновик — в разделе «Механика».

| Случай | Сейчас, с наблюдателем | Сейчас, без | Черновик, с наблюдателем | Черновик, без |
| --- | --- | --- | --- | --- |
| S1. Корень, его `value` ждут | `onError` | пусто | `onError`, `onUnanswered`, зона | зона |
| S2. Ребёнок `ctx.run`, родителя отменили | `onError`, `onUnanswered`, зона | зона | без изменений | без изменений |
| S3. Корень, секция `uncancellable` упала, пока держала отмену; исход никто не читает | `onError`, зона | зона | `onError`, `onUnanswered`, зона | зона |
| S4. Ребёнок `each`, его `value` ждёт тело | `onError` | пусто | `onError`, `onUnanswered`, зона | зона |
| S5. Корень с `ignore()` | `onError` | пусто | без изменений | без изменений |
| S6. `child.ignore()` под `ctx.run` | `onError`, `onUnanswered`, зона | зона | `onError` | пусто |
| S7. `ctx.run(child).ignore()` | `onError`, `onUnanswered`, зона | зона | без изменений | без изменений |

Читатель исхода в S1 и тело родителя в S2 и S4 получают `Cancelled` и сейчас,
и на черновике.

`solo`, корень `solo.run`, `Solo.errorHandler` задан:

| Случай | Сейчас | Черновик |
| --- | --- | --- |
| Исход никто не читает | зона, обработчик не спрошен | `Solo.errorHandler` |
| `value` ждут | пусто | `Solo.errorHandler` |

На черновике `solo` зелёный весь, 795 тестов. В `async_job` красные семь, и все
держат прежнее правило:

- `unanswered_test`: «a failure the cancellation covered while children
  finished» (группа «a failure of the body no parent took is never asked
  about»), «ignore on the child does not silence it», оба теста группы «a job
  no parent took keeps the rule of its outcome»;
- `observing_rakes_test`: «a cancellation after the failure: the same as the
  failure», «a cancellation while the cleanup runs: the same as the failure» —
  строка таблицы на странице;
- `zone_test`: «a listener one microtask late still counts for a covered error
  too».

## Что станет

**Правило.** Провал тела, который потом покрыла отмена, не лежит в исходе той
задачи, которая за него отвечает: её исход — `Cancelled`. Он идёт маршрутом
ошибки без исхода: `onUnanswered` наблюдателя задачи, по умолчанию зона её
создания; без наблюдателя — прямо в зону. Объявляется он один раз, как и сейчас
у ребёнка `ctx.run`: провал тела `onError` слышал там, где тело его бросило,
и дальше только ответ; провал, поданный движком через `finish` поверх отметки,
не слышал никто — `notifyError`. Читать исход — `value`, `done`, `ctx.run`,
группа — значит получить отмену, и ответа это не снимает.

**Продолжение `then`.** Источник упал, продолжение переслало его провал
и объявило его, а наблюдатель продолжения отменил продолжение прямо
в `onError`. Провал лежит в исходе источника, `Failed`, но пересылка сняла
с источника ответственность за него, а исход продолжения — `Cancelled`.
Отвечает продолжение, `announced: true`, теперь и тогда, когда его `value`
ждут. Кто читает `value` источника, получает ошибку, как и сейчас.

**Провал, поданный движком поверх отметки корня.** Сейчас он идёт у корня прямо
в зону, мимо наблюдателя и фильтра отмены. Станет как у ребёнка `ctx.run`:
`onError`, затем `onUnanswered`. `Failed`, собранный вокруг `Cancelled`
и поданный так, фильтр теперь отбрасывает, а не отдаёт в зону.

**`Job.ignore` глушит.** Его обещание — «nobody is interested in this job's
failure», и покрытый провал — провал этой задачи. `onError` его уже слышал,
ответа нет. Это правило одно для всех: `child.ignore()` под `ctx.run` теперь
тоже глушит (S6), решение прошлого плана о P7 разворачивается.
`ctx.run(child).ignore()` глушит будущее, а не ребёнка, и провал отвечается
(S7). Провал, поданный движком поверх отметки, у задачи с `ignore()` слышит
`onError` — `notifyObserver`, без ответа: иначе его не услышал бы никто,
а `ignore()` отдаёт провалы наблюдателю, а не выбрасывает. То же у ветки
`ctx.runAll`, чей провал группа не бросила: это тоже провал этой задачи, и при
`ignore()` провал тела слышит только `onError`, а поданный движком —
`notifyObserver`.

**Механика.**

- Флаг `_takenByParent` уходит вместе со строками в `_awaitChild`
  и в `_RunAllGroup.run` и их комментариями.
- `JobBase` получает `_ignored`, его ставит только `ignore()`. `_observed`
  остаётся за непокрытым `Failed`: для него чтение исхода по-прежнему значит
  «ошибку получили».
- `_reportCovered(Failed, {required bool announced})` без ветвления по хозяину
  исхода: при `_ignored` — `notifyObserver`, если провал ещё не объявлен,
  и больше ничего; иначе `announced` — `_handleUnanswered`, нет —
  `notifyError`. Микрозадача с проверкой `_observed` уходит.
- Вызовы не меняются: `_execute` — `announced: true`, `finish` для подменённого
  `Failed` — `announced: false`, продолжение `then` — `announced: true`.
- `_RunAllGroup._conclude` смотрит на `_ignored` ветки: провал тела — ничего,
  поданный движком — `notifyObserver`.

**Когда отвечает.** Синхронно, после `finish`, то есть после `finished`
и `onFinish` — как сейчас у ребёнка `ctx.run`. Окно наблюдения здесь больше
ничего не решает: чтение исхода ответа не снимает. `ignore()` успевает, если
вызван до конца задачи или из `finished`, `onFinish` и `whenCancelled`;
из слушателя `done` или микрозадачей позже — нет, хотя непокрытому `Failed` там
ещё дают микрозадачу. Этот срок называет dartdoc `Job.ignore`. `ignore()` зовут
при создании задачи, а порядок «ответ раньше, чем родитель услышит отмену»
держит сторож прошлой работы.

**`solo`.** Кода не трогает. Покрытый провал корня `solo` и ребёнка `each`
приходит в `_SoloJobObserver.onUnanswered`, дальше — `Solo.onUnanswered`,
`Solo.errorHandler` или зона.

**Вне этой работы.** Поле в `Cancelled`, которое несёт покрытый провал читателю
исхода, владелец рассмотрит отдельно. Движок домена, кончающий задачу руками,
пока упавшее первым тело ждёт детей, — как в прошлом плане: там по-прежнему
слышен один `onError`. Поэтому страницы описывают случай обстоятельствами —
тело упало, отмена пришла, пока задача ждала детей или шла уборка, —
а не словами «у любой задачи»; оговорка — в dartdoc `_reportCovered`
и `docs/architecture.md`.

## Сторожа

`packages/async_job/test/unanswered_test.dart`:

- группа «a failure a cancellation covered, when a parent took the outcome»
  становится группой о покрытом провале любой задачи; каждый новый тест — через
  `expectAnswered` (с наблюдателем, который смотрит, без наблюдателя
  и с отвечающим);
- новые случаи: корень, исход которого никто не читает; корень, чей `value`
  ждут; корень, чей `done` ждут; ребёнок `each`, которого никто не читает;
  ребёнок `each`, чьё `value` ждёт тело; `ctx.run(child).ignore()` (S7);
- `ignore()`, через `expectOnlyTold`: корень с `ignore()`; `child.ignore()` под
  `ctx.run` — вместо «ignore on the child does not silence it»; ветка `runAll`
  с `ignore()`, покрытая отменой; ветка `runAll` с `ignore()`, чей провал тела
  группа не бросила; такая же ветка, которую движок кончил `Failed` руками, —
  один `onError`; `ignore()` из `onFinish` и из `whenCancelled` ещё успевает;
  провал, поданный движком поверх отметки, у задачи с `ignore()` — один
  `onError`, без ответа и зоны;
- `ignore()` из слушателя `done` уже не успевает — `expectAnswered`;
- продолжение `then`, которое его наблюдатель отменил из `onError`, пока слышал
  провал источника, и чьё `value` ждут, — `expectAnswered` с одним `onError`;
  то же с `ignore()` на продолжении — `expectOnlyTold`;
- корень, которому движок подал провал поверх отметки, — `onError`, затем
  ответ; `Failed`, собранный вокруг `Cancelled` и поданный поверх отметки
  корня, в зону не доходит — с наблюдателем и без;
- тест о покрытом провале уходит из группы «a failure of the body no parent
  took is never asked about», группа сужается до непокрытых; группа «a job no
  parent took keeps the rule of its outcome» уходит — её случаи переезжают
  в новые тесты выше.

`packages/async_job/test/zone_test.dart`: «a listener one microtask late still
counts for a covered error too» становится обратным — читатель `done`,
пришедший к концу задачи, покрытого провала из зоны не уводит. «a covered error
waits for the same window an uncovered one waits for» остаётся зелёным
(`ignore()` из `onFinish`), но его имя и причина говорят об окне наблюдения —
переписать под `ignore()`. Зелёными остаются и два теста с неверными словами:
«an error a late cancellation covers goes where an uncovered one goes» — имя
и причина о `onUnanswered`; причина в «an observer that cancels from onError
does not hide the failure» — переписать.

`packages/async_job/test/observing_rakes_test.dart`: два теста строки таблицы
о покрытом провале берут наблюдателя `Answering(passedOn: true)` и ждут
`onError`, `onUnanswered` и зону: `Reporter` печатает один `onError`. Тест «the
same in a child of run: onError, then the zone» остаётся сторожем слитой строки
у ребёнка `ctx.run`, с именем под неё.

`packages/solo/test/zone_test.dart`: покрытый провал корня `solo.run` доходит
до `Solo.errorHandler` — когда исход никто не читает и когда `value` ждут;
покрытый провал ребёнка `each`, чьё `value` ждёт тело, — тоже. Все красные
на `HEAD`.

## Мутации

Откат копией файла со сверкой хэша.

| Мутация | Ожидается красным |
| --- | --- |
| `ignore()` не ставит `_ignored` | тесты `ignore()` |
| `done` и `value` ставят `_ignored` | корень и `each`, чей исход читают |
| `_reportCovered` не смотрит на `_ignored` | тесты `ignore()` |
| при `_ignored` поданный движком провал не объявляется | провал движка у задачи с `ignore()` |
| при `_ignored` провал тела объявляется снова | тесты `ignore()`: второй `onError` |
| вернуть проверку `_observed` в микрозадаче | корень и `each`, чей исход читают; `solo` |
| ответ микрозадачей | порядок ответа и отмены у родителя |
| всегда `_handleUnanswered` | провал, поданный движком |
| всегда `notifyError` | второй `onError` |
| `then` передаёт `announced: false` | продолжение, отменённое из `onError`: второй `onError` |
| `_conclude` не смотрит на `_ignored` | ветка `runAll` с `ignore()`, чей провал не бросили |
| в `_conclude` при `_ignored` поданный движком провал не объявляется | ветка с `ignore()`, кончённая движком руками |

## Документы

- Dartdoc ядра: `Failed` в `outcome.dart` (развилка «to the zone on the terms
  above, or — when a parent took the outcome» уходит), `JobObserver.onError`
  и `JobObserver.onUnanswered` (перечни), `notifyObserver`, `_ignored`,
  `JobContext.run` («whether or not [Job.ignore] was called» — теперь
  наоборот), `JobContext.runAll` («A failure the group received and did not
  throw is not lost either» — кроме ветки с `ignore()`).
- Dartdoc `Job.ignore` целиком: «calling this afterwards changes nothing»
  и «Has no effect on [Cancelled]» неверны для покрытого провала, абзац
  о ребёнке `ctx.run` и ветке `ctx.runAll` («so this changes nothing for them»)
  разворачивается; срок вызова — до конца задачи, самое позднее из `onFinish`
  или `whenCancelled`.
- Dartdoc `_handleUnanswered` и `_toZone`: строки о покрытом провале «in a job
  whose outcome a parent took» — о любой задаче, чей исход решает ядро;
  `Failed`, собранный вокруг `Cancelled` и поданный поверх отметки, фильтр
  отбрасывает у любой такой задачи. `_reportCovered`: оговорка о задаче,
  которую движок кончил руками, и почему при `ignore()` провал движка слышит
  `onError` — непокрытый виден в исходе, а покрытый без `onError` исчез бы
  бесследно.
- Комментарии ядра: `_execute` после `finish` (окно наблюдения для задачи, чей
  исход не брал родитель), `_awaitChild` и группа (строки флага), `_conclude`
  (ветка с `ignore()`).
- Dartdoc `Solo.onUnanswered` (перечень).
- `packages/async_job/doc/observing.md` и перевод: строки таблицы «The body's,
  and a cancellation arrives…» и «The same, in a child of `ctx.run`…» сливаются
  в одну — `onError`, затем `onUnanswered`: по умолчанию зона; без
  наблюдателя — зона. Абзац за таблицей: путь в зону «when nobody observed the
  outcome» остаётся только у первой строки; `ignore()` закрывает второй путь
  для провалов тела — покрытого и невыбранного, — но не для ошибок вне тела.
  Страница под чтением владельца, правка идёт пунктом
  в `2026-09-25-observing-rakes-report.md`.
- `packages/async_job/doc/children.md`, `packages/solo/doc/children.md`
  и переводы: абзац о будущем `ctx.run` и покрытом провале — `child.ignore()`
  теперь глушит, `ctx.run(child).ignore()` — нет.
- `packages/async_job/doc/outcomes.md` и перевод, раздел «Telling the engine it
  is handled»: «code that waits for the job … needs no `ignore()`» — кроме
  провала, который потом покрыла отмена: ждущий получает отмену, провал идёт
  в `onUnanswered`, и глушит его `ignore()`.
- `packages/solo/doc/errors.md` и перевод: раздел «Observing the outcome» —
  вызывающий `await job.value` при покрытом провале ловит `Cancelled`; раздел
  «Answering for an error» — перечень того, что не несёт исход.
- `CHANGELOG` `async_job`, `Unreleased`: запись `Fix` о покрытом провале
  ребёнка переписывается целиком. Покрытый провал любой задачи отвечается через
  `onUnanswered`; чтение исхода — `value`, `done`, `ctx.each(...).value` —
  больше не держит его вне зоны, читатель получает отмену; `ignore()` глушит
  его, и у ребёнка `ctx.run` тоже, и провал ветки, который группа не бросила.
  Класс — `Fix`: ошибка терялась и теперь доходит.
- `CHANGELOG` `solo`: перечень в записи `Breaking` о `Solo.onUnanswered`,
  и фраза: покрытый провал корня и ребёнка `each` доходит
  до `Solo.errorHandler`, даже когда `value` ждали. `CHANGELOG` `flutter_solo`
  не трогается: его унаследованные записи несут только ломающие изменения;
  отчёт это назовёт.
- `docs/architecture.md`: определение «Наблюдение исхода» — `ignore()` теперь
  больше, чем наблюдение; маршрут покрытого провала; оговорка о `Failed`,
  собранном вокруг отмены; задача, которую движок кончил руками.

Проверены и не правятся `packages/solo/doc/testing.md`,
`packages/flutter_solo/README.md` и хвост `then`
в `packages/async_job/doc/children.md`: они говорят о провале, который несёт
исход, и для него чтение исхода по-прежнему снимает ответ.

## Проверки

Формат, анализ, `dart doc --dry-run` и тесты `async_job`, `solo` с примером,
`flutter_solo` с примером; пять питоновских проверок документов и сторожа
скриптов; сборка сайта; стенды `doc_snippets.py`, `accumulation_snippets.py`,
`flutter_snippets.py`; `jargon.py` и `bare_names.py` по тронутым страницам.

## Порядок

1. Ревью плана на Opus, вердикты в запись ревью.
2. Код ядра, сторожа ядра, мутации.
3. Сторож `solo`, dartdoc `Solo.onUnanswered`.
4. Документы, переводы, `CHANGELOG`, `docs/architecture.md`.
5. Проверки, отчёт, handoff, коммит.
6. Ревью сделанного на Opus.

## Открытые вопросы

Оба вопроса для ревью решены в пользу плана (находки 8 и 9 ревью): ответ
синхронный; провал, поданный движком поверх отметки, у задачи с `ignore()`
слышит один `onError`.

Для владельца: поле в `Cancelled` с покрытым провалом — отдельной работой.
