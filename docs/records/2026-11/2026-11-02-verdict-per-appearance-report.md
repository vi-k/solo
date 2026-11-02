> **Состояние на 2026-11-02:** сделано и смержено в `main` коммитом
> «test: give one error object a verdict each time it is asked about»,
> отправлено в origin по слову владельца.
> **Что это:** два теста `async_job` на то, что `Job.isCancellationError`
> выносит вердикт каждому появлению ошибки, а не объекту.
> **Связанные записи:** `2026-11-01-async-job-release-report.md`.

# Вердикт фильтра — каждому появлению ошибки

Задачу передала 2026-11-02 сессия scopo по просьбе владельца: пункт тянулся
в её handoff с 2026-10-25. Фильтр приложения `Job.isCancellationError` ядро
спрашивает в `_verdicts` (`packages/async_job/lib/src/job_base.dart`). Его
dartdoc обещает, что фильтр спрашивают «once for each failure», и вердикты
одного обхода служат и `onError`, и ответу. Ни один тест не проверял, что
вердикт относится к появлению ошибки, а не к объекту: ядро, которое
запомнило бы вердикт по `identical(error)`, отдало бы второму появлению того же
объекта ответ первого, и набор остался бы зелёным. Группа «what the filter is
asked about» в `packages/async_job/test/cancellation_error_test.dart` гоняла
разные объекты, а `const Stopped()` там один на все тесты, но фильтр отвечает
о нём всегда одно и то же.

## Что сделано

В `cancellation_error_test.dart` помощник `nameOnlyTheFirst`: фильтр, который
называет первую ошибку, о которой его спросили, и никакую больше, и возвращает
список спрошенных объектов. Два теста в группе «what the filter is asked
about», оба на одном объекте `StateError('connection reset')` у отменённого
задания:

- «one object twice in an envelope: a verdict for each time» — тело бросает
  `ParallelWaitError` с этим объектом в двух `AsyncError`, один обход;
- «one object in two errors of a job: a verdict for each» — тот же объект
  бросают операция `join` и уборка `onDispose`, два обхода.

Ожидание в обоих: фильтр спрошен дважды и оба раза о том же объекте
(`same(failure)`), `onError` слышит оба появления, ответ — `onUnanswered`
и зона — получает одно. Ядро не менялось: тесты зелёные на нём как есть.

## Нагруженность

Две мутации `_verdicts`, откат копией файла:

- кеш вердикта по объекту на один обход, `Map.identity()` с `putIfAbsent`:
  падает первый тест, остальные 24 зелёные;
- кеш на задание, поле `Expando<bool>` с `??=`: падают оба новых теста и «the
  errors no outcome carries of a cancelled job» — у него фильтр спрашивают
  четыре раза о `const Stopped()`, а с кешем один.

Третья мутация, общий статический `Expando` на все задания, слишком грубая: она
роняет 14 тестов файла, потому что `const Stopped()` и вердикты задания без
отмены переходят из теста в тест; как мерило новых тестов её не брали.

## Проверки

`packages/async_job`: `dart format` — 99 файлов, 0 изменений;
`dart analyze --fatal-infos` — No issues found; `dart test` — +1891, All tests
passed.

Поведение ядра не менялось, поэтому scopo, который держит `async_job`
на `'>=1.0.0 <1.1.0'`, это не задевает. Список изменений не тронут: правка
только в тестах, в архив пакета они входят, но пользователю ничего не меняют.
