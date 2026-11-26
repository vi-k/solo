> **Состояние на 2026-11-27:** план написан по дизайну, одобренному владельцем
> 2026-11-27 («да, одобряю, пиши план»), прошёл независимое ревью Opus
> и исправлен по нему (раздел «Ревью плана»). Ждёт одобрения владельца. Кода нет.
> **Что это:** план работ по пулу в `SoloLanes`: одно ядро с N местами, ключ,
> политики, закрытие и `pending`, накопитель, линты, документы и переводы.
> **Связанные записи:** `2026-11-27-solo-pool-design.md` (дизайн),
> `2026-11-11-solo-lanes-plan.md`, `2026-11-12-queue-key-index-report.md`.

# Пул: план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** `pool(name, concurrency: N)` в `SoloLanes`: до N корней одной очереди
сразу, две задачи одного ключа никогда не вместе, при неизменных `Solo`
и линиях.

**Architecture:** пул — одно ядро `_SoloPoolCore`, подкласс `_SoloLaneCore`,
со своей очередью `_SoloPoolQueue`, подклассом `_SoloQueue`. Вместо одного
`current` у ядра пула список идущих задач и словарь ключей, которые заняты;
очередь пула держит упорядоченный набор кандидатов на старт, где нет задач
занятых ключей. Места движка, которые читают `current`, получают ветку
`core is _SoloPoolCore<S>`; ветка линий остаётся как была.

**Tech Stack:** Dart 3.10 (пол `sdk: ^3.10.0`), `dart:collection`
(`SplayTreeMap`), `package:test`, `fake_async`; `solo` 2.0.1 → 2.1.0,
`async_job_lints` 0.2.3 → патч, `solo_lints` 0.3.1 → минор; `async_job`
не трогается.

**Spec:** `docs/records/2026-11/2026-11-27-solo-pool-design.md`. Дизайн —
источник правды; где план с ним расходится, прав дизайн, а расхождение
записывается решением исполнителя в отчёт. Номера строк — на `e67fa090`.

## Global Constraints

- **Ветка.** Работа идёт в ветке `solo-pool` в своей копии дерева
  (`EnterWorktree`), первой командой `git merge --ff-only main`. В `main` она
  вливается `git merge --ff-only` после ревью всей ветки. Пуш — только по слову
  владельца. Выпуска в плане нет: связка публикации — отдельная задача
  по отдельному слову владельца.
- **Неизменность `Solo` и линий.** Прежние тесты `solo` не правятся: в файлах
  `packages/solo/test/` до этой работы допустимы только добавления (новые
  `test(...)`, новые хелперы в `support/`, новые классы в `_classes`
  `reference_page_test.dart`), ни одно прежнее ожидание не меняется. Исключение
  одно — счётчики сторожа страницы линий в `lanes_rakes_test.dart`
  (`hasLength(5)` первых попыток, `:1187`; `hasLength(11)` цитат трасс,
  `:1192`; карта `holders`, `:1204`): новый раздел страницы обязан их поднять,
  и задача 8 поднимает их ровно на свои разделы и трассы. Отладочные строки,
  тексты ошибок, порядок событий и число микрозадач `Solo` и линий — прежние,
  слово в слово.
- **Ветвление.** Код линий и `Solo` в `_step`, `_enqueueIn`, `_lastJobWhereIn`,
  `_onJobFinished`, `_pendingOf` и накопителе остаётся текстом как был; пул
  идёт отдельной веткой `core is _SoloPoolCore<S>` или членом `_SoloPoolCore`.
  Общий код — только там, где задача это прямо говорит.
- **Код по-английски**, включая комментарии и тексты ошибок; документы для
  владельца — по-русски; правка английского публичного документа идёт с правкой
  перевода тем же коммитом, сверка `python3 tool/check_translations.py`.
- **Новых зависимостей нет.** `SplayTreeMap` — из `dart:collection`.
- **Проверки перед каждым коммитом кода** в каждом затронутом пакете из его
  папки: `dart format --output=none --set-exit-if-changed .`,
  `dart analyze --fatal-infos`, `dart test`. Документы:
  `python3 tool/reflow.py --check`, `python3 tool/check_line_width.py`,
  `python3 tool/check_links.py`, `python3 tool/check_dartdoc.py`; свежую запись
  в `docs/records/` заливать по имени.
- **Оверрайды.** Пока `solo` 2.1.0 не опубликован, пакеты над ним идут против
  дерева: задача 1 возвращает `pubspec_overrides.yaml`.
- **Коммиты** — Conventional Commits по-английски, с последней строкой
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Открытые вопросы дизайна взяты по моим предложениям**, владелец их
  не отменил: имя базы — `SoloQueueOwner<S>`; группы накопителя без ключа идут
  рядом.

## Review Focus

1. Ключ, не равный себе (`double.nan`): индекс очереди его не хранит
   (`queue.dart`, `_insert`). В пуле такая задача ни с кем ключ не делит и идёт
   как задача без ключа. Тест — задача 2.
2. Задача, отклонённая правилами или законченная в окне правил, освобождает
   ключ, и следующая задача ключа стартует в том же проходе насоса, как в линии
   стартует следующая голова очереди. Тест — задача 2.
3. `first: true` при занятом ключе ставит задачу перед прочими задачами ключа,
   но не перед идущей: она ждёт конца идущей. Тест — задача 2.
4. Отмена задачи из очереди при свободном ключе (`queue.remove`) делает
   кандидатом следующую задачу ключа, и та стартует без новой постановки.
   Тест — задача 2.
5. Ребёнок задачи пула пишет состояние, корень потом пишет своё: строки
   о записи поверх чужой нет, ребёнок — своя работа. Тест — задача 3.

---

### Task 1: Пул без ключей — объявление, тип, места

**Files:**
- Create: `packages/solo/test/pool_test.dart`
- Modify: `packages/solo/lib/src/lane.dart` (база, `SoloPool`, лица, ядро пула)
- Modify: `packages/solo/lib/src/queue.dart` (`_SoloPoolQueue`, пока без
  ключей)
- Modify: `packages/solo/lib/src/job.dart` (поле `_seq`)
- Modify: `packages/solo/lib/src/solo.dart` (`pool`, `pools`, `_step`,
  `_onJobFinished`, `_stopWork`, `cancelAll`, `_lastJobWhereIn`)
- Create: `pubspec_overrides.yaml` у `packages/async_job_lints`,
  `packages/solo_lints`, `packages/flutter_solo`,
  `packages/flutter_solo/example`, `packages/flutter_solo/camera_example`
- Modify: `packages/solo/doc/reference.md`, `docs/ru/solo/reference.md`,
  `packages/solo/test/reference_page_test.dart` (`_classes`: добавить
  `SoloQueueOwner` и `SoloPool`)

**Interfaces:**
- Produces (публичное, `lane.dart`):
  ```dart
  abstract interface class SoloQueueOwner<S extends Object> {
    String get name;
    SoloLaneId get id;
    SoloJob<T> job<W extends S, T>(...);        // as SoloLane.job today
    SoloJob<T> enqueueJob<T>(Job<T> job, {bool first = false,
        Policy policy = Policy.sequential});
    SoloJob<T> enqueue<W extends S, T>(...);    // as SoloLane.enqueue today
    SoloAccumulator<E, T> collect<W extends S, E, T>(...);
    SoloAccumulator<E, T> accumulate<W extends S, E, T>(...);
    SoloQueue get queue;
    SoloJob<Object?>? lastJobWhere(bool Function(SoloJob<Object?> job) test);
    SoloPending? get pending;
  }
  abstract interface class SoloLane<S extends Object>
      implements SoloQueueOwner<S> { /* every member as today */ }
  abstract interface class SoloPool<S extends Object>
      implements SoloQueueOwner<S> {
    int get concurrency;
    List<SoloJob<Object?>> get running;   // unmodifiable snapshot, start order
  }
  // SoloLanes:
  @protected SoloPool<S> pool(String name, {required int concurrency});
  @protected List<SoloPool<S>> get pools;
  ```
- Produces (закрытое):
  - `_SoloQueueFace<S>` — общий код `_SoloLane` и `_SoloPool` (сегодня он весь
    в `_SoloLane`); `_SoloLaneCore.lane` получает тип `_SoloQueueFace<S>?`,
    накопитель зовёт `_core.lane!.enqueueJob`, как сейчас.
  - `final class _SoloPoolCore<S> extends _SoloLaneCore<S>`:
    `final int concurrency`, `final List<_SoloJob<S, S, Object?>> running`
    (порядок старта), `bool get isFull => running.length >= concurrency`,
    `_SoloPoolQueue<S> get poolQueue`.
  - `_SoloLaneCore.runningJobs` → `List<_SoloJob<S, S, Object?>>`: у линии
    `[?current]`, у пула копия `running`.
  - `_SoloPoolQueue<S> extends _SoloQueue<S>`: `_takeNext()` →
    `_SoloJob<S, S, Object?>?`.
  - `_SoloJob._seq` (`int`, ставит только очередь пула).

- [ ] **Step 1: Ветка, копия и оверрайды**

`EnterWorktree` с именем `solo-pool`, `git merge --ff-only main`. Пять файлов
`pubspec_overrides.yaml` по образцу снятых в `66332a82`
(`git show 66332a82^:packages/<пакет>/pubspec_overrides.yaml`): первая строка
`# Until solo 2.1.0 is published.`, вместо `async_job` — `solo`: `../solo`
у `async_job_lints`, `solo_lints` и `flutter_solo`, `../../solo`
у `flutter_solo/example` и `flutter_solo/camera_example`. У `solo_lints` ещё
`async_job_lints: path: ../async_job_lints`: он меняется в задаче 7.
`packages/solo/example` зависит от `solo` путём сам
(`solo/example/pubspec.yaml:11-12`), оверрайд ему не нужен. `dart pub get`
(во Flutter- пакетах `flutter pub get`) в каждом, `git status` — только новые
оверрайды и их `pubspec.lock`, если он под гитом.

- [ ] **Step 2: Написать падающие тесты**

`packages/solo/test/pool_test.dart`, `@Timeout(Duration(seconds: 5))`,
шапка-комментарий в стиле `lanes_test.dart`. Хелпер:

```dart
/// Pools and lanes declared by whoever makes it, in its constructor body.
final class _Pools extends SoloLanes<int> {
  final log = <String>[];
  _Pools([void Function(_Pools self)? declare]) : super(0) {
    declare?.call(this);
  }
  SoloPool<int> declarePool(String name, int concurrency) =>
      pool(name, concurrency: concurrency);
  SoloLane<int> declareLane(String name) => lane(name);
  List<SoloPool<int>> get declaredPools => pools;
  List<SoloLane<int>> get declaredLanes => lanes;
}

/// A body that logs `start name`, waits for [gate] and logs `end name`.
Future<void> Function(SoloContext<int, int>) _gated(
  List<String> log, String name, Completer<void> gate) => ...;
```

Тесты (группа `declaring`, затем `places`):

```dart
test('pool takes a place among lanes in the order of declaration', ...);
  // declareLane('a'), declarePool('p', 2), declareLane('b'):
  // declaredLanes names == ['a', 'b'], declaredPools names == ['p'],
  // pool.concurrency == 2, '$pool' == 'SoloPool(p)', pool.id.name == 'p'.
test('a pool and a lane of one name throw', ...);
  // declareLane('x') then declarePool('x', 2): StateError whose message
  // contains 'has a lane named x already'; declarePool('y', 2) then
  // declareLane('y'): contains 'has a pool named y already'.
test('concurrency below 1 throws ArgumentError', ...);   // 0 and -1
test('pool after the constructor throws', ...);
  // a pool declared after flushMicrotasks: StateError containing
  // 'Cannot declare pool'.
test('a job of the pool says the pool in job.lane', ...);
  // job.lane identical to pool.id, also for a child made with ctx.child.
test('a job of another pool or lane is refused', ...);
  // pool.enqueueJob(lane.job(...)) and pool.enqueueJob(otherPool.job(...)):
  // ArgumentError whose message contains 'was not created by this pool'.
test('up to concurrency root jobs run at once', ...);
  // pool of 2, three gated jobs a, b, c without keys; after flush:
  // log == ['start a', 'start b'], running == [a, b],
  // queue.jobs == [c]; open a: log gains 'end a', 'start c';
  // running == [b, c].
test('a pool of one runs like a lane', ...);
  // pool of 1, a and b: 'start a', then 'end a', 'start b'.
test('running is a snapshot', ...);
  // the list taken before a job ends keeps it; add throws
  // UnsupportedError.
test('a child of a pool job takes no place', ...);
  // pool of 1: a running job runs two children with ctx.child at once;
  // both start before the root ends, running == [root].
test('lastJobWhere finds a running job of the pool', ...);
  // two running, the later started one is found first by a test
  // that accepts both.
test('cancelAll cancels every running job of a pool and waits for all', ...);
  // two running and one queued: the queued ends Cancelled(manual,
  // started: false), both running are cancelled; the returned future
  // completes after the second ends.
test('close waits for every running job of a pool', ...);
  // close() completes only after both running jobs end.
```

- [ ] **Step 3: Прогнать — тесты падают**

Run: `cd packages/solo && dart test test/pool_test.dart` Expected: FAIL —
`pool` и `SoloPool` не определены.

- [ ] **Step 4: База и лица**

В `lane.dart`: `SoloQueueOwner<S>` с dartdoc общих членов (тексты из нынешнего
`SoloLane`, слово «lane» там, где речь о любом владельце очереди, — «lane or
pool»); `SoloLane<S> implements SoloQueueOwner<S>` сохраняет все свои члены
и dartdoc как есть. `SoloPool<S>` с dartdoc: до [concurrency] корней сразу,
ключ держит порядок своих задач и с `Policy.sequential`. Ссылку на раздел
страницы (`lanes.md#a-pool-of-places`) ставит задача 8 вместе с разделом:
`tool/check_links.py` проверяет якоря и в dartdoc, и ссылка раньше раздела
красит гейт `docs`. `_SoloQueueFace<S>` берёт тела нынешних членов `_SoloLane`;
`enqueueJob` отказывает чужой задаче текстом своего вида: у линии
`_notCreatedByLane` как есть, у пула новая константа рядом с ним:

```dart
const _notCreatedByPool =
    'was not created by this pool (make it with job(...) of this pool, or '
    'with ctx.child of a job running in it)';
```

- [ ] **Step 5: Ядро и очередь пула без ключей**

`_SoloPoolCore<S>` — как в Interfaces. Очередь ядру даёт фабричный метод базы,
а не переопределённое поле (`overridden_fields` в `analysis_options.yaml`
включён через `recommended`). `_SoloQueue` и `_SoloLaneCore` остаются `final`:
подкласс в той же библиотеке разрешён. `_SoloPoolQueue<S>`: счётчики `_first`
и `_last`, `job._seq` при вставке — `--_first` для `first: true`, `++_last`
иначе; набор кандидатов `SplayTreeMap<int, _SoloJob<S, S, Object?>> _ready`
по `_seq`. Переопределены `_insert` (кладёт в `_ready`), `_unlink` (убирает),
`_drain` (чистит `_ready`). `_takeNext()` идёт по `_ready.values`
по возрастанию, пропускает группу, чьё окно не открыто
(`job._accumulation?._ready == false`, как `_takeFirst`), снимает первую
готовую `_unlink`-ом, зовёт `_accumulation?._seal()` и возвращает её сразу,
не продолжая обход.

- [ ] **Step 6: `pool`, `pools` и общие обходы**

`SoloLanes`: список `_pools`, вид `_poolsView`; `pool` проверяет сначала
`concurrency`
(`ArgumentError.value(concurrency, 'concurrency', 'must be at least 1')`),
затем печать набора и `close`:
`'Cannot declare pool $name of $runtimeType $why; see $_declaringLanes'`, где
`why` —
`'after its constructor: lanes and pools are declared in the constructor body,
and a late final field declares its pool on its first read'`, `'after
enqueueJob of one of its lanes or pools was called: from the first call on,
the lanes and pools are what the pump walks'` или
`'after close: a closed controller takes no pool'`; затем имя по всем `_cores`.
Тексты `lane` не меняются; имя, занятое пулом, даёт у `lane` ту же фразу с «a
pool named»: `'$runtimeType has a pool named $name already: every call of lane
declares a new lane,
and two of one name would read as one; see $_declaringLanes'`; у `pool` — `'...
has a {lane|pool} named $name already: every call of pool declares a new pool,
and two of one name would read as one; see ...'`.

`_stopWork` (`solo.dart:480`) и `cancelAll` (`:573`): `?core.current` →
`...core.runningJobs`; ветвление `switch (running)` в `cancelAll` остаётся.
`_lastJobWhereIn`: для ядра пула после очереди и окна — `running` с конца.

- [ ] **Step 7: Насос и конец задачи**

`_step` (`solo.dart:1259`): первой строкой
`if (core is _SoloPoolCore<S>) return _stepPool(core);`. `_stepPool`:

```text
if closed and not draining: return _stepEnd
loop while !core.isFull:
  job = core.poolQueue._takeNext()
    null -> drained when draining && queue.isEmpty && running.isEmpty;
          otherwise 'queue has no ready jobs' is said when a job was
          dropped since the last launch of this step (a `dropped` flag,
          reset at every launch), or once, by saidWaiting, when the
          only candidates left are groups waiting for their window;
          nothing is said for jobs that wait for a held key or a
          place: their enqueue line said it; return _stepEnd
  the window and the rules exactly as in _step: inTransition, _rejectStart,
  a rule that threw, a job ended in the window, a rejection — each continues
  the loop
  launched: running.add(job), inTransition = null, saidWaiting = false,
  job._launch(); then go on with the loop, not return
return _stepEnd
```

Тело окна правил вынести из `_step` в общий метод нельзя без правки текста
ветки линии; исполнитель выбирает: копия с комментарием «as in `_step`» или
вынос, после которого `_step` линии даёт те же строки и микрозадачи —
доказывают прежние тесты.

`_onJobFinished`: для ядра пула `wasCurrent = core.running.remove(job)`; дальше
как сейчас. Освобождение ключа в задаче 2 встаёт после `_schedulePump`: `==`
и `hashCode` ключа — код пользователя, и бросок не должен оставить насос
незапланированным.

- [ ] **Step 8: Страница справки**

`packages/solo/doc/reference.md`: строки `pool` и `pools` в разделе
`## SoloLanes`, разделы `## SoloQueueOwner` и `## SoloPool` по образцу
`## SoloLane`, перевод в `docs/ru/solo/reference.md` тем же коммитом.
`reference_page_test.dart` через mirrors требует строку на каждый публичный
член (`:34`, `:81-109`).

- [ ] **Step 9: Прогнать — зелёное**

Run: `cd packages/solo && dart test test/pool_test.dart && dart test` Expected:
PASS всего набора, `git diff main -- packages/solo/test` — только новый файл.

- [ ] **Step 10: Проверки и коммит**

`dart format`, `dart analyze --fatal-infos` в `packages/solo`;
`dart analyze --fatal-infos` и `dart test` в `packages/solo/example`
и `packages/solo_lints` (оверрайды на месте);
`python3 tool/check_translations.py`.

```bash
git add packages/solo packages/*/pubspec_overrides.yaml \
  packages/*/*/pubspec_overrides.yaml
git commit -m "feat(solo): declare a pool of places in SoloLanes"
```

---

### Task 2: Ключ в пуле — занятость, обгон, цена

**Files:**
- Modify: `packages/solo/lib/src/queue.dart` (`_SoloPoolQueue`, `_QueueIndex`)
- Modify: `packages/solo/lib/src/solo.dart` (`_stepPool`, `_onJobFinished`,
  отладочная строка постановки)
- Test: `packages/solo/test/pool_test.dart`

**Interfaces:**
- Consumes: задача 1 — `_SoloPoolCore`, `_SoloPoolQueue._takeNext`,
  `_SoloJob._seq`.
- Produces:
  - `_SoloPoolQueue._holders` — `Map<Object, _SoloJob<S, S, Object?>>` по `==`:
    ключ → задача, которая с ним идёт или в окне правил;
  - `_SoloPoolQueue._holderOf(Object key)` → `_SoloJob<S, S, Object?>?`;
  - `_SoloPoolQueue._release(_SoloJob<S, S, Object?> job)` — отпускает ключ,
    если его держит [job], и делает кандидатом голову ключа;
  - `_QueueIndex._firstOf(Object by)` → `_SoloJob<S, S, Object?>?`.

- [ ] **Step 1: Написать падающие тесты** (группа `keys`)

```dart
test('two jobs of one key never run together', ...);
  // pool of 4: a1 (key 'a'), a2 (key 'a'), b (key 'b'):
  // 'start a1', 'start b'; a2 waits; open a1: 'end a1', 'start a2'.
test('a job of a held key is overtaken by the jobs behind it', ...);
  // pool of 2: a1, a2 (key 'a'), c (no key): a1 and c start, a2 waits.
test('the jobs of one key keep their order', ...);
  // a1..a3 of key 'a' in a pool of 4: starts in order a1, a2, a3,
  // each after the end of the one before.
test('the likes of the debate', ...);
  // fakeAsync; pool of 4; like p1 at 10 ms lasting 2000 ms, unlike p1 at
  // 20 ms, like p2 at 150 ms, each emits a mark on start:
  // start times p1-like 10, p2-like 150, p1-unlike 2010.
test('Policy.sequential with a key keeps the order in a pool', ...);
test('first: true with a held key waits for the running job', ...);
  // a1 running, a2 queued, a0 first: true: starts after a1 ends, before a2.
test('a key not equal to itself shares nothing', ...);
  // two jobs with key double.nan in a pool of 2 start together.
test('a job dropped in the window frees its key at once', ...);
  // real async, not fakeAsync: a1 with canStart false, a2 of the same
  // key; after one `await Future<void>.value()` a1 has ended
  // Cancelled(rules) and a2 has started — a second pass would come
  // after this continuation.
test('a group waiting for its window holds the jobs of its key', ...);
  // fakeAsync, pool of 2: collect with key 'p1' and debounce 300 ms gets
  // a like at 0 ms; at 10 ms a plain job of key 'p1' is queued: it
  // starts only after the group, which starts at 300 ms, ends; a job of
  // key 'p2' queued at 10 ms starts at once.
test('removing the head of a free key lets the next one start', ...);
  // pool of 1 busy with x; a1, a2 of key 'a' queued; queue.remove(a1);
  // open x: a2 starts.
test('a held key costs nothing to the jobs of other keys', ...,
    timeout: Timeout(Duration(seconds: 30)));
  // pool of 2, one running job of key 'k' held open, 40 000 queued jobs
  // of key 'k', then 40 000 jobs without a key, each ending at once;
  // all 40 000 keyless jobs end; Stopwatch under 6 s.
```

- [ ] **Step 2: Прогнать — падают**

Run: `cd packages/solo && dart test test/pool_test.dart -N keys` Expected:
FAIL — `a2` стартует вместе с `a1`.

- [ ] **Step 3: Занятые ключи и кандидаты**

Задача с ключом, равным себе (`key == key`), — «ключевая»; остальные идут как
задачи без ключа. Правила набора `_ready`:

- голова ключа держит ключ, даже если это группа накопителя, чьё окно
  не открыто: `_takeNext` её пропускает, а задачи её ключа за ней кандидатами
  не становятся — «держит, порядок ключа строгий», слово владельца;
- кандидаты — задачи без ключа и голова каждого ключа (первая в `_byKey` его
  ключа), если ключ не в `_holders`;
- `_insert`: задача без ключа — в `_ready`; ключевая — в `_ready`, если она
  стала головой своего ключа и ключ свободен, а прежняя голова при этом
  из `_ready` уходит;
- `_unlink`: задача уходит из `_ready`; если она была головой свободного ключа,
  новая голова ключа входит в `_ready`;
- `_takeNext`: ключевую задачу кладёт в `_holders` **до** `_unlink`, чтобы
  следующая задача ключа не стала кандидатом;
- `_release(job)`: если `_holders[key]` — эта задача, ключ уходит
  из `_holders`, голова ключа (если есть) входит в `_ready`.

Новый кандидат, допущенный вне насоса, будит насос: `_unlink`, который делает
кандидатом новую голову свободного ключа (снятие головы через `remove`,
`cancel`, перенос `_moveToTail` при `AccumulationPolicy.replace`), зовёт
`_core.controller._schedulePump()`. `_onJobFinished` будит насос только при
`wasCurrent || _draining` (`solo.dart:1207`), и без этого задача стояла бы
до чужого события. Тесты: снятие головы ключа из очереди при свободном месте
и свободном ключе; группа ключа, перенесённая в хвост `replace`.

`_onJobFinished` ядра пула зовёт `poolQueue._release(job)` для любой своей
задачи, после `_schedulePump`: так ключ отпускают и конец идущей, и задача,
законченная в окне правил. Цена каждой операции — `O(log R)`, где `R` — число
кандидатов; задачи занятых ключей в `_ready` не лежат и не стоят ничего. Это
расходится с «амортизированным O(1)» дизайна: упорядоченный набор кандидатов —
сортировка по порядку очереди, и `O(1)` на произвольную вставку нет. Требование
дизайна «при любом числе задач занятых ключей» держится; расхождение — в отчёт.

- [ ] **Step 4: Строки постановки пула**

В `_enqueueIn` после вставки для ядра пула вместо строки линии — своя:

```dart
// what the job waits for, the first that holds:
// a job of the key that runs or is in the window:
'$pool: enqueue $job while $holder holds key $key: it starts after $holder ends'
// a job of the key queued ahead of it:
'$pool: enqueue $job behind $ahead of key $key: it starts after $ahead ends'
// every place is taken:
'$pool: enqueue $job while all $n places are taken: it starts when one is free'
// otherwise
'$pool: enqueue $job'
```

`first` дописывается к `enqueue $job` так же, как у линии. Тесты — в группе
`debug lines` файла `pool_test.dart`, по строке на случай.

- [ ] **Step 5: Прогнать — зелёное, мутация цены**

Run: `cd packages/solo && dart test test/pool_test.dart && dart test` Expected:
PASS. Затем подменить в копии `_takeNext` обходом всей очереди (`_entries`)
с пропуском занятых ключей и убедиться, что тест цены краснеет; вернуть копией
файла, не `git checkout`. Замер обоих прогонов — в отчёт.

- [ ] **Step 6: Коммит**

```bash
git commit -am "feat(solo): keep two jobs of one key apart in a pool"
```

---

### Task 3: Политики, правила и запись поверх чужой

**Files:**
- Modify: `packages/solo/lib/src/solo.dart` (`_enqueueIn`, `_setState`,
  `_wroteSinceSeen`)
- Modify: `packages/solo/lib/src/lane.dart` (`_SoloPoolCore`: учёт записей)
- Modify: `packages/solo/lib/src/job.dart` (поле `_writer`, наследуется
  ребёнком при усыновлении, `job.dart:168`)
- Modify: `packages/solo/lib/src/job_context.dart` (`:328`)
- Test: `packages/solo/test/pool_test.dart`

**Interfaces:**
- Consumes: задача 2 — `_holderOf`.
- Produces: `_SoloLaneCore.wrote(int revision, int writer)` — у линии
  `lastWrite = revision`; `_wroteSinceSeen` → `({String name, _Wrote by})?`.

- [ ] **Step 1: Написать падающие тесты** (группа `policies`, `rules`)

```dart
test('droppable hands back the running job of the key', ...);
test('droppable hands back the queued job of the key', ...);
test('droppable in a drain hands back the accepted job of the key', ...);
test('keepLatest drops the queued jobs of the key, not the running one', ...);
test('restart cancels the running job of the key and starts after its end',
  ...);
  // a1 running with ifCancelled writing 7; a2 restart: a1 ends
  // Cancelled(replaced); state 7 is written before 'start a2'.
test('restart leaves the running jobs of other keys alone', ...);
test('canStart and W are asked at the start, after an overtaking', ...);
  // a2 of a held key with canStart(state > 0); b written state 1 while
  // a2 waited: a2 starts.
test('a write of another job of the pool over a stale read says so', ...);
  // Solo.debug lines: p1 reads, waits, p2 of the same pool writes, p1
  // writes what it read: one line
  // 'Job(p1) emit over a write of another job of pool likes made after '
  // 'Job(p1) last read the state: read ctx.state after the wait, or this '
  // 'write undoes the work of that job'.
test('a write of a child of the same root says nothing', ...);
test('a write of another lane over a pool job reads as today', ...);
  // the lane line word for word, naming the lane.
test('a write of another pool says pool', ...);
  // 'Job(p1) emit over a write of pool uploads made after ...'.
```

- [ ] **Step 2: Прогнать — падают**

Run: `cd packages/solo && dart test test/pool_test.dart -N policies` Expected:
FAIL на `restart` и строке о записи.

- [ ] **Step 3: Политики**

В `_enqueueIn` ветка ядра пула:
- `droppable`: поиск `_lastJobWhereIn` уже видит `running` (задача 1); строка
  дубликата для идущей — как у линии (`'$line,
  which is running: if awaited from inside $name, it waits for itself'`), для
  стоящей в очереди — `'$line, which is queued'`, для задачи в окне правил —
  `$line` как есть, как у линии без `current`;
- `keepLatest`/`restart`: снятие очереди ключа как есть; `restart` отменяет
  `poolQueue._holderOf(key)`, если это идущая задача (а не окно), с тем же
  `ReplacedCancelReason` и строкой `'restart: ${current._restartAnswer}'`.

- [ ] **Step 4: Учёт записей пула**

Строка «emit over» должна видеть запись другого корня своего пула, но не своего
ребёнка. Корню пула при постановке ядро даёт номер
(`job._writer = ++core._writers`) рядом с `impl._execution = core`
(`solo.dart:1040`), после всех отказов `_enqueueIn` и только для ядра пула:
повторная постановка идущей задачи бросает раньше и номер не трогает. Ребёнок
берёт номер родителя. Ядро пула держит четыре числа — `_writers` и три ниже,
`_setState` зовёт `emitter._execution?.wrote(revision, emitter._writer)`:

```dart
// _SoloPoolCore:
int lastWriter = 0;     // the root number of the last write
int otherWrite = 0;     // the last write of a root other than lastWriter
@override
void wrote(int revision, int writer) {
  if (writer != lastWriter) {
    otherWrite = lastWrite;
    lastWriter = writer;
  }
  lastWrite = revision;
}
/// The last write made by a root of this pool other than [writer].
int writeOtherThan(int writer) =>
    writer == lastWriter ? otherWrite : lastWrite;
```

`_wroteSinceSeen`: своё ядро линии пропускается как сейчас; своё ядро пула
участвует числом `writeOtherThan(job._writer)`; побеждает самая поздняя запись,
как сейчас. Ответ — `({String name, _Wrote by})?`, где
`enum _Wrote { lane, ownPool, pool }`: `ownPool` — строка пула из шага 1;
`pool` — строка линии, где «lane» — «pool»: `'$_job emit over a write of pool
$name made after $_job last read the state: read ctx.state after the wait,
or this write undoes the work of $name'`; `lane` — нынешняя строка слово
в слово.

- [ ] **Step 5: Прогнать — зелёное, коммит**

Run: `cd packages/solo && dart test` Expected: PASS.

```bash
git commit -am "feat(solo): run the policies and the rules in a pool"
```

---

### Task 4: Закрытие, `drain`, `pending` и ожидание своего пула

**Files:**
- Modify: `packages/solo/lib/src/solo.dart` (`_pendingOf`, `_pending`
  `SoloLanes`, `_stepPool`)
- Modify: `packages/solo/lib/src/lane.dart` (`_SoloPool.pending`)
- Modify: `packages/solo/lib/src/pending.dart` (dartdoc, `_SoloPendingPlaces`)
- Modify: `packages/solo/doc/diagnostics.md`, `docs/ru/solo/diagnostics.md`
- Test: `packages/solo/test/pool_test.dart`

**Interfaces:**
- Produces: `List<SoloPendingLane> _pendingEntriesOf(_SoloPoolCore<S> core)`
  в `SoloController`; `SoloPool.pending` → `null` или всегда `SoloPendingLanes`
  с записями этого пула (форма не зависит от числа идущих).

- [ ] **Step 1: Написать падающие тесты** (группа `closing`, `pending`,
  `awaiting the own pool`)

```dart
test('drain ends once the queue is empty and every place is over', ...);
test('drain of a pool with a canceled queued upload ends', ...);
  // the uploads of the debate: three uploads in a pool of 2, the third
  // cancelled before its start: ends Cancelled(manual, started: false),
  // the other two complete, close(mode: drain) completes.
test('close with a cancel drops the queue before any running job hears', ...);
test('pending gives an entry for every running job', ...);
  // two running a1, b; a2 of key 'a' queued: pending is SoloPendingLanes
  // with two SoloPendingLane of pool.id; a1's SoloPendingJob.queued == [a2],
  // b's queued is empty.
test('pending shows the jobs that wait for a place', ...);
  // pool of 1, x running, c without a key queued: entries are
  // SoloPendingJob(x) and SoloPendingQueue([c]).
test('pending in a drain shows what has not started', ...);
test('pool.pending is a list for one running job as for two', ...);
test('a job awaiting a job of its own key in its pool waits for good', ...);
  // fakeAsync, elapse 1 hour: the awaited job has not started.
test('a job awaiting another key of its pool with a free place ends', ...);
test('every place awaiting its pool waits for good, and pending says it',
  ...);
```

- [ ] **Step 2: Прогнать — падают**

Run: `cd packages/solo && dart test test/pool_test.dart -N pending` Expected:
FAIL.

- [ ] **Step 3: `pending` пула**

`_pendingEntriesOf(core)`: для каждой задачи `running` по порядку старта —
`SoloPendingLane(core.id!, job._pending(closing:, draining:,
queued: List.unmodifiable(<задачи её ключа в очереди>)))`; затем, если
`_draining || core.isFull`, — одна
`SoloPendingLane(core.id!, SoloPendingQueue(...))` с задачей окна, если она
не закончена, и задачами очереди, чей ключ не держит ни одна идущая; пустой
список — без записи. `SoloLanes._pending` для ядра пула добавляет все его
записи, для линии — как сейчас. `SoloPendingLanes.lanes`
и `SoloPendingLane.pending` в dartdoc говорят: у пула записей столько, сколько
идёт задач, плюс одна очередь; `SoloPendingQueue` — что у пула она бывает и без
`drain`, когда заняты все места; абзац dartdoc о группах, которые держит окно
(`pending.dart:180-185`), — что у пула там бывают и задачи, ждущие места. Вне
`drain` запись — закрытый подкласс
`_SoloPendingPlaces extends SoloPendingQueue` в `pending.dart` (подкласс
`final`-класса в своей библиотеке разрешён, публичного API нет) с `toString`
`'SoloPending(waiting for a place, ${jobs.length} queued: $jobs)'`: нынешний
`'SoloPending(draining, ...)'` (`pending.dart:203-205`) сказал бы неправду.
Тест на обе строки. `doc/diagnostics.md:164-183` и перевод: у пула записей
столько, сколько идёт задач, и одна очередь.

- [ ] **Step 4: Прогнать — зелёное, коммит**

Run: `cd packages/solo && dart test` Expected: PASS.

```bash
git commit -am "feat(solo): close, drain and say what holds a pool"
```

---

### Task 5: Накопитель в пуле

**Files:**
- Modify: `packages/solo/lib/src/accumulator.dart` (`:233`, `:280`)
- Modify: `packages/solo/lib/src/lane.dart` (`runsGroupOf`, `isFull` базы)
- Test: `packages/solo/test/pool_test.dart`

**Interfaces:**
- Produces: `_SoloLaneCore.runsGroupOf(Object owner)` → `bool` (у линии
  `identical(current?._accumulation?._owner, owner)`, у пула — любая
  из `running`); `_SoloLaneCore.isFull` у линии — `current != null`.

- [ ] **Step 1: Написать падающие тесты** (группа `accumulation`)

```dart
test('groups of an accumulator without a key run side by side', ...);
  // pool of 2, collect without key, debounce: two groups made one after
  // another both run before the first ends.
test('groups of an accumulator with a key run one at a time', ...);
test('a throttle wakes the pump when the pool has a free place', ...);
  // pool of 2, one long job of another key runs, a throttled group
  // waits out its interval: it starts at the end of the interval, not at
  // the end of the long job. A guard: green before this task too, since
  // a pool core never sets current.
test('a group of a pool running past its interval does not rearm it', ...);
  // throttle without startAtOnce, a group longer than the interval;
  // an add after the interval while the group still runs: the new group
  // starts as soon as a place is free, without a second interval —
  // red today: _isIdle reads current, which a pool never sets.
```

- [ ] **Step 2: Прогнать — падают**

Run: `cd packages/solo && dart test test/pool_test.dart -N accumulation`
Expected: FAIL на «does not rearm it»: `_isIdle` (`accumulator.dart:231-233`)
не видит своей группы среди идущих пула.

- [ ] **Step 3: Реализация**

`_isIdle`: `!_hasQueuedGroup && !_core.runsGroupOf(this)`; пробуждение
throttle: `if (!_core.isFull && _hasQueuedGroup) _schedulePump();`. Для линии
оба выражения равны нынешним.

- [ ] **Step 4: Прогнать — зелёное, коммит**

Run: `cd packages/solo && dart test` Expected: PASS, включая
`accumulation_*_test.dart` без правок.

```bash
git commit -am "feat(solo): queue the groups of an accumulator in a pool"
```

---

### Task 6: Неизменность `Solo` и линий

**Files:**
- Test: `packages/solo/test/pool_test.dart` (группа `lanes as they were`)

- [ ] **Step 1: Тесты-сторожа**

```dart
test('a controller with a pool keeps the lines of its lanes', ...);
  // the same scenario on a SoloLanes with lane 'a' only and with lane 'a'
  // and pool 'p' idle: the Solo.debug lines of lane 'a' are equal.
test('a lane next to a busy pool counts its microtasks as before', ...);
  // real async: the number of `await Future<void>.value()` turns until a
  // lane job ends is the same with and without a busy pool declared
  // after it.
```

- [ ] **Step 2: Сверка прежнего набора**

Run: `git diff main --stat -- packages/solo/test` — только добавления;
`git diff main -- packages/solo/test | grep '^-[^-]'` — пусто, кроме счётчиков
`lanes_rakes_test.dart`, которые поднимет задача 8. Run:
`cd packages/solo && dart test` и `cd packages/solo/example && dart test`.
Expected: PASS.

- [ ] **Step 3: Коммит**

```bash
git commit -am "test(solo): pin the lanes beside a pool"
```

---

### Task 7: Линты

**Files:**
- Modify: `packages/async_job_lints/lib/src/context.dart` (`:75`, `:96-103`,
  `:480`, `:578`), `packages/async_job_lints/lib/plugin_api.dart`
- Modify: `packages/async_job_lints/CHANGELOG.md`, его перевод
  `docs/ru/async_job_lints/CHANGELOG.md`
- Modify: `packages/solo_lints/lib/src/rules/lane_outside_constructor.dart`
  (`:51-52`), `await_own_queue.dart`, `stale_emit.dart` (`:117`)
- Modify: `packages/solo_lints/CHANGELOG.md`, `README.md` и переводы
- Test: `packages/async_job_lints/test/` (файлы правил, где лежат тесты
  `queueLaneOf`),
  `packages/solo_lints/test/lane_outside_constructor_test.dart`,
  `await_own_queue_test.dart`, `stale_emit_test.dart`

Находка плана: распознавание линии живёт в `async_job_lints` (`isSoloLane`,
`_laneField`, `_laneQueuedBy`, `isSoloMember`), а не в `solo_lints`, как
говорит дизайн. Значит, меняются оба пакета линтов: `async_job_lints` — патчем
(новое распознавание, ни одного нового правила), `solo_lints` — минором после
него.

**Interfaces:**
- Produces (`plugin_api.dart`): `bool isSoloQueueOwner(DartType? type)` —
  `SoloQueueOwner`, `SoloLane`, `SoloPool` и подтипы;
  `bool isSoloPool(DartType? type)`. `isSoloLane` остаётся как есть.

- [ ] **Step 1: Падающие тесты**

`async_job_lints`: поле `SoloPool` в `SoloLanes` — поле своей очереди для
`queueLaneOf` (ожидание задачи своего пула — `QueueLane.own`, другого —
`QueueLane.other`); `enqueue` пула считается `Solo.enqueue` для `isSoloMember`.
`solo_lints`:

```dart
// lane_outside_constructor_test.dart
Future<void> test_pool_in_late_final_initializer() => ...;
  // late final _likes = pool('likes', concurrency: 4); — reported with
  // LaneOutsideConstructor.poolCode
Future<void> test_pool_in_constructor_body() => ...;   // []
// await_own_queue_test.dart
Future<void> test_await_own_pool() => ...;
  // await _likes.enqueue(...) inside a job of _likes: poolCode with
  // arguments [enqueue, _likes]
Future<void> test_await_other_pool() => ...;            // []
// stale_emit_test.dart
Future<void> test_pool_member_body() => ...;
  // a body given to _likes.enqueue that reads before an await and emits
  // after it: reported as for a lane member
```

- [ ] **Step 2: Прогнать — падают**

Run: `cd packages/solo_lints && dart test`
и `cd packages/async_job_lints && dart test` Expected: FAIL на новых тестах.

- [ ] **Step 3: Распознавание**

`context.dart`: `isSoloQueueOwner`, `isSoloPool`; `_laneField` берёт поля
`isSoloQueueOwner`; `_laneQueuedBy` принимает владельца `SoloLane`, `SoloPool`
и `SoloQueueOwner`; `isSoloMember` для `type == 'Solo'` — член любого из трёх.
Поле — «своя очередь», только если записано объявлением в теле конструктора:
`_LaneDeclarations.visitAssignmentExpression` (`:521`) зовёт `declaresLane`
(`:559-570`), а та знает один `lane`. Новая
`bool declaresQueueOwner(MethodInvocation call)` — то же для `lane` и `pool`,
экспорт в `plugin_api.dart`; `_LaneDeclarations` зовёт её. `declaresLane`
экспортирована (`plugin_api.dart:27`) и смысла не меняет. Тест
в `async_job_lints`: `bare_await` и `discarded_outcome` при
`ownLaneReportedElsewhere` молчат на ожидании своего пула
(`bare_await.dart:112-113`, `discarded_outcome.dart:92-93`).

- [ ] **Step 4: Правила `solo_lints`**

- `LaneOutsideConstructor.poolCode`:
  ```dart
  static const LintCode poolCode = LintCode(
    'lane_outside_constructor',
    "'pool' outside the constructor body throws once SoloLanes has sealed "
        'its set of lanes and pools, a microtask after the constructor.',
    correctionMessage:
        "Call 'pool' in the constructor body and keep the pool in a "
        "'late final' field.",
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'LintCode.lane_outside_constructor_pool',
  );
  ```
  `diagnosticCodes` — `[code, poolCode]`; визитор узнаёт
  `isSoloMember(..., 'SoloLanes', 'pool')` и пропускает
  `declaresQueueOwner(node)` (сегодня `declaresLane`, `:52`).
- `AwaitOwnQueue.poolCode`:
  ```dart
  static const LintCode poolCode = LintCode(
    'await_own_queue',
    "'{0}' waits for a job of the pool '{1}' this job runs in: a job of the "
        'same key never starts while this one runs, and with every place '
        'taken no job of the pool does.',
    correctionMessage:
        "Run the job with 'ctx.run' instead of the pool, or queue it in "
        'another lane or pool.',
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'LintCode.await_own_queue_pool',
  );
  ```
  `severity` и прочие поля — как у `laneCode`; выбор кода —
  по `isSoloPool((lane as FieldElement).type)`: `queuedBodyOf(...).lane` —
  `Element?` (`context.dart:616`), а `_laneField` отдаёт `FieldElement`.
- `stale_emit`: `isSoloLane` → `isSoloQueueOwner` (`:117`).

- [ ] **Step 5: CHANGELOG, README, переводы**

`async_job_lints`: «Unreleased» — экспортированы `isSoloQueueOwner`,
`isSoloPool` и `declaresQueueOwner`; поле `SoloPool`, объявленное в теле
конструктора, — поле своей очереди для `queueLaneOf`; `declaresLane`
по-прежнему только о `lane`. `solo_lints`: «Unreleased» — три правила о пуле;
требует `async_job_lints` нового патча (ограничение поднимает подготовка
выпуска). Переводы тем же коммитом; `python3 tool/check_translations.py`.

- [ ] **Step 6: Прогнать, проверки, коммит**

Run: в `packages/async_job_lints` и `packages/solo_lints` — `dart format`,
`dart analyze --fatal-infos`, `dart test`; из корня
`python3 tool/plugin_probe.py`. Expected: PASS.

```bash
git commit -am "feat(lints): know the pools of SoloLanes"
```

---

### Task 8: Документация

**Files:**
- Modify: `packages/solo/doc/lanes.md` — раздел `## A pool of places` перед
  `## Declaring lanes`, строки в `## The table of cases`, абзац о `pool`
  в `## Declaring lanes`
- Modify: `packages/solo/test/support/lanes_page.dart` и соседи — драйверы
  нового раздела; `packages/solo/test/lanes_rakes_test.dart` — сторож страницы:
  счётчики `:1187`, `:1192`, карта `holders` `:1204`, тест «every heading with
  code under it is held to a file» `:1236`
- Modify: `packages/solo/doc/vs-bloc.md:94-96`, `tool/doc_snippets.py`
  (`QUOTED`, `SAID`), если цитата касается этих строк
- Modify: dartdoc `Policy`, `Policy.sequential` (`policy.dart`),
  `SoloPendingJob.queued`, `SoloQueue` (`queue.dart:11-19`: в пуле задачу
  занятого ключа обгоняют, а группа, ждущая окна, держит задачи своего ключа),
  библиотеки (`lib/solo.dart:1-2`: «One job at a time…»), `lane`, `close`,
  `cancelAll` («the current job of every lane»)
- Modify: `packages/solo/CHANGELOG.md` («Unreleased»), README `solo`, если его
  таблица выбора контроллера говорит «по одному корню»
- Modify: переводы — `docs/ru/solo/lanes.md`, `docs/ru/solo/vs-bloc.md`,
  `docs/ru/solo/CHANGELOG.md`, `packages/solo/README.ru.md`
- Modify: `docs/settled.md` (решение 84), `docs/architecture.md`

- [ ] **Step 1: Раздел страницы**

По скиллу `doc-reader`: раздел начинается с ошибки. Первая попытка — рабочая
линия с вечной задачей из спора
(`2026-11-12-bloc-vs-solo-second-debate-report.md`): отменённая до старта
загрузка роняет рабочего, `drain` не кончается; трасса из драйвера. Ответ — пул
из «Два примера» дизайна: лайки с ключом поста и загрузки без ключа, с трассами
лайков (снятие `p1` в 2010 мс, лайк `p2` в 150 мс). Затем: ключ держит порядок
и с `sequential`, поэтому один постоянный ключ у всех задач пула делает пул
линией; `running` вместо `current`; ожидание своего пула (таблица дизайна)
и линт `await_own_queue`. Код раздела — под стендом страницы линий, как
остальные разделы (задача добавляет драйверы и сторожа, прежних не трогает).

- [ ] **Step 2: `vs-bloc.md`**

Фраза «There is no concurrent root-job policy…» становится правдой о пуле:
корни `Solo` и линии идут по одному, пул `SoloLanes` — до N, по ключу
по одному; ссылка на `lanes.md#a-pool-of-places`; та же ссылка — в dartdoc
`SoloPool`. Прогнать стенд: `python3 tool/doc_snippets.py`
и `python3 tool/check_traces.py`.

- [ ] **Step 3: dartdoc, CHANGELOG, README**

`Policy.sequential`: «keys are ignored» — у `Solo` и линии; в пуле ключ держит
порядок своих задач. CHANGELOG `solo`, «Unreleased», Features: `pool`, `pools`,
`SoloPool`, `SoloQueueOwner`; в Notes — подкласс `SoloLanes` со своим членом
`pool` или `pools` перестанет собираться.

- [ ] **Step 4: Переводы и записи**

Переводы каждого изменённого английского абзаца; `humanizer--ru` на изменённых
абзацах переводов (только `ERROR` линтера скилла). `docs/settled.md`, решение
53: ожидающая группа пропускает готовую в `Solo` и линии; в пуле она держит
готовые задачи своего ключа — слово владельца 2026-11-27 «держит, порядок ключа
строгий». Решение 84: посылка — «не больше суммы объявленных мест линий
и пулов»; там же «постановка, удаление и запуск за O(1)» дополняется: у очереди
пула — `O(log R)` по числу кандидатов, задачи занятых ключей не стоят ничего.
Решения 50 («текущую задачу своей линии») и 54 («дедлок — внутри одной линии»):
формулировки — о линии или пуле. `docs/architecture.md` — ядро пула
в устройстве `solo`.

- [ ] **Step 5: Проверки и коммит**

Run: из корня `python3 tool/reflow.py --check`,
`python3 tool/check_line_width.py`, `python3 tool/check_links.py`,
`python3 tool/check_dartdoc.py`, `python3 tool/check_translations.py`,
`python3 tool/build_site.py` с его сторожем; в `packages/solo` — `dart test`.
Expected: всё зелёное.

```bash
git commit -am "docs(solo): a pool of places on the lanes page"
```

---

### Task 9: Итоговая проверка и отчёт

- [ ] **Step 1: Весь гейт в копии**

Все пять заданий CI локально: `dart` (ядро и пример без Flutter в PATH, оба
линта, `tool/plugin_probe.py`), `flutter` (`flutter_solo`, его пример,
`camera_example`), `floor` (`tool/archive_floor.py stage` и `run`
на `~/fvm/versions/3.38.1`), `snippets` (пять стендов
и `tool/check_traces.py`), `docs` (семь проверок и сборка сайта). Expected:
зелёные все.

- [ ] **Step 2: Ревью всей ветки**

Свежий ревьюер на Opus в своей копии дерева на `HEAD` ветки: дизайн, план, дифф
`main..solo-pool`. Находки — в отчёт с вердиктами; принятые исправляются
отдельными коммитами.

- [ ] **Step 3: Отчёт и состояние**

`docs/records/2026-11/2026-11-27-solo-pool-report.md` (или дата дня
исполнения): что сделано, замеры задачи 2, решения исполнителя и расхождения
с дизайном (цена `O(log R)`, находка о `async_job_lints`), ревью. Шапки дизайна
и плана — «исполнено, ждёт выпуска». `docs/handoff.md`. Вливание в `main` —
`git merge --ff-only solo-pool` после проверки ветки и `git status` основной
копии.

## Ревью плана

План `9168fdbe` прочёл свежий агент на Opus в своей копии дерева: где план
расходится с кодом и дизайном, что исполнитель не сможет сделать однозначно.
Каждое его утверждение о коде сверено с кодом. Находки — его словами вкратце.

1. Задача 7 не трогает `declaresLane` и `_LaneDeclarations`
   (`context.dart:521`, `:559-570`): поле `pool(...)` не станет своей очередью,
   новые тесты линтов покраснеют, а `lane_outside_constructor` сообщит
   и о `pool` в теле конструктора.

   Вердикт: принято. В задачу 7 вписана `declaresQueueOwner`; экспортированная
   `declaresLane` смысла не меняет; добавлен тест молчания `bare_await`
   и `discarded_outcome`.

2. «В тестах только добавления» нарушают `reference_page_test.dart` (требует
   строку справки на каждый член) и счётчики `lanes_rakes_test.dart`.

   Вердикт: принято. Справка `doc/reference.md` с переводом — в задаче 1;
   счётчики сторожа страницы — названное исключение ограничения и задачи 6.

3. Новый кандидат, допущенный вне насоса (снятие головы ключа, `_moveToTail`),
   не будит насос: `_onJobFinished` будит только при `wasCurrent || _draining`
   (`solo.dart:1207`).

   Вердикт: принято. `_unlink` очереди пула будит насос, два теста.

4. Строгий порядок ключа сталкивается с решением 53 `docs/settled.md`
   («ожидающая группа пропускает готовую») и dartdoc `SoloQueue.jobs`:
   держит ли группа, ждущая окна, готовые задачи своего ключа.

   Вердикт: вынесено владельцу; ответ — «держит, порядок ключа строгий».
   Правило и тест — в задаче 2; решение 53 и dartdoc `SoloQueue.jobs` правит
   задача 8.

5. Тест throttle в задаче 5 зелёный до неё: ядро пула не ставит `current`.
   Падает `_isIdle` при группе длиннее интервала.

   Вердикт: принято. Тест throttle оставлен сторожем, добавлен тест
   на `_isIdle`, ожидаемое падение названо.

6. `SoloPendingQueue.toString` говорит «draining» и вне `drain`
   (`pending.dart:203-205`), абзац dartdoc `:180-185` для пула ложен,
   `doc/diagnostics.md:164-183` не правится.

   Вердикт: принято. Закрытый подкласс `_SoloPendingPlaces` со своей строкой,
   правка dartdoc и страницы диагностики с переводом.

7. Строка «emit over» о записи другого пула назвала бы его линией.

   Вердикт: принято. Три вида ответа: линия, свой пул, другой пул.

8. Место, где корень пула получает номер писателя, не названо; счётчик
   `_writers` не объявлен.

   Вердикт: принято. Номер — рядом с `impl._execution = core`, после отказов;
   чисел четыре.

9. Причина отказа `pool` после `enqueueJob` назвала бы только пулы.

   Вердикт: принято. Тексты `why` пула выписаны целиком.

10. Строка «queue has no ready jobs» в `_stepPool` неоднозначна: `took` в линии
    значит «взял и отбросил».

    Вердикт: принято. Флаг `dropped`, сброс при запуске, молчание о задачах
    занятых ключей.

11. Тест «один проход» и счёт микрозадач в задаче 6 на `flushMicrotasks` ничего
    не различают.

    Вердикт: принято. Оба — на настоящем async, счёт продолжений
    `await Future<void>.value()`.

12. `O(log R)` держится, но решение 84 говорит «за O(1)».

    Вердикт: принято. Решение 84 дополняется в задаче 8.

13. Второе расхождение (`async_job_lints`) держится; новый экспорт —
    в CHANGELOG.

    Вердикт: принято. CHANGELOG `async_job_lints` перечисляет экспорт.

14. Документы, которых нет в задаче 8: `doc/diagnostics.md`, dartdoc
    `SoloQueue`, библиотеки, `lane`, `close`, `cancelAll`, решения 50 и 54.

    Вердикт: принято. Вписаны в задачи 4 и 8.

15. Ссылка `#a-pool-of-places` в dartdoc задачи 1 мертва до задачи 8,
    а `check_links.py` проверяет dartdoc.

    Вердикт: принято. Ссылку ставит задача 8.

16. У `queuedBodyOf(...).lane` тип `Element?`, `.type` нет.

    Вердикт: принято. `(lane as FieldElement).type`.

17. Строка дубликата `droppable` для задачи в окне правил не названа.

    Вердикт: принято. `$line` как есть, как у линии без `current`.

18. `packages/solo/example` зависит от `solo` путём, оверрайд лишний; пути
    не названы.

    Вердикт: принято. Пять файлов, пути выписаны.

19. `_release` до `_schedulePump` при броске ключа оставит насос
    незапланированным.

    Вердикт: принято. `_release` — после планирования насоса.
