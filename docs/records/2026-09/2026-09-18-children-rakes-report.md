> **Состояние на 2026-09-18:** сделано в ветке `docs/children`, коммиты
> `1e433af` и `b6afcdd`; владелец читает страницу, слияния нет.
> **Что это:** отчёт о вычитке `packages/async_job/doc/children.md` —
> четыре первых попытки, 13 сторожей с мутациями, снятое ложное
> утверждение.
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

## Проверки

В копии `~/development/my/solo-children` на ветке `docs/children`:
`dart analyze` в `packages/async_job` без замечаний, `dart test` — 446 зелёных,
`lib/` после мутаций побайтово совпадает с копией. Из корня копии:
`reflow.py --check`, `check_line_width.py`, `check_translations.py` (семнадцать
блоков и шестнадцать заголовков сходятся с переводом), `check_doc_shape.py` —
все зелёные.

## Что дальше

Владелец читает страницу. Слияние в `main` — после чтения, вместе с обновлением
шапки этой записи.
