> **Состояние на 2026-09-03:** ревью принято, правки в работе; вердикты
> стоят в конце каждой находки.
> **Что это:** независимое ревью README пакета `solo` перед публикацией,
> сделанное агентом с чистым контекстом, и решения владельца по нему.
> **Связанные записи:** `2026-09-02[1]-solo-design.md`,
> `2026-09-02[2]-solo-plan.md`, `2026-09-03[1]-solo-final-review-report.md`.

# Независимое ревью README (2026-09-03)

Ревьюер — агент с чистым контекстом, роль: сторонний Dart-разработчик с
опытом bloc в проде, впервые видящий пакет. Читал README сверху вниз, потом
проверял каждое утверждение против исходников bloc 9.2.1,
bloc_concurrency 0.3.0, локального `packages/solo/lib/src/`, трекера bloc и
прогонов всех фрагментов кода.

Пути к пробам в тексте ведут во временный каталог сессии и уже не
существуют; сами проверочные проекты жили вне репозитория.

Текст ревью ниже приведён целиком и по-английски, как его написал ревьюер;
проза находок не тронута. Вердикт владельца и мой разбор стоят отдельными
абзацами в конце каждой находки, по одному на находку.

## Решения владельца

1. Раздел «Where bloc falls short» вынесен из README в отдельный документ
   `packages/solo/doc/vs-bloc.md` (перевод — `doc/vs-bloc.ru.md`).
2. Формат сравнения изменён: сначала рабочее решение задачи на bloc — то,
   что напишет знающая команда, — с его ценой, и только потом то же самое
   на `solo`.
3. Быстрый старт упрощён, камера ушла ниже развёрнутым примером.
4. Добавлены разделы про ошибки, тесты, владение контроллером во Flutter и
   таблица миграции с bloc.
5. Движок изменён: отказ (`Failed`), которого никто не наблюдал, уходит в
   зону через `handleUncaughtError`; появился `Job.ignore()`.
6. Вырезать ли пункт 6 (метод, а не событие) — владелец решит позже, пункт
   пока оставлен.

---

# Independent review — `packages/solo/README.md` (solo 1.0.0)

Reviewer: outside Dart/Flutter engineer, production bloc background, no prior
contact with this project. Read top to bottom once as a newcomer, then verified.

Everything below was checked against
`~/.pub-cache/hosted/pub.dev/bloc-9.2.1/lib/src/`,
`~/.pub-cache/hosted/pub.dev/bloc_concurrency-0.3.0/lib/src/`,
`/Users/user/development/my/solo/packages/solo/lib/src/`, the GitHub tracker
(`gh issue view`), and by compiling and running every snippet. New probes:

- `/private/tmp/claude-502/-Users-user-development-my-solo/f493d04f-2035-4661-8bac-8c3b11712a69/scratchpad/bloc_check/bin/rev_item7_close.dart`
- `/private/tmp/claude-502/-Users-user-development-my-solo/f493d04f-2035-4661-8bac-8c3b11712a69/scratchpad/bloc_check/bin/rev_items.dart`
- `/private/tmp/claude-502/-Users-user-development-my-solo/f493d04f-2035-4661-8bac-8c3b11712a69/scratchpad/bloc_check/bin/rev_fairness.dart`
- `/private/tmp/claude-502/-Users-user-development-my-solo/f493d04f-2035-4661-8bac-8c3b11712a69/scratchpad/solo_check/bin/rev_solo.dart`
- `/private/tmp/claude-502/-Users-user-development-my-solo/f493d04f-2035-4661-8bac-8c3b11712a69/scratchpad/solo_check/bin/rev_quickstart.dart`
- `/private/tmp/claude-502/-Users-user-development-my-solo/f493d04f-2035-4661-8bac-8c3b11712a69/scratchpad/solo_check/bin/rev_debounce_exact.dart`
- `/private/tmp/claude-502/-Users-user-development-my-solo/f493d04f-2035-4661-8bac-8c3b11712a69/scratchpad/solo_check/bin/rev_gaps.dart`
- `/private/tmp/claude-502/-Users-user-development-my-solo/f493d04f-2035-4661-8bac-8c3b11712a69/scratchpad/solo_check/bin/rev_reads.dart`
- `/private/tmp/claude-502/-Users-user-development-my-solo/f493d04f-2035-4661-8bac-8c3b11712a69/scratchpad/solo_check/bin/rev_close_bare.dart`
- `/private/tmp/claude-502/-Users-user-development-my-solo/f493d04f-2035-4661-8bac-8c3b11712a69/scratchpad/solo_check/bin/rev_lang36.dart`

---

## 1. Verdict in three sentences

The bloc half of this README is the most accurate competitive comparison I have
read in a Dart package: I tried to break all eight items and could not — every
issue quote is verbatim and in context, and even the subtlest claim (that
`sequential()` alone makes `close()` wait for the running handler so the late
`emit` lands, while every other transformer drops it silently) is exactly right,
which I confirmed by running it. The solo half is weaker than the bloc half: the
item-4 firmware snippet can only ever flash once because `Policy.restart` and
`canStart: (state) => state is Idle` contradict each other, the Debounce recipe
does not compile as printed, and the item-5 checkout snippet reproduces the very
confusion it accuses bloc of — `pay(orderB)` returns `Done(receipt for orderA)`.
Structurally the document is upside down: 58% of it argues against bloc using API
the reader will not be introduced to for another 600 lines, and it never answers
three day-one questions — how do I test a controller, what happens when a job
throws and nobody is looking, and who owns and closes the controller in Flutter.

**Publish as is? — With fixes.** (Details in §6.)

---

## 2. Part A — the reader's experience

### A1. The whole comparison section sits before the tutorial (Critical, structural)

**Lines 28–635.** "Where bloc falls short" is 608 of the README's 1056 lines —
58% — and it runs *before* `## Install` (636), `## Quick start` (648) and
`## Concepts` (788).

The result is that every `solo` API is used long before it is defined. A newcomer
meets, in order and with no explanation:

| README line | First use | First explanation |
|---|---|---|
| 94 | `extends Solo<DeviceState>` | 795 |
| 101 | `Job<void>` | 800 |
| 104 | `queue.removeWhere` | 846 |
| 108 | `run<Connected, void>(key:, …)` | 800 / 806 |
| 109 | `ctx.guard(…)` | 822 |
| 112 | `ctx.emit(…)` | 793 |
| 119 | `Cancelled(manual)`, `done` | 836 |
| 189 | `Policy.restart` | 846 |
| 325 | `canStart:` | 811 |
| 611 | `externalSetState` | 831 |
| 712 | `describe:` | never |

The very first `solo` code the reader sees (lines 91–117) contains six
undocumented concepts at once. A reader trying to *evaluate* the package cannot
tell whether the code is elegant or arbitrary, because they cannot read it yet.

Quote that shows the problem: line 108–114,

> ```dart
> return run<Connected, void>(
>   key: DeviceKey.disconnect,
>   (ctx) async {
>     await ctx.guard(_ble.disconnect);
>     ctx.emit(const Offline());
>   },
> );
> ```

A reader who has never seen this package cannot tell what `Connected` is doing
in the type argument, why the body is the *last* argument after named ones
(that's Dart's named-arguments-anywhere, fine on the declared SDK — I verified
`// @dart=3.6` accepts it — but it looks like a typo the first time), or what
`guard` guards.

**Suggested rewrite.** Move `Install` + `Quick start` + `Concepts` ahead of the
comparison, and reduce "Where bloc falls short" to two or three items in the
README with a link to a `doc/vs-bloc.md` for the rest. The current order asks
the reader to be persuaded before they can be taught.

**Вердикт (2026-09-03):** Принято, и сильнее предложенного: раздел вынесен
целиком в `packages/solo/doc/vs-bloc.md`, в README остался указатель из «Why».
Инлайн-пунктов не оставлено — документ теперь опирается на раздел Concepts и
потому пишет `Policy.restart` и `keepWhile` прямо, без опережающих ссылок.

### A2. "six complaints" vs eight items (Important)

**Line 12:** "`solo` grew out of six complaints about bloc". **Lines 25–26:**
"[Where bloc falls short](#where-bloc-falls-short) shows all six in code, on
eight scenarios from different domains."

Items 7 ("Closing while work is in flight") and 8 ("The state changes from
outside") do not correspond to any of the six. The reader tries to map 8 → 6,
fails, and then hits line 45, "`emit` after `close` throws … (item 7 below)",
which speaks of item 7 as if it were on the list. Line 285's mirror-image
paragraph and item 3 also do not map cleanly onto complaint 3.

**Suggested rewrite.** Either make it eight complaints, or say "six complaints,
plus two more traps that showed up later — items 7 and 8".

**Вердикт (2026-09-03):** Принято, исправлено: указатель говорит про восемь
сценариев, список из шести претензий остался списком претензий.

### A3. The Quick start is not a quick start (Important)

**Lines 648–786, 138 lines.** It opens with a 31-line four-class sealed
hierarchy, then a 66-line controller that uses `Policy.droppable`,
`Policy.replace`, `describe:`, `canStart:`, `cancellable: false`,
`queue.clear(force: true)`, `current?.cancel()`, `ctx.run(child)` and `ctx.log`.

Three specific problems:

1. **Line 725, `queue.clear();` inside `takePhoto`.** Nothing explains why
   taking a photo throws away every queued job. The prose at 780–786 covers
   `replace`, `droppable` and `dispose` but never this line. To a newcomer it
   reads as a bug or a copy-paste slip. Either explain it ("a shot invalidates
   the pending zoom/focus commands") or delete it from the first example.
2. **Lines 737–754, `dispose()`.** This is the most advanced code in the whole
   README — queue surgery, a non-cancellable job, a child job awaited by handle
   — and it is the second method a reader ever sees.
3. **`dispose()` and `close()` are both used** (line 768 and line 777) and their
   relationship is never stated. A newcomer will ask: do I need both? What
   happens if I only call `close()`? (Answer, from `solo_base.dart:204-241`: you
   skip your own teardown job entirely.) This must be one sentence in the text.

**And the Quick start never shows how to read the state.** Lines 760–778 create
a controller, drive it, and close it — but never touch `camera.state` and never
subscribe to `camera.stream`. For a *state-management* package, the first
example not showing state consumption is a striking omission. `stream` is
mentioned once, at line 855, in a Concepts bullet.

**Suggested rewrite.** A 20-line first example: one state class, two jobs, one
`await job.done`, one `controller.stream.listen(print)`. Move the camera
controller to a "A fuller example" section after Concepts.

**Вердикт (2026-09-03):** Принято: быстрый старт переписан на
`ProfileController` — состояние, одна задача, чтение `state`, подписка на
`stream`, `await job.value`, `close()`. Камера ушла в раздел Example с разбором
`queue.clear()`, рабочего типа и разницы `dispose()` и `close()`.

### A4. Nothing about testing (Important — the biggest missing piece)

The README never shows a test. Line 1048 mentions "four tests over an ordered
journal" in `example/`, and that is all. bloc ships `bloc_test`; a reader
switching away from it will ask on day one:

- How do I assert a sequence of states? (`solo.stream` is async, so
  `expectLater(c.stream, emitsInOrder([...]))` — but nothing says so.)
- How do I assert an outcome? (`expect(await c.pay(o).done, isA<Done<Receipt>>())`.)
- Does `fake_async` work? (The package's own dev-dependency list includes
  `fake_async: ^1.3.1`, so presumably yes — a reader cannot know.)

**Suggested rewrite.** A "Testing" section, ~15 lines, with one `test()` that
awaits `.done` and one that asserts over `stream`.

**Вердикт (2026-09-03):** Принято: добавлен раздел Testing — ожидание задачи,
`fakeAsync`, наблюдатель-журнал со сверкой всего порядка одним `expect`.

### A5. Nothing about how errors surface (Important)

I ran a job that throws and never awaited it
(`solo_check/bin/rev_gaps.dart`). Output:

```

**Вердикт (2026-09-03):** Принято, и не только в README: изменён движок (раздел
5.10 спецификации). Необслуженный `Failed` уходит в зону создания задачи через
`handleUncaughtError`, появился `Job.ignore()`. README описывает правило в
разделе Errors.

--- Does an unawaited failing job say anything?
  (nothing above this line means the error was silent)
```

A `Failed` job is *completely silent* unless you await `.done`/`.value` or
install `onError` / a `SoloObserver` (`job.dart:189-192`). This is a deliberate
and defensible design, and it is the opposite of bloc, where an uncaught handler
error is reported to the observer **and rethrown** (`bloc.dart:228-231`), so it
surfaces as an unhandled zone error in debug.

A bloc user migrating will lose every crash report on the day they switch and
will not know why. The word "silent" does not appear in the README.

**Suggested rewrite.** In `## Concepts`, after **Outcomes** (line 836): "A job
that throws does not crash the app and does not print anything: the error
becomes `Failed` and goes to `onError` and to the observer. Install a
`SoloObserver` at startup, or you will not see failures you do not await."

### A6. The Flutter section answers the wrong question (Important)

**Lines 1005–1042.** It shows `ValueListenableBuilder`. It does not say:

- **Who creates the controller and who calls `close()`.** In bloc this is
  `BlocProvider`'s job, and it is the single most common source of leaks. There
  is no `SoloProvider`; the README should show `StatefulWidget` +
  `dispose() => camera.close()`, or say "use provider/get_it".
- **Side effects.** Item 5's entire argument is "await the job, then navigate".
  The Flutter section never shows that call site inside a widget, so the payoff
  of the strongest item is never delivered in Flutter terms. bloc's answer is
  `BlocListener`; solo's answer is "just await the method" — show it.
- `ListenableBuilder` / `AnimatedBuilder` also work (it's a `ValueListenable`);
  worth one clause.

**Вердикт (2026-09-03):** Принято: раздел Flutter говорит, кто создаёт и кто
закрывает контроллер, и показывает «дождаться и уйти» с проверкой `mounted`.
Экран проверен виджет-тестом.

### A7. No migration path from bloc (Important)

58% of the document argues against bloc and there is no table telling a
persuaded reader what to do. Minimum: `Bloc`/`Cubit` → `Solo`; `on<E>` +
`add(E())` → a method returning `Job<T>`; transformer → `Policy`; `emit.isDone`
→ `ctx.guard`/`ctx.check`; `BlocObserver` → `SoloObserver`; `BlocBuilder` →
`ValueListenableBuilder`; `bloc_test` → plain `test` + `await job.done`.

**Вердикт (2026-09-03):** Принято: добавлен раздел Coming from bloc — таблица
соответствий, соответствие трансформеров политикам и три вещи, которых нет
намеренно.

### A8. "Rules that are not visible in signatures" — good section, two soft spots

The section (862–903) is the best-written part of the README and I would not cut
a word of most of it. Two corrections:

- **Lines 871–874**, "`emit` is trusted, reads are checked. The emitted state is
  not verified against the rules of the job that emitted it — otherwise a
  `close` job declared as `run<NotClosed, void>` would cancel itself the moment
  it emitted `Closed()`." Literally true, and misleading in effect. I probed it
  (`rev_quickstart.dart`, `selfClosing`): a job that emits itself out of `W` and
  then touches the context at all dies with `Cancelled(rules: is not TOpen)`.
  The rule the reader actually needs is: *emit yourself out of `W` only as the
  last statement of the body.* (The fact is stated, obliquely, 40 lines earlier
  at 833–834 under **External state**, about a different actor.)
  **Rewrite:** add "…and the job is cancelled on its next read through the
  context, so a job that emits itself out of `W` must not touch `ctx` again."
- **Lines 893–896**, "Reads (`state`, `stateAs`, `check`, `guard`, `log`) after
  the job finished are allowed." True only for a job that finished `Done`. My
  probe (`rev_reads.dart`): after a `Cancelled` job the same read throws
  `Cancelled(manual)`. **Rewrite:** "…after the job finished normally are
  allowed; after a cancelled job they still throw its `Cancelled`."

**Вердикт (2026-09-03):** Принято: формулировка про доверие к `emit` дополнена
— задача умрёт на следующем чтении, вывести себя из `W` можно только последним
оператором тела. Уточнено, что после отменённой задачи чтения по-прежнему
бросают.

### A9. Recipes are incomplete for a real app (Important)

Present: Timeout, Debounce, Hooks, Observer. Missing, in rough order of how
often a real controller needs them:

- **Testing** (see A4).
- **Retry/backoff** — the obvious neighbour of Timeout, and `Policy.droppable`
  + `Job.done` makes it a nice five-liner.
- **Listening to a stream from inside a job** — bloc has `emit.forEach`/`onEach`
  as first-class API (`emitter.dart:28-54`). solo has no equivalent, and a BLE /
  media / chat package *must* answer "how do I hold a subscription for the life
  of a job". Nothing in the README says `ctx.run(child)` + a `StreamSubscription`
  in the controller, or anything else.
- **Two controllers talking to each other** (bloc's `BlocListener` /
  stream-subscription-in-constructor pattern).

**Вердикт (2026-09-03):** Принято частично: тесты стали отдельным разделом,
рецепт Debounce починен. Рецепты retry с отступом и «держать подписку на стрим
на время задачи» не добавлены — у второго нет очевидного ответа в текущем API.
Оба записаны в открытые вопросы `docs/handoff.md`.

### A10. Smaller Part A notes

- **Lines 5–8** define the package only in its own vocabulary ("sequential jobs
  with exclusive state ownership"). A reader who does not already use bloc
  cannot tell from lines 1–26 that this is a general state-management /
  controller package. One sentence of plain framing before "## Why" would fix it.
- **No badges, no link to the API docs, no `Contents` list** for a
  1056-line README. On pub.dev this is the landing page.
- **`Ready` names three unrelated states** (line 179 player, line 620 sensor,
  line 670 camera). Harmless, mildly confusing when scanning.
- **Line 1047**, "the controller above in full". The example's controller is a
  superset — it also has `reopen()`, `pause()`, `resume()`, `setFocusPoint()`
  and a `Broken` state
  (`/Users/user/development/my/solo/packages/solo/example/lib/src/camera_controller.dart`,
  `.../camera_state.dart:76`). "the controller above, extended" would be honest.
- **Lines 1051–1055** tell the reader `cd example && dart run bin/main.dart`
  without `dart pub get` first; `example/` is a separate package.
- `example/` has no `README.md` and its entry point is `bin/main.dart`; pub.dev's
  Example tab may come out empty. Cheap insurance: add `example/README.md`.
- **Line 3** links `README.ru.md` at the repo root — verified present
  (`/Users/user/development/my/solo/README.ru.md`), and its section structure
  matches the English one 1:1. Fine.

**Вердикт (2026-09-03):** Вердикты по этим замечаниям стоят ниже, в таблице
Minor.

---

## 3. Part B — "Where bloc falls short", item by item

Preamble (lines 30–45) first.

**Truth.** "the default transformer is concurrent" and "since bloc 7.2" —
verified verbatim in bloc's own changelog, line 148: "feat: introduce
`on<Event>` API to register event handlers / by default events are processed
concurrently". Cubit paragraph: `emit` after `close` throws `Bad state: Cannot
emit new states after calling close` — verified by probe (`rev_items.dart`,
`cubitProbe`), matching `bloc_base.dart:100`. felangel pointing at Cubit in
#1556 — verified (`gh issue view 1556 --comments`: "You can accomplish this more
easily using `Cubit` (in v6.0.0 of bloc)"). **OK.**

**Fairness.** Line 34, "None of them is a bug: they follow from bloc's design",
and line 30, "bloc fits an ordinary screen well" — this is the right register,
and it is what makes the rest readable. **OK.**

---

### Item 1 — The queue cannot be managed (lines 47–126)

**Truth about bloc — OK.** Probe `rev_items.dart::item1` runs the README's
snippet verbatim and emits, in order:
`[online:true] → [b:100] → [b:100, s:-60] → [offline]`. Both reads do emit into
the closed window before the disconnect. The premise that one funnel handler is
the only way to get one queue is right (`bloc.dart:195`, the transformer is
applied per `on<E>` subscription), and item 2's probe confirms separate handlers
overlap. There is no public API on `Bloc` to enumerate or remove pending events;
`sequential()` is `events.asyncExpand(mapper)`
(`bloc_concurrency/sequential.dart:9`) and the buffer lives inside the paused
source subscription.

Nit (Minor): line 57–58, "There is nothing to look at it with". You *can* see
events arriving (`onEvent` / `BlocObserver.onEvent`); what you cannot do is
enumerate what is still pending or remove it. "Nothing to enumerate what is
pending with, and nothing to remove a pending event with" is both true and
stronger.

**Fairness — Important finding.** The bloc snippet is what an honest bloc dev
would write *given the constraint the text imposes*, and the text does explain
why five handlers are worse. But the section states the trap as unsolvable
("nothing lets you drop them", line 56) and never mentions the fix a bloc dev
reaches for in ten seconds: a flag or generation counter checked at the top of
each case.

```dart
case ReadBattery():
  if (_disconnecting) return;      // the two lines the README does not show
```

with `_disconnecting = true` set synchronously at the call site. solo is still
better here — the flag does not complete the reads' callers, and it grows one
branch per command — but the text should say so instead of leaving a bloc reader
to think of it themselves and stop trusting the section.

**Truth about solo — OK.** `rev_solo.dart::item1`, snippet verbatim:

```
hardware trace: [connect start, connect end, rename kitchen, disconnect]
battery: Cancelled(manual)   signal: Cancelled(manual)
rename : Done(null)   disconnect: Done(null)
```

All three sentences of lines 119–126 verified: `Cancelled(manual)` with `done`
completed, the rename survives and runs, the in-flight connect finishes first.

**Pedagogy — Critical (see A1).** Six unexplained concepts in the first snippet.
Also: the `// Both reads are queued ahead of this and run first` comment (lines
76–77) is inside the `Disconnect` case, but it describes queue order, not that
case — a reader looks for what in `_ble.disconnect()` causes it.

**Persuasion — good.** A bloc reader will recognise this trap and will accept
`queue.removeWhere` as obviously nicer. They will be *slightly* annoyed that the
flag workaround goes unmentioned.

**Вердикт (2026-09-03):** Принято: пункт переписан по новой схеме. Рабочее
решение bloc — одна воронка с `sequential()` плюс флаг, выставляемый в
`onEvent`, — показано кодом, и названа его цена: правило живёт в поле блока, а
не на месте вызова, и вызывающему ничего не сообщить.

---

### Item 2 — One restartable among sequential (lines 128–202)

**Truth about bloc — OK.** Probe `rev_items.dart::item2`, three handlers,
`sequential()` on `Play`/`Pause`, `restartable()` on `Seek`:

```
trace: [play start, pause start, seek 1 start, seek 2 start,
        play end, pause end, seek 1 end, seek 2 end]
play and pause overlapped: true
```

Confirms line 136–139 exactly. "one handler has one transformer" is right
(`bloc.dart:178-195`). The escape hatch is honestly named at 140–142 ("write an
`EventTransformer` by hand … at the cost of writing it").

Understatement worth fixing (Minor): line 138, "Give `seek` its own `on<Seek>`
with `restartable()` and it does restart". Look at the trace: `seek 1 end`
arrives after `seek 2 start`. Only the *emitter* restarts; the previous
`_player.seek()` keeps talking to the one native player — which is item 4, and
which is the actual disaster in this domain. Saying "the emitter restarts; the
native call does not, see item 4" makes item 2 stronger, not weaker.

Nit (Minor): line 133, "In bloc a transformer is an argument to `on<E>`". There
is also the global `Bloc.transformer` (`bloc.dart:61`, added in 7.2). It does not
merge queues, so the argument survives, but a bloc dev will notice the omission.

**Fairness — Important finding.** There *is* an idiomatic bloc answer to the
stated requirement ("only the last position matters, the two toggles keep their
order") that needs no custom `EventTransformer`, and the README does not
acknowledge it. Probe `rev_fairness.dart::item2Fix` — one funnel handler with
`sequential()` plus a newest-seek field:

```dart
@override
void onEvent(PlayerCommand event) {
  if (event is Seek) _newestSeek = event.position;
  super.onEvent(event);
}
// …
case Seek(:final position):
  if (position != _newestSeek) return;   // stale drag step
```

Result:

```
trace: [play start, play end, seek 3 start, seek 3 end, pause start, pause end]
only the last seek hit the native player: [seek 3 start]
play/pause still in tap order, no overlap: true
```

Three lines, no custom transformer. In fairness to solo, this reproduces
`Policy.replace`, not `Policy.restart` — it drops queued seeks but cannot cancel
one already in flight, which is exactly what `Policy.restart` adds and what item
4 shows bloc cannot do at all. So the honest framing is: *bloc can get the
dropping; it cannot get the cancelling.* As written, the section claims more
than that and a bloc reader will catch it.

**Truth about solo — OK.** `rev_solo.dart::item2`, snippet verbatim:
`[play start, play end, seek 3 start, seek 3 end, pause start, pause end]`,
final `Ready(3ms)`. Lines 198–202 verified, including "the restart reaches
seeks and nothing else".

**Pedagogy — OK-ish.** `Policy.restart` is used before `Policy` exists (846).
The escalation from item 1 (queue as object) to item 2 (policy per job) is
sensible. Scenario is realistic and its "right behavior" is not disputable — no
practitioner defends queueing every step of a slider drag.

**Persuasion — good**, with the caveat above.

**Вердикт (2026-09-03):** Принято: показано решение с полем «последний seek» в
одной воронке и названо, чего оно не даёт — это `Policy.replace`, а не
`restart`: начавшийся seek доигрывает до конца и публикует промежуточное
положение.

---

### Item 3 — Handlers running in parallel write one state (lines 204–275)

**Truth about bloc — OK.** Probe `rev_items.dart::item3`, snippet verbatim, with
a server list that snapshots at call time:

```
final state: NotesState([n0], uploading: false)
note n1 lost: true
```

The interleaving loses the note, exactly as lines 210–214 claim, with fresh
`state` reads after every await. This is the cleanest demonstration in the
section.

**Fairness — Important finding.** A bloc reader's first reaction is "so give
them a transformer", and the section never answers it. I tested both readings:

- `sequential()` on **each** handler separately does **not** fix it
  (`rev_items.dart::item3`, second half: `note n1 kept: false`) — two handlers
  are two queues, which is item 2.
- One `on<NotesEvent>` funnel with `sequential()` **does** fix it
  (`rev_fairness.dart::item3Fix`: `NotesState([n0, n1], uploading: false)`,
  `note n1 kept: true`), as does the global `Bloc.transformer = sequential()`.

So the honest statement is: *the cure exists and it is item 1's funnel shape,
which then costs you item 1 and item 2.* That is a much better argument than
leaving the cure unmentioned, because a bloc reader who thinks of it on their own
concludes the section is loading the dice. Two sentences fix this.

**Truth about solo — OK.** `rev_solo.dart::item3`, snippet verbatim:
`NotesState([n0, n1], uploading: false)`. "Runs before upload or after it, never
across it" verified. Lines 271–275 (the two deliberate ways in) match
`solo_base.dart:287-301` and `_reevaluate`.

**Pedagogy — OK.** Uses only API from items 1–2 plus `ctx.state`. The escalation
(queue → policy → ownership) is right, and this is the item where the package's
actual thesis lands.

**Persuasion — strong**, once the missing acknowledgement is added.

**Вердикт (2026-09-03):** Принято: сказано, что одна воронка с `sequential()`
лечит гонку, и что это форма пункта 1 ценой пунктов 1 и 2.

---

### Item 4 — After cancellation the handler keeps running (lines 277–342)

**Truth about bloc — OK, and the quote is exact.** `gh issue view 3349` returns
felangel's comment word for word:

> This is because Futures aren't truly cancelable. To get the behavior you're
> describing you can simply check if `emit.isDone` is true before performing any
> expensive computations:

matching lines 286–288 exactly, including the trailing colon. Probe
`rev_items.dart::item4`, the README snippet with and without the guard line:

```
guarded=false  chunks actually written to the device: [0, 1, 100, 2, 101, 3, 102, 4, 103, 5, 104, 105]
guarded=true   chunks actually written to the device: [0, 1, 100, 101, 102, 103, 104, 105]
```

Without the `emit.isDone` line the cancelled flash writes all six of its chunks
to the device, interleaved with the restart's. Exactly the claim.

The `#2961` reference is right too: the issue's title and body carry the
assertion text `emit was called after an event handler completed normally`
(`emitter.dart:118`).

**Fairness — OK.** No idiomatic bloc one-liner disproves this; `emit.isDone`
after every await *is* the answer and the README says so. The maintainer's own
words carry the item. This is the strongest bloc-side item in the section.

**Truth about solo — Critical finding: the snippet can only ever flash once.**

Lines 322–335:

```dart
Job<void> flash(List<Chunk> chunks) => run<NotBroken, void>(
      key: 'flash',
      policy: Policy.restart,
      canStart: (state) => state is Idle,
      (ctx) async {
        for (final chunk in chunks) {
          await ctx.guard(() => _ble.write(chunk));
          ctx.emit(Flashing(chunk.index));
        }
      },
    );
```

`Policy.restart` and `canStart: (state) => state is Idle` contradict each other.
After the first chunk the state is `Flashing(0)`; nothing in the controller ever
returns it to `Idle`; so `_pump` rejects the restarting job at
`job.dart:146-155` / `solo_base.dart:460-470`. Probe
`rev_solo.dart::item4`, snippet verbatim:

```
written: [0, 1]
first outcome: Cancelled(manual)   second: Cancelled(rules: canStart)
```

The old flash stops — that part is true and is what the prose at 339–342 claims.
But the **new** flash never starts, and no prose says so. The reader's whole
reason for `Policy.restart` is that the restart runs; the bloc counterpart's
`restartable()` genuinely does run the new handler (see the trace above). So the
two sides of the comparison are not equivalent, and the solo side is strictly
worse at the advertised behaviour. Copy this controller into an app and
`flash()` works exactly once in the controller's lifetime.

Fix: drop `canStart` (the `W = NotBroken` bound already carries the
precondition), or make the body return to `Idle` on exit, or drop
`Policy.restart` and say so.

Verified as claimed: "guard returns the moment the job is cancelled, so the next
write never starts" — after `externalSetState(Broken)` at t≈40ms, `written =
[0, 1, 2]` and the outcome is `Cancelled(rules: is not NotBroken)`; index 2 was
already in flight, and no further write begins. Correct and precisely worded.

**Pedagogy.** Introduces `canStart` (explained at 811) and `Policy.restart`
(846). The domain is realistic and the "right behavior" is not disputable — a
cancelled firmware flash must stop writing.

**Persuasion — the bloc half is devastating; the solo half undercuts it.** A
reader who tries the snippet finds the restart silently dropped.

**Вердикт (2026-09-03):** Принято, исправлено: `canStart` убран, перезапуск
действительно работает (проба: первая прошивка `Cancelled(manual)`, вторая
`Done`). Решение bloc через `emit.isDone` показано как рабочее; разница теперь
в охвате — `guard` видит и смену состояния — и в том, что исход доходит до
вызывающего.

---

### Item 5 — You cannot await your own event (lines 344–427)

**Truth about bloc — OK, quote exact.** `gh issue view 1556` gives felangel's

> …it would be confusing because a single add can result in multiple state
> changes so you would never know when the event was actually "done" being
> processed.

matching lines 352–353 with an honest leading ellipsis. `add` returning `void`
follows the `Sink` API (`bloc.dart:16, 82`). Line 425–427's "Later in the same
thread felangel points at `Cubit`" is verified.

**Fairness — OK, and understated.** I ran the README's screen snippet verbatim
(`rev_fairness.dart::item5`). It works for the happy path, and the *drop* case
is worse than the README says: with `droppable()`, a second press produces no
state at all, so `firstWhere` latches onto the **first** payment's `Paid` and
navigates:

```
navigated with Receipt
navigated with Receipt
navigated with Receipt
```

Three navigations for two payments. The README's "a retry from another screen
produces the same Paid" is if anything too mild. No strawman here.

**Truth about solo — Important finding.** The solo snippet reproduces the same
confusion for the same reason. `key: 'pay'` is a constant, so `Policy.droppable`
deduplicates on the key, not on the order. Probe `rev_gaps.dart`:

```
same handle for A and B? true
B caller receives: Done(receipt for Order(A))
```

`pay(orderB)` returns `Done` carrying **orderA's receipt**, and the screen
navigates to a receipt for an order it never paid — the exact failure the item
accuses bloc of, now with a type-checked `Done<Receipt>` giving false
confidence. Line 422–424, "`done` carries the outcome of this call … Neither has
to guess whose state change it is looking at", is not true of this snippet.

Also (same probe): `canStart: (state) => state is Cart` plus a body that emits
`Paid` makes `pay()` one-shot — a retry returns `Cancelled(rules: canStart)`.
Defensible for a screen that is disposed after checkout, but it is the same
pattern as item 4's defect and deserves a word.

Fix: key the job by the order (`key: ('pay', order.id)`), or say plainly that
`droppable` dedupes by key and a key must identify the *request*, not the method.

**Pedagogy — good.** This is where `Outcome` earns its keep and the exhaustive
`switch` reads beautifully. `Done`/`Cancelled`/`Failed` are used 400 lines before
they are defined (836), but the snippet is self-evident.

**Persuasion — strongest item in the section for a bloc reader**, provided the
key hazard is fixed or acknowledged.

**Вердикт (2026-09-03):** Принято, исправлено: ключ стал `('pay', order.id)`,
`canStart` убран как делавший `pay()` одноразовым. Решение bloc — `Completer`
на событии плюс метод `pay()` с картой заказов — показано целиком, с ценой.

---

### Item 6 — A method, not an event (lines 429–497)

**Truth about bloc — OK.** Three event classes, three registrations, an `add`
call site. Accurate and unremarkable. Line 434–436 concedes `Cubit` answers it —
"which is another way of saying the ceremony belongs to events, not to the
package" is a fair and self-aware sentence.

**Fairness — OK, Cubit is treated fairly here and in the preamble.**

**Truth about solo — OK.** `run<MapState, void>((ctx) => ctx.guard(…))` compiles
and runs; line 495–497's claim that a `Job<void>` raises no `unawaited_futures`
lint is verified — `solo_check/analysis_options.yaml` enables
`unawaited_futures: true`, and `camera.setZoom(2);` inside an `async` function in
`rev_quickstart.dart` produces no lint.

**Pedagogy — Important finding.** The solo `MapController` (475–489) uses no
`key` and no `policy`, so `onMapDrag` queues one sequential job per drag frame —
about 60 a second, each awaiting the previous. That is the trap item 2 just spent
70 lines teaching the reader to avoid, and here it is in the "good" column, two
items later. Either add `key: MapKey.moveTo, policy: Policy.replace` or say why
it is fine here.

**Persuasion — weakest item, and it is fine that it is.** Cubit already answers
it, the README says so, and it costs 70 lines to make a point about ceremony.
This is the first item I would cut for length.

**Вердикт (2026-09-03):** Принято частично: пункт переделан — `MapController`
получил ключ и `Policy.restart`, решением на bloc назван `Cubit`, и названа его
цена: вместе с церемонией уходит очередь. Вырезать пункт целиком владелец решит
отдельно, пока он оставлен.

---

### Item 7 — Closing while work is in flight (lines 499–568)

**Truth about bloc — OK, and this is the claim I most expected to break.**
Reading `bloc.dart:313-321` I initially concluded the README was wrong, because
`close()` cancels *every* emitter unconditionally before waiting. Running it
proves the README right — the `sequential()` subscription is paused inside
`asyncExpand`'s `addStream`, so `await _eventController.close()` (line 314) does
not return until the handler finishes, and the late `emit` lands before any
emitter is cancelled. Probe `rev_item7_close.dart`:

```

**Вердикт (2026-09-03):** Принято: акцент смещён. «`close` дожидается тела»
названо слабой стороной прямо в тексте; пункт держится на том, что поздний
`emit` отвергается броском, а не `assert`, и что `send` после закрытия
возвращает завершённую задачу вместо исключения.

--- sequential()
  close() took 54ms (body needs ~50ms more)
  emit.isDone at resume?      false
  state right after close:    St(1)
  stream listener saw:        [St(1)]
  add() after close threw:    Bad state: Cannot add new events after calling close

--- default (concurrent) / concurrent() / droppable() / restartable()
  close() took 0-1ms
  emit.isDone at resume?      true
  state right after close:    St(0)
  stream listener saw:        []
  add() after close threw:    Bad state: Cannot add new events after calling close
  body finished?              true
```

Every clause of lines 504–514 is exactly right, including the error string
verbatim and "Either way the body keeps running". Nicely done.

**Citations — Minor.** #52 and #120 are from the `mapEventToState`/rxdart era and
their stack traces show the error coming from the *state* subject, not from
`add`. #120's description is the README's scenario word for word ("I dispose the
bloc when the page is popped… before the fetching finished"), so the citation is
apt in spirit; a reader who opens them will notice they predate `on<Event>` by
several major versions. Consider a date or a "historically" qualifier. #3069 is
verified OPEN and authored by felangel, exactly as described.

**Fairness — OK.** `if (isClosed) return;` after every await is genuinely the
usual workaround; felangel proposes the same in #3069's "Alternatives
Considered".

**Truth about solo — OK, with a nuance the prose skips.**
`rev_solo.dart::item7`, snippet verbatim:

```
close() took 0ms (body needs ~50ms more)
running send outcome: Cancelled(closed)
queued send outcome:  Cancelled(closed)
state after close:    ChatState(null)
add after close:      Cancelled(closed)
```

All of lines 565–568 verified. The nuance: `close()` returned in 0ms only
because the body uses `ctx.guard`. With a bare `await` — which is what a reader
who has not reached line 817 will write — `rev_close_bare.dart` gives:

```
close() with a bare await in the body: 52ms (body needed ~50ms more)
outcome: Cancelled(closed)   state: ChatState(null)
```

i.e. the same wait as bloc's `sequential()`. solo is still better (the stale
`emit` cannot land, and `state` stays clean), but the advantage is *the emit is
refused*, not *the close is fast*. The prose at 558–560 and 565 emphasises the
waiting, which is the half bloc already does.

**Pedagogy — OK.** Self-contained; the `onScreenClosed` function is the clearest
call site in the section.

**Persuasion — very strong.** The transformer-dependent behaviour is a genuine
"I did not know that" for most bloc users, and it is verifiable in ten lines.

---

### Item 8 — The state changes from outside (lines 570–635)

**Truth about bloc — OK.** The `@visibleForTesting` quote is verbatim from
`bloc.dart:130-131` ("**[emit] is only for internal use and should never be
called directly outside of tests…"). Probe `rev_items.dart::item8`, the README's
snippet with and without the repeated guards:

```
guarded=false  states: [Broken(cable unplugged), Calibrated]  final: Calibrated
guarded=true   states: [Broken(cable unplugged)]              final: Broken(...)
```

Without the guards the calibration overwrites `Broken` with `Calibrated` — a
sensor screen that reports "calibrated" on unplugged hardware. Exactly the claim
at 577–579.

Minor honesty point, in the README's favour and unstated: even *with* the guards
the probe shows `sampled: 1`, because the `_hw.sample()` call was already in
flight when the failure arrived. Neither library can abort it; worth one clause
so the comparison stays symmetric (solo's `ctx.guard(_hw.sample)` has the same
property, and my solo probe likewise shows `sampled=1`).

Minor: in the snippet, `emit.isDone` (lines 594, 596) can never be true under
`sequential()` before `close()`, so those two conjuncts are dead weight that
makes the bloc code look noisier than it needs to be. Dropping them costs the
item nothing and removes the only place a bloc reader could cry strawman.

**Fairness — OK.** `add(HardwareFailed(...))` really is the supported route, and
a bloc dev would write it this way.

**Truth about solo — OK, fully verified.** `rev_solo.dart::item8`, snippet
verbatim:

```
outcome: Cancelled(rules: is not SReady)
final state: Broken(cable unplugged)
zeroed=1 sampled=1
```

Lines 631–635 match `solo_base.dart:287-346` precisely: `externalSetState` →
`_setState` → `_reevaluate(except: null)` → `_cancel(..., CancelReason.rules)`.

**Pedagogy — excellent, and the right place to finish.** This is the item where
"the precondition is the signature" finally pays off, and it uses only API the
reader has now seen four times. Escalation across items 1→8 is genuinely
well-judged: queue → policy → ownership → cancellation → handles → ergonomics →
lifecycle → external truth. Items 6 and 7 are the two that break the ramp (6 is
a step down in difficulty, 7 is a step up in bloc arcana).

**Persuasion — strong close.**

**Вердикт (2026-09-03):** Принято: мёртвые `emit.isDone` убраны, ссылки #52 и
#120 помечены как эпоха `mapEventToState`, и названо противоречие — лекарство
пункта 3 (одна воронка) ломает раздельный обработчик поломки.

---

## 4. Consolidated findings

### Critical

| # | Where | Finding |
|---|---|---|
| C1 | 322–335 | Item 4's solo snippet can only ever flash once: `Policy.restart` + `canStart: (state) => state is Idle` are contradictory, and the restarting job is dropped with `Cancelled(rules: canStart)` (probe `rev_solo.dart::item4`). The bloc counterpart genuinely restarts, so the comparison is not like-for-like. |
| C2 | 941 | The Debounce recipe does not compile: `api` is undefined. `dart analyze` on the snippet exactly as printed: `error - Undefined name 'api'` (`solo_check/bin/rev_debounce_exact.dart`). The snippet is presented as a complete class, so a reader will copy it. |
| C3 | 28–635 vs 636–1056 | 58% of the README argues against bloc using API that is not introduced for another 600 lines (§A1). For a package README this is the single biggest obstacle to a first-time reader. |

**Вердикт (2026-09-03):** Вердикты: C1 принята и исправлена (`canStart` убран
из пункта 4). C2 принята и исправлена (рецепт Debounce получил объявление
зависимости и компилируется). C3 принята и решена сильнее предложенного: раздел
вынесен в отдельный документ.

### Important

| # | Where | Finding |
|---|---|---|
| I1 | 394–404, 422–424 | Item 5's constant `key: 'pay'` with `Policy.droppable` returns order A's receipt to the caller who paid for order B (`Done(receipt for Order(A))`, probe `rev_gaps.dart`), reproducing the confusion the item accuses bloc of. |
| I2 | 206–214 | Item 3 never acknowledges that one `on<NotesEvent>` funnel with `sequential()` cures the interleaving (verified, `rev_fairness.dart::item3Fix`). Say that the cure is item 1's shape and costs items 1 and 2. |
| I3 | 130–142 | Item 2 never acknowledges the three-line newest-seek guard inside one funnel, which delivers the stated requirement without a custom `EventTransformer` (verified, `rev_fairness.dart::item2Fix`). What bloc still cannot do is cancel the in-flight seek — say that instead. |
| I4 | 56 | Item 1 never acknowledges the flag/generation-counter workaround a bloc dev reaches for. |
| I5 | 12, 25–26, 45 | "six complaints" vs eight items; item 7 is referenced as if it were on the list. |
| I6 | 648–786 | The Quick start is 138 lines, opens with the most advanced code in the document (`dispose()`), never reads `state` or `stream`, and never explains `dispose()` vs `close()` or the unexplained `queue.clear()` at line 725. |
| I7 | — | No testing section (§A4). |
| I8 | — | No statement that a `Failed` job is silent unless awaited or observed (§A5; probe `rev_gaps.dart`). |
| I9 | 1005–1042 | The Flutter section never says who creates and closes the controller, and never shows the await-then-navigate call site that item 5 promised. |
| I10 | — | No migration table for a persuaded bloc user (§A7). |
| I11 | 871–874 | "`emit` is trusted" invites the wrong conclusion; the job dies on its next read (probe `rev_quickstart.dart::rules`). |
| I12 | 475–489 | Item 6's `MapController` queues one job per drag frame — the trap item 2 just taught the reader to avoid. |
| I13 | 558–560, 565 | Item 7's prose sells "close waits for the body", which bloc's `sequential()` already does; solo's real advantage is that the stale `emit` is refused. With a bare `await` solo's `close()` waits just as long (52ms, `rev_close_bare.dart`). |
| I14 | 905–1003 | Recipes omit testing, retry, and "hold a stream subscription for the life of a job" — the last is first-class in bloc (`emit.onEach`/`forEach`) and has no answer here. |

**Вердикт (2026-09-03):** Вердикты: I1-I13 приняты и закрыты правками этой
волны. I14 принята частично — тесты стали отдельным разделом, рецепты retry и
подписки на стрим на время задачи отложены и записаны в открытые вопросы.

### Minor

| # | Where | Finding |
|---|---|---|
| M1 | 138 | "it does restart" — only the emitter does; the native call keeps running (that's item 4). |
| M2 | 133 | "a transformer is an argument to `on<E>`" — there is also the global `Bloc.transformer`. |
| M3 | 57–58 | "nothing to look at it with" — you can observe events arriving, just not enumerate what is pending. |
| M4 | 510–511 | #52 / #120 predate `on<Event>`; their stack traces show the state subject, not `add`. Add a "historically" qualifier. |
| M5 | 594, 596 | `emit.isDone` in item 8's snippet is unreachable under `sequential()` before `close()`; it makes the bloc code look noisier than necessary. |
| M6 | 76–77 | The "Both reads are queued ahead of this" comment sits in the wrong `case`. |
| M7 | 893–896 | "Reads after the job finished are allowed" — only after a `Done` job; a cancelled job's reads still throw. |
| M8 | 712, 940 | `describe:` is used twice and explained nowhere. |
| M9 | 179 / 620 / 670 | Three unrelated `Ready` classes. |
| M10 | 1047 | "the controller above in full" — the example's controller is a superset with an extra `Broken` state. |
| M11 | 1051–1055 | `cd example && dart run` without `dart pub get`; `example/` has no `README.md`, so pub.dev's Example tab may be empty. |
| M12 | 890–891 | The `ArgumentError` this line advertises prints as `Invalid argument (policy): requires a job key: Instance of 'Policy'` — `Error.safeToString` bypasses the enum's `toString`. Passing `policy.name` would make the message readable. (Package nit, not a README error.) |
| M13 | 5–8 | Nothing tells a non-bloc reader what kind of package this is before the polemic starts. |
| M14 | — | No badges, no API-docs link, no table of contents on a 1056-line README. |

**Вердикт (2026-09-03):** Вердикты: M1-M6 закрыты переписанным документом про
bloc. M7, M8, M10, M11 закрыты правками README (плюс у примера появился свой
`README.md` с `dart pub get`). M9 снята: одноимённые классы разъехались по
разным документам. M12 исправлена в движке — сообщение теперь `Policy.restart
requires a job key`. M13 принята: первая строка README называет предмет пакета.
M14 отклонена: бейджи и оглавление не добавляются, ссылка на API-доки есть на
pub.dev.

---

## 5. What I would add and what I would cut

**Add (in priority order).**

1. A 20-line real Quick start: one state, two jobs, `await job.done`, and
   `controller.stream.listen`. Before anything about bloc.
2. A **Testing** section — the single largest gap for anyone leaving `bloc_test`.
3. Two sentences on error visibility: a `Failed` job is silent; install a
   `SoloObserver`.
4. Flutter lifecycle: who constructs the controller, who calls `close()`, and
   the await-then-navigate call site inside a widget.
5. A bloc→solo mapping table (10 rows).
6. One paragraph on holding a stream subscription for the life of a job.
7. In each of items 1, 2 and 3, one sentence naming the idiomatic bloc
   workaround and what it costs. This *strengthens* the section — right now a
   bloc reader supplies the workaround themselves and quietly discounts the
   whole comparison.

**Cut / move.**

1. Move "Where bloc falls short" behind Quick start + Concepts, or out to
   `doc/vs-bloc.md` with three items left inline (3, 4, 8 — the ones bloc really
   cannot answer). It is a superb document; it is not a README's first 600 lines.
2. Cut item 6 (70 lines) — the README itself concedes Cubit answers it.
3. Cut `queue.clear()` from `takePhoto` (line 725) or explain it.
4. Cut `emit.isDone` from item 8's bloc snippet (dead under `sequential()`).
5. Trim the Quick start's `dispose()` into a later "Teardown" subsection.

**Вердикт (2026-09-03):** Из списка взято всё, кроме двух рецептов (retry,
подписка на стрим) и предложения вырезать пункт 6: рецепты отложены, судьба
пункта 6 за владельцем. Вынос раздела сделан целиком, без трёх пунктов,
оставленных в README.

---

## 6. Publish as is?

**With fixes.**

Blocking (must not ship): **C2** (the Debounce recipe does not compile) and
**C1** (item 4's controller can flash exactly once). Both are copy-paste
material and both are cheap to fix — C2 is one line, C1 is deleting a `canStart`.
I would also fix **I1** before publishing, because a checkout example that hands
a caller someone else's receipt is the kind of thing that ends up in a bug
report against the package.

Not blocking for 1.0.0 but I would not wait long: the structural inversion
(**C3**) and the three missing day-one sections — testing, error visibility,
Flutter ownership. A reader can adopt this package without them, but they will
be back with questions the README should have answered.

Everything else is polish. The engineering underneath is clearly sound — I
probed a dozen behavioural claims against `lib/src/` and the engine did what the
prose said every time except in the two snippets above — and the bloc comparison
is more careful with its sources than most published criticism of any framework.
Fix the two snippets, add the three missing sections, and this is a very good
README with an unusually good essay attached to it.


**Вердикт (2026-09-03):** Обе блокирующие находки закрыты, публикация не
запускалась: разрешение на неё приходит отдельным запросом владельца.
