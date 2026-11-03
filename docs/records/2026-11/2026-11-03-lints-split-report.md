# Два пакета линтов: `async_job_lints` и `solo_lints` — отчёт

> **Состояние на 2026-11-03:** план исполнен в копии `lints-split-impl`
> шестью коммитами; ждёт независимого ревью Opus всей ветки и вливания
> в `main`. Ничего не опубликовано.
> **Что это:** как пять правил ядра ушли из `solo_lints` в новый пакет
> `async_job_lints`, что показал зонд обоих плагинов из дерева и мутации, какие
> решения принял исполнитель сверх плана.
> **Связанные записи:** `2026-11-03-lints-split-design.md`,
> `2026-11-03-lints-split-plan.md`, `2026-10-28-solo-lints-design.md`,
> `2026-10-29-bare-await-design.md`.

## Что сделано

Владелец 2026-11-03: «сам, исполняй». План исполнен по задачам, без
исполнителя-субагента; журнал задач вёлся рядом с копией и в гит не входит, его
решения перенесены сюда.

| Задача | Коммит | Что |
| --- | --- | --- |
| 1 | `82a3ebb4` refactor: move the rules of the core into async_job_lints | пакет `async_job_lints` с пятью правилами и двумя исправлениями, `registerAsyncJobLints`, `solo_lints` поверх него |
| 2 | `3ad3e35c` test: probe the plugins from the tree through the analysis server | фикстура `tool/plugin_probe/fixture.dart` и `tool/plugin_probe.py` |
| 3 | без коммита | зонд на Dart 3.13 и на полу 3.10 |
| 4 | `e1e30ed8` docs: describe async_job_lints in its README, changelog and example | README с переводом, список изменений 0.1.0, пример со сторожем, сторож версии README |
| 5 | `edbee4a1` build: gate async_job_lints and probe the plugins | задание `dart` гейта, шаг «Plugins», пол и проверка dartdoc |
| 6 | `5512381e` docs: record the split of the lints for agents | `AGENTS.md`, `docs/architecture.md`, `docs/conventions.md`, решение 145 |
| 7 | `aef32b50` docs: point the core and the site at async_job_lints | README ядра и `solo_lints`, сайт, главная, корневой README, решения 129 и 144 |

Тесты: `async_job_lints` +114, `solo_lints` +95 (до раздела +196), ядро +1891,
`solo` +2231, его пример +112. Пол: `tool/archive_floor.py stage` без
предупреждений для пяти пакетов, `run` на Flutter 3.38.1 зелёный.

## Зонд обоих плагинов

`tool/plugin_probe.py` раскладывает пакет-пользователь с фикстурой, называет
в его `analysis_options.yaml` плагины из дерева путём — каждый один и оба
в обоих порядках — и сравнивает вывод `dart analyze --format=machine`
с пометками фикстуры. С `--fixes` он же спрашивает сервер анализа по LSP
о быстрых исправлениях на каждой диагностике с исправлением.

| SDK | Наборы | Диагностики | Исправлений на диагностику |
| --- | --- | --- | --- |
| Dart 3.13.0 | 4 | все по пометкам | по одному во всех четырёх наборах |
| Dart 3.10.0 (Flutter 3.38.1) | 4 | все по пометкам | по одному во всех четырёх наборах |

Вывод `--fixes` на 3.13.0:

```text
ok async_job_lints
  async_job_lints, release_on_the_call at 27: 1
  async_job_lints, catch_without_check at 33: 1
  async_job_lints, catch_without_check at 40: 1
ok solo_lints
  solo_lints, release_on_the_call at 27: 1
  solo_lints, catch_without_check at 33: 1
  solo_lints, catch_without_check at 47: 1
  solo_lints, key_per_request at 109: 1
ok async_job_lints, solo_lints
  async_job_lints, solo_lints, release_on_the_call at 27: 1
  async_job_lints, solo_lints, catch_without_check at 33: 1
  async_job_lints, solo_lints, catch_without_check at 40: 1
  async_job_lints, solo_lints, key_per_request at 109: 1
ok solo_lints, async_job_lints
  solo_lints, async_job_lints, release_on_the_call at 27: 1
  solo_lints, async_job_lints, catch_without_check at 33: 1
  solo_lints, async_job_lints, catch_without_check at 47: 1
  solo_lints, async_job_lints, key_per_request at 109: 1
```

На 3.10.0 вывод тот же строка в строку. Строки 40 и 47 — две копии одного
`catch` под `// ignore:` разных плагинов: глушит тот, что назван первым,
и исправление предлагается на той, что осталась.

Локально весь зонд без `--fixes` занимает 123 с. Шаг гейта стоит под
`timeout 900`; на macOS `timeout` нет, и локально зонд гоняется без него.

## Мутации

Три мутации кода на Dart 3.13.0, каждая в своей копии, откат — копией.

| Мутация | Что сломано | Что увидел зонд |
| --- | --- | --- |
| m1 | `solo_lints` не зовёт `registerAsyncJobLints` | набор `solo_lints` красный: нет семи диагностик ядра |
| m2 | `solo_lints` зовёт её без `ownQueueReportedElsewhere: true` | набор `solo_lints` красный: лишний `bare_await` на строке 105 рядом с `await_own_queue` |
| m3 | коды диагностик ядра создаются на каждый вызов регистрации | набор «async_job_lints, solo_lints» красный: `ctx_in_cleanup` на строках 29 и 91 по два раза |

Вывод m1 и m2:

```text
== m1
ok async_job_lints
  missing:  [('bare_await', 51), ('catch_without_check', 33), ('catch_without_check', 47), ('ctx_in_cleanup', 29), ('ctx_in_cleanup', 91), ('release_on_the_call', 27), ('sync_fake_async', 55)]
  extra:    []
FAILED solo_lints
== m2
ok async_job_lints
  missing:  []
  extra:    [('bare_await', 105)]
FAILED solo_lints
```

Первый прогон m3 сравнивал множества, а не мультимножества: дубль строки 29
красил набор, но в `extra` не попадал. После этого сравнение переведено
на `Counter`, и m3 печатает дубли в `extra`.

Мутации сторожей пакетов: тест регистрации краснеет без вызова функции ядра,
тест собственной очереди — без параметра; сторож примера `async_job_lints`
краснеет на сдвинутой пометке. Сторож README ядра краснел на старом блоке
`solo_lints: ^0.1.3`, пока README не назвал `async_job_lints`.

## Решения исполнителя

Каждое — с ценой, если оно неверно.

1. Скрипты `task-start` и `task-done` ищут заголовки `Task N`, а в плане
   `Задача N`: брифы читались из плана, база задачи записывалась руками. Цена —
   никакой, это учёт.
2. Идентификаторы `FixKind` перенесённых исправлений стали
   `async_job_lints.fix.*` вместо `solo_lints.fix.*`: идентификатор называет
   пакет, которому исправление принадлежит. Цена — привязка клавиши редактора
   к старому идентификатору перестанет срабатывать.
3. Фикстура импортирует только `package:solo`: он реэкспортирует ядро, а второй
   импорт даёт подсказку `unnecessary_import`. Пакет-пользователь зависит
   от обоих. Цена — никакой: правила видят те же элементы.
4. `--fixes` требует ровно одного исправления на диагностику только в одиночных
   наборах, в наборах с двумя плагинами печатает. Совпадает с планом,
   а оказалось по одному и там. Цена — никакой.
5. Ссылки правил в README `async_job_lints` ведут на страницы ядра:
   `ctx_in_cleanup` — `cleanup.md`, раздел о `dispose` для того, что задача
   оставляет себе; `release_on_the_call` — `cleanup-rules.md`, регистрация
   по приходу; `catch_without_check` — `cancellation.md`, перехват ошибок
   операции; `sync_fake_async` — `testing.md`, отменённое открытие;
   `bare_await` — `time.md`, «дать времени пройти». Примеры правил переписаны
   без `solo`. Цена — ссылка на более слабый раздел, правится текстом.
6. Кортежи `PACKAGES` в `tool/archive_floor.py` и `tool/check_dartdoc.py`
   разнесены по строке на имя: новое имя дотянуло их до 81 символа. Цена —
   никакой.
7. README `solo_lints` держит разделы своих трёх правил и таблицу всех восьми,
   имена пяти правил ядра ведут на разделы README `async_job_lints`. Абзац под
   таблицей говорит, что в `// ignore:` для них при этом плагине стоит
   `solo_lints/`, а раздел `await_own_queue` — что `bare_await` на его
   ожиданиях молчит: это то, что пользователь `solo` знал из удалённого раздела
   `bare_await`. Цена — абзац текста.
8. Абзац главной сайта о плагинах называет оба одной фразой — какой назвать для
   какого кода, — а не по фразе на плагин. Цена — текст.

## Ревью

Ждёт независимого ревью Opus всей ветки.
