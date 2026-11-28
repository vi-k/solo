> **Состояние на 2026-11-28:** черновик, вне пакетов и вне CI, как и модель,
> которую он продолжает. Модель и настройки записаны здесь целиком.
> **Что это:** накопители в модели очереди `solo` на TLA+ — группы, их
> тайминг, три политики события и таймеры, — прогоны TLC и мутации модели.
> **Связанные записи:** `2026-11-28-solo-queue-tla-draft-report.md`
> (модель без накопителей), `2026-11-25-invariant-checking-plan.md` (три
> ступени).

# Накопители в модели очереди `solo`

Владелец сказал: «добавь в модель накопители». Черновик
`2026-11-28-solo-queue-tla-draft-report.md` кончился тем, что двух побудок
насоса модель не стережёт: без накопителей задача ждёт в очереди, только пока
что-то идёт или насос назначен. Обе побудки нужны ради группы накопителя,
которая ждёт своего окна, а накопителей в модели не было.

Правила взяты из кода 2.1.0: группа и её тайминг —
`packages/solo/lib/src/accumulator.dart`, выбор задачи, снятие и перенос —
`packages/solo/lib/src/queue.dart`, таймеры и закрытие —
`packages/solo/lib/src/solo.dart`. Что обещано пользователю, сверено
со страницей `packages/solo/doc/accumulation-rules.md`.

## Что добавлено в модель

Накопители — `ACCS`. У каждого ядро, ключ, тайминг, политика и `cancellable`;
TLC выбирает их в начальном состоянии из констант `ATIMES`, `APOLS` и `ACNS`
и перебирает все сочетания. Тайминг: `none` — без тайминга или
с `Duration.zero`, `debounce`, `throttle` и `late` — `throttle`
с `startAtOnce: false`. Времени в модели нет: таймер срабатывает, когда TLC
позволит, но никогда внутри прохода насоса — у таймера свой ход цикла событий.

Переходы:

- `add` без группы, к которой можно примкнуть: новая группа встаёт в хвост
  последовательной задачей с ключом накопителя. Debounce заводит таймер, `late`
  на праздном накопителе заводит интервал. Праздный — без своей группы
  в очереди и идущей; группа в окне правил праздности не мешает, как в коде:
  `runsGroupOf` смотрит в `current` и `running`, а задача окна лежит
  в `inTransition`;
- `add` в группу: `adjacent` примыкает только к открытой группе в хвосте
  очереди, `join` и `replace` — к последней открытой группе накопителя.
  `replace` переносит задачу группы в хвост через `_moveToTail`, и перенос
  кандидата пула будит насос так же, как снятие. Debounce отсчитывает паузу
  заново;
- `add` после `close` получает отказанную задачу `Cancelled(closed)`, как
  обычная постановка закрытого контроллера: её покрывает прежний переход;
- таймер debounce запечатывает группу и будит насос;
- конец интервала будит насос, если у ядра есть свободное место и в его очереди
  ждёт группа накопителя;
- `close()` снимает все таймеры, конец осушения — тоже.

Группа готова сразу без тайминга, после паузы у debounce и вне интервала своего
накопителя у throttle. Линия берёт первую готовую задачу в порядке очереди
и перешагивает ждущие группы. Пул берёт первого готового кандидата, а голова
ключа, ждущая окна, остаётся кандидатом и держит задачи своего ключа позади,
как `_ready` в `queue.dart`. Взятая группа запечатывается. Старт
throttle-группы заводит интервал заново, отказ правил старта — нет. Конец
задачи группы и снятие её из очереди отпускают таймер debounce, интервал
throttle остаётся.

Число событий, примкнувших к группам, в инвариантах не ограничено. В живости
его держит `MERGES`: без предела поток событий держит debounce-группу вечно,
и страница это обещает.

Без накопителей модель та же, что прежде: с `ACCS = {}` на двух задачах пула
и без симметрии она дала те же 102 653 состояния, что и модель черновика.

Три прежних правила поменялись:

- `KeyOrder` — теперь только о пуле. Линия перешагивает ждущую группу и задачей
  её же ключа, и страница так и говорит: «The queue takes the first ready job
  in list order, allowing ready jobs to pass waiting groups. In a pool of a
  `SoloLanes` the order of a key holds instead»;
- `NoOvertake` обещает то же, но готова теперь не всякая задача очереди:
  обогнать можно и группу, ждущую окна;
- `DrainNotStuck`: осушение без идущих задач и без назначенного насоса
  допустимо, пока идёт таймер, который вернёт насос, — debounce или интервал
  накопителя, чья группа ждёт в очереди.

## Новые инварианты

| Инвариант | Правило |
|---|---|
| `OpenOnlyQueued` | группа принимает события только в очереди, и только там идёт её таймер debounce |
| `SealedTakesNothing` | к запечатанной группе событие не примыкает |
| `AdjacentTail` | событие `adjacent` примыкает только к группе в хвосте очереди |
| `ThrottleSpacing` | throttle-группа не стартует, пока не кончился интервал прошлого старта |
| `DebounceWaits` | debounce-группа уходит только после паузы после последнего события |
| `TimersDown` | после `close()` и после конца осушения таймеров нет |

Времени нет, поэтому два инварианта держатся на флагах. `ths` говорит, что
интервал, начатый последним стартом группы, ещё идёт; снимает его только
срабатывание таймера, то есть прошедшее время, а не отмена таймера.
Debounce-таймер со значением 2 отсчитывает паузу не от последнего события
группы; в верной модели такого не бывает.

## Прогоны

У всех настроек два ключа, два места в пуле, все четыре политики задач и один
накопитель со всеми таймингами, политиками события и обоими `cancellable`. TLC
2.19 на 14 потоках:

| Настройка | Ядра | Задачи | Проверяет | Различных | Сгенерировано | Глубина | Время |
|---|---|---|---|---|---|---|---|
| `small` | пул | 2 | 22 инварианта | 2 267 016 | 11 433 754 | 19 | 13 с |
| `pool` | пул | 3 | 22 инварианта | 73 775 431 | 523 705 633 | 24 | 24 мин |
| `lane` | линия | 3 | 22 инварианта | 25 980 032 | 192 443 669 | 26 | 13 мин |
| `both` | линия и пул | 2 | 22 инварианта | 16 642 598 | 85 532 794 | 22 | 2 мин |
| `livep` | пул | 2 | `CloseEnds`, `NoStarve` | 12 164 994 | 59 160 730 | 21 | 29 мин |
| `livel` | линия | 2 | `CloseEnds`, `NoStarve` | 6 153 786 | 34 429 608 | 23 | 35 мин |
| `old` | пул, без накопителей | 2 | 22 инварианта | 102 653 | 518 723 | 18 | 1 с |

Все чистые. Накопитель умножает пространство состояний примерно в 80 раз:
`small` черновика прошла 27 499 состояний, а здесь 2 267 016. Больше всего даёт
выбор самого накопителя: в начальном состоянии их 48 различных, и на каждый
приходится меньше двух пространств черновика. Вероятность того, что два разных
состояния `pool` совпали по отпечатку и одно осталось непроверенным, TLC
оценивает в 8,7·10⁻⁴ по настоящим отпечаткам.

Главной настройки черновика — два ядра на трёх задачах — здесь нет.
По отношению `main` к `pool` в черновике она прошла бы около полумиллиарда
состояний, по прикидке часа три; два ядра проверены на двух задачах. Живость
на двух ядрах без симметрии по отношению `livep` к `small` прошла бы около
девяноста миллионов состояний, поэтому она проверена по одному ядру: на пуле
и на линии.

`livel` одним прогоном за 33 минуты прошла только 3,1 млн состояний и всё
медленнее: потоки TLC стояли в очереди на общей таблице графа живости,
и процесс занимал одно ядро. Тайминг накопителя выбирается в начальном
состоянии и дальше не меняется, поэтому четыре прогона, по одному на тайминг,
вместе проходят ровно те же состояния. Они шли параллельно, по три потока;
в таблице их сумма, наибольшая глубина и время самого долгого.

Число состояний под симметрией на 14 потоках чуть плавает, как и в черновике.
`old` гоняется без симметрии, и её число от прогона не зависит.

## Мутации

Каждая мутация ломает одно правило модели, константа `MUT` её включает.
Прогон — `small` на одном потоке: так TLC отдаёт кратчайшую трассу. Две мутации
требуют третьей задачи, и тогда настройка сужена, чтобы один поток прошёл её
быстро: `poolOverfill` гоняется без накопителей, `dropStopsInterval` — с одним
`throttle` и политикой `join`.

Семнадцать прежних мутаций перепрогнаны на модели с накопителями. Пятнадцать
пойманы тем же инвариантом и трассой той же длины, что и в черновике. Две,
которых черновик не ловил, теперь пойманы:

| `MUT` | Что сломано | Ловит | Состояний в трассе |
|---|---|---|---|
| `laneTwo` | линия не бывает полной (на одной линии) | `LaneSerial` | 7 |
| `poolOverfill` | пул полон только сверх `concurrency` (на трёх задачах, без накопителей) | `PoolBound` | 10 |
| `keyNotHeld` | голова ключа готова, даже когда ключ занят | `KeyAlone` | 7 |
| `cancelledFreesKey` | отменённая задача отпускает ключ, ещё не кончившись | `KeyAlone` | 7 |
| `keyStack` | головой ключа считается последняя вставшая задача | `KeyOrder` | 5 |
| `pickLast` | насос берёт последнюю готовую задачу, а не первую | `NoOvertake` | 5 |
| `markIgnored` | принятая отмена не решает исход: тело кончается `Done` | `MarkDecides` | 8 |
| `closeIgnoresRefusal` | `close()` просит отмениться и `cancellable: false` | `RefusalHolds` | 6 |
| `dupQueueOnly` | `droppable` ищет дубликат только в очереди | `DroppableAlone` | 5 |
| `keepSparesQueue` | `keepLatest` и `restart` не снимают очередь ключа | `KeepLatest` | 3 |
| `restartNoCancel` | `restart` не просит отмениться идущую задачу ключа | `RestartCancels` | 6 |
| `closeKeepsQueue` | `close()` снимает окно, а очередь оставляет | `NothingQueuedAfterStop` | 3 |
| `drainEndsEarly` | осушение кончается на пустой очереди линии, пока задача ещё идёт (на одной линии) | `ClosedQuiet` | 7 |
| `drainDropsQueue` | `close(mode: drain)` снимает очередь | `DrainKeeps` | 3 |
| `noPumpOnEnd` | конец тела не будит насос | `NoIdleStall` | 8 |
| `noPumpOnUnlink` | снятие или перенос кандидата пула не будит насос | `NoIdleStall` | 6 |
| `noPumpOnDrainDrop` | задача, кончившаяся вне очереди во время осушения, не будит насос | `DrainNotStuck` | 6 |

Десять новых ломают правила накопителей:

| `MUT` | Что сломано | Ловит | Состояний в трассе |
|---|---|---|---|
| `noSealOnTake` | насос не запечатывает взятую группу | `OpenOnlyQueued` | 4 |
| `joinSealed` | событие ищет группу, не глядя, открыта ли она | `SealedTakesNothing` | 4 |
| `adjacentAsJoin` | `adjacent` ищет группу мимо хвоста, как `join` | `AdjacentTail` | 4 |
| `throttleIgnored` | throttle-группа готова и внутри интервала | `ThrottleSpacing` | 8 |
| `dropStopsInterval` | снятая из очереди throttle-группа останавливает интервал (на трёх задачах, один `throttle`) | `ThrottleSpacing` | 10 |
| `debounceIgnored` | debounce-группа готова, пока таймер идёт | `DebounceWaits` | 4 |
| `noRestart` | событие не отсчитывает паузу debounce заново | `DebounceWaits` | 4 |
| `closeKeepsTimers` | `close()` оставляет таймеры | `TimersDown` | 3 |
| `noPumpOnDebounce` | таймер debounce не будит насос | `NoIdleStall` | 5 |
| `noPumpOnThrottle` | конец интервала не будит насос | `NoIdleStall` | 5 |

Теперь своя мутация есть у каждого инварианта, кроме `OneOutcome`:
`DrainNotStuck` ловит `noPumpOnDrainDrop`. Черновик говорит, что без мутации
остался один `DrainNotStuck`, но своей не было и у `OneOutcome`.

Против живости гоняются `livep.cfg` с `MUT = "<имя>"`, суженной до одного
тайминга и одной политики события. Все четыре побудки насоса, которые нужны
ради ждущей группы, роняют живость:

| `MUT` | Тайминг и политика | Чем кончается трасса | Состояний в трассе |
|---|---|---|---|
| `noPumpOnUnlink` | `debounce`, `replace` | задача ключа вечно ждёт в очереди (`NoStarve`) | 9 |
| `noPumpOnDrainDrop` | `debounce`, `join` | осушение с пустой очередью не кончается (`CloseEnds`) | 9 |
| `noPumpOnDebounce` | `debounce`, `join` | запечатанная группа вечно ждёт в осушении | 8 |
| `noPumpOnThrottle` | `late`, `join` | группа вечно ждёт в осушении после конца интервала | 8 |

TLC не называет нарушенное свойство, и оно прочитано по последнему состоянию
трассы. В двух последних строках падают оба: осушение не кончается, пока группа
ждёт. В черновике `noPumpOnUnlink` и `noPumpOnDrainDrop` живость не роняли.

## Что нашёл TLC

Нового о коде — ничего: на верной модели все 22 инварианта и оба свойства
живости держатся.

Обе побудки насоса, которых черновик не стерёг, модель теперь видит. Без каждой
из них TLC находит застрявшую очередь за шесть состояний, и обе трассы — те
самые сценарии, на которых побудки ловят тесты `solo`:

- `noPumpOnUnlink`: в пуле debounce-группа ключа `k1` ждёт своей паузы, за ней
  обычная задача того же ключа. Проход насоса взять нечего: группа ждёт окна,
  задача — ключа. Событие `replace` переносит группу в хвост, задача становится
  головой свободного ключа, места есть, ничего не идёт — и насос никто
  не будит. Это тест «keys a group of a key moved to the tail lets the next job
  start» в `pool_test.dart`;
- `noPumpOnDrainDrop`: в пуле ждёт паузы debounce-группа, приходит
  `close(mode: drain)`, проход ничего не берёт, затем `cancelAll` снимает
  группу. Очередь пуста, ничего не идёт, таймера нет, насос не назначен —
  осушение не кончится никогда. Это тест «a drain ends when its last waiting
  group is cancelled» в `drain_test.dart`.

При снятии побудок в коде упало по два теста на каждую. Второй тест пары —
тот же сценарий с другим снятием группы: «keys removing a waiting group of a
key lets the next job start» снимает её отменой, «a drain ends when the waiting
group cancels itself» — её собственной отменой. В модели такие трассы той же
длины, и TLC отдал одну из кратчайших.

## Чего модель не видит

- Время. Длительностей нет, и TLC перебирает любой порядок срабатывания
  таймеров, в том числе невозможный: debounce двух групп с одной длительностью
  срабатывает в порядке их последних событий, а в модели — как угодно. Модель
  от этого шире кода, а не уже: ложной тревоги она не дала.
- Значения событий, `seed`, `merge` и `snapshot`, ошибку `merge` и `StateError`
  от `add` изнутри `merge`.
- Подмену `enqueueJob` подклассом `Solo`: группа всегда встаёт в очередь.
- Больше одного накопителя: два не прогонялись.
- Сверку с кодом новых правил. Зондов на накопители нет: правила взяты из кода
  и страницы, и обе побудки, ради которых накопители добавлены, сверены
  с тестами `solo`, упавшими при их снятии в коде.
- Всё, чего не видел черновик, кроме накопителей: дети, `timeout`, ошибки тел,
  порядок микрозадач, больше одной линии и одного пула, третий ключ.
- Размер: инварианты на двух ядрах — только на двух задачах, живость — только
  по одному ядру на двух задачах.

## Вывод

Модель выросла с 431 строки до 642. К 16 инвариантам черновика добавились шесть
о накопителях, три прежних уточнены. Все 22 держатся на пуле и на линии с тремя
задачами и на двух ядрах с двумя, живость держится на каждом ядре.

Нового о коде модель опять не нашла. Зато она теперь видит обе побудки насоса,
которые без накопителей были лишними: без каждой TLC за шесть состояний находит
застрявшую очередь — те же сценарии, на которых побудки ловят тесты `solo`, —
и живость тоже падает. Своя мутация теперь есть у каждого инварианта, кроме
`OneOutcome`.

Цена — размер. Накопитель умножил пространство состояний в 80 раз, и главная
настройка черновика, два ядра на трёх задачах, в минуты больше не помещается.
Правку правил очереди удобно сперва прогнать на `small` за 13 секунд и `both`
за две минуты; `lane` и `pool` идут четверть часа и полчаса.

## Как запустить

TLC 2.19 и Java — те же, что в черновике. Текст модели из последнего раздела
ложится в `SoloQueue.tla`, настройки — рядом в `<имя>.cfg`; из их каталога:

```sh
java -XX:+UseParallelGC -cp tla2tools.jar tlc2.TLC -workers auto -deadlock \
  -metadir ./states -config pool.cfg SoloQueue.tla
```

Настройка `pool.cfg`:

```text
CONSTANTS
  JOBS = {j1, j2, j3}
  KEYS = {k1, k2}
  NOKEY = nokey
  SETUP = "pool"
  PCAP = 2
  POLS = {"seq", "drop", "keep", "restart"}
  ACCS = {a1}
  ATIMES = {"none", "debounce", "throttle", "late"}
  APOLS = {"join", "replace", "adjacent"}
  ACNS = {TRUE, FALSE}
  MERGES = 0
  MUT = "none"
SPECIFICATION Spec
SYMMETRY Sym
INVARIANTS
  OneOutcome LaneSerial PoolBound KeyAlone KeyOrder NoOvertake MarkDecides
  RefusalHolds DroppableAlone KeepLatest RestartCancels
  NothingQueuedAfterStop ClosedQuiet DrainKeeps NoIdleStall DrainNotStuck
  OpenOnlyQueued SealedTakesNothing AdjacentTail ThrottleSpacing
  DebounceWaits TimersDown
VIEW View
```

`small.cfg` отличается строкой `JOBS = {j1, j2}`, `lane.cfg` — строкой
`SETUP = "lane"`, `both.cfg` — обеими: `JOBS = {j1, j2}` и `SETUP = "both"`.
`old.cfg` — `small.cfg` с `ACCS = {}` и без `SYMMETRY`.

Настройка мутации — `small.cfg` с `MUT = "<имя>"`, у `laneTwo`
и `drainEndsEarly` с `SETUP = "lane"`; гоняется она с `-workers 1`.
`poolOverfill` — на `pool.cfg` с `ACCS = {}`, `dropStopsInterval` —
на `pool.cfg` с `ATIMES = {"throttle"}`, `APOLS = {"join"}` и `ACNS = {TRUE}`.

`livep.cfg` проверяет живость без `SYMMETRY`:

```text
CONSTANTS
  JOBS = {j1, j2}
  KEYS = {k1, k2}
  NOKEY = nokey
  SETUP = "pool"
  PCAP = 2
  POLS = {"seq", "drop", "keep", "restart"}
  ACCS = {a1}
  ATIMES = {"none", "debounce", "throttle", "late"}
  APOLS = {"join", "replace", "adjacent"}
  ACNS = {TRUE, FALSE}
  MERGES = 2
  MUT = "none"
SPECIFICATION Spec
PROPERTIES
  CloseEnds NoStarve
VIEW View
```

`livel.cfg` — та же настройка с `SETUP = "lane"`. Гоняется она четырьмя
частями, по одной на тайминг: в копии `livel.cfg` строка `ATIMES` заменена
на `ATIMES = {"none"}`, `{"debounce"}`, `{"throttle"}` или `{"late"}`, и четыре
TLC идут параллельно с `-workers 3`.

## Текст модели

```tla
----------------------------- MODULE SoloQueue -----------------------------
(* The queue of solo 2.1 by its code: a lane and a pool of SoloLanes, the
   four policies, the window of the start rules, the pump, cancelAll, close
   and the drain, and the accumulators: their groups, the three policies of
   an event and the timing that keeps a group waiting for its window. No
   bodies: a running job ends when TLC lets it, and a write of the state may
   cancel it by its keepWhile at any moment. No time: a timer fires when TLC
   lets it.                                                                *)
EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS JOBS, KEYS, NOKEY, SETUP, PCAP, POLS, ACCS, ATIMES, APOLS, ACNS,
          MERGES, MUT

\* The cores in the order of declaration, as the pump walks them.
Order == CASE SETUP = "pool" -> <<"P">>
           [] SETUP = "lane" -> <<"L">>
           [] OTHER -> <<"L", "P">>
Cores == {Order[i] : i \in 1..Len(Order)}
IsPool(c) == c = "P"
Cap(c) == IF IsPool(c) THEN PCAP ELSE 1

VARIABLES
  st,      \* "new", "queued", "window" (rules asked), "running", "done"
  co,      \* the core the job was enqueued in, "none" before
  ky,      \* its key, NOKEY for none
  pl,      \* its policy: "seq", "drop", "keep", "restart"
  cn,      \* cancellable
  pos,     \* its place in the queue of its core
  lo, hi,  \* the places last given to `first: true` and to the tail
  mk,      \* a cancellation the running job took: "no", "request", "rule"
  out,     \* outcome: "none", "done", "cancelled"
  rs,      \* reason of the cancellation
  ac,      \* the accumulator the job is a group of, "none" for a plain job
  af,      \* every accumulator: its core, key, timing, policy, cancellable
  open,    \* the group takes events
  deb,     \* its debounce timer: 0 none, 1 counting from its last event,
           \* 2 counting from an earlier one
  thr,     \* the interval timer of the accumulator runs
  ev,      \* the events joined to groups, counted only when MERGES > 0
  cl,      \* "open", "draining", "cancelling", "closed"
  due,     \* a pump is scheduled
  pass,    \* the cores the running pass has yet to step, the head in its step
  drained, \* cores this pass found drained
  lch,     \* the step of the head core launched a job
  win,     \* the job whose start rules are asked, or "none"
  kob,     \* ghost: a job of a pool was taken while one of its key queued
           \* before it
  fob,     \* ghost: a job was taken while a ready one queued before it
  klb,     \* ghost: a keepLatest or restart job left an older one queued
  rcb,     \* ghost: a restart job left the running job of its key unasked
  stopped, \* ghost: a close that cancels came
  ths,     \* ghost: the interval the last start of a group began is not over
  seb,     \* ghost: an event joined a sealed group
  atb,     \* ghost: an event of `adjacent` joined a group off the tail
  tsb,     \* ghost: a throttle group started in the interval of the last one
  dwb      \* ghost: a debounce group went out before a pause after its last
           \* event

vars == <<st, co, ky, pl, cn, pos, lo, hi, mk, out, rs, ac, af, open, deb,
          thr, ev, cl, due, pass, drained, lch, win, kob, fob, klb, rcb,
          stopped, ths, seb, atb, tsb, dwb>>

\* What no job action touches.
pump == <<cl, pass, drained, lch, win, kob, fob, klb, rcb, stopped>>
jobFix == <<co, ky, pl, cn, pos, lo, hi>>
\* What only an event of an accumulator touches.
grpFix == <<ac, af, ev, seb, atb>>
\* The timers of the accumulators with the ghosts they feed.
tim == <<thr, ths, tsb, dwb>>

-----------------------------------------------------------------------------
Live(j) == st[j] \in {"queued", "window", "running"}
GoingOn(j) == Live(j) /\ mk[j] = "no"
Queued(c) == {j \in JOBS : st[j] = "queued" /\ co[j] = c}
Running(c) == {j \in JOBS : st[j] = "running" /\ co[j] = c}
Busy(c) == {j \in JOBS : st[j] \in {"window", "running"} /\ co[j] = c}
Draining == cl = "draining"
InStep(c) == pass # <<>> /\ Head(pass) = c

\* A key is held by the job of the pool that runs with it or whose rules are
\* asked; a cancelled one that winds down holds it still.
Held(c, k) ==
  \E h \in JOBS : /\ co[h] = c /\ ky[h] = k /\ st[h] \in {"window", "running"}
                  /\ (MUT = "cancelledFreesKey" => mk[h] = "no")

Full(c) ==
  CASE MUT = "poolOverfill" /\ IsPool(c) -> Cardinality(Running(c)) > Cap(c)
    [] MUT = "laneTwo" /\ ~IsPool(c) -> FALSE
    [] OTHER -> Cardinality(Running(c)) >= Cap(c)

\* The head of its key: no job of the key is queued before it.
KeyHead(c, j) ==
  \A y \in Queued(c) : (y # j /\ ky[y] = ky[j]) =>
    IF MUT = "keyStack" THEN pos[y] < pos[j] ELSE pos[y] > pos[j]

\* A group is out of its window when its timing lets it go: at once without
\* one, after the pause of a debounce, outside the interval of a throttle.
GReady(j) ==
  \/ ac[j] = "none"
  \/ CASE af[ac[j]].time = "none" -> TRUE
       [] af[ac[j]].time = "debounce" ->
            deb[j] = 0 \/ MUT = "debounceIgnored"
       [] OTHER -> ~thr[ac[j]] \/ MUT = "throttleIgnored"

\* The candidates of a pool: the head of every free key and every job
\* without a key, a group waiting for its window among them.
Cand(c) ==
  {j \in Queued(c) :
     \/ ky[j] = NOKEY
     \/ KeyHead(c, j) /\ (MUT = "keyNotHeld" \/ ~Held(c, ky[j]))}

\* The jobs the pump may take next: in a lane the first job of the queue out
\* of its window, in a pool every candidate out of its window.
Ready(c) ==
  IF IsPool(c)
  THEN {j \in Cand(c) : GReady(j)}
  ELSE {j \in Queued(c) :
          GReady(j) /\ \A y \in Queued(c) : GReady(y) => pos[y] >= pos[j]}

\* The first of them in the queue.
Pick(c) ==
  IF MUT = "pickLast"
  THEN CHOOSE j \in Ready(c) : \A y \in Ready(c) : pos[j] >= pos[y]
  ELSE CHOOSE j \in Ready(c) : \A y \in Ready(c) : pos[j] <= pos[y]

\* A job that ends off the queue brings the pump back in a drain; so does the
\* removal or the move of a pool's candidate that has a job of its key behind
\* it, made outside the step of that pool.
WakeDrain(D) == D # {} /\ Draining /\ MUT # "noPumpOnDrainDrop"
UnlinkWakes(D) ==
  /\ MUT # "noPumpOnUnlink"
  /\ \E x \in D : /\ st[x] = "queued" /\ IsPool(co[x]) /\ ~InStep(co[x])
                  /\ x \in Cand(co[x]) /\ ky[x] # NOKEY
                  /\ \E y \in Queued(co[x]) : y # x /\ ky[y] = ky[x]

\* The groups of D let go of their events and of their debounce timers.
Released(D) ==
  /\ open' = [y \in JOBS |-> IF y \in D THEN FALSE ELSE open[y]]
  /\ deb' = [y \in JOBS |-> IF y \in D THEN 0 ELSE deb[y]]

\* Dropping a queued group leaves the interval of its accumulator running.
ThrAfterDrop(D) ==
  [a \in ACCS |->
     IF /\ MUT = "dropStopsInterval"
        /\ \E y \in D : ac[y] = a /\ st[y] = "queued"
     THEN FALSE ELSE thr[a]]

\* An accumulator is idle with no group of its own queued or running; one
\* in the window of its rules is neither.
Idle(a) == ~\E y \in JOBS : ac[y] = a /\ st[y] \in {"queued", "running"}

\* The group an event of `a` joins: for `adjacent` the job at the tail of the
\* queue if it is an open group of `a`, for the others the last open group of
\* `a` in the queue. With none the event makes a group of its own.
Joinable(a, y) == ac[y] = a /\ (open[y] \/ MUT = "joinSealed")
Candidates(a) ==
  LET c == af[a].core IN
  IF af[a].pol = "adjacent" /\ MUT # "adjacentAsJoin"
  THEN {y \in Queued(c) :
          Joinable(a, y) /\ \A z \in Queued(c) : pos[z] <= pos[y]}
  ELSE {y \in Queued(c) :
          Joinable(a, y) /\ \A z \in Queued(c) : Joinable(a, z) =>
                                                   pos[z] <= pos[y]}

-----------------------------------------------------------------------------
Init ==
  /\ st = [j \in JOBS |-> "new"]
  /\ co = [j \in JOBS |-> "none"]
  /\ ky = [j \in JOBS |-> NOKEY]
  /\ pl = [j \in JOBS |-> "seq"]
  /\ cn = [j \in JOBS |-> TRUE]
  /\ pos = [j \in JOBS |-> 0]
  /\ lo = 0 /\ hi = 0
  /\ mk = [j \in JOBS |-> "no"]
  /\ out = [j \in JOBS |-> "none"]
  /\ rs = [j \in JOBS |-> "none"]
  /\ ac = [j \in JOBS |-> "none"]
  /\ af \in [ACCS -> [core : Cores, key : KEYS \cup {NOKEY}, time : ATIMES,
                      pol : APOLS, cn : ACNS]]
  /\ open = [j \in JOBS |-> FALSE]
  /\ deb = [j \in JOBS |-> 0]
  /\ thr = [a \in ACCS |-> FALSE]
  /\ ev = 0
  /\ cl = "open" /\ due = FALSE /\ pass = <<>> /\ drained = 0 /\ lch = FALSE
  /\ win = "none"
  /\ kob = FALSE /\ fob = FALSE /\ klb = FALSE /\ rcb = FALSE
  /\ stopped = FALSE
  /\ ths = [a \in ACCS |-> FALSE]
  /\ seb = FALSE /\ atb = FALSE /\ tsb = FALSE /\ dwb = FALSE

\* enqueueJob: refused when closed, a duplicate for `droppable`, otherwise
\* queued; `keepLatest` and `restart` remove the queued jobs of the key, the
\* one in the window included, but not a `cancellable: false` one; `restart`
\* asks the running job of the key to cancel. An event of an accumulator
\* after a close is such a refused job as well.
Enqueue(j) ==
  /\ st[j] = "new"
  /\ \E c \in Cores, k \in KEYS \cup {NOKEY}, p \in POLS, b \in BOOLEAN,
        f \in BOOLEAN :
       /\ p # "seq" => k # NOKEY
       /\ co' = [co EXCEPT ![j] = c]
       /\ ky' = [ky EXCEPT ![j] = k]
       /\ pl' = [pl EXCEPT ![j] = p]
       /\ cn' = [cn EXCEPT ![j] = b]
       /\ LET closed == cl # "open"
              twin(o) == /\ co[o] = c /\ ky[o] = k /\ GoingOn(o)
                         /\ (MUT = "dupQueueOnly" => st[o] = "queued")
              dup == /\ ~closed \/ Draining
                     /\ p = "drop"
                     /\ \E o \in JOBS : twin(o)
          IN IF closed \/ dup
             THEN /\ st' = [st EXCEPT ![j] = "done"]
                  /\ out' = [out EXCEPT ![j] = "cancelled"]
                  /\ rs' = [rs EXCEPT ![j] =
                              IF dup THEN "dup" ELSE "closedEnq"]
                  /\ due' = (due \/ WakeDrain({j}))
                  /\ UNCHANGED <<pos, lo, hi, mk, klb, rcb, open, deb, thr>>
             ELSE
               LET np == IF f THEN lo - 1 ELSE hi + 1
                   Rm == IF /\ p \in {"keep", "restart"}
                            /\ MUT # "keepSparesQueue"
                         THEN {y \in JOBS \ {j} :
                                 /\ co[y] = c /\ ky[y] = k /\ cn[y]
                                 /\ st[y] \in {"queued", "window"}}
                         ELSE {}
                   Tg == IF p = "restart" /\ MUT # "restartNoCancel"
                         THEN {h \in Running(c) :
                                 ky[h] = k /\ cn[h] /\ mk[h] = "no"}
                         ELSE {}
               IN /\ st' = [y \in JOBS |->
                              IF y = j THEN "queued"
                              ELSE IF y \in Rm THEN "done" ELSE st[y]]
                  /\ pos' = [pos EXCEPT ![j] = np]
                  /\ lo' = IF f THEN np ELSE lo
                  /\ hi' = IF f THEN hi ELSE np
                  /\ out' = [y \in JOBS |->
                               IF y \in Rm THEN "cancelled" ELSE out[y]]
                  /\ rs' = [y \in JOBS |->
                              IF y \in Rm \cup Tg THEN "replaced" ELSE rs[y]]
                  /\ mk' = [y \in JOBS |->
                              IF y \in Tg THEN "request" ELSE mk[y]]
                  /\ due' = TRUE
                  /\ Released(Rm)
                  /\ thr' = ThrAfterDrop(Rm)
                  \* Checked here: a job queued later comes after this one.
                  /\ klb' = (klb \/ /\ p \in {"keep", "restart"}
                                    /\ \E y \in JOBS \ {j} :
                                         /\ st'[y] \in {"queued", "window"}
                                         /\ co[y] = c /\ ky[y] = k /\ cn[y])
                  /\ rcb' = (rcb \/ /\ p = "restart"
                                    /\ \E h \in Running(c) :
                                         ky[h] = k /\ cn[h] /\ mk'[h] = "no")
  /\ UNCHANGED <<grpFix, cl, pass, drained, lch, win, kob, fob, stopped, ths,
                 tsb, dwb>>

\* add() of an accumulator with no group to join: a new group goes to the
\* tail as a sequential job of the accumulator's key; a debounce starts its
\* timer, and a throttle with `startAtOnce: false` starts the interval when
\* the accumulator is idle and none runs.
AddNew(j, a) ==
  /\ st[j] = "new" /\ cl = "open"
  /\ Candidates(a) = {}
  /\ LET f == af[a] IN
       /\ st' = [st EXCEPT ![j] = "queued"]
       /\ co' = [co EXCEPT ![j] = f.core]
       /\ ky' = [ky EXCEPT ![j] = f.key]
       /\ cn' = [cn EXCEPT ![j] = f.cn]
       /\ pos' = [pos EXCEPT ![j] = hi + 1]
       /\ hi' = hi + 1
       /\ ac' = [ac EXCEPT ![j] = a]
       /\ open' = [open EXCEPT ![j] = TRUE]
       /\ deb' = [deb EXCEPT ![j] = IF f.time = "debounce" THEN 1 ELSE 0]
       /\ thr' = IF f.time = "late" /\ Idle(a)
                 THEN [thr EXCEPT ![a] = TRUE] ELSE thr
  /\ due' = TRUE
  /\ UNCHANGED <<pl, lo, mk, out, rs, af, ev, seb, atb, pump, ths, tsb, dwb>>

\* add() that joins a group: the group keeps its job, `replace` moves it to
\* the tail, and a debounce counts its pause again from this event.
Merge(a) ==
  /\ cl = "open"
  /\ (MERGES = 0 \/ ev < MERGES)
  /\ Candidates(a) # {}
  /\ LET x == CHOOSE y \in Candidates(a) : TRUE
         f == af[a]
     IN /\ seb' = (seb \/ ~open[x])
        /\ atb' = (atb \/ /\ f.pol = "adjacent"
                          /\ \E z \in Queued(f.core) : pos[z] > pos[x])
        /\ IF f.pol = "replace"
           THEN /\ pos' = [pos EXCEPT ![x] = hi + 1]
                /\ hi' = hi + 1
                /\ due' = (due \/ UnlinkWakes({x}))
           ELSE UNCHANGED <<pos, hi, due>>
        /\ deb' = IF f.time = "debounce" /\ open[x]
                  THEN [deb EXCEPT ![x] =
                          IF MUT = "noRestart" /\ deb[x] # 0 THEN 2 ELSE 1]
                  ELSE deb
  /\ ev' = IF MERGES = 0 THEN ev ELSE ev + 1
  /\ UNCHANGED <<st, co, ky, pl, cn, lo, mk, out, rs, ac, af, open, thr,
                 pump, ths, tsb, dwb>>

\* cancel() of one job: a queued one, or the one in the window, ends; a
\* running one takes it; `cancellable: false` refuses either way.
CancelJob(j) ==
  /\ cn[j]
  /\ \/ /\ st[j] \in {"queued", "window"}
        /\ st' = [st EXCEPT ![j] = "done"]
        /\ out' = [out EXCEPT ![j] = "cancelled"]
        /\ rs' = [rs EXCEPT ![j] = "manual"]
        /\ due' = (due \/ WakeDrain({j}) \/ UnlinkWakes({j}))
        /\ Released({j})
        /\ thr' = ThrAfterDrop({j})
        /\ UNCHANGED mk
     \/ /\ st[j] = "running" /\ mk[j] = "no"
        /\ mk' = [mk EXCEPT ![j] = "request"]
        /\ rs' = [rs EXCEPT ![j] = "manual"]
        /\ UNCHANGED <<st, out, due, open, deb, thr>>
  /\ UNCHANGED <<jobFix, grpFix, pump, ths, tsb, dwb>>

\* A write of the state, by another job or by externalSetState, whose
\* keepWhile this running job refuses: the rules go past `cancellable: false`.
RuleCancel(j) ==
  /\ st[j] = "running" /\ mk[j] = "no"
  /\ mk' = [mk EXCEPT ![j] = "rule"]
  /\ rs' = [rs EXCEPT ![j] = "keep"]
  /\ UNCHANGED <<st, out, due, jobFix, grpFix, open, deb, tim, pump>>

\* cancelAll: every queue with the window, then every running job.
CancelAll ==
  \E force \in BOOLEAN :
    LET D == {y \in JOBS : st[y] \in {"queued", "window"} /\ (force \/ cn[y])}
        R == {y \in JOBS : st[y] = "running" /\ cn[y] /\ mk[y] = "no"}
    IN /\ D \cup R # {}
       /\ st' = [y \in JOBS |-> IF y \in D THEN "done" ELSE st[y]]
       /\ out' = [y \in JOBS |-> IF y \in D THEN "cancelled" ELSE out[y]]
       /\ rs' = [y \in JOBS |-> IF y \in D \cup R THEN "manual" ELSE rs[y]]
       /\ mk' = [y \in JOBS |-> IF y \in R THEN "request" ELSE mk[y]]
       /\ due' = (due \/ WakeDrain(D) \/ UnlinkWakes(D))
       /\ Released(D)
       /\ thr' = ThrAfterDrop(D)
       /\ UNCHANGED <<jobFix, grpFix, pump, ths, tsb, dwb>>

\* close() and close() over a drain: every timer goes down, the window and
\* every queue are dropped without asking, every running job is asked; a
\* refusing one is waited for.
StopWork ==
  LET D == {y \in JOBS : st[y] \in {"queued", "window"}
                         /\ (MUT = "closeKeepsQueue" => st[y] = "window")}
      R == {y \in JOBS : st[y] = "running" /\ mk[y] = "no"
                         /\ (cn[y] \/ MUT = "closeIgnoresRefusal")}
      keep == MUT = "closeKeepsTimers"
  IN /\ st' = [y \in JOBS |-> IF y \in D THEN "done" ELSE st[y]]
     /\ out' = [y \in JOBS |-> IF y \in D THEN "cancelled" ELSE out[y]]
     /\ rs' = [y \in JOBS |-> IF y \in D \cup R THEN "closed" ELSE rs[y]]
     /\ mk' = [y \in JOBS |-> IF y \in R THEN "request" ELSE mk[y]]
     /\ open' = [y \in JOBS |-> IF y \in D THEN FALSE ELSE open[y]]
     /\ deb' = [y \in JOBS |-> IF keep /\ y \notin D THEN deb[y] ELSE 0]
     /\ thr' = IF keep THEN thr ELSE [a \in ACCS |-> FALSE]
     /\ ths' = IF keep THEN ths ELSE [a \in ACCS |-> FALSE]
     /\ cl' = "cancelling"
     /\ stopped' = TRUE
     /\ UNCHANGED <<jobFix, grpFix, due, pass, drained, lch, win, kob, fob,
                    klb, rcb, tsb, dwb>>

\* close(mode: drain): no new root job, the queues run, the pump is due.
Drain ==
  /\ cl = "open"
  /\ cl' = "draining"
  /\ due' = TRUE
  /\ IF MUT = "drainDropsQueue"
     THEN LET D == {y \in JOBS : st[y] = "queued"}
          IN /\ st' = [y \in JOBS |-> IF y \in D THEN "done" ELSE st[y]]
             /\ out' = [y \in JOBS |-> IF y \in D THEN "cancelled" ELSE out[y]]
             /\ rs' = [y \in JOBS |-> IF y \in D THEN "closed" ELSE rs[y]]
             /\ Released(D)
     ELSE UNCHANGED <<st, out, rs, open, deb>>
  /\ UNCHANGED <<jobFix, grpFix, mk, tim, pass, drained, lch, win, kob, fob,
                 klb, rcb, stopped>>

Close == Drain \/ (cl \in {"open", "draining"} /\ StopWork)

-----------------------------------------------------------------------------
\* The timers fire in their own turn of the event loop, never in a pass.
\* The debounce timer seals its group and brings the pump back.
DebounceFires(j) ==
  /\ deb[j] # 0 /\ pass = <<>>
  /\ deb' = [deb EXCEPT ![j] = 0]
  /\ open' = [open EXCEPT ![j] = FALSE]
  /\ dwb' = (dwb \/ deb[j] = 2)
  /\ due' = IF MUT = "noPumpOnDebounce" THEN due ELSE TRUE
  /\ UNCHANGED <<st, jobFix, mk, out, rs, grpFix, thr, ths, tsb, pump>>

\* The interval ends; the pump comes back if the core has a free place and
\* a group of the accumulator waits in its queue.
ThrottleFires(a) ==
  /\ thr[a] /\ pass = <<>>
  /\ thr' = [thr EXCEPT ![a] = FALSE]
  /\ ths' = [ths EXCEPT ![a] = FALSE]
  /\ due' = (due \/ /\ MUT # "noPumpOnThrottle"
                    /\ ~Full(af[a].core)
                    /\ \E y \in JOBS : ac[y] = a /\ st[y] = "queued")
  /\ UNCHANGED <<st, jobFix, mk, out, rs, grpFix, open, deb, tsb, dwb, pump>>

-----------------------------------------------------------------------------
\* The pump: a microtask, one pass over the cores in their order.
PassStart ==
  /\ due /\ pass = <<>>
  /\ due' = FALSE /\ pass' = Order /\ drained' = 0 /\ lch' = FALSE
  /\ UNCHANGED <<st, jobFix, mk, out, rs, grpFix, open, deb, tim, cl, win,
                 kob, fob, klb, rcb, stopped>>

\* The step of the head core is over: on to the next core; the pass that found
\* every core drained ends the drain and takes the timers left down.
Advance(d) ==
  LET ends == Tail(pass) = <<>> /\ Draining /\ drained + d = Len(Order)
  IN /\ pass' = Tail(pass)
     /\ drained' = drained + d
     /\ lch' = FALSE
     /\ cl' = IF ends THEN "closed" ELSE cl
     /\ thr' = IF ends THEN [a \in ACCS |-> FALSE] ELSE thr
     /\ ths' = IF ends THEN [a \in ACCS |-> FALSE] ELSE ths

\* One move of the step of the head core: stop on a close that cancels, end
\* the step on a full core or an empty choice, or take the next job into the
\* window of its rules, sealing it if it is a group.
Step ==
  /\ pass # <<>> /\ win = "none"
  /\ LET c == Head(pass) IN
     CASE cl \in {"cancelling", "closed"} ->
            /\ pass' = <<>>
            /\ UNCHANGED <<st, drained, lch, cl, win, kob, fob, open, deb,
                           tim>>
       [] Full(c) ->
            /\ Advance(IF MUT = "drainEndsEarly" /\ ~IsPool(c) /\ Draining
                          /\ Queued(c) = {} THEN 1 ELSE 0)
            /\ UNCHANGED <<st, win, kob, fob, open, deb, tsb, dwb>>
       [] Ready(c) # {} ->
            LET x == Pick(c)
                seal == MUT # "noSealOnTake"
            IN
              /\ st' = [st EXCEPT ![x] = "window"]
              /\ win' = x
              /\ open' = [open EXCEPT ![x] = IF seal THEN FALSE ELSE open[x]]
              /\ deb' = [deb EXCEPT ![x] = IF seal THEN 0 ELSE deb[x]]
              /\ dwb' = (dwb \/ deb[x] # 0)
              /\ kob' = (kob \/ \E y \in Queued(c) :
                           /\ IsPool(c) /\ y # x /\ ky[x] # NOKEY
                           /\ ky[y] = ky[x] /\ pos[y] < pos[x])
              /\ fob' = (fob \/ \E y \in Ready(c) : pos[y] < pos[x])
              /\ UNCHANGED <<pass, drained, lch, cl, thr, ths, tsb>>
       [] OTHER ->
            /\ Advance(IF /\ Draining /\ Queued(c) = {}
                          /\ (IsPool(c) => ~lch /\ Running(c) = {})
                       THEN 1 ELSE 0)
            /\ UNCHANGED <<st, win, kob, fob, open, deb, tsb, dwb>>
  /\ UNCHANGED <<jobFix, mk, out, rs, grpFix, due, klb, rcb, stopped>>

\* The rules of the job in the window answer: it starts, or it is turned down.
\* The start of a throttle group begins the interval of its accumulator
\* again; a refusal begins none.
Decide ==
  /\ win # "none" /\ st[win] = "window"
  /\ LET a == ac[win] IN
     \/ /\ st' = [st EXCEPT ![win] = "running"]
        /\ lch' = TRUE
        /\ IF a # "none" /\ af[a].time \in {"throttle", "late"}
           THEN /\ thr' = [thr EXCEPT ![a] = TRUE]
                /\ ths' = [ths EXCEPT ![a] = TRUE]
                /\ tsb' = (tsb \/ ths[a])
           ELSE UNCHANGED <<thr, ths, tsb>>
        /\ UNCHANGED <<out, rs, due, open, deb>>
     \/ /\ st' = [st EXCEPT ![win] = "done"]
        /\ out' = [out EXCEPT ![win] = "cancelled"]
        /\ rs' = [rs EXCEPT ![win] = "rules"]
        /\ due' = (due \/ WakeDrain({win}))
        /\ Released({win})
        /\ UNCHANGED <<lch, thr, ths, tsb>>
  /\ win' = "none"
  /\ UNCHANGED <<jobFix, mk, grpFix, cl, pass, drained, kob, fob, klb, rcb,
                 stopped, dwb>>

\* The rules ended their own job, by a cancel, cancelAll or close made from
\* in there: the step goes on without launching it.
WindowEnded ==
  /\ win # "none" /\ st[win] = "done"
  /\ win' = "none"
  /\ UNCHANGED <<st, jobFix, mk, out, rs, grpFix, open, deb, tim, cl, due,
                 pass, drained, lch, kob, fob, klb, rcb, stopped>>

\* A running job ends, never in the synchronous code of a pass; a taken
\* cancellation decides its outcome. Its end brings the pump back.
BodyEnd(j) ==
  /\ st[j] = "running" /\ pass = <<>>
  /\ st' = [st EXCEPT ![j] = "done"]
  /\ out' = [out EXCEPT ![j] =
               IF mk[j] # "no" /\ MUT # "markIgnored"
               THEN "cancelled" ELSE "done"]
  /\ due' = IF MUT = "noPumpOnEnd" THEN due ELSE TRUE
  /\ Released({j})
  /\ UNCHANGED <<jobFix, mk, rs, grpFix, tim, pump>>

\* A close that cancels finishes once the last running job is over.
FinishClose ==
  /\ cl = "cancelling" /\ pass = <<>>
  /\ \A j \in JOBS : st[j] # "running"
  /\ cl' = "closed"
  /\ UNCHANGED <<st, jobFix, mk, out, rs, grpFix, open, deb, tim, due, pass,
                 drained, lch, win, kob, fob, klb, rcb, stopped>>

Next ==
  \/ \E j \in JOBS : Enqueue(j) \/ CancelJob(j) \/ RuleCancel(j) \/ BodyEnd(j)
                     \/ DebounceFires(j)
  \/ \E j \in JOBS, a \in ACCS : AddNew(j, a)
  \/ \E a \in ACCS : Merge(a) \/ ThrottleFires(a)
  \/ CancelAll \/ Close
  \/ PassStart \/ Step \/ Decide \/ WindowEnded \/ FinishClose

Fair ==
  /\ WF_vars(PassStart) /\ WF_vars(Step) /\ WF_vars(Decide)
  /\ WF_vars(WindowEnded) /\ WF_vars(FinishClose)
  /\ \A j \in JOBS : WF_vars(BodyEnd(j)) /\ WF_vars(DebounceFires(j))
  /\ \A a \in ACCS : WF_vars(ThrottleFires(a))

Spec == Init /\ [][Next]_vars /\ Fair

-----------------------------------------------------------------------------
\* Every job has an outcome once it is over, and only then.
OneOutcome == \A j \in JOBS : (st[j] = "done") <=> (out[j] # "none")

\* Invariant 1: a lane runs one root job at a time, the window included.
LaneSerial ==
  \A c \in Cores : ~IsPool(c) => Cardinality(Busy(c)) <= 1

\* A pool runs no more than `concurrency` root jobs, the window included.
PoolBound ==
  \A c \in Cores : IsPool(c) => Cardinality(Busy(c)) <= Cap(c)

\* Two jobs of one key never run together in a pool.
KeyAlone ==
  \A c \in Cores, k \in KEYS :
    IsPool(c) => Cardinality({j \in Busy(c) : ky[j] = k}) <= 1

\* The order of a key in a pool is strict: no job starts while one of its
\* key queued before it waits, a group waiting for its window included.
KeyOrder == ~kob

\* Only a job that waits for its key or its window is overtaken: none starts
\* while a ready one queued before it.
NoOvertake == ~fob

\* Invariant 3: a job that took a cancellation ends Cancelled.
MarkDecides ==
  \A j \in JOBS : st[j] = "done" /\ mk[j] # "no" => out[j] = "cancelled"

\* `cancellable: false` refuses every cancellation but that of the rules.
RefusalHolds ==
  \A j \in JOBS : ~cn[j] => mk[j] \in {"no", "rule"}

\* `droppable` hands back the live job of the key, so two droppable jobs of
\* one key never go on in one core together.
DroppableAlone ==
  \A c \in Cores, k \in KEYS :
    Cardinality({j \in JOBS : co[j] = c /\ ky[j] = k /\ pl[j] = "drop"
                              /\ GoingOn(j)}) <= 1

\* After a `keepLatest` or `restart` job was queued, no cancellable job of its
\* key queued before it still waits.
KeepLatest == ~klb

\* A cancellable job of the key that ran when a `restart` job was queued has
\* been asked to cancel.
RestartCancels == ~rcb

\* After a close that cancels nothing waits in a queue or a window.
NothingQueuedAfterStop ==
  cl \in {"cancelling", "closed"} =>
    \A j \in JOBS : st[j] \notin {"queued", "window"}

\* Invariant 7: a closed controller has nothing left.
ClosedQuiet == cl = "closed" => \A j \in JOBS : st[j] \in {"new", "done"}

\* A drain drops nothing it accepted: only a close that cancels drops.
DrainKeeps == ~stopped => \A j \in JOBS : rs[j] # "closed"

\* Whenever nothing runs synchronously and no pump is due, no core has a free
\* place and a ready job: the queue does not stand still.
NoIdleStall ==
  (pass = <<>> /\ ~due /\ cl \in {"open", "draining"}) =>
    \A c \in Cores : Full(c) \/ Ready(c) = {}

\* A drain with nothing running, no pump due and no timer that brings the
\* pump back would never end.
DrainNotStuck ==
  (pass = <<>> /\ ~due /\ Draining) =>
    \/ \E j \in JOBS : st[j] = "running" \/ deb[j] # 0
    \/ \E a \in ACCS : thr[a] /\ \E j \in JOBS : ac[j] = a /\ st[j] = "queued"

\* A group takes events only in the queue, and only there its debounce timer
\* runs: the pump seals the group it takes.
OpenOnlyQueued ==
  \A j \in JOBS : /\ open[j] => st[j] = "queued"
                  /\ deb[j] # 0 => open[j]

\* No event joins a sealed group.
SealedTakesNothing == ~seb

\* An event of `adjacent` joins only the group at the tail of the queue.
AdjacentTail == ~atb

\* No group of a throttle starts within the interval of the last start.
ThrottleSpacing == ~tsb

\* A debounce group goes out only after a pause after its last event.
DebounceWaits == ~dwb

\* A close that cancels takes every timer down, and so does the end of a
\* drain.
TimersDown ==
  cl \in {"cancelling", "closed"} =>
    /\ \A j \in JOBS : deb[j] = 0
    /\ \A a \in ACCS : ~thr[a]

\* Liveness: a close ends, and no job waits in a queue for good.
CloseEnds == (cl # "open") ~> (cl = "closed")
NoStarve == \A j \in JOBS : (st[j] = "queued") ~> (st[j] # "queued")

Sym == Permutations(JOBS) \cup Permutations(KEYS) \cup Permutations(ACCS)

\* What TLC tells states apart by. A job that is over matters only by its
\* outcome, whether it took a cancellation and whether a close cancelled it;
\* the places of the live ones only by their order in their core, since a new
\* place is always before or after all of them.
Rank(j) ==
  Cardinality({y \in JOBS : Live(y) /\ co[y] = co[j] /\ pos[y] < pos[j]})
JobView(j) ==
  CASE st[j] = "new" -> <<"new">>
    [] st[j] = "done" -> <<"done", out[j], mk[j] # "no", rs[j] = "closed">>
    [] OTHER -> <<st[j], co[j], ky[j], pl[j], cn[j], Rank(j), mk[j],
                  rs[j] = "closed", ac[j], open[j], deb[j]>>
View == <<[j \in JOBS |-> JobView(j)], af, thr, ev, cl, due, pass, drained,
          lch, win, kob, fob, klb, rcb, stopped, ths, seb, atb, tsb, dwb>>
=============================================================================
```
