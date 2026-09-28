# `async_job`: `cancellation.md` и `outcomes.md` по находкам ревью

> **Состояние на 2026-09-28:** сделано в `6ec4f76`; независимое ревью
> нашло две неточности Medium и девять мест поменьше, все приняты и исправлены.
> **Что это:** отчёт о правке `packages/async_job/doc/cancellation.md`,
> `packages/async_job/doc/outcomes.md`, их переводов в `docs/ru/async_job/`,
> dartdoc и сторожей по находкам `2026-09-26-async-job-project-review.md`:
> M13, M14, L38–L46, а с ними L12, L19 без части о `check()`, L21, L25, L60
> для этих двух страниц, часть L1 о странице, слово «operation» из L29 и часть
> L41 о `cancellation.md`.
> **Связанные записи:** `2026-09-26-async-job-project-review.md`,
> `2026-09-28-observing-page-report.md` (предыдущая страница того же пункта
> порядка работ), `2026-09-25-cancellation-rakes-report.md` (вычитка страницы
> об отмене, откуда её первые попытки).

Поведение ядра не менялось: страницы и dartdoc говорили неверно, шире или уже
кода, а ядро право. Зонд —
`.artifacts/2026-09-28-cancellation-outcomes-pages/probe_pages_test.dart`,
вывод рядом, `probe.out`. Все находки воспроизвелись.

Сверх M13, M14 и L38–L46 из порядка работ взяты находки, которые стоят
на этих же страницах: L12, L19, L21, L25, L60 и по куску L1, L29 и L41.
Не взяты: код L1 (описание `child null`, меняет ядро и два теста), часть L19
о том, кто зовёт `check()` (это переопределение `check`, страница
`extending.md`, рядом с M7), первая половина L43 и выбор по L29 — вопросы
владельцу, и словарь M22 и M23 («the engine», «answers at a checkpoint») —
подготовка выпуска.

## M13. `async`-колбэк до первого `await`

Зонд: наблюдатель с `onError`, задача создана в одной зоне, `cancel()`
из другой. `async`-слушатель `whenCancelled` и `async`-колбэк `onCancel`,
бросившие до первого `await`, дают `[cancel: Bad state: before await]`,
`onError` молчит. Если отмену придержала секция `uncancellable`, оба уходят
в зону тела: `[creation: …]`.

На `outcomes.md` «an error after its first `await`» стало «none of its errors
reaches `onError`»: `async`-функция синхронно не бросает, и ошибка до первого
`await` тоже уходит в её future. Зона названа так, как её показывает зонд: та,
где позвали слушателя; для отмены, принятой внутри `cancel()`, — зона
вызвавшего; для отмены, придержанной секцией, и для тела, которое сдалось
само, — зона тела, у задачи, что стартует сама, это зона создания. Разошлось
с предложенным: было «for a cancellation from outside», но отмена, придержанная
секцией, тоже снаружи, а зона у неё другая. Первая редакция ещё обещала, что
ошибка не доходит до зоны создания; это нашло ревью, находка 1 ниже.
На `cancellation.md` в абзаце о долгой остановке названа та же зона и та же
причина.

Сторожа: «an async listener fails there before its first await too», «an async
onCancel callback fails before its first await the same» и «an async listener
fails in the zone of the body when …» на секцию и на сдавшееся тело, все
на настоящем времени и своих зонах.

## M14. Остановка через `unattended` не ждётся

Зонд: `onDispose` и остановка на 10 мс в `onCancel` через `unattended` —
`[dispose (device released), outcome: Cancelled(manual), device stopped]`;
с `join` вокруг операции, которую остановка прерывает, —
`[device stopped, dispose (device released), outcome: Cancelled(manual)]`.

После фрагмента: «That is all it does: the job does not wait for the stop…»
и что ждать остаётся `join` вокруг прерываемой операции, если она кончается
только с остановкой устройства, как миграция кончается, только прочитав токен.
«Hand the stop to the job» стало «run the stop as work the job does not wait
for». Сторожа: «the job does not wait for the stop it handed to unattended», «a
join around the operation the stop interrupts waits for it» и «a join around an
operation that ends first waits for nothing more».

## L38 и слово «operation» из L29

Зонд: необязательный ребёнок отменён напрямую, ветка «Asking the job» —
`log: thumbnail failed: Cancelled(manual)`, исход
`Done(page without a thumbnail)`.

Последний абзац страницы разбит надвое. Первая половина называет оба случая
чужого `Cancelled`: операцию, которая ждёт `value` отменённой задачи (слово
«operation» из L29), и ребёнка, отменённого напрямую. Дальше — что ветка
«Asking the job» пишет такой `Cancelled` в лог как сбой, и фрагмент
с `if (error is! Cancelled)` после `ctx.check()`. Вторая половина — ветка,
которая пробрасывает любой `Cancelled`; вместо `Cancelled(handler)` там теперь
«a `Cancelled` whose reason is `HandlerCancelReason`» — это часть L1
о странице: напечатано было бы
`Cancelled(handler: child null: Cancelled(manual))`.

Сторожа: «the clause of Asking the job logs a cancelled child as a failure», «a
test of the type tells a cancelled child from a failed one» на отменённый
и на упавший ребёнок, «an operation waiting for a cancelled job passes check».

## L39. Порядок последствий принятия

Зонд: `[child onCancel, parent onCancel, whenCancelled, cancel() returned]`.
Дети поставлены первыми в обеих версиях. Сторож «accepting reaches the children
at once…» проверяет и `onCancel` самой задачи после ребёнка.

## L40. Слова с двумя предметами

- «section» для частей страницы на `cancellation.md` ушло: «Each part of the
  page below», две ссылки вместо «the section on catching» и «the token
  section». В переводе «раздел» и «секция» и так разные слова, «Каждый раздел
  ниже» оставлен;
- «hand over» остался только за базой, которую задача отдаёт: «is handed over
  the same way» стало «goes through `onCancel` the same way», «A stop that
  takes time is handed over differently» — «needs more»;
- «errors included» стало «`Error` included», как в переводе;
- на `outcomes.md` «the cancellation listener» до введения `whenCancelled` — «a
  listener registered with `fetch.whenCancelled`» со ссылкой на «Reacting
  before the outcome»; «Only a child is linked this way» — «A job that is not a
  child gets no such link»; «announced» ушло с правкой L25.

## L41. Ссылки на `cancellation.md`

«[Catching errors of the operation](#catching-errors-of-the-operation)»
и «[A token through `onCancel`](#a-token-through-oncancel)». Часть
о `extending.md` открыта до её страницы.

## L42. Определения

`CancelToken` — «the database client's stop signal and not a type of this
package» в требовании раздела и в комментарии вступления. `readyFlag()`
«returns a job made with `Job.deferred`, because `ctx.run` refuses a job that
starts itself»; зонд: `run` бросает
`ArgumentError: … starts itself; a child is made with Job.deferred`. У `report`
показано тело: `fetch` создан через `Job.deferred`, тело ждёт `ctx.run(fetch)`
и ничего не ловит.

## L43. Форма

Вторая половина: ошибочный `join` вокруг шага с `ctx.run` стоял под заголовком
ответа «Holding the cancellation back». Разошлось с обоими предложенными
путями: шаг с ребёнком стал отдельным разделом «A step that runs a child» —
требование, «The first attempt» с тем же одним `join`, ответ «Holding the
cancellation back». Так обещание вступления сходится без правки, а «One `join`
for the step» остаётся ответом для обычного кода. Якорь «Holding the
cancellation back» не изменился. Первая половина — вопрос владельцу,
не тронута.

## L44, L45, L46

- L44: «neither does … any callback of the observer: `onError` and `onFinish`
  hear the failure, and it reaches the zone all the same». Сторож «onError of
  the observer hears the failure and does not observe it».
- L45: «`done` never throws; with `value` the waiting code gets the error
  itself and has to handle it, as with any `Future`». Сторож «value left
  unhandled throws the error, as any future does».
- L46: строки `zone:` и `status:` поменялись местами, проза за ними. Сторож
  собирает трассу одним журналом, в порядке событий.

## L12, L19, L21, L25

- L12: абзац на `cancellation.md` и dartdoc `onCancel`: тело, которое сдаётся
  само, кончается `Cancelled`, но `onCancel` не вызывает. Сторож «a body that
  gives itself up runs no onCancel», оба пути: бросок и отмена ребёнка.
- L19: `runAll` в списке членов, которые бросают после принятия, — на странице
  и в dartdoc `JobContext`; `runAll` и `each` в dartdoc `unattended`
  и `throwIfUnattended`; `runAll` в dartdoc `Job.deferred`. Сторожа: `runAll`
  в «after the cancellation, the waiting members throw…» и «runAll inside
  unattended work throws and starts no branch». Непустой `runAll` там бросает
  тем же сообщением, что и `run`: отказ приходит на допуске ветки. `each`
  из `unattended` держал сторож и раньше. Кто зовёт `check()` — часть
  `extending.md`.
- L21: dartdoc `SiblingCancelReason` и `cause`, строка страницы и перечень
  встроенных причин: ошибка или отмена другой ветки либо ошибка самой группы,
  например `ArgumentError` о задаче, которую она не приняла веткой. Сторож «a
  group that refused a job gives the others its ArgumentError».
- L25: регистрация изнутри прохода выполняется сразу, впереди ждущих;
  на странице абзац переписан, «A listener added during notification runs
  immediately» ушло в него, в dartdoc `whenCancelled` — «ahead of the callbacks
  still waiting in that pass». Сторож «a listener registered inside the call
  runs ahead of the waiting».

## L60 на этих страницах

В обоих файлах сторожей новый последний тест «every piece of code on the page
is a run of lines of this file», общий код — `test/support/page_code.dart`.
Блок `dart` страницы режется на куски по пустым строкам, и каждый кусок должен
найтись в исходнике сторожа целыми строками подряд; отступы, пустые строки
и `// ignore:` теста не считаются, а первая строка куска может быть концом
строки теста — там, где тест отдаёт выражение страницы своему помощнику. Первая
редакция сверяла каждую строку отдельно, по подстроке; ревью показало четыре
правки страниц, которые она пропускала, находка 2 ниже. До правки не находились
вступление `cancellation.md`, первая строка первой попытки, фрагмент
`whenCancelled` и все `print` страницы `outcomes.md`. Теперь вступление
гоняется четырьмя тестами — без отмены и с отменой во время чтения, миграции
и секции, — первая попытка идёт дословно через `watch`, страница исходов
печатает через свой `print` в журнал, а фрагмент `whenCancelled` стоит в тесте
целиком. Код первой попытки гоняется без наблюдателя, как на странице: в её
трассе наблюдателю нечего печатать.

## Мутации

`.artifacts/2026-09-28-cancellation-outcomes-pages/mutate.py`, лог
`mutations.out`, снимок — `snapshot/`. Гонялся весь набор, в копии дерева
`../solo-mut-pages`; после прогона каждый файл сверен со снимком через `cmp`.

| Мутация | Красные новые сторожа | Прочих красных |
| --- | --- | --- |
| l39 свои `onCancel` до каскада на детей | порядок принятия | 1 |
| l12 тело, сдавшееся само, зовёт `onCancel` | `onCancel` не вызывается | 2 |
| l25 регистрация изнутри прохода ждёт очереди | регистрация изнутри прохода | 1 |
| m13a future `async`-слушателя ловится | слушатель до `await` | 1 |
| m13b future `async`-колбэка `onCancel` ловится | `onCancel` до `await` | 1 |
| l19 пустой `runAll` после принятия не бросает | список членов | 1 |
| l21 отказ в допуске даёт другую причину | `ArgumentError` группы | 0 |
| l44 наблюдатель считается наблюдением | `onError` не наблюдает | 2 |
| l45 `value` глотает провал | `value` без обработки, упавший ребёнок | 39 |
| u1 `run` и `runAll` работают из `unattended` | `runAll` из `unattended` | 2 |
| p1 вступление ждёт чтение через `join` | код страницы | 0 |
| p2 проверка типа на странице перевёрнута | код страницы | 0 |
| p3 `print` страницы исходов расходится | код страницы | 0 |
| p4 тело `report` ловит ошибку `fetch` | код страницы | 0 |
| q1 трасса статуса в старом порядке | цитаты страницы | 0 |

Сторожа M13 держат и прежние тесты «после первого `await`»: мутации, которая
отличала бы бросок до `await` от броска после, в Dart нет, `async`-функция
синхронно не бросает. M14 мутацией не проверен: ядро, которое ждёт работу
`unattended`, — не одна строка.

## Перевод

Изменённые абзацы переведены заново и прошли `humanizer-ru`: сканер (через
`uvx ru-humanizer`) — 100 из 100, запретов нет. В тронутых абзацах стояли
одиннадцать старых тире; все сняты, в том числе в абзаце об `ignore()`
и в перечне причин, куда правка пришла одной фразой.

## Проверки

`async_job`: format, analyze, `dart doc --dry-run`, 793 теста. Документы:
заливка, ширина, переводы, ссылки, форма разделов, сборка сайта и её сторож.
`jargon.py` чист, `bare_names.py` называет «future» и «Dart» — так эти страницы
пишут и до правки.

## Независимое ревью

Ревьюер на Opus, в копии дерева `../solo-mut-pages`. Зонды, код обеих страниц,
собранный против дерева (22 блока, `dart analyze` чист), мутации и проверки —
`.artifacts/2026-09-28-cancellation-outcomes-pages/reviewer/`; отчёт он
записать не смог, инструмент отказал субагенту, и `report.md` там сохранён
из его сообщения. Верны: порядок «каскад, свои `onCancel`, `whenCancelled`»,
регистрация во время каскада и изнутри прохода, что бросает после принятия
и из `unattended`, зона `async`-колбэка при `cancel()` и при каскаде родителя,
тело, которое сдалось, без `onCancel`, `value` отменённой задачи внутри
операции, «any callback of the observer» вместе с `onUnanswered`, сторожа L44,
L45 и L46, форма нового раздела, ссылки и якоря, переводы по смыслу, кроме
находок 3 и 11. Каждую находку я проверил своим зондом —
`.artifacts/2026-09-28-cancellation-outcomes-pages/probe_review_test.dart`:

```text
R1 [creation: Bad state: listener]
R3 [device released, outcome: Cancelled(manual), device stopped]
R4 [child onCancel, child: Cancelled(parent), job: Cancelled(handler: why)]
R5 Cancelled(manual) ManualCancelReason
R6 group threw StateError; cause StateError
R7 thrown Cancelled(manual); branch Cancelled(parent) ParentCancelReason
```

Мутации ревьюера по всему набору:

| Мутация | Красных | Итог |
| --- | --- | --- |
| K1 `whenCancelled` раньше своих `onCancel` | 1 | поймана не сторожем L39 |
| K2 сдавшееся тело не отменяет детей | 9 | поймана |
| K3 `runAll` пропускает отвергнутую ветку | 0 | эквивалентна |
| K4 слушатели в зоне создания | 2 | поймана |
| K5 `onCancel` в зоне создания | 1 | поймана |
| K6 регистрация во время каскада вызывается сразу | 1 | поймана |
| K7 при отказе ветки получают `StateError` | 1 | поймана |
| K8 `runAll([job])` после принятия отдаёт `[]` | 0 | выжила, находка 7 |
| K9 `each` глотает отказ | 1 | поймана |
| K10 задача ждёт остановку из `unattended` | 2 | поймана |
| P1 без `ctx.check()` в «Asking the job» | 0 | выжила, находка 2 |
| P2 без `ctx.check()` во фрагменте `thumbnail` | 0 | выжила |
| P3 `log` перед `check` | 0 | выжила |
| P4 без `await` у `fetch.cancel` | 0 | выжила |
| P5 перевёрнута проверка типа | 1 | поймана |

После правок я прогнал выжившие своим `mutate.py`, лог
`mutations-p5-p6-p7-p8-k8.out`: K8 краснеет на «after the cancellation, the
waiting members throw…», P2, P3 и P4 — на сверке кода страницы. P1 выживает
и теперь: без `ctx.check()` код «Asking the job» совпадает строка в строку
с кодом соседнего теста «on Exception alone takes the Cancelled of join»,
и сверка находит его там. Она доказывает, что код страницы гоняется,
но не знает, какой тест даёт трассу под каким блоком; это остаётся за L60.

**1. Medium. «None of its errors reaches … the job's creation zone» —
не всегда.**

**Вердикт: принято, Medium.** Мой зонд R1: у задачи, стартующей саму себя,
слушатель сдавшегося тела бросает в зону создания, как и при отмене,
придержанной секцией (`M13d held=true` в `probe.out`). Зона создания снята
с первой фразы, вторая называет все три пути; сторожа на секцию и на сдавшееся
тело.

**2. Medium. Сверка кода страницы держит меньше, чем обещает шапка.**

**Вердикт: принято, Medium.** Сверка переписана: куски блока по пустым строкам,
каждый целыми строками подряд; шапки обоих сторожей говорят «every piece of its
code to a run of lines of this file». Разошлось с предложенным: первая строка
куска может кончать строку теста, иначе вступление и первая попытка
требовали бы убрать из тестов их обёртки. Чтобы фрагмент `thumbnail` стоял
в тесте подряд, отмену ребёнка ставит сам `renderThumbnail`, через
`ctx.job.cancel`, — всё так же напрямую, не через родителя. P1 выживает,
причина — выше.

**3. Low. Совет о `join` верен только при условии.**

**Вердикт: принято, Low.** Мой зонд R3 — тот же итог. Условие дописано в обеих
версиях, «ждёт её» из перевода ушло; сторож «a join around an operation that
ends first waits for nothing more».

**4. Low. Абзац о сдавшемся теле не называет детей, и вернулось «hand».**

**Вердикт: принято, Low.** Зонд R4. Текст по предложению: отмена по-прежнему
уходит детям, свои `onCancel` не зовутся, и ни один токен, отданный
в `onCancel`, не отменяется. Сторож проверяет ребёнка с `ParentCancelReason`.

**5. Low. Последняя фраза верна только для ребёнка.**

**Вердикт: принято, Low.** Зонд R5. «With `HandlerCancelReason` for a child's,
and with the other job's own reason for an operation's».

**6. Low. `cause`: «the `ArgumentError`» уже кода.**

**Вердикт: принято, Low.** Зонд R6: уже работающий хэндл даёт `StateError`
и группе, и соседям. Dartdoc поля — «such as the [ArgumentError] or
[StateError] it refused a job with».

**7. Low. Сторож L19 держит `runAll` только пустым.**

**Вердикт: принято, Low.** Зонд R7. В списке членов `runAll` с отложенной
задачей, и сторож проверяет, что она кончилась с `ParentCancelReason`.

**8. Low. Один проход назван тремя словами.**

**Вердикт: принято, Low.** Везде «the pass», «before the call» стало «earlier»;
в переводе «проход».

**9. Low. Ссылка из раздела на него же.**

**Вердикт: принято, Low.** «The clause above», «Ветка выше».

**10. Low. Число членов без имён.**

**Вердикт: принято, Low.** В dartdoc `unattended` и `throwIfUnattended` члены
названы.

**11. Low. «На ней» в переводе.**

**Вердикт: принято, Low.** «На `SiblingCancelReason` `origin`
и останавливается».

Правленые русские абзацы снова прошли сканер: 100 из 100, тире нет.

