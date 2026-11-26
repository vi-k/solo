> **Состояние на 2026-11-26:** черновик, вне пакетов и вне CI. Модель,
> настройки прогонов и зонды записаны здесь целиком; брать ли ступень 2
> в работу, владелец не решал.
> **Что это:** черновая модель правил ядра `async_job` на TLA+, прогоны
> проверщика TLC на ней, мутации модели и зонды сверки с кодом.
> **Связанные записи:** `2026-11-25-invariant-checking-plan.md` (три ступени
> и прототип ступени 1 на ядре).

# Черновик ступени 2: правила ядра на TLA+

Владелец посмотрел, что даёт ступень 2, и сказал: «делай черновик». План
описывает модель очереди и закрытия `solo`, но работа с 2026-11-25 сужена
до ядра («пока только async_job»). Поэтому черновик моделирует правила ядра:
отмену, секции `uncancellable`, `cancellable: false`, каскад к детям, ручной
`finish` движка, `abandonable` и освобождение значения. Очереди `solo` в модели
нет.

## Что в модели

Задачи: корень `r`, его ребёнок `a`, а при `DEPTH = 2` ещё и `b`, ребёнок `a`.
Кода тел нет: тело — последовательность вызовов контекста, и TLC перебирает их
во всех порядках вместе с отменами снаружи. Флаг `cancellable` каждой задачи
выбирается в начальном состоянии, так что перебор идёт по всем сочетаниям.

Переходы:

- старт корня и запуск ребёнка; на отменённом родителе ребёнок кончается
  `Cancelled`, не начавшись;
- отмена запросом, которой задача может отказать, и отмена правилом, которой
  не может; доставка отмены из каскада родителя;
- открытие и закрытие секции `uncancellable`, одной на тело; закрытие принимает
  придержанную отмену;
- вызов `abandonable` и приход его значения, один на тело;
- конец тела значением или брошенной отменой, ожидание детей, уборка;
- ручной `finish` движка с любым исходом и `finish` из каскада собственной
  отмены задачи — случай правки 2026-11-26.

Упрощения. Ошибка тела кончает задачу по всем правилам модели так же, как
значение, поэтому модель держит одно. Справедливость: тела и действия
кончаются, доставка отмены, закрытие секции и уборка не застревают; на этом
допущении стоит свойство `Termination`.

Источники правил: `doc/cancellation.md`, `doc/children.md`, раздел «Finishing a
job by hand» `doc/extending.md`, `doc/cleanup-rules.md`, инварианты 3 и 9
`docs/architecture.md`.

## Инварианты

| Инвариант | Правило |
|---|---|
| `MarkDecides` | отменённая задача кончается `Cancelled`, что бы ни вернуло тело или `finish` (инвариант 3) |
| `SectionHolds` | открытая секция придерживает запрос; отметить задачу в ней может только правило или отмена, брошенная самим телом (инвариант 9) |
| `RefusalHolds` | `cancellable: false` после старта отказывает всякому запросу |
| `ParentAfterChildren` | родитель кончается после всех начатых детей, если движок не кончил его руками |
| `OnCancelOnce`, `OnCancelRan` | `onCancel` бежит один раз и на каждой задаче, принявшей отмену, кроме кончённых руками |
| `ReleasedOnce`, `ValueReleased` | значение, пришедшее к задаче, освобождается ровно раз |
| `NoStateErrorOnCancelled` | вызов на отменённой задаче слышит отмену, а не «задача кончилась» (правка 2026-11-26) |
| `AbandonableEndsAtOnce` | `abandonable` при отмене «stops waiting for it and throws Cancelled at once» — таблица `doc/cancellation.md` |
| `Termination` | каждая задача кончается и каждое тело останавливается, если тела и действия кончаются |

`AbandonableEndsAtOnce` проверяется отдельной настройкой `doc.cfg`: на нынешних
правилах он красный, о нём ниже.

## Прогоны

Две задачи (`DEPTH = 1`): 263 205 различных состояний, глубина 19. Инварианты
проходят за 2 с, вместе с `Termination` — за 7 с. Всё зелёное.

Три задачи (`DEPTH = 2`), только инварианты: за 27 минут перебор нашёл 107 млн
различных состояний без единого нарушения, а в очереди оставалось ещё 22,5 млн;
прогон остановлен, не дойдя до конца. Первый прогон на трёх задачах вместе
с `Termination`, когда ошибка тела ещё была отдельным исходом, за 10 минут
набрал 2,8 ГБ графа живости и был остановлен.

## Мутации

Правило модели ломается константой `MUT`, и прогон обязан покраснеть на своём
инварианте. Все на двух задачах; «шагов» — длина трассы TLC вместе с начальным
состоянием.

| `MUT` | Что сломано | Ловит | Шагов |
|---|---|---|---|
| `sectionNoHold` | секция не придерживает запрос | `SectionHolds` | 4 |
| `refusalIgnored` | `cancellable: false` не отказывает | `RefusalHolds` | 3 |
| `finishIgnoresMark` | `finish` ставит свой исход отменённой задаче | `MarkDecides` | 4 |
| `noWaitForChildren` | родитель не ждёт детей | `ParentAfterChildren` | 6 |
| `waitForUnstarted` | родитель ждёт ребёнка, которого никто не запустит | `ParentAfterChildren`; `Termination` в прогоне живости | 2 |
| `lateValueKept` | брошенное значение, пришедшее поздно, не освобождается | `ValueReleased` | 8 |
| `lateValueStacked` | брошенное значение и освобождается, и ложится на стек уборки | `ReleasedOnce` | 8 |
| `skipOnCancel` | принятая отмена не зовёт `onCancel` | `OnCancelRan` | 5 |
| `acceptTwice` | повторная отмена принимается снова | `OnCancelOnce` | 4 |

Каждый инвариант ловит хотя бы одну мутацию. `FIXED = FALSE` возвращает ядро
до правки 2026-11-26 (`before.cfg`), и `NoStateErrorOnCancelled` краснеет
трассой в пять шагов: тот самый `StateError`, который правка убрала.

## Что нашёл TLC

Нового о ядре — ничего. Единственное противоречие правил в модели —
`AbandonableEndsAtOnce`, и оно уже записано в конце раздела «Нацеленные тесты
на 20 мест» `2026-11-25-invariant-checking-plan.md`. Трасса в четыре шага:

```text
State 1: <Initial predicate> | canc=[r |-> TRUE, a |-> TRUE]
State 2: <StartRoot | phase=[r |-> "body", a |-> "idle"]; bodyLive=[r |-> TRUE, a |-> FALSE]
State 3: <AbCall | ab=[r |-> "waiting", a |-> "none"]; abFlight=[r |-> TRUE, a |-> FALSE]
State 4: <FinishInCascade | phase=[r |-> "finished", a |-> "unused"]; outcome=[r |-> "Cancelled", a |-> "none"]; marked=[r |-> "request", a |-> "no"]; byHand=[r |-> TRUE, a |-> FALSE]
```

Движок кончает корень из каскада его отмены, пока тело ждёт `abandonable`.
`finish` не зовёт `onCancel`, а гонка `abandonable` — один из этих колбэков,
поэтому тело ждёт, пока действие вернёт значение, хотя таблица обещает конец
ожидания сразу. TLC вывел это из одних правил за доли секунды; сессия того же
дня пришла к нему нацеленным тестом на мутанта `job_context.dart:1095`.

Ещё две ошибки нашлись в самой модели, обе в правиле «ребёнок, не начатый
к концу тела, не запустится». Сперва его не было в ветке «отменена до старта»:
корень кончался, а ребёнок оставался ждать старта, и краснел
`ParentAfterChildren`. Потом оно снимало детей, но не внуков, и краснело
`Termination`. Это ошибки пересказа доков, а не ядра.

## Сверка с кодом

Модель отвечает и там, где доки говорят мало: отмена, пришедшая во время уборки
или ожидания детей, принимается, если задача её принимает, и решает исход. Три
зонда на копии ядра с правкой 2026-11-26 сверили это с кодом.

```dart
import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  for (final cancellable in [true, false]) {
    test('a cancel that comes while the cleanup of a job that returned runs, '
        'cancellable: $cancellable', () {
      final seen = <String>[];
      fakeAsync((async) {
        final gate = Completer<void>();
        final job = Job<String>(cancellable: cancellable, (ctx) async {
          ctx.onCancel(() => seen.add('onCancel'));
          ctx.onDispose(() async {
            seen.add('cleanup starts');
            await gate.future;
            seen.add('cleanup ends');
          });
          return 'v';
        });
        async.flushMicrotasks();
        seen.add('cancel');
        job.cancel().then((_) => seen.add('cancel returned')).ignore();
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();
        seen.add('outcome ${job.outcome}');
      });
      print(seen);
    });
  }

  test('a cancel while a job that returned waits for its child', () {
    final seen = <String>[];
    fakeAsync((async) {
      final gate = Completer<void>();
      final job = Job<String>((ctx) async {
        ctx.onCancel(() => seen.add('onCancel'));
        ctx
            .run(Job.deferred<void>((c) => c.join(() => gate.future)))
            .ignore();
        return 'v';
      });
      async.flushMicrotasks();
      seen.add('cancel');
      job.cancel().ignore();
      async.flushMicrotasks();
      gate.complete();
      async.flushMicrotasks();
      seen.add('outcome ${job.outcome}');
    });
    print(seen);
  });
}
```

```text
[cleanup starts, cancel, onCancel, cleanup ends, cancel returned, outcome Cancelled(manual)]
[cleanup starts, cancel, cleanup ends, cancel returned, outcome Done(v)]
[cancel, onCancel, outcome Cancelled(manual)]
```

Модель даёт то же: отмена в фазе уборки или ожидания детей отмечает задачу
с `cancellable: true`, зовёт `onCancel` и делает исход `Cancelled`;
с `cancellable: false` отвергается, и исход остаётся `Done`.

Третий зонд — `onDiscard` под медленным `onDispose`, отмена во время уборки:

```text
[dispose starts, dispose ends, outcome Done(v)]
[dispose starts, cancel, dispose ends, discard runs, outcome Cancelled(manual)]
```

`discard` бежит вторым проходом после `dispose`, как говорит
`doc/cleanup-rules.md`. В модели `discard` нет; зонд показывает, что правило
второго прохода в код дошло.

## Чего модель не видит

- Dart-код. Модель проверяет, что правила не противоречат друг другу; сверка
  с кодом — ступень 3, здесь её заменяют три зонда.
- `discard` и второй проход уборки, группы `runAll` и `each`, `join`, `pause`,
  `check`, дедлайны, порядок микрозадач, `onError` и зону, несколько вызовов
  `abandonable` и секций на тело.
- Размер: третья задача уже даёт больше 107 млн состояний, и перебор за 27
  минут не кончился. Четвёртая задача или второй вызов на тело без сужения
  в разумное время не пройдут.

## Вывод

Модель на 344 строки проверяет на двух задачах за секунды девять инвариантов
ядра и его живость, и у каждого инварианта есть мутация, которую он ловит.
Нового о ядре она не нашла: её единственное противоречие правил сессия нашла
тем же днём тестами. Правила ядра уже плотно вычитаны тестами и ревью, и модель
на них подтверждает, а не находит. Если брать ступень 2 всерьёз, то на очереди
`solo`, как и предлагал план: там главный риск — порядок событий между линиями,
политиками и закрытием.

## Как запустить

TLC 2.19 (`tla2tools.jar` от 8 августа 2024), Java из Homebrew. Модель лежит
в `Core.tla`, рядом настройки `<имя>.cfg`; из их каталога:

```sh
java -XX:+UseParallelGC -cp tla2tools.jar tlc2.TLC -workers auto -deadlock \
  -metadir ./states -config main.cfg Core.tla
```

`-deadlock` выключает проверку тупиков: законченная модель стоит на месте,
и это не тупик. Настройка `main.cfg`:

```text
SPECIFICATION Spec
CONSTANTS FIXED = TRUE
          DEPTH = 1
          MUT = "none"
INVARIANTS MarkDecides SectionHolds RefusalHolds ParentAfterChildren OnCancelOnce OnCancelRan ReleasedOnce ValueReleased NoStateErrorOnCancelled
PROPERTY Termination
```

Остальные настройки отличаются от неё одной-двумя строками: `doc.cfg` проверяет
только `AbandonableEndsAtOnce`, `before.cfg` ставит `FIXED = FALSE`,
`mut_<имя>.cfg` — `MUT = "<имя>"` без `PROPERTY`, `DEPTH = 2` — три задачи.

## Текст модели

```tla
------------------------------ MODULE Core ------------------------------
(* Rules of the async_job core, as its pages state them, for a root r,    *)
(* its child a and, at DEPTH 2, a's child b. No code of bodies: a body is *)
(* sequence of context calls chosen by the checker in every order.         *)
(*                                                                          *)
(* Sources: doc/cancellation.md (checkpoints, sections, cancellable:false), *)
(* doc/children.md (cascade, parent ends after children), doc/extending.md *)
(* "Finishing a job by hand" (finish waits for no children, runs no        *)
(* onCancel, unwinds nothing; an accepted cancellation keeps the outcome), *)
(* docs/architecture.md invariants 3 and 9.                                *)
EXTENDS Naturals

CONSTANTS FIXED,  \* the abandonable fix of 2026-11-26 is in
          MUT,    \* a rule broken on purpose, or "none"
          DEPTH   \* 1: r and its child a; 2: also a's child b

Jobs == IF DEPTH = 2 THEN {"r", "a", "b"} ELSE {"r", "a"}
Par(j) == CASE j = "a" -> "r" [] j = "b" -> "a" [] OTHER -> "none"
Kids(j) == {c \in Jobs : Par(c) = j}
Running == {"body", "children", "cleanup"}
Over == {"finished", "unused"}

VARIABLES
  phase,     \* idle | body | children | cleanup | finished | unused
  canc,      \* cancellable, fixed per job by the constructor
  marked,    \* who made the job cancelled: no | pre | request | rule | self
  held,      \* a request held by an open section
  section,   \* an uncancellable section is open
  secUsed,   \* the body has opened its one section
  bodyLive,  \* the body still runs, also after a finish by hand
  bodyEnd,   \* none | value | cancel (an error ends the job as a value
             \* does for every rule here, so the model keeps one)
  outcome,   \* none | Done | Failed | Cancelled
  byHand,    \* an engine ended the job with finish
  onCancel,  \* how many times the onCancel callbacks ran
  ab,        \* the one abandonable call: none | waiting | gotValue
             \*   | gotCancelled | gotStateError
  abFlight,  \* its action still runs
  resHeld,   \* the value it gave the body is on the cleanup stack
  released,  \* how many times that value was released
  req        \* a cancellation from the parent's cascade on its way

vars == <<phase, canc, marked, held, section, secUsed, bodyLive, bodyEnd,
          outcome, byHand, onCancel, ab, abFlight, resHeld, released, req>>

Init ==
  /\ phase = [j \in Jobs |-> "idle"]
  /\ canc \in [Jobs -> BOOLEAN]
  /\ marked = [j \in Jobs |-> "no"]
  /\ held = [j \in Jobs |-> FALSE]
  /\ section = [j \in Jobs |-> FALSE]
  /\ secUsed = [j \in Jobs |-> FALSE]
  /\ bodyLive = [j \in Jobs |-> FALSE]
  /\ bodyEnd = [j \in Jobs |-> "none"]
  /\ outcome = [j \in Jobs |-> "none"]
  /\ byHand = [j \in Jobs |-> FALSE]
  /\ onCancel = [j \in Jobs |-> 0]
  /\ ab = [j \in Jobs |-> "none"]
  /\ abFlight = [j \in Jobs |-> FALSE]
  /\ resHeld = [j \in Jobs |-> FALSE]
  /\ released = [j \in Jobs |-> 0]
  /\ req = [j \in Jobs |-> FALSE]

(* Descendants not started when a body is over will never start.        *)
Desc(j) == Kids(j) \cup UNION {Kids(k) : k \in Kids(j)}
DropIdleKids(j, ph) ==
  [c \in Jobs |-> IF c \in Desc(j) /\ ph[c] = "idle"
                       /\ MUT # "waitForUnstarted"
                    THEN "unused" ELSE ph[c]]

(* Accepting a cancellation: the job is marked, its onCancel callbacks run *)
(* (the race of a waiting abandonable is one of them), and the cascade     *)
(* goes to every started child. r is the request map to build on.         *)
Accept(j, who, r) ==
  /\ marked' = [marked EXCEPT ![j] = who]
  /\ onCancel' = [onCancel EXCEPT ![j] =
                     @ + (IF MUT = "skipOnCancel" THEN 0 ELSE 1)]
  /\ ab' = IF ab[j] = "waiting" THEN [ab EXCEPT ![j] = "gotCancelled"] ELSE ab
  /\ req' = [c \in Jobs |->
               IF c \in Kids(j) /\ phase[c] \in Running THEN TRUE ELSE r[c]]
  /\ held' = [held EXCEPT ![j] = FALSE]

AcceptVars == <<marked, onCancel, ab, req, held>>
Rest(vs) == UNCHANGED vs

(* A cancellation reaching job j. rej: the job may refuse it.             *)
Receive(j, rej, who, r) ==
  \/ /\ phase[j] = "idle"
     \* Before the start there is nothing to cut: cancellable is not asked.
     /\ phase' = DropIdleKids(j, [phase EXCEPT ![j] = "finished"])
     /\ outcome' = [outcome EXCEPT ![j] = "Cancelled"]
     /\ marked' = [marked EXCEPT ![j] = "pre"]
     /\ req' = r
     /\ UNCHANGED <<canc, held, section, secUsed, bodyLive, bodyEnd, byHand,
                    onCancel, ab, abFlight, resHeld, released>>
  \/ /\ phase[j] \in Running
     /\ marked[j] = "no"
     /\ \/ /\ rej /\ ~canc[j] /\ MUT # "refusalIgnored"
           /\ req' = r
           /\ UNCHANGED <<phase, canc, marked, held, section, secUsed,
                          bodyLive, bodyEnd, outcome, byHand, onCancel, ab,
                          abFlight, resHeld, released>>
        \/ /\ rej /\ section[j] /\ (canc[j] \/ MUT = "refusalIgnored")
           /\ MUT # "sectionNoHold"
           /\ held' = [held EXCEPT ![j] = TRUE]
           /\ req' = r
           /\ UNCHANGED <<phase, canc, marked, section, secUsed, bodyLive,
                          bodyEnd, outcome, byHand, onCancel, ab, abFlight,
                          resHeld, released>>
        \/ /\ ~rej \/ ((canc[j] \/ MUT = "refusalIgnored")
                       /\ (~section[j] \/ MUT = "sectionNoHold"))
           /\ Accept(j, who, r)
           /\ UNCHANGED <<phase, canc, section, secUsed, bodyLive, bodyEnd,
                          outcome, byHand, abFlight, resHeld, released>>
  \/ /\ phase[j] \in Running /\ marked[j] # "no" /\ MUT = "acceptTwice"
     /\ Accept(j, who, r)
     /\ UNCHANGED <<phase, canc, section, secUsed, bodyLive, bodyEnd,
                    outcome, byHand, abFlight, resHeld, released>>
  \/ /\ (phase[j] \in Over \/ (phase[j] \in Running /\ marked[j] # "no"))
     /\ req' = r
     /\ UNCHANGED <<phase, canc, marked, held, section, secUsed, bodyLive,
                    bodyEnd, outcome, byHand, onCancel, ab, abFlight, resHeld,
                    released>>

StartRoot ==
  /\ phase["r"] = "idle"
  /\ phase' = [phase EXCEPT !["r"] = "body"]
  /\ bodyLive' = [bodyLive EXCEPT !["r"] = TRUE]
  /\ UNCHANGED <<canc, marked, held, section, secUsed, bodyEnd, outcome,
                 byHand, onCancel, ab, abFlight, resHeld, released, req>>

(* The body is free to make a call: not waiting in abandonable.           *)
Free(j) == phase[j] = "body" /\ bodyLive[j] /\ ab[j] # "waiting"

RunChild(c) ==
  LET p == Par(c) IN
  /\ c # "r" /\ Free(p) /\ phase[c] = "idle"
  /\ IF marked[p] # "no"
       \* ctx.run on a cancelled job throws, and the core cancels the child
       \* it turned away.
       THEN /\ phase' = DropIdleKids(c, [phase EXCEPT ![c] = "finished"])
            /\ outcome' = [outcome EXCEPT ![c] = "Cancelled"]
            /\ marked' = [marked EXCEPT ![c] = "pre"]
            /\ UNCHANGED bodyLive
       ELSE /\ phase' = [phase EXCEPT ![c] = "body"]
            /\ bodyLive' = [bodyLive EXCEPT ![c] = TRUE]
            /\ UNCHANGED <<outcome, marked>>
  /\ UNCHANGED <<canc, held, section, secUsed, bodyEnd, byHand, onCancel, ab,
                 abFlight, resHeld, released, req>>

UserCancel(j) == Receive(j, TRUE, "request", req)
RuleCancel(j) == Receive(j, FALSE, "rule", req)
Deliver(c) == req[c] /\ Receive(c, TRUE, "request", [req EXCEPT ![c] = FALSE])

OpenSection(j) ==
  /\ Free(j) /\ ~section[j] /\ ~secUsed[j] /\ marked[j] = "no"
  /\ section' = [section EXCEPT ![j] = TRUE]
  /\ secUsed' = [secUsed EXCEPT ![j] = TRUE]
  /\ UNCHANGED <<phase, canc, marked, held, bodyLive, bodyEnd, outcome, byHand,
                 onCancel, ab, abFlight, resHeld, released, req>>

CloseSection(j) ==
  /\ section[j] /\ bodyLive[j] /\ ab[j] # "waiting"
  /\ section' = [section EXCEPT ![j] = FALSE]
  /\ IF held[j] /\ marked[j] = "no" /\ phase[j] \in Running
       THEN Accept(j, "request", req)
       ELSE /\ held' = [held EXCEPT ![j] = FALSE]
            /\ UNCHANGED <<marked, onCancel, ab, req>>
  /\ UNCHANGED <<phase, canc, secUsed, bodyLive, bodyEnd, outcome, byHand,
                 abFlight, resHeld, released>>

AbCall(j) ==
  /\ Free(j) /\ ab[j] = "none" /\ marked[j] = "no"
  /\ ab' = [ab EXCEPT ![j] = "waiting"]
  /\ abFlight' = [abFlight EXCEPT ![j] = TRUE]
  /\ UNCHANGED <<phase, canc, marked, held, section, secUsed, bodyLive,
                 bodyEnd, outcome, byHand, onCancel, resHeld, released, req>>

(* The action of abandonable returns its value.                           *)
AbValue(j) ==
  /\ abFlight[j]
  /\ abFlight' = [abFlight EXCEPT ![j] = FALSE]
  /\ CASE ab[j] = "waiting" /\ phase[j] # "finished" ->
            \* The body takes the value; its dispose goes on the stack.
            /\ ab' = [ab EXCEPT ![j] = "gotValue"]
            /\ resHeld' = [resHeld EXCEPT ![j] = TRUE]
            /\ UNCHANGED released
       [] ab[j] = "waiting" /\ phase[j] = "finished" ->
            \* Finished by hand while the call was in flight: the value is
            \* released, and the body hears the cancellation (since the fix)
            \* or that the job is over.
            /\ ab' = [ab EXCEPT ![j] = IF marked[j] # "no" /\ FIXED
                                          THEN "gotCancelled"
                                          ELSE "gotStateError"]
            /\ released' = [released EXCEPT ![j] = @ + 1]
            /\ UNCHANGED resHeld
       [] OTHER ->
            \* Abandoned: the value that comes late reaches nobody.
            /\ released' = [released EXCEPT ![j] =
                              @ + (IF MUT = "lateValueKept" THEN 0 ELSE 1)]
            /\ resHeld' = [resHeld EXCEPT ![j] =
                             @ \/ (MUT = "lateValueStacked"
                                   /\ phase[j] \in Running)]
            /\ UNCHANGED ab
  /\ UNCHANGED <<phase, canc, marked, held, section, secUsed, bodyLive,
                 bodyEnd, outcome, byHand, onCancel, req>>

BodyEnd(j, res) ==
  /\ bodyLive[j] /\ ab[j] # "waiting" /\ ~section[j]
  /\ bodyLive' = [bodyLive EXCEPT ![j] = FALSE]
  /\ bodyEnd' = [bodyEnd EXCEPT ![j] = res]
  /\ IF phase[j] = "body"
       THEN /\ phase' = DropIdleKids(j, [phase EXCEPT ![j] = "children"])
            /\ IF res = "cancel" /\ marked[j] = "no"
                 \* A body that throws Cancelled cancels its job: no section
                 \* or cancellable:false holds back what the body throws.
                 THEN Accept(j, "self", req)
                 ELSE UNCHANGED AcceptVars
       ELSE /\ UNCHANGED phase
            /\ UNCHANGED AcceptVars
  /\ UNCHANGED <<canc, section, secUsed, outcome, byHand, abFlight, resHeld,
                 released>>

ChildrenDone(j) ==
  /\ phase[j] = "children"
  /\ MUT = "noWaitForChildren" \/ \A c \in Kids(j) : phase[c] \in Over
  /\ phase' = [phase EXCEPT ![j] = "cleanup"]
  /\ UNCHANGED <<canc, marked, held, section, secUsed, bodyLive, bodyEnd,
                 outcome, byHand, onCancel, ab, abFlight, resHeld, released,
                 req>>

Cleanup(j) ==
  /\ phase[j] = "cleanup"
  /\ phase' = [phase EXCEPT ![j] = "finished"]
  /\ released' = [released EXCEPT ![j] = @ + (IF resHeld[j] THEN 1 ELSE 0)]
  /\ outcome' = [outcome EXCEPT ![j] =
                   IF marked[j] # "no" THEN "Cancelled"
                   ELSE IF bodyEnd[j] = "value" THEN "Done" ELSE "Failed"]
  /\ UNCHANGED <<canc, marked, held, section, secUsed, bodyLive, bodyEnd,
                 byHand, onCancel, ab, abFlight, resHeld, req>>

(* An engine ends a running job with finish: no children waited for, no   *)
(* onCancel, no cleanup. An accepted cancellation keeps the outcome.      *)
EngineFinish(j, o) ==
  /\ phase[j] \in Running
  /\ phase' = DropIdleKids(j, [phase EXCEPT ![j] = "finished"])
  /\ byHand' = [byHand EXCEPT ![j] = TRUE]
  /\ outcome' = [outcome EXCEPT ![j] =
                   IF marked[j] # "no" /\ MUT # "finishIgnoresMark"
                     THEN "Cancelled" ELSE o]
  /\ section' = [section EXCEPT ![j] = FALSE]
  /\ held' = [held EXCEPT ![j] = FALSE]
  /\ UNCHANGED <<canc, marked, secUsed, bodyLive, bodyEnd, onCancel, ab,
                 abFlight, resHeld, released, req>>

(* The same, from inside the cascade of the job's own cancellation: the   *)
(* job is marked and its children told, and finish drops the onCancel     *)
(* callbacks before the pass reaches them.                                *)
FinishInCascade(j) ==
  /\ phase[j] \in Running /\ marked[j] = "no" /\ canc[j] /\ ~section[j]
  /\ marked' = [marked EXCEPT ![j] = "request"]
  /\ req' = [c \in Jobs |->
               IF c \in Kids(j) /\ phase[c] \in Running THEN TRUE ELSE req[c]]
  /\ phase' = DropIdleKids(j, [phase EXCEPT ![j] = "finished"])
  /\ byHand' = [byHand EXCEPT ![j] = TRUE]
  /\ outcome' = [outcome EXCEPT ![j] = "Cancelled"]
  /\ UNCHANGED <<canc, held, section, secUsed, bodyLive, bodyEnd, onCancel, ab,
                 abFlight, resHeld, released>>

Next ==
  \/ StartRoot
  \/ \E j \in Jobs :
       \/ RunChild(j) \/ UserCancel(j) \/ RuleCancel(j) \/ Deliver(j)
       \/ OpenSection(j) \/ CloseSection(j) \/ AbCall(j) \/ AbValue(j)
       \/ \E res \in {"value", "cancel"} : BodyEnd(j, res)
       \/ ChildrenDone(j) \/ Cleanup(j)
       \/ \E o \in {"Done", "Cancelled"} : EngineFinish(j, o)
       \/ FinishInCascade(j)

Fairness ==
  /\ WF_vars(StartRoot)
  /\ \A j \in Jobs :
       /\ WF_vars(Deliver(j)) /\ WF_vars(CloseSection(j))
       /\ WF_vars(AbValue(j))
       /\ WF_vars(\E res \in {"value", "cancel"} : BodyEnd(j, res))
       /\ WF_vars(ChildrenDone(j)) /\ WF_vars(Cleanup(j))

Spec == Init /\ [][Next]_vars /\ Fairness

-----------------------------------------------------------------------------
(* Invariants, each with the rule it stands for.                          *)

\* Invariant 3: a cancelled job ends Cancelled, whatever the body or finish.
MarkDecides ==
  \A j \in Jobs : phase[j] = "finished" /\ marked[j] # "no"
                    => outcome[j] = "Cancelled"

\* Invariant 9: an open section holds a request back; only a rule the job
\* cannot refuse marks it there.
SectionHolds ==
  \A j \in Jobs : section[j] /\ marked[j] # "no"
                    => marked[j] \in {"rule", "self"}

\* Invariant 9: cancellable:false refuses every request once started.
RefusalHolds ==
  \A j \in Jobs : ~canc[j] => marked[j] \in {"no", "pre", "rule", "self"}

\* children.md: the parent ends after every child it started, unless an
\* engine finished it by hand.
ParentAfterChildren ==
  \A j \in Jobs : phase[j] = "finished" /\ ~byHand[j]
                    => \A c \in Kids(j) : phase[c] \in Over

\* onCancel runs once, and on every job that accepted a cancellation and
\* was not finished by hand.
OnCancelOnce == \A j \in Jobs : onCancel[j] <= 1
OnCancelRan ==
  \A j \in Jobs : phase[j] = "finished" /\ ~byHand[j]
                    /\ marked[j] \in {"request", "rule", "self"}
                    => onCancel[j] = 1

\* cleanup-rules.md: a value that came to the job is released once.
ReleasedOnce == \A j \in Jobs : released[j] <= 1
ValueReleased ==
  \A j \in Jobs : phase[j] = "finished" /\ ~byHand[j] /\ ~abFlight[j]
                    /\ ab[j] \in {"gotValue", "gotCancelled"}
                    => released[j] = 1

\* The fix: a call in flight on a cancelled job hears the cancellation,
\* never that the job is over.
NoStateErrorOnCancelled ==
  \A j \in Jobs : ab[j] = "gotStateError" => marked[j] = "no"

\* cancellation.md table: on cancellation abandonable "stops waiting for it
\* and throws Cancelled at once".
AbandonableEndsAtOnce ==
  \A j \in Jobs : marked[j] \in {"request", "rule", "self"}
                    => ab[j] # "waiting"

\* Every job ends and every body stops, if bodies and actions do.
Settled ==
  \A j \in Jobs : phase[j] \in Over /\ ~bodyLive[j] /\ ~abFlight[j]
Termination == <>[]Settled
=============================================================================
```
