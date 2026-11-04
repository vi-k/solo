# Страницы о bloc после ревью простоты: отчёт

> **Состояние на 2026-11-04:** сделано и влито в `main`: страница ядра о bloc
> снята, страница `solo` сужена до трёх разделов; ревью готовой работы — три
> находки Important и три Minor, все приняты и закрыты.
> **Что это:** отчёт о работе по ревью простоты страниц о bloc и о независимом
> ревью этой работы перед вливанием, с вердиктами.
> **Связанные записи:** `2026-11-04-bloc-pages-simplicity-report.md`,
> `2026-11-04-core-bloc-page-rework-design.md`,
> `2026-11-04-bloc-pages-report.md`.

## Что сделано

Два коммита по слову владельца, оба на ветке поверх 1ba906ba. Находки ревью
простоты и итог каждой — в `2026-11-04-bloc-pages-simplicity-report.md`.

- 5eadf502, «docs: drop the core bloc page». По слову «да, убираем» страница
  ядра `packages/async_job/doc/bloc.md` снята вместе с переводом, входами,
  страницей сайта и драйверами ядра в стенде. Почему — в шапке
  `2026-11-04-core-bloc-page-rework-design.md`: один bloc останавливает работу
  стримом с `onCancel`.
- 0eb42bc4, «docs: narrow the solo bloc page to three sections». По слову
  «Узкая страница» у `packages/solo/doc/bloc.md` остались мосты с ценой слоя
  и разделы «Restarting», «Removing» и «Finishing»; «Ordering», «Closing»
  и «Reacting» ушли в таблицу «Where bloc keeps its answer» с ответом одного
  bloc. Вступление советует оставить на одном bloc приложение с одной такой
  проблемой.

## Ревью работы

Независимое ревью Opus по копии дерева на 0eb42bc4; строки в находках —
по этому коммиту. Ревьюер собрал стенд, гонял зонды на bloc 9.2.1, 9.2.0,
`bloc_concurrency` 0.3.0 и `async` 2.13.0 и мутации по копии своей копии;
репозиторий не тронут. Находки ниже — его текст; пути к его временным каталогам
убраны. Вердикт — отдельным абзацем после каждой находки. Все приняты и закрыты
коммитом «docs: close the review of the narrowed bloc page».

### Итог ревьюера

Ревьюировал `5eadf502` и `0eb42bc4` поверх `1ba906ba` по своей копии дерева.
Копию не правил: HEAD `0eb42bc4`, `git status` чист. Critical нет, Important
три, Minor три. Всё, что страницы говорят о коде, сейчас верно: я проверил это
зондами на bloc 9.2.1, bloc_concurrency 0.3.0 и async 2.13.0. Все находки
о том, что не держит стенд, плюс устаревший код в проверке ссылок и неточности
в записях.

### Important

**I1. Строку Closing в таблице не держит ни один драйвер. Она верна только
на bloc 9.2.1 и расходится с разделом, на который ссылается.**
- **Где:** `packages/solo/doc/bloc.md:655`, `docs/ru/solo/bloc.md:654`. Тот же
  расчёт на версию записан в комментарии `tool/bloc_snippets.py:49–52` («the
  closing row of the table of the page stands on it») и в `docs/handoff.md`.
- **В чём дело:**
  - Ни в одном драйвере стенда нет `ChatBloc` и проверки `isClosed` до вызова.
    Если выйдет bloc, где проверка до вызова перестанет работать, ничего
    не покраснеет.
  - Ссылка строки ведёт в «Closing…» `vs-bloc.md`. Там ответ Bloc проверяет
    только после `await`, и проза говорит обратное строке: «Each is still sent
    to the API while `close()` runs».
- **Чем подтверждено:**
  - `grep -l -E 'ChatBloc|isClosed\) return' bin/v/*.dart` в `bloc_pages_check`
    → `grep exit 1`.
  - Зонд: `ChatBloc` из `vs-bloc.md` плюс `if (isClosed) return;` перед `send`;
    «hi» в полёте, «bye» в очереди, закрытие через 10 мс.
    - На 9.2.1: `before and after (the row): isClosed before close false,
      right after close() true; close took 40ms, sent [hi], reply null,
      reads 0, zone []`. Строка верна.
    - На 9.2.0: `before and after (the row): ... right after close() false;
      close took 90ms, sent [hi, bye], reply reply to bye, reads 0,
      zone [Bad state: Cannot add new events after calling close, ...]`.
  - Причина видна в исходниках:
    `bool get isClosed => _eventController.isClosed || super.isClosed;` есть
    только в `bloc-9.2.1/lib/src/bloc.dart:303`.
- **Что предложить:**
  - Завести драйвер `solo_table_closing`. Он берёт `ChatBloc` из `vs-bloc.md`
    через `from_vs_bloc`, вставляет проверку до вызова заменой одной строки,
    как это делает `KEPT_EVENT`, и требует
    `close took 40ms, sent [hi], reply null, reads 0` и пустую зону.
  - В строке или во вступлении таблицы сказать, что проверка до вызова —
    добавка к ответу Bloc из `vs-bloc.md`.

Вердикт: принято, как предложено. Итог: драйвер `solo_table_closing` стенда
`tool/bloc_snippets.py` берёт ответ Bloc раздела «Closing…» `vs-bloc.md` через
`from_vs_bloc` и вставляет `if (isClosed) return;` перед `send` заменой одной
строки. Он требует `sent [hi]`, ни одного состояния после `close()`, ни одного
прочтения, пустую зону и `close()`, который ждёт только вызов в полёте,
и печатает `isClosed before and after the call: close took 40ms, sent [hi],
reply null, reads 0`. Без вставленной проверки он краснеет:
`close took 90ms, sent [hi, bye]` и «"bye" must not be sent». Строка таблицы
теперь называет, к чему проверка добавлена: «the Bloc answer there with a check
of `isClosed` before the call as well as after it», в переводе — «ответ Bloc
оттуда с проверкой `isClosed` и до вызова, а не только после него». Комментарий
стенда о 9.2.1 и строка handoff теперь верны: строку держит драйвер, а стенд
и так просит `bloc: ^9.2.1`. Коммит «docs: close the review of the narrowed
bloc page».

**I2. В `tool/check_links.py` остался допуск для снятой страницы ядра.**
- **Где:** `tool/check_links.py:62–66` (docstring: «the bloc page of
  `async_job` sends its reader to `solo`…»), `:88`
  `LEADS_UP = {('async_job', 'bloc.md')}`, и тест
  `tool/check_links_test.py:308–309`, который держит это множество.
- **В чём дело:** страницы нет, а docstring описывает её как существующую. Если
  когда-нибудь появится новая `packages/async_job/doc/bloc.md`, ей молча
  разрешат ссылаться вверх на `solo` в обход решения 144. Бриф просил
  не оставлять ссылок на снятую страницу.
- **Чем подтверждено:** `grep -rn "bloc\.md" tool` показывает строки 88 и 309,
  и больше ничего про ядро.
- **Что предложить:** опустошить `LEADS_UP` или убрать его вместе с абзацем
  docstring и тестом `test_the_pages_that_answer_with_the_queue`. Сам механизм
  проверяется отдельно, на моке (`test_a_page_that_answers_with_the_queue`).

Вердикт: принято, первый путь. Итог: `LEADS_UP` пуст (`set[tuple[str, str]]`),
абзац docstring `tool/check_links.py` описывает механизм без снятой страницы —
решение 144 такие страницы допускает, — а тест
`test_the_pages_that_answer_with_the_queue` держит пустое множество. Механизм
по-прежнему проверяется на моке. Коммит «docs: close the review of the narrowed
bloc page».

**I3. Новый абзац в «A handler that restarts» не держит стенд, хотя
по соглашению стенд держит прозу этой страницы.**
- **Где:** `packages/async_job/doc/riverpod-and-bloc.md:338–348` и перевод.
  Соглашение — `docs/conventions.md:299–305`: «Сказанное в прозе держат сторожа
  драйверов».
- **В чём дело:** рецепт, который читатель скопирует,
  `CancelableOperation.fromFuture(call, onCancel: token.cancel).asStream()`,
  нигде не собирается. В `tool/adapter_snippets.py` нет ни `package:async`,
  ни `CancelableOperation` (grep пуст). Утверждение «`restartable()` and
  `close()` stop the call through it» тоже ничем не охраняется.
- **Чем подтверждено:** утверждение сейчас верно. Зонд:
  ```
  restartable: [a started, ab started, a aborted, closed, ab aborted], state "", zone []
  concurrent (default): [a started, ab started, closed, ab aborted, a aborted], state "", zone []
  sequential: [a started, a answered, ab started, ab answered, closed], state "rows of ab", zone []
  ```
  Под `sequential()` вызов не обрывается, но это уже сказано в абзаце выше.
  Источник: `async-2.13.0/lib/src/cancelable_operation.dart:116–118`,
  `onCancel: _completer._cancel`.
- **Что предложить:** драйвер в `adapter_snippets.py` с зависимостью `async`.
  Он должен собирать выражение из код-спана и требовать `aborted` для обоих
  запросов при `restartable()` и при `close()`, а также пустую зону.

Вердикт: принято, как предложено. Итог: драйвер `bloc_single_call`
в `tool/adapter_snippets.py`, у стенда зависимость `async: ^2.13.0`. Выражение
драйвер берёт из строки `STOPPING_STREAM`, и генератор падает, если такого
код-спана нет в прозе страницы. Сценарий: «a», через 30 мс «ab», через 15 мс
`close()`; вызов — три шага по 20 мс, между ними он смотрит на свой токен.
Драйвер требует `[a started, ab started, a aborted, closed, ab aborted]`,
пустое состояние и пустую зону; с `Stream.fromFuture(call)` вместо выражения он
краснеет на `[a started, ab started, closed, a answered, ab answered]`. Коммит
«docs: close the review of the narrowed bloc page».

### Minor

**M1. Итог I4 в ревью простоты «исправил» верный номер строки на неверный.**
- **Где:** `docs/records/2026-11/2026-11-04-bloc-pages-simplicity-report.md`,
  итог I4; `tool/bloc_snippets.py:463`.
- **В чём дело:**
  - Итог говорит: «Строка `seed` … — 202, а не 203».
    Но в `bloc_test-10.0.0/lib/src/bloc_test.dart` строка 202 — это
    `// ignore: invalid_use_of_protected_member…`, а строка 203 —
    `if (seed != null) bloc.emit(seed());`. Проверено: `sed -n '202,203p'`.
    Ревьюер был прав, а драйвер ссылается на `:202`.
  - Итог говорит, что драйверы «печатают строки этой находки». Для p11 это
    не так: в находке `seeded 9: states [0], bloc.state 0, controller 0`,
    а `solo_bridge_seed` печатает `seeded 9: bloc.state 0, controller 0`.
- **Что предложить:** в итоге и в комментарии драйвера поставить 203. Либо
  вернуть `states` в вывод драйвера, либо смягчить формулировку «слово
  в слово».

Вердикт: принято. Итог: драйвер `solo_bridge_seed` ссылается
на `bloc_test.dart:203`, и итог I4
в `2026-11-04-bloc-pages-simplicity-report.md` исправлен: строка `seed` — 203,
как в находке, а «202» прежнего итога было ошибкой итога. Там же сказано, что
p11 драйвер печатает без списка состояний; вывод драйвера не менялся, смягчена
формулировка. Коммит «docs: close the review of the narrowed bloc page».

**M2. Шапки двух записей залиты с нарушениями.**
- **Где:** шапка `2026-11-04-bloc-pages-simplicity-report.md`, строка 4,
  и шапка `2026-11-04-core-bloc-page-rework-design.md`, строка 4.
- **В чём дело:**
  - В первой строка 4 — огрызок `> Находки`: слово «ядра» влезает в него.
  - Во второй строка 4 длиной 80 символов:
    `> ответ одного bloc — стрим с `onCancel` в `emit.forEach` — даёт ту же остановку`.
    Цитаты `reflow.py` не заливает, поэтому `--check` это не ловит.
- **Что предложить:** перезалить обе шапки вручную.

Вердикт: принято. Итог: обе шапки перезалиты вручную. Коммит «docs: close the
review of the narrowed bloc page».

**M3. Две фразы шире того, что верно.**
- **Где:** `packages/solo/doc/bloc.md:150–151`
  и `packages/async_job/doc/riverpod-and-bloc.md:347–348`, в обоих случаях
  вместе с переводом.
- **В чём дело:**
  - «Every bloc pays … a class that adds `SoloStream` to its controller».
    Но `Counter` и `PlayerController` объявлены с примесью сразу,
    и в Restarting этот класс не нужен.
  - «a check it misses lets the reads run to the end». При проверке перед
    каждой страницей одна пропущенная проверка стоит одной страницы. До конца
    чтение доходит только без проверки вовсе: так и было в зонде дизайна
    `check forgotten`.
- **Что предложить:**
  - В первой фразе: «unless the controller is declared with it».
  - Во второй: «without the check the reads run to the end».

Вердикт: принято, как предложено. Итог: «unless the controller is declared with
it», в переводе — «если контроллер объявлен без него»; «without the check the
reads run to the end», в переводе — «без проверки чтение доходит до конца».
Абзацы перезалиты. Коммит «docs: close the review of the narrowed bloc page».

### Проверено и верно

- **Стенд.** `python3 tool/bloc_snippets.py` пишет 15 файлов.
  `dart analyze --fatal-infos bin/v` → «No issues found!». Все 15 драйверов
  с `--enable-asserts` дают exit 0. `check_traces.py packages/solo/doc/bloc.md`
  → «7 quoted traces, 0 not printed». Разрешились bloc 9.2.1 и bloc_concurrency
  0.3.0.
- **Новые драйверы печатают то, что говорит страница:**
  - `solo_bridge_emit`: `after Clear: bloc.state 0, controller 2`, переходы
    `[_Started: 0->1, _Started: 1->2, Clear: 2->0, _Started: 0->3]`.
  - `solo_bridge_seed`: `bloc.state 0, controller 0`. Модель `seed` совпадает
    с `bloc_test.dart:202–204`: `emit` сразу после `build`, до подписки.
  - `solo_bridge_unclosed`: `controller 5, counter.isClosed false`.
  - `solo_bridge_failed`: `[Bad state: count: broken]`.
  - `solo_restarting_bloc_identical`: `[play, seek 1, pause]`.
  - `solo_removing_bloc_online`: `[connect, disconnect], the zone []`, а общая
    метка по-прежнему пропускает `battery`.
- **Мутации** (по копии копии):
  - Без сравнения в `follow` краснеют `solo_bridge_late` и `solo_bridge_seed`.
  - `settle`, сокращённый до `await job.done`, роняет `solo_bridge_failed`.
  - Без `ctx.onCancel` в обоих документах краснеет `restarting_controller`.
  - Без `removeWhere` в обоих документах краснеет `removing_controller`.
  - Подменённая трасса роняет `check_traces`.
  - Без override `close()` в `CounterBloc` падает assert генератора.
- **Правило регистраций по умолчанию проверено отдельно** (зондом, импорт
  `bloc_concurrency` добавлен). Это нужно было потому, что в мутации
  с `sequential()` перед `Seek` и `Flash` анализ падал на отсутствующем
  импорте, а не на правиле:
  - `sequential()` у `Seek` даёт `[play, seek 1, pause, seek 2, seek 3]`.
  - У `Flash` — `upload 0 must end Cancelled(replaced): Done(null)`.
  - `restartable()` у `Seek` тоже ломает порядок: `[play, pause, seek 3]`.
    Правило верно, хотя страница объясняет его только через `sequential()`.
- **Строки Ordering и Reacting** совпадают с ответами Bloc
  в `vs-bloc.md:204–244` и `1600–1625`.
- **Переводы.** `docs/ru/solo/bloc.md` и абзац
  в `docs/ru/async_job/riverpod-and-bloc.md` говорят то же, что оригиналы.
  README обоих пакетов на двух языках, CHANGELOG `solo` и `async_job`
  с переводами, `vs-bloc.md:51–54` с переводом и `site/astro.config.mjs`
  согласованы.
- **Остатки.** Ни `NotesController`, ни `ChatBloc`, ни `ReportController`,
  ни ссылок на `async_job/doc/bloc.md` на страницах обоих языков не осталось;
  внутренние якоря живы. Единственный хвост — I2.
- **Проверки в отдельной копии:** `check_translations`, `check_links`,
  `check_line_width`, `check_dartdoc`, `reflow --check` (всё дерево и названные
  записи) — exit 0. `build_site.py` → «wrote 92 pages», страницы
  `async_job/bloc` нет. `unittest` по `build_site_test`, `check_links_test`,
  `reflow_test` → 76 OK. `gate.yml` гонит `bloc_pages_check` в один
  `bloc-page.out` и сверяет его со страницей `solo`.
- **Записи.** Итоги C3, I1, I4, I5, I6, M1, M3 и M4 ревью простоты и итог I4
  в `2026-11-04-bloc-pages-report.md` совпадают со сделанным, кроме мелочей
  из M1 этого отчёта. Шапки записей, решения 133 и 144 и `docs/handoff.md`
  говорят текущее состояние. Ссылок на временные пути я не нашёл.
- **Узкая страница читается связно.** Вступление обещает три раздела, цену
  мостов, совет оставаться на одном bloc при одной проблеме и таблицу, и всё
  это на странице есть. Каждый раздел кончается ссылкой на ответ Solo без
  мостов.
