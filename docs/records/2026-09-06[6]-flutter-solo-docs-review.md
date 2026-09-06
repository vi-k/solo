> **Состояние на 2026-09-06:** все двенадцать находок, список «Что
> дописать» и найденный дефект закрыты тем же коммитом, что и эта
> запись. Вердикт стоит в конце каждой находки.
> **Что это:** ревью `packages/flutter_solo` 0.2.0 глазами пользователя
> пакета: README, отсутствующий пример, dartdoc, `pubspec.yaml`,
> `CHANGELOG.md`, вид на pub.dev. Не код и не архитектура — лицо пакета и
> путь Flutter-разработчика с чистого листа.
> **Связанные записи:** `2026-09-06[4]-jobs-docs-review.md` (такое же
> ревью `jobs`, принято и внесено), `2026-09-03[2]-readme-review.md`
> (ревью README `solo`), `2026-09-06[1..3]-jobs-*.md` (три круга ревью
> кода ядра).

# Ревью документации `flutter_solo` глазами пользователя

## Вердикт ревьюера

Сам пакет — хороший. Пятьдесят девять строк кода, один класс, точный
дартдок, все обещания сошлись с прогоном: листенеры действительно
вызываются синхронно и в порядке подписки, `stream` действительно
приходит микротаской позже, `ValueListenableBuilder`, `ListenableBuilder`,
`AnimatedBuilder` и `Listenable.merge` берут контроллер без единой
оговорки, реэкспорт `solo` вместе с `jobs` не конфликтует ни с одним
именем из `package:flutter/material.dart`. `dry-run` — 0 предупреждений,
`dart doc` — 0 warning'ов, `repository` отдаёт 200, лицензия узнана.

Плохо всё остальное — то, что человек видит.

Первое: **страница пакета не даёт принять решение**. README — 55 строк,
три заголовка, два блока кода. У `jobs` — 330 строк, у `solo` — 932. Нет
«Why», нет границ пакета, нет ссылки на `vs-bloc.md`, нет таблицы
«Coming from bloc». Первая фраза круговая: «Flutter integration for
`solo`» — а что такое `solo` и зачем оно, страница не говорит нигде.
Flutter-разработчик, для которого этот пакет и есть точка входа, обязан
уйти читать README пакета, который на pub.dev представляется словами
«Pure Dart, no Flutter dependency» — ровно той фразой, от которой он
закроет вкладку. И это тем обиднее, что у `solo` есть отличный раздел
«Flutter» на 93 строки (`packages/solo/README.md:636-728`), который в
одиночку сильнее всего README `flutter_solo` целиком.

Второе: **первый же шаг не работает**. Блок «Install» велит написать
`flutter_solo: ^0.1.0`. Публикуется 0.2.0, а `^0.1.0` — это
`>=0.1.0 <0.2.0` (прогон ниже). Версии 0.1.0 на pub.dev не будет
никогда, `flutter pub get` упадёт на version solving. Копировать из
README нечего.

Третье: **у Flutter-пакета нет примера**. pana говорит «No example
found» и снимает 10 баллов, вкладки Example на pub.dev не будет, а
единственный фрагмент README не запускается — в нём нет `main`, и
`CounterView` никто не создаёт. Я собрал пример, которого не хватает:
83 строки, компилируется без замечаний под `flutter_lints`, проходит два
виджет-теста, включая отмену при уходе с экрана.

Четвёртое: **README не знает слова `close`**. Ни `close`, ни `dispose`,
ни `initState` в нём нет ни разу. Про то, что задачу надо остановить при
уходе с экрана и что контроллер никто не закроет за тебя, сказано только
в README `solo`. Прогон подтверждает цену: без `close()` тело доходит до
конца и пишет состояние в контроллер, которого уже никто не смотрит.

Публиковать так не стоит. Не из-за кода — код чист, — а из-за того, что
`flutter_solo` сегодня выйдет к людям как заготовка: страница ни о чём,
установка с неверной версией, без примера и без ответа на первый вопрос
дня («как убрать за собой»). Все двенадцать находок закрываются правкой
документов и `pubspec.yaml` плюс добавлением `example/`; кода трогать не
нужно ни в одной.

## Что проверено

Стенд: `<scratchpad>/flutter-solo-review/bench` — отдельный Flutter-пакет
`flutter_solo_doc_bench`, зависимость `flutter_solo: ^0.2.0` и
`pubspec_overrides.yaml` с путями на `flutter_solo`, `solo` и `jobs`,
`flutter pub get`. `analysis_options.yaml` — `package:flutter_lints`
(то, что стоит у пользователя, а не строгий набор пакета) плюс
`strict-casts`/`strict-inference`/`strict-raw-types`. Локально Dart SDK
3.13.0 (stable, macos_arm64), Flutter 3.47.0 stable.

Прогон стенда — 22 теста, все зелёные (`<scratchpad>/bench-run.txt`):

```
### flutter analyze
No issues found!            (для каждого проверяемого фрагмента отдельно)
### flutter test
00:01 +22: All tests passed!
```

Что в нём:

- фрагмент README дословно (`bench/lib/readme_usage.dart`) — собирается
  без замечаний, виджет перерисовывается;
- путь новичка целиком (`newbie_path_test.dart`): экран, контроллер в
  `initState`, `close()` в `dispose`, уход с экрана на середине задачи,
  и отдельно — что бывает, если `close()` забыть;
- все утверждения шапки README (`claims_test.dart`):
  `ValueListenableBuilder`, `ListenableBuilder`, `AnimatedBuilder`,
  синхронность листенеров и порядок подписки, `stream` микротаской позже;
- вопросы второго дня (`day2_test.dart`): два контроллера на экране,
  `Listenable.merge`, необслуженный `Failed` в `testWidgets`;
- сколько нужно `pump`'ов (`rebuild_probe_test.dart`,
  `pump_recipe_test.dart`) — прогон детерминированный, три запуска
  подряд дали один и тот же журнал;
- порядок в `dispose` (`dispose_order_test.dart`): `close()` до и после
  `super.dispose()`;
- перерисовка на `==`-равном состоянии (`equal_state_test.dart`);
- листенеры после `close()` (`after_close_test.dart`);
- предлагаемый пример (`proposed_example.dart` + два виджет-теста);
- 22 публичных имени реэкспорта против `package:flutter/material.dart`
  на конфликты (`collision_probe.dart`).

Проверки публикации из `packages/flutter_solo`:

```sh
flutter pub publish --dry-run  # 0 warnings, 2 известных hint'а; 6 КБ
dart doc .                     # Found 0 warnings and 0 errors
```

В архив идут `CHANGELOG.md`, `LICENSE`, `README.md`,
`analysis_options.yaml`, `lib/` (2 файла), `pubspec.yaml`,
`test/solo_listenable_test.dart`. `README.ru.md`, `doc/api/`,
`pubspec.lock` и `pubspec_overrides.yaml` отсечены правильно.
`python3 tool/check_translations.py` зелёный: 3 заголовка, 2 блока кода,
«no differences».

pana 0.23.19 **полностью прогнать нельзя**: `solo` ещё не на pub.dev,
резолвинг падает, и всё, что требует `pub get`, обнуляется. Обход через
`dependency_overrides` внутри `pubspec.yaml` не помогает — pana их
вырезает (проверено на копии дерева, `<scratchpad>/panacopy`). То, что
pana посчитала не глядя в резолв:

```
[30/30] Follow Dart file conventions (passed)
        [*] 10/10 Provide a valid `pubspec.yaml`
        [*]  5/5  Provide a valid `README.md`
        [*]  5/5  Provide a valid `CHANGELOG.md`
        [*] 10/10 Use an OSI-approved license (BSD-3-Clause)
[ 0/20] Provide documentation (failed)
        [x]  0/10 dartdoc — не запускался, резолвинг упал
        [x]  0/10 Package has an example  →  "No example found."
[10/40] Support up-to-date dependencies
        [*] 10/10 Package supports latest stable Dart and Flutter SDKs
urlProblems: []
```

Пункт «Package has an example» от резолвинга не зависит: pana смотрит
раскладку файлов (`pana/lib/src/report/documentation.dart:20-38`). То
есть после публикации `solo` эти 10 баллов пакет всё равно не получит —
это находка 3.

`repository` пакета проверен живьём:

```
200  https://github.com/vi-k/solo/tree/main/packages/flutter_solo
200  https://github.com/vi-k/solo/tree/main/packages/solo
404  https://github.com/vi-k/solo/tree/main/packages/jobs   (ещё не запушен)
```

то есть 10 баллов за `repository`, которые сегодня теряет `jobs`,
`flutter_solo` не теряет.

## Находки

### 1. [critical] «Install» ставит `^0.1.0` — версию, которой на pub.dev не будет

`README.md:14-17`:

```yaml
dependencies:
  flutter_solo: ^0.1.0
```

То же в `README.ru.md:18-21`. При этом `pubspec.yaml:5` — `version:
0.2.0`, и по «Следующим шагам» handoff первой и единственной публикуемой
версией будет 0.2.0: 0.1.0 в дереве была, но на pub.dev не уезжала.

Что означает написанное:

```
$ dart run bin/main.dart          # pub_semver 2.1.4
^0.1.0 normalises to: ^0.1.0
  allows 0.1.0: true
  allows 0.1.9: true
  allows 0.2.0: false
```

Цена. Первый шаг человека — скопировать блок «Install» и запустить
`flutter pub get` — кончается «Because ... depends on flutter_solo ^0.1.0
which doesn't match any versions, version solving failed». Дальше он либо
уходит, либо чинит сам и запоминает, что README пакета врёт на первой же
команде. Хуже того, вкладка «Installing», которую pub.dev генерирует сам,
покажет правильное `^0.2.0` — то есть страница будет противоречить сама
себе в двух местах.

Направление правки. Убрать версию из README вообще и сделать как у
соседей — `solo/README.md:34-44` и `jobs`: команда, а не yaml.

```sh
flutter pub add flutter_solo
```

Это заодно снимает сам класс ошибки: команда не устаревает при смене
версии, а yaml-блок устаревает молча — он уже устарел один раз.

**Вердикт (2026-09-06):** Принято. Блока с версией в README больше нет:
вместо него `flutter pub add flutter_solo`, как у соседей. Команда не
устаревает при смене версии — этот yaml устарел один раз и устарел бы
снова.

### 2. [critical] Страница пакета не отвечает на вопрос «что это и брать ли»

Размеры README семьи:

```
jobs           330 lines   12201 bytes
solo           932 lines   34835 bytes
flutter_solo    55 lines    1301 bytes
```

Три заголовка (`# flutter_solo`, `## Install`, `## Usage`) и два блока
кода — это весь текст, который увидит Flutter-разработчик на своей
естественной точке входа.

Чего в нём нет: «Why» (у `solo` — шесть претензий к bloc,
`solo/README.md:9-32`), ссылки на `vs-bloc.md` с восемью сценариями,
таблицы «Coming from bloc» (`solo/README.md:730-745`), границ пакета,
рассказа об исходах, об отмене, об ошибках. Ни одного слова о том, чем
это лучше `setState`, `ChangeNotifier`, `bloc` или `riverpod` — то есть
ровно того, ради чего человек и открывает страницу.

Первая фраза круговая: «Flutter integration for [`solo`](../solo): a
`ValueListenable` face for `Solo` controllers» (`README.md:3-4`). Что
такое `solo`, страница не объясняет ни здесь, ни ниже; последняя строка
(`README.md:54-55`) отправляет за этим на другой пакет.

Отдельная неприятность: тот пакет на pub.dev представляется как «Pure
Dart, no Flutter dependency» (`solo/README.md:5`). Flutter-разработчик,
которого сюда прислали за объяснением, читает первым делом, что пакет не
про Flutter.

И самое обидное. У `solo` есть раздел «Flutter»
(`solo/README.md:636-728`), в котором есть всё, чего нет здесь:
контроллер в `initState`, `close()` в `dispose`, «There is no
`SoloProvider`, and nothing closes the controller for you», где держать
общий контроллер, `switch` по исходу с `mounted` после `await`,
`ListenableBuilder`/`AnimatedBuilder`, «`value` и `state` — один
объект», почему нет сеттера. Девяносто три строки, которые в одиночку
сильнее всего README `flutter_solo`.

Цена. Решение «моё / не моё» за 60 секунд по этой странице принять
нельзя: на ней нет ни одного аргумента. Человек либо уходит, либо тратит
ещё пять минут на чужой README — а таких, кто потратит, меньшинство.

Направление правки. `flutter_solo` — это витрина семьи для
Flutter-мира, и она должна стоять на своих ногах: короткое «Why» своими
словами (последовательные задачи, монопольное владение состоянием,
кооперативная отмена, перерисовка по `ValueListenable`), абзац «что тебе
нужно в `pubspec.yaml`» (находка 7), ссылки на `solo` и на `vs-bloc.md`
абсолютными адресами pub.dev (находка 9), и разделы про жизненный цикл
(находка 4) и тестирование (находка 5). Раздел «Flutter» из `solo`
частично переезжает сюда — по существу он написан про этот пакет, а не
про тот.

**Вердикт (2026-09-06):** Принято. README переписан целиком, 55 строк
стали 240: «Why» своими словами (что за жизненный цикл здесь имеется в
виду и чем это отличается от `setState` и `ChangeNotifier`), границы
пакета, ссылка на `vs-bloc.md`, разделы «Жизнь контроллера», «Исходы»,
«Тестирование» и «Заметки», внизу — что такое `solo` и когда брать его
вместо этого. Раздел «Flutter» у `solo` не тронут: он про то же, но с
другой стороны, и дублировать его целиком смысла нет.

### 3. [important] Примера нет вовсе: pana снимает 10 баллов и вкладки Example не будет

Раскладка пакета (`find packages/flutter_solo`): `lib/`, `test/`,
`README.md`, `README.ru.md`, `CHANGELOG.md`, `LICENSE`,
`analysis_options.yaml`, `pubspec.yaml`, `.pubignore`. Папки `example/`
нет.

pana, прогон:

```
### [x] 0/10 points: Package has an example
No example found.
See package layout guidelines on how to add an example.
```

Этот пункт не зависит от того, что резолвинг сегодня падает: pana просто
смотрит список файлов (`pana/lib/src/report/documentation.dart:20-38`)
против фиксированного списка кандидатов
(`pana/lib/src/maintenance.dart:6-23`). Для Flutter-пакета естественный
кандидат — `example/lib/main.dart`.

Цена двойная. Десять баллов из 160 — это заметная часть оценки для
пакета, у которого больше нечем набрать: своего кода в нём шестьдесят
строк. И вкладка Example на pub.dev — у виджетного пакета первое, куда
человек нажимает, потому что ему нужен не абзац, а экран, который
запускается.

Отдельно: единственный фрагмент README (`README.md:21-52`) сам по себе
не запускается — в нём нет `main`, а `CounterView` никто не создаёт. То
есть даже скопировав всё, что на странице есть, запустить нечего.

Направление правки. `example/lib/main.dart` — один экран, один
контроллер, задача, которую можно отменить уходом с экрана. Я собрал
такой (`<scratchpad>/bench/lib/proposed_example.dart`, 83 строки):
`flutter analyze` — «No issues found!», два виджет-теста зелёные —
проходит путь «кнопка → индикатор → результат в снекбаре» и уход с
экрана на середине без единого исключения. Он показывает разом то, чего
в README нет: `initState`/`dispose`, `close()`, `switch` по `Outcome`,
`Policy.droppable` на двойное нажатие.

**Вердикт (2026-09-06):** Принято. `example/` — отдельный пакет с
`lib/main.dart`: экран, контроллер, `Policy.droppable` на второе нажатие,
`switch` по исходу и `close()` в `dispose`. Это тот же фрагмент, что в
разделе «Как пользоваться», с фальшивым API и экраном вокруг.
`flutter analyze` чист, в `dry-run` пример виден. Локальные пути уехали в
`example/pubspec_overrides.yaml`, закрытый `.pubignore`, — иначе
повторилась бы находка 1 ревью `solo`: опубликованный пример не собрался бы
ни у кого.

### 4. [important] Слова `close` в README нет ни разу, и про уход с экрана не сказано ничего

Подсчёт вхождений в `packages/flutter_solo/README.md`:

```
close        0
dispose      0
initState    0
Outcome      0
done         0
```

Единственное вхождение «cancellation» — в последней строке, в перечне
того, за чем идти в `solo`.

Между тем `SoloListenable.close()` (`lib/src/solo_listenable.dart:44-58`)
— единственный обязательный вызов во всём пакете, и его никто за
пользователя не сделает: `solo/README.md:657-661` говорит об этом прямо,
но говорит на другой странице.

Что показывает прогон (`newbie_path_test.dart`, журнал тела и сборок):

```
LEAVE:    [build: Loading, body: start, State.dispose: close()]
NO CLOSE: [body: start, body: got hello, body: emitted]
          isClosed=false state=Instance of 'Ready'
```

С `close()` в `dispose` тело останавливается там, где ждало
(`ctx.wait`), и дальше не идёт. Без него — доходит до конца, пишет
состояние и держит контроллер живым; на экране этого не видно, потому
что виджета уже нет, и найти такое можно только профайлером.

Заодно проверено то, о чём README тоже молчит и о чём человек спросит
сразу: безопасен ли `close()` из `dispose` в обоих порядках. Безопасен —
`dispose_order_test.dart`, оба варианта (`close()` до `super.dispose()`
и после) зелёные, ни одного «setState() called after dispose».

Цена. Первый экран новичка либо течёт, либо он идёт искать ответ в
чужой README. И то и другое — минут двадцать, ровно тот бюджет, который
у него был на весь первый виджет.

Направление правки. Раздел на десяток строк: контроллер создаётся в
`initState`, закрывается в `dispose` через `unawaited(c.close())`,
`close()` отменяет то, что бежит, и после него листенеры сброшены; общий
контроллер живёт там, где живут остальные ваши синглтоны, и закрывается
там же. Две трети текста уже написаны в `solo/README.md:657-661`.

**Вердикт (2026-09-06):** Принято. Раздел «Жизнь контроллера»: контроллер
создаётся полем состояния, закрывается `unawaited(close())` в `dispose`,
`close()` отменяет то, что бежит, и безопасен по обе стороны от
`super.dispose()`; там же — что `SoloProvider`'а нет, что общий контроллер
живёт там же, где остальные синглтоны, и что `close()` — не `dispose()` и
возвращает `Future`.

### 5. [important] Про тестирование виджетов ни слова, а одного `pump()` не хватает

Слова «test» в README нет. У `solo` раздел «Testing» есть
(`solo/README.md:437`), у `jobs` появился по прошлому ревью — у
виджетного пакета, где тестирование как раз и неочевидно, его нет.

Прогон, три запуска подряд, журнал совпадает до строки
(`rebuild_probe_test.dart`):

```
  initial                      state=0 builds=1  onScreen=0
  after increment(), no pump   state=0 builds=1  onScreen=0
  after pump 1                 state=1 builds=2  onScreen=1
  after two increments         state=1 builds=2  onScreen=1
  after pump 2                 state=3 builds=2  onScreen=1   <--
  after pump 3                 state=3 builds=3  onScreen=3
```

После `pump 2` состояние контроллера уже 3, а на экране всё ещё 1: кадр
отстаёт ровно на один. Тест, написанный очевидным образом
(`expect(find.text('3'), findsOneWidget)` после одного `pump`), падает —
и падает не всегда, а в зависимости от того, сколько задач стояло в
очереди, что выглядит как плавающий тест и стоит вечера.

Оба рабочих рецепта проверены (`pump_recipe_test.dart`, оба зелёные):
`await tester.pumpAndSettle()`, либо `await controller.job().done` и
затем один `pump`. Второй точнее и заодно показывает, зачем задача
вообще возвращает хэндл.

Второе, что относится сюда же. Необслуженный `Failed` в `testWidgets`
валит тест целиком, и `tester.takeException()` его **не** ловит — ошибка
уходит в зону теста, а не через `FlutterError.onError`:

```
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞═══════════════════
The following StateError was thrown running a test:
Bad state: boom
#1      _SoloJob.execute (package:solo/src/job.dart:94:66)
#2      JobBase._execute (package:jobs/src/job_base.dart:533:28)
```

Лечится `job.ignore()` или `await job.done` — проверено, оба варианта
дают зелёный тест. Правило `solo/README.md:417-427` («A job nobody looks
at is not silent») это описывает, но во Flutter-контексте следствие
другое и его надо назвать: в `testWidgets` «fire and forget» — это
красный тест.

Направление правки. Раздел «Testing» на 15 строк: `testWidgets`,
`await job.done` как точка синхронизации, `pumpAndSettle` как запасной
вариант, и строчка про `ignore()`.

**Вердикт (2026-09-06):** Принято, с поправкой к предложенному рецепту.
`await job.done` как единственная точка синхронизации — дедлок, если работа
ждёт таймера: часы внутри `testWidgets` двигает только сам тест, и мой
первый прогон повис на две минуты именно на этом. В разделе стоят оба
рецепта — `pumpAndSettle` и хэндл после сдвига часов, — и оба прогнаны в
стенде настоящими виджет-тестами, вместе с уходом с экрана на середине
задачи. Про необслуженный `Failed` и `takeException()` сказано там же.

### 6. [important] `pubspec.yaml`: нет `topics`, нет `issue_tracker`, а `description` не называет предмет

Соседи их получили, `flutter_solo` пропущен —
`a1aa4e0 chore(solo): topics and an issue tracker for pub.dev` тронул
только `packages/solo/pubspec.yaml`:

```yaml
# packages/solo/pubspec.yaml          # packages/flutter_solo/pubspec.yaml
issue_tracker: .../solo/issues        # (нет)
topics:                               # (нет)
  - state-management
  - async
  - cancellation
  - concurrency
```

Баллов pana это не стоит — проверено, в `pana/lib/src/report/` ни
`topics`, ни `issue_tracker` не упоминаются вовсе. Стоит другого: топик
на pub.dev — это работающий фильтр, по `state-management` человек и
ищет, а страница без топиков в такой список не попадает. Для пакета,
чьё имя ничего не говорит, это единственный способ быть найденным.
`issue_tracker` — вопрос доверия: без него на странице нет кнопки «View
issues», и пакет выглядит ничьим.

`description` — 74 символа, самое короткое в семье (у `jobs` 112, у
`solo` 125) и единственное, которое не называет предмета:

```
Flutter integration for solo: a ValueListenable face for Solo controllers.
```

Строка проходит порог pana (60–180), но это вся информация, которую
человек получает в выдаче поиска pub.dev, и в ней нет ни «state
management», ни «cancellation», ни «rebuild» — ни одного слова, по
которому её ищут.

Направление правки. `issue_tracker: https://github.com/vi-k/solo/issues`
— тот же, что у соседей. Топики — те же четыре, что у `solo`:
`state-management`, `async`, `cancellation`, `concurrency`. Обоснование
именно такого набора: `state-management` — канонический топик pub.dev и
единственный, по которому этот пакет вообще станут искать; остальные три
описывают, чем он отличается от прочих менеджеров состояния; а общий с
`solo` набор склеивает семью — открыв топик, человек видит оба пакета
рядом и сразу понимает, что это одно и то же в двух изданиях. Пятый слот
(pub.dev разрешает пять) лучше оставить пустым, чем занимать `flutter`:
SDK-имя в топиках ничего не фильтрует, платформа и так видна по бейджам.

`description` — переписать так, чтобы она называла предмет и работала
без контекста, например «State management for Flutter: sequential jobs,
exclusive state ownership, cooperative cancellation, rebuilds through
`ValueListenable`».

**Вердикт (2026-09-06):** Принято. `description` переписан и называет
предмет: «State management for Flutter: sequential jobs, exclusive state
ownership, cooperative cancellation, rebuilds through ValueListenable».
`issue_tracker` и четыре топика — те же, что у `solo`, по изложенному в
находке обоснованию; пятый слот оставлен пустым.

### 7. [important] Какие пакеты класть в `pubspec.yaml`, README не говорит, а `Job` берётся из ниоткуда

В единственном фрагменте (`README.md:36`) стоит:

```dart
Job<void> increment() => run<Idle, void>((ctx) async {
```

`Job` приезжает из реэкспорта: `lib/flutter_solo.dart:1-2` — это
`export 'package:solo/solo.dart'`, а `solo/lib/solo.dart:5` — это
`export 'package:jobs/jobs.dart'`. Проверено по сгенерированной справке:
одна публичная библиотека даёт 22 имени — `CancelReason`, `Cancelled`,
`DeferredJob`, `Done`, `Failed`, `Job`, `JobBase`, `JobContext`,
`JobContextBase`, `JobObserver`, `JobStatus`, `JobStream`, `Outcome`,
`Policy`, `Solo`, `SoloBase`, `SoloCancelReason`, `SoloContext`,
`SoloJob`, `SoloListenable`, `SoloObserver`, `SoloQueue`.

О реэкспорте README не говорит ни слова. Сказано об этом в двух местах,
и оба — не здесь: `CHANGELOG.md:9-10` («Re-exports
`package:solo/solo.dart`, so importing `flutter_solo` alone is enough»)
и `solo/README.md:40` («For Flutter, take `flutter_solo` instead — it
re-exports all of `solo`»). Про `jobs` не сказано нигде: то, что
`flutter_solo` тянет и его целиком, не написано ни в одном из трёх
README.

Цена. Вопрос «сколько строк класть в `pubspec.yaml`» — самый первый
после «брать ли», и ответ на него человек получает опытным путём: либо
кладёт три пакета вместо одного, либо ищет `Job` на pub.dev, попадает в
`jobs` и добавляет его отдельно. И то и другое потом живёт в проекте
годами.

Направление правки. Один абзац рядом с «Install»: в зависимостях —
только `flutter_solo`; он реэкспортирует весь `solo`, а `solo` —
весь `jobs`, поэтому `import 'package:flutter_solo/flutter_solo.dart'`
— единственный импорт, и `Solo`, `Job`, `JobContext`, `Outcome`,
`Policy` приходят вместе с ним. Заодно назвать, что даёт сам
`flutter_solo` сверх `solo` — ровно один класс.

**Вердикт (2026-09-06):** Принято. Абзац сразу за «Установкой»: в
зависимостях только `flutter_solo`, он реэкспортирует весь `solo`, а тот —
весь `jobs`, поэтому импорт один, и `Solo`, `SoloContext`, `Job`,
`Outcome`, `Policy` приходят вместе с ним; сверху пакет добавляет ровно
один класс.

### 8. [minor] У контроллера `close()`, а не `dispose()`, и это не `ChangeNotifier`

Проверено (`claims_test.dart`): `c is ChangeNotifier` — `false`,
`c is Listenable` и `c is ValueListenable<int>` — `true`. Метода
`dispose()` у `SoloListenable` нет, есть `close()`
(`lib/src/solo_listenable.dart:47`).

Цена невелика, но осечка гарантированная: во Flutter всё, к чему
подписываются, освобождается через `dispose()`, и рука напишет
`counter.dispose()`. Компилятор поправит сразу, так что это минуты, а не
часы — но README, который вообще не упоминает освобождение (находка 4),
не даёт даже повода задуматься.

Направление правки. Одна фраза там же, где появится жизненный цикл:
«`SoloListenable` — не `ChangeNotifier`; закрывается `close()`, и это
`Future`».

**Вердикт (2026-09-06):** Принято. Фраза стоит в «Жизни контроллера», там
же, где `dispose`: не `ChangeNotifier`, метод `close()`, и он возвращает
`Future`.

### 9. [minor] Ссылка на `solo` — относительная, уводит с pub.dev в дерево исходников

`README.md:3` и `README.md:54` — `[`solo`](../solo)`. Обратная ссылка у
соседа абсолютная: `solo/README.md:6` — `[`flutter_solo`](https://pub.dev/packages/flutter_solo)`,
и `solo/README.md:30` — `[jobs](https://pub.dev/packages/jobs)`.

Ссылка не битая: pub.dev переписывает относительные адреса через
`repository`, и получившийся
`https://github.com/vi-k/solo/blob/main/packages/solo` отдаёт 200
(проверено `curl`). Но ведёт она на GitHub, в дерево файлов, а не на
страницу пакета — то есть читателя, который решает «нужен ли мне ещё и
`solo`», выбрасывает с pub.dev в исходники.

Направление правки. `https://pub.dev/packages/solo`, как в обратную
сторону. Ссылка будет битой до публикации `solo` — это уже известное и
принятое неудобство, а публикация идёт связкой подряд.

**Вердикт (2026-09-06):** Принято. Обе ссылки — абсолютные на pub.dev, как
в обратную сторону у `solo`.

### 10. [minor] У библиотеки нет dartdoc — титульная страница справки пустая

`lib/flutter_solo.dart` целиком:

```dart
export 'package:solo/solo.dart';
export 'src/solo_listenable.dart';
```

Ни `library;`, ни комментария. У соседей есть: `solo/lib/solo.dart:1-3`
— «One job at a time: sequential jobs with exclusive state ownership,
declarative rules and cooperative cancellation», у `jobs` то же самое.

Следствие видно в сгенерированной справке
(`doc/api/index.html`): в списке библиотек стоит голое «flutter_solo»
без единого слова описания. Это первая страница, которую видит человек,
нажавший на pub.dev кнопку «API reference».

Направление правки. Две строки: `/// ...` и `library;` — одна фраза о
том, что даёт пакет.

**Вердикт (2026-09-06):** Принято. У библиотеки появился дартдок в четыре
строки; `dart doc` по-прежнему 0 warnings.

### 11. [minor] Верхняя запись CHANGELOG для первого релиза говорит о переезде, а не о пакете

`CHANGELOG.md:1-4`:

```markdown
## 0.2.0

- Floor raised to `solo: ^0.2.0`, whose job kernel lives in
  `package:jobs`. Nothing changes in `SoloListenable` itself.
```

0.2.0 — первая версия, которая попадёт на pub.dev, и вкладка Changelog
откроется этой записью. Читателю, который видит пакет впервые, она
сообщает, что ничего не изменилось — в пакете, о котором он ничего не
знает. Содержательная запись («Initial release: SoloListenable»,
«Re-exports `package:solo/solo.dart`») стоит ниже, в разделе 0.1.0,
который описывает релиз, недоступный на pub.dev.

Направление правки. Свести обе записи в одну — 0.2.0 как первый
публичный релиз, с содержанием обеих, — или дописать к 0.2.0 строку о
том, чем пакет является.

**Вердикт (2026-09-06):** Принято. `## 0.2.0` — первый публичный релиз, с
содержанием обеих записей: что такое `SoloListenable`, чем он отдаёт
состояние, что `close()` обязателен и что реэкспорт избавляет от двух
других зависимостей. `## 0.1.0` — одна строка: «Never published».

### 12. [minor] Тип `ValueListenable` нельзя назвать, импортировав только пакет и `material.dart`

README (`:6-7`) и дартдок (`lib/src/solo_listenable.dart:6-7`) описывают
класс через `ValueListenable`. Но сам тип пакет не реэкспортирует, а
`package:flutter/material.dart` его не отдаёт: `widgets.dart:18` —
`export 'foundation.dart' show Brightness, UniqueKey;`, а
`ValueListenable` объявлен в `src/foundation/change_notifier.dart:94`.

Проверено компилятором — файл с `material.dart` и
`flutter_solo/flutter_solo.dart` не собирается:

```
test/claims_test.dart:75:19: Error: 'ValueListenable' isn't a type.
    expect(c, isA<ValueListenable<int>>());
```

Лечится `import 'package:flutter/foundation.dart';`. На фрагмент из
README это не влияет — `ValueListenableBuilder` из `material.dart`
приходит, — но всплывает у любого, кто захочет объявить поле или
параметр типа `ValueListenable<S>`, то есть ровно у того, кто собирается
прятать контроллер за интерфейсом.

Направление правки. Либо строка в README, либо
`export 'package:flutter/foundation.dart' show ValueListenable;` в
`lib/flutter_solo.dart` — второе честнее: пакет обещает
`ValueListenable`-лицо, разумно, чтобы имя этого лица приходило вместе с
ним.

**Вердикт (2026-09-06):** Принято, вторым из двух предложенных способов:
`lib/flutter_solo.dart` реэкспортирует `ValueListenable` из
`package:flutter/foundation.dart`. Пакет обещает `ValueListenable`-лицо —
имя этого лица теперь приходит вместе с ним, и в README оно названо среди
того, что даёт единственный импорт.

## Что дописать

Чего в README нет и о чём человек спросит на второй день:

- **Несколько контроллеров на одном экране.** Работает без оговорок —
  проверено (`day2_test.dart`): два контроллера с двумя
  `ValueListenableBuilder` дают `a1,b2`, а `Listenable.merge([a, b])` в
  `ListenableBuilder` даёт `1/1`. Две строки текста, и вопрос закрыт;
  сейчас человек это выясняет пробой.
- **Где живёт контроллер.** «There is no `SoloProvider`, and nothing
  closes the controller for you» (`solo/README.md:657-661`) — это самая
  нужная фраза для Flutter-читателя, и она лежит не на его странице.
  Вместе с ответом про `provider`/`get_it`/`InheritedWidget`.
- **Ошибки.** `Outcome`, `switch` по `Done`/`Failed`/`Cancelled`,
  `job.done`, `job.value`, `ignore()`, `mounted` после `await` — у
  `solo` целый раздел (`solo/README.md:365-435`), у `flutter_solo` ноль
  слов, хотя показ ошибки пользователю — это ровно виджетная задача.
- **Равные состояния не фильтруются.** Прогон
  (`equal_state_test.dart`): три `emit` состояния, равного текущему по
  `==`, дают одну лишнюю сборку (кадр их склеивает), но фильтра, как у
  `Cubit`, здесь нет. Для человека «из bloc» это заметное отличие, и
  одна строка снимает вопрос.
- **Границы пакета.** Что `flutter_solo` даёт сверх `solo` — ровно один
  класс, `SoloListenable`. Сейчас это приходится выводить.
- **Куда идти дальше.** Ссылки на `vs-bloc.md` (восемь сценариев,
  сильнейший аргумент семьи) и на API-справку. На странице
  `flutter_solo` нет ни одной.

**Вердикт (2026-09-06):** Написаны все шесть. Несколько контроллеров на
экране и `Listenable.merge` — в «Заметках», туда же ушли равные состояния
без фильтра. Где живёт контроллер и что его никто не закроет — в «Жизни
контроллера». Ошибки, `Outcome`, `switch`, `mounted` после `await` и
`ignore()` — раздел «Исходы». Границы пакета — последний абзац «Why», а
что даёт сам `flutter_solo` сверх `solo` — абзац в «Установке». Ссылки на
`vs-bloc.md` и на `solo` — в «Why» и в последнем разделе.

## Что хорошо

Не трогать:

- **Код и дартдок.** Пятьдесят девять строк, один класс, ни одной
  лишней сущности. Дартдок точный до мелочи: «A listener removed during
  the pass is skipped; one added during the pass hears the next change»
  (`lib/src/solo_listenable.dart:31-33`) — это ровно то поведение,
  которое подтверждают тесты пакета, и такие фразы в документации
  встречаются редко.
- **Все утверждения README сошлись с прогоном.** Синхронность
  листенеров, порядок подписки, `stream` микротаской позже,
  `ValueListenableBuilder`, `ListenableBuilder`, `AnimatedBuilder`,
  `value` и `state` — один объект. Ни одного обещания, которое не
  выполняется.
- **Реэкспорт не конфликтует.** 22 публичных имени против
  `package:flutter/material.dart` — ни одной неоднозначности
  (`collision_probe.dart`, `flutter analyze` чист). Для пакета, который
  тянет за собой два чужих API целиком, это не само собой.
- **`close()` из `dispose()` безопасен в обоих порядках** — и до
  `super.dispose()`, и после. Ни одного «setState() called after
  dispose», ни одного исключения. Осталось об этом сказать.
- **Публикационная гигиена.** `dry-run` — 0 предупреждений, 6 КБ, в
  архиве ровно то, что нужно; `README.ru.md` отсечён `.pubignore`,
  `doc/api/` и `pubspec.lock` не попали. `dart doc` — 0 warning'ов.
  `repository` отдаёт 200, лицензия узнаётся как BSD-3-Clause, pana даёт
  30/30 по файловым соглашениям.
- **Согласованный пол.** `sdk: ^3.6.0` и `flutter: '>=3.27.0'` — это
  одна и та же точка (Dart 3.6 приехал во Flutter 3.27), а не два
  независимых числа.

## Настоящий дефект

Один, мелкий, вне предмета ревью — записываю коротко, как условлено.

Листенер, добавленный **после** `close()`, всё ещё получает уведомления,
а добавленный до — нет. Прогон (`after_close_test.dart`):

```
after close:              isClosed=true  calls=[7]  state=7
registered before close:  calls=[]              state=7
```

Причина: `close()` — разовая уборка
(`lib/src/solo_listenable.dart:56`, `.then((_) => _listeners.clear())`),
а не состояние, и `SoloListenable.publish` (`:35-42`) не смотрит на
`isClosed`. Соседний канал того же контроллера ведёт себя иначе:
`Solo.publish` (`solo/lib/src/solo.dart:39-41`) событие после закрытия
отбрасывает по `_controller.isClosed`.

Практический сценарий узкий: `externalSetState` после `close()`
разрешён и задокументирован (`solo/lib/src/solo_base.dart:225-232`,
«Stop the source of external states before closing the controller»), так
что попасть сюда можно, только если виджет подписался на уже закрытый
контроллер — например, экран перестроился, пока идёт разрушение. Цена —
лишняя перерисовка, не падение. Лечится либо проверкой `isClosed` в
`publish`, либо фразой в дартдоке `close`.

**Вердикт (2026-09-06):** Принято и починено кодом. `SoloListenable`
запоминает, что уборка прошла, и `publish` после этого не зовёт никого:
слушатель, подписавшийся на закрытый контроллер, больше не получает
уведомлений — ровно как у стрима `Solo`, закрытого к этому моменту.
Уведомления во время самого закрытия не тронуты: `isClosed` поднимается в
начале `close()`, и проверка по нему отняла бы у виджета последний кадр
закрывающегося контроллера. В сьюте — тест «a listener added after close
hears nothing»; мутант (снятая проверка) его роняет, целиком сьюта
8 зелёных.
