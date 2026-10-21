> **Состояние на 2026-10-22:** волна сделана и смержена в `main`: части 1–5,
> переезды разбора из dartdoc на страницы, ревью сделанного и его правки
> (раздел «Ревью сделанного»), закрытие находок в записях ревью.
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

## Часть 5. Страницы `solo` и `flutter_solo`

Две половины, у каждой свой исполнитель на Opus в своей копии: входы и основной
путь — `state.md`, `accumulation.md`, `jobs.md`, `errors.md`; длинные фразы
и «Notes» — `children.md`, `vs-bloc.md`, `camera.md`, `streams.md` и README
`flutter_solo`. Файлы не пересекаются. Дифф обеих я прочёл целиком: факты новых
таблиц сверены со страницами, разрезанные фразы по словам — со старыми.

### Входы

- `state.md`: перед `## State and rules` — таблица «Rule | When it is asked |
  What a refusal does» по строке на `W`, `canStart` и `keepWhile` и абзац под
  ней: отказ не держит задачу в очереди, её `ifFailed` и `ifCancelled` после
  него не выполняются, и ссылки на «The rules», «Reading and updating state»
  и «Handler eligibility and errors». Столбец «когда» — столбец таблицы «The
  rules», «что делает отказ» — абзац под ней, обработчики — строки таблицы
  «Handler eligibility and errors».
- `accumulation.md`: перед `## Recipes` — таблица «The controller needs |
  Read»: рецепты одной строкой со ссылкой на их таблицу, по строке на три
  раздела «Reference».
- `errors.md` и `testing.md` — входы прежние.

Ни один тест входные таблицы не держит.

### Основной путь первым

Абзацы переставлены целиком, без правки слов и без связок; скрипт перестановки
сверял, что набор абзацев не изменился. Изменены пять разделов:

- `jobs.md`, «Queue and policies»: абзац о `restart` — перед двумя абзацами
  об ограничениях `droppable`;
- `state.md`, «externalSetState»: «Use job bodies and their state handlers…» —
  после «An event being delivered…», перед абзацами о гонке с закрытием;
- `accumulation.md`, «Start, cancellation and errors»: «Additions to one group
  share…» и «For the same reason…» — первыми, парой;
- `errors.md`, «Reporting an error»: «The hook reports and returns…» — перед
  «It hears each error once…»;
- `errors.md`, «Retrying from the caller»: «The gap itself…» — в конец.

Остальные разделы, открытые ответом, и подразделы ответов на пяти страницах уже
идут основным путём и не тронуты; порядок абзацев каждого записан в заметках
исполнителя. Две оговорки. В «Observing state» `state.md` абзацы основного пути
«Like `ChangeNotifier`…» и «`SoloListenable` adds…» стоят после четырёх абзацев
о вложенной записи, но поднять их, не правя слов, нельзя: «that order» держится
за список прямо над ним. И несколько абзацев несут основной путь и краевой
случай вместе: развести их — значит резать абзац, а это правка,
не перестановка.

### Длинные фразы

Фразы длиннее 35 слов, счёт скриптом ниже:

| Страница | До | После |
| --- | ---: | ---: |
| `children.md` | 6 | 0 |
| `vs-bloc.md` | 28 | 0 |
| `camera.md` | 6 | 0 |
| `streams.md` | 6 | 0 |
| README `flutter_solo` | 8 | 0 |

Почти везде двоеточие, точка с запятой или тире между двумя самостоятельными
частями стали точкой. Новых связок немного: «That page shows», «They show»,
«The rest covers», «The third is», «Through it,». `vs-bloc.md` не сокращена,
решение 86. Четыре из восьми случаев README — не фразы, а списки: пункты шли
со строчной через `;`, и скрипт читал список одной фразой. Пункты теперь
с заглавной и с точкой, как в списках остальных страниц; слова те же. Две новые
фразы ровно в 35 слов — `streams.md` «That is why waits belong…» и `vs-bloc.md`
«They differ in what each does…» — порога не переходят.

Переводы разрезаны в тех же местах. Попутно поправлен перевод `children.md`,
«Working beside a child»: «каждую запись одной задачи проверяют правила другой»
при оригинале «each job answers to its own rules for every one of them»;
расхождение было и до волны.

### «Notes» README `flutter_solo`

Две таблицы, страница одна (решение 76). Первая — «A failure of | Where it
goes», по строке на маршрут: слушатель контроллера с `SoloListenable` и без
него — со ссылками на «A base class without Flutter» в `doc/mixins.md` и «Where
each error goes» на `errors.md` `solo`; слушатель проекции и её селектор — без
ссылки, их маршрут не говорит ни один раздел. Вторая — прежние пять вопросов;
«Are equal states filtered?» и «Several controllers on one screen?» получили
ссылки на «Selecting one value» и «The controller as a `ValueListenable`»,
остальным трём фактам сослаться некуда. Ни один факт прежних ячеек не выброшен.
Это отступление от варианта Fable в вердикте L13 — «куда идёт ошибка» и «жизнь
контроллера», — как и записано в плане.

### Тесты

Ни одно `_says` не снято и не ослаблено. Везде одна причина: держимая фраза
разрезана, и её кусок начинает свою фразу.

| Тест | Правок |
| --- | ---: |
| `children_rakes_test.dart` | 4 |
| `camera_rakes_test.dart` примера `solo` | 4 |
| `streams_rakes_test.dart` | 4 |
| `vs_bloc_rakes_test.dart` | 7 |
| `tool/doc_snippets.py`, `SAID` | 1 |
| `readme_rakes_test.dart` `flutter_solo` | 12 фраз; тест маршрутов держит пять строк таблицы вместо двух фраз; `Listenable.merge` — вместе со ссылкой |

### Проверки части 5

`solo`: формат без изменений, анализ чистый, +2063; пример +112.
`flutter_solo`: формат без изменений, анализ чистый, +241; пример +6. Стенды
вне репозитория: `bin/v` трёх пакетов без замечаний, все драйверы прошли;
`check_traces.py` — 3 цитаты `vs-bloc.md`, 13 `accumulation.md`, 6 `mixins.md`,
ни одной не напечатанной; `flutter_check` +47. Документные — все семь зелёные.
Линтер `humanizer--ru` по изменённым абзацам переводов: 0 `ERROR`.

### Чего часть 5 не сделала

Правило 4 плана откладывает разбор, который есть только в dartdoc, «в заметки
части 4 или 5»: переезжать на страницы ему полагалось в этих частях. В задания
частей 4 и 5 я переезды не включил, и списки «Ждёт страниц частей 4 и 5» выше
пока не исполнены. Ничего не потеряно — разбор стоит в dartdoc, пока страница
его не скажет. Переезды сделаны следующим шагом, отдельным коммитом, — раздел
«Переезды из dartdoc».

## Переезды из dartdoc

Оба списка «Ждёт страниц частей 4 и 5». Писал исполнитель на Opus в копии
на вершине части 5; дифф я прочёл целиком и сверил утверждения с dartdoc,
из которого они взяты. Dartdoc и код не менялись: разбор остался в dartdoc
коротким, как велит правило 4, а страница теперь его говорит. Каждый факт —
краевой случай, после основного пути своего раздела.

| Член | Что | Где теперь |
| --- | --- | --- |
| `runAll` | список читается один раз копией; пустая группа; ветвь, отменившая родителя до первого `await`; отказ после старта части ветвей | `children.md` ядра, «When `ctx.run` refuses a child» |
| `runAll`, `run` | значения без проверки после конца тела | `children.md` ядра, «When the parent is cancelled» |
| `runAll` | регистрация на прибытии через `ctx.run(locked, discard: ...)`, `discard` без замка | `groups.md`, «The lock in a child of the branch» |
| `unattended` | зона вложенной работы; `abandonable` и `join` после конца тела; опрос `check` | `errors.md` ядра, «Work handed to the job» |
| `uncancellable` | передача с `disown` в одной секции | `cleanup.md`, «Unregistering inside the action» |
| `uncancellable` | позднее приземление при живом ребёнке | `cancellation.md` ядра, «Holding the cancellation back» |
| `abandonable` | тип при `unawaited`; значение вызова, брошенного без отмены; с какого момента значение опоздало | `cleanup.md`, «A value that comes late» |
| `join` | проверка после действия отпускает значение, что бы ни бросила | `cleanup.md`, «Registering on arrival» |
| `ignoreFailure` | не позже `onFinish` | `outcomes.md`, «Telling the core it is handled» |
| `visitErrors` | правила обхода | `errors.md` ядра, «Several failures in one error» |
| `Solo.job` | запись изнутри `keepWhile` | `state.md`, «The rules» |
| `Solo.job` | `cancellable: false` — только у движка; очередная задача, отказавшая `cancel`, доходит до конца | `cancellation.md` `solo`, «A whole job» |
| `Solo.job` | `ifCancelled` по завершении, `onCancel` — сразу | `state.md`, «The handlers» |
| `Solo.job` | правило, бросившее на контрольной точке, и `ifFailed` | строка таблицы «Handler eligibility and errors» |
| `Solo.onUnanswered` | каждая ошибка уже прошла `onError` | `errors.md` `solo`, «Where each error goes» |
| `SoloListenable` | голый — это `SoloListenable<Object>` | README `flutter_solo`, «The controller as a `ValueListenable`» |
| `SoloSelection`, `SoloSelector` | селектор только выбирает; выборка раз на изменение и источник, меняющий значение на месте; без слушателей; выборка переживает источник; чужой `ValueListenable`; виджету не нужен `State` | README `flutter_solo`, «Selecting one value» |

Три места разошлись с названными. На `groups.md` нет ни «When `runAll`
refuses», ни абзаца о допуске: допуск `runAll` разобран на `children.md` ядра,
туда и ушло. «Running a child» ещё не вводит проверку, о которой фраза про
поздний успех, поэтому фраза — в «When the parent is cancelled», где проверка
названа. Чужой `ValueListenable` дописан к абзацу о конструкторе
`SoloSelection`: список правил `SoloSelector` стоит раньше, чем `SoloSelection`
введён.

Уже было на страницах и не добавлялось: `abandonable` без `await` бросает
в зону, пока тело идёт, — `errors.md` ядра; сбой селектора проекции — таблица
«Notes» README; дешёвая выборка с одним ответом — список правил `SoloSelector`.

Одна правка при сверке: исполнитель написал о селекторе проекции «it does not
change the state», dartdoc `SoloSelection` говорит «must not». Это запрет,
а не описание: на странице и в переводе стоит «must not».

Для итога L7: «Finishing a job by hand» называет dartdoc `JobBase.finish` и два
его случая; третий — `Failed`, поданный уже законченной задаче, — есть только
в dartdoc `finish`.

Решения 50, 59, 61 и 64 не менялись; то, на чём они стоят, теперь сказано
и на страницах.

### Проверки переездов

`async_job`: формат без изменений, анализ чистый, +1789. `solo`: формат,
анализ, +2063; пример +112. `flutter_solo`: формат, анализ, +241; пример +6.
Стенды вне репозитория: `bin/v` без замечаний, все драйверы прошли,
`check_traces.py` — ни одной не напечатанной цитаты; `flutter_check` +47.
Документные — все семь зелёные. Линтер `humanizer--ru` по изменённым абзацам
переводов: 0 `ERROR`.

## Ревью сделанного

Независимое ревью на Opus по копии дерева на `b819bf6c`: одна находка Medium,
девять Low. Ревьюер проследил 31 убранный факт, воспроизвёл числа отчёта,
проверил форму всех 19 членов, переводы изменённых абзацев и решения 18, 27,
29, 38, 59 и 100 — там замечаний нет. Каждую находку я перепроверил по дереву
сам; все десять подтвердились. Правки — одним коммитом,
`docs: close the review of the form wave`.

### 1. Medium: блок `commit` + `disown` не дошёл до страниц ядра

Второй блок кода dartdoc `uncancellable` — `transaction.commit()` голым `await`
и `ctx.disown(transaction)` в одной секции — правило 2 из dartdoc убрало,
а ни на одной странице `async_job` его не было: он есть только в `resources.md`
`solo`. Отчёт в «Что ушло и где это сказано» и в таблице переездов называет
`cleanup.md`, «Unregistering inside the action», но там на `b819bf6c` стоял
один абзац прозы без блока.

Вердикт: принять. Блок встаёт на страницу под абзац о передаче, его код —
в `test/support/cleanup_page.dart`, как велит сторож раздела.

Итог: блок стоит в `cleanup.md` под абзацем «An asynchronous hand-over…»
и в переводе. Функция `handingOver` — в `cleanup_page.dart`, заглушка
`Transaction` — в `cleanup_stubs.dart`, два теста в `cleanup_rakes_test.dart`
проверяют, что ни отмена во время `commit`, ни успех переданную транзакцию
не откатывают. Строки отчёта о `cleanup.md` верны с этого коммита,
а на `b819bf6c` были ложны.

### 2. Low: невыровненный перенос в dartdoc `unattended`

Строка кончалась на «instead of handing it over closed. A job», хотя следующее
слово в неё влезало.

Вердикт: принять.

Итог: фразы о задаче, созданной внутри, стали отдельным абзацем dartdoc, оба
абзаца залиты жадно — вместе с находкой 5.

### 3. Low: висячее «instead» и `TimeoutCancelReason` в dartdoc `Solo.job`

«Instead» противопоставляло фразу случаю, который часть 3 вырезала: правилу,
бросившему, пока проверяется право обработчиков. «[ifCancelled] gets a
[TimeoutCancelReason]» неточно: обработчик получает `Cancelled` с такой
причиной.

Вердикт: принять; вернуть противопоставленный случай фразой.

Итог: перед «The same rule throwing at `ctx.state` or `ctx.check()` reaches the
body instead» вернулась фраза «A rule that throws while the permission of the
handlers is checked suppresses the correction, and its error is reported».
О тайм-ауте: «[ifCancelled] gets a [Cancelled] whose reason is a
[TimeoutCancelReason]».

### 4. Low: перечень «What comes:» в `JobAnswerer.onUnanswered` неполон

Из перечня пропали ветвь `runAll`, которую группа не бросила, и сбой при
форматировании описания отмены ребёнка. Оба маршрута живут в «Rare routes»
`errors.md`.

Вердикт: принять; вернуть оба пункта, как в прежнем тексте.

Итог: оба пункта стоят в перечне после работы `unattended`.

### 5. Low: ответ наблюдателя выпал из фразы о задаче внутри `unattended`

«Its unobserved failure lands … in the zone» верно, только пока у задачи нет
ответчика, и пропало «rather than to this job's observer», ради которого фраза
писалась.

Вердикт: принять, в dartdoc и на странице.

Итог: «Its unobserved failure goes to the answer of its own observer, or to
that zone, rather than to the observer of this job» — в dartdoc, в «Work the
job does not wait for» `errors.md` и в переводе.

### 6. Low: двусмысленности после резки длинных фраз в части 5

Два «The rest» подряд в `streams.md`; «it» во фразе «For each update that
subscription brings, it either queues» можно отнести к подписке; «Three
things…» во `vs-bloc.md` перечисляет после двоеточия две вещи, третья вынесена
в новую фразу.

Вердикт: принять все три.

Итог: в `streams.md` — «There you find what …» и «the controller either
queues», сторож `_says` в `streams_rakes_test.dart` поправлен вслед.
Во `vs-bloc.md` три пункта стоят в одной фразе «The application keeps three
things right: …». В переводе `streams.md` «Речь в нём о том» стало «Там
описано»; фраза о подписке не тронута: «он» там по роду относится только
к контроллеру. Перевод `vs-bloc.md` перечисляет три пункта так же. Длинных фраз
на трёх страницах по-прежнему ноль.

### 7. Low: повтор и порядок в разделе выборки README `flutter_solo`

«Nothing has to be disposed of» и «there is nothing to dispose of» стояли
подряд, а краевой случай «With nobody listening» — раньше основного пути «While
somebody listens».

Вердикт: принять.

Итог: из абзаца о `SoloSelector` вывод снят: он там и неточен, проекция
в `State` тоже ничего освобождать не требует. «With nobody listening…» стоит
второй фразой абзаца «While somebody listens…». Перевод так же.

### 8. Low: раздел «The two barriers» открывается прозой, а не таблицей

План велел подраздел, открытый таблицей; раздел открывается вводной фразой
с двоеточием перед таблицей, и отчёт отклонение не назвал.

Вердикт: принять первое предложение — назвать отклонение. Фраза говорит
правило, без которого таблица стадий не читается: ни одна ветвь не проходит
барьер, пока его не достигли все. Раздел по-прежнему открывается ответом, как
велит решение 71.

Итог: отклонение названо здесь и в итоге M3 записи
`2026-10-21-async-job-project-review-3.md`.

### 9. Low: тест таблицы «The whole engine» пропускал три поломки

Код разделов ключевался текстом заголовка, и две «The first attempt»
склеивались; якорь ссылки с её текстом не сверялся; строка `MyContext` без имён
в бэктиках проходила при любом разделе, даже отсутствующем.

Вердикт: принять; ключевать разделы якорем.

Итог: тест ключует код раздела якорем по правилам GitHub (`the-first-attempt`
и `the-first-attempt-1` врозь), требует, чтобы текст ссылки был заголовком её
якоря, и для строки «the constructor alone» ищет конструктор класса в коде
раздела. Три мутации таблицы — ссылка на вторую «The first attempt», чужой
якорь при верном тексте, строка `MyContext` со ссылкой на раздел без
конструктора — тест роняют; файл после каждой восстановлен копией.

### 10. Low: `prose_len.py` падал с `-v`

Скрипт проверял `-v` в `sys.argv`, но шёл по всем аргументам как по путям.

Вердикт: принять.

Итог: цикл по путям пропускает `-v`, Usage флаг называет; текст скрипта
в «Счётчик длинных фраз» поправлен.

### Проверки правок ревью

`async_job`: формат без изменений, анализ чистый, +1791 — на два теста передачи
больше. `solo`: формат, анализ, +2063; пример +112. `flutter_solo`: формат,
анализ, +241; пример +6. Стенды: все драйверы прошли, `check_traces.py` — 3, 13
и 6 цитат, ни одной не напечатанной; `flutter_check` +47. Документные — все
семь зелёные. Линтер `humanizer--ru` по изменённым абзацам переводов: 0
`ERROR`.

## Счётчик длинных фраз

`prose_len.py`, как его гоняли до и после части 5: `python3 prose_len.py
packages/solo/doc/children.md packages/solo/doc/vs-bloc.md
packages/solo/doc/camera.md packages/solo/doc/streams.md
packages/flutter_solo/README.md`.

```python
"""Sentence lengths of the prose of Markdown pages.

Usage: python3 prose_len.py [-v] FILE...

Code blocks, tables, headings, quotes and HTML are left out. A sentence
ends at `.`, `!` or `?` followed by a space or the end of a paragraph; a
dot inside a code span does not end one. Prints, per file: sentences, mean
words, and how many are longer than 35 words.
"""
import re
import sys

LIMIT = 35


def paragraphs(text):
    fence = False
    para = []
    for line in text.split('\n'):
        if line.lstrip().startswith('```'):
            fence = not fence
            if para:
                yield ' '.join(para)
                para = []
            continue
        if fence:
            continue
        s = line.strip()
        if not s or s.startswith(('#', '|', '>', '<')):
            if para:
                yield ' '.join(para)
                para = []
            continue
        s = re.sub(r'^([-*]|\d+\.)\s+', '', s)
        para.append(s)
    if para:
        yield ' '.join(para)


def sentences(para):
    # Code spans and link targets become single words with no dots in them.
    para = re.sub(r'`[^`]*`', 'CODE', para)
    para = re.sub(r'\]\([^)]*\)', ']', para)
    for sentence in re.split(r'(?<=[.!?])\s+(?=[A-Z«"`(\[А-Я])', para):
        words = sentence.split()
        if words:
            yield words


def main():
    for path in [a for a in sys.argv[1:] if a != '-v']:
        lengths = []
        long_ones = []
        for para in paragraphs(open(path).read()):
            for words in sentences(para):
                lengths.append(len(words))
                if len(words) > LIMIT:
                    long_ones.append(' '.join(words[:8]) + ' ...')
        n = len(lengths)
        mean = sum(lengths) / n if n else 0
        print(f'{path}\tsentences {n}\tmean {mean:.1f}\tover {LIMIT}: '
              f'{len(long_ones)} ({100 * len(long_ones) / n if n else 0:.1f}%)')
        if '-v' in sys.argv:
            for line in long_ones:
                print('   ', line)


main()
```

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
