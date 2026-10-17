# Код ядра по второму полному ревью: M1–M4, L5, L10, L11, L13

> **Состояние на 2026-10-17:** сделано в `main` одним коммитом, не отправлено.
> **Что это:** первая из пяти волн правок по второму полному ревью — код ядра,
> восемь находок записи `2026-10-17-async-job-project-review.md`, записи
> `CHANGELOG.md` ядра с переводом.
> **Связанные записи:** `2026-10-17-async-job-project-review.md`,
> `2026-10-17-solo-project-review.md`,
> `2026-09-26-covered-failure-any-job-work-review.md`,
> `2026-09-28-engine-failure-announced-report.md`.

Владелец 2026-10-17 на первый вопрос записей ревью ответил «да, чини всё
с твоими рекомендациями». Правки идут пятью волнами: код ядра, документы ядра,
код `solo` и `flutter_solo`, пример камеры, документы `solo`. Эта запись —
о первой.

## Что сделано

**M1.** `_awaitChild` в `job_context.dart`: если `check()` после возврата
ребёнка бросает — отмена родителя или правило домена, — значение освобождается
на месте через `dispose` или `discard`, и отказ летит дальше, как в `join`.
Раньше значение лежало на стеке условной регистрацией, тело ловило отказ
и кончалось `Done`, и `discard` не бежал никогда. Тест «run registers the value
before the checkpoint that could take it» держал старый порядок и переименован
в «run releases the value when the checkpoint after it refuses»; два новых —
тело, которое поймало отказ и кончилось `Done`, на отмене и на броске правила.
У ветки `runAll` такой щели нет: `discard:` у неё нет, значение ветки закрывает
её собственный стек.

Попутно поменялось, что слышит тело, когда движок кончил задачу руками отменой,
пока шёл `run`: проверка после возврата ребёнка бросает эту отмену, как `join`,
и значение закрыто к тому моменту, как тело её слышит. Раньше `run` бросал
`StateError` о кончившейся задаче, а значение закрывал, не дожидаясь. Тест —
«run on a job an engine ended with a cancellation throws it and releases the
value first». Запись «Fixed» об освобождении такого значения говорила только
о `StateError`; теперь она называет оба ответа.

**M2.** Ключ метки развилки `ctx.unattended` — личный `Object()` задачи
(`_forkKey`), а не сама задача; проверки собраны в геттер `_inOwnFork`. Зона
ищет ключ через `==`, и из двух равных задач с вложенными развилками внутренняя
отвечала за внешнюю. Тест — `KeyedJob` с `==` по ключу: `ctx.uncancellable`
из вложенной развилки бросает `StateError`, задача кончается `Cancelled`.

**M3.** В `cancelWith` строка отладочного канала говорится после пометки:
у бегущей задачи после `_pendingCancel = marked`, у удержанной после
`_heldCancel ??= marked`. Колбэк `Job.debug`, отменивший ту же задачу на этой
строке, теперь опаздывает, как всякая вторая отмена. Удержанную ветку ревью
не называло; у неё та же ошибка порядка, только наоборот: первая отмена
терялась, а исход нёс вторую. Два теста в `debug_test.dart`. У задачи, которая
ещё не стартовала, отмена из канала берёт верх, но слушатели и исход говорят
о ней одной, как и раньше; запись CHANGELOG поэтому говорит о бегущей задаче
и об удержанной отмене, а не о любой.

**M4.** Ветка, чьё значение группа уже отдала, отклоняет любую отмену, пока
разматывается, и каскад родителя тоже, и правила домена. Группа ставит
`_committedByGroup` в шаге, где отдаёт список, а не на втором барьере: ветка
узнаёт вердикт на ход позже, и отмена между двумя моментами успела бы. Из двух
вариантов вердикта взят первый, «ветка отвергает каскад». Тест «a cancellation
from the finish of a sibling comes after the commit and closes nothing» держал
старое поведение — ветка кончалась `Cancelled` — и стал «… and is turned away»
с исходом `Done`. Два новых — под `uncancellable(runAll)` с отменой родителя
и с отменой правилом домена после возврата `runAll`. Фраза `children.md`
с переводом: после передачи списка решение окончательное.

**L5.** Флаг `_failureWentToZone` ставится, когда провал ушёл в зону
по истечении грации. Продолжение `then`, приставленное после этого, несёт
провал и слышит его в `onError`, но в зону его второй раз не шлёт, в том числе
когда наблюдатель отменил продолжение из `onError`. Флаг переходит
к продолжению, и продолжение продолжения тоже молчит, приставлено ли оно
до конца первого или после.

**L10.** Провал тела задачи, которую движок кончил руками своим исходом, идёт
в ответ: `onUnanswered` или зона, с фильтром `Job.isCancellationError`,
и `ignoreFailure()` его глушит. Так же идёт провал тела отменённой задачи.
Исключение — движок подал ту же ошибку: тогда её несёт исход. Ревью называло
только провал после ручного `finish`. Ручной `finish` попадает в процедуру
задачи в любом месте, и ответ стоит на всех четырёх выходах из неё: после
ожидания детей, на первом и на втором барьере группы и в `conclude`, куда
приходит задача, кончённая руками из уборки или пока уборку ждали. Метод
`_answerForHandFinished` один на все четыре.

Ошибку, которую движок подал в `finish` до того, как тело её бросило, `finish`
уже отчитал — поверх пометки или задаче, которая уже кончилась. Тело, бросив
её, ничего нового не приносит: локальная `announcedBefore` запоминает в `catch`
тела, что ошибку объявили раньше, а задача к этому моменту уже кончилась,
и ответа второй раз нет. Без второго условия под него попадал оборванный старт:
первый проход объявляет провал тела, второй бросает его снова на задаче,
которая ещё идёт, и ответить за провал некому, кроме него.

Задачу, которую движок кончил руками, пока разматывалась уборка, `conclude`
в `finish` больше не отдаёт: на кончившейся задаче `finish` отвечал бы
за провал тела как за ошибку, поданную задаче, которая уже кончилась, а ответ
и так стоит в `conclude`.

Три старых сторожа держали дыру: два в `finish_announced_test.dart` и один
в `unanswered_test.dart`. Последний ставили ровно на этот случай: запись
`2026-09-26-covered-failure-any-job-work-review.md`, находка 1, обещала, что он
покраснеет, когда дыру починят, и приведёт к dartdoc. Все три переписаны
на ответ. Dartdoc `finish`, `_reportCovered`, `_handleUnanswered`, `_ignored`,
`Job.ignoreFailure`, `JobObserver.onError` и `JobAnswerer.onUnanswered` и абзац
`docs/architecture.md`, где стояла обратная оговорка, поправлены. Абзац
о `finish` в `doc/extending.md` теперь говорит, куда идёт провал тела задачи,
кончённой руками; перевод — тем же коммитом.

**L11.** `finish` чистит стек уборки, если тот не разматывается: задачу кончили
руками до уборки, и никто его больше не прочтёт. Внутри уборки стек и список
отложенных читает сама процедура уборки, и `conclude` их чистит; вне уборки
отложенных не бывает. Выход второго барьера, где ветку кончили руками, чистит
оба списка сам. Три теста в `retention_test.dart` на настоящем сборщике: ручной
финиш бегущей задачи, ветка, кончившаяся руками, пока разматывалась, и ветка,
кончившаяся руками на втором барьере после регистрации, сделанной там же.

**L13.** Цикл по арностям и позициям кортежа в `parallel_wait_test.dart` стал
отдельным тестом на каждый случай. Случаев 44, а не 72: арность от 2 до 9,
на каждое место кортежа по тесту.

## CHANGELOG

Записи только там, где поведение 0.2.0 меняется; сверено по исходникам тега
`async_job-v0.2.0`.

- M3 — в «Fixed»: в 0.2.0 строка канала тоже стояла до пометки.
- L5 — в «Fixed»: в 0.2.0 продолжение так же слало провал в зону второй раз.
- L11 — в «Fixed»: `finish` 0.2.0 чистил `_onCancel` и слушателей, но не стек
  уборки.
- L10 — в список «Changes you will see on upgrade»: в 0.2.0 тело, упавшее
  у задачи, кончённой руками, слышал один `onError`, а без наблюдателя
  не слышал никто. `ignoreFailure()` в тексте под списком теперь глушит «первые
  два» пункта.
- M1 и M4 — без своей записи: `dispose`/`discard` у `ctx.run` и `runAll`
  появились после 0.2.0. Поправлена чужая: «Fixed» о значении для задачи,
  кончённой руками, говорила, что тело слышит `StateError`, а после M1 `run`,
  как и `join`, бросает отмену, которой задачу кончили. Запись называет теперь
  оба ответа.
- M3 — запись сужена до бегущей задачи и удержанной отмены после ревью волны,
  а после второго круга прошлое в ней названо прошлым: «used to hear»,
  в переводе «раньше … слышали».
- M2 — без новой записи: в «Fixed» уже стоит «Two jobs equal by `==` are no
  longer taken for one another inside work handed to `ctx.unattended`», и это
  её недоделанный случай.

## Проверки

Каждую правку откатывал по одной в отдельной копии дерева — отвязанный worktree
на `ee04d82c` с правками поверх, скрипт `mutate_w1.py` в скретч-каталоге
сессии — и гонял весь набор ядра. У L5, L10 и L11 правка из нескольких частей,
и каждая часть откатывалась ещё и отдельно: `L10-once` — защита от второго
ответа, `L10-children`, `L10-first`, `L10-conclude`, `L10-second` — ответ
на одном из четырёх выходов, `L10-finish-again` — снова `finish` в `conclude`
у задачи, кончённой руками, `L10-torn` — `announcedBefore` без проверки, что
задача кончилась, `L11-second` и `L11-skipped` — по одной очистке на выходе
второго барьера. Откат краснит ровно свои тесты:

```text
== M1: 3 red
    test/cleanup_test.dart: a body that catches a cancellation after run and succeeds still releases
    test/cleanup_test.dart: a body that catches a rule that throws after run and succeeds still releases
    test/cleanup_test.dart: run on a job an engine ended with a cancellation throws it and releases the value first
== M2: 1 red
    test/unattended_boundary_test.dart: a nested fork of an equal job does not lift the ban on a section
== M3: 2 red
    test/debug_test.dart: a cancellation from the channel on the cancel line comes too late
    test/debug_test.dart: so does one on the line of a held cancellation
== M4: 3 red
    test/run_all_test.dart: a branch whose value the group handed over is not cancelled after it
    test/run_all_test.dart: a branch whose value the group handed over refuses a cancellation
    test/run_all_test.dart: a cancellation from the finish of a sibling comes after the commit and is turned away
== L5: 4 red
    test/then_test.dart: a continuation attached after the zone heard the failure does not send it again
    test/then_test.dart: a continuation attached after the zone heard the failure does not send it again, cancelled while hearing it
    test/then_test.dart: nor does a continuation of that continuation, attached after it ended
    test/then_test.dart: nor does a continuation of that continuation, attached before it ended
== L5-chain: 2 red
    test/then_test.dart: nor does a continuation of that continuation, attached after it ended
    test/then_test.dart: nor does a continuation of that continuation, attached before it ended
== L10: 10 red
    test/finish_announced_test.dart: a Failed an engine hands to finish a body that fails after the engine ended the job with a value is answered for
    test/finish_announced_test.dart: a Failed an engine hands to finish over the mark, when the body failed with it first, is not announced again and is answered for once
    test/finish_announced_test.dart: a body that fails after the engine ended the job with another failure is answered for
    test/finish_announced_test.dart: a failed body of a job an engine ends by hand as the stack unwinds from a cleanup is answered for
    test/finish_announced_test.dart: a failed body of a job an engine ends by hand as the stack unwinds while a cleanup is awaited is answered for
    test/finish_announced_test.dart: a failed body of a job an engine ends by hand as the stack unwinds with a failure of its own from a cleanup is answered for once
    test/finish_announced_test.dart: a failed body of a job an engine ends by hand as the stack unwinds with a failure of its own while a cleanup is awaited is answered for once
    test/finish_announced_test.dart: a failed branch an engine ends by hand is answered for once
    test/start_depth_test.dart: a child cut short after its body failed, then ended by hand, answers for that failure
    test/unanswered_test.dart: a failed body waiting when an engine ends its job is answered for
== L10-once: 2 red
    test/finish_announced_test.dart: a Failed an engine hands to finish on a finished job, that the body throws afterwards, is answered for once
    test/finish_announced_test.dart: a Failed an engine hands to finish over the mark, that the body throws afterwards, is answered for once
== L10-children: 5 red
    test/finish_announced_test.dart: a Failed an engine hands to finish a body that fails after the engine ended the job with a value is answered for
    test/finish_announced_test.dart: a Failed an engine hands to finish over the mark, when the body failed with it first, is not announced again and is answered for once
    test/finish_announced_test.dart: a body that fails after the engine ended the job with another failure is answered for
    test/finish_announced_test.dart: a failed branch an engine ends by hand is answered for once
    test/unanswered_test.dart: a failed body waiting when an engine ends its job is answered for
== L10-first: 1 red
    test/finish_announced_test.dart: a failed branch an engine ends by hand is answered for once
== L10-conclude: 5 red
    test/finish_announced_test.dart: a failed body of a job an engine ends by hand as the stack unwinds from a cleanup is answered for
    test/finish_announced_test.dart: a failed body of a job an engine ends by hand as the stack unwinds while a cleanup is awaited is answered for
    test/finish_announced_test.dart: a failed body of a job an engine ends by hand as the stack unwinds with a failure of its own from a cleanup is answered for once
    test/finish_announced_test.dart: a failed body of a job an engine ends by hand as the stack unwinds with a failure of its own while a cleanup is awaited is answered for once
    test/start_depth_test.dart: a child cut short after its body failed, then ended by hand, answers for that failure
== L10-second: 1 red
    test/finish_announced_test.dart: a failed branch an engine ends by hand is answered for once
== L10-finish-again: 2 red
    test/finish_announced_test.dart: a failed body of a job an engine ends by hand as the stack unwinds with a failure of its own from a cleanup is answered for once
    test/finish_announced_test.dart: a failed body of a job an engine ends by hand as the stack unwinds with a failure of its own while a cleanup is awaited is answered for once
== L10-torn: 1 red
    test/start_depth_test.dart: a child cut short after its body failed, then ended by hand, answers for that failure
== L11: 1 red
    test/retention_test.dart: a job finished by hand lets go of the cleanups it never ran
== L11-second: 1 red
    test/retention_test.dart: a branch ended by hand at the second barrier lets go of what it registered there
== L11-skipped: 1 red
    test/retention_test.dart: a branch ended by hand while it unwinds drops what it put aside
```

Тест «a failed branch an engine ends by hand is answered for once» перебирает
по числу микрозадач, через которое движок кончает ветку руками, от нуля
до семи. Ноль и одна попадают на выход после детей, две — на первый барьер,
три — на второй, дальше ветка успевает кончиться своим провалом. Тест требует,
чтобы встретились оба исхода, иначе он ничего не проверяет. Выходы по числам
определены печатью в копии, в дерево печать не попала.

Наборы на дереве с правками: `async_job` — формат и анализ чистые,
`00:15 +1536: All tests passed!`; `solo` — 1945, его пример — 98,
`flutter_solo` — 213, его пример — 4, пример ядра запускается. Проверки
документов — ширина, заливка, ссылки, переводы, форма документов — зелёные,
сайт собран, 56 страниц, его тест и тесты скриптов зелёные. Оба стенда
фрагментов: 27 драйверов, `every quoted trace is what the bench prints`. Линтер
humanizer--ru на изменённых русских абзацах — 0 ошибок.

## Ревью

Первую версию правок смотрел независимый ревьюер на Opus в отдельной копии,
с зондами и мутациями. Подписать её он не смог: восемь находок, все приняты.

1. Medium, регрессия первой версии L10. Ошибку, которую движок подал в `finish`
   поверх пометки или задаче, уже кончившейся, `finish` отчитал, а тело, бросив
   её потом, получало второй ответ: два `onUnanswered`, две ошибки в зоне.
   Проверка «движок подал ту же ошибку» смотрела только в исход. Закрыто
   `announcedBefore`, тесты — два «… that the body throws afterwards, is
   answered for once».
2. Low, L10 неполон: ручной финиш во время уборки — из уборки или пока её
   ждали — оставлял провал тела без ответа, хотя новый dartdoc обещал ответ
   «до этого или после». Закрыто ответом на всех четырёх выходах, тесты —
   группа «a failed body of a job an engine ends by hand as the stack unwinds»
   и развёртка по ветке.
3. Low, L5 неполон: продолжение позднего продолжения слало провал в зону снова.
   Закрыто передачей флага по цепочке, два теста.
4. Low, dartdoc отстал: `JobAnswerer.onUnanswered`, `_handleUnanswered`,
   `_ignored`, `Job.ignoreFailure` не называли новый случай, комментарий
   в `_execute` говорил, что стек остаётся на месте. Поправлено.
5. Low, тесты L11 не держали очистку `_cleanups` на выходе второго барьера,
   строка `_skipped.clear()` в `finish` не исполнялась никогда, имя теста
   обещало второй барьер, а ветку кончали в первом проходе. Строка убрана, тест
   переименован, новый регистрирует уборку на самом барьере.
6. Nit, запись M3 в CHANGELOG обещала опоздание и задаче, которая ещё
   не стартовала, а там отмена из канала берёт верх. Запись сужена.
7. Nit, M1 молча поменял ответ `run` на задаче, кончённой руками отменой:
   отмена вместо `StateError`. Закреплено тестом, запись «Fixed» поправлена.
8. Процесс: итогов в вердиктах, отчёта и handoff не было. Сделаны.

Попутно ревьюер нашёл дефект, которого правки не касаются, и он воспроизводится
на `ee04d82c` без них. Ветка `runAll`, чьё тело упало, а движок потом кончил её
руками `Done`, роняет родителя внутренней ошибкой ядра
`Bad state: Job(p): a group failed with nothing to throw`: группа начала падать
по провалу тела, а к концу не нашла, что бросить. До правки L10 сам провал
ветки при этом не слышал никто, теперь он идёт в ответ ветки. Не исправлен,
вынесен владельцу.

Исправленную версию смотрел второй независимый ревьюер на Opus, тоже в своей
копии, с зондами и мутациями. Находки 1–7 первого круга он подтвердил
закрытыми; других двойных ответов его зонды не нашли — развёртки `runAll`,
`ParallelWaitError`, `ignoreFailure()`, фильтр `Job.isCancellationError`. Своих
находок четыре.

1. Medium, регрессия исправленной версии. Движок кончил задачу руками своим
   провалом Y, пока разматывалась уборка, — из уборки или пока её ждали.
   `conclude` всё равно отдавал провал тела X в `finish`, а тот на кончившейся
   задаче отвечал за X как за ошибку, поданную задаче, которая уже кончилась:
   место объявленной ошибки занимал Y. Следом за X отвечал
   `_answerForHandFinished`, и X дважды приходил в `onUnanswered` и в зону.
   На `ee04d82c` за X отвечал один `finish`, один раз. Закрыто: у задачи,
   кончённой руками, `conclude` не зовёт `finish`, ответ остаётся
   за `_answerForHandFinished`. Тесты — два «with a failure of its own … is
   answered for once» в `finish_announced_test.dart`.
2. Low, оборванный старт. Первый проход объявляет провал тела, второй бросает
   его снова, и `announcedBefore` принимал это за ошибку, поданную движком:
   если уборка второго прохода кончала задачу руками, за провал не отвечал
   никто. Закрыто: `announcedBefore` верен, только если задача к броску уже
   кончилась, а так бывает, лишь когда движок подал ошибку в `finish`. Тест —
   «a child cut short after its body failed, then ended by hand, answers for
   that failure» в `start_depth_test.dart`.
3. Low, граница слота. Движок подаёт задаче X поверх пометки, затем Y задаче,
   которая уже кончилась, затем тело бросает X — X получает два ответа: слот
   объявленной ошибки один и держит последнюю, Y вытеснил X. Второй `onError`
   здесь был и на `ee04d82c`. Так не делает ни один движок: `solo` кончает
   руками только задачи, которые не стартовали. Оставлено границей: слот
   по устройству хранит одну ошибку.
4. Nit, слова. Запись M3 в CHANGELOG читалась так, будто колбэки и сейчас
   слышат чужую причину. Абзац dartdoc `_reportCovered` начинался с «So does»,
   которое не к чему было отнести. Комментарий в `job_then.dart` говорил
   о «той же» зоне, а у продолжения она может быть своя. Абзац о `finish`
   в `doc/extending.md` не говорил, куда идёт провал тела задачи, кончённой
   руками. Всё поправлено, переводы тем же коммитом.

Обе регрессии подтверждены зондами ревьюера на дереве до правки: X дважды
в зоне во всех трёх зондах ручного финиша во время уборки — провал Y из уборки,
`Done` и следом провал Y из уборки, провал Y, пока уборку ждали, — и пустая
зона у оборванного старта. После правки — по одному ответу. Мутанты
`L10-finish-again` и `L10-torn` в таблице выше откатывают эти две правки.
