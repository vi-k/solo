> **Состояние на 2026-11-26:** словарь перебора расширен таймаутом,
> `unattended`, `abandonable` и `runAll`, перебор прогнан на тех же 20 местах;
> в пакет и в CI не вошёл, код целиком в конце записи. Он теперь проходит
> строки 14 мутантов из 20 (было 9) и не ловит ни одного. Обе прежние
> калибровочные поломки и две новые, по дедлайну и по `unattended`, ловит
> за первые сотни путей. На чистом ядре нарушений нет. Слова, названные
> в выводе, добавлены третьим шагом и поймали M08, M11, M12 и M19 —
> `2026-11-26-core-explorer-domain-report.md`.
> **Что это:** второй шаг перебора порядков на настоящем ядре: новые слова,
> оракулы к ним, прогон на 20 мутантах и разбор, почему достигнутые места
> остаются невидимыми.
> **Связанные записи:** `2026-11-26-core-explorer-domain-report.md`
> (третий шаг: домен, `discard`, секция без `await`),
> `2026-11-26-core-exhaustive-explorer-report.md`
> (первый перебор, его устройство и оракулы 1–12),
> `2026-11-25-invariant-checking-plan.md` (план ступеней и 20 мест).

# Перебор порядков на ядре: словарь шире

2026-11-26, по слову владельца «расширь словарь перебора: таймаут, unattended,
abandonable, runAll». Ядро — `async_job` 1.0.5 (`2b728670`); `lib/`
с `1ded8216`, на котором гонялся первый перебор, не менялся, номера строк
мутантов те же.

## Что добавлено

Устройство перебора прежнее: путь — список выборов, каждый путь проигрывается
с начала, микрозадачи идут по одной в зоне пути. Новые слова включаются ключом
`--with aband,free,all,timeout`; без ключа словарь прежний, и на границе A
первого перебора выходят те же 83 946 путей.

Шаги тела:

- `aband` — `ctx.abandonable` на воротах, с `dispose`, который считает
  освобождения;
- `free[...]` — `ctx.unattended` с работой из шагов `wait`, `hold` и `aband`;
  работа кончается значением или ошибкой `WorkError`;
- `all(...)` — `ctx.runAll` на 0, 1 или 2 ветки, каждая — задача со своим
  телом.

Дедлайн. Каждая задача выбирает, есть ли у неё `timeout`. Таймеры зоны пути
больше не запрещены: каждый становится `FakeTimer`, который сам не срабатывает.
Событие «задача исчерпала время» вызывает его, расходуя тот же бюджет
`--disrupt`, что отмена и ручной `finish`. Ядро взводит таймер прямо перед
`started`, и хук `started` приписывает последний взведённый таймер своей
задаче.

Задача — свой подкласс `JobBase` с `timeout`, а не `ProbeJob`
из `test/support/`: у того нет дедлайна. Перебор теперь зависит только
от `package:async_job/engine.dart`.

## Новые оракулы

Нумерация продолжает оракулы 1–12 первого перебора.

13. Исход идёт за телом. Задача без ручного `finish`, не принявшая отмену,
    кончается `Done` со значением тела, если тело вернуло значение, и `Failed`
    с той же ошибкой, если тело бросило не отмену. Работа `unattended`, уборка
    и группы исход не меняют.
14. Дедлайн. Задача, чей таймер сработал, пока она шла и не была кончена
    руками, кончается `Cancelled`. К `onFinish` таймер снят, к концу пути
    взведённых таймеров нет, периодических не бывает.
15. Группа, без ручного `finish` в ней и у родителя. Отдала список — каждая
    ветка кончилась `Done` со значением из списка, и оно — значение её тела.
    Бросила — к этому моменту все ветки кончились и всё, что ветки взяли (кроме
    ресурсов работы `unattended`), освобождено; ни одна ветка не кончилась
    `Done`; брошено одно из падений веток, а если ни одна ветка не кончилась
    `Failed` — отмена.
16. Ошибки сценария — тела, работы, ворот, которых ядро ждало, — слышит
    `onError` той задачи, где они случились, и ни одна задача не слышит одну
    ошибку дважды.
17. Ни одна ошибка сценария не доходит до зоны дважды. Не доходит вовсе только
    та, что стала исходом `Failed` какой-то задачи: её наблюдают через задачу —
    родитель или `done` корня.

Уточнены прежние. Оракул 6 (ресурс освобождён до `onFinish`) для `hold` смотрит
на пришедшие значения, для `aband` и работы — на значения, которые вызов отдал:
значение, пришедшее к брошенному вызову, освобождается при приходе, и это
бывает после `onFinish`. Оракул 10 пропускает ещё `StateError` «is cleaning up
after its body, cannot …» и «has already finished, cannot …» от работы
`unattended`, которая зовёт контекст во время размотки или после конца задачи.
Из оракула 11 «таймеров нет» заменено оракулом 14, запрет на `AssertionError`
в `onError` остался.

Оракул 15 в первой редакции брал в «падения» и падения тел. Он покраснел
на чистом ядре: `root [all([shield throw]) value]`, `cancel j0` — ветка
принимает отмену внутри `shield`, потом её тело бросает, и группа бросает
отмену. Ветка кончилась `Cancelled`, её падение ушло в `onError`, как у ребёнка
`ctx.run`, который принял отмену до падения тела. Оракул сужен до исходов
`Failed`; дырой это не названо.

Оракулы 16 и 17 появились после первого прогона мутантов. До того оракул 16
засчитывал ошибку, если её слышал `onError` любой задачи. Мутанты барьеров
меняют маршрут ответа за падение тела, поэтому оракул сделан строже, а маршрут
до зоны проверен оракулом 17. Мутантов это не поймало, см. ниже.

## Чистое ядро

У каждой границы `--depth 1 --disrupt 2`; число путей — на последней ступени
углубления, память — пик процесса.

| Граница | Словарь | Аргументы | Путей | Время | Память |
| --- | --- | --- | --- | --- | --- |
| AB | aband | `--steps 2 --jobs 2 --events 5` | 170 094 | 1,8 с | 28 МБ |
| TO | timeout | `--steps 2 --jobs 2 --events 5` | 419 036 | 5,0 с | 44 МБ |
| AL1 | all | `--steps 1 --jobs 3 --events 4` | 151 120 | 2,7 с | 31 МБ |
| FRP | free | `--steps 1 --jobs 2 --events 3 --preempt 1` | 7 486 | 0,07 с | 17 МБ |
| ABP | aband | `--steps 2 --jobs 2 --events 4 --preempt 1` | 937 454 | 10,3 с | 49 МБ |
| ALP | all | `--steps 1 --jobs 3 --events 3 --preempt 1` | 991 856 | 18,8 с | 49 МБ |
| TOP | timeout | `--steps 2 --jobs 2 --events 4 --preempt 1` | 2 028 864 | 24,7 с | 49 МБ |
| MIX | все четыре | `--steps 1 --jobs 3 --events 3` | 3 345 740 | 71,6 с | 49 МБ |
| FR | free | `--steps 2 --jobs 2 --events 3` | 5 680 862 | 78,7 с | 49 МБ |
| AL | all | `--steps 2 --jobs 3 --events 2` | 4 732 746 | 81,7 с | 49 МБ |

Нарушений нет ни на одной. Границы уже, чем у первого перебора: форм тел стало
много. `free` с тремя задачами до одного события дал 6 млн путей за 212 с,
`all` с тремя задачами и двумя шагами растёт примерно в девять раз на событие —
до четырёх событий вышло бы около двух часов.

Калибровка — четыре поломки:

- K1 и K2 первого перебора — пойманы на AB, на первых десятках путей;
- K3, `job_base.dart:1380`, дедлайн не отменяет задачу (`cancelWith(...)` →
  `reason.toString();`): путь 537 на TO,

  ```text
  root [run[timeout wait value] value]
  j1 runs out of time
  => j1 ran out of time and ended Done(v1)
  ```

- K4, `job_context.dart:1504`, ошибка работы `unattended` не объявляется
  (`notifyError(...)` убран): путь 81 на FRP, `root [free[throw] value]` —
  `WorkError(j0) of j0 never reached its onError`.

## Двадцать мест

Тот же драйвер, что в первом переборе, с новыми границами; сначала пробы
досягаемости, потом мутант на границах начиная с первой, где место достигнуто.
Оракулы 16 и 17 в окончательном виде гонялись на 14 достигнутых мутантах
и калибровке вторым прогоном; итог тот же.

| Мутант | Место | Правка | Досягаемо | Итог |
| --- | --- | --- | --- | --- |
| M01 | `job_base.dart:849` | `error is StackOverflowError && _outOfStack` → `_outOfStack` | нет | — |
| M02 | `job_context.dart:918` | без `error is StackOverflowError` | нет | — |
| M03 | `job_base.dart:2332` | `body is Failed && body.error is StackOverflowError` → `body is Failed` | нет | — |
| M04 | `job_base.dart:2358` | без `child.isFinished` | нет | — |
| M05 | `job_base.dart:2388` | `_status == JobStatus.created` → `false` | нет | — |
| M06 | `job_base.dart:970` | без `_isOwnTimeout(held)` | на AB | чист на всех десяти |
| M07 | `job_base.dart:970` | без `!_isOwnTimeout(marked)` | на AB | чист на всех десяти |
| M08 | `job_context.dart:702` | `_owner.bodyEnded && _inOwnFork` → `_inOwnFork` | на AB | чист на всех десяти |
| M09 | `job_context.dart:1026` | `_owner.bodyEnded && !_inOwnFork` → `false` | нет | — |
| M10 | `job_context.dart:1095` | без `(fromFork \|\| !_owner.bodyEnded)` | на AB | чист на всех десяти |
| M11 | `job_base.dart:1686` | без `unmatched[i]` | на AB | чист на всех десяти |
| M12 | `job_base.dart:1686` | без `identical(verdicts[i].failure, failure)` | на AB | чист на всех десяти |
| M13 | `job_base.dart:2452` | без `identical(verdicts.error, outcome.error)` | на AB | чист на всех десяти |
| M14 | `job_context.dart:1248` | `branches.isEmpty` → `false` | на AL1 | чист на всех десяти |
| M15 | `job_base.dart:2253` | `_cleanups.isEmpty && hold == null` → `false` | на AB | чист на всех десяти |
| M16 | `job_base.dart:2628` | `if (child.isFinished)` → `if (false)` | на AL1 | чист на всех десяти |
| M17 | `job_base.dart:2150` | `if (isFinished)` → `if (false)` | на AB | чист на всех десяти |
| M18 | `job_base.dart:2191` | `if (isFinished)` → `if (false)` | на AL1 | чист на всех десяти |
| M19 | `job_base.dart:2289` | `if (isFinished)` → `if (false)` | на AL1 | чист на всех десяти |
| M20 | `job_base.dart:1532` | без `replaced == null` | на AB | чист на всех десяти |

Что видно по местам:

- переполнение стека и разорванный старт (M01–M05) — не предмет перебора;
- M09, `job_context.dart:1026`, синхронное действие `abandonable` от кода,
  который не тело и не его работа, после конца тела — такого вызова в словаре
  нет;
- M06, M07, `job_base.dart:970`, отмена за дедлайном, который держит секция
  `uncancellable`. Строка идёт на всякой отмене внутри `shield`, но разница
  видна, только когда дедлайн снимается при живой секции: тело должно
  кончиться, не дождавшись `uncancellable`. В словаре `shield` всегда
  дожидаются;
- M08, `job_context.dart:702`, и M14, `job_context.dart:1248`, — вызов
  из работы при живом теле идёт веткой работы, пустая группа идёт через
  `_RunAllGroup`. Обе ветки отличаются только проверкой правил домена, а домена
  в словаре нет;
- M11–M13 — ответы `onError` по вердиктам доменов, их в словаре нет;
- M15 и M16 — лишний проход по пустому стеку и ожидание уже кончившегося
  ребёнка: только лишняя микрозадача;
- M17 и M18 — ручной `finish` во время ожидания детей и на первом барьере. Там
  `finish` уже выбросил стек (`if (!_disposing) _Cleanup.dropAll`),
  и продолжать нечего; на одном пути — `all([hold value] [wait value])`, ворота
  `hold` открыты, `finish` ветки руками, ворота `wait` открыты — ядро и мутант
  M18 дали один исход, одни освобождения и одно состояние размотки. Ветка,
  которую мутант пропускает, ещё отвечает за падение тела, но оракул 17 разницы
  на этом маршруте не увидел;
- M19, `job_base.dart:2289`, ручной `finish` на втором барьере — остаток там
  выбрасывается, а остаток — это `discard`, отложенные первым проходом.
  В словаре только `dispose`;
- M10, `job_context.dart:1095`, — место достигнуто на AB, мутант чист на всех
  десяти границах; почему, не разбиралось;
- M20 — эквивалентен по плану.

## Вывод

Четыре слова сделали то, что могли: перебор теперь проходит строки 14 мест
из 20, и обе новые калибровочные поломки находит за сотни путей. Поймать
мутанта они не помогли. Пять мест — переполнение стека и разорванный старт —
не предмет перебора. На девяти достигнутых разница живёт в том, чего в словаре
по-прежнему нет: правила и вердикты домена (M08, M11–M14), `discard` (M19),
секция, которую тело не дождалось (M06, M07), — или видна только по числу
микрозадач (M15, M16). M17, M18 и M10 не видны на нынешних оракулах, M20
эквивалентен.

Следующие слова, если брать перебор дальше, — по этому списку: домен с правилом
в `check()` и ответом `onError`, `discard` рядом с `dispose`, `uncancellable`
без `await`. Каждое умножает формы тел, и границы придётся сужать дальше: цена
слова видна по таблице выше.

## Как запустить

Как в первом переборе, плюс ключ словаря:

```sh
dart compile exe tool/explore_core.dart -o /tmp/explore
/tmp/explore --with aband,free,all,timeout --steps 1 --depth 1 --jobs 3 \
  --events 3 --disrupt 2
```

Драйвер мутантов — тот же, с новыми границами и калибровками K3 и K4:

```sh
python3 mutate.py <каталог пакета> <абсолютный каталог работы> [K1 M01 R01 ...]
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
//       [--with aband,free,all,timeout] [--no-hand] [--stop-first]

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
      'free=$free all=$all timeout=$timeout';
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
  XJob(this._body, this._onStarted, {super.observer, super.timeout});
  final Future<Object?> Function(JobContext ctx) _body;
  final void Function() _onStarted;

  @override
  void started() => _onStarted();

  void launch() => start();

  void drop(Outcome<Object?> outcome) => finish(outcome);

  @override
  JobContextBase createContext() => XContext(this);

  @override
  Future<Object?> execute(covariant XContext ctx) => _body(ctx);
}

final class XContext extends JobContextBase {
  XContext(super.owner);
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
  @override
  String toString() => 'g$id($kind of $owner)';
}

final class Res {
  Res(this.id, this.kind);
  final int id;
  final String kind; // hold, aband, or work: taken by unattended work
  bool arrived = false;
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
  late final Obs obs = Obs(this);
  int clock = 0;
  int jobsMade = 1;
  late int eventsLeft = eventBound;
  late int disruptLeft = cfg.disrupt;
  late int preemptLeft = cfg.preempt;
  int resCount = 0;
  bool anyHand = false;
  bool anyWork = false;

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
        if (!work) ...[
          'shield',
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
    gates.add(g);
    return g;
  }

  void checkShield(Rec rec, String where) {
    if (rec.shield > 0 && !rec.hand && rec.job.isCancelled) {
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
      r.arrived = true;
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
      rethrow;
    }
    rec.bodyReturned = true;
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
          await ctx.join(() {
            g.taken = true;
            return g.c.future;
          });
        case Hold():
          final g = newGate(rec, 'hold');
          final r = Res(resCount++, work ? 'work' : 'hold');
          rec.res.add(r);
          await ctx.join<Res>(resource(g, r), dispose: dispose);
          r.registered = true;
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
        case Run(:final shape):
          final child = newRec(rec, shape);
          if (rec.job.isFinished) child.turnedAway = true;
          await ctx.run(child.job);
        case All(:final shapes):
          final branches = [for (final s in shapes) newRec(rec, s)];
          final group = Group(groups.length, rec, branches);
          groups.add(group);
          for (final b in branches) {
            b.group = group;
            if (rec.job.isFinished) b.turnedAway = true;
          }
          try {
            group.values = await ctx.runAll<Object?>([
              for (final b in branches) b.job,
            ]);
          } on Object catch (e) {
            group.thrown = e;
            atThrow(group);
            rethrow;
          }
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
            final error = GateError(gate.id);
            if (gate.taken) ours.add((error, gate.owner));
            gate.c.completeError(error);
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
        case Expire(:final timer):
          disruptLeft--;
          final owner = timer.owner!;
          timer
            ..active = false
            ..fired = true
            ..firedLive = !owner.job.isFinished && !owner.hand;
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
      ..outcomeAtFinish ??= job.outcome;
    if (rec.timer case final t? when t.active) {
      note('$rec finished with its deadline still armed');
    }
    if (!rec.hand) {
      for (final r in rec.res) {
        // A value the body waited for is released before the job ends; one
        // that arrived for a call nobody waits for any more is released on
        // arrival, which may come after.
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
      if (o case Failed(:final error)) {
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
    groups.forEach(groupChecks);
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
      final n = sched.zoneErrors.where((x) => identical(x, e)).length;
      final outcome = recs.any((r) {
        final o = r.job.outcome;
        return o is Failed && identical(o.error, e);
      });
      if (n > 1 || n == 0 && !outcome) {
        note('$e of $owner reached the zone $n times');
      }
    }
    for (final e in sched.zoneErrors) {
      final mine =
          e is GateError || e is BodyError || e is WorkError || e is HandError;
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
      if (thrown is! Cancelled) note('$group threw $thrown with no failure');
    } else if (!failures.any((f) => identical(f, thrown))) {
      note('$group threw $thrown, not one of the failures $failures');
    }
  }

  String summary() => [
    for (final rec in recs) '$rec ${rec.job.outcome}',
    for (final g in groups) '$g ${g.values ?? g.thrown}',
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
    ('K3', B, 1380, 'cancelWith(Cancelled.by(reason: reason, stackTrace: _timeoutTrace));', 'reason.toString();'),
    ('K4', C, 1504, 'notifyError(error, stackTrace);', ''),
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
