# `runAll`: общий замок веток, H1 закрыт документами

> **Состояние на 2026-09-27:** сделано: документы, перевод и сторожа
> в `e075e4b`; независимое ревью нашло семь неточностей, все приняты и
> исправлены следующим коммитом, вердикты — в разделе «Ревью».
> **Что это:** как закрыта H1 из `2026-09-26-async-job-project-review.md`: ядро
> не меняется, документы называют зависание, его причину, когда его снимает
> отмена и как взять общий замок, чтобы его не было; сторожа держат эти
> утверждения.
> **Связанные записи:** `2026-09-26-async-job-project-review.md`,
> `2026-09-26-run-all-one-barrier-design.md` (правка ядра, брошена).

## Решение

H1: ветка `runAll` начинает размотку, только когда все ветки кончили тела
и дождались своих детей или когда тело одной из них кончилось не значением.
Замок, который делят две ветки и который взят через `dispose`, как учит
`cleanup.md`, остаётся у первой, вторая его ждёт, и группа висит без таймеров
и без ошибок, пока тело какой-нибудь ветки не кончится не значением.

Вердикт H1 предлагал править ядро. Дизайн правки,
`2026-09-26-run-all-one-barrier-design.md`, прошёл шесть кругов ревью
и не сошёлся: решения о том, когда группа слышит отмену ветки, меняли, какие
программы виснут, а не убирали зависания, и в шестом круге восемь находок
из четырнадцати были их следствиями. Даже полная правка оставляла висеть замок,
взятый раньше ресурса, который ветка отдаёт, так что правило для страниц было
нужно в любом случае. Владелец 2026-09-27 решил закрыть H1 документами.

## Что изменено

- Dartdoc `JobContext.runAll`: абзац «Nor for what another branch releases in
  its cleanup» сразу за запретом ждать `Job.value` соседа. В абзаце «No branch
  ends before the group has decided» первая остановка ветки названа точнее:
  когда кончились её тело и дети.
- `doc/children.md`: «Four things `runAll` does not promise» стало «Five
  things», пятый пункт — тот же текст, что в dartdoc. Перевод
  в `docs/ru/async_job/children.md`.
- `doc/cleanup.md`: за разделом «Dispose for what stays» абзац о ветке `runAll`
  со ссылкой на пятый пункт — у того самого замка, который страница показывает.
  Перевод в `docs/ru/async_job/cleanup.md`.
- `CHANGELOG.md` пакета, раздел Unreleased.
- Сторожа в `packages/async_job/test/run_all_test.dart`, четыре теста в конце
  файла, и помощник `SharedSlots` — замок или пул с очередью ждущих, из которой
  ждущий может уйти.

Что говорит текст после ревью: размотка ветки начинается, когда все ветки
кончили тела и дождались детей или тело одной кончилось не значением. Замок или
слот пула, где свободных слотов меньше, чем веток, которым они нужны, взятые
через `dispose`, держат группу, пока тело другой ветки не кончится
не значением. Отмена, родителя или ветки, снимает зависание, только кончая тело
ветки, которая ещё работает; `ctx.join` на глухой к отмене операции, голый
`await`, `cancellable: false` и отмена держащей ветки его не снимают. Выходы:
замок в ребёнке ветки, с регистрацией по приходу того, что ребёнок отдаёт, или
`[...].wait`.

Русские абзацы оба раза прошли через humanizer-ru: сканер дал 100 из 100, тире
в них нет; одна длинная фраза о блокировке разбита на две.

## Что держит каждое утверждение

Первый зонд, до ревью, на нынешнем ядре под `fakeAsync`: однослотовый замок,
две ветки берут его и держат 10 мс.

| Случай | Итог |
| --- | --- |
| `runAll`, замок через `join` с `dispose` | висит: `[a holds, b waits]`, таймеров 0, микрозадач 0, ошибок в зоне нет |
| то же, затем `parent.cancel()` | `cancel` не возвращается, исхода нет |
| замок голым `await` и `onDispose`, затем отмена | так же |
| замок через `wait` с `dispose`, затем отмена | `Cancelled(manual)`, `[a holds, b waits, a releases, b holds, b releases]` |
| пул на два слота, три ветки через `join` | висит: `[a holds, b holds, c waits]` |
| `[ctx.run(a), ctx.run(b)].wait` | `Done([1, 1])` |
| `runAll`, замок в ребёнке каждой ветки | `Done([1, 1])` |
| тело `a` 10 мс, тело `b` 40 мс, ребёнок `b` 80 мс | `dispose` у `a` на 80 мс |
| то же, но тело `b` бросает на 40 мс | `dispose` у `a` на 40 мс |

Случаи, которые добавило ревью, — в его находках ниже; я воспроизвёл их
на нынешнем ядре зондами ревьюера, они лежат
в `.artifacts/2026-09-27-run-all-shared-lock/reviewer/`.

Сторожа:

- «a branch unwinds once every body is over, or one ended without a value» —
  три пути: все тела кончились значением (80 мс, когда кончился ребёнок), тело
  бросило (40 мс) и ветку отменили саму, пока третья ещё в теле (20 мс);
- «a lock or a pool the branches share through dispose hangs the group» —
  `join`, голый `await` и `wait`, до отмены родителя и после; пул на два слота
  с тремя ветками и с двумя, когда один слот держит родитель;
- «a cancellation unties the hang only by ending a body still running» — шесть
  случаев: отмена родителя, когда `b` ждёт через `join` операцию, слышащую
  `ctx.onCancel` (снимает), когда третья ветка стоит в `ctx.wait` (снимает),
  когда `b` создана с `cancellable: false` (не снимает); отмена самой `b` через
  `wait` (снимает) и через `join` (не снимает); отмена `a`, которая держит
  замок (не снимает);
- «a lock two branches share is free in a child of each, or under .wait» — оба
  выхода, которые советуют документы.

«Без ошибок» держит зона теста: ошибка, дошедшая до неё, валит тест. Мутация
«тело, кончившееся отменой, не даёт раннего сигнала» краснит первый и третий
тесты. На прототипе правки ядра (`prototype-b9.diff`
из `.artifacts/2026-09-26-run-all-one-barrier/`) краснеют первые три, четвёртый
зелёный: правка, которая тронет первый барьер, перепишет эти документы вместе
со сторожами.

`async_job`: `dart format`, `dart analyze` без замечаний, `dart test` 632
из 632. Проверки документов: `reflow.py --check`, `check_line_width.py`,
`check_doc_shape.py`, `check_translations.py`, `check_links.py` — чисто.

## Ревью

Одно независимое ревью на Opus, в своей копии дерева на `e075e4b`, с зондами
на нынешнем ядре, мутацией и прототипом правки ядра. Ревьюер прогнал набор (631
из 631), проверки документов и сканер humanizer-ru, подтвердил таблицу зонда,
тайминг, зависание и оба выхода, а на прототипе — что краснеют ровно первые два
сторожа. Находки ниже — как он их записал; зонды и черновики —
в `.artifacts/2026-09-27-run-all-shared-lock/`.

### 1. Условие «отмена родителя снимает зависание» неверно в обе стороны

**Важность:** Medium.

**Где:** `packages/async_job/doc/children.md:261-262`;
`packages/async_job/lib/src/job_context.dart:445-446`;
`packages/async_job/CHANGELOG.md:225-226`;
`docs/ru/async_job/children.md:261-262`. То же повторяют итог H1
в `2026-09-26-async-job-project-review.md:192` («только через `ctx.wait`»)
и отчёт.

**Что не так:** текст говорит: «Cancelling the parent unties it only when the
waiting branch waits through `ctx.wait`; through `ctx.join` or a bare `await`
it does not». На деле зависание снимается, когда отмена кончает тело любой
ветки, которая ещё в теле, и не обязательно ждущей. Она кончает его, если то,
на чём ветка стоит, выпускает отмену на любой глубине. Отсюда шесть случаев:

- `ctx.join`, чьё действие слышит `ctx.onCancel`, зависание снимает. Ровно это
  советует первый пункт того же списка: «hand the cancellation to it with
  `ctx.onCancel` and wait for it with `ctx.join`».
- `ctx.join` у ждущей ветки снимает зависание, если третья ветка группы ещё
  стоит в `ctx.wait`.
- Ветка ждёт через `ctx.run` ребёнка, который ждёт через `ctx.wait`: зависание
  снимается, хотя сама ветка `ctx.wait` не зовёт. Во вложенной группе так же.
- Обратная, опасная сторона: ждущая ветка с `cancellable: false` ждёт через
  `ctx.wait`, и зависание **не** снимается.
- Отмена самой ветки, которая держит замок, не помогает никогда: её тело уже
  кончилось.
- Отмена ждущей ветки помогает только через `wait`.

**Доказательство** (`shared_lock_probe_test.dart`):

```
P1 trace: [a holds, b waits, --- cancel parent, b gives up, a releases]
P1 returned: true, outcome: Cancelled(manual), zone errors: []
P10 trace: [a holds, b waits, --- cancel parent, a releases, b holds, b releases], returned: true, outcome: Cancelled(manual), zone errors: []
P8 [wait] trace: [a holds, b waits, a releases, b holds, b releases], returned: true, outcome: Cancelled(manual), zone errors: []
P11 [outer b holds, other waits via wait] trace: [b holds, a1 waits, --- cancel parent, b releases, a1 holds, a1 releases], returned: true, outcome: Cancelled(manual), zone errors: []
P2 trace: [a holds, b waits, --- cancel parent]
P2 returned: false, finished: false, zone errors: []
P3 [holder a / wait] trace: [a holds, b waits, --- cancel holder a]
P3 [holder a / wait] parent finished: false, outcome: null, zone errors: []
P3 [waiter b / wait] parent finished: true, outcome: Cancelled(handler: child b: Cancelled(manual)), zone errors: []
P3 [waiter b / join] parent finished: false, outcome: null, zone errors: []
```

Условия зондов: P1 — ветка `b` зовёт `ctx.onCancel(() => lock.abort(name))`,
потом `ctx.join(() => lock.acquire(name), dispose: …)`; P10 — ветки `a` и `b`
берут замок через `join`, третья стоит в `ctx.wait(() => delay(60000))`; P2 —
`b` создана с `cancellable: false` и ждёт через `ctx.wait`.

**Что предложить:** назвать настоящее условие. Например: «Cancelling the parent
unties it only when the cancellation ends the body of a branch still running:
through `ctx.wait`, or through an operation that hears `ctx.onCancel`. A
`ctx.join` on an operation deaf to it, a bare `await`, or a branch created with
`cancellable: false` stays put, and cancelling the branch that holds the lock
does nothing: its body is over.» Поправить так же dartdoc, CHANGELOG, перевод,
итог H1 и отчёт. Поставить сторожей на P1 и P2.

**Вердикт: принято, Medium.** Зонды ревьюера воспроизвёл на нынешнем ядре своим
прогоном: P1, P2, P3, P8, P10 и P11 дают те же строки. Условие переписано так,
как предлагает ревьюер, но шире: «A cancellation, of the parent or of a branch,
unties it only by ending the body of a branch still running», с теми же
исключениями и отменой держащей ветки. Сделано в dartdoc, `children.md`,
CHANGELOG, переводе, итоге H1 и в этом отчёте. Сторож «a cancellation unties
the hang only by ending a body still running» держит P1, P10, P2 и три случая
P3.

### 2. `cleanup.md` и CHANGELOG описывают начало уборки неточно, а CHANGELOG неверно

**Важность:** Low.

**Где:** `packages/async_job/doc/cleanup.md:77-80`,
`docs/ru/async_job/cleanup.md:78-81`,
`packages/async_job/CHANGELOG.md:221-222`. Попутно
`lib/src/job_context.dart:424-425`.

**Что не так:**

- В `cleanup.md` написано «it starts unwinding only when every branch of the
  group has ended its body», без «and its children». Первый новый тест сам это
  опровергает: тело `late` кончилось на 40 мс, а `early disposed` пришёл на 80
  мс, когда кончился ребёнок `late`.
- «the branch waiting for it never ends its body» слишком сильно: отказ третьей
  ветки группу развязывает, ждущая получает замок и кончает тело (P4).
- CHANGELOG пишет «A branch starts unwinding only when every branch has ended
  its body», без исключения для отказа. Это прямо неверно: в P4 ветка `a`
  отпускает замок, пока `b` ещё ждёт внутри своего тела.
- В dartdoc `runAll` один и тот же момент теперь описан двумя способами: старый
  абзац говорит «A branch stands twice: once when its body is over», новый
  говорит «every branch has ended its body and its children».

**Доказательство:**

```
P4 trace: [a holds, b waits, a body ends, a releases, b holds, b releases]
P4 outcome: Failed(Bad state: c), zone errors: []
```

Здесь `a` и `b` берут замок через `join` и `dispose`, а `c` через 100 мс
бросает `StateError`. Из `run_all_test.dart` (успешный путь):
`'40: late body ends', '80: child of late ends', '80: early disposed'`.

**Что предложить:**

- В `cleanup.md` и переводе написать «…has ended its body and waited for its
  children…».
- «Never ends its body» заменить на «waits for it as long as no branch of the
  group fails».
- В CHANGELOG добавить исключение «or the body of one of them ends in anything
  but a value».
- Старый абзац dartdoc можно выровнять: «once its body and its children are
  over».

**Вердикт: принято.** P4 воспроизвёл. В `cleanup.md` и переводе — «has ended
its body and waited for its children», с исключением для тела, кончившегося
не значением; вместо «never ends its body» — «keeps the group from getting
there, so the group hangs», а ссылка говорит, что снимает зависание. В пятом
пункте и dartdoc вместо «waits forever» — группа висит, «until the body of
another branch ends in anything but a value»: это покрывает и отказ, и отмену.
В CHANGELOG исключение добавлено. Старый абзац dartdoc: «once when its body and
its children are over».

### 3. «A slot of a pool smaller than the group» — не то условие

**Важность:** Low.

**Где:** `packages/async_job/doc/children.md:257-258`,
`packages/async_job/lib/src/job_context.dart:442`,
`docs/ru/async_job/children.md:257-258`.

**Что не так:** любой пул меньше группы, где каждая ветка берёт слот через
`dispose`, действительно вешает группу. Но условие не в размере пула, а в числе
свободных слотов. Пул на два слота и группа из двух веток тоже виснут, если
один слот уже держит кто-то, кто ждёт группу, например родитель. Под `.wait`
тот же код кончается `Done`. Читатель, у которого пул не меньше группы, решит,
что он в безопасности.

**Доказательство** (P5: родитель берёт слот через `join` и `dispose`, потом две
ветки по слоту):

```
P5 [runAll] timers: 0, microtasks: 0
P5 [runAll] trace: [parent holds, a holds, b waits]
P5 [runAll] finished: false, outcome: null, zone errors: []
P5 [.wait] trace: [parent holds, a holds, b waits, a releases, b holds, b releases, parent releases]
P5 [.wait] finished: true, outcome: Done([1, 1]), zone errors: []
```

**Что предложить:** написать «a slot of a pool with fewer free slots than the
branches that take one» или короче «a pool the group can drain».

**Вердикт: принято.** P5 воспроизвёл. Текст: «a slot of a pool with fewer free
slots than the branches that want one», перевод — «слот пула, где свободных
слотов меньше, чем веток, которым они нужны». Сторож зависания получил случай
P5.

### 4. Совет «замок в ребёнке ветки» молчит о том, что переезжает вместе с замком

**Важность:** Low.

**Где:** `packages/async_job/doc/children.md:262-264`,
`packages/async_job/lib/src/job_context.dart:447-449`,
`docs/ru/async_job/children.md:262-264`.

**Что не так:**

- Под замком часто берут и то, что ветка отдаёт наружу (`discard`). Если
  перенести такой код в ребёнка целиком, запись ребёнка пропадает, когда он
  кончается `Done`. Тогда при отказе группы ресурс никто не закрывает.
- Регистрация по приходу его спасает, но компенсация теперь выполняется уже
  после того, как замок отпущен. Прежде, в самой ветке, она шла под замком.
- Замок больше не покрывает значение по пути к вызывающему.

На странице правило регистрации по приходу стоит в следующем разделе («What a
group hands back»), в dartdoc `runAll` его нет совсем.

**Доказательство:** в P7 ребёнок берёт замок через `join` и `dispose`,
открывает ресурс через `wait` и `discard`, а третья ветка падает. P7b —
контроль: то же в самой ветке, пул на 2 слота.

```
P7 [register no] trace: [a holds, b waits, a releases, b holds, b releases]
P7 [register no] outcome: Failed(Bad state: c), zone errors: 0
P7 [register on arrival] trace: [a holds, b waits, a releases, b holds, b releases, a resource closed, b resource closed]
P7b trace: [a holds, b holds, a resource closed, b resource closed, a releases, b releases]
```

**Что предложить:** дописать к совету «…and registers on arrival what that
child hands it, `ctx.run(child, discard: ...)`» со ссылкой
на `cleanup.md#registering-on-arrival`. Можно одной фразой сказать, что такая
компенсация выполняется уже без замка.

**Вердикт: принято.** P7 и P7b воспроизвёл. К совету дописано: если ребёнок
открывает и то, что ветка отдаёт наружу, ветка регистрирует это по приходу,
`ctx.run(child, discard: ...)`, со ссылкой на «Registering on arrival», и такой
`discard` выполняется уже без замка. В dartdoc — то же, без ссылки. Своего
сторожа у фразы нет: регистрацию по приходу в ветке держит тест «a branch
registers on arrival what a child of its own opened» того же файла, а порядок
«сначала замок, потом компенсация» — зонд P7.

### 5. Три сторожа не держат часть утверждений, отчёт обещает больше

**Важность:** Low.

**Где:** `packages/async_job/test/run_all_test.dart:1999-2172`. В отчёте
`2026-09-27-run-all-shared-lock-report.md` это шапка («сторожа держат каждое
утверждение») и раздел «Что держит каждое утверждение».

**Что не так:**

- Мутация M1 (тело, кончившееся `Cancelled`, не даёт раннего слова) делает
  неверным «or when the body of one of them has ended in anything but a value»
  для отменённой ветки. Все три новых теста при ней зелёные: первый тест
  пробует отказ только через `StateError`; во втором родителя отменяют, и тогда
  тела кончают все ветки, так что группа разматывается и без раннего слова.
- M1 ловят четыре старых теста `run_all_test.dart`.
- Утверждение об отмене родителя держится только на том частном случае, где оно
  верно: две ветки, `join` без `onCancel` (см. находку 1).
- «no error» держится лишь неявно, через зону теста. «микрозадач 0» из таблицы
  не проверяет ни один тест.

**Доказательство:** под M1:

```
00:00 +1: All tests passed!   (a branch unwinds once every body is over, or one ended without a value)
00:00 +1: All tests passed!   (a lock or a pool the branches share through dispose hangs the group)
00:00 +1: All tests passed!   (a lock two branches share is free in a child of each, or under .wait)
cancelled_body_timing_test.dart:
[20: cancel the branch, 60: slow body ends, 60: early disposed]
  Expected: ['20: cancel the branch', '20: early disposed']
весь набор, красные:
test/run_all_test.dart: a branch the group stopped never gives the group its outcome [E]
test/run_all_test.dart: a cancellation nobody asked for is trouble, whatever it wears [E]
test/run_all_test.dart: a cancellation this call asked for never comes out of it [E]
test/run_all_test.dart: a failure covered by the stop does not beat a real cancellation [E]
```

На чистом ядре тот же зонд даёт `20: early disposed` и зелёный.

**Что предложить:**

- Добавить в первый тест вариант, где ветку отменяют саму, без отмены родителя
  (как в `cancelled_body_timing_test.dart`).
- После правки находки 1 поставить сторожей на новое условие.
- В отчёте написать, что утверждение об отменённом теле держат старые тесты
  `run_all_test.dart`.

**Вердикт: принято.** M1 воспроизвёл: три теста зелёные, зонд
`cancelled_body_timing_test.dart` красный. Первый тест получил путь, где ветку
отменяют саму; первая версия этого пути M1 не ловила: отмена доходит
и до ребёнка ветки, и к 20 мс кончались все тела, так что размотка шла и без
раннего сигнала. С третьей веткой, которая ещё в теле, тест под M1 красный:
`Actual: ['20: late cancelled', '60: early disposed']`. Новый тест про отмену
под M1 тоже красный. Шапка и раздел «Что держит каждое утверждение» говорят,
что держит каждый тест; «без ошибок» держит зона теста, и это сказано;
«микрозадач 0» — строка таблицы зонда, документы его не утверждают.

### 6. Записи: L15 и L17 в записи ревью по-прежнему привязаны к правке ядра H1

**Важность:** Low.

**Где:** `docs/records/2026-09/2026-09-26-async-job-project-review.md`:
`:1193-1194` — вердикт L15: «тем же заходом, что и правку H1: правка барьера
всё равно их трогает»; `:1226-1228` — вердикт L17: «Если правка H1 уберёт
первый барьер, пересмотреть…»; `:2159` — «2. Код ядра, до выпуска: H1 вместе
с L15 и L17»; `:187-195` — итог H1.

**Что не так:**

- `docs/handoff.md:36-37` и шапка `2026-09-26-run-all-one-barrier-design.md`
  говорят, что L15 и L17 снова отдельные находки. Сама запись ревью, которую
  читают по находкам, этого не говорит: оба вердикта и порядок работ ссылаются
  на правку ядра, которой не будет.
- Мелочь по форме: итог H1 стоит отдельным абзацем после вердикта.
  В прецеденте, `2026-09-19-solo-project-review.md:118` («Сделано в `f18efc6`,
  но не так, как предложено здесь…»), итог дописан в сам абзац вердикта.
- По существу итог повторяет неточное «только через `ctx.wait`» (находка 1).

**Доказательство:** `grep -n "L15 и L17"` находит `docs/handoff.md:36`,
`2026-09-26-run-all-one-barrier-design.md:5` («L15 и L17 вернулись…»)
и `2026-09-26-async-job-project-review.md:2159` («H1 вместе с L15 и L17»). Diff
коммита не трогает строки 1183–1228 записи ревью.

**Что предложить:** дописать к вердиктам L15 и L17 строку: H1 закрыт
документами (`2026-09-27-run-all-shared-lock-report.md`), находка
самостоятельна. Поправить пункт 2 «Порядка работ». Итог H1 можно влить в абзац
вердикта.

**Вердикт: принято.** К вердиктам L15 и L17 дописана поправка: правки барьера
не будет, H1 закрыт документами, находка самостоятельна. Пункт 2 «Порядка
работ» начинается с «L15 и L17 (H1 закрыт документами)». Итог H1 влит в абзац
вердикта и поправлен по находке 1.

### 7. Перевод: «unwinding» передан как «уборка», а в остальных переводах это «размотка»

**Важность:** Low.

**Где:** `docs/ru/async_job/children.md:254-255` («Уборку ветка начинает»),
`docs/ru/async_job/children.md:264` («каждая ветка убирает за собой сама»),
`docs/ru/async_job/cleanup.md:78-79` («уборку она начинает»).

**Что не так:** в английском это два разных слова, «cleanup» (колбэки)
и «unwinding» (фаза). Русский `cleanup.md` передаёт фазу словом «размотка»:
`:230` «ни та, что придёт в саму размотку», `:247` «пришедшей в саму размотку».
Новый пятый пункт оба английских слова передаёт одним «уборка». Смысл
не искажён: уборка начинается вместе с размоткой. Но термин разъезжается
с соседними абзацами.

Остальное в переводе в порядке: смысл совпадает, «блокировка» и «уборка» как
в других переводах, тире и жёстких запретов нет (скан 100/100).

**Что предложить:** по желанию «Размотку ветка начинает…» и «там каждая ветка
разматывается сама», прогнать через humanizer-ru. Либо оставить как есть.

**Вердикт: принято.** «Размотку ветка начинает», «там каждая ветка
разматывается сама» и в `cleanup.md` «размотку она начинает»; «уборка» осталась
там, где в английском «cleanup». Изменённые абзацы прогнаны через humanizer-ru:
100 из 100, тире нет.
