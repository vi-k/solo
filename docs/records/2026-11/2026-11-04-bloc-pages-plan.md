# Страницы «async_job in a bloc app» и «solo under bloc»: план

> **Состояние на 2026-11-04:** план написан по одобренному дизайну, ждёт
> независимого ревью Opus; исполнения не было.
> **Что это:** план двух страниц — `packages/async_job/doc/bloc.md`
> и `packages/solo/doc/bloc.md`, их общего стенда `tool/bloc_snippets.py`
> в задании `snippets`, переводов, входов, сайта и правок записей.
> **Связанные записи:** `2026-11-03-bloc-pages-design.md`,
> `2026-11-02-riverpod-page-plan.md`, `2026-10-30-riverpod-and-bloc-design.md`.

> **Исполнителю:** скилл `superpowers:subagent-driven-development` или
> `superpowers:executing-plans`; шаги — флажки `- [ ]`. Перед текстом
> страницы — скиллы `doc-reader` и `doc-bench`, перед кодом Dart — `dart`.

**Цель:** разработчик с приложением на bloc видит на странице ядра, что задача
`async_job` в обработчике снимает с его кода, а на странице `solo` — что
снимает контроллер `solo` под тем же bloc; bloc остаётся на обеих, и каждый
фрагмент собран и прогнан в CI.

**Устройство:** обе страницы одной формы: вступление, раздел о мосте, разделы
по сценариям `vs-bloc.md` в его порядке, итоговая таблица. Один стенд
`tool/bloc_snippets.py` по образцу `tool/riverpod_snippets.py` копирует блоки
обеих страниц байт в байт в пакет `bloc_pages_check`; драйверы на виртуальном
времени гоняют ответ bloc и ответ страницы на одном сценарии и держат прозу
сторожами `require`.

**Стек:** Dart 3.10+, `bloc: ^9.0.0`, `bloc_concurrency: ^0.3.0`, `solo` путём
из дерева и `async_job` путём в `dependency_overrides`, `fake_async`; Python 3
для стенда и проверок; Starlight для сайта.

**Дизайн:** `docs/records/2026-11/2026-11-03-bloc-pages-design.md` — читать
вместе с планом; доводы, критерий отбора и зонды — там.

## Общие ограничения

- Страницы по-английски; переводы `docs/ru/async_job/bloc.md`
  и `docs/ru/solo/bloc.md` — тем же коммитом, что любая правка оригинала после
  задачи перевода.
- Заголовки: «async_job in a bloc app» и «solo under bloc».
- Первая попытка раздела — ответ bloc из `vs-bloc.md` (или его первая попытка)
  с теми же классами: `ChatBloc`, `LockedFirmwareBloc`, `GuardedPreviewBloc`
  и прочие; на странице `solo` контроллеры — из разделов Solo `vs-bloc.md`:
  `ChatController`, `FirmwareController` и прочие, код как там.
- Призыва уйти с bloc нет: путь без bloc — ссылка в конце раздела страницы
  `solo` на раздел Solo того же сценария `vs-bloc.md`.
- Нового API нет: `watch` и мост состояний — код страниц.
- Фрагменты страницы ядра собираются в файлы без `package:solo` — генератор
  проверяет это сам.
- Ширина 79, жадный перенос: `python3 tool/reflow.py` по названным файлам.
- Слово «джоба» в русском тексте запрещено: «задача» или `Job`.
- Git — `/usr/bin/git`; коммиты Conventional Commits по-английски,
  с `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Коммиты страницы
  ядра идут раньше коммитов страницы `solo`, и ни один коммит не трогает обе.
- Между задачами 2 и 4 (и 5 и 7) у страницы нет перевода: русская локаль сайта
  показывает английскую, `check_translations.py` страницу ещё не знает. Строка
  в `items` сайта идёт тем же коммитом, что страница: иначе краснеет
  `test_every_page_is_listed_and_every_entry_is_a_page`.

## Куда смотреть ревьюеру

1. Числа в прозе (длительность `close()`, задержки фейков) `check_traces.py`
   не сверяет: в задачах 4 и 7 их сверяют с фейками стенда по списку.
2. Серия из трёх загрузок в разделе о записи: зазоры `[0, 30, 5]`
   и `[0, 30, 0]`. На двух загрузках гонка дизайна C1 не видна — драйвер обязан
   гнать три и требовать `maxInFlight == 1` и ни одного куска средней загрузки.
3. `emit` обработчика из тела задачи законен, пока обработчик ждёт `forEach`.
   Задача, пережившая эмиттер, роняет утверждение bloc: драйверы требуют пустую
   зону.
4. Новый минор bloc может изменить `close()` под `sequential()` (прогон
   очереди) — это довод раздела о мосте; сторож его держит и краснеет,
   а не печатает другое.
5. Страница, которой нет в `items` своей темы, и тема не та: проверка — сборка
   сайта и `TheSidebarTopics` в `tool/build_site_test.py`.

---

### Задача 1. Зонды по критерию отбора

**Файлы:** создать `docs/records/2026-11/2026-11-04-bloc-pages-report.md`.
Зонды — вне репозитория, в пакете с зависимостями стенда (см. «Стек»).

**Даёт:** состав разделов каждой страницы и задержки фейков — в отчёте,
с выводом зондов.

- [ ] **Шаг 1. Перепроверить известное.** Сценарии 3, 10 и 11 на текущих bloc
  и `bloc_concurrency`: трассы раздела «Сценарии» дизайна сходятся (закрытие:
  задача без `isClosed` отправляет `[hi, bye]`, контроллер — `[hi]` и `close()`
  не ждёт вызов; запись: `maxInFlight` 2 у дизайна, 1 у цепочки и контроллера
  на `[0, 30, 5]` и `[0, 30, 0]`; ресурс: каждый буфер освобождён ровно раз
  у `try`/`finally` и у `dispose`). Расходится — остановиться и сказать
  владельцу.
- [ ] **Шаг 2. Страница `solo`, сценарии 1, 4, 5, 7, 9.** Для каждого —
  контроллер раздела Solo `vs-bloc.md` под bloc против ответа Bloc того же
  раздела, на сценарии его драйвера в `tool/doc_snippets.py` и на более жёстком
  (серия из трёх, закрытие с событием в очереди). Вердикт по критерию: «трасса
  лучше», «меньше правил» с перечнем снятых правил, или «таблица».
- [ ] **Шаг 3. Страница ядра, сценарий 9.** Отзыв сессии отменяет задачу
  из поля: тот же вердикт.
- [ ] **Шаг 4. Мост состояний для страницы `solo`.** Обработчик служебного
  события, зарегистрированный в конструкторе и запущенный `add` там же,
  с `emit.forEach(controller.stream, onData: …)`. Требуется: состояние bloc
  повторяет каждое состояние контроллера, `close()` bloc закрывает контроллер,
  зона пуста. Не держит — другой кандидат, без `Bloc.emit` из слушателя.
- [ ] **Шаг 5. Отчёт.** Шапка, раздел «Зонды»: код каждого зонда (кратко,
  только то, что решает) и вывод; итоговые списки разделов обеих страниц.
  У страницы ядра меньше трёх разделов — остановиться и спросить владельца.
- [ ] **Шаг 6.** Reflow отчёта, ширина, коммит
  `docs: probe the bloc page scenarios against the selection rule`.

### Задача 2. Стенд, мост и закрытие на странице ядра

**Файлы:**
- Создать: `tool/bloc_snippets.py`, `packages/async_job/doc/bloc.md`.
- Изменить: `.github/workflows/gate.yml` (задание `snippets`), `AGENTS.md`
  («Проверки»: пять стендов, пятый скрипт и два документа, «в шесть пакетов»).
- Изменить: `site/astro.config.mjs` — `page('async_job/bloc',
  'async_job in a bloc app', 'async_job в приложении на bloc')` после
  `async_job/riverpod-and-bloc`.

**Интерфейсы:**
- Даёт: пакет `bloc_pages_check` под `<workdir>`, драйверы
  `bloc_pages_check/bin/v/<name>.dart`; `CORE = .../async_job/doc/bloc.md`,
  `SOLO = .../solo/doc/bloc.md`, по своему `Blocks` на страницу, `unbuilt()`
  обеих в конце; `CORE_HEAD` без `package:solo` и проверка генератора: файл
  драйвера ядра, в котором есть `package:solo`, — ошибка. Фейки: `Api`
  (`Future<String> send(String text)`, задержка из отчёта задачи 1, журнал
  `sent`), `delay(int ms)`, `require(bool, String)`, `RUNNER` — копия
  из `tool/adapter_snippets.py`.
- Ключи разделов ядра: `BRIDGE = 'the-bridge'`,
  `CLOSING = 'closing-and-cancelling-in-flight-work'` — как даёт
  `doc_blocks.slug`, проверить `--list`.

Форма раздела на обеих страницах: абзац требования, `### With bloc alone`,
`### With a job in the handler` (ядро) или
`### With a controller under the bloc` (`solo`), последний абзац раздела
начинается с «What stays with bloc:».

- [ ] **Шаг 1. Драйверы со сторожами раньше текста.**
  - `core_bridge_sequential`: обработчик под `sequential()`, два события,
    `close()` во время первого; `require`: оба обработчика дошли до конца,
    задачи не отменены — `close()` прогнал очередь.
  - `core_closing_bloc`: `ChatBloc` из `vs-bloc.md`, «hi» в полёте, «bye»
    в очереди, `close()` через 10 мс; `require`: `sent == [hi, bye]`, `close()`
    ждал вызов. Печатает строку вида зонда дизайна.
  - `core_closing_job`: ответ страницы — текущая задача в поле, `close()`
    отменяет её до `super.close()`, обработчик ждёт `job.done`, `isClosed`
    после; `require`: `close()` короче вызова, `sent == [hi, bye]` — очередь
    остаётся на bloc, ни одного состояния после `close()`, зона пуста. Печатает
    ту же форму строки.
- [ ] **Шаг 2.** `python3 tool/bloc_snippets.py <tmp>` падает: блоков нет.
- [ ] **Шаг 3. Текст.** Заголовок, вступление одним абзацем (для кого, что bloc
  остаётся, обещание «states and traces under the code are what that code
  prints»; список ловушек — заглушкой до задачи 3). `## The bridge`: `watch`
  одним блоком из `riverpod-and-bloc.md` байт в байт, ссылка туда за разбором,
  два факта — отмена подписки `forEach` отменяет задачу, `close()` под
  `sequential()` прогоняет очередь, отсюда задача в поле и `job.done`,
  не `job.value`. Раздел о закрытии по форме выше; довод — «трасса лучше»:
  `close()` не ждёт вызов; честно — `isClosed` и очередь остаются на bloc.
- [ ] **Шаг 4.** Генерация, `dart pub get`, `dart analyze --fatal-infos bin/v`,
  прогон драйверов;
  `python3 tool/check_traces.py packages/async_job/doc/bloc.md <вывод>`.
- [ ] **Шаг 5. CI.** В `gate.yml`, задание `snippets`: ключ кеша
  (`tool/bloc_snippets.py`), строка генератора, `bloc_pages_check` в трёх
  циклах, свой вывод `bloc-pages.out` (ветка `elif`), в `check_traces` — пары
  обеих страниц с `bloc-pages.out`. Комментарий о правилах анализа: пакет берёт
  правила `async_job`.
- [ ] **Шаг 6.** Reflow, ширина, коммит
  `docs: start the bloc page of async_job with the bridge and closing`.

### Задача 3. Остальные разделы страницы ядра и итоговая таблица

**Файлы:** `packages/async_job/doc/bloc.md`, `tool/bloc_snippets.py`.

**Интерфейсы:** берёт `watch`, `Api`, `RUNNER` задачи 2. Даёт фейки `Ble`
(запись куска — задержка из отчёта, журнал `+`/`-` по кускам, `maxInFlight`)
и `Decoder` (`Future<Buffer> open(String clip)`, `Buffer.release()`, счётчик
освобождений по буферу); ключи разделов — по `--list`.

- [ ] **Шаг 1. Драйверы.**
  - Запись перед перезапуском: `core_firmware_bloc` (`LockedFirmwareBloc`)
    и `core_firmware_chain` (цепочка: прежняя задача берётся и поле
    присваивается до первого `await`, тело ждёт прежнюю под `ctx.join`,
    прогресс — `emit` обработчика). Оба на `[0, 30, 5]` и `[0, 30, 0]`;
    `require(maxInFlight == 1)`, ни одного куска средней загрузки, зона пуста.
  - Ресурс после отмены: `core_preview_bloc` (`GuardedPreviewBloc`)
    и `core_preview_job` (`ctx.abandonable(() => _decoder.open(clip),
    dispose: (buffer) => buffer.release())` под `watch`); серия открытий
    и `close()`; `require`: каждый буфер освобождён ровно раз, текущий тоже.
  - Сценарий 9 — если задача 1 оставила его на странице: пара драйверов
    по вердикту отчёта.
- [ ] **Шаг 2.** Генерация падает на отсутствующих блоках.
- [ ] **Шаг 3. Текст.** Разделы в порядке `vs-bloc.md`, по форме задачи 2;
  каждый называет свой довод. Запись: прогресс через `emit` обработчика
  и почему это законно. Ресурс: почему `dispose`, а не `discard`.
  `## Where the queue is the problem` — таблица сценариев без раздела: что
  остаётся на bloc, ссылка на раздел Bloc `vs-bloc.md`; где нужна очередь —
  ссылка на страницу `solo` (`doc/bloc.md` `solo` на GitHub, как прочие ссылки
  ядра на `solo`). Вступление: список ловушек со ссылками на разделы.
- [ ] **Шаг 4.** Прогон всего стенда, `unbuilt()` пуст, `check_traces`.
- [ ] **Шаг 5.** Reflow, ширина, коммит
  `docs: finish the bloc page of async_job with the write,
  the resource and the table`.

### Задача 4. Перевод и входы страницы ядра

**Файлы:**
- Создать: `docs/ru/async_job/bloc.md`.
- Изменить: `tool/check_translations.py` (пара в `PAIRS` рядом
  с `riverpod-and-bloc.md`: список явный, без пары страница не сверяется),
  `packages/async_job/README.md` и `README.ru.md` (строка «Guides» после «With
  riverpod and bloc»), `packages/async_job/doc/riverpod-and-bloc.md` и перевод
  (конец раздела «A handler that restarts»: ссылка на новую страницу),
  `packages/async_job/CHANGELOG.md` и `docs/ru/async_job/CHANGELOG.md`
  («Unreleased» / «Не выпущено»).

- [ ] **Шаг 1.** Пара в `PAIRS`; `python3 tool/check_translations.py` краснеет:
  перевода нет.
- [ ] **Шаг 2.** Перевод страницы, строк README и CHANGELOG, фразы
  `riverpod-and-bloc.md`; фрагменты кода — те же байты, кроме комментариев.
  Изменённые абзацы — линтер `humanizer--ru`, ноль `ERROR`.
- [ ] **Шаг 3.** `python3 tool/check_doc_shape.py` зелёный (README ядра).
- [ ] **Шаг 4.** Сайт: `python3 tool/build_site.py`,
  `python3 -m unittest tool/build_site_test.py`; `async_job/bloc` на обоих
  языках в теме `async_job`.
- [ ] **Шаг 5.** Числа прозы против фейков стенда — список в отчёт.
- [ ] **Шаг 6.** `check_translations.py`, reflow, ширина, `check_links.py`;
  коммит
  `docs: translate the bloc page of async_job and link it from the README,
  the changelog and the riverpod page`.

### Задача 5. Мосты и закрытие на странице `solo`

**Файлы:** создать `packages/solo/doc/bloc.md`; изменить
`tool/bloc_snippets.py`, `site/astro.config.mjs`
(`page('solo/bloc', 'solo under bloc', 'solo под bloc')` после `solo/riverpod`
и запись в `optionalLinks`).

**Интерфейсы:** берёт `watch`, `Api`, `RUNNER`; мост состояний — по отчёту
задачи 1. Ключи — `SOLO_BRIDGES = 'the-bridges'` и ключ раздела закрытия, оба
по `--list`.

- [ ] **Шаг 1. Драйверы.**
  - `solo_bridge_states`: мост задачи 1; `require` — то же, что в шаге 4 задачи
    1.
  - `solo_closing_bloc`: тот же `ChatBloc`, что у ядра (блок страницы `solo`,
    не ядра).
  - `solo_closing_controller`: `ChatController` раздела Solo `vs-bloc.md` под
    bloc, `close()` bloc закрывает контроллер; `require`: `sent == [hi]`,
    `close()` не ждал вызов, ни одного состояния после `close()`, зона пуста.
- [ ] **Шаг 2.** Генерация падает.
- [ ] **Шаг 3. Текст.** Заголовок, вступление, `## The bridges`: `watch`
  и ссылка на `riverpod-and-bloc.md` ядра, мост состояний, почему
  не `Bloc.emit` из слушателя (`invalid_use_of_visible_for_testing_member`),
  методы `solo` возвращают `Job` и обработчик ждёт их так же. Раздел
  о закрытии; довод — «трасса лучше»; в конце — «What stays with bloc:»
  и ссылка на раздел Solo «Closing and cancelling in-flight work» `vs-bloc.md`.
- [ ] **Шаг 4.** Генерация, анализ, прогон, `check_traces` по обеим страницам.
- [ ] **Шаг 5.** Reflow, ширина, коммит
  `docs: start solo under bloc with the bridges and closing`.

### Задача 6. Остальные разделы страницы `solo` и итоговая таблица

**Файлы:** `packages/solo/doc/bloc.md`, `tool/bloc_snippets.py`.

- [ ] **Шаг 1. Драйверы.** Запись: `solo_firmware_bloc` (`LockedFirmwareBloc`)
  и `solo_firmware_controller` (`FirmwareController` под bloc) — те же
  требования, что у ядра в задаче 3. Сценарии, оставленные задачей 1 (из 1, 4,
  5, 7, 9), — пара драйверов на каждый по вердикту отчёта.
- [ ] **Шаг 2.** Генерация падает.
- [ ] **Шаг 3. Текст.** Разделы в порядке `vs-bloc.md`, каждый со своим доводом
  и ссылкой на раздел Solo своего сценария. Итоговая таблица: сценарии без
  раздела, ссылки на разделы Bloc и Solo `vs-bloc.md`; у ресурса после отмены —
  ссылка на раздел страницы ядра (GitHub). Вступление: список ловушек
  со ссылками.
- [ ] **Шаг 4.** Прогон, `unbuilt()` пуст, `check_traces`.
- [ ] **Шаг 5.** Reflow, ширина, коммит
  `docs: finish solo under bloc with the write and the table`.

### Задача 7. Перевод и входы страницы `solo`

**Файлы:** создать `docs/ru/solo/bloc.md`; изменить
`tool/check_translations.py` (как в задаче 4), `packages/solo/README.md`
и `README.ru.md` (строка таблицы «Guides» после «solo under riverpod»
и перезалитый абзац над таблицей — раздел «Coming from bloc» не трогать),
`packages/solo/doc/vs-bloc.md` и перевод (фраза во вступлении о странице «solo
under bloc»), `packages/solo/CHANGELOG.md` и `docs/ru/solo/CHANGELOG.md`.

- [ ] **Шаги 1–6** — как в задаче 4, для страницы `solo`; плюс
  `tool/doc_snippets.py` (стенд `vs-bloc`) после правки вступления: генерация
  и `check_traces` по `vs-bloc.md` зелёные, `QUOTED` и `SAID` не задеты. Коммит
  `docs: translate solo under bloc and link it from the README,
  the changelog and vs-bloc`.

### Задача 8. Записи и полная проверка

**Файлы:** `docs/settled.md` (решение 133), шапка и раздел «Что вышло»
`2026-11-03-bloc-pages-design.md`, шапки этого плана и отчёта,
`docs/handoff.md`.

- [ ] **Шаг 1.** Решение 133 — дописать по разделу «Что ещё меняется» дизайна,
  со ссылкой на дизайн и слова владельца 2026-11-03.
- [ ] **Шаг 2.** Проверки задания `docs` целиком: `reflow.py --check`,
  `check_line_width.py`, `check_doc_shape.py`, `check_dartdoc.py`,
  `check_page_code.py`, `check_translations.py`, `check_links.py`,
  `python3 -m unittest tool/archive_floor_test.py tool/build_site_test.py`,
  `build_site.py`; все пять стендов `snippets` с прогоном драйверов
  и `check_traces.py` по семи документам, как в `gate.yml`.
- [ ] **Шаг 3.** Коммит
  `docs: record the bloc pages in the decisions and the handoff`.
- [ ] **Шаг 4.** Независимое ревью готовой работы — агент на Opus в своей копии
  дерева; находки и вердикты — разделом «Ревью работы» отчёта; принятые закрыть
  до вливания.
- [ ] **Шаг 5.** Влить в `main` (`ExitWorktree keep`, `git merge --ff-only`).
  Push — только по слову владельца.
