> **Состояние на 2026-10-31:** сделано и смержено в `main` коммитами «fix:
> settle the public API of 1.0.0 after the Fable review» и «fix: close the
> independent review of the 1.0.0 wave»; не опубликовано.
> **Что это:** отчёт о волне правок по полному ревью перед 1.0.0: два
> переименования, сужение `SoloContext.each`, две строки отладки, правки
> документов, решения 135–143 и независимое ревью волны.
> **Связанные записи:** `2026-10-31-async-job-project-review.md`,
> `2026-10-31-solo-project-review.md` (ревью, по которому шла волна),
> `2026-10-30-one-zero-report.md` (подготовка 1.0.0).

# Волна правок по ревью Fable перед 1.0.0

## Что решил владелец

На вопросы по ревью владелец ответил так:

- `SoloContext.each` — «Сузить до `SoloJob<void>`»;
- правки документов и две строки отладки — «До публикации»;
- оба переименования, `HandlerCancelReason` в `BodyCancelReason`
  и `Policy.replace` в `Policy.keepLatest`, — «да».

Остальное закрыто вердиктами в записях ревью: принятое сделано в этом же
коммите, отказы стали решениями 135–143 в `docs/settled.md`.

## Что сделано в коде

**`BodyCancelReason`.** Класс, конструктор `Cancelled()` и трассы: `name`
теперь `body`, `Cancelled('why')` печатается `Cancelled(body: why)`. Правка
прошла скриптом по коду, тестам, страницам и переводам; `CHANGELOG.md`
и `docs/records/` — история, их скрипт обходил. Остались на месте строки, где
`handler` — не причина: `TestCancelReason('handler')`, `StateError('handler')`,
`Cancelled('handler')` в `zone_test.dart` `solo`, где это сообщение обработчика
без ответа.

**`Policy.keepLatest`.** Переименован член enum и все упоминания политики,
в том числе голое имя `replace` в `jobs.md`, `camera.md`, `reference.md`,
`docs/architecture.md` и в тестах. `ReplacedCancelReason`,
`Cancelled(replaced)` и `AccumulationPolicy.replace` не тронуты: это причина
и политика накопителя, они о другом. Первый абзац dartdoc говорит, что
в очереди ждёт только последняя задача с ключом; `check_dartdoc.py` требует
одну фразу в нём, поэтому `restart` для идущей задачи назван во втором.

**`SoloContext.each`.** Интерфейс, `createEachJob` и `each` возвращают
`SoloJob<void>`; `each` приводит то, что вернуло ядро, с комментарием, почему
приведение верно. `streams.md` говорит о типе и советует ждать `.done`.

**Строки отладки.** `Job.debug` пишет `Job() awaited before start` один раз,
когда `done` или `value` неначатой отложенной задачи читают впервые.
`Solo.debug` пишет `drop Job(…): Cancelled(rules: …)`, когда правила рабочего
типа отклоняют задачу на старте. Текст отладки вне обещания semver, но строки
вышли до 1.0 по слову владельца.

**Комментарий** у `_chainCancellations` в `job_then.dart` о том, что видит
вложенный слушатель.

## Что сделано в документах

Строка «A new value of an enum or a new subclass of a sealed class — a major
release» в «Versions» трёх README и правило в `docs/conventions.md`; абзацы
README о `await job` и об отказе правил на старте; правки страниц D1–D15 `solo`
и D1, D2, D4 ядра — каждая названа в своём вердикте. Разделы `## 1.0.0` трёх
`CHANGELOG.md` и переводов получили ломающие изменения, «Added» и пункты
документации.

## Где разошлось с предложенным

- Строку `Listeners` в `reference.md` я сначала добавил,
  а `reference_page_test.dart` её отверг: «Other types» — экспорты
  `package:solo/solo.dart`. Строка снята, решение 140.
- D15: ссылки на README `flutter_solo` со страницы `solo` нет, `check_links.py`
  такие ссылки запрещает; фраза называет README словами.
- A1, A2 и A4 `solo` сказаны в README и прозе страниц, а не новыми разделами
  `mistakes.md`, решение 143.
- Правило `await_only_futures` README ядра называет из базового набора
  `package:lints`, а не из `recommended`, как писал ревьюер: оно в `core.yaml`.

## Что держит правки

Новые тесты:

- `async_job/test/debug_test.dart` — два теста строки `awaited before start`;
- `async_job/test/streams_rakes_test.dart` — группа «a second each on a
  single-subscription stream», два теста;
- `solo/test/each_child_test.dart` — «each hands back a SoloJob, as child
  does»;
- `solo/test/diagnostics_rakes_test.dart` — «a job the rules turn down at its
  start is traced as dropped»;
- `solo/test/errors_rakes_test.dart` — случай «a keepWhile asked at the start
  throws»;
- `flutter_solo/test/readme_rakes_test.dart` — «a queued job made with
  cancellable: false is dropped».

Цитаты сторожей страниц подогнаны под новую прозу
в `resources_rakes_test.dart`, `errors_rakes_test.dart`,
`camera_rakes_test.dart`, `streams_rakes_test.dart` `solo`,
`outcomes_rakes_test.dart` и `readme_rakes_test.dart` `flutter_solo`.

Первый полный прогон гейта нашёл места, где правка прозы или имени не дошла
до сторожа: ожидание `cancelled: handler`, форму dartdoc `keepLatest`, линт
`close_sinks` в новом тесте стримов, строку `Listeners`, две цитаты маршрута
ошибки, строку таблицы ошибок и цитату README `flutter_solo`. Все исправлены,
итог прогона — в `docs/handoff.md`.

## Независимое ревью

Коммит волны прошёл ревью Opus 5.5, субагента Claude Code, в отдельной копии
дерева на этом коммите: код, полнота переименований, правда новой прозы,
переводы, вердикты и решения 135–143. Ревьюер проверял зондами и мутациями;
зонды не сохранены, их вывод назван ниже. Девять находок, все приняты и закрыты
коммитом «fix: close the independent review of the 1.0.0 wave».

- R1, High. Dartdoc `Job.debug`, `error-rules.md`, список изменений `async_job`
  и переводы говорили, что ожидание неначатой отложенной задачи «never ends».
  Зонд: прочитанный `value`, потом `start()`, дают
  `[Job(d) awaited before start, Job(d) started, Job(d) finished: Done(7)]`.
  Строку даёт чтение, а ожидание кончается, когда задачу запустят или отменят;
  так теперь и сказано во всех местах.
- R2, Medium. Комментарий `// replace:` над `Policy.keepLatest` в коде
  `jobs.md`, в переводе и в стороже страницы `jobs_page.dart` — теперь
  `// keepLatest:`.
- R3, Medium. Правило `canStart`, которое само зовёт `cancelAll()` или
  `close()` и отвечает `false`, давало `drop Job(…): Cancelled(rules: …)`,
  а исход у задачи `Cancelled(manual)` или `Cancelled(closed)`. `_pump` теперь
  проверяет `job.isFinished` до отказа и пишет
  `start Job(…): ended while the rules were asked`. Тест «a job its own rule
  ends and then turns down is not traced as dropped»
  в `diagnostics_rakes_test.dart`; на коде волны он падает.
- R4, Low. Тест строки `awaited before start` читал оба геттера сразу,
  и мутация, снявшая трассу с одного из них, проходила. Два теста, по одному
  на `done` и `value`, в `debug_test.dart`.
- R5, Low. README `solo` и список изменений обещали строку `drop` для любой
  отклонённой задачи, а пишет её только очередь: дочерняя задача, которую
  правила не пустили, строки не получает. Обещание сужено до задачи из очереди,
  код не тронут.
- R6, Low. Список изменений `flutter_solo` называл два ломающих изменения
  реэкспорта из четырёх; теперь названы и `SoloContext.each`, и `name` `body`.
- R7, Low. Перевод README `solo`: «сказать об этом может только исход» спорил
  со следующей фразой о `Solo.debug`; теперь «и говорит об этом исход».
- R8, Low. Два имени теста в `async_job` говорили «handler cancellation»;
  теперь «body cancellation».
- R9, Low. Запись `2026-10-31-solo-project-review.md` не говорила, что зонды
  Fable не сохранены; фраза добавлена, как в записи ядра.
