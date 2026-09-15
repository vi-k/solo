> **Состояние на 2026-09-15:** круг пройден, вердикты стоят под каждой
> находкой. **Что это:** полное ревью работы «освобождение регистрируется
> у получателя» — ревьюер Fable (`claude-fable-5-1`), изолированный клон
> на коммите `782fc38`. Astra в лимите до 19 сентября, отказ безымянный —
> общий пул; по решению владельца от 2026-09-12 ревью в этом случае идёт
> на Fable.
> **Связанные записи:** работа —
> `2026-09-15[8]-cleanup-registers-on-arrival-report.md`; отменённая спека,
> которую эта работа заменила, —
> `2026-09-14[17]-discard-follows-the-value-design.md`. Второй ревьюер круга,
> `agy`, записью не стал: прогон отдал `SUCCESS` при одном ходе за 26 секунд,
> тридцать минут ждал собственную фоновую задачу и был убит по таймауту,
> клон остался нетронутым. Разбор этого отказа — в скилле `agy`, раздел
> «Прогон, где ничего не было». Задание для повтора —
> `/private/tmp/z7k2v9/brief.md`.

> **Состояние на 2026-09-15:** ревью пяти коммитов `cd53172`, `a10e0b7`,
> `58cbb9b`, `8cc994f`, `8fd302b` на изолированном клоне, стоящем
> на `782fc38`. Зонды — `packages/async_job/.artifacts/review/`
> и `packages/solo/.artifacts/review/` клона, все под `.gitignore`.
> **Что это:** независимое ревью решения «получатель регистрирует ресурс
> там, где получил» и диагностики «канал отладки называет каждую передачу».
> **Связанные записи:** `2026-09-15[8]-cleanup-registers-on-arrival-report.md`,
> `2026-09-14[17]-discard-follows-the-value-design.md`.

# Ревью: регистрация у получателя и строка о передаче

**Итог: не годится.** Рецепт `ctx.wait(() => ctx.run(child), discard: ...)`
не доводит значение до `discard`, когда контрольная точка родителя
срабатывает между `Done` ребёнка и приходом значения: `_awaitChild` зовёт
`check()` и выбрасывает значение, ребёнок свою регистрацию уже отбросил,
и закрыть ресурс некому. Вход воспроизводится в ядре тремя триггерами
и в `solo` внешней сменой состояния, детерминированно; отменённая спека этот
вход закрывала бы. Остальное — существенные неточности в документах
и в диагностике, ни одна из них сама по себе не блокирует.

Тяжесть: блокирующих — 1, существенных — 5, мелочей — 2.

## 1. Значение из `ctx.run` не доходит до `discard`, если контрольная точка родителя бросает между `Done` ребёнка и `wait`

**Тяжесть:** блокирующая.

`ctx.run(child)` возвращает `_awaitChild`: `await child.value`, затем
`if (!_owner.bodyEnded) check()`, и только потом `return value`. Если
`check()` бросает — родитель помечен отменой в это самое окно или правило
домена перестало держаться, — значение выбрасывается внутри `_awaitChild`,
и `_race.forward` (для `wait`) или `await action()` (для `join`) получают
ошибку, а не значение. `discard` получателя не видит ничего. Ребёнок при этом
кончился `Done` и свою регистрацию отбросил — строка канала отладки об этом
честно сообщает. Ресурс не закрывает никто. Рецепт из `doc/cleanup.md`,
дартдока `onDiscard` и `doc/children.md` на этом входе не работает, а фраза
«`wait` is handed the value all the same and runs the `discard`» верна только
тогда, когда тело родителя уже кончилось к моменту `Done` ребёнка (как
в тесте `cleanup_test.dart`, где отмена приходит за 15 мс до конца ребёнка).

Три триггера в ядре: слушатель `child.done.then(...)`, зарегистрированный
до `ctx.run` (B); правило домена, переставшее держаться, пока ребёнок отдаёт
значение (C — контекст с переопределённым `check()`, ровно так работает
`solo`); отмена из `onFinish` наблюдателя при рецепте через `join` (F).
Наблюдатель с `wait` (A, D) не течёт только из-за счёта микрозадач: тело
успевает кончиться на один хоп раньше. В `solo` вход детерминирован без
всяких гонок: `externalSetState` в ответ на конец ребёнка ломает `keepWhile`
родителя, и `ctx.run` бросает `Cancelled(rules)`, выбросив базу. Собственный
`emit` ребёнка не течёт — он же и роняет ребёнка отменой, и ребёнок
закрывает сам.

Отменённая спека (`2026-09-14[17]-discard-follows-the-value-design.md`)
этот вход закрывала бы: ребёнок, кончившийся `Done`, отдавал бы регистрацию
родителю, и родитель, кончившийся `Cancelled`, её выполнил бы независимо
от того, дошло ли значение до тела. Замер G показывает, что механика ядра
для обхода есть — `ctx.run(child).ignore()` и `ctx.wait(() => child.value,
discard: ...)`, где проверка родителя не стоит между значением и `wait`, —
но это не тот рецепт, который записан.

**Замер:**
```
$ cd packages/async_job && dart run .artifacts/review/probe_window.dart
A observer.onFinish(opener) cancels the parent
  parent=Cancelled(manual) opener=Done(db) closed=[parent:db]
  traces: [Job(opener) handed its value over: 1 conditional cleanup dropped]
B opener.done.then(parent.cancel) registered before ctx.run
  parent=Cancelled(manual) opener=Done(db) closed=[]
C the rules of a domain stop holding while the child hands over
  parent=Cancelled(manual: rules stopped holding) opener=Done(db) closed=[]
D a group: the branch registers on arrival, the parent is cancelled as the opener finishes
  parent=Cancelled(manual) branch=Cancelled(parent) opener=Done(db) closed=[branch:db]
E control: the cancel lands after the value arrived
  parent=Cancelled(manual) opener=Done(db) closed=[parent:db]
F the same through join
  parent=Cancelled(manual) opener=Done(db) closed=[]
G ctx.run(opener).ignore() + ctx.wait(() => opener.value, discard:)
  parent=Cancelled(manual) opener=Done(db) closed=[parent:db]

$ cd packages/solo && dart run .artifacts/review/probe_solo_window.dart
wait, the child emits out of keepWhile and returns: parent=Cancelled(rules: keepWhile) child=Cancelled(parent) closed=[child:db]
join, the child emits out of keepWhile and returns: parent=Cancelled(rules: keepWhile) child=Cancelled(parent) closed=[child:db]
wait, externalSetState on child.done: parent=Cancelled(rules: keepWhile) child=Done(db) closed=[]
join, externalSetState on child.done: parent=Cancelled(rules: keepWhile) child=Done(db) closed=[]
```

**Вердикт: принята, воспроизведена своим зондом.** На том же входе
`parent=Cancelled(manual) child=Done(db) closed=[]`, а названный обход
(`ctx.run(child).ignore()` плюс `ctx.wait(() => child.value, discard: ...)`)
даёт `closed=[closed db]`. Дыра не в рецепте, а в `_awaitChild`: `check()`
стоит после `await child.value`, и значение пропадает вместе с броском —
получателю нечего регистрировать, потому что до него оно не доходит.
Двухстрочная форма теряет его точно так же, так что выбор формы тут ни при
чём. Закрывается это тремя разными способами, и выбор не мой: назвать
границу и записать обход; дать `ctx.run` параметр `discard:`, чтобы ядро
регистрировало значение в момент прихода, до `check()`; или вернуться
к отменённой спеке. Вынесено владельцу; до его решения работа не закрыта.

## 2. Дартдок `runAll` говорит, что `Future.wait` бросает `ParallelWaitError`

**Тяжесть:** существенная.

Абзац «When which» из `8cc994f`: «`[ctx.run(a), ctx.run(b)].wait` and
[Future.wait] wait for every branch and stop none, ..., and what they throw
is a `ParallelWaitError`». `Future.wait` бросает первую ошибку как есть;
конверт `ParallelWaitError` бросает только расширение `.wait` на списке.
`doc/children.md` рядом говорит это правильно («`Future.wait` keeps the
first error to reach it»), дартдок — место, где читатель выбирает, —
говорит обратное.

**Замер:**
```
$ cd packages/async_job && dart run .artifacts/review/probe_future_wait.dart
1 Future.wait throws StateError: Bad state: a
  [..].wait throws ParallelWaitError<List<int?>, List<AsyncError?>>
```

**Вердикт: принята, исправлено.** Фраза сливала две разные вещи в одну.
Теперь `.wait` и `Future.wait` в дартдоке разведены: первый бросает конверт
со значениями и ошибками всех веток, второй — первую дошедшую ошибку,
а остальные отпускает.

## 3. `doc/children.md` приписывает `eagerError: true` то, что делает и обычный `Future.wait`

**Тяжесть:** существенная.

Абзац из `8fd302b`: «What the early waking does change is who decides:
a body that catches the error and returns ends the job `Done` with a branch
failed, and a branch that opened a resource and returned it hands it to
a `Future.wait` that has already completed, where nobody closes it». Замер
трёх форм на одном входе: с `eagerError` и без него задание кончается
`Done(null)`, ветка `Done(db)`, `closed=[]` — ни «кто решает», ни судьба
ресурса от раннего пробуждения не зависят; отличается только момент, когда
тело просыпается. Ресурс сохраняет лишь `[...].wait` — он лежит
в `ParallelWaitError.values`, и тело может его закрыть. Перевод повторяет
то же самое. Тест `eagerError wakes the body early and ends nothing early`
проверяет только эйджерную сторону и контраст не сторожит.

**Замер:**
```
$ cd packages/async_job && dart run .artifacts/review/probe_future_wait.dart
2 extension=false eager=true: job=Done(null) late=Done(db) closed=[] caught=StateError values=null
2 extension=false eager=false: job=Done(null) late=Done(db) closed=[] caught=StateError values=null
2 extension=true eager=false: job=Done(null) late=Done(db) closed=[] caught=ParallelWaitError<List<String?>, List<AsyncError?>> values=[null, db]
```

**Вердикт: принята, исправлено и взято под сторож.** Абзац и перевод
переписаны: `eagerError` меняет ровно одно — когда просыпается тело;
и «кто решает», и потеря ресурса верны для обеих форм `Future.wait`,
а значения хранит только `.wait`, в `ParallelWaitError.values`. Тест
`eagerError moves when the body wakes, and nothing else` сравнивает три формы
на одном входе и сторожит именно контраст.

## 4. Задание, конченное движком руками, теряет отложенную запись без строки — или со строкой, которая врёт

**Тяжесть:** существенная.

Два выхода из `_execute` после `finish` руками (`if (isFinished) {
_disposing = false; return; }` у обоих барьеров) не трогают `_skipped`:
отложенная запись не выполняется, не называется и остаётся полем
законченного задания — ровно то, ради чего список чистят в конце. Дартдок
`finish` обещает «how many cleanups were left behind is in the debug
trace», но строка `finished with N cleanups pending` считает только
`_cleanups`: ветка, снятая у второго барьера с одной отложенной записью,
не говорит ничего. Ветка кончилась `Cancelled`, значение не досталось
никому, `closed=[]`.

Второй вход — без группы: движок кончает задание, пока размотка ждёт
диспозер. Цикл продолжается после `finish`, `valueHandedOver()` читает
локальный `outcome` (`Done`), а не исход задания (`Cancelled`), и строка
сообщает «handed its value over» о задании, которое кончилось отменой
и значение никому не отдало. Путь поддержан ядром явно (комментарии
«An engine of a domain ended the branch by hand while it stood there»),
но `solo` пользуется `_drop` только для незапущенных заданий — поэтому
существенная, а не блокирующая.

**Замер:**
```
$ cd packages/async_job && dart run .artifacts/review/probe_by_hand.dart
1 held branch: a.disposing=true a.finished=false
  root=Cancelled(handler: child a: Cancelled(manual: by hand)) a=Cancelled(manual: by hand) b=Cancelled(sibling) closed=[]
  traces of a: [Job(a) started, Job(a) finished: Cancelled(manual: by hand)]
2 plain job: disposing=true finished=false
  outcome=Cancelled(manual: by hand) closed=[]
  traces of j: [Job(j) started, Job(j) finished with 1 cleanups pending, Job(j) finished: Cancelled(manual: by hand), Job(j) handed its value over: 1 conditional cleanup dropped]
```

**Вердикт: принята, исправлено и взято под сторож.** Строка больше
не выбирает слова по локальному `outcome`: если задание уже закончено чужой
рукой, она так и говорит — `was finished as Cancelled(handler: by hand) with
1 conditional cleanup left aside`. Оба ранних выхода после барьеров теперь
тоже её зовут, так что отложенная запись не пропадает молча. Сторож —
`a job finished by hand while unwinding says that instead`.

## 5. Продолжение цепочки, отменённое в ожидании источника, — получатель без момента

**Тяжесть:** существенная.

Источник с `discard` кончается `Done` (здесь — отвергнув отмену цепочки),
его регистрация отброшена, строка сказала «handed its value over». Хвост
`then` был отменён, пока ждал, и «finishes without calling its callback»:
колбэк с его `ctx` не запускается, регистрировать негде и некогда. Значение
не досталось никому, `closed=[]`. Дартдок `onDiscard` перечисляет
получателей — «a parent awaiting [run], a caller holding [Job.value]» —
и продолжение цепочки среди них не называет; раздел «Chains»
в `doc/children.md` говорит «Cleanup registered by the source has already
run when the continuation receives its value», что для `discard` неверно
в обе стороны: не выполнялось и не выполнится. Спека этот вход исключала
явно («не переходит он именно соседу по цепочке»), поэтому не блокирующая;
но документы должны назвать владельца — хэндл источника, как для
`cancellable: false` в группе.

**Замер:**
```
$ cd packages/async_job && dart run .artifacts/review/probe_wording.dart
4 chain, tail cancelled while waiting, source refuses: source=Done(db) tail=Cancelled(manual) callbackRan=false closed=[] [Job(source) handed its value over: 1 conditional cleanup dropped]
```

**Вердикт: принята, исправлено в документах.** Раздел «Chains»
и перевод дописаны: `discard` источника — наоборот, он не выполнялся
и не выполнится, а получатель — само продолжение, и регистрирует оно в своём
теле. Случай без получателя назван прямо: продолжение, отменённое в ожидании,
своего колбэка не зовёт, и ресурс закрывает вызывающий через хэндл
источника — как у ветки, отвергающей остановку группы.

## 6. Вставка `traceDroppedCleanups` разорвала дартдок `finish` и добавила публичный член без `@protected`

**Тяжесть:** существенная.

Метод вставлен внутрь дартдока `finish`: текст `finish` обрывается
на «...is in the debug», продолжается абзацем про `traceDroppedCleanups`,
а самому `finish` достаётся дартдок `/// trace.`. `JobBase` экспортируется,
так что это видно в API-справке. Сам `traceDroppedCleanups` — публичный,
без `@protected` и без подчёркивания, при том что класс обещает «Everything
the engine of that domain needs is protected», а `_RunAllGroup` живёт в той
же библиотеке и достал бы и приватный. `CHANGELOG` называет строку,
но не новый публичный член. `dart analyze` этого не ловит.

**Замер:**
```
$ cd packages/async_job && sed -n 745,749p lib/src/job_base.dart; sed -n 757p lib/src/job_base.dart; sed -n 767,769p lib/src/job_base.dart
  /// body opened stays open. Cancel with [cancelWith] instead, and let the
  /// body unwind; how many cleanups were left behind is in the debug
  /// Says what went nowhere when the value of this job went to somebody.
  ///
  /// Said out loud because the silence is the whole trouble. A conditional
  void traceDroppedCleanups() {
  /// trace.
  @protected
  void finish(Outcome<T> outcome) {
```

**Вердикт: принята, исправлено.** Дартдок `finish` собран обратно —
вставка уехала ниже, и «how many cleanups were left behind is in the debug
trace» снова одно предложение. Член стал приватным (`_traceDroppedCleanups`):
`job_context.dart` — часть той же библиотеки, поэтому публичным он не нужен
был вовсе, и никакого прироста публичного API у работы теперь нет.

## 7. Строка говорит «handed its value over» там, где значения нет или его никто не взял

**Тяжесть:** мелочь.

`Job<void>` с `onDiscard` кончается `Done(null)` — строка сообщает
о переданном значении. Корневое задание, чей `value` никто не читал, —
то же. Счёт верен, событие (запись отброшена) настоящее, формулировка —
нет: `doc/cleanup.md` говорит «names every hand-over», а передачи здесь
не было. Читатель, который придёт по строке к правилу «регистрируйте
у получателя», получателя не найдёт.

**Замер:**
```
$ cd packages/async_job && dart run .artifacts/review/probe_wording.dart
1 Job<void> with onDiscard: [Job(void) handed its value over: 1 conditional cleanup dropped]
2 a root nobody reads: closed=[] [Job(root) handed its value over: 1 conditional cleanup dropped]
```

**Вердикт: принята наполовину.** Слова «handed its value over»
оставлены: это словарь самого контракта — `discard` выполняется, «если
значение никому не досталось», — и переписать их значило бы развести трассу
с дартдоком `onDiscard`. Ловушка при этом настоящая и теперь названа там же,
где живёт правило: задание, которое ничего не возвращает, всё равно отдаёт
своё ничто, поэтому `discard` на нём не выполнится никогда, и для такого
ресурса член — `onDispose`. Вторая половина находки, про враньё
на пути «движок кончил руками», закрыта правкой из находки 4.

## 8. Главное обещание документа — без сторожа в дереве

**Тяжесть:** мелочь.

Пример `doc/cleanup.md` обещает, что с рецептом падение миграции закрывает
базу, и что ветка `ctx.runAll`, получившая ресурс от своего ребёнка,
закрывает его до возврата из группы. В дереве на это нет ни одного теста:
новый тест `cleanup_test.dart` сторожит только путь отмены с `cancellable:
false`, `debug_test.dart` — строки. Замеры отчёта лежат в `.artifacts/`
под `.gitignore` и в клон не приехали. Зонд подтверждает оба обещания,
но сторож должен стоять в `test/`.

**Замер:**
```
$ cd packages/async_job && grep -rln "run(connect\|run(opener" test/
test/debug_test.dart
$ dart run .artifacts/review/probe_recipe.dart
2 recipe, migrationFails=true cancelDuringMigration=false: ready=Failed(Bad state: migration) root=Failed(Bad state: migration) closed=[ready:db]
3 group, sibling fails after the branch got its value: branch=Cancelled(sibling) opener=Done(db) closed at catch=[branch:db] closed now=[branch:db]
```

**Вердикт: принята, закрыто двумя тестами.** Главный пример документа
теперь под сторожем в `cleanup_test.dart` — получатель, зарегистрировавший
базу по прибытии, закрывает её при падении миграции, один раз. Обещание про
группу — в `run_all_test.dart`: ветка, получившая ресурс от своего ребёнка
и зарегистрировавшая его по прибытии, закрывает его до того, как группа
вернула ошибку.

## Что проверено и не найдено

**Документы на счастливых входах** (`probe_recipe.dart`): без рецепта
падение миграции оставляет базу открытой (`closed=[]`); с рецептом
падение и отмена во время миграции закрывают её один раз (`[ready:db]`);
успех отдаёт нетронутой (`closed=[]`) и даёт две строки — `connect`
и `ready`; строка `connect` приходит независимо от того, зарегистрировал ли
`ready`; хэндл `connect.value` после закрытия по-прежнему отдаёт `db` («две
дороги»); ветка группы, зарегистрировавшая по получении, закрывает
до `catch` родителя. Формат строки совпадает с процитированным
в `doc/cleanup.md`, переводе и `CHANGELOG`.

**Переводы:** `python3 tool/check_translations.py` — «no differences»
по всем парам; новые абзацы `cleanup.md` и `children.md` прочитаны рядом
с оригиналами — говорят то же, включая неточность из находки 3.
`tool/reflow.py --check`, `tool/check_line_width.py`, `dart format
--set-exit-if-changed lib test` — чисто.

**Строка на группе:** после фиксации ветка получает строку из `_commit`;
мутация M2 (группа не называет) роняет ровно тест ветки. Счёт: `disown`
и функция-отписка снимают запись из обоих списков, в счёт не попадают.

**Приёмка — мутации, все кусаются** (`mutate.py`, откат копией `.orig`,
после прогона `git status lib` чист):

```
== M1 _execute does not trace
   FAIL test/debug_test.dart: a job that hands its value over says what it dropped
   FAIL test/debug_test.dart: the line counts them, and a job that keeps them gets no line
== M2 _commit does not trace
   FAIL test/debug_test.dart: a branch of a group says it too, once the group has committed
== M3 _race drops a late value
   FAIL test/cleanup_test.dart: a receiver registers through wait, and the next line is too late
== M4 the parent does not wait for children
   FAIL test/cleanup_test.dart: children run before the cleanup, and the outcome waits for it
   FAIL test/parallel_wait_test.dart: invariance guards eagerError wakes the body early and ends nothing early
== M5 the count is off by one
   FAIL test/debug_test.dart: a branch of a group says it too, once the group has committed
   FAIL test/debug_test.dart: a job that hands its value over says what it dropped
   FAIL test/debug_test.dart: the line counts them, and a job that keeps them gets no line
== M6 the cascade cannot be refused
   FAIL test/cleanup_test.dart: a receiver registers through wait, and the next line is too late
restored: clean
```

Заметка без находки: утверждение `lastChild?.outcome` is `Done('db')`
из `58cbb9b` при M6 до исполнения не дошло — тест упал на предыдущем
`expect`. Мутации, которую ловило бы только оно, я не нашёл; на сломанном
коде оно не проходит, просто сторожит после других.

**Цепочка при отмене хвоста, когда источник принимает отмену:** источник
кончается `Cancelled(chain)` до открытия ресурса, закрывать нечего
(`probe_wording.dart`, вход 3). Ложной строки нет.

**Собственный `emit` ребёнка в `solo`,** выводящий состояние из `keepWhile`
родителя: ребёнок кончается `Cancelled(parent)` и закрывает сам,
`closed=[child:db]`. Течёт только внешняя смена состояния (находка 1).

**Наблюдатель, отменяющий родителя на `onFinish` ребёнка, при рецепте через
`wait`** (A и D) — не течёт на этом дереве; но только по счёту хопов, и через
`join` (F) тот же триггер течёт. Опираться на это нельзя.
