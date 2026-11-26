> **Состояние на 2026-11-27:** словарь перебора расширен `discard`,
> `uncancellable` без `await`, доменом с правилом в `check()` и ответами
> `onError`; перебор прогнан на тех же 20 местах, в пакет и в CI не вошёл, код
> целиком в конце записи. Пойманы четыре мутанта из 20 — M08, M11, M12, M19;
> все семь калибровочных поломок, три из них новые, ловятся за первые сотни
> путей. На чистом ядре нарушений нет; ложные тревоги по дороге оказались
> ошибками самих оракулов. Разбор непойманных: M13 эквивалентен; M10 зонд
> отличает, и на его месте ядро расходится с dartdoc `abandonable` — держатель
> брошенного вызова получает уже освобождённое значение вместо `Cancelled`.
> 2026-11-27 ядро поправлено, раздел «Правка M10»; в pub.dev уйдёт выпуском
> `async_job` 1.0.6. Третий порядок, ручной `finish` без отмены, не тронут.
> **Что это:** третий шаг перебора порядков на настоящем ядре: новые слова,
> оракулы к ним, прогон на 20 местах и разбор непойманных.
> **Связанные записи:** `2026-11-26-core-explorer-vocabulary-report.md`
> (второй шаг, оракулы 13–17 и прежние границы),
> `2026-11-26-core-exhaustive-explorer-report.md` (первый перебор, его
> устройство и оракулы 1–12), `2026-11-25-invariant-checking-plan.md` (план
> ступеней и 20 мест).

# Перебор порядков на ядре: домен, discard, секция без await

2026-11-26, по слову владельца «добавь discard и uncancellable без await,
добавь домен с правилом и onError». Ядро — `async_job` 1.0.5, `lib/` тот же,
что у второго шага, номера строк мутантов те же.

## Что добавлено

Устройство прежнее. Новые слова включаются тем же ключом:
`--with disc,loose,rule,answer`, вместе с прежними `aband,free,all,timeout`.
Без новых слов перебор даёт прежние числа: на границе A первого перебора те же
83 946 путей.

Шаги тела:

- `disc` — `ctx.join(..., discard: ...)` на воротах; бывает и в теле,
  и в работе `unattended`;
- `loose` — только в теле: `ctx.uncancellable(...)` без `await`, на воротах,
  чью ошибку никто не ждёт. Тело идёт дальше, секция живёт сама и может
  пережить задачу.

Домен. Задача — подкласс `JobBase`, чей контекст переопределяет `check()`:
`super.check()`, потом правило перебора. Правило открыто, пока не случится
событие «the rule closes»; оно доступно при `rule` и бюджет `--disrupt`
не тратит. Закрытое правило бросает `RuleError` из каждой проверки ядра.

Ответы. При `answer` ворота выбирают, чем падают:

- 0 — своей ошибкой `GateError`;
- 1 — конвертом `ParallelWaitError` с двумя ошибками x и y;
- 2–4 — конвертом `Shaky`, чей список ошибок на чётных и нечётных обходах
  разный: `[y, x]` и `[x, x]`, `[x, y]` и `[y, x]` с повтором впереди или
  позади.

`Job.isCancellationError` при `answer` называет отменой `StopError` — ошибку
ворот, которые закрылись отменой. Наблюдатель — `JobAnswerer`: ответы идут
в `onUnanswered`, и перебор считает их вместе с зоной.

`Shaky` — то, от чего защищается `_announce`: вердикты сопоставляются с обходом
`onError` по идентичности, каждый — один раз. Вид конверта решает: M11
не поймали ни `[x, y]` с `[x, x]`, ни `[x, x]` с `[x, y]`, а поймал `[x, x]`
при первом обходе и `[y, x]` при втором.

Ключ `--path a,b,c` проигрывает один путь с заданными выборами и печатает его
лог и сводку: так разбирались ложные тревоги. Выбор, которого на пути нет,
перебор называет в конце и выходит с кодом 2. Сам этот ключ поначалу не ставил
фильтр `isCancellationError`, и путь M12 на чистом ядре показал нарушение,
которого полный перебор не видел; фильтр теперь ставится до обоих режимов.
После итогового прогона мутантов правился только этот режим.

## Новые оракулы

Нумерация продолжает оракулы 1–17.

18. `discard`. Зарегистрированный ресурс освобождён ни разу, если задача
    кончилась `Done`, и один раз иначе. Ресурс, который ручной `finish` застал
    на стеке посреди размотки, освобождён ни разу, если ветка группы ещё
    не решила или тело уже вернуло значение, и один раз иначе.
19. Правило домена. `join`, `run` и `runAll` не отдают телу значение, пришедшее
    после того, как правило закрылось; работа `unattended` после конца тела
    и ручной `finish` — исключения ядра, оракул их пропускает. Пустая группа
    не бросает `RuleError`, если правило было открыто при вызове.
20. Ответы. На каждый сбой, кроме `Cancelled`, ответов не меньше, чем раз
    `onError` сказал `answered`, и — кроме сбоев внутри `Shaky` — не больше,
    чем `answered` и `later` вместе. Без ручного `finish` `onError` говорит
    `cancellation` ровно о `StopError` задачи, принявшей отмену.

Уточнены прежние:

- `shield` под отметкой отмены проверяется только у задачи, которая ещё
  не кончилась: секция `loose` переживает задачу;
- «отменена при живом теле — кончилась `Cancelled`» и то же о дедлайне — только
  когда нет живой секции `loose`: отмену, которую держит брошенная секция, ядро
  выбрасывает на кончившейся задаче, как пишет `job_base.dart:1494`;
- оракул 15 допускает группу, все ветки которой кончились `Done`, а бросила она
  `RuleError` своего владельца: фиксация зовёт `check()`;
- оракул 17 считает зону и `onUnanswered` вместе и пропускает сбой, который
  несёт исход — сам или внутри конверта, — и `StopError` задачи, принявшей
  отмену;
- оракул 10 пропускает `StopError`, `RuleError` и `ParallelWaitError` — ошибки
  ворот, которые никто не взял после ручного `finish`.

## Ложные тревоги

Каждая из них — ошибка оракула, а не ядра; разобраны через `--path`.

- `ParallelWaitError` в зоне: ворота открылись после ручного `finish`, их
  ошибку никто не взял. Та же история, что у `GateError` второго шага.
- Сбой внутри конверта не дошёл до зоны: его несёт исход `Failed`. Оракул 17
  научился смотреть внутрь.
- `StopError` у задачи, принявшей отмену, не дошёл никуда — ни до зоны,
  ни до ответа. Путь `root [wait value]`, ворота падают, `cancel j0` между
  микрозадачами:

  ```text
  told [j0 GateError(g0) later, j0 StopError(g0) later]
  answers [j0 GateError(g0)]
  ```

  Отмена пришла после того, как `onError` услышал сбой, и `later`
  не превратилось в ответ: сбой стал частью отмены. Оракул 17 теперь пропускает
  `StopError` задачи, которая кончилась `Cancelled`.

## Чистое ядро

У каждой границы `--depth 1 --disrupt 2`; число путей — на последней ступени
углубления.

| Граница | Словарь | Аргументы | Путей | Время | Память |
| --- | --- | --- | --- | --- | --- |
| DI | disc | `--steps 2 --jobs 2 --events 5` | 181 614 | 5,6 с | 32 МБ |
| LO | loose | `--steps 2 --jobs 2 --events 5` | 351 718 | 10,5 с | 47 МБ |
| RU | rule | `--steps 2 --jobs 2 --events 5` | 277 236 | 8,7 с | 34 МБ |
| AN | answer | `--steps 2 --jobs 2 --events 3` | 1 419 702 | 25,2 с | 49 МБ |
| DIA | disc, all | `--steps 1 --jobs 3 --events 4` | 261 892 | 8,8 с | 47 МБ |
| LOT | loose, timeout | `--steps 2 --jobs 2 --events 4` | 1 342 380 | 30,9 с | 50 МБ |
| RUF | rule, free | `--steps 2 --jobs 1 --events 4` | 61 814 | 1,2 с | 19 МБ |
| RUA | rule, all | `--steps 1 --jobs 2 --events 4 --preempt 1` | 60 602 | 1,3 с | 21 МБ |
| ANF | answer, free | `--steps 1 --jobs 3 --events 3 --preempt 1` | 35 694 | 0,7 с | 19 МБ |
| ANA | answer, all | `--steps 1 --jobs 3 --events 3` | 1 936 192 | 48,0 с | 50 МБ |
| DIAP | disc, all | `--steps 1 --jobs 3 --events 3 --preempt 1` | 1 640 984 | 36,7 с | 49 МБ |

Нарушений нет ни на одной. Время — весь процесс, со всеми ступенями углубления.
Слова дорогие: `answer` на работе `unattended` с двумя шагами не уложился
в десять минут даже на одном событии, поэтому граница ANF взята с одним шагом,
тремя задачами и вклиниванием; `rule` и `free` с двумя шагами тянутся только
на одной задаче.

Калибровка — все семь поломок пойманы. Прежние: K1 на DI, путь 8; K2 на DI,
путь 41; K3, дедлайн не отменяет задачу, на LOT, путь 829; K4, ошибка работы
`unattended` не объявляется, на RUF, путь 47. Новые:

- K5, `job_context.dart:784`, `discard` выполняется и на `Done`
  (`always: dispose != null` → `always: true`): путь 27 на DI,
  `root [disc value]` —
  `j0 finished Done(v0) with discard of resource 0 run 1 times`;
- K6, `job_context.dart:733`, `join` не проверяет домен после прихода значения:
  путь 9 на RU, `root [wait value]`, `the rule closes` —
  `j0: join handed over a value that came after the rule closed`;
- K7, `job_base.dart:1828`, вердикт всегда `answered`, фильтр не спрашивается:
  путь 20 на AN, `root [wait value]`, `cancel j0`, ворота падают конвертом —
  `j0: onError told answered of StopError(g0) (cancelled: true)`.

## Двадцать мест

Драйвер тот же, границы новые, первыми дешёвые: сначала пробы досягаемости,
потом мутант на всех одиннадцати границах.

| Мутант | Место | Правка | Досягаемо | Итог |
| --- | --- | --- | --- | --- |
| M01 | `job_base.dart:849` | `error is StackOverflowError && _outOfStack` → `_outOfStack` | нет | — |
| M02 | `job_context.dart:918` | без `error is StackOverflowError` | нет | — |
| M03 | `job_base.dart:2332` | `body is Failed && body.error is StackOverflowError` → `body is Failed` | нет | — |
| M04 | `job_base.dart:2358` | без `child.isFinished` | нет | — |
| M05 | `job_base.dart:2388` | `_status == JobStatus.created` → `false` | нет | — |
| M06 | `job_base.dart:970` | без `_isOwnTimeout(held)` | на DI | чист на всех одиннадцати |
| M07 | `job_base.dart:970` | без `!_isOwnTimeout(marked)` | на DI | чист на всех одиннадцати |
| M08 | `job_context.dart:702` | `_owner.bodyEnded && _inOwnFork` → `_inOwnFork` | на DI | пойман на RUF, путь 1 079 |
| M09 | `job_context.dart:1026` | `_owner.bodyEnded && !_inOwnFork` → `false` | нет | — |
| M10 | `job_context.dart:1095` | без `(fromFork \|\| !_owner.bodyEnded)` | нет | — |
| M11 | `job_base.dart:1686` | без `unmatched[i]` | на DI | пойман на AN, путь 62 |
| M12 | `job_base.dart:1686` | без `identical(verdicts[i].failure, failure)` | на DI | пойман на AN, путь 34 |
| M13 | `job_base.dart:2452` | без `identical(verdicts.error, outcome.error)` | на DI | чист на всех одиннадцати |
| M14 | `job_context.dart:1248` | `branches.isEmpty` → `false` | на DIA | чист на всех одиннадцати |
| M15 | `job_base.dart:2253` | `_cleanups.isEmpty && hold == null` → `false` | на DI | чист на всех одиннадцати |
| M16 | `job_base.dart:2628` | `if (child.isFinished)` → `if (false)` | на DIA | чист на всех одиннадцати |
| M17 | `job_base.dart:2150` | `if (isFinished)` → `if (false)` | на DI | чист на всех одиннадцати |
| M18 | `job_base.dart:2191` | `if (isFinished)` → `if (false)` | на DIA | чист на всех одиннадцати |
| M19 | `job_base.dart:2289` | `if (isFinished)` → `if (false)` | на DIA | пойман на DIAP, путь 15 845 |
| M20 | `job_base.dart:1532` | без `replaced == null` | на DI | чист на всех одиннадцати |

Пойманные:

- M08, `job_context.dart:702`: вызов из работы `unattended` при живом теле идёт
  веткой «работа после конца тела» и не проверяет домен. RUF, путь 1079:

  ```text
  root [free[wait value] wait value]
  the rule closes
  ```

  `join` работы отдал значение, пришедшее после того, как правило закрылось.
- M11, `job_base.dart:1686`: без `unmatched[i]` вердикт используется дважды.
  AN, путь 62: `root [wait value]`, `cancel j0`, ворота падают конвертом
  `Shaky` пятого вида — `GateError(g0) told answered 2 times, answered 1`.
- M12, `job_base.dart:1686`: без сверки по идентичности чужой вердикт достаётся
  первому сбою обхода. AN, путь 34: `root [wait value]`, `cancel j0`, ворота
  падают — `onError` сказал `cancellation` о `GateError`, хотя фильтр называет
  только `StopError`.
- M19, `job_base.dart:2289`: ручной `finish` ветки на втором барьере, и проход
  продолжается. DIAP, путь 15 845:

  ```text
  root [all([disc value]) value]
  finish j0 by hand cancelled
  open g0(disc of j1) value
  finish j1 by hand done  <- between microtasks
  ```

  Ресурс `disc` ветки освобождён после того, как движок кончил её руками.

Непойманные:

- M06 и M07, `job_base.dart:970`, — по чтению эквивалентны, и перебор с `loose`
  и дедлайном (LOT) этого не опроверг. M06 пишет `_heldBehindTimeout`, только
  когда удержанное — не дедлайн, а читается поле, только когда удержанное —
  дедлайн. M07 требует, чтобы второй запрос был своим дедлайном при удержанном
  дедлайне, а дедлайн у задачи один;
- M13, `job_base.dart:2452`, эквивалентен, см. «Разбор M10 и M13»;
- M14, `job_context.dart:1248`: пустая группа через `_RunAllGroup`. Асинхронная
  `_settle` без веток не встаёт ни на одном `await` и доходит до `_ctx.check()`
  синхронно, как `Future.sync` прямого пути. Разница — число микрозадач
  до значения;
- M15 и M16 — лишний проход и лишнее ожидание, только микрозадачи;
- M17 и M18 — как во втором шаге: на путях с ручным `finish` во время ожидания
  детей и на первом барьере ядро и мутант дают одно и то же;
- M10, `job_context.dart:1095`, на новых границах не достигнут: его место —
  в `aband`, а новые границы этого слова не берут. Во втором шаге оно было
  достигнуто, и мутант чист. Зонд его отличает, см. «Разбор M10 и M13»;
- M09 и M01–M05 не достигнуты, M20 эквивалентен по плану.

## Разбор M10 и M13

Разобраны после итогового прогона, по слову владельца «разбери M10 и M13».

### M13 эквивалентен

Мутант убирает из `_reportCovered` сверку
`identical(verdicts.error, outcome.error)`: вердикты тела шли бы к ответу
на любую ошибку исхода. Разойтись им не с чем. `_bodyVerdicts` пишет одно
место, `_announceBodyFailure` (`job_base.dart:2493`), и зовёт его одно место
в `_execute` (строка 2074) — в той же ветке, что ставит
`outcome = Failed(error, stackTrace)` с той же ошибкой. Локальное `outcome`
после этого не переписывается, и оба вызова `_reportCovered` с вердиктами —
строка 2248 и `_answerForHandFinished` на строке 2529 — получают именно его.
Сверка — страховка на будущее, а не ветка, которую можно пройти. Догадка первой
редакции этой записи, что расхождение даст уборка, которая бросает, неверна:
падение уборки исход тела не переписывает. Тот же вывод, с ещё одним звеном —
второй проход разорванного старта выходит раньше через `ignoreFailure`, — уже
стоял в `2026-11-25-invariant-checking-plan.md`, раздел «Нацеленные тесты на 20
мест»; этот разбор сделан, не заглянув туда, и его только повторяет.

### M10: значение брошенного вызова после ручного `finish` в отмене

Место — `_race` под `ctx.abandonable`, ветка «значение пришло, задача отмечена
отменённой, а колбэк гонки не слышал отмену». Ядро идёт в неё, только если ждёт
тело или работа `unattended`:
`pendingCancel != null && (fromFork || !_owner.bodyEnded)`. Тогда вызов
кончается отменой, как кончила бы его гонка. Если тело уже кончилось, ядро
считает, что значения не ждёт никто, и идёт в `_keepLate`: на кончившейся
задаче освобождает значение и отдаёт его в будущее вызова. Мутант пускает
в первую ветку и тело, которое кончилось.

Колбэк гонки не слышит отмену, когда движок кончает задачу руками, пока отмена
спускается к детям: `cancelWith` зовёт `_cascadeToChildren`,
а `_markCancelled` — только если задача ещё не кончена. Чтобы отличить мутанта,
нужны четыре вещи сразу: тело ушло от `abandonable`, но его будущее кто-то
держит; задача жива после тела, потому что ждёт ребёнка; `onCancel` ребёнка
кончает родителя руками; значение приходит после этого. В словаре перебора нет
ни ухода от `abandonable` с удержанием будущего, ни ручного `finish` из колбэка
ребёнка, поэтому место не достигается даже там, где есть `aband`.

Зонд — тест против `package:async_job/engine.dart`, в трёх порядках:

```dart
import 'dart:async';

import 'package:async_job/engine.dart';
import 'package:test/test.dart';

final class PJob<T> extends JobBase<T> implements ChildJob<T> {
  PJob(this._body);
  final Future<T> Function(JobContext ctx) _body;

  void launch() => start();

  void drop(Outcome<T> outcome) => finish(outcome);

  @override
  JobContextBase createContext() => PContext(this);

  @override
  Future<T> execute(covariant PContext ctx) => _body(ctx);
}

final class PContext extends JobContextBase {
  PContext(super.owner);
}

/// The holder of the future of an `abandonable` the body walked away from:
/// what does it get when the value comes after the job was cancelled
/// (`cascade-plain`), cancelled and finished by hand in the cascade
/// (`cascade-hand`), or finished by hand with no cancellation
/// (`hand-no-cancel`)?
Future<(Object?, List<String>)> scenario(String mode) async {
  final log = <String>[];
  final gate = Completer<String>();
  final forever = Completer<void>();
  late Future<String> held;
  late PJob<String> parent;
  parent = PJob<String>((ctx) async {
    // A child keeps the job alive past its body. Its `onCancel` runs in the
    // cascade, before the callbacks of the parent.
    ctx.start(
      PJob<void>((c) async {
        c.onCancel(() {
          log.add('child hears the cancel');
          if (mode == 'cascade-hand') parent.drop(const Done('hand'));
        });
        await forever.future;
      }),
    );
    held = ctx.abandonable(
      () => gate.future,
      dispose: (v) => log.add('dispose $v'),
    )..ignore();
    return 'body';
  })..launch();
  await pumpEventQueue();
  log.add('body ended, parent finished: ${parent.isFinished}');
  if (mode == 'hand-no-cancel') {
    parent.drop(const Done('hand'));
  } else {
    unawaited(parent.cancel());
  }
  await pumpEventQueue();
  log.add('parent ${parent.isFinished ? parent.outcome : 'running'}');
  gate.complete('v');
  Object? got;
  try {
    got = await held;
  } on Object catch (e) {
    got = e;
  }
  await pumpEventQueue();
  forever.complete();
  await pumpEventQueue();
  return (got, log);
}

void main() {
  for (final mode in ['cascade-hand', 'cascade-plain', 'hand-no-cancel']) {
    test('M10: $mode', () async {
      final (got, log) = await scenario(mode);
      print(log.join('\n'));
      print('holder got: $got');
    });
  }
}
```

На ядре:

```text
00:00 +0: M10: cascade-hand
body ended, parent finished: false
child hears the cancel
parent Cancelled(manual)
dispose v
holder got: v
00:00 +1: M10: cascade-plain
body ended, parent finished: false
child hears the cancel
parent running
dispose v
holder got: Cancelled(manual)
00:00 +2: M10: hand-no-cancel
body ended, parent finished: false
parent Done(hand)
dispose v
holder got: v
00:00 +3: All tests passed!
```

На мутанте отличается одна строка, в `cascade-hand`:

```text
holder got: Cancelled(manual)
```

В обоих отменных порядках отмена пришла раньше значения, и держатель видит одно
и то же: отмену, потом значение. Обычным путём он получает `Cancelled`. Если
движок кончил задачу в каскаде, он получает `v` — уже после `dispose v`.
Dartdoc `abandonable` обещает первое: «If a cancellation arrives while [action]
is in flight, the wait ends there with that [Cancelled] … its result is
dropped». Комментарий ветки описывает тот же порядок: «An engine ended the job
by hand while its cancellation went down to the children, and `finish` dropped
the callbacks», — но говорит о теле или работе, которые ждут значение,
и условие на `bodyEnded` отрезает от ветки держателя, которого оставило тело.
Что такой держатель бывает, говорит соседний `_keepLate`: «a body that walked
away may have handed that future to a child».

Мутант здесь ведёт себя по dartdoc, а ядро — нет. Правка в духе мутанта:
в ветке `_owner.bodyEnded && !fromFork` при `pendingCancel != null` кончать
вызов отменой, а значение отдавать `_releaseAbandoned`, как отдала бы его
гонка, услышавшая отмену. Правка меняет ядро и требует выпуска `async_job`; её
не делали.

Тесты ядра этого не держат. Весь набор ядра на мутанте M10 зелёный. План числит
место `:1095` пойманным нацеленным тестом, но тест писался до фикса 1.0.5
(`10575b00`), который и ввёл условие `(fromFork || !_owner.bodyEnded)`: фикс
научил ветку отдавать `Cancelled` телу, которое ждёт вызов, а держатель,
от которого тело ушло, остался за условием.

Третий порядок, `hand-no-cancel`, мутант не затрагивает, но он из того же
семейства. Движок кончил задачу руками без отмены, значение пришло после конца,
и держатель получает его уже освобождённым. Тело, которое ждало бы сам вызов,
на том же порядке, по чтению кода, получило бы `StateError` из `_keepOnStack`:
«the caller hears the plain truth about the job instead». Таблица «A value that
comes late» в `cleanup-rules.md` о держателе после конца задачи не говорит.

### Правка M10

Владелец решил 2026-11-27 править второй порядок. Ветка гонки, которая отдаёт
отмену вызову, не услышавшему её, больше не смотрит на `bodyEnded`: отмену
получает и держатель будущего, от которого ушло тело. Значение отдаётся
`_releaseAbandoned`, как отдала бы его гонка, услышавшая отмену.

Сначала правка расширила условие и оставила в ветке прежнее
`await _dispose(...)`. Независимый ревьюер на Opus нашёл в этом второй путь
к той же ветке и дефект на нём. Ветку открывает не только ручной `finish`
в каскаде, но и сырой колбэк отмены, зарегистрированный раньше гонки, если он
бросит: обход колбэков останавливается, задача при этом жива. Освобождение
через `await _dispose` в `forward` задача не ждёт, и она кончается раньше, чем
освобождение, — вопреки строке таблицы «A value that comes late»
в `cleanup-rules.md`: «A release that begins before the job ends keeps the job
from ending until the release is over». Прежний `_keepLate` держал такую
задачу, потому что клал значение на стек. Тот же дефект был и в ветке
до правки, для тела, которое ждёт вызов: его ревьюер показал зондом, и он
выпущен в 1.0.5. `_releaseAbandoned` чинит оба случая.

Тесты в `late_value_test.dart`, все три падают на ядре до правки:

- «a value a holder the body walked away from takes after the job was ended by
  hand in the cascade of its cancellation» — порядок `cascade-hand` зонда.
  До правки держатель получал `db` после `released db`.
- «a value taken after a raw callback threw, on a job still waiting for a
  child», для тела, которое ушло, и для тела, которое ждёт. Ребёнок идёт 100
  мс, значение приходит в 20, освобождение длится 200. С правкой задача
  кончается в 220, вместе с освобождением. До правки ушедшее тело давало
  держателю `db`, освобождение шло 100–300 на стеке; ждущее тело получало
  отмену, а задача кончалась в 100. Вариант с `await _dispose` вместо
  `_releaseAbandoned` тоже даёт конец в 100.

Ошибка бросившего сырого колбэка уходит из `job.cancel()` к тому, кто отменял,
синхронно; тест её ловит там.

Ревьюер отметил и то, что держатель без `onError` теперь отдаёт в зону
`Cancelled` там, где раньше получал значение. Обычный путь отмены делает
так же, и правка выравнивает с ним.

## Вывод

Слова, названные во втором шаге, оказались теми: домен поймал M08, ответы — M11
и M12, `discard` с вклиниванием — M19. Для M11 одного словаря мало:
неустойчивый конверт нужен именно того вида, который ловит сопоставление
вердиктов, — `[x, x]` при первом обходе и `[y, x]` при втором. Пустую группу
(M14) домен не поймал, и, по чтению, ловить там нечего, кроме числа микрозадач.

Цена — границы. `answer` и `free` вместе тяжелее всего; `rule` и `free` с двумя
шагами тянутся только на одной задаче.

Непойманные, кроме M10, эквивалентны или видны лишь по числу микрозадач. M10
перебор не достигает, а зонд показывает, что на его месте ядро отдаёт держателю
брошенного вызова освобождённое значение вместо обещанной отмены. Ядро
поправлено, раздел «Правка M10».

## Как запустить

```sh
dart compile exe tool/explore_core.dart -o /tmp/explore
/tmp/explore --with rule,free --steps 2 --jobs 1 --events 4 --depth 1 \
  --disrupt 2
/tmp/explore --with answer --steps 2 --jobs 2 --events 3 --depth 1 \
  --disrupt 2 --path 1,0,0,2,2,1
```

Драйвер мутантов — тот же; новые границы и калибровки K5–K7 выбирает `SET=3`:

```sh
SET=3 python3 mutate.py <каталог пакета> <абсолютный каталог работы> [K5 M08 ...]
```

## Код перебора

```dart
// Exhaustive exploration of event orders on the real core, bounded.
//
// Every choice -- the shape of the bodies, which event comes next, whether an
// event cuts in between two microtasks -- goes through `Path.choose`. A path
// is the list of choices; the explorer replays each path from scratch (Dart
// has no snapshots) and walks them all in depth-first order, the way CHESS and
// Coyote do. The microtasks and timers of the run go to a zone of its own and
// run one at a time, in the FIFO order Dart keeps; a deadline's timer runs
// only when the path chooses the event that makes it run out.
//
//   dart run tool/explore_core.dart [--steps N] [--depth N] [--jobs N]
//       [--events N] [--disrupt N] [--preempt N] [--branches N]
//       [--with aband,free,all,timeout,disc,loose,rule,answer] [--no-hand]
//       [--stop-first]

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:async_job/engine.dart';

// ---------------------------------------------------------------- config

final class Config {
  int steps = 2; // steps of a body before its end
  int depth = 1; // levels of children below the root
  int jobs = 2; // jobs in all, the root included
  int events = 6; // events a path may hold
  int disrupt = 2; // of them cancels, hand finishes and deadlines
  int preempt = 0; // events that cut in between two microtasks
  int branches = 2; // branches of a group at most
  bool hand = true; // an engine may finish a job by hand
  bool aband = false; // `ctx.abandonable`
  bool free = false; // `ctx.unattended`
  bool all = false; // `ctx.runAll`
  bool timeout = false; // a job may have a deadline
  bool disc = false; // `join` with `discard` in place of `dispose`
  bool loose = false; // `ctx.uncancellable` the body does not await
  bool rule = false; // a domain whose `check()` refuses once a rule closes
  bool answer = false; // an answering observer, a filter and envelopes
  bool stopFirst = false;
  bool deepen = true; // raise the event bound one by one
  List<int>? path; // play this one path and tell what happened

  static Config parse(List<String> args) {
    final c = Config();
    for (var i = 0; i < args.length; i++) {
      int next() => int.parse(args[++i]);
      switch (args[i]) {
        case '--steps':
          c.steps = next();
        case '--depth':
          c.depth = next();
        case '--jobs':
          c.jobs = next();
        case '--events':
          c.events = next();
        case '--disrupt':
          c.disrupt = next();
        case '--preempt':
          c.preempt = next();
        case '--branches':
          c.branches = next();
        case '--with':
          for (final w in args[++i].split(',')) {
            switch (w) {
              case 'aband':
                c.aband = true;
              case 'free':
                c.free = true;
              case 'all':
                c.all = true;
              case 'timeout':
                c.timeout = true;
              case 'disc':
                c.disc = true;
              case 'loose':
                c.loose = true;
              case 'rule':
                c.rule = true;
              case 'answer':
                c.answer = true;
              default:
                throw ArgumentError('unknown word $w');
            }
          }
        case '--no-hand':
          c.hand = false;
        case '--stop-first':
          c.stopFirst = true;
        case '--no-deepen':
          c.deepen = false;
        case '--path':
          c.path = [for (final x in args[++i].split(',')) int.parse(x)];
        default:
          throw ArgumentError('unknown argument ${args[i]}');
      }
    }
    return c;
  }

  @override
  String toString() =>
      'steps=$steps depth=$depth jobs=$jobs events=$events disrupt=$disrupt '
      'preempt=$preempt branches=$branches hand=$hand aband=$aband '
      'free=$free all=$all timeout=$timeout disc=$disc loose=$loose '
      'rule=$rule answer=$answer';
}

// ---------------------------------------------------------------- paths

final class Nondeterminism implements Exception {
  Nondeterminism(this.message);
  final String message;
  @override
  String toString() => 'Nondeterminism: $message';
}

final class Path {
  Path(this.prefix, this.prefixWidths);
  final List<int> prefix;
  final List<int> prefixWidths;
  final choices = <int>[];
  final widths = <int>[];

  /// The first choice of a path given by hand that had no such option.
  String? invalid;

  int choose(int width) {
    if (width <= 1) return 0;
    final i = choices.length;
    var c = 0;
    if (i < prefix.length) {
      // Width 0: a path given by hand, whose widths nobody knows.
      if (prefixWidths[i] != 0 && prefixWidths[i] != width) {
        throw Nondeterminism(
          'choice $i had ${prefixWidths[i]} options, '
          'now $width',
        );
      }
      c = prefix[i];
      // A path given by hand may ask for an option that is not there; the
      // choice is made inside the bodies, where a throw would only fail a
      // job, so it is said at the end instead.
      if (c >= width) {
        invalid ??= 'choice $i is $c, and it has $width options';
        c = 0;
      }
    }
    choices.add(c);
    widths.add(width);
    return c;
  }

  Path? next() {
    for (var i = choices.length - 1; i >= 0; i--) {
      if (choices[i] + 1 < widths[i]) {
        return Path([
          ...choices.sublist(0, i),
          choices[i] + 1,
        ], widths.sublist(0, i + 1));
      }
    }
    return null;
  }
}

// ---------------------------------------------------------------- scheduler

final class _NoTimer implements Timer {
  @override
  void cancel() {}
  @override
  bool get isActive => false;
  @override
  int get tick => 0;
}

/// A timer of the run: it never runs by itself, only when the path chooses to
/// make it run out.
final class FakeTimer implements Timer {
  FakeTimer(this.id, this.f);
  final int id;
  final void Function() f;
  Rec? owner;
  bool active = true;
  bool fired = false;
  // It ran out on a job that was still running and not finished by hand.
  bool firedLive = false;
  @override
  void cancel() => active = false;
  @override
  bool get isActive => active;
  @override
  int get tick => fired ? 1 : 0;
  @override
  String toString() => 'deadline of ${owner ?? 't$id'}';
}

final class Sched {
  final queue = ListQueue<void Function()>();
  final zoneErrors = <Object>[];
  final timers = <FakeTimer>[];
  int periodic = 0;
  int ran = 0;

  late final Zone zone = Zone.current.fork(
    specification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, f) {
        queue.add(() => zone.runGuarded(f));
      },
      createTimer: (self, parent, zone, duration, f) {
        final t = FakeTimer(timers.length, f);
        timers.add(t);
        return t;
      },
      createPeriodicTimer: (self, parent, zone, duration, f) {
        periodic++;
        return _NoTimer();
      },
      handleUncaughtError: (self, parent, zone, error, stackTrace) {
        zoneErrors.add(error);
      },
    ),
  );

  void step() {
    ran++;
    queue.removeFirst()();
  }
}

// ---------------------------------------------------------------- jobs

/// A job of the core the way an engine makes one, with a deadline if asked.
final class XJob extends JobBase<Object?> implements ChildJob<Object?> {
  XJob(
    this._body,
    this._onStarted,
    this._rule, {
    super.observer,
    super.timeout,
  });
  final Future<Object?> Function(JobContext ctx) _body;
  final void Function() _onStarted;
  final void Function() _rule;

  @override
  void started() => _onStarted();

  void launch() => start();

  void drop(Outcome<Object?> outcome) => finish(outcome);

  @override
  JobContextBase createContext() => XContext(this, _rule);

  @override
  Future<Object?> execute(covariant XContext ctx) => _body(ctx);
}

/// The context of a domain with one rule: once the scenario closes it, every
/// checkpoint refuses.
final class XContext extends JobContextBase {
  XContext(super.owner, this._rule);
  final void Function() _rule;

  @override
  void check() {
    super.check();
    _rule();
  }
}

// ---------------------------------------------------------------- scenario

final class GateError implements Exception {
  GateError(this.gate);
  final int gate;
  @override
  String toString() => 'GateError(g$gate)';
}

final class BodyError implements Exception {
  BodyError(this.job);
  final int job;
  @override
  String toString() => 'BodyError(j$job)';
}

final class WorkError implements Exception {
  WorkError(this.job);
  final int job;
  @override
  String toString() => 'WorkError(j$job)';
}

final class StopError implements Exception {
  StopError(this.gate);
  final int gate;
  @override
  String toString() => 'StopError(g$gate)';
}

final class RuleError implements Exception {
  RuleError(this.id, this.job);
  final int id;
  final int job;
  @override
  String toString() => 'RuleError#$id(j$job)';
}

typedef Errors = List<AsyncError?>;

/// An envelope whose `errors` reads [first] and [second] by turns: the core
/// walks one error more than once and promises to hold up when the walks
/// meet other failures, or the same ones in another order.
final class Shaky extends ParallelWaitError<List<Object?>, Errors> {
  Shaky(this.first, this.second) : super(const [null, null], first);
  final Errors first;
  final Errors second;
  int reads = 0;
  @override
  Errors get errors => (reads++).isEven ? first : second;
}

final class HandError implements Exception {
  HandError(this.job);
  final int job;
  @override
  String toString() => 'HandError(j$job)';
}

sealed class Step {}

final class Wait extends Step {
  @override
  String toString() => 'wait';
}

final class Hold extends Step {
  @override
  String toString() => 'hold';
}

final class Aband extends Step {
  @override
  String toString() => 'aband';
}

final class Shield extends Step {
  @override
  String toString() => 'shield';
}

final class Disc extends Step {
  @override
  String toString() => 'disc';
}

final class Loose extends Step {
  @override
  String toString() => 'loose';
}

final class Run extends Step {
  Run(this.shape);
  final Shape shape;
  @override
  String toString() => 'run$shape';
}

final class All extends Step {
  All(this.shapes);
  final List<Shape> shapes;
  @override
  String toString() => 'all(${shapes.join(' ')})';
}

final class Free extends Step {
  Free(this.shape);
  final Shape shape;
  @override
  String toString() => 'free$shape';
}

final class Shape {
  Shape(this.steps, this.throws, {this.timed = false});
  final List<Step> steps;
  final bool throws;
  final bool timed;
  @override
  String toString() {
    final words = [if (timed) 'timeout', ...steps, if (throws) 'throw'];
    return '[${[...words, if (!throws) 'value'].join(' ')}]';
  }
}

final class Rec {
  Rec(this.id, this.parent);
  final int id;
  final Rec? parent;
  late final XJob job;
  int finishes = 0;
  int finishOrder = -1;
  Outcome<Object?>? outcomeAtFinish;
  bool hand = false; // finished by hand at least once
  bool handFirst = false; // the first hand finish came on an unfinished job
  bool markBefore = false;
  Outcome<Object?>? handed;
  final errors = <Object>[];
  bool accepted = false;
  bool turnedAway = false; // its parent was over when it called run
  int shield = 0;
  final res = <Res>[];
  bool bodyReturned = false;
  Object? bodyFailure; // what the body threw, a cancellation aside
  FakeTimer? timer;
  Group? group; // the group this job is a branch of
  bool bodyEnded = false; // set before the body returns or throws
  bool cancelledLive = false; // cancel() came while the body ran
  int looseActive = 0; // sections the body did not await, running
  bool finishedClosed = false; // it finished after the rule closed
  @override
  String toString() => 'j$id';
}

final class Group {
  Group(this.id, this.owner, this.branches);
  final int id;
  final Rec owner;
  final List<Rec> branches;
  List<Object?>? values;
  Object? thrown;
  bool finishedAtThrow = true;
  final openAtThrow = <String>[];
  @override
  String toString() => 'group$id of $owner';
}

final class Gate {
  Gate(this.id, this.owner, this.kind);
  final int id;
  final Rec owner;
  final String kind;
  final c = Completer<Object?>();
  bool opened = false;
  bool taken = false; // the core called the action that waits for it
  // What it fails with: 0 an error of its own, 1 an envelope of two, 2 to 4
  // a `Shaky` envelope whose walks by turns swap the failures or repeat one,
  // the repeat on the even walks or on the odd ones.
  int err = 0;
  bool get quiet => kind == 'loose'; // its failure goes to nobody
  @override
  String toString() => 'g$id($kind of $owner)';
}

final class Res {
  Res(this.id, this.kind);
  final int id;
  final String kind; // hold, aband, disc, or work: taken by unattended work
  bool arrived = false;
  bool arrivedClosed = false; // it arrived after the rule closed
  // How many times it is disposed of in the end, as a finish by hand in the
  // middle of the unwinding leaves it; null when that finish says nothing.
  int? handExpect;
  int disposed = 0;
  // The call handed the value to its caller: the core has put its cleanup on
  // the stack.
  bool registered = false;
  // Registered when an engine finished the job by hand before the core began
  // to unwind its stack: `finish` unwinds nothing, so the core must not
  // dispose of it. An unwinding under way when `finish` comes goes on to the
  // end, as `doc/extending.md` says.
  bool keptByHand = false;
}

sealed class Event {}

final class Open extends Event {
  Open(this.gate, this.value);
  final Gate gate;
  final bool value;
  @override
  String toString() => 'open $gate ${value ? 'value' : 'error'}';
}

final class Cancel extends Event {
  Cancel(this.rec);
  final Rec rec;
  @override
  String toString() => 'cancel $rec';
}

final class Hand extends Event {
  Hand(this.rec, this.kind);
  final Rec rec;
  final String kind; // done, failed, cancelled
  @override
  String toString() => 'finish $rec by hand $kind';
}

final class CloseRule extends Event {
  @override
  String toString() => 'the rule closes';
}

final class Expire extends Event {
  Expire(this.timer);
  final FakeTimer timer;
  @override
  String toString() => '${timer.owner} runs out of time';
}

final class Violation implements Exception {
  Violation(this.message);
  final String message;
  @override
  String toString() => message;
}

final class Run1 {
  Run1(this.cfg, this.path, this.eventBound);
  final Config cfg;
  final Path path;
  final int eventBound;
  final sched = Sched();
  final recs = <Rec>[];
  final gates = <Gate>[];
  final groups = <Group>[];
  final byJob = Map<Job<Object?>, Rec>.identity();
  final log = <String>[];
  final violations = <String>[];
  // Errors of the scenario that reached the core: each must reach `onError`.
  final ours = <(Object, Rec)>[];
  late final Obs obs = cfg.answer ? AnsweringObs(this) : Obs(this);
  int clock = 0;
  int jobsMade = 1;
  late int eventsLeft = eventBound;
  late int disruptLeft = cfg.disrupt;
  late int preemptLeft = cfg.preempt;
  int resCount = 0;
  bool anyHand = false;
  bool anyWork = false;
  bool ruleClosed = false;
  int ruleErrors = 0;
  // Envelopes of errors, and the failures inside the shaky ones: those are
  // walked differently each time, and only the answer oracle speaks of them.
  final envelopes = Set<Object>.identity();
  final shaky = Set<Object>.identity();
  // What `onError` was told, and what `onUnanswered` was asked.
  final told = <(Rec, Object, JobErrorAnswer)>[];
  final answers = <(Rec, Object)>[];

  void violate(String message) {
    violations.add(message);
    throw Violation(message);
  }

  // A violation found inside the core's own callbacks must not be swallowed
  // by its error routes: note it and carry on, the run stops afterwards.
  void note(String message) => violations.add(message);

  Shape shape(int depth, {bool work = false}) {
    final timed = !work && cfg.timeout && path.choose(2) == 1;
    final n = path.choose(cfg.steps + 1);
    final steps = <Step>[];
    for (var i = 0; i < n; i++) {
      final room = depth < cfg.depth ? cfg.jobs - jobsMade : 0;
      final kinds = <String>[
        'wait',
        'hold',
        if (cfg.aband) 'aband',
        if (cfg.disc) 'disc',
        if (!work) ...[
          'shield',
          if (cfg.loose) 'loose',
          if (cfg.free) 'free',
          if (room > 0) 'run',
          if (cfg.all) 'all',
        ],
      ];
      switch (kinds[path.choose(kinds.length)]) {
        case 'wait':
          steps.add(Wait());
        case 'hold':
          steps.add(Hold());
        case 'aband':
          steps.add(Aband());
        case 'disc':
          steps.add(Disc());
        case 'loose':
          steps.add(Loose());
        case 'shield':
          steps.add(Shield());
        case 'free':
          steps.add(Free(shape(depth, work: true)));
        case 'run':
          jobsMade++;
          steps.add(Run(shape(depth + 1)));
        default:
          final k = path.choose(min(room, cfg.branches) + 1);
          jobsMade += k;
          steps.add(All([for (var b = 0; b < k; b++) shape(depth + 1)]));
      }
    }
    return Shape(steps, path.choose(2) == 1, timed: timed);
  }

  Rec newRec(Rec? parent, Shape s) {
    final rec = Rec(recs.length, parent);
    recs.add(rec);
    final job = XJob(
      (ctx) => body(rec, s, ctx),
      () => started(rec, s),
      () => rule(rec),
      observer: obs,
      timeout: s.timed ? const Duration(seconds: 1) : null,
    );
    rec.job = job;
    byJob[job] = rec;
    job.whenCancelled((_) => rec.accepted = true);
    return rec;
  }

  // The core arms the deadline right before `started`.
  void started(Rec rec, Shape s) {
    if (!s.timed) return;
    final t = sched.timers.isEmpty ? null : sched.timers.last;
    if (t == null || t.owner != null) {
      note('$rec has a deadline and no timer was armed for it');
      return;
    }
    t.owner = rec;
    rec.timer = t;
  }

  Gate newGate(Rec owner, String kind) {
    final g = Gate(gates.length, owner, kind);
    if (cfg.answer && !g.quiet) g.err = path.choose(5);
    gates.add(g);
    return g;
  }

  void rule(Rec rec) {
    if (!ruleClosed) return;
    final e = RuleError(ruleErrors++, rec.id);
    ours.add((e, rec));
    throw e;
  }

  // A call that hands a value to a body still running, or to work while the
  // body runs, has passed its checkpoint after the value came: a value that
  // came after the rule closed never gets there.
  void afterCall(Rec rec, bool closed, String what) {
    if (closed && !rec.bodyEnded && !rec.hand) {
      note('$rec: $what handed over a value that came after the rule closed');
    }
  }

  Object gateError(Gate g) {
    AsyncError a(Object e) => AsyncError(e, StackTrace.empty);
    final x = GateError(g.id);
    if (g.err == 0) {
      if (g.taken) ours.add((x, g.owner));
      return x;
    }
    final y = StopError(g.id);
    final Object envelope = switch (g.err) {
      1 => ParallelWaitError<List<Object?>, Errors>(
        const [null, null],
        [a(x), a(y)],
      ),
      2 => Shaky([a(x), a(y)], [a(y), a(x)]),
      // Walks that repeat a failure on one side and not on the other: the
      // matching of verdicts to failures by identity, one use each, is what
      // keeps a verdict from answering twice.
      3 => Shaky([a(y), a(x)], [a(x), a(x)]),
      _ => Shaky([a(x), a(x)], [a(y), a(x)]),
    };
    envelopes.add(envelope);
    if (g.taken) {
      if (g.err == 1) {
        ours
          ..add((x, g.owner))
          ..add((y, g.owner));
      } else {
        shaky
          ..add(x)
          ..add(y);
      }
    }
    return envelope;
  }

  void checkShield(Rec rec, String where) {
    // A section the body walked away from may outlive its job, and a job
    // that ended Cancelled is cancelled for good.
    if (rec.shield > 0 &&
        !rec.hand &&
        !rec.job.isFinished &&
        rec.job.isCancelled) {
      note('$rec is marked cancelled inside uncancellable ($where)');
    }
  }

  void dispose(Res v) {
    v.disposed++;
    if (v.disposed > 1) note('resource ${v.id} disposed twice');
  }

  Future<Res> Function() resource(Gate g, Res r) => () {
    g.taken = true;
    return g.c.future.then((_) {
      r
        ..arrived = true
        ..arrivedClosed = ruleClosed;
      return r;
    });
  };

  Future<Object?> body(Rec rec, Shape s, JobContext ctx) async {
    try {
      await play(rec, s.steps, ctx, work: false);
      if (s.throws) {
        final e = BodyError(rec.id);
        ours.add((e, rec));
        throw e;
      }
    } on Object catch (e) {
      if (e is! Cancelled) rec.bodyFailure = e;
      rec.bodyEnded = true;
      rethrow;
    }
    rec
      ..bodyReturned = true
      ..bodyEnded = true;
    return 'v${rec.id}';
  }

  Future<void> play(
    Rec rec,
    List<Step> steps,
    JobContext ctx, {
    required bool work,
  }) async {
    for (final step in steps) {
      switch (step) {
        case Wait():
          final g = newGate(rec, 'wait');
          var closed = false;
          await ctx.join(() {
            g.taken = true;
            return g.c.future.then((v) {
              closed = ruleClosed;
              return v;
            });
          });
          afterCall(rec, closed, 'join');
        case Hold():
          final g = newGate(rec, 'hold');
          final r = Res(resCount++, work ? 'work' : 'hold');
          rec.res.add(r);
          await ctx.join<Res>(resource(g, r), dispose: dispose);
          r.registered = true;
          afterCall(rec, r.arrivedClosed, 'join');
        case Disc():
          final g = newGate(rec, 'disc');
          final r = Res(resCount++, 'disc');
          rec.res.add(r);
          await ctx.join<Res>(resource(g, r), discard: dispose);
          r.registered = true;
          afterCall(rec, r.arrivedClosed, 'join');
        case Aband():
          final g = newGate(rec, 'aband');
          final r = Res(resCount++, work ? 'work' : 'aband');
          rec.res.add(r);
          await ctx.abandonable<Res>(resource(g, r), dispose: dispose);
          r.registered = true;
        case Shield():
          final g = newGate(rec, 'shield');
          await ctx.uncancellable(() async {
            g.taken = true;
            rec.shield++;
            checkShield(rec, 'enter');
            try {
              await g.c.future;
            } finally {
              checkShield(rec, 'leave');
              rec.shield--;
            }
          });
        case Loose():
          final g = newGate(rec, 'loose');
          rec.looseActive++;
          try {
            ctx
                .uncancellable(() async {
                  g.taken = true;
                  rec.shield++;
                  checkShield(rec, 'enter');
                  try {
                    await g.c.future;
                  } finally {
                    checkShield(rec, 'leave');
                    rec.shield--;
                  }
                })
                .whenComplete(() => rec.looseActive--)
                .ignore();
          } on Object {
            rec.looseActive--;
            rethrow;
          }
        case Run(:final shape):
          final child = newRec(rec, shape);
          if (rec.job.isFinished) child.turnedAway = true;
          await ctx.run(child.job);
          afterCall(rec, child.finishedClosed, 'run');
        case All(:final shapes):
          final branches = [for (final s in shapes) newRec(rec, s)];
          final group = Group(groups.length, rec, branches);
          groups.add(group);
          for (final b in branches) {
            b.group = group;
            if (rec.job.isFinished) b.turnedAway = true;
          }
          // A group checks the rules once it has committed, and an empty one
          // commits at the call.
          final closedAtCall = ruleClosed;
          try {
            group.values = await ctx.runAll<Object?>([
              for (final b in branches) b.job,
            ]);
          } on Object catch (e) {
            group.thrown = e;
            atThrow(group);
            if (e is RuleError && branches.isEmpty && !closedAtCall) {
              note('$group, empty, refused by a rule that closed after it');
            }
            rethrow;
          }
          afterCall(rec, closedAtCall, 'runAll');
        case Free(:final shape):
          anyWork = true;
          ctx.unattended(() async {
            await play(rec, shape.steps, ctx, work: true);
            if (shape.throws) {
              final e = WorkError(rec.id);
              ours.add((e, rec));
              throw e;
            }
          });
      }
    }
  }

  Iterable<Rec> subtree(Rec top) => recs.where((r) {
    for (Rec? p = r; p != null; p = p.parent) {
      if (identical(p, top)) return true;
    }
    return false;
  });

  // "By the time the error arrives, everything the branches took is closed."
  void atThrow(Group group) {
    for (final b in group.branches) {
      if (!b.job.isFinished) group.finishedAtThrow = false;
      for (final r in subtree(b)) {
        for (final x in r.res) {
          if (x.kind != 'work' &&
              x.arrived &&
              x.disposed == 0 &&
              !x.keptByHand) {
            group.openAtThrow.add('resource ${x.id} of $r');
          }
        }
      }
    }
  }

  List<Event> enabled() {
    final ev = <Event>[];
    for (final g in gates) {
      if (!g.opened) {
        ev
          ..add(Open(g, true))
          ..add(Open(g, false));
      }
    }
    if (disruptLeft > 0) {
      for (final rec in recs) {
        if (rec.job.isFinished || rec.turnedAway) continue;
        ev.add(Cancel(rec));
        if (cfg.hand) {
          ev
            ..add(Hand(rec, 'done'))
            ..add(Hand(rec, 'failed'))
            ..add(Hand(rec, 'cancelled'));
        }
      }
      for (final t in sched.timers) {
        if (t.active) ev.add(Expire(t));
      }
    }
    if (cfg.rule && !ruleClosed) ev.add(CloseRule());
    return ev;
  }

  void apply(Event e, {bool cut = false}) {
    log.add(cut ? '$e  <- between microtasks' : '$e');
    eventsLeft--;
    sched.zone.run(() {
      switch (e) {
        case Open(:final gate, :final value):
          gate.opened = true;
          if (value) {
            gate.c.complete('g${gate.id}');
          } else {
            gate.c.completeError(
              gate.quiet ? GateError(gate.id) : gateError(gate),
            );
          }
        case CloseRule():
          ruleClosed = true;
        case Cancel(:final rec):
          disruptLeft--;
          final job = rec.job;
          // A section the body did not wait for holds the request, and it
          // lands nowhere once the job is over.
          if (!rec.bodyEnded &&
              !job.isFinished &&
              !rec.hand &&
              rec.looseActive == 0) {
            rec.cancelledLive = true;
          }
          job.cancel().then((_) {
            if (!job.isFinished) note('cancel() of $rec returned unfinished');
          });
        case Hand(:final rec, :final kind):
          disruptLeft--;
          anyHand = true;
          final job = rec.job;
          final outcome = handOutcome(rec, kind);
          if (!rec.hand && !job.isFinished) {
            rec
              ..handFirst = true
              ..markBefore = job.isCancelled
              ..handed = outcome;
            final unwinding = rec.res.any((r) => r.disposed > 0);
            final g = rec.group;
            // A branch whose group has not decided stands between its two
            // passes: the second one, of `discard`, never comes. Any other
            // unwinding goes on and decides by what the body did.
            final between = g != null && g.values == null && g.thrown == null;
            for (final r in rec.res) {
              r.keptByHand = r.registered && !unwinding;
              if (unwinding &&
                  r.kind == 'disc' &&
                  r.registered &&
                  r.disposed == 0) {
                r.handExpect = between || rec.bodyReturned ? 0 : 1;
              }
            }
          }
          rec.hand = true;
          try {
            job.drop(outcome);
          } on Object catch (error) {
            note('finish of $rec threw $error');
          }
        case Expire(:final timer):
          disruptLeft--;
          final owner = timer.owner!;
          timer
            ..active = false
            ..fired = true
            // A deadline held by a section the body did not wait for is
            // lifted with the body and the children, and lands nowhere.
            ..firedLive =
                !owner.job.isFinished && !owner.hand && owner.looseActive == 0;
          timer.f();
      }
    });
  }

  Outcome<Object?> handOutcome(Rec rec, String kind) => switch (kind) {
    'done' => Done<Object?>('hand${rec.id}'),
    'failed' => Failed(HandError(rec.id), StackTrace.current),
    // A fresh instance: the core tells cancellations apart by identity.
    _ => Cancelled.by(
      reason: const ManualCancelReason(),
      stackTrace: StackTrace.current,
    ),
  };

  void flush() {
    while (sched.queue.isNotEmpty) {
      if (preemptLeft > 0 && eventsLeft > 0) {
        final ev = enabled();
        final c = path.choose(ev.length + 1);
        if (c > 0) {
          preemptLeft--;
          apply(ev[c - 1], cut: true);
        }
      }
      sched.step();
      if (sched.ran > 200000) violate('livelock: 200000 microtasks');
    }
  }

  void stopIfNoted() {
    if (violations.isNotEmpty) throw Violation(violations.first);
  }

  void run() {
    final root = shape(0);
    log.add('root $root');
    // Made inside the zone of the run: a job schedules its microtasks in the
    // zone it was created in, and one made outside would send them to the
    // real event loop, where nothing runs them while the path plays out.
    sched.zone.run(() {
      final rec = newRec(null, root);
      rec.job.done.then((_) {});
      rec.job.launch();
    });
    flush();
    stopIfNoted();
    while (eventsLeft > 0) {
      final ev = enabled();
      if (ev.isEmpty) break;
      apply(ev[path.choose(ev.length)]);
      flush();
      stopIfNoted();
    }
    for (var i = 0; i < gates.length; i++) {
      final g = gates[i];
      if (g.opened) continue;
      sched.zone.run(() {
        g.opened = true;
        g.c.complete('g${g.id}');
      });
      flush();
      stopIfNoted();
    }
    endChecks();
    stopIfNoted();
  }

  void finishedHook(Job<Object?> job) {
    final rec = byJob[job]!
      ..finishes += 1
      ..finishOrder = clock++
      ..outcomeAtFinish ??= job.outcome
      ..finishedClosed = ruleClosed;
    if (rec.timer case final t? when t.active) {
      note('$rec finished with its deadline still armed');
    }
    if (!rec.hand) {
      for (final r in rec.res) {
        // A value the body waited for is released before the job ends; one
        // that arrived for a call nobody waits for any more is released on
        // arrival, which may come after.
        if (r.kind == 'disc') {
          // Released unless the job ends Done: a value the body holds; one
          // that never reached it is released on arrival.
          if (r.registered && r.disposed != (job.outcome is Done ? 0 : 1)) {
            note(
              '$rec finished ${job.outcome} with discard of resource ${r.id} '
              'run ${r.disposed} times',
            );
          }
          continue;
        }
        final gone = r.kind == 'hold' ? r.arrived : r.registered;
        if (gone && r.disposed != 1) {
          note('$rec finished before resource ${r.id} was disposed');
        }
      }
    }
  }

  void endChecks() {
    if (sched.periodic > 0) note('a periodic timer was made');
    for (final t in sched.timers) {
      if (t.owner == null) note('a timer nobody owns was made');
      if (t.active) note('$t is still armed at the end');
    }
    for (final rec in recs) {
      final job = rec.job;
      final o = job.outcome;
      if (!job.isFinished) {
        if (!rec.turnedAway) note('$rec never finished');
        continue;
      }
      if (rec.finishes != 1) note('$rec: onFinish ran ${rec.finishes} times');
      if (!identical(o, rec.outcomeAtFinish)) {
        note(
          '$rec: outcome changed after onFinish: ${rec.outcomeAtFinish} '
          '-> $o',
        );
      }
      if (rec.accepted && o is! Cancelled) {
        note('$rec accepted a cancellation and ended $o');
      }
      if (o case Failed(:final error) when !envelopes.contains(error)) {
        final heard = rec.errors.where((e) => identical(e, error)).length;
        if (heard != 1) note('$rec: onError heard its failure $heard times');
      }
      if (!rec.hand && !rec.accepted) {
        // The outcome is the body's: work it handed over, its cleanup and the
        // groups it ran change nothing about it.
        if (rec.bodyReturned) {
          if (o is! Done || o.value != 'v${rec.id}') {
            note('$rec: the body returned and the job ended $o');
          }
        } else if (rec.bodyFailure case final f?) {
          if (o is! Failed || !identical(o.error, f)) {
            note('$rec: the body threw $f and the job ended $o');
          }
        }
      }
      if (rec.timer case final t? when t.firedLive && !rec.hand) {
        if (o is! Cancelled) note('$rec ran out of time and ended $o');
      }
      if (rec.cancelledLive && !rec.hand && o is! Cancelled) {
        note('$rec was cancelled while its body ran and ended $o');
      }
      if (rec.handFirst) {
        final handed = rec.handed!;
        if (rec.markBefore) {
          if (o is! Cancelled) {
            note(
              '$rec was marked cancelled, finished by hand with $handed, '
              'ended $o',
            );
          }
        } else {
          final ok = switch (handed) {
            Done(:final value) => o is Done && o.value == value,
            Failed(:final error) => o is Failed && identical(o.error, error),
            Cancelled() => o is Cancelled,
          };
          if (!ok) note('$rec finished by hand with $handed, ended $o');
        }
      }
      final p = rec.parent;
      if (p != null && !p.hand && !rec.turnedAway && p.job.isFinished) {
        if (p.finishOrder < rec.finishOrder) {
          note('$p finished before its child $rec');
        }
      }
      for (final r in rec.res) {
        final times = r.kind == 'disc' && r.registered && o is Done ? 0 : 1;
        if (r.arrived && !rec.hand && r.disposed != times) {
          note('resource ${r.id} of $rec disposed ${r.disposed} times');
        }
        if (r.handExpect case final n? when r.disposed != n) {
          note(
            'resource ${r.id} of $rec, on the stack when an engine finished '
            'it by hand, disposed ${r.disposed} times, not $n',
          );
        }
        if (r.keptByHand && r.disposed != 0) {
          note(
            'resource ${r.id} of $rec was disposed of after a finish by '
            'hand',
          );
        }
      }
    }
    groups.forEach(groupChecks);
    if (cfg.answer) answerChecks();
    // Every failure of a body, of its work and of what they waited for
    // reaches `onError` of the job it happened in, once, finished by hand or
    // not; a parent that rethrows it hears it once more, as its own.
    for (final (e, owner) in ours) {
      for (final rec in recs) {
        final n = rec.errors.where((x) => identical(x, e)).length;
        if (n > 1) note('$rec: onError heard $e $n times');
      }
      if (!owner.errors.any((x) => identical(x, e))) {
        note('$e of $owner never reached its onError');
      }
    }
    // Nothing in the scenario catches, and nobody answers: a failure that is
    // the outcome of a job is observed through that job -- by its parent, or
    // through the root's `done` -- and every other one reaches the zone,
    // once.
    for (final (e, owner) in ours) {
      final n =
          sched.zoneErrors.where((x) => identical(x, e)).length +
          answers.where((x) => identical(x.$2, e)).length;
      final outcome = recs.any((r) {
        final o = r.job.outcome;
        return o is Failed && carries(o.error, e);
      });
      // A failure the filter names in a job that has accepted a
      // cancellation is the cancellation's: nobody answers for it. `onError`
      // says so, or says `later` when the cancellation came after it.
      final stopped =
          e is StopError && owner.job.outcome is Cancelled ||
          told.any(
            (t) =>
                identical(t.$1, owner) &&
                identical(t.$2, e) &&
                t.$3 == JobErrorAnswer.cancellation,
          );
      if (n > 1 || n == 0 && !outcome && !stopped) {
        note('$e of $owner reached the zone $n times');
      }
    }
    for (final e in sched.zoneErrors) {
      final mine =
          e is GateError ||
          e is BodyError ||
          e is WorkError ||
          e is HandError ||
          e is StopError ||
          e is RuleError ||
          e is ParallelWaitError;
      // A body that goes on after an engine finished its job by hand meets
      // the finished context at its next call, and so does work handed over
      // with `unattended` that outlives its job or calls in while the stack
      // unwinds: that failure reaches the zone, and nothing else of the core
      // may.
      final late =
          e is StateError &&
          ((anyHand || anyWork) &&
                  e.message.contains('has already finished, cannot') ||
              anyWork &&
                  e.message.contains('is cleaning up after its body, cannot'));
      if (!mine && !late) note('zone heard $e');
    }
  }

  // Each failure `onError` was told goes to the answer the job asks for:
  // `answered` means it is asked, `later` that it may be, and nothing else
  // is. A shaky envelope is walked once for the answers and once more for
  // `onError`, and a failure the second walk misses is answered unannounced.
  void answerChecks() {
    for (final rec in recs) {
      final failures = <Object>[];
      for (final (r, e, _) in told) {
        if (identical(r, rec) && !failures.any((f) => identical(f, e))) {
          failures.add(e);
        }
      }
      for (final (r, e) in answers) {
        if (identical(r, rec) && !failures.any((f) => identical(f, e))) {
          failures.add(e);
        }
      }
      for (final f in failures) {
        if (f is Cancelled) continue;
        var a = 0;
        var l = 0;
        for (final (r, e, answer) in told) {
          if (!identical(r, rec) || !identical(e, f)) continue;
          if (answer == JobErrorAnswer.answered) a++;
          if (answer == JobErrorAnswer.later) l++;
        }
        final u = answers
            .where((x) => identical(x.$1, rec) && identical(x.$2, f))
            .length;
        if (u < a) note('$rec: $f told answered $a times, answered $u');
        if (!shaky.contains(f) && u > a + l) {
          note('$rec: $f answered $u times, told answered $a and later $l');
        }
      }
    }
  }

  bool carries(Object error, Object e) {
    if (identical(error, e)) return true;
    if (error is! ParallelWaitError || !envelopes.contains(error)) return false;
    final inner = error is Shaky
        ? [...error.first, ...error.second]
        : error.errors as Errors;
    return inner.any((x) => identical(x?.error, e));
  }

  void groupChecks(Group group) {
    final involved = [
      group.owner,
      for (final b in group.branches) ...subtree(b),
    ];
    if (involved.any((r) => r.hand)) return;
    if (group.branches.any((b) => b.turnedAway)) return;
    final values = group.values;
    final thrown = group.thrown;
    if (values == null && thrown == null) {
      if (group.owner.job.isFinished) note('$group neither returned nor threw');
      return;
    }
    if (values != null) {
      if (values.length != group.branches.length) {
        note('$group returned ${values.length} values');
        return;
      }
      for (final (i, b) in group.branches.indexed) {
        final o = b.job.outcome;
        if (values[i] != 'v${b.id}') {
          note('$group handed ${values[i]} for $b');
        }
        // "Once the group has handed the list over, the decision is final.
        // Every branch ends Done with the value it gave."
        if (o is! Done || o.value != values[i]) {
          note('$group handed the list over and $b ended $o');
        }
      }
      return;
    }
    if (!group.finishedAtThrow) note('$group threw before its branches ended');
    for (final open in group.openAtThrow) {
      note('$group threw with $open still open');
    }
    final failures = <Object>[
      // A branch that accepted a cancellation before its body failed ends
      // Cancelled, and the failure goes to `onError`, as for a child of
      // `run`: no failure of the group.
      for (final b in group.branches)
        if (b.job.outcome case Failed(:final error)) error,
    ];
    for (final b in group.branches) {
      if (b.job.outcome is Done) {
        note('$group failed and its branch $b ended ${b.job.outcome}');
      }
    }
    if (failures.isEmpty) {
      // Every branch ended Done and the checkpoint of the commit refused: a
      // rule of the owner's domain, or a cancellation.
      final refused = thrown is RuleError && thrown.job == group.owner.id;
      if (thrown is! Cancelled && !refused) {
        note('$group threw $thrown with no failure');
      }
    } else if (!failures.any((f) => identical(f, thrown))) {
      note('$group threw $thrown, not one of the failures $failures');
    }
  }

  String summary() => [
    for (final rec in recs) '$rec ${rec.job.outcome}',
    for (final g in groups) '$g ${g.values ?? g.thrown}',
    'zone ${sched.zoneErrors}',
    if (cfg.answer) ...[
      'told ${[for (final t in told) '${t.$1} ${t.$2} ${t.$3.name}']}',
      'answers ${[for (final a in answers) '${a.$1} ${a.$2}']}',
    ],
  ].join('; ');
}

class Obs extends JobObserver {
  Obs(this.run);
  final Run1 run;

  @override
  void onFinish(Job<Object?> job) => run.finishedHook(job);

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) {
    if (run.byJob[job] case final rec?) {
      rec.errors.add(error);
      run.told.add((rec, error, answer));
      // The filter names StopError, and only for a job that has accepted a
      // cancellation: the answer `onError` is told goes by that.
      if (run.cfg.answer &&
          !rec.hand &&
          (answer == JobErrorAnswer.answered ||
              answer == JobErrorAnswer.cancellation)) {
        final named = error is StopError && job.isCancelled;
        if (named != (answer == JobErrorAnswer.cancellation)) {
          run.note(
            '$rec: onError told ${answer.name} of $error '
            '(cancelled: ${job.isCancelled})',
          );
        }
      }
    }
    if (error is AssertionError || error is UnsupportedError) {
      run.note('onError heard $error');
    }
  }
}

final class AnsweringObs extends Obs with JobAnswerer {
  AnsweringObs(super.run);

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    if (run.byJob[job] case final rec?) run.answers.add((rec, error));
  }
}

// ---------------------------------------------------------------- explorer

/// Microtasks and timers that reached the zone around the runs instead of the
/// zone of a run: work of the core that the run would never play out.
int escaped = 0;

void main(List<String> args) {
  exitCode = runZoned(
    () => explore(Config.parse(args)),
    zoneSpecification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, f) => escaped++,
      createTimer: (self, parent, zone, duration, f) {
        escaped++;
        return _NoTimer();
      },
    ),
  );
}

int explore(Config cfg) {
  stdout.writeln('config: $cfg');
  // Failures of a job that has accepted a cancellation that this filter names
  // are its cancellation's, and nobody answers for them.
  if (cfg.answer) Job.isCancellationError = (e) => e is StopError;
  if (cfg.path case final choices?) {
    final run = Run1(
      cfg,
      Path(choices, List.filled(choices.length, 0)),
      cfg.events,
    );
    try {
      run.run();
    } on Object catch (e) {
      stdout.writeln('stopped: $e');
    }
    stdout
      ..writeln(run.log.map((l) => '  $l').join('\n'))
      ..writeln('  => ${run.summary()}');
    if (run.path.invalid case final why?) {
      stdout.writeln('no such path: $why');
      return 2;
    }
    return 0;
  }
  final bounds = cfg.deepen
      ? [for (var e = 1; e <= cfg.events; e++) e]
      : [cfg.events];
  var found = 0;
  final kinds = <String>{};
  for (final bound in bounds) {
    final watch = Stopwatch()..start();
    var paths = 0;
    var microtasks = 0;
    Path? path = Path(const [], const []);
    while (path != null) {
      final run = Run1(cfg, path, bound);
      paths++;
      String? violation;
      try {
        run.run();
      } on Violation catch (v) {
        violation = v.message;
      } on Nondeterminism catch (e) {
        stdout.writeln('NONDETERMINISM at path $paths: $e');
        return 2;
      } on Object catch (e) {
        violation = 'the run threw $e';
      }
      if (violation == null && escaped > 0) {
        violation = '$escaped microtasks or timers escaped the zone of the run';
      }
      escaped = 0;
      if (violation != null) {
        final kind = violation.replaceAll(RegExp(r'\d+'), '#');
        if (kinds.add(kind)) {
          found++;
          stdout
            ..writeln('VIOLATION (events<=$bound, path $paths): $violation')
            ..writeln('  choices ${run.path.choices}')
            ..writeln(run.log.map((l) => '  $l').join('\n'))
            ..writeln('  => ${run.summary()}');
          if (cfg.stopFirst) {
            stdout.writeln('paths: $paths');
            return 1;
          }
        }
      }
      microtasks += run.sched.ran;
      // Every 997th path is run again: the same choices must give the same
      // log and the same outcomes.
      if (paths % 997 == 0) {
        final again = Run1(cfg, Path(run.path.choices, run.path.widths), bound);
        try {
          again.run();
        } on Object {
          // compared below
        }
        escaped = 0;
        if (again.log.join('|') != run.log.join('|') ||
            again.summary() != run.summary()) {
          stdout.writeln('NONDETERMINISM on replay of path $paths');
          return 2;
        }
      }
      path = run.path.next();
    }
    stdout.writeln(
      'events<=$bound: $paths paths, $microtasks microtasks, '
      '${watch.elapsedMilliseconds} ms',
    );
  }
  stdout.writeln(found == 0 ? 'no violations' : '$found kinds of violation');
  return found == 0 ? 0 : 1;
}
```

## Драйвер мутантов

```python
#!/usr/bin/env python3
"""Runs the bounded explorer on each mutant of the core, in copies of the package.

usage: mutate.py <package dir> <work dir> [mutant ids...]
"""
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

B = 'lib/src/job_base.dart'
C = 'lib/src/job_context.dart'

# id, file, line, old, new
MUTANTS = [
    ('K1', B, 1469, '(_pendingCancel ?? outcome)', 'outcome'),
    ('K2', B, 961, '_uncancellableDepth > 0 && rejectable', 'false'),
    ('K3', B, 1380, 'cancelWith(Cancelled.by(reason: reason, stackTrace: _timeoutTrace));', 'reason.toString();'),
    ('K4', C, 1504, 'notifyError(error, stackTrace);', ''),
    ('K5', C, 784, 'always: dispose != null', 'always: true'),
    ('K6', C, 733, 'check();', ''),
    ('K7', B, 1828, '!_askIsCancellationError(isCancellationError, failure)', 'true'),
    ('M01', B, 849, 'error is StackOverflowError && _outOfStack', '_outOfStack'),
    ('M02', C, 918, 'error is StackOverflowError && _owner._outOfStack', '_owner._outOfStack'),
    ('M03', B, 2332, 'body is Failed && body.error is StackOverflowError', 'body is Failed'),
    ('M04', B, 2358, 'child.isFinished || !child._startWasTorn', '!child._startWasTorn'),
    ('M05', B, 2388, '_status == JobStatus.created', 'false'),
    ('M06', B, 970, 'held != null && _isOwnTimeout(held) && !_isOwnTimeout(marked)', 'held != null && !_isOwnTimeout(marked)'),
    ('M07', B, 970, 'held != null && _isOwnTimeout(held) && !_isOwnTimeout(marked)', 'held != null && _isOwnTimeout(held)'),
    ('M08', C, 702, '_owner.bodyEnded && _inOwnFork', '_inOwnFork'),
    ('M09', C, 1026, '_owner.bodyEnded && !_inOwnFork', 'false'),
    ('M10', C, 1095, 'pendingCancel != null && (fromFork || !_owner.bodyEnded)', 'pendingCancel != null'),
    ('M11', B, 1686, 'unmatched[i] && identical(verdicts[i].failure, failure)', 'identical(verdicts[i].failure, failure)'),
    ('M12', B, 1686, 'unmatched[i] && identical(verdicts[i].failure, failure)', 'unmatched[i]'),
    ('M13', B, 2452, 'verdicts != null && identical(verdicts.error, outcome.error)', 'verdicts != null'),
    ('M14', C, 1248, 'branches.isEmpty', 'false'),
    ('M15', B, 2253, '_cleanups.isEmpty && hold == null', 'false'),
    ('M16', B, 2628, 'if (child.isFinished) {', 'if (false) {'),
    ('M17', B, 2150, 'if (isFinished) {', 'if (false) {'),
    ('M18', B, 2191, 'if (isFinished) {', 'if (false) {'),
    ('M19', B, 2289, 'if (isFinished) {', 'if (false) {'),
    ('M20', B, 1532, 'replaced == null &&', ''),
]

# name, arguments, timeout in seconds: each word of the vocabulary on its own,
# with and without an event cutting in between microtasks, then all four.
def _c(words, steps, jobs, events, preempt=0):
    return ['--with', words, '--steps', str(steps), '--depth', '1', '--jobs', str(jobs),
            '--events', str(events), '--disrupt', '2', '--preempt', str(preempt)]


CONFIGS = [
    ('AB', _c('aband', 2, 2, 5), 60),
    ('TO', _c('timeout', 2, 2, 5), 60),
    ('AL1', _c('all', 1, 3, 4), 60),
    ('FRP', _c('free', 1, 2, 3, 1), 60),
    ('ABP', _c('aband', 2, 2, 4, 1), 120),
    ('ALP', _c('all', 1, 3, 3, 1), 180),
    ('TOP', _c('timeout', 2, 2, 4, 1), 240),
    ('MIX', _c('aband,free,all,timeout', 1, 3, 3), 600),
    ('FR', _c('free', 2, 2, 3), 600),
    ('AL', _c('all', 2, 3, 2), 600),
]
# The words of the third round, each next to the old words it meets; picked
# with SET=3.
CONFIGS3 = [
    ('DI', ['--with', 'disc', '--steps', '2', '--jobs', '2', '--events', '5'], 60),
    ('LO', ['--with', 'loose', '--steps', '2', '--jobs', '2', '--events', '5'], 60),
    ('RU', ['--with', 'rule', '--steps', '2', '--jobs', '2', '--events', '5'], 60),
    ('AN', ['--with', 'answer', '--steps', '2', '--jobs', '2', '--events', '3'], 120),
    ('DIA', ['--with', 'disc,all', '--steps', '1', '--jobs', '3', '--events', '4'], 120),
    ('LOT', ['--with', 'loose,timeout', '--steps', '2', '--jobs', '2', '--events', '4'], 240),
    ('RUF', ['--with', 'rule,free', '--steps', '2', '--jobs', '1', '--events', '4'], 600),
    ('RUA', ['--with', 'rule,all', '--steps', '1', '--jobs', '2', '--events', '4', '--preempt', '1'], 600),
    ('ANF', ['--with', 'answer,free', '--steps', '1', '--jobs', '3', '--events', '3', '--preempt', '1'], 600),
    ('ANA', ['--with', 'answer,all', '--steps', '1', '--jobs', '3', '--events', '3'], 600),
    ('DIAP', ['--with', 'disc,all', '--steps', '1', '--jobs', '3', '--events', '3', '--preempt', '1'], 600),
]
for _, a, _t in CONFIGS3:
    a += ['--depth', '1', '--disrupt', '2']
if os.environ.get('SET') == '3':
    CONFIGS = CONFIGS3
RSS_CAP_KB = 4 * 1024 * 1024


def rss_kb(pid):
    out = subprocess.run(['ps', '-o', 'rss=', '-g', str(pid)], capture_output=True, text=True).stdout
    return sum(int(x) for x in out.split() if x.isdigit())


def run_capped(cmd, cwd, timeout):
    p = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, start_new_session=True)
    start = time.time()
    verdict = None
    while p.poll() is None:
        if time.time() - start > timeout:
            verdict = 'timeout'
        elif rss_kb(p.pid) > RSS_CAP_KB:
            verdict = 'memory'
        if verdict:
            os.killpg(p.pid, signal.SIGKILL)
            break
        time.sleep(0.5)
    out = p.communicate()[0]
    return verdict, p.returncode, out, time.time() - start


def apply(path, line, old, new):
    lines = open(path).read().split('\n')
    text = lines[line - 1]
    if text.count(old) != 1:
        raise SystemExit(f'{path}:{line}: expected one {old!r} in {text!r}')
    lines[line - 1] = text.replace(old, new)
    with open(path, 'w') as f:
        f.write('\n'.join(lines))


def reach(path, line, mid):
    lines = open(path).read().split('\n')
    text = lines[line - 1]
    indent = text[:len(text) - len(text.lstrip())]
    lines.insert(line - 1, f"{indent}if (identical(1, 1)) throw UnsupportedError('reached {mid}');")
    with open(path, 'w') as f:
        f.write('\n'.join(lines))


def one(pkg, work, slot, mutant, configs):
    mid, rel, line, old, new = mutant
    copy = os.path.join(work, f'slot{slot}')
    for f in (B, C, 'tool/explore_core.dart'):
        shutil.copyfile(os.path.join(pkg, f), os.path.join(copy, f))
    if mid.startswith('R'):
        reach(os.path.join(copy, rel), line, mid)
    else:
        apply(os.path.join(copy, rel), line, old, new)
    exe = os.path.join(work, f'explore-{mid}')
    comp = subprocess.run(['dart', 'compile', 'exe', 'tool/explore_core.dart', '-o', exe],
                          cwd=copy, capture_output=True, text=True)
    result = {'id': mid, 'where': f'{rel}:{line}', 'runs': []}
    if comp.returncode != 0:
        result['verdict'] = 'did not compile'
        result['detail'] = (comp.stdout + comp.stderr)[-2000:]
        return result
    result['verdict'] = 'missed'
    if not configs:
        result['verdict'] = 'site not reached'
        return result
    for name, args, timeout in configs:
        verdict, code, out, secs = run_capped([exe, *args, '--stop-first'], copy, timeout)
        tail = out[-4000:]
        run = {'config': name, 'secs': round(secs, 1)}
        if verdict:
            run['result'] = verdict
        elif code == 1:
            run['result'] = 'caught'
        elif code == 0:
            run['result'] = 'clean'
        else:
            run['result'] = f'exit {code}'
        run['tail'] = tail
        result['runs'].append(run)
        if run['result'] == 'timeout' and name == 'B':
            result['verdict'] = 'undecided: B ran out of time'
            break
        if run['result'] != 'clean':
            result['verdict'] = f"{run['result']} by {name}"
            result['first'] = name
            break
    return result


def main():
    pkg, work = sys.argv[1], sys.argv[2]
    wanted = set(sys.argv[3:])
    reachable = [('R' + m[0][1:], m[1], m[2] - (1 if m[0] == 'M20' else 0), m[3], m[4])
                 for m in MUTANTS if m[0].startswith('M')]
    mutants = [m for m in MUTANTS + reachable if not wanted or m[0] in wanted]
    os.makedirs(work, exist_ok=True)
    slots = 3
    for s in range(slots):
        copy = os.path.join(work, f'slot{s}')
        if not os.path.exists(copy):
            shutil.copytree(pkg, copy, symlinks=True)
    results = []

    def phase(items, configs_for):
        queue = list(items)

        def worker(slot):
            while True:
                try:
                    m = queue.pop(0)
                except IndexError:
                    return
                r = one(pkg, work, slot, m, configs_for(m))
                print(f"{r['id']} {r['where']}: {r['verdict']} "
                      f"{[(x['config'], x['result'], x['secs']) for x in r['runs']]}", flush=True)
                results.append(r)

        with ThreadPoolExecutor(slots) as ex:
            list(ex.map(worker, range(slots)))

    # First where each site is executed at all, then each mutant only on the
    # bounds that execute its site: a mutant whose line never runs behaves as
    # the core does.
    phase([m for m in mutants if m[0].startswith('R')], lambda m: CONFIGS)
    first = {r['id'][1:]: r.get('first') for r in results if r['id'].startswith('R')}
    names = [c[0] for c in CONFIGS]

    def configs_for(m):
        if m[0].startswith('K') or m[0][1:] not in first:
            return CONFIGS
        f = first[m[0][1:]]
        return [] if f is None else CONFIGS[names.index(f):]

    phase([m for m in mutants if not m[0].startswith('R')], configs_for)
    results.sort(key=lambda r: r['id'])
    with open(os.path.join(work, os.environ.get('RESULTS', 'results.json')), 'w') as f:
        json.dump(results, f, indent=1)


if __name__ == '__main__':
    main()
```
