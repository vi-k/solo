# `Job.ignore()` стал `Job.ignoreFailure()`

> **Состояние на 2026-10-07:** сделано и закоммичено в `main`, не отправлено.
> **Что это:** отчёт о переименовании метода задачи и о том, что им не тронуто.
> **Связанные записи:** `2026-10-04-solo-children-reread-report.md`,
> `2026-10-05-ctx-abandonable-report.md`.

## Зачем

Владелец на втором чтении `packages/solo/doc/children.md`, 2026-10-07:
«не будет ли у нас сильной путаницы из-за ignore у нас и у Future? я уже
несколько раз запутался». На странице рядом стояли `child.ignore()`
и `ctx.run(child).ignore()`: первое — метод задачи, который гасит отчёт ядра
о её провале, второе — `Future.ignore()` на future от `run`. Написаны
одинаково, делают разное, и таблица раздела «Two ways to ignore a child»
существовала ровно из-за этого.

Имя выбирали четыре модели независимо: Fable, Opus 5.5, GPT-6-Astra
и GPT-6.1-Sol. Все четыре назвали `ignoreFailure`: глагол остаётся знакомым,
`Failure` называет предмет и связывает имя с `Failed`, а совпадения написания
с `Future.ignore()` больше нет. Решение владельца: «переименовывай
в ignoreFailure, ignore убери сразу» — без устаревшего псевдонима.

## Что сделано

- `packages/async_job/lib/src/job_base.dart`: объявление и реализация
  `ignoreFailure()`; ссылки dartdoc `[Job.ignoreFailure]` в `job_context.dart`,
  `observer.dart`, `run_all.dart`, `outcome.dart`
  и в `packages/solo/lib/src/solo.dart`. Внутреннее поле `_ignored` осталось.
- Вызовы в тестах и примерах правил анализатор: `Job` не реализует `Future`,
  поэтому после переименования он назвал каждое место, где `ignore` звали
  у задачи, ошибкой `undefined_method`, а места с `Future.ignore()` не тронул.
  По его списку заменено 388 мест в `packages/async_job`, 264
  в `packages/solo`, 35 в `packages/flutter_solo`.
- Страницы и README с переводами: вызовы у задачи и упоминания метода в прозе.
  `ctx.run(child).ignore()`, `cancel().ignore()`, `Future.ignore()`
  и `ignore()` на сохранённой future в «Working beside a child» остались как
  были — это `Future.ignore()`.
- Имена тестов, комментарии и цитаты сторожей `_says(...)`;
  `tool/flutter_snippets.py`; `docs/architecture.md`.
- `CHANGELOG.md` трёх пакетов: запись в «Breaking changes» с «Migrating»,
  у `solo` и `flutter_solo` — унаследованная, со ссылкой на запись ядра.
  Упоминания метода в `## Unreleased` названы новым именем, в разделах
  выпущенных версий оставлены старым.

## Проверки

`dart format`, `dart analyze --fatal-infos`, `dart doc --dry-run` и наборы:
`async_job` 1332, `solo` 1769, пример `solo` 102, `flutter_solo` 186, его
пример 4. Три стенда собраны и пройдены, `tool/check_traces.py` сошёлся.
`reflow.py --check`, `check_line_width.py`, `check_links.py`,
`check_translations.py`, `check_doc_shape.py` зелёные, сайт собран: 47 страниц.
