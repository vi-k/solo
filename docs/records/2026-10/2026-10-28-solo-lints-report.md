> **Состояние на 2026-10-28:** первая волна сделана: пакет `packages/solo_lints`
> с пятью правилами, тестами, README, CHANGELOG и переводами, в CI и в полу;
> не опубликован. Вторая волна — `key_per_request`, сторож страницы ошибок
> и быстрые исправления — не начата.
> **Что это:** отчёт о реализации `solo_lints` по дизайну: что сделано, где
> разошлось с дизайном и что проверено.
> **Связанные записи:** `2026-10-28-solo-lints-design.md`,
> `2026-10-28-sdk-floor-3-10-report.md`.

# `solo_lints`: отчёт о первой волне

## Что сделано

Пакет `packages/solo_lints` 0.1.0: `analysis_server_plugin: ^0.3.14`,
`analyzer: '>=12.1.0 <15.0.0'`, `sdk: ^3.10.0`. Правила по дизайну:
предупреждения `ctx_in_cleanup`, `release_on_the_call`, `sync_fake_async`,
`await_own_queue` и линт `catch_without_check`.

- `lib/main.dart` — точка входа сервера анализа, объявляет `plugin`. Сам класс
  `SoloLintsPlugin` лежит в `lib/solo_lints.dart`: пробный `publish` без
  библиотеки с именем пакета выдаёт предупреждение, а оно роняет шаг `stage`
  задания `floor`.
- `lib/src/context.dart` — общее: узнать типы ядра и `solo` по имени
  и библиотеке, контекст тела, точки отмены, функции очистки, вызовы
  на контексте.
- `lib/src/rules/` — по файлу на правило.
- `test/` — по файлу на правило, 41 тест: ctx_in_cleanup 10,
  release_on_the_call 7, catch_without_check 11, sync_fake_async 4,
  await_own_queue 9. `test/support/rule_base.dart` кладёт в `newPackage`
  настоящие `lib/` пакетов `async_job`, `solo`, `meta`, `fake_async`, `clock`
  и `collection`, как требовал дизайн.
- `pubspec_overrides.yaml` ведёт `async_job` и `solo` в дерево до выпуска
  0.6.0.
- `README.md`, `CHANGELOG.md` (раздел `## 0.1.0`: пробный `publish` требует
  версию в списке изменений), перевод `README.ru.md` рядом,
  `docs/ru/solo_lints/CHANGELOG.md`, `.pubignore` с `README.ru.md`.
- Репозиторий: задание `dart` в `.github/workflows/gate.yml` получает формат,
  анализ, тесты и `dart doc --dry-run` пакета; пакет в `PACKAGES`
  `tool/archive_floor.py` и `tool/check_dartdoc.py`; две пары
  в `tool/check_translations.py`; `AGENTS.md`, `docs/architecture.md`,
  `docs/conventions.md` и корневой `README.md` называют пакет. Сайт — отдельным
  шагом после первого выпуска, как в дизайне.

## Где разошлось с дизайном

**API на двух краях `analyzer` не одинаков.** Дизайн принимал середину
диапазона на веру, потому что «API правил на обоих краях одинаков». Это
неверно: в `analyzer` 12 именованный аргумент — `NamedExpression`, а список
аргументов — `NodeList<Expression>`; с 13 — `NamedArgument`
и `NodeList<Argument>`. Код, написанный под один край, на другом
не компилируется. Обход — `argumentName` в `lib/src/context.dart`: имя
аргумента читается по токенам (идентификатор, за ним двоеточие), а поверх него
`argumentValue`, `firstPositional` и `namedValue`. Ни один из этих типов в коде
не назван. Середину теперь проверили руками: Dart 3.12.2 (Flutter 3.44.4),
`analyzer` 14.5.0, `analysis_server_plugin` 0.3.24, `analyzer_testing` 0.4.3 —
формат, анализ и 41 тест зелёные. Задания на середину в CI по-прежнему нет.

**`await_own_queue` смотрит и на то, что метод возвращает.** Дизайн брал метод,
который «возвращает `SoloJob`» по объявленному типу. Пример самой страницы
ошибок, `Job<String> sync(int item) => enqueueJob(_sync(item))`
из `packages/solo/doc/children.md`, объявлен как `Job<String>` и мимо такого
правила прошёл бы. Метод считается, если объявленный тип — `SoloJob` или если
метод объявлен в том же файле и статический тип возвращаемого выражения —
`SoloJob`. Метод из другого файла с типом `Job` правило не узнаёт.

**`sync_fake_async` берёт и `FakeAsync.run`.** Дизайн называл только функцию
`fakeAsync`; метод `run` экземпляра `FakeAsync` виснет так же.

**`catch_without_check` молчит в очистке.** Очистка — уже не тело: отмена там
не бросается, и `ctx.check()` в ней сам бросает `StateError`. Блок `try`
учитывается, если в нём есть `await`, `await for` или точка отмены, без
вложенных функций. Исключения — по дизайну: первая инструкция `catch` — точка
отмены (выражением или инициализатором переменной),
`if (ctx.job.isCancelled) rethrow;` или единственный `rethrow;`.

**`ctx_in_cleanup` сообщает и о `ctx.state`.** Чтение `state` у `SoloContext` —
не вызов, и диагноз ставится на само обращение. Вложенная очистка того же `ctx`
внутри очистки проверяется один раз, своим проходом.

## Что проверено

- Формат, `dart analyze --fatal-infos` и `dart test` зелёные на трёх SDK:
  3.10.0 (`analyzer` 12.1.0, `analysis_server_plugin` 0.3.14,
  `analyzer_testing` 0.2.5), 3.12.2 (14.5.0, 0.3.24, 0.4.3) и 3.13.0 (14.6.0,
  0.3.25, 0.4.4).
- Пакет-пользователь, который включает плагин путём, на 3.10.0 и 3.13.0:
  `dart analyze` выдаёт `ctx_in_cleanup` и `await_own_queue` предупреждениями,
  `catch_without_check` — `info` при `diagnostics: catch_without_check: true`;
  `// ignore: solo_lints/await_own_queue` диагноз гасит. После переноса класса
  в `lib/solo_lints.dart` прогон на 3.10.0 повторён.
- `dart pub publish --dry-run` — 0 предупреждений, `dart doc --dry-run` — 0.
- `tool/archive_floor.py stage` и `run` на полу 3.38.1 по всем четырём пакетам.
- Проверки документов: `reflow.py --check`, `check_line_width.py`,
  `check_links.py`, `check_doc_shape.py`, `check_translations.py`,
  `check_dartdoc.py`.

## Чего нет

- Сторожа страницы ошибок: блоки «Don't do this»
  `packages/solo/doc/mistakes.md` с диагнозом своего правила — вторая волна,
  вместе с `key_per_request` и быстрыми исправлениями.
- Плагина в пакетах самого репозитория и упоминаний в README ядра и `solo` —
  позже, решением владельца.
