> **Состояние на 2026-10-12:** вычитка сделана в клоне
> `.artifacts/2026-10-04-flutter-solo-readme-reread/tree/` на `11fc9a5` одним
> коммитом и перенесена в `main` коммитом `5c51816`. Тридцать девять находок
> разобраны тем же коммитом: тридцать пять приняты, четыре отклонены.
> Основная сессия после переноса прогнала проверки пяти пакетов, пять
> проверок документов и стенд `tool/flutter_snippets.py`.
> Владелец прочитал страницу и принял её 2026-10-11 вместе с правками
> по девяти пунктам раздела «По чтению владельца». По четвёртому страница
> перестроена: первый пример стоит на чистом `Solo` и `SoloBuilder`, а миксин
> `SoloListenable` получил свой раздел. По пятому исправлен сам виджет
> `SoloSelector`: замыкание в `selector:` или `changed:`, написанное на месте,
> больше не двигает подписку и не сбрасывает значение, с которым сравнивает
> `changed:`. По девятому примеры со scopo в разделе «The controller's life»
> решены и ждут обновления scopo.
> Вопрос владельцу о размере страницы и месте раздела «Testing» и список
> правок показанного кода на подтверждение закрыты 2026-10-12: страница
> остаётся как есть, с разделом «Testing» в README, а правки владелец
> подтвердил.
> **Что это:** отчёт о повторной вычитке `packages/flutter_solo/README.md`
> перед чтением владельца: находки ревью с вердиктами, два раздела,
> перестроенные первыми попытками, новый сторож пакета, правки стенда
> и сверки переводов, мутации.
> **Связанные записи:** `2026-09-06[6]-flutter-solo-docs-review.md` (ревью
> страницы версии 0.2.0), `2026-09-19-solo-project-review.md` (M10, M11, M16),
> `2026-09-18[9]-flutter-stream-screen-report.md`,
> `2026-09-24-mixins-rakes-report.md`,
> `2026-10-04-solo-vs-bloc-reread-report.md`,
> `2026-10-04-solo-testing-reread-report.md`,
> `2026-10-02-solo-readme-reread-report.md`,
> `2026-10-02-outcomes-reread-report.md`,
> `2026-09-11[16]-docs-structure-design.md`.

# Повторная вычитка README flutter_solo

## Зачем

Владелец прочитал все страницы `doc/` трёх пакетов; README `flutter_solo`
в этом круге он ещё не читал, так что первого чтения у страницы нет и вычитана
она как новая. Последний раз её читали целиком 2026-09-06, в ревью
`2026-09-06[6]-flutter-solo-docs-review.md`: тогда в ней было 252 строки
и восемь разделов. После того коммита, `8ca3bee`, оригинал меняли двадцать
шесть коммитов, перевод — тридцать два: +260 −78 строк, 434 строки
на `11fc9a5`. Четырёх разделов из двенадцати тогда не было вовсе: «Selecting
one value», «Builders for any controller», «Listening without keeping the
callback» и «Methods from a second import» появились 2026-09-11…13 вместе
с `SoloSelection`, `SoloSelector`, `SoloBuilder` и `listen`. Остальное — миксин
вместо класса (`9383e05`), `currentState` (`538db22`), стрим, ушедший
в `SoloStream` (`492ec8b`), обработчики состояния у `load` и стенд (`dde5df9`,
`c9b95dd`), `onUnanswered` (`eb94a2a`), ссылки по якорю (`7eb7036`). Последняя
правка обеих сторон — 2026-09-25.

Сторожа-теста у страницы не было. Её код собирает стенд
`tool/flutter_snippets.py`, задание `flutter` гейта; `flutter test` пакета
о странице не знал ничего.

По решению владельца 2026-10-02 перед чтением страница вычитана заново,
по образцу `2026-10-02-outcomes-reread-report.md` и вычиток 2026-10-04.

## Как

Один ревьюер, эта сессия, в клоне на `11fc9a5`. Каждое утверждение страницы —
проза, комментарии в коде, таблица, числа — сверено программой, которая
запускается.

Зонды лежат в `.artifacts/2026-10-04-flutter-solo-readme-reread/probes/`:
`probe.sh` кладёт их в `packages/flutter_solo/.probe/` клона вместе
с `model.dart`, моделью страницы с управляемым API, и запускает оттуда, вывод
рядом в `.out`; после работы каталога в пакете нет. `a_test.dart` — «Why»,
«Install» и «Usage», 11 сценариев; `b_test.dart` — выбор значения и билдеры,
10; `c_test.dart` — подписки и второй импорт, 8; `d_test.dart` — жизнь
контроллера и исходы, 9; `d2_test.dart` — корневая зона без обработчика;
`e_test.dart`, `e2_test.dart` и `e3_test.dart` — раздел «Testing», 20, из них
девять нарочно красных: провал или зависание и есть ответ зонда;
`f_test.dart` — таблица «Notes». `lints/` — семь файлов под `dart analyze`: что
не компилируется и с каким кодом ошибки. `plain/exit.dart` — обычная программа
на Dart с упавшей задачей, запущена из `packages/solo`. Проверки внутри
`runZonedGuarded` собирают ошибки в список, утверждения стоят снаружи зоны.

По исходникам `flutter_test` (Flutter 3.47.0, канал stable, и пол 3.27.0)
сверены шаг `pumpAndSettle`, порядок шагов `pump`, таймаут теста виджета
по умолчанию и обработчик непойманной ошибки зоны теста; по `dart:ui` —
документация `PlatformDispatcher.onError`.

Отдельным проходом страница прочитана глазами читателя, у которого есть только
она: слово без предмета, одно слово для двух вещей, местоимение с двумя
кандидатами, фраза, отвечающая на реплику, которой читатель не слышал, слова
нашей кухни, сравнение двух версий, из которых проверена одна.

О движке страница не ошиблась: всё, что она говорит о `solo` и об `async_job`,
зонды подтвердили, и со страницами `packages/solo/doc/`, вычитанными 2026-10-03
и 2026-10-04, она не расходится. Ошибалась она о Flutter и о самой себе. Раздел
«Testing» учил тесту, который краснеет на упавшей загрузке (H1), приписывал
`pumpAndSettle` то, чего он не делает (H2), и показывал закрытие контроллера
там, где оно виснет на десять минут (H3). Блок раздела о жизни контроллера
не собирался с импортами, которые показывает страница (M1). В переводе не было
последнего абзаца раздела о тестах (M2). Раздел о подписках объяснял `listen`
замыканиями, а слушал методами (M3). Остальное — разница, которую читателю
нечем наблюдать (M4), фраза, спорящая с соседним разделом (M5), имена без
введения, слова кухни и местоимения.

От ядра страница не отстала. Голого `Future.delayed` в теле задачи на ней нет
и не было: тела зовут API через `ctx.wait` и `ctx.join`, и `ctx.pause` брать
не для чего; в примере пакета его тоже нет. `Job.each`, `Job.visitErrors`
и пара `JobObserver` и `JobAnswerer` — предмет страниц ядра и `solo`. Имена
на странице нынешние: `Solo`, `currentState`, `onUnanswered`,
`Solo.errorHandler`, `SoloObserver`; с разделами `## Unreleased` трёх
`CHANGELOG.md` она не расходится.

Страница выросла с 434 до 512 строк, перевод — с 429 до 511. Блоков `dart`
стало 14 вместо 12, заголовков 17 вместо 13: разделы о подписках и о тестах
получили по первой попытке и по ответу под своими заголовками. Заголовки
второго уровня не переименованы, ссылки на них из `CHANGELOG.md`, README `solo`
и `mixins.md` целы.

## Находки ревью

### High

**H1. Хэндл в разделе «Testing» читал `done`, когда `Job` уже кончилась.** Блок
«точной версии» был `final job = controller.load();`, прокачка на двадцать
миллисекунд, `await job.done`. На загрузке, которая падает, тест с этими
строками красный: о `Failed`, про который никто не спросил, движок сообщает
в момент конца `Job`, внутри прокачки, и зона теста проваливает тест, хотя
следующей строкой тест читает `done` и получает `Failed` (зонд E3b). Абзац ниже
советовал «await the outcome or call `ignore()`» — блок над ним ждал исход
и краснел. Четвёртая строка блока, `await tester.pump();` с комментарием «the
frame that shows the last state», кадра не добавляла: прокачка с длительностью
сдвигает часы и рисует после этого, так что последнее состояние экран
показывает уже после неё (E3).

Вердикт: принято. Блок стал
`final done = controller.load().done; // before the job can end`, прокачка,
`final outcome = await done;`, а абзац под ним говорит, почему порядок важен,
и называет случай: «A load that fails makes a test red even though it reads
`done`, if it reads it after the pump». Сторожа —
`the handle waits for the job, and its pump leaves the frame`,
`read before the clock moves, a load that fails is no trouble`
и `read after the pump, the same load fails the test`; последний запускает
прежние строки так, как их запускает `testWidgets`, и ловит провал. В стенде —
драйвер `read before the clock moves, a failed load is an outcome`.

**H2. «`pumpAndSettle` does both — it runs the clock out and rebuilds».** Часы
до конца он не гоняет: качает по кадру раз в сто миллисекунд, пока запрошен
следующий кадр. Зонд E2: под спиннером страницы и с API, отвечающим через
секунду, — одиннадцать прокачек, 1100 мс, состояние `Loaded`; на экране без
анимации и с тем же API — две прокачки, 200 мс, состояние `Loading`. Тест
страницы проходил, потому что фейку хватает первой сотни миллисекунд, а при
фейке медленнее его держал бы спиннер; читатель с экраном без анимации получал
красный тест и причину, которой страница не называла.

Вердикт: принято. Абзац под тестом говорит, что делает `pumpAndSettle`, почему
он проходит здесь и что ждут экран, а не задачу. Сторож —
`pumpAndSettle waits for the screen, not for the job`: секундная загрузка под
спиннером и та же загрузка на `QuietView` без анимации.

**H3. `addTearDown(controller.close)` в тесте страницы виснет до таймаута.**
Колбэк `addTearDown` выполняется после тела теста, когда фейковые часы никто
не двигает и микротаски их зоны никто не выполняет. `close()`, которого там
ждут при ещё идущей `Job`, не возвращается: зонд E10a — проверка упала посреди
загрузки, сообщение о провале напечатано, а прогон стоит до таймаута, десять
минут по умолчанию; следующий тест файла после этого падает
с `'!inTest': is not true`, потому что `binding.postTest` до него не дошёл.
То же, когда тело уже звало `close()`: повторный вызов отдаёт ту же future,
завершённую в остановленной зоне (E8).

Вердикт: принято. Тест страницы закрывает контроллер в теле, последней строкой,
и абзац в конце раздела говорит почему. Сторожа —
`closed in the body, a controller with a load running lets go`
и `awaited once the clock has stopped, the same close() never returns`.
Драйверы README в стенде закрывают контроллер помощником `closing`, который
`close()` не ждёт: красный драйвер должен сказать, что упало, а не стоять
до таймаута. Драйверы `mixins.md` не тронуты, это страница следующей вычитки.

### Medium

**M1. Блок «The controller's life» не собирался с импортами страницы.**
`unawaited` живёт в `dart:async`, а страница показывает только
`package:flutter/material.dart` и `package:flutter_solo/flutter_solo.dart`:
`dart analyze` на таком файле говорит `undefined_method`
(`probes/lints/unawaited.dart`). Стенд этого не видел: `import 'dart:async';`
драйверу дописывал генератор.

Вердикт: принято. Блок начинается с `import 'dart:async';`. Генератор своих
импортов драйверу README больше не добавляет, кроме `flutter_test`: уберёт
страница импорт — драйвер не соберётся (мутация B2).

**M2. В переводе не было последнего абзаца раздела «Testing».** Абзац «One
Flutter-specific trap…» в `README.ru.md` отсутствовал. `check_translations.py`
сверяет заголовки и код и абзацев не считает.

Вердикт: принято. Раздел переведён заново. `tool/check_translations.py` теперь
сверяет и форму прозы: под каждым заголовком в переводе столько же абзацев,
пунктов списка и строк таблицы, сколько в оригинале, и на тех же местах между
блоками кода. Все двадцать одна пара проходят. Мутации P7 и P8.

**M3. Раздел о подписках объяснял `listen` замыканием, а слушал методами.**
Первая фраза: «`addListener` has to be given the same callback back, so a
closure needs a field of its own to live in». Колбэк отдают `removeListener`,
а не `addListener`; а пример звал `listen(_onState)` и `listen(_onCanSave)` —
методы, которым поле не нужно: `removeListener` сравнивает по `==`, и метод
снимается без `listen` (зонд C1, раздел «Observing state» страницы `state.md`).
Того, ради чего `listen` существует, пример не показывал.

Вердикт: принято. Раздел перестроен: задача, «The first attempt» — замыкание
в `addListener` и такое же, написанное заново, в `removeListener`, — и ответ
под заголовком «A subscription that keeps the callback». Первая попытка ничего
не снимает и ничего не говорит, замыкание зовут над `State`, которого уже нет,
пока контроллер не закроют; сторож —
`the first attempt goes on being called after dispose()`, в стенде драйвер
`a closure handed to removeListener again removes nothing`. В ответе `listen`
получает замыкания, которые читают значение и отдают его `_onState`
и `_onCanSave`; так же переписана строка `listen` в блоке второго импорта. Итог
2026-10-11: по слову владельца между первой попыткой и ответом встал подраздел
«A method instead of the closure», где колбэк — метод `State`, названный
и в `addListener`, и в `removeListener`; фраза первой попытки о собственном
поле для замыкания убрана. Сторож и драйвер стенда зовутся
`a method named twice is the callback dispose() removes`. Подробности в седьмом
пункте раздела «По чтению владельца».

**M4. «Two things set it apart from `ValueListenableBuilder`».** Первая из двух
вещей — «It reads `currentState` in `build`, where `ValueListenableBuilder`
builds from a copy that every notification refreshes» — устройство, которого
читателю нечем наблюдать. Зонд B8: равное состояние, тот же объект дважды, две
смены за ход, смена из слушателя, закрытие — оба билдера строят одно и то же.
К тому же выводу пришёл `2026-09-18[9]-flutter-stream-screen-report.md`, назвав
такой раздел рассказом о нашей кухне.

Вердикт: принято. Осталась одна вещь, наблюдаемая: сравнение контроллеров
по идентичности. Фраза о ней уточнена сторожем: получив контроллер, равный
старому по `==`, `ValueListenableBuilder` «goes on listening to the old one» —
прежнее «stays with the old» не говорило, что именно остаётся. Сторож —
`it moves to a controller that == calls the old one`, считает перестроения
каждого билдера после смены нового и старого контроллера (мутация C2). Итог
2026-10-11: по четвёртому пункту раздела «По чтению владельца» раздел «Builders
for any controller» убран, и отличие стоит в разделе «The controller as a
`ValueListenable`»: «One thing sets it apart from `ValueListenableBuilder`: it
compares controllers by identity». По слову владельца следующая фраза называет
оба сравнения, «a new controller that equals the old one by `==` but not by
`identical`», и сторож проверяет оба на паре контроллеров, которую отдаёт
билдерам.

**M5. «`SoloSelector` … keeps its selection across a parent rebuild».** Раздел
выше говорит обратное про пример самой страницы: замыкание на месте на каждом
перестроении родителя новое, и проекция создаётся заново. Зонд B3: три
перестроения — четыре `addListener` и три `removeListener`, а с функцией
в `static` — один и ноль. Продолжение, «so the value the comparison answers
from survives one», наблюдаемо только при своём `changed:` (B6b).

Вердикт: принято. Абзац раздела о билдерах говорит только то, зачем он там:
`SoloSelector` принимает любой контроллер, `SoloSelection.from` — его проекция
без виджета. Цена замыкания на месте названа там, где о нём речь: «one
`removeListener`, one `addListener` and one pick, and with a `changed:` of your
own the value it compares against starts over». Сторожа —
`an inline selector makes a new selection on every build`
и `a new selection forgets what changed was comparing with`. Итог 2026-10-11:
цены, которую называла эта фраза, больше нет. По вопросу владельца исправлен
сам виджет: замыкание на месте стоит одной выборки на перестроение родителя,
подписка остаётся на месте, значение для `changed:` не сбрасывается. Фраза
страницы переписана, сторожа теперь называются
`closures written in place cost a pick and no subscription`
и `a parent rebuild leaves what changed compares with alone`. Подробности
в пятом пункте раздела «По чтению владельца».

**M6. `ctx.unattended`, `onUnanswered`, `Solo.errorHandler` и `SoloObserver`
появлялись в «Outcomes» без введения и без ссылки.** Читателю этой страницы
четыре имени не сказаны нигде.

Вердикт: принято. Фраза ведёт в раздел «Answering for an error» страницы
об ошибках `solo`, в переводе — в «Ответ за ошибку»; утверждения фразы держат
сторожа `unattended work that fails takes the same road`
и `an observer sees such a failure and does not take it`.

**M7. Абзац о том, что значит «в зону» во Flutter.** Три вещи. «The `EXIT=255`
of a plain Dart program» — запись нашей кухни, ни на одной странице её нет.
«`PlatformDispatcher.onError` may end the process» — процесс кончает не колбэк:
документация `onError` говорит, что VM или процесс могут завершиться после его
вызова. «The engine's log if you did not» — туда же ошибка идёт, когда колбэк
вернул `false`.

Вердикт: принято. Абзац переписан по зондам и документации: своя error-зона
видит ошибку первой, за ней `PlatformDispatcher.instance.onError` (D9), без
него или при `false` ошибку получает встраивающая сторона и печатает её (D9b),
процесс после колбэка может завершиться; обычная программа на Dart кончается
с кодом выхода 255 (`probes/plain/exit.out`). Первые два утверждения держит
сторож `an error zone of your own comes before PlatformDispatcher.onError`,
остальные — раздел «Сторож», «Чего тест не видит».

**M8. «Starting a job and pumping once — the state moves on a microtask after
that pump, and whether the expectation sees it depends on how much was
queued».** От длины очереди не зависит ничего. Зонд E5b: `pump()` без
длительности рисует кадр, только если он уже запрошен, а микротаски выполняет
после этого решения. Запрошен кадр — как сразу после `pumpWidget`
с `MaterialApp` — и одна прокачка показывает новое состояние; не запрошен —
состояние сдвинулось, экран нет, рисует вторая прокачка.

Вердикт: принято. Фраза переписана этими словами. Сторожа —
`one pump after load() moves the state and not the screen`
и `right after a MaterialApp has been pumped, one pump draws it`.

**M9. «The error goes to the zone of the test, not through
`FlutterError.onError`».** Обработчик зоны теста сам отдаёт ошибку
в `FlutterError.reportError` и тут же кончает тест: подменённый
`FlutterError.onError` её видит, с контекстом «running a test» (E6b). Верно
другое: `tester.takeException()` после этого забирать нечего.

Вердикт: принято. «Here that is the zone of the test, which fails the test on
the spot, and `tester.takeException()` has nothing to take afterwards». Сторож
`read after the pump, the same load fails the test` проверяет и провал,
и `null` из `takeException()`.

**M10. «The rest of the API this package inherits whole — all but the broadcast
`stream` of `SoloStream`, which a widget has no use for».** `SoloStream`
приходит тем же импортом (`probes/lints/no_stream.dart`), сама страница
отправляет за контроллером с обеими доставками и экраном на стриме
в `mixins.md`.

Вердикт: принято. «…and the rest of the API, which this package re-exports
whole — `SoloStream` included, whose broadcast `stream` is for what is not a
widget». Сторож — `SoloStream comes with the same import`.

**M11. Двадцать миллисекунд хэндла было не с чем сравнить.** `FakeApi`
на странице не объявлен, и сколько он отвечает, она не говорила.

Вердикт: принято. Первый абзац раздела: «`FakeApi` below is the test's own: it
answers with the name ten milliseconds after the call». Сторожа —
`the first attempt stands until the clock moves` (через девять миллисекунд ещё
стоит, через десять прошла)
и `twenty milliseconds are more than the fake takes`; мутации T20 и P13.

**M12. Стенд не замечал блока, которого не берёт ни один драйвер, и проверял
по одной стороне сравнений.** Генератор берёт блоки по ключам, и новый блок
страницы молча оставался несобранным; ветку `Failed` в `_load` и первые попытки
не запускал никто.

Вердикт: принято. Сборка падает на блоке README или `mixins.md`, которого
не взял ни один драйвер (B1, B7); блок под Install теперь тоже берётся.
Добавлены драйверы первых попыток, упавшей загрузки под хэндлом и ветки
`Failed`. Подробности — раздел «Сторож».

### Low

**L1. `Text('$state')` в примере `SoloBuilder` показывает на экране
`Instance of 'Empty'`.** Зонд B4.

Вердикт: принято. Билдер возвращает `Text` со `switch` по трём состояниям, как
бейдж в `mixins.md`; сторож —
`the builder takes a controller that is not a listenable`. Итог 2026-10-11:
этого блока на странице больше нет. По четвёртому пункту раздела «По чтению
владельца» раздел «Builders for any controller» убран, `SoloBuilder` показан
в «Usage» экраном `ProfileView`, а `Text` со `switch` по трём состояниям стоит
теперь под `ValueListenableBuilder` в разделе «The controller as a
`ValueListenable`». Сторож заменён
на `SoloBuilder takes a controller with the mixin or without`.

**L2. «Would subscribe and unsubscribe every frame».** `build` зовут не каждый
кадр; зонд B6 считает подписки по построениям. И чем плохо, что «the value it
holds notifications back with would go with it», не сказано: при `!=` ничем,
при своём `changed:` — значение начинается заново (B6b).

Вердикт: принято. «One built inside `build` is a new object on every build: the
builder under it unsubscribes from the old one and subscribes to the new, and
the value a selection holds notifications back with starts over each time».
Те же слова «every frame» стояли в dartdoc `SoloSelection` и `SoloSelector`,
поправлены там же: правка `lib/` — два предложения комментария. Сторож —
`a selection built inside build is a new one every build`.

**L3. «`listen` works on any `Listenable` — a controller, …».** Голый `Solo`
не `Listenable`, и `listen` у него нет (`probes/lints/plain_listen.dart`),
а раздел выше как раз о таких контроллерах.

Вердикт: принято: «a controller with `SoloListenable`».

**L4. «Leaves the rest of that frame's elements unmounted».** По-английски
читается как «размонтированы»; на деле они остаются без своего `dispose()`
(зонд C5: бросил второй из трёх — у третьего `dispose()` не вызван).

Вердикт: принято: «costs the elements behind it in that frame their own
`dispose()`, listeners and all». Сторож —
`a throw out of dispose() costs the elements behind it theirs`.

**L5. «Without it nothing is lost but the shorthand».** Без второго импорта нет
и `SoloSubscription` с `SoloSubscriptions` (`probes/lints/one_import.dart`),
а что остаётся вместо `listen`, не сказано.

Вердикт: принято. Абзац называет, что остаётся: `SoloSelection(…)`,
`SoloSelector` и `addListener` с колбэком, который хранишь сам, — и что
подписки приходят только со вторым импортом. Сторожа —
`select, listen and the subscriptions are in the second import`
и `without the methods the same things are still done`.

**L6. «It is also why a controller of your own with a `select` method keeps
it».** У «it» три кандидата: импорт из предыдущей фразы, «ничего не теряется»
и то, что это расширения, двумя абзацами выше.

Вердикт: принято: «Being extensions is also why…».

**L7. «A job hands back a handle».** Хэндл отдаёт метод, и хэндл этот — сама
`Job`; в «Why» так и сказано.

Вердикт: принято: «A method hands back its job».

**L8. «`SoloSelector` and `SoloSelection` come with it».** В перечне нет
`SoloBuilder`, которому на странице отдан раздел, и не сказано, что второй
импорт несёт ещё и подписки.

Вердикт: принято, обе вещи названы. Итог 2026-10-11: по слову владельца абзац
перечисляет собственную часть пакета ровно и называет род каждого имени: «the
mixin `SoloListenable`, the widgets `SoloBuilder` and `SoloSelector`, and the
class `SoloSelection`»; второй импорт с подписками назван следующей фразой.
Подробности во втором пункте раздела «По чтению владельца».

**L9. «Still notifies, the way `Solo` does».** Контроллер и есть `Solo`: фраза
осталась от времён, когда `SoloListenable` был отдельным классом. Там же
«`select` filters its own value» — фильтрует проекция, и `SoloSelector` тоже.

Вердикт: принято: «the listeners are the engine's own, and the engine compares
nothing», «A selection filters its own value». Сторож —
`equal states are not filtered, and a frame swallows several`.

**L10. «Bloc gives you the work and asks for an event class per call».**
`Cubit` класса события не просит и работу не планирует; `vs-bloc.md` говорит
об обоих.

Вердикт: принято: «`Bloc` schedules the work and asks for an event class per
call; `Cubit` keeps plain methods and schedules nothing». Утверждение о чужой
библиотеке держит стенд `vs-bloc.md`, не эта страница.

**L11. В блоке «Why» контроллер звался `profile`, а комментарии выровнены двумя
пробелами.** Дальше на странице `Profile` — состояние, а контроллер —
`controller`; два пробела перед `//` `dart format` не оставляет.

Вердикт: принято: `controller.load()`, один пробел. Без этого блок не стоит
дословно в support-файле, который проходит `dart format`.

**L12. «The frame is always one behind the state».** На один что?

Вердикт: принято, фраза ушла вместе с прежним вступлением раздела; о кадре
говорит абзац про одну прокачку (M8).

**L13. «`close()` cancels whatever is running».** И всё, что стоит в очереди.

Вердикт: принято: «whatever is queued or running — a running body stops at its
next context call». Сторожа —
`close() cancels what is queued and what is running`
и `a running body stops at its next context call`.

**L14. «`value` gives the value and rethrows the failure».** А у отменённой
`Job` бросает её `Cancelled` (зонд D11); README `solo` говорит об обоих.

Вердикт: принято. Сторож — `done never throws, value rethrows`.

**L15. «Without `didUpdateWidget` the button would take its permission from the
old controller and save to the new one».** Запущена была только версия
с `didUpdateWidget`. Зонд B5: без него кнопка над пустым новым контроллером
остаётся нажимаемой, нажатие уходит в новый, и правило `save` его отклоняет;
в обратную сторону кнопка мертва над профилем, который можно сохранить.

Вердикт: принято: «would go on taking its permission from the old controller
while its tap went to the new one». Сторож —
`without didUpdateWidget it stays with the old one`, обе стороны. Итог
2026-10-11: по вопросу владельца перед этой фразой сказано, откуда у кнопки
старый контроллер: инициализатор поля выполняется один раз, а `State` живёт
дольше виджета. Тот же тест сторожа теперь цитирует и эти слова. Подробности
в шестом пункте раздела «По чтению владельца».

**L16. «The pick is made from the state as it is now, so it is never behind».**
Ответ на вопрос, которого читатель не задавал; практическая половина фразы —
селектор должен быть дешёвым — осталась без причины.

Вердикт: принято: «The selector runs once for every change of the state, so
keep it a cheap pick…». Сторож — `the selector runs once for every change`.

**L17. В блоке `_SaveButtonState` `canSave` — и проекция, и выбранное
значение.** Поле и параметр билдера в соседних строках.

Вердикт: принято: параметр билдера зовётся `enabled`.

**L18. «So it does not start in any other state».** Что получит вызвавший,
не сказано.

Вердикт: принято: «— it ends `Cancelled` there —». Сторож —
`save does not start over a state that is not Loaded`, исход
`Cancelled(rules: is not Loaded)`.

**L19. «`Policy.droppable`… a second tap returns the first job» и остальные
комментарии в коде не держал никто, кроме стенда.**

Вердикт: принято: сторожа раздела «Usage», пять тестов.

**L20. Перевод.** 42 длинных тире, два «X — это Y», «является»,
«`SoloProvider`'а», `Future` в бэктиках там, где это слово, «задача» там, где
речь о `Job` как об объекте, «на один» без предмета.

Вердикт: принято, раздел «Перевод».

**L21. Абзац о `State`, которому передали другой контроллер, без кода.** Блок
над ним объявляет `final _listening`, а абзац велит взять новую группу.

Вердикт: отклонено. Блок показывает `State`, у которого источник не меняется,
и для него `final` верен; тот же приём для проекции показан кодом в разделе
о выборе значения. Обе стороны абзаца держат сторожа
`handed another controller, initState goes on hearing the old`
и `the subscriptions are taken again into a new group`.

**L22. `key: 'save'` при политике по умолчанию на странице ничего не делает.**

Вердикт: отклонено. Ключ называет операцию, и страница `jobs.md` показывает
`save` с ключом как пример политики по умолчанию.

**L23. «The documentation site carries this page and the guides of the packages
below it» не называет собственное руководство пакета.**

Вердикт: отклонено. Фраза верна, а «Mixins» страница называет сама, в разделе
о билдерах. Итог 2026-10-11: раздела о билдерах на странице больше нет,
четвёртый пункт раздела «По чтению владельца»; «Mixins» страница называет
в разделе «The controller as a `ValueListenable`».

**L24. У `ProfileView` нет кнопки Save, хотя у контроллера есть `save`.**

Вердикт: отклонено. Кнопку показывает следующий раздел, ради неё он и написан.
Итог 2026-10-11: после перестройки по четвёртому пункту раздела «По чтению
владельца» кнопку показывает раздел «Selecting one value», второй после
«Usage».

## Чего ревью не нашло, но нашлось рядом

`flutter test` кончает оболочку, когда ошибка доходит до корневой зоны,
а `PlatformDispatcher.onError` не задан или вернул `false`: оба теста зонда
`d2_test.dart` «did not complete». В самом тесте виджета ошибку перехватывает
зона теста, так что видно это только из кода, запущенного в `Zone.root`.

Драйверы `mixins.md` в стенде закрывают контроллеры в `addTearDown`
с ожиданием. Пока они зелёные, это не видно; красный драйвер с идущей задачей
простоит до таймаута (H3). Оставлено следующей вычитке.

`packages/flutter_solo/CHANGELOG.md`, запись «Documentation» раздела
`## Unreleased`: в опубликованном README 0.2.0 раздел о тестах тот самый, что
исправлен находками H1–H3. Назвать ли это в записи — к списку релиза. Там же,
в «Added», о `SoloSelector` сказано «holds its selection across a parent
rebuild» без условия, что селектор тот же объект (M5); `CHANGELOG.md` этой
вычиткой не правлен.

`await` во фрагменте «Why» ненаблюдаем: загрузку, отменённую в очереди,
`cancel()` роняет внутри вызова, и исход есть уже на следующей строке (мутации
T7 и B9). Фразу комментария, «returns when the job has actually stopped»,
держит тест с идущей загрузкой.

Замыкание без захвата, написанное на месте, в VM каждый раз новый объект — так
показал зонд B3 под `flutter test`. В сборке AOT это не проверялось.

Шапка `2026-09-06[6]-flutter-solo-docs-review.md` говорит, что все находки
закрыты тем же коммитом. После переноса её стоит дополнить руками: страницу
с тех пор переписали, повторная вычитка — эта запись.

## Вопросы владельцу

Один вопрос, и работу он не останавливал.

**Размер страницы и место раздела «Testing».** README `flutter_solo` теперь 512
строк. Карта `2026-09-11[16]-docs-structure-design.md` числила его страницей
в 325 строк, которую разносить не надо; к этой вычитке он вырос до 434, вычитка
добавила 78. Раздел «Testing» — 70 строк с двумя заголовками третьего уровня,
раздел о подписках — 68. Варианты. Оставить как есть: README остаётся
единственной страницей о виджетах и тестах пакета. Вынести «Testing»
на страницу `packages/flutter_solo/doc/testing.md` с переводом, оставив
в README тест `the profile appears` и ссылку, как сделано с `mixins.md`: README
вернётся примерно к 455 строкам, пара добавится в `check_translations.py`,
блоки — в стенд. Вынести туда же и раздел о подписках.

На подтверждение — правки, которые меняют показанный код. Блок хэндла (H1).
Тест страницы закрывает контроллер в теле, а не в `addTearDown` (H3). Разделы
о подписках и о тестах получили заголовки «The first attempt» и ответ под своим
заголовком (M3, H1). Пример `SoloBuilder` (L1), параметр `enabled` (L17),
`import 'dart:async';` в блоке экрана (M1), `controller` вместо `profile`
в «Why» (L11), строка `listen` в блоке второго импорта (M3). В `lib/` — два
предложения dartdoc (L2); код не менялся. С действующими решениями
из `docs/handoff.md` правки не спорят.

Итог 2026-10-11: владелец прочитал страницу и принял её. В ней теперь 565
строк, в переводе 563, раздел «Testing» стоит в README. На вопрос о размере
страницы и на список правок показанного кода он ответил 2026-10-12. Страница
остаётся как есть: «Testing» и раздел о подписках на свои страницы
не выносятся. Правки показанного кода подтверждены, и с ними две вещи, которых
на странице не видно: два предложения dartdoc в `packages/flutter_solo/lib/`
и строка о пакете на сайте, изменённая при перестройке страницы сверх
одобренного списка, о ней четвёртый пункт раздела «По чтению владельца».
Примера `SoloBuilder` (L1) в списке к тому времени уже не было: по тому же
пункту этот блок со страницы ушёл.

## Сторож

**Стенд** `tool/flutter_snippets.py` остаётся сторожем кода страницы: он
собирает блоки из самого markdown. Вырос с 1073 до 1287 строк, тестов в нём 33
вместо 29, из них у README 16 вместо 12.

Блоки. Каждый из 14 блоков `dart` README и каждый из шести блоков `mixins.md`
берёт хотя бы один драйвер, и сборка падает на блоке, которого не взял никто,
как у стендов `vs-bloc` и `accumulation`. Из README `solo` стенд по-прежнему
берёт два блока быстрого старта: остальное держит сторож пакета `solo`. Блоки
раздела о подписках адресуются по подзаголовку: первая попытка и ответ оба
объявляют `initState` и `dispose`.

Импорты. Строки `import` поднимаются в голову драйвера со страницы, и генератор
добавляет к ним только `flutter_test`. `dart:async`, который нужен и самим
драйверам, приходит из блока раздела о жизни контроллера.

Новые драйверы: первая попытка раздела о тестах стоит, пока тест не сдвинет
часы; хэндл над упавшей загрузкой отдаёт `Failed` и тест не краснит; первая
попытка раздела о подписках слышна после `dispose()`; ветка `Failed` в `_load`
показывает тост. Помощник `closing` закрывает контроллеры драйверов README,
не дожидаясь `close()`.

Чего стенд не делает: трасс под забором `text` на странице нет,
и `check_traces.py` по ней не гоняется; прозу страницы стенд не читает, её
держит тест пакета.

**Тест пакета** `packages/flutter_solo/test/readme_rakes_test.dart` — новый
файл, 69 тестов; до вычитки `flutter test` страницу не видел. Код страницы
дословно стоит в четырёх файлах `test/support/`: `readme_profile.dart` — модель
раздела «Usage» под двумя импортами блока и больше ни под чем,
`readme_widgets.dart` — фрагменты от «Why» до «Outcomes», `readme_tests.dart` —
код раздела «Testing», `readme_install.dart` — имена раздела «Install» под
одним импортом. Фрагмент стоит внутри того, что ему нужно: строки — в функции,
члены `State` — в классе; выражение виджета, которое на странице кончается
строкой `)`, стоит единственным элементом списка, иначе последняя строка
была бы `);`. Тест страницы объявляет функция `theProfileAppears`, и сторож
зовёт её в своей группе. Пятый файл, `readme_variants.dart`, — версии,
о которых страница говорит прозой, не показывая кода: контроллер без
обработчиков состояния, кнопка без `didUpdateWidget`, экран без анимации,
`State`, который берёт подписки заново, и контроллеры, которыми тест
дотягивается до защищённых членов. Кода страницы сторож в нём не ищет.

Сверка — `codeMissingFrom` из `page_code.dart`: каждый кусок каждого блока
страницы стоит в одном из четырёх файлов подряд идущими строками. Помощник
скопирован в `packages/flutter_solo/test/support/` четвёртой копией, шапки трёх
прежних её называют. Сторож считает блоки `dart` — четырнадцать — и забор `sh`
под Install, единственный, которого проверки не читают.

Группы: «The page» — 2, «Why» — 6, «Install» — 2, «Usage» — 5, «Selecting one
value» — 9, «Builders for any controller» — 4, «Listening without keeping the
callback» — 8, «Methods from a second import» — 4, «The controller's life» — 5,
«Outcomes» — 7, «Testing» — 12, «Notes» — 4, «solo» — 1. Тест, который
проверяет фразу, держит страницу к ней через `_says`.

Первые попытки, которые кончаются провалом теста, запущены так, как тело теста
запускает `testWidgets`: помощник `_asWidgetTest` зовёт `binding.runTest`
из обычного `test` и на время подменяет `reportTestException`, так что провал
приходит списком, а не красным тестом. Первая попытка, которая виснет, запущена
без `await`: сторож смотрит, что она стоит после прокачек без длительности
и проходит, когда часы сдвинуты на десять миллисекунд. Таймаут теста виджета
сторож ставит себе сам, тридцать секунд вместо десяти минут.

Перевод тест пакета не читает: `README.ru.md` закрыт `.pubignore`, а тесты
гоняются и из архива, на полу. Его держит `tool/check_translations.py`, в том
числе новой сверкой формы прозы.

Блок, который сторож запустить не может, один: `flutter pub add flutter_solo`
под забором `sh`.

Чего тест не видит. Двусмысленность двух расширений с одним именем — ошибка
компиляции, `probes/lints/ambiguous.dart`; тест держит только то, что `select`
и `listen` — расширения на `ValueListenable` и `Listenable`. Код выхода 255
обычной программы на Dart — свойство VM, `probes/plain/exit.out`. Запасной путь
встраивающей стороны при `false` из `onError` и слова о процессе после
колбэка — зонд D9b и документация `dart:ui`; на устройстве не проверено. «Ten
minutes by default» прочитано в `flutter_test/lib/src/binding.dart` обеих
версий Flutter, само зависание — зондом E4. «The test after it fails with it» —
зонды E7 и E10a: повисший колбэк `addTearDown` не может быть частью зелёного
набора. Фраза о `Bloc` и `Cubit` — предмет `vs-bloc.md` и его стенда.

## Мутации

`.artifacts/2026-10-04-flutter-solo-readme-reread/mutate.py`, журнал
`mutations.out` там же, вывод каждого прогона в `mut/`: 88 мутаций — 26 правок
движка и пакета (C), 29 правок кода страницы и вариантов в support-файлах (T),
18 правок текста страницы и перевода (P), 12 для стенда (B) и три для сверок
документов (R). Каждая правит файл, запускает свой сторож — тест пакета, сборку
стенда, его анализ, драйверы README, `check_translations.py` или
`check_links.py` — и возвращает файл копией из `snapshot/` со сверкой побайтно;
`git status` после прогона тот же, что до него. Красные тесты считаны по меткам
`[E]`. Каждый из 69 тестов краснеет хотя бы от одной мутации.

| Мутация | Красных |
| --- | --- |
| C1 `SoloSelector` не замечает нового селектора | 2 |
| C2 `SoloBuilder` сравнивает контроллеры по `==` | 1 |
| C3 отменённая группа хранит то, что ей передали | 2 |
| C4 группа выпускает ошибку участника наружу | 1 |
| C5 подписка снимает слушателя на каждый `cancel()` | 1 |
| C6 проекция считает изменением любую выборку | 5 |
| C7 проекция остаётся подписанной после последнего слушателя | 3 |
| C8 проекция выбирает заново на каждое чтение `value` | 2 |
| C9 первый импорт экспортирует и подписки | 1 |
| C10 `Policy.droppable` не находит дубликат | 1 |
| C11 `externalSetState` после конца закрытия не бросает | 1 |
| C12 смена состояния не переоценивает правил | 1 |
| C13 задача встаёт в голову очереди | 3 |
| C14 слушателей зовут с конца | 3 |
| C15 слушатели сброшены в момент вызова `close()` | 5 |
| C16 о `Failed`, которого никто не наблюдал, не сообщается | 3 |
| C17 `ignore()` не отмечает исход наблюдённым | 5 |
| C18 чтение `done` не отмечает исход наблюдённым | 3 |
| C19 `Solo.errorHandler` не спрашивают | 1 |
| C20 запись того же объекта состояния не публикуется | 2 |
| C21 у `value` миксина появился сеттер | 1 |
| C22 установленный наблюдатель не пускает ошибку в зону | 1 |
| C23 `SoloSelector` не отдаёт `changed` проекции | 2 |
| C24 `emit` отменённой задачи пишет состояние | 1 |
| C25 `close()` не отменяет идущую задачу | 6 |
| C26 `value` отменённой задачи бросает другое | 1 |
| T1 у `load` нет `Policy.droppable` | 2 |
| T2 у `load` нет `onError` и `onCancel` | 7 |
| T3 `load` ждёт через `ctx.join` | 7 |
| T4 `save` ждёт через `ctx.wait` | 3 |
| T5 `canSave` истинно во время загрузки | 12 |
| T6 экран страницы не показывает спиннер | 4 |
| T7 фрагмент «Why» не ждёт `cancel()` | 1 |
| T8 селектор страницы выбирает обратное | 2 |
| T9 поле страницы не пересоздаётся в `didUpdateWidget` | 2 |
| T10 билдер страницы показывает `Loading` как «no profile» | 2 |
| T11 первая попытка раздела о подписках не подписывается | 2 |
| T12 `dispose()` страницы не отменяет группу | 2 |
| T13 второй импорт слушает пустым колбэком | 2 |
| T14 экран страницы не закрывает контроллер | 3 |
| T15 ветка `Failed` в `_load` молчит | 2 |
| T16 `_load` показывает тост, не спросив `mounted` | 2 |
| T17 первая попытка раздела о тестах не ждёт `Job` | 2 |
| T18 тест страницы качает один раз вместо `pumpAndSettle` | 2 |
| T19 хэндл читает `done` после прокачки | 2 |
| T20 фейк отвечает через пятнадцать миллисекунд | 26 |
| T21 экран без анимации показывает спиннер | 1 |
| T22 `State`, идущий за контроллером, всегда берёт новую группу | 1 |
| T23 у контроллера без обработчиков они есть | 1 |
| T24 «равные» контроллеры равны только себе | 1 |
| T25 API, который не отвечает, отвечает сразу | 1 |
| T26 `dispose()` соседа не бросает | 1 |
| T27 кнопка без `didUpdateWidget` идёт за новым контроллером | 1 |
| T28 хэндл двигает часы, не рисуя кадра | 2 |
| T29 фрагмент «Why» не отменяет загрузку | 2 |
| P1 комментарий «Why» называет другой исход | 1 |
| P2 на странице хэндл читает `done` после прокачки | 1 |
| P3 `pumpAndSettle` «качает раз в двести миллисекунд» | 1 |
| P4 `close()` в `addTearDown` «возвращается вовремя» | 1 |
| P5 блок кода, которого нет в support-файлах | 2 |
| P6 забор блока «Why» без языка | 1 |
| P7 в переводе пропал абзац | `check_translations` падает |
| P8 в переводе пропала строка таблицы | `check_translations` падает |
| P9 подписки «приходят и с первым импортом» | 1 |
| P10 `ValueListenableBuilder` «тоже переходит» на новый контроллер | 1 |
| P11 `close()` «безопасен только до» `super.dispose()` | 1 |
| P12 слушатель «склеивает» равные состояния, как кадр | 1 |
| P13 фейк «отвечает через двадцать миллисекунд» | 1 |
| P14 пять имён «приходят отдельно» | 1 |
| P15 расширение «никогда не уступает» члену класса | 1 |
| P16 `Listenable.merge` «не закрывает» случай двух контроллеров | 1 |
| P17 `select` и `listen` названы членами | 1 |
| P18 `SoloStream` «исключён» из реэкспорта | 1 |
| B1 блок README, которого не берёт ни один драйвер | сборка падает |
| B2 блок экрана без `import 'dart:async';` | сборка падает |
| B3 экран страницы называет переменную, которой нет | `analyze` падает |
| B4 блок хэндла начинается с другой строки | сборка падает |
| B5 `Policy.droppable` не находит дубликат | 1 |
| B6 `dispose()` страницы не отменяет группу | 1 |
| B7 блок `mixins.md`, которого не берёт ни один драйвер | сборка падает |
| B8 первая попытка раздела о тестах начинается с другой строки | сборка падает |
| B9 фрагмент «Why» на странице не ждёт `cancel()` | 0 |
| B10 первая попытка раздела о подписках не подписывается | 1 |
| B11 фейк драйверов отвечает сразу | 3 |
| B12 чтение `done` не отмечает исход наблюдённым | 2 |
| R1 блок кода перевода разошёлся с оригиналом | `check_translations` падает |
| R2 ссылка страницы в раздел, которого нет | `check_links` падает |
| R3 ссылка перевода в раздел, которого нет | `check_links` падает |

B9 — единственная зелёная, и для стенда она эквивалентна. Фрагмент отменяет
загрузку, которая ещё стоит в очереди, а такую `cancel()` роняет внутри вызова:
исход `Cancelled(manual)` есть уже на следующей строке, ждали future или нет.
По той же причине T7 красит только сверку кода. Что `cancel()` возвращается,
когда задача остановилась, держит тест
`cancel() comes back when the job has stopped` с идущей загрузкой (T3).

B4 и B8 красят сборку, а не драйвер: блок без объявленного имени стенд берёт
по первой строке, и правка этой строки оставляет драйвер без блока. Драйверы
за этими блоками краснят B12 и B11.

## Перевод

`packages/flutter_solo/README.ru.md` правлен вместе с оригиналом: те же 17
заголовков, те же 15 блоков, код совпадает с точностью до комментариев. Сканер
`uvx ru-humanizer`: было 84 из 100 на версии `11fc9a5`, вердикт «правка» — 42
длинных тире, два «X — это Y», «является»; стало 90, вердикт «чисто».
Оставшийся штраф — за заголовки `##`; маркер «внедрени» оставлен: «внедрение
зависимостей» — термин, и так же он стоит в переводе README `solo`. Тире
в прозе, в таблице и в комментариях кода нет. Изменённые абзацы прошли
редактуру по процедуре скилла `humanizer-ru`: жёстких запретов в них нет, пять
фраз переписаны после холодного чтения, без смены смысла.

Сверх зеркала правок оригинала: переведён абзац, которого не было (M2);
«задача» заменена на `Job` там, где речь об объекте — хэндле, исходе,
`cancel()`, — и оставлена для самой работы; `Job` женского рода; future
в прозе — обычное слово без бэктиков; «`SoloProvider`'а нет» стало «Никакого
`SoloProvider` нет»; «является» ушло; «кадр всегда отстаёт на один» ушло вместе
с оригиналом. `SoloSelection` по-прежнему «проекция», выбранное значение —
«выборка». Ссылка в раздел «Ответ за ошибку» — относительная, на русскую
страницу `docs/ru/solo/errors.md`.

## Проверки

В клоне, `packages/flutter_solo`:
`dart format --output=none --set-exit-if-changed .` —
`Formatted 22 files (0 changed)`, `flutter analyze` — `No issues found!`,
`flutter test` — `+154: All tests passed!`; было 85. `dart doc --dry-run` —
`Found 0 warnings and 0 errors.` Пример пакета: формат и анализ чистые,
`flutter test` — `+4: All tests passed!`.

Шапки трёх копий `page_code.dart` правлены, поэтому прогнаны и их пакеты.
`packages/async_job`: `Formatted 74 files (0 changed)`, `No issues found!`,
`+1261: All tests passed!`. `packages/solo`: `Formatted 144 files (0 changed)`,
`No issues found!`, `+1719: All tests passed!`. `packages/solo/example`:
`Formatted 12 files (0 changed)`, `No issues found!`,
`+102: All tests passed!`.

Из корня клона: `reflow.py --check` —
`every paragraph is filled to 79 columns`, `check_line_width.py` —
`no Markdown line over 79 columns`, `check_links.py` —
`every document link resolves`, `check_translations.py` — `no differences`,
`check_doc_shape.py` — `every section opens with code or a table`. Сторожа
`reflow_test.py`, `check_line_width_test.py`, `check_links_test.py`,
`archive_floor_test.py` и `build_site_test.py` — `OK`. `build_site.py` —
`wrote 44 pages under site/src/content/docs`, дерево после него то же.

Стенд прогнан так, как его гоняет задание `flutter`, сборка лежит
в `.artifacts/2026-10-04-flutter-solo-readme-reread/bench2/`:
`python3 tool/flutter_snippets.py` — `wrote 6 files`, `flutter pub get`,
`flutter analyze` — `No issues found!`, `flutter test --concurrency=1`
с выводом в файл — `+33: All tests passed!`, затем
`python3 tool/check_traces.py packages/flutter_solo/doc/mixins.md` по этому
выводу: `packages/flutter_solo/doc/mixins.md: 6 quoted traces, 0 not printed`
и последняя строка, `every quoted trace is what the bench prints`. Исходный
прогон на `11fc9a5` — в `bench0/`, 29 тестов.

Новый тест идёт в архив пакета, поэтому после коммита прогнан и пол:
`tool/archive_floor.py stage` и `run` на Flutter 3.27.0 с Dart 3.6.0, последняя
строка — `every archive passes its gate on the floor: 5 roots`. Набор
`flutter_solo` на полу — те же 154 теста, `async_job` — 1261, `solo` — 1719,
пример `solo` — 102, пример `flutter_solo` — 4. Что сторож утверждает
о `flutter_test` — кадр, запрошенный после прокачки `MaterialApp`, число
прокачек `pumpAndSettle`, запуск тела через `binding.runTest`, — на 3.27.0
держится так же, как на 3.47.0.

Код `lib/` не менялся, кроме двух предложений dartdoc. Ширина этой записи
проверена отдельно: шире 79 колонок в ней только строки таблицы мутаций.

## По чтению владельца

1. Вступление, абзац «What is not here». Он перечислял, чего в пакете нет,
   и среди прочего `SoloProvider` и внедрение зависимостей, но не говорил, куда
   с этим идти. Владелец: надо отправить в scopo. Теперь после перечня стоит
   «Dependencies are left out deliberately: they are passed by other means and
   packages, such as [scopo](https://pub.dev/packages/scopo)», в переводе
   «Зависимости оставлены в стороне сознательно: их передают другими способами
   и пакетами, например scopo». Формулировка та же, что в строке `BlocProvider`
   таблицы соответствий `packages/solo/doc/vs-bloc.md`. Хвост прежней фразы
   о том, что пакет работает по одной задаче за раз, стал отдельной фразой, она
   в третьем пункте. Сканер перевода: 90 до и 90 после.

2. Раздел «Install», абзац под импортом. «`SoloListenable` is the mixin this
   package is about; `SoloBuilder`, `SoloSelector` and `SoloSelection` come
   with it», в переводе «Пакет существует ради миксина `SoloListenable`…».
   Владелец: уже не ради одного миксина, раз в пакете есть `SoloBuilder`,
   `SoloSelector` и `SoloSelection`. Теперь абзац перечисляет собственную часть
   пакета ровно и называет род каждого имени: «The package's own part arrives
   with the same import: the mixin `SoloListenable`, the widgets `SoloBuilder`
   and `SoloSelector`, and the class `SoloSelection`. A second import next door
   adds `select` and `listen` as methods, with the subscriptions `listen` hands
   back», в переводе «Собственная часть пакета приходит с тем же импортом:
   миксин `SoloListenable`, виджеты `SoloBuilder` и `SoloSelector`, класс
   `SoloSelection`. Второй импорт по соседству добавляет `select` и `listen`
   методами, вместе с подписками, которые отдаёт `listen`». Сторож
   `readme_rakes_test.dart` держит обе новые цитаты, а роды имён держит функция
   `ownPart` в `test/support/readme_install.dart`: она собирается, только пока
   `SoloBuilder` и `SoloSelector` виджеты, а `SoloSelection` реализует
   `ValueListenable`.

3. Вступление, тот же абзац «What is not here», фраза о работе по одной задаче.
   Владелец: сказать, что поэтому пакет и называется solo. Теперь: «One job at
   a time is deliberate too, hence the `solo` in the name: it is the subject of
   the package, not a limit of its engine», в переводе «По одной задаче за раз
   пакет работает тоже намеренно, отсюда и `solo` в его имени: в этом его
   предмет, а не предел его движка». Сканер перевода: 90 до и 90 после.

4. Раздел «Usage» и порядок страницы за ним. Первый пример объявлял
   `ProfileController` сразу `with SoloListenable` и рисовал его через
   `ValueListenableBuilder`, а `SoloBuilder` появлялся только в середине
   страницы, в разделе «Builders for any controller». Владелец: может, стоит
   показывать чистый `Solo` и `SoloBuilder`, а `ValueListenableBuilder`
   в другом месте? План перестройки он одобрил, страница перестроена.

   «Usage» теперь объявляет
   `final class ProfileController extends Solo<Profile>` без миксина,
   а `ProfileView` стоит на `SoloBuilder`. Под блоком новая фраза:
   «`SoloBuilder` is what draws the state: it takes the controller as `solo`,
   rebuilds on every change of the state and hands `child` through untouched»,
   в переводе «Состояние рисует `SoloBuilder`: он принимает контроллер как
   `solo`, перестраивается на каждое изменение состояния и передаёт `child`
   нетронутым».

   Сразу за «Usage» встал новый раздел «The controller as a `ValueListenable`»,
   в переводе «Контроллер как `ValueListenable`». Он открывается фразой «The
   framework has builders of its own, and they take a `ValueListenable`. Mix
   `SoloListenable` into the controller, and it is one», в переводе
   «У фреймворка есть свои билдеры, и они принимают `ValueListenable`.
   Подмешайте в контроллер `SoloListenable`, и он им станет». Дальше идёт блок
   с миксином, который пишет тело класса как `// ...same as above...`,
   по образцу блока `SoloStream` в `packages/solo/README.md`, затем
   `ValueListenableBuilder` над этим контроллером и фраза
   о `ListenableBuilder`, `AnimatedBuilder` и `Listenable.merge`. Раздел
   «Builders for any controller» убран: показ `SoloBuilder` ушёл в «Usage»,
   а отличие билдеров переехало в новый раздел: «One thing sets it apart from
   `ValueListenableBuilder`: it compares controllers by identity», в переводе
   «От `ValueListenableBuilder` его отличает одно: контроллеры он сравнивает
   по идентичности». Разделы о выборе значения и о подписке остались
   на контроллере с миксином, и новый раздел говорит об этом одной фразой.

   Там, где страница молча полагалась на миксин, она теперь его называет.
   Вступление: «…and `SoloBuilder` rebuilds a widget on every change of that
   state. Mix `SoloListenable` into the controller, and it is a
   `ValueListenable` of its state as well». «Selecting one value»: «The
   constructor takes a `ValueListenable`: here, the controller with
   `SoloListenable`. For a controller without the mixin,
   `SoloSelection.from(controller, selector)` builds the same selection»,
   в переводе «Конструктор принимает `ValueListenable`: здесь это контроллер
   с `SoloListenable`. Для контроллера без миксина ту же проекцию строит
   `SoloSelection.from(controller, selector)`». «The controller's life»: «Even
   with `SoloListenable` a controller is not a `ChangeNotifier`». Таблица
   «Notes»: первая строка говорит «With `SoloListenable`, `value` and
   `currentState` are the same object», третья — что `Listenable.merge` берёт
   контроллеры с миксином.

   Сторож `packages/flutter_solo/test/readme_rakes_test.dart` вырос с 72 тестов
   до 77, пакет `flutter_solo` — со 186 до 191. На странице два класса с именем
   `ProfileController`, поэтому второй живёт в новом файле
   `test/support/readme_listenable.dart`, и фрагменты, которым нужен
   `ValueListenable` (`SaveButton`, `Listening`, блок второго импорта), берут
   его оттуда. Блок с `// ...same as above...` — единственный кусок страницы,
   которого нет в support-файлах дословно; сторож ждёт ровно его и отдельным
   тестом держит тело класса в `readme_listenable.dart` равным телу
   из `readme_profile.dart`. Мутация: `key: 'load'` в копии заменён
   на `key: 'fetch'`, красным стал один этот тест. Новые тесты держат каждое
   новое утверждение страницы: `SoloBuilder` перестраивается на каждое
   изменение и не трогает `child`; `ValueListenableBuilder`,
   `ListenableBuilder`, `AnimatedBuilder` и `Listenable.merge` принимают
   контроллер с миксином; `SoloBuilder` принимает контроллер с миксином, без
   него и `with SoloStream`; `SoloSelection.from` над контроллером без миксина
   даёт ту же проекцию, что конструктор; контроллер с миксином
   не `ChangeNotifier`; билдеры подписываются на сам контроллер.

   Стенд `tool/flutter_snippets.py` собирает README двумя файлами: модель
   «Usage» с фрагментами, которым хватает любого контроллера, и ту же модель
   под заголовком блока с миксином с фрагментами, которым нужен
   `ValueListenable`. Тело во втором файле стенд берёт из блока «Usage»
   и падает, если блок с миксином перестанет быть заголовком класса,
   комментарием и скобкой. Тестов в стенде стало 43 вместо 42.

   За пределами README тем же коммитом изменены: `description`
   в `packages/flutter_solo/pubspec.yaml` («rebuilds through SoloBuilder or
   ValueListenable»), ссылка записи `SoloBuilder`
   в `packages/flutter_solo/CHANGELOG.md` (теперь на «Usage»), вступление
   `packages/flutter_solo/doc/mixins.md` и его перевода (ссылка на новый
   раздел), пример `packages/flutter_solo/example/lib/main.dart` (чистый `Solo`
   и `SoloBuilder`). В одобренный список не входила, но повторяла прежнее
   вступление строка о пакете в `site/content/index.md`,
   `site/content/ru/index.md` и `site/astro.config.mjs`; теперь она читается
   «The Flutter face: `SoloBuilder`, `ValueListenable`, `select`, `listen`».
   Сканер перевода: 90 до и 90 после у `packages/flutter_solo/README.ru.md`
   и у `docs/ru/flutter_solo/mixins.md`.

5. Раздел «Selecting one value», абзац под блоком `SoloSelector`. Страница
   говорила, что селектор сравнивается по идентичности и замыкание на месте
   на каждом перестроении родителя создаёт новую проекцию: «one
   `removeListener`, one `addListener` and one pick, and with a `changed:` of
   your own the value it compares against starts over. Hold the function in a
   field or a `static` where the parent rebuilds often». Владелец: получается,
   при любом замыкании в `changed` получим перестроение? Это выглядит как баг.
   Так и было, и чинить пришлось не текст, а виджет.

   Зонды на прежнем виджете. Три перестроения родителя с селектором, написанным
   на месте, давали четыре `addListener` и три `removeListener`. С `changed:`,
   написанным на месте и называющим изменением шаг в два, билдер после
   монтирования на нуле, смены состояния на единицу и перестроения родителя
   получал `[0, 1]`: перестроение родителя показывало значение, которое
   `changed:` изменением не называл, а отсчёт шага начинался с него заново.
   Виджет держал внутри `SoloSelection` и на каждую новую функцию заводил
   новую.

   Теперь виджет сравнивает только `solo`, по идентичности, как `SoloBuilder`.
   На контроллер он подписан сам, `selector` и `changed` читает из виджета
   на каждое изменение состояния. Перестроение родителя с другим `selector` или
   другим `changed` выбирает один раз и спрашивает `changed` против значения,
   которое билдер получил последним; подписку оно не трогает. Перестроение
   с теми же двумя функциями не зовёт ни одну. Новый контроллер переносит
   подписку, и первая выборка из него уходит билдеру без вопроса. Тот же
   сценарий с шагом в два теперь даёт `[0]`, `[0, 0]` и после смены состояния
   на двойку `[0, 0, 2]`, а три перестроения родителя оставляют один
   `addListener` и ни одного `removeListener`. Выпущенного поведения правка
   не меняет: `SoloSelector` стоит в разделе `## Unreleased`
   `packages/flutter_solo/CHANGELOG.md`, и запись о нём там переписана.

   По дороге нашлась утечка уже в новом виджете. Функция виджета может бросить
   в `initState` или в `didUpdateWidget`, а подписка к этому моменту стоит.
   Зонд на голом `StatefulWidget`: `State`, бросивший в любом из двух,
   фреймворк оставляет без `dispose`, и следующий проход родителя монтирует
   новый. Поэтому виджет в обоих местах сам снимает слушателя и пробрасывает
   ошибку дальше. Два теста на это были красными до правки: слушатель оставался
   на контроллере.

   Фраза страницы теперь: «The selector and `changed:` can be closures written
   in place, as the selector is above. Such a closure is a new one on every
   build of the parent, and it may pick something else, so the widget picks
   once more and puts the pick to `changed:`. It moves no subscription for
   that, and the value `changed:` compares against stays the one the builder
   was last given», в переводе «Селектор и `changed:` можно писать замыканиями
   на месте, как селектор выше. Такое замыкание на каждом построении родителя
   новое и может выбирать уже другое, поэтому виджет выбирает ещё раз
   и спрашивает `changed:` о результате. Подписку он при этом не трогает,
   а `changed:` по-прежнему сравнивает со значением, которое билдер получил
   последним». Совет держать функцию в поле или в `static` убран: платить
   за замыкание больше нечем. Переход к проекции под блоком прежде говорил, что
   виджет держит `SoloSelection` за вас; теперь это неправда, и фраза читается
   «Where a listenable of the picked value is what you need, the same pick is
   made by an object, a `SoloSelection`, and a `State` holds it in a field»,
   в переводе «Там, где нужен именно listenable выбранного значения, ту же
   выборку делает объект, проекция `SoloSelection`, и `State` держит её
   в поле». Сканер перевода: 90 до и 90 после.

   Набор `packages/flutter_solo/test/solo_selector_test.dart` вырос с 13 тестов
   до 19, пакет `flutter_solo` — со 191 до 197. Новые тесты: замыкания на месте
   не сбрасывают значение для `changed`; не двигают подписку; функции, которые
   родитель держит, на его перестроение не зовутся; новый контроллер начинает
   значение заново; селектор, бросивший на монтировании, не оставляет
   слушателя; селектор или `changed`, бросившие на перестроении родителя, тоже.
   В стороже `packages/flutter_solo/test/readme_rakes_test.dart` тестов
   по-прежнему 77: два переписаны под новую фразу и названы
   `closures written in place cost a pick and no subscription`
   и `a parent rebuild leaves what changed compares with alone`, в третьем
   сменилась цитата.

   Мутации виджета. Три гонялись по всему пакету. Прежний файл на место: шесть
   красных тестов, четыре в наборе и два в стороже. Перестроение родителя берёт
   свежую выборку, не спрашивая `changed`: три красных, два в наборе и один
   в стороже. Без флага, который пропускает уведомление во время подписки: один
   красный, `mounting and immediate unmounting in one frame does not throw when
   the controller publishes on listen`. Ещё две гонялись по набору виджета: без
   снятия слушателя после броска на монтировании и без снятия после броска
   на перестроении родителя. В каждой красным стал один тест, свой.

6. Раздел «Selecting one value», абзац под блоком `_SaveButtonState`. «A field
   is built from the first widget only, though, and a parent can hand the
   `State` another controller», в переводе «Только поле создаётся по первому
   виджету, а родитель может передать `State` другой контроллер». Владелец:
   не могу понять фразу. Она стояла на том, чего не говорила: что `State` живёт
   дольше своего виджета, а «первый виджет» в примере не назван ничем. Теперь:
   «The initializer of the field runs once, though, and reads
   `widget.controller` as it is at that moment. The `State` outlives the
   widget: a parent that rebuilds can hand it a new `SaveButton` with another
   controller, and without `didUpdateWidget` the button would go on taking its
   permission from the old controller while its tap went to the new one»,
   в переводе «Но инициализатор поля выполняется один раз и читает
   `widget.controller`, каким тот был в этот момент. `State` при этом живёт
   дольше виджета: перестраиваясь, родитель может передать ему новый
   `SaveButton` с другим контроллером, и без `didUpdateWidget` кнопка и дальше
   брала бы разрешение у старого контроллера, а её нажатие уходило бы в новый».
   Следующая фраза, «Both come with the field that `SoloSelector` spares you»,
   не говорила, что именно «оба»; теперь «The field and its `didUpdateWidget`
   are what `SoloSelector` spares you», в переводе «От поля и от его
   `didUpdateWidget` избавляет `SoloSelector`». Фразы об инициализаторе
   и о `State` держит тест сторожа
   `without didUpdateWidget it stays with the old one`: он и раньше показывал
   это поведением на `StuckSaveButton`, теперь цитирует и слова. Фразу о том,
   от чего избавляет `SoloSelector`, сторож не цитирует, как не цитировал
   и прежнюю. Та же фраза о первом виджете стояла в dartdoc `SoloSelection`
   и переписана там так же. Сканер перевода: 90 до и 90 после.

7. Раздел «Listening without keeping the callback», конец подраздела «The first
   attempt». «To be given back, the closure would need a field of its own to
   live in», в переводе «Чтобы замыкание можно было вернуть, ему
   понадобилось бы собственное поле». Владелец: стоит показать примером, что
   это значит; и проще не поле, а отдельный метод. Фраза убрана, а за первой
   попыткой встал подраздел «A method instead of the closure», в переводе
   «Метод вместо замыкания». Его блок объявляет
   `void _onChange() => _onState(widget.controller.value);`, отдаёт `_onChange`
   в `addListener` в `initState()` и в `removeListener` в `dispose()`. Под
   блоком: «A method can be named in both places. `removeListener` compares
   with `==`: a method named twice is equal to itself, and a closure written
   twice is not. The cost is a method for every listener, and for every
   `addListener` a `removeListener` that `dispose()` must not leave out»,
   в переводе «Метод можно назвать в обоих местах. `removeListener` сравнивает
   через `==`: метод, названный дважды, равен сам себе, а замыкание, написанное
   дважды, нет. Цена: свой метод на каждого слушателя и на каждый `addListener`
   свой `removeListener`, который нельзя забыть в `dispose()`».

   Блоков `dart` на странице стало 16 вместо 15. В support-файлах сторожа новый
   блок стоит классом `_MethodState`
   в `packages/flutter_solo/test/support/readme_widgets.dart`. Новый тест
   сторожа, `a method named twice is the callback dispose() removes`, держит
   и поведение, и слова: после `dispose()` колбэк больше не зовут, два имени
   одного метода равны по `==`, а два одинаково написанных замыкания нет.
   Сторож вырос с 77 тестов до 78, пакет `flutter_solo` — со 197 до 198.
   Мутация: без `removeListener(_onChange)` в `_MethodState` красными стали
   этот тест и тест, который ищет код страницы в support-файлах. Стенд
   `tool/flutter_snippets.py` берёт новый блок по его подразделу и собирает
   из него виджет `Named`; тестов в стенде стало 44 вместо 43. Сканер перевода:
   90 до и 90 после.

8. Раздел «The controller's life», последний абзац. «A controller shared by
   several screens lives where your other singletons live — a `get_it`
   registration, an `InheritedWidget`, a field of the app object», в переводе
   «…живёт там же, где остальные ваши синглтоны». Владелец: почему синглтоны?
   С `InheritedWidget` контроллеру не обязательно быть синглтоном. Слово
   называло не то свойство: общему контроллеру нужно стоять выше экранов,
   которые его делят, а быть единственным на приложение ему незачем. Теперь: «A
   controller shared by several screens lives where the other objects they
   share live — a `get_it` registration, an `InheritedWidget` above those
   screens, a field of the app object — and is closed there, once», в переводе
   «Контроллер, общий для нескольких экранов, живёт там же, где остальные общие
   для них объекты: в регистрации `get_it`, в `InheritedWidget` над этими
   экранами, в поле объекта приложения. Там же он и закрывается, один раз».
   Сторож эту фразу не цитирует: кода за ней на странице нет. Сканер перевода:
   90 до и 90 после.

9. Тот же абзац, перечень мест, где живёт общий контроллер. Владелец предложил
   написать в разделе примеры со scopo. Зонд в отдельном пакете вне
   репозитория: scopo 0.16.0 с pub.dev против `async_job` из дерева
   не собирается, потому что `JobBase` и `JobContextBase` в дереве переехали
   в `package:async_job/engine.dart`, а scopo берёт их из `async_job.dart`.
   Пример со scopo поэтому пока нельзя ни поставить в support-файлы сторожа,
   ни прогнать стендом. Решение владельца: сейчас назвать scopo в перечне,
   а примеры писать здесь же, в этом README, после обновления scopo. Теперь:
   «…a `get_it` registration, an `InheritedWidget` above those screens, a scope
   of [scopo](https://pub.dev/packages/scopo), a field of the app object — and
   is closed there, once», в переводе «…в регистрации `get_it`,
   в `InheritedWidget` над этими экранами, в скоупе
   [scopo](https://pub.dev/packages/scopo), в поле объекта приложения. Там же
   он и закрывается, один раз». Сторож эту фразу не цитирует. Сканер перевода:
   90 до и 90 после.
