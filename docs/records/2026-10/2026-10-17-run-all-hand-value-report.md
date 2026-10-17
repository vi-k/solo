# Ветка `runAll`, которой движок подал значение после провала тела: отчёт

> **Состояние на 2026-10-17:** сделано в `main` одним коммитом, не отправлено.
> **Что это:** исправление внутренней ошибки
> `a group failed with nothing to throw`, оба ревью и проверки.
> **Связанные записи:** `2026-10-17-run-all-hand-value-design.md`,
> `2026-10-17-async-job-code-fixes-report.md`,
> `2026-10-17-async-job-project-review.md`.

Дефект попутно нашёл ревьюер первой волны правок по второму полному ревью; он
есть и на `ee04d82c`. Владелец 2026-10-17 сказал «чини». Правило и устройство —
в записи `2026-10-17-run-all-hand-value-design.md`, здесь — что сделано, что
нашли ревью и чем это проверено.

## Что сделано

Группа `runAll` идёт по тому, о чём услышала первым: о провале тела ветки или
о значении, которое движок домена подал ветке руками. Если первым был провал,
значение для группы опоздало: она бросает провал или отвечает за него, а ветка
за него не отвечает. Если первым было значение, группа может его отдать,
а за провал отвечает ветка, как и до правки.

Код:

- `run_all.dart`: `_GroupHold.takeFailure`, `_GroupBranch.failureTaken`,
  `_RunAllGroup._takeFailure` и `_endOf`. `_chooseOutcome` и цикл ответов
  в `_conclude` берут исход ветки через `_endOf`. Цикл старта не вешает хватку
  на кончившуюся ветку, цикл после старта не читает её тело.
- `job_base.dart`: поле `_failureWentToGroup`. `finish` спрашивает группу сразу
  после `_status = finished` и только когда решено `Done`.
  `_answerForHandFinished` с этим флагом молчит и отпускает `_bodyOutcome`.

Документы:

- dartdoc `finish` — абзац об исключении: когда группа слышит о провале и куда
  идёт значение;
- dartdoc `runAll`, `Job.ignoreFailure`, `JobObserver.onError`,
  `JobAnswerer.onUnanswered` — оговорка со ссылкой на `finish`;
- внутренние комментарии, которые говорили, что раннее слово ничего не решает;
- `doc/extending.md` и `doc/children.md` ядра с переводами
  в `docs/ru/async_job/`; линтер humanizer--ru на изменённых русских абзацах —
  0 ошибок;
- абзац об ответе за провал задачи, кончённой руками, в `docs/architecture.md`.

`CHANGELOG.md` не менялся: в 0.2.0 `runAll` не было.

Тестов 17 новых, и у развёртки «a failed branch an engine ends by hand with a
value is thrown» новые имя и ожидания: тринадцать в группе «a branch an engine
hands a value after its body failed» в `finish_announced_test.dart`, один
в `start_depth_test.dart`, три в `retention_test.dart`.

## Ревью дизайна

Дизайн до кода смотрел независимый ревьюер на Opus в своей копии: собрал его
прототипом, гонял зонды и мутантов. Вывод — «ready with changes», девять
находок. Все приняты, каждая перепроверена своими тестами или чтением.

1. High. Три пути «значение раньше» и с дизайном роняли родителя той же
   внутренней ошибкой: тело в своём старте кончает свою задачу руками
   и бросает, сразу, если оно не `async`, или позже, или `onError` подаёт
   значение, пока идёт старт группы. Хватка вешалась на уже кончившуюся ветку,
   а цикл после старта читал тело кончившейся задачи. Проверено: три теста
   «from … in its start / before its first await is handed over» красные
   на `HEAD` и на прототипе дизайна. Закрыто: на кончившуюся ветку хватка
   не вешается, цикл после старта её пропускает.
2. Medium. Правило противоречило обещанию dartdoc `runAll`: исход решают
   конечные исходы, и бросается то, что бросил бы `await ctx.run(child)`.
   Дизайн говорил этот dartdoc не трогать. Под удар попадали и `children.md`,
   `Job.ignoreFailure`, `onError`, `onUnanswered`, `architecture.md` и девять
   внутренних комментариев. Проверено чтением. Закрыто: поправлено всё,
   список — в «Что сделано».
3. Medium. Слова правила «после провала тела» не совпадали с механизмом:
   граница проходит там, где группа услышала. Щель старта и значение
   из `onError` приходят после провала, а группа отдаёт значения. Закрыто:
   правило теперь «группа идёт по тому, о чём услышала первым», и dartdoc
   `finish` называет, когда группа слышит и что `onError` лежит до этой
   границы.
4. Medium. Предложенные тесты не держали три проверки: `bodyOutcome is Failed`,
   `heard` и `decided is Done`. Мутанты без каждой проходили набор. Проверено
   мутантами на прототипе. Закрыто тестами: щель старта и значение до провала
   тела, ветка оборванной группы в `start_depth_test.dart`, поданные
   `Failed(Y)` и `Cancelled`.
5. Low. Ожидание теста «сосед падает первым» зависело от порядка: с медленным
   соседом группа бросает X. Закрыто: порядок в тестах закреплён, медленный
   сосед — свой тест «ahead of the failure of a sibling is thrown».
6. Low. Кончившаяся ветка держала группу через хватку, а провал тела — через
   `_bodyOutcome`; так было и до дизайна. Проверено: два теста
   в `retention_test.dart` красные на `HEAD`. Закрыто тем же, что первая
   находка, и тем, что `_answerForHandFinished` отпускает `_bodyOutcome`.
7. Nit. Аргумент `takeFailure(Failed failure)` не использовался. Убран.
8. Nit. Вопрос группе стоял перед `_hold = null`, уже после `onFinish`
   и `_done.complete`. Перенесён сразу за `_status = finished`, до любого
   чужого кода.
9. Nit. Dartdoc `finish` должен сказать, что значение остаётся только в исходе
   ветки. Сказано.

## Проверки

Новые тесты на библиотеке `HEAD`: отвязанный worktree на `508eb2af`, три файла
тестов из дерева, `00:06 +82 -9: Some tests failed.` Красные — ровно те, что
запись дизайна называет красными:

```text
test/finish_announced_test.dart: a branch an engine hands a value after its body failed ahead of the failure of a sibling is thrown
test/finish_announced_test.dart: a branch an engine hands a value after its body failed from a cleanup has its failure thrown by the group
test/finish_announced_test.dart: a branch an engine hands a value after its body failed from onError in the start is handed over
test/finish_announced_test.dart: a branch an engine hands a value after its body failed from the body before its first await is handed over
test/finish_announced_test.dart: a branch an engine hands a value after its body failed from the body in its start is handed over
test/finish_announced_test.dart: a failed branch an engine ends by hand with a value is thrown
test/retention_test.dart: a branch ended by hand in its start lets go of its group
test/retention_test.dart: a job ended by hand keeps nothing its body failed with after it
test/retention_test.dart: a job ended by hand keeps nothing its body returned after it
```

Пять красных из `finish_announced_test.dart` падают той самой ошибкой:
`Failed(Bad state: Job(): a group failed with nothing to throw)`. Шестой,
«ahead of the failure of a sibling is thrown», получает
`Failed(Bad state: sibling)`: до правки группа бросала провал соседа, хотя
о провале ветки услышала раньше. Тесты удержания — `Actual: <false>`.

Тесты удержания поначалу оставались красными и с правкой. Причина была в тесте,
а не в ядре: `ProbeJob` держит замыкание тела, замыкания одного кадра Dart
делят контекст, и провал держался этим контекстом. Задачу теперь строит
отдельная функция, а провал передаётся через коробку, которую тело опустошает.

Мутанты — каждая часть правки откатывалась по одной в копии `tmp/p6-mut`
скретч-каталога сессии, скриптом `mutate_p6.py`, весь набор ядра на итоговом
дереве:

- `no-ask` — `finish` не спрашивает группу;
- `any-decided`, `not-cancelled`, `outcome-is-done` — спрашивает при любом
  исходе, при любом, кроме `Cancelled`, или по поданному исходу,
  а не по решённому;
- `no-body-check`, `no-heard-check` — группа берёт провал без одной из двух
  проверок;
- `endof-settled`, `endof-choose`, `endof-conclude` — `settled` вместо `_endOf`
  везде, только в выборе, только в ответах;
- `flag-ignored`, `keep-body`, `clear-late` — `_answerForHandFinished`
  не смотрит на флаг, не отпускает `_bodyOutcome` или отпускает его только
  на провале;
- `hold-finished`, `postloop-finished` — хватка на кончившейся ветке, цикл
  после старта читает её тело.

Убиты все четырнадцать:

```text
== hold-finished: 2 red
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed from the body before its first await is handed over
    test/retention_test.dart: a branch ended by hand in its start lets go of its group
== postloop-finished: 2 red
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed from onError in the start is handed over
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed from the body in its start is handed over
== keep-body: 2 red
    test/retention_test.dart: a job ended by hand keeps nothing its body failed with after it
    test/retention_test.dart: a job ended by hand keeps nothing its body returned after it
== not-cancelled: 1 red
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed is not this one when the hand-in is Failed
== no-ask: 3 red
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed ahead of the failure of a sibling is thrown
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed from a cleanup has its failure thrown by the group
    test/finish_announced_test.dart: a failed branch an engine ends by hand with a value is thrown
== any-decided: 9 red
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed is not this one when a cancellation it accepted decides
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed is not this one when the hand-in is Cancelled
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed is not this one when the hand-in is Failed
    test/observing_rakes_test.dart: Where errors go a branch cancelled from outside fails the group with its stop
    test/run_all_test.dart: a failure covered by the stop does not beat a real cancellation
    test/unanswered_test.dart: a failure a cancellation covered is answered for, whoever reads it a branch of runAll whose parent was cancelled
    test/unanswered_test.dart: a failure a cancellation covered is answered for, whoever reads it a branch that failed first and was stopped by a refused sibling
    test/unanswered_test.dart: a failure a cancellation covered is answered for, whoever reads it a branch that failed inside uncancellable while holding the stop
    test/unanswered_test.dart: ignoreFailure silences a failure no outcome carries on a branch of runAll
== no-body-check: 3 red
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed before the body fails is handed over
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed before the group heard the body is handed over
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed from onError is handed over
== no-heard-check: 1 red
    test/start_depth_test.dart: a branch the group never heard answers for its failure past a value
== endof-settled: 4 red
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed ahead of the failure of a sibling is thrown
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed behind the failure of a sibling is answered for by the group, once
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed from a cleanup has its failure thrown by the group
    test/finish_announced_test.dart: a failed branch an engine ends by hand with a value is thrown
== endof-conclude: 1 red
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed behind the failure of a sibling is answered for by the group, once
== endof-choose: 3 red
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed ahead of the failure of a sibling is thrown
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed from a cleanup has its failure thrown by the group
    test/finish_announced_test.dart: a failed branch an engine ends by hand with a value is thrown
== flag-ignored: 4 red
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed ahead of the failure of a sibling is thrown
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed behind the failure of a sibling is answered for by the group, once
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed from a cleanup has its failure thrown by the group
    test/finish_announced_test.dart: a failed branch an engine ends by hand with a value is thrown
== clear-late: 1 red
    test/retention_test.dart: a job ended by hand keeps nothing its body returned after it
== outcome-is-done: 1 red
    test/finish_announced_test.dart: a branch an engine hands a value after its body failed is not this one when a cancellation it accepted decides
```

Наборы на дереве с правкой: `async_job` — формат, анализ и `dart doc` чистые,
`00:09 +1553: All tests passed!`; `solo` — 1945, его пример — 98,
`flutter_solo` — 213, его пример — 4, пример ядра запускается. Проверки
документов — ширина, заливка, форма, переводы, ссылки — и тесты скриптов
зелёные, сайт собран, 56 страниц. Оба стенда фрагментов:
`every quoted trace is what the bench prints`.

## Ревью готовой правки

Готовую правку смотрел второй независимый ревьюер на Opus в своей копии:
отвязанный worktree на `508eb2af` с правкой поверх. Дефектов поведения он
не нашёл: на каждом его зонде каждая ошибка получает один ответ, родитель
внутренней ошибки не получает, кончившаяся ветка ничего не держит. Зонды:
каждый из четырёх выходов `_answerForHandFinished` и выходы `_conclude` —
отказ, своя ошибка группы, выбранный провал; ручной финиш, пока ждут уборку;
`runAll` в ветке `runAll`; `cancellable: false`; `ParallelWaitError`; отмена
родителя после провала; удержание с настоящей сборкой мусора. Девять находок
ревью дизайна он подтвердил закрытыми; два хвоста — его находки 1 и 3. Своих
находок восемь, все приняты.

1. Medium. Проверку `decided is Done` в `finish` набор не держал: мутант,
   который спрашивает группу по поданному `Done`, а не по решённому исходу,
   проходил весь набор. Ловил его только зонд ревьюера: тело падает, ветку
   отменяют извне, пока идёт уборка, движок подаёт ей значение. Отмена
   отбрасывает значение, а мутант всё равно отдавал провал группе, и родитель
   вместо отмены получал X. Закрыто тестом «is not this one when a cancellation
   it accepted decides»; dartdoc `finish` теперь говорит о ветке, которая
   кончается `Done`, поданным руками, а комментарий у вопроса группе — что
   принятая отмена значение отбрасывает.
2. Medium. Документы состояния отставали от дерева: handoff говорил
   о незаконченном ревью и нетронутом `lib`, отчёта не было, якорь мутанта
   `keep-body` в `mutate_p6.py` стоял на комментарии, которого больше нет.
   Ревьюер получил копию, снятую до того, как я дописал отчёт и handoff. Якорь
   поправлен, мутанты перезапущены на итоговом дереве.
3. Low. Очистку `_bodyOutcome` держал только путь провала: мутант, который
   чистит поле после раннего выхода, проходил набор, и задача, кончённая
   руками, держала значение, которое тело вернуло позже. Закрыто тестом «a job
   ended by hand keeps nothing its body returned after it»
   в `retention_test.dart`, красным и на `HEAD`; комментарий у очистки называет
   и значение.
4. Low. «Тело, бросившее до первого `await`» неверно для тела `async`: его
   провал приходит через future, уже после старта. Внутри `startChild`
   кончается только тело, которое не `async`. Исходы правила от этого
   не меняются. Поправлено в dartdoc `finish`, комментариях `run`
   и `_bodyOutcome`, на `extending.md` с переводом и в записи дизайна.
5. Low. Фразы публичных документов, которые прочтут не так. В dartdoc `onError`
   исключение читалось как переход в случай, который останавливает
   `ignoreFailure()`; в `onUnanswered` «took it over a value» читалось как
   фразовый глагол; в `ignoreFailure` у «after it» не было ясного предмета;
   dartdoc `runAll` обещал «решают конечные исходы, а не раннее слово» без
   оговорки. На `extending.md` исключение читалось как исключение
   из `ignoreFailure()` и молчало, что `ignoreFailure()` гасит ответ группы;
   на `children.md` «as in» делало раздел примером, а «The one exception»
   обещало больше, чем есть. Всё переписано, с переводами.
6. Low. Внутренние комментарии: «hold the group for good» в файле, где hold —
   барьер, читалось как зависание; `takeFailure` и `_failureWentToGroup`
   говорили, что группа отвечает за провал, а она может его и бросить;
   у `_takeFailure` стоял обрывок фразы, и там же не был назван путь
   из `onError`. Поправлено.
7. Low. Ошибки в записи дизайна: «кроме двух» при трёх тестах вне
   `finish_announced_test.dart`; тест «ahead of the failure of a sibling is
   thrown» среди зелёных до правки, хотя на `HEAD` он красный; «ранее слово»
   вместо «раннее». Поправлено; второе я нашёл и сам, пока ревью шло.
8. Low. На `architecture.md` вставка встала прямо перед «Остановка по токену
   бросает такую ошибку», и «такую» потеряло предмет, а «отвечает за него сама»
   молчало об `ignoreFailure()`. Предмет назван, `ignoreFailure()` упомянут.

Мелочи, без правки кода. Три мутанта ревьюер счёл равносильными оригиналу:
`is! Failed` вместо `== null` в `_takeFailure` — отмена тела всё равно кончает
ветку отменой; вопрос группе после `onFinish` или до `_status = finished`;
`isRunning` вместо `!isFinished` в `run`. Две ветки со взятыми провалами:
группа бросает провал той, что кончилась первой, — так и выходит из «как
если бы ветка кончилась провалом»; записано в дизайне, зонд ревьюера
перезапущен в его копии:

```text
=== N11 bFirst=false
  p: Failed(Bad state: X)
  heard: [onError a: Bad state: X, onError b: Bad state: Y, onFinish a, onFinish b, onUnanswered b: Bad state: Y]
  zone: [Bad state: Y]
=== N11 bFirst=true
  p: Failed(Bad state: Y)
  heard: [onError a: Bad state: X, onError b: Bad state: Y, onFinish b, onFinish a, onUnanswered a: Bad state: X]
  zone: [Bad state: X]
```

Провал, взятый группой и не брошенный, получает ответ, когда группа закончит,
а не когда ветке подали значение: так с любым провалом, который группа
не бросила. Вне этой работы: движок, чей `finish` сам превращает `Failed`
в `Done`, под `ctx.run` оставляет провал тела одному `onError`, никто за него
не отвечает. Так было и до правки. В `runAll` с таким движком теперь работает
правило: родитель получает `Failed(Bad state: X)`, а до правки получал
внутреннюю ошибку. Зонд ревьюера, перезапущен в его копии:

```text
=== N10 inGroup=false
  p: Done(fallback)
  b: Done(fallback)
  heard: [onError b: Bad state: X, onFinish b]
  zone: []
=== N10 inGroup=true
  p: Failed(Bad state: X)
  b: Done(fallback)
```

## Чего не прогоняли

- `floor` локально: правка не трогает ни `pubspec.yaml`, ни состав архива. Его
  гоняет CI после отправки в `main`, а отправка — по слову владельца.
- Ревьюер готовой правки не гонял `solo`, `flutter_solo`, примеры, сайт
  и стенды; их гонял гейт на дереве.
- Движок, чей `finish` превращает провал в значение, под `ctx.run` дальше
  одного зонда не смотрели: это вне работы.
