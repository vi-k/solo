> **Состояние на 2026-09-18:** сделано в ветке `docs/children`, коммиты
> `1e433af` и `b6afcdd`; владелец читает страницу, слияния нет.
> **Что это:** отчёт о вычитке `packages/async_job/doc/children.md` —
> четыре первых попытки, 13 сторожей с мутациями, снятое ложное
> утверждение; в конце — правки по чтению владельца, включая абзац
> про стартовые правила в `packages/solo/doc/children.md`.
> **Связанные записи:** `2026-09-18-children-rakes-plan.md`,
> `2026-09-15[17]-async-job-project-review.md`,
> `2026-09-18[8]-cancellation-rakes-report.md`.

# Вычитка children.md

## Что стало со страницей

Было 374 строки, три раздела, семь блоков кода и ни одной первой попытки:
каждый раздел начинался с требования и сразу правильного кода, а оговорки шли
прозой. Стало 544 строки, шестнадцать заголовков, семнадцать блоков и таблица.
Четыре места, где ошибиться есть на чём, начинаются с версии, к которой ведёт
словарь самого API:

- **Ожидание нескольких детей.** Первая попытка — `Future.wait` над двумя
  `ctx.run`. Вторая — то же с `eagerError: true`. Решение — `.wait` с одним
  конвертом, и `ctx.runAll` там, где один отказ делает остальное бессмысленным.
- **Что группа отдаёт обратно.** Первая попытка —
  `ctx.wait(() => sources, discard: …)` для списка, уже лежащего на руках.
  Решение — `ctx.onDispose` или `ctx.onDiscard` следующей же строкой.
- **Обработка потоков.** Первая попытка — голый `await` в колбэке `each`.
  Решение — `child.join` на каждый шаг.
- **Цепочки.** Первая попытка — `ctx.run(tail)` для продолжения. Решение —
  ребёнком берётся только голова, хвост наблюдает вызывающий.

Прозой осталось то, где ошибаться не на чем: обычный `Job` вместо
`Job.deferred`, глубина дерева и переполнение стека, четыре обещания, которых
`runAll` не даёт. Ожидание соседа по группе там же и осталось: этот дедлок
нельзя показать кодом, который что-то печатает.

Находка ревью закрыта. Три сравнения `.wait`/`Future.wait`/`runAll`, которые
страница вела в трёх разных местах, сведены в один раздел и заканчиваются
таблицей на четыре формы. Разбор конверта стоит после примера с `.wait`,
а не до него.

## Ложное утверждение, которое сняли

Страница говорила про регистрацию списка после группы:

> `ctx.wait(() => value, discard: ...)` is not a substitute: it opens with its
> own checkpoint before the action ever runs, and a value already in hand has
> no action to lose it with, so it is never registered at all -- silently,
> with nothing on the debug channel to show for it.

Зонд говорит другое. Без висящей отмены форма работает: `discard`
регистрируется и выполняется при отмене, пришедшей позже.

```
== the list through ctx.wait
  the group returned [a, b]
  registered
  the parent is cancelled
  discard of wait closes [a, b]
  parent Cancelled(manual)
```

Узкий случай, о котором страница, видимо, и говорила, действительно есть, и он
в том же зонде. Если отмена пришла **раньше** этой строки, контрольная точка
`wait` бросает `Cancelled` до вызова действия, и список не регистрируется
вовсе:

```
== ctx.wait with a pending cancellation
  the group returned [a, b]
  the parent is cancelled while the body waits
  the body is back, and the parent is already cancelled: true
  the registration line threw Cancelled(manual)
  parent Cancelled(manual)
== ctx.onDiscard with a pending cancellation
  the group returned [a, b]
  the parent is cancelled while the body waits
  the body is back, and the parent is already cancelled: true
  registered
  onDiscard closes [a, b]
  parent Cancelled(manual)
```

Страница теперь говорит ровно это: форма почти всегда работает, а не переживает
она отмену, пришедшую до строки регистрации. Причина в тексте осталась той же —
контрольная точка раньше действия, — а вывод «не регистрируется вовсе» ушёл.
Слово «молча» тоже ушло: `wait` бросает, и вызывающий видит обычную отмену;
не объявляет никто именно утечку.

Из скилла `doc-reader`: цена второй версии проверяется прогоном. Здесь
проверкой поймано не сравнение, а само описание одной формы — писали его
по устройству движка, а не по прогону.

## Что ещё выяснили зондами

`Future.wait` с двумя ветвями, одна падает, другую отменяют. Исход родителя
решает то, чья беда пришла первой, — и это гонка, а не правило:

```
== Future.wait, failure arrives first
  parent Failed(Bad state: disk)
== Future.wait, cancellation arrives first
  parent Cancelled(handler: child stops: Cancelled(manual))
== .wait, failure arrives first
  parent Failed(ParallelWaitError(2 errors): Bad state: disk)
== .wait, cancellation arrives first
  parent Failed(ParallelWaitError(2 errors): Bad state: disk)
```

`eagerError: true` двигает только пробуждение тела, а конец задания — нет:

```
== Future.wait eagerError: true
  the first branch fails
  body wakes: StateError
  body returns
  the slow branch gets its handle
  the slow branch returns its handle
  parent Done(null)
```

В обеих формах `Future.wait` ручка, которую вернула удавшаяся ветка,
не закрывается никем: в трассе нет строки `handle closed`. Ветка кончилась
`Done` и отдала значение наружу, а тело его не получило.

Колбэк `each` на двух шагах: голый `await` доигрывает оба шага после отмены,
и уборка родителя ждёт весь колбэк; `child.join` выпускает отмену на втором
шаге:

```
== each with a plain await
  m1: first step
  the parent is cancelled
  the first step completes
  m1: second step
  the second step completes
  m1: callback done
  parent cleanup
== each through child.join
  m1: first step
  the parent is cancelled
  the first step completes
  parent cleanup
  the second step completes
```

`ctx.run` на продолжении: `ArgumentError: Invalid argument (child): A
continuation starts itself after its source finishes`. Текст ошибки
процитирован на странице.

## Сторожа

`packages/async_job/test/children_rakes_test.dart` — 13 тестов, по одному
на каждое утверждение, добавленное этой работой. Набор `async_job` стал 443.

Стенда у страницы нет — так решил владелец, выбирая объём. Поэтому код страницы
собран руками: все семнадцать блоков перенесены в один файл с заглушками
и проанализированы против дерева — ошибок нет. Эта сборка одноразовая
и в дереве не остаётся; при следующей правке страницы её придётся повторить или
завести стенд.

У каждого сторожа своя мутация движка, и каждая проверена прогоном: мутация
ставится на копию `lib/`, сторож гоняется один, файл возвращается из копии. Все
тринадцать краснеют:

| Сторож | Мутация |
| --- | --- |
| исход решает первая ошибка | отказ ветки доходит до тела завёрнутым |
| исход решает первая отмена | отмена ребёнка теряет `HandlerCancelReason` |
| ручку не закрывает никто | `discard` выполняется и при `Done` |
| `eagerError` двигает пробуждение | задание перестаёт ждать детей |
| конверт несёт отмену и значение | отменённый ребёнок выходит другим типом |
| `.wait` даёт один исход в любом порядке | любой конверт читается отменой |
| `wait` регистрирует без висящей отмены | `wait` не регистрирует значение |
| `wait` бросает при висящей отмене | `wait` открывается без проверки |
| `onDispose` регистрирует на помеченном | `onDispose` проверяет заранее |
| голый `await` доигрывает колбэк | ребёнок стрима не ждёт колбэк |
| `child.join` выпускает отмену | `join` возвращается без проверки |
| `ctx.run` отвергает продолжение | продолжение можно усыновить |
| родитель кончается раньше хвоста | источник не стартует продолжение |

Прогон мутаций — `.artifacts/2026-09-18-children/mutations.md`; раннер
и зонды — `packages/async_job/.artifacts/children/`. И то и другое вне гита
и снимается в конце работы.

## Правка по чтению владельца

Первый вопрос владельца по странице — про фразу в разделе «Children»:

> Ignoring the handle with `child.ignore()` alone does not handle errors of
> the `run` future; an unhandled future error, including cancellation,
> follows Dart's rules.

Причины в ней нет, а «недостаточно одного» ещё и мягче правды: рядом
с `ctx.run` вызов `child.ignore()` не делает ничего. Метод ставит флаг
`_observed` (`lib/src/job_base.dart`), по которому движок решает, слать ли
неувиденный `Failed` в зону создания задачи; но `run` внутри ждёт
`child.value`, а этот геттер ставит тот же флаг сам. Ошибка приходит не оттуда:
её несёт future, которую вернул `_awaitChild`, и погасить её может только
`ignore()` на ней самой. Зонд `probe_ignore.dart`:

| Сценарий | В зону ушло |
| --- | --- |
| `child.ignore(); ctx.run(child);`, ребёнок падает | `StateError` |
| `ctx.run(child);` без всякого `ignore` | `StateError` — ровно то же |
| `child.ignore(); ctx.run(child);`, ребёнка отменили | `Cancelled` |
| `ctx.run(child).ignore();` — оба случая | ничего |

Вторая строка и решает вопрос: с `child.ignore()` и без него в зоне одно
и то же. Фраза заменена на ту, что называет две разные ошибки: отчёт движка
об исходе, на который никто не посмотрел, и ошибку обычной future Dart.

Сторожа встали в `packages/async_job/test/zone_test.dart` рядом с «a run Future
nobody handles reports the child's failure», три теста и две мутации:

- `child.ignore()` не гасит future от `run`, и в зоне ровно одна ошибка.
  Мутация: убрать `_observed = true;` из геттера `value` — в зоне две.
- `ctx.run(child).ignore()` гасит её, и зона молчит. Та же мутация — в зоне
  появляется `StateError`.
- отмена ребёнка тоже уходит в зону через ту future. Мутация: ветка `Cancelled`
  в `value` бросает `StateError` — в зоне не отмена.

## Вторая правка по чтению: стартовые правила в `solo`

Следующие два вопроса владельца были уже про `packages/solo/doc/children.md`,
про абзац о ребёнке, которого отвернули стартовые правила: что значит «получает
родителя, уровень вложенности и наблюдателя», если он не запустится, и чья
ошибка в «ошибке стартового правила» — правила или отказа по правилу.

Абзац отвечал на оба вопроса неверно по акцентам. Усыновление в ядре идёт
до вопроса правилам: `startChild` ставит ребёнку `_parent`, уровень
и наблюдателя, и только потом зовёт `beforeChildStart`. Поэтому отказ — это
завершённая задача со своим местом в дереве: её исход приходит наблюдателю,
и `job.level` говорит тому, насколько она глубже родителя, а `child.done`
хранит отмену. Сам движок ничего не отступает — отступ `>` в журнале тестов
рисует `JournalObserver` по этому самому `level`; первая версия абзаца выдавала
его за свойство движка, и владелец на этом и споткнулся. В список ожидания
такой ребёнок не попадает, но future от `ctx.run` отмену несёт,
и неперехваченной она делает родителя `Cancelled(handler: …)`. Про наблюдателя
в `solo` добавить нечего: там каждая задача создаётся с наблюдателем
контроллера, поэтому из трёх вещей осталось две.

Второе предложение говорило про ошибку правила, а по-русски читалось как отказ
по правилу; вдобавок «стартовое правило» — это три разных проверки, и бросить
может только код вызывающего. Это разные исходы: отказ — `Cancelled`
с `RulesCancelReason` и без запуска тела, а брошенная правилом ошибка завершает
ребёнка `Failed`, и `ctx.run` бросает её синхронно — строка после вызова
не выполняется. Бросить могут `canStart` и `keepWhile`: `W` задачи — проверка
типа, и путь у неё один, отказ. Зонд `probe_start_rules.dart` показал все
исходы, у `canStart` и у `keepWhile` одинаково; синхронность видна по тому, что
присваивание сразу за `ctx.run` не произошло.

Абзац разбит на два и переписан, перевод следом. Сторожа —
`packages/solo/test/children_test.dart`, рядом с «a start rule of a child that
throws reaches the observer»:

- «a canStart that throws leaves ctx.run before it returns» и такой же
  на `keepWhile` — один тест на оба правила в цикле. Мутация: `rethrow`
  в `beforeChildStart` заменён на `return null` — строка после `ctx.run`
  выполняется, оба краснеют.
- «the Future of run carries the drop of a child nobody awaits». Мутация:
  проверка типа в `_rejectStart` возвращает `null` — future приходит `Done`.

Набор `solo` — 626 зелёных.

## Третья правка по чтению: почему ожидания контекстом колбэка

Страница говорила «Use the callback's context for waits; a plain `await` can
keep the child and parent alive indefinitely» — правило без причины, а причина
стоит строкой выше: отмена ждёт текущий колбэк, прежде чем завершить ребёнка.
Значит, длина колбэка и есть длина жизни ребёнка, а с ним и родителя.
`child.wait` заканчивается отменой в тот же миг, когда она пришла, и оставляет
действие доигрывать само; обычный `await` кончается только вместе со своей
future. Зонд `probe_each_wait.dart` на отмене родителя посреди колбэка
с задержкой в 1000 мс:

| Колбэк | Отмена пришла | Родитель завершился |
| --- | --- | --- |
| `await delay(1000)` | 50 мс | 1011 мс |
| `await child.wait(() => delay(1000))` | 50 мс | 55 мс |

Сторожа — два теста в `packages/solo/test/each_test.dart`, оба с мутациями:

- «a plain await in the callback holds the parent until it returns». Мутация:
  `await active;` в `job_stream.dart` закомментирован — родитель завершается
  раньше колбэка, и только этот тест краснеет.
- «child.wait in the callback ends the parent with the cancellation». Мутация:
  `onCancel` в `_race` больше не завершает completer — ожидание перестаёт
  кончаться отменой; краснеет и этот тест, и четыре соседних.

Набор `solo` — 628 зелёных.

## Четвёртая правка по чтению: причина и следствие у открытого стрима

«The parent waits for this child even without an explicit await, so an open
stream with no events still keeps the parent running» — владелец спросил,
не наоборот ли. Наоборот: ждёт родитель детей всегда, а работающим ребёнка
держит именно открытый источник. В одну фразу были сведены две разные вещи,
и «поэтому» стояло между ними неверно.

Теперь звенья названы по порядку: ребёнок `each` завершается, когда источник
пришлёт `onDone`, — значит, открытый стрим без событий это работающий ребёнок;
а детей родитель ждёт и без явного `await`, поэтому работает и он. Фраза про
`onDone` из последнего абзаца раздела при этом убрана: она теперь стоит там,
где объясняет.

Сторож — «a stream with no events at all still holds the parent»
в `packages/solo/test/each_child_test.dart`: тело родителя возвращается сразу,
событий нет вовсе, десять секунд спустя родитель всё ещё работает, а после
`source.close()` завершается `Done`. Обе мутации его красят, каждая со своей
стороны: `await _awaitChildren();` в `job_base.dart` закомментирован — родитель
перестаёт ждать; `onDone` в `job_stream.dart` возвращается сразу — ребёнок
не заканчивается и после закрытия источника.

Набор `solo` — 629 зелёных.

## Проверки

В копии `~/development/my/solo-children` на ветке `docs/children`:
`dart analyze` в `packages/async_job` без замечаний и `dart analyze lib test`
в `packages/solo` тоже, `dart test` — 446 в `async_job` и 629 в `solo`, `lib/`
после мутаций побайтово совпадает с копией. Из корня копии:
`reflow.py --check`, `check_line_width.py`, `check_translations.py` (семнадцать
блоков и шестнадцать заголовков сходятся с переводом), `check_doc_shape.py` —
все зелёные.

## Что дальше

Владелец читает страницу. Слияние в `main` — после чтения, вместе с обновлением
шапки этой записи.
