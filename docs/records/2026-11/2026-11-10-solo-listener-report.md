> **Состояние на 2026-11-10:** сделано в ветке `solo-listener` (голова
> `85c0e59a`), в `main` не влито и ждёт выпусков: часть `solo` — коммиты
> `c00f5cbc` и `9e44a3a0`, она выходит с `solo` 1.1.0; остальное — с
> `flutter_solo`. Ревью ветки на Opus: пять находок, три правлены коммитом
> `85c0e59a`, две мелкие отложены. Кода из этого отчёта в `main` нет.
> **Что это:** отчёт об исполнении плана `SoloListener` и о ревью всей ветки.
> **Связанные записи:** `2026-11-09-solo-listener-async-design.md`,
> `2026-11-09-solo-listener-plan.md`, `2026-11-09-solo-listener-design.md`,
> `2026-11-07-bloc-vs-solo-debate-report.md`.

# `SoloListener`: отчёт

Владелец одобрил дизайн `2026-11-09-solo-listener-async-design.md` («да,
снимает с обоих, дизайн одобряю») и план `2026-11-09-solo-listener-plan.md`
(«одобряю, делай сам»). План исполнен в ветке `solo-listener` от `main`
`c989de24`, семь задач и проход правок по ревью. Ветка ждёт выпусков: часть
`solo` входит в `main` перед выпуском `solo` 1.1.0, остальное — перед выпуском
`flutter_solo`, порядок — раздел «Как ветка входит в `main`» плана.

## Коммиты

| Коммит | Задача | Что |
| --- | --- | --- |
| `c00f5cbc` | 1 | `Solo.addChangeListener` и `removeChangeListener`, строки справочника |
| `9e44a3a0` | 2 | `state.md`, README `solo`, `vs-bloc` (строка `state`, `stream`), `CHANGELOG` |
| `18ea1068` | 3 | `SoloListener`, `SoloListenerMode`, `solo: ^1.1.0`, оверрайды |
| `6e8aced1` | 4 | отмена с экраном и новым `solo`, ошибки в `FlutterError` |
| `b524160d` | 5 | два раздела README `flutter_solo`, перевод, стенд |
| `2cc24e79` | 6 | `testing.md`, `mixins.md`, переводы |
| `59cef380` | 7 | строка `BlocListener` в `vs-bloc`, причины отмены, `CHANGELOG` `solo` |
| `85c0e59a` | ревью | находки 1, 2 и 4 |

## Что сделано

**Задача 1.** `Solo` получил `addChangeListener` и `removeChangeListener`.
Слушатель получает пару «прежнее, текущее» синхронно, после слушателей
`addListener` того же изменения. Работает по снимку списка, ошибки уходят
в `onListenerError`, а запись во время обхода приходит следующей парой. Строки
обоих членов в справочнике и его переводе — в этом же коммите, иначе
`reference_page_test.dart` краснел бы (находка 1 ревью плана).

**Задача 2.** `state.md` показывает `addChangeListener` в «Observing state»
рядом с `addListener`, таблица README отправляет туда того, кому нужно
изменение вместе с тем, что оно заменило. `CHANGELOG` `solo`: «Unreleased»
разбит на «Added» и «Documentation».

**Задачи 3 и 4.** Виджет `SoloListener<S>`: реакция — `Job` ядра на микрозадаче
после изменения; режимы `concurrent`, `sequential`, `droppable`, `keepLatest`,
`restart`; уход из дерева или новый `solo` отменяет реакции и сбрасывает
ждущих; ошибки `listenWhen` и реакций — в `FlutterError` через наблюдателя
`JobAnswerer`. До кода задачи 4 краснели девять тестов: `dispose` отменяет
идущую реакцию с `ManualCancelReason`; `dispose` до старта не вызывает реакцию;
`dispose` сбрасывает ждущих; новый контроллер отменяет реакции старого;
бросающий `listenWhen` уходит в `FlutterError`; упавшая реакция уходит туда же;
синхронно бросающий `listener` — тоже; провал после ухода экрана — бросок
и `ScaffoldMessenger.of`. Зелёными уже на коде задачи 3 были: ожидание новым
контроллером отменённых реакций, `droppable` после смены, A → B → A,
закончивший закрытие контроллер, перенос по `GlobalKey`, закрытие контроллера,
отмена без отчёта и шесть записей из `initState`, `build` и `dispose` соседа.

**Задача 5.** README `flutter_solo`: «Reacting to a change» (первая попытка —
снэкбар из билдера, ответ — `SoloListener` с `listenWhen`) и «A reaction the
next change replaces» (первая попытка — обычный `await`, затем `ctx.join`,
затем `ctx.pause` и `ctx.abandonable`; токен — абзацем со ссылкой на страницу
ядра). Таблица выбора, строка Notes об ошибках, ответ «When do listeners run?»,
раздел установки, перевод. Стенд `tool/flutter_snippets.py` собирает новые
блоки в свой файл, трассы времени держат тесты `readme_rakes_test.dart`.

**Задача 6.** `testing.md`: реакция, которая ждёт в обычном `await`, держит
свой таймер и после ухода виджета, и тест падает с «A Timer is still pending»,
если не переведёт часы; `ctx.pause` кончается с виджетом. Сторож — три варианта
в `testing_rakes_test.dart`. `mixins.md`: «The widgets of this package» вместо
«The builders».

**Задача 7.** `vs-bloc`: строка «`BlocListener` for a change this screen did
not make» → `SoloListener`. Dartdoc `SoloCancelReason`
и `ReplacedCancelReason`, строка справочника и таблица «Cancellation details»
называют `SoloListener` код-спаном. Сторож имён в `tool/doc_snippets.py`
считает четыре имени `flutter_solo`.

## Решения исполнителя

- Задача 2: «Unreleased» обоих `CHANGELOG` разбит на «Added» и «Documentation»,
  как в 1.0.0. Цена ошибки — два заголовка.
- Задача 2: `vs_bloc_rakes_test.dart` цитирует строку `state`/`stream` дословно
  и в списке файлов плана не стоял; сторож пошёл за строкой.
- Задача 5: токен через `ctx.onCancel` — абзац со ссылкой на страницу ядра,
  а не блок: остановленный клиент бросает, и без `Job.isCancellationError`
  каждая остановка уходит в `FlutterError`, что блоку пришлось бы показывать
  с фейковым клиентом. Цена ошибки — читатель берёт код с соседней страницы.
- Задача 5: строка Notes — «`listenWhen` or a reaction of `SoloListener`»,
  а не «A listener or a reaction»: «a listener» в этой таблице — слушатель
  контроллера.
- Задача 5: две ловушки — два раздела `##`, новых блоков шесть, `hasLength(17)`
  → 23, стенд собирает их в своём файле `readme_reacting_test`.
- Задача 6: стенд не перезапускался, блоков кода задача не добавила.
- Задача 6: «The widgets of this package»: `SoloListener` своего ничего
  не строит.
- Задача 7: драйверы `doc_snippets` в коммите не гонялись, блоки `vs-bloc.md`
  не менялись; полный гейт после ревью их прогнал.

## Ревью ветки

Независимое ревью Opus 2026-11-10 ветки `c989de24..59cef380`, в своей копии
дерева. Текст ревьюера — дословно, вердикты — мои.

### 1. Важная. Решение README «A wait that gives up» шлёт в `FlutterError` поздний провал брошенного запроса, и README об этом молчит

**Суть.** Раздел «A reaction the next change replaces» предлагает как решение
`await ctx.abandonable(() => api.suggest(text))` и говорит, что старая загрузка
«ends with nobody waiting for it». Но по договору ядра ошибка брошенного
действия идёт в `onError` и дальше в ответ задачи. Dartdoc `abandonable`
в `job_context.dart:46–49`: «its result is dropped, and an error of its own
goes to `onError` and on to the job's answer». У виджета этот ответ —
наблюдатель `JobAnswerer`, то есть `FlutterError.reportError`. `try`/`catch`
вокруг `await ctx.abandonable(...)` такой провал не ловит: `await` к тому
времени уже бросил `Cancelled`. Пользователь, который набирает текст без сети,
получает по отчёту в `FlutterError` на каждую брошенную подгрузку. Если
`FlutterError.onError` направлен в отчёты о падениях, как обычно делают
с Crashlytics, это ложные «фатальные» падения. В тесте виджета такой провал
краснит `takeException`. Страница ядра «A token through `onCancel`» сама
называет это последствие для `join`: «Each stop would reach the crash reports
of the app as a failure». Для `abandonable` в README этого предупреждения нет.

**Свидетельство.** `packages/flutter_solo/README.md:620–625` и перевод
`README.ru.md:619–621`. Зонд — тест в `packages/flutter_solo/test/`, режим
`restart`. Реакция: `try { await ctx.abandonable(() => Future.delayed(100 ms,
() => throw StateError('network down for $s'))); } on Object catch (e) {
log.add('caught …'); if (e is Cancelled) rethrow; }`. Запись 1, через 10 мс
запись 2:

```text
P4 early=null late=Bad state: network down for 1 log=[s1, caught 1 Cancelled, s2, caught 2 StateError]
```

Свой `catch` реакция 1 видит только как `Cancelled`. Её `StateError` через 100
мс приходит в `takeException`, то есть в `FlutterError`.

**Что делать.** Под блоком «A wait that gives up» дописать фразу с переводом
и сторожем `_says`. Смысл фразы: провал брошенного вызова всё равно уходит
в `FlutterError`, поэтому вызов, который может упасть, ловит свою ошибку внутри
действия, переданного `abandonable`. Если такой код оставить вне примера, тест
раздела в `readme_rakes_test.dart` должен показать маршрут поздней ошибки,
по образцу варианта с токеном без имени.

Вердикт: принято, важность оставлена. Сделано в `85c0e59a`: в абзац
«`abandonable` leaves the old request running» README и перевода добавлена
фраза о провале брошенного запроса и о `catch` внутри действия. Тест «a failure
of the abandoned load goes to FlutterError» в двух вариантах: без `catch`
внутри действия провал приходит в `takeException`, с ним — нет, а `catch`
вокруг `await` в обоих видит только `Cancelled`. Краснел на `_says` до правки
README.

### 2. Мелкая. Dartdoc `SoloListener.solo` обещает, что реакции нового контроллера ждут отменённых, а в `concurrent` (режим по умолчанию) и `droppable` это не так

**Суть.** `solo_listener.dart:82–85`: «The reactions to the new one wait for
the cancelled ones to end». Дизайн, пункт 6, говорит иначе: ждут только
`sequential`, `keepLatest` и `restart`, а `droppable` изменение отбрасывает.
Это же написано в dartdoc `SoloListenerMode.droppable` (`:28–31`). Код следует
дизайну, а dartdoc поля противоречит и ему, и соседнему dartdoc. Для режима
по умолчанию утверждение неверно.

**Свидетельство.** Зонд: A пишет 1, реакция ждёт обычным `await` 100 мс; на 10
мс виджет переходит на B, и B пишет 7.

```text
P10 concurrent log=[s1@0, s7@10]
P10 sequential log=[s1@0, s7@99]
P10 droppable  log=[s1@0]
P10 keepLatest log=[s1@0, s7@99]
P10 restart    log=[s1@0, s7@99]
```

**Что делать.** Сузить фразу, например: «In `sequential`, `keepLatest` and
`restart` the reactions to the new one wait for the cancelled ones to end; see
[SoloListenerMode.droppable]». Перевода нет, это dartdoc.

Вердикт: принято, поднято до важной: неверный договор API в режиме
по умолчанию. Сделано в `85c0e59a`: dartdoc поля называет три режима, которые
ждут, а также `concurrent`, который стартует сразу, и `droppable`, который
отбрасывает. Тест «the reactions of the new controller wait for the cancelled
ones» стал четырьмя: `concurrent` стартует на 10 мс, `sequential`, `keepLatest`
и `restart` — на 100 мс; `droppable` держит прежний тест. Поведение было
верным, поэтому красного прогона у правки нет: тест держит исправленный текст.

### 3. Мелкая. После смены `sequential` → `concurrent` ждущие изменения разбираются уже после более нового, и последней идёт реакция на устаревшее состояние

**Суть.** `_changed` в `concurrent` запускает новую реакцию сразу. Ждущие при
этом стартуют из `_finished` только тогда, когда идущих нет совсем. Пример:
в `sequential` идёт реакция на 1, ждут 2 и 3, перестроение в `concurrent`,
запись 4. Реакция на 4 идёт раньше реакций на 2 и 3, и последнее, на что
отвечает экран, — 3, хотя контроллер стоит на 4. Dartdoc `mode` (`:111–114`)
говорит только, что `keepLatest` и `restart` заменяют ждущих. Что `concurrent`
пропускает новое вперёд старых, нигде не сказано. Смена режима на ходу — редкий
случай, поэтому важность мелкая.

**Свидетельство.**

```text
P5 log=[s1, s4, e1, e4, s2, e2, s3, e3]
```

**Что делать.** Одно из двух, решением исполнителя:
- в `concurrent` перед новой реакцией запускать ждущих по порядку (`concurrent`
  тогда тоже «применяется к ждущим»);
- назвать порядок в dartdoc `mode` и поставить тест.

Вердикт: отложено как мелкая. Смена режима на ходу при ждущих — редкий случай,
и в README его нет. Выбор между двумя вариантами — за владельцем.

### 4. Мелкая. Тесты не держат порядок `_letGo` при смене контроллера и проверяют только половину ожиданий Review Focus 1 и 2

**Суть.**
- Дизайн, пункт 6, называет порядок «сначала очистить ждущих, потом отменять»
  важным. При уходе экрана ошибку маскирует флаг `_disposed`. При смене `solo`
  флага нет, и обратный порядок запускает реакцию на ждущее изменение старого
  контроллера. Ни один тест этого не ловит: в тесте
  `a new controller cancels the reactions of the old one` к моменту смены
  реакция уже стартовала, и отмена асинхронна.
- Тест Review Focus 1 (`solo_listener_test.dart:812–827`) проверяет только
  `takeException`, а не то, что следующие реакции идут.
- Тест Review Focus 2 (`:684–702`) не проверяет, что реакции первого A
  отменены.

Поведение во всех трёх случаях верное (зонды ниже), не хватает только сторожей.

**Свидетельство.** Мутация: в `_letGo` строка `_waiting.clear()` перенесена
после цикла отмены. Результат `flutter test test/solo_listener_test.dart` →
`+51: All tests passed!` — мутант выжил. Зонд P11 (`sequential`; в одной сборке
A пишет 1 и 2, и виджет переходит на B): на мутанте `P11 log=[r2]` — реакция
на изменение старого контроллера, на исходнике `P11 log=[]`. Поведение Review
Focus 1 и 2 на исходнике:

```text
P1 <каждый из пяти режимов> ex=Bad state: sync log=[r2]
P2 log=[s1, c1 manual, s2, e2] ex=null
```

Для сравнения та же мутация порядка в ветке `restart` гибнет
на `restart with two writes in one turn reacts to the second only [E]`.

**Что делать.** Добавить тест P11 (`sequential`, две записи и смена `solo`
в одном кадре → реакций нет). В тест Review Focus 1 добавить запись 2
и `expect(log, ['r2'])`. В тест Review Focus 2 добавить реакцию на `ctx.pause`
и проверку `Cancelled(manual)` у первого A.

Вердикт: принято, поднято до важной: мутант пережил весь набор. Сделано
в `85c0e59a`: тест «a new controller drops the waiting states of the old one
before it cancels» — на мутанте краснеет (`Actual: ['r2']`), на исходнике
зелёный; тест синхронного броска проверяет реакцию на 2, тест A → B → A —
`c1 Cancelled(manual)`.

### 5. Мелкая. Оборванный перенос в комментарии `readme_install.dart`

**Суть.** `packages/flutter_solo/test/support/readme_install.dart:8–10`: строка
«own part, and» из трёх слов, а слово `SoloStream` уехало на следующую строку.
Правило «Ширина и перенос строк» `AGENTS.md` требует жадных переносов;
`reflow.py` файлы `.dart` не проверяет.

**Что делать.** Перезалить абзац комментария руками.

Вердикт: отложено как мелкая: читателя пакета не касается.

### Отложено ревьюером как вне плана

- Неограниченный рост ждущих в `sequential` и идущих в `concurrent` — так
  задумано дизайном, не находка.
- `listenWhen`, бросающий `Cancelled`, и реакция с `ctx.uncancellable`
  в `restart` — не зондировал, план и дизайн этих входов не называют.
- `reassemble` и hot reload — не проверял, в тестах виджетов
  не воспроизводится.
- Полный `archive_floor.py` и драйверы `doc_snippets` — не гонял по брифу;
  блоки `vs-bloc.md` не менялись.
- Перевод «Оба шага показывает раздел» вместо «shows both» — смысл сохраняется,
  не поднимаю.
- Русский `CHANGELOG` `flutter_solo` называет разделы README по-английски —
  `check_translations.py` зелёный, не поднимаю.

Вердикт: согласен со всем списком. Рост очередей задуман дизайном. Входы
с `Cancelled` из `listenWhen` и `uncancellable` в `restart` — случаи, которые
ни план, ни разумное использование не называют сломанными. Гейт после правок
прогнал и `floor`, и драйверы.

### Вердикт ревьюера

Готово к слиянию с правками. Код виджета и подписки корректен: все шесть
пунктов Review Focus подтверждены зондами, гонки отмены и порядок ждущих верны,
проверки зелёные. До слияния нужны находки 1, 2 и 4; находки 3 и 5 правятся
по решению исполнителя.

### Что ревьюер запускал

- `git checkout --detach 59cef380` в своей копии.
- `packages/solo`: формат, `dart analyze --fatal-infos`, `dart test` → `+2260`,
  `dart doc --dry-run` → 0 предупреждений.
- `packages/flutter_solo`: формат, `flutter analyze`, `flutter test` → `+323`,
  `dart doc --dry-run` → 0 предупреждений; пример — анализ обоими анализаторами
  и `flutter test` → `+6`.
- Документные проверки из корня — все с кодом 0.
- Стенд `flutter_solo` как в CI: `flutter test --concurrency=1` → `+56`,
  `check_traces.py` для `mixins.md` — 6 трасс, 0 не напечатано.
- Зонды P1–P11 в тестовом файле пакета; две мутации `solo_listener.dart`, откат
  копией: порядок `_letGo` — выжил, порядок `restart` — убит. Зонды удалены,
  копия чиста.

## Гейт

Пять заданий CI локально, на голове ветки: `dart`, `flutter` (со стендом
и сверкой трасс `mixins.md`), `floor` на `~/fvm/versions/3.38.1` (7 корней,
«every archive passes its gate on the floor»), `snippets` (шесть пакетов
стендов, все драйверы, трассы шести страниц) и `docs` (все питоновские
проверки, их сторожа и сборка сайта). Дерево после прогона не сдвинулось.
На `59cef380` гейт зелёный, кроме двух шагов, упавших по вине самого скрипта
прогона: `timeout` нет на macOS, а список трасс был взят устаревший; оба шага
перезапущены отдельно и зелёные. На `85c0e59a`, после правок по ревью, гейт
прошёл целиком: `async_job` +1905, `solo` +2260, пример `solo` +112,
`async_job_lints` +203, `solo_lints` +96, оба плагина через сервер анализа,
`flutter_solo` +329, его пример +6, стенд `flutter_solo` +56.

## Отложенное

- Находка 3: порядок ждущих после смены `sequential` → `concurrent`.
- Находка 5: перенос комментария `test/support/readme_install.dart`.
