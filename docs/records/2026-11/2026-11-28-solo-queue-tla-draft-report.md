> **Состояние на 2026-11-28:** черновик, вне пакетов и вне CI. Модель,
> настройки прогонов и зонды записаны здесь целиком; брать ли ступень 2
> в работу, владелец не решал. Модель продолжена накопителями
> в `2026-11-28-solo-queue-tla-accumulators-report.md`: там она ловит обе
> побудки насоса, которых здесь не стережёт.
> **Что это:** черновая модель очереди `solo` на TLA+ — линия и пул
> `SoloLanes`, четыре политики, окно стартовых правил, насос, `cancelAll`,
> `close` и осушение, — прогоны TLC на ней, мутации модели, зонды сверки
> с кодом и мутации двух побудок насоса в коде.
> **Связанные записи:** `2026-11-25-invariant-checking-plan.md` (три ступени),
> `2026-11-26-core-tla-draft-report.md` (черновик ступени 2 на ядре),
> `2026-11-27-solo-pool-design.md` (пул),
> `2026-11-28-solo-queue-tla-accumulators-report.md` (накопители).

# Черновик ступени 2: очередь `solo` с пулом на TLA+

Владелец сказал: «делай черновик модели очереди solo с пулом на TLA+». Черновик
ядра `2026-11-26-core-tla-draft-report.md` кончился выводом, что ступень 2
стоит брать на очереди `solo`: там главный риск — порядок событий между
линиями, политиками и закрытием. План `2026-11-25-invariant-checking-plan.md`
описывал такую модель ещё без пула; пул вышел в `solo` 2.1.0, и модель берёт
его вместе с линией.

Правила взяты из кода 2.1.0, а не только со страниц: насос, постановка
и закрытие — `packages/solo/lib/src/solo.dart`, очередь пула —
`packages/solo/lib/src/queue.dart`. Страницы говорят о местах пула и порядке
ключа, но не о том, когда просыпается насос, а без этого модель не отличит
рабочую очередь от застрявшей.

## Что в модели

Ядра: линия `L` и пул `P` на `PCAP` мест, насос обходит их в порядке
объявления. Константа `SETUP` берёт оба ядра, одну линию или один пул. Задачи —
`JOBS`; ключ из `KEYS` или никакого, политику, `cancellable` и `first` задача
получает при постановке, и TLC перебирает все сочетания. Тел нет: идущая задача
кончается, когда TLC позволит.

Переходы:

- постановка: закрытый контроллер отказывает; `droppable` получает живую задачу
  своего ключа — в очереди, в окне или идущую, в осушении тоже; остальное
  встаёт в голову (`first: true`) или в хвост; `keepLatest` и `restart` снимают
  задачи ключа в очереди и в окне, кроме `cancellable: false`, а `restart` ещё
  просит отмениться идущую задачу ключа;
- `cancel` одной задачи: задача в очереди или в окне кончается, идущая
  принимает отмену; `cancellable: false` отказывает в обоих случаях;
- отмена правилом `keepWhile` от чужой записи состояния, сквозь
  `cancellable: false`;
- `cancelAll` с `force` и без: очереди вместе с окном, затем идущие;
- `close()`: окно и очереди снимаются не спрашивая, идущих просят отмениться,
  отказавшую ждут; `close(mode: drain)` и `close()` поверх осушения;
- насос — микрозадача, один проход по ядрам. Шаг ядра берёт в окно правил
  первую готовую задачу, правила её пускают или отказывают ей; шаг пула
  заполняет места подряд. Проход, нашедший все ядра осушенными, кончает
  осушение;
- конец тела, никогда не внутри прохода; `close()` кончается с последней идущей
  задачей.

Готовая задача пула — голова свободного ключа или задача без ключа, как
`_ready` в `queue.dart`. Ключ держит задача, которая идёт или чьи правила
спрашиваются, и отменённая, пока сворачивается. Насос будят, как в коде:
постановка, конец идущей задачи, конец любой задачи во время осушения и снятие
кандидата пула, за которым стоит задача его ключа, вне шага пула.

Правила старта — чужой код и могут позвать что угодно, поэтому постановка,
отмены, `cancelAll` и `close` случаются и между шагами прохода, и внутри окна.
Так модель заменяет и обработчики конца, и хуки, которые зовут API: они бегут
в тех же точках.

Упрощения. Бросившее правило старта кончает задачу в окне так же, как отказ:
исходы у них разные, а для очереди это одно и то же. Детей, накопителей,
таймеров, `timeout` и ошибок тел нет. Справедливость: насос, шаги, ответы
правил и концы тел не застревают; на этом стоят свойства живости.

Две вещи сделаны ради размера. Флаги `klb` и `rcb` проверяют `keepLatest`
и `restart` в момент постановки: задача, поставленная позже, и встаёт позже,
так что нарушение может родиться только там. `VIEW` различает законченную
задачу только по исходу, отметке отмены и тому, сняла ли её `close`, а места
живых — только по порядку внутри ядра: новое место всегда раньше или позже
всех. Будущее модели от отброшенного не зависит.

## Инварианты

| Инвариант | Правило |
|---|---|
| `OneOutcome` | у законченной задачи один исход, у живой — никакого |
| `LaneSerial` | линия ведёт не больше одной корневой задачи, окно правил в счёт (инвариант 1) |
| `PoolBound` | пул ведёт не больше `concurrency` корневых задач, окно в счёт (инвариант 1) |
| `KeyAlone` | две задачи одного ключа в пуле не идут вместе, сворачивающаяся отменённая в счёт (инвариант 1) |
| `KeyOrder` | порядок ключа строгий: задача не стартует, пока ждёт задача её ключа, вставшая раньше |
| `NoOvertake` | обгоняют только ждущую своего ключа: никто не стартует, пока ждёт готовая задача, вставшая раньше |
| `MarkDecides` | принявшая отмену кончается `Cancelled` (инвариант 3) |
| `RefusalHolds` | `cancellable: false` отказывает всякой отмене, кроме отмены правилом (инвариант 9) |
| `DroppableAlone` | две живые задачи `droppable` одного ключа в одном ядре не живут вместе |
| `KeepLatest` | после постановки `keepLatest` или `restart` не ждёт ни одна отменяемая задача её ключа, вставшая раньше |
| `RestartCancels` | отменяемая задача ключа, шедшая при постановке `restart`, получила просьбу отмениться |
| `NothingQueuedAfterStop` | после `close()` ничего не ждёт ни в очереди, ни в окне (инвариант 7) |
| `ClosedQuiet` | у закрытого контроллера нет живых задач (инвариант 7) |
| `DrainKeeps` | осушение не снимает принятого: `Cancelled(closed)` даёт только `close()` |
| `NoIdleStall` | пока насос не идёт и не назначен, ни у одного ядра нет свободного места вместе с готовой задачей |
| `DrainNotStuck` | осушение без идущих задач всегда с назначенным насосом |
| `CloseEnds` | закрытие кончается (живость) |
| `NoStarve` | задача не ждёт в очереди вечно (живость) |

## Прогоны

У всех настроек два ключа, два места в пуле и все четыре политики. TLC 2.19
на 14 потоках:

| Настройка | Ядра | Задачи | Проверяет | Различных | Сгенерировано | Глубина | Время |
|---|---|---|---|---|---|---|---|
| `small` | пул | 2 | 16 инвариантов | 27 499 | 137 773 | 18 | 3 с |
| `pool` | пул | 3 | 16 инвариантов | 794 691 | 5 666 341 | 25 | 7 с |
| `main` | линия и пул | 3 | 16 инвариантов | 5 134 849 | 36 601 946 | 25 | 45 с |
| `live` | линия и пул | 2 | `CloseEnds`, `NoStarve` | 409 165 | 2 103 625 | 20 | 31 с |

Все четыре чистые. Вероятность того, что два разных состояния `main` совпали
по отпечатку и одно осталось непроверенным, TLC оценивает в 5,9·10⁻⁶.

Число различных состояний на 14 потоках от прогона к прогону чуть плавает:
`small` дала 27 498, 27 499 дважды и 27 514. Плавает симметрия. Представителя
класса TLC выбирает по всему состоянию, а не по `VIEW`, и два равных по `VIEW`
состояния порой достаются разным представителям. Класс от этого дробится,
а разные состояния не склеиваются. На одном потоке `small` дважды дала 27 501,
без симметрии — 102 653 трижды, на одном потоке и на 14. Сам `VIEW`, судя
по этому, склеивает только состояния с одним будущим: иначе от порядка обхода
зависело бы, чьих потомков TLC увидит, и число плавало бы и без симметрии.

Живость проверена без симметрии: с ней TLC может пропустить нарушение живости.
`VIEW` оставлен. Без него `live` за пять минут прошла больше 8 млн различных
состояний, очередь ещё росла, и прогон я остановил.

## Мутации

Каждая мутация ломает одно правило в модели, константа `MUT` её включает.
Прогон — `small` или, где сказано, `pool` на одном потоке: так TLC отдаёт
кратчайшую трассу.

| `MUT` | Что сломано | Ловит | Состояний в трассе |
|---|---|---|---|
| `laneTwo` | линия не бывает полной (на одной линии) | `LaneSerial` | 7 |
| `poolOverfill` | пул полон только сверх `concurrency` (на трёх задачах) | `PoolBound` | 10 |
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
| `noPumpOnUnlink` | снятие кандидата пула не будит насос | никто, 27 501 состояние | — |
| `noPumpOnDrainDrop` | задача, кончившаяся вне очереди во время осушения, не будит насос | никто, 27 602 состояния | — |

`DrainNotStuck` своей мутации не получила: `noPumpOnEnd` первой роняет
`NoIdleStall`, а одна `DrainNotStuck` ловит ту же мутацию за 8 состояний.
На `live` мутация `noPumpOnEnd` роняет `NoStarve` трассой из 9 состояний:
первая задача ключа кончилась, насос не проснулся, и вторая ждёт в очереди
вечно. `noPumpOnUnlink` и `noPumpOnDrainDrop` живость не роняют.

## Что нашёл TLC

Нового о коде — ничего: на верной модели все инварианты и оба свойства живости
держатся, противоречий между правилами нет.

Нашлось другое: двух побудок насоса модель не стережёт. По модели задача ждёт
в очереди, только пока что-то идёт или насос назначен, а конец идущей задачи
будит насос и так. Комментарии кода объясняют, зачем побудки нужны: ради групп
накопителя, которые ждут своего окна. Шаг пропускает такую группу, ничего
не идёт, и разбудить насос, кроме этих двух мест, некому. Накопителей в модели
нет.

Обе побудки сняты в отдельной копии дерева, по одной, и `dart test` пакета
`solo` прогнан целиком:

- в `_onJobFinished` (`solo.dart:1364`) условие `wasCurrent || _draining`
  заменено на `wasCurrent`. Из 2588 тестов упали два, оба в `drain_test.dart`:
  «a drain ends when its last waiting group is cancelled» и «a drain ends when
  the waiting group cancels itself»;
- в `_unlink` очереди пула (`queue.dart:454`) убрана строка
  `if (!_stepping) _core.controller._schedulePump();`. Из 2588 тестов упали
  два, оба в `pool_test.dart`: «keys removing a waiting group of a key lets the
  next job start» и «keys a group of a key moved to the tail lets the next job
  start».

Обе побудки тесты стерегут, и оба раза через группу накопителя, ждущую окна,
как и говорят комментарии.

## Сверка с кодом

Модель держится на нескольких правилах, которые взяты из кода, а не со страниц.
Пять зондов на `solo` 2.1.0 сверили их с кодом. Зонд — скрипт под `fake_async`,
запущенный с `package_config.json` пакета `solo`:

```dart
// Probes of SoloQueue.tla against the code: the places where the model
// rests on what was read in the code rather than on a page.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';

final class Probe extends SoloLanes<int> {
  late final SoloPool<int> p;
  final log = <String>[];
  final names = <Object, String>{};

  Probe(int concurrency) : super(0) {
    p = pool('p', concurrency: concurrency);
  }

  SoloJob<void> put(
    String name, {
    Object? key,
    Policy policy = Policy.sequential,
    bool cancellable = true,
    bool Function(int state)? canStart,
    Completer<void>? gate,
  }) {
    final g = gate ?? (Completer<void>()..complete());
    final job = p.enqueue<int, void>(
      key: key,
      policy: policy,
      cancellable: cancellable,
      canStart: canStart,
      describe: () => name,
      (ctx) async {
        log.add('start $name');
        await g.future;
        log.add('end $name');
      },
    );
    names[job] ??= name;
    return job;
  }

  String queued() => '[${p.queue.jobs.map((j) => names[j]).join(', ')}]';
}

String said(SoloJob<Object?> job) {
  final o = job.outcome;
  if (o == null) {
    return job.isCancelled ? 'cancelled, not over' : 'not over';
  }
  if (o is Cancelled) {
    return 'Cancelled(${o.reason.runtimeType}, started: ${o.started})';
  }
  return '${o.runtimeType}';
}

void heldByCancelled() {
  print('== a cancelled job of the pool holds its key until it ends');
  fakeAsync((async) {
    final c = Probe(2);
    final g = Completer<void>();
    final a1 = c.put('a1', key: 'a', gate: g);
    final a2 = c.put('a2', key: 'a');
    async.flushMicrotasks();
    unawaited(a1.cancel());
    async.flushMicrotasks();
    print('after cancel: log ${c.log}, a1 ${said(a1)}, '
        'running ${c.p.running.length}, queue ${c.queued()}');
    g.complete();
    async.flushMicrotasks();
    print('after a1 ends: log ${c.log}, a1 ${said(a1)}, a2 ${said(a2)}');
  });
}

void replacedInWindow() {
  print('== keepLatest from the rules takes the job out of its window');
  fakeAsync((async) {
    final c = Probe(2);
    late SoloJob<void> n;
    final w = c.put(
      'w',
      key: 'a',
      canStart: (_) {
        n = c.put('n', key: 'a', policy: Policy.keepLatest);
        return true;
      },
    );
    async.flushMicrotasks();
    print('log ${c.log}, w ${said(w)}, n ${said(n)}');
  });
}

void cancelAllInWindow() {
  print('== cancelAll from the rules ends the job, the step goes on');
  fakeAsync((async) {
    final c = Probe(2);
    late SoloJob<void> x;
    final w = c.put(
      'w',
      key: 'a',
      canStart: (_) {
        unawaited(c.cancelAll());
        x = c.put('x');
        return true;
      },
    );
    async.flushMicrotasks();
    print('log ${c.log}, w ${said(w)}, x ${said(x)}');
  });
}

void refusingInQueue() {
  print('== cancellable: false in the queue');
  fakeAsync((async) {
    final c = Probe(1);
    final g = Completer<void>();
    final r = c.put('r', gate: g);
    async.flushMicrotasks();
    final q = c.put('q', key: 'a', cancellable: false);
    final k = c.put('k', key: 'a', policy: Policy.keepLatest);
    print('after keepLatest: queue ${c.queued()}, q ${said(q)}');
    unawaited(c.cancelAll());
    print('after cancelAll: queue ${c.queued()}, k ${said(k)}, '
        'r ${said(r)}');
    unawaited(c.cancelAll(force: true));
    print('after cancelAll(force: true): queue ${c.queued()}, q ${said(q)}');
    g.complete();
    async.flushMicrotasks();
    print('after r ends: log ${c.log}, r ${said(r)}');
  });
  fakeAsync((async) {
    final c = Probe(1);
    final g = Completer<void>();
    final r = c.put('r', gate: g, cancellable: false);
    async.flushMicrotasks();
    final q = c.put('q', key: 'a', cancellable: false);
    var closed = false;
    unawaited(c.close().then((_) => closed = true));
    async.flushMicrotasks();
    print('after close: queue ${c.queued()}, q ${said(q)}, r ${said(r)}, '
        'closed $closed');
    g.complete();
    async.flushMicrotasks();
    print('after r ends: r ${said(r)}, closed $closed');
  });
}

void restartInPool() {
  print('== restart in the pool');
  fakeAsync((async) {
    final c = Probe(2);
    final g = Completer<void>();
    final a1 = c.put('a1', key: 'a', gate: g);
    async.flushMicrotasks();
    final a2 = c.put('a2', key: 'a', policy: Policy.restart);
    async.flushMicrotasks();
    print('after restart: log ${c.log}, a1 ${said(a1)}, a2 ${said(a2)}');
    g.complete();
    async.flushMicrotasks();
    print('after a1 ends: log ${c.log}, a1 ${said(a1)}, a2 ${said(a2)}');
  });
  fakeAsync((async) {
    final c = Probe(2);
    final g = Completer<void>();
    final b1 = c.put('b1', key: 'b', gate: g, cancellable: false);
    async.flushMicrotasks();
    final b2 = c.put('b2', key: 'b', policy: Policy.restart);
    async.flushMicrotasks();
    print('over cancellable: false: log ${c.log}, b1 ${said(b1)}, '
        'b2 ${said(b2)}');
    g.complete();
    async.flushMicrotasks();
    print('after b1 ends: log ${c.log}, b1 ${said(b1)}, b2 ${said(b2)}');
  });
}

void main() {
  heldByCancelled();
  replacedInWindow();
  cancelAllInWindow();
  refusingInQueue();
  restartInPool();
}
```

```text
== a cancelled job of the pool holds its key until it ends
after cancel: log [start a1], a1 cancelled, not over, running 1, queue [a2]
after a1 ends: log [start a1, end a1, start a2, end a2], a1 Cancelled(ManualCancelReason, started: true), a2 Done<void>
== keepLatest from the rules takes the job out of its window
log [start n, end n], w Cancelled(ReplacedCancelReason, started: false), n Done<void>
== cancelAll from the rules ends the job, the step goes on
log [start x, end x], w Cancelled(ManualCancelReason, started: false), x Done<void>
== cancellable: false in the queue
after keepLatest: queue [q, k], q not over
after cancelAll: queue [q], k Cancelled(ManualCancelReason, started: false), r cancelled, not over
after cancelAll(force: true): queue [], q Cancelled(ManualCancelReason, started: false)
after r ends: log [start r, end r], r Cancelled(ManualCancelReason, started: true)
after close: queue [], q Cancelled(ClosedCancelReason, started: false), r not over, closed false
after r ends: r Done<void>, closed true
== restart in the pool
after restart: log [start a1], a1 cancelled, not over, a2 not over
after a1 ends: log [start a1, end a1, start a2, end a2], a1 Cancelled(ReplacedCancelReason, started: true), a2 Done<void>
over cancellable: false: log [start b1], b1 not over, b2 not over
after b1 ends: log [start b1, end b1, start b2, end b2], b1 Done<void>, b2 Done<void>
```

Все пять совпали с моделью. Отменённая задача пула держит ключ, пока
не кончится, — без этого `cancelledFreesKey` краснеет на `KeyAlone`.
`keepLatest` и `cancelAll`, позванные из правил старта, снимают задачу из её
окна, не дав ей начаться, и шаг идёт дальше: новая задача стартует тем же
проходом. `cancellable: false` в очереди переживает `keepLatest` и `cancelAll`
без `force`, а `cancelAll(force: true)` и `close()` её снимают, и `close()`
ждёт отказавшую идущую. `restart` в пуле отменяет держателя ключа, новая задача
ждёт его конца; над `cancellable: false` он получает отказ, и новая идёт после
старой, как `sequential`.

## Чего модель не видит

- Dart-код. Модель написана по чтению кода, и проверяет она, что правила
  не противоречат друг другу и держат обещанное; сверка с кодом — ступень 3,
  здесь её заменяют пять зондов.
- Накопители и их окна, а с ними обе побудки насоса, которые модель
  не стережёт.
- Детей задач, таймеры и `timeout`, ошибки тел и `onError`, состояние
  `SoloLanes`: правила старта отвечают как угодно, а запись состояния приходит
  только отменой правилом `keepWhile`.
- Бросившее правило старта: оно кончает задачу в окне так же, как отказ.
- Порядок микрозадач: назначенный насос в модели просто когда-нибудь приходит.
- Больше одной линии и одного пула, третий ключ, третье место пула.
- Размер: три задачи на инварианты и две на живость. Четыре задачи и живость
  на трёх не прогонялись.

## Вывод

На модели в 431 строку держатся 16 инвариантов — на трёх задачах, линии
и пуле — и живость на двух задачах: закрытие кончается, очередь не голодает.
У каждого инварианта, кроме `DrainNotStuck`, есть мутация, которую ловит именно
он. Нового о коде модель не нашла. Единственное, что она показала, — две
побудки насоса, лишние без накопителей; мутации кода подтвердили, что тесты
`solo` их стерегут.

Очередь `solo` плотно вычитана тестами, как и ядро, и модель на ней тоже
подтверждает, а не находит. Её польза — в другом: правила пула, политик, окна
и закрытия теперь записаны в одном месте, и будущую правку этих правил можно
сперва внести в модель и за минуту прогнать на всех порядках трёх задач. Чтобы
модель видела больше, ей нужны накопители, а сверку с кодом — ступень 3 — пока
заменяют зонды.

## Как запустить

TLC 2.19 (`tla2tools.jar` от 8 августа 2024), Java из Homebrew. Текст модели
из последнего раздела ложится в `SoloQueue.tla`, настройки — рядом
в `<имя>.cfg`; из их каталога:

```sh
java -XX:+UseParallelGC -cp tla2tools.jar tlc2.TLC -workers auto -deadlock \
  -metadir ./states -config main.cfg SoloQueue.tla
```

`-deadlock` выключает проверку тупиков: законченная модель стоит на месте,
и это не тупик. Настройка `main.cfg`:

```text
CONSTANTS
  JOBS = {j1, j2, j3}
  KEYS = {k1, k2}
  NOKEY = nokey
  SETUP = "both"
  PCAP = 2
  POLS = {"seq", "drop", "keep", "restart"}
  MUT = "none"
SPECIFICATION Spec
SYMMETRY Sym
INVARIANTS
  OneOutcome LaneSerial PoolBound KeyAlone KeyOrder NoOvertake MarkDecides
  RefusalHolds DroppableAlone KeepLatest RestartCancels
  NothingQueuedAfterStop ClosedQuiet DrainKeeps NoIdleStall DrainNotStuck
VIEW View
```

`pool.cfg` отличается строкой `SETUP = "pool"`, `small.cfg` — ещё
и `JOBS = {j1, j2}`. Настройка мутации — `pool.cfg` с `MUT = "<имя>"`,
у `laneTwo` и `drainEndsEarly` с `SETUP = "lane"`, у всех, кроме
`poolOverfill`, с `JOBS = {j1, j2}`; гоняется она с `-workers 1`, и тогда TLC
отдаёт кратчайшую трассу. `live.cfg` проверяет живость без `SYMMETRY`:

```text
CONSTANTS
  JOBS = {j1, j2}
  KEYS = {k1, k2}
  NOKEY = nokey
  SETUP = "both"
  PCAP = 2
  POLS = {"seq", "drop", "keep", "restart"}
  MUT = "none"
SPECIFICATION Spec
PROPERTIES
  CloseEnds NoStarve
VIEW View
```

Мутации живости — `live.cfg` с `MUT = "<имя>"`.

## Текст модели

```tla
----------------------------- MODULE SoloQueue -----------------------------
(* The queue of solo 2.1 by its code: a lane and a pool of SoloLanes, the
   four policies, the window of the start rules, the pump, cancelAll, close
   and the drain. No bodies: a running job ends when TLC lets it, and a
   write of the state may cancel it by its keepWhile at any moment.        *)
EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS JOBS, KEYS, NOKEY, SETUP, PCAP, POLS, MUT

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
  cl,      \* "open", "draining", "cancelling", "closed"
  due,     \* a pump is scheduled
  pass,    \* the cores the running pass has yet to step, the head in its step
  drained, \* cores this pass found drained
  lch,     \* the step of the head core launched a job
  win,     \* the job whose start rules are asked, or "none"
  kob,     \* ghost: a job was taken while one of its key queued before it
  fob,     \* ghost: a job was taken while a ready one queued before it
  klb,     \* ghost: a keepLatest or restart job left an older one queued
  rcb,     \* ghost: a restart job left the running job of its key unasked
  stopped  \* ghost: a close that cancels came

vars == <<st, co, ky, pl, cn, pos, lo, hi, mk, out, rs,
          cl, due, pass, drained, lch, win, kob, fob, klb, rcb, stopped>>

\* What no job action touches.
pump == <<cl, pass, drained, lch, win, kob, fob, klb, rcb, stopped>>
jobFix == <<co, ky, pl, cn, pos, lo, hi>>

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

\* The jobs the pump may take next: the head of a lane's queue; in a pool the
\* head of every free key, and every job without a key.
Ready(c) ==
  IF IsPool(c)
  THEN {j \in Queued(c) :
          \/ ky[j] = NOKEY
          \/ KeyHead(c, j) /\ (MUT = "keyNotHeld" \/ ~Held(c, ky[j]))}
  ELSE {j \in Queued(c) : \A y \in Queued(c) : pos[y] >= pos[j]}

\* The first of them in the queue.
Pick(c) ==
  IF MUT = "pickLast"
  THEN CHOOSE j \in Ready(c) : \A y \in Ready(c) : pos[j] >= pos[y]
  ELSE CHOOSE j \in Ready(c) : \A y \in Ready(c) : pos[j] <= pos[y]

\* A job that ends off the queue brings the pump back in a drain; so does the
\* removal of a pool's candidate that has a job of its key behind it, made
\* outside the step of that pool.
WakeDrain(D) == D # {} /\ Draining /\ MUT # "noPumpOnDrainDrop"
UnlinkWakes(D) ==
  /\ MUT # "noPumpOnUnlink"
  /\ \E x \in D : /\ st[x] = "queued" /\ IsPool(co[x]) /\ ~InStep(co[x])
                  /\ x \in Ready(co[x]) /\ ky[x] # NOKEY
                  /\ \E y \in Queued(co[x]) : y # x /\ ky[y] = ky[x]

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
  /\ cl = "open" /\ due = FALSE /\ pass = <<>> /\ drained = 0 /\ lch = FALSE
  /\ win = "none"
  /\ kob = FALSE /\ fob = FALSE /\ klb = FALSE /\ rcb = FALSE
  /\ stopped = FALSE

\* enqueueJob: refused when closed, a duplicate for `droppable`, otherwise
\* queued; `keepLatest` and `restart` remove the queued jobs of the key, the
\* one in the window included, but not a `cancellable: false` one; `restart`
\* asks the running job of the key to cancel.
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
                  /\ UNCHANGED <<pos, lo, hi, mk, klb, rcb>>
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
                  \* Checked here: a job queued later comes after this one.
                  /\ klb' = (klb \/ /\ p \in {"keep", "restart"}
                                    /\ \E y \in JOBS \ {j} :
                                         /\ st'[y] \in {"queued", "window"}
                                         /\ co[y] = c /\ ky[y] = k /\ cn[y])
                  /\ rcb' = (rcb \/ /\ p = "restart"
                                    /\ \E h \in Running(c) :
                                         ky[h] = k /\ cn[h] /\ mk'[h] = "no")
  /\ UNCHANGED <<cl, pass, drained, lch, win, kob, fob, stopped>>

\* cancel() of one job: a queued one, or the one in the window, ends; a
\* running one takes it; `cancellable: false` refuses either way.
CancelJob(j) ==
  /\ cn[j]
  /\ \/ /\ st[j] \in {"queued", "window"}
        /\ st' = [st EXCEPT ![j] = "done"]
        /\ out' = [out EXCEPT ![j] = "cancelled"]
        /\ rs' = [rs EXCEPT ![j] = "manual"]
        /\ due' = (due \/ WakeDrain({j}) \/ UnlinkWakes({j}))
        /\ UNCHANGED mk
     \/ /\ st[j] = "running" /\ mk[j] = "no"
        /\ mk' = [mk EXCEPT ![j] = "request"]
        /\ rs' = [rs EXCEPT ![j] = "manual"]
        /\ UNCHANGED <<st, out, due>>
  /\ UNCHANGED <<jobFix, pump>>

\* A write of the state, by another job or by externalSetState, whose
\* keepWhile this running job refuses: the rules go past `cancellable: false`.
RuleCancel(j) ==
  /\ st[j] = "running" /\ mk[j] = "no"
  /\ mk' = [mk EXCEPT ![j] = "rule"]
  /\ rs' = [rs EXCEPT ![j] = "keep"]
  /\ UNCHANGED <<st, out, due, jobFix, pump>>

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
       /\ UNCHANGED <<jobFix, pump>>

\* close() and close() over a drain: the window and every queue are dropped
\* without asking, every running job is asked; a refusing one is waited for.
StopWork ==
  LET D == {y \in JOBS : st[y] \in {"queued", "window"}
                         /\ (MUT = "closeKeepsQueue" => st[y] = "window")}
      R == {y \in JOBS : st[y] = "running" /\ mk[y] = "no"
                         /\ (cn[y] \/ MUT = "closeIgnoresRefusal")}
  IN /\ st' = [y \in JOBS |-> IF y \in D THEN "done" ELSE st[y]]
     /\ out' = [y \in JOBS |-> IF y \in D THEN "cancelled" ELSE out[y]]
     /\ rs' = [y \in JOBS |-> IF y \in D \cup R THEN "closed" ELSE rs[y]]
     /\ mk' = [y \in JOBS |-> IF y \in R THEN "request" ELSE mk[y]]
     /\ cl' = "cancelling"
     /\ stopped' = TRUE
     /\ UNCHANGED <<jobFix, due, pass, drained, lch, win, kob, fob, klb, rcb>>

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
     ELSE UNCHANGED <<st, out, rs>>
  /\ UNCHANGED <<jobFix, mk, pass, drained, lch, win, kob, fob, klb, rcb,
                 stopped>>

Close == Drain \/ (cl \in {"open", "draining"} /\ StopWork)

-----------------------------------------------------------------------------
\* The pump: a microtask, one pass over the cores in their order.
PassStart ==
  /\ due /\ pass = <<>>
  /\ due' = FALSE /\ pass' = Order /\ drained' = 0 /\ lch' = FALSE
  /\ UNCHANGED <<st, jobFix, mk, out, rs, cl, win, kob, fob, klb, rcb,
                 stopped>>

\* The step of the head core is over: on to the next core; the pass that found
\* every core drained ends the drain.
Advance(d) ==
  /\ pass' = Tail(pass)
  /\ drained' = drained + d
  /\ lch' = FALSE
  /\ cl' = IF Tail(pass) = <<>> /\ Draining /\ drained + d = Len(Order)
           THEN "closed" ELSE cl

\* One move of the step of the head core: stop on a close that cancels, end
\* the step on a full core or an empty choice, or take the next job into the
\* window of its rules.
Step ==
  /\ pass # <<>> /\ win = "none"
  /\ LET c == Head(pass) IN
     CASE cl \in {"cancelling", "closed"} ->
            /\ pass' = <<>>
            /\ UNCHANGED <<st, drained, lch, cl, win, kob, fob>>
       [] Full(c) ->
            /\ Advance(IF MUT = "drainEndsEarly" /\ ~IsPool(c) /\ Draining
                          /\ Queued(c) = {} THEN 1 ELSE 0)
            /\ UNCHANGED <<st, win, kob, fob>>
       [] Ready(c) # {} ->
            LET x == Pick(c) IN
              /\ st' = [st EXCEPT ![x] = "window"]
              /\ win' = x
              /\ kob' = (kob \/ \E y \in Queued(c) :
                           /\ y # x /\ ky[x] # NOKEY /\ ky[y] = ky[x]
                           /\ pos[y] < pos[x])
              /\ fob' = (fob \/ \E y \in Ready(c) : pos[y] < pos[x])
              /\ UNCHANGED <<pass, drained, lch, cl>>
       [] OTHER ->
            /\ Advance(IF /\ Draining /\ Queued(c) = {}
                          /\ (IsPool(c) => ~lch /\ Running(c) = {})
                       THEN 1 ELSE 0)
            /\ UNCHANGED <<st, win, kob, fob>>
  /\ UNCHANGED <<jobFix, mk, out, rs, due, klb, rcb, stopped>>

\* The rules of the job in the window answer: it starts, or it is turned down.
Decide ==
  /\ win # "none" /\ st[win] = "window"
  /\ \/ /\ st' = [st EXCEPT ![win] = "running"]
        /\ lch' = TRUE
        /\ UNCHANGED <<out, rs, due>>
     \/ /\ st' = [st EXCEPT ![win] = "done"]
        /\ out' = [out EXCEPT ![win] = "cancelled"]
        /\ rs' = [rs EXCEPT ![win] = "rules"]
        /\ due' = (due \/ WakeDrain({win}))
        /\ UNCHANGED lch
  /\ win' = "none"
  /\ UNCHANGED <<jobFix, mk, cl, pass, drained, kob, fob, klb, rcb, stopped>>

\* The rules ended their own job, by a cancel, cancelAll or close made from
\* in there: the step goes on without launching it.
WindowEnded ==
  /\ win # "none" /\ st[win] = "done"
  /\ win' = "none"
  /\ UNCHANGED <<st, jobFix, mk, out, rs, cl, due, pass, drained, lch, kob,
                 fob, klb, rcb, stopped>>

\* A running job ends, never in the synchronous code of a pass; a taken
\* cancellation decides its outcome. Its end brings the pump back.
BodyEnd(j) ==
  /\ st[j] = "running" /\ pass = <<>>
  /\ st' = [st EXCEPT ![j] = "done"]
  /\ out' = [out EXCEPT ![j] =
               IF mk[j] # "no" /\ MUT # "markIgnored"
               THEN "cancelled" ELSE "done"]
  /\ due' = IF MUT = "noPumpOnEnd" THEN due ELSE TRUE
  /\ UNCHANGED <<jobFix, mk, rs, pump>>

\* A close that cancels finishes once the last running job is over.
FinishClose ==
  /\ cl = "cancelling" /\ pass = <<>>
  /\ \A j \in JOBS : st[j] # "running"
  /\ cl' = "closed"
  /\ UNCHANGED <<st, jobFix, mk, out, rs, due, pass, drained, lch, win, kob,
                 fob, klb, rcb, stopped>>

Next ==
  \/ \E j \in JOBS : Enqueue(j) \/ CancelJob(j) \/ RuleCancel(j) \/ BodyEnd(j)
  \/ CancelAll \/ Close
  \/ PassStart \/ Step \/ Decide \/ WindowEnded \/ FinishClose

Fair ==
  /\ WF_vars(PassStart) /\ WF_vars(Step) /\ WF_vars(Decide)
  /\ WF_vars(WindowEnded) /\ WF_vars(FinishClose)
  /\ \A j \in JOBS : WF_vars(BodyEnd(j))

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

\* The order of a key is strict: no job starts while one of its key queued
\* before it waits.
KeyOrder == ~kob

\* Only a job that waits for its key is overtaken: none starts while a ready
\* one queued before it.
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

\* A drain with nothing running and no pump due would never end.
DrainNotStuck ==
  (pass = <<>> /\ ~due /\ Draining) => \E j \in JOBS : st[j] = "running"

\* Liveness: a close ends, and no job waits in a queue for good.
CloseEnds == (cl # "open") ~> (cl = "closed")
NoStarve == \A j \in JOBS : (st[j] = "queued") ~> (st[j] # "queued")

Sym == Permutations(JOBS) \cup Permutations(KEYS)

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
                  rs[j] = "closed">>
View == <<[j \in JOBS |-> JobView(j)], cl, due, pass, drained, lch, win,
          kob, fob, klb, rcb, stopped>>
=============================================================================
```
