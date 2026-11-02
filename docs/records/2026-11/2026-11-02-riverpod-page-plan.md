# Страница «solo under riverpod»: план

> **Состояние на 2026-11-02:** план написан, ждёт просмотра владельцем
> и выбора способа исполнения. Работа не начата.
> **Что это:** план страницы `packages/solo/doc/riverpod.md`, её стенда
> `tool/riverpod_snippets.py` в задании `snippets`, перевода, README, сайта
> и правок записей — по одобренному дизайну.
> **Связанные записи:** `2026-11-02-riverpod-page-design.md`,
> `2026-11-02-riverpod-pain-points-research.md`,
> `2026-10-30-riverpod-and-bloc-design.md`.

> **Исполнителю:** скилл `superpowers:subagent-driven-development` или
> `superpowers:executing-plans`; шаги — флажки `- [ ]`. Перед текстом
> страницы — скиллы `doc-reader` и `doc-bench`, перед кодом Dart — `dart`.

**Цель:** страница `packages/solo/doc/riverpod.md` показывает разработчику
на riverpod 3, который слой состояния не меняет, где под его провайдером встаёт
контроллер `solo`, — каждым фрагментом, собранным и прогнанным в CI.

**Устройство:** страница по образцу
`packages/async_job/doc/riverpod-and-bloc.md`: разделы с первой попыткой
и ответом, трассы в блоках `text`. Новый стенд `tool/riverpod_snippets.py`
копирует блоки страницы байт в байт в пакет `riverpod_check`, драйверы
на виртуальном времени со сторожами `require`. Общая адресация блоков
с подразделами переезжает в `tool/doc_blocks.py`.

**Стек:** Dart 3.10+, `riverpod: ^3.0.0` (чистый Dart), `solo` и `async_job`
путями из дерева, `fake_async`, Python 3 для стенда и проверок, Starlight для
сайта.

**Дизайн:** `docs/records/2026-11/2026-11-02-riverpod-page-design.md` — читать
вместе с планом; доводы и зонды — там.

## Общие ограничения

- Страница по-английски, перевод `docs/ru/solo/riverpod.md` в том же коммите,
  что и каждая правка оригинала.
- Ширина 79, жадный перенос: `python3 tool/reflow.py` по названным файлам.
- На странице нет номеров заявок riverpod, нет «Coming from riverpod», нет
  призыва уходить с riverpod; первая попытка — код из документации riverpod
  с её охранами.
- Нового API нет: ни `SoloProvider`, ни хелпера; `packages/*` от riverpod
  не зависят.
- Стенд: `riverpod: ^3.0.0`, `solo` путём, `async_job` путём
  в `dependency_overrides`; утверждения страницы о поведении riverpod держат
  сторожа `require`.
- Слово «джоба» в русском тексте запрещено: «задача» или `Job`.
- Git — `/usr/bin/git`; коммиты Conventional Commits по-английски,
  с `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Куда смотреть ревьюеру

Пять мест, которые тесты не держат и где ошибка больнее всего:

1. Числа в прозе (50 мс открытия, 10 и 80 мс ухода, 30 мс отправки)
   `check_traces.py` не сверяет: в задаче 6 их сверяют с фейками стенда
   глазами, по списку.
2. `removeListener(ref.notifyListeners)` работает, только если два отрыва
   метода равны по `==`; если стенд покажет иначе — остановиться и спросить,
   а не менять мост молча. Сторож — задача 2, шаг 1, драйвер `bridge`.
3. Новый минор riverpod может сделать мутации ограниченными или
   `MutationPending` асинхронным: сторожа задачи 4 должны краснеть,
   а не печатать другое.
4. Боковую панель сайта не держит ни один тест: в задаче 6 её проверяют сборкой
   сайта и поиском строки в выводе.
5. Пара в `PAIRS`: без неё `check_translations.py` молчит. В задаче 6
   проверить, что он называет `riverpod.md` в своём выводе или падает
   на намеренно испорченном переводе.

---

### Задача 1. Адресация с подразделами — в `tool/doc_blocks.py`

**Файлы:**
- Изменить: `tool/doc_blocks.py`, `tool/adapter_snippets.py:72-115`
  (`page_blocks`, `Blocks`).
- Изменить: `~/.claude/skills/doc-bench/doc_blocks.py` — копия.

**Интерфейсы:**
- Даёт: `doc_blocks.subsection_blocks(text: str) -> dict[str, str]` — то, что
  сейчас `page_blocks` в `adapter_snippets.py`, ключ
  `section/[subsection/]Name`, повтор — `POISONED`; `doc_blocks.Blocks(dict)`
  с `taken` и `unbuilt()` без изменений.

- [ ] **Шаг 1.** Снять эталон: `python3 tool/adapter_snippets.py --list` в файл
  и `python3 tool/adapter_snippets.py <tmp>/before` — запомнить список ключей
  и `wrote N files`.
- [ ] **Шаг 2.** Перенести `page_blocks` (переименовав в `subsection_blocks`)
  и `Blocks` в `tool/doc_blocks.py`; `adapter_snippets.py` берёт их оттуда.
- [ ] **Шаг 3.** `--list` и генерация в `<tmp>/after`: список ключей тот же,
  `diff -r <tmp>/before <tmp>/after` пуст.
- [ ] **Шаг 4.** Скопировать `tool/doc_blocks.py` в скилл `doc-bench`; `diff`
  пуст.
- [ ] **Шаг 5.** Коммит
  `refactor: move subsection block addressing into doc_blocks`.

### Задача 2. Стенд и раздел «A controller under a provider»

**Файлы:**
- Создать: `tool/riverpod_snippets.py`, `packages/solo/doc/riverpod.md`.
- Изменить: `.github/workflows/gate.yml` (задание `snippets`), `AGENTS.md`
  (абзацы о `snippets` и об адресации).

**Интерфейсы:**
- Даёт: пакет `riverpod_check` под `<workdir>`, драйверы
  `riverpod_check/bin/v/<name>.dart`; Dart-фейки `Device`
  (`static Future<Device> open()` — 50 мс, `Future<void> close()`, множество
  `alive`, журнал `log`), `delay(int ms)`, `require(bool, String)`, `RUNNER`
  (копия из `adapter_snippets.py`, `scenario()` — драйвер); ключи разделов
  `CONTROLLER = 'a-controller-under-a-provider'`.
- Страница: состояния `CameraState` — `Closed`, `Opening`, `Ready(Device)`;
  контроллер `Camera extends Solo<CameraState>` с `Job<void> open()`: ключ
  `#camera`, `Policy.restart`, `ifCancelled` → `Closed`, тело —
  `emit(Opening())`, `ctx.join(Device.open, discard: (d) => d.close())`,
  `emit(Ready(d))`. Без `onClose` — его добавит задача 3.

Генератор — по образцу `tool/adapter_snippets.py`: `PUBSPEC`
с `riverpod: ^3.0.0`, `fake_async`, `solo` путём
и `dependency_overrides: async_job:` путём (как `tool/doc_snippets.py:80-84`),
правила анализа — копия `packages/solo/analysis_options.yaml`, `--list`,
проверка `unbuilt()` в конце.

- [ ] **Шаг 1. Драйверы со сторожами раньше текста.**
  - `bridge_first`: провайдер `camera` первой попытки —
    `addListener (ref.notifyListeners)` без `removeListener` в `onDispose`.
    Экран слушает `camera.select((c) => c.currentState)`, зовёт `open()`,
    уходит через 10 мс. `require`: в зоне ровно одна ошибка, и её текст
    начинается с `Cannot use the Ref of`. Печатает
    `zone: <первая строка ошибки>`.
  - `bridge`: тот же сценарий с ответом. `require(zone.isEmpty)`,
    `require(outcome is Cancelled)`, `require(alive.isEmpty)`. Печатает строки
    вида зонда дизайна: `screen left`, затем
    `outcome=... alive=... log=... seen=...`.
- [ ] **Шаг 2.** `python3 tool/riverpod_snippets.py <tmp>` падает: блоков
  на странице нет (`KeyError`).
- [ ] **Шаг 3. Текст.** Заголовок страницы «solo under riverpod», абзац
  о читателе (остаётся на riverpod), заглушка таблицы вступления (её заполнит
  задача 5). Раздел `## A controller under a provider`:
  - `### The first attempt` — блоки `CameraState`, `Camera`, провайдер `camera`
    без `removeListener`, трасса `zone:`; проза — почему: при `close()`
    `ifCancelled` публикует `Closed`, слушатель зовёт удалённый `Ref`.
  - `### Removing the listener` — провайдер `camera` с `removeListener`
    в `onDispose`, строка экрана
    `ref.watch(camera.select((c) => c.currentState))` комментарием, трасса
    ухода во время открытия; проза: `notifyListeners` riverpod описывает для
    изменяемого объекта, `select` отдаёт каждое изменение; `StreamProvider` над
    `SoloStream` не годится — поток не отдаёт текущее состояние; во Flutter —
    `ref.watch(camera)` и `SoloBuilder` из `flutter_solo`, ссылкой, без кода.
- [ ] **Шаг 4.** Генерация, `dart pub get`, `dart analyze --fatal-infos bin/v`,
  прогон обоих драйверов: сторожа держат, трассы совпадают.
  `python3 tool/check_traces.py packages/solo/doc/riverpod.md <вывод>`.
- [ ] **Шаг 5. CI.** В `gate.yml`, задание `snippets`: ключ кеша
  (`tool/riverpod_snippets.py`), сборка (строка генератора), цикл зависимостей
  и анализа (`riverpod_check`), прогон (`riverpod.out`, своя ветка `elif`),
  `check_traces` (пара `riverpod.md` и `riverpod.out`). В `AGENTS.md`: «четыре
  стенда», четвёртый скрипт и документ, «в пять пакетов»; абзац об адресации —
  подразделы теперь в `doc_blocks.py`, ими пользуются два стенда.
- [ ] **Шаг 6.** `python3 tool/reflow.py --check`,
  `python3 tool/check_line_width.py`, коммит
  `docs: start the riverpod page of solo with a controller under a provider`.

### Задача 3. Раздел «A camera closed when the screen goes»

**Файлы:** `packages/solo/doc/riverpod.md`, `tool/riverpod_snippets.py`.

**Интерфейсы:**
- Берёт: `Camera`, провайдер `camera` с `removeListener`, фейки задачи 2.
- Даёт: `Camera` с `@override void onClose()`, закрывающим устройство
  из `Ready`; ключ `CAMERA = 'a-camera-closed-when-the-screen-goes'`.

- [ ] **Шаг 1. Драйверы.**
  - `camera_naive`: `FutureProvider.autoDispose`,
    `final d = await Device.open(); ref.onDispose(d.close);` — уход через 10
    мс; `require(alive.length == 1)`; печатает `riverpod naive: alive=...`.
  - `camera_flag`: флаг `disposed` в `onDispose` до `await`, после открытия —
    `if (disposed) { await d.close(); throw ...; }` по образцу рецепта
    riverpod, иначе `ref.onDispose(d.close)`; уход через 10 мс и через 80 мс;
    `require(alive.isEmpty)` в обоих.
  - `camera_late`: контроллер задачи 2, уход через 80 мс;
    `require(alive.length == 1)`, `require(outcome is Done)`.
  - `camera_on_close`: контроллер с `onClose`, уход через 10 и через 80 мс;
    `require(alive.isEmpty)` в обоих.
- [ ] **Шаг 2.** Генерация падает на отсутствующих блоках.
- [ ] **Шаг 3. Текст.** `## A camera closed when the screen goes`:
  - `### The first attempt` — наивный провайдер, трасса, проза: уход во время
    открытия, `onDispose` ещё не зарегистрирован, в зону ничего.
  - `### A flag before the await` — правильный riverpod; сказать прямо, что он
    работает; уборка в двух местах, порядок регистрации держит автор.
  - `### Leaving after the camera opened` — контроллер раздела выше, уход через
    80 мс, `alive={1}`: `close()` отменяет очередь и задач не ставит.
  - `### onClose` — переопределение, обе трассы; довод: флаг и порядок
    регистрации держать не нужно — гонку держит `discard` у захвата, владение —
    `onClose`. Ссылка на «Disposing of the camera» в `camera.md` для
    контроллера, у которого закрытие само — задача.
- [ ] **Шаг 4.** Прогон, анализ, `check_traces`; `Camera` объявлен в двух
  подразделах — ключи с подразделом, `unbuilt()` пуст.
- [ ] **Шаг 5.** Reflow, ширина, коммит `docs: show solo closing a camera under
  riverpod on either side of the opening`.

### Задача 4. Раздел «A form sent once»

**Файлы:** `packages/solo/doc/riverpod.md`, `tool/riverpod_snippets.py`.

**Интерфейсы:**
- Даёт: фейк `Future<String> send(String text)` — 30 мс, счётчик `calls`, ответ
  `'sent $text #$n'`, где `n` — номер вызова, взятый до задержки; `FormState`,
  `MessageForm extends Solo<FormState>` с `Job<String> submit(String text)`:
  ключ `#submit`, `Policy.droppable`, тело — `ctx.join(() => send(text))`,
  `emit(Sent(receipt))`; ключ `FORM = 'a-form-sent-once'`.

- [ ] **Шаг 1. Драйверы.**
  - `form_unguarded` (сторож, блоков страницы не берёт, кроме `sendMessage`):
    два `run` подряд без охраны; `require(calls == 2)`. Если riverpod начнёт
    ограничивать мутации — красный CI, и цитата `mutations.dart:282`
    на странице снимается.
  - `form_mutation`: охрана из документации riverpod —
    `if (container .read(sendMessage) is MutationPending) return null;` перед
    `run`; `require(state right after run is MutationPending)`,
    `require(calls == 1)`, второй вызывающий получил `null`.
  - `form_droppable`: `submit('hi')` и `submit('bye')` подряд;
    `require(identical(a, b))`, `require(calls == 1)`, оба `value` —
    `'sent hi #1'`, состояние `Sent('sent hi #1')`.
- [ ] **Шаг 2.** Генерация падает.
- [ ] **Шаг 3. Текст.** `## A form sent once`:
  - `### The first attempt` — мутация с охраной по `MutationPending`, как
    в документации riverpod; мутации названы экспериментальными
    (`package:riverpod/experimental/mutation.dart`); сказать, что охрана
    работает. Разница узкая: второй вызывающий получает `null`, а не результат;
    охрана у каждого вызывающего, без неё мутация не ограничивает параллельные
    вызовы — цитата из её документации.
  - `### Policy.droppable` — `MessageForm`, трасса; `await job.value` у обоих,
    без `shared()` (он для `then`, ссылка на `jobs.md`); отправка через
    `ctx.join`, а не `abandonable`, и почему; цена — второй вызов с другими
    аргументами получает первую задачу, `'bye'` теряется.
- [ ] **Шаг 4.** Прогон, анализ, `check_traces`.
- [ ] **Шаг 5.** Reflow, ширина, коммит
  `docs: show a form sent once under riverpod,
  with its mutation guard and with droppable`.

### Задача 5. Вступление и «What you take on»

**Файлы:** `packages/solo/doc/riverpod.md`, `tool/riverpod_snippets.py`.

**Интерфейсы:** берёт провайдер `camera` с `onClose` (задачи 2–3).

- [ ] **Шаг 1. Драйверы.**
  - `price_read`: `container.read(camera).open()` без подписчика;
    `require(outcome is Cancelled)`, `require(alive.isEmpty)`; печатает
    `read without a listener: <outcome> alive=...`.
  - `price_invalidate`: экран слушает, камера открыта,
    `ref.invalidate (camera)`; `require` — прежний контроллер закрыт,
    устройство закрыто, новый контроллер в `Closed`. Печатает строку об этом.
- [ ] **Шаг 2.** Генерация падает (блоки раздела без драйвера или наоборот).
- [ ] **Шаг 3. Текст.**
  - Таблица вступления «The trap in riverpod | What answers it | Where»: `Ref`
    после `await` в методе нотифайера — «A notifier that starts again» ядра,
    у метода контроллера `Ref` нет, а `emit` отменённой задачи до состояния
    не доходит; провайдер удалён посреди работы — «A provider that is gone»
    ядра; debounce флагом и броском (ссылка на how_to/cancel riverpod) —
    `ctx.pause`, «A pause of the job» в `time.md`, у `solo` — `accumulate`, «A
    search that fires on every keystroke» в `accumulation.md`, с оговоркой:
    свой тип исключения riverpod бросать может, `async_job` даёт его всему
    коду; ресурс до уборки, форма, состояние на экране — разделы этой страницы.
    Фраза: граф, кеш и `AsyncValue` остаются за riverpod. Ссылки на ядро —
    на GitHub, как у прочих страниц `solo`, ссылающихся на `async_job`.
  - `## What you take on` — список пункт в пункт из раздела 4 дизайна,
    с трассами `price_read` и `price_invalidate`, ссылка на «Retrying a failed
    call» в `errors.md`; последний абзац — когда `solo` не нужен.
- [ ] **Шаг 4.** Прогон всего стенда, `unbuilt()` пуст, `check_traces`,
  `python3 tool/check_links.py`.
- [ ] **Шаг 5.** Reflow, ширина, коммит `docs: open the riverpod page with the
  traps it answers and close it with the price`.

### Задача 6. Перевод, README, CHANGELOG, сайт

**Файлы:**
- Создать: `docs/ru/solo/riverpod.md`.
- Изменить: `tool/check_translations.py` (`PAIRS` и строка в docstring),
  `packages/solo/README.md` и `README.ru.md` («Guides» / «Страницы»: абзац
  о порядке целиком и строка таблицы; новый раздел «With riverpod» /
  «С riverpod» после «Coming from bloc» / «Переход с bloc»),
  `packages/solo/CHANGELOG.md` и `docs/ru/solo/CHANGELOG.md` («Unreleased» /
  «Не выпущено»), `site/astro.config.mjs`
  (`page('solo/riverpod', 'solo under riverpod', 'solo под riverpod')` после
  `solo/vs-bloc` и запись в `optionalLinks`).

- [ ] **Шаг 1.** Пара в `PAIRS`; `python3 tool/check_translations.py` краснеет:
  перевода нет.
- [ ] **Шаг 2.** Перевод страницы, раздела README и записи CHANGELOG; фрагменты
  кода — те же байты, кроме комментариев. Абзацы перевода —
  `python3 /Users/user/.claude/skills/humanizer--ru/scripts/lint.py`, ноль
  `ERROR`.
- [ ] **Шаг 3.** README: раздел «With riverpod» — три-четыре фразы: для кого
  страница, что остаётся за riverpod, ссылка. Запись «Unreleased»: новая
  страница `doc/riverpod.md`.
- [ ] **Шаг 4.** Сайт: `python3 tool/build_site.py`, затем
  `python3 -m unittest tool/build_site_test.py`; в собранном
  `site/src/content/docs/` есть `solo/riverpod` на обоих языках, строка
  панели — в `astro.config.mjs`.
- [ ] **Шаг 5.** Сверить числа прозы с фейками стенда (п. 1 «Куда смотреть
  ревьюеру»), записать список в отчёт задачи.
- [ ] **Шаг 6.** `check_translations.py` зелёный и называет пару; reflow,
  ширина, ссылки; коммит
  `docs: translate the riverpod page and link it from the README,
  the changelog and the site`.

### Задача 7. Записи и полная проверка

**Файлы:** `docs/settled.md` (решение 133),
`docs/records/2026-10/2026-10-30-pub-dev-landscape-review.md` (вердикт F2),
шапки `2026-11-02-riverpod-page-design.md` (плюс раздел «Что вышло»: где работа
разошлась с дизайном), этого плана
и `2026-11-02-riverpod-pain-points-research.md`, `docs/handoff.md`.

- [ ] **Шаг 1.** Решение 133: дописать — к пользователям riverpod идёт
  и `solo`, страница `doc/riverpod.md` для читателя, который остаётся
  на riverpod (владелец 2026-11-02; `2026-11-02-riverpod-page-design.md`).
- [ ] **Шаг 2.** Итог в конец вердикта F2: что сделано, коммит, запись. Старую
  запись скрипту целиком не называть: абзац — заливкой на временной копии.
- [ ] **Шаг 3.** Проверки задания `docs` целиком: `reflow.py --check`,
  `check_line_width.py`, `check_doc_shape.py`, `check_dartdoc.py`,
  `check_page_code.py`, `check_translations.py`, `check_links.py`,
  `python3 -m unittest tool/archive_floor_test.py tool/build_site_test.py`,
  `build_site.py`; все четыре стенда `snippets` с прогоном драйверов
  и `check_traces.py` по пяти документам, как в `gate.yml`.
- [ ] **Шаг 4.** Коммит `docs: record the riverpod page in the decisions,
  the review and the handoff`.
- [ ] **Шаг 5.** Независимое ревью готовой работы — агент `reviewer` на Opus
  в своей копии дерева; находки и вердикты — разделом «Ревью работы» записи
  дизайна; принятые закрыть до вливания.
- [ ] **Шаг 6.** Влить в `main` (`ExitWorktree keep`, `git merge --ff-only`).
  Push — только по слову владельца.
