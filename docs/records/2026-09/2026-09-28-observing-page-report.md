# `async_job`: `observing.md` по находкам ревью

> **Состояние на 2026-09-28:** сделано в `7763e54`; независимое ревью нашло одну ошибку
> таблицы и пять мест поменьше, все приняты и исправлены.
> **Что это:** отчёт о правке `packages/async_job/doc/observing.md`, перевода
> `docs/ru/async_job/observing.md` и абзаца `doc/cancellation.md` по находкам
> `2026-09-26-async-job-project-review.md`: M11, M12, L47, L51, M26 и часть
> L61, которая про эту страницу.
> **Связанные записи:** `2026-09-26-async-job-project-review.md`,
> `2026-09-28-cleanup-page-report.md` (предыдущая страница того же пункта
> порядка работ), `2026-09-25-observing-rakes-report.md` (вычитка страницы,
> откуда её первые попытки).

Поведение ядра не менялось: страница говорила неверно в двух местах и шире кода
в третьем, а ядро право. Dartdoc `JobObserver` сужен так же, как таблица.
Зонды — `.artifacts/2026-09-28-observing-page/probe_observing_test.dart`, вывод
рядом, `probe.out`.

## M11. Шаг `uncancellable` под придержанной отменой

Зонд: отмена на 10-й мс, шаг падает на 20-й.

| Шаг | С `Reporter` | Без наблюдателя |
| --- | --- | --- |
| `ctx.uncancellable` | `onError`, зона | зона |
| `ctx.join` | `onError` | никто |

Вторая строка таблицы «Where errors go» теперь говорит о том, когда задача
приняла отмену, как и третья: «the job accepts a cancellation after it: one
arriving before the error leaves the body, while the job waits for its children
or runs its cleanup, or one `ctx.uncancellable` held while its step failed».
Разошлось с предложенным: ревьюер дописывал к строке отдельный случай, а здесь
две соседние строки стали парой по одному глаголу — приняла отмену после
провала или до него, — и секция встала в первую по тому же правилу. Под
таблицей абзац о том, почему шаг секции и тот же шаг за `join` попадают
в разные строки. На `cancellation.md` в «Holding the cancellation back» — та же
мысль в двух фразах и ссылка на таблицу.

Сторожа: «a step of uncancellable fails first: onError, then the zone» и «the
same step behind join fails after: onError or nobody».

## M12. Засечка отмены

Зонд: ребёнок `cancellable: false` на 110 мс, уборка на 50 мс; тело, бросившее
`Cancelled` на 10-й мс, даёт `ran 50 ms`, хотя проработало после отмены 150.
Тело, выпустившее отмену ребёнка через `await ctx.run(child)`, даёт `0 ms` при
100 мс работы после неё. `whenCancelled` у тела, которое сдалось само,
срабатывает после дочерних.

У абзаца теперь код наблюдателя: `Expando<Stopwatch>`, `whenCancelled`
в `onStart`, печать в `onFinish`. «Fires when the job accepts the cancellation»
стало «accepts a cancellation from outside», и в конце абзаца оговорка: тело,
которое сдаётся само, бросая `Cancelled` или выпуская отмену ребёнка, принимает
отмену в момент броска, но `whenCancelled` срабатывает после дочерних,
и засечка показывает одну уборку.

Сторожа: «a body that gives itself up counts from the end of its children» и «a
child's cancellation let out counts the same way». Наблюдатель в тесте идёт
по фейковому времени, а не по `Stopwatch`: его `fake_async` не двигает. Это
та же копия кода, о которой L60.

## L47. «Every error»

Зонды:

- собственная отмена задачи из работы `unattended` или из действия, которое
  бросил `wait` (`ctx.check()` после отмены), не доходит ни до `onError`,
  ни до `onUnanswered`: её отсеивает `_isOwnCancellation`;
- тот же экземпляр, переброшенный колбэком `whenCancelled`, доходит
  до `onError` и `onUnanswered`;
- ошибка `ctx.join`, вызванного без `await`, уходит в зону мимо наблюдателя,
  и `onUnanswered` о ней не спрашивают. Так же уходит всё, что бросают `wait`,
  `uncancellable` и `run`, вызванные без `await`, и собственная отмена задачи
  тоже: её бросает future брошенного вызова. `wait` отличается одним: когда
  тело кончилось, он отпускает действие, и его ошибка идёт как поздняя ошибка
  брошенного действия. Зона при этом та, где идёт тело, у отложенной задачи —
  зона запустившего. Это нашло ревью, зонд
  `.artifacts/2026-09-28-observing-page/probe_unawaited_test.dart`, вывод
  `probe_unawaited.out`.

«An observer hears every error of its job» стало «hears through `onError` the
errors its job catches, all but its own cancellation». В таблице две новые
строки: собственная отмена из брошенного `wait` и `unattended` — никто в обоих
столбцах; то, что бросает вызов контекста без `await`, собственная отмена
включительно, а у `wait` — пока тело не кончилось, — зона, где идёт тело, «as
with any future nobody awaits». Под таблицей абзац о таких вызовах и о зоне
отложенной задачи, в dartdoc `wait`, который советует
`unawaited(ctx.wait<Db>(...))`, — фраза о том, куда идёт брошенное. Разошлось
с предложенным: ревьюер писал в строке «A `Cancelled` other than the job's
own», но колбэк, перебросивший собственную отмену, до `onError` доходит,
и отдельная строка точнее. В dartdoc `JobObserver` «told about every error of
the job» стало «told about the errors the job catches, all but its own
cancellation».

Сторожа: «the job's own cancellation out of work left behind: nobody», «the
same cancellation thrown by a callback: onError», «a join the body did not
await: the zone, past the observer», «any call the body did not await: the
zone, cancellation included», «a wait left behind by a body that ended: an
abandoned action» и «a call the body did not await: the zone the body runs in».

## L51. Пять мест

- «the body gives up with it» → «fails with it»: «gives up» на соседних
  страницах и в dartdoc `cancel` значит «бросает `Cancelled`»; в абзаце засечки
  оно теперь так и употреблено;
- `describe` определён: «A job can be given a `key` and a `describe` callback
  when it is created», и «returns something» стало «returns a description that
  is not empty» — у пустой строки вид `Job($key)`, сторож — строка в «the four
  string representations»;
- «cannot tell apart» → «cannot tell from a cancellation»;
- «shows up with the rest of that wait» → «adds the rest of that wait to the
  count»;
- «this package uses it in its own tests» снято.

## M26. Заголовок перевода

«Время двигает тест» стало «Тест двигает время». Ссылок на якорь нет, копия
в `site/` собирается и под гитом не лежит. В порядке работ M26 не стояла,
но она про эту страницу.

## L61 на этой странице

Засечка для самоотмены — сторожа M12 выше. «Ошибка хука идёт в текущую зону»:
«a hook's error goes to the zone that calls it», задача создана в одной зоне
и отменена до старта из другой, ошибка `onFinish` приходит в зону отменившего.
Утверждение стоит за пределами `runZonedGuarded`. Остальное в L61 — `check()`
из `wait` и `uncancellable` (закрыто сторожами M29) и фрагмент `MyJob` страницы
`extending.md`, он остаётся открытым.

## Мутации

`.artifacts/2026-09-28-observing-page/mutate.py`, лог `mutations.out`, снимок
ядра — `snapshot/`. Гонялся один файл, `observing_rakes_test.dart`; прогон
всего набора и мутации к остальным сторожам — в «Независимом ревью»:

| Мутация | Красных |
| --- | --- |
| z1 `onFinish` зовётся в зоне создания | 1, «a hook's error goes to the zone that calls it» |
| t1 `whenCancelled` тела, сдавшегося само, до дочерних | 2, оба сторожа M12 |
| o1 собственная отмена не отсеивается | 1, «the job's own cancellation out of work left behind» |
| u1 провал шага секции не отмечается первым | 1, «a step of uncancellable fails first» |

После прогона оба файла ядра сверены со снимком побайтно.

## Перевод

Изменённые абзацы переведены заново и прошли `humanizer-ru`: сканер (через
`uvx ru-humanizer`) — 100 из 100, запретов нет, тире в изменённых абзацах нет.
Абзац, где «сдаётся» стало «падает», тронут одним словом, но проходил сканер
целиком, и его два тире ушли вместе с правкой. После ревью четыре абзаца
и строка таблицы тронуты снова и прошли сканер ещё раз: 89 из 100, запретов
нет, тире нет.

## Независимое ревью

Ревьюер на Opus, в копии дерева; первый запуск остановил сбой проверки
безопасности автоматического режима, второй дошёл до конца. Зонды, вывод, лог
мутаций и проверки — `.artifacts/2026-09-28-observing-page/reviewer/`. Верны:
код засечки, прогнанный дословно на настоящем `Stopwatch` (голый `await` 290
мс, `ctx.wait` 0, самоотмена с ребёнком на 110 мс и уборкой на 50 мс — 52),
строки таблицы 1–3, 6 и 7 со всеми тремя наблюдателями, новые абзацы о секции
и `join`, зона хука, строковые виды, термины «gives up» и «accepts a
cancellation», перевод, отчёт и вердикты. Мутации по всему набору, каждая
сверена со снимком через `cmp`:

| Мутация | Красные новые сторожа | Прочих красных |
| --- | --- | --- |
| z1 `onFinish` в зоне создания | зона хука | 0 |
| t1 `whenCancelled` самоотмены в момент броска | оба сторожа засечки | 1 |
| t2 он же только к концу задачи | оба сторожа засечки | 2 |
| o1a своя отмена из брошенного `wait` не отсеивается | своя отмена: никто | 2 |
| o1b своя отмена из `unattended` не отсеивается | своя отмена: никто | 7 |
| u1 провал шага секции не отмечен первым | шаг секции первым | 4 |
| u2 секция не держит отмену | шаг секции первым | 17 |
| j1 провал после отметки отмечен первым | тот же шаг за `join` | 15 |
| c1 `Cancelled` из колбэка `whenCancelled` не объявлен | брошенный колбэком | 0 |
| c2 ошибка колбэка `whenCancelled` не отвечена | брошенный колбэком | 7 |
| j8 поздний `join` без `await` сообщён и в `onError` | `join` без `await` | 1 |
| k1 провал в обход `onUnanswered` прямо в зону | ни один | 21 |
| d1 пустое описание печатается `Job(k: )` | ни один | 0 |

k1 и d1 после правок ниже краснеют на новых сторожах: k1 — на «a step of
uncancellable fails first» и трёх прежних, d1 — на «the four string
representations» (`mutation-k1.out`, `mutation-d1.out`).

**1. Medium. Вызов `wait` без `await` бросает собственную отмену в зону,
а таблица ведёт к «никто».**

**Вердикт: принято, Medium.** Воспроизвёл своим зондом: `wait`, `join`,
`uncancellable` и `run` без `await` отдают зоне всё, что бросают, пока тело
идёт, отмену тоже, с любым наблюдателем; `wait`, чьё тело кончилось, ведёт себя
как брошенное действие, пятая строка. Строка таблицы расширена, под таблицей
абзац, dartdoc `wait` дополнен. Фраза dartdoc `join` о том, что `wait` отдал бы
ошибку в `onError` и `onUnanswered`, верна: она о теле, которое уже кончилось.
См. L47 выше.

**2. Low. Зона строки о `join` без `await` — не зона создания.**

**Вердикт: принято, Low.** Мой зонд: отложенная задача, созданная в зоне A
и запущенная из B, отдаёт ошибку в B. Строка говорит «the zone the body runs
in», абзац под таблицей называет зону запустившего; сторож «a call the body did
not await: the zone the body runs in».

**3. Low. «Hears the errors its job catches» шире кода: свою отмену задача
ловит и не сообщает.**

**Вердикт: принято, Low.** «All but its own cancellation» на странице,
в переводе и в dartdoc `JobObserver`.

**4. Для ясности. «The failure came before the cancellation the section held»,
хотя отмену попросили раньше.**

**Вердикт: принято.** В `cancellation.md` «before the job accepted the
cancellation the section held»; в абзаце «A failure comes first» «a
cancellation arriving in that time» стало «a cancellation the job accepted in
that time». Перевод так же.

**5. Low. Две новые мысли не держит ни один сторож.**

**Вердикт: принято, Low.** Сторож M11 гоняет ещё и `Answering`: `onError`,
`onUnanswered`, без зоны. В «the four string representations» строка с пустым
`describe`. Код `SlowCancellations` со страницы по-прежнему не гоняется: это
L60.

**6. Low. Таблица мутаций отчёта про один файл и пять сторожей из восьми.**

**Вердикт: принято, Low.** В «Мутациях» сказано, что гонялся один файл; таблица
ревьюера выше.

## Проверки

`async_job`: format, analyze, 770 тестов. Документы: заливка, ширина, переводы,
ссылки, форма разделов, сборка сайта.
