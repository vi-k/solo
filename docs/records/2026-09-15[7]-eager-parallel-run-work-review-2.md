> **Состояние на 2026-09-15:** разобрано, вердикты проставлены. Два пробела
> приёмки закрыты коммитом `6ca88db`; остальное — подтверждение либо названная
> граница.
> **Что это:** узкое ревью того же круга: `agy` (`gemini-3.8-flash-high`),
> двенадцать мутаций и три вопроса живучести. Проза ревьюера не тронута,
> вердикт по каждому пункту добавлен отдельным абзацем.
> **Связанные записи:** спека
> `2026-09-14[10]-eager-parallel-run-design.md`, отчёт о проходе
> `2026-09-15[2]-eager-parallel-run-report.md`, полное ревью того же круга —
> `2026-09-15[6]-eager-parallel-run-work-review.md`.

# Ревью координатора `runAll` (коммит 4def576)

## Таблица мутаций

| № | Файл и место | Мутация | Результат тестов / точная строка ошибки |
|---|---|---|---|
| 1 | `packages/async_job/lib/src/job_context.dart:967` | Замена `Set<Job<T>>.identity()` на обычный `Set<Job<T>>` (`<Job<T>>{}`) при дедупликации входного списка дочерних задач | Покраснел тест:<br>`00:00 +4 -1: the same child twice is refused before anything starts [E]` |
| 2 | `packages/async_job/lib/src/job_context.dart:1509-1517` | Перестановка шагов в `_commit`: вызов `_letPastSecondBarrier` до `branch.job._skipped.clear()` | Не покраснел ни один |
| 3 | `packages/async_job/lib/src/job_context.dart:1451` | Удаление `_ctx.check();` перед `_commit()` в `_settle()` | Покраснели тесты:<br>`00:00 +14 -1: the group checks the parent before it commits, and reads again [E]`<br>`00:00 +18 -2: a branch is held before it unwinds, and let go on every path [E]` |
| 4 | `packages/async_job/lib/src/job_context.dart:1455` | Удаление `_rereadBranches();` перед `_commit()` в `_settle()` | Покраснели тесты:<br>`00:00 +14 -1: the group checks the parent before it commits, and reads again [E]`<br>`00:00 +19 -2: the second barrier catches what the first one would have missed [E]` |
| 5 | `packages/async_job/lib/src/job_context.dart:1329` | В фильтре собственных отмен в `_sawTrouble` замена проверки тождества `identical(outcome, branch.requested)` на проверку типа `(outcome is Cancelled && outcome.reason is SiblingCancelReason)` | Не покраснел ни один |
| 6 | `packages/async_job/lib/src/job_context.dart:1562-1567` | В `_chooseOutcome()` предпочтение отмены (`Cancelled`) отказу (`Failed`) при выборе итогового исхода | Покраснел тест:<br>`00:00 +5 -1: a real failure beats a cancellation, whenever it arrives [E]` |
| 7 | `packages/async_job/lib/src/job_context.dart:1566` | В `_chooseOutcome()` выбор последней пришедшей отмены вместо первой (`cancelled = outcome` вместо `cancelled ??= outcome`) | Не покраснел ни один |
| 8 | `packages/async_job/lib/src/job_context.dart:1345` | В `_beginFailing` удаление условия `identical(branch, source)` (отправка отмены источнику ошибки тоже) | Покраснели тесты:<br>`00:00 +7 -1: the cancellation that comes out names the branch it came from [E]`<br>`00:00 +16 -2: the decision of the group is what runs the conditional cleanup [E]`<br>`00:00 +16 -3: a group inside a branch of a group stops both levels [E]` |
| 9 | `packages/async_job/lib/src/job_context.dart:1371` | В `_beginFailing` пропуск вызова `_letPastSecondBarrier(branch, committed: false)` на аварийном пути | Покраснели 17 тестов, включая:<br>`00:00 +6 -9: the group checks the parent before it commits, and reads again [E]` |
| 10 | `packages/async_job/lib/src/job_base.dart:1036-1037` | В `valueHandedOver()` удаление ветки `_committedByGroup` (`valueHandedOver() => (_pendingCancel ?? outcome) is Done<T>;`) | Покраснели 6 тестов, включая:<br>`00:00 +13 -1: the cancellation of the parent wins over the group [E]`<br>`00:00 +17 -5: what a branch registers while it waits follows the verdict [E]` |
| 11 | `packages/async_job/lib/src/job_context.dart:1326` | В `_sawTrouble` сужение проверки `outcome is Done<Object?>` до `outcome is Done<T>` конкретного типа группы | Не покраснел ни один |
| 12 | `packages/async_job/lib/src/job_context.dart:962` | Запуск первого дочернего элемента до снятия снимка `List.of(children)` и проверки повторов | Покраснели 22 теста, включая:<br>`00:00 +0 -1: the list is read once, by copy, before the first start [E]` |

**Вердикт по таблице: принята целиком, ни одна строка не оспорена.** Восемь
покрасневших мутаций перепроверены выборочно и совпали. Четыре непокрасневшие
разобраны ниже поимённо.

## Разбор непокрасневших мутаций

### Мутация 2: Перестановка шагов 4 и 5 в `_commit`

- **Что изменено:** в методе `_commit()` цикл
  `_letPastSecondBarrier(branch, committed: true)` запущен перед циклом
  `branch.job._skipped.clear()`.
- **Наблюдаемое поведение:** поведение **не меняется вовсе**, код строго
  избыточен относительно порядка.
- **Причина:** метод `_commit()` выполняется полностью синхронно в рамках
  одного тика событийного цикла (микротаски). `branch.pastSecondBarrier`
  является стандартным асинхронным `Completer<bool>()`, поэтому его
  `complete(true)` лишь ставит возобновление ветки в очередь микротасок
  и не выполняет код веток синхронно. К моменту, когда ветка возобновляется
  после барьера в `JobBase._execute`, цикл очистки `_skipped` уже завершён.
  Более того, в `JobBase._execute` при `_committedByGroup == true` предикат
  `valueHandedOver()` возвращает `true`, из-за чего цикл вызова `_skipped`
  вообще не запускается, а в конце фазы `_skipped.clear()` вызывается
  безусловно.
- **Зонд:** `packages/async_job/.probe/probe_commit_order.dart` ```bash cd
  packages/async_job && dart run .probe/probe_commit_order.dart
  # Вывод: PROBE_OK: behavior intact, closed=false
```


**Вердикт: принята как подтверждение, правки не требует.** Это ровно то, что я
записал в отчёте `2026-09-15[2]-eager-parallel-run-report.md`: шаг четвёртый
фиксации ненаблюдаем, пока вердикт односторонен. Второй ревьюер пришёл
к тому же выводу тем же способом. Шаг оставлен — он в спеке и стоит трёх строк,
— а окно закрывает вердикт, и это проверяет мутация «решать
по `_pendingCancel`, а не по вердикту».

### Мутация 5: Фильтрация собственных отмен по типу `SiblingCancelReason` вместо тождества в `_sawTrouble`

- **Что изменено:** в `_sawTrouble` проверка
  `identical(outcome, branch.requested)` заменена
  на `outcome is Cancelled && outcome.reason is SiblingCancelReason`.
- **Наблюдаемое поведение:** меняется критическое поведение: если ветка
  завершилась отменой с причиной `SiblingCancelReason`, пришедшей из внешнего
  источника (например, отмена группы более высокого уровня или внутренней
  доменной координации), координатор ошибочно считает её *собственной*
  остановкой (`branch.requested`) и игнорирует («Not trouble: the stop
  working»). В результате `_beginFailing` **не вызывается**, и соседние ветки
  **не останавливаются**!
- **Причина пропуска тестами:** в существующих тестах (в частности
  `a cancellation this call asked for never comes out of it`) внешняя отмена
  ветки инициируется с кастомным `TestCancelReason('outside')`, поэтому
  в тестах тип причины никогда не совпадает с `SiblingCancelReason`.
- **Зонд:** `packages/async_job/.probe/probe_saw_trouble_type.dart` ```bash
  # На чистом коде:
dart run .probe/probe_saw_trouble_type.dart
  # Вывод: PROBE_B_STOPPED: true (сосед b остановлен)

  # На мутированном коде:
dart run .probe/probe_saw_trouble_type.dart
  # Вывод: PROBE_B_STOPPED: false (сосед b НЕ остановлен!)
```


**Вердикт: принята, пробел закрыт.** Тот же пробел независимо нашёл второй
ревьюер (его находка 4, мутация `filter_by_reason`), и это самое сильное
свидетельство за него. Тест «a cancellation nobody asked for is trouble,
whatever it wears» добавлен в `6ca88db`: чужая отмена с публичной
`SiblingCancelReason` обязана останавливать соседей. Замечание про разбор
причины верно и по сути: `SiblingCancelReason` — публичный тип, построить его
может кто угодно, и узнавать по нему свою остановку нельзя.

### Мутация 7: Выбор последней пришедшей отмены вместо первой (`cancelled = outcome`) в `_chooseOutcome`

- **Что изменено:** в цикле выбора исхода `_chooseOutcome` строка `cancelled ??= outcome;` заменена на `cancelled = outcome;`. При отсутствии ошибок (`Failed`) наружу выбрасывается последняя завершившаяся отмена ветки вместо первой.
- **Наблюдаемое поведение:** нарушается спецификация и контракт: координатор обещает вернуть *первый* пришедший исход среди отмен (`The branches that have finished, in the order the group learned it. Which one came first is what decides between two cancellations.`). При мутации вместо причины первой отменившейся ветки наружу выбрасывается отмена более поздней ветки.
- **Причина пропуска тестами:** тест `the first outcome to arrive wins, whatever the list order` проверяет гонку только между исходами `Failed` (`errors = {'a': StateError('a'), 'b': StateError('b')}`). Для `Failed` в цикле стоит немедленный `return outcome;`, поэтому гонка отказов покрыта. Гонка нескольких независимых отмен (`Cancelled`) с разными причинами в тестах вообще не проверялась.
- **Зонд:** `packages/async_job/.probe/probe_first_cancellation_wins.dart`
  ```bash
  # На чистом коде:
dart run .probe/probe_first_cancellation_wins.dart
  # Вывод: PROBE_OK: first cancellation (A) won

  # На мутированном коде:
dart run .probe/probe_first_cancellation_wins.dart
  # Вывод: PROBE_FAIL: unexpected outcome thrown: Cancelled(cancel-B) (expected reasonA)
```


**Вердикт: принята, пробел закрыт — но тест пришлось переписать.** Гонка
нескольких отмен действительно не проверялась. Первый вариант теста опирался
на прежний фильтр по тождеству; после решения владельца о фильтре по ветке (см.
`2026-09-15[6]-eager-parallel-run-work-review.md`, находка 2) вход стал другим:
две ветки кончают руками движка на втором барьере подряд, ни одну группа
остановить не просила, и выигрывает та, чей исход она узнала первой. Тест стоит
в обоих порядках; мутация `cancelled = outcome` его краснит.

### Мутация 11: Проверка `outcome is Done<T>` вместо `outcome is Done<Object?>` в `_sawTrouble`

- **Что изменено:**
  в `_sawTrouble(_GroupBranch<T> branch, Outcome<Object?> outcome)` проверка
  `outcome is Done<Object?>` заменена на `outcome is Done<T>`.
- **Наблюдаемое поведение:** поведение **не меняется вовсе**, код полностью
  эквивалентен (избыточен).
- **Причина:** в классе `_RunAllGroup<T>` все дочерние ветки типизированы как
  `JobBase<T>`. В Dart дженерик-класс `Done<E>` ковариантен по `E`. Любой
  успешный результат выполнения задачи `JobBase<T>` представляет собой
  `Done<T>` (или `Done<S>`, где `S extends T`). Следовательно, проверка
  `outcome is Done<Object?>` и `outcome is Done<T>` для исхода ветки
  `JobBase<T>` в Dart дают строго одинаковый логический результат. Тип
  `Outcome<Object?>` в сигнатуре `_sawTrouble` и замыкания `bodyEnded` был
  использован лишь во избежание лишней типизации структуры `_GroupHold`.
- **Зонд:** `packages/async_job/.probe/probe_saw_trouble_done.dart` ```bash cd
  packages/async_job && dart run .probe/probe_saw_trouble_done.dart
  # Вывод: PROBE_OK: polymorphic Done branches handled cleanly: done
```


**Вердикт: принята как разбор, изменений не вношу.** Вывод об эквивалентности
верен: ветка группы — `JobBase<T>`, и оба теста дают один результат.
`Done<Object?>` остаётся потому, что подпись шва не типизирована по `T`
нарочно: удержание живёт на ветке, а не на группе. Замена ничего не улучшает
и ничего не ломает.

## Ответы на вопросы живучести

### Вопрос 1: Может ли ветка остаться на барьере навсегда — то есть `runAll` никогда не вернётся?

**Ответ: ДА, в двух из четырёх исследованных случаев координатор зависает
навсегда и `runAll` никогда не возвращается.**

1. **Ветка отвергает отмену (`cancellable: false`) и висит в теле:** -
   **Результат:** `runAll` **зависает навсегда**. - **Механика:** при ошибке
   соседней ветки координатор переходит в фазу `_failing = true`
   и в `_settle()` ожидает завершения абсолютно всех веток
   (`while (_received.length < _branches.length)`). Ветка, отклонившая отмену
   и зависшая в теле, никогда не завершит выполнение тела, не дойдёт до барьера
   и не вызовет `finish()`. Координатор будет бесконечно ждать завершения этой
   ветки.
2. **Доменный `cancelWith` бросает исключение:** - **Результат:** координатор
   **НЕ зависает** и корректно выходит с выбросом этой ошибки. - **Механика:**
   в методе `_beginFailing` вызов `branch.job.cancelWith(cancelled)` обёрнут
   в блок `try/catch`. Выброшенное исключение перехватывается
   (`_ownError ??= (error, stackTrace);`), после чего цикл безусловно
   освобождает все ветки на первом и втором барьерах (`_letPastFirstBarrier`,
   `_letPastSecondBarrier`). Метод `_conclude()` выбрасывает `_ownError`.
3. **Ветка кончается по руке движка прямо на барьере:** - **Результат:**
   координатор **НЕ зависает** и корректно завершается. - **Механика:**
   в `JobBase._execute` барьеры защищены проверкой
   `if (isFinished) { _disposing = false; return; }`. Метод `finish()`
   завершает `done`, что синхронно регистрирует ветку в `_received` и будит
   координатор через `_wake()`. Предикаты готовности барьеров
   `_everyBranchIsAtFirstBarrier` и `_everyBranchIsAtSecondBarrier` проверяют
   `branch.job.isFinished`. Координатор завершает работу без зависания.
4. **Ребёнок ветки не кончается:** - **Результат:** `runAll` **зависает
   навсегда**. - **Механика:** в `JobBase._execute` ожидание детей ветки
   `await _awaitChildren()` происходит *до* входа на первый барьер
   (`hold.beforeDisposal()`). Если ребёнок не завершается, сама ветка никогда
   не завершит шаг ожидания детей, не придёт на барьер и никогда не завершится
   (`isFinished == false`). Координатор в `_settle()` зависает на цикле
   `while (_received.length < _branches.length)`.

**Зонд:** `packages/async_job/.probe/probe_q1_liveness.dart`
```bash
cd packages/async_job && dart run .probe/probe_q1_liveness.dart
```
**Вывод зонда:**
```
=== QUESTION 1 PROBES ===
Case 1.1 (cancellable: false and hangs in body): runAll returned=false (hangs forever: true)
Case 1.2 (cancelWith throws): runAll returned=true, thrown=Bad state: domain cancelWith explosion
Case 1.3 (branch ended by engine at barrier): runAll returned=true, thrown=Cancelled(handler: dropped-at-barrier)
Case 1.4 (child of branch does not end): runAll returned=false (hangs forever: true)
```

---


**Вердикт: принята как разбор; случаи 1 и 4 дефектами не считаю.** Случаи 2 и 3
подтверждают правку — она для того и делалась. Случаи 1 и 4 — договор,
а не дефект, и оба воспроизводятся без всякой группы. Ветка
с `cancellable: false`, зависшая в теле, останавливает `ctx.run` точно так же:
спека говорит прямо, что такую ветку группа дожидается, «как дождалось бы
и ядро». Незаканчивающийся ребёнок ветки держит `_awaitChildren` — это ядро,
и до первого барьера дело не доходит вовсе. Группа не вводит таймаута
и не обещает его; сформулировано это в dartdoc `runAll` через кооперативность
остановки. Второй ревьюер пришёл к тому же: «непрерываемые действия без
разрешения их барьера по контракту могут удерживать группу бессрочно; таймаут
это ревью не приписывает реализации».

### Вопрос 2: Может ли `runAll` вернуть значения, когда хоть одна ветка ещё не дошла до конца тела?

**Ответ: НЕТ, `runAll` ни при каких условиях не может вернуть значения
до завершения тел всех веток.**

- **Механика:** 1. В `JobBase._execute` тело ветки выполняется через
  `await execute(ctx)`. Флаг `_bodyEnded = true` выставляется строго после
  завершения `execute`. Первый барьер `hold.beforeDisposal()` вызывается строго
  после завершения тела и ожидания потомков (`_awaitChildren()`). 2.
  Координатор в `_settle()` ожидает готовности барьеров в два строгих этапа: -
  `while (!_failing && !_everyBranchIsAtFirstBarrier()) await
  _somethingChanges();` — пока все ветки не дойдут до первого барьера (или
  не завершатся), ни одна ветка не пропускается дальше. - `while (!_failing &&
  !_everyBranchIsAtSecondBarrier()) await _somethingChanges();` — ожидание
  достижения всеми ветками второго барьера. 3. Только после прохождения обоих
  барьеров всеми ветками синхронно вызывается `_commit()`, который собирает
  значения и возвращает их вызывающему. Если хоть одна ветка ещё находится
  внутри своего тела, она не дошла до первого барьера,
  и `_everyBranchIsAtFirstBarrier()` вернёт `false`.

**Зонд:** `packages/async_job/.probe/probe_q2_values_before_body_ended.dart`
```bash
cd packages/async_job && dart run .probe/probe_q2_values_before_body_ended.dart
```
**Вывод зонда:**
```
=== QUESTION 2 PROBE ===
runAll returned values: [1, 2, 3]
All branch bodies ended at return: true
Any branch still active in body at return: false
ANSWER Q2: NO, runAll CANNOT return values before every branch body ends.
```

---


**Вердикт: принята как подтверждение.** Разбор верен и совпадает с приёмкой:
это же свойство проверяет критерий 20 в тесте «a branch is held before it
unwinds, and let go on every path», а мутация «не удерживать успешную ветку»
его краснит.

### Вопрос 3: Может ли группа вернуться, оставив ресурс ветки незакрытым, при том что наружу вышла ошибка? Ресурс берётся так: `ctx.wait(() async => resource, discard: (r) => closes++)`.

**Ответ: ДА, может.**

- **Условие воспроизведения:** когда одна ветка создана с `cancellable: false` и берёт ресурс через `ctx.wait(..., discard: ...)`, а соседняя ветка падает с ошибкой.
- **Механика утечки:**
  1. Соседняя ветка падает. Координатор вызывает `_beginFailing`, устанавливает `_failing = true` и шлёт отмену `cancelWith` остальным веткам.
  2. Ветка с ресурсом была создана с `cancellable: false`, поэтому она **отклоняет** запрос на отмену от координатора (`_pendingCancel` остаётся `null`).
  3. Ветка успешно завершает своё тело с результатом `Done(value)`.
  4. При раскрутке стека очистки в `JobBase._execute` проверяется предикат:
     ```dart
     bool valueHandedOver() =>
         _committedByGroup || (_pendingCancel ?? outcome) is Done<T>;
     ```
     Поскольку ветка завершилась исходом `Done`, а отмена была отклонена (`_pendingCancel == null`), `valueHandedOver()` возвращает `true` (ядро считает, что ветка передаст значение через `branch.value`).
  5. Из-за `valueHandedOver() == true` регистрация `discard` отправляется в `_skipped` и **не выполняется**.
  6. Координатор в `_conclude()` выбрасывает ошибку упавшего соседа. Вызывающий код получает ошибку из `runAll`, значение ветки никем не читается, а `discard` не был вызван. Ресурс остаётся открытым (`closes == 0`).

**Зонд:** `packages/async_job/.probe/probe_q3_unclosed_resource.dart`
```bash
cd packages/async_job && dart run .probe/probe_q3_unclosed_resource.dart
```
**Вывод зонда:**
```
=== QUESTION 3 PROBE ===
Scenario 3.1 (normal cancellable): thrown=Bad state: b failed, closes=1
Scenario 3.2 (cancellable: false): thrown=Bad state: b failed, closes=0, branchA.outcome=Done(123)
ANSWER Q3: YES! When branch is cancellable: false, it ends Done, group throws error from sibling, and discard is NEVER called (closes==0)!
Scenario 3.3 (discard throws): thrown=Bad state: b failed, closes=1
```

---


**Вердикт: принята как разбор; дефектом это не является, но документ был
неправ.** Механика описана точно, и сценарий 3.2 — это критерий 15, вход «г»,
названный спекой границей, а не дефектом: ветка кончается `Done(resource)`
и отдаёт ресурс через свой `value`, то есть закрыть его может вызывающий через
тот же хэндл, который сам и передал. Приёмка этот вход держит отдельным входом
того же теста. Неверным было обещание документа — и это независимо нашёл второй
ревьюер (его находка 5). `doc/children.md`, перевод и dartdoc `onDiscard`
исправлены в `6ca88db`: гарантия ограничена веткой, принявшей остановку, и обе
оставшиеся открытыми вещи названы прямо.

## Что я выполнил

1. Проведено исследование кодовой базы `packages/async_job`
   (`job_context.dart`, `job_base.dart`) и приёмочных тестов
   (`packages/async_job/test/run_all_test.dart`,
   `packages/solo/test/run_all_test.dart`).
2. Сформулировано и последовательно проверено 12 мутаций ядра и координатора: -
   8 мутаций привели к покраснению тестов (зафиксированы точные строки упавших
   тестов). - 4 мутации не вызвали падения ни одного теста в обоих пакетах: 2
   из них выявили пробелы в приёмке (проверены доказательными зондами), 2
   выявили избыточность кода.
3. Разработаны автономные зонды в `packages/async_job/.probe/` для всех
   непокрасневших мутаций и для всех трёх вопросов живучести.
4. Выполнены полные прогоны анализатора и тестовых наборов обоих пакетов
   в чистом репозитории:

```bash
cd packages/async_job && dart analyze && dart test
```
Точные последние строки вывода:
```
00:01 +367: All tests passed!
```

```bash
cd packages/solo && dart analyze && dart test
```
Точные последние строки вывода:
```
00:02 +563: All tests passed!
```


## Вердикт по итогу ревью

Из двенадцати мутаций восемь покраснели, четыре нет; из четырёх две оказались
настоящими пробелами приёмки и закрыты, две — разбором избыточности кода.
Из трёх вопросов живучести один подтвердил правку, один подтвердил свойство,
один описал названную спекой границу и попутно вывел на неверное обещание
в документах.

Дерево владельца после прогона не тронуто: `git status --short` показывал
только чужую параллельную работу. Клон удержал исполнителя — третий раз подряд,
считая замеры 2026-09-12.

Узкое задание себя оправдало: полное ревью спеки этот исполнитель дважды
не доводил до отчёта, а здесь уложился в 20 минут и дал две находки, одна
из которых совпала с находкой второго ревьюера.
