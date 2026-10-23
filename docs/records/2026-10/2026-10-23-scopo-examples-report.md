> **Состояние на 2026-10-23:** сделано, коммит в `main`, не отправлено;
> README ждёт чтения владельца.
> **Что это:** примеры со scopo в разделе «The controller's life» README
> `flutter_solo`, сторожа пакета и драйвер стенда.
> **Связанные записи:** `2026-10-21-handoff-archive.md`,
> `2026-10-04-flutter-solo-readme-reread-report.md`.

# Примеры со scopo в README `flutter_solo`

## Повод

2026-10-11, по чтению README `flutter_solo`, владелец захотел примеры со scopo
в разделе «The controller's life», но после обновления scopo: scopo 0.16.0
против `async_job` 0.3.0 не собирался. 2026-10-23 вышел scopo 0.17.0
с `async_job: ^0.3.0`, `sdk: ^3.6.0`, `flutter: >=3.27.0`. Порядок и два
кандидата — `2026-10-21-handoff-archive.md`, «Открытые вопросы владельцу».

## Что сделано

Раздел получил два блока и три абзаца после абзаца о контроллере, общем для
нескольких экранов. Кандидаты взяты оба, как были записаны.

- `ScopeModel` с `create` и `dispose` занимает место `State` из первого блока
  раздела: `create` создаёт контроллер и запускает загрузку, `dispose` зовёт
  `unawaited(controller.close())`, поддерево берёт контроллер через
  `ScopeModel.of`. `dispose` у `ScopeModel` синхронный — так говорит и страница
  `scope_model.md` scopo, — поэтому закрытия никто не ждёт.
- `AsyncDataScope` с `disposeData: (controller) => controller.close()` — для
  случая, когда ждать нужно. Разбор по scopo `async_scope.md`, «Disposal, in
  order»: шаг 5 ждёт дочерние скоупы, шаг 6 — `disposeScope`, то есть
  асинхронный родитель освобождается после детей.

Зонд в отдельном пакете вне репозитория проверил это до правки README:
родитель — `AsyncScope`, чей `disposeScope` пишет в трассу API, сохранение идёт
через `ctx.join`, дерево убирают посреди сохранения. Под `AsyncDataScope`
трасса кончается `save ends`, `parent released`, под `ScopeModel` —
`parent released`, `save ends`. Это и есть фраза README «Under `ScopeModel` the
parent releases it while that save is still running».

## Где держится

- `packages/flutter_solo/pubspec.yaml` — `scopo: ^0.17.0` в `dev_dependencies`.
- `test/support/readme_scopo.dart` — оба блока дословно, отдельным файлом
  от `readme_widgets.dart` (почему — ниже). Файл добавлен в `_support` проверки
  «every piece of its code stands in the support files», число блоков `dart`
  страницы — 17 вместо 15.
- `test/readme_scopo_test.dart` — свой файл, а не группа
  `readme_rakes_test.dart` (находка 3 ревью ниже), четыре теста: `ScopeModel`
  закрывает контроллер при уходе из дерева; под `ScopeModel` родитель уходит
  первым; `AsyncDataScope` держит родителя до конца закрытия, а экран ниже
  достаёт контроллер через
  `AsyncDataScope.of<ProfileController>(context, listen: false).data`. Каждый
  держит свою фразу страницы через `_says`. Четвёртый держит предел ожидания:
  `ScopeConfig.defaultDisposeScopeTimeout` и `defaultWaitForChildrenTimeout` —
  три секунды. Мутации кода страницы в файле поддержки: `disposeData`,
  не возвращающий future закрытия, краснит третий тест (`parent released`
  раньше `save ends`); `dispose: (controller) {}` краснит первый (`isClosed`
  ложно). Файл после мутаций сверен `cmp` с копией.
- `tool/flutter_snippets.py` — `scopo: ^0.17.0` в пакете стенда и драйвер
  `readme_scopo_test` из двух блоков с моделью Usage. Три теста те же, что
  у сторожа; родитель читает `api.saved` в момент освобождения: `[]` под
  `ScopeModel`, `[Ada Lovelace]` под `AsyncDataScope`.
- `README.ru.md` — перевод трёх абзацев, тот же код.

Проверки 2026-10-23, после правок по ревью: `flutter_solo` +246 (было 242),
пример +6, анализ с `--fatal-infos` и формат чистые; стенд — анализ чистый, 50
тестов зелёные; `check_line_width`, `reflow --check`, `check_doc_shape`,
`check_dartdoc`, `check_page_code`, `check_translations`, `check_links`,
`build_site_test` и сборка сайта — чистые; `floor` на 3.27.0 — все пять корней.

## Стык `listen`

scopo экспортирует `ListenableListenExtension` с методом `listen`
на `Listenable`, а второй импорт `flutter_solo`,
`package:flutter_solo/listenable.dart`, — `SoloListen` с методом `listen`
на том же типе. Библиотека, импортирующая оба целиком, не может вызвать
`listen` ни у одного: вызов неоднозначен. Поэтому код страницы со scopo стоит
в своём файле поддержки, своём файле сторожей и своём драйвере.

Пользователь, который возьмёт scopo и раздел «Methods from a second import»
вместе, упрётся в то же. README об этом молчит. Решать владельцу: оставить,
написать в README `flutter_solo` о `hide`, или менять имя в одном из пакетов.

## Ревью работы

Независимый ревьюер на Opus прочёл коммит до правок по ревью, в своей копии,
сверяясь с исходниками scopo 0.17.0 из `~/.pub-cache`; мутации повторил,
`floor` прогнал. Находки — его, в пересказе; вердикты — мои.

**1. README обещает безусловно то, что scopo делает только три секунды.** «It
awaits the future `disposeData` returns…» и «What the parent releases outlives
the jobs of the controller…» верны лишь в пределах `disposeScopeTimeout`
и `waitForChildrenTimeout`, по умолчанию `Duration(seconds: 3)`
(`scope_config.dart:68,83,104`). Зонд ревьюера с `ProfileApi(delay: 10 s)`
и реальным временем через `runAsync` дал трассу `save begins`,
`parent released`, `save ends` и два `TimeoutException` от scopo. Сторожа этого
не видят: задержки по 10 мс, а таймеры scopo живут в `Zone.root`, и фейковые
часы теста их не двигают.

Вердикт: принято, предел проверен по исходникам сам. В README и переводе
названы оба предела, их три секунды, что scopo делает по истечении
и `ScopeTimeout.none`; четвёртый тест `readme_scopo_test.dart` держит значения
по умолчанию и обе фразы. Поведение по истечении сторож не гоняет: это контракт
scopo, и проверять его на реальных часах в наборе `flutter_solo` дорого.

**2. «Where something has to, put the controller in `AsyncDataScope`» верно
только при асинхронном скоупе scopo над ним.** Без родителя или координатора
скоуп нигде не регистрируется, и его никто не ждёт
(`async_scope_parent.dart:5-7`).

Вердикт: принято. Фраза сужена: «Where an asynchronous scope of scopo above it
has to wait», в переводе так же.

**3. `scopo` в `dev_dependencies` связывает выпуски.** scopo 0.17.0 требует
`async_job: ^0.3.0`. Следующий минорный выпуск `async_job` оставит
`flutter_solo` без разрешимых dev-зависимостей, пока не выйдет scopo под него,
а между выпусками ломающая правка `async_job` валит загрузку файла сторожей,
который импортирует scopo, — в коммите это был весь `readme_rakes_test.dart`,
около 80 тестов. Предложено вынести сторожей scopo в свой файл и записать
порядок выпусков `async_job`, scopo, `flutter_solo` в `AGENTS.md` и решение 65
`docs/settled.md`.

Вердикт: принято частью. Сторожа вынесены в `test/readme_scopo_test.dart`,
обход `show` из `readme_rakes_test.dart` ушёл. Порядок выпусков записан в «Что
стоит помнить» `docs/handoff.md`, а не в `AGENTS.md` и `docs/settled.md`: это
новое правило выпуска, и ставить ли его туда — вопрос владельцу.

**4. Перевод: «сохранение, которое контроллер дожидается».** «Дожидаться»
управляет родительным падежом, страница так и пишет в других местах.

Вердикт: принято, «которого».

**5. Шапка и handoff говорят «коммит в `main`», а коммит в ветке копии.**

Вердикт: верно на момент ревью; коммит вливается в `main` перемоткой, после неё
запись точна.
