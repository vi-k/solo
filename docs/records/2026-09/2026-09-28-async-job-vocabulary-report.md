# `async_job`: чистка словаря по M22, M23 и L27

> **Состояние на 2026-09-28:** сделано; независимое ревью нашло восемь мест
> Low, все приняты, седьмое частично.
> **Что это:** отчёт о чистке словаря dartdoc, страниц `doc/`, README,
> `## Unreleased` в `CHANGELOG.md` и русских переводов `async_job` по находкам
> M22, M23 и L27 из `2026-09-26-async-job-project-review.md`.
> **Связанные записи:** `2026-09-26-async-job-project-review.md`,
> `2026-09-28-async-job-readme-report.md` (предыдущий пункт того же порядка
> работ).

Решение владельца по M22, 2026-09-28: «оставляй оба слова и имя файла». Ядро —
«core», надстройка над ним — «engine», библиотека остаётся `engine.dart`.
Словарь, по которому шла правка:

| Предмет | Английский | Русский |
| --- | --- | --- |
| машинерия самого пакета | core (было engine, kernel) | ядро (было движок) |
| библиотека поверх ядра | engine, an engine of a domain | движок |
| ошибка без исхода и `onUnanswered` | answer for | отвечать за |
| наблюдение исхода | observe | наблюдать |
| ресурсы, открытые работой | look after | следить |
| отмена, которую задача приняла | accepted | принята |
| то, что возвращает `then` | continuation (было `then` job, tail) | продолжение (было задача `then`, хвост) |
| начало цепочки | source (было head) | источник (было голова) |
| колбэк `each` и `then` | callback (было handler) | колбэк (было обработчик) |

`HandlerCancelReason` и `CancelReason.handler` остались: это имена API, и там
handler — само тело.

## M22. Core и engine

В `lib/` 43 места, где «the engine» или «kernel» значили само ядро, стали «the
core»: `Job.ignore` («Tells the core…»), `isRunning`, `isCancelled`, `Failed`,
`Cancelled`, `onDispose`, `unattended`, `pendingCancel`, вводные абзацы
`async_job.dart` и `engine.dart` и внутренние комментарии. «An engine of a
domain», «engines built on [JobBase]», «an engine waiting for the job» — про
надстройку и остались. Сообщение ошибки `ctx.run` уже говорило «is not a job of
this core».

Страницы: заголовок `outcomes.md` «Telling the engine it is handled» стал
«Telling the core it is handled», перевод — «Сказать ядру, что она обработана»;
ссылок на старый якорь нет ни в документах, ни на сайте. В `children.md` три
«kernel» и «engine's report», в `extending.md` одно «while the engine cleans
up» — всё «core». Остальные «engine» в `extending.md` — свой движок читателя,
так и задумано. `cleanup.md` «whatever an engine holds» — тоже надстройка.

В `## Unreleased` `CHANGELOG.md` семь «kernel» стали «core». Выпущенные разделы
`0.2.0` и `0.1.0` не тронуты: это история. В `solo` «engine» везде значит сам
контроллер, то есть надстройку, и совпадает с решением; «kernel» было в четырёх
комментариях кода, стало «core».

## M23. «Answer for» — только маршрут `onUnanswered`

- README «nothing answers for what the work has already opened» и «A job
  answers for it» — «looks after»; перевод «не следит никто» и «`Job` следит».
- Строка таблицы README про страницу исходов: «who is answerable for an
  error» — «observing a failure», перевод «наблюдение за провалом».
- `children.md` «that counts as answering for them» — «as observing them»; «so
  its steps can be answered for» — «can stop for a cancellation».
- `cancellation.md` «the body answers at a checkpoint» — «stops».
- Внутренний комментарий `cancelWith`: «have been answering for that
  cancellation» — «reporting».

Остальные «answer for» в dartdoc и на страницах — маршрут `onUnanswered`,
а «answers `true`» и «the answer» в смысле ответа на вопрос — обычный глагол,
не термин. `job_base.dart:169-170` из находки к этому времени уже говорил
«transfers responsibility».

## L27. Accepted, continuation, callback

«Marked cancelled» и «is not marked» в dartdoc публичных и защищённых членов —
16 мест — стали «has accepted a cancellation», «accepts it at once», «accepts
no cancellation»: `isCancelled`, `then`, `pendingCancel` (оба), `heldCancel`,
`enterUncancellable`, вводный абзац `JobContext`, `join`, `uncancellable`,
`onCancel`, `each`, `unattended` (два), `throwIfCancelled`, класс `Cancelled`.
Во внутренних комментариях «mark» — имя механизма, и слово там осталось.

«`then` job», «tail» и «head» в прозе `children.md` и `outcomes.md` — теперь
«continuation» и «source». Переменная `tail` в коде осталась: это имя. Фраза
«`continuation` is the engine's own word for it» после сообщения ошибки ушла:
слово теперь то же, что на странице.

«Handler» колбэка `each` — в dartdoc `each`, в dartdoc порядка провалов
в `job_base.dart` и в четырёх комментариях `job_stream.dart` — стало
«callback»; в русской `children.md` «обработчик» колбэка `then` стал
«колбэком», как в оригинале.

В `## Unreleased` заменены `then` job, tail, head и handler. Слово «mark» там
сквозное, в описаниях исправлений, и уходит в переписывание раздела — следующий
шаг порядка работ (M19, M20, M21, L32, L34).

## Перевод

Изменённые абзацы `children.md` переписаны под средний род «продолжения».
Попутно в них сняты тире, а в абзаце о `discard` источника местоимение «он»,
которое читалось как источник, стало «`discard`». «Каждая задача `then` —
корневой `Job` ядра» стала «Каждое продолжение относится к корневым `Job`
ядра». Сканер `humanizer-ru` на 25 изменённых абзацах — 90 из 100, и все десять
баллов сняты за служебные заголовки `##` самой выборки; тире нет.

## Независимое ревью

Ревьюер Opus в копии дерева на HEAD с правкой; отчёт, зонд и сравнение слов —
`.artifacts/2026-09-28-vocab/reviewer/`. Зонд подтвердил переписанный dartdoc
`isCancelled`, `join`, `onCancel`, `uncancellable`, `heldCancel`, `then`,
`each` и класса `Cancelled`; переливка абзацев dartdoc не потеряла
и не задвоила ни слова. Находки 2 и 3 я проверил по коду, остальные — поиском.

1. **«A handler of `ctx.each`» в `observing.md`** и «обработчика» в переводе.

   Вердикт: принято. «a callback of `ctx.each`», «колбэка `ctx.each`».

2. **`throwIfCancelled` против `isCancelled`.** `isCancelled` — это
   `_pendingCancel != null || _outcome is Cancelled`, а dartdoc говорил только
   о принятой отмене; `throwIfCancelled` про задачу, законченную движком
   руками, говорил «never accepted it».

   Вердикт: принято. `isCancelled` — «has accepted a cancellation, even if the
   body still runs, or has ended with one»; `throwIfCancelled` — у такой задачи
   нет `pendingCancel`, и отмена живёт только в исходе.

3. **`uncancellable` абсолютнее кода.** Секция держит только отклоняемую отмену
   (`job_base.dart:747`), неотклоняемая принимается сразу.

   Вердикт: принято. «accepts no cancellation it may refuse», как
   у `enterUncancellable`.

4. **«Over the mark» в защищённом `notifyObserver`.**

   Вердикт: принято. «after such a job accepted a cancellation».

5. **«Answer for the outer» в `throwIfUnattended`** — там это «выдать себя за».

   Вердикт: принято. «pass for the outer».

6. **`## Unreleased`:** «`onCancel` handler» и «looks after what it opened».

   Вердикт: принято. «`onCancel` hook», «what the work opened».

7. **Вне заявленной области:** «kernel» и «the engine» в смысле ядра в тестах,
   tail и head в именах тестов, «kernel» в `## Unreleased` `solo`, «`then` job»
   в `packages/solo/doc/children.md`.

   Вердикт: принято частично. «kernel» и «the engine» в тестах — «core»; имена
   тестов `children_rakes_test.dart`, которые повторяют страницу, —
   «continuation» и «source»; `solo/CHANGELOG.md` — «on the core».
   `then_test.dart` оставил: там tail — последнее звено цепочки в имени теста,
   читатель документации его не видит. Словарь страниц `solo` — отдельная
   работа вместе с переводом, в эту правку не входит.

8. **«The tails of its branches» в `runAll`.**

   Вердикт: принято. «does not wait for its branches to finish».

## Проверки

`packages/async_job`: формат чистый, анализ без замечаний, `dart test` — 837,
`dart doc --dry-run` — 0 предупреждений. `packages/solo`: формат и анализ
чистые, 803. Из корня: `reflow.py --check`, `check_line_width.py`,
`check_translations.py`, `check_links.py`, `check_doc_shape.py` — чисто.
