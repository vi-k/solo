# Ревью сделанного: покрытый провал отвечается у любой задачи

> **Состояние на 2026-09-26:** вердикты записаны: все четыре находки приняты
> и закрыты коммитом следом за `e5e6d20`; не отправлено.
> **Что это:** независимое ревью работы по плану
> `2026-09-25-covered-failure-any-job-plan.md` на Opus, по копии дерева
> на `e5e6d20`: код ядра, dartdoc, страницы и переводы, сторожа, числа
> и мутации отчёта `2026-09-26-covered-failure-any-job-report.md`.
> **Связанные записи:** `2026-09-25-covered-failure-any-job-plan.md`,
> `2026-09-25-covered-failure-any-job-plan-review.md`,
> `2026-09-26-covered-failure-any-job-report.md`,
> `2026-09-25-covered-child-failure-plan.md`,
> `2026-09-25-covered-child-failure-report.md`.

## Итог

Код делает то, что обещают план и вердикты его ревью, и ничего сверх. Двойного
ответа, двойного объявления и потери ошибки я не нашёл ни на одном пути,
который прогнал: корень, ребёнок `each`, продолжение `then`, ребёнок `ctx.run`,
ветка `runAll` — покрытая и невыбранная, — движок, кончающий задачу руками
поверх отметки и пока упавшее первым тело ждёт детей, `cancellable: false`,
секция `uncancellable`, `unattended`. Ошибки вне тела `ignore()` не глушит,
и это держат тесты. Внутренний вызов `Job.ignore()` в ядре один — у ребёнка,
которому отказал `startChild`, — и покрытого провала у такого ребёнка быть
не может; в `solo` и `flutter_solo` внутренних вызовов нет.

Числа отчёта сходятся все: 622, 799, 48, 38, 22, пример `solo` 47,
`flutter_solo` 85. Новые и развёрнутые тесты красные на ядре `c6e5399` поимённо
так, как сказано в отчёте: 14, 3, 1 и 1 в ядре, 4 в `solo`. Десять строк
таблицы мутаций я воспроизвёл с тем же числом красных, одиннадцатую —
с близким, и обе строки `solo` — точно. Ширина, заливка, форма, переводы
и ссылки зелёные.

Находок четыре, все Low. У двух из трёх путей ответа нет сторожа срока
`ignore()` (находка 1). Dartdoc `notifyObserver` и двух соседних мест молчит
о `ignore()` (находка 2). Слова «no outcome carries» о ветке, которую группа
не бросила, неточны, а правка их размножила (находка 3). Шапка прошлого плана
потеряла «не отправлено» (находка 4).

## Находки

1. **Low. Срок `ignore()` держит сторож только на одном из трёх путей ответа,
   а оговорку о задаче, которую движок кончил руками, не держит никто.**

   Суть. Dartdoc `Job.ignore` и запись `CHANGELOG` ядра обещают для любой
   задачи: «Call it before the job ends, or at the latest from
   [JobObserver.onFinish] or a callback of [whenCancelled]». Покрытый провал
   отвечается тремя путями: в `_execute` после `finish`,
   в `_ThenJob._sourceFinished` после `finish` и в конце самого `finish` — для
   провала, поданного движком поверх отметки, после `_notifyFinish`. Сторож
   срока, `zone_test.dart` «ignore from onFinish still silences a covered
   error», проходит только первый путь. Перенос ответа раньше `onFinish`
   на двух других не краснит ни одного теста. Сегодня поведение верное — зонды
   P9 и P10 это показывают, — но держит его только порядок строк.

   Туда же две мелочи. «A callback of [whenCancelled]» верно для колбэка,
   зарегистрированного до конца задачи: зарегистрированный позже зовётся сразу,
   и ответ к тому времени уже ушёл (зонд P7). И оговорка dartdoc
   `_reportCovered` и `docs/architecture.md` — задача, которую движок кончил
   руками, пока упавшее первым тело ждёт детей, слышит один `onError` —
   не держится ни одним тестом: поведение такое (зонд P8), но в `test/` этого
   сценария нет.

   Свидетельство. Мутации `mutate.py` по всему набору `async_job`:

```text
execute-report-before-finish [async_job]: 622 tests, 1 red
    test/zone_test.dart: ignore from onFinish still silences a covered error
then-report-before-finish [async_job]: 622 tests, 0 red
finish-report-before-onfinish [async_job]: 622 tests, 0 red
```

   Зонды `zz_review_probe_test.dart`; строки `onFinish Cancelled(parent)`
   и `onFinish Done(null)` — ребёнок корня, наблюдатель у них общий:

```text
P9 ProbeJob, Failed over the mark, ignore() in onFinish:
    onFinish Cancelled(manual)
    onError: Bad state: by hand
P10 continuation cancelled in onError, ignore() in onFinish:
    onError: Bad state: source
    onFinish Cancelled(manual)
P7 root, whenCancelled registered in a done listener:
    onError: Bad state: body
    onFinish Cancelled(parent)
    onFinish Cancelled(manual)
    onUnanswered: Bad state: body
    zone: Bad state: body
    done listener registers whenCancelled
    whenCancelled -> ignore
P8 ProbeJob body fails first, drop(Cancelled) at 10:
    onError: Bad state: body
    onFinish Cancelled(manual)
    onFinish Done(null)
```

   Предложение. В группу «ignore silences a failure no outcome carries» два
   теста через `expectOnlyTold`: `ignore()` из `onFinish` продолжения, которое
   его наблюдатель отменил из `onError`, и `ignore()` из `onFinish` задачи,
   которой движок подал `Failed` поверх отметки, — один `onError`. Мутации
   «ответ продолжения раньше `finish`» и «ответ за провал движка раньше
   `onFinish`» — в таблицу. В dartdoc `Job.ignore` — «a callback of
   [whenCancelled] registered before it ends», или промолчать о поздней
   регистрации сознательно. Оговорке о задаче, кончённой руками, — тест
   с `ProbeJob`: `onError`, `onFinish`, ни ответа, ни зоны; когда эту дыру
   будут чинить, он покраснеет и приведёт к dartdoc.

   Вердикт: принято. В группу «ignore silences a failure no outcome carries»
   встали два сторожа: `ignore()` из `onFinish` продолжения, которое его
   наблюдатель отменил из `onError`, и `ignore()` из `onFinish` задачи, которой
   движок подал провал поверх отметки, — оба через `expectOnlyTold`. Мутацию
   «ответ за провал движка раньше `onFinish`» второй ловит. «Ответ продолжения
   раньше `finish`» эквивалентна: отмена из `onError` кончает продолжение
   сразу, и `onFinish` проходит внутри неё (зонд), так что тест держит
   обещание, а не порядок строк. Dartdoc `Job.ignore`, запись `CHANGELOG` ядра
   и `docs/architecture.md` говорят о колбэке `whenCancelled`,
   зарегистрированном до конца задачи. Оговорку о задаче, которую движок кончил
   руками, держит тест с `ProbeJob`: один `onError`, ни ответа, ни зоны.

2. **Low. Dartdoc трёх мест — `notifyObserver`, `_handleUnanswered`
   и `JobObserver.onError` — молчит о `ignore()`.**

   Суть. `notifyObserver` — член `@protected`, его читают авторы движков. После
   правки он говорит: «For an error that has an outcome of its own — the
   body's. … When a cancellation covers it afterwards, the outcome no longer
   carries it, and it is answered later without being announced again.»
   С `ignore()` покрытый провал тела не отвечается вовсе. А сам
   `notifyObserver` ядро теперь зовёт и для ошибки, у которой исхода нет:
   провала, поданного движком поверх отметки задачи с `ignore()` (ветка
   `_ignored` в `_reportCovered`). То же умолчание в `_handleUnanswered`
   («[notifyError] ends here, and so do two failures of a body: …»)
   и в `JobObserver.onError` («The errors with no outcome go on to
   [onUnanswered], and so do two failures of the body that no outcome
   carries»): оба ведут эти провалы в `onUnanswered` без исключения.
   `JobObserver.onUnanswered`, `Failed`, `Job.ignore`, `JobContext.runAll`
   и `Solo.onUnanswered` исключение называют.

   Свидетельство. Зонд P3, корень с секцией `uncancellable`, которая упала,
   пока держала отмену, и `ignore()`: `onError: Bad state: held`,
   `onFinish Cancelled(manual)` — ни ответа, ни зоны. Зонд P9 в находке 1 —
   `onError` через `notifyObserver` для провала, которого нет ни в одном
   исходе.

   Предложение. В `notifyObserver`: «…and it is answered later without being
   announced again, unless [Job.ignore] was called — then a failure an engine
   handed to [finish] over the mark is told here, and nowhere else».
   В `_handleUnanswered` и `JobObserver.onError` — «unless [Job.ignore] was
   called» или ссылка на `onUnanswered`.

   Вердикт: принято. `notifyObserver` называет исключение: при `ignore()`
   за покрытый провал никто не отвечает, а провал, поданный движком поверх
   отметки такой задачи, объявляется здесь и больше нигде.
   `_handleUnanswered` — «unless [Job.ignore] was called on the job»,
   `JobObserver.onError` — «[Job.ignore] on the job stops these two here».

3. **Low. «No outcome carries» о провале ветки, которую группа не бросила,
   неточно, и правка это слово размножила.**

   Суть. Исход самой ветки — `Failed` с этой ошибкой: её видят `onFinish`
   и `branch.outcome`, а кто держит хэндл ветки и ждёт `branch.value`, получает
   ошибку. Не несёт её исход группы — то, что родитель передаёт дальше. Прежний
   dartdoc `JobObserver.onError` говорил точно: «two failures of the body that
   a parent cannot pass on». Правка заменила это на «that no outcome carries»,
   и то же стоит в новых местах: поле `_ignored` («is in no outcome anybody
   gets»), `Job.ignore` («reach no caller»), абзац под таблицей `observing.md`
   и его перевод («two failures of a body that the outcome does not carry — …
   one of a branch whose group throws another»). О покрытом провале эти слова
   верны, о ветке — нет. Перечни `JobObserver.onUnanswered`
   и `packages/solo/doc/errors.md` называли ветку так и до правки.

   Свидетельство. Зонд P12: ветка `cancellable: false`, которую группа
   не бросила; её хэндл держат и читают `value`:

```text
P12 branch not thrown: its own outcome and value:
    onError: Bad state: first
    onFinish Failed(Bad state: first)
    onError: Bad state: second
    onFinish Failed(Bad state: second)
    second.value threw: Bad state: second
    onUnanswered: Bad state: second
    zone: Bad state: second
    parent caught: Bad state: first
    onFinish Done(null)
    second.outcome: Failed(Bad state: second)
```

   Предложение. Вернуть в `JobObserver.onError` «that a parent cannot pass on».
   В `_ignored`, `Job.ignore` и `observing.md` с переводом сказать о ветке
   «that the group did not throw» или «that its parent does not pass on», а «no
   outcome carries» оставить покрытому провалу. Что читатель `branch.value`
   получает ошибку, а группа ещё и отвечает за неё, — поведение не этой правки;
   я его только называю.

   Вердикт: принято. `JobObserver.onError` говорит о двух провалах тела без
   определения. `_ignored`: покрытый провал не лежит ни в одном исходе,
   а провал ветки — ни в чём, что передаёт группа. `Job.ignore`: «do not reach
   the parent's caller». Абзац `observing.md` и перевод: «два провала тела,
   которые таблица ведёт в `onUnanswered`». Фразу «that a parent cannot pass
   on» не вернул: покрытый провал бывает и у корня, у которого родителя нет.

4. **Low. Шапка `2026-09-25-covered-child-failure-plan.md` потеряла
   «не отправлено».**

   Суть. Правка шапки убрала «; не отправлено» после имени отчёта, а `38db07d`
   по-прежнему не на `origin`: `docs/handoff.md` того же коммита говорит, что
   коммиты после `b0dca01`, включая починку покрытого провала ребёнка,
   не отправлены. Шапка отчёта той же работы,
   `2026-09-25-covered-child-failure-report.md`, «не отправлено» сохранила.

   Свидетельство. `git diff c6e5399 e5e6d20` по файлу плана: «отчёт —
   `2026-09-25-covered-child-failure-report.md`; не отправлено. План прошёл…»
   стало «отчёт — `2026-09-25-covered-child-failure-report.md`. План прошёл…».

   Предложение. Вернуть «не отправлено» в шапку плана.

   Вердикт: принято, «не отправлено» в шапке плана возвращено.

## Как проверено

- Копия дерева: `git checkout --detach e5e6d20`; git звал как `/usr/bin/git`,
  потому что обёртку `rtk` над git сторож изоляции копии не пропускал.
  Вершина — `e5e6d20`; дерево чистое до и после работы, своих файлов в нём
  не осталось.
- Код: `git diff c6e5399 e5e6d20` по `lib/` ядра и `solo`, затем чтение целиком
  `_execute`, `finish`, `_reportCovered`, `_reportUnobserved`,
  `notifyObserver`, `notifyError`, `_handleUnanswered`, `_toZone`,
  `_ThenJob._sourceFinished`, `startChild`, `_RunAllGroup.run` и `_conclude`.
  Внутренние `ignore()` — грепом по `lib/` трёх пакетов: в ядре на `Job` один,
  отказ `startChild` (ребёнок ещё `created`, отметки у него нет, `finish`
  не подменяет исход); остальные — `Future.ignore`; в `solo` и `flutter_solo`
  ни одного. `solo` кончает руками (`_drop`) только задачи, которые ещё
  не стартовали.
- Числа: `dart test -r json` и счёт по событиям `testDone` (`jcount.py`):
  `async_job` 622, из них `unanswered_test.dart` 48,
  `observing_rakes_test.dart` 38, `outcomes_rakes_test.dart` 22; `solo` 799;
  пример `solo` 47; `flutter_solo` 85. В `unanswered_test.dart` на `c6e5399` —
  34 теста. Формат и анализ обоих пакетов чистые.
- Красные на старом ядре: копия пакетов в скретч-каталоге, `lib/` ядра и `solo`
  из `c6e5399` через `git archive`, тесты из `e5e6d20` (`run_old.sh`,
  `async_old.json`, `solo_old.json`). В ядре 19 красных: 14
  в `unanswered_test.dart`, 3 в `observing_rakes_test.dart`, по одному
  в `outcomes_rakes_test.dart` и `zone_test.dart`; в `solo` 4. Пять тестов,
  которые отчёт называет зелёными на старом ядре, зелёные.
- Мутации: `mutate.py` и `run_mut.sh`, в отдельной копии пакетов; откат копией
  файла со сверкой sha256, `hash ok` после каждой, в конце `diff -r` копии
  с `lib/` дерева — совпадают. Из таблицы отчёта с тем же числом красных: ответ
  микрозадачей — 4, те же четыре теста; `then` с `announced: false` — 2;
  `_conclude` не смотрит на `_ignored` — 3; в `_conclude` провал движка
  не объявляется — 1; `done` ставит `_ignored` — 15; `value` ставит
  `_ignored` — 12; при `_ignored` провал движка не объявляется — 1; всегда
  `_handleUnanswered` — 3; всегда `notifyError` — 20; `_reportCovered`
  не смотрит на `_ignored` — 11, в `solo` 1. Проверка `_observed`
  в микрозадаче — 22 против 21 отчёта: у меня она стоит и перед веткой
  `_ignored`, и лишним краснеет «a failure an engine handed in over the mark is
  still told, once»; в `solo` 5, как в отчёте. Свои мутации: `ignore()` без
  `_observed` — 41; `notifyError` смотрит на `_ignored` — 3, то есть ошибки вне
  тела `ignore()` не глушит, и это держится; ответ в `_execute` раньше
  `finish` — 1; продолжение без ответа — 2; `_conclude` смотрит на `_observed`
  вместо `_ignored` — 7; две выжившие — в находке 1.
- Зонды `zz_review_probe_test.dart` — в третьей копии пакета, печатают
  из `tearDownAll`, за пределами зоны, и ничего не утверждают. P1: корень
  с `ignore()` — покрытый провал слышит один `onError`, провалы уборки
  и `unattended` идут в `onUnanswered` и зону. P2: `cancellable: false`
  отказывается от отмены, исход `Failed`, в зону один раз. P3: секция
  `uncancellable` у корня — без чтения и с чтением `value` отвечена (читатель
  получает `Cancelled(manual)`), с `ignore()` — один `onError`. P4: покрытый
  источник и продолжение со своим наблюдателем — отвечает один источник,
  продолжение кончается `Cancelled(chain)`. P5: ребёнок `each`, чьё `value`
  ждёт тело, — отвечен без `ignore()`, заглушён с ним. P6:
  `scheduleMicrotask(job.ignore)` из `onFinish` опаздывает, как и записано
  в ревью плана. P7–P10 — в находках 1 и 2. P11: ветка с `ignore()`, чей провал
  группа бросила, — его ловит родитель. P12 — в находке 3.
- Документы: dartdoc, страницы обеих версий, оба `CHANGELOG`
  и `docs/architecture.md` сверены с зондами и тестами выше. Грепом по дереву
  без `doc/api/`, `build/`, `.dart_tool` и `docs/records/` — «took the
  outcome», «parent took», `_takenByParent`, «whether or not … ignore»,
  «changes nothing», «keeps the rule it had», «observed by their parent», окно
  наблюдения рядом с покрытым провалом — не осталось ничего, кроме имени нового
  теста в `zone_test.dart`, которое говорит обратное. `check_translations.py`,
  `reflow.py --check`, `check_line_width.py`, `check_doc_shape.py`
  и `check_links.py` зелёные; `reflow.py --check` по новому отчёту чистый; шире
  79 в тронутых записях только строки таблиц. Сайт и стенды фрагментов я
  не пересобирал.
- Всё названное — в `wr-any/` скретч-каталога рядом с этим файлом: скрипты,
  логи `*.json` и `mutations*.txt`, копии `old/`, `new/`, `probe/`.

## Общий вывод

Работу можно принимать. Механика верна и совпадает с планом и вердиктами его
ревью, числа и красные на старом ядре воспроизводятся, мутации отчёта ловятся.
Все четыре находки — о сторожах и словах, не о поведении. Первую стоит закрыть
двумя тестами до того, как код вокруг ответа тронут снова: сейчас обещание
срока `ignore()` на двух путях держит только порядок строк.
