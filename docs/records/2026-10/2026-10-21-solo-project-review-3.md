> **Состояние на 2026-10-22:** ревью проведено, находки сведены, вердикты
> записаны. Владелец ответил на все вопросы — раздел «Ответы владельца»
> в конце; волна по вопросу 1 сделана, итоги — в вердиктах, отчёт
> `2026-10-21-sixth-review-wave-report.md`; L4 закрыта решением; M1 и M2
> сделаны, итоги в вердиктах; волна формы (M4, L5, L13) сделана 2026-10-22,
> итоги в вердиктах, отчёт `2026-10-21-form-wave-report.md`; M3 владелец
> пересмотрел 2026-10-22, она сделана переименованием, отчёт
> `2026-10-22-enqueue-rename-report.md`.
> **Что это:** шестое полное ревью `solo` и `flutter_solo`, на подготовленном
> выпуске 0.3.0, двумя ревьюерами Claude — Opus 5.5 и Fable 5.1: оценка
> из десяти, ответ на вопрос «что сделать, чтобы поставить 10», оценка
> читаемости каждой страницы. После сведения дубликатов 18 находок: 0 High,
> 4 Medium, 14 Low.
> **Связанные записи:** `2026-10-21-async-job-project-review-3.md` (то же
> ревью ядра), `2026-10-21-solo-project-review-2.md` (пятое ревью, Codex),
> `2026-10-21-solo-project-review.md` (четвёртое, Opus, там прежние оценки
> Opus), `2026-10-20-solo-project-review.md` (третье, там прежние оценки
> Fable).

# Шестое полное ревью `solo` и `flutter_solo`: Opus и Fable

## Как это делалось

По слову владельца 2026-10-21 «давай полное ревью на Opus и Fable». Дерево
на `3dd09e42`, клоны `.artifacts/2026-10-21-full-review-3/solo-<ревьюер>/tree`;
задание и базовая линия — те же, что у ревью ядра,
`2026-10-21-async-job-project-review-3.md`.

| Ревьюер | Модель и вызов | Время |
| --- | --- | --- |
| Opus | `claude-opus-5-5`, субагент `general-purpose` | 951 с |
| Fable | `claude-fable-5-1`, так же | 2040 с |

Opus написал зонды в пяти файлах (`probe_review*_test.dart` в `solo`, один
в `flutter_solo`). Fable — пятнадцать зондов (P1–P14, INFER, F1–F4) и десять
мутаций движка и виджетов в копии `/tmp/review3-mut`: все десять пойманы, от 1
до 17 падений на мутацию. `docs/settled.md` прочли оба; handoff и записи
по заданию не читал ни один, отслеживаемых файлов не тронул ни один.

Зонды обоих прогнаны в моей копии на том же коммите
(`.artifacts/2026-10-21-full-review-3/mine/probes/`); всё, что они печатают,
совпало с отчётами. Первая версия зонда Q2 у Opus в клоне не сохранилась, её
текст ошибки сверен с кодом: `cannot $action` в `throwIfFinished` ядра. Сырые
отчёты — `out/solo-opus.md` и `out/solo-fable.md`.

## Оценки

| Ревьюер | Общая | Код | Документация | `solo` | `flutter_solo` |
| --- | --- | --- | --- | --- | --- |
| Opus | 7,5 (8) | 8,5 (8) | 6,5 (7) | 7,5 (8) | 8,5 (9) |
| Fable | 9 (8) | 9 (8) | 8 (8) | 9 (8) | 9 (9) |

В скобках — прежняя оценка того же ревьюера: Opus — четвёртое ревью 2026-10-21,
Fable — третье, 2026-10-20. Для сравнения пятое ревью, Codex: Astra 9,2 / 9,5 /
9 (`solo` 9,3, `flutter_solo` 8,9), Sol 8,9 / 9,2 / 8,5 (9 и 8,8).

Ревьюеры разошлись сильнее, чем когда-либо: 7,5 и 9. Неверного поведения
не нашёл ни один, оба называют движок детерминированным и описанным точно. Opus
снимает за согласованность API: замена задачи зовёт её `ifCancelled`
и публикует лишний переход (M1), у накопителей нет обработчиков состояния (M2),
`run` у контроллера и у контекста значит противоположное (M3), — и за плотность
изложения на всех страницах (M4). Fable находок Medium не нашёл и снимает
только за цену входа: длину страниц и фраз, ранний абзац о `Failed` в Quick
start (L8), невысказанный вывод типов (L9).

До десяти. Opus: M1 и M2 в движке — +0,5, переименовать очередной `run` — +0,5,
основной путь первым абзацем каждого раздела и Quick start без зоны — +1,
короткий dartdoc — +0,5. Fable: снять плотность документации — единственное,
что отделяет пакет от десяти; строки `Solo.debug` на решения политик — +0,3
коду, разбить `add` и `_pump` — +0,5, таблица «что вы здесь найдёте» в начале
длинных страниц — +0,6.

## Страницы

Читаемость каждой страницы для разработчика с pub.dev. В скобках — оценка
того же ревьюера в том ревью, что и выше; у `diagnostics.md` в третьем ревью
оценки нет.

| Страница | Opus | Fable |
| --- | --- | --- |
| `solo/README.md` | 7 (8) | 8 (7) |
| `solo/doc/jobs.md` | 6,5 (7) | 8 (8) |
| `solo/doc/state.md` | 6,5 (7) | 7 (8) |
| `solo/doc/cancellation.md` | 6,5 (7) | 7 (8) |
| `solo/doc/resources.md` | 6,5 (8) | 8 (8) |
| `solo/doc/children.md` | 6,5 (8) | 7 (8) |
| `solo/doc/streams.md` | 7,5 (8) | 8 (9) |
| `solo/doc/accumulation.md` | 6 (7) | 7 (7) |
| `solo/doc/diagnostics.md` | 6,5 (8) | 8 |
| `solo/doc/errors.md` | 5,5 (6) | 8 (7) |
| `solo/doc/testing.md` | 7 (7) | 6 (8) |
| `solo/doc/mistakes.md` | 8 (9) | 9 (9) |
| `solo/doc/reference.md` | 6,5 (8) | 9 (9) |
| `solo/doc/camera.md` | 7 (8) | 7 (8) |
| `solo/doc/vs-bloc.md` | 6,5 (6) | 6 (6) |
| `flutter_solo/README.md` | 8 (8) | 8 (8) |
| `flutter_solo/doc/mixins.md` | 6,5 (7) | 7 (9) |
| `flutter_solo/doc/testing.md` | 8,5 (8) | 9 (9) |

Opus опустил почти каждую страницу на полбалла–балл, и причина у всех одна —
плотность фразы (M4); Fable опускал страницы за объём и число первых попыток:
`testing.md` с 8 до 6 (743 строки, 16 попыток, ни одной таблицы), `mixins.md`
с 9 до 7 (правило «Who reports» — в конце страницы). Поднялись у Fable только
README и `errors.md`.

**Заметно хуже остальных:** у Opus — `errors.md` (5,5) и `accumulation.md` (6):
`errors.md` вводит глаголы report, answer, observe без словаря и сразу ведёт
в таблицы маршрутов; раздел «Reference» `accumulation.md` требует держать
одновременно окно, политику, очередь и правило старта. У Fable — `vs-bloc.md`
(объём) и `testing.md` (объём, 16 попыток, нет таблиц), следом `children.md`
(длина фраз: в среднем 25 слов, 17,6% длиннее 35) и `mixins.md`. Общее у обоих
одно: `mixins.md` — таблицу листов и ответ `ListenableController` поставить
в начало. Предложения по каждой странице — в сырых отчётах, раздел 6.

## Сводка

High нет. Общие оценки 7,5 и 9.

**Неверного поведения кода не нашёл ни один.** Найдено место, где движок делает
обещанное, но с видимым следом: `Policy.restart` с `ifCancelled` публикует
состояние отмены между старой задачей и новой (M1). Два места согласованности
API: у `collect` и `accumulate` нет обработчиков состояния, и группе,
выставившей «прогресс», вернуться нечем (M2); `Solo.run` ставит в очередь,
а `ctx.run` запускает сразу (M3). По мелочи: ручная отмена
с `RulesCancelReason` отключает обработчики (L1), накопитель и `droppable` под
`drain` (L2), отказ `restart` без строки отладки (L3).

**Форма документов:** плотность фразы на всех страницах (M4), dartdoc длиной
в страницу (L5), длинные фразы CHANGELOG (L10), ячейки «Notes»
во `flutter_solo` (L13), строки `reference.md` (L14).

**Мелкие места:** абзац о `Failed` до `main()` в Quick start (L8), вывод типов
`run` не назван (L9), `SoloSelection.from` нет в CHANGELOG (L11), `_sync`
на `mistakes.md` без определения (L12), «Replaces» в dartdoc
`AccumulationPolicy.replace` (L7), черновая строка в `analysis_options.yaml`
(L6).

## Medium

### M1. `Policy.restart` с `ifCancelled` публикует промежуточное состояние

**Нашёл:** Opus (C1, D1). **Где:** `packages/solo/lib/src/solo.dart`,
`Solo.add`, ветка `Policy.restart`; `lib/src/job.dart`,
`_SoloJob._correctState`; `doc/state.md`, «Handler eligibility and errors»;
dartdoc `Policy.restart`.

Заменённая задача, уже стартовавшая, отменяется `ReplacedCancelReason`
и проходит `_correctState`: её `ifCancelled` пишет состояние после отмены,
и тут же стартует замена того же ключа со своим. `_correctState` различает
только `Failed` и `Cancelled`, причина ему безразлична. Сочетание — ровно поиск
из Quick start (`ifCancelled: → Initial`) и `Policy.restart` из «The dozen
calls». Таблица «What happens → What becomes of the handlers» на `state.md`
замену не называет.

```text
T1 [Searching(a), Idle, Searching(ab), Results(ab)]
```

`SoloBuilder` этот `Idle` в кадр не выводит (зонд F1: кадры
`[empty, loading, loading, empty]`, два синхронных `setState` сливаются). Видят
его синхронные слушатели, `listen`, `onChange`, `SoloObserver` и `SoloStream`.

Opus предлагает два варианта: не звать обработчики задачи, отменённой заменой,
пока замена в очереди, — ломающая правка, но 0.3.0 не выпущен; или описать
идиому
`ifCancelled: (s, c) => c.reason is ReplacedCancelReason ? s : const Idle()` —
по решению 95 возврат того же состояния ничего не публикует.

Вердикт: принято, Medium, вопрос владельцу (вопрос 2). Предлагаю второй
вариант: строка таблицы «Handler eligibility and errors» о замене, идиома
с `ReplacedCancelReason` там же и в dartdoc `Policy.restart`, тест страницы
на трассу зонда T1 и на идиому. Правка движка дешевле для читателя, но вводит
исключение в правило «отменённая задача зовёт `ifCancelled`», и замена, которую
потом саму отменят до старта, оставит состояние старой задачи. Итог: владелец
2026-10-21 выбрал идиому, сделано в тот же день: строка о замене в таблице
«Handler eligibility and errors» `state.md`, под разделом абзац с перезагрузкой
профиля и блоком идиомы, тот же фрагмент в dartdoc `Policy.restart`. Разошлось
с предложенным в примере: вместо поиска — `reload` профиля страницы, потому что
код раздела держит `state_page_profile.dart`. Тест страницы
`a replaced reload publishes Initial unless its handler asks` держит обе
трассы: без проверки причины `Loading, Initial, Loading, Loaded`, с ней —
`Loading, Loading, Loaded`; `emit` того же `Loading` новой задачей публикуется,
это её собственная запись. Движок не менялся. Позже, 2026-10-22: та же ловушка
стояла в README, у `Player.play` из «The dozen calls» — `Policy.restart`
с `ifCancelled → Idle`. Теперь там идиома с `ReplacedCancelReason`, в переводе
тоже. Тест `a replaced play publishes nothing between the two` держит трассу
без `Idle`, а `a play cancelled by hand still returns to Idle` — ручную отмену.
Раздел «После закрытия» `2026-10-21-form-wave-report.md`.

### M2. У накопителя нет обработчиков состояния, и вернуться из «прогресса» нечем

**Нашёл:** Opus (C2, D2). **Где:** `packages/solo/lib/src/solo.dart`,
`Solo.collect`, `Solo.accumulate`; `lib/src/accumulator.dart`,
`_SoloAccumulator`; `doc/accumulation.md`, «Start, cancellation and errors»;
`doc/reference.md`, «Parameters of a job».

`collect` и `accumulate` принимают `timeout`, `keepWhile` и `cancellable` —
всё, что отменяет группу, — но не `ifFailed` и `ifCancelled`. Сама группа
за собой не уберёт: `emit` после принятой отмены бросает `Cancelled`,
а в уборке — `StateError` (решение 33). В `reference.md` у обработчиков
в столбце «Taken by» стоят только `run, job`, а почему у накопителя их нет
и что вместо них, не сказано нигде; рецепты страницы пишут состояние только
после работы, и ловушки в них не видно.

```text
P5 outcome Cancelled(closed); state -99
Q2 outcome Cancelled(closed); state 0
```

P5: группа пишет `-99` («сохраняю»), затем `close()`. Q2 — обход: тело группы
делает работу ребёнком `ctx.run(job(ifCancelled: (s, c) => before, ...))`.
Первая версия Q2, `ctx.onDiscard(() => ctx.emit(before))`, упала
с `Bad state: Job(batch) is cleaning up after its body, cannot emit`.

Вердикт: принято, Medium, вопрос владельцу (вопрос 3). Документами сейчас
в любом случае: на `accumulation.md`, «Start, cancellation and errors», —
почему у группы нет обработчиков и обход ребёнком с `ifCancelled`, фрагментом
под стендом `accumulation_snippets.py`; в `reference.md` — ссылка туда.
Параметры `ifFailed` и `ifCancelled` у `collect` и `accumulate` — новое API
и вопрос владельцу: группа — обычная задача, механика `_correctState` есть,
но у группы много вызывающих, и обработчик пишет состояние за всех. Итог:
владелец выбрал параметры (вопрос 3), и обход ребёнком, который предлагался для
страницы, не понадобился. `collect` и `accumulate` принимают `ifFailed`
и `ifCancelled` и отдают их задаче группы; на `accumulation.md`, в «Start,
cancellation and errors», — фрагмент `PhotoUploader` под стендом с трассой
и абзац о группах, которые не начались; в `reference.md` у обоих обработчиков
четыре фабрики в «Taken by»; записи CHANGELOG в «Breaking changes» и «Added».
Дизайн, его ревью и ревью сделанного —
`2026-10-21-accumulator-state-handlers-design.md`, коммит
`feat(solo): give accumulators the state handlers of job`.

### M3. `run` у контроллера и `run` у контекста — противоположные действия

**Нашёл:** Opus (C3), повтор решений 46 и 54 с доводом об имени. **Где:**
`packages/solo/lib/src/solo.dart`, `Solo.run`; `JobContext.run` ядра;
`doc/mistakes.md`, «Steps as children».

`Solo.run(body)` делает корневую задачу, ставит её в хвост очереди и отдаёт
`SoloJob<T>`. `ctx.run(child)` запускает ребёнка сразу, мимо очереди, и отдаёт
`Future<T>`. В теле контроллера обе формы стоят рядом:
`await ctx.run(_sync(item))` работает, `await sync(item).value`, где `sync`
ставит задачу в очередь, — вечный дедлок. Решение 54 — о том, что дедлок
не ловят в `add`; довод Opus — об имени: в 0.3.0 и так ломаются `SoloBase`,
`onError` и `state`, а решение 48 переименовало `state` ровно затем, чтобы
перепутанный член не компилировался молча. Предлагает `enqueue`, `schedule` или
`queue`.

Вердикт: принято как вопрос владельцу (вопрос 4); предлагаю не переименовывать.
Довод новый, но дедлок — не от имени `run`, а от `await` своего метода из тела:
на самой `mistakes.md` `sync(item)` возвращает `add(_sync(item))`, и имени
`run` в нём нет. Решение 48 закрывало ошибку, которую компилятор пропускал
на каждом чтении состояния; здесь ошибку называют строка `Solo.debug` и раздел
`mistakes.md`. `run` стоит во всех страницах, стендах и переводах. Если
владелец согласен — дополнить решение 54 этим доводом.

Итог: владелец 2026-10-21 — не переименовывать. Решение 54 `docs/settled.md`
дополнено доводом об имени. Позже, 2026-10-22, владелец пересмотрел: «мне
кажется эта претензия верной». `Solo.run` переименован в `enqueue`, а заодно,
по его же вопросу, `Solo.add` — в `enqueueJob`: `add` совпадал с `add`
накопителя и с `add` событий Bloc. Разошлось с предложенным тем, что
переименованы оба члена, а не один, и имя выбрано из пары с одним глаголом.
Довод о дедлоке и фраза «не переименовывается» из решения 54 ушли. Отчёт —
`2026-10-22-enqueue-rename-report.md`.

### M4. Плотность изложения на страницах `solo`

**Нашёл:** Opus (D3); Fable — тот же резерв в оценке документации и страниц.
**Где:** все страницы `packages/solo/doc/`, сильнее всего `errors.md`,
`accumulation.md` («Reference»), `reference.md`, `jobs.md` («Queue and
policies»), `testing.md`.

По Opus, фразы по словам средние, 12–16 слов, но в одной фразе по три-четыре
понятия через двоеточия и «the way … does»: строка `cancellable`
в `reference.md` («`false` turns down manual cancellation, the parent's and
closing, and keeps a queued job through removals and `cancelAll()` without
`force: true`, though not through `close()`»), `accumulator.add` там же,
«Answering for every failure» на `mistakes.md`. Основной путь и краевой случай
идут одним тоном и в одном абзаце. Решение 86 запрещает сворачивать
`vs-bloc.md` из-за длины; находка — о плотности фразы на всех страницах. Fable
считает по-другому: длинные фразы на `children.md`, `vs-bloc.md`, `camera.md`,
`streams.md` и README `flutter_solo` (12–18% длиннее 35 слов) и объём
`testing.md`; предлагает таблицу «что вы здесь найдёте» в начале длинных
страниц.

Вердикт: принято, Medium, вопрос владельцу о волне (вопрос 5). Предлагаю
по пересечению двух ревьюеров: в каждом разделе первым абзацем основной путь,
краевые случаи — после него; таблица-вход в начале `testing.md`, `state.md`,
`accumulation.md` и `errors.md`, где её нет, — решение 71 не трогается, вход
стоит перед разделами; редакторский проход по фразам длиннее 35 слов на пяти
страницах Fable. Волна большая, переводы идут следом, стенды держат код. Итог:
сделано 2026-10-22. Входы: таблицы перед разделами `state.md`
и `accumulation.md`; у `errors.md` и `testing.md` входы уже были. Основной путь
первым — перестановкой целых абзацев в пяти разделах `jobs.md`, `state.md`,
`accumulation.md` и `errors.md`. Разошлось с предложенным: в «Observing state»
`state.md` абзацы основного пути стоят после абзацев о вложенной записи —
поднять их можно, только переписав слова. Фраз длиннее 35 слов на пяти
страницах Fable было 54, стало 0. Ревью сделанного нашло после резки три
двусмысленности на `streams.md` и `vs-bloc.md`, они поправлены. Отчёт —
`2026-10-21-form-wave-report.md`. Позже, 2026-10-22, и это расхождение снято:
блок о вложенной записи стоит в конце «Observing state», а его первая фраза
называет порядок прямо — «the order of the list above». Раздел «После закрытия»
того же отчёта.

## Low

### L1. Ручная отмена с `RulesCancelReason` отключает обработчики

**Нашёл:** Opus (C4). **Где:** `packages/solo/lib/src/job.dart`,
`_SoloJob.cancelWith`; `lib/src/solo_cancel_reason.dart`, `RulesCancelReason`.

`cancelWith` решает, что отменили правила, по типу причины. У причины публичный
`const`-конструктор, и `job.cancel(reason: const RulesCancelReason())`
отключает `ifCancelled`: состояние задачи остаётся.

```text
P4 outcome Cancelled(rules); state 99
P4b outcome Cancelled(manual); state -1
```

Вердикт: принято, Low, кодом. Решение «отменили правила» — по внутреннему флагу
движка, а не по типу причины; тест на P4. Скрыть конструктор, как второй
вариант ревьюера, — ломающая правка ради случая, где причину подделали руками,
не предлагаю. Итог: сделано 2026-10-21. `_SoloJob.cancelWith` больше не смотрит
на тип причины: флаг ставят сами точки, где отменяют правила, — `_checkedState`
и `stateAs` контекста, а смена состояния в `Solo` ставила его и раньше. Три
теста в `state_handlers_test.dart`: ручная отмена с `RulesCancelReason` зовёт
`ifCancelled`, отказ контрольной точки и `stateAs` его отключают; мутант
со старой проверкой типа роняет первый, мутант без новых флагов — два других.
Отчёт — `2026-10-21-sixth-review-wave-report.md`.

### L2. Под `drain` накопитель отвергает событие ждущей группы, а `droppable` отдаёт задачу

**Нашёл:** Opus (C5). **Где:** `packages/solo/lib/src/accumulator.dart`,
`_SoloAccumulator.add`; `lib/src/solo.dart`, `Solo.add`, ветка `droppable` при
`_draining`; dartdoc `SoloCloseMode.drain`.

Во время `close(mode: drain)` вызов `droppable` с занятым ключом получает ту же
задачу, а событие накопителя, чья группа ещё ждёт окна и будет выполнена,
получает новую задачу `Cancelled(closed)`, и событие теряется.
`accumulation.md` это говорит («Neither mode takes anything new»), но разницу
с `droppable` не называет ни страница, ни dartdoc.

```text
P2 same handle after drain: false
P2 first: Done(5); late: Cancelled(closed); state 5
P3 identical: true
```

Вердикт: принято, Low, документами. Фраза в dartdoc `SoloCloseMode.drain`
и `SoloAccumulator.add`: под `drain` накопитель новых событий не берёт, даже
в ждущую группу, — в отличие от `droppable`, который отдаёт идущую задачу.
Принимать событие в группу под `drain` — правка поведения закрытия,
не предлагаю. Итог: сделано 2026-10-21, как предложено: фраза в dartdoc
`SoloCloseMode.drain` и `SoloAccumulator.add`. Отчёт —
`2026-10-21-sixth-review-wave-report.md`.

### L3. `Solo.debug` молчит, что `restart` отказали

**Нашёл:** Fable (C1). **Где:** `packages/solo/lib/src/solo.dart`, `Solo.add`,
ветка `Policy.restart`.

`restart` поверх идущей задачи того же ключа с `cancellable: false`: отмена
отклонена, новая задача ждёт конца старой, — это в dartdoc `Policy.restart`.
Но трасса печатает ту же строку, что для `sequential`, без слова «restart»
и без отказа.

```text
P14 debug: add Job(k)
P14 debug: add Job(k) while Job(k) is running: it starts after Job(k) ends
P14 debug: queue has no ready jobs
```

Вердикт: принято, Low, кодом. Строка `Solo.debug` на решение политики
`restart`, когда отмена отклонена, и на снятые из очереди задачи `replace`;
тест на текст. Поведение не меняется. Итог: сделано 2026-10-21. После отмены
`restart` пишет `restart: cancel Job(k)`,
`restart: Job(k) turns the cancellation down: it is not cancellable` или
`restart: Job(k) holds the cancellation back until its uncancellable section
closes`; тест в `hooks_test.dart`. Строку для `replace` не добавлял: снятая
задача уже печаталась, `remove Job(k): Cancelled(replaced)` или
`remove Job(k): not cancellable`, — зонд показал это до правки. Отчёт —
`2026-10-21-sixth-review-wave-report.md`.

### L4. `Solo.add` и `Solo._pump` — длинные методы

**Нашёл:** Fable (C2). **Где:** `packages/solo/lib/src/solo.dart`, `Solo.add`,
`Solo._pump`, `Solo.close`.

`solo.dart` — 1478 строк; `add` несёт политику, поиск дубликата, отладочную
строку с тремя хвостами, вставку, замену и перезапуск; `_pump` — цикл
по очереди, правила, три исхода отказа и запуск. Комментарии объясняют каждый
порядок, но инвариант «задача между очередью и `_current` принадлежит только
`_inTransition`» проверяется глазами по сотне строк. Fable предлагает
именованные приватные шаги.

Вердикт: не делать до выпуска, предлагаю. Ревьюер сам называет это стоимостью
сопровождения, а не дефектом; перекройка самых нагруженных методов движка перед
0.3.0 — риск без выигрыша для пользователя. После выпуска — вместе со следующей
правкой политики. Если владелец согласен — в `docs/settled.md` рядом с решением
40 (вопрос 6). Итог: владелец 2026-10-21 — после выпуска; решение 102
`docs/settled.md`.

### L5. Публичный dartdoc — спецификация, а не подсказка

**Нашёл:** Opus (C6). **Где:** `packages/solo/lib/src/solo.dart`: `Solo.job`
(83 строки `///`), `Solo.run` (38), `Solo.onUnanswered` (37);
`packages/flutter_solo/lib/src/solo_selection.dart`: `SoloSelection` (55);
`solo_listenable.dart`: `SoloListenable` (38); `solo_selector.dart`:
`SoloSelector` (37). У `solo.dart` 560 строк `///` на 704 строки кода.

В подсказке IDE и на странице API главное — что делает член и пример — тонет
в краевых случаях: повторный вход, порядок хуков, зоны.

Вердикт: принято, Low, в ту же волну, что M3
`2026-10-21-async-job-project-review-3.md` (вопрос 5): контракт первым абзацем,
пример, ссылка на раздел страницы. Итог: сделано 2026-10-22 по тем же правилам,
что M3 ядра: у шести членов было 288 строк `///`, стало 191. Пример остался
только там, где он уже был: у `Solo.job` ушёл блок с `TimeoutCancelReason`,
у `Solo.run` — повтор того же `ifCancelled`. Разбор, который был только
в dartdoc, переехал на страницы отдельным коммитом. Ревью сделанного нашло
в `Solo.job` висячее «instead» и неточность о `TimeoutCancelReason`, обе
поправлены. Отчёт — `2026-10-21-form-wave-report.md`.

### L6. Черновая строка в `analysis_options.yaml`

**Нашёл:** Opus (C7). **Где:** `packages/solo/analysis_options.yaml`, строка
14; `packages/flutter_solo/analysis_options.yaml`, строка 29; та же строка
в `packages/async_job/analysis_options.yaml`, строка 14.

`# invalid_annotation_target: ignore ???` — черновая пометка, которая уходит
в архив каждого пакета.

Вердикт: принято, Low, удалить во всех трёх копиях одним коммитом — набор один
на три пакета (решение 66). Итог: сделано 2026-10-21: строки `# Ignore`
и `# invalid_annotation_target: ignore ???` удалены из всех трёх файлов.
Отчёт — `2026-10-21-sixth-review-wave-report.md`.

### L7. Dartdoc `AccumulationPolicy.replace` говорит «Replaces»

**Нашёл:** Opus (D4), повтор решения 53 в части текста. **Где:**
`packages/solo/lib/src/accumulator.dart`, строка 9.

«Replaces the last matching group's job at the queue's tail, keeping its
handle» читается как замена задачи. На деле событие сливается с группой, как
у `join`, и группа переезжает в хвост; ничего не отменяется. CHANGELOG пишет
верно («moves the waiting group's job to the tail»), а рядом `Policy.replace`
действительно отменяет.

```text
R1 same handle: true
R1 outcome Done(3); log [other, acc 3]
```

Вердикт: принято, Low, документами; довод новый — решение 53 об имени,
а не о тексте подсказки. Имя остаётся. Dartdoc: «Joins the last matching group,
as [join] does, and moves that group's job to the queue's tail. Nothing is
cancelled.» Итог: сделано 2026-10-21; фраза о `cancellable: false` осталась
второй, как была. Отчёт — `2026-10-21-sixth-review-wave-report.md`.

### L8. Абзац о ненаблюдённом `Failed` стоит в Quick start до `main()`

**Нашли:** Opus (D6), Fable (D2). **Где:** `packages/solo/README.md`, «Quick
start», абзац «A `Failed` that nobody observes goes on to the zone…» (строка
119), до блока `main()` (строка 135).

Читатель ещё не видел `job.value`, `done` и `main()`, а ему уже объясняют зону,
`Solo.unansweredHandler`, `ignoreFailure()` и «a plain Dart program ends
there». Мысль важная, но для первого запуска хватит одной фразы. Решение 73
не мешает: речь о месте, а не о наличии.

Вердикт: принято, Low, документами. Абзац — после `main()`, где появляется
`await job.value`, одной-двумя фразами со ссылкой на `errors.md`; полный текст
остаётся на `errors.md`. Перевод тем же коммитом. Итог: сделано 2026-10-21.
Абзац стоит после `main()` и ужат до двух фраз: фраза о том, что делают Dart
и Flutter, ушла, а две, которые держит `readme_rakes_test.dart`, остались,
со ссылкой на `errors.md`. Отчёт — `2026-10-21-sixth-review-wave-report.md`.

### L9. Не сказано, что аргументы типов `run` выводятся

**Нашёл:** Fable (D1). **Где:** `packages/solo/README.md`, «Quick start»;
`doc/jobs.md`, «Jobs and results»; `doc/state.md`, «The rules»;
`doc/accumulation.md`, вступление.

Все примеры пишут оба аргумента явно, проза говорит о них как об обязательных,
и читатель выучит `run<ProfileState, String>` как ритуал. На деле `W` падает
к границе `S`, а `T` выводится из тела.

```text
INFER noArgs: Job() -> Done(1) (_SoloJob<St, St, int>)
INFER narrow: Done(n=1)
INFER handlers: Done(null)
```

Вердикт: принято, Low, документами. Одна фраза в Quick start: оба аргумента
можно оставить выводу, когда тело работает во всём `S`; `W` пишут, когда оно
уже. Ссылкой на неё — `jobs.md`; остальные места не трогать. Перевод тем же
коммитом. Итог: сделано 2026-10-21. В Quick start — фраза о выводе обоих
аргументов; в `jobs.md` вместо ссылки — своя короткая фраза в абзаце
об аргументах типа: ссылка с этой страницы на README вела бы с подробного
на вводное. Отчёт — `2026-10-21-sixth-review-wave-report.md`.

### L10. Фразы CHANGELOG `solo` длинные, первый ломающий пункт не разобрать

**Нашли:** Opus (D5), Fable (D4). **Где:** `packages/solo/CHANGELOG.md`,
`## 0.3.0`, «Breaking changes» и «Changes you will see on upgrade».

Opus: первый пункт — «A `Failed` nobody observes reaches the zone as it did in
`0.2.0` only while neither is there: with a handler set, or `onUnanswered`
overridden, it goes there, a microtask after the job ends, and not to the
zone» — не понять, что такое «neither» и куда «there». Fable: средняя фраза
раздела — 40,4 слова, девяностый перцентиль — 83; человек, который обновляется,
ищет «что мне поменять», а читает «почему». Решение 75 — одна фраза на запись —
писано для `## Unreleased`, но дух тот же.

Вердикт: принято, Low, документами. Первый пункт переписать по варианту Opus:
ненаблюдённый `Failed` идёт к `Solo.unansweredHandler` или переопределённому
`onUnanswered`, а в зону — только когда нет ни того, ни другого. В каждой
записи «Breaking changes» действие — первой фразой, обоснование — после.
Перевод `docs/ru/solo/CHANGELOG.md` тем же коммитом. Итог: сделано 2026-10-21:
первый пункт переписан действием вперёд, остальные пункты «Breaking changes»
и так начинались с действия жирным. Отчёт —
`2026-10-21-sixth-review-wave-report.md`.

### L11. CHANGELOG `flutter_solo` не называет `SoloSelection.from`

**Нашёл:** Fable (D3). **Где:** `packages/flutter_solo/CHANGELOG.md`,
`## 0.3.0`, «Added», пункт `SoloSelection<S, T>`.

Конструктор берёт `ValueListenable`; для контроллера без `SoloListenable` вход
другой — статический `SoloSelection.from`. Запись CHANGELOG о нём молчит
(`SoloSelection.from` в файле не встречается ни разу).

Вердикт: принято, Low, документами. Дописать в пункт `SoloSelection.from` для
контроллера, который не `ValueListenable`. Перевод тем же коммитом. Итог:
сделано 2026-10-21, как предложено. Отчёт —
`2026-10-21-sixth-review-wave-report.md`.

### L12. `mistakes.md`, «Steps as children»: `_sync` и `sync` не показаны

**Нашёл:** Opus (D7). **Где:** `packages/solo/doc/mistakes.md`, «Steps as
children», строки 158–160.

«`_sync` and `_recordPath` make the jobs and start nothing, and `sync` and
`recordPath` put them into the queue» — но на странице нет ни одного из четырёх
методов, а разница `sync` и `_sync` — вся суть ошибки.

Вердикт: принято, Low, документами. Две строки определений над «Don't do this»;
тест страницы и перевод тем же коммитом. Итог: сделано 2026-10-21 прозой,
а не строками кода: тест страницы `mistakes_page_test.dart` держит блоки парами
«Don't / Do», и третий блок его бы сломал. Четыре метода названы в абзаце над
«Don't do this», из абзаца под ним пересказ убран. Отчёт —
`2026-10-21-sixth-review-wave-report.md`.

### L13. Ячейки «Notes» в README `flutter_solo` — абзацы

**Нашли:** Opus (D8); Fable — тот же совет в оценке страницы. **Где:**
`packages/flutter_solo/README.md`, «Notes».

Ответ «Where does a listener's failure go?» — четыре фразы с тремя маршрутами
в одной ячейке; на pub.dev это колонка в полэкрана сплошного текста. Opus
предлагает вопросы подзаголовками, Fable — две таблицы: «куда идёт ошибка»
и «жизнь контроллера».

Вердикт: принято, Low, вопрос владельцу в волне формы (вопрос 5). Предлагаю
вариант Fable: две таблицы, ячейка — одна фраза и ссылка на раздел; решение 76
не трогается, страница одна. Итог: сделано 2026-10-22, две таблицы на одной
странице, но не те, что у Fable. Первая — «A failure of | Where it goes»,
по строке на маршрут, вторая — прежние пять вопросов. «Жизни контроллера»
отдельной таблицей нет: вопросы о ней остались во второй. Двум ячейкам вопросов
и двум маршрутам сослаться некуда, ссылок у них нет. Ячейки в одну фразу
не вышло: ответы на вопросы — от двух до пяти фраз прежними словами. Ни один
факт прежних ячеек не выброшен. Отчёт — `2026-10-21-form-wave-report.md`.

### L14. Строки `reference.md` пересказывают контракт

**Нашёл:** Opus (D9). **Где:** `packages/solo/doc/reference.md`, «Parameters of
a job» (`cancellable`, `keepWhile`), «SoloAccumulator», «Other types»
(`Policy`).

Справочник обещает одну строку на член, но строки несут условия и исключения
(примеры в M4), и при чтении по диагонали не дают ни краткого ответа,
ни полного. Fable, напротив, ставит странице 9 и советует её формат остальным.

Вердикт: принято частично, Low, документами. Названные строки — `cancellable`,
`keepWhile`, `accumulator.add`, `Policy` — сократить до того, что член делает,
условия оставить разделу, куда ведёт «Where». Остальную страницу не трогать:
второй ревьюер считает её лучшей. Итог: сделано 2026-10-21: четыре строки — что
член делает; условия остались разделам, куда ведёт «Where». Отчёт —
`2026-10-21-sixth-review-wave-report.md`.

## Вопросы владельцу

1. Чинить ли одной волной до выпуска 0.3.0 то, что не меняет API: документную
   часть M1 и M2, L1–L3, L6–L12, L14.
2. M1: описать замену в таблице обработчиков и дать идиому
   с `ReplacedCancelReason` (предлагаю) или не звать обработчики задачи,
   которую отменила замена.
3. M2: давать ли `collect` и `accumulate` параметры `ifFailed` и `ifCancelled`,
   или оставить обход ребёнком, описанный на странице.
4. M3: переименовывать ли защищённый `Solo.run`. Предлагаю нет и дополнить
   решение 54.
5. Брать ли волну формы: основной путь первым абзацем и вход-таблица на длинных
   страницах (M4), короткий dartdoc (L5), «Notes» `flutter_solo` (L13) — вместе
   с волной M3 ревью ядра.
6. L4: не разбивать `add` и `_pump` до выпуска и записать решение.

## Ответы владельца

2026-10-21: волна по вопросу 1 — да; `Solo.run` не переименовывать (вопрос 4,
итог — в вердикте M3). Остальные вопросы владелец решит позже. Документная
часть M1 и M2 ждёт ответов на вопросы 2 и 3: от них зависит, что описывать.

2026-10-21, позже: M1 (вопрос 2) — идиома в документах, движок не меняется:
строка о замене в таблице «Handler eligibility and errors» `state.md`, идиома
с `ReplacedCancelReason` там и в dartdoc `Policy.restart`, тест страницы
на трассу T1 и на идиому. M2 (вопрос 3) — параметры `ifFailed` и `ifCancelled`
у `collect` и `accumulate` добавляются: причины их отсутствия не записано
нигде, а довод о многих вызывающих слаб — обработчик задают один раз,
в фабрике. Сначала дизайн и его ревью на Opus. Волна формы (вопрос 5) — да,
до выпуска 0.3.0, вместе с волной M3 ядра; проверка — список членов в отчёте
волны со строками `///` до и после. L4 (вопрос 6) — после выпуска.

2026-10-22: вопрос 4 пересмотрен — `Solo.run` переименовать в `enqueue`,
`Solo.add` — в `enqueueJob`, до выпуска 0.3.0. Итог — в вердикте M3.
