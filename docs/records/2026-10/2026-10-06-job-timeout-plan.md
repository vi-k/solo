> **Состояние на 2026-10-06:** первая редакция, ждёт ревью на Opus. Работа
> не начата.
> **Что это:** план работ по `2026-10-06-job-timeout-design.md`: две волны
> в клоне — код с тестами и dartdoc, затем страницы с переводами и сторожами —
> и перенос в `main`.
> **Связанные записи:** `2026-10-06-job-timeout-design.md`.

# План: срок задачи

Источник правды — вторая редакция спеки `2026-10-06-job-timeout-design.md`.
План говорит, в каком порядке и где её делать; где план и спека расходятся,
права спека, а расхождение — дефект плана.

## Где

Клон `main` на `HEAD`: `git clone` локального репозитория
в `.artifacts/2026-10-06-job-timeout/tree`. Не worktree агента: тот встаёт
на `origin/main`, а в `main` есть неотправленные коммиты. Оверрайды разработки
в дереве уже живут — `solo` и `flutter_solo` собираются против дерева
`async_job`.

Две волны, каждая — отдельный агент на Opus в том же клоне, одна за другой.
Каждая кончается коммитом в клоне. Основная сессия проверяет коммит волны,
гоняет проверки и переносит его в `main` (`git fetch` из клона
и `cherry-pick`), обновляя `docs/handoff.md` тем же коммитом.

Владелец тем временем читает `packages/solo/doc/children.md`
и `packages/solo/doc/streams.md`, и правки по его вопросам идут в `main`. Волны
этих страниц не трогают, поэтому перенос конфликтов не ждёт; если `main` ушёл
вперёд, клон перед второй волной подтягивает его (`git pull --rebase`).

## Волна 1: код, тесты, dartdoc, CHANGELOG

### Ядро, `packages/async_job`

1. `lib/src/outcome.dart`: `TimeoutCancelReason` как в спеке, рядом с прочими
   причинами; экспорт тем же путём, что у них.
2. `lib/src/job_base.dart`, конструктор `JobBase`: `Duration? timeout` сразу
   за `cancellable`. Проверки в конструкторе, до любого состояния:
   `timeout <= Duration.zero` — `ArgumentError.value(timeout, 'timeout', …)`;
   `timeout != null && !cancellable` — `ArgumentError` с объяснением, что срок
   отклоняемый. Поля: срок, трасса `StackTrace.current` из конструктора (только
   когда срок задан), таймер, `Cancelled` срока. Геттера нет.
3. `Job(...)`, `Job.deferred(...)`, `_Job`, `_AutoJob`, `_DeferredJob` передают
   `timeout`; `Job.each` и `_EachJob` — нет, `ctx.each` и продолжение `then` —
   тоже нет.
4. `_start`: таймер ставится сразу после `_status = running` и до `started()`.
   Колбэк строит `Cancelled.by(reason: TimeoutCancelReason(timeout),
   started: true, stackTrace: trace)`, запоминает этот объект и зовёт
   `cancelWith` в `try`/`catch`; пойманное — в `notifyError`.
5. `_execute`, сразу после `await _awaitChildren()` и проверки `isFinished`:
   снять таймер и обнулить поле; если `_heldCancel` — тот самый объект срока
   (`identical`), обнулить `_heldCancel`. Комментарий называет, почему здесь:
   дальше уборка и барьеры группы, а отмена там переписывает исход.
6. `finish`: снять таймер и обнулить поле, рядом с обнулением `_heldCancel`.
7. dartdoc: `timeout` у `Job.new` — от старта тела, тело и дети после тела,
   не уборка; `Cancelled(timeout)`, а не `TimeoutException`, в отличие
   от `Future.timeout`; секция `uncancellable` придерживает; ошибки аргументов;
   задача, не кончившаяся к концу теста, держит таймер. `Job.deferred`
   и `JobBase` ссылаются на `Job.new`. `TimeoutCancelReason` — свой dartdoc.
8. `test/timeout_test.dart`: семнадцать пунктов раздела «Тесты» спеки, под
   `fakeAsync`; утверждения — вне зоны, как в остальных сторожах (память:
   `expect` внутри `runZonedGuarded` глотается обработчиком).
9. `CHANGELOG.md`, «Unreleased»: новый параметр и причина, в разделе
   добавлений, по форме соседних записей.

### `packages/solo`

10. `job`, `run`, `collect`, `accumulate` в `lib/src/solo.dart`:
    `Duration? timeout` сразу за `cancellable`, дальше в `_SoloJob`
    (`lib/src/job.dart`) и в `JobBase`. Аккумулятор
    (`lib/src/accumulator.dart`): поле и параметр внутреннего конструктора,
    та же проверка, что в `JobBase`, при создании — тексты ошибок те же;
    в `_job(...)` срок передаётся каждой задаче.
11. dartdoc `job` и `run`: срок приходит в `onCancel` с `TimeoutCancelReason`,
    `onError` его не видит; пример развилки из спеки. dartdoc `collect`
    и `accumulate`: срок у каждой задачи, отсчёт после окна. dartdoc
    `Policy.droppable`: дубликат возвращает живую задачу, срок нового вызова
    пропадает.
12. `test/support/test_solo.dart`: параметр в четырёх переопределениях.
13. `test/timeout_test.dart`: пункты `solo` раздела «Тесты» спеки.
14. `CHANGELOG.md`, «Unreleased»: в «Breaking changes» — переопределения
    четырёх членов с миграцией; в добавлениях — параметр.

### `packages/flutter_solo`

15. Тест: задача со сроком, уложившаяся в него, не оставляет таймера
    в `testWidgets`. Задача, которая не кончилась, — проверка, что тест
    краснеет, не нужна: это поведение `flutter_test`, а не наше.
16. `CHANGELOG.md`: «Breaking changes» о переопределениях `solo`, как у пакета,
    который реэкспортирует.

### Общее

17. `docs/architecture.md`: граница в «Границы» — ядро знает срок задачи
    и не знает таймаутов отдельных шагов, debounce и композиции;
    `TimeoutCancelReason` в списке причин `outcome.dart`.

Проверки волны: в каждом пакете
`dart format --output=none --set-exit-if-changed .`,
`dart analyze --fatal-infos`, `dart test` (`flutter test` в `flutter_solo`),
примеры отдельно; из корня `tool/reflow.py --check`, `check_line_width.py`,
`check_links.py`, `check_translations.py`, `check_doc_shape.py`. README про
таймаут волна не трогает: рецепт с `Timer` остаётся верным и после неё.

Мутации: по одной на правило — постановка до `started()`, снятие в `_execute`,
снятие придержанного запроса, снятие в `finish`, `try`/`catch` колбэка, трасса
конструктора, обе проверки аргументов, проверка аккумулятора при создании.
Каждая должна уронить хотя бы один тест; откат — копией файла.

## Волна 2: страницы, переводы, сторожа

По разделу «Документы» спеки, в его порядке. Хозяин материала — новый раздел
`packages/async_job/doc/cancellation.md`: первая попытка
`Timer(limit, job.cancel)` с двумя оговорками, затем `timeout:`, затем ребёнок
со сроком. Остальные страницы говорят своё и ссылаются на него.

- Каждая правка оригинала — с переводом в том же коммите; новые русские
  абзацы — через `uvx ru-humanizer --genre academic`, тире в них нет.
- Сторожа страниц: новый код страницы стоит в `test/support/*_page.dart` или
  `*_first_attempts.dart` своей страницы и запускается её сторожем; утверждения
  прозы держит `_says`, как у соседей. README `async_job` теряет тесты рецепта
  и цитаты `job.done.whenComplete(timer.cancel)` в `readme_recipe_test.dart`
  и получает тест параметра.
- Раздел «Timeouts» `packages/solo/doc/testing.md` переписывается по спеке
  вместе со вступлением страницы и сторожами раздела:
  `testing_rakes_test.dart`, `support/testing_first_attempt_timeout.dart`,
  `support/testing_page.dart`.
- Трассы, которые страница цитирует, сверяет `tool/check_traces.py`; если
  раздел попадает в стенд `snippets`, стенд гоняется.
- Поиск по `timeout`, `Timer(` и `таймаут` во всех трёх пакетах и в `docs/ru/`
  перед концом волны: всё, что говорит «таймаута нет», найдено и поправлено или
  названо в отчёте.

Проверки волны — те же, что у первой, плюс `tool/doc_snippets.py`,
`tool/accumulation_snippets.py` и `tool/flutter_snippets.py`, если тронуты их
страницы, и сборка сайта: `python3 tool/build_site.py`, затем в `site/`
`npm run build`.

## После волн

- Ревью сделанной работы на Opus по копии дерева на коммите второй волны: код
  против спеки, страницы против кода.
- Отчёт `2026-10-06-job-timeout-report.md`: что сделано, где разошлось
  со спекой и почему, мутации, проверки. Шапки спеки и плана — «сделано
  и перенесено» с коммитами.
- `docs/handoff.md`: абзац «Срок задачи» сжимается до итога.
- Владельцу — сводка. Публикации, тега и выпуска работа не касается.
