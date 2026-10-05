> **Состояние на 2026-10-05:** сделано в клоне
> `.artifacts/2026-10-05-ctx-abandonable/tree/` одним коммитом
> `refactor(async_job)!: rename ctx.wait to ctx.abandonable`; в `main`
> не перенесено, `docs/handoff.md` не обновлён.
> **Что это:** отчёт о волне переименования `ctx.wait` в `ctx.abandonable` —
> что изменилось и сколько, решение о линте, расхождения с дизайном, проверки.
> **Связанные записи:** `2026-10-05-ctx-abandonable-design.md`,
> `2026-10-05-ctx-abandonable-design-review-report.md`,
> `2026-10-02-cancellation-reread-report.md`.

# Переименование `ctx.wait` в `ctx.abandonable`: отчёт

## Что сделано

Работа шла по `2026-10-05-ctx-abandonable-design.md` с поправками его ревью
`2026-10-05-ctx-abandonable-design-review-report.md`.

**Ядро.** В `packages/async_job/lib/src/job_context.dart` член интерфейса
`JobContext` и переопределение в `JobContextBase` теперь называются
`abandonable`; поведение, параметры (`dispose`, `discard`) и порядок проверок
прежние. Вызов на закончившейся задаче говорит
`cannot run an abandonable action`. `wait` остался псевдонимом на обоих
объявлениях: `@Deprecated('Use abandonable')` и короткий dartdoc на каждом.
Тело в `JobContextBase` — `async`, сначала `throwIfFinished('wait')`, затем
`return abandonable(action, dispose: dispose, discard: discard)`: ошибка
на закончившейся задаче по-прежнему говорит `cannot wait`, всё остальное делает
`abandonable`. Неквалифицированный `wait(` в `_JobStreamBody`
(`job_stream.dart`) и вызов в `pause` перешли на новое имя.

**Как нашлись вызовы.** Линт `deprecated_member_use_from_same_package` включён
в `packages/async_job/analysis_options.yaml`, после чего анализатор назвал 575
мест в `async_job` (46 файлов): вызовы и, на 3.13, ссылки в dartdoc `[wait]`
и `[JobContext.wait]` тоже. В `solo` подсказка `deprecated_member_use` назвала
187 мест в 54 файлах, в `flutter_solo` — 5 в 5 файлах, в примерах — ни одного.
Все они заменены по позиции из машинного вывода анализатора, затем
`dart format` и `dart fix` для висячих запятых.

**Проза и строки.** Второй проход — по тексту всех файлов, кроме
`docs/records/` и `CHANGELOG.md`: `ctx.wait`, `childCtx.wait`, `c.wait`,
`child.wait` и `JobContext.wait` — 273 замены, имя `wait` в бэктиках — 105,
`[wait]` — 2, из которых одна вернулась: в `resources_rakes_test.dart` это
параметр функции по имени `wait`, а не член. Третий проход — 65 точечных правок
имён, названных по члену: имена тестов («wait closes the database…» →
«abandonable closes…»), ключи и списки (`'wait'` в картах членов сторожей;
список членов в `solo/test/cancellation_rakes_test.dart`, который сторож
вынимает из прозы `doc/cancellation.md`), идентификаторы `viaWait`,
`delayUnderWait`, `throughWait`, `afterWait`, `runWaitingDownload`,
`probeWait`, классы `WaitingPlayer`, `WaitingNotesController`, `TempWaiter`
и строки трассы «wait got» и «wait threw Cancelled»
в `vs_bloc_8_checkout.dart`. Файл `packages/solo/test/wait_test.dart`
переименован через `git mv` в `abandonable_test.dart`, имена его тестов тоже.

Где глагол держался за имя, фраза переписана: «`wait` waits for the migration:»
стало «The body waits for the migration through `abandonable`:», в переводе
«Тело ждёт миграцию через `abandonable`:». Артикли после замены: «a
`abandonable` inside it throws» → «`abandonable` inside it throws», «one during
a `abandonable`» → «one during `abandonable`», «a [abandonable] or a [join]» →
«a call of [abandonable] or [join]», «the body has to leave its `abandonable`»
→ «its `abandonable` call» (в переводе «из своего вызова `abandonable`»).
Таблица вступления `cancellation.md` осталась со своими словами об ожидании.
Абзацы Markdown перезалиты `tool/reflow.py`, абзацы комментариев Dart, которые
вылезли за 80 колонок, перезалиты жадно тем же правилом.

**Журналы изменений.** В разделах `Unreleased` трёх `CHANGELOG.md` все
упоминания `ctx.wait` и одно имя `wait` в бэктиках перешли на новое имя. Первой
записью ломающих изменений `async_job` встала запись о переименовании: зачем,
что псевдоним делает и до какого выпуска живёт, текст ошибки обоих имён
и **Migrating** — заменить `ctx.wait` на `ctx.abandonable`; анализ, где infos
фатальны (`flutter analyze` по умолчанию и `dart analyze --fatal-infos`),
краснеет до замены; класс, который реализует `JobContext` руками, реализует
и `abandonable`. У `solo` и `flutter_solo` — короткая первая запись со ссылкой
на журнал `async_job`. Выпущенные разделы (`0.2.0`, `0.1.0`) не тронуты:
сверено `diff` с `HEAD` по каждому файлу.

**Остальное.** `docs/architecture.md` (11 упоминаний), `site/astro.config.mjs`
(описание страницы отмены), стенды `tool/doc_snippets.py` (комментарий)
и `tool/accumulation_snippets.py` (вставки,
`.replace('ctx.abandonable', 'ctx.join')` с `assert`, комментарий,
`probeAbandonable` и переменная `abandoned` в паре с `joined`).

## Сколько

Прирост вхождений `abandonable` по областям, `git diff` против `HEAD`:

| Область | Файлов | `abandonable` |
| --- | --- | --- |
| `async_job/lib` | 5 | 51 |
| `async_job/test` с новым тестом | 43 | 623 |
| `async_job/doc` | 6 | 65 |
| `solo/lib` | 4 | 6 |
| `solo/test` | 57 | 252 |
| `solo/doc` | 9 | 54 |
| `solo/example` | 1 | 1 |
| `flutter_solo/test` и пример | 6 | 7 |
| README и `README.ru.md` | 6 | 20 |
| `docs/ru/` | 15 | 119 |
| `docs/architecture.md` | 1 | 11 |
| `CHANGELOG.md` | 3 | 25 |
| `tool/`, `site/` | 3 | 8 |

## Линт

`deprecated_member_use_from_same_package: true` оставлен
в `packages/async_job/analysis_options.yaml` насовсем: пол его принимает.
Проверка на 3.6.0 (`~/fvm/versions/3.27.0`): `dart analyze` в пакете
с включённым линтом не дал предупреждения о неизвестном правиле,
а подставленное рядом `bogus_lint_xyz` дало `undefined_lint` — значит,
неизвестное имя пол назвал бы. Три предупреждения `included_file_warning`
о правилах из `lints` 6.1.0 были на полу и до правки.

## Сторож

Новый файл `packages/async_job/test/abandonable_alias_test.dart`, четыре теста,
по два на имя. Первый — один сценарий для обоих: вызов отдаёт значение; второй
вызов с действием на 100 мс, отмена на 10 мс — вызов бросает `Cancelled` на 10
мс, действие доходит до 100 мс, его позднее значение уходит в `dispose`.
Второй — точный текст `StateError` на закончившейся задаче:
`<задача> has already finished, cannot run an abandonable action`
и `… cannot wait`; действие при этом не запускается. Вызов псевдонима стоит под
`// ignore: deprecated_member_use_from_same_package`. Скрипт проверки имён —
в каталоге сессии, не в CI, как решил дизайн.

## Расхождения с дизайном

1. Тело псевдонима не только зовёт `abandonable`: перед вызовом оно само
   спрашивает `throwIfFinished('wait')`, иначе ошибка назвала бы новое имя,
   а дизайн требует `cannot wait`. Тело `async`, поэтому ошибка, как и раньше,
   приходит упавшей future, а не синхронным броском; цена — лишний шаг
   до завершения future псевдонима.
2. Ревью называет `exportWithWait` идентификатором по члену. Это не так: он
   собирает ветки через `[...].wait` из Dart, рядом с ним
   `exportWithFutureWait` — через `Future.wait`. Оба оставлены. Оставлены
   и `WaitingJob` в `extending_test.dart` (движок, который ждёт задачу),
   `WaitingCheckoutController` (контроллер про все три члена ожидания),
   `closedToWait` (глагол).
3. Имена тестов, где «a wait» — существительное, ожидание, а не член,
   оставлены: «a wait the body walked away from…», «a sign-out during a wait…»,
   «a wait left behind…». Так же имена с `wait` у списка: «a child waiting for
   another child under wait…» (`running.wait`), «an external cancellation
   inside wait…» (`[...].wait`).
4. В `packages/async_job/doc/children.md` и переводе две строки кода разбиты
   на две: `final rows =` и `await ctx.run(...)` на следующей. Сторож требует,
   чтобы блоки страницы были строками `test/support/children_page.dart`, а там
   тот же код стоит глубже и `dart format` его разбил. Ещё две строки,
   `ctx.abandonable(openCache, …)` и `ctx.abandonable(openRows, …)`, вылезли
   за 80 колонок и разбиты так же.
5. Вступления `Unreleased` у `solo` и `flutter_solo` говорили, что ломающие
   изменения ядра называет последняя запись группы; теперь — «the first and the
   last entries».
6. `docs/handoff.md` проход по `docs/` тоже переписал, правка отменена: handoff
   ведёт основная сессия.

## Проверки

Все зелёные, кроме оговорённого ниже.

- `packages/async_job`: `dart format --output=none --set-exit-if-changed .` —
  75 файлов, 0 изменений; `dart analyze --fatal-infos` — без замечаний;
  `dart test` — 1269 тестов (было 1265 и 4 новых). Тест
  `a body that gives itself up counts its child and cleanup`
  в `observing_rakes_test.dart` меряет настоящим `Stopwatch`, с первой попытки
  получил 139 мс при пороге 140 и прошёл на повторе (`retry: 2`); правка его
  не касается.
- `packages/solo`: формат — 144 файла, 0 изменений; анализ чистый; 1719 тестов.
- `packages/solo/example`: формат — 12 файлов; анализ чистый; 102 теста.
- `packages/flutter_solo`: формат, `flutter analyze` чистый, `flutter test` —
  182 теста; пример — 4 теста, анализ чистый.
- `dart doc --dry-run` у `async_job`, `solo`, `flutter_solo`: 0 предупреждений.
- Стенды вне репозитория: `doc_snippets.py` и `accumulation_snippets.py`,
  `dart analyze --fatal-infos bin/v` у `bloc_check`, `solo_check`,
  `accumulation_check` чистый, 27 драйверов дошли до конца; `check_traces.py`:
  `vs-bloc.md` — 2 цитаты, `accumulation.md` — 12, все напечатаны.
  `flutter_snippets.py`: анализ чистый, 42 теста, `mixins.md` — 6 цитат, все
  напечатаны.
- Из корня: `reflow.py --check`, `check_line_width.py`, `check_links.py`,
  `check_translations.py`, `check_doc_shape.py`, сторожа
  `check_line_width_test.py`, `reflow_test.py`, `archive_floor_test.py`,
  `check_links_test.py`, `build_site_test.py`, сборка `build_site.py`.
- Пол — из чистого клона коммита, потому что `stage` на дереве с чужими
  правками `analysis_options.yaml` падает на предупреждении dry-run:
  `archive_floor.py stage` — `async_job` 87 файлов, 0 предупреждений, `solo`
  163 и `flutter_solo` 39 — 0 предупреждений, подсказки только об оверрайдах;
  `run` на 3.6.0 — 5 корней, `async_job` 1269 тестов, `solo` 1719, пример 102,
  `flutter_solo` 182, пример 4, анализ `lib` и программы примеров зелёные.
- Критерий конца волны: ни одного `deprecated_member_use*` в трёх пакетах, двух
  примерах и трёх стендах (`--fatal-infos`, `flutter analyze`), кроме вызова
  псевдонима под `// ignore:`. Скрипт имён: вне `docs/records/` и выпущенных
  разделов `ctx.wait` и `[wait]` стоят только в записях о переименовании трёх
  журналов, в вызове псевдонима в тесте, в `[wait]` — ссылке на параметр
  в `resources_rakes_test.dart` — и в `docs/handoff.md`, который волна
  не трогает.
- Изменённые абзацы перевода (67, считал скрипт: абзац, которого нет в версии
  `HEAD`): тире ни в одном; `uvx ru-humanizer -` по ним — чистота 100/100,
  запретов и маркеров нет.

## Что осталось `wait` намеренно

- Псевдоним: объявления в `JobContext` и `JobContextBase`, их dartdoc,
  `throwIfFinished('wait')`, тест псевдонима.
- Записи о переименовании в `Unreleased` трёх `CHANGELOG.md`.
- `Future.wait`, `.wait` у списков и рекордов, глагол и существительное
  «wait/ждать» в прозе, комментариях и именах тестов.
- `gate.wait()` в `cleanup_rakes_test.dart` — метод заглушки; параметр `wait`
  в `resources_rakes_test.dart`.
- Имена файлов `waiting_test.dart` и `parallel_wait_test.dart`.
- Выпущенные разделы `CHANGELOG.md` и `docs/records/`.
- `docs/handoff.md`: строки 48–50 о самом переименовании, строка 437 в описании
  вычитки `extending.md` и строки 477–478 в указаниях о русском тексте, где
  `wait` назван как член. handoff ведёт основная сессия; строки 437 и 477–478
  ей переводить на новое имя при переносе.

## Чего не делал

- Не гонял CI и не переносил коммит в `main`; `docs/handoff.md` не обновлён.
- В клоне до начала работы уже были чужие правки трёх `analysis_options.yaml`
  (`android/**`, `ios/**` и прочие в `exclude`) — у `async_job`, `solo`
  и `solo/example`. В коммит они не вошли: у `async_job` закоммичена только
  строка линта.
