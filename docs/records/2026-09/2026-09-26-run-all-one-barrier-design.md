# `runAll`: ветка держится на одном барьере

> **Состояние на 2026-09-26:** дизайн, ждёт независимого ревью; кода нет.
> **Что это:** правка H1 из `2026-09-26-async-job-project-review.md`
> по варианту (а): ветка `runAll` выполняет безусловную уборку сразу после тела
> и встаёт только на барьер между двумя проходами уборки. Заодно L15 (группа
> уезжает в свою часть `run_all.dart`) и L17 (ветка, ждущая соседа).
> **Связанные записи:** `2026-09-26-async-job-project-review.md`,
> `2026-09-14[10]-eager-parallel-run-design.md`.

## Зачем

H1: ветка встаёт на первый барьер сразу после конца тела и детей, раньше
первого прохода уборки, и стоит там, пока не кончатся тела всех соседей. Замок,
взятый через `ctx.join(Lock.acquire, dispose: (l) => l.release())`, как учит
`cleanup.md`, остаётся занятым; сосед, который ждёт этот замок, не кончит тело
никогда. Взаимная блокировка без таймеров и без диагностики, а при `join`
не помогает и `parent.cancel()`.

Решение владельца 2026-09-26 — вариант (а): безусловная уборка ветки до барьера
группы, условная после приговора.

## Зачем был первый барьер

Дизайн `2026-09-14[10]-eager-parallel-run-design.md` называет его так: «Группа
собирает здесь все ветки и решает предварительно: есть отказ или чужая отмена —
фиксирует неуспех, нет — пускает всех в уборку». На деле он даёт одно: если
сосед упал после того, как тело ветки вернуло значение, но до того, как группа
отпустила первый барьер, ветку отменяют раньше, чем она тронула стек, и она
разматывается как отменённая задача — весь стек, строго от последней
регистрации к первой, `discard` на своём месте.

Закрытие ресурса на неуспехе держит не он. Это установил четвёртый круг того
дизайна: с одним первым барьером окно не закрывается, а передвигается, и его
закрыл второй барьер, между проходами. Отложенное доигрывается после приговора
тем же механизмом, которым ядро доигрывает отмену, пришедшую в саму уборку.

Эксперимент: копия пакета на `7823123`, из `_execute` убран первый барьер,
из `_RunAllGroup._settle` — первый цикл ожидания и отпускание первого барьера
(`.artifacts/2026-09-26-run-all-one-barrier/experiment.diff`: в `lib` 23 строки
удалены, одна поправлена). Из 628 тестов `async_job` краснеет одно
утверждение — состояние на удержании «уборка не начиналась»
(`run_all_test.dart:1499`, критерий 20 того дизайна). С ним, поправленным
на «безусловная уборка прошла», зелёные все
628. `solo` на этой копии ядра (оверрайд на неё) — 803 из 803. Порядок уборки
     ветки на пути отказа не держит ни один тест.

## Зонд

`.artifacts/2026-09-26-run-all-one-barrier/h1_probe_test.dart`, `fakeAsync`,
на нетронутой копии и на эксперименте; вывод — `probe-orig.txt`
и `probe-new.txt` там же. Пул на `n` слотов и `n + 1` ветка; слот ветка берёт
через `join` с `dispose`, через `wait` с `dispose` или через `wait`
и `onDispose`, потом ждёт 10 мс и возвращает значение.

Было:

```text
H1 join n=1: parent=null values=null log=[b0 holds, b1 waits]
H1 join n=1 after cancel: parent=null cancel returned=false
H1 wait n=1: parent=null values=null log=[b0 holds, b1 waits]
H1 wait n=1 after cancel: parent=Cancelled(manual) cancel returned=true
H1 onDispose n=2: parent=null values=null log=[b0 holds, b1 holds, b2 waits]
H1 onDispose n=2 after cancel: parent=Cancelled(manual) cancel returned=true
```

Стало, все шесть сочетаний:

```text
H1 join n=1: parent=Done(null) values=[0, 1] log=[b0 holds, b1 waits, b0 releases, b1 holds, b1 releases]
H1 join n=2: parent=Done(null) values=[0, 1, 2] log=[b0 holds, b1 holds, b2 waits, b0 releases, b2 holds, b1 releases, b2 releases]
```

Остальные четыре строки те же по форме.

## Что станет

### Ядро

В `_execute` убирается блок первого барьера: `await hold.beforeDisposal()`
и проверка `isFinished` за ним. Больше ничего не двигается:
`_disposing = true`, первый проход, барьер `beforeOutcome`, проверка
`isFinished` с `_traceDroppedCleanups`, перечитывание стека, проход
отложенного, `finish`. Движок домена, закончивший ветку по руке во время
первого прохода или на барьере, ловится проверкой после барьера, как и сейчас;
этот путь держит `debug_test.dart:273`.

Путь ветки после правки:

1. тело, ранний сигнал группе, ожидание детей — как сейчас;
2. первый проход сразу: безусловная регистрация выполняется, условная
   выполняется, если исход, как он стоит, не `Done`, иначе откладывается;
3. барьер: группа ждёт здесь все ветки и дальше либо фиксирует успех одним
   синхронным шагом (шаги 1–5 из `2026-09-14[10]-eager-parallel-run-design.md`,
   без изменений), либо останавливает всех, кроме источника, и отпускает
   с вердиктом «неуспех»;
4. после барьера: перечитывание стека, отложенное выполняется, если значение
   не зафиксировано, `finish`.

Комментарии ядра: «The second barrier» становится «The barrier»; у первого
прохода — абзац о том, что у ветки он идёт до решения группы, и почему это
верно для безусловных регистраций.

### Группа

- `_GroupHold.beforeDisposal` удаляется; `bodyEnded` и `beforeOutcome`
  остаются.
- `_GroupBranch`: `pastFirstBarrier` и `atFirstBarrier` удаляются,
  `pastSecondBarrier` и `atSecondBarrier` становятся `pastBarrier`
  и `atBarrier`.
- `_letPastFirstBarrier`, `_parkBeforeDisposal`
  и `_everyBranchIsAtFirstBarrier` удаляются, `_letPastSecondBarrier`
  и `_everyBranchIsAtSecondBarrier` переименовываются тем же образом.
- `_settle`: один цикл ожидания вместо двух.
- `_beginFailing` отпускает один барьер.
- Dartdoc `_RunAllGroup`, `_GroupHold` и поля `_hold`: «two barriers», «its
  barriers» — один барьер между двумя проходами уборки.

### Что это даёт

Безусловная уборка ветки идёт тогда же, когда у того же тела под
`[ctx.run(a), ctx.run(b)].wait`: в конце тела. Ловушка H1 уходит для всего, что
ветка держит для себя: замок, слот пула, временный файл, подписка.

Правила уборки ветки становятся правилами любой задачи с одним исключением.
Абзац `cleanup.md` «Cancellation after the body returns» описывает и ветку:
отмена, пришедшая после тела, закрывает `discard` вторым проходом. Исключение —
фиксация: `discard` зафиксированного значения не выполняется никогда.

Движущихся частей меньше: один барьер, один цикл ожидания, одно отпускание.

### Цена: порядок на пути отказа

Было и стало, та же ветка: `onDispose` снизу, `discard` сверху, тело вернуло
значение, сосед упал позже:

```text
было:  [a: body returns, b: throws, a: resource closed (discard), a: lock released (dispose), parent caught Bad state: b]
стало: [a: body returns, a: lock released (dispose), b: throws, a: resource closed (discard), parent caught Bad state: b]
```

Строгий обратный порядок теряется только в этом сочетании: безусловная
регистрация лежит под условной, и сосед упал после того, как тело ветки вернуло
значение. Упал раньше — ветку отменяют в теле, и она разматывается, как сейчас.
`discard` снизу и `dispose` сверху дают один порядок до и после.

Почему цена приемлема:

- ресурс, который ветка отдаёт, не может рассчитывать на ресурс, который она
  держит для себя: на успехе вызывающий получает его, когда тот уже закрыт.
  `discard`, которому нужен живой `dispose`-ресурс, сломан на успешном пути
  и без этой правки;
- тот же порядок `cleanup.md` описывает для любой задачи, которую отменили
  после тела: отложенный `discard` идёт вторым проходом, после колбэков,
  зарегистрированных раньше него (формулировку страницы поправляет M15);
- обещание, ради которого группа ждёт ветки на неуспехе, остаётся: всё, что
  ветки взяли, закрыто до того, как ошибка дойдёт до родителя — в зонде
  `resource closed` стоит раньше `parent caught`.

### Что не меняется

- Фиксация синхронна, вердикт переопределяет только в сторону успеха, стек
  перечитывается после барьера, фаза на барьере одна у ветки с уборщиками и без
  них (`isDisposing` истинно, `check()` бросает `StateError`) — критерии 21
  и 22 дизайна `runAll`, их тесты не трогаются.
- Ранний сигнал, отказ приёма, вложенные группы, ветка `cancellable: false`.
- L17. Ветка, которая ждёт значение соседа, висит по-прежнему: сосед стоит
  на барьере до решения группы, а группа решает, когда на барьере все. Зонд,
  одинаково на обоих ядрах:

  ```text L17 bare after cancel: parent=null cancel returned=false a=null
  b=null L17 ctx.wait after cancel: parent=Cancelled(manual) cancel
  returned=true a=Cancelled(parent) b=Cancelled(parent) ```

  Голый `await b.value` не развязывает и отмена родителя. Через `ctx.wait`
  отмена развязывает: `wait` бросает `Cancelled`, тело ветки кончается,
  и ранний сигнал останавливает группу.
- По тому же правилу висят и остальные зависимости между ветками: уборка ветки,
  которая ждёт соседа (`b.onDispose` ждёт `a.value`, находка
  `2026-09-14[31]-eager-parallel-run-review-10.md`), и сосед, который ждёт
  ресурс, отданный через `discard`: этот ресурс по построению принадлежит
  вызывающему, и `.wait` висит на нём так же. Всё это — «a branch must not wait
  for another branch», и правка этого не обещает.

## Документы

Английский — источник, перевод в том же коммите, изменённые абзацы перевода
через `humanizer-ru` до коммита (правило `~/.claude/CLAUDE.md`).

- `lib/src/job_context.dart`, dartdoc `runAll`. Абзац «No branch ends before
  the group has decided» становится таким:

  ```text /// **No branch ends before the group has decided.** A branch stands
  /// once, between the two passes of its unwinding. What it registered to ///
  run whatever the outcome — the `dispose` of [wait] and [join],
  /// [onDispose] — has run by then,
  as it would have for a child under /// `.wait`: a lock or a pool slot one
  branch keeps for itself is free /// for its siblings while the group decides.
  What it registered through ///
  `discard` waits: it stays alive until the group is sure the caller /// will get it,
  and the branch closes it itself when the caller will /// not. While a branch
  is held, its outcome is not final: a body that /// returned a value may still
  end [Cancelled]. ```

  В абзаце «A branch must not wait for another branch» после «Nothing here
  catches that» — L17: «and cancelling the parent unties it only where the
  waiting branch waits through [wait]».
- `doc/children.md`, раздел «What a group hands back». Фраза «A resource a
  branch keeps for itself goes to `onDispose`, and the end of the branch closes
  it whatever the outcome» становится «…and the branch closes it as soon as its
  body is over, whatever the outcome: a lock or a pool slot is free for the
  siblings while the group waits for them». После фразы о неуспехе группы —
  правило из раздела «Цена»: что ветка держала для себя, к этому моменту уже
  закрыто, поэтому отдаваемый ресурс не должен нуждаться в удерживаемом —
  на успехе вызывающий и так получает его после закрытия того.
- `doc/children.md`, «Four things `runAll` does not promise», пункт «A branch
  must not wait for another branch» — та же фраза L17, что в dartdoc.
- `doc/cleanup.md`, абзац «A branch of `ctx.runAll` is the one exception»:
  безусловные колбэки ветки не держатся, они идут в конце тела, как у любой
  задачи; группу ждёт только `discard`.
- Переводы: `docs/ru/async_job/children.md`, `docs/ru/async_job/cleanup.md`.
- `docs/architecture.md:326`: «держит каждую ветку на двух барьерах» — на одном
  барьере между двумя проходами уборки; плюс строка о `run_all.dart` из L15.
- `CHANGELOG.md:136`: «at the second barrier» — «at the barrier». Новой строки
  нет: `runAll` не выпущен, и раздел `## Unreleased` описывает его
  окончательное поведение; сам раздел потом переписывает M20.

## Сторожа

В `test/run_all_test.dart`, под `fakeAsync`, без реального времени.

1. **Общий замок.** Однослотовый замок, две ветки берут его через `join`
   с `dispose`, через `wait` с `dispose` и через `wait` с `onDispose`. Группа
   кончается `Done` со значениями по порядку списка, журнал замка
   `[a holds, b waits, a releases, b holds, b releases]`. И пул на два слота
   с тремя ветками через `join`: блокировка H1 не только про один слот.
2. **Отмена родителя в том же сценарии.** `b` взял замок и ждёт в теле; `a`
   кончила тело. `parent.cancel()` возвращается, обе ветки `Cancelled`, журнал
   замка сбалансирован. На старом ядре к этому моменту `a` стоит на первом
   барьере с замком, `b` ждёт в `join`, и `cancel()` не возвращается.
3. **Порядок на пути отказа.** Сценарий из раздела «Цена», журнал — строка
   «стало» оттуда. Держит три вещи: безусловная уборка прошла до решения
   группы, `discard` после провала соседа, и до того, как родитель поймал
   ошибку.
4. **Критерий 20**
   (`a branch is held before it unwinds, and let go on every path`): имя — «a
   branch is held between the two passes of its unwinding»; на удержании
   `disposed == 1`, `discarded == 0`, ветка не кончена. Варианты второй
   половины `first` и `second` называются по тому, что они делают: движок
   домена не может остановиться (`engine`) и правила родителя бросают
   на фиксации (`rules`) — барьер у обоих теперь один.
5. **Имена и комментарии.**
   `the second barrier catches what the first one would have missed` — «the
   barrier catches a cancellation that arrives into the unwinding»;
   `debug_test.dart:273` «at the second barrier» — «at the barrier»;
   комментарии тестов про «second barrier» — так же.
6. **L17.** Ветка ждёт значение соседа: через голый `await` группа не решает
   и `parent.cancel()` не возвращается; через `ctx.wait` отмена родителя
   кончает обе ветки `Cancelled(parent)`.

## Мутации

- **Вернуть первый барьер** — обратный `experiment.diff`. Краснеют 1 (группа
  не кончается), 2 (`cancel()` не возвращается), 3 (замок отпущен после провала
  соседа) и 4 (`disposed == 0` на удержании).
- **Выполнять условные регистрации в первом проходе всегда**, как безусловные.
  Краснеет успешный путь критерия 20 (`discarded == 0`) и тесты фиксации.
- **Отпускать барьер на неуспехе без отмены.** Краснеет вторая половина
  критерия 20 — это уже держат существующие тесты, мутация проверяет, что
  переименование их не ослабило.

Прогон мутаций — в копии пакета, откат копией файла, не `git checkout`.

## Порядок

1. `refactor(async_job): move the runAll group into a part of its own` — L15.
   `_GroupHold`, `_GroupBranch` и `_RunAllGroup` переезжают
   в `lib/src/run_all.dart` (`part of 'job_base.dart'`), ни одна строка кода
   не меняется; строка о файле в `docs/architecture.md`; итог в вердикт L15.
   Гейт: 628 тестов, `solo` зелёный.
2. `fix(async_job): let a runAll branch release what it keeps before the group
   decides` — H1 и L17: ядро, группа, dartdoc, сторожа 1–6, страницы
   с переводами, `docs/architecture.md`, `CHANGELOG.md`, итоги в вердикты H1
   и L17, handoff.
3. Отчёт о сделанном и независимое ревью сделанного.

Проверки перед каждым коммитом: `dart format`, `dart analyze`, `dart test`
в `packages/async_job` и `packages/solo` (оверрайды на месте), стенды
`tool/doc_snippets.py` и `tool/accumulation_snippets.py` — они собирают `solo`
против ядра из дерева, пять питоновских проверок документации.

## Что проверить ревью

1. Есть ли у первого барьера роль, кроме порядка уборки на пути отказа.
   Отдельно: движок домена, закончивший ветку по руке; `solo` и его правила,
   которые на первом барьере ещё могли отменить ветку в фазе «не убирается»;
   вложенные группы; ранний сигнал и `_rereadBranches`.
2. Не открывает ли правка окна, которые закрывали круги дизайна `runAll`:
   фиксация остаётся синхронной, отпускание — на всех путях.
3. Держится ли довод о цене: может ли ресурс, отданный через `discard`, законно
   нуждаться в живом ресурсе той же ветки из `dispose`.
4. Краснеют ли сторожа 1–4 и 6 на мутациях и зеленеют ли на правке: собрать
   эксперимент в своей копии и прогнать.
5. Полон ли список документов, нет ли ещё мест, где обещан порядок «весь стек
   после решения группы».

## Решения владельца

- 2026-09-26: H1 чинится вариантом (а) — безусловная уборка ветки до барьера
  группы, условная после приговора.
