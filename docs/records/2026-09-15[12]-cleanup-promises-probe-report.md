> **Состояние на 2026-09-15:** сделано, смержено. **Что это:** отчёт о второй
> части задания ревьюеру — пять обещаний документов, проверенных зондами;
> два обещания оказались написаны шире, чем держатся, и документы поправлены,
> одно взято под сторожа. **Связанные записи:**
> 2026-09-15[8]-cleanup-registers-on-arrival-report.md,
> 2026-09-15[9]-cleanup-registers-on-arrival-work-review.md.

# Пять обещаний, проверенных зондами

Задание ревьюеру состояло из двух частей: мутации (часть 1, прогнал Fable)
и обещания документов, которые никто не сторожит (часть 2). Часть 2 осталась
за мной и сделана здесь. Зонды лежат
в `packages/async_job/.artifacts/promises/` — каталог под `.gitignore`, поэтому
ниже приводится не только вывод, но и то, какой вход его породил.

Запускались из каталога пакета: `dart run .artifacts/promises/<имя>.dart`.
Из других мест `package:async_job` не разрешается.

## 1. «Регистрация решается исходом того задания, которое её сделало»

`doc/cleanup.md`: «A conditional registration is settled by the outcome of the
job that made it, and by nothing else.» Зонд прогоняет семь входов: обычный
успех, отмена, провал, конец руками посреди размотки, ветка группы, чей сосед
упал, конец руками с готовым значением и ребёнок, отвергший остановку.

```text
1 done                     outcome=Done<Res> value=yes res=open
2 cancelled                outcome=Cancelled value=no res=closed
3 failed                   outcome=Failed value=no res=closed
4 by hand, mid-unwind      outcome=Cancelled value=no res=open
5 branch, group failed     outcome=Cancelled value=no res=closed
6 by hand, Done            outcome=Done<Res> value=yes res=open
7 refused the stop         outcome=Done<Res> value=yes res=open
```

**Держится**, но с границей, которую стоит знать. Строка 4 — единственная, где
исход `Cancelled`, а условная регистрация не выполнилась: движок домена кончил
задание руками из его же `onDispose`, размотка пошла дальше по локальному
исходу (`Done`), и регистрация под этим обработчиком легла в отложенные
навсегда. Формально обещание не нарушено — регистрацию не решил никто, —
но вывод «кончилось не значением, значит `discard` выполнился» на этом входе
ломается.

Границу называет дартдок `JobBase.finish`, и называет верно: «Ending a job that
is still running is not a way to cancel it: this waits for no children and
unwinds no cleanup stack, so everything the body opened stays open.» В `solo`
этот вход недостижим: все восемь мест, где движок зовёт `_drop`, кончают
задания, которые ещё не стартовали (`started: false`). Достижим он у любого
другого движка домена, и туда же смотрит строка канала отладки `left aside`
из пункта 3. Правку `cleanup.md` не делал: страница написана для автора тела,
а у тела такого входа нет.

## 2. «Канал отладки называет каждую передачу»

`doc/cleanup.md`: «The debug channel names every hand-over, whether or not the
receiver registered anything». Проверялись обе половины плюс три соседних
случая.

```text
a receiver that registers:
  Job(opener-a) handed its value over: 1 conditional cleanup dropped
  Job(receiver-a) handed its value over: 1 conditional cleanup dropped
a receiver that registers nothing:
  Job(opener-b) handed its value over: 1 conditional cleanup dropped
a giver with no registration:
  (no line)
a branch of a group:
  Job(branch-d) handed its value over: 1 conditional cleanup dropped
a chain:
  Job(source-e) handed its value over: 1 conditional cleanup dropped
```

**Названная половина держится**: строка приходит и когда получатель
зарегистрировал ресурс, и когда не зарегистрировал ничего. Не держится
неназванная: передача, на которой отдающему нечего было отбрасывать, не даёт
строки вовсе — `_traceDroppedCleanups` выходит на пустом списке. «Every
hand-over» обещает больше, чем есть, а обещать этого и не нужно: строка о том,
что отброшено, и на пустой передаче ей нечего сказать.

Исправлено в обоих языках: «names every hand-over **that drops a
registration**», «называет каждую передачу, **на которой что-то отброшено**».

## 3. Строка про конец руками посреди размотки

Дартдок `_traceDroppedCleanups` обещает, что на этом пути строка называет
исход, как он стоит на самом деле, и говорит `left aside`, а не `handed over`.
Зонд строит оба входа рядом — обычную передачу и конец руками:

```text
Job(plain) handed its value over: 1 conditional cleanup dropped
Job(engine) finished with 1 cleanups pending
Job(engine) was finished as Cancelled(handler: by hand) with 1 conditional cleanup left aside
outcome as it stands: Cancelled(handler: by hand)
```

**Держится.** Попутно зонд стоил лишнего круга и дал правило, которое стоит
записать: `done` завершается внутри `finish`, а `finish` в этом сценарии зовут
из обработчика посреди размотки — то есть `await job.done` возвращает раньше,
чем размотка дочитает стек и выдаст строку. Первый прогон зонда печатал до неё
и показывал «строки нет». Читать состояние после конца руками можно только дав
прогону осесть.

## 4. `eagerError` и значения успешных веток

`doc/children.md` обещает три вещи: задание всё равно кончается вместе
с последней веткой; `Future.wait` теряет значения успевших веток, и ресурс
среди них не закрывает никто; `.wait` их сохраняет
в `ParallelWaitError.values`.

```text
1 body woke at 27ms, the last branch ended at 127ms, the job ended at 128ms
2 after Future.wait: res=open, branch=Done(open), through the handle: true
3 after .wait: res=closed
```

**Все три держатся.** Тело проснулось на 27 мс (первая ветка упала на 20),
задание кончилось на 128 мс — через миллисекунду после последней ветки,
а не вместе с первой ошибкой. После `Future.wait` ресурс остался открытым
и дошёл только через хэндл ветки; после `.wait` тело достало его из конверта
и закрыло.

Сторож у этого обещания уже есть — `test/parallel_wait_test.dart`, «eagerError
moves when the body wakes, and nothing else»: он гоняет все три формы и сверяет
и момент пробуждения, и закрытое. Зонд это подтвердил, нового сторожа не нужно.

## 5. Цепочка без получателя

`doc/children.md` про `discard` источника: «a continuation cancelled while it
waited finishes without ever calling its callback, so there is no body and no
moment», и ресурс тогда закрывает вызывающий через хэндл источника. Зонд
прогоняет три источника: обычный, `cancellable: false` и такой, чью отмену
роняют в его же хук завершения.

```text
a cancellable source: source=Cancelled(chain) tail=Cancelled(manual) callback=false res=closed handle=no: Cancelled(chain)
a source that refuses: source=Done(open) tail=Cancelled(manual) callback=false res=open handle=yes
cancelled at the finish hook: source=Done(open) tail=Cancelled(manual) callback=false res=open handle=yes
```

**Не держится в самом частом случае.** Отмена продолжения отменяет и источник —
это сказано двумя абзацами выше, — и обычный источник забирает отмену с собой:
его собственный `discard` выполняется, ресурс закрыт, а хэндл не отдаёт ничего,
кроме `Cancelled(chain)`. Закрывать вызывающему в этом случае нечего. Открытым
ресурс остаётся только там, где источник всё равно кончается `Done`:
`cancellable: false` или конец, уже наступивший к приходу запроса.

Исправлено в обоих языках: абзац теперь называет развилку прямо — источник,
забравший отмену с собой, по пути закрыл то, что взял; отвергший её кончается
`Done` всё равно, и вот тогда ресурс у вызывающего.

Обещание взято под сторожа: `test/then_test.dart`, «what a cancelled chain
leaves open depends on the source» — обе половины в одном тесте. Мутации:
не передавать отмену источнику (`job_then.dart`) и снять `valueHandedOver`
(`job_base.dart`) — каждая краснит этот тест.

## Числа

`async_job` — 383 теста (было 382), анализ чист, формат не меняет ничего.
Проверки документов — `reflow --check`, ширина, переводы, форма — зелёные.
