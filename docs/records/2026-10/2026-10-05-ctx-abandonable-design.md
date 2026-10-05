> **Состояние на 2026-10-05:** сделано в клоне
> `.artifacts/2026-10-05-ctx-abandonable/tree/` по этому дизайну с семью
> находками ревью (`2026-10-05-ctx-abandonable-design-review-report.md`);
> в `main` не перенесено. Расхождения и проверки —
> `2026-10-05-ctx-abandonable-report.md`.
> **Что это:** переименование `ctx.wait` в `ctx.abandonable` — имя, решение
> владельца, устаревший псевдоним, объём волны правок и порядок проверки.
> **Связанные записи:** `2026-10-05-ctx-abandonable-design-review-report.md`,
> `2026-10-02-cancellation-reread-report.md`,
> `2026-10-03-ctx-pause-design.md`, `2026-10-05-ctx-abandonable-report.md`.

# `ctx.wait` становится `ctx.abandonable`

## Зачем

Владелец читал таблицу вступления `packages/async_job/doc/cancellation.md`
второй раз (пункт 1 раздела «По чтению владельца»
`2026-10-02-cancellation-reread-report.md`) и спросил, оставлять ли имена
`wait` и `join`. `join` ему нравится, смущает `wait`. Читатель Dart знает
`Future.wait` и `.wait` у списков и рекордов: они ждут до конца. `ctx.wait` при
отмене перестаёт ждать и оставляет действие работать, и именно этим отличается
от `join`, а имя об этом не говорит. Документы уже называют это свойство словом
«abandon»: «an action abandoned by `ctx.wait`».

Имя выбрано 2026-10-05. Четыре независимых рецензента (Fable, Opus 5.5, Codex
`gpt-6-astra` и `gpt-6.1-sol`) получили одну постановку и предложили
по шесть-семь имён; `abandonable` поставили первым трое, `race` — один.
Владелец до этого отклонил `waitUnlessCancelled` как слишком длинное. Выбор
владельца — `abandonable`. Прецедент проверен по истории выпусков Trio:
в 0.23.0 параметр `cancellable` у `trio.to_thread.run_sync` переименован
в `abandon_on_cancel` — при `True` вызов сразу бросает `Cancelled`, поток
работает дальше, а результат отбрасывается, то есть поведение `ctx.wait`.

Имя встаёт в пару к `ctx.uncancellable`: оба прилагательных говорят, что будет
с действием при отмене, — его бросят или отмену придержат.

## Что меняется

Только имя. Поведение, параметры (`dispose`, `discard`), тип и порядок проверок
прежние; приватный `_race`, на котором стоит вызов, остаётся.

```dart
final rows = await ctx.abandonable(database.readAll);
await ctx.abandonable(() => database.migrate(stop));
final db = await ctx.abandonable(Database.open, discard: (db) => db.close());
```

### Устаревший псевдоним

`wait` остаётся на один выпуск: `@Deprecated` с отсылкой к `abandonable`, тело
зовёт `abandonable` с теми же аргументами. Объявлен он и в интерфейсе
`JobContext`, и в `JobContextBase`, иначе тело с контекстом типа `JobContext`
перестанет собираться, и псевдоним ничего не даст. Пометка `@Deprecated`
и dartdoc стоят на обоих объявлениях: устаревание не наследуется, и без пометки
на переопределении вызов на подклассе `JobContextBase`, движке вроде
`MyContext` из `doc/extending.md`, анализатор не назовёт (находка 2 ревью).
Удаляется в первом ломающем выпуске после `0.3.0`.

Почему псевдоним, хотя `solo` дважды переименовывал без него. Там причины были
свои: псевдоним `controller.state` собирался бы внутри тела и оставлял дыру,
ради которой имя меняли. Здесь дыры нет — имя меняется ради читателя, поведение
то же, — а `ctx.wait` стоит почти в каждом теле каждого пользователя.
С псевдонимом `0.3.0` собирается, а анализатор подсказкой
`deprecated_member_use` уровня info называет замену в строке вызова. Info
не роняет `dart analyze`, но роняет `flutter analyze`, где infos фатальны
по умолчанию, и `dart analyze --fatal-infos`: «Migrating» говорит это прямо
(находка 6).

Цена псевдонима: класс, который **реализует** `JobContext` (`implements`,
например подделка в тестах), должен реализовать оба члена — новый член
интерфейса ломает такой класс с псевдонимом или без. Движок, который
**наследует** `JobContextBase`, не замечает ничего.

Ошибка вызова после конца задачи и во время уборки собирается как
`'cannot $action'` (`throwIfFinished`, `throwIfDisposing`), и соседи передают
глагольную фразу: `'run an uncancellable action'`, `'register onCancel'`.
`abandonable` передаёт `'run an abandonable action'`, псевдоним — `'wait'`, как
сейчас (находка 3).

### Где имя меняется

Всё, что описывает текущий API, переходит на `abandonable` одной волной:

- код, dartdoc и комментарии `packages/async_job/lib`, `packages/solo/lib`,
  `packages/flutter_solo/lib` — ссылки `[wait]`, `ctx.wait(...)` в примерах
  dartdoc, `JobContext.wait`, неквалифицированный `wait(` в расширении
  `_JobStreamBody` (`job_stream.dart`), комментарии, которые анализатор
  не видит;
- тесты всех трёх пакетов и примеры (`example/`) — вызовы, имена групп
  и тестов, где `wait` — имя члена, и идентификаторы, названные по члену
  (`viaWait`, `exportWithWait`, `delayUnderWait`, `throughWait`, `probeWait`,
  `runWaitingDownload` и подобные); `packages/solo/test/wait_test.dart` — весь
  о члене — становится `abandonable_test.dart`;
- сторожа, которые цитируют прозу страниц: `_says(...)`, ключи вроде `_calls`,
  `packages/solo/test/cancellation_rakes_test.dart`, который вынимает список
  членов из прозы `doc/cancellation.md` и ждёт в нём `'wait'`; проза и её
  сторож меняются одним коммитом;
- страницы `doc/`, README и их переводы в `docs/ru/` и `README.ru.md`;
- `docs/architecture.md`: один `ctx.wait` и десять `wait` в бэктиках;
- стенды `tool/doc_snippets.py` и `tool/accumulation_snippets.py` — их вставки;
  у второго `.replace('ctx.wait', 'ctx.join')` с `assert` и комментарий
  о `ctx.wait`. `tool/flutter_snippets.py` и списки `QUOTED`/`SAID` имени члена
  не содержат;
- `site/astro.config.mjs` — описание страницы, где перечислены контрольные
  точки;
- раздел `Unreleased` в `CHANGELOG.md` трёх пакетов: записи, которые называют
  `ctx.wait`, переходят на новое имя, и в начало ломающих изменений `async_job`
  встаёт запись о переименовании с «Migrating» — заменить `ctx.wait`
  на `ctx.abandonable`, псевдоним до следующего ломающего выпуска. У `solo`
  и `flutter_solo` — короткая запись со ссылкой на запись ядра.

Не меняется:

- выпущенные разделы `CHANGELOG.md` (`0.2.0`, `0.1.0`) и записи
  в `docs/records/` — история;
- `Future.wait`, `.wait` у списков и рекордов и глагол «wait/ждать» в прозе:
  «the wait ends there», «Stops waiting» и подобное описывают ожидание,
  а не член;
- имена файлов `waiting_test.dart` и `parallel_wait_test.dart` пакета
  `async_job`: первый о том, как задача ждёт, второй о `.wait` из Dart; имена
  тестов внутри них, где `wait` — член, правятся по общему правилу.

Проза вокруг имени правится там, где глагол держался за имя: «`ctx.wait`
waits…», «`wait` stops waiting» читаются иначе, когда имя — прилагательное.
Таблица вступления `cancellation.md` после пункта 1 чтения говорит о каждом
члене, что он делает с ожиданием, и остаётся такой.

### Как найти все вызовы

Псевдоним помечен `@Deprecated`, но сам гейт пропущенный вызов не поймает
(находка 1 ревью). Вызов из другого пакета анализатор отмечает info
`deprecated_member_use`, а вызов из того же пакета — линт
`deprecated_member_use_from_same_package`, который на 3.13 по умолчанию
выключен; гейт гоняет `dart analyze` без `--fatal-infos`, и info его не роняют.
Поэтому линт включается в `analysis_options.yaml` `async_job` насовсем, если
пол 3.6.0 его принимает, а иначе только на волну. Критерий конца волны:
`dart analyze --fatal-infos` (`flutter analyze` для `flutter_solo`) без единого
`deprecated_member_use*` во всех трёх пакетах, двух примерах и трёх стендах.
Тесты самого псевдонима несут `// ignore:` с именем правила. Прозу находит
поиск по имени `wait` в бэктиках, `ctx.wait`, `[wait]`, `.wait(` на контексте
и `JobContext.wait`; каждое попадание решает человек, потому что `[a, b].wait`
и «wait» в прозе остаются.

## Сторож

- Тест псевдонима в `async_job`: `wait` отдаёт значение, бросает `Cancelled`
  при отмене, оставляет действие работать и отдаёт поздний результат
  в `dispose` — так же, как `abandonable`, в одном сценарии для обоих.
- Тест точного текста ошибки после конца задачи для обоих имён:
  `cannot run an abandonable action` и `cannot wait`.
- Проверка, что вне раздела выпущенных версий `CHANGELOG.md` и вне записей
  `ctx.wait` не остался: скрипт в отчёте о волне, а не в CI.

## Проверки

Формат, анализ и тесты трёх пакетов и двух примеров, три стенда
и `tool/check_traces.py`, пять проверок документов, сборка сайта, пол
(`tool/archive_floor.py` на 3.27.0) — пол важен: `@Deprecated` на члене
интерфейса и переопределение в `JobContextBase` должны собраться на Dart 3.6.0.

## Выпуск

`solo/pubspec.yaml` держит `async_job: ^0.2.0`: `solo` выходит только после
`async_job` 0.3.0 и с поднятым ограничением. Сайт выкладывается при push
в `main` и покажет `abandonable` раньше pub.dev, как и всё из `Unreleased`.

## Открытое

Нет. Имя и псевдоним — решения этой записи; псевдоним — обещание владельцу
2026-10-05, когда он выбирал имя.
