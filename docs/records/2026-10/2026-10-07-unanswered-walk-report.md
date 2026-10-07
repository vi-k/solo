# Ответ за ошибку спрашивают по одному провалу

> **Состояние на 2026-10-07:** сделано и закоммичено в `main`, не отправлено.
> Тем же днём второй правкой так же стали звать `onError`, раздел «Отчёт
> тоже по одной ошибке».
> **Что это:** отчёт о том, что ядро само разворачивает `ParallelWaitError`
> перед `onUnanswered` и перед `onError`, и о том, что из-за этого изменилось
> в страницах.
> **Связанные записи:** `2026-10-04-solo-errors-reread-report.md` (пункты 3
> и 6 раздела «По чтению владельца»), `2026-10-02-observing-reread-report.md`,
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

## Отчёт тоже по одной ошибке

Владелец, 2026-10-07, после чтения фразы о хуке отчёта
в `packages/solo/doc/errors.md`: «почему для onError нам не стоит использовать
Job.visitErrors сразу?» — и, выслушав ответ, «делай». Разделы выше описывают
состояние после первой правки; там, где они говорят, что `onError` слышит
ошибку такой, какой она пришла, и что `Job.visitErrors` показан на `onError`,
действует этот раздел.

`JobBase.notifyObserver` идёт по ошибке тем же обходом и зовёт `onError`
на каждый провал и на каждую отмену внутри `ParallelWaitError` отдельно,
со стеком этой ошибки; каждый вызов защищён сам по себе. Отмена приходит, как
и провал: кроме этого хука, о ней не узнаёт никто. Собственная отмена задачи
внутри конверта пропускается, её называет исход; `Cancelled`, который пришёл
один, объявляется, как и раньше, — так доходит отмена, которую бросил колбэк
`whenCancelled`. Через наблюдателя `solo` то же получают `Solo.onError`
и `SoloObserver.onError`; код `solo` не менялся.

Исход, `ifFailed` и `catch` в теле получают ошибку такой, какой её бросили.
`Job.visitErrors` остался публичным для них.

Страницы. В `packages/async_job/doc/observing.md` конец раздела «Answering for
errors» говорит, что `onError` слышит ошибки так же по одной, а наблюдатель
`Failures` заменён чтением исхода: `Job.visitErrors` стоит под
`if (outcome case Failed(...))`. В `packages/solo/doc/errors.md` последняя
фраза абзаца под обработчиком: хук отчёта `onError` слышит их так же, по одной,
и каждый `Cancelled` тоже. Переводы обеих страниц, dartdoc `Job.visitErrors`,
`JobObserver.onError`, `JobAnswerer`, `Solo.onError` и `SoloObserver.onError`,
записи `Job.visitErrors` в двух `CHANGELOG.md`, `docs/architecture.md`.

Тесты. `packages/async_job/test/parallel_wait_test.dart`
и `unanswered_test.dart` переписаны под вызовы по одной ошибке. Сторож
`observing_rakes_test.dart` получил тест «the outcome keeps the envelope, and
Job.visitErrors walks it», а тест об ответе по одному провалу ждёт и двух
вызовов `onError`. Сторож `errors_rakes_test.dart` цитирует новую фразу
и сверяет, что хук услышал провал и четыре отмены, каждую отдельно.

Проверки те же, что ниже: `packages/async_job` 1336 тестов, `packages/solo`
1763, его пример 102, `packages/flutter_solo` 186, его пример 4.

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
