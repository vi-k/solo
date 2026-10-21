> **Состояние на 2026-10-21:** волна идёт. Части 1–4 сделаны и закоммичены,
> часть 5, ревью сделанного и закрытие впереди.
> **Что это:** отчёт волны формы по плану `2026-10-21-form-wave-plan.md`:
> что ушло из dartdoc и где это сказано на странице, проверенные решения,
> строки `///` до и после.
> **Связанные записи:** `2026-10-21-form-wave-plan.md`,
> `2026-10-21-async-job-project-review-3.md` (M3, L7, «Страницы»),
> `2026-10-21-solo-project-review-3.md` (M4, L5, L13).

# Отчёт волны формы

## Часть 1. Сторож ссылок dartdoc

Коммит `build: check_links holds the links of dartdoc`. `tool/check_links.py`
читает блоки `///` в `packages/*/lib/` целиком, сняв `/// `, без оград кода
и код-спанов. Ссылка в репозиторий — только адрес `blob/main` с файлом и якорем
из дерева; относительная ссылка и `#…` — ошибка, как и ссылка dartdoc вверх,
из ядра на страницу `solo`. Класс `Dartdoc` в `tool/check_links_test.py` — 11
тестов; пять мутантов прохода — без пропуска оград, построчное чтение, без
проверки `main`, без проверки «вверх», без снятия код-спанов — убиты все.

## Часть 2. Dartdoc ядра

Тринадцать членов `packages/async_job/lib/src/job.dart`, `job_context.dart`
и `observer.dart`. Писал исполнитель на Opus в копии дерева, я сверил каждое
удаление со страницами своей командой и вернул три факта, которых нет
ни на одной странице (ниже, «Возвращено при сверке»). Код вне `///` не менялся.

| Член | До | После |
| --- | ---: | ---: |
| `JobContext.runAll` | 116 | 41 |
| `JobContext.unattended` | 87 | 47 |
| `JobContext.uncancellable` | 79 | 34 |
| `JobContext.run` | 59 | 40 |
| `JobContext.abandonable` | 54 | 35 |
| `JobContext.join` | 53 | 27 |
| `Job.new` | 61 | 36 |
| `Job.ignoreFailure` | 50 | 32 |
| `Job.visitErrors` | 48 | 40 |
| `Job.each` | 48 | 29 |
| `Job.then` | 48 | 29 |
| `JobObserver.onError` | 52 | 31 |
| `JobAnswerer.onUnanswered` | 49 | 28 |
| Всего | 804 | 449 |

В числах и последний абзац каждого члена — «See …» со ссылкой на раздел
страницы, от двух до пяти строк. Первый абзац у всех — одна фраза, блок кода —
не больше одного: вторые блоки `join`, `uncancellable` и `unattended` ушли.

### Длиннее 30 строк

- `runAll` (41): договор решений 27 и 100 и порядок допуска, которого нет
  ни на одной странице.
- `unattended` (47): абзац решения 38, граница зоны, опрос `check`,
  `abandonable` и `join` после конца тела, зона вложенной работы — всё, кроме
  границы, только здесь.
- `run` (40): список допуска — решения 29, 83 и 100; ссылки на три раздела.
- `visitErrors` (40): правила обхода, 15 строк; полностью их не говорит ни одна
  страница.
- `Job.new` (36): прежний блок кода в 10 строк; текст — 24.
- `abandonable` (35): тип при `unawaited`, значение брошенного без отмены
  вызова, момент, с которого ловится позднее значение.
- `uncancellable` (34): вложенные секции, позднее приземление при живом
  ребёнке, передача с `disown` — после ухода блока кода только здесь.
- `ignoreFailure` (32): когда звать, не позже `onFinish`; страницы этого
  не говорят.
- `onError` (31): абзац решения 18 — 12 строк.

### Что ушло и где это сказано

Строки страниц — на `85aaca10`; страницы ядра с тех пор не менялись.

- **`runAll`.** «When which» с `eagerError` — `groups.md`, «When one failure
  makes the rest pointless», таблица 167–176, вход 8–14. «The stop is
  cooperative» — там же, «What `runAll` does not promise», 473–482. «No branch
  ends before the group has decided» — таблица стадий 190–212 и 484–487. Что
  отмена развязывает и что нет — «Branches that wait for each other», 254–261.
  Успех без ожидания ветвей и провал с ожиданием — 199–204, 210–212. Брошенный
  объект — тот, что в исходе, — сжат до «as `await ctx.run(child)` would throw
  it»; 157–165.
- **`unattended`.** «Четвёртый член семьи ожидания» — README ядра, «The context
  at a glance». Граница зоны в обе стороны сжата до двух оборотов —
  `errors.md`, «Work handed to the job», 342–351. Голый `unawaited` — «Work the
  job does not wait for», «The first attempt», 306–322. «How the work stops»
  с блоком `ctx.onCancel(() => ctx.unattended(device.stop))` —
  `cancellation.md`, «A stop that takes time», 518–576.
- **`uncancellable`.** Удержание до закрытия секции — `cancellation.md`,
  «Holding the cancellation back», 299–325. Шаг, который бросил при удержанной
  отмене, — 327–331. Невзятая секция и тело, которое отменило себя само, —
  333–340. Отличие от `join` — таблица 32–36, 277–279. Правила движка
  не держатся — 323–325. Блок `commit` + `disown` — `cleanup.md`,
  «Unregistering inside the action».
- **`run`.** `cancellable: false` у ребёнка и проверка родителя после успеха —
  `children.md`, 86–105. Будущее `run` и `ignoreFailure` ребёнка — 151–157. Что
  такое `ChildJob` — 66–70. Регистрация на следующей строке — `cleanup.md`,
  «The second attempt», 231–263; ловушка осталась вторым абзацем.
- **`abandonable`.** Правило «не дошло до тела — без условий, дошло — на стек»
  и когда срабатывает позднее значение — `cleanup.md`, «A value that comes
  late», таблица 498–502, 504–507. `dispose` против `discard`, утечка замка
  на успешном пути, `discard` не смотрит на возвращённое — 20–27, 47–65,
  135–138.
- **`join`.** «`abandonable` отпускает, `join` остаётся» — `cancellation.md`,
  149–152. Второй блок кода ушёл по правилу 2. Ошибка действия и невзятый
  вызов — 185–187, 410–412; `errors.md`, 573–588.
- **`Job.new`.** Что ограничивает срок и как он встречает `uncancellable`,
  таймер в тесте — `time.md`, «A deadline of the job», 169–215. Наследование
  наблюдателя — `observing.md`, 59–61, одна фраза осталась.
- **`ignoreFailure`.** Сравнение с `Future.ignore` и ожидание `done`/`value` —
  `outcomes.md`, 102–136. Ребёнок и ветвь — `errors.md`, 184–186;
  `children.md`, 231. Случай движка — `extending.md`, 675–687, и dartdoc
  `JobBase.finish`. «Задача — не фоновая работа» — `errors.md`, «Work the job
  does not wait for».
- **`visitErrors`.** Абзац о хуках наблюдателя и `Solo.unansweredHandler` —
  `errors.md`, 423–435; упоминание `solo` было ссылкой вверх.
- **`Job.each`.** Стек уборки копится до конца задачи, `onCancel` тоже —
  `streams.md`, 172–217. С `cancellable: false` её ничто снаружи
  не останавливает, и внутри тела другой задачи она той не ребёнок — 285–308.
- **`Job.then`.** Обратный ход отмены и `ChainCancelReason` — `chains.md`,
  43–72. Продолжение до конца источника, `started: false` — 68–72, 224–240.
  Источник не запускается, наблюдатель не наследуется — 224–240. Пересылка
  провала и отменённое продолжение — 166–180. Что возвращает колбэк — 182–222.
- **`onError`.** Куда ошибка идёт дальше, что держит `ignoreFailure`
  и `isCancellationError` — `errors.md`, «Where each error goes», 173–196.
  Откуда берётся `Cancelled` без исхода — «Rare routes», 567–569.
- **`onUnanswered`.** Умолчание и переопределение — `errors.md`, «Answering for
  errors», 369–373. Полный список ошибок без исхода, `ignoreFailure`
  и `isCancellationError` — таблица 173–180, «What keeps an error out of the
  answer» 182–196, «Rare routes» 567–568; случаи движка — ссылка
  на `JobBase.finish`. Брошенное переопределением — 394–399.

Фразы удалённых абзацев искались по `packages/*/test`, `packages/*/example`
и `tool/`: dartdoc ядра не читает ни один тест. Фраза «the held one never
lands» осталась в `uncancellable` нарочно — её держит строка
`test/extending_test.dart:577`.

### Решения `docs/settled.md`

- 18 — фильтр `identical` и `Expando` в `onError`: абзац остался почти
  дословно.
- 27 — зависание `runAll` на замке и оба выхода: второй абзац, жирным.
- 29 — отказанный `Job.deferred` остаётся незапущенным: в `run` для одного
  ребёнка и в `runAll` для группы.
- 38 — незаконченная работа держит задачу: абзац `unattended` почти дословно,
  `solo` названа текстом, без ссылки.
- 100 — отказ допуска не трогает ни одну ручку, `done` ждёт; после отказа
  движка остальные ручки не запускаются: в `runAll`.
- Ещё стоят на тексте и остались договором: 5 (удержание отмены), 12
  (незапущенный `Job.deferred` из тела `void`), 15 (неувиденный `Failed` через
  микрозадачу), 16 (хук только слышит), 22 (по одной ошибке, отмена
  не приходит), 67 (продолжают один раз), 83 (ошибки допуска синхронны).
- 59 — `Solo.job` — относится к части 3.

### Возвращено при сверке

Исполнитель выбросил три факта, которых не говорит ни одна страница; правило 4
плана велит такие оставлять коротко. Вернул:

- `unattended`: `abandonable` и `join` после конца тела — на принявшей отмену
  задаче значение отпускается и вызов бросает отмену, на законченной значение
  с `dispose` или `discard` отпускается и вызов бросает `StateError`;
- `unattended`: опрос `check` на задаче, которую никто не отменял, бросает
  `StateError` при раскрутке стека уборки;
- `Job.each`: срок следования за потоком задаётся снаружи — почему у него нет
  `timeout`.

### Ждёт страниц частей 4 и 5

Разбор, который пока есть только в dartdoc. Он остаётся там, пока страница его
не скажет:

- `runAll`: список читается один раз копией; пустая группа; ветвь, отменившая
  родителя до первого `await`; отказ движка после старта части ветвей; значения
  без проверки после конца тела. Место — `groups.md`, абзац о допуске рядом
  с «When `runAll` refuses».
- `runAll`: регистрация на прибытии в ветви с замком в ребёнке,
  `run(child, discard: ...)`, и её `discard` без замка — `groups.md`, «Branches
  that wait for each other».
- `unattended`: опрос `check`, `abandonable` и `join` после конца тела, зона
  вложенной работы — `errors.md`, «Work handed to the job».
- `uncancellable`: передача с `disown` — `cleanup.md`, «Unregistering inside
  the action»; позднее приземление при живом ребёнке — `cancellation.md`,
  «Holding the cancellation back».
- `run`: поздний успех после конца тела без проверки — `children.md`, «Running
  a child».
- `abandonable`: тип при `unawaited`, значение брошенного без отмены вызова,
  момент ловли — `cleanup.md`, «A value that comes late».
- `join`: проверка после действия отпускает значение, что бы ни бросила —
  `cleanup.md`, «Registering on arrival».
- `ignoreFailure`: не позже `onFinish` — `outcomes.md`, «Telling the core it is
  handled».
- `visitErrors`: правила обхода — `errors.md`, «Several failures in one error».
- `onUnanswered`: провал, который движок отдаёт уже законченной задаче, —
  только в dartdoc `JobBase.finish`; `extending.md`, «Finishing a job by hand».
  Часть 4 сжимает этот раздел — после неё dartdoc `JobBase.finish` останется
  единственным полным изложением, и это нужно назвать в итоге L7.

`Job.then` ведёт на всю страницу `chains.md`, а не на раздел: его факты
разнесены по нескольким разделам.

### Проверки части 2

`async_job`: `dart format` без изменений, `dart analyze` чисто, `dart test`
+1788. `solo` против нового ядра: `dart analyze` чисто, `dart test` +2063.
`check_links.py` и `check_links_test.py` зелёные: ссылки dartdoc ведут
в существующие разделы.

## Часть 3. Dartdoc `solo` и `flutter_solo`

Шесть членов `packages/solo/lib/src/solo.dart` и трёх файлов
`packages/flutter_solo/lib/src/`. Писал исполнитель на Opus в копии дерева,
каждое удаление я сверил со страницами своей командой; выброшенных фактов,
которых нет на страницах, на этот раз нет. Код вне `///` не менялся.

| Член | До | После |
| --- | ---: | ---: |
| `Solo.job` | 83 | 34 |
| `Solo.run` | 38 | 30 |
| `Solo.onUnanswered` | 37 | 27 |
| `SoloSelection` | 55 | 45 |
| `SoloListenable` | 38 | 29 |
| `SoloSelector` | 37 | 26 |
| Всего | 288 | 191 |

Блоки кода: у `Solo.job` ушёл блок с `TimeoutCancelReason` — тот же разбор
причины на `cancellation.md`, «A deadline of a job»; у `Solo.run` из двух
блоков ушёл повтор того же `ifCancelled`, пример `load()` остался; у трёх типов
`flutter_solo` их единственные блоки на месте. Две ссылки dartdoc остались ради
импортов: `solo_selection.dart` импортирует `solo_selector.dart`, а тот
`solo_builder.dart` только для ссылок dartdoc, и без них `dart analyze` находит
неиспользованный импорт.

### Длиннее 30 строк

- `Solo.job` (34): абзацы решений 50 и 59 и три факта, которых нет
  на страницах, — запись изнутри `keepWhile` бросает `StateError`;
  `ifCancelled` срабатывает по завершении, а `onCancel` — сразу; правило,
  которое бросило на контрольной точке, доходит до тела, и `Failed` правится
  как любой другой.
- `SoloSelection` (45): блок кода — 14 строк; из текста абзац решения 61
  и правило «селектор только выбирает» не говорит ни одна страница.

### Что ушло и где это сказано

Строки — на `359e12d4`.

- **`Solo.job`.** Зона задачи в очереди и внутри `ctx.unattended` — `jobs.md`,
  112. Очередная и идущая задача с `cancellable: false`, `close` и `force` —
       `cancellation.md`, «A whole job», 215–219. Обработчики состояния: когда
       срабатывают, что не меняют, кто их отключает, запись изнутри
       обработчика, тот же объект и равный — `state.md`, «The handlers» 497–509
       и «Handler eligibility and errors» 577–599. Срок и очередь после него —
       `cancellation.md`, «A deadline of a job», 372–420.
- **`Solo.run`.** Отказы `timeout` — сказаны в `job`, на который `run`
  ссылается; ветвление по причине срока — `cancellation.md`, «A deadline of a
  job».
- **`Solo.onUnanswered`.** Умолчание, переопределение, брошенное
  переопределением и доклад дважды — `errors.md`, «Answering for an error»;
  `canStart`, который бросил, — там же, таблица «Where each error goes».
- **`SoloListenable`.** Обе доставки — `mixins.md` пакета `flutter_solo`, «A
  controller with both deliveries»; отчёт базы под другим именем — «A report
  under another name», 251–253.
- **`SoloSelection`.** Выборка в `build` и `didUpdateWidget`, подписка только
  со слушателями — README `flutter_solo`, «Selecting one value», 319–330.
- **`SoloSelector`.** Кнопка бросает задачу `save` — README, 260–263; три
  выборки без `State` — там же.

Фразы удалённых абзацев искались по `packages/*/test`, `packages/*/example`
и `tool/`: совпадения — имя метода примера, имена тестов, цитата `vs-bloc.md`
и фраза «watching is not answering», которая в dartdoc осталась; dartdoc
ни один тест не цитирует.

### Решения `docs/settled.md`

44, 45, 46, 50, 54, 55, 59, 60, 61, 63, 64 и 95. Текст, на котором стоит
решение, остался договором или сказан страницей; правки решений не нужны. 59 —
дословно по смыслу: «A queued job that turned down `cancel` starts in its turn
and runs to its end, and `await job.cancel()` comes back only then». 50, 61, 63
и 64 — договором. 44 — в `onUnanswered`: `Failed` из отмены идёт мимо хука,
а `ifFailed` — не наблюдение. 95 — фраза ушла, `state.md` 501–505 говорит её.

### Ждёт страниц частей 4 и 5

- `Solo.job`: запись изнутри `keepWhile` — `state.md`, «The rules»; флаг
  `cancellable: false` действует, только когда задача у движка (решение 50),
  и очередная задача, отказавшая `cancel`, доходит до конца (решение 59), —
  `cancellation.md`, «A whole job»; `ifCancelled` против `onCancel` —
  `state.md`, «The handlers»; брошенное правилом на контрольной точке
  и `ifFailed` — строкой таблицы «Handler eligibility and errors».
- `Solo.onUnanswered`: каждая ошибка здесь уже прошла `onError` — `errors.md`,
  «Where each error goes».
- `SoloSelection`: селектор только выбирает; выборка раз на изменение
  и отставание от источника, который меняет значение на месте (решение 61); без
  слушателей выборка каждый раз; выборка переживает источник — README,
  «Selecting one value».
- `SoloListenable`: голый `SoloListenable` — это `SoloListenable<Object>` —
  README, «The controller as a `ValueListenable`».
- `SoloSelector`: чужой `ValueListenable` — через `SoloSelection`
  и `ValueListenableBuilder` (решение 64); виджету не нужен `State` — README,
  «Selecting one value».

### Проверки части 3

`solo`: формат без изменений, анализ чистый, +2063; его пример +112.
`flutter_solo`: формат без изменений, анализ чистый, +241; его пример +6.
`check_links.py` зелёный. Стенд `flutter_snippets.py` исполнитель собрал вне
репозитория: анализ чистый, +47.

## Часть 4. Страницы ядра

`extending.md`, `groups.md` и `cleanup.md` в `packages/async_job/doc/` и их
переводы. Писал исполнитель на Opus в копии дерева; дифф я прочёл целиком,
каждое удаление сверил с dartdoc и страницами своей командой.

| Файл | До | После |
| --- | ---: | ---: |
| `extending.md` | 699 | 616 |
| `groups.md` | 491 | 489 |
| `cleanup.md` | 523 | 524 |

### `extending.md`

«The whole engine» больше не повторяет листинг: каждая его строка уже стояла
в разделах «A job of your own», «Refusing while the job waits» и «One loop, and
no other way to start». Раздел говорит то, чего в разделах нет: движок — одна
библиотека Dart, которая импортирует `engine.dart`, потому что задача и очередь
ходят к приватным членам друг друга; таблица «Class | Members | Shown in»
по строке на кусок со ссылкой на раздел; из двух показов члена действует
поздний — `finished()`, который отпускает и очередь, `add` и `run` вместо
первой попытки. Пример двух `run()`, его трасса и ссылка на «A rule of your
own» остались. Пункт входа: «says which piece goes where».

Два последних абзаца «Finishing a job by hand» сжаты до одного, который
называет dartdoc `JobBase.finish` по имени, без адреса. Одной фразой
не обошлось: двух фактов в dartdoc нет, и они остались на странице —
`onSignOut` строит `Cancelled` при каждом вызове, и `Cancelled`, брошенный
телом или правилом из `check()`, может быть общим, `const` тоже: задача
кончается тем, который строит ядро. Второго не говорит ни одна страница
и ни один публичный dartdoc, только комментарий приватного `_outcomeChild`.
Остальное ушло туда, где сказано:

- `Done` ветке `runAll` после провала тела, когда группа о нём слышит, что она
  бросает и где остаётся значение — dartdoc `finish`, `job_base.dart`
  1357–1366;
- `ignoreFailure()` на ветке — dartdoc `runAll`, `job_context.dart` 397–402:
  в dartdoc `finish` этого нет;
- один `Cancelled` на двух детей, поиск по экземпляру, `const`
  и `AssertionError` — dartdoc `finish`, 1385–1390. Со страницы ушло
  и «а не того, кого ждало тело»: dartdoc говорит «names the child that ended
  last», и это следует из него.

Тест `extending_rakes_test.dart` с ожиданием `missing == [firstShown]` снят.
Пример под разделом теперь держит общий проход `holders`, а новый тест держит
таблицу: каждый член строки объявлен в коде раздела, на который строка
ссылается; члены `MyJob` — ровно члены `MyJob` этого файла без `_stop` правила,
`MyQueue` — ровно его `MyQueue`, у `MyContext` нет ни одного, как
в `extending_plain.dart`. Шесть мутаций таблицы исполнитель уронил; одна дыра
названа: `finished()`, перенесённый в строку «A job of your own», тест
пропустит — он объявлен и там.

### `groups.md`

Ссылка из «When one failure makes the rest pointless» на «Finishing a job by
hand» ушла, правило осталось своей фразой: «The group then goes by that failure
and not by the branch's `Done`.» Таблица стадий и два абзаца под ней переехали
в конец «Branches that wait for each other» подразделом «The two barriers».
Фраза «Branches that wait for each other shows how» внутри самого раздела стала
«as the lock of The first attempt above does». Ссылка из «What `runAll` does
not promise» ведёт теперь на «The two barriers»: прежняя была верна, новая
точнее называет то, о чём фраза. Dartdoc `runAll` не тронут: его первая
ссылка — на таблицу форм, она осталась на месте, вторая — на зависание.

Порядок разделов до: «Waiting for several children» (…, «When one failure makes
the rest pointless»: формы, таблица форм, абзацы о закрытии, таблица стадий
и два абзаца), «Branches that wait for each other» («The first attempt», «The
lock in a child of the branch»). После: таблица стадий и два абзаца — третьим
подразделом «Branches that wait for each other», после «The lock in a child of
the branch».

### `cleanup.md`

Вход «Callback | When it runs» в две строки стал «What the job holds | Member
| When it runs» в пять: `dispose` и `discard` вызова, `ctx.onDispose`,
`ctx.onDiscard`, `ctx.disown`. Строки сверены с dartdoc `abandonable`, `join`,
`run`, `onDispose`, `onDiscard` и `disown` в `job_context.dart`. Сверх задания
абзац под таблицей сжат до фразы об `ArgumentError`: остальное говорит таблица,
а об `onDispose` и `onDiscard` — ещё и «Registering without a call».

### Проверки части 4

`async_job`: формат без изменений, анализ чистый, +1789. `solo` +2063.
Документные: `reflow.py --check`, `check_line_width.py`, `check_links.py`,
`check_translations.py`, `check_doc_shape.py`, `check_page_code.py`,
`build_site_test.py` — зелёные. Линтер `humanizer--ru` по изменённым абзацам
перевода: 0 `ERROR`.

## Счётчик строк `///`

Строки `///` над объявлением члена, через аннотации и обычные комментарии.

```python
"""Counts the `///` lines above each member of the form wave.

Usage: python3 doc_lines.py <repo root>
"""
import re
import sys

ROOT = sys.argv[1]
AJ = 'packages/async_job/lib/src/'
SO = 'packages/solo/lib/src/'
FS = 'packages/flutter_solo/lib/src/'

MEMBERS = [
    ('JobContext.runAll', AJ + 'job_context.dart', r'^  Future<List<T>> runAll<T>\(Iterable<ChildJob<T>> children\);'),
    ('JobContext.unattended', AJ + 'job_context.dart', r'^  void unattended\(FutureOr<void> Function\(\) action\);'),
    ('JobContext.uncancellable', AJ + 'job_context.dart', r'^  Future<T> uncancellable<T>\('),
    ('JobContext.run', AJ + 'job_context.dart', r'^  Future<T> run<T>\(\s*$'),
    ('JobContext.abandonable', AJ + 'job_context.dart', r'^  Future<T> abandonable<T>\('),
    ('JobContext.join', AJ + 'job_context.dart', r'^  Future<T> join<T>\('),
    ('Job.new', AJ + 'job.dart', r'^  factory Job\('),
    ('Job.ignoreFailure', AJ + 'job.dart', r'^  void ignoreFailure\(\);'),
    ('Job.visitErrors', AJ + 'job.dart', r'^  static void visitErrors\('),
    ('Job.each', AJ + 'job.dart', r'^  static Job<void> each<'),
    ('Job.then', AJ + 'job.dart', r'^  Job<R> then<R>\('),
    ('JobObserver.onError', AJ + 'observer.dart', r'^  void onError\('),
    ('JobAnswerer.onUnanswered', AJ + 'observer.dart', r'^  void onUnanswered\('),
    ('Solo.job', SO + 'solo.dart', r'^  SoloJob<T> job<W extends S, T>\('),
    ('Solo.run', SO + 'solo.dart', r'^  SoloJob<T> run<W extends S, T>\('),
    ('Solo.onUnanswered', SO + 'solo.dart', r'^  void onUnanswered\(Job<Object\?> job, Object error, StackTrace stackTrace\) \{'),
    ('SoloSelection', FS + 'solo_selection.dart', r'^(final |abstract |base |sealed )*(class|mixin) SoloSelection\b'),
    ('SoloListenable', FS + 'solo_listenable.dart', r'^(base )?mixin SoloListenable\b'),
    ('SoloSelector', FS + 'solo_selector.dart', r'^(final |abstract )*class SoloSelector\b'),
]


def count(path, pattern):
    lines = open(ROOT + '/' + path).read().split('\n')
    rx = re.compile(pattern)
    hits = [i for i, line in enumerate(lines) if rx.search(line)]
    counts = []
    for hit in hits:
        i = hit - 1
        n = 0
        while i >= 0:
            s = lines[i].strip()
            if s.startswith('///'):
                n += 1
            elif s.startswith('@') or s.startswith('//'):
                pass
            else:
                break
            i -= 1
        if n:
            counts.append(n)
    if len(counts) != 1:
        return f'{len(hits)} hits, documented {counts}'
    return counts[0]


total = 0
for name, path, pattern in MEMBERS:
    n = count(path, pattern)
    print(f'{name}\t{n}')
    if isinstance(n, int):
        total += n
print(f'total\t{total}')
```
