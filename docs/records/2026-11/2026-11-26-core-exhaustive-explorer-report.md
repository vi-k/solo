> **Состояние на 2026-11-26:** перебор собран вне пакета и прогнан на 20
> местах, которые прототип ступени 1 пропустил; в пакет и в CI не вошёл, код
> целиком в конце записи. Не поймал ни одного из 20: строки 9 мутантов он
> проходит, но поломка на его словаре снаружи не видна, до строк 11
> не доходит вовсе. Обе калибровочные поломки ловит за первые 30 путей.
> Брать ли его дальше, со словарём шире, не решено. Вопрос о ручном
> `finish` посреди размотки владелец решил тем же днём: оставить и описать —
> раздел «Ручной finish посреди размотки».
> **Что это:** шаги 0 и 1 плана перебора порядков на настоящем ядре, как
> в Coyote: зонд своей зоны и перебор в глубину по всем путям в границах
> на словаре прототипа с движком и ручным `finish`, проверенный на 20
> мутантах.
> **Связанные записи:** `2026-11-25-invariant-checking-plan.md` (план ступеней,
> прототип и 20 мест), `2026-11-26-core-tla-draft-report.md` (модель на TLA+),
> `2026-11-26-solo-invariant-spike-report.md` (такой же прототип на `Solo`).

# Полный перебор порядков на настоящем ядре

2026-11-26, по слову владельца «делай зонд и первый перебор на словаре
прототипа с движком и ручным finish, проверь на 20 мутантах». Ядро —
`async_job` на `1ded8216`, с правкой `abandonable` из `10575b00`.

## Устройство

Перебор без сохранения состояния, как в CHESS и Coyote. Всякий выбор — форма
тел, какое событие следующее, вклинится ли событие между двумя микрозадачами —
идёт через `Path.choose`. Путь — список выборов. Каждый путь проигрывается
заново от начала: снимков у Dart нет. Пути обходятся в глубину, следующий
получается из предыдущего сменой последнего выбора, у которого остались
варианты.

Микрозадачи и таймеры пути уходят в его собственную зону и идут по одной,
в порядке FIFO, как их ведёт Dart. Ядро не читает часов и не берёт случайных
чисел, поэтому путь определяется выборами целиком. Это проверяется дважды: при
переигрывании сверяется ширина каждого выбора, а каждый 997-й путь
проигрывается ещё раз, и журнал с исходами должен совпасть.

Сценарий. Тела задач собираются из шагов:

- `wait` — `ctx.join` на воротах;
- `hold` — `ctx.join` с `dispose`, который считает освобождения;
- `shield` — `ctx.uncancellable` на воротах; на входе и выходе проверяется, что
  задача не отмечена отменённой;
- `run[...]` — `ctx.run` ребёнка со своим телом.

Тело кончается значением или ошибкой. События: открыть ворота значением или
ошибкой, отменить задачу (`cancel`), кончить её руками (`finish` с `Done`,
`Failed` или `Cancelled`). Задача движка — `ProbeJob` из `test/support/`. Под
конец пути все неоткрытые ворота открываются значением, и очередь доигрывается.

Границы: `--steps` (шагов в теле), `--depth` (уровней детей), `--jobs` (задач
всего), `--events` (событий на путь), `--disrupt` (из них отмен и ручных
`finish`), `--preempt` (событий, которые вклиниваются между микрозадачами). Без
`--no-deepen` граница событий растёт от 1, и первым находится самый короткий
контрпример.

Оракулы — после каждого пути:

1. каждая задача кончилась, `onFinish` слышен ровно раз, исход после него
   не меняется;
2. задача, принявшая отмену (`whenCancelled`), кончилась `Cancelled`;
3. `Failed` слышен в `onError` ровно раз;
4. ручной `finish`: отметка отмены до него даёт `Cancelled`, иначе исход — тот,
   что передан;
5. родитель, не кончившийся руками, кончается после детей;
6. пришедший ресурс задачи без ручного `finish` освобождён ровно раз
   и до `onFinish`; двойное освобождение — нарушение всегда;
7. ресурс, взятый телом до ручного `finish`, когда размотка стека ещё
   не началась, ядро не освобождает: `finish` ничего не разматывает;
8. `cancel()` возвращается только у кончившейся задачи;
9. внутри `uncancellable` задача не отмечена отменённой;
10. в зону пути доходят только ошибки самого сценария и `StateError` «has
    already finished, cannot …» тела, которое после ручного `finish` зовёт
    контекст;
11. таймеров нет, `onError` не слышит `AssertionError`;
12. ни одна микрозадача и ни один таймер не ушли мимо зоны пути.

## Зонд: дыра в первой версии

Первая версия перебора создавала задачу-корень вне зоны пути, а задача
планирует микрозадачи в зоне, где её создали. Часть работы ядра уходила
в настоящий цикл событий, который во время пути не крутится. Оракулы её
не видели, а память росла на 2–4 КБ за путь, как только в пути появлялась
отмена: на границах B перебор упирался в 4 ГБ меньше чем за минуту. Отдельная
проба на 100 000 путей это показала: тело с `join` на воротах, созданных в зоне
пути, — 4 КБ на путь; тело без ожидания — 66 байт.

Исправление — корень создаётся внутри зоны пути, а весь перебор идёт внутри
внешней зоны, которая считает дошедшие до неё микрозадачи и таймеры: это
оракул 12. На старой ошибке он краснеет с первого же пути:

```text
VIOLATION (events<=1, path 1): 1 microtasks or timers escaped the zone of the run
```

После исправления память на всех трёх границах — 18–51 МБ.

Зонд в остальном пройден: вся работа ядра идёт через зону пути, задачи
кончаются без настоящего цикла событий, недетерминизма нет ни на одной границе.

## Чистое ядро

| Граница | Аргументы | Путей | Микрозадач | Время | Память |
| --- | --- | --- | --- | --- | --- |
| A | `--steps 2 --depth 1 --jobs 2 --events 5 --disrupt 2` | 83 946 | 574 468 | 0,8 с | 18 МБ |
| P | то же, `--events 4 --preempt 1` | 413 110 | 2 781 644 | 4,6 с | 22 МБ |
| B | `--steps 2 --depth 2 --jobs 3 --events 6 --disrupt 2 --no-deepen` | 5 617 192 | 55 159 914 | 98,5 с | 51 МБ |

Для A и P число путей — на последней ступени углубления. Нарушений нет.

Калибровка — две поломки, которые прототип ступени 1 пропускал:

- K1, `job_base.dart:1469`, `(_pendingCancel ?? outcome)` → `outcome` («отметка
  решает» при ручном `finish`): путь 8 на A;

  ```text
  root [wait value]; cancel j0; finish j0 by hand done
  => j0 accepted a cancellation and ended Done(hand0)
  ```

- K2, `:961`, `_uncancellableDepth > 0 && rejectable` → `false`: путь 29 на A,
  `root [shield value]; cancel j0` — задача отмечена отменённой внутри
  `uncancellable`.

## Ручной finish посреди размотки

Оракул 7 в первой редакции дважды покраснел на чистом ядре на P, где события
вклиниваются между микрозадачами. Оба раза ядро обещания не нарушало:

- `root [hold value]`, `finish` руками после второй микрозадачи за открытием
  ворот: тело уже вернуло значение, ядро разматывает стек и освободило ресурс
  до `finish`. Оракул считал любое освобождение, теперь — только освобождения
  после `finish`;
- `root [run[hold hold value] value]`, `finish` руками между освобождениями
  двух ресурсов ребёнка: первый освобождён до `finish`, второй — после.

Второй случай — то, о чём документы молчат. `finish` сам стека не разматывает
(«unwinds no cleanup stack», dartdoc `JobBase.finish`; таблица раздела
«Finishing a job by hand» в `doc/extending.md`), но и начатую размотку
не останавливает: цикл `_unwind` не смотрит на `isFinished`. На барьерах
`runAll` ядро ведёт себя иначе — ручной `finish` на барьере останавливает оба
прохода (`job_base.dart:2191`, `:2289`), и остаток держится, пока держат
задачу. Оракул сужен до задач, у которых размотка не началась; дырой это
не названо. Вопрос владельцу: должен ли ручной `finish` останавливать размотку,
которая уже идёт, как останавливает её на барьере.

Решено тем же днём. Разбор показал, что порядок намеренный: `conclude` прямо
разбирает задачу, которую движок кончил руками «while the stack unwound — from
a cleanup, or while one was awaited», а тест `when_finished_test.dart` «an
engine that ends a job by hand calls the listeners at once» закрепляет, что
уборка ниже по стеку выполняется после слушателей. Прототип остановки —
`_nextCleanup` отдаёт `null` на законченной задаче, второй проход
не начинается, `conclude` выбрасывает остаток стека — ронял четыре теста: этот
и три трассы `debug_test.dart`; остальные 1929 зелёные. Цена остановки —
открытое телом остаётся открытым, а движку до стека не добраться. Движок `solo`
до случая не доходит. Владелец: «Оставить, описать». Правило вписано абзацем
в «Finishing a job by hand» `doc/extending.md` ядра с переводом; dartdoc
`JobBase.finish` не тронут — его «unwinds no cleanup stack» верно о самом
`finish`, а предел в 30 строк новой фразы не вмещает, и dartdoc ссылается
на раздел страницы. Решение 166 в `docs/settled.md`.

## Двадцать мест

Места те же, что в разделе «Тесты на пропущенных прототипом» плана, номера
строк — на нынешнем ядре. Сначала каждое место проверено на досягаемость: перед
строкой вставлялся бросок `UnsupportedError`, и место достигнуто, если перебор
его встретил. Мутант гонялся только на границах, где его место достигнуто, —
на непройденной строке он ведёт себя как ядро.

Итог: калибровка поймана, из 20 мутантов не пойман ни один. Строки 9 мутантов
перебор проходит уже на A, и мутант чист на всех трёх границах; до строк 11 он
не доходит ни на одной из трёх.

| Мутант | Место | Правка | Досягаемо | Итог |
| --- | --- | --- | --- | --- |
| M01 | `job_base.dart:849` | `error is StackOverflowError && _outOfStack` → `_outOfStack` | нет | — |
| M02 | `job_context.dart:918` | без `error is StackOverflowError` | нет | — |
| M03 | `job_base.dart:2332` | `body is Failed && body.error is StackOverflowError` → `body is Failed` | нет | — |
| M04 | `job_base.dart:2358` | без `child.isFinished` | нет | — |
| M05 | `job_base.dart:2388` | `_status == JobStatus.created` → `false` | нет | — |
| M06 | `job_base.dart:970` | без `_isOwnTimeout(held)` | на A | чист на A, P и B (B — 177 с) |
| M07 | `job_base.dart:970` | без `!_isOwnTimeout(marked)` | на A | чист на A, P и B (B — 177 с) |
| M08 | `job_context.dart:702` | `_owner.bodyEnded && _inOwnFork` → `_inOwnFork` | на A | чист на A, P и B (B — 178 с) |
| M09 | `job_context.dart:1026` | `_owner.bodyEnded && !_inOwnFork` → `false` | нет | — |
| M10 | `job_context.dart:1095` | без `(fromFork \|\| !_owner.bodyEnded)` | нет | — |
| M11 | `job_base.dart:1686` | без `unmatched[i]` | на A | чист на A, P и B (B — 173 с) |
| M12 | `job_base.dart:1686` | без `identical(verdicts[i].failure, failure)` | на A | чист на A, P и B (B — 170 с) |
| M13 | `job_base.dart:2452` | без `identical(verdicts.error, outcome.error)` | на A | чист на A, P и B (B — 170 с) |
| M14 | `job_context.dart:1248` | `branches.isEmpty` → `false` | нет | — |
| M15 | `job_base.dart:2253` | `_cleanups.isEmpty && hold == null` → `false` | на A | чист на A, P и B (B — 143 с) |
| M16 | `job_base.dart:2628` | `if (child.isFinished)` → `if (false)` | нет | — |
| M17 | `job_base.dart:2150` | `if (isFinished)` → `if (false)` | на A | чист на A, P и B (B — 142 с) |
| M18 | `job_base.dart:2191` | `if (isFinished)` → `if (false)` | нет | — |
| M19 | `job_base.dart:2289` | `if (isFinished)` → `if (false)` | нет | — |
| M20 | `job_base.dart:1532` | без `replaced == null` | на A | чист на A, P и B (B — 141 с) |

Что это значит по местам:

- переполнение стека (`job_base.dart:849`, `job_context.dart:918`,
  `job_base.dart:2332`) и разорванный старт ребёнка (`:2358`, `:2388`) —
  словарь не переполняет стек; это и не предмет перебора;
- `unattended` и `abandonable` (`job_context.dart:702`, `:1026`, `:1095`) —
  в словаре их нет. `:702` достигнута, но без работы `unattended` звено
  `_inOwnFork` всегда ложно, и мутант равен ядру;
- дедлайн за `uncancellable` (оба звена `job_base.dart:970`) — строка идёт
  на всякой отмене внутри `shield`, но без таймаута звенья `_isOwnTimeout`
  ничего не решают;
- ответы `onError` по вердиктам (оба звена `:1686`, `:2452`) — строки идут,
  но вердикты без доменов и ответов `onError` пусты;
- барьеры `runAll` (`:2191`, `:2289`) и пустой `runAll`
  (`job_context.dart:1248`) — `runAll` в словаре нет;
- ожидание детей (`job_base.dart:2628`) — тело в словаре ждёт каждого ребёнка
  через `ctx.run`, и детей после конца тела не остаётся;
- `:2150` идёт на каждом пути; по разбору плана мутант на ней эквивалентен,
  и оракул 7, добавленный ради него, этого не опроверг;
- `:2253` (лишний проход уборки) и `:1532` (без `replaced == null`) — по плану
  первая видна только микрозадачей, вторая эквивалентна; перебор этого
  не опроверг.

Сводка с нацеленными тестами плана: из 20 мест тесты ловят 15, пять
эквивалентны или видны лишь необещанным. Перебор на этом словаре ничего к ним
не добавляет. Со словарём шире — таймаут, `unattended` и `abandonable`,
`runAll`, домены с ответами `onError`, дети, которых тело не ждёт, — он
доходил бы до 10 из 15 мест, которые ловят тесты; до пяти мест переполнения
стека и разорванного старта — нет.

## Вывод

Механизм работает и дёшев: 5,6 млн путей за 100 с на одном ядре процессора,
память ровная, детерминизм проверен, первый же контрпример — самый короткий,
и журнал пути читается как сценарий. Обе калибровочные поломки находятся
за десятки путей.

Предела словаря механизм не снимает. На 20 местах, которые выбирались как
непойманные прототипом, тот же словарь, перебранный полностью, тоже ничего
не ловит: прототип пропускал их не из-за случайности порядков, а потому что
словарь до этих мест не доходит или поломка на нём не видна. Ценность
перебора — в словаре, который будет шире словаря тестов; на нынешнем словаре он
повторяет тесты.

Побочно найдено одно: ручной `finish` не останавливает начатую размотку стека —
раздел выше.

## Как запустить

Файл перебора кладётся в `packages/async_job/tool/explore_core.dart`
и запускается из `packages/async_job`:

```sh
dart compile exe tool/explore_core.dart -o /tmp/explore
/tmp/explore --steps 2 --depth 1 --jobs 2 --events 5 --disrupt 2
```

Код выхода: 0 — нарушений нет, 1 — найдены (с `--stop-first` — на первом), 2 —
недетерминизм. Драйвер мутантов гоняет перебор в копиях пакета, со сторожем
памяти на группу процессов и потолком времени на границу:

```sh
python3 mutate.py <каталог пакета> <абсолютный каталог работы> [K1 M01 R01 ...]
```

`R01`…`R20` — пробы досягаемости, `M01`…`M20` — мутанты, `K1`, `K2` —
калибровка. Номера строк в драйвере — на `1ded8216`.

## Код перебора

```dart
// Exhaustive exploration of event orders on the real core, bounded.
//
// Every choice -- the shape of the bodies, which event comes next, whether an
// event cuts in between two microtasks -- goes through `Path.choose`. A path
// is the list of choices; the explorer replays each path from scratch (Dart
// has no snapshots) and walks them all in depth-first order, the way CHESS and
// Coyote do. The microtasks and timers of the run go to a zone of its own and
// run one at a time, in the FIFO order Dart keeps.
//
//   dart run tool/explore_core.dart [--steps N] [--depth N] [--jobs N]
//       [--events N] [--disrupt N] [--preempt N] [--no-hand] [--stop-first]

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:async_job/engine.dart';

import '../test/support/probe_job.dart';

// ---------------------------------------------------------------- config

final class Config {
  int steps = 2; // steps of a body before its end
  int depth = 1; // levels of children below the root
  int jobs = 2; // jobs in all, the root included
  int events = 6; // events a path may hold
  int disrupt = 2; // of them cancels and hand finishes
  int preempt = 0; // events that cut in between two microtasks
  bool hand = true; // an engine may finish a job by hand
  bool stopFirst = false;
  bool deepen = true; // raise the event bound one by one

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
        case '--no-hand':
          c.hand = false;
        case '--stop-first':
          c.stopFirst = true;
        case '--no-deepen':
          c.deepen = false;
        default:
          throw ArgumentError('unknown argument ${args[i]}');
      }
    }
    return c;
  }

  @override
  String toString() =>
      'steps=$steps depth=$depth jobs=$jobs events=$events disrupt=$disrupt '
      'preempt=$preempt hand=$hand';
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

  int choose(int width) {
    if (width <= 1) return 0;
    final i = choices.length;
    var c = 0;
    if (i < prefix.length) {
      if (prefixWidths[i] != width) {
        throw Nondeterminism(
          'choice $i had ${prefixWidths[i]} options, '
          'now $width',
        );
      }
      c = prefix[i];
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

final class Sched {
  final queue = ListQueue<void Function()>();
  final zoneErrors = <Object>[];
  int timers = 0;
  int ran = 0;

  late final Zone zone = Zone.current.fork(
    specification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, f) {
        queue.add(() => zone.runGuarded(f));
      },
      createTimer: (self, parent, zone, duration, f) {
        timers++;
        return _NoTimer();
      },
      createPeriodicTimer: (self, parent, zone, duration, f) {
        timers++;
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

final class Shield extends Step {
  @override
  String toString() => 'shield';
}

final class Run extends Step {
  Run(this.shape);
  final Shape shape;
  @override
  String toString() => 'run$shape';
}

final class Shape {
  Shape(this.steps, this.throws);
  final List<Step> steps;
  final bool throws;
  @override
  String toString() =>
      '[${[...steps, if (throws) 'throw' else 'value'].join(' ')}]';
}

final class Rec {
  Rec(this.id, this.parent);
  final int id;
  final Rec? parent;
  late final ProbeJob<Object?> job;
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
  @override
  String toString() => 'j$id';
}

final class Gate {
  Gate(this.id, this.owner, this.kind);
  final int id;
  final Rec owner;
  final String kind;
  final c = Completer<Object?>();
  bool opened = false;
  @override
  String toString() => 'g$id($kind of $owner)';
}

final class Res {
  Res(this.id);
  final int id;
  bool arrived = false;
  int disposed = 0;
  // The body has the value: the core has put its cleanup on the stack.
  bool registered = false;
  // Registered when an engine finished the job by hand before the core began
  // to unwind its stack: `finish` unwinds nothing, so the core must not
  // dispose of it. An unwind under way when `finish` comes goes on to the
  // end; no document says whether it should.
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
  final byJob = Map<Job<Object?>, Rec>.identity();
  final log = <String>[];
  final violations = <String>[];
  late final Obs obs = Obs(this);
  int clock = 0;
  int jobsMade = 1;
  late int eventsLeft = eventBound;
  late int disruptLeft = cfg.disrupt;
  late int preemptLeft = cfg.preempt;
  int resCount = 0;
  bool anyHand = false;

  void violate(String message) {
    violations.add(message);
    throw Violation(message);
  }

  // A violation found inside the core's own callbacks must not be swallowed
  // by its error routes: note it and carry on, the run stops afterwards.
  void note(String message) => violations.add(message);

  Shape shape(int depth) {
    final n = path.choose(cfg.steps + 1);
    final steps = <Step>[];
    for (var i = 0; i < n; i++) {
      final canRun = depth < cfg.depth && jobsMade < cfg.jobs;
      final k = path.choose(canRun ? 4 : 3);
      switch (k) {
        case 0:
          steps.add(Wait());
        case 1:
          steps.add(Hold());
        case 2:
          steps.add(Shield());
        default:
          jobsMade++;
          steps.add(Run(shape(depth + 1)));
      }
    }
    return Shape(steps, path.choose(2) == 1);
  }

  Rec newRec(Rec? parent, Shape s) {
    final rec = Rec(recs.length, parent);
    recs.add(rec);
    final job = ProbeJob<Object?>((ctx) => body(rec, s, ctx), observer: obs);
    rec.job = job;
    byJob[job] = rec;
    job.whenCancelled((_) => rec.accepted = true);
    return rec;
  }

  Gate newGate(Rec owner, String kind) {
    final g = Gate(gates.length, owner, kind);
    gates.add(g);
    return g;
  }

  void checkShield(Rec rec, String where) {
    if (rec.shield > 0 && !rec.hand && rec.job.isCancelled) {
      note('$rec is marked cancelled inside uncancellable ($where)');
    }
  }

  Future<Object?> body(Rec rec, Shape s, JobContext ctx) async {
    for (final step in s.steps) {
      switch (step) {
        case Wait():
          final g = newGate(rec, 'wait');
          await ctx.join(() => g.c.future);
        case Hold():
          final g = newGate(rec, 'hold');
          final r = Res(resCount++);
          rec.res.add(r);
          await ctx.join<Res>(
            () => g.c.future.then((_) {
              r.arrived = true;
              return r;
            }),
            dispose: (v) {
              v.disposed++;
              if (v.disposed > 1) note('resource ${v.id} disposed twice');
            },
          );
          r.registered = true;
        case Shield():
          final g = newGate(rec, 'shield');
          await ctx.uncancellable(() async {
            rec.shield++;
            checkShield(rec, 'enter');
            try {
              await g.c.future;
            } finally {
              checkShield(rec, 'leave');
              rec.shield--;
            }
          });
        case Run(:final shape):
          final child = newRec(rec, shape);
          if (rec.job.isFinished) child.turnedAway = true;
          await ctx.run(child.job);
      }
    }
    if (s.throws) throw BodyError(rec.id);
    return 'v${rec.id}';
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
    }
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
            gate.c.completeError(GateError(gate.id));
          }
        case Cancel(:final rec):
          disruptLeft--;
          final job = rec.job;
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
            for (final r in rec.res) {
              r.keptByHand = r.registered && !unwinding;
            }
          }
          rec.hand = true;
          try {
            job.drop(outcome);
          } on Object catch (error) {
            note('finish of $rec threw $error');
          }
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
      ..outcomeAtFinish ??= job.outcome;
    if (!rec.hand) {
      for (final r in rec.res) {
        if (r.arrived && r.disposed != 1) {
          note('$rec finished before resource ${r.id} was disposed');
        }
      }
    }
  }

  void endChecks() {
    if (sched.timers > 0) note('a timer was made: ${sched.timers}');
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
      if (o case Failed(:final error)) {
        final heard = rec.errors.where((e) => identical(e, error)).length;
        if (heard != 1) note('$rec: onError heard its failure $heard times');
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
        if (r.arrived && !rec.hand && r.disposed != 1) {
          note('resource ${r.id} of $rec disposed ${r.disposed} times');
        }
        if (r.keptByHand && r.disposed != 0) {
          note(
            'resource ${r.id} of $rec was disposed of after a finish by '
            'hand',
          );
        }
      }
    }
    for (final e in sched.zoneErrors) {
      final ours = e is GateError || e is BodyError || e is HandError;
      // A body that goes on after an engine finished its job by hand meets
      // the finished context at its next call, and that failure reaches the
      // zone: nothing else of the core may.
      final late =
          e is StateError &&
          anyHand &&
          e.message.contains('has already finished, cannot');
      if (!ours && !late) note('zone heard $e');
    }
  }

  String summary() => [
    for (final rec in recs) '$rec ${rec.job.outcome}',
    'zone ${sched.zoneErrors}',
  ].join('; ');
}

final class Obs extends JobObserver {
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
    run.byJob[job]?.errors.add(error);
    if (error is AssertionError || error is UnsupportedError) {
      run.note('onError heard $error');
    }
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

# name, arguments, timeout in seconds. A run of A or P that outlives its
# timeout hangs: unmutated, A takes about 2 s and P about 8.
CONFIGS = [
    ('A', ['--steps', '2', '--depth', '1', '--jobs', '2', '--events', '5', '--disrupt', '2'], 120),
    ('P', ['--steps', '2', '--depth', '1', '--jobs', '2', '--events', '4', '--disrupt', '2', '--preempt', '1'], 240),
    ('B', ['--steps', '2', '--depth', '2', '--jobs', '3', '--events', '6', '--disrupt', '2', '--no-deepen'], 1800),
]
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
