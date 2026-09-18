> **Состояние на 2026-09-14:** тот же первый круг ревью спеки
> `2026-09-14[10]-eager-parallel-run-design.md`, второй ревьюер — Codex
> (`gpt-6-astra:xhigh`). Здесь его **второй проход**, с прогонами:
> двенадцать находок, одиннадцать подтверждены выполненными сценариями, одну
> он опроверг сам и написал об этом. Вердикт: не годится для плана.
> **Почему проходов два:** первый кончился без единого выполненного прогона —
> я не открыл песочнице `~/fvm`, решив по отсутствию `.fvmrc` в репозитории,
> что проект идёт мимо FVM, тогда как `which dart` даёт
> `/Users/user/fvm/default/bin/dart`. Ревьюер назвал отказы дословно и честно
> пометил все находки гипотезами. Тот статический отчёт сохранён
> в `.artifacts/2026-09-14-eager-run-review/codex-static/review.md`, урок
> записан в скилл `codex`.
> **Что это:** отчёт как он выдан, без заливки переносов; мой вердикт стоит
> отдельным абзацем после его собственного, проза находок не тронута.
> **Связанные записи:** спека — `2026-09-14[10]-eager-parallel-run-design.md`;
> первый ревьюер круга — `2026-09-14[11]-eager-parallel-run-review.md`;
> соседняя работа — `2026-09-14[4]-parallel-wait-cancellation-design.md`.

# Ревью спеки `2026-09-14[10]-eager-parallel-run-design.md`: второй проход

## Вердикт

**Не годится для плана:** прогоны подтвердили расхождения обещаний спеки
с поведением прототипа и текущего ядра. Ошибка тела может задержаться
за потомками, настоящий отказ теряется на пути отказа приёма, а приоритет
списка для двух ошибок из одной микрозадачи не работает.

Номера сохранены из `/private/tmp/7f2a1c-out/review.md`. Находки 1–9, 11 и 12
подтверждены воспроизведёнными сценариями. **В находке 10 опровергнуто моё
утверждение, что работающие дети участвуют в поиске дубликатов `droppable`.**
Её утверждения о доменном приёме и диагностике подтвердились. Не считаю находку
10 целиком подтверждённой и не сохраняю ошибочный довод ради счёта. Среди
перечисленных находок нет случая, оставшегося гипотезой из-за невозможности
запуска; границы остальных проверок названы отдельно.

Все четыре ранее подготовленных запускаемых файла скомпилировались без
исправлений и завершились кодом 0. `mutant.dart` скомпилировался как
импортируемая библиотека; собственного `main` у него нет. Дополнительный зонд
сначала получил мою ошибку компиляции, затем был исправлен и выполнен:
`CHECKS 59 FAILURES 0`. Это число проверок диагностического зонда, не число
пакетных тестов и не приёмка ещё отсутствующего `ctx.runAll`.

Пакетные наборы: **341 / 526 / 9**, все зелёные. Для соблюдения запрета
на запись вне `probe/` они запущены в побайтовых копиях пакетов под
`packages/async_job/probe/test_workspace/packages/`. В исходных каталогах
`solo` и его примера нет `.dart_tool/package_config.json`; обычный запуск
создал бы там служебные файлы. Фактические рабочие каталоги приведены
в «ПРОГОН». Оверрайды сохранены, `solo` и пример проверялись против копии
текущего ядра, а не опубликованного `async_job`.

Публичного `ctx.runAll` в дереве нет. Проверен предоставленный временный
прототип и явно названные мутации внутри `probe/`. Реализацию пакетов,
существующие тесты, handoff и старый отчёт не правил. Коммитов и других
запрещённых git-операций не выполнял.

## Находки

### 1. `Job.deferred` не превращает прекращение ожидания в остановку работы

**Важность:** блокирует план

**Что не так:** Оборачивание голого Future не останавливает саму операцию.
В сценарии `physical/bare` группа ждёт таймер и запись происходит.
В `physical/wait` группа уже завершилась отказом, но таймер всё равно позже
совершает запись. Только вариант с передачей отмены таймеру через `onCancel`
и ожиданием через `join` предотвращает запись. Это контрпример к обещанию
раздела «Чего не делаем» и к использованию последней строки тела как
доказательства физической остановки операции.

**Доказательство:** точный вывод выполненных сценариев ниже.

```text
CASE physical/bare
beforeTimer parent=null slow=null write=false
afterTimer parent=Failed(Bad state: first) slow=Cancelled(sibling) write=true
zone=[]
```

```text
CASE physical/wait
beforeTimer parent=Failed(Bad state: first) slow=Cancelled(sibling) write=false
afterTimer parent=Failed(Bad state: first) slow=Cancelled(sibling) write=true
zone=[]
```

```text
CASE physical/join-abort
beforeTimer parent=Failed(Bad state: first) slow=Cancelled(sibling) write=false
afterTimer parent=Failed(Bad state: first) slow=Cancelled(sibling) write=false
zone=[]
```

**Что предлагаю:** Обещать кооперативный запрос отмены. Отдельно назвать
поддержку отмены внешней операцией, конец тела и завершение уборки.

**Вердикт:** **подтверждена прогоном**.

**Вердикт: принято.** Обещание «завернул голый `Future` в `Job.deferred` —
и его можно остановить» будет сужено: комбинатор просит ветку свернуться,
а остановится ли сама операция, решает ветка — через `onCancel` и `join`.
Критерий 5 получит вторую половину: флаг в конце тела доказывает, что тело
кончилось, и ничего не говорит о побочном эффекте, который оно оставило.

### 2. Первая ошибка тела может вообще не добраться до комбинатора

**Важность:** блокирует план

**Что не так:** `packages/async_job/lib/src/job_base.dart:932` ждёт потомков
до выдачи исхода; `job_context.dart:893` ждёт `child.value`. Ветка уже бросила
`StateError`, наблюдатель его получил, но Future от `ctx.run` ещё
не завершилась. Прототип не получает эту ошибку и не отменяет соседа.
Освобождение потомка запускает оставшуюся цепочку. Воспроизведённое
незавершённое ожидание управляется барьером; бесконечность не измерялась
таймером. Без внешнего освобождения этого барьера в сценарии нет события,
которое позволило бы обнаружить отказ через `ctx.run`.

**Доказательство:** точный вывод выполненных сценариев ниже.

```text
CASE failed-branch-waits-for-descendant
beforeRelease bodyThrew=true parent=null branch=null otherCancelled=false
afterRelease parent=Failed(Bad state: branch-body) other=Cancelled(sibling)
zone=[]
```

```text
CASE descendant/direct-ctx-run
beforeRelease bodyErrorObserved=true branchFinished=false childRunning=true runSettled=false parentFinished=false
afterRelease runSettled=true parent=Failed(Bad state: branch-body)
zone=[]
```

**Что предлагаю:** Определить первую ошибку как результат завершённого ребёнка
и назвать ограничение либо выбрать другой сигнал обнаружения броска тела.

**Вердикт:** **подтверждена прогоном**.

**Вердикт: принято, блокирует, и это меняет не спеку, а механизм.**
Проверил своим зондом: ветка упала на 20-й мс, а `runAll` узнал об этом
на 311-й, потому что у ветки жил собственный ребёнок на 300 мс; сосед на 400 мс
всё это время работал. Отсюда закрывается и вопрос 2 из спеки — не вкусом,
а механикой: расширение поверх публичного API не может дать ранний выход
вовсе, потому что раннего сигнала в публичном API нет. Правило будет
определять первую ошибку как исход **тела** ветки.

### 3. Обещание сохранить все ошибки не определяет границу наблюдения

**Важность:** блокирует план

**Что не так:** Поздний настоящий отказ внутри уже отменённого `ctx.join`
остаётся уведомлением самого ребёнка. С наблюдателем его слышит `slow`, без
наблюдателя он не попадает в зону. Итог ребёнка в обоих случаях —
`Cancelled(sibling)`, и по Future от `ctx.run` восстановить отказ нельзя.
Контрольный `ctx.wait` ведёт себя иначе: у оставленной операции поздняя ошибка
без наблюдателя доходит до зоны. Обобщать результат `join` на `wait` было бы
ошибкой; прошлый отчёт различал эти пути.

При внешней отмене родителя во время сворачивания первая ошибка группы тоже
может уступить уже принятой отмене. Это действующее правило
`_pendingCancel ?? outcome`, сохранённое
в `2026-09-14[4]-parallel-wait-cancellation-design.md`; новый комбинатор поверх
публичных Future не даёт более сильной гарантии автоматически.

**Доказательство:** точный вывод выполненных сценариев ниже.

```text
CASE late-internal-error/join/observer=false
beforeLate parent=null slowCancelled=true
afterLate parent=Cancelled(handler: child bad: Cancelled(handler: first)) slow=Cancelled(sibling) lateInZone=false reportedBy=[]
zone=[]
```

```text
CASE late-internal-error/join/observer=true
beforeLate parent=null slowCancelled=true
afterLate parent=Cancelled(handler: child bad: Cancelled(handler: first)) slow=Cancelled(sibling) lateInZone=false reportedBy=[slow]
zone=[]
```

```text
CASE late-internal-error/wait/observer=false
beforeLate parent=Cancelled(handler: child bad: Cancelled(handler: first)) slowCancelled=true
afterLate parent=Cancelled(handler: child bad: Cancelled(handler: first)) slow=Cancelled(sibling) lateInZone=true reportedBy=[]
zone=[Bad state: late-internal]
```

```text
CASE late-internal-error/wait/observer=true
beforeLate parent=Cancelled(handler: child bad: Cancelled(handler: first)) slowCancelled=true
afterLate parent=Cancelled(handler: child bad: Cancelled(handler: first)) slow=Cancelled(sibling) lateInZone=false reportedBy=[slow]
zone=[]
```

```text
CASE parent-cancel-during-drain
parent=Cancelled(manual) firstErrorInZone=false
zone=[]
```

**Что предлагаю:** Ограничить гарантию ошибками, полученными комбинатором,
и назвать маршруты внутреннего отказа после принятой отмены.

**Вердикт:** **подтверждена прогоном**.

**Вердикт: принято.** Обещание «ни одна ошибка не теряется» сужается
до «ни одна ошибка, которую получил сам комбинатор». Поздний отказ внутри уже
отменённой ветки — её собственная диагностика, и `runAll` его не видит;
разница между `join` и `wait` в прогоне видна и будет названа.

### 4. Обезвреживание завершителя при отказе приёма может съесть настоящий отказ

**Важность:** править до плана

**Что не так:** Первый ребёнок синхронно бросает заранее созданный настоящий
отказ и отвергает отмену. Второй не принимается, потому что стартует сам.
Наружу выходит отказ приёма, а первый отказ ребёнка остаётся в `first`, который
гасится через `catchError`. В `late_` этот отказ не попадает. У наблюдателя
остаётся сообщение `first`, пересказа от родителя нет; без наблюдателя ошибка
не слышна нигде. Исход ребёнка проверен отдельно: это `Failed`, а не отмена.

Контрольная мутация отключает только гашение завершителя. Тогда тот же объект
настоящей ошибки появляется в зоне ровно один раз; при включённом гашении
исчезает. Это устанавливает причинную связь, а не только тишину журнала. Речь
о коде прототипа, `probe_race.dart:57–63,93–97`.

**Доказательство:** точный вывод выполненных сценариев ниже.

```text
CASE admission-first-error/observer=false
parent=Failed(Invalid argument (child): starts itself; a child is made with Job.deferred: Instance of '_AutoJob<int>') child=Failed(Bad state: earlier-child-failure) lostInZone=false reportedBy=[]
zone=[]
```

```text
CASE admission-first-error/observer=true
parent=Failed(Invalid argument (child): starts itself; a child is made with Job.deferred: Instance of '_AutoJob<int>') child=Failed(Bad state: earlier-child-failure) lostInZone=false reportedBy=[first]
zone=[]
```

```text
CASE admission/real-error/silence=false
admissionWon=true realErrorInZone=1 child=Failed(Bad state: earlier-child-failure)
zone=[Bad state: earlier-child-failure]
```

```text
CASE admission/real-error/silence=true
admissionWon=true realErrorInZone=0 child=Failed(Bad state: earlier-child-failure)
zone=[]
```

**Что предлагаю:** Учесть настоящий отказ уже принятого ребёнка на пути отказа
приёма; добавить этот вход к критерию 9 вместе с обычным случаем отмены.

**Вердикт:** **подтверждена прогоном**.

**Вердикт: принято.** Мутация показала причинную связь, а не только
тишину: с гашением завершителя настоящий отказ исчезает, без гашения приходит
в зону ровно один раз. Вход идёт в критерий 9 рядом с обычной отменой.

### 5. Общий оборот событий не задаёт общий порядок разных Future

**Важность:** блокирует план

**Что не так:** В одной микрозадаче последовательно завершаются два разных
Future. Побеждает тот, который завершается первым: A при A→B, B при B→A.
Разворот списка детей не меняет победителя в этой управляемой матрице.
Следовательно, утверждение спеки и критерий 13 о приоритете более ранней
позиции неверны для прототипа. Это не универсальное утверждение, что список
никогда ни на что не влияет: порядок синхронных стартов по-прежнему задан
списком.

Ещё один прогон разделяет бросок тела и готовый результат: A бросила первой,
но задержалась в уборке; B завершилась раньше и победила. Во время ожидания
уборки A уже получила отмену.

**Доказательство:** точный вывод выполненных сценариев ниже.

```text
CASE order/listReversed=false/completionReversed=false
winner=a parentFinished=true lateCount=1
zone=[Bad state: b]
```

```text
CASE order/listReversed=false/completionReversed=true
winner=b parentFinished=true lateCount=1
zone=[Bad state: a]
```

```text
CASE order/listReversed=true/completionReversed=false
winner=a parentFinished=true lateCount=1
zone=[Bad state: b]
```

```text
CASE order/listReversed=true/completionReversed=true
winner=b parentFinished=true lateCount=1
zone=[Bad state: a]
```

```text
CASE body-error-versus-finished-error
beforeCleanup parent=null aCancelled=true
winnerIsBodyFirst=false winnerIsFinishedFirst=true
zone=[]
```

**Что предлагаю:** Выбрать первый полученный результат ошибки; если нужен
приоритет списка, отдельно определить окно сбора ошибок и задержку обнаружения.

**Вердикт:** **подтверждена прогоном**.

**Вердикт: принято.** «Первая по времени, а ничья — по порядку списка»
неверно: побеждает тот, чьё будущее завершилось первым, и разворот списка
ничего не меняет. Правило станет «первый полученный результат», без обещания
приоритета позиции; критерий 13 переписывается под это.

### 6. Ожидание соседей меняет доступность тела, а его необходимость обоснована неверно

**Важность:** править до плана

**Что не так:** Полный исход родителя в обоих режимах ждёт неотменяемого
ребёнка, но вход в `catch` различается до освобождения барьера. В `solo` эта
разница меняет даже итог: без ожидания тело успело закончиться и родитель
получает `Done`; с ожиданием тело активно во время изменения состояния
и получает `Cancelled(rules: keepWhile)`. Фраза «не стоит ничего по времени»
скрывает задержку обработки ошибки и продолжение действия правил тела.

Отсутствие пересказа в режиме без ожидания — поведение данного прототипа,
который проходит `late_` раньше появления ошибки. Прогон не доказывает
невозможность поздней диагностики через другие сохранённые обработчики.

**Доказательство:** точный вывод выполненных сценариев ниже.

```text
CASE criterion-10/awaitSiblings=false
beforeRelease caughtInBody=true parentFinished=false
afterRelease caughtInBody=true parent=Failed(Bad state: first)
zone=[]
```

```text
CASE solo-body-lifetime/awaitSiblings=false
beforeChange caught=true parentFinished=false
afterChange parentCancelled=false
parent=Done(null) slow=Done(1)
zone=[]
```

```text
CASE criterion-10/awaitSiblings=true
beforeRelease caughtInBody=false parentFinished=false
afterRelease caughtInBody=true parent=Failed(Bad state: first)
zone=[]
```

```text
CASE solo-body-lifetime/awaitSiblings=true
beforeChange caught=false parentFinished=false
afterChange parentCancelled=true
parent=Cancelled(rules: keepWhile) slow=Done(1)
zone=[]
```

**Что предлагаю:** Обосновать ожидание выбранным контрактом владения, назвать
его цену для catch/finally и правил solo; проверять момент продолжения тела.

**Вердикт:** **подтверждена прогоном**.

**Вердикт: принято.** Сходится с находкой 4 первого ревьюера, и сверх неё
названо то, чего тот не увидел: в `solo` тело считается активным до конца
сворачивания группы, и `keepWhile` может отменить родителя в это окно.

### 7. Три критерия требуют не того результата, который обеспечивает контракт

**Важность:** блокирует план

**Что не так:** **Критерий 2.** Обычный пустой вызов проходит через микрозадачу
вызывающего `await`: `[before, microtask, after]`. Мутация с незаполняемым
завершителем отличается незавершением. В дополнительном зонде она доведена
до `TimeoutException` за одну виртуальную секунду; исправный вариант
завершается без таймаута. Мутация различает завершимость, но не обещание «без
единой микрозадачи»: это буквальное обещание не выполняет уже исходный
прототип. `childCount=-1` у мутации означает, что строка после `await`
не достигнута.

**Доказательство:** точный вывод выполненных сценариев ниже.

```text
CASE criterion-2/stallEmpty=false
afterFlush log=[before, microtask, after] completed=true childCount=0 parentFinished=true
afterDeadline timeout=false parentFinished=true
zone=[]
```

```text
CASE criterion-2/stallEmpty=true
afterFlush log=[before, microtask] completed=false childCount=-1 parentFinished=false
afterDeadline timeout=true parentFinished=true
zone=[]
```

**Критерий 6.** Конверт сохранил все перечисленные наблюдения: итоговую отмену,
`HandlerCancelReason.cause` по тождеству, описание ребёнка, единственный
`whenCancelled`, тишину наблюдателя и зоны. Мутация выживает по указанным
в спеке проверкам. Прямой `catch` вокруг вызова до классификатора ядра
различает её: там уже `ParallelWaitError`, а не отмена ребёнка тем же объектом.

```text
CASE criterion-6/envelope=false
parent=Cancelled(handler: child victim: Cancelled(handler: why)) causeIsChild=true whenCancelled=1 onError=0
zone=[]
```

```text
CASE criterion-6/direct-catch/envelope=false
caughtEnvelope=false caughtSameChild=true causeIsChild=true whenCancelled=1 onError=0
zone=[]
```

```text
CASE criterion-6/envelope=true
parent=Cancelled(handler: child victim: Cancelled(handler: why)) causeIsChild=true whenCancelled=1 onError=0
zone=[]
```

```text
CASE criterion-6/direct-catch/envelope=true
caughtEnvelope=true caughtSameChild=false causeIsChild=true whenCancelled=1 onError=0
zone=[]
```

**Критерий 7.** При снятом фильтре наблюдатель слышит одну лишнюю отмену. Без
наблюдателя зона пуста как с фильтром, так и без него: срабатывает
`JobBase._toZone`. Требование убить мутацию обоими прогонами не выполняется.

```text
CASE criterion-7/filter=false/observer=false
onError=0 zoneCount=0 parentFinished=true
zone=[]
```

```text
CASE criterion-7/filter=false/observer=true
onError=1 zoneCount=0 parentFinished=true
zone=[]
```

```text
CASE criterion-7/filter=true/observer=false
onError=0 zoneCount=0 parentFinished=true
zone=[]
```

```text
CASE criterion-7/filter=true/observer=true
onError=0 zoneCount=0 parentFinished=true
zone=[]
```

**Что предлагаю:** В 2 проверять завершимость; в 6 — объект на границе runAll;
в 7 разделить различающий тест наблюдателя и проверку тишины зоны.

**Вердикт:** **подтверждена прогоном**.

**Вердикт: принято.** Критерии 2, 6 и 7 переписываются. По шестому
отдельно: ловить ошибку надо прямо вокруг `await runAll`, до классификатора
`_execute`, иначе мутация «завернуть в конверт» не различима — разбор конверта
уже стоит в ядре и сам даст тот же исход.

### 8. У списка и контекста нет полного контракта допустимых входов

**Важность:** править до плана

**Что не так:** Пустой вызов обходит проверки жизненного цикла, которые
получает непустой через `ctx.run`: это воспроизведено в `unattended`, после
конца тела, после полного завершения и после принятой отмены. Повторный ребёнок
вызывает отказ второго старта и отменяет уже запущенный первый.

Гипотеза об изменяемом списке тоже воспроизвелась: синхронное тело первого
ребёнка добавляет второго. Оба ребёнка завершились, в зоне `RangeError`,
а родитель не завершён. В обработчике результата обращение за границы `values`
не даёт дойти до `settle`; незавершённый `pending` больше некому уменьшить. Это
наблюдение после исчерпания микрозадач, без реального бесконечного ожидания
процесса.

**Доказательство:** точный вывод выполненных сценариев ниже.

```text
CASE duplicate-child
parent=Failed(Bad state: Job(slow) is already running) child=Cancelled(sibling)
zone=[]
```

```text
CASE list-mutated-during-synchronous-start
parentFinished=false listLength=2 childrenFinished=true
zone=[RangeError (index): Invalid value: Only valid value is 0: 1]
```

```text
CASE from-unattended/empty=false
returned=false childRunning=false errors=[Bad state: Job() cannot run a child inside unattended work]
zone=[]
```

```text
CASE after-job-finish/empty=false
returned=false rejected=Bad state: Job() has already finished, cannot run a child childRunning=false
zone=[]
```

```text
CASE after-body-before-finish/empty=false
parentFinished=false returned=false rejected=Bad state: Job() has ended its body, cannot run a child
zone=[]
```

```text
CASE already-cancelled-parent/empty=false
returned=false rejectedIsAccepted=true child=Cancelled(parent)
zone=[]
```

```text
CASE from-unattended/empty=true
returned=true childRunning=false errors=[]
zone=[]
```

```text
CASE after-job-finish/empty=true
returned=true rejected=null childRunning=false
zone=[]
```

```text
CASE after-body-before-finish/empty=true
parentFinished=false returned=true rejected=null
zone=[]
```

```text
CASE already-cancelled-parent/empty=true
returned=true rejectedIsAccepted=false child=null
zone=[]
```

**Что предлагаю:** Определить проверки пустой группы, повторные хэндлы и снимок
списка перед синхронными стартами.

**Вердикт:** **подтверждена прогоном**.

**Вердикт: принято.** Список снимается копией до первого старта, повтор
ребёнка отвергается там же, а пустая группа проходит те же проверки контекста,
что и непустая. Замечание про изменяемый `List` — то, чего не нашёл никто,
кроме этого прохода.

### 9. `dispose` не закрывает вопрос передачи ресурса из успешной группы

**Важность:** править до плана

**Что не так:** Ветка действительно возвращает объект с `closed` и счётчиком
закрытий. На полном успехе проверены два перехода по тождеству: результат
ребёнка и список, полученный внешним вызывающим от родителя. Через `dispose`
наружу приходит уже закрытый ресурс; через `discard` — живой. При отказе соседа
список не выдаётся; `dispose` закрывает ресурс ровно один раз, `discard`
не закрывает ни разу.

Это подтверждает границу, которую автор уже назвал для неуспешной группы,
и дополнительную проблему универсального совета применять `dispose`: так нельзя
передать живой ресурс даже при успехе. Это вопрос владения нового API,
а не дефект существующего контракта `dispose`.

**Доказательство:** точный вывод выполненных сценариев ниже.

```text
CASE returned-resource/dispose=false/failure=false
childReturnedSame=true callerReceivedSame=true closedAtDelivery=false closed=false closes=0
zone=[]
```

```text
CASE returned-resource/dispose=false/failure=true
childReturnedSame=true callerReceivedSame=false closedAtDelivery=null closed=false closes=0
zone=[]
```

```text
CASE returned-resource/dispose=true/failure=false
childReturnedSame=true callerReceivedSame=true closedAtDelivery=true closed=true closes=1
zone=[]
```

```text
CASE returned-resource/dispose=true/failure=true
childReturnedSame=true callerReceivedSame=false closedAtDelivery=null closed=true closes=1
zone=[]
```

Старые ресурсные зонды тоже запущены. `probe_res.dart` по-прежнему проверяет
`[...].wait`, а не `runAll`. В O из `probe_race.dart` напечатано
`ветки: a=null, b=Failed(Exception: boom)`: `show` смотрит исходный список,
в то время как тело подменило первого ребёнка. Там возвращается `1`, а открытая
строка остаётся внутри тела. Эти ограничения старого доказательства прогон
не снял; новый зонд проверяет именно возврат объекта.

**Что предлагаю:** Определить передачу владения успешными результатами и их
уборку при неуспехе группы либо ограничить поддержанные возвращаемые значения.

**Вердикт:** **подтверждена прогоном**.

**Вердикт: принято.** Сходится с находкой 1 первого ревьюера и добавляет
к ней замер по тождеству: на полном успехе вызывающий получает **тот же**
объект уже закрытым (`closedAtDelivery=true`), а через `discard` при отказе
соседа не закрывает никто (`closes=0`). `cleanUp` входит в член.

### 10. Наследование в `solo` не сохраняет без уточнений обещания о приёме и диагностике

**Важность:** прежний вывод о политиках снять; ограничения приёма уточнить

**Что не так:** В прошлом отчёте я написал: «уже работающие дети участвуют
в поиске дубликатов при `add`». **Это утверждение неверно.** При двух
работающих детях с одинаковым ключом `add(..., policy: Policy.droppable)`
вернул новый хэндл и поставил его в очередь. После завершения родителя новый
хэндл выполнился с `Done(3)`. Повторное чтение кода подтверждает прогон:
`packages/solo/lib/src/solo_base.dart:537–544` ищет в очереди, затем проверяет
текущую корневую задачу; коллекцию работающих детей не обходит.

**Доказательство:** точный вывод выполненных сценариев ниже.

```text
CASE solo-policy-same-key-and-droppable
bothRunning=true reused=false fresh=null
foundIsFresh=true freshQueued=true freshFinished=false
parent=Done(null) freshAfterRelease=Done(3)
zone=[]
```

Две другие части прежней находки подтвердились: чужое и обычное ядровое задание
отвергаются доменным приёмом; стоящее в очереди задание нельзя усыновить; отказ
`canStart` даёт отмену. Публичный `SoloObserver` без `SoloBase.errorHandler`
не поглощает позднюю диагностику: отказ слышен и ему, и зоне. Эти требования
к новому пути остаются, но ошибочную историю про `droppable` из обоснования
нужно убрать.

```text
CASE solo-admission/core
parent=Failed(Invalid argument (job): was not created by this Solo: Instance of '_DeferredJob<int>') child=null
zone=[]
```

```text
CASE solo-admission/foreign
parent=Failed(Invalid argument (job): was not created by this Solo: Instance of '_SoloJob<int, int, int>') child=null
zone=[]
```

```text
CASE solo-admission/queued
parent=Failed(Bad state: Job() is queued and cannot be run as a child) child=null
zone=[]
```

```text
CASE solo-admission/rules
parent=Cancelled(handler: child null: Cancelled(rules: canStart)) child=Cancelled(rules: canStart)
zone=[]
```

```text
CASE solo-observer-does-not-replace-error-handler
observer=[slow, parent] lateInZone=true
zone=[Bad state: late]
```

**Что предлагаю:** Убрать утверждение об участии детей в поиске droppable.
Сохранить только проверенные ограничения доменного приёма и маршрута
диагностики.

**Вердикт:** **опровергнута прогоном** в части участия детей в поиске

**Вердикт: принято вместе с его собственной поправкой.** Опровержение
своего же довода прогоном — ровно то, чего ждёшь от второго прохода; счёт
находок за это не держат. Остаток находки — доменный приём и отдельный маршрут
`errorHandler` в `solo` — принят.
дубликатов; части о приёме и диагностике подтверждены приведёнными прогонами.

### 11. `Future.wait` не может стереть уже состоявшееся уведомление ребёнка

**Важность:** править до плана

**Что не так:** После первой ошибки поздний отказ второго ребёнка действительно
услышал унаследованный наблюдатель, с ключом `late-child`. `Future.wait`
не передал его в итог родителя, но не отменил вызов `onError` самим ребёнком.
Следовательно, утверждение о том, что остальных ошибок не увидит даже
наблюдатель, неверно для приведённого в спеке случая с `ctx.run`.

**Доказательство:** точный вывод выполненных сценариев ниже.

```text
CASE future-wait-does-not-erase-child-observer
parent=Failed(Bad state: first) lateReportedBy=[late-child]
zone=[]
```

**Что предлагаю:** Разделить результат Future.wait, уведомление ребёнка
и пересказ от родителя; уточнить этим же различием критерий 17.

**Вердикт:** **подтверждена прогоном**.

**Вердикт: принято.** В разделе «Первая попытка» фраза «ни наблюдатель,
ни зона» смешивает результат комбинатора с диагностикой самого ребёнка.
Будет разведено: `Future.wait` глотает поздний результат своего будущего
и не отменяет уже случившегося `onError` ребёнка.

### 12. Гейт требует тестировать Flutter-пример без тестового каталога

**Важность:** править до плана

**Что не так:** В копии Flutter-примера, сделанной без добавления тестов,
реально выполнен `rtk proxy flutter test --no-pub`. Команда закончилась кодом 1
на отсутствии каталога `test`. `--no-pub` исключает подготовку зависимостей;
не создаёт тесты и не исправляет отсутствующий вход гейта. Это ошибка команды
гейта, не отказ песочницы. Полный flutter-набор в этом проходе не запускался.

**Доказательство:** точный вывод выполненных сценариев ниже.

```text
Test directory "test" not found.
```

**Что предлагаю:** Задать для примера анализ/сборку либо включить создание
содержательных тестов в объём работы.

**Вердикт:** **подтверждена прогоном**.

**Вердикт: принято.** Сходится с пунктом 9.2 первого ревьюера:
у примера `flutter_solo` есть анализ и нет тестов.

## Разбор всех 20 критериев

Ниже различаются прогоны прототипа и полноценная приёмка будущего члена.
Мутаций `packages/*/lib` не было; ещё отсутствующие тесты спеки не объявляю
пройденными или упавшими.

| № | Что установлено этим проходом |
|---|---|
| 1 | L дал `[1, 1]`; это не доказательство порядка разных успешных значений. Мутацию порядка результатов не выполнял. |
| 2 | Исправный пустой вызов проходит через микрозадачу. Незаполняемый завершитель различим завершимостью и виртуальным таймаутом. |
| 3 | Прямой отказ `runAll` и одиночного `ctx.run` на одном входе отдельным тестом по тождеству не сравнивал. |
| 4 | Отказ и отмена соседа воспроизведены. У причины в прототипе нет `cause`; обещанную тройку error/stack/cause целиком не проверял. |
| 5 | Тело с `ctx.wait` заканчивается отменой, но оставленная операция совершает запись после группы. Остановка операции требует отдельного подтверждения. |
| 6 | Мутация конверта сохраняет все перечисленные результаты; прямой catch её различает. |
| 7 | Снятие фильтра различает только наблюдатель; зона пуста в обоих вариантах. |
| 8 | F/H показывают пересказ позднего Failed; join после принятой отмены даёт более узкую гарантию. |
| 9 | Без гашения завершителя отмена уходит в зону; с гашением настоящий первый отказ может пропасть. Обе пары выполнены. |
| 10 | При снятом ожидании catch наступает раньше, parent.done всё равно ждёт. В solo меняется даже итог. |
| 11 | M дал принятую отмену родителя и отмены детей с тишиной диагностики. Мутацию приоритета каскада не выполнял. |
| 12 | N дал отмену внешне отменённой ветки через handler и отмену соседа через sibling. Мутацию проверки владения не выполнял. |
| 13 | Во всех четырёх комбинациях списка/завершения побеждает первая завершившаяся ошибка. Мутацию обратной регистрации обработчиков отдельно не выполнял. |
| 14 | Объект реально возвращается: через dispose уже закрыт на успехе, через discard открыт на провале. Закрытий 1 либо 0. |
| 15 | Вложенный настоящий отказ сохранил тождество. При отмене каждый уровень получил собственный HandlerCancelReason; обычный потомок без внутреннего runAll задерживает ошибку. |
| 16 | Чистый конверт дал Cancelled с каскадом, смешанный — Failed; мутацию классификатора не выполнял. |
| 17 | Поздний отказ не меняет результат Future.wait, но слышен наблюдателю ребёнка. |
| 18 | Прямое ожидание ребёнка с потомком проверено; полного отдельного сторожа run не добавлял. |
| 19 | В unattended наблюдатель слышит чужую отмену, собственная фильтруется. Мутаций ядра нет. |
| 20 | Существующие наборы 341/526/9 зелёные; исходные тесты и библиотеки побайтово совпали с проверенными копиями. Новые пакетные тесты не добавлены. |

## Восемь замеров и происхождение доказательств

`probe_race.dart` реально запущен один раз в этом проходе. Его измерения ниже —
время до `job.done`, как и в исходном `show`. Это разовый замер, не эталон
миллисекунд и не измерение экономии трафика.

| Замер | В спеке, мс | В этом прогоне, мс |
|---|---:|---:|
| A | 207 | 207 |
| B | 209 | 204 |
| D | 202 | 202 |
| C | 26 | 24 |
| F | 125 | 124 |
| K | 122 | 122 |
| J | 0 | 0 |
| L | 66 | 63 |

«Тело просыпается на 21-й мс» этот зонд не измеряет. Фактический ранний вход
в catch отдельно проверен управляемым барьером в критерии 10. Полные журналы
A–O и ресурса находятся в `probe/logs/probe_race_initial.log`
и `probe/logs/probe_res_initial.log` внутри `packages/async_job`.

## Цена, которую следует назвать

- Результат ошибки ребёнка может ждать потомков и уборки; запрос отмены соседей
  не создаёт физического прерывания внешней операции.
- Ожидание соседей задерживает обработку ошибки в теле и продлевает действие
  `keepWhile` у родителя `solo`.
- При отказе приёма предыдущие старты уже произошли; их ошибки и ресурсы всё
  ещё требуют определённого владельца.
- Ресурс, возвращаемый наружу, требует правил передачи владения и уборки
  успешного результата на неуспешном пути группы.
- Первое наблюдаемое завершение ошибки и первый бросок тела — разные события.
  Порядок списка не разрешает автоматически их гонки.

## Ответы на вопросы владельца

Рекомендации прошлого отчёта в этом проходе не превращаются в разрешение
на реализацию: имя `runAll` можно оставить; член интерфейса или расширение
выбирать после правил жизненного цикла; передачу ресурсов описать явно;
кортежную форму можно отложить. Разделять ли выпуск с уже готовым `0.3.0`, этот
прогон не решает. Действий по реализации или выпуску не было.

## Чего я не проверил

Реального `ctx.runAll` нет, поэтому это проверка прототипа и требований.
Не проверены весь предложенный API причины `SiblingCancelReason.cause`,
минимальный Dart 3.6, полная Flutter-матрица, исключения уборщика при передаче
ресурса, реальные сетевые abort/close и все мутации из 20 критериев. Сайт,
сниппеты и переводы в этом проходе не собирались. Анализ пакетов целиком
не запускался.

Уже подготовленные диагностические сценарии печатают ожидаемые ошибки
в перехваченной зоне. Поэтому один только код 0 этих программ не означает
отсутствия ошибок: значимы приведённые журналы. Новый дополнительный зонд также
проверяет результаты 59 явными проверками и завершился без их отказов.

## ПРОГОН

### Среда и компиляция

Рабочий каталог зондов: `/private/tmp/7f2a1c-cx/packages/async_job`.

Команда `rtk proxy dart --version`, код 0, точная строка:

```text
Dart SDK version: 3.13.0 (stable) (Wed Aug 5 00:28:05 2026 -0700) on "macos_arm64"
```

Следующие команды реально выполнены через `rtk proxy`; первые четыре также
выполнены до дополнительных правок. `probe_race.dart` и `probe_res.dart`
оставлены без изменений. `probe_solo.dart` дополнен печатью состояния нового
хэндла; `mutant.dart` — вариантом незаполняемого завершителя для пустой группы.
После этих изменений повторены зависимые зонды `probe_review.dart`,
`probe_solo.dart` и `probe_confirmation.dart`.

| Точная команда | Код | Точная последняя строка |
|---|---:|---|
| `rtk proxy dart run probe/probe_review.dart` | 0 | `END probe_review` |
| `rtk proxy dart run probe/probe_solo.dart` | 0 | `END probe_solo` |
| `rtk proxy dart run probe/probe_race.dart` | 0 | `   наблюдатель: []   зона: []` |
| `rtk proxy dart run probe/probe_res.dart` | 0 | `   закрыто: [ресурс родителя]` |
| `rtk proxy dart run probe/probe_confirmation.dart` | 0 | `END probe_confirmation` |

Последние две строки окончательного дополнительного прогона:

```text
CHECKS 59 FAILURES 0
END probe_confirmation
```

Первая попытка нового `probe_confirmation.dart`, та же команда, закончилась
**кодом 254**. Это моя ошибка компиляции, не отказ песочницы. Точный полный
вывод:

```text
probe/probe_confirmation.dart:95:30: Error: The getter 'children' isn't defined for the type 'Job<Object?>'.
 - 'Job' is from 'package:async_job/src/job_base.dart' ('lib/src/job_base.dart').
 - 'Object' is from 'dart:core'.
Try correcting the name to the name of an existing getter, or defining a getter or field named 'children'.
        childCount = ctx.job.children.length;
                             ^^^^^^^^
```

Исправление: число стартов детей считаю через `JobObserver.onStart`,
не обращаясь к отсутствующему публичному getter. После исправления
дополнительный зонд выполнен дважды: сначала 57 проверок, затем 59 после
добавления отдельного опыта с `ctx.run` и потомком; оба запуска — код 0.

Команда форматирования, код 0:

```sh
rtk proxy dart format probe/probe_confirmation.dart probe/probe_solo.dart probe/mutant.dart
```

```text
Formatted probe/probe_confirmation.dart
Formatted probe/probe_solo.dart
Formatted probe/mutant.dart
Formatted 3 files (3 changed) in 0.01 seconds.
```

`rtk proxy dart analyze probe/probe_confirmation.dart` выполнена в каталоге
ядра, код 0. Ошибок и предупреждений нет, **есть 27 диагностик уровня info**
по стилю. Чистым анализом это не называю. Последняя строка:

```text
27 issues found.
```

### Пакетные тесты и рабочие каталоги

Подготовка копий из корня:
`rtk proxy python3 -B packages/async_job/probe/prepare_test_copies.py`, код 0.
Копировались существующие файлы, исключены `probe`, `.dart_tool`, `build`
и `.DS_Store`. Точный вывод:

```text
async_job: 47 files copied and byte-verified
solo: 93 files copied and byte-verified
flutter_solo: 28 files copied and byte-verified
```

Команды захватывал `packages/async_job/probe/capture.py`: аргументы и рабочий
каталог сохранены в одноимённых JSON, полный stdout/stderr — в `.log` внутри
`probe/logs`. Скрипт возвращает реальный код дочернего процесса. Ниже указаны
точные дочерние команды, каталоги и последние строки, без фильтрации RTK.

**async_job_pub.** Рабочий каталог:

```text
/private/tmp/7f2a1c-cx/packages/async_job/probe/test_workspace/packages/async_job
```

Команда: `rtk proxy dart pub get --offline`. Код: **0**. Точные последние
строки:

```text
Resolving dependencies...
Downloading packages...
Got dependencies!
```

**solo_pub.** Рабочий каталог:

```text
/private/tmp/7f2a1c-cx/packages/async_job/probe/test_workspace/packages/solo
```

Команда: `rtk proxy dart pub get --offline`. Код: **0**. Точные последние
строки:

```text
Resolving dependencies in `./example`...
Downloading packages...
Got dependencies in `./example`.
```

**solo_example_pub.** Рабочий каталог:

```text
/private/tmp/7f2a1c-cx/packages/async_job/probe/test_workspace/packages/solo/example
```

Команда: `rtk proxy dart pub get --offline`. Код: **0**. Точные последние
строки:

```text
Downloading packages...
! async_job 0.2.0 from path ../../async_job (overridden in ./pubspec_overrides.yaml)
Got dependencies!
```

**async_job_test.** Рабочий каталог:

```text
/private/tmp/7f2a1c-cx/packages/async_job/probe/test_workspace/packages/async_job
```

Команда: `rtk proxy dart test`. Код: **0**. Точные последние строки:

```text
00:00 +339: test/lifecycle_test.dart: the lifecycle hooks bracket the body
00:00 +340: test/lifecycle_test.dart: a job dropped before it started gets finished without started
00:00 +341: All tests passed!
```

**solo_test.** Рабочий каталог:

```text
/private/tmp/7f2a1c-cx/packages/async_job/probe/test_workspace/packages/solo
```

Команда: `rtk proxy dart test`. Код: **0**. Точные последние строки:

```text
00:01 +524: test/queue_test.dart: cancelAll clears the queue and cancels the current job
00:01 +525: test/queue_test.dart: add from inside a body runs after the current job
00:01 +526: All tests passed!
```

**solo_example_test.** Рабочий каталог:

```text
/private/tmp/7f2a1c-cx/packages/async_job/probe/test_workspace/packages/solo/example
```

Команда: `rtk proxy dart test`. Код: **0**. Точные последние строки:

```text
00:00 +7: test/camera_controller_test.dart: a close that fails is not a disposal
00:00 +8: test/camera_controller_test.dart: a first open that fails leaves a state reopen can start from
00:00 +9: All tests passed!
```

**flutter_example_test.** Рабочий каталог:

```text
/private/tmp/7f2a1c-cx/packages/async_job/probe/test_workspace/packages/flutter_solo/example
```

Команда: `rtk proxy flutter test --no-pub`. Код: **1**. Точные последние
строки:

```text
Test directory "test" not found.
```

Пример `solo` разрешался своим pubspec и своим override. После прогонов
проверены SHA-256 исходных файлов и равенство `lib/` и `test/` в копиях.
Результат: изменённых исходных входов 0, различий библиотек и тестов 0 для
каждого из трёх Dart-наборов. Конфигурации зависимостей всех копий указывают
на `async_job` и `solo` внутри `probe/test_workspace`, а не на опубликованные
пакеты. Это результаты тестов неизменённых копий; команду `dart test`
в исходных каталогах не выдаю за выполненную.

### Отказы песочницы

**В этом проходе отказов песочницы не было.** Доступ к FVM позволил дойти
до компиляции и выполнения. Дословные `Operation not permitted` предыдущего
прохода остаются в `/private/tmp/7f2a1c-out/review.md`; не повторяю их как
результат новых запусков.

Код 254 у дополнительного зонда — ошибка обращения к отсутствующему getter. Код
1 у `flutter test --no-pub` — `Test directory "test" not found.`. Ни тот
ни другой не связан с песочницей. Расширенных прав не запрашивал.

### Проверка исходников, отчёта и границ записи

Из корня реально выполнена команда, код 0:

```sh
rtk proxy python3 -B packages/async_job/probe/verify_inputs.py
```

Точный вывод:

```text
Original copied inputs changed: 0
async_job: 32 library/test files byte-identical
async_job: dart test passed=341 exit=0 local_dependencies=true
solo: 63 library/test files byte-identical
solo: dart test passed=526 exit=0 local_dependencies=true
solo/example: 6 library/test files byte-identical
solo/example: dart test passed=9 exit=0 local_dependencies=true
END verify_inputs
```

Из корня также выполнены следующие проверки. У всех код 0:

```text
$ rtk proxy python3 tool/reflow.py --check
every paragraph is filled to 79 columns
$ rtk proxy python3 tool/check_line_width.py
no Markdown line over 79 columns
$ rtk proxy python3 tool/reflow.py /private/tmp/7f2a1c-out/review2.md
/private/tmp/7f2a1c-out/review2.md: refilled
1 files refilled
$ rtk proxy python3 tool/reflow.py --check /private/tmp/7f2a1c-out/review2.md
every paragraph is filled to 79 columns
$ rtk proxy git status --short
?? packages/async_job/probe/
```

`rtk proxy git diff --exit-code` выполнена из корня, код 0, stdout пустой.
Отслеживаемые файлы репозитория не изменены. Все новые файлы стенда, копии
пакетов и журналы лежат внутри разрешённого `packages/async_job/probe/`; новый
отчёт — по явно разрешённому внешнему пути.

Внешнюю ширину проверял отдельной командой из корня:

```sh
rtk proxy python3 -B - <<'CHECK'
from pathlib import Path
import runpy
check=runpy.run_path('tool/check_line_width.py')['offenders']
errors=list(check(Path('/private/tmp/7f2a1c-out/review2.md')))
for line,width,text in errors:
    print(f'{line}: {width} columns: {text}')
print(f'review2.md: {len(errors)} width violations')
raise SystemExit(bool(errors))
CHECK
```

Первая проверка закончилась кодом 1; последняя строка:

```text
review2.md: 5 width violations
```

Пять длинных абсолютных путей рабочих каталогов перенесены в блоки кода. Повтор
той же проверки завершился кодом 0, точная последняя строка:

```text
review2.md: 0 width violations
```

Проверки Markdown проверяют оформление, а не правильность выводов Dart.
