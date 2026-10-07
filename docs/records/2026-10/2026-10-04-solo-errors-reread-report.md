> **Состояние на 2026-10-07:** вычитка сделана в клоне
> `.artifacts/2026-10-04-solo-errors-reread/tree/` на `5e2b858` и перенесена
> в `main` коммитом `c54da7b`, отправлена. Агент кончился на переполнении
> контекста перед коммитом; основная сессия прогнала проверки на готовом
> дереве клона и закоммитила его сама. Тридцать две находки разобраны тем же
> коммитом: двадцать шесть приняты, пять отклонены, одна передана владельцу.
> Владелец читает страницу с 2026-10-07; правки по его вопросам —
> в разделе «По чтению владельца».
> **Что это:** отчёт о повторной вычитке `packages/solo/doc/errors.md` перед
> вторым кругом чтения: находки ревью с вердиктами, сторож, который запускает
> код страницы, мутации и вопрос владельцу.
> **Связанные записи:** `2026-09-20-errors-rakes-report.md` (первая вычитка
> страницы и чтение владельца), `2026-09-22-error-hook-split-report.md`,
> `2026-09-26-async-job-project-review.md` (находка L29 и решение владельца
> по ней), `2026-10-01-multi-observer-design.md`,
> `2026-10-01-visit-errors-design.md`, `2026-10-03-ctx-pause-design.md`,
> `2026-10-02-cancellation-reread-report.md` и
> `2026-10-02-observing-reread-report.md` (страницы ядра о том же),
> `2026-10-03-solo-cancellation-reread-report.md` (оставила этой вычитке
> замечание), `2026-10-04-solo-resources-reread-report.md`,
> `2026-10-02-outcomes-reread-report.md`,
> `2026-09-11[16]-docs-structure-design.md`.

# Повторная вычитка errors.md пакета solo

## Зачем

Владелец читал `packages/solo/doc/errors.md` 2026-09-22 и 2026-09-23. Первая
вычитка страницы и восемнадцать правок по его чтению записаны
в `2026-09-20-errors-rakes-report.md`; последний коммит по чтению — `eb8b0bb`.
После чтения страницу изменили четырнадцать коммитов, +89 −30 строк оригинала
из 573, перевод — +96 −32. 2026-09-25 страница перешла на слово «accepts»
(`4560aad`). С 2026-09-25 по 2026-09-27 в перечень ошибок, которых не несёт
исход, вошли провал ветки `ctx.runAll`, который группа не бросила, и провал
тела, накрытый отменой, а в «Observing the outcome» — тот же провал
у `await job.value` (`38db07d`, `d25a1a6`, `e5e6d20`, `4543d7d`). 2026-09-26
по поручению владельца число рецепта стало считаться от момента, когда отмена
начала действовать (`84d96b9`). 2026-09-28 в «Logs» встал `Job.debug`
(`340a5e2`), а отказ внутри работы `ctx.unattended` получил слова «names the
call» (`ca9339b`). 2026-09-30 `pending` стал одним из трёх: появились
`SoloPendingQueue` и `SoloPendingStream`, поле `draining`, трасса из трёх строк
и абзац о `null` (`2289bc6`). 2026-10-01 появился абзац о `SoloObserver.all`
с блоком (`9a6d95a`), а пример обработчика пошёл через `Job.visitErrors`
(`99ab426`, `f0ee2f7`, `1a6a618`). 2026-10-03 в таблицу задержек встала строка
`ctx.pause` (`8ca57be`). Две из этих правок владелец поручал сам, но текста
не видел ни одной.

По решению владельца 2026-10-02 перед вторым чтением страница вычитана заново,
по образцу `2026-10-04-solo-resources-reread-report.md`,
`2026-10-03-solo-cancellation-reread-report.md`
и `2026-10-02-outcomes-reread-report.md`.

## Как

Один ревьюер, эта сессия, в клоне на `5e2b858`. Каждое утверждение страницы —
проза, три таблицы, цитаты строк лога, комментарии в коде — сверено программой,
которая запускается. Зонды лежат
в `.artifacts/2026-10-04-solo-errors-reread/probes/`, `probe.sh` рядом кладёт
их в `packages/solo/.probe/` клона и запускает оттуда. Десять файлов-тестов,
218 сценариев: `probe_reporting_test.dart`, `probe_watching_test.dart`,
`probe_holding_test.dart`, `probe_slow_test.dart`, `probe_failures_test.dart`,
`probe_covered_test.dart`, `probe_catching_test.dart`, `probe_rules_test.dart`,
`probe_background_test.dart` и `probe_core_news_test.dart`; их вывод —
`probes.out` там же. Код страницы до правок стоит в `probe_page.dart`,
приложение вокруг него — в `probe_stubs.dart`, рамка с фейковым временем
и зоной — в `probe_util.dart`. Вызов заглушки идёт, пока зонд его не завершит,
поэтому порядок событий задаёт зонд, а не таймер; фейковое время движется
только там, где страница говорит о времени. Внутри зоны зонд ничего
не утверждает: он печатает, что услышали хук `onError`, хук `onUnanswered`,
обработчик и зона, а сверяет это чтение. Отдельным проходом страница прочитана
глазами читателя, у которого есть только она: слово без предмета в примере,
одно слово для двух вещей, местоимение с двумя кандидатами, фраза, отвечающая
на реплику, которой читатель не слышал, сравнение двух версий, из которых
проверена одна.

Главное нашлось в разделе о перехвате ошибок в теле. Цена его первой попытки
названа для кода, которого на странице нет: `join` дожидается открытия камеры,
и камеру, «которую задача не открывала», показанный код сбросить не может.
Прежний сторож гонял эту попытку со строкой, которой на странице не было. Ответ
того же раздела показывал две формы, которые спрашивают у ошибки,
а не у задачи: с токеном, который страница об отмене учит заводить, ошибка
операции проходит мимо них, и цена первой попытки возвращается. Владелец
отказался от этих двух форм 2026-09-29 по находке L29
в `2026-09-26-async-job-project-review.md`; на эту страницу решение не дошло.
Остальное — места, где страница говорит больше, чем делает код: хук слышит
ошибку «один раз», хотя провал ребёнка, который родитель пропустил, приходит
дважды; все ошибки делятся на те, что несёт исход, и те, за которые отвечает
`onUnanswered`, хотя у провала тела после принятой отмены нет ни того,
ни другого; движок «никогда» не отдаёт `Cancelled` в зону, хотя хук, бросивший
`Cancelled`, отдаёт.

От ядра страница не отстала. `ctx.pause` стоит в таблице задержек; `ctx.pause`
под правилами `solo` кончается отменой правил и снимает таймер (зонд
`probe_core_news_test.dart`, N3). `Job.visitErrors` стоит в примере
обработчика: N4 — провалы по одному, отмены по одной. Разделение `JobObserver`
и `JobAnswerer` страница говорит своими словами: наблюдатель только смотрит,
а ответа спрашивают у контроллера, N5 —
`observer.onError, controller.onError, controller.onUnanswered`. `Job.each` —
корневая задача ядра: очередь её не берёт, N1,
`ArgumentError: was not created by this Solo`, а о провале такой задачи,
созданной в теле, хуки контроллера не слышат вовсе, N2; это предмет страницы
о детях, и здесь о нём ни слова. Голого `Future.delayed` в коде страницы нет:
он стоит только подписью строки таблицы, где и назван ошибкой.

## Находки ревью

### High

**H1. Первая попытка «Catching errors inside a body» сбрасывает камеру, которую
задача открыла сама.** Блок — `try` с двумя `ctx.join` и широкий `catch`,
который зовёт `hw.reset()`, `ctx.emit(Broken(error))` и `rethrow`. Проза под
ним: «Cancel this job while `hw.open` is in flight: `join` throws `Cancelled`,
the catch reads it as a failure of the camera and resets a camera this job
never opened». Но `join` дожидается своего вызова и бросает отмену уже после
него. Зонд `probe_catching_test.dart`, C1, версия `broad`: пока камера
открывается, исхода у задачи нет, а трасса устройства —
`open start, open end, reset start, reset end`. Камеру открыла эта самая
задача, и сброс идёт после открытия. Страница о камере говорит то же: «`join`
has waited for the opening, so the hardware is open». Камеру, которую задача
не открывала, показанный код сбросить не может вовсе: `try` начинается
с `ctx.join(hw.open)`, а задача, отменённая до старта, тела не запускает.
Прежний сторож этого не видел. Его копия первой попытки держала перед `join`
строку `await ctx.wait(() => gate.future);`, которой на странице нет, и тест
отменял задачу на ней: отсюда `calls == ['reset']` и название
`the first attempt resets a camera the job never opened`. По чтению владельца
2026-09-22, пункт четырнадцатый `2026-09-20-errors-rakes-report.md`, именно
этот сброс назван настоящим вредом попытки, так что раздел стоял на сценарии,
которого его код не даёт.

Вердикт: принято. Взят сценарий, который код даёт: «Cancel this job while
`hw.setZoom` is in flight: `join` waits the call out and throws `Cancelled` in
place of its result, and the catch reads that as a failure of the camera. It
resets a camera that opened and took its zoom, and whoever cancelled the job
waits for the reset as well». Зонд C2:
`open start, open end, setZoom start, setZoom end, reset start, reset end`,
исход `Cancelled(manual)`, хуки и зона молчат; C7: `close()` не возвращается,
пока идёт сброс. Второй абзац попытки — о том, что `emit` и `rethrow` под
сбросом ничего не меняют, — верен и остался как был. Код первой попытки
не менялся. Тесты — группы `the first attempt:`
и `the catch that asks the job:` раздела «Catching errors inside a body»,
по семь сценариев на версию, одни и те же; мутации T38, T39, T43, P22, P25,
E58.

### Medium

**M1. Ответ «Letting cancellation through» спрашивает у ошибки,
а не у задачи.** Раздел показывал ответом ветку `on Cancelled { rethrow; }`
перед широкой и вторым блоком её однострочную форму,
`if (error is Cancelled) rethrow;` первой строкой `catch`. В примере раздела
токена нет, и обе формы работают: `join` бросает `Cancelled`. Страница
об отмене того же пакета учит отдавать операции токен через `ctx.onCancel`,
и с ним из `join` выходит ошибка самой операции, а не `Cancelled`. Зонд
`probe_catching_test.dart`, C8, камера с токеном, которая останавливается
броском: у обеих форм трасса
`open start, open end, open stopped, reset start, reset end` — камеру снова
сбрасывают по отмене, то есть цена первой попытки на месте. У `catch`, который
первой строкой зовёт `ctx.check()`, сброса нет: `open stopped`, и всё. Вычитка
`cancellation.md` оставила это замечание здесь
(`2026-10-03-solo-cancellation-reread-report.md`, раздел «Чего ревью не нашло,
но нашлось рядом»). Обе формы — те самые два примера проброса `Cancelled`,
которых требовал прежний пункт «Требований к README». Владелец снял его
2026-09-29 по находке L29: «действует страница об отмене с `ctx.check()`»;
в `docs/handoff.md` стоит «Отменена ли джоба, спрашивают у джобы,
а не у ошибки: `ctx.check()` первой строкой `catch`, и для `on Exception`,
и для `on Object`», а ветка `on Cancelled { rethrow; }` названа первой попыткой
страницы ядра. Однострочную форму сюда добавили по слову владельца 2026-09-22,
за неделю до этого решения.

Вердикт: принято, по действующему решению владельца от 2026-09-29. Ответ
раздела — один блок, широкий `catch` с `ctx.check();` первой строкой. Проза:
«`ctx.check()` asks the job, not the error: it throws the job's `Cancelled` if
the job has accepted one, whatever the catch took, and what follows handles the
failures of a job nobody cancelled»; фраза о том, что проверка стоит первой
строкой и почему, осталась. Обе прежние формы названы следующим абзацем как то,
что работает, пока каждый вызов в `try` идёт до конца, со ссылкой на «The
token» страницы об отмене и на «Catching errors of the operation» страницы
ядра, которая эту ветку разбирает; сам разбор не пересказан. Блоков `dart`
на странице стало двадцать вместо двадцати одного. У вопроса к задаче есть
цена, и она сказана: камеру, которая сама упала после принятой отмены, такой
`catch` не сбрасывает, и о сбое не слышит ни один хук (C5, версия `asking`:
`open start, open failed`, хук пуст); широкий `catch` и обе формы с веткой
в том же сценарии сбрасывают. Обе версии страницы проверены на одних и тех же
семи сценариях. Тесты — те же две группы и ещё пять тестов с камерой, у которой
есть токен; мутации T19–T23, T44, P23, P24, P26, E59.

**M2. «The engine never hands a `Cancelled` to the zone, by this route or any
other of its own».** И фразой ниже: неперехваченная ошибка `job.value` — «the
one way a `Cancelled` gets there». Путей больше. Хук контроллера или
наблюдателя, который бросил `Cancelled`, отдаёт его в зону: зонд
`probe_reporting_test.dart`, R17, `zone: [Cancelled(handler: from the hook)]`.
Это не выдуманный случай: R17b — хук `onLog` из раздела «Logs» зовёт ленивое
сообщение, сообщение читает `ctx.state` на отменённой задаче, и в зоне
`Cancelled(manual)`. Стартовое правило, бросившее `Cancelled`, кончает задачу
`Failed(Cancelled)`, и ненаблюдённый исход уносит его в зону:
`probe_failures_test.dart`, F8. Вызов контекста, который тело не стало ждать,
бросает отмену задачи в future, которую не ждёт никто: F8b. Формулировка
сложилась по чтению владельца 2026-09-22, пункт десятый
`2026-09-20-errors-rakes-report.md`; слова «ни любым другим из своих» тогда
добавил автор правки.

Вердикт: принято. Фразы сужены до того, что держит код: «The zone does not: the
default body of `onUnanswered` never hands a `Cancelled` to it» и «that route
to the zone is Dart's own, not the engine's». Обе верны при любом ответе
на вопрос M5. Тесты `an abandoned call that ends in a Cancelled`,
с обработчиком и без, и `the value of a cancelled job, taken and not handled`;
мутации C20, P20.

**M3. «It is told once».** Хуку отчёта рассказывают о каждой ошибке один раз —
на каждую задачу. Ошибка, которую бросил ребёнок, а родитель не поймал, кончает
обоих, и хук слышит её дважды: зонд `probe_reporting_test.dart`, R20,
`hook [child: child, parent: child]`. С хуком самой страницы,
`reportCrash(error, stackTrace)`, это два отчёта о сбое на одно исключение. Так
устроено ядро, инвариант 4 `docs/architecture.md`: `Failed` любой задачи, в том
числе ребёнка, зовёт `onError` один раз.

Вердикт: принято: «…and it is told once for each job. An error a child throws
and its parent lets through is the failure of both: the hook hears it twice,
and the `job` it is given tells the two calls apart». Тесты
`an error a child throws and its parent lets through`
и `an error a child throws and its parent catches`; мутации C7, P2.

**M4. У провала тела после принятой отмены нет ни исхода, ни ответа.** Раздел
«Answering for an error» делит ошибки надвое: почти каждую несёт исход, «What
no outcome carries is the rest», и за остальное спрашивают `onUnanswered`.
Третьего не дано, а оно есть. Вызов, которого дожидается `ctx.join`, падает
после того, как задача приняла отмену: исход — `Cancelled`, хук `onError`
слышит ошибку, а ответа не спрашивают ни у кого. Зонд
`probe_reporting_test.dart`, R9: `hook [after: stopped] unanswered []`,
обработчик и зона пусты. Читатель, который отправляет отчёты из `onUnanswered`
или из `Solo.errorHandler`, как учит раздел, таких ошибок не увидит никогда
и не узнает, что они бывают. Страница об отмене говорит об этом в одном
предложении и ведёт сюда «за всем маршрутом».

Вердикт: принято. Новый абзац перед последним: «One error no outcome carries is
missing from that list, and nobody is asked to answer for it: the failure of a
body that comes after its job has accepted a cancellation… The job ends
`Cancelled`, the reporting hook is told of the error, and it goes no further»,
и почему: чаще всего так кончается операция, которую отмена остановила,
и отличить от неё настоящий сбой движок не может. Таблицу ядра «Where errors
go» абзац не пересказывает. Тест `a failure that comes after the cancellation`;
мутации C9, P5. Первый прогон мутаций показал, что этот тест был пустым: задача
в нём стояла под `ignore()`, а `ignore()` сам гасит запрос ответа, и мутация C9
осталась зелёной. `ignore()` из теста убран.

**M5. В `solo` хук, бросивший `Cancelled`, отдаёт его в зону, а в ядре
не отдаёт.** С 2026-09-28 ядро глушит `Cancelled`, брошенный хуком наблюдателя;
запись «Fixed» в `packages/async_job/CHANGELOG.md` называет повод: «a lazy log
message that asks a cancelled job, for one». В `solo` эта правка не работает:
наблюдатель каждой задачи — `_SoloJobObserver`, он оборачивает каждый хук
в `callHook`, а `callHook` ловит всё и отдаёт в текущую зону, не разбирая.
До фильтра ядра бросок не доходит. Зонд R17b против R17c: тот же ленивый лог
на отменённой задаче даёт в `solo` `zone: [Cancelled(manual)]`, а на голом
`Job` ядра — пустую зону. Расхождение замечено 2026-10-01: ревью дизайна
нескольких наблюдателей, пункт 17 `2026-10-01-multi-observer-design.md`,
назвало его «вопросом отдельным», и с тех пор его никто не задал. Сейчас
поведение держит тест `a hook that throws switches off none of the others`
в `packages/solo/test/observer_all_test.dart`.

Вердикт: передано владельцу, вопрос — в разделе «Вопросы владельцу». Страница
поправлена так, чтобы быть верной при любом ответе (M2).

### Low

**L1. В перечне хуков, которые контроллер может переопределить, нет
`onUnanswered`.** Раздел называет семь имён, а следующий подраздел
переопределяет восьмое. Перечень дополняли при первой вычитке, до разделения
хука 2026-09-22.

Вердикт: принято: `onUnanswered` встал в перечень. Тест
`a controller that overrides the eight hooks the page names` переопределяет все
восемь и видит вызов каждого; мутация P1.

**L2. Перечень «What no outcome carries is the rest» неполон, а «an `onCancel`
callback» на этой странице — два предмета.** Туда же идут слушатель
`whenCancelled`, обработчик состояния у `run` и `keepWhile`, бросивший
на переоценке: зонды R4, R11, R10 — у всех трёх `hook […] unanswered […]`.
А `onCancel` — это и `ctx.onCancel`, и параметр `run`, обработчик состояния.

Вердикт: принято. Перечень стал списком из шести пунктов: брошенная операция;
то, что задача зовёт вне своего тела, — уборщик, колбэк `ctx.onCancel`,
слушатель `whenCancelled`, обработчик состояния у `run`; `keepWhile`, бросивший
на переоценке; работа `ctx.unattended`; провал ветки `ctx.runAll`; провал,
накрытый отменой. Предложение почти на восемьдесят слов ушло. Тесты — группа
`what no outcome carries:`, одиннадцать, по тесту на каждое имя списка
и на каждое из трёх окон накрытого провала; мутации C8, C10–C19, E3, P3, P4.

**L3. «`SoloObserver` receives the same events across controllers».** Не те же:
`onListenerError` и `onUnanswered` есть только у контроллера. Зонд
`probe_watching_test.dart`, W4: в трассе вызовов `controller.onListenerError`
и `controller.onUnanswered` стоят без пары.

Вердикт: принято: шесть хуков названы по именам, плюс `onCreate`,
и «`onUnanswered` and `onListenerError` stay with the controller alone». Тест
`what the observer is told, and what stays with the controller`; мутации E4,
E7, E10, E11, P6.

**L4. «The `job` whose `emit` made it».** Состояние, которое вернул обработчик
состояния у `run`, тоже записано на задачу, хотя её тело к тому времени
кончилось и ничего не излучало. Зонд W2: `#4 root: 3 -> -1` после провала
и `#5 cancelled: -1 -> -2` после отмены.

Вердикт: принято: «The `job` is the one whose `emit` made the change or whose
state handler returned it». Тест
`the job of a transition: an emit, a child, a handler, the outside`; мутации
E16, E17, P7.

**L5. Первая из трёх строк трассы закрытия не выходит из блока над ней.** Блок
зовёт `controller.close()`, обычное закрытие, а строка говорит
`SoloPending([stuck] in its body, draining)`: это дренаж. Зонд
`probe_holding_test.dart`, H1: блок страницы на задаче, которая не замечает
отмены, печатает
`SoloPending([stuck] in its body, closing, cancelled by Cancelled(closed))`.

Вердикт: принято: первая строка — та, которую печатает блок. Вторую и третью
дают дренаж с группой и стрим с подпиской на паузе, как сказано в прозе над
ними: H1d. Тесты — три теста о строках трассы, строки читаются со страницы;
мутации T7, T8, E24, E32, E34–E37, P8–P10.

**L6. У ребёнка рецепты `Hangs` и `StuckCancellations` печатают снимок корня.**
«One that does not is still the job the controller is on, so the snapshot in
the line is about it» — неверно для дочерней задачи: `onStart` приходит
и за ней, а `solo.pending` снимает корневую. Зонды H6c
и `probe_slow_test.dart`, S6c:
`child is still running: SoloPending([root] in its body)`
и `child has not stopped: SoloPending([root] in its body,
cancelled by Cancelled(manual))`.

Вердикт: принято. У `Hangs`: «One that does not is named at the front of its
line. The snapshot beside the name is of the root job the controller is on,
which is the same job unless the one that hangs is a child»;
у `StuckCancellations` — «A child the cancellation passed to gets a line of its
own, and the snapshot in it is of the root again». Тесты
`a child that hangs under its root` и `a child the cancellation passed to`;
мутации C32, E31, P13.

**L7. «It reports and does not diagnose».** У местоимения нет хозяина: абзацем
выше речь о пяти секундах, двумя — о таймере. До 2026-09-22 абзац стоял под
описанием снимка, потом между ними встал рецепт. И «a resource that takes its
time to release» выглядит не «так же»: у него фаза `cleanup`, зонд H7 —
`SoloPending([slow] in its cleanup)`.

Вердикт: принято: «The snapshot reports…», а о ресурсе — «holds the job as
long, in its `cleanup` phase». Тесты
`the phase of a body: through the context, bare, inside a call`
и `a resource that takes its time to release`; мутации E27, E28, E31.

**L8. «Takes effect» и «accepts» — два слова для одного.** С 2026-09-25 все
страницы говорят, что задача отмену «accepts», и таблица полей здесь говорит
так же. Абзац о числе рецепта и комментарий в блоке, написанные днём позже,
говорили «takes effect». Больше нигде в документах этого оборота нет.

Вердикт: принято: «from the moment the job accepted the cancellation», «is
accepted when the section ends», комментарий — «fires when the job accepts the
cancellation». Мутация P33.

**L9. «Reported delay: 0 ms».** Рецепт сообщает только о задержке больше 50 мс,
так что о двух нижних строках таблицы он не сообщает ничего. Зонд
`probe_slow_test.dart`, S2: рецепт страницы печатает одну строку,
`bare ran 290 ms past its cancellation`; тот же рецепт без порога — `290`, `0`,
`0`.

Вердикт: принято: столбец назван «the number», а под таблицей сказано: «Only
the first row is a line in the log: the other two stay under the 50 ms the
observer starts reporting at». Числа таблицы читает со страницы
`cancel_delay_recipe_test.dart`; мутации T12, P14–P16, P39.

**L10. «This page has made four by now».** К этому месту классов-наблюдателей
на странице пять: четвёрка из блока и `SlowJobs`, первая попытка.

Вердикт: принято: «this page has four to install by now». Мутации T16, T17,
P19.

**L11. «The same observer twice in the list throws `ArgumentError`».** Бросает
не наблюдатель, а `SoloObserver.all`.

Вердикт: принято: «The same observer twice in the list, and `SoloObserver.all`
throws `ArgumentError`», как на странице ядра о наблюдении. Мутация E14.

**L12. «Handle those futures with `await`, `catchError` or `ignore()`».**
На этой странице `ignore()` строкой выше — `Job.ignore()`, а здесь нужен
`Future.ignore()`; `testing.md` эти два разводит прямо. Зонд
`probe_failures_test.dart`, F7c: future взята, следом `job.ignore()` — в зоне
`Cancelled(manual)`. И `catchError` принимает обработчик как `Function`; его
типизированная замена в SDK — `onError`.

Вердикт: принято: «`await` them where the error is caught, or give them
`onError` or `Future.ignore()`. `job.ignore()` does nothing for a future
already taken». Тест `job.ignore() on a job whose value is already taken`;
мутация P21.

**L13. «A `Cancelled` that arrives this way… they see it» — кроме собственной
отмены задачи.** Брошенная операция, которая сама зовёт контекст после отмены,
получает отмену своей же задачи, и о ней не сообщают никому. Зонд F6c:
`hook [] unanswered []`.

Вердикт: принято: пример назван — «ended in the cancellation of another job,
say», и в конце абзаца: «The job's own cancellation, thrown back by such an
action, is news to nobody and is not reported at all». Тест
`an abandoned call that throws back the cancellation of its job`; мутации C42,
P41.

**L14. «The `onError` handler of that same `run` does not answer for it
either».** «Отвечать» на этой странице — дело `onUnanswered`, а обработчик
состояния вычисляет состояние; у «either» нет пары: до этой фразы никто
не отказывался отвечать.

Вердикт: принято: «The state handler passed as `onError` to that same `run` is
not called for it: a state handler computes the state after a job that ran».
Мутации E44, P27.

**L15. «It finds out at the next `ctx.state` or `ctx.check()`».**
И на ожидающем методе: зонд `probe_rules_test.dart`, U3e — после своего `emit`
задача доходит до `ctx.wait`, получает `Cancelled(rules: keepWhile)`, и вызов
не начинается.

Вердикт: принято: «at its next checkpoint — a `ctx.state`, a `ctx.check()`, a
waiting method». Три теста, по одному на вид контрольной точки; мутации E51,
E55, P28.

**L16. Последняя строка таблицы «Where it throws».** «A check that also
controls a final state handler» — слова, по которым читатель не узнаёт своей
ситуации; у `state.md` тот же случай зовётся «A rule throws while eligibility
is checked». И подводка обещает «who hears about it», а столбец — «What
happens». Зонд U4d и U4f: у задачи с обработчиком состояния о броске правила
сообщают, обработчик не идёт, и перепроверяют её и после конца тела.

Вердикт: принято: строка — «The same re-evaluation, on a job with a state
handler | Reported, and the handler is disabled», подводка — «decides what
becomes of the error», и новая фраза ведёт в «Handler eligibility and errors»
страницы о состоянии. Тесты — группа `where a rule throws:`, одиннадцать;
мутации E42, E43, E47–E50, E64–E66, P29.

**L17. «Reported through the job's error hooks… with the same zone fallback».**
Хуки не задачи, а контроллера; «the same» отсылает через две секции. Разница
с первой попыткой в зоне, а она не названа: зонд `probe_background_test.dart`,
B2 — ошибка `unawaited` всплывает в зоне, где шло тело, а ошибка работы
`ctx.unattended` кончает в зоне, где задачу создали.

Вердикт: принято: «Its errors stay with the job, even after the job finishes:
the reporting hooks are told, `onUnanswered` is asked to answer, and with
nothing to answer they end in the zone the job was created in». Тесты
`the zone it surfaces in is the one the body ran in`
и `the zone it ends in is the one the job was created in`; мутации C16, C21,
P30.

**L18. `message is Object Function()`.** Колбэк, который может вернуть `null`,
этой проверки не проходит, и логгер получает само замыкание: зонд B6c,
`fine (a closure, 1, a plain line)`. Страница ядра о наблюдении пишет
`Object? Function()`.

Вердикт: принято: в блоке `Object? Function()`. Тест
`a callback that may return null, and a plain message`; мутации T30, P31.

**L19. «Nothing is called on the way either».** Пара этому «either» — «as it
is» двумя предложениями раньше, а между ними встали два предложения о каналах
отладки.

Вердикт: принято: «`ctx.log` calls nothing on the way either». Мутация C37.

**L20. Блок `LoggingObserver` стоял не так, как его оставляет `dart format`.**
`onStart` был разорван после стрелки, хотя строка умещается в восемьдесят
символов. Нашла сверка кода: форматированный support-файл со страницей
не сошёлся.

Вердикт: принято: блок в обоих файлах стоит одной строкой. Мутация P32.

**L21. Перевод.** В файле стояло тридцать шесть тире; «reporting hooks» звались
то «хуками диагностики», то «хуком отчёта»; сканер отмечал «является»,
«в соответствии с» и определение через тире.

Вердикт: принято; подробности — в разделе «Перевод».

**L22. `log(...)` в рецептах без хозяина, а рядом на странице `ctx.log`.**

Вердикт: отклонено. В наблюдателе контекста нет, и спутать свободную функцию
с `ctx.log` негде; владелец читал три рецепта с этим именем и вопроса не задал.

**L23. «The second stands still».** `DateTime.now()` под `fake_async` не стоит,
а идёт по настоящим часам.

Вердикт: отклонено. За триста фейковых миллисекунд он сдвигается меньше чем
на пять настоящих, зонд S8, и для рецепта это и есть «стоит на месте». Тест
`clock.now() and DateTime.now() under fake time`; мутации T13, P40.

**L24. «A cancellation that never lands».** В dartdoc ядра «lands» значит
«принята», а здесь — «задача остановилась».

Вердикт: отклонено. На странице слово стоит в одном значении, а на заголовок
ведёт якорь из `packages/solo/CHANGELOG.md`.

**L25. `Hangs` сообщит и о ребёнке `ctx.each`, который по делу живёт столько,
сколько открыт стрим.**

Вердикт: отклонено. Абзац «Five seconds is a statement about the domain»
говорит ровно об этом, а кого не считать зависшим, решает приложение.

**L26. «If the load fails and a cancellation reaches the job afterwards» —
граница в микротасках.** Зонд `probe_covered_test.dart`: отмена в том же
синхронном ходе, что и сбой вызова, застаёт `ctx.wait` ещё не узнавшим о сбое,
и провал идёт путём брошенной операции — `ignore()` его не гасит. Микротаской
позже это уже провал, накрытый отменой, и `ignore()` его гасит. Тремя
микротасками позже задача успевает кончиться `Failed`.

Вердикт: отклонено. Оба пути страница описывает, и оба кончаются
у `onUnanswered`; между событием сбоя и следующим событием микротаски
отрабатывают целиком, так что первое окно достижимо только из кода, который
отменяет задачу в том же синхронном ходе. Тесты накрытого провала отменяют
задачу микротаской позже сбоя.

## Чего ревью не нашло, но нашлось рядом

Прежний сторож держал не код страницы, а свои контроллеры, и поэтому H1 прожил
с 2026-09-20: первая попытка раздела о перехвате шла со строкой, которой
на странице нет. Рецепты `Hangs`, `SlowJobs`, `SlowCancellations`
и `StuckCancellations` стояли в нём копиями, где `log` заменён списком. Теперь
код страницы стоит в support-файлах дословно, и сверка читает его со страницы.

dartdoc класса `Solo` в `packages/solo/lib/src/solo.dart` с 2026-09-22 называл
хуком «with a body of its own» `onError`, чьё тело пусто, и вёл ошибку из него
сразу в зону, минуя `Solo.errorHandler`. Абзац поправлен этим же коммитом:
в перечне хуков есть `onUnanswered`, тело своё — у него, и ведёт оно
к `errorHandler`, а в зону — когда обработчика нет. Поведение не менялось,
`dart doc --dry-run` — «Found 0 warnings and 0 errors».

Рецепты `Hangs` и `StuckCancellations` собраны из публичной поверхности,
а снимка для дочерней задачи в ней нет: `solo.pending` снимает корневую (L6).
Это довод к записи бэклога об общем отлове зависаний; запись не трогалась.

Соседние страницы правка не задела. `cancellation.md` и `resources.md` ведут
в «Answering for an error» «за всем маршрутом» и в «What is holding the
controller» — оба раздела на месте, и маршрут там тот же. `jobs.md`,
`state.md`, `testing.md` и README ведут в «Handled and unhandled failures»,
«Watching every controller» и «Why cancellation was slow». Три записи «Added»
в `packages/solo/CHANGELOG.md` ведут в «A cancellation that never lands»,
«Stamping the cancellation» и «Answering for an error»: `SoloObserver.all`,
строка `ctx.pause` и `Job.visitErrors` стоят там, куда ведут ссылки. Новый
ответ раздела о перехвате совпал с тем, что `cancellation.md` советует
в разделе «The token».

Шапка `2026-09-20-errors-rakes-report.md` говорит о состоянии на 2026-10-01.
В коммит вычитки старая запись не входит; при переносе в `main` её шапку стоит
дополнить руками: повторная вычитка —
`2026-10-04-solo-errors-reread-report.md`.

`docs/handoff.md` основная сессия обновит при переносе: у сторожа `errors.md`
теперь четыре support-файла и 166 тестов вместо 63, а пункт о ветке
`on Cancelled { rethrow; }`, оставленный этой вычитке, закрыт находкой M1.

## Вопросы владельцу

**Глушить ли в `solo` `Cancelled`, брошенный хуком, как это делает ядро?** Хуки
контроллера и `SoloObserver` зовутся через `callHook`: всё, что хук бросил,
уходит в текущую зону, `Cancelled` тоже. Ядро с 2026-09-28 `Cancelled` из хука
своего наблюдателя в зону не пускает, но в `solo` до этого фильтра бросок
не доходит. Практический случай — ленивый лог со страницы: хук `onLog` зовёт
колбэк сообщения, колбэк читает `ctx.state`, задача к этому времени отменена —
и в зоне `Cancelled(manual)`, во Flutter это запись
в `PlatformDispatcher.onError` на обычную отмену.

- Оставить как есть. Правило `solo` простое: ошибка хука идёт в зону, какая бы
  она ни была. Страница при этом уже верна: она больше не говорит, что движок
  не отдаёт `Cancelled` в зону никаким своим путём. Цена — зонд
  `probe_reporting_test.dart`, R17 и R17b: `zone: [Cancelled(manual)]` там, где
  на голом `Job` ядра зона пуста (R17c).
- Глушить, как ядро. Прототип — `Q1` в `mutate.py`: `callHook` спрашивает
  `Job.visitErrors` и отдаёт в зону только то, в чём есть провал; шесть строк
  в `packages/solo/lib/src/call_hook.dart`. Набор `solo` целиком с прототипом —
  один красный тест, `a hook that throws switches off none of the others`
  в `observer_all_test.dart`, который и держит нынешнее правило
  (`probes/q1_prototype.out`); R17 и R17b дают пустую зону, а ошибка хука,
  которая не отмена, доходит до зоны по-прежнему (`probes/q1_probe.out`).
  Понадобятся запись «Fixed» в `packages/solo/CHANGELOG.md` и правка одного
  утверждения этого теста; страница не меняется.

## Сторож

`packages/solo/test/errors_rakes_test.dart` — 166 тестов, было 63;
`packages/solo/test/cancel_delay_recipe_test.dart` — девять, как было. Код
страницы дословно стоит в `test/support/`. `errors_page.dart` — контроллер
с хуком отчёта, наблюдатель лога и `main`, закрытие с таймаутом, `Hangs`,
`SlowCancellations`, `StuckCancellations`, четверо под `SoloObserver.all`,
`load()` с `ignore()`, `catch`, который спрашивает задачу, правило, которое
отвечает, работа `ctx.unattended`, три строки логов и хук `onLog`.
`errors_page_answering.dart` — оба блока раздела «Answering for an error»:
страница показывает там вторую версию класса `ProfileController`,
а в библиотеке класс с таким именем один. `errors_first_attempts.dart` — пять
первых попыток. Приложение вокруг кода — `errors_stubs.dart`: состояния и API
профиля из быстрого старта, `reportCrash`, `Sentry`, `log`, камера с её
состояниями и токеном, слоты, аналитика, устройство и логгер с уровнями, миксин
`Desk` с тем, что тестам нужно от контроллера сверх страницы, и `Bench` —
контроллер, тела задач которого пишутся в самих тестах. Запускаются все
двадцать блоков `dart`; блоков, которые сторож запустить не может, нет.

Вызов заглушки идёт, пока тест его не завершит, поэтому каждая трасса — тот
порядок, который задал тест. Весь файл идёт под `fakeAsync`; прежний шёл
на настоящих таймерах нулевой длины через `pumpEventQueue`. Что дошло до зоны
и что напечатано, собирает зона вокруг сценария, а утверждения стоят снаружи
неё.

Сверка кода идёт по заголовкам: `### The first attempt` — с файлом попыток,
`### Answering for an error` — со своим файлом, десять остальных заголовков,
под которыми есть код, — с файлом ответов, и ещё раз вся страница по трём
файлам. Отдельный тест требует, чтобы каждый заголовок с кодом был в этом
списке; `strayFences` пуст. Со страницы читаются три блока цитат — шесть строк
лога, и каждую печатает код страницы в своём сценарии, — три таблицы: у таблицы
полей имена, у двух других обе ячейки каждой строки, — и больше ста фраз прозы:
тест, который проверяет фразу, первой строкой требует, чтобы страница её
говорила. `cancel_delay_recipe_test.dart` гоняет отметку рецепта без порога
в 50 мс, чтобы прочитать и нули; его шапка теперь так и говорит, а числа
и фразу о секции он читает со страницы.

Где код страницы стоит в тестах не строка в строку. Закрытие с таймаутом стоит
под `// ignore: require_trailing_commas`: линт пакета просит запятую, с которой
`dart format` перекладывает блок иначе, чем на странице и в dartdoc
`Solo.pending`; помощник сверки такие строки пропускает. Фрагменты страницы
стоят в функциях и методах, помеченных «Not on the page»: `closeWithTimeout`,
`installAll`, `loadAndIgnore`, `sendZoom`, `logZoom`, `logLazily`,
`traceTheEngine`, `traceTheCore`, `installErrorHandler`, тела `Camera.open`,
`BroadCamera.open`, `Pool.take` и `ThrowingPool.take`. Задачи быстрого старта,
которые страница сокращает до комментария, стоят под этим комментарием.

Что страница утверждает о движке, а её код не показывает, держат тела
на `Bench`: каждый пункт списка «исход не несёт», маршрут обработчика, зоны,
порядок хуков наблюдателя и контроллера, поля снимка и фазы, трассы отмены
по правилам, строки таблицы правил, отказ контекста в работе `ctx.unattended`,
захваченный контекст, два канала отладки. Камера с токеном — класс
`_TokenCamera` в самом тесте: у камеры страницы токена нет.

Чего сторож запустить не может. «Taking it costs most of what a change costs» —
утверждение о скорости: зонд `probe_rules_test.dart`, U5, двадцать тысяч
изменений с трассой — около 40 мс, без неё — 3,7. «It is a leaf package, and
`fake_async` depends on it anyway» сверено чтением: у `clock` 1.1.3
в `pubspec.yaml` нет зависимостей, у `fake_async` 1.3.3 — `clock`
и `collection`. `Sentry`, `logger` и `Level` в тестах — заглушки с теми же
именами членов. Что «The token» страницы об отмене заводит токен, держит её
сторож, а что «Catching errors of the operation» страницы ядра разбирает ветку
`on Cancelled`, — сторож страницы ядра; здесь `check_links.py` сверяет, что
разделы существуют, а оба поведения в `solo` держат свои тесты.

## Мутации

`.artifacts/2026-10-04-solo-errors-reread/mutate.py`, журнал `mutations.out`:
правка ядра, движка, кода страницы в support-файлах или текста страницы, прогон
обоих сторожей, красные по меткам `[E]`. После каждой мутации файл возвращён
из снимка `snapshot/mutate/` и сверен `cmp`; `git status` после прогона
показывает в `lib/` одну правку — dartdoc класса `Solo`. Таблица — прогон всех
мутаций на итоговых сторожах и итоговой странице; `table.py` рядом собирает её
из журнала.

| Мутация | Красных в `errors_rakes_test.dart` | в `cancel_delay_recipe_test.dart` |
| --- | --- | --- |
| C1 ядро: ненаблюдённый провал не уходит в зону | 5 | 0 |
| C2 ядро: чтение `done` не считается наблюдением | 2 | 0 |
| C3 ядро: чтение `value` не считается наблюдением | 2 | 0 |
| C4 ядро: `ignore()` не считается наблюдением | 9 | 0 |
| C5 ядро: `ignore()` не гасит провал, который накрыла отмена | 1 | 0 |
| C6 ядро: о провале тела наблюдателю не рассказывают | 20 | 0 |
| C7 ядро: об ошибке, рассказанной за ребёнка, за родителя не рассказывают | 1 | 0 |
| C8 ядро: за провал, который накрыла отмена, ответа не спрашивают | 4 | 0 |
| C9 ядро: за провал после отмены спрашивают ответ, как за провал до неё | 1 | 0 |
| C10 ядро: провал датируется броском тела, а не тем, когда случился | 2 | 0 |
| C11 ядро: отмена, пришедшая после провала тела, исход не меняет | 6 | 0 |
| C12 ядро: ошибка колбэка уборки проглатывается | 12 | 0 |
| C13 ядро: ошибка слушателя `whenCancelled` проглатывается | 1 | 0 |
| C14 ядро: ошибка колбэка `ctx.onCancel` проглатывается | 1 | 0 |
| C15 ядро: поздняя ошибка вызова, отпущенного `wait`, пропадает | 7 | 0 |
| C16 ядро: ошибка работы `ctx.unattended` уходит мимо задачи | 8 | 0 |
| C17 ядро: провал ветки, который группа не бросила, пропадает | 1 | 0 |
| C18 ядро: об ошибке без исхода рассказывают, а ответа не спрашивают | 37 | 0 |
| C19 ядро: ошибка хука движка `finished` проглатывается | 1 | 0 |
| C20 ядро: `Cancelled` без исхода уходит в зону, как любая ошибка | 2 | 0 |
| C21 ядро: ошибка без исхода уходит в текущую зону | 2 | 0 |
| C22 ядро: `wait` из одних отмен для зоны считается провалом | 1 | 0 |
| C23 ядро: `Job.visitErrors` отдаёт `ParallelWaitError` целиком | 1 | 0 |
| C24 ядро: `wait` дожидается своего вызова | 19 | 3 |
| C25 ядро: `pause` досиживает задержку до конца | 1 | 2 |
| C26 ядро: `pause` оставляет свой таймер | 0 | 1 |
| C27 ядро: `pause` переспрашивает правила, когда время вышло | 0 | 1 |
| C28 ядро: `join` отпускает вызов, как `wait` | 9 | 0 |
| C29 ядро: секция ничего не удерживает | 5 | 3 |
| C30 ядро: слушатели слышат придержанную отмену сразу | 3 | 3 |
| C31 ядро: слушатели слышат отмену только в конце задачи | 6 | 8 |
| C32 ядро: отмена не переходит к детям | 1 | 0 |
| C33 ядро: `cancel()` не ждёт задачу | 1 | 2 |
| C34 ядро: задача с `cancellable: false` принимает отмену | 3 | 0 |
| C35 ядро: работа `ctx.unattended` может запустить ребёнка и открыть секцию | 2 | 0 |
| C36 ядро: отказ внутри работы `ctx.unattended` не называет вызов | 2 | 0 |
| C37 ядро: `ctx.log` зовёт сообщение-колбэк | 1 | 0 |
| C38 ядро: `Job.debug` не трассирует старт задачи | 2 | 0 |
| C39 ядро: `Job.debug` не трассирует ошибку, за которую не ответили | 1 | 0 |
| C40 ядро: наблюдатель слышит `onFinish`, когда задача принимает отмену | 5 | 8 |
| C41 ядро: `Cancelled` не реализует `Exception` | 1 | 0 |
| C42 ядро: о собственной отмене задачи из брошенного вызова сообщают | 1 | 0 |
| E1 движок: `Solo.errorHandler` не спрашивают никогда | 10 | 0 |
| E2 движок: при заданном обработчике ошибка уходит ещё и в зону | 9 | 0 |
| E3 движок: у контроллера не спрашивают ответа | 37 | 0 |
| E4 движок: ответа спрашивают ещё и у наблюдателя | 4 | 0 |
| E5 движок: хуку `onError` контроллера не рассказывают | 37 | 0 |
| E6 движок: `Solo.observer` об ошибках не рассказывают | 5 | 0 |
| E7 движок: `onStart` контроллера зовётся раньше наблюдателя | 3 | 0 |
| E8 движок: хук, который бросил, не изолирован | 2 | 0 |
| E9 движок: ошибка хука проглатывается | 4 | 0 |
| E10 движок: наблюдателю не говорят о созданном контроллере | 4 | 0 |
| E11 движок: о слушателе, который бросил, говорят наблюдателю | 1 | 0 |
| E12 движок: `SoloObserver.all` зовёт наблюдателей с конца списка | 1 | 0 |
| E13 движок: `SoloObserver.all` не изолирует наблюдателей | 1 | 0 |
| E14 движок: `SoloObserver.all` принимает одного наблюдателя дважды | 1 | 0 |
| E15 движок: `revision` не растёт | 2 | 0 |
| E16 движок: изменение ребёнка записано на корневую задачу | 2 | 0 |
| E17 движок: состояние, которое вернул обработчик, не принадлежит ни одной задаче | 1 | 0 |
| E18 движок: внешнее изменение записано на работающую задачу | 7 | 0 |
| E19 движок: `pending` не несёт принятую отмену | 5 | 0 |
| E20 движок: `pending` не несёт придержанную отмену | 2 | 0 |
| E21 движок: `pending` не считает детей | 1 | 0 |
| E22 движок: `pending` не говорит об открытой секции | 1 | 0 |
| E23 движок: `pending` не говорит, что задача отклоняет отмену | 2 | 0 |
| E24 движок: `pending` не говорит, что контроллер закрывается | 4 | 0 |
| E25 движок: `pending` не говорит, что закрытие идёт дренажом | 1 | 0 |
| E26 движок: `pending` называет не ту задачу | 1 | 0 |
| E27 движок: фаза остаётся `body`, пока задача ждёт детей | 1 | 0 |
| E28 движок: фаза остаётся `body`, пока идёт уборка | 2 | 0 |
| E29 движок: `cancellationPending` считает одну принятую отмену | 1 | 0 |
| E30 движок: `cancellationPending` истинно у задачи, которая отклоняет отмену | 1 | 0 |
| E31 движок: снимок задачи печатает фазу другими словами | 11 | 0 |
| E32 движок: снимок задачи не печатает, чем она отменена | 4 | 0 |
| E33 движок: снимок задачи не печатает придержанную отмену | 1 | 0 |
| E34 движок: дренаж без работающей задачи читается как `null` | 1 | 0 |
| E35 движок: снимок очереди не печатает задач | 1 | 0 |
| E36 движок: стрим, ждущий подписку, читается как `null` | 1 | 0 |
| E37 движок: стрим закрывается, не дожидаясь подписок | 1 | 0 |
| E38 движок: задача ещё текущая, пока идёт её хук `onFinish` | 1 | 0 |
| E39 движок: `close()` не ждёт работающую задачу | 4 | 1 |
| E40 движок: `close()` не отменяет работающую задачу | 3 | 1 |
| E41 движок: дренаж сбрасывает очередь, как обычный `close()` | 2 | 0 |
| E42 движок: стартовое правило, которое бросило, отменяет задачу | 5 | 0 |
| E43 движок: очередь встаёт на задаче, чьё стартовое правило бросило | 3 | 0 |
| E44 движок: обработчик состояния идёт у задачи, которая не стартовала | 2 | 0 |
| E45 движок: задача, которой стартовое правило отказало, проваливается | 3 | 0 |
| E46 движок: задача, которой стартовое правило отказало, считается стартовавшей | 1 | 0 |
| E47 движок: о правиле, бросившем на переоценке, не сообщают | 5 | 0 |
| E48 движок: правило, бросившее на переоценке, отменяет тело | 3 | 0 |
| E49 движок: правило, которое бросило, оставляет обработчик состояния разрешённым | 2 | 0 |
| E50 движок: задачу с обработчиком состояния не перепроверяют после конца тела | 1 | 0 |
| E51 движок: задачу перепроверяют на её собственном `emit` | 3 | 0 |
| E52 движок: изменение никогда не записывает трассу | 5 | 0 |
| E53 движок: изменение записывает трассу при любом значении переключателя | 4 | 0 |
| E54 движок: переключатель включён там, где проверки выключены | 1 | 0 |
| E55 движок: контрольная точка забывает трассу изменения | 3 | 0 |
| E56 движок: задача, отменённая правилами на изменении, получает трассу отказа | 2 | 0 |
| E57 движок: отказ стартового правила несёт трассу последнего изменения | 1 | 0 |
| E58 движок: `emit` не проверяет отмену до записи | 4 | 0 |
| E59 движок: `check` спрашивает правила, но не отмену | 7 | 0 |
| E60 движок: контекст кончившейся задачи всё ещё пишет состояние | 1 | 0 |
| E61 движок: `Solo.debug` не трассирует постановку в очередь | 2 | 0 |
| E62 движок: `Solo.debug` не трассирует закрытие | 1 | 0 |
| E63 движок: об изменении говорят хукам, а состояние не записано | 27 | 0 |
| E64 движок: о правиле, бросившем в контрольной точке, ещё и сообщают | 2 | 0 |
| E65 движок: обработчик состояния не идёт у задачи, которая работала | 10 | 0 |
| E66 движок: задачу без обработчика состояния перепроверяют после конца тела | 1 | 0 |
| T1 хук отчёта: ничего не отправляет | 7 | 0 |
| T2 контроллер с ответом: переопределение сохраняет маршрут по умолчанию | 3 | 0 |
| T3 обработчик: отправляет ошибку целиком | 3 | 0 |
| T4 наблюдатель лога: печатает ключ, а не задачу | 5 | 0 |
| T5 наблюдатель лога: печатает состояние до изменения | 4 | 0 |
| T6 старт приложения: наблюдатель не установлен | 4 | 0 |
| T7 закрытие с таймаутом: закрывает дренажом | 3 | 0 |
| T8 закрытие с таймаутом: таймаут полминуты | 4 | 0 |
| T9 `Hangs`: таймер заводится на конце задачи | 9 | 0 |
| T10 `Hangs`: таймер не снимается | 3 | 0 |
| T11 отметка отмены: отметка ставится на старте | 8 | 0 |
| T12 отметка отмены: без порога | 5 | 0 |
| T13 отметка отмены: `DateTime.now()` на месте `clock.now()` | 5 | 0 |
| T14 `StuckCancellations`: таймер заводится на старте | 4 | 0 |
| T15 `StuckCancellations`: таймер не снимается | 2 | 0 |
| T16 четверо в одном: в списке нет `Hangs` | 3 | 0 |
| T17 четверо в одном: установлен один последний | 3 | 0 |
| T18 наблюдение исхода: без `ignore()` | 3 | 0 |
| T19 ответ о перехвате: проверка стоит под сбросом | 6 | 0 |
| T20 ответ о перехвате: проверки нет | 6 | 0 |
| T21 ответ о перехвате: камеру не сбрасывает | 4 | 0 |
| T22 ответ о перехвате: `Broken` не публикует | 4 | 0 |
| T23 ответ о перехвате: провал проглочен | 4 | 0 |
| T24 правило отвечает: правило бросает | 3 | 0 |
| T25 правило отвечает: ему нужно два свободных слота | 3 | 0 |
| T26 работа со своей жизнью: отправка через `unawaited` | 5 | 0 |
| T27 логи: данные логируются строкой | 3 | 0 |
| T28 логи: строка собрана до вызова | 3 | 0 |
| T29 логи: хук не зовёт колбэк | 4 | 0 |
| T30 логи: хук зовёт только колбэк, который не возвращает `null` | 3 | 0 |
| T31 логи: хук не спрашивает уровень | 3 | 0 |
| T32 логи: трасса движка не включена | 4 | 0 |
| T33 логи: трасса ядра не включена | 4 | 0 |
| T34 первая попытка, `SlowJobs`: отметка ставится на отмене | 3 | 0 |
| T35 первая попытка, `SlowJobs`: без порога | 3 | 0 |
| T36 первая попытка, `Failures`: исход ещё и наблюдён | 3 | 0 |
| T37 первая попытка, `Failures`: об отмене тоже отправляет отчёт | 3 | 0 |
| T38 первая попытка, широкий `catch`: ветка пропускает `Cancelled` | 5 | 0 |
| T39 первая попытка, широкий `catch`: без сброса | 8 | 0 |
| T40 первая попытка, правило: отвечает | 4 | 0 |
| T41 первая попытка, отправка: отдана `ctx.unattended` | 2 | 0 |
| T42 первая попытка, правило: бросает и при свободном слоте | 3 | 0 |
| T43 первая попытка, широкий `catch`: сброс и после успеха | 1 | 0 |
| T44 ответ о перехвате: сброс и после успеха | 1 | 0 |
| P1 страница: в списке хуков нет `onUnanswered` | 1 | 0 |
| P2 страница: хуку рассказывают один раз, о ребёнке ни слова | 1 | 0 |
| P3 страница: в списке «исход не несёт» нет обработчика состояния | 1 | 0 |
| P4 страница: в том же списке нет `keepWhile`, который бросил | 1 | 0 |
| P5 страница: о провале после отмены не сказано, что ответа не спрашивают | 1 | 0 |
| P6 страница: наблюдатель получает «те же события» | 1 | 0 |
| P7 страница: `job` перехода только та, чей `emit` сделал изменение | 1 | 0 |
| P8 страница: первая строка трассы закрытия взята у дренажа | 1 | 0 |
| P9 страница: вторая строка трассы считает две задачи | 1 | 0 |
| P10 страница: третья строка трассы говорит другое | 1 | 0 |
| P11 страница: в таблице полей нет `draining` | 2 | 0 |
| P12 страница: строка зависания придержанной задачи цитирует принятую отмену | 1 | 0 |
| P13 страница: снимок зависания всегда о зависшей задаче | 1 | 0 |
| P14 страница: в таблице 300 мс у голого `await` | 2 | 1 |
| P15 страница: в таблице 10 мс у `ctx.wait` | 1 | 1 |
| P16 страница: в таблице нет строки `ctx.pause` | 1 | 1 |
| P17 страница: вызвавший `cancel` ждал 100 мс | 2 | 2 |
| P18 страница: строка `StuckCancellations` цитирует придержанную отмену | 1 | 0 |
| P19 страница: ставить пора пятерых наблюдателей | 1 | 0 |
| P20 страница: движок не отдаёт `Cancelled` в зону никаким своим путём | 2 | 0 |
| P21 страница: `catchError` и `ignore()` для future, которую уже взяли | 1 | 0 |
| P22 страница: первая попытка сбрасывает камеру, которую задача не открывала | 2 | 0 |
| P23 страница: ответ о перехвате заменён веткой `on Cancelled` | 2 | 0 |
| P24 страница: ответ о перехвате заменён первой попыткой | 1 | 0 |
| P25 страница: первая попытка о перехвате заменена ответом | 1 | 0 |
| P26 страница: камеру, упавшую после отмены, ответ всё равно сбрасывает | 1 | 0 |
| P27 страница: обработчик состояния «тоже не отвечает» | 1 | 0 |
| P28 страница: задача узнаёт на ближайшем `ctx.state` или `ctx.check()` | 3 | 0 |
| P29 страница: последняя строка таблицы правил в прежнем виде | 1 | 0 |
| P30 страница: ошибки `ctx.unattended` идут «хукам ошибок задачи» | 1 | 0 |
| P31 страница: хук лога проверяет `Object Function()` | 2 | 0 |
| P32 страница: наблюдатель лога рвёт строку после стрелки | 2 | 0 |
| P33 страница: комментарий отметки говорит «takes effect» | 2 | 0 |
| P34 страница: «Six sections below» | 1 | 0 |
| P35 страница: первая попытка под другим заголовком | 2 | 0 |
| P36 страница: блок трассы под забором `console` | 5 | 0 |
| P37 страница: обработчик без `Job.visitErrors` | 2 | 0 |
| P38 страница: под первой попыткой стоит правило, которое отвечает | 1 | 0 |
| P39 страница: у блока отметки другой порог | 2 | 0 |
| P40 страница: с фальшивым временем идёт `DateTime.now()` | 1 | 0 |
| P41 страница: о любом `Cancelled` из брошенного вызова сообщают | 1 | 0 |

Все 193 красные, и каждый из 175 тестов двух сторожей краснеет хотя бы
от одной; у `cancel_delay_recipe_test.dart` красных мутаций пятнадцать,
и каждый из девяти его тестов краснеет хотя бы от двух. Журнал первого прогона
лежит в `round1/`: 181 мутация на 165 тестах. Он показал три вещи. Мутация C9 —
за провал после отмены спрашивают ответ — осталась зелёной: тест ставил задачу
под `ignore()`, а `ignore()` запрос ответа гасит сам (M4). Два теста носили
одно имя: два цикла по ветке `on Cancelled` и проверке типа. И десять тестов
не краснели ни от чего. Все десять верны, но мутации под них не было: рецепты,
читающие `onFinish`, молчат о зависании — C40; `Cancelled` реализует
`Exception` — C41; `clock.now()` против `DateTime.now()` — P40; обе версии
`catch` на пути без отмены и без сбоя — T43 и T44; ветка `on Cancelled` при
настоящем сбое камеры — E63; первая попытка правила при свободном слоте — T42;
правило, бросившее в контрольной точке, о котором никому, кроме тела,
не сообщают, — E64; обработчик состояния у задачи, чьё правило держится, — E65;
задача без обработчика, которую после конца тела не перепроверяют, — E66. Ещё
две, C42 и P41, пришли с абзацем о собственной отмене задачи (L13).

Каждую мутацию кода страницы в support-файлах, T1–T44, кроме сверки кода ловит
свой тест поведения. P23, P24 и P25 — ответ раздела о перехвате, заменённый
веткой или первой попыткой, и наоборот — ловит сверка по заголовку.

`Q1` в том же файле — не мутация, а прототип к вопросу владельцу; в общий
прогон он не входит, запускается по имени, `mutate.py --full Q1`.

## Перевод

`docs/ru/solo/errors.md` правлен вместе с оригиналом: те же абзацы и те же
блоки кода с русскими комментариями, `check_translations.py` — двадцать два
заголовка и двадцать три блока в обоих файлах, считая три блока цитат.
Правленые абзацы прошли `humanizer-ru`. Сканер `uvx ru-humanizer` с `--before`
против перевода до вычитки: было 87, стало 90, жёстких запретов нет,
единственная отметка — заголовки `##`; ушли «является», «в соответствии с»
и определение через тире. Тире в файле было тридцать шесть, не осталось
ни одного. Правка по существу задела большинство абзацев, а где не задела, тире
сняты перестройкой фразы: «членом, названным по вопросу, который вы задаёте,
или вызовом…», «выше, принятая или придержанная», «пока экран ещё открыт
и никто ничего не закрывает», «Пять секунд говорят о предметной области»,
«`onStart` и `onFinish` приходят на двух концах задачи, и разница между ними
равна времени её жизни», «о самой долгой отмене из всех, о той, что
не кончается, она как раз молчит», «может завершить приложение через мгновение
после того, как отправили отчёт», «Бросок читается как отказ, а оказывается
провалом», «Ответ `false` от правила ошибкой не считается», «этот вызывающий
код не ждёт. Больше он не говорит ничего», «а звать его или нет, пусть решает
уровень».

«Reporting hooks» по всей странице — «хуки отчёта», как в комментарии второго
блока; «хуки диагностики» ушли. «Обработчика» в «хук зовёт обработчик» стало
«обработчик»: слово неодушевлённое.

Скилл просит отдать чистовик на сверку свежему агенту; субагентов задание
запрещает, поэтому чистовик перечитан холодно самим автором по тому же брифу.
Перечитывание сняло два места. «Хуку отчёта об ошибке рассказывают» читалось
и как «хук отчёта об ошибке»: стало «об ошибке рассказывают хуку отчёта».
«Вызов, которому велели остановиться, передав токен через `ctx.onCancel`» —
токен передают вызову, а через `ctx.onCancel` его отменяют: стало «Вызов
с токеном, которому `ctx.onCancel` велит остановиться»; та же неточность
поправлена в оригинале — «through a token that `ctx.onCancel` cancels».

Сверка фактов сканера назвала новыми то, что получил оригинал, — `ctx.join`,
`ctx.onCancel`, `hw.setZoom`, `Future.ignore()`, обе формы ветки, «токен», —
а пропавшими `catchError`, `hw.open` и голый `onCancel`. Имена из кода
в бэктиках: `bare_names.py` называет только `Dart` и future, по решению
владельца 2026-09-15 это обычные слова. `Job` в правленых абзацах названа прямо
и женского рода.

## Проверки

В клоне, на итоговом дереве. `packages/solo`:
`dart format --output=none --set-exit-if-changed .` — «Formatted 113 files (0
changed)»; `dart analyze` — «No issues found!»; `dart test --concurrency=4` —
1350 тестов, «All tests passed!», до вычитки было 1247. Из корня
`reflow.py --check` — «every paragraph is filled to 79 columns»,
`check_line_width.py` — «no Markdown line over 79 columns», `check_links.py` —
«every document link resolves», `check_translations.py` — «no differences»,
`check_doc_shape.py` — «every section opens with code or a table». Сверх
заданного запущены `dart doc --dry-run` в `packages/solo` — «Found 0 warnings
and 0 errors» — и `tool/build_site.py` — «wrote 44 pages under
site/src/content/docs»: новые ссылки страницы на сайте ведут в страницы сайта,
русские — в русские. Ширину этой записи сверил сам: шире 79 только строки
таблицы мутаций.

В `packages/solo/lib` изменён один абзац dartdoc. Файлы
`packages/async_job/lib` и остальные файлы `packages/solo/lib` менялись только
на время мутаций и возвращены из снимков, `git status` по ним чистый. После
прогона мутаций для сверки запущены набор `async_job` — 1261 тест, «All tests
passed!», набор примера `packages/solo/example` — 47 — и `flutter test`
в `packages/flutter_solo` — 85. Каталог `packages/solo/.probe/` из клона убран.
Стенда у страницы нет: `tool/doc_snippets.py`, `tool/accumulation_snippets.py`
и `tool/flutter_snippets.py` её не собирают, код держит сторож. `jargon.py`
по странице и переводу слов кухни не нашёл.

## По чтению владельца

1. Вступление, фраза о том, чем открываются разделы. Владелец спросил, надо ли
   назвать привычку: фраза говорила только о словаре. Из пяти первых попыток
   три идут от привычки, а не от имён API: широкий `catch`, `throw`
   в `canStart` и `unawaited`. Теперь версия названа той, к которой ведёт
   привычка или словарь этого API: широким `catch`, `throw` вместо отказа или
   членом, названным по вопросу, который задаёт читатель. Правка в оригинале
   и в переводе.

2. «Ответ за ошибку», абзац перед кодом с `Solo.errorHandler`. Фраза кончалась
   словами о теле по умолчанию и двоеточием, и код под ней читался как это
   тело, а он показывает обработчик, которому тело передаёт ошибки. Теперь
   сказано, куда тело их передаёт, `Solo.errorHandler`, и отдельной фразой, что
   обработчик задаёт приложение; код стоит под ней. Правка в оригинале
   и в переводе.

3. «Ответ за ошибку», пример с `Solo.errorHandler`. Владелец спросил,
   не должен ли обход `Job.visitErrors` идти под капотом, раз каждый ответчик
   его зовёт, и решил: делать. Ядро теперь само спрашивает ответ по одному
   провалу, а отмен до `onUnanswered` и обработчика не доводит. Обработчик
   страницы стал одной строкой с `Sentry.captureException`, абзац под ним
   говорит о провалах по одному, абзац о `Cancelled` от брошенной операции
   говорит, что ответа за него не спрашивают. Подробности —
   `2026-10-07-unanswered-walk-report.md`.

4. «Ответ за ошибку», абзац под обработчиком: «один на весь процесс» по слову
   владельца стало «один на всё приложение», и «общий обработчик процесса»
   в том же абзаце стал обработчиком приложения. Правка в оригинале, переводе
   и стороже.
