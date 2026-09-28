# `async_job`: README и пример по находкам ревью

> **Состояние на 2026-09-28:** сделано, в дереве, не закоммичено;
> независимое ревью нашло шесть мест Low, все приняты, одно частично.
> **Что это:** отчёт о правке `packages/async_job/README.md`, его перевода
> `packages/async_job/README.ru.md`, примера `example/example.dart`
> и сторожа `test/readme_recipe_test.dart` по находкам
> `2026-09-26-async-job-project-review.md`: M10, L30, L31, L35, L36 и часть
> L69, L72 и L75, которая приходится на `README.ru.md`.
> **Связанные записи:** `2026-09-26-async-job-project-review.md`,
> `2026-09-28-extending-page-report.md` (предыдущий пункт того же порядка
> работ, откуда `test/support/page_code.dart`).

README правлен по абзацам, раздела не прибавилось. Пример переписан: он
запускает задачу Quick start четыре раза и печатает, что делает каждый прогон.
Сторож README теперь исполняет каждый блок README как написано и сверяет тело
задачи в примере с README строка в строку. Зонд —
`.artifacts/2026-09-28-readme/probe_readme_test.dart`, мутации — `mutate.py`
и `mutations-2.out` там же.

## M10. После секции

Зонд: отмена на 55-й мс, пока пишется версия. Журнал `opened, migrated, cancel,
version written, ready flag written, onCancel, section returned, closed`, исход
`Cancelled(manual)`. Секция возвращается обычным образом, отмена приходит
на выходе из неё, `onCancel` срабатывает тогда же, тело доходит
до `return database`, а исход всё равно `Cancelled`, и `discard` закрывает
базу.

Фраза «After the section, the request takes effect and the next context
checkpoint throws `Cancelled`» заменена на то, что показал зонд: задача
принимает отмену, когда секция закрывается, тело доходит до `return database`,
но задача кончается `Cancelled`, и `discard` закрывает базу; секция бережёт
шаг, а не результат. Сторож — тест «a cancellation the section held lands as
the section closes, and the body goes on to return» и последний прогон примера.

## L31. `Job.deferred`, `CancelToken`, таблица

Зонд: `readyFlag()` через `Job(...)` без отмены даёт `Failed(Invalid argument
(child): starts itself; a child is made with Job.deferred …)`, флаг пишется уже
после `closed`, ошибка уходит в зону.

- В пункт про `uncancellable` вошла фраза: `readyFlag()` делает задачу через
  `Job.deferred`, запуск остаётся за `ctx.run`, а задачу из `Job(...)`
  `ctx.run` не принимает и бросает `ArgumentError`. Сторож — «a child made with
  Job(...) is refused by ctx.run».
- В пункт про `onCancel`: `CancelToken` принадлежит клиенту базы, а не пакету.
  Указатель на пример называет обе имитации, `Database` и `CancelToken`.
- Строка таблицы о детях: `Job.deferred`, `ctx.run`, `ctx.runAll`, `ctx.each`,
  `then`. Из строки `extending.md` «deferred start» ушло в строку детей, там
  теперь `JobBase`, `JobContextBase`, your own engine.

## L30. Что уже есть в Dart

Зонды, обе стороны сравнения:

- `Database.open().timeout(10 ms)`: `TimeoutException`, база открывается
  на 20-й мс и никем не закрывается.
- `CancelableOperation.fromFuture(Database.open(), onCancel: …)`, `cancel()`
  на 10-й мс: `onCancel` вызван, и `cancel()` ждёт его future; `value`
  не приходит; база открывается и никем не закрывается.
- `Timer(limit, job.cancel)`: работающая задача — `Cancelled(manual)`, база
  закрыта; кончившаяся — исход прежний (`Done(1)`); провал, кончившийся
  до таймера, всё равно уходит в зону: `cancel` не наблюдает исход.

Фраза «`CancelableOperation` cancels the waiting; a job owns what the work left
behind» заменена абзацем в «Why»: оба средства останавливают ожидание,
`CancelableOperation` ещё и зовёт `onCancel`, который может попросить работу
остановиться; ни одно не отвечает за то, что работа открыла, и поздно открытая
база остаётся открытой; `ctx.join` передаёт своему `dispose` и базу, открытую
после отмены. Абзац о том, чего нет в пакетах, называет таймаут одной строкой
`Timer(limit, job.cancel)`. Сторожа — группа «what Dart already has». Для
`CancelableOperation` пакет получил dev-зависимость `async`.

## L35. Ошибки, которые не стали исходом, и `solo`

«For errors from work the body no longer awaits, `Job` also provides an
observer» заменено на фразу без обещания канала: ошибка, которая не стала
исходом, например ошибка уборки, тоже уходит в зону или ни к кому, смотря
откуда пришла, а раздел «Where errors go» перечисляет каждую, с наблюдателем
и без. Сверено с таблицей `doc/observing.md`: уборка — пятая строка, зона;
ошибка после принятой отмены — третья, никто.

Абзац о границах ядра в «Why» сведён к одной фразе со ссылкой на раздел
`## solo`: чего в `async_job` нет, и что это добавляет `solo`. Подробности —
очередь, одна корневая задача, реэкспорт — остались только в разделе `## solo`.
Требование владельца «упоминание `solo` следует из границ ядра» соблюдено.

## L36. Пример и три копии

Пример запускает задачу четыре раза: без отмены (база возвращается,
и вызывающий её закрывает), отмена во время открытия, во время миграции
и во время записи версии. Времена в примере в десять раз длиннее, чем в тесте,
чтобы на обычной машине прогон не зависел от дрожания таймеров: `dart run`
занимает около двух секунд. Строки печатает сама имитация `Database`.

Сторожа:

- «every block of the README runs in this file» и «and each of them runs whole,
  with nothing more» — копии блоков в тесте стоят между метками
  `// README: begin` и `// README: end`, и каждая отмеченная область равна
  своему блоку целиком; до ревью была только проверка `codeMissingFrom`
  по всему README против теста. Для этого в тесте стоят все четыре блока как
  написаны: флаг из «Why» (`load`, и два теста показывают, что база остаётся
  открытой), первая задача (`openingJob`), Quick start (`quickStart`).
- «the example runs the job of the Quick start as the README writes it» — тело
  задачи из README, от `Job<Database>(` до `});` в нулевой колонке, должно
  стоять в примере подряд, строка в строку, без учёта комментариев: пример
  объясняет тело своими комментариями.
- «the example runs the job to its end and cancels it at each step» — пример
  исполняется на фейковом времени, его вывод сверяется целиком.

Прежние три теста Quick start с отменой на разных шагах ушли в сверку вывода
примера: те же пути, теперь в самом примере.

## Перевод

Изменённые абзацы переведены заново. Тем же заходом README-часть трёх находок
о переводах:

- L72: «…и запоминает, чем она кончилась» в первой фразе.
- L75: «входит в правила написания» → «Поэтому отменяемое тело ждёт через
  контекст»; «запускает дочерней» → «запускает ребёнком»; «фейковое время»
  в таблице → «время под управлением теста».
- L69: «обработчики» → «слушателей».

Род `Job` (L65) не трогал: ждёт решения владельца. Сканер `humanizer-ru`
на восьми изменённых абзацах — 100 из 100, тире нет.

## Мутации

В копии пакета в scratchpad, откат копией, `cmp` после каждой.

| ID | Мутация | Итог |
| --- | --- | --- |
| e1 | `uncancellable` бросает придержанную отмену на выходе | поймана |
| e2 | `ctx.run` принимает задачу из `Job(...)` | поймана |
| e3 | `join` не отдаёт `dispose` значение, пришедшее после отмены | поймана |
| d1 | из Quick start README убран `onCancel` | поймана |
| d2 | в Quick start README `discard` → `dispose` | поймана |
| d3 | первая задача README отменяется во время открытия | поймана |
| d4 | в примере секция заменена на `join` | поймана |
| d5 | флаг в примере сделан через `Job(...)` | поймана |
| d6 | последний прогон примера отменяется во время миграции | поймана |
| d7 | копия Quick start в тесте: `discard` → `dispose` | поймана со второго раза |
| d8 | из блока с флагом убрана вторая проверка | поймана |
| d9 | из первой задачи README убрано чтение | поймана |
| r8 | из первого блока README убрана последняя строка | поймана после ревью |
| t2 | в копию теста вставлена строка между кусками | поймана после ревью |

d7 в первом прогоне выжила: тест M10 повторял первые строки Quick start,
и фрагмент README находился в нём, а для отмены во время открытия `dispose`
и `discard` неразличимы. Тело в тесте M10 записано иначе, и во втором прогоне
d7 поймана. r8 и t2 — выжившие мутации ревьюера (R8 и T2), см. находку 6 ниже;
итог — `mutations-4.out`.

## Проверки

`packages/async_job`: `dart format` чисто, `dart analyze` без замечаний,
`dart test` — 837, `dart doc --dry-run` без предупреждений. Из корня:
`reflow.py --check`, `check_line_width.py`, `check_translations.py`,
`check_links.py`, `check_doc_shape.py`, `build_site_test.py` — чисто.

## Независимое ревью

Ревьюер Opus в копии дерева на HEAD с правкой; отчёт, зонды и мутации —
`.artifacts/2026-09-28-readme/reviewer/`. High и Medium нет, шесть мест Low.
Каждое изменённое утверждение README ревьюер проверил зондом, M10 закрыта
точно; из 35 его мутаций пойманы 28, выжившие разобраны ниже. Находки 1 и 2 я
повторил своим зондом (`.artifacts/2026-09-28-readme/probe_rev_test.dart`),
остальные проверил чтением.

1. **`CancelableOperation` на стороне Dart.** `value` после `cancel()`
   не завершается никогда, «stops it» неточно; и `onCancel` может забрать
   поздний результат сам. Мой зонд:
   `[closed db, cancel returned, value completed: false]`.

   Вердикт: принято. «stops delivering its value on `cancel()`»; «Neither holds
   on to what the work opens: unless an `onCancel` is written to catch it…»;
   к `ctx.join` добавлено «with no code written for the cancellation» — это
   и есть разница. Сторож — «an onCancel written to catch the late database
   closes it».

2. **Таймер живёт до лимита, а `job.done` глушит провал.** Мой зонд:
   `viaDone=false pending@5ms=1 zone=[Bad state: boom]`,
   `viaDone=true pending@5ms=0 zone=[]`.

   Вердикт: принято частично. Абзац говорит, что таймер живёт до лимита и что
   снимать его через `job.done` значит наблюдать исход, и провал до зоны
   не дойдёт. Свою причину `TimedOut` не показывал: строка перестала бы быть
   одной. Сторож — «the timer lives until the limit, and stopping it through
   job.done keeps a failure from the zone».

3. **L35 без наблюдателя.** Вердикт: принято. «goes to the zone as well by
   default, or to nobody unless the job has an observer», в переводе так же.

4. **Эллипсис в переводе.** Вердикт: принято. «перестаёт отдавать значение
   по вызову `cancel()` и вызывает при этом свой `onCancel`».

5. **«кончается» и «запускает ребёнком».** Вердикт: принято в тронутых фразах:
   «завершается» в них и в первой фразе README, «запускает ребёнка,
   `database.readyFlag()`: отдельную задачу…». Весь README к одному глаголу
   приведёт последний проход `humanizer-ru` из порядка работ.

6. **Сторож в одну сторону.** R8 и T2 выживали. Вердикт: принято. Копии блоков
   в тесте отмечены метками, и тест требует, чтобы отмеченные области совпали
   с блоками README целиком и по порядку. r8 и t2 в моём прогоне пойманы. Сверх
   предложенного: не только тело `quickStart`, а все три блока.

Замечания без оценки: длинный пункт про `ctx.uncancellable` оставил одним — все
три темы про один шаг Quick start; деталь «next checkpoint throws» для Quick
start не нужна и живёт на `cancellation.md`. C8 и C9 ловит остальной набор, C10
и R10 эквивалентны или про прозу.
