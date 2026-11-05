# Вход у `async_job`: README на два с половиной экрана, план

> **Состояние на 2026-11-05:** план написан по дизайну, одобренному владельцем
> 2026-11-05, и прошёл независимое ревью Opus: все находки приняты, задачи
> поправлены по ним (раздел «Ревью плана»). Ждёт слова владельца.
> **Что это:** план короткого README ядра: две новые страницы «Why a job»
> и «Reference», новый Quick start, раздел об `abandonable`, переводы, сайт,
> ссылки и сторожа.
> **Связанные записи:** `2026-11-04-core-readme-entry-design.md`,
> `2026-10-30-pub-dev-landscape-review.md`.

> **Исполнителю:** скилл `superpowers:executing-plans` или
> `superpowers:subagent-driven-development`; шаги — флажки `- [ ]`. Перед
> текстом страниц — скилл `doc-reader`, перед кодом Dart — `dart`.

**Цель:** читатель pub.dev получает в README ядра короткий вход — `Job`,
`ctx.join`, `ctx.abandonable`, `dispose`, `cancel()`, исход, — код которого,
скопированный как есть, не теряет провал до отмены и называет, куда уходит
ошибка после неё, а всё, что уходит из README, живёт целиком на двух страницах
ядра.

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
- Внутри переехавшего текста правятся только ссылки: `doc/x.md` → `x.md`;
  в переводе `../../docs/ru/async_job/x.md` → `x.md`. Ссылка на README своего
  пакета — адресом `blob/main`, как на `packages/solo/doc/jobs.md:12`
  и `docs/ru/solo/jobs.md:12`: `[solo](#solo)` →
  `https://github.com/vi-k/solo/blob/main/packages/async_job/README.md#solo`,
  в переводе — на `README.ru.md#solo`.
- README через Quick start — не больше 95 строк исходника, до `## Guides` —
  не больше 125 (цель дизайна исправлена этим планом, «Поправка дизайна» ниже).
- Проза README до `## Guides`, без блоков кода и с пробелами, сведёнными
  к одному, не совпадает
  с `RegExp(r'observ|answer(?:s|ed|ing)? for|\bzones?\b|#four-words',
  caseSensitive: false)`; проза перевода до `## Страницы` —
  с `RegExp(r'наблюда|отве(?:т|ча)[а-яё]*
  за|(?<![а-яё])зон(?:а|е|у|ы|ой)?(?![а-яё])|#четыре-слова',
  caseSensitive: false)`: `\b` в Dart знает только латинские буквы.
- Английские ссылки из других пакетов — абсолютные `blob/main`, решение 74.
  Русские со страниц `docs/ru/solo/` — относительные:
  `../async_job/reference.md#контекст-коротко`;
  `async_job_lints/README.ru.md` —
  `https://github.com/vi-k/solo/blob/main/docs/ru/async_job/reference.md#контекст-коротко`.
- Перевод — тем же коммитом, что и оригинал; после правки русского текста —
  линтер `humanizer--ru` (только `ERROR`), `bare_names.py` и `jargon.py`. Код
  во фрагментах перевода, строки вывода включительно (`'read'`,
  `'failed: $error'`, `'cancelled: $reason'`), остаётся английским: его сверяют
  `check_translations.py` и сторож вывода.
- «Зелёный» каждой задачи — из `packages/async_job`:
  `dart format --output=none --set-exit-if-changed .`,
  `dart analyze --fatal-infos`, `dart test`; из корня:
  `python3 tool/check_translations.py`, `python3 tool/check_links.py`,
  `python3 tool/check_doc_shape.py`, `python3 tool/reflow.py --check`,
  `python3 tool/check_line_width.py`, `python3 tool/build_site.py`,
  `python3 -m unittest tool/build_site_test.py`. Задача, которая правит другой
  пакет, гоняет те же три команды Dart и в нём.
- Комментарии `readme_recipe_test.dart`, которые называют README, проходятся
  поиском по слову `README` в той задаче, которая уносит их текст: шапка,
  строки около 13–16, 136, 157, 171, 461, 512, 939, 1069, 1547.
- Нового API нет; `solo` не меняется, кроме ссылок и прозы рядом с ними.

## Поправка дизайна

Цель «README до "Guides" — не больше 90 строк» не сходится с самим дизайном.
Сейчас до «Guides» 305 строк и 2058 слов. Черновик входа по составу из дизайна,
сделанный при плане, дал 85 строк через Quick start и 115 до «Guides»; черновик
ревьюера плана по тому же составу — 88 и 120, 649 слов: вступление с фразой
о новых страницах 20, Install 20, Quick start со `switch` 48, раздел
об `abandonable` с блоком, выводом и абзацем 32. Фраза о поздней ошибке под
Quick start, находка I2 ревью плана, прибавляет ещё около двух. Сокращения
из ревью дизайна дают три-четыре строки, а не двадцать пять.

Мерка плана: через Quick start — не больше 95 строк, до «Guides» — не больше
125; держит её сторож README. Это около двух с половиной экранов pub.dev
(оценка ревьюера, не замер), а не «один-два», как обещал дизайн. Уложиться
в два экрана можно, только сократив раздел об `abandonable` — например, сняв
его блок вывода и оставив ответ в комментарии кода; план этого не делает,
владелец решает по отчёту о плане.

Вторая поправка — о цели «код входа не роняет программу на провале». Ошибка
вызова, который падает уже после отмены, не становится исходом: задача
кончается `Cancelled`, а ошибка уходит необработанной, и у `join` Quick start
так же, как у `abandonable` (строка 35 `doc/error-rules.md`, зонд ревью плана
I2). Вход не может её поймать, не вводя словаря модели; он называет её одной
фразой со ссылкой на «Where errors go», общей для обоих вызовов.

## Куда смотреть ревьюеру

Входы и случаи, которых задачи плана иначе не проверили бы, — у каждого свой
тест в задаче, которая владеет кодом:

1. Quick start или раздел об `abandonable` в README вернутся к чтению `done`
   после `cancel()`: проверка порядка строк блока на каждой странице `readmes`
   краснеет — тест в задачах 3 и 4. Поведение формы на провале до отмены держит
   отдельный тест копии тела в задаче 3.
2. Чтение Quick start падает уже после отмены, `done` взят сразу: ошибка
   приходит в зону, исход — `cancelled: manual` — тест в задаче 3; на нём стоит
   фраза README о поздней ошибке.
3. Брошенный через `ctx.abandonable` вызов падает после отмены, `done` взят
   сразу: ошибка всё равно приходит в зону — тест в задаче 4.
4. Чтение Quick start под `ctx.abandonable`: база закрыта раньше, чем чтение
   кончилось, — тест в задаче 4; на нём стоит фраза о ресурсе.
5. Опубликованная ссылка на `#the-context-at-a-glance` открывает README сверху:
   README называет обе новые страницы до `## Install` — тест в задаче 3.
6. Архив без каталога `docs/ru`: сторож читает только оригиналы новых страниц
   и не падает — раскладка `floor` в задаче 5.

---

### Задача 1. Справочник ядра: «The context at a glance» и «Four words»

**Файлы:**
- Создать: `packages/async_job/doc/reference.md`,
  `docs/ru/async_job/reference.md`
- Изменить: `packages/async_job/README.md`, `packages/async_job/README.ru.md`
  (разделы уходят; строка `Guides`; ссылка Quick start на «Four words»),
  `packages/async_job/test/readme_recipe_test.dart`,
  `packages/solo/doc/reference.md:8-9,106-107`,
  `docs/ru/solo/reference.md:8-9,107-108`,
  `packages/async_job_lints/README.md:185`,
  `packages/async_job_lints/README.ru.md:190`, `tool/check_translations.py`
  (`PAIRS`), `site/astro.config.mjs`

**Интерфейсы:**
- Даёт: в сторожe список `referencePages`: `['doc/reference.md', if
  (Directory('../../docs/ru').existsSync())
  '../../docs/ru/async_job/reference.md']`, по образцу `versions`
  в `test/errors_rakes_test.dart:38-45`, с комментарием о том, почему каталог,
  а не файл.

- [ ] **Шаг 1. Сторож читает таблицу со справочника.** В группе
  `'the context at a glance'` все `readmes` заменить на `referencePages`;
  `contextTable('README.md')` — на `contextTable('doc/reference.md')`; проверка
  перевода около строки 1145 — `referencePages.length > 1` и путь перевода;
  ключи карт в тестах `'the notes say…'` и `'the errors of unattended work…'` —
  пути двух страниц справочника. Комментарии группы — о странице справочника.
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
    на `../async_job/reference.md#контекст-коротко`, проза рядом (строки 9
    и 108) — «справочника `async_job`».
  - `packages/async_job_lints/README.md:185` и перевод: адрес по «Общим
    ограничениям», и обе ссылки фразы называют свою страницу: «See
    [The context at a glance](…) on the reference page of `async_job` and
    [Letting time pass](…) on its time page».
- [ ] **Шаг 5. Пара, сайт.** В `PAIRS` `tool/check_translations.py` —
  `(…/"async_job"/"doc"/"reference.md", …/"ru"/"async_job"/"reference.md")`
  последней парой ядра. В `site/astro.config.mjs` перед
  `changelog('async_job')`:
  `page('async_job/reference', 'Reference', 'Справочник'),`.
- [ ] **Шаг 6. Зелёный** по «Общим ограничениям», в `packages/async_job`,
  `packages/solo` и `packages/async_job_lints`; линтеры перевода
  на `docs/ru/async_job/reference.md` и правленых строках
  `docs/ru/solo/reference.md`, `async_job_lints/README.ru.md`.
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
  - Шапка файла и комментарии о README, которые теперь говорят о туре, —
    о README и двух его страницах (поиск по «Общим ограничениям»).
- [ ] **Шаг 2. Убедиться, что он краснеет:** тот же прогон падает
  с `PathNotFoundException` на `doc/why.md`.
- [ ] **Шаг 3. Перенести разделы.** `doc/why.md`: `# Why a job`, вступление
  в одну-две фразы (что делает задача, чего не делают `Future`, флаг
  и `CancelableOperation`, и пример, где она делает всё сразу), затем оба
  раздела как есть; ссылки — по «Общим ограничениям». В «Guides» первой
  строкой: `| [Why a job](doc/why.md) | What a job adds to a Future,
  a flag and CancelableOperation, and a fuller example |` (имена — в бэктиках).
  То же в переводе.
- [ ] **Шаг 4. Комментарии и пара.** `example/example.dart:60`:
  `/// The job of "A fuller example" on doc/why.md.`;
  `test/cleanup_test.dart:719`: «The pattern of the fuller example on the why
  page». `PAIRS` — пара `why.md` первой среди страниц ядра; сайт —
  `page('async_job/why', 'Why a job', 'Зачем задача'),` сразу после
  `page('async_job', 'Overview', 'Обзор')`.
- [ ] **Шаг 5. Зелёный** по «Общим ограничениям»; линтеры перевода
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
  `switch` в нём начинается строкой `print(switch (await outcome) {`; помощник
  `void expectDoneTakenFirst(String block, String page)` — строка
  `final outcome = job.done;` идёт сразу за `});` конструктора `Job` и раньше
  первой строки с `await`.

- [ ] **Шаг 1. Тесты входа.** В `readme_recipe_test.dart`, рядом с тестом Quick
  start:
  1. `'the Quick start earns every line of it'`: вместо
     `quotedAfter(page, 'print(job.outcome);')` —
     `printed.join('\n') == quotedOutputs(page, 1).single`, без литерала
     вывода.
  2. `'the Quick start takes done next to its constructor'`: для каждой
     страницы `readmes` — `expectDoneTakenFirst` на блоке Quick start.
  3. `'taken first,
     done hands a failure before the cancellation to the switch'`: тело Quick
     start с `Database.openError = StateError('disk gone')`,
     `final outcome = job.done;` сразу после конструктора, ожидание 50 мс,
     `cancel()`, `switch` как в README; `zoneErrorsOf` пуст, напечатано
     `failed: Bad state: disk gone`.
  4. `'a read that fails after the cancellation reaches the zone,
     done taken first'`: то же тело с `Database.readError`, чтение кончается
     на 120 мс, отмена на 50; `zoneErrorsOf` даёт `['Bad state: disk gone']`,
     напечатано `cancelled: manual`.
  5. `'the entry names both pages before Install'`: для каждой страницы
     `readmes` текст до `## Install` (`## Установка`) содержит ссылки
     на `why.md` и на `reference.md`.
  6. `'the entry speaks without the words of the model'`: регулярки «Общих
     ограничений» по прозе README и перевода.
  7. `'the entry stays within 95 lines through the Quick start and 125 before
     Guides'`: счёт строк `README.md` до `## Guides` и до заголовка, который
     идёт за Quick start (или до `## Guides`, если его нет).
  8. `'cancelled next to its constructor…'`: регулярку `started: false`
     по страницам убрать — фраза уходит из README; проверка поведения остаётся.
     Шапку файла (строки около 13–16) поправить: исход задачи, отменённой
     до старта, README больше не цитирует.
- [ ] **Шаг 2. Убедиться, что краснеют** 1, 2, 5 и 6. Тесты 3 и 4 проверяют
  поведение ядра, обещанное абзацем, и зеленеют сразу; тест 7 зеленеет сразу
  (после задач 1–2 в README 81 строка) и держит будущий рост — так и записать
  в журнал.
- [ ] **Шаг 3. Переписать вход.**
  - Вступление: два нынешних абзаца и третий — по фразе о каждой новой странице
    со ссылкой.
  - Install: `sh`, фраза о плагине, которая говорит и «name it», и «turn its
    lints on by name» со ссылкой на его Install, блок `yaml`. Фраза о `solo`
    и `solo_lints` уходит в раздел `## solo` README.
  - Quick start: блок как в `example/quick_start.dart` после шага 4; абзац под
    выводом — `ctx.join` дождался чтения; `cancel()` вернулся, когда задача
    кончилась вместе с уборкой; `done` взят рядом с конструктором, и провал
    до отмены приходит в `switch`, а не роняет программу; ошибка вызова,
    брошенная уже после отмены, исходом не становится — задача кончается
    `Cancelled`, а ошибка приходит необработанной, ссылкой
    на `doc/errors.md#where-errors-go`; тело стартует на следующей микрозадаче,
    поэтому блок сначала ждёт. Фраза о «Four words» и о `started: false`
    уходит.
  - Перевод — тем же.
- [ ] **Шаг 4. Пример.** `example/quick_start.dart` между метками:
  `final outcome = job.done;` сразу после `Job(…)`, в конце
  `print(switch (await outcome) { Done() => 'read',
  Failed(:final error) => 'failed: $error',
  Cancelled(:final reason) => 'cancelled: $reason', });`.
- [ ] **Шаг 5. Зелёный** по «Общим ограничениям»;
  `dart run example/quick_start.dart` печатает три строки вывода README;
  линтеры на `README.ru.md`.
- [ ] **Шаг 6. Коммит** `docs: make the core README a short entry`.

### Задача 4. Раздел «Walking away from a call»

**Файлы:**
- Создать: `packages/async_job/example/walk_away.dart`
- Изменить: `packages/async_job/README.md`, `packages/async_job/README.ru.md`,
  `packages/async_job/test/readme_recipe_test.dart`

**Интерфейсы:**
- Потребляет: `quotedOutputs(page, 2)`, `expectDoneTakenFirst`, тест
  `'and each of them runs whole…'` из задачи 2.
- Даёт: `example/walk_away.dart` с `Future<void> main()` между метками
  `// README: begin/end` и функцией `Future<String> fetchQuote()` с dartdoc:
  печатает `request sent`, через 100 мс — `quote answered` и возвращает строку;
  сама не бросает.

- [ ] **Шаг 1. Тесты.**
  1. `'walking away from a call returns before the call ends'`: запуск
     `walk_away.main()` на `fakeAsync` с перехватом `print`, у каждой строки —
     `async.elapsed`; напечатано `quotedOutputs(page, 2).last` каждой страницы
     `readmes`; `Cancelled(manual)` — на 50 мс, `quote answered` — на 100.
  2. Тест Quick start берёт `quotedOutputs(page, 2).first`.
  3. `'the walk away takes done next to its constructor'`:
     `expectDoneTakenFirst` на блоке раздела каждой страницы `readmes`.
  4. `'the read of the Quick start under abandonable ends on a closed
     database'`: тело Quick start с `ctx.abandonable(db.readAll)`; отмена на 50
     мс; `Database.events == ['opened', 'closed', 'read']`.
  5. `'an error the abandoned call throws later reaches the zone,
     done taken first'`: `ctx.abandonable` над вызовом, который бросает
     `StateError` на 100 мс; `done` взят сразу, отмена на 50 мс; `zoneErrorsOf`
     даёт `['Bad state: …']`, исход — `Cancelled(manual)`.
  6. `'and each of them runs whole…'`: блоки README сверяются с метками
     `quick_start.dart`, затем `walk_away.dart`; `codeMissingFrom('README.md',
     …, alsoIn: ['example/quick_start.dart', 'example/walk_away.dart'])`.
- [ ] **Шаг 2. Убедиться, что краснеет.** Тест импортирует
  `../example/walk_away.dart`, и пока файла нет, `readme_recipe_test.dart`
  не загружается вовсе: красный шаг — ошибка загрузки. Тесты 4 и 5 проверяют
  поведение ядра и после шага 3 зеленеют без правки README — записать как
  проверку оговорок.
- [ ] **Шаг 3. Пример** `example/walk_away.dart`: между метками — `main`
  с `Job<String>((ctx) => ctx.abandonable(fetchQuote))`, `done` сразу, ожидание
  50 мс, `await job.cancel()`, `print(await outcome)`. Исход печатается
  целиком, без `switch`: Quick start уже показал разбор, а четыре строки
  `switch` вывели бы вход за мерку.
- [ ] **Шаг 4. Раздел README** `## Walking away from a call` после Quick start,
  открывается блоком; фраза о `example/walk_away.dart`; вывод `text`
  (`request sent`, `Cancelled(manual)`, `quote answered`); абзац: `abandonable`
  перестаёт ждать, вызов идёт дальше, `cancel()` вернулся раньше ответа,
  в отличие от `join` Quick start; не для вызова на ресурсе, который закрывает
  уборка, — чтение Quick start кончилось бы на закрытой базе; запрос, который
  умеет прерываться, — через `ctx.onCancel` и `ctx.join`, ссылкой
  на `doc/cancellation.md#a-token-through-oncancel`; ошибка, которую вызов
  бросит позже, уходит так же, как поздняя ошибка Quick start, — коротко, без
  второй ссылки. Перевод — `## Уйти от вызова`, тем же.
- [ ] **Шаг 5. Зелёный** по «Общим ограничениям», плюс
  `dart run example/walk_away.dart` и он же на полу:
  `~/fvm/versions/3.38.1/bin/dart run example/walk_away.dart` — три строки
  вывода, код 0.
- [ ] **Шаг 6. Коммит** `docs: show ctx.abandonable in the core README`.

### Задача 5. Записи и полная проверка

**Файлы:**
- Изменить: `packages/async_job/CHANGELOG.md`,
  `docs/ru/async_job/CHANGELOG.md`, `packages/solo/CHANGELOG.md`,
  `docs/ru/solo/CHANGELOG.md`, `packages/async_job_lints/CHANGELOG.md` и его
  перевод, если он есть в `PAIRS`, `docs/settled.md` (решение 77),
  `docs/handoff.md`, шапки записей дизайна и плана

- [ ] **Шаг 1. CHANGELOG ядра.** В «Unreleased» → «Documentation»:
  - нынешний пункт о плагине в Install поправить: фраза о `solo_lints` теперь
    в разделе «solo»;
  - новая фраза: README стал коротким входом с разделом об `ctx.abandonable`;
    «Why» и «A fuller example» ушли на [Why a job](doc/why.md), таблица
    контекста и «Four words» — на [Reference](doc/reference.md). Перевод —
    тем же, ссылки относительные `why.md` и `reference.md`, как у соседних
    пунктов.
- [ ] **Шаг 2. CHANGELOG `solo` и `async_job_lints`.** В «Unreleased» →
  «Documentation» по фразе: ссылки на таблицу контекста ведут на справочник
  `async_job`. Переводы — тем же.
- [ ] **Шаг 3. Решение 77** переписать на месте, в последней форме, как велит
  шапка `docs/settled.md`: «README `async_job` — короткий вход; "Why" и "A
  fuller example" — на `doc/why.md`, таблица контекста и "Four words" —
  на `doc/reference.md`»; в скобках — прежние источники и «пересмотрено
  2026-11-05, `2026-11-04-core-readme-entry-design.md`», как у решения 78.
- [ ] **Шаг 4. Handoff:**
  - строка `readme_recipe_test.dart` в перечне страничных тестов — «для README
    и страниц "Why a job" и "Reference"»;
  - раздел «Требования к README, которые нужно сохранить»: что из него теперь
    живёт на `doc/why.md` (`discard`, пример миграции, границы ядра и `solo`),
    сказать там; число пар — по `PAIRS` после работы (47);
  - абзац «Сейчас» — о состоянии работы.
- [ ] **Шаг 5. Полная проверка и коммит.** «Зелёный» по «Общим ограничениям»
  в `packages/async_job`, `packages/solo`, `packages/async_job_lints`, все
  питоновские проверки задания `docs` с их сторожами. Коммит
  `docs: record the core entry in the changelog and the decisions`.
- [ ] **Шаг 6. Пол — после коммита, в копии.** `dart pub publish --dry-run`
  на изменённых под гитом файлах кончается предупреждением, и `stage` падает.
  Копия на коммите без ветки (`git worktree add --detach <копия> HEAD`), в ней
  фоновым запуском `python3 tool/archive_floor.py stage <каталог>`
  и `PATH=~/fvm/versions/3.38.1/bin:$PATH python3 tool/archive_floor.py run
  <каталог>`, оба каталога вне репозитория. `async_job` и его пример зелёные;
  сторож README в архиве читает одни оригиналы. Красный пол — исправление
  отдельным коммитом и повтор.

## Ревью плана

Независимое ревью Opus по копии дерева на 806d6849, с первой редакцией плана;
строки в находках — по ней. Ревьюер гонял зонды на Dart 3.13 и на полу 3.10.0
против ядра из копии; репозиторий не тронут. Находки ниже — его текст,
вердикт — отдельным абзацем после каждой. I6 я проверил счётом строк README:
`305 2058` до «Guides»; I2 — своим зондом: `join` над чтением, которое падает
на 120 мс, отмена на 50, `done` взят сразу, — `read failed`,
`ZONE: Bad state: disk gone`, `cancelled: manual`; строку 35
`doc/error-rules.md` — по файлу. Все находки приняты, план выше переписан
по ним.

### Итог ревьюера

План в целом можно исполнять. Номера строк, имена тестов и помощников, пути
и порядок задач я проверил. Коммиты задач 1–4 получаются зелёными, если каждую
задачу довести до шага «Зелёный». Critical-находок нет.

Есть шесть Important-находок:
- два сторожа держат не то, что о них сказано: проверка «done взят первым»
  и регулярка словаря;
- вход остаётся с не названным путём к краху, это поздняя ошибка через `join`;
- у задач 3 и 4 неверно описан шаг «краснеют»;
- у задачи 5 пол нельзя снимать на грязном дереве;
- в «Поправке дизайна» неверная исходная цифра, а у новой мерки нет запаса.

Сама поправка по существу честная: 90 строк до «Guides» без раздела
об `abandonable` не набрать.

Проверить `git status` копии я не смог: харнесс отказывает любой git-команде
вне своей рабочей копии. Мои записи шли только в каталог зондов. Одно
исключение: `importlib` при чтении `PAIRS` создал в копии
`tool/__pycache__/check_translations.cpython-314.pyc`, я его удалил вместе
с каталогом. Каталог и так под `.gitignore`. Фоновых задач я не запускал.

### Important

**I1. Проверка «done взят сразу» держит копию тела в тесте, а не README.**

- **Где:** задача 3, шаг 1, тест `'the Quick start takes done first,
  so a failure before the cancellation reaches it'`. Пункт 1 «Куда смотреть
  ревьюеру» говорит, что сама программа Quick start печатает `failed: …`.
- **Подтверждение:** зонд гонял тело Quick start на `fakeAsync` в двух
  вариантах: `done` взят сразу и `done` прочитан после `cancel()`.
  На счастливом пути вывод одинаковый:
  ```
  late=false happy printed=[cancelled: manual] events=[opened, read, closed]
  late=true happy printed=[cancelled: manual] events=[opened, read, closed]
  ```
  Значит, тест `'the Quick start earns every line of it'` (`printed.last`,
  `quotedOutputs`, `closedAt` 120 мс) не заметит, если README или
  `example/quick_start.dart` вернут чтение `done` после `cancel()`. Новый тест
  гоняет свою копию тела и тоже останется зелёным. Анти-цель «исход прочитан
  так, что провал до отмены уходит мимо него» при этом не держит ни один
  сторож. Сама копия ведёт себя, как обещано:
  ```
  late=false printed=[failed: Bad state: disk gone] zone=[]
  late=true  printed=[failed: Bad state: disk gone] zone=[Bad state: disk gone]
  ```
- **Что предложить:** добавить проверку формы блока на каждой странице
  `readmes`. В блоке Quick start строка `final outcome = job.done;` стоит
  до первого `await Future<void>.delayed`, сразу за `});` конструктора. Пункт 1
  «Куда смотреть» переписать: тест копии держит поведение ядра, форму README
  держит проверка порядка строк.

Вердикт: принята, как предложено. Помощник `expectDoneTakenFirst` проверяет
порядок строк блока на каждой странице `readmes` — в задаче 3 для Quick start,
в задаче 4 для нового раздела; тест копии тела остался и держит поведение;
пункт 1 «Куда смотреть ревьюеру» переписан.

**I2. Ошибка вызова через `join` после отмены роняет программу, а вход называет
поздний путь только у `abandonable`.**

- **Где:** задача 4, шаг 4. Там фраза «ошибку, брошенную вызовом после конца
  задачи…» стоит только под `abandonable`, а рядом противопоставление
  «в отличие от `join` Quick start». Абзац Quick start в задаче 3 говорит
  только о провале до отмены.
- **Подтверждение:** зонд по форме Quick start: `done` взят сразу, `readAll`
  бросает на 120 мс, отмена на 50 мс:
  ```
  read-after-cancel printed=[cancelled: manual] zone=[Bad state: disk gone] events=[opened, closed]
  ```
  Это строка 35 `doc/error-rules.md`: «The body's, and the job ends
  `Cancelled` | `onError`, then the answer | The zone». Путь `onCancel`
  + `join`, который советует сам раздел, ведёт туда же.
  `doc/cancellation.md:185-191`: «Each stop would reach the crash reports of
  the app as a failure», если не задан `Job.isCancellationError`. Цель дизайна
  оговорена словами «провал до отмены», так что это не нарушение буквы. Но
  противопоставление с `join` читатель поймёт так, что `join` от этого
  защищён.
- **Что предложить:** сделать фразу о поздней ошибке общей для обоих вызовов,
  без новых строк. Например: «An error a call throws once the job is
  cancelled — the read of the Quick start as well as this one — has nobody
  waiting for it and arrives as an uncaught error; see [Where errors go]».
  Добавить тест-оговорку по образцу зонда выше. Владельцу сказать, что дизайн
  этот путь не называл.

Вердикт: принята. Фраза о поздней ошибке встаёт под Quick start, со ссылкой
на «Where errors go», и держится тестом 4 задачи 3; раздел об `abandonable`
говорит коротко, что его поздняя ошибка уходит так же. Разошлось
с предложенным: фраза в Quick start прибавляет около двух строк, это учтено
в мерке. Цель дизайна о том, что вход не роняет программу, поправлена
в «Поправке дизайна», владелец слышит об этом в отчёте о плане.

**I3. Регулярки словаря пропускают перенос строки, заглавную букву и падежи.**

- **Где:** задача 3, шаг 1, тест
  `'the entry speaks without the words of the model'`, и «Общие ограничения».
- **Подтверждение:** зонд на Dart 3.13 и на полу 3.10.0 с регулярками ровно
  из плана. Перенос в прозе ставит `reflow.py`, так что пара слов на стыке
  строк выпадает случайно.
  ```
  en the\nzone: false     en answer\nfor: false    en answered for: false   en a zone: false
  ru Зона: false          ru зоной: false          ru нет зон: false        ru Наблюдать провал: false
  ru отвечает\nза: false  ru Отвечает за: false    ru ответить за ошибку: false
  ```
  Русский термин модели в README.ru — «Ответить за ошибку» (строка 305),
  а «отвечает за» его не ловит. Lookbehind на полу работает, ложного
  срабатывания на «резона» нет.
- **Что предложить:** перед проверкой убрать блоки кода и свести пробельные
  символы к одному пробелу, как уже делают тесты `'the notes say…'`. Взять
  такие регулярки:
  ```dart
  RegExp(r'observ|answer(?:s|ed|ing)? for|\bzones?\b|#four-words', caseSensitive: false)
  RegExp(r'наблюда|отве(?:т|ча)[а-яё]* за|(?<![а-яё])зон(?:а|е|у|ы|ой)?(?![а-яё])|#четыре-слова', caseSensitive: false)
  ```
  Обе я прогнал по нынешним вступлению и Install README и перевода: совпадений
  `[]`. Нечувствительность к регистру для кириллицы работает и на 3.10.0:
  «Зона», «Наблюдать» и «Ответить за ошибку» дают `true`.

Вердикт: принята, как предложено: регулярки и сведение пробелов — в «Общих
ограничениях», тест 6 задачи 3 берёт их оттуда.

**I4. Шаги «краснеют» в задачах 3 и 4 описаны неверно.**

- **Где:** задача 3, шаг 2: «краснеют первый, третий, четвёртый и пятый».
  Задача 4, шаг 2: «краснеют первый и четвёртый… второй и третий… зеленеют
  сразу».
- **Подтверждение:**
  - Задача 3. После задач 1–2 в README остаются вступление, Install и Quick
    start, это строки 1–81 нынешнего README (`awk` до `## Quick start`/`## Why`
    даёт 81). До `## Guides` выходит 81 строка, то есть меньше и 90, и 120.
    Пятый тест, о длине, зелёный до правки.
  - Задача 4, первая проблема. В шаге 1 пять пунктов, а нумерация шага 2 их
    не совпадает. Пункт «Тест Quick start снова берёт
    `quotedOutputs(page, 2).first`» покраснеет: в README пока один блок `text`,
    а `quotedOutputs` требует ровно `count`.
  - Задача 4, вторая проблема. Тест импортирует `../example/walk_away.dart`,
    а `codeMissingFrom` читает его через `alsoIn`. Пока файла нет, весь
    `readme_recipe_test.dart` не загрузится, и «зеленеют сразу» не увидеть.
- **Что предложить:** в задаче 3 записать, что тест длины зелёный сразу
  и держит будущий рост. В задаче 4 начать с заготовки `example/walk_away.dart`
  или прямо сказать, что красный шаг — ошибка загрузки файла. Нумерацию
  поправить.

Вердикт: принята. Тесты шагов 1 задач 3 и 4 пронумерованы, шаги 2 называют
номера; тест длины записан зелёным сразу; красный шаг задачи 4 — ошибка
загрузки файла.

**I5. Задача 5, шаг 4: `archive_floor.py stage` до коммита упадёт.**

- **Где:** шаг 4 стоит раньше коммита из шага 5,
  а `packages/async_job/CHANGELOG.md` к этому моменту уже изменён.
- **Подтверждение:** `tool/archive_floor.py:245-250` берёт состав
  из `dart pub publish --dry-run` и падает, когда код возврата ненулевой.
  AGENTS.md говорит то же: «Dry-run, который кончился предупреждением, роняет
  шаг». На изменённые файлы под гитом dry-run даёт предупреждение. Это записано
  и в памяти проекта: «Пол до коммита — в копии».
- **Что предложить:** снимать пол после коммита задачи 5 или в копии на коммите
  без ветки, затем исправлять отдельным коммитом, если пол красный.

Вердикт: принята: шаг 6 задачи 5 снимает пол после коммита, в копии на коммите
без ветки; красный пол — отдельный коммит.

**I6. «Поправка дизайна»: неверная исходная цифра и нет запаса.**

- **Где:** план, строки 68–78. Дизайн, строки 41–47, а строка 42 повторяет
  «сейчас до „Guides“ их 235».
- **Подтверждение:**
  - `awk '/^## Guides/{exit}{print}' README.md | wc -lw` даёт `305 2058`. Слова
    (2058) верны, а строк 305, не 235. Цифры 235 и 236 — это строки
    до `## The context at a glance`.
  - Мой черновик входа по составу плана: нынешнее вступление и третий абзац
    о двух страницах, Install без фразы о `solo`, Quick start со `switch`
    и абзацем из четырёх мыслей, раздел с блоком, выводом, фразой о файле
    и абзацем из четырёх фраз с двумя ссылками. Разделы начинаются на строках
    21, 41, 89 и 121. По разделам выходит 20/20/48/32, итого **88 через Quick
    start и 120 до «Guides»**, 649 слов. У плана 85 и 115.
  - Мерка 90 держится с запасом в две строки, мерка 120 — без запаса. Если дать
    разделу `switch`, как в дизайне («тем же чтением исхода, что и Quick
    start»), прибавятся четыре строки и выйдет 124, красный.
  - Сокращения действительно дают около 3–4 строк: фраза о `solo` 2–3 строки,
    хвост о микрозадаче около одной. Довод плана здесь верен.
  - Тест называется `'the entry fits two screens'`, но держит 120 строк
    исходника с четырьмя блоками. По моей оценке (замера не было) это около 2,5
    экрана pub.dev, а не «один-два», как в handoff:130.
- **Что предложить:** исправить 235 на 305 в плане и дизайне. Записать в план
  счёт черновика по разделам. Назвать тест по тому, что он держит
  (`'the entry stays within 90 and 120 lines'`). Владельцу сказать прямо: вход
  теперь около двух с половиной экранов, а не два. Поправка честная в том, что
  90 до «Guides» без раздела об `abandonable` недостижимы, но не в цифрах.

Вердикт: принята. Цифра исправлена на 305 в плане и дизайне, счёт черновика
ревьюера по разделам записан в «Поправке дизайна». Разошлось с предложенным:
с фразой I2 мерка поднята до 95 и 125, чтобы у неё был запас в несколько строк;
тест назван по ней. Владелец слышит в отчёте о плане, что вход — около двух
с половиной экранов, и что вернуть два можно только за счёт раздела
об `abandonable`.

### Minor

- **M1. Задачи 1 и 2 правят Dart без формата и анализатора.** Шаг «Зелёный»
  требует только `dart test test/readme_recipe_test.dart`, хотя задачи меняют
  `readme_recipe_test.dart`, `example/example.dart` и `cleanup_test.dart`.
  По AGENTS.md нужны ещё `dart format` и `dart analyze --fatal-infos`. Шаги
  «Зелёный» задач 1–4 не называют и `reflow.py --check`
  с `check_line_width.py`, они есть только в «Общих ограничениях».

Вердикт: принята: «Зелёный» один на все задачи, в «Общих ограничениях»,
с форматом, анализатором, всем пакетом и проверками ширины.

- **M2. Неточные номера строк.** В файлах задачи 1 стоит
  `docs/ru/solo/reference.md:8,107`. Ссылки там на 8 и 107, а проза «README
  пакета `async_job`» — на строках 9 и 108.

Вердикт: принята, номера поправлены.

- **M3. Вид ссылки `#solo` на `doc/why.md` не выбран явно.**
  - Своё README со страниц `doc/` репозиторий везде ведёт адресом `blob/main`:
    `packages/solo/doc/jobs.md:12`, `state.md:610`, `vs-bloc.md:50`,
    `docs/ru/solo/jobs.md:12`. План берёт относительную `../README.md#solo`.
  - Для перевода план пишет «`check_links.py` решает». Но мой зонд показал, что
    `check_links.py` принимает оба вида: `../README.md#solo`,
    `../../../packages/async_job/README.ru.md#solo`
    и `https://github.com/vi-k/solo/blob/main/packages/async_job/README.ru.md#solo`
    дают «every document link resolves». `build_site.py` (`rewrite`/`page_of`)
    тоже понимает оба.
  - Выбрать вид для обеих сторон явно, лучше по прецеденту.

Вердикт: принята, по прецеденту: адрес `blob/main` на обеих сторонах, в «Общих
ограничениях».

- **M4. Расхождение с дизайном в чтении исхода.** Задача 4, шаг 3 читает исход
  через `print(await outcome)`. Дизайн, п. 4, говорит «тем же чтением исхода,
  что и Quick start». Выбор разумный из-за длины, см. I6, но записать его как
  решение плана.

Вердикт: принята: шаг 3 задачи 4 называет это решением и его причину; общее
с Quick start — `done`, взятый у конструктора, и это держит
`expectDoneTakenFirst`.

- **M5. Литерал в тесте Quick start.** `printed.last == 'cancelled: manual'`
  противоречит шапке теста («A literal kept here would follow the code»)
  и лишний рядом со сверкой `quotedOutputs`.

Вердикт: принята: тест 1 задачи 3 сверяет вывод только с цитатой страницы.

- **M6. Комментарии теста о README.** Шапку и комментарии план правит только
  в задаче 2. Но строки 13–16 шапки говорят об исходе задачи, отменённой
  до старта, а эту регулярку задача 3 убирает. Комментарии о README есть
  и на строках 136, 157, 171, 461, 512, 939, 1069, 1547: их надо пройти
  поиском, не только «над метками».

Вердикт: принята: поиск по слову `README` — в «Общих ограничениях», шапка
о старте — в тесте 8 задачи 3.

- **M7. Handoff.** Раздел «Требования к README, которые нужно сохранить»
  (`docs/handoff.md:397-431`) говорит о README то, что уезжает на `doc/why.md`:
  `discard`, пример миграции, границы ядра и `solo`. Шаг 3 задачи 5 его
  не трогает. Там же уже устаревшее «сорок одна пара»: сейчас в `PAIRS` 45 пар,
  после работы будет 47.

Вердикт: принята: шаг 4 задачи 5.

- **M8. CHANGELOG.** Нынешний пункт «Unreleased» «names the analyzer plugin …
  in `Install` …; code on `solo` names `solo_lints`» после переезда фразы
  в «solo» стоит поправить. Ссылки в русском CHANGELOG — относительные `why.md`
  и `reference.md`, как у соседних пунктов. Нужна ли строка в CHANGELOG
  `async_job_lints` и `solo` о новой ссылке — решить явно.

Вердикт: принята: шаги 1 и 2 задачи 5; строки в CHANGELOG `solo`
и `async_job_lints` нужны — их опубликованные страницы ведут на уехавший
раздел.

- **M9. Фраза в README плагина.** «See [The context at a glance](…) on the
  reference page of `async_job`» в `async_job_lints/README.md:185` продолжается
  словами «and [Letting time pass](…)». Получается двусмысленно, лучше назвать
  и вторую страницу: «… and [Letting time pass](…) on its time page».

Вердикт: принята, как предложено: шаг 4 задачи 1.

- **M10. Dartdoc у `fetchQuote`.** В `example/walk_away.dart` ей нужен `///`,
  этого требует `public_member_api_docs` в `analysis_options.yaml`. Мелочь,
  анализатор поймает.

Вердикт: принята: интерфейс задачи 4.

- **M11. Строки `switch` в переводе остаются английскими.** `'read'`,
  `'failed: …'` и `'cancelled: …'` сверяет и `check_translations.py` (код без
  комментариев), и сторож вывода. Стоит одной строкой сказать переводчику.

Вердикт: принята: «Общие ограничения».

### Проверено и верно

- **Номера строк и имена.** `example/example.dart:60`,
  `test/cleanup_test.dart:719`, `async_job_lints/README.md:185`,
  `README.ru.md:190`, `solo/doc/reference.md:8-9,106-107`,
  `errors_rakes_test.dart` (образец `versions` — строки 38–45), проверка
  перевода около строки 1145 (`cell()`, 1144–1154). Все названные тесты
  и помощники (`quotedAfter`, `quotedOutputs`, `codeMissingFrom` с `alsoIn`,
  `strayFences`, `contextTable`, `zoneErrorsOf`, `printedBy`) существуют.
  `quotedOutputs` сейчас принимает один аргумент и требует ровно 2 блока, новую
  сигнатуру даёт задача 2.
- **Все места, где сторож читает страницы.** Строки 493–499, 515–518, 895–897,
  928–931, 1016–1020, 1065–1074, 1080–1448, 1456, 1492–1508, 1516–1524,
  1549–1553, 1567–1568. Каждое отнесено к своей задаче. Других чтений README
  ядра в тестах, `lib/`, `tool/`, на сайте и в gate нет. Ссылок
  на `#the-context-at-a-glance` в дереве ровно три и три перевода. Других
  якорей в README ядра извне никто не ведёт.
- **Порядок задач.** После задачи 1 в README остаются оба блока `text`,
  `quotedOutputs` старого вида проходит. Задача 2 меняет его на `count`. Задача
  3 трогает только README и `quick_start.dart`. Задача 4 добавляет второй
  вывод. Сайт: `build_site.py` берёт `doc/*.md` глобом, страницы встают
  в панель в своих коммитах. `PAIRS` перечислен явно.
- **Новый Quick start.** На Dart 3.13 и на полу 3.10.0 печатает
  `database opened` / `database closed` / `cancelled: manual`, код 0.
  `dart format --set-exit-if-changed` оставляет
  `print(switch (await outcome) {` как есть. `dart analyze --fatal-infos`
  с `analysis_options.yaml` ядра: «No issues found». `CancelReason.toString()`
  возвращает `name`, отсюда `manual`.
- **`walk_away.dart`.** На обоих SDK печатает `request sent` /
  `Cancelled(manual)` / `quote answered`, код 0. Тест времени на `fakeAsync`
  с перехватом `print` даёт
  `[request sent @0, Cancelled(manual) @50, quote answered @100]`, как
  и обещает план. С `join` вместо `abandonable` порядок вывода сменился бы,
  и сверка с README покраснела бы.
- **Тесты-оговорки задачи 4.** Чтение Quick start под `abandonable` даёт
  `events=[opened, closed, read]`, исход `Cancelled(manual)`. Поздняя ошибка
  `abandonable` при `done`, взятом сразу, даёт
  `zone=[Bad state: network down]`, исход `Cancelled(manual)`.
- **Красный шаг задачи 1** — действительно `PathNotFoundException`
  на `doc/reference.md`. Тесты 1, 3 и 4 задачи 3 до правки красные:
  `Cancelled(manual)` вместо `cancelled: manual`, во вступлении нет ссылок,
  есть «observes» и `#four-words`/«наблюдает».
- **`check_doc_shape.py`.** Переехавшие разделы открываются кодом или таблицей
  в пределах 10 строк. Раздел «solo» с добавленной фразой о `solo_lints` (около
  9 строк прозы) проходит, это я проверил на копии.
- **`archive_floor.py`** запускает каждый `example/*.dart` без dev-зависимостей
  (строки 329–332), и `walk_away.dart` импортирует только ядро. `doc/` входит
  в архив. `../../docs/ru` из `$RUNNER_TEMP/archive/async_job` не существует,
  поэтому в архиве проверяются одни оригиналы.
- **Запись плана** проходит `reflow.py --check` и `check_line_width.py`, как
  и запись дизайна.
- **Скрипты** `bare_names.py` и `jargon.py` существуют, они в скилле
  `doc-reader`.
