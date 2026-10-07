# `onError` и `onCancel` у `run` стали `ifFailed` и `ifCancelled`

> **Состояние на 2026-10-07:** сделано и закоммичено в `main`, не отправлено.
> **Что это:** отчёт о переименовании двух параметров `run` и `job` в `solo`
> и о том, что им не тронуто.
> **Связанные записи:** `2026-10-07-ignore-failure-rename-report.md`,
> `2026-10-03-solo-cancellation-reread-report.md`.

## Зачем

Владелец на втором чтении `packages/solo/doc/cancellation.md`, 2026-10-07:
«посоветуйся, не нужно ли переименовать колбэки onCancel и onError у run».
У `run` и `job` два параметра синхронно вычисляют состояние после исхода
`Failed` или `Cancelled`. Теми же словами в том же API названо другое: хук
контроллера `Solo.onError` и `SoloObserver.onError`, куда приходят ошибки для
отчёта, и `ctx.onCancel`, который зовёт колбэк в момент принятия отмены.
В примере `seek` раздела «A deadline of a job» параметр `onCancel:` и вызов
`ctx.onCancel(...)` стояли в одном `run` через четыре строки, а странице
приходилось писать «the `onCancel` parameter of `run`» и «`run(onError: ...)`».

Спрашивали четыре модели независимо: Fable, Opus 5.5, GPT-6-Astra
и GPT-6.1-Sol. Все четыре ответили переименовать оба параметра парой: главным
нарушителем назван `onCancel`, единственный в API, который зовётся после
завершения отменённого и возвращает значение, а `onError` идёт с ним, потому
что параметры всегда описываются вдвоём. Имена разошлись два на два:
`ifFailed`/`ifCancelled` у Fable и Opus, `stateOnError`/`stateOnCancel` у Astra
и Sol. Решение владельца: `ifFailed` и `ifCancelled`.

## Что сделано

- `packages/solo/lib/src/solo.dart`: параметры `ifFailed` и `ifCancelled`
  у `job` и `run`, dartdoc обоих; `packages/solo/lib/src/job.dart`: поля
  `_ifFailed` и `_ifCancelled`. Псевдонима со старым именем нет.
- Вызовы в тестах и примерах: аргументы заменены во всех файлах
  `packages/solo/test`, `packages/solo/example`, `packages/flutter_solo/test`
  и `packages/flutter_solo/example`, после чего анализатор назвал тридцать
  шесть мест, где `onError:` и `onCancel:` принадлежат не `run`, а `listen`,
  `then`, `StreamController` и подобным, и они возвращены. Метки трасс и имена
  тестов, которые называли обработчик состояния старым словом, переименованы
  следом.
- Страницы `solo` и оба README на двух языках: блоки кода и проза. Оговорка
  «the `onCancel` parameter of `run`» больше не нужна; абзац о тёзке под
  `ctx.onCancel` в `packages/solo/doc/cancellation.md` убран.
- `packages/solo/CHANGELOG.md` и `packages/flutter_solo/CHANGELOG.md`: запись
  в «Breaking changes»; записи раздела «Unreleased», которые называли
  обработчики состояния, говорят новыми именами.
- `docs/architecture.md`, `tool/doc_snippets.py` (текст одного сторожа).

## Что не тронуто

Хуки `Solo.onError`, `SoloObserver.onError`, `JobObserver.onError`,
`Solo.errorHandler` и `ctx.onCancel` называются как раньше, как
и `Job.visitErrors(onFailure:, onCancelled:)` ядра. Пакет `async_job`
не менялся. Записи в `docs/records/` и разделы CHANGELOG о выпущенных версиях
хранятся как написаны.

## Проверки

`dart format`, `dart analyze --fatal-infos` и тесты зелёные: `solo` — 1762
теста, его пример — 102, `flutter_solo` — 186, его пример — 4;
`dart doc --dry-run` у `solo` без предупреждений. Стенды
`tool/doc_snippets.py`, `tool/accumulation_snippets.py`,
`tool/flutter_snippets.py` и `tool/check_traces.py` зелёные. Проверки
документов (`reflow.py --check`, `check_line_width.py`,
`check_translations.py`, `check_links.py`, `check_doc_shape.py`) зелёные.
