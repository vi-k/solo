> **Состояние на 2026-10-22:** выполнен, отчёт
> `2026-10-22-seventh-review-wave-report.md`; ревью плана на Opus учтено
> там же.
> **Что это:** план волны по седьмому ревью — все принятые находки обеих
> записей и три ответа владельца, одним заходом до выпуска 0.3.0.
> **Связанные записи:** `2026-10-22-async-job-project-review.md`,
> `2026-10-22-solo-project-review.md`.

# Волна по седьмому ревью: план

Берётся всё, что принято в вердиктах и ответах владельца 2026-10-22. Деление
длинных страниц — в бэклоге, не здесь. Повторы решений 60, 75, 76 и 86
не делаются.

Каждая правка английского документа или комментария во фрагменте кода идёт
с переводом тем же коммитом; изменённые абзацы переводов — через линтер
`humanizer--ru`, только `ERROR`. Тексты, которые цитируют тесты страниц
(`_says`, списки `QUOTED`/`SAID`), правятся вместе со страницей.

## Часть 1. Код ядра: `key` и `describe` у `then`, `shared` и `ctx.each`

L1 ядра, ответ на вопрос 1.

- `Job.then<R>(onValue, {Object? key, String Function()? describe,
  JobObserver? observer})` и `Job.shared({Object? key,
  String Function()? describe, JobObserver? observer})` — в интерфейсе `Job`
  (`job.dart`) и в `JobBase` (`job_base.dart`).
- `_ThenJob` и `_SharedJob` принимают `key` и `describe` и передают в `super`:
  `describe: describe ?? () => 'then'` и `?? () => 'shared'`. Без `describe`
  имя прежнее: `Job(then)`, а с одним `key` — `Job(load: then)`.
- `JobContext.each<T>(stream, onData, {Object? key,
  String Function()? describe})` — в интерфейсе и в `JobContextBase.each`.
- Защищённая фабрика: `JobContextBase.createEachJob(body, {Object? key,
  String Function()? describe})`. Умолчание решает ядро: `each` передаёт
  `describe: describe ?? () => 'each'`, и фабрика ядра —
  `Job.deferred<void>( body, key: key, describe: describe)`. Движок,
  переопределяющий фабрику, передаёт оба дальше.
- `timeout` у `then` не добавляется.
- Dartdoc трёх членов: одна фраза о `key` и `describe` и об умолчании, ссылка
  на «A job's name» `observing.md`; форма решения 103.
- Тесты в `async_job`: имя продолжения, ручки и ребёнка `each` с `key`,
  с `describe`, с обоими и без; `key` доходит до наблюдателя в `onError`
  продолжения (сценарий R16 ревьюера); переопределённая фабрика получает `key`
  и `describe` (`extending_test.dart`, `EachContext`).
- `extending_test.dart`: `EachContext.createEachJob` — новая сигнатура.

## Часть 2. Код `solo`

### 2.1. `ctx.each` и фабрика

- `_SoloContext.createEachJob(body, {key, describe})` передаёт оба
  в `_solo.job(...)` вместо своего `describe: () => 'each'`. `key` у ребёнка
  в `solo` — только имя: политика правит одной очередью корневых задач (решение
  50).
- `_SoloContext.each` и интерфейс `SoloContext.each` (оба в `job_context.dart`
  `solo`) получают те же `key` и `describe` и передают в `super.each`.
- Тест: ребёнок `ctx.each` контроллера печатается с `key` и `describe`.

### 2.2. Один тип задачи контроллера

L1 `solo`, ответ на вопрос 1.

- `SoloQueue.jobs` — `Iterable<SoloJob<Object?>>`.
- `SoloQueue.removeWhere(bool Function(SoloJob<Object?> job) test, …)`.
- `Solo.current` — `SoloJob<Object?>?`.
- `Solo.lastJobWhere(bool Function(SoloJob<Object?> job) test)`.
- `SoloQueue.remove(Job<Object?> job, …)` не меняется: шире принимать можно.
- Тесты защищённой поверхности (`protected_operations_test.dart` и соседи), где
  проверяется тип; новый тест, что элемент `queue.jobs` и `current` — `SoloJob`
  без приведения (статически: присваивание в переменную `SoloJob<Object?>`).
- `reference.md` `solo`: типы в строках `jobs`, `current`, `lastJobWhere`,
  `removeWhere`, если они там написаны; перевод.

## Часть 3. Документы ядра

- **L2.** Слова словаря при первом употреблении на странице ведут на разбор:
  «observe» — `outcomes.md#a-failure-nobody-waits-for`; «answer for» —
  `errors.md#answering-for-errors`; «the zone» — `errors.md#where-errors-go`.
  Страницы: `chains.md`, `children.md`, `streams.md`, `testing.md`,
  `extending.md`, `observing.md`. На README не ссылаться (решение 74). Одна
  ссылка на слово на страницу, при первом употреблении в прозе, не в таблице
  и не в заголовке. Переводы — те же якоря русских страниц.
- **L3.** Dartdoc `JobObserver.onError`, `JobAnswerer.onUnanswered`, `Failed`
  и `Job.whenCancelled` — в форму решения 103: первая фраза, договор, одна
  ловушка, ссылка на раздел страницы. Разбор, который страница уже говорит,
  уходит; то, чего на странице нет, переезжает на неё, а не теряется. Перечень
  источников `onUnanswered` — список, если остаётся в dartdoc.
- **L4.** Dartdoc `JobContext.each` — в ту же форму, ссылка
  на `streams.md#processing-a-stream`; правило о стеке уборки, растущем
  с каждым событием, остаётся одной фразой. Сюда же — фраза из части 1.
- **L5.** README, «The context at a glance»: ячейки — по нескольку слов,
  оговорки под таблицу. Если не уложится — две таблицы: члены, которые ждут,
  и члены, которые регистрируют.
- **L6.** Dartdoc `Job.each` у `cancellable`: с `cancellable: false` `cancel()`
  вернётся, когда кончится поток; на потоке, который может не кончиться, его
  не ждать.
- **L7.** `CHANGELOG.md` ядра: таблица «`0.2.0` | `0.3.0`» в начале «Breaking
  changes», как у `solo`: `ignore()` → `ignoreFailure()`, `whenDone` →
  `untilFinished`, `wait` → `abandonable`, переезд `JobBase`, `JobContextBase`,
  `JobStatus` в `engine.dart`, `Job` → `ChildJob` у `ctx.run`. Проза пунктов
  остаётся. Перевод.
- **`observing.md`, «A job's name»:** абзац о том, что продолжение, ручка
  и ребёнок `ctx.each` берут те же `key` и `describe`, а без `describe`
  называются `then`, `shared` и `each`.
- **`CHANGELOG.md` ядра:** «Added» — `key` и `describe` у трёх членов;
  «Breaking changes» — новая сигнатура `createEachJob` для движков. Перевод.

## Часть 4. Документы `solo` и `flutter_solo`

- **M1.** `packages/solo/example/README.md` → `example/example.md` (`git mv`).
  Проверить ссылки на него в дереве, `tool/` и сайте; `archive_floor.py` берёт
  только `example/*.dart`. Проверка: `dart pub publish --dry-run` в копии
  показывает `example/example.md` в архиве.
- **L2.** `accumulation.md`, у «Neither mode takes anything new»: событие —
  новые данные, в ждущую группу при дренаже оно не вливается, группа уходит
  такой, какой была на `close`; в отличие от дубликата `Policy.droppable`,
  который получает ждущую задачу, потому что новой работы не добавляет. Что
  должно попасть в последний пакет, пишут до `close`. Dartdoc `add` — одна
  фраза. Перевод. Решение в `docs/settled.md` с доводом о debounce.
- **L3.** Dartdoc `SoloSelector`: изменение и возврат до кадра строят ещё раз
  с тем же значением, как `ValueListenableBuilder`.
- **L4.** Dartdoc `Solo.pending`: абзац открывается договором — не `null`, пока
  задача идёт или дренаж не кончился; `closing` и `cancelled by` говорят,
  просили ли её остановиться; «для `close`, который не вернулся» — применение
  после. Строка `pending` в `reference.md` — тем же смыслом. Перевод.
- **`CHANGELOG.md` `solo`:** «Breaking changes» — типы очереди (часть 2.2);
  «Added» — `key` и `describe` у `ctx.each` контроллера, если это видно в API
  `solo`. `flutter_solo` — без записи, если его API не меняется. Переводы.

## Часть 5. Записи

- Итоги — в вердикты каждой закрытой находки обеих записей, с коммитом
  и отчётом; шапки обеих записей.
- `docs/settled.md`: новое решение о дренаже накопителя; решения, которые
  правка задевает (50 — ключ ребёнка), — дописать, если нужно.
- Отчёт `2026-10-22-seventh-review-wave-report.md`.
- `docs/handoff.md`.

## Проверки

Полный гейт (`gate_all.sh`, теперь с кодами выхода тестов): формат, анализ
и тесты пяти корней, стенды и сверка трасс, документные проверки, сборка сайта.
Ширина записей — своей проверкой. Потом ревью сделанного на Opus по копии
дерева, правки по нему, гейт ещё раз.

Коммиты: код ядра и `solo` с документами — по частям, если гейт зелёный
на каждой; итоговые записи — последним.
