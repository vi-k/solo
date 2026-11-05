# Вход у `async_job`: README на один-два экрана, план

> **Состояние на 2026-11-05:** план написан по дизайну, одобренному владельцем
> 2026-11-05; ждёт независимого ревью Opus.
> **Что это:** план короткого README ядра: две новые страницы «Why a job»
> и «Reference», новый Quick start, раздел об `abandonable`, переводы, сайт,
> ссылки и сторожа.
> **Связанные записи:** `2026-11-04-core-readme-entry-design.md`,
> `2026-10-30-pub-dev-landscape-review.md`.

> **Исполнителю:** скилл `superpowers:executing-plans` или
> `superpowers:subagent-driven-development`; шаги — флажки `- [ ]`. Перед
> текстом страниц — скилл `doc-reader`, перед кодом Dart — `dart`.

**Цель:** читатель pub.dev получает в README ядра вход на два экрана — `Job`,
`ctx.join`, `ctx.abandonable`, `dispose`, `cancel()`, исход, — код которого,
скопированный как есть, не теряет провал, а всё, что уходит из README, живёт
целиком на двух страницах ядра.

**Устройство:** «Why» и «A fuller example» переезжают
на `packages/async_job/doc/why.md`, «The context at a glance» и «Four words» —
на `packages/async_job/doc/reference.md`, байт в байт, с правкой одних ссылок.
Сторож `test/readme_recipe_test.dart` остаётся одним файлом и читает каждый
текст с той страницы, где он теперь стоит. Quick start берёт `done` сразу после
конструктора, новый раздел исполняется своим файлом примера.

**Стек:** Dart 3.10+, `package:test`, `fake_async`; Python 3 для проверок
`tool/`; Starlight для сайта.

**Дизайн:** `docs/records/2026-11/2026-11-04-core-readme-entry-design.md` —
читать вместе с планом; доводы, зонды и ревью — там.

## Общие ограничения

- Новые страницы: `packages/async_job/doc/why.md`, заголовок `# Why a job`;
  `packages/async_job/doc/reference.md`, заголовок `# Reference`. Переводы:
  `docs/ru/async_job/why.md`, `# Зачем задача`;
  `docs/ru/async_job/reference.md`, `# Справочник`.
- Разделы переезжают с нынешними заголовками и якорями: `## Why`,
  `## A fuller example`, `## The context at a glance`, `## Four words`;
  в переводе `## Зачем`, `## Развёрнутый пример`, `## Контекст коротко`,
  `## Четыре слова`. Вступление страницы — одна-две фразы, без карты разделов,
  решение 107.
- Внутри переехавшего текста правятся только ссылки: `doc/x.md` → `x.md`,
  `#solo` → `../README.md#solo`; в переводе `../../docs/ru/async_job/x.md` →
  `x.md`, `#solo` → ссылка на раздел «solo» `README.ru.md` тем же видом, каким
  перевод ведёт в README своего пакета (смотри соседние страницы
  `docs/ru/async_job/`; `check_links.py` решает).
- README до `## Guides` — не больше 120 строк исходника, через Quick start —
  не больше 90 (цель дизайна исправлена этим планом, «Поправка дизайна» ниже).
- В прозе README до `## Guides` нет «observe», «answer for», «the zone»
  и ссылки на «Four words»; в переводе — «наблюда», «отвечает за», «зон[аеуы]»
  и «#четыре-слова».
- Английские ссылки из других пакетов — абсолютные `blob/main`, решение 74.
  Русские со страниц `docs/ru/solo/` — относительные:
  `../async_job/reference.md#контекст-коротко`;
  `async_job_lints/README.ru.md` —
  `https://github.com/vi-k/solo/blob/main/docs/ru/async_job/reference.md#контекст-коротко`.
- Перевод — тем же коммитом, что и оригинал; после правки русского текста —
  линтер `humanizer--ru` (только `ERROR`), `bare_names.py` и `jargon.py`.
- Ширина 79: `python3 tool/reflow.py <файлы>` для записей,
  `python3 tool/reflow.py --check` и `python3 tool/check_line_width.py`
  из корня.
- Нового API нет; `solo` не меняется, кроме ссылок и прозы рядом с ними.

## Поправка дизайна

Цель «README до "Guides" — не больше 90 строк» не сходится с самим дизайном.
Черновик входа по составу из дизайна, сделанный при плане: вступление с фразой
о новых страницах — 20 строк, Install с одной фразой о плагине — 18, Quick
start со `switch` — 47, итого 85 через Quick start; раздел об `abandonable`
с блоком, выводом и абзацем из трёх оговорок — ещё 30, итого 115 до «Guides».
Ревьюер мерил 115 строк с новым блоком и предложил 80–90 вместе с сокращениями;
сокращения дают четыре строки, а не двадцать пять. Сейчас до «Guides» 235 строк
и 2058 слов, в черновике — 115 строк и 631 слово. Мерка плана: через Quick
start — не больше 90 строк, до «Guides» — не больше 120; держит её сторож
README. Дизайн правится тем же коммитом, что и план, и владелец слышит об этом
в отчёте о плане.

## Куда смотреть ревьюеру

Входы и случаи, которых задачи плана иначе не проверили бы, — у каждого свой
тест в задаче, которая владеет кодом:

1. Открытие базы в Quick start падает до отмены: программа печатает `failed: …`
   из `switch`, в зону не уходит ничего — тест в задаче 3.
2. Брошенный через `ctx.abandonable` вызов падает после отмены, `done` взят
   сразу: ошибка всё равно приходит в зону — тест в задаче 4; на нём стоит
   фраза README о необработанной ошибке.
3. Чтение Quick start под `ctx.abandonable`: база закрыта раньше, чем чтение
   кончилось, — тест в задаче 4; на нём стоит фраза о ресурсе.
4. Опубликованная ссылка на `#the-context-at-a-glance` открывает README сверху:
   README называет обе новые страницы до `## Install` — тест в задаче 3.
5. Архив без каталога `docs/ru`: сторож читает только оригиналы новых страниц
   и не падает — проверка раскладкой `floor` в задаче 5.

---

### Задача 1. Справочник ядра: «The context at a glance» и «Four words»

**Файлы:**
- Создать: `packages/async_job/doc/reference.md`,
  `docs/ru/async_job/reference.md`
- Изменить: `packages/async_job/README.md`, `packages/async_job/README.ru.md`
  (разделы уходят; строка `Guides`; ссылка Quick start на «Four words»),
  `packages/async_job/test/readme_recipe_test.dart`,
  `packages/solo/doc/reference.md:8-9,106-107`,
  `docs/ru/solo/reference.md:8,107`, `packages/async_job_lints/README.md:185`,
  `packages/async_job_lints/README.ru.md:190`, `tool/check_translations.py`
  (`PAIRS`), `site/astro.config.mjs`

**Интерфейсы:**
- Даёт: в сторожe список `referencePages`: `['doc/reference.md', if
  (Directory('../../docs/ru').existsSync())
  '../../docs/ru/async_job/reference.md']`, по образцу `versions`
  в `test/errors_rakes_test.dart:30-45`, с комментарием о том, почему каталог,
  а не файл.

- [ ] **Шаг 1. Сторож читает таблицу со справочника.** В группе
  `'the context at a glance'` все `readmes` заменить на `referencePages`;
  `contextTable('README.md')` — на `contextTable('doc/reference.md')`; проверка
  перевода в строках около 1145 — `referencePages.length > 1` и путь перевода;
  ключи карт в тестах `'the notes say…'` и `'the errors of unattended work…'` —
  пути двух страниц справочника.
- [ ] **Шаг 2. Убедиться, что он краснеет.**
  `cd packages/async_job && dart test test/readme_recipe_test.dart` — падают
  тесты группы `the context at a glance` с `PathNotFoundException`
  на `doc/reference.md`.
- [ ] **Шаг 3. Перенести разделы.** `doc/reference.md`: `# Reference`,
  вступление в одну-две фразы (каждый член контекста — что он делает
  у отменённой задачи, и четыре слова модели, которыми говорят остальные
  страницы), затем оба раздела из README как есть, с правкой ссылок по «Общим
  ограничениям». Из README оба раздела удалить; ссылку Quick start
  `[Four words](#four-words)` временно повести
  на `[Four words](doc/reference.md#four-words)` — задача 3 убирает фразу.
  То же в переводе. В «Guides» последней строкой: `|
  [Reference](doc/reference.md) | Every member of the context and what it does
  once the job is cancelled; the four words of the model |`, в переводе —
  так же к `../../docs/ru/async_job/reference.md`.
- [ ] **Шаг 4. Ссылки и проза других пакетов.**
  - `packages/solo/doc/reference.md`: обе ссылки —
    на `https://github.com/vi-k/solo/blob/main/packages/async_job/doc/reference.md#the-context-at-a-glance`,
    «of the `async_job` README» → «on the reference page of `async_job`».
  - `docs/ru/solo/reference.md`:
    на `../async_job/reference.md#контекст-коротко`, проза рядом — «справочника
    `async_job`».
  - `packages/async_job_lints/README.md:185` и перевод: адрес по «Общим
    ограничениям», текст ссылки называет страницу: «See
    [The context at a glance](…) on the reference page of `async_job`».
- [ ] **Шаг 5. Пара, сайт.** В `PAIRS` `tool/check_translations.py` —
  `(…/"async_job"/"doc"/"reference.md", …/"ru"/"async_job"/"reference.md")`
  последней парой ядра. В `site/astro.config.mjs` перед
  `changelog('async_job')`:
  `page('async_job/reference', 'Reference', 'Справочник'),`.
- [ ] **Шаг 6. Зелёный.** Из `packages/async_job`:
  `dart test test/readme_recipe_test.dart` — всё зелёное. Из корня:
  `python3 tool/check_translations.py`, `python3 tool/check_links.py`,
  `python3 tool/check_doc_shape.py`, `python3 tool/build_site.py`,
  `python3 -m unittest tool/build_site_test.py` — без замечаний. Линтер
  `humanizer--ru`, `bare_names.py`, `jargon.py`
  на `docs/ru/async_job/reference.md` — без `ERROR` в новом вступлении.
- [ ] **Шаг 7. Коммит**
  `docs: move the context table and the four words to a core reference page`.

### Задача 2. «Why a job»: «Why» и «A fuller example»

**Файлы:**
- Создать: `packages/async_job/doc/why.md`, `docs/ru/async_job/why.md`
- Изменить: `packages/async_job/README.md`, `packages/async_job/README.ru.md`,
  `packages/async_job/test/readme_recipe_test.dart`,
  `packages/async_job/example/example.dart:60`,
  `packages/async_job/test/cleanup_test.dart:719`,
  `tool/check_translations.py`, `site/astro.config.mjs`

**Интерфейсы:**
- Потребляет: образец `referencePages` из задачи 1.
- Даёт: `whyPages` того же вида для `doc/why.md`; помощник
  `List<String> quotedOutputs(String page, int count)` — требует ровно `count`
  блоков `text` и возвращает их по порядку.

- [ ] **Шаг 1. Сторож читает тур со страницы «Why a job».**
  - `whyPages` вместо `readmes` в тестах: `'Job(body, timeout: limit)…'`,
    группе `'the fuller example'`
    (`quotedAfter(page, 'final outcome = await job.done;')`
    и `'…names that filter…'`), `'the example prints what the README quotes'`
    (переименовать в `'the example prints what the why page quotes'`,
    `quotedOutputs(page, 1).single`, счёт прогонов — из `doc/why.md`).
  - Тест Quick start берёт `quotedOutputs(page, 1).single`: в README остаётся
    один вывод, задача 4 добавит второй.
  - `'every block of the README runs in this file'` — вторым ожиданием
    `codeMissingFrom('doc/why.md', 'test/readme_recipe_test.dart')` пуст.
  - `'and each of them runs whole…'`: блоки README сверяются с метками
    `example/quick_start.dart`, блоки `doc/why.md` — с метками
    `test/readme_recipe_test.dart`; две отдельные `expect`.
  - `'the example runs the job of the fuller example…'` читает блок
    из `doc/why.md`.
  - Шапку файла и комментарии над метками («The blocks of the README») —
    о README и двух его страницах.
- [ ] **Шаг 2. Убедиться, что он краснеет:** тот же прогон падает
  с `PathNotFoundException` на `doc/why.md`.
- [ ] **Шаг 3. Перенести разделы.** `doc/why.md`: `# Why a job`, вступление
  в одну-две фразы (что делает задача, чего не делают `Future`, флаг
  и `CancelableOperation`, и пример, где она делает всё сразу), затем оба
  раздела как есть; ссылки — по «Общим ограничениям», в том числе
  `[solo](#solo)` → `[solo](../README.md#solo)`. В «Guides» первой строкой:
  `| [Why a job](doc/why.md) | What a job adds to a Future,
  a flag and CancelableOperation, and a fuller example |` (имена — в бэктиках).
  То же в переводе.
- [ ] **Шаг 4. Комментарии и пара.** `example/example.dart:60`:
  `/// The job of "A fuller example" on doc/why.md.`;
  `test/cleanup_test.dart:719`: «The pattern of the fuller example on the why
  page». `PAIRS` — пара `why.md` первой среди страниц ядра; сайт —
  `page('async_job/why', 'Why a job', 'Зачем задача'),` сразу после
  `page('async_job', 'Overview', 'Обзор')`.
- [ ] **Шаг 5. Зелёный** — те же команды, что в шаге 6 задачи 1, линтеры —
  на `docs/ru/async_job/why.md`.
- [ ] **Шаг 6. Коммит**
  `docs: move "Why" and the fuller example to a core page of their own`.

### Задача 3. Вход: вступление, Install, Quick start

**Файлы:**
- Изменить: `packages/async_job/README.md`, `packages/async_job/README.ru.md`,
  `packages/async_job/example/quick_start.dart`,
  `packages/async_job/test/readme_recipe_test.dart`

**Интерфейсы:**
- Потребляет: `whyPages`, `referencePages`, `quotedOutputs(page, count)`.
- Даёт: Quick start печатает последней строкой `cancelled: manual`; выражение
  `switch` в нём начинается строкой `print(switch (await outcome) {`.

- [ ] **Шаг 1. Тесты входа.** В `readme_recipe_test.dart`, рядом с тестом Quick
  start:
  - `'the Quick start earns every line of it'`: вместо
    `quotedAfter(page, 'print(job.outcome);')` —
    `printed.last == 'cancelled: manual'`
    и `printed.join('\n') == quotedOutputs(page, 1).single`.
  - `'the Quick start takes done first,
    so a failure before the cancellation reaches it'`: тело Quick start
    с `Database.openError = StateError('disk gone')`,
    `final outcome = job.done;` сразу после конструктора, ожидание 50 мс,
    `cancel()`, `switch` как в README; `zoneErrorsOf` пуст, напечатано
    `failed: Bad state: disk gone`.
  - `'the entry names both pages before Install'`: для каждой страницы
    `readmes` текст до `## Install` (`## Установка`) содержит ссылки
    на `why.md` и на `reference.md`.
  - `'the entry speaks without the words of the model'`: проза README
    до `## Guides` (`## Страницы`), без блоков кода, не совпадает с
    `RegExp(r'observ|answer for|the zone|#four-words', caseSensitive: false)`;
    перевода — с `RegExp(r'наблюда|отвечает
    за|(?<![а-яё])зон[аеуы](?![а-яё])|#четыре-слова')`: `\b` в Dart знает
    только латинские буквы.
  - `'the entry fits two screens'`: в `README.md` строк до `## Guides` —
    не больше 120, до раздела после Quick start — не больше 90.
  - `'cancelled next to its constructor…'`: регулярку `started: false`
    по страницам убрать — фраза уходит из README; сама проверка поведения
    остаётся.
- [ ] **Шаг 2. Убедиться, что краснеют** первый, третий, четвёртый и пятый.
  Второй проверяет форму на нынешнем ядре и зеленеет сразу: это проверка того,
  что обещает абзац, а не кода, — так и записать в журнал.
- [ ] **Шаг 3. Переписать вход.**
  - Вступление: два нынешних абзаца и третий — по фразе о каждой новой странице
    со ссылкой.
  - Install: `sh`, фраза о плагине, которая говорит и «name it», и «turn its
    lints on by name» со ссылкой на его Install, блок `yaml`. Фраза о `solo`
    и `solo_lints` уходит в раздел `## solo` README.
  - Quick start: блок как в `example/quick_start.dart` после шага 4; абзац под
    выводом — `ctx.join` дождался чтения; `cancel()` вернулся, когда задача
    кончилась вместе с уборкой; `done` взят рядом с конструктором, и провал
    до отмены приходит в `switch`, а не роняет программу; тело стартует
    на следующей микрозадаче, поэтому блок сначала ждёт. Фраза о «Four words»
    и о `started: false` уходит.
  - Перевод — тем же.
- [ ] **Шаг 4. Пример.** `example/quick_start.dart` между метками:
  `final outcome = job.done;` сразу после `Job(…)`, в конце
  `print(switch (await outcome) { Done() => 'read',
  Failed(:final error) => 'failed: $error',
  Cancelled(:final reason) => 'cancelled: $reason', });`.
- [ ] **Шаг 5. Зелёный:** `dart format`, `dart analyze --fatal-infos`,
  `dart test` всего пакета; `dart run example/quick_start.dart` печатает три
  строки вывода README; проверки из шага 6 задачи 1; линтеры на `README.ru.md`.
- [ ] **Шаг 6. Коммит** `docs: make the core README a short entry`.

### Задача 4. Раздел «Walking away from a call»

**Файлы:**
- Создать: `packages/async_job/example/walk_away.dart`
- Изменить: `packages/async_job/README.md`, `packages/async_job/README.ru.md`,
  `packages/async_job/test/readme_recipe_test.dart`

**Интерфейсы:**
- Потребляет: `quotedOutputs(page, 2)`, тест `'and each of them runs whole…'`
  из задачи 2.
- Даёт: `example/walk_away.dart` с `Future<void> main()` между метками
  `// README: begin/end` и функцией `Future<String> fetchQuote()`: печатает
  `request sent`, через 100 мс — `quote answered` и возвращает строку; сама
  не бросает.

- [ ] **Шаг 1. Тесты.**
  - `'walking away from a call returns before the call ends'`: запуск
    `walk_away.main()` на `fakeAsync` с перехватом `print`, у каждой строки —
    `async.elapsed`; напечатано `quotedOutputs(page, 2).last` каждой страницы
    `readmes`; `Cancelled(manual)` — на 50 мс, `quote answered` — на 100.
  - Тест Quick start снова берёт `quotedOutputs(page, 2).first`.
  - `'the read of the Quick start under abandonable ends on a closed
    database'`: тело Quick start с `ctx.abandonable(db.readAll)`; отмена на 50
    мс; `Database.events == ['opened', 'closed', 'read']`.
  - `'an error the abandoned call throws later reaches the zone,
    done taken first'`: `ctx.abandonable` над вызовом, который бросает
    `StateError` на 100 мс; `done` взят сразу, отмена на 50 мс; `zoneErrorsOf`
    даёт `['Bad state: …']`, исход — `Cancelled(manual)`.
  - `'and each of them runs whole…'`: блоки README сверяются с метками
    `quick_start.dart`, затем `walk_away.dart`; `codeMissingFrom('README.md',
    …, alsoIn: ['example/quick_start.dart', 'example/walk_away.dart'])`.
- [ ] **Шаг 2. Убедиться, что краснеют** первый и четвёртый (нет файла
  и блока); второй и третий проверяют поведение ядра и зеленеют сразу —
  записать как проверку оговорок.
- [ ] **Шаг 3. Пример** `example/walk_away.dart`: между метками — `main`
  с `Job<String>((ctx) => ctx.abandonable(fetchQuote))`, `done` сразу, ожидание
  50 мс, `await job.cancel()`, `print(await outcome)`.
- [ ] **Шаг 4. Раздел README** `## Walking away from a call` после Quick start,
  открывается блоком; фраза о `example/walk_away.dart`; вывод `text`
  (`request sent`, `Cancelled(manual)`, `quote answered`); абзац из четырёх
  фраз: `abandonable` перестаёт ждать, вызов идёт дальше, `cancel()` вернулся
  раньше ответа, в отличие от `join` Quick start; не для вызова на ресурсе,
  который закрывает уборка — чтение Quick start кончилось бы на закрытой базе;
  запрос, который умеет прерываться, — через `ctx.onCancel` и `ctx.join`,
  ссылкой на `doc/cancellation.md#a-token-through-oncancel`; ошибку, брошенную
  вызовом после конца задачи, никто не ждёт, и она приходит необработанной
  ошибкой, ссылкой на `doc/errors.md#where-errors-go`. Перевод —
  `## Уйти от вызова`, тем же.
- [ ] **Шаг 5. Зелёный** — как шаг 5 задачи 3, плюс
  `dart run example/walk_away.dart` и он же на полу:
  `~/fvm/versions/3.38.1/bin/dart run example/walk_away.dart` — три строки
  вывода, код 0.
- [ ] **Шаг 6. Коммит** `docs: show ctx.abandonable in the core README`.

### Задача 5. Записи и полная проверка

**Файлы:**
- Изменить: `packages/async_job/CHANGELOG.md`,
  `docs/ru/async_job/CHANGELOG.md`, `docs/settled.md` (решение 77),
  `docs/handoff.md`, шапки записей дизайна и плана

- [ ] **Шаг 1. CHANGELOG.** В «Unreleased» → «Documentation» одна фраза: README
  стал коротким входом с разделом об `ctx.abandonable`; «Why» и «A fuller
  example» ушли на [Why a job](doc/why.md), таблица контекста и «Four words» —
  на [Reference](doc/reference.md). Перевод — тем же.
- [ ] **Шаг 2. Решение 77** переписать на месте, в последней форме, как велит
  шапка `docs/settled.md`: «README `async_job` — короткий вход; "Why" и "A
  fuller example" — на `doc/why.md`, таблица контекста и "Four words" —
  на `doc/reference.md`»; в скобках — прежние источники и «пересмотрено
  2026-11-05, `2026-11-04-core-readme-entry-design.md`», как у решения 78.
- [ ] **Шаг 3. Handoff:** строка `readme_recipe_test.dart` в перечне страничных
  тестов — «для README и страниц "Why a job" и "Reference"»; абзац «Сейчас» —
  о состоянии работы.
- [ ] **Шаг 4. Полная проверка.** В `packages/async_job`, `packages/solo`,
  `packages/async_job_lints`:
  `dart format --output=none --set-exit-if-changed .`,
  `dart analyze --fatal-infos`, `dart test`. Из корня — все семь питоновских
  проверок задания `docs` с их сторожами. Раскладка пола в каталог вне
  репозитория, фоновым запуском:
  `python3 tool/archive_floor.py stage <каталог>`
  и `PATH=~/fvm/versions/3.38.1/bin:$PATH python3 tool/archive_floor.py run
  <каталог>` — `async_job` и его пример зелёные; сторож README в архиве читает
  одни оригиналы.
- [ ] **Шаг 5. Коммит**
  `docs: record the core entry in the changelog and the decisions`.
