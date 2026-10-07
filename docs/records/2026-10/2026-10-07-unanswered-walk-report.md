# Ответ за ошибку спрашивают по одному провалу

> **Состояние на 2026-10-07:** сделано и закоммичено в `main`, не отправлено.
> **Что это:** отчёт о том, что ядро само разворачивает `ParallelWaitError`
> перед `onUnanswered`, и о том, что из-за этого изменилось в страницах.
> **Связанные записи:** `2026-10-04-solo-errors-reread-report.md` (пункт 3
> раздела «По чтению владельца»), `2026-10-02-observing-reread-report.md`,
> `2026-09-25-observing-rakes-report.md`.

## Зачем

Владелец на втором чтении `packages/solo/doc/errors.md`, 2026-10-07: «если мы
уже всегда ставим Job.visitErrors в onUnanswered и errorHandler, то, может, его
надо запускать под капотом, чтобы onUnanswered и errorHandler получали уже
"распакованные" ошибки?» Каждый ответчик в документах оборачивал своё тело
в `Job.visitErrors`, а первый пример раздела «Answering for an error»,
`_apiFailures.add(error)`, обходился без него и положил бы в список
и `Cancelled`, и целый `ParallelWaitError`. Владелец решил: «делай».

## Что сделано

`JobBase._handleUnanswered` в `packages/async_job/lib/src/job_base.dart` идёт
по ошибке тем же обходом, что и `Job.visitErrors`, и о каждом провале
спрашивает отдельно: `onUnanswered` наблюдателя с `JobAnswerer` или зону, где
задача создана, со стеком этого провала. Каждый вызов защищён сам по себе:
ответ, который бросил, не отнимает ответа у следующего провала. Об отмене —
`Cancelled`, одном или внутри `ParallelWaitError` — не спрашивают никого.
`ParallelWaitError`, который обход прочитать не может, приходит целиком, как
и раньше. `onError` по-прежнему слышит ошибку такой, какой она пришла.

В `solo` код не менялся: `Solo.onUnanswered` и `Solo.errorHandler` получают
то же самое через наблюдателя, которого `solo` ставит на свои задачи.

`Job.visitErrors` остался публичным: он нужен в `onError` и в `catch` вокруг
`.wait` в теле.

## Что изменилось для читающего код

- `onUnanswered` и `Solo.errorHandler` больше не получают `Cancelled`. Раньше
  переопределение получало его и должно было отбросить само.
- На один вызов `onError` с `ParallelWaitError` приходится по вызову
  `onUnanswered` на каждый провал внутри.
- Зона без ответчика получает провалы по одному, а не `ParallelWaitError`.

Всё это не выпущено: `onUnanswered`, `JobAnswerer` и `Solo.errorHandler`
появились после `0.2.0`, поэтому в CHANGELOG поправлены существующие записи,
а отдельной записи о ломающей правке нет.

## Страницы

- `packages/async_job/doc/observing.md`, раздел «Answering for errors»: первая
  попытка — проверка типа в `onUnanswered` — была ловушкой, пока хук получал
  `ParallelWaitError` целиком. Теперь она работает, и раздел открывается
  ответом; подраздел «Each failure on its own» ушёл. `Job.visitErrors` показан
  на `onError`, наблюдатель `Failures`. Вступление называет два раздела,
  которые открываются работающим кодом. Строка таблицы о `Cancelled`, брошенном
  вне тела: `onError`, и никто больше.
- `packages/solo/doc/errors.md`: обработчик в примере — одна строка
  с `Sentry.captureException`; абзац под ним говорит, что хук и обработчик
  получают по одному провалу, а `Cancelled` не приходит. Абзац о `Cancelled`
  от брошенной операции: хуки отчёта узнают, ответа не спрашивают ни у кого.
- `packages/solo/doc/resources.md`: `Cancelled`, брошенный уборкой, доходит
  до `onError` и `Solo.observer`, и дальше не идёт.
- Переводы всех трёх страниц, dartdoc `Job.visitErrors`, `JobAnswerer`,
  `Solo.errorHandler` и `Solo.onUnanswered`, `docs/architecture.md`.

## Тесты

`packages/async_job/test/unanswered_test.dart`: два новых теста — каждый провал
конверта спрашивают отдельно, с ответчиком и без; ответ, который бросил,
не стоит ответа следующему. Восемь тестов ядра и шесть сторожей `solo` ждали
прежнего маршрута и переписаны под новый: отмена до `onUnanswered`
и обработчика не доходит, зона получает провал, а не конверт. Сторож
`observing_rakes_test.dart` получил тест раздела: трасса страницы, зона без
наблюдателя, `onError` с целым конвертом и `Failures` с обходом.

## Проверки

На итоговом дереве, в каждом пакете из его папки:
`dart format --output=none --set-exit-if-changed .`,
`dart analyze --fatal-infos` (`flutter analyze --fatal-infos` для
`flutter_solo` и его примера) и тесты — `packages/async_job` 1335 тестов,
`packages/solo` 1763, его пример 102, `packages/flutter_solo` 186, его пример
4, всё зелёное. `dart doc --dry-run` в трёх пакетах без предупреждений.
Из корня `reflow.py --check`, `check_line_width.py`, `check_links.py`,
`check_translations.py` и `check_doc_shape.py` зелёные. Стенды `vs-bloc`,
`accumulation` и `mixins` прогнаны так, как их гоняет задание `snippets`: все
процитированные трассы напечатаны. Изменённые абзацы переводов прошли
`uvx ru-humanizer --genre academic` с баллом 90 из 100. Раскладка архивов
на полу прошла на коммите `aba92d3`: пять корней, все зелёные.
