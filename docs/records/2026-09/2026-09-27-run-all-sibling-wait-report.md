# `async_job`: strawman, файл группы `runAll` и ожидание соседа

> **Состояние на 2026-09-27:** сделано: L37 в `6add97b`, L15 и L17 в `9304277`;
> независимое ревью обоих коммитов нашло десять неточностей, все Low, все
> приняты и исправлены следующим коммитом, вердикты — в разделе «Ревью».
> **Что это:** отчёт о правках трёх находок
> `2026-09-26-async-job-project-review.md` — L37, L15 и L17 — и о независимом
> ревью этих правок.
> **Связанные записи:** `2026-09-26-async-job-project-review.md`,
> `2026-09-27-run-all-shared-lock-report.md` (H1: зависание на общем замке,
> на условия которого ссылается абзац L17).

## Что сделано

L37: из обеих версий `children.md` снята фраза о том, что первая попытка
не strawman, и две фразы о наших прогонах; `--` в `children.md` и в разделе
`## Unreleased` `CHANGELOG.md` `async_job` заменено на `—`. L15: `_GroupHold`,
`_GroupBranch` и `_RunAllGroup` вынесены из `job_context.dart` в часть
`lib/src/run_all.dart` без правок кода. L17: абзац «A branch must not wait for
another branch of the same group» говорил, что ожидание `Job.value` соседа
не кончится никогда; мой зонд показал, что узел развязывается на условиях замка
из H1, и абзац стал говорить это. Итоги каждой находки — в её вердикте в записи
ревью.

Ревью правок нашло, что условие замка, на которое теперь ссылается L17, само
сказано слишком узко: отмена снимает зависание и тогда, когда кончает ребёнка,
которого ветка ждёт после тела. Правило переписано в dartdoc `runAll`,
`children.md`, переводе и CHANGELOG: «A cancellation, of the parent or of a
branch, unties it only by ending something a branch still waits for before it
unwinds, its body or a child of it», и в исключения вошёл `ctx.uncancellable`.
Абзац о соседе называет и `Job.done`, и те же исключения.

## Что держит каждое утверждение

Два сторожа в `packages/async_job/test/run_all_test.dart`, каждый — группа
с тестом на случай, и в каждом случае до действия проверено, что группа висит:

- «a cancellation unties the hang only by ending what a branch waits for» —
  замок, девять случаев, из них два с ребёнком ветки `b`, чьё тело уже
  кончилось, и по одному с `cancellable: false` и `ctx.uncancellable`;
- «a branch awaiting a sibling hangs until the group can decide» — сосед,
  шестнадцать случаев: `Job.value` и `Job.done`, голый `await`, `ctx.join`
  глухой и слышащий `ctx.onCancel`, `ctx.wait`, `cancellable: false`,
  `ctx.uncancellable`, третья ветка в `ctx.wait`, её отказ и её отмена, отмена
  самой ждущей ветки и соседа с кончившимся телом. В случаях без третьей ветки
  проверено и то, что таймеров нет.

Мутации раннего сигнала в `_RunAllGroup._branchBodyEnded`, мой прогон, какие
случаи краснеют:

| Мутация | Замок | Сосед |
| --- | --- | --- |
| отменённое тело не даёт раннего сигнала | 1 | 2 |
| ранний сигнал снят совсем | 1 | 3 |
| ручная отмена ветки не даёт раннего сигнала | 0 | 1 |

Набор `async_job` — 656 из 656.

## Ревью

Одно независимое ревью на Opus, в своей копии дерева на `9304277`. Ревьюер
проверил каждое утверждение нового абзаца своими зондами, поставил девять
мутаций ядра, прогнал набор (633 из 633), `dart doc --dry-run`, `solo` против
дерева (803) и документные проверки. Верным он нашёл: зависание при ожидании
`a.value`, «Nothing catches that» (ни таймера, ни ошибки в зоне), «the group
decides only once every branch is held, or once the body of one of them has
ended in anything but a value», все случаи сторожа L17, чистоту переноса L15,
пункт `docs/architecture.md`, снятие strawman и кухни и замену `--` в L37.
Находки ниже — как он их записал; его зонды, мутации и черновики —
в `.artifacts/2026-09-27-run-all-sibling-wait/reviewer/`.

### 1. «Only by ending the body of a branch still running» неверно: отмена развязывает и через ребёнка ветки, чьё тело уже кончилось

**Важность:** Low.

**Где:** `packages/async_job/doc/children.md:259-261`,
`packages/async_job/lib/src/job_context.dart:449-451`,
`docs/ru/async_job/children.md:261-262`. Через «on the same terms as the lock
below» то же унаследовал новый абзац: `children.md:247`,
`job_context.dart:436-437`, `docs/ru/async_job/children.md:248-249`.

**Что не так.** Правило о замке говорит: «A cancellation, of the parent or of a
branch, unties it only by ending the body of a branch still running». Но ветка
до первого барьера ждёт не только своё тело, но и своих детей. Бывает так: тело
ветки кончилось значением, ветка ждёт ребёнка, которого не ждала в теле,
а ребёнок ждёт замок или `Job.value` соседа. Тогда отмена родителя кончает
этого ребёнка, ветка доходит до барьера, все ветки держатся, группа решает,
и проверка отменённого родителя её роняет. Зависание снято, хотя ни одно тело
при этом не кончилось. Ошибка в безопасную сторону: текст обещает меньше, чем
делает код. Но «only» неверно.

**Свидетельство.** Файл
`packages/async_job/test/zz_probe_descendant_test.dart`. Тело `b` запускает
ребёнка через `ctx.run(...).ignore()` и сразу возвращает 2. Ребёнок ждёт
значение `a` или однослотовый замок, который `a` взяла через `join`
с `dispose`. Через секунду отменяется родитель.

```
P15a child of b waits a.value through ctx.wait | before cancel: finished false | after: finished true Cancelled(manual) | [a body ends, b body ends, --- cancel parent]
P15b child of b awaits a.value bare | before cancel: finished false | after: finished false null | [a body ends, b body ends, --- cancel parent]
P16a child of b waits the lock through ctx.wait | before cancel: finished false | after: finished true Cancelled(manual) | [a holds, b-child waits, b body ends, a body ends, --- cancel parent, a releases, b-child holds, b-child releases]
P16b child of b awaits the lock bare | before cancel: finished false | after: finished false null | [a holds, b-child waits, b body ends, a body ends, --- cancel parent]
```

Оба тела кончились значением до отмены, а P15a и P16a развязаны.

**Что предлагаю.** Назвать настоящее условие: «unties it only by ending what a
branch still waits for before it unwinds: its body, or a child it has to wait
for». Второй вариант: оставить «only by ending the body…» и добавить «or a
child the branch waits for after its body». Перевод — «только если кончает то,
чего ветка ещё ждёт перед размоткой: её тело или её ребёнка». Абзац о соседе
поправится сам, раз он ссылается на эти условия.

**Вердикт: принято, Low.** Мой зонд на нынешнем ядре дал те же четыре исхода:
через `ctx.wait` ребёнка `b` узел развязан и для `a.value`, и для замка, голым
`await` — нет. Правило переписано по первому варианту: «unties it only by
ending something a branch still waits for before it unwinds, its body or a
child of it», в dartdoc `runAll`, `children.md`, переводе («только если кончает
то, чего ветка ещё ждёт перед размоткой: её тело или её ребёнка») и в записи
CHANGELOG о H1. Сторож замка переименован в «a cancellation unties the hang
only by ending what a branch waits for» и держит оба случая с ребёнком. Итог H1
в записи ревью и шапка `2026-09-27-run-all-shared-lock-report.md` получили
поправку.

### 2. «A branch awaiting the value through `ctx.wait` ends» сказано без оговорок; `cancellable: false` и `ctx.uncancellable` не кончаются

**Важность:** Low.

**Где:** `packages/async_job/doc/children.md:247-248`,
`packages/async_job/lib/src/job_context.dart:436-438`,
`docs/ru/async_job/children.md:249-250`. Для `ctx.uncancellable` ещё и список
исключений у замка: `children.md:261-263`, `job_context.dart:452-454`.

**Что не так.** Короткое правило абзаца о соседе звучит безусловно. Ждущая
ветка, созданная с `cancellable: false`, или ветка, которая ждёт через
`ctx.wait` внутри `ctx.uncancellable`, не кончается ни от отмены родителя,
ни от отмены самой себя. Первый случай абзац закрывает только ссылкой «on the
same terms as the lock below»: в списке у замка `cancellable: false` есть.
Секции `ctx.uncancellable` нет ни в одном из двух абзацев.

**Свидетельство:** `packages/async_job/test/zz_probe_sibling_test.dart`.

```
P3a b cancellable:false, ctx.wait, parent cancel | … | after: parent false null a false null b false timers 0 micro 0 | after flush: parent false null | zone errors: []
P3b b cancellable:false, ctx.wait, cancel b | … | after: parent false null … | after flush: parent false null | zone errors: []
P4 b ctx.wait inside uncancellable, parent cancel | … | after: parent false null … | after flush: parent false null | zone errors: []
```

Тело в P4: `await ctx.uncancellable(() => ctx.wait(() => a.value)) + 1`.

**Что предлагаю.** В абзаце о соседе: «a branch awaiting the value through
`ctx.wait` ends, unless it refuses the cancellation; one in a bare `await` does
not». В списке у замка дописать «…or in a branch created with
`cancellable: false` or inside `ctx.uncancellable`». Перевод и dartdoc —
так же.

**Вердикт: принято, Low.** Мой зонд: и `cancellable: false`, и `ctx.wait`
внутри `ctx.uncancellable` висят и после отмены родителя, и после отмены самой
`b`. Абзац о соседе называет оба исключения прямо: «ends, unless it was created
with `cancellable: false` or waits inside `ctx.uncancellable`». «Refuses» я
не взял: `ctx.uncancellable` отмену придерживает, а не отклоняет. В списке
у замка появилось «inside `ctx.uncancellable`», а «in a branch created with
`cancellable: false`» стало «in a job created with»: после находки 1 ждать
может и ребёнок ветки. Сделано в dartdoc, странице и переводе; оба сторожа
держат оба исключения.

### 3. Вердикт L17 повторяет неточность «через `ctx.join` не развязывает»

**Важность:** Low.

**Где:**
`docs/records/2026-09/2026-09-26-async-job-project-review.md:1244-1247`. Так же
сказано в сообщении коммита `9304277`, но его уже не исправить.

**Что не так.**

- «Отмена родителя не развязывает его, пока ветка ждёт голым `await` или через
  `ctx.join`» неверно для `ctx.join` на операции, которая слышит
  `ctx.onCancel`: такой узел развязывается. Это ровно находка 1 ревью
  в `2026-09-27-run-all-shared-lock-report.md`, исправленная в документах,
  но вернувшаяся в итог L17.
- «висит, пока тело другой ветки не кончится не значением» опускает второй
  путь, который страница называет верно: группа решает и тогда, когда держатся
  все ветки.

**Свидетельство.** P5: `b` зовёт
`ctx.onCancel(() => abort.completeError(StateError('aborted')))`, затем
`ctx.join(() => Future.any([a.value, abort.future]))`.

```
P5 b join hearing onCancel, parent cancel | before: parent false … | after: parent true Cancelled(manual) a true Cancelled(parent) b true timers 0 micro 0 | … | zone errors: []
```

P11: `b` ловит `Cancelled` из `ctx.wait` и возвращает `-1`, то есть её тело
кончается значением. Узел всё равно развязан, потому что держатся все ветки.

```
P11 b catches cancel from ctx.wait and returns, parent cancel | … | after: parent true Cancelled(manual) a true Cancelled(parent) b true …
```

**Что предлагаю.** В итоге L17 написать: «висит, пока группа не держит все
ветки или пока тело одной не кончится не значением; отмена не развязывает его,
пока ждущая ветка стоит в голом `await` или в `ctx.join` на операции, глухой
к отмене».

**Вердикт: принято, Low.** Мой зонд воспроизвёл P5 и P11: оба развязаны
и отменой родителя, и отменой самой `b`. Итог L17 переписан так, как
предложено, с исключениями из находки 2; сообщение коммита осталось как было.

### 4. Сторож L17 зелёный по верной причине, но держит меньше, чем кажется, а его комментарий неверен

**Важность:** Low.

**Где:** `packages/async_job/test/run_all_test.dart:2284-2334`, комментарий
`:2285-2289`.

**Что не так.**

- **Один тест с циклом.** Первый упавший случай обрывает тест, и остальные
  не проверяются. Под M2 падают два случая, а исходный сторож называет только
  первый.
- **Комментарий неверен.** «the group does that only when the body of a branch
  still running ends in anything but a value» не так. Случаи
  `parent; b waits for it through ctx.wait`
  и `b itself; b waits for it through ctx.wait` развязываются и без раннего
  сигнала. Отменённое тело `b` доводит её до барьера, все ветки держатся,
  и группа падает на `ctx.check()` родителя или на перечитывании веток. Под
  мутацией «ранний сигнал снят совсем» эти два случая зелёные. P11 развязан,
  хотя ни одно тело не кончилось не значением.
- **Ранний сигнал держит один случай.** Мутацию «отменённое тело не ранний
  сигнал» (в записи она названа M1) ловит ровно один случай из девяти,
  с третьей веткой.
- **Нет проверки «висело до действия».** Тест не проверяет, что до отмены
  группа висела: для случаев с `untied: true` зависание до действия
  не утверждается.
- **Чего сторож не держит:**
  - отмену третьей ветки напрямую (P9a);
  - `ctx.join` с `ctx.onCancel` (P5);
  - ждущую ветку с `cancellable: false` (P3);
  - ожидание через `ctx.run` ребёнка (P6).

  Мутацию «ручная отмена ветки не ранний сигнал» (M11) сторож L17 пропускает
  целиком, хотя утверждение ломается: под M11 P9a висит. Ловят её два других
  теста `run_all_test.dart`.

**Свидетельство.** Копия сторожа с отдельным тестом на каждый случай —
`packages/async_job/test/zz_sentinel_cases_test.dart`, сгенерирована из строк
2284-2334. Мутации — `reviewer-scratch/mutate.py`, прогон —
`reviewer-scratch/run_mut.sh`. Какие случаи из девяти падают:

| Мутация | Падают случаи сторожа L17 |
| --- | --- |
| M1: в `_branchBodyEnded` `_sawTrouble` только если `outcome is! Cancelled` | 1: «parent; b awaits it bare, a third branch waits through ctx.wait» |
| M2: `_sawTrouble` из `_branchBodyEnded` снят | 2: тот же и «a third branch fails; b awaits it bare» |
| M3: отменённое тело с `ParentCancelReason` не сигнал | 1: случай с третьей веткой |
| M4: `Failed` тела не сигнал | 1: «a third branch fails» |
| M5: оба барьера пропускают сразу | 5 |
| M7: `cancelWith` держимой ветки зовёт `_hold.bodyEnded` | 3 («parent; bare», «parent; joins», «a itself») |
| M8: `runAll` вешает `_ctx.onCancel` → `_beginFailing` | 2 («parent; bare», «parent; joins») |
| M11: `Cancelled` с `ManualCancelReason` не сигнал | 0. Весь набор: красные «a branch unwinds once every body is over, or one ended without a value» и «a failure covered by the stop does not beat a real cancellation» |
| M6: первый барьер не держит | 0: соседа держит второй барьер, утверждение остаётся верным |

Под M1 весь набор краснеет в восьми тестах, включая сторож L17; итог L17 это
подтверждает.

Под M11 зонд показывает, что утверждение сломано:

```
P9a third in ctx.wait cancelled itself, b bare | … | after: parent false null a false null b false timers 1 micro 0 | after flush: parent false null
```

**Что предлагаю:**

- разбить сторож на тест на случай, как в `zz_sentinel_cases_test.dart`;
- до действия проверять `expect(parent.isFinished, isFalse)`;
- исправить комментарий: «…only once every branch is held, or once the body of
  a branch ends in anything but a value»;
- добавить случаи «a third branch in ctx.wait is cancelled itself» (P9a) и «b
  is created cancellable: false» (P3a). Их сторож L17 сейчас не держит.

**Вердикт: принято, Low.** Мой зонд воспроизвёл P9a на нынешнем ядре: узел
развязан. Сторож L17 стал группой «a branch awaiting a sibling hangs until the
group can decide» с тестом на случай; до действия проверяется, что группа
висит, а без третьей ветки — и что таймеров нет. Комментарий исправлен
по предложению. Случаев стало шестнадцать: добавлены P9a, P5, P3a,
`ctx.uncancellable` и `Job.done`; отказ третьей ветки теперь приходит после
проверки зависания, по сигналу теста, а не по таймеру. Ожидание через `ctx.run`
ребёнка (P6) держит сторож замка случаями находки 1. Той же формой цикла был
сторож замка из H1 — он тоже разбит на тест на случай и проверяет зависание
до действия. Мой прогон мутаций на новых сторожах — в таблице раздела «Что
держит каждое утверждение»: «ручную отмену» ловит новый случай P9a, «отменённое
тело» — три случая, снятый ранний сигнал — четыре.

### 5. Перевод: «развязывает … блокировку» расходится с «снимает зависание» соседнего абзаца

**Важность:** Low.

**Где:** `docs/ru/async_job/children.md:248-250`.

**Что не так.**

- «Отмена развязывает этот узел на тех же условиях, что и блокировку ниже»
  читается как «развязывает блокировку». Но абзац о замке ниже говорит, что
  отмена «снимает зависание», а блокировка остаётся у ветки. Термин
  разъезжается с абзацем, на который текст ссылается, и смысл слегка смещается.
- «а ветка в голом `await` нет» — сказуемое пропущено, а тире, которое
  по правилам пунктуации отмечает пропуск, в переводе запрещено. Фраза выходит
  оборванной.

**Что предлагаю.** «Отмена снимает это зависание на тех же условиях, что
и зависание на блокировке ниже: ветка, которая ждёт значение через `ctx.wait`,
кончается, а ветка, которая ждёт голым `await`, не кончается». Прогнать через
humanizer-ru.

**Вердикт: принято, Low.** Взято предложенное, с исключениями из находки 2:
«Отмена снимает это зависание на тех же условиях, что и зависание на блокировке
ниже: ветка, которая ждёт соседа через `ctx.wait`, кончается, если только она
не создана с `cancellable: false` и не ждёт внутри `ctx.uncancellable`, а ветка
в голом `await` не кончается». Сканер humanizer-ru на обоих правленых абзацах —
100 из 100, тире нет.

### 6. Итог L37: список `--` вне области неполон

**Важность:** Low.

**Где:**
`docs/records/2026-09/2026-09-26-async-job-project-review.md:1566-1568`.

**Что не так.** Итог называет только `packages/solo/doc/children.md` (8 строк)
и `packages/solo/doc/state.md` (7). Двойной дефис как тире стоит ещё в трёх
местах:

- `packages/solo/doc/vs-bloc.md:1152`;
- `## Unreleased` в `packages/solo/CHANGELOG.md`, 36 строк;
- `## Unreleased` в `packages/flutter_solo/CHANGELOG.md`, 24 строки.

С выпуском CHANGELOG уйдут на pub.dev двумя дефисами, то есть тот самый дефект,
который L37 чинил в `async_job`.

**Свидетельство.** Мой подсчёт прозы вне блоков кода и таблиц:

```
packages/flutter_solo/CHANGELOG.md 24
packages/solo/CHANGELOG.md 36
packages/solo/doc/children.md 8
packages/solo/doc/state.md 5
packages/solo/doc/vs-bloc.md 1
```

По разделам: `packages/solo/CHANGELOG.md {'## Unreleased': 36}`,
`packages/flutter_solo/CHANGELOG.md {'## Unreleased': 24}`. Число 7
у `state.md` получается простым grep, вместе со строкой кода и строкой таблицы.

**Что предлагаю.** Дописать в итог `vs-bloc.md` и оба `## Unreleased`; их
приведение к `—` поставить в подготовку выпуска `solo` и `flutter_solo`.

**Вердикт: принято, Low.** Мой подсчёт прозы вне кода и таблиц дал те же числа.
Итог L37 дополнен, а приведение к `—` записано в подготовку выпуска
в `docs/handoff.md`, раздел «На следующий релиз собрано у всех трёх»: это
правка `solo` и `flutter_solo`, вне области ревью `async_job`.

### 7. «Мутацию M1» в итоге L17 путается с находкой M1 той же записи

**Важность:** Low.

**Где:** `docs/records/2026-09/2026-09-26-async-job-project-review.md:1252`.

**Что не так.** В этой записи M1 — находка «`ctx.wait` переворачивает порядок…»
(строка 266). Имя мутации M1 взято
из `2026-09-27-run-all-shared-lock-report.md`, находка 5. Кто читает запись
по находкам, прочтёт «мутацию M1» как мутацию по находке M1.

**Что предлагаю.** Назвать мутацию словами без номера: «мутацию „отменённое
тело не даёт раннего сигнала“ и снятый ранний сигнал он ловит; первую — одним
случаем из девяти, с третьей веткой».

**Вердикт: принято, Low.** В итоге L17 мутации названы словами, с числами
случаев нового сторожа. В этом отчёте номера мутаций ревьюера остались только
внутри его находки 4.

### 8. `docs/handoff.md` противоречит сам себе насчёт push

**Важность:** Low.

**Где:** `docs/handoff.md:7-8` против `:202-203`.

**Что не так.** Вверху сказано «`main` отправлен на `origin` целиком», ниже —
«`origin/main` — `1a332d6`; пятнадцать коммитов … не отправлены». Верно второе:
`git rev-list --count origin/main..9304277` дал `15`. Первая фраза осталась
с `1a332d6`; оба коммита правили handoff и её не тронули.

**Что предлагаю.** Вверху написать: «`main` опережает `origin` на пятнадцать
коммитов, push только отдельным поручением».

**Вердикт: принято, Low.** Сверил: `origin/main` — `1a332d6`. Первая фраза
handoff переписана по предложению, с числом на коммите этой правки.

### 9. Итог L15: «склейка совпадает, кроме одной строки dartdoc `_GroupHold`» — не единственное отличие

**Важность:** Low.

**Где:**
`docs/records/2026-09/2026-09-26-async-job-project-review.md:1199-1201`.

**Что не так.** Склейка `job_context.dart` и `run_all.dart` на `9304277`
отличается от `job_context.dart` на `6add97b` в двух местах. Первое — абзац
dartdoc `runAll` о соседе, правка L17 тем же коммитом (строки 432-439).
Второе — dartdoc `_GroupHold`: одна строка стала двумя. Код не менялся, это
верно.

**Свидетельство:** `diff` склейки с `git show 6add97b:…/job_context.dart` дал
два блока, `432,437c432,439` (абзац L17) и `1383c1385,1386` (`_GroupHold`).

**Что предлагаю.** «…совпадает с прежним `job_context.dart`, кроме абзаца
dartdoc `runAll` о соседе (L17) и строки dartdoc `_GroupHold`…».

**Вердикт: принято, Low.** Верно: я сравнивал склейку с копией, снятой уже
после правки dartdoc L17, и потому видел одно отличие. Итог L15 переписан
по предложению.

### 10. Абзац называет только `Job.value`, а `Job.done` и `whenDone` виснут так же

**Важность:** Low, по желанию.

**Где:** `packages/async_job/doc/children.md:243-244`,
`job_context.dart:432-433`, `docs/ru/async_job/children.md:245`.

**Что не так.** Заголовок «A branch must not wait for another branch» общий,
но пример назван один. Кто ждёт исход соседа через `done`, чтобы не ловить
ошибку, может решить, что его это не касается.

**Свидетельство:**

```
P1a done bare, nothing | … | after: parent false null a false null b false timers 0 micro 0 | after flush: parent false null | zone errors: []
P1b done bare, parent cancel | … parent false null …
P1c done through ctx.wait, parent cancel | … parent true Cancelled(manual) …
P1d whenDone bare, parent cancel | … parent false null …
```

**Что предлагаю.** «Awaiting a sibling's `Job.value` or `Job.done` hangs the
group».

**Вердикт: принято, Low.** Мой зонд: `a.done` голым `await` висит и при отмене,
через `ctx.wait` развязывается. Абзац, перевод и dartdoc называют `Job.done`
рядом с `Job.value`; `whenDone` не назван: он `@protected`, приложению его
не видно. Сторож держит `a.done` голым `await` и через `ctx.wait`.

### Замечание к L15

Пункт `job_context.dart` в `docs/architecture.md:324-325` говорит, что
`startChild` используют `run` и `each`. Теперь его зовёт и `_RunAllGroup`
из `run_all.dart`. Это уже часть L28 (`:322-324`), но итог L15 откладывает
на L28 только `observer.dart`.

**Вердикт: принято как замечание.** `startChild` зовёт группа `runAll`
и до переноса, так что перенос неточности не добавил; правка остаётся за L28,
и итог L15 называет теперь и её.
