> **Состояние на 2026-10-21:** ревью проведено, у каждой находки стоит
> вердикт. Правок по нему ещё нет: что чинить, решает владелец, вопросы —
> в конце записи.
> **Что это:** пятое полное ревью `solo` и `flutter_solo`, на подготовленном
> выпуске 0.3.0, двумя ревьюерами Codex — Astra и Sol 6.1: оценка из десяти,
> ответ на вопрос «что сделать, чтобы поставить 10», оценка читаемости каждой
> страницы. После сведения дубликатов 8 находок: 0 High, 2 Medium, 6 Low.
> **Связанные записи:** `2026-10-21-async-job-project-review-2.md` (то же
> ревью ядра, там устройство прогона), `2026-10-21-solo-project-review.md`
> (четвёртое ревью, Opus), `2026-10-20-solo-project-review.md` (третье, там
> прежние оценки Astra и Sol; его M1 и M4 — предки L3 и M1).

# Пятое полное ревью `solo` и `flutter_solo`: Astra и Sol 6.1

## Как это делалось

Устройство то же, что у половины про ядро,
`2026-10-21-async-job-project-review-2.md`: дерево на `3e3445a4`, клоны
`.artifacts/2026-10-21-full-review-2/solo-<ревьюер>/tree`, задание Codex
2026-10-20 с пунктом о `docs/settled.md`, базовая линия та же.

| Ревьюер | Модель и вызов | Время |
| --- | --- | --- |
| Astra | `gpt-6-astra`, усилие `xhigh`, `codex exec` через `run.sh` скилла `codex` | 1776 с |
| Sol 6.1 | `gpt-6.1-sol`, усилие `xhigh`, так же | 844 с |

Оба прогнали наборы `solo`, его примера, `flutter_solo` и его примера с числами
базовой линии; Sol — ещё `format`, `analyze` и `dart doc --dry-run` обоих
пакетов. Astra сверх находок гонял смешанный зонд очереди: 4000 подач
со случайными политиками, отменами и уборкой — ни перекрытия корневых задач,
ни незавершённой задачи, ни оставшегося таймера. Отслеживаемых файлов не тронул
ни один.

Зонды обоих скопированы в `.artifacts/2026-10-21-full-review-2/mine/probes/`
и прогнаны в моей копии; всё, что они печатают, совпало с отчётами дословно.
Сырые отчёты — `out/solo-astra.json` и `out/solo-sol.json` там же.

## Оценки

| Ревьюер | Общая | Код | Документация | `solo` | `flutter_solo` |
| --- | --- | --- | --- | --- | --- |
| Astra | 9,2 (8,7) | 9,5 (9) | 9 (8,2) | 9,3 (8,7) | 8,9 (8,8) |
| Sol 6.1 | 8,9 (8,5) | 9,2 (8,6) | 8,5 (8,2) | 9 (8,7) | 8,8 (8,3) |

В скобках — их оценки 2026-10-20. Подняли все десять чисел: общую — на 0,4–0,5,
документацию — Astra на 0,8, Sol на 0,3. Дефектов в `lib/` `solo` Astra
не нашёл, Sol нашёл один край (L2); `flutter_solo` снижают у Sol повторный вход
в подписку `SoloSelection` (M1), у Astra — пример, который не замечает замены
`api` (M2), и два места README (L5, L6). Оба по-прежнему ставят код выше
документации и снимают с неё больше за плотность, чем за неправду: неверных
мест четыре, L1, L3, L4, L5.

До десяти, по их словам: M1 с регрессионными тестами — +0,7…0,8 `flutter_solo`,
M2 — +0,5, исправить найденное в документах и разгрузить `errors.md`,
`testing.md` и `mixins.md`. Переделывать реализацию ради оценки не предлагает
ни один.

## Страницы

Читаемость каждой страницы для разработчика с pub.dev. В скобках — оценка
того же ревьюера 2026-10-20; у `diagnostics.md` прежней нет, страница новая.

| Страница | Astra | Sol 6.1 |
| --- | --- | --- |
| `solo/README.md` | 9,5 (8) | 8,5 (8,5) |
| `solo/doc/jobs.md` | 9 (8) | 8 (8) |
| `solo/doc/state.md` | 9,3 (7,5) | 8 (8) |
| `solo/doc/cancellation.md` | 9,5 (8,5) | 8 (8,5) |
| `solo/doc/resources.md` | 9,7 (9) | 8,5 (8,5) |
| `solo/doc/children.md` | 9,2 (8,5) | 8 (8,5) |
| `solo/doc/streams.md` | 9,4 (9) | 8,5 (9) |
| `solo/doc/accumulation.md` | 9 (8) | 8 (7,5) |
| `solo/doc/diagnostics.md` | 9,5 | 8,5 |
| `solo/doc/errors.md` | 8,8 (7) | 7,5 (7) |
| `solo/doc/testing.md` | 9,2 (8,5) | 7,5 (8) |
| `solo/doc/mistakes.md` | 10 (9) | 9 (9) |
| `solo/doc/reference.md` | 9,1 (9) | 8,5 (8,5) |
| `solo/doc/camera.md` | 9,2 (8,5) | 8,5 (7,5) |
| `solo/doc/vs-bloc.md` | 8,8 (8) | 8,5 (6,5) |
| `flutter_solo/README.md` | 8,8 (8) | 8 (8) |
| `flutter_solo/doc/mixins.md` | 8,5 (8,5) | 8,5 (9) |
| `flutter_solo/doc/testing.md` | 10 (9) | 9 (9) |

Astra поднял все страницы, кроме `mixins.md`, и три поставил на 10:
`mistakes.md`, `testing.md` `flutter_solo` и, сверх задания, README примера
`solo`. Sol сдвинул меньше и в обе стороны: `vs-bloc.md` +2, `camera.md` +1,
`accumulation.md` +0,5; `cancellation.md`, `children.md`, `streams.md`,
`testing.md` `solo` и `mixins.md` −0,5 — за пропущенный `drain` (L3), сроки
жизни и маршруты в прозе и рецепт `testing.md` на фикстурах, которых нет
на странице.

**Заметно хуже остальных:**

- `solo/doc/errors.md` — у обоих: карта ошибок полна, но большая таблица
  и словарь «hears / answers for» требуют держать в голове несколько маршрутов.
  Оба просят короткую схему двух маршрутов перед таблицей.
- `solo/doc/testing.md` — у Sol: последний рецепт стоит на `FakeCamera`,
  `CancelToken` и `OpenCancelled`, которых на странице нет; импорты разбросаны.
- `flutter_solo/doc/mixins.md` — у Astra: цепочку base, leaf, mixin
  и переопределения читатель строит из прозы; просит схему с победившим
  `onListenerError`.
- `vs-bloc.md` — у Astra: длинные абзацы после трасс; одиннадцать сценариев он
  недостатком не считает.

## Сводка

High нет. Общие оценки 9,2 и 8,9, обе выше прошлого раза.

**Два дефекта, оба воспроизведены:** повторный вход во время подписки
`SoloSelection` роняет её `TypeError`, шлёт лишнее уведомление или стирает
чужую подписку (M1) — ещё один из семьи M4 третьего ревью, где тогда закрыли
пять; пример `flutter_solo` не замечает нового `api` у того же `State` (M2).

**Край накопителя:** отмена из `Solo.debug` посреди переноса группы `replace`
оставляет таймер закрытой группы до `close()` (L2).

**Документы:** порядок `Policy.replace` описан наоборот в трёх местах — нашли
оба (L1); исключение `drain` не дошло до dartdoc `run` и `cancellation.md` (L3,
хвост M1 третьего ревью); «ошибка правила подавляет коррекцию» шире правды
(L4); README `flutter_solo` упрощает `close()` (L5) и не объявляет `ProfileApi`
(L6).

## Medium

### M1. `SoloSelection.addListener`: устаревшая попытка подписки

**Нашёл:** Sol (C1). **Где:**
`packages/flutter_solo/lib/src/solo_selection.dart`,
`SoloSelection.addListener` и его откат в `catch`.

`addListener` запоминает `_selected` и зовёт `_source.addListener`. Источник
может опубликовать изменение прямо в своём `addListener` — это поддержано
и держится тестами. Если в этот момент другой слушатель источника снимет
последнего слушателя выборки, `_forget()` очистит `_selected`, а внешний вызов
вернётся и продолжит с очищенным состоянием. Три исхода из четырёх сценариев
зонда:

```text
PROBE eager removal: type 'Null' is not a subtype of type 'int' in type cast; final value=1
PROBE eager replacement: unsolicited event=[1]
PROBE failed outer subscribe: successful replacement heard=[]
```

Во втором новая подписка, сделанная внутри вызова, получает уведомление,
о котором не просила; в третьем откат упавшего внешнего вызова снимает успешную
вложенную подписку, и `source.value = 2` до неё уже не доходит. M4 третьего
ревью закрыл повторный вход при снятии и при упавшей подписке по отдельности;
это их сочетание с публикацией в момент подписки.

Вердикт: принято, Medium, кодом в `flutter_solo`. Поколение подписки: после
возврата из чужого `addListener` попытка проверяет, что она ещё текущая,
а откат снимает только свою регистрацию; проверки `_listeners.isEmpty` мало —
слушатели могут быть уже нового поколения. Тест на каждый из трёх сценариев.
Воспроизведено зондом Sol.

### M2. Пример `flutter_solo`: новый `api` у того же `State` не доходит до контроллера

**Нашёл:** Astra (C1). **Где:** `packages/flutter_solo/example/lib/main.dart`,
`_ProfileScreenState`, `late final controller = ProfileController(widget.api)`;
`didUpdateWidget` нет.

Родитель передаёт другой `api` с тем же типом и ключом — Flutter сохраняет
`State`, а `late final` не пересчитывается. Reload ходит в старый `api`
и показывает его данные:

```text
API REPLACED old=2; new=0; visible=Alice
```

Четыре теста примера держат успех, ошибку, отмену и повторное нажатие, замену
зависимости — нет. В `main()` примера `api` не меняется.

Вердикт: принято, кодом примера; тяжесть скорее Low — библиотеки не касается,
но пример копируют как образец экрана. `didUpdateWidget` сравнивает `api`
по идентичности, делает новый контроллер и закрывает старый; `_load` после
`await` проверяет, что контроллер тот же. Тест на замену в покое и посреди
загрузки.

## Low

### L1. Порядок `Policy.replace` описан наоборот

**Нашли:** Astra (D1), Sol (D1). **Где:** `packages/solo/doc/jobs.md`, «Queue
and policies», строка `Policy.replace`; `packages/solo/doc/camera.md`,
«Policy.replace»; dartdoc `Policy.replace`.

Все три говорят «удалить прежние, затем поставить новую»: «Remove cancellable
queued jobs with that key, then enqueue the new job». `Solo.add` делает
наоборот, и намеренно: отмена синхронно зовёт `onFinish` и слушателей отмены,
и они уже видят новую задачу в очереди. Dartdoc `Solo.add` и раздел «Fixed»
`CHANGELOG.md` говорят верно.

```text
replace: old onFinish sees [second] already queued
REPLACE [old cancelled; queue=[new], body from listener]; new=Cancelled(replaced)
```

Вердикт: принято. Три места — «новая встаёт в очередь, затем отменяются
прежние», с полуфразой о том, что колбэки отмены её уже видят. Сторож на строку
таблицы и dartdoc. Воспроизведено зондами обоих.

### L2. Накопитель: отмена из `Solo.debug` при переносе группы оставляет таймер

**Нашёл:** Sol (C2). **Где:** `packages/solo/lib/src/accumulator.dart`,
`_SoloAccumulator.add`, ветка `AccumulationPolicy.replace`.

После переноса группы `add` зовёт `Solo.debug` со строкой `move`. Если колбэк
отменяет переносимую задачу, отмена снимает таймер и освобождает группу,
а `add` после возврата без проверки зовёт `group._accepted()` и ставит новый.
Таймер держит группу, накопитель и контроллер до конца окна или до `close()`.

```text
PROBE queued=0 outcome=Cancelled(manual) moveCallbacks=1 timersAfterCancellation=1 timersAfterClose=0
```

Вердикт: принято, Low, кодом. Перед `_accepted()` — та же проверка, что в ветке
новой группы: задача ещё в очереди, группа открыта. Тест на отмену из строки
`move`.

### L3. Исключение `drain` не дошло до dartdoc `run` и `cancellation.md`

**Нашёл:** Sol (D2). **Где:** dartdoc `Solo.run`;
`packages/solo/doc/cancellation.md`, «Three ways to stop».

M1 третьего ревью сделал так, что во время `drain` вызов `droppable` с живой
задачей того же ключа возвращает её; строку об этом получили dartdoc `add`
и `close`. Dartdoc `run` по-прежнему обещает на закрытом контроллере уже
кончившуюся `Cancelled(closed)`, и `cancellation.md` рядом с обещанием отменять
позднюю работу исключения не называет.

```text
drain: late load is the original job, Done(Ada Lovelace)
```

Вердикт: принято. По полуфразе в dartdoc `run` и в описании `drain`: новая
работа получает `Cancelled(closed)`, а `droppable` может вернуть ту, что уже
стоит; ссылка из строки `reference.md`.

### L4. Dartdoc `Solo.job`: «A rule error suppresses correction» шире правды

**Нашёл:** Sol (D3). **Где:** dartdoc `Solo.job`, абзац о том, когда
выполняются `ifFailed` и `ifCancelled`.

Ошибка правила при проверке права на коррекцию обработчиков действительно
не пускает. Но ошибка того же правила на `ctx.state` или `ctx.check()` выходит
в тело; не поймав её, тело кончается `Failed`, и `ifFailed` исправляет
состояние:

```text
outcome=Failed(Bad state: rule at checkpoint); corrected=true; state=corrected
```

Таблица «Handler eligibility and errors» на `state.md` говорит точно.

Вердикт: принято. Сузить фразу до ошибки на проверке права и назвать второй
путь — через тело в `ifFailed`.

### L5. README `flutter_solo`, «The controller's life»: `close()` упрощён

**Нашёл:** Astra (D2). **Где:** `packages/flutter_solo/README.md`, «The
controller's life».

«`close()` cancels whatever is queued or running, drops every listener and
stops notifying for good» скрывает два условия: идущая задача
с `cancellable: false` отказывается от отмены и может кончиться `Done`,
а слушатели снимаются в конце закрытия — между вызовом `close()` и его концом
уведомляют `ifCancelled` или тело защищённой задачи.

```text
CLOSE cancellable=true; after-call=[2]; outcome=Cancelled(closed); closed=true
CLOSE cancellable=false; after-call=[1]; outcome=Done(null); closed=true
```

Вердикт: принято. Разделить начало и конец закрытия, назвать
`cancellable: false`; подписки самого экрана снимает его `dispose`, ждать
`close()` для этого не нужно.

### L6. README `flutter_solo`, «Usage»: `ProfileApi` не объявлен

**Нашёл:** Astra (D3). **Где:** `packages/flutter_solo/README.md`, «Usage».

Первый полный пример показывает импорты, состояния, контроллер и виджет,
а `ProfileApi` с `fetchName` и `saveName` нигде не объявлен и не назван типом
приложения. Блок как есть даёт `Undefined class 'ProfileApi'.`
и `4 issues found.`; с двумя объявленными методами — `No issues found!`. Тесты
README подставляют свой `ProfileApi`, поэтому разрыва не видят.

Вердикт: принято. Короткий абстрактный класс с двумя сигнатурами в блоке или
фраза «`ProfileApi` — ваш сервис с `fetchName` и `saveName`» перед ним,
со ссылкой на запускаемый пример.

## Вопросы владельцу

1. Чинить ли M1 кодом `flutter_solo` и L2 кодом `solo` до выпуска 0.3.0. Обе
   правки внутренние, API не меняют.
2. Чинить ли пример `flutter_solo` (M2) — или считать, что пример держит один
   `api` на всю жизнь экрана, и сказать это в нём.
3. Чинить ли документы — L1, L3–L6 — одной волной вместе с документами ядра.
4. Брать ли что-то из советов по страницам — `errors.md`, `testing.md` `solo`,
   `mixins.md` — или оставить на после выпуска.
