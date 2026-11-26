> **Состояние на 2026-11-26:** прототип собран вне дерева и прогнан
> на мутантах движка `solo`; в пакет и в CI не вошёл. Брать ли ступень 1
> на `solo`, не решено.
> **Что это:** прототип ступени 1 на настоящем `Solo` — случайные цепочки
> событий с проверкой инвариантов после каждого — и его сравнение с тестами
> `solo` на 241 мутанте движка; код прототипа целиком в конце.
> **Связанные записи:** `2026-11-25-invariant-checking-plan.md` (план ступеней
> и такой же прогон на ядре), `2026-11-26-core-tla-draft-report.md`.

# Прототип ступени 1 на solo

## Что просили

2026-11-26 владелец спросил, нужна ли первая ступень для `solo`, и затем
попросил: «делай прототип ступени 1 на solo и прогони на мутантах». Образец —
прототип на ядре и его прогон на 408 мутантах
из `2026-11-25-invariant-checking-plan.md`: там поломки, которую ловит только
прототип, не нашлось. Вопрос тот же: ловит ли генератор в движке `solo` то, что
тесты пропускают.

## Как устроен

Одна программа на 830 строк вне дерева, на `solo` и `async_job` из дерева под
`fakeAsync`. Контроллер — наследник `Solo<int>` с состоянием 0..2 и открытыми
`enqueueJob`, `job`, `queue`, `current` и `externalSetState`.

Сценарий по seed строит четыре описания корневых задач и цепочку от 4 до 15
событий. Описание задачи:

- ключ `a`, `b` или без ключа, и одна из четырёх политик (без ключа только
  `sequential`);
- `cancellable: false` в пятой части случаев;
- `canStart` и `keepWhile` вида «состояние не равно N»;
- `ifFailed` и `ifCancelled`, отвечающие числом;
- тело из шагов `wait` (`ctx.join` на воротах), `hold` (то же с `dispose`),
  `shield` (`ctx.uncancellable` на воротах), `emit(N)` и `run` (ребёнок через
  `ctx.run` со своим телом, один уровень); тело кончается значением или
  бросает. Отмену ребёнка тело ловит и зовёт `ctx.check()`, поэтому само
  бросает отмену только по своей отметке.

События: поставить задачу по описанию; открыть одни из открытых ворот значением
или ошибкой; `cancel()` одной из созданных задач; `cancelAll` и `queue.clear`
с `force` и без; `externalSetState(N)`; `close` с `cancel` или `drain`, в том
числе второй раз; повторная постановка уже поставленной задачи; `emit` через
контекст кончившейся задачи. Номер цели берётся по модулю, поэтому выкинутое
при урезании событие не ломает остальные. После каждого события
`elapse(Duration.zero)` и проверки; в конце все ворота открываются значением,
контроллер закрывается, таймеры сбрасываются.

Что проверялось:

- корневая задача стартует, только когда никакая другая не идёт (инвариант 1),
  при верном `canStart` и не после `close(cancel)`;
- после `externalSetState` работающая задача с ложным `keepWhile`, не кончившая
  тело, отмечена отменённой (инвариант 2);
- принявшая отмену кончается `Cancelled` (инвариант 3);
- каждый `Failed` слышен в `onError` ровно один раз (инвариант 4);
- `onFinish` ровно один раз, каждый пришедший ресурс убран ровно один раз,
  родитель кончается после детей;
- `cancel()` возвращается после конца задачи, `cancelAll` — после конца
  отменяемых работающих;
- `droppable` не ставит вторую задачу ключа, а отдав чужую, кончает новую
  `Cancelled(duplicate)`; `keepLatest` и `restart` не оставляют в очереди
  отменяемую задачу того же ключа, а снятая кончается `Cancelled`; `restart`
  отменяет текущую того же ключа, если она отменяемая и не в секции
  `uncancellable`;
- `clear` без `force` оставляет ровно `cancellable: false`, с `force` снимает
  всё;
- `close(cancel)` снимает очередь `Cancelled(closed)`, `drain` не снимает;
  задача, поставленная после `close`, кончается `Cancelled(closed)`; `close`
  возвращается, когда кончилось всё и очередь пуста (инвариант 7);
- `emit` через контекст кончившейся задачи бросает `StateError` и состояния
  не меняет (инвариант 8); `externalSetState` отказывает `StateError` после
  конца закрытия и только тогда;
- `cancellable: false` после постановки принимает только отмену своими
  правилами, а в очереди — ещё `close(cancel)` и `clear(force: true)`; внутри
  `uncancellable` задача не принимает чужой отмены (инвариант 9);
- повторная постановка бросает `StateError` и не трогает ни очередь, ни исход;
- ни одной ошибки в зоне, кроме отмен и ошибок самих тел.

Урезание выкидывает события по одному, пока нарушение держится, и печатает
описания, урезанную цепочку и журнал.

По дороге прототип трижды кричал зря, и все три раза ошибался он сам: `restart`
не отменяет текущую задачу посреди её секции `uncancellable`, а придерживает
отмену до конца секции (инвариант 9); `cancelAll` отвечает за задачи, которые
были на момент вызова, а не за поставленные после; `externalSetState` после
конца закрытия бросает `StateError` — это его обещание (`solo.dart:382`),
а не ошибка.

## Прогон на дереве

20 000 сценариев, 190 828 событий, около трёх секунд: нарушений нет. Стартовало
41 229 задач; исходы — 23 828 `Done`, 8351 `Failed` и отмены: 13 866 `closed`,
7574 `rules`, 7364 `manual`, 2671 `replaced`, 2416 `duplicate`, 1714 `parent`.

## Генератор против тестов

Мутанты делались механически, как на ядре, в `solo.dart`, `queue.dart`,
`job.dart`, `job_context.dart` и `lane.dart` на `1ded8216`. Грубый оператор:
каждое однострочное `if (условие) {` по очереди становилось `if (false) {`
и `if (!(условие)) {` — 174 мутанта. Тонкий: из каждого `if`, чьё условие —
цепочка `&&` или `||`, по очереди выкидывалось одно звено — 67 мутантов.
На каждом шли прототип на 20 000 сценариев с потолком 120 с и все тесты `solo`
(`dart test -j 3`, 2498 тестов, на дереве 7 с) с потолком 300 с, в четыре
потока, со сторожем памяти в 4 ГБ на группу процессов. Прототип в этом прогоне
ещё не знал двух событий — второго `close` и повторной постановки: их добавили
потом, для мутантов, которых не поймал никто.

| | Грубые | Тонкие | Всего |
|---|---|---|---|
| Не собрались | 54 | 17 | 71 |
| Ловят оба | 44 | 11 | 55 |
| Ловят только тесты | 70 | 27 | 97 |
| Ловит только прототип | 0 | 0 | 0 |
| Не ловит никто | 6 | 12 | 18 |

Что прототип поймал: чаще всего — «`close` так и не вернулся» (15),
«`keepLatest` оставил в очереди задачу того же ключа» (7), ошибка в зоне (5),
старт при ложном `canStart` (4); остальные правила — по одной-три поимки. Тесты
на этих 55 падают от 12 штук и больше, а на 13 набор не укладывается в 300 с —
зависает; прототип на тех же 13 печатает урезанную цепочку за секунды.

Чего прототип не поймал, а тесты поймали: 97 мутантов, на 21 из них падает
ровно один тест. Это места вне словаря генератора: накопление, линии, таймеры
и `timeout`, отладочный режим, тексты ошибок, хуки, которые бросают.

## Не ловит никто

18 мутантов. Прототип, научившийся второму `close` и повторной постановке,
прогнан на них ещё раз — не поймал ни одного.

- Эквивалентны:
  - `solo.dart:998`, без `queue._has(impl)` в проверке повторной постановки —
    поставленную задачу уже отсекает `_taken`, его ставит та же функция
    (`:1032`);
  - `solo.dart:1245`, без `_draining` в конце прохода — `drained` растёт только
    во время осушения, а ядро у контроллера есть всегда;
  - `solo.dart:1216`, `if (false)` вместо `_pumpScheduled` — лишний проход
    насоса, который ничего не находит.
- Меняют только текст: шесть мутантов `job.dart:359` (какие значения ошибки
  печатать как есть, то же место, что `job_base.dart:409` в ядре)
  и `solo.dart:1364` (подсказка отладочного режима).
- Меняют путь кода, вне словаря прототипа и не пойманы тестами:
  - `solo.dart:1232`, проход не останавливается на `close(cancel)` — видно
    только у `SoloLanes`, где ядер больше одного;
  - `solo.dart:1174`, без первого `_goingOn(transition)` — правила старта
    спрашиваются и у задачи на пороге, которую уже отменили;
  - `job.dart:140`, без проверки, что ребёнок того же контроллера;
  - `job.dart:485`, без `_isExpectedError == null` — `isExpectedError`;
  - `job.dart:261`, снимок `pending` не показывает фазу `cleanup` у задачи,
    которая убирает ресурсы;
  - `solo.dart:418`, второй `close(cancel)` после `close(cancel)` снова зовёт
    `_stopWork`;
  - `solo.dart:454`, `_drop` у задачи на пороге старта, которая уже кончилась;
  - `solo.dart:518`, без защиты от второго пути к `_finishClose` — осушение,
    остановленное простым `close`.

Последние три — места, куда прототип с повторным `close` ходит, но нужного
порядка не находит. Зондом ни одно из восьми не проверено.

## Вывод

На этих 241 мутанте поломки, которую ловит только прототип, нет — как
и на ядре. Всё, что он ловит, тесты `solo` ловят с запасом от 12 упавших. Своё
у прототипа другое: на 13 мутантах набор тестов зависает, а прототип за секунды
печатает короткую цепочку событий; и проверки прототипа написаны по инвариантам
`docs/architecture.md`, а не по примерам, поэтому мутант, которого тесты ловят
одним тестом, прототип ловит своим правилом. Тесты `solo` при этом шире словаря
прототипа: 97 мутантов ловят только они.

Если ступень 1 на `solo` брать, её словарь надо растить туда, где тесты тоньше
всего: линии (`solo.dart:1232`), правила, которые сами зовут `cancelAll`,
`isExpectedError`, накопление и время. Восемь непойманных мест из раздела
выше — материал для нацеленных тестов, как на ядре.

## Чего прототип не видит

`SoloLanes`, накопление (`collect`), таймеры и `timeout`, `runAll` и `each`,
`isExpectedError`, хуки, которые бросают, правила, которые бросают или сами
зовут операции контроллера, ребёнок второго уровня, `ctx.start`, отладочный
режим. Урезается только список событий, описания задач остаются
сгенерированными целиком.

## Как запустить

Программа ниже кладётся в `bin/fuzz.dart` пакета вне репозитория:

```yaml
name: solo_spike
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  solo:
    path: <репозиторий>/packages/solo
  fake_async: ^1.3.3
dependency_overrides:
  async_job:
    path: <репозиторий>/packages/async_job
```

`dart pub get`, затем `dart run bin/fuzz.dart 20000` — число сценариев. Без
нарушений программа печатает их число и счёт исходов; с нарушением — seed,
урезанную цепочку и журнал.

Мутации делал скрипт на Python по образцу прогона на ядре: копия пакета
на поток в каталоге с `packages/solo` и ссылкой на `docs` (тесты страниц читают
`../../docs`), прототип в той же копии, правка одной строки, прогон обоих,
возврат файла.

## Код прототипа

```dart
// A throwaway spike: random event chains on the real Solo controller, with
// invariants checked after every event.
import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';

// ---------------------------------------------------------------- scenario

sealed class Step {}

/// `await ctx.join(gate)`.
final class Wait extends Step {
  @override
  String toString() => 'wait';
}

/// `await ctx.join(gate, dispose: ...)`: a resource.
final class Hold extends Step {
  @override
  String toString() => 'hold';
}

/// `await ctx.uncancellable(() => gate)`.
final class Shield extends Step {
  @override
  String toString() => 'shield';
}

/// `ctx.emit(value)`.
final class Emit extends Step {
  Emit(this.value);
  final int value;
  @override
  String toString() => 'emit($value)';
}

/// `await ctx.run(ctx.child(...))`; the child's own cancellation is caught.
final class Child extends Step {
  Child(this.script);
  final Script script;
  @override
  String toString() => 'run($script)';
}

final class Script {
  Script(this.steps, {required this.fails});
  final List<Step> steps;
  final bool fails;
  @override
  String toString() => [...steps, fails ? 'throw' : 'return'].join(', ');
}

/// A root job: its parameters and its body.
final class Spec {
  Spec({
    required this.key,
    required this.policy,
    required this.cancellable,
    required this.startBan,
    required this.keepBan,
    required this.ifFailed,
    required this.ifCancelled,
    required this.script,
  });
  final String? key;
  final Policy policy;
  final bool cancellable;

  /// `canStart: (s) => s != startBan`.
  final int? startBan;

  /// `keepWhile: (s) => s != keepBan`.
  final int? keepBan;
  final int? ifFailed;
  final int? ifCancelled;
  final Script script;

  @override
  String toString() => [
    'key: $key',
    policy.name,
    if (!cancellable) 'cancellable: false',
    if (startBan != null) 'canStart != $startBan',
    if (keepBan != null) 'keepWhile != $keepBan',
    if (ifFailed != null) 'ifFailed $ifFailed',
    if (ifCancelled != null) 'ifCancelled $ifCancelled',
    '{$script}',
  ].join(', ');
}

sealed class Event {}

final class Enqueue extends Event {
  Enqueue(this.spec);
  final int spec;
  @override
  String toString() => 'enqueue(s$spec)';
}

final class Resolve extends Event {
  Resolve(this.pick, {required this.ok});
  final int pick;
  final bool ok;
  @override
  String toString() => 'resolve(#$pick, ${ok ? 'value' : 'error'})';
}

final class CancelJob extends Event {
  CancelJob(this.pick);
  final int pick;
  @override
  String toString() => 'cancel(#$pick)';
}

final class CancelAll extends Event {
  CancelAll({required this.force});
  final bool force;
  @override
  String toString() => 'cancelAll(force: $force)';
}

final class Clear extends Event {
  Clear({required this.force});
  final bool force;
  @override
  String toString() => 'clear(force: $force)';
}

final class External extends Event {
  External(this.value);
  final int value;
  @override
  String toString() => 'externalSetState($value)';
}

final class Close extends Event {
  Close({required this.drain});
  final bool drain;
  @override
  String toString() => 'close(${drain ? 'drain' : 'cancel'})';
}

/// Calls `emit` through the context of a job that has ended.
/// Enqueues a job that has already been enqueued.
final class Requeue extends Event {
  Requeue(this.pick);
  final int pick;
  @override
  String toString() => 'requeue(#$pick)';
}

final class Leak extends Event {
  Leak(this.pick);
  final int pick;
  @override
  String toString() => 'leak(#$pick)';
}

final class Scenario {
  Scenario(this.specs, this.events);
  final List<Spec> specs;
  final List<Event> events;
}

Script _script(Random r, int depth) => Script([
  for (var i = 0, n = 1 + r.nextInt(3); i < n; i++)
    if (depth < 1 && r.nextDouble() < 0.2)
      Child(_script(r, depth + 1))
    else if (r.nextDouble() < 0.25)
      Emit(r.nextInt(3))
    else
      [Wait(), Hold(), Shield()][r.nextInt(3)],
], fails: r.nextDouble() < 0.15);

int? _maybe(Random r, double p) => r.nextDouble() < p ? r.nextInt(3) : null;

Spec _spec(Random r) {
  final key = r.nextDouble() < 0.8 ? ['a', 'b'][r.nextInt(2)] : null;
  return Spec(
    key: key,
    policy: key == null ? Policy.sequential : Policy.values[r.nextInt(4)],
    cancellable: r.nextDouble() < 0.8,
    startBan: _maybe(r, 0.25),
    keepBan: _maybe(r, 0.25),
    ifFailed: _maybe(r, 0.2),
    ifCancelled: _maybe(r, 0.2),
    script: _script(r, 0),
  );
}

Scenario generate(int seed) {
  final r = Random(seed);
  final specs = [for (var i = 0; i < 4; i++) _spec(r)];
  return Scenario(specs, [
    for (var i = 0, n = 4 + r.nextInt(12); i < n; i++)
      switch (r.nextDouble()) {
        < 0.30 => Enqueue(r.nextInt(specs.length)),
        < 0.60 => Resolve(r.nextInt(6), ok: r.nextDouble() < 0.85),
        < 0.70 => CancelJob(r.nextInt(6)),
        < 0.74 => CancelAll(force: r.nextBool()),
        < 0.78 => Clear(force: r.nextBool()),
        < 0.90 => External(r.nextInt(3)),
        < 0.95 => Close(drain: r.nextBool()),
        < 0.97 => Requeue(r.nextInt(6)),
        _ => Leak(r.nextInt(6)),
      },
  ]);
}

// ----------------------------------------------------------------- runtime

final class Gate {
  Gate(this.id, this.owner, {required this.resource});
  final int id;
  final Tracked owner;
  final bool resource;
  final completer = Completer<int>();
  bool closed = false;
}

final class Tracked {
  Tracked(this.name, this.spec, this.parent);
  final String name;

  /// Null for a child.
  final Spec? spec;
  final Tracked? parent;
  late final Job<int> job;
  SoloContext<int, int>? ctx;
  final children = <Tracked>[];
  int finishes = 0;
  bool started = false;
  bool bodyEnded = false;

  /// Whether the controller held it: queued, or handed back by a policy.
  bool held = false;
  CancelReason? markReason;
  String? markedDuring;
  int inSection = 0;
  final arrived = <int>{};
  final disposed = <int, int>{};
  final heard = <Object>[];

  bool get isRoot => parent == null;
}

final class Ctl extends Solo<int> {
  Ctl(this.w) : super(0);
  final World w;

  SoloJob<int> make(Tracked t) {
    final s = t.spec!;
    return job<int, int>(
      w.body(s.script, t),
      key: s.key,
      cancellable: s.cancellable,
      canStart: s.startBan == null ? null : (st) => st != s.startBan,
      keepWhile: s.keepBan == null ? null : (st) => st != s.keepBan,
      ifFailed: s.ifFailed == null ? null : (st, e, _) => s.ifFailed!,
      ifCancelled: s.ifCancelled == null ? null : (st, c) => s.ifCancelled!,
      describe: () => t.name,
    );
  }

  SoloJob<int> put(SoloJob<int> job, Policy policy) =>
      enqueueJob(job, policy: policy);

  SoloQueue get q => queue;
  SoloJob<Object?>? get cur => current;
  void setExternal(int v) => externalSetState(v);

  @override
  void onStart(Job<Object?> job) => w.started(job);

  @override
  void onFinish(Job<Object?> job) => w.finished(job);

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => w.byJob[job]?.heard.add(error);

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {}
}

final class World {
  World() {
    ctl = Ctl(this);
  }
  late final Ctl ctl;
  final jobs = <Tracked>[];
  final byJob = Map<Job<Object?>, Tracked>.identity();
  final gates = <Gate>[];
  final journal = <String>[];
  final violations = <String>[];
  String event = 'start';
  Set<Tracked>? queuedAtClose;
  bool? closeDrains;
  bool closeReturned = false;
  bool closeMayReturn = false;

  void log(String line) => journal.add(line);
  void violate(String what) {
    violations.add(what);
    log('!! $what');
  }

  Tracked track(String name, Spec? spec, Tracked? parent) {
    final t = Tracked(name, spec, parent);
    jobs.add(t);
    parent?.children.add(t);
    return t;
  }

  void watch(Tracked t) {
    byJob[t.job] = t;
    t.job.whenCancelled((c) {
      t.markReason = c.reason;
      t.markedDuring = event;
      log('${t.name} accepts ${c.reason.name}');
    });
  }

  Gate open(Tracked owner, {bool resource = false}) {
    final g = Gate(gates.length, owner, resource: resource);
    gates.add(g);
    log('${owner.name} waits on g${g.id}${resource ? ' (resource)' : ''}');
    return g;
  }

  Future<int> Function(SoloContext<int, int>) body(Script s, Tracked me) =>
      (ctx) async {
        me.ctx = ctx;
        try {
          var k = 0;
          for (final step in s.steps) {
            switch (step) {
              case Wait():
                await ctx.join(() => open(me).completer.future);
              case Hold():
                final g = open(me, resource: true);
                await ctx.join(
                  () => g.completer.future,
                  dispose: (_) {
                    me.disposed[g.id] = (me.disposed[g.id] ?? 0) + 1;
                    log('${me.name} disposes g${g.id}');
                  },
                );
              case Shield():
                await ctx.uncancellable(() async {
                  me.inSection++;
                  try {
                    return await open(me).completer.future;
                  } finally {
                    me.inSection--;
                  }
                });
              case Emit(:final value):
                ctx.emit(value);
                log('${me.name} emits $value');
              case Child(:final script):
                final t = track('${me.name}.${k++}', null, me);
                t.job = ctx.child<int>(body(script, t), describe: () => t.name);
                watch(t);
                try {
                  await ctx.run(t.job as SoloJob<int>);
                } on Cancelled {
                  // The child's own cancellation; a cancellation of this job
                  // is what the next member throws.
                  ctx.check();
                }
            }
          }
          if (s.fails) throw StateError('${me.name} failed');
          return 1;
        } finally {
          me.bodyEnded = true;
        }
      };

  // ------------------------------------------------------------ the hooks

  void started(Job<Object?> job) {
    final t = byJob[job];
    if (t == null) return;
    t.started = true;
    log('${t.name} starts');
    if (!t.isRoot) return;
    // Invariant 1: one root job at a time.
    for (final o in jobs) {
      if (o != t && o.isRoot && o.started && !o.job.isFinished) {
        violate('${t.name} starts while ${o.name} still runs');
      }
    }
    // The start rule held when the job started.
    final ban = t.spec!.startBan;
    if (ban != null && ctl.currentState == ban) {
      violate('${t.name} starts though canStart is false');
    }
    if (closeDrains == false) violate('${t.name} starts after close');
  }

  void finished(Job<Object?> job) {
    final t = byJob[job];
    if (t == null) return;
    t.finishes++;
    final outcome = job.outcome;
    log('${t.name} ends $outcome');
    // Invariant 3: a job marked cancelled ends with that cancellation.
    if (t.markReason != null && outcome is! Cancelled) {
      violate('${t.name} accepted a cancellation and ended $outcome');
    }
    // Invariant 4: every Failed is heard by onError, once.
    if (outcome case Failed(:final error)) {
      final times = t.heard.where((e) => identical(e, error)).length;
      if (times != 1) {
        violate('${t.name} ended $outcome, onError heard it $times times');
      }
    }
    for (final id in t.arrived) {
      if (t.disposed[id] != 1) {
        violate(
          '${t.name} ended with g$id disposed ${t.disposed[id] ?? 0} '
          'times',
        );
      }
    }
    for (final c in t.children) {
      if (!c.job.isFinished) {
        violate('${t.name} ended before its child ${c.name}');
      }
    }
    if (t.finishes > 1) violate('${t.name} finished ${t.finishes} times');
    // Invariant 9: cancellable: false turns down every request once held.
    final reason = t.markReason;
    final spec = t.spec;
    if (spec != null &&
        !spec.cancellable &&
        t.held &&
        reason != null &&
        reason is! RulesCancelReason) {
      final allowed =
          !t.started &&
          (t.markedDuring!.startsWith('close(cancel') ||
              t.markedDuring == 'clear(force: true)');
      if (!allowed) {
        violate(
          '${t.name} (cancellable: false) accepted ${reason.name} '
          'during ${t.markedDuring}',
        );
      }
    }
    // Invariant 7: a drain runs what was queued, it does not drop it.
    if (closeDrains == true &&
        (queuedAtClose?.contains(t) ?? false) &&
        reason is ClosedCancelReason) {
      violate('${t.name}, queued before close(drain), ended $outcome');
    }
  }

  // ----------------------------------------------------------- the events

  List<Tracked> get live => [
    for (final t in jobs)
      if (!t.job.isFinished) t,
  ];

  void apply(Event e, Scenario s) {
    event = '$e';
    log('> $e');
    switch (e) {
      case Enqueue(spec: final i):
        final spec = s.specs[i];
        final t = track('j${jobs.length}', spec, null);
        t.job = ctl.make(t);
        watch(t);
        final key = spec.key;
        final queuedSame = [
          for (final o in ctl.q.jobs)
            if (o.key == key && key != null) byJob[o]!,
        ];
        final current = ctl.cur == null ? null : byJob[ctl.cur!];
        final closed = ctl.isClosed;
        final back = ctl.put(t.job as SoloJob<int>, spec.policy);
        final handedBack = !identical(back, t.job);
        t.held = !handedBack && !t.job.isFinished;
        if (closed && !handedBack) {
          if (t.job.outcome case Cancelled(
            :final reason,
          ) when reason is ClosedCancelReason) {
          } else {
            violate('${t.name} enqueued after close ended ${t.job.outcome}');
          }
          return;
        }
        switch (spec.policy) {
          case Policy.droppable:
            if (queuedSame.isNotEmpty && !handedBack) {
              violate(
                'droppable ${t.name} queued beside '
                '${queuedSame.first.name} of the same key',
              );
            }
            if (handedBack) {
              if (t.job.outcome case Cancelled(
                :final reason,
              ) when reason is DuplicateCancelReason) {
              } else {
                violate(
                  'droppable ${t.name} handed back another job and '
                  'ended ${t.job.outcome}',
                );
              }
            }
          case Policy.keepLatest || Policy.restart:
            for (final o in ctl.q.jobs) {
              final other = byJob[o]!;
              if (other != t && o.key == key && other.spec!.cancellable) {
                violate(
                  '${spec.policy.name} ${t.name} left ${other.name} '
                  'of the same key queued',
                );
              }
            }
            for (final o in queuedSame) {
              if (o.spec!.cancellable && o.job.outcome is! Cancelled) {
                violate(
                  '${o.name} replaced by ${t.name} ended '
                  '${o.job.outcome}',
                );
              }
            }
            if (spec.policy == Policy.restart &&
                current != null &&
                current.spec!.key == key &&
                current.spec!.cancellable &&
                !current.bodyEnded &&
                current.markReason == null &&
                current.inSection == 0 &&
                !current.job.isFinished) {
              violate('restart ${t.name} left ${current.name} running');
            }
          case Policy.sequential:
        }
      case Resolve(:final pick, :final ok):
        final open = [
          for (final g in gates)
            if (!g.closed) g,
        ];
        if (open.isEmpty) return;
        final g = open[pick % open.length];
        g.closed = true;
        log('  g${g.id} ${ok ? 'gives a value' : 'breaks'}');
        if (ok) {
          if (g.resource) g.owner.arrived.add(g.id);
          g.completer.complete(g.id);
        } else {
          g.completer.completeError(Exception('g${g.id} broke'));
        }
      case CancelJob(:final pick):
        if (jobs.isEmpty) return;
        final t = jobs[pick % jobs.length];
        log('  cancel ${t.name}');
        t.job.cancel().then((_) {
          if (!t.job.isFinished)
            violate('cancel() of ${t.name} returned early');
        });
      case CancelAll(:final force):
        final then = [...jobs];
        ctl.cancelAll(force: force).then((_) {
          for (final t in then) {
            if (t.isRoot &&
                t.held &&
                t.started &&
                !t.job.isFinished &&
                t.spec!.cancellable &&
                t.markReason == null &&
                t.inSection == 0 &&
                !t.bodyEnded) {
              violate('cancelAll returned while ${t.name} runs on');
            }
          }
        });
      case Clear(:final force):
        final before = [for (final o in ctl.q.jobs) byJob[o]!];
        ctl.q.clear(force: force);
        final after = {for (final o in ctl.q.jobs) byJob[o]!};
        for (final t in before) {
          final stays = !force && !t.spec!.cancellable;
          if (stays != after.contains(t)) {
            violate(
              'clear(force: $force) ${stays ? 'dropped' : 'kept'} '
              '${t.name}',
            );
          }
        }
      case External(:final value):
        // Invariant 8: the state of a controller that has closed is final.
        final over = ctl.isFinished;
        try {
          ctl.setExternal(value);
          if (over) violate('externalSetState went through after closing');
        } on StateError {
          if (!over) violate('externalSetState refused before the end');
        }
      case Close(:final drain):
        // A second close changes nothing, except a cancel after a drain:
        // the drain gives way, and the close goes on as a cancel.
        final again = ctl.isClosed;
        final givesWay =
            again && !drain && closeDrains == true && !ctl.isFinished;
        if (!again || givesWay) {
          queuedAtClose = {for (final o in ctl.q.jobs) byJob[o]!};
          closeDrains = drain;
        }
        ctl
            .close(mode: drain ? SoloCloseMode.drain : SoloCloseMode.cancel)
            .then((_) {
              closeReturned = true;
              for (final t in jobs) {
                if (!t.job.isFinished) {
                  violate('close returned while ${t.name} has not ended');
                }
              }
              if (ctl.q.isNotEmpty) violate('close returned, queue not empty');
              if (!ctl.isFinished) violate('close returned, not finished');
            });
        if (!drain && (!again || givesWay)) {
          for (final t in queuedAtClose!) {
            if (t.job.outcome case Cancelled(
              :final reason,
            ) when reason is ClosedCancelReason) {
            } else {
              violate('${t.name}, queued at close, ended ${t.job.outcome}');
            }
          }
        }
      case Requeue(:final pick):
        final roots = [
          for (final t in jobs)
            if (t.isRoot) t,
        ];
        if (roots.isEmpty) return;
        final t = roots[pick % roots.length];
        final queued = [...ctl.q.jobs];
        final outcome = t.job.outcome;
        try {
          ctl.put(t.job as SoloJob<int>, t.spec!.policy);
          violate('${t.name} was enqueued twice');
        } on StateError {
          // A job is enqueued once.
        }
        final now = [...ctl.q.jobs];
        if (now.length != queued.length ||
            [
              for (var i = 0; i < now.length; i++) identical(now[i], queued[i]),
            ].contains(false)) {
          violate('enqueuing ${t.name} again changed the queue');
        }
        if (!identical(t.job.outcome, outcome)) {
          violate('enqueuing ${t.name} again ended it ${t.job.outcome}');
        }
      case Leak(:final pick):
        final ended = [
          for (final t in jobs)
            if (t.job.isFinished && t.ctx != null) t,
        ];
        if (ended.isEmpty) return;
        final t = ended[pick % ended.length];
        final before = ctl.currentState;
        try {
          t.ctx!.emit(7);
          violate('emit from the ended ${t.name} went through');
        } on StateError {
          // Invariant 8.
        }
        if (ctl.currentState != before) {
          violate('emit from the ended ${t.name} changed the state');
        }
    }
  }

  void checkBetweenEvents(Event? e) {
    for (final t in jobs) {
      // Invariant 9: an uncancellable section holds a request back; only the
      // job's own rules pass through it.
      if (t.inSection > 0 &&
          t.markReason != null &&
          t.markReason is! RulesCancelReason &&
          t.markedDuring != null) {
        violate(
          '${t.name} accepted ${t.markReason!.name} inside '
          'uncancellable',
        );
      }
      for (final entry in t.disposed.entries) {
        if (entry.value > 1) violate('${t.name} disposed g${entry.key} twice');
      }
    }
    // Invariant 2: an outside write asks the rules of the running job.
    if (e is External) {
      for (final t in jobs) {
        final ban = t.spec?.keepBan;
        if (t.isRoot &&
            t.started &&
            !t.bodyEnded &&
            !t.job.isFinished &&
            ban != null &&
            ctl.currentState == ban &&
            t.markReason == null) {
          violate('${t.name} runs on though keepWhile is false');
        }
      }
    }
  }
}

/// Runs [s] and returns the world it leaves.
World run(Scenario s) {
  final w = World();
  fakeAsync((async) {
    runZonedGuarded(
      () {
        for (final e in s.events) {
          w.apply(e, s);
          async.elapse(Duration.zero);
          w.checkBetweenEvents(e);
        }
        w.event = 'drain';
        void settle() {
          for (var open = true; open;) {
            open = false;
            for (final _ in w.gates.where((g) => !g.closed).toList()) {
              open = true;
              w.apply(Resolve(0, ok: true), s);
              async.elapse(Duration.zero);
              w.checkBetweenEvents(null);
              break;
            }
          }
        }

        settle();
        if (!w.ctl.isClosed) {
          w.apply(Close(drain: false), s);
          async.elapse(Duration.zero);
        }
        settle();
        async.flushTimers();
        for (final t in w.jobs) {
          if (!t.job.isFinished) w.violate('${t.name} never ended');
        }
        if (!w.closeReturned) w.violate('close never returned');
      },
      (error, stack) {
        final text = '$error';
        if (error is Cancelled ||
            text.contains(' failed') ||
            text.contains(' broke')) {
          w.log('zone: $error');
        } else {
          w.violate('zone: $error');
        }
      },
    );
  });
  return w;
}

/// Drops events one at a time while the scenario still violates something.
Scenario shrink(Scenario s) {
  var events = s.events;
  for (var changed = true; changed;) {
    changed = false;
    for (var i = 0; i < events.length; i++) {
      final fewer = [...events]..removeAt(i);
      if (run(Scenario(s.specs, fewer)).violations.isNotEmpty) {
        events = fewer;
        changed = true;
        break;
      }
    }
  }
  return Scenario(s.specs, events);
}

void main(List<String> args) {
  final count = args.isEmpty ? 20000 : int.parse(args.first);
  var events = 0;
  final tally = <String, int>{};
  void count1(String k, [int n = 1]) => tally[k] = (tally[k] ?? 0) + n;
  for (var seed = 0; seed < count; seed++) {
    final s = generate(seed);
    events += s.events.length;
    final world = run(s);
    for (final t in world.jobs) {
      count1(switch (t.job.outcome) {
        Done() => 'Done',
        Failed() => 'Failed',
        Cancelled(:final reason) => 'Cancelled(${reason.name})',
        null => 'none',
      });
    }
    count1('started', world.jobs.where((t) => t.started).length);
    count1('zone', world.journal.where((l) => l.startsWith('zone')).length);
    if (world.violations.isEmpty) continue;
    final small = shrink(s);
    final w = run(small);
    print('seed $seed breaks an invariant: ${w.violations.first}');
    print('');
    for (final (i, spec) in small.specs.indexed) {
      print('  s$i: $spec');
    }
    print('  events: ${small.events.join(', ')}');
    print('');
    print('  journal:');
    for (final line in w.journal) {
      print('    $line');
    }
    return;
  }
  print('$count scenarios, $events events: no invariant broken');
  print(tally);
}
```
