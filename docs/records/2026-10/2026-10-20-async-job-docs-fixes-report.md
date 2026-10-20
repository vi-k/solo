# Документы ядра по третьему полному ревью: M3–M7, L1–L4, L8, L12, L15–L19

> **Состояние на 2026-10-20:** сделано в `main` одним коммитом, не отправлено.
> **Что это:** третья волна правок по третьему полному ревью — документы
> `async_job`, их стенды, dartdoc и сторож двух пустых строк подряд;
> шестнадцать находок записи `2026-10-20-async-job-project-review.md` и L15
> записи `2026-10-20-solo-project-review.md`.
> **Связанные записи:** `2026-10-20-async-job-project-review.md`,
> `2026-10-20-solo-project-review.md`,
> `2026-10-20-async-job-code-fixes-report.md`,
> `2026-10-20-solo-code-fixes-report.md`.

Владелец 2026-10-20 сказал «чини всё, что можешь». Первые две волны закрыли код
ядра и код `solo` (`2026-10-20-async-job-code-fixes-report.md`,
`2026-10-20-solo-code-fixes-report.md`). Эта — о документах ядра. Форма длинных
страниц (M8, L20) — пятая волна; код M4 и M6, подсказка `Job.debug` из M5
и `ctx.start` из L4 ждут решения владельца.

## Что сделано

**M3.** `extending.md`, очередь `MyQueue`. Один цикл: поле `_running`,
`run() => _running ??= Future.microtask(_loop)`, и `_loop` в `finally` снимает
поле, так что `run()` после пустого прохода заводит свой цикл.
`MyJob.adoptedBy` отказывает задаче, которая стоит в очереди:
`StateError('$this waits in its queue')`, и `ctx.run` бросает
`Bad state: Job(queued) waits in its queue`. Новые разделы «One loop, and no
other way to start» и «The whole engine» — полный листинг `MyJob` и `MyQueue`.
Вердикт оставлял второй путь — передать задачу явно; его нет, страница учит
отказу. Тесты в `extending_rakes_test.dart`: второй `run` ждёт идущий цикл;
`run`, не нашедший работы, оставляет следующему свой цикл; `ctx.run` отказывает
стоящей задаче. Каждая из трёх мутаций — `run` без `??=`, `_loop` без
`finally`, `adoptedBy` без отказа — краснит свой тест.

**M4.** `chains.md`. В таблице отмены строка «`parsed`, while `loaded` has
another continuation». Новый раздел «Two continuations of one source»: первая
попытка — два `loaded.then`, отмена одного, вывод `loaded: Cancelled(chain)`
и `shown: Cancelled(chain)`; ответ «Jobs that wait for the source» — задача
с `ctx.abandonable(() => loaded.value)`, отмена которой источник не трогает:
`parsed: Cancelled(manual)`, `loaded: Done(21)`, `shown: Done(null)`. Код
стенда — `twoContinuations()` и `twoWaiting()` в `children_page.dart`, сторожа
и сверка цитат — в `chains_rakes_test.dart`, там же тест поздней ошибки
источника: зона и `onError` слышат её по разу.

**M5.** `discard` описан тем, чем решается: «unless the job ends `Done`».
Dartdoc `abandonable`, `join`, `run`, `onDiscard`, строка README
о `ctx.onDiscard`, таблица и список «what happens» на `cleanup.md`, две фразы
`groups.md`. На `cleanup.md` раздел «A value the job keeps back»: первая
попытка с `return null` оставляет базу открытой, ответ — `ctx.disown`
и `close()` в самом теле; почему сначала `disown`, сказано под ответом.

**M6.** Dartdoc `JobObserver.onError`: «Each is told here once per job…»
и абзац о провале, который стал исходом нескольких задач — ребёнка `run`
и родителя, ветки `runAll` и родителя, источника и продолжения `then`. Такой же
абзац на `observing.md`. Наблюдатель, который считает, отсеивает по `identical`
и помнит услышанное в `Expando`; ошибка, брошенная константой, — один объект
при каждом броске, и два таких провала он посчитает за один. `isChild`
из вердикта рецептом не стал: источник и продолжение `then` оба корни,
и признак их не разделяет. Тесты «one error is heard on each job whose outcome
it became» и «an Expando counts a failure once, and a constant error once»
в `observing_rakes_test.dart`.

**M7.** `testing.md`. Строки таблицы «what moves the time» для
`ctx.pause(duration)` и `timeout: limit`. Три раздела:

- «A failure the test expects» — вердикт называл его «did not expect»,
  но ловушка в провале, которого тест ждёт: проверка исхода проходит, а тест
  падает `Bad state: database locked` из зоны. Ответ — `..ignoreFailure()`;
- «Comparing outcomes» — `expect(job.outcome, const Done(3))` падает
  с `Expected: Done<int>:<Done(3)>` и `Actual: Done<int>:<Done(3)>`; ответ —
  `isA<Done<int>>().having(...)`;
- «Settings between tests» — `setUp` ставит `Job.debug`
  и `Job.isCancellationError`, `addTearDown` возвращает прежние.

Оба провала сняты настоящим `dart test` во временном файле и процитированы
дословно; сторожа и сверка цитат — в группе «Testing»
`observing_rakes_test.dart`. Порядок событий журналом через `JobObserver`
отдельного раздела не получил: его показывает `observing.md`.

**L1.** `cleanup.md`, «Registering on arrival», и dartdoc `run`: когда проверка
после прихода значения бросает, `run` закрывает значение на месте и ждёт
закрытия до `Cancelled`; когда проходит — запись ложится на стек. Тест «a
checkpoint of run that throws closes the value before the body hears it»
в `cleanup_rakes_test.dart`.

**L2.** `groups.md`. Строка `ctx.runAll` в таблице: «on success, the cleanup of
every branch, except one a branch registers after running it; on failure, every
branch to its end», и абзац после таблицы: при успехе значения приходят после
уборки веток, но до их конца; ветка, выполнившая уборку, ждёт уборки остальных,
и уборка, которую она регистрирует в этом ожидании, выполняется уже после
значений; при провале значения не приходят, а ошибка — после конца каждой
ветки. Тесты «What ctx.runAll waits for» в `groups_rakes_test.dart`: успех
и провал, уборка, зарегистрированная до своей и после неё.

**L3.** Quick start в README обёрнут в `main`, рядом названа его программа
`example/quick_start.dart`. `readme_recipe_test.dart` сверяет блок README
с файлом и вывод программы с трассой под ним.

**L4.** Строка `ctx.run` в таблице README: «Starts a `ChildJob`, such as one
made with `Job.deferred`», и `.ignore()` для future, который тело не ждёт.

**L8.** Dartdoc `whenCancelled`: отмена источника отменяет его продолжения
до колбэков; отмена продолжения отменяет источник, а соседей после, так что
в колбэке источника они могут быть ещё не `isCancelled`. Два теста
в `then_test.dart`, по точке входа.

**L12.** Строка `ctx.log` в README: замыкание зовёт наблюдатель, который строит
строку.

**L15, L16.** `CHANGELOG.md`: в 0.1.0 `Job` — «a cancellable piece of
asynchronous work», а не `Future`; в «Breaking changes» — класс, который сам
реализует `JobContext`, добавляет `abandonable`, `pause` и `runAll`.

**L17 и L15 `solo`.** Отступ `return database;` на `cleanup.md`, двойные пустые
строки — в страницах ядра и в `errors.md` и `streams.md` `solo`, с переводами.
Сторож — `doubled_blanks` в `tool/check_line_width.py`: Markdown под теми же
корнями, вне блоков кода, две пустые строки подряд — красное. Шесть тестов
в `check_line_width_test.py`, фраза в `docs/conventions.md`, шаг гейта
переименован в «Line width and doubled blank lines». На дереве до волны сторож
находит четырнадцать строк, после — ни одной.

**L18.** README: «An error that comes after the cancellation has no outcome to
carry it».

**L19.** `outcomes.md`: `done` и `value`, прочитанные после микротаски,
на которой провал ушёл в зону, исход отдают, а зону уже не остановят; в таблице
«Observes the failure?» строка «too late: the zone has heard the error». Тест
в `outcomes_rakes_test.dart`.

Все правки оригиналов переведены тем же коммитом, сверка
`tool/check_translations.py` зелёная.

## CHANGELOG

L15 и L16 — сами записи `CHANGELOG.md`, выше. Остальное записей не требует:
поведение не менялось, менялись слова о нём.

## Проверки

- `packages/async_job`: `dart format` без изменений, `dart analyze` —
  `No issues found!`, `dart test` — 1678 зелёных (до волны 1643);
  `example/example.dart` и `example/quick_start.dart` печатают свои трассы.
- `packages/solo`: 1995 зелёных, пример — 111; `packages/flutter_solo`: 230,
  пример — 4. Сняты до правок по ревью: те `solo` и `flutter_solo` не касаются.
- Стенды `vs-bloc` и `accumulation` со сверкой трасс — зелёные.
- Пол, `tool/archive_floor.py` на Flutter 3.27.0 по копии с коммитом волны
  до правок по ревью: пять корней зелёные.
- Мутация `if found or doubled:` в `if found:` в `check_line_width.py` краснит
  новый тест выхода.
- `reflow.py --check`, `check_line_width.py`, `check_doc_shape.py`,
  `check_page_code.py`, `check_links.py`, `check_translations.py`, тесты
  питоновских скриптов — зелёные.

## Ревью

Opus в отдельной копии дерева, отвязанный worktree на `41d04884` с волной
поверх. Ревьюер прогнал гейт ядра, проверки документов и тесты питоновских
скриптов, собрал листинг «The whole engine» со своим `main`, снял цитаты
провалов `testing.md` своим `dart test` и откатывал правки мутациями: каждая
краснила названный тест. Все шестнадцать находок он признал закрытыми, две —
частично; расхождения с вердиктами M3, M6, M7 и L2 — обоснованными. Его
находки, все исправлены этим же коммитом:

1. Medium. Итоги не дописаны в вердикты, `docs/handoff.md` не тронут. Дописаны.
2. Medium. Строка таблицы `groups.md` говорила, что при успехе группа ждёт
   уборки каждой ветки, а его зонд показал уборку, которая приходит после
   значений. Моя первая правка — «уборка, зарегистрированная до решения
   группы» — тоже была неверна: сторож показал, что уборка, зарегистрированная
   до своей, выполняется до значений. Окно — регистрация после своей уборки,
   пока ветка ждёт уборки остальных; так и сказано, два теста держат обе
   стороны.
3. Medium. Отчёт говорил `No issues found!`, а `dart analyze` давал пять info
   в новом коде тестов. Исправлены все пять.
4. Low. Старая формулировка о `discard` осталась на `cancellation.md`, в записи
   0.1.0 `CHANGELOG.md` и в приватном dartdoc `_Cleanup`, а у `solo` —
   на `resources.md` и в `CHANGELOG.md`. Исправлены все, с переводами.
5. Low. Фраза `groups.md` об `onDiscard` списка снова говорила через значение.
   Теперь «when the branch does not end `Done`».
6. Low. Стенд раздела «Refusing while the job waits» гонит итоговую очередь,
   где цикл стартует микротаской, и отмена приходит до старта первой задачи,
   а проза говорила «while the first one runs». Проза теперь «while it waits in
   the queue»: верно для обеих очередей.
7. Low. Выход `check_line_width.py` по двойным пустым строкам не держал ни один
   тест. Три теста `TheExitCode`.
8. Low. `testing.md`: «awaits» вместо «reads» у `job.done`. Исправлено.
9. Low. `outcomes.md`: строка L19 разрывала пару строк о `done` и `value`,
   а фраза давала `value` «исход». Строка переставлена, фраза говорит, что
   получает каждый.
10. Low. Рецепт M6 не говорил ни где помнить услышанное, ни о константных
    ошибках. Дописано, с тестом.
11. Low, косметика: оборванная строка dartdoc `onError`, пустой `onDispose`
    в тесте, падеж в строке русской таблицы `testing.md`. Исправлены.

Повторного ревью правки по его находкам не было; находки 2, 7 и 10 держат новые
тесты.
