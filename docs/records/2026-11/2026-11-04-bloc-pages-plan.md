# Страницы «async_job in a bloc app» и «solo under bloc»: план

> **Состояние на 2026-11-04:** план написан по одобренному дизайну и прошёл
> независимое ревью Opus: все находки приняты, задачи поправлены по ним
> (раздел «Ревью плана»). Задачи 1 и 2 исполнены — отчёт
> `2026-11-04-bloc-pages-report.md`; задачи 3–8 впереди.
> **Что это:** план двух страниц — `packages/async_job/doc/bloc.md`
> и `packages/solo/doc/bloc.md`, их общего стенда `tool/bloc_snippets.py`
> в задании `snippets`, переводов, входов, сайта и правок записей.
> **Связанные записи:** `2026-11-03-bloc-pages-design.md`,
> `2026-11-04-bloc-pages-report.md`, `2026-11-02-riverpod-page-plan.md`,
> `2026-10-30-riverpod-and-bloc-design.md`.

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
из дерева, `async_job` путём и в `dependencies`, и в `dependency_overrides`
(без первого анализ краснеет `depend_on_referenced_packages`, без второго путь
конфликтует с ограничением `solo`), `fake_async`, в dev — `lints: ^5.1.1`;
Python 3 для стенда и проверок; Starlight для сайта.

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
- Страница ядра ссылается на документы `solo` только там, где ответ требует
  очереди (решение 144); `check_links.py` пропускает это узким исключением
  из шага 1 задачи 3.
- Ссылка на сценарий `vs-bloc.md` ведёт на заголовок его раздела
  (`vs-bloc.md#closing-and-cancelling-in-flight-work`), а не на повторяющиеся
  `### Bloc` и `### Solo` с номером: новый раздел сдвинул бы номера молча.
- Контроллер под bloc закрывается первым: `close()` bloc делает
  `await controller.close()` и только потом `super.close()`. Мост состояний —
  под трансформером по умолчанию: под `sequential()` `close()` не завершается.
- Драйверы `bloc_pages_check` гоняются с `dart run --enable-asserts`: без него
  утверждения bloc о позднем `emit` молчат. Сторож позднего `emit` — состояния
  и исходы, не пустая зона.
- `docs/handoff.md` обновляется в коммите каждой законченной задачи.
- Ширина 79, жадный перенос: `python3 tool/reflow.py` по названным файлам.
- Слово «джоба» в русском тексте запрещено: «задача» или `Job`.
- Git — `/usr/bin/git`; коммиты Conventional Commits по-английски,
  с `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Коммиты страницы
  ядра идут раньше коммитов страницы `solo`, кроме ссылки ядра на страницу
  `solo` в задаче 7, и ни один коммит не трогает обе.
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
   Задачу, пережившую эмиттер, пустая зона не ловит: поздний `emit` отменённого
   эмиттера отбрасывается молча, а `AssertionError` под asserts становится
   исходом `Failed` задачи. Драйверы требуют: после первого состояния новой
   загрузки ни одного состояния заменённой, исход каждой задачи `Done` или
   `Cancelled`.
4. Новый минор bloc может изменить `close()` под `sequential()` (прогон
   очереди) — это довод раздела о мосте; сторож его держит и краснеет,
   а не печатает другое.
5. Страница, которой нет в `items`, ловится `TheSidebarTopics`
   в `tool/build_site_test.py`; тему страницы тест не проверяет, её сверяют
   глазом по `site/astro.config.mjs`.
6. `job.done` не бросает: ошибка вызова, прочитанная через `done`, не доходит
   ни до `onError` bloc, ни до зоны. Ответ страницы разбирает `Failed`
   из исхода, драйвер с падающим вызовом это держит.
7. Порядок закрытия контроллера под bloc: `super.close()` первым прогоняет
   очередь через контроллер и возвращает обе ошибки сценария. Сторож обратного
   порядка — в задаче 5.

---

### Задача 1. Зонды по критерию отбора

**Файлы:** создать `docs/records/2026-11/2026-11-04-bloc-pages-report.md`.
Зонды — вне репозитория, в пакете с зависимостями стенда (см. «Стек»).

**Даёт:** состав разделов каждой страницы и задержки фейков — в отчёте,
с выводом зондов.

- [x] **Шаг 1. Перепроверить известное.** Сценарии 3, 10 и 11 на текущих bloc
  и `bloc_concurrency`: трассы раздела «Сценарии» дизайна сходятся (закрытие:
  задача без `isClosed` отправляет `[hi, bye]`, контроллер — `[hi]` и `close()`
  не ждёт вызов; запись: `maxInFlight` 2 у дизайна, 1 у цепочки и контроллера
  на `[0, 30, 5]` и `[0, 30, 0]`; ресурс: каждый буфер освобождён ровно раз
  у `try`/`finally` и у `dispose`). Расходится — остановиться и сказать
  владельцу.
- [x] **Шаг 2. Страница `solo`, сценарии 1, 4, 5, 7, 9.** Для каждого —
  контроллер раздела Solo `vs-bloc.md` под bloc против ответа Bloc того же
  раздела, на сценарии его драйвера в `tool/doc_snippets.py` и на более жёстком
  (серия из трёх, закрытие с событием в очереди). Вердикт по критерию: «трасса
  лучше», «меньше правил» с перечнем снятых правил, или «таблица».
- [x] **Шаг 3. Страница ядра, сценарий 9.** Отзыв сессии отменяет задачу
  из поля: тот же вердикт.
- [x] **Шаг 4. Мост состояний для страницы `solo`.** Обработчик служебного
  события, зарегистрированный в конструкторе и запущенный `add` там же,
  с `emit.forEach(controller.stream, onData: …)`, под трансформером
  по умолчанию. Требуется: состояние bloc повторяет каждое состояние
  контроллера, не равное предыдущему (равное bloc отбрасывает), `close()` bloc
  закрывает контроллер до `super.close()`, зона пуста. Не держит — другой
  кандидат, без `Bloc.emit` из слушателя.
- [x] **Шаг 5. Отчёт.** Шапка, раздел «Зонды»: код каждого зонда (кратко,
  только то, что решает) и вывод; итоговые списки разделов обеих страниц.
  У страницы ядра меньше трёх разделов — остановиться и спросить владельца.
- [x] **Шаг 6.** Reflow отчёта, ширина, коммит
  `docs: probe the bloc page scenarios against the selection rule`.

### Задача 2. Стенд, мост и закрытие на странице ядра

**Файлы:**
- Создать: `tool/bloc_snippets.py`, `packages/async_job/doc/bloc.md`.
- Изменить: `.github/workflows/gate.yml` (задание `snippets`), `AGENTS.md`
  («Проверки»: пять стендов, пятый скрипт и документ ядра, «в шесть пакетов»;
  абзац об адресации блоков — «у всех пяти стендов»; второй документ называет
  задача 5).
- Изменить: `site/astro.config.mjs` — `page('async_job/bloc',
  'async_job in a bloc app', 'async_job в приложении на bloc')` после
  `async_job/riverpod-and-bloc`.

**Интерфейсы:**
- Даёт: пакет `bloc_pages_check` под `<workdir>`, драйверы
  `bloc_pages_check/bin/v/<name>.dart`; `CORE = .../async_job/doc/bloc.md`, его
  `Blocks` и `unbuilt()` в конце (`SOLO` и его `Blocks` добавляет задача 5);
  `CORE_HEAD` без `package:solo` и проверка генератора: файл драйвера ядра,
  в котором есть `package:solo`, — ошибка; вторая проверка — блок `watch`
  страницы входит подстрокой в блок
  `a-handler-that-restarts/a-stream-that-cancels-the-j/watch`
  `riverpod-and-bloc.md`. Фейки: `Api` (`Future<String> send(String text)`,
  задержка из отчёта задачи 1, журнал `sent`), `delay(int ms)`,
  `require(bool, String)`, `RUNNER` — копия из `tool/doc_snippets.py`
  с `nowMs()` поверх виртуальных часов. `--list` печатает ключи с подразделом
  и пометкой страницы.
- Ключи разделов ядра: `BRIDGE = 'the-bridge'`,
  `CLOSING = 'closing-and-cancelling-in-flig'` (`doc_blocks.slug` режет до 30
  символов), подраздел ответа — `with-a-job-in-the-handler`; сверить
  по `--list`.

Форма раздела на обеих страницах: абзац требования, `### With bloc alone`,
`### With a job in the handler` (ядро) или
`### With a controller under the bloc` (`solo`), последний абзац раздела
начинается с «What stays with bloc:».

- [x] **Шаг 1. Драйверы со сторожами раньше текста.**
  - `core_bridge_sequential`: обработчик под `sequential()`, два события,
    `close()` во время первого; `require`: оба обработчика дошли до конца,
    задачи не отменены — `close()` прогнал очередь.
  - `core_closing_bloc`: `ChatBloc` из `vs-bloc.md`, «hi» в полёте, «bye»
    в очереди, `close()` через 10 мс; `require`: `sent == [hi, bye]`, `close()`
    ждал вызов. Печатает строку вида зонда дизайна.
  - `core_closing_job`: ответ страницы — текущая задача в поле, `close()`
    отменяет её до `super.close()`, обработчик ждёт `job.done` и разбирает
    исход, `isClosed` после; `require`: `close()` задачи короче `close()` bloc
    на остаток вызова «hi» в полёте (длительности — `nowMs()`),
    `sent == [hi, bye]` — очередь остаётся на bloc, ни одного состояния после
    `close()`, зона пуста. Печатает ту же форму строки.
  - `core_closing_job_failed`: тот же ответ, вызов падает; `require`: ошибка
    дошла туда же, куда её отправляет `ChatBloc`.

  Блок трассы, собранный из вывода двух драйверов, сходится, только если они
  соседи по алфавиту и печатают ровно свои строки.
- [x] **Шаг 2.** `python3 tool/bloc_snippets.py <tmp>` падает: блоков нет.
- [x] **Шаг 3. Текст.** Заголовок, вступление одним абзацем (для кого, что bloc
  остаётся, обещание «states and traces under the code are what that code
  prints»; список ловушек — заглушкой до задачи 3). `## The bridge`: `watch`
  одним блоком из `riverpod-and-bloc.md` байт в байт, ссылка туда за разбором,
  два факта — отмена подписки `forEach` отменяет задачу, `close()` под
  `sequential()` прогоняет очередь, отсюда задача в поле и `job.done`,
  не `job.value`; `done` не бросает, поэтому ответ разбирает `Failed`
  из исхода. Раздел о закрытии по форме выше; довод — «трасса лучше»: `close()`
  не ждёт вызов в полёте, но ждёт вызов каждого сообщения из очереди; числа —
  из вывода стенда; честно — `isClosed` и очередь остаются на bloc.
- [x] **Шаг 4.** Генерация, `dart pub get`, `dart analyze --fatal-infos bin/v`,
  прогон драйверов с `dart run --enable-asserts`;
  `python3 tool/check_traces.py packages/async_job/doc/bloc.md <вывод>`;
  `python3 tool/check_doc_shape.py`.
- [x] **Шаг 5. CI.** В `gate.yml`, задание `snippets`: ключ кеша
  (`tool/bloc_snippets.py`), строка генератора, `bloc_pages_check` в трёх
  циклах, драйверы `core_*` — `dart run --enable-asserts` в свой вывод
  `bloc-pages-core.out` (ветка `elif`),
  `: > "$RUNNER_TEMP/bloc-pages-core.out"` рядом с остальными,
  в `check_traces` — пара страницы ядра с `bloc-pages-core.out`, комментарий
  «the benches write five packages» — six. Комментарий о правилах анализа:
  пакет берёт правила `async_job`.
- [x] **Шаг 6.** Reflow, ширина, handoff, коммит
  `docs: start the bloc page of async_job with the bridge and closing`.

### Задача 3. Остальные разделы страницы ядра и итоговая таблица

**Файлы:** `packages/async_job/doc/bloc.md`, `tool/bloc_snippets.py`,
`tool/check_links.py`, `tool/check_links_test.py`.

**Интерфейсы:** берёт `watch`, `Api`, `RUNNER` задачи 2. Даёт фейки `Ble`
(запись куска — задержка из отчёта, журнал `+`/`-` по кускам, `maxInFlight`)
и `Decoder` (`Future<Buffer> open(String clip)`, `Buffer.release()`, счётчик
освобождений по буферу); ключи разделов — по `--list`.

- [ ] **Шаг 1. Исключение в `check_links.py`.** Случай
  в `tool/check_links_test.py`: страница `async_job/doc/bloc.md` и её перевод
  со ссылкой на документ `solo` не отчитываются, другая страница ядра с той же
  ссылкой — отчитывается; прогон краснеет. Затем перечень пар «страница ядра →
  пакет выше» в скрипте, строка в docstring с причиной по решению 144; тест
  и `python3 tool/check_links.py` зелёные.
- [ ] **Шаг 2. Драйверы.**
  - Запись перед перезапуском: `core_firmware_bloc` (`LockedFirmwareBloc`)
    и `core_firmware_chain` (цепочка: прежняя задача берётся и поле
    присваивается до первого `await`, тело ждёт прежнюю под `ctx.join`,
    прогресс — `emit` обработчика). Оба на `[0, 30, 5]` и `[0, 30, 0]`;
    `require(maxInFlight == 1)`, ни одного куска средней загрузки; после
    первого состояния новой загрузки ни одного состояния заменённой, исход
    каждой задачи `Done` или `Cancelled`. Перед печатью драйвер ждёт `done`
    последней задачи и требует `inFlight == 0`.
  - Ресурс после отмены: `core_preview_bloc` (`GuardedPreviewBloc`)
    и `core_preview_job` (`ctx.abandonable(() => _decoder.open(clip),
    dispose: (buffer) => buffer.release())` под `watch`); серия открытий
    и `close()`; драйвер ждёт `done` последней задачи; `require`: каждый буфер
    освобождён ровно раз, текущий тоже.
  - Сценарий 9 — если задача 1 оставила его на странице: пара драйверов
    по вердикту отчёта.
- [ ] **Шаг 3.** Генерация падает на отсутствующих блоках.
- [ ] **Шаг 4. Текст.** Разделы в порядке `vs-bloc.md`, по форме задачи 2;
  каждый называет свой довод. Запись: довод — «меньше правил» (трасса цепочки
  та же, что у `LockedFirmwareBloc`), прогресс через `emit` обработчика
  и почему это законно. Ресурс: почему `dispose`, а не `discard`.
  `## Where the queue is the problem` — таблица сценариев без раздела: что
  остаётся на bloc, ссылка на раздел сценария `vs-bloc.md` по его заголовку.
  Ссылку на страницу `solo` ставит задача 7. Вступление: список ловушек
  со ссылками на разделы.
- [ ] **Шаг 5.** Прогон всего стенда, `unbuilt()` пуст, `check_traces`,
  `check_doc_shape.py`, `check_links.py`.
- [ ] **Шаг 6.** Reflow, ширина, handoff, коммит
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
- [ ] **Шаг 4.** Сайт: запись `optionalLinks` для `async_job/bloc`
  в `site/astro.config.mjs`, раньше записей `solo`;
  `python3 tool/build_site.py`, `python3 -m unittest tool/build_site_test.py`;
  `async_job/bloc` на обоих языках в теме `async_job` — глазом по конфигу, тест
  тему не проверяет.
- [ ] **Шаг 5.** Числа прозы против фейков стенда — список в отчёт.
- [ ] **Шаг 6.** `check_translations.py`, reflow, ширина, `check_links.py`;
  коммит
  `docs: translate the bloc page of async_job and link it from the README,
  the changelog and the riverpod page`.

### Задача 5. Мосты и закрытие на странице `solo`

**Файлы:** создать `packages/solo/doc/bloc.md`; изменить
`tool/bloc_snippets.py`, `.github/workflows/gate.yml`, `AGENTS.md`,
`site/astro.config.mjs`
(`page('solo/bloc', 'solo under bloc', 'solo под bloc')` после `solo/riverpod`
и запись в `optionalLinks` после записи `async_job/bloc`).

**Интерфейсы:** берёт `watch`, `Api`, `RUNNER`; мост состояний — по отчёту
задачи 1. Даёт `SOLO = .../solo/doc/bloc.md`, его `Blocks` и `unbuilt()`,
проверку подстроки `watch` для своей страницы. Ключи —
`SOLO_BRIDGES = 'the-bridges'`, `CLOSING` (тот же слаг, что у ядра), подраздел
ответа — `with-a-controller-under-the-bl`; сверить по `--list`.

- [ ] **Шаг 1. Драйверы.**
  - `solo_bridge_states`: мост задачи 1; `require` — то же, что в шаге 4 задачи
    1.
  - `solo_closing_bloc`: тот же `ChatBloc`, что у ядра (блок страницы `solo`,
    не ядра).
  - `solo_closing_controller`: `ChatController` раздела Solo `vs-bloc.md` под
    bloc, `close()` bloc закрывает контроллер, потом `super.close()`;
    `require`: `sent == [hi]`, `close()` не ждал вызов, ни одного состояния
    после `close()`, зона пуста.
  - `solo_closing_bloc_first`: тот же bloc с обратным порядком, `super.close()`
    первым; `require`: `sent == [hi, bye]` и два состояния после `close()` —
    очередь bloc прогнана через контроллер.
- [ ] **Шаг 2.** Генерация падает.
- [ ] **Шаг 3. Текст.** Заголовок, вступление, `## The bridges`: `watch`
  и ссылка на `riverpod-and-bloc.md` ядра, мост состояний под трансформером
  по умолчанию, почему не `Bloc.emit` из слушателя
  (`invalid_use_of_visible_for_testing_member`), методы `solo` возвращают `Job`
  и обработчик ждёт их так же. Раздел о закрытии; довод — «трасса лучше»;
  порядок `close()` — контроллер первым, и почему; в конце — «What stays with
  bloc:» и ссылка на раздел «Closing and cancelling in-flight work»
  `vs-bloc.md` по заголовку.
- [ ] **Шаг 4.** Генерация, анализ, прогон с `--enable-asserts`, `check_traces`
  по обеим страницам, `check_doc_shape.py`.
- [ ] **Шаг 5. CI.** `gate.yml`: драйверы `solo_*` — в `bloc-pages-solo.out`
  со своим `: >`, пара страницы `solo` в `check_traces`. `AGENTS.md`: второй
  документ стенда.
- [ ] **Шаг 6.** Reflow, ширина, handoff, коммит
  `docs: start solo under bloc with the bridges and closing`.

### Задача 6. Остальные разделы страницы `solo` и итоговая таблица

**Файлы:** `packages/solo/doc/bloc.md`, `tool/bloc_snippets.py`.

- [ ] **Шаг 1. Драйверы.** Запись: `solo_firmware_bloc` (`LockedFirmwareBloc`)
  и `solo_firmware_controller` (`FirmwareController` под bloc) — те же
  требования, что у ядра в задаче 3, включая состояния, исходы и ожидание
  `done` последней задачи. Сценарии, оставленные задачей 1 (из 1, 4, 5, 7,
  9), — пара драйверов на каждый по вердикту отчёта.
- [ ] **Шаг 2.** Генерация падает.
- [ ] **Шаг 3. Текст.** Разделы в порядке `vs-bloc.md`, каждый со своим доводом
  и ссылкой на раздел своего сценария `vs-bloc.md` по заголовку. Итоговая
  таблица: сценарии без раздела, ссылки на разделы сценариев `vs-bloc.md`;
  у ресурса после отмены — ссылка на раздел страницы ядра (GitHub). Вступление:
  список ловушек со ссылками.
- [ ] **Шаг 4.** Прогон, `unbuilt()` пуст, `check_traces`,
  `check_doc_shape.py`.
- [ ] **Шаг 5.** Reflow, ширина, handoff, коммит
  `docs: finish solo under bloc with the write and the table`.

### Задача 7. Перевод и входы страницы `solo`

**Файлы:** создать `docs/ru/solo/bloc.md`; изменить
`tool/check_translations.py` (как в задаче 4), `packages/solo/README.md`
и `README.ru.md` (строка таблицы «Guides» после «solo under riverpod» и абзац
над таблицей: фраза о странице riverpod переписывается так, чтобы назвать обе
страницы, и абзац не растёт — `LEAD = 10` в `tool/check_doc_shape.py`, а раздел
уже 10 строк; не выходит — остановиться и спросить владельца о другом входе;
раздел «Coming from bloc» не трогать), `packages/solo/doc/vs-bloc.md` и перевод
(фраза во вступлении о странице «solo under bloc»),
`packages/solo/CHANGELOG.md` и `docs/ru/solo/CHANGELOG.md`,
`packages/async_job/doc/bloc.md` и перевод (в таблице, где нужна очередь, —
ссылка на `packages/solo/doc/bloc.md` по GitHub).

- [ ] **Шаги 1–6** — как в задаче 4, для страницы `solo`; плюс
  `tool/doc_snippets.py` (стенд `vs-bloc`) после правки вступления: генерация
  и `check_traces` по `vs-bloc.md` зелёные, `QUOTED` и `SAID` не задеты. Правка
  страницы ядра — отдельным коммитом раньше коммита задачи: ни один коммит
  не трогает обе страницы. Коммит
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
  `check_page_code.py`, `check_translations.py`, `check_links.py`, `python3 -m
  unittest tool/archive_floor_test.py tool/build_site_test.py
  tool/check_links_test.py`, `build_site.py`; все пять стендов `snippets`
  с прогоном драйверов и `check_traces.py` по семи документам, как
  в `gate.yml`.
- [ ] **Шаг 3.** Handoff: в «следующие шаги» — вторая фаза страницы riverpod
  по предложению дизайна. Коммит
  `docs: record the bloc pages in the decisions and the handoff`.
- [ ] **Шаг 4.** Независимое ревью готовой работы — агент на Opus в своей копии
  дерева; находки и вердикты — разделом «Ревью работы» отчёта; принятые закрыть
  до вливания.
- [ ] **Шаг 5.** Влить в `main` (`ExitWorktree keep`, `git merge --ff-only`).
  Push — только по слову владельца.

## Ревью плана

Независимое ревью Opus по копии дерева на 9880eedd. Ревьюер гонял свои зонды
на bloc 9.2.1, `bloc_concurrency` 0.3.0 и `async_job`/`solo` путём,
а `check_links.py` и `check_doc_shape.py` — на копии `packages`, `docs`
и `tool`; репозиторий не тронут. Находки ниже — его текст, вердикт — отдельным
абзацем после каждой. Выводы зондов, на которые ссылаются находки,
процитированы в них.

### Critical

**C1. Ссылки страницы ядра на `solo` роняют `check_links.py`, а в задачах 3–4
ссылка ведёт ещё и на несуществующий файл.**
- Где: задача 3, шаг 3 («где нужна очередь — ссылка на страницу `solo` (GitHub,
  как прочие ссылки ядра на `solo`)», плюс «ссылка на раздел Bloc `vs-bloc.md`»
  в каждой строке таблицы); задача 4, шаг 6 (`check_links.py`); то же
  в переводе.
- Что не так:
  - `tool/check_links.py:37-47`: «A guide page does not lead up… a guide page,
    or its translation, that links into a document of a package built on its
    own is reported». Адрес GitHub проверяется так же, как относительный
    (`offenders`, строки 154-165).
  - «Прочих ссылок ядра на `solo`» из `doc/` нет: дизайн сам говорит, что ядро
    ссылалось на `solo` только из README.
  - `packages/solo/doc/bloc.md` появляется лишь в задаче 5.
- Доказательство: положил в копию `packages/async_job/doc/bloc.md` с двумя
  строками таблицы. Вывод `python3 tool/check_links.py`:
  ```
  bloc.md:9: a page of async_job leads up to solo: https://github.com/vi-k/solo/blob/main/packages/solo/doc/vs-bloc.md#bloc
  bloc.md:10: a page of async_job leads up to solo: https://github.com/vi-k/solo/blob/main/packages/solo/doc/bloc.md
  bloc.md:10: no such file: https://github.com/vi-k/solo/blob/main/packages/solo/doc/bloc.md
  ```
- Что предлагаю. Решение 144 и `AGENTS.md` такие ссылки разрешают («ядро
  ссылается на страницы `solo` только там, где ответ требует очереди»),
  а скрипт их запрещает без исключений. Нужен свой шаг до задачи 3:
  - узкое исключение в `check_links.py`: перечень пар «страница ядра → документ
    `solo`», сейчас это `async_job/doc/bloc.md` и его перевод, с причиной
    по решению 144;
  - случай в `tool/check_links_test.py`;
  - строка в docstring.

  Либо владелец решает, что таблица ядра называет страницы без ссылок. В любом
  случае ссылку на `solo/doc/bloc.md` надо переносить в задачу 5 или 7, иначе
  коммиты 3–4 красные.

Вердикт: принято. Проверил сам: `tool/check_links.py:36-47` запрещает странице
`doc/` ссылку на пакет выше без исключений. Решение 144 и `AGENTS.md` ядру
такую ссылку разрешают, поэтому исключение, а не страница без ссылок: задача 3
открывается шагом с исключением для `packages/async_job/doc/bloc.md` и его
перевода — случай в `tool/check_links_test.py` сначала красный, строка
docstring с причиной. Ссылка на `packages/solo/doc/bloc.md` уходит в задачу 7,
где страница `solo` уже есть.

### Important

**I1. С `async_job` только в `dependency_overrides` анализ стенда краснеет.**
- Где: «Стек» и задача 2 («`solo` путём… `async_job` путём
  в `dependency_overrides`»), при `CORE_HEAD`, который импортирует
  `package:async_job`.
- Доказательство: зонд с таким pubspec под правилами `async_job`,
  `dart analyze --fatal-infos bin`:
  ```
  info - bin/a_close.dart:5:8 - The imported package 'async_job' isn't a dependency of the importing package. - depend_on_referenced_packages
  ```
  Прецеденты устроены иначе: `solo_check` (`tool/doc_snippets.py:64-89`)
  `async_job` не импортирует, а `adapters_check` берёт его в `dependencies`.
- Что предлагаю: `async_job: path:` и в `dependencies`,
  и в `dependency_overrides`, иначе он конфликтует с hosted-ограничением
  `solo`. Проверил: лint пропадает. В «Стек» добавить и `lints: ^5.1.1` в dev:
  без него не разрешится `include: package:lints/recommended.yaml`.

Вердикт: принято. «Стек» и интерфейсы задачи 2 называют `async_job` путём
в обоих местах и `lints: ^5.1.1` в dev.

**I2. В `core_closing_job` сторож «`close()` короче вызова» не выполнится,
и формулировка прозы неверна.**
- Где: задача 2, шаг 1 и шаг 3 (довод «`close()` не ждёт вызов»).
- Доказательство: зонд `bin/c_closing.dart`. Api — 50 мс, как `CHAT_API`
  в `doc_snippets.py`; «hi» в полёте, «bye» в очереди, `close()` через 10 мс.
  Ответ страницы — поле, `close()` отменяет задачу до `super.close()`,
  обработчик ждёт `job.done`, затем `isClosed`:
  ```
  bloc close 90 ms, sent [hi, bye], reads 0, states []
  job  close 50 ms, sent [hi, bye], reads 0, states []
  ```
  `close()` не ждёт вызов «hi», но ждёт весь вызов «bye»: 50 мс равны одному
  вызову, так что сторож «короче вызова» не держит. Вариант
  с `await _current?.cancel()` даёт те же 50 мс.
- Что предлагаю:
  - сторож — `close` задачи меньше `close` bloc на остаток вызова в полёте;
  - проза говорит: «не ждёт вызов в полёте, но ждёт вызов каждого сообщения
    из очереди»;
  - числа взять из этого прогона, а не 58 мс из дизайна.

Вердикт: принято; сходится с моим зондом закрытия (задача с `isClosed` — 54 мс
против 93 у bloc, `[hi, bye]`). Сторож и формулировка — как предложено, числа —
из прогона стенда на виртуальном времени, не из дизайна и не из зонда.

**I3. Порядок закрытия контроллера под bloc в плане не задан, а от него зависит
всё.**
- Где: задача 1, шаг 4 и задача 5, шаг 1 (`solo_closing_controller`: «`close()`
  bloc закрывает контроллер»).
- Доказательство: зонд `bin/e_solo_chat.dart` — `ChatController` из `vs-bloc`
  с `SoloStream`, мост
  `on<_Follow>((e, emit) => emit.forEach(_chat.stream, onData: (s) => s))`,
  `SendMessage` под `sequential()` ждёт `_chat.send(..).done`:
  ```
  controller first follow=concurrent: closed=true, sent [hi], reads 0, states []
  bloc first follow=concurrent: closed=true, sent [hi, bye], reads 2, states [ChatState(reply to hi), ChatState(reply to bye)]
  controller first follow=sequential: closed=true, sent [hi], reads 0, states []
  bloc first follow=sequential: closed=false after >1000 ms, ... controller finished false
  ```
  Если `super.close()` идёт первым, `sequential()` прогоняет очередь через
  контроллер, и обе ошибки сценария возвращаются. Если вдобавок мост стоит под
  `sequential()` (или под глобальным `Bloc.transformer`), `close()`
  не завершается никогда.
- Что предлагаю:
  - в плане и на странице прямо: `await _chat.close()` до `super.close()`;
  - мост — под трансформером по умолчанию;
  - драйвер с обратным порядком как первая попытка или как сторож.

Вердикт: принято; мой зонд закрытия давал контроллер первым — 7 мс и `[hi]`.
Порядок и трансформер моста — в «Общих ограничениях», на странице `solo` они
говорятся прямо. Обратный порядок — драйвер-сторож `solo_closing_bloc_first`
в задаче 5: он требует `[hi, bye]` и два состояния после `close()` и тем держит
довод порядка.

**I4. Сторож «зона пуста» не ловит задачу, пережившую эмиттер, и `assert` bloc
в гейте выключены.**
- Где: «Куда смотреть ревьюеру», п. 3; задача 3, шаг 1 («прогресс — `emit`
  обработчика… зона пуста»).
- Что не так:
  1. Гейт гоняет `timeout 300 dart run "$driver"` без `--enable-asserts`,
     поэтому `assert(!_isCompleted)` в `_Emitter.call`
     (`bloc-9.2.1/lib/src/emitter.dart`) не срабатывает.
  2. После `cancel()` эмиттера `complete()` выходит рано
     (`if (isDone) return;`): `_isCompleted` остаётся false, поздний `emit`
     молча отбрасывается, утверждения нет даже с asserts.
  3. Обработчик, кончившийся нормально раньше задачи, с asserts даёт
     `AssertionError` внутри тела задачи. Это `Failed`, его поглощает `done`,
     зона пуста.
- Доказательство: зонд `bin/d_emit.dart`, restartable, вторая загрузка через 30
  мс. `leave=true` — обработчик не ждёт задачу.
  ```
  dart run:                  leave=false states=[1:0, 2:0, 2:1, 2:2] zone=[]
                             leave=true  states=[1:0, 1:1, 2:0, 1:2, 2:1, 2:2] zone=[]
  dart run --enable-asserts: leave=false states=[1:0, 2:0, 2:1, 2:2] zone=[]
                             leave=true  states=[] zone=[]
  ```
  Утверждение «законно, пока ждёт `forEach`» верно (строка `leave=false`).
  Но «пустая зона» его не доказывает.
- Что предлагаю: сторожить по состояниям и исходам. Требовать, чтобы после
  первого состояния новой загрузки не было ни одного состояния заменённой,
  а исход каждой задачи был `Done` или `Cancelled`, не `Failed`. И/или
  запускать `bloc_pages_check` с `dart run --enable-asserts` своей веткой
  в `gate.yml`.

Вердикт: принято, оба предложения. Драйверы задач 3 и 6 требуют по состояниям
и исходам, как предложено; драйверы `bloc_pages_check` гоняются
с `dart run --enable-asserts` и в шагах плана, и своей веткой в `gate.yml`.
Пункт 3 «Куда смотреть ревьюеру» переписан.

**I5. Правка гейта в задаче 2 сломает CI до задачи 5.**
- Где: задача 2, шаг 5 («в `check_traces` — пары обеих страниц
  с `bloc-pages.out`») и «Интерфейсы» (`SOLO = .../solo/doc/bloc.md`,
  `unbuilt()` обеих).
- Что не так: `check_traces.py` делает `doc.read_text()` и падает
  `FileNotFoundError` на отсутствующей `packages/solo/doc/bloc.md`. Генератор,
  который открывает `SOLO` на старте, падает так же. Коммиты 2–4 красные; это
  противоречит и правилу «ни один коммит не трогает обе».
- Что предлагаю: в задаче 2 — только `CORE` и пара ядра; `SOLO`, его `Blocks`,
  `unbuilt()` и пару `check_traces` добавляет задача 5. То же в `AGENTS.md`:
  «два документа» и «шесть пакетов» в задаче 2 — один документ ядра, второй
  называет задача 5.

Вердикт: принято. Задача 2 знает только `CORE`; `SOLO`, его `Blocks`,
`unbuilt()`, пару `check_traces` и второй документ в `AGENTS.md` добавляет
задача 5.

**I6. Абзац «Guides» в README `solo` уже на пределе `LEAD`, «перезалитый абзац»
уронит `check_doc_shape.py`.**
- Где: задача 7 («перезалитый абзац над таблицей»), дизайн, «Входы».
- Доказательство: в разделе 2 строки «Also on the documentation site…» и 8
  строк абзаца, ровно 10. Дописал в копии «, and solo under bloc for one who
  stays on bloc.» (одна строка):
  ```
  packages/solo/README.md:297: "Guides" opens with prose only
  ```
- Что предлагаю: в плане прямо — новая фраза не добавляет строк, абзац
  сокращается до 8 строк; иначе предложить владельцу другой вход. Довод дизайна
  про «Coming from bloc» (9 из 10) годится и для «Guides» (10 из 10).

Вердикт: принято. Проверил сам: `LEAD = 10` в `tool/check_doc_shape.py`, абзац
с «Also on the documentation site…» — ровно 10 строк. Задача 7: фраза
о `riverpod` переписывается так, чтобы назвать обе страницы, и абзац остаётся
в 8 строках; не выходит — остановиться и спросить владельца о другом входе.

**I7. `job.done` молча глотает `Failed`, а это рецепт страницы.**
- Где: задача 2, шаг 3 («отсюда задача в поле и `job.done`, не `job.value`»).
- Доказательство: зонд `bin/f_value.dart`, `sequential()`, `close()` отменяет
  задачу из поля:
  ```
  byValue=true  fail=false onError=[Cancelled(manual)] zone=[Cancelled(manual)]
  byValue=false fail=false onError=[] zone=[]
  byValue=false fail=true  onError=[] zone=[]
  ```
  Первая строка подтверждает довод про `value`. Последняя показывает, что
  ошибка API при `done` не доходит ни до `onError` bloc, ни до зоны: чтение
  `done` считается наблюдением.
- Что предлагаю: ответ страницы разбирает `Failed` из `outcome` (состояние
  ошибки, `addError` или повторный `throw`), а драйвер держит случай с падающим
  вызовом.

Вердикт: принято. Ответ страницы разбирает исход `job.done`: `Failed` уходит
туда же, куда ошибку вызова отправляет `ChatBloc` `vs-bloc.md`; драйвер
`core_closing_job_failed` с падающим вызовом требует, чтобы ошибка дошла.

### Minor

**M1. Ключ `CLOSING` неверен.** Задача 2, «Интерфейсы»: `slug` режет до 30
символов (`tool/doc_blocks.py:51`). `slug('Closing and cancelling in-flight
work') == 'closing-and-cancelling-in-flig'`,
`slug('With a controller under the bloc') == 'with-a-controller-under-the-bl'`,
а `'the-bridge'` и `'the-bridges'` верны. Предлагаю записать верные значения.
И `--list` у генератора на двух страницах должен печатать ключи каждой
с пометкой страницы; `doc_blocks.py --list` даёт ключи без подразделов.

Вердикт: принято. Ключи в задачах 2 и 5 исправлены; `--list` генератора
печатает ключи с подразделом и пометкой страницы.

**M2. `RUNNER` из `adapter_snippets.py` не даёт виртуального времени**,
а драйверам закрытия нужна длительность `close()`. `Stopwatch`
и `DateTime.now()` считают реальное время. `nowMs()` поверх `_clock` есть
в `RUNNER` `tool/doc_snippets.py:586-589`: взять его или дописать.

Вердикт: принято. `RUNNER` берётся из `tool/doc_snippets.py` вместе
с `nowMs()`; мой зонд записи на реальном времени уже дал ложный кусок средней
загрузки от дрожания таймеров.

**M3. `watch` — копия без сторожа.** В `riverpod-and-bloc.md:274-304` `watch`
и `SearchBloc` стоят одним блоком, и «байт в байт» значит подстроку. Предлагаю
`assert` в генераторе: блок `watch` каждой страницы входит в блок
`a-handler-that-restarts/a-stream-that-cancels-the-j/watch` соседки.

Вердикт: принято; проверка генератора — в задаче 2 для ядра, в задаче 5 для
`solo`.

**M4. Остальные правки гейта.** Плану недостаёт:
- `: > "$RUNNER_TEMP/bloc-pages.out"` рядом с остальными;
- комментария «the benches write five packages» → six;
- `AGENTS.md:290` («у всех четырёх стендов», «Стенды riverpod-and-bloc
  и riverpod добавляют подраздел»): задача 2 называет только строку 246.

Ещё одно: общий `bloc-pages.out` позволяет трассе страницы `solo` найтись
в выводе драйвера ядра: `ChatBloc` и `LockedFirmwareBloc` есть на обеих. Лучше
два файла вывода по префиксу драйвера (`core_`/`solo_`). Блок трассы из двух
драйверов сходится, только если они соседи по алфавиту и печатают ровно свои
строки: стоит сказать в плане.

Вердикт: принято. Два вывода, `bloc-pages-core.out` и `bloc-pages-solo.out`,
по префиксу драйвера; задача 2 заводит первый, задача 5 — второй, каждая
со своей строкой `: >`, комментарием о числе пакетов и строками `AGENTS.md`.
Оговорка про соседей по алфавиту — в шаге 1 задачи 2.

**M5. Драйверы должны дождаться конца задач.** Под `restartable()` `close()`
отменяет задачу из поля и возвращается до конца текущей записи (зонд
`a_close.dart`: `restartable: close 0ms, outcomes [Cancelled…]`). `RUNNER`
брошенные таймеры не замечает. Предлагаю, чтобы драйверы записи и ресурса ждали
`done` последней задачи и требовали `inFlight == 0` и все буферы
освобождёнными, прежде чем печатать.

Вердикт: принято; в шагах 1 задач 3 и 6.

**M6. `TheSidebarTopics` тему не проверяет.** «Куда смотреть ревьюеру», п. 5,
и задача 4, шаг 4: тест (`tool/build_site_test.py:344-363`) сверяет только, что
страница где-то перечислена. «Тема не та» он не ловит, а Astro гейт
не собирает. Это проверка глазом, так и написать. И `optionalLinks` для llms
в задаче 5 добавляется только у `solo/bloc`: при ставке ядра (решение 144)
странно без записи для `async_job/bloc`; ни у одной страницы ядра записи пока
нет.

Вердикт: принято. Тема — проверка глазом по `site/astro.config.mjs`, так
и записано; запись `optionalLinks` для `async_job/bloc` добавляет задача 4,
раньше записи `solo/bloc`.

**M7. `check_doc_shape.py` гоняется только в задаче 4 и только для README.**
Его правило «раздел начинается с кода за 10 строк» касается и новых страниц:
`## The bridge` с двумя фактами легко его превысит. Предлагаю добавить его
в шаги 4 задач 2, 3, 5 и 6.

Вердикт: принято.

**M8. Якоря `#solo-N` / `#bloc-N` к повторяющимся `### Solo`/`### Bloc`
хрупкие.** Новый раздел в `vs-bloc.md` сдвигает номера, и ссылка молча ведёт
на чужой сценарий: `check_links` проверяет только существование якоря.
Предлагаю ссылаться на раздел сценария или держать список якорей в генераторе.

Вердикт: принято: ссылки на `vs-bloc.md` ведут на заголовок раздела сценария,
не на `### Bloc`/`### Solo`; правило — в «Общих ограничениях».

**M9. Мост состояний.** Bloc отбрасывает равное состояние
(`if (this.state == state && _emitted) return;`, `bloc.dart`),
а `SoloStream.stream` «Equality is not checked: each change is an event».
Требование шага 4 задачи 1 «повторяет каждое состояние» на равных значениях
не выполнится. Уточнить формулировку.

Вердикт: принято: «каждое состояние, не равное предыдущему».

**M10. Мелочи по записям.**
- `docs/handoff.md` обновляется только в задаче 8, а `AGENTS.md` требует после
  каждого законченного шага.
- Предложение дизайна о второй фазе riverpod ни в один шаг не попало (handoff,
  «следующие шаги»).
- В «Связанных записях» плана нет будущего `2026-11-04-bloc-pages-report.md`.

Вердикт: принято, все три: handoff — в коммите каждой задачи (правило в «Общих
ограничениях»), вторая фаза riverpod — в «следующие шаги» handoff задачей 8,
отчёт — в «Связанных записях».

### Ответы по пунктам

1. **Покрытие дизайна.** Разделы, мост, критерий, стенд, входы, переводы,
   CHANGELOG, решение 133 и порядок коммитов покрыты. Не покрыты: конфликт
   ссылок ядра на `solo` с `check_links` (C1), бюджет «Guides» (I6), фаза
   riverpod (M10).
2. **Исполнимость.** `slug`, `Blocks`, `subsection_blocks`, `unbuilt`
   и `RUNNER` есть и устроены как в плане. Места в `gate.yml`,
   `astro.config.mjs` (`page(...)` после `async_job/riverpod-and-bloc`
   и `solo/riverpod`), `PAIRS` и `TheSidebarTopics` существуют. Расходятся
   `CLOSING` (M1), зависимость `async_job` (I1), порядок пар `check_traces`
   и `SOLO` (I5).
3. **Технические утверждения.**
   - (а) Верно. `a_close.dart`:
     `sequential: close 90ms, outcomes [Done(1), Done(2)]`; `restartable`,
     `concurrent` и `droppable: close 0ms, Cancelled(manual)`.
   - (б) Верно. `b_firmware.dart`, запись 20 мс, по 4 куска:
     `design [0, 30] maxInFlight=1` (гонки не видно); `design [0, 30, 5]`
     и `[0, 30, 0] maxInFlight=2 … 100+, 200+` (кусок средней загрузки).
     У цепочки (`before = _flashing` до создания задачи,
     `await ctx.join(() => before.done)` в теле, поле присваивается синхронно),
     у `LockedFirmwareBloc` и у `FirmwareController` с `Policy.restart` под
     bloc — `maxInFlight=1` и ни одного куска средней загрузки на обеих сериях.
     Трасса цепочки совпадает с `LockedFirmwareBloc`, так что её довод —
     «меньше правил», не «трасса лучше».
   - (в) Верно, пока обработчик ждёт `forEach`. Но сторож из плана этого
     не держит (I4).
4. **Что укусит.** I2, I3, I4, I7, M2, M5. `__pycache__` в `.gitignore`, так
   что `git status --porcelain` после стенда остаётся пустым.

Вердикт по пункту 3(б): принято — довод раздела о записи на странице ядра
«меньше правил», задача 3 так и говорит.
