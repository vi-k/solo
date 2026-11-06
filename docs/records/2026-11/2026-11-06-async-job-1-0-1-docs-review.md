> **Состояние на 2026-11-06:** ревью проведено, у каждой находки стоит
> вердикт с итогом. Принятые исправлены по слову владельца «исправляй»
> коммитом «docs: close the findings of the async_job 1.0.1 docs review»,
> находки ревью этой правки — коммитом «docs: tighten the fixes of the
> async_job 1.0.1 docs review»; на pub.dev правка придёт со следующим выпуском
> ядра. Отказы — решение 147 и дополненное решение 142 в `docs/settled.md`.
> **Что это:** ревью документации `async_job` 1.0.1, как она вышла, одним
> ревьюером на Fable: оценки документации и агента-пользователя, вход README,
> находки D и A, читаемость каждой страницы.
> **Связанные записи:** `2026-10-31-async-job-project-review.md`,
> `2026-11-06-async-job-1-0-1-release-report.md`,
> `2026-11-04-core-readme-entry-design.md`.

# Ревью документации async_job 1.0.1

## Как это делалось

Владелец спросил 2026-11-06 после выпуска 1.0.1, нужно ли ревью ядра
с оценками. Я предложил не полное ревью, а одну область — документацию: `lib/`
с 1.0.0 не менялся, а полное ревью 2026-10-31 уже поставило оценки коду.
Владелец: «давай на патч».

Дерево на `6a79b3b8`, коммит тега `async_job-v1.0.1`. Ревьюер — Fable 5.1, как
у ревью 2026-10-31, чтобы оценки стояли рядом; субагент Claude Code в своей
копии репозитория на этом коммите. Задание — в конце записи. Прошлых оценок
ревьюер не видел: `docs/records/` задание закрыло. Отслеживаемых файлов он
не тронул.

Как я принимал. Находки сверены с деревом моими командами: `readAll`
в `example/quick_start.dart` молчит (D1); README просит `^0.1.0` и не называет
блок `diagnostics:`, README плагина просит `^0.1.1` (D2); клетка `ctx.pause`
в `reference.md` — «Ends and throws» (D3); dartdoc `Job` считает наблюдением
ручку `shared`, «Four words» — нет (D5); `riverpod-and-bloc.md` называет класс
README (D8); фразы о голом `await` в README и `why.md` нет (A1). Зонды ревьюера
жили в его копии и в репозиторий не перенесены: их вывод процитирован в отчёте.

Оценки рядом с ревью 2026-10-31. Это два прогона двух ревьюеров с разными
заданиями, и разница в балл между ними — разброс, а не сдвиг:

| Что | 2026-10-31 | 2026-11-06 |
| --- | --- | --- |
| Документация | 8 | 8 |
| Для ИИ-агентов | 8 (обе роли) | 7 (только пользователь) |
| `README.md` | 8 | 8 |
| `why.md`, `reference.md` | — | 8, 7 |
| `cancellation.md` | 6 | 8 |
| `error-rules.md` | 6 | 5 |
| `cleanup-rules.md` | 7 | 6 |

Остальные страницы разошлись не больше чем на балл. Короткий вход оценку README
не поднял: ревьюер снял её за абзац Install и за умолчание о голом `await`,
а не за длину, за которую её снимали 2026-10-31.

Исправление. Владелец 2026-11-06: «исправляй». Принятые находки сделаны одним
коммитом «docs: close the findings of the async_job 1.0.1 docs review»,
с переводами и записью в разделе «Unreleased» списка изменений. Итог каждой —
в конце её вердикта. Сторож длины входа в `readme_recipe_test.dart` держал
«Guides» не дальше 125-й строки, и на `HEAD` раздел стоял ровно на ней. yaml
плагина, фраза о голом `await` и строка `rows read` добавили шесть строк,
и порог поднят до 131; 95 строк до конца Quick start держатся. Под нагрузкой
машины, средняя 87–114, два теста на время `let_go_together_test.dart` падали
в общем прогоне и проходили одни; набор с `-j 2` — +1902, все прошли.

Ревью правки. Независимый ревьюер на Opus прочёл коммит и дал шесть находок,
все приняты и исправлены вторым коммитом «docs: tighten the fixes of the
async_job 1.0.1 docs review». R1: фраза Quick start говорила, что отмена ждёт
следующего вызова через `ctx`, а задача принимает отмену сразу, `onCancel`
срабатывает внутри `cancel()`, ждёт только тело, и не всякий вызов `ctx`
контрольная точка; теперь «the body runs on to the next checkpoint or its end».
R2: на `errors.md` ручка, отменённая раньше провала, оставляла провал
ненаблюдаемым, хотя его несёт другая ручка того же источника; теперь
ненаблюдаемым он остаётся, когда нести его больше некому. R3: итог D5 ниже
говорил, что ручка гасит зону сама, а гасит её только ручка, которую ждут. R4:
на `cancellation.md` «does not do it» читалось как «не отменяет», а задача
отменяется и только не кончается. R5: «which throws» цеплялось к значению,
а перевод говорил «получить ошибку»; теперь `value` бросает. R6: комментарий
сторожа трассы не называл строку чтения. Зонды R1, R2 и R4 повторены моим
прогоном, выводы те же: `onCancel` на 40 мс, тело после голого `await` на 210
мс, `ctx.log` не бросил; вторая ручка получила `Failed`, зона молчала;
`isCancelled true`, `isFinished false`. Ревьюер предлагал в R1 «reports it»
ради строки; оставлено «reports such an `await`», и «Guides» остался на 131-й
строке, порог тот же.

Ниже — отчёт ревьюера без правок прозы. Конец раздела ПРОГОН называл зонды
путём в копии ревьюера; путь заменён словами. Вердикты — отдельным абзацем
в конце каждой находки.

## Отчёт ревьюера

Копия на `6a79b3b8` (тег `async_job-v1.0.1`). Читал всю документацию пакета как
вышла: README, 18 страниц `doc/`, три примера, раздел 1.0.1 CHANGELOG, dartdoc
публичного API (`job.dart`, `job_context.dart` до `JobContextBase`,
`outcome.dart`, `observer.dart`, `async_job.dart`, `engine.dart`). Код `lib/`
не ревьюил. `docs/settled.md` прочитан целиком; `docs/handoff.md`,
`docs/backlog.md`, `docs/records/` не открывал. Конфликт с `AGENTS.md` (начать
с handoff, обновлять его, коммитить) решён в пользу задания: ничего
не коммичено, handoff не читан и не правлен.

**Отклонение от задания:** файл `.review-tmp/report.md` не записан — харнесс
отказал инструменту Write с формулировкой «Subagents should return findings as
text, not write report files». Обходить отказ через shell не стал. Каталог
`.review-tmp/` создан и пуст; весь отчёт — в этом сообщении.

### 1. Оценка

**Документация: 8/10.** Поднимает: ни одно утверждение входа, которое я
проверил зондом, не разошлось с кодом (десять зондов, все совпали с текстом);
трассы под кодом совпадают с запуском примеров строка в строку; форма «первая
попытка → трасса → разбор» работает почти на каждой странице; словарь един
от README до dartdoc; README стал коротким и конкретным, а `why.md`
и `reference.md` ничего не потеряли при переносе. Опускает: вход не говорит
словами главное, о чём весь пакет, — что голый `await` в теле отмену не слышит;
трасса Quick start не доказывает то, что проза утверждает про `join`; абзац
об `async_job_lints` путает «warnings» и «lints» и не говорит, что `bare_await`
выключен, пока его не назовут; две страницы правил (`error-rules.md`,
`cleanup-rules.md`) написаны прозой там, где нужен список, и читаются заметно
тяжелее остальных.

**Агент-пользователь: 7/10.** Поднимает: система типов отсекает
`ctx.run(Job(...))`, dartdoc каждого члена — договор с главной ловушкой
и ссылкой на страницу, таблица `reference.md` — то, что агент прочтёт первым
и правильно; `doc/*.md` попадают в архив pub, так что агент с кэшем pub видит
страницы; тексты исключений (`already has a continuation… call shared()`) сами
указывают исправление. Опускает: три привычки, которые компилируются и молча
ведут себя иначе, README не называет ни словом, а на страницах они лежат далеко
от входа: голый `await` в теле (`cancel()` ждёт его 1 с, зонд G), `Job(...)`
внутри тела — не ребёнок (отмена родителя до него не доходит, зонд I),
`await job.value` без слова о том, что он бросает `Cancelled`. Плагин, который
ловит первую из них, README называет, но не говорит, что правило надо включать
по имени.

### 2. Сводка

- Патч сделал то, что обещал: README — короткий вход, `why.md`
  и `reference.md` — перенос без потерь, трассы примеров совпадают.
- Десять зондов по утверждениям входа и привычкам агента — все сошлись
  с документацией. Расхождений документа с кодом не нашёл.
- Главная дыра входа — не в точности, а в умолчании: ни README, ни `why.md`
  не говорят словами, что голый `await` — не точка отмены. Это первое, что
  напишет и человек, и агент.
- Трасса Quick start не отличает `join` от `abandonable`: `readAll` ничего
  не печатает, и «`ctx.join` waited for the read» остаётся на слово.
- Абзац об `async_job_lints` в README: «turns on its warnings; its lints are
  turned on by name» — различие не объяснено, а `^0.1.0` отстаёт от `^0.1.1`
  в README самого плагина (0.1.1 вышел 2026-11-04, за два дня до 1.0.1).
- `reference.md`: клетка `ctx.pause` «Ends and throws» читается как «дождётся
  конца паузы», хотя пауза бросает сразу (зонд C: 32 мс из 1 с); список «What
  the cells leave out» разорван пустой строкой на два; «Four words» не считает
  наблюдением ручку `shared`, которую dartdoc `Job` считает.
- Хуже остальных читаются `error-rules.md` (5/10) и `cleanup-rules.md` (6/10):
  таблицы с клетками-абзацами и по четыре абзаца, пересказывающих строки
  таблицы.

### 3. Вход

**README → `why.md` → `reference.md` работает.** Первый экран отвечает «что это
и зачем» в двух абзацах, Quick start даёт одну задачу с трассой, «Walking away
from a call» — вторую, и вместе они ставят `join` против `abandonable`, то есть
главный выбор пакета. Третий абзац и таблица Guides ведут дальше. Со второго
вопроса читатель находит страницу по таблице: описания строк говорят, что
на странице, а не как она называется.

**Что потерялось при переносе.** Ничего по смыслу: «Why», «A fuller example»,
таблица контекста и «Four words» перенесены дословно; ссылки на `doc/`
переписаны относительными, `[solo](#solo)` стал абсолютным адресом на README.
Пропали две фразы старого Quick start: «the body starts on the next microtask»
и «`started: false`». Первое заменено на «A job cancelled right away never
starts its body» — лучше; второе живёт на `outcomes.md`.

**Что повторяется.** Фраза «What a job adds to a `Future`, a flag and
`CancelableOperation`, and a fuller example» стоит трижды: третий абзац README,
строка Guides, вступление `why.md`. Для `reference.md` — дважды. Это цена того,
что третий абзац и таблица делают одно и то же.

**Чего входу не хватает.** (1) Одной фразы о голом `await` — A1. (2) Трассы,
которая доказывает `join` — D1. (3) `why.md` кончается трассой и никуда
не ведёт; на GitHub, куда pub.dev отправляет по ссылке, боковой панели нет —
D7. (4) Второй абзац README не говорит, что `value` бросает — A2.

### 4. Находки по документации

**D1. Medium. README, «Quick start».** Проза: «`ctx.join` waited for the read
it had already started, and the rows never reached the body». Трасса:
`database opened / database closed / cancelled: manual`. `Database.readAll`
в `example/quick_start.dart` ничего не печатает, поэтому трасса одинакова для
`join` и для `abandonable` и не доказывает единственное, что раздел утверждает
о `join`. «Walking away» своё утверждение доказывает: строка `quote answered`
стоит после `Cancelled(manual)`. Читатель, который сравнит две трассы, увидит
доказательство только у второй. Доказательство: запуск
`dart run example/quick_start.dart`, вывод выше, плюс чтение `readAll` (строки
37–40). Предлагаю: `readAll` печатает `rows read`, трасса становится
`database opened / rows read / database closed / cancelled: manual`, и фраза
«waited for the read» получает строку в трассе.

Вердикт: принять. `readAll` молчит — сверено чтением примера. С `rows read`
трасса `join` кончает чтение до `database closed`, а у `abandonable` этой
строки до закрытия не было бы: трасса начинает доказывать прозу. Правка
примера, README, перевода и сторожа трассы README. Итог: сделано коммитом
«docs: close the findings of the async_job 1.0.1 docs review». `readAll`
печатает `rows read`, трасса README и перевода — `database opened`,
`rows read`, `database closed`, `cancelled: manual`; сторож «the Quick start
earns every line of it» сверяет её с запуском примера без правки.

**D2. Medium. README, «Install».** «Naming it in `analysis_options.yaml` turns
on its warnings; its lints are turned on by name, as its Install section
shows» — читатель не знает, что у плагина правила двух родов, и из yaml под
абзацем видит только имя плагина. В README плагина: три правила — warnings
и включены с плагином, два — `bare_await` и `catch_without_check` — lints
и включаются по имени. Именно эти два ловят ошибки, о которых README говорит
в этом же абзаце («a wait in cleanup that never happens» — это warning
`ctx_in_cleanup`, а голый `await` — выключенный `bare_await`). Читатель,
который скопирует yaml, не получит `bare_await` и не узнает об этом. Второе:
`^0.1.0` против `^0.1.1` в README плагина; `async_job_lints-v0.1.1` помечен
2026-11-04, `async_job-v1.0.1` — 2026-11-06, то есть на момент выпуска 1.0.1
строка уже отставала (ограничение верное, но два README называют две версии).
Доказательство: по чтению; `git log -1 --format=%ci` обоих тегов. Предлагаю:
одна фраза «Three of its rules come on with the plugin; `bare_await`, which
reports a plain `await` in a body, and `catch_without_check` are turned on by
name» и yaml с блоком `diagnostics:` из README плагина; версия `^0.1.1`.

Вердикт: принять. Сверено: README ядра просит `^0.1.0` без `diagnostics:`,
README плагина — `^0.1.1` с блоком, где `bare_await` и `catch_without_check`
включены по имени. `^0.1.0` пускает 0.1.1, и запись выпуска 1.0.1 оставила его
нарочно, но читатель видит две версии и yaml, который двух правил не включает.
Правка — как предложено, вместе с A1. Итог: сделано коммитом «docs: close the
findings of the async_job 1.0.1 docs review». Разошлось с предложенным: абзац
Install не описывает правила, а говорит, что два линта включаются по имени,
и ссылки на раздел Install плагина больше не даёт — что делает `bare_await`,
сказано в Quick start (A1), а строки входа на счету. yaml — блок
с `version: ^0.1.1` и `diagnostics:`, как у плагина; сторож формы блока
в `readme_recipe_test.dart` переписан под него.

**D3. Low. `reference.md`, «The context at a glance».** Клетка `ctx.pause` /
«Cancelled while it runs»: «Ends and throws». Рядом `abandonable` — «Throws at
once», `join` — «Waits, then throws». «Ends and throws» читается третьим
вариантом: дождётся конца паузы и бросит. `time.md` говорит обратное: «throws
`Cancelled` at once … and its timer is cancelled with it». Доказательство: зонд
`probe_readme.dart`, раздел C — пауза 1 с, отмена на 30 мс, «cancel() returned
after 32 ms; outcome: Cancelled(manual)». Предлагаю: «Throws at once, and
cancels its timer».

Вердикт: принять. Клетка сверена, `time.md` говорит «at once»; это точность
справочника, а не плотность. Итог: сделано коммитом «docs: close the findings
of the async_job 1.0.1 docs review». Клетка — «Throws at once», в переводе
«Бросает сразу»; без «and cancels its timer» из предложения: о таймере говорит
`time.md`. Сторож клетки «pause throws at once» и словарь перевода
в `readme_recipe_test.dart` поправлены.

**D4. Low. `reference.md`, «What the cells leave out».** Список разорван пустой
строкой после пункта о `ctx.each` (строки 47–49): рендерится как два списка,
второй начинается с `onCancel` без связи с первым. То же было в README 1.0.0
и переехало. Доказательство: по чтению. Предлагаю: убрать пустую строку.

Вердикт: отклонить, решение 147. По CommonMark пункты одного маркера через
пустую строку — один рыхлый список, а не два. Пустая строка делит пункты
о членах, которые ждут и запускают, и пункты о колбэках регистрации.

**D5. Low. `reference.md`, «Four words», строка «Observe a failure»; то же
`errors.md` «An observer» (список из трёх пунктов) и `outcomes.md` таблица
«Observes the failure?».** Все три называют `done`, `value`, `ignoreFailure()`
и `then`. Dartdoc класса `Job` (строки 13–15) и `chains.md` «A handle for each
branch» (строки 130–132) считают наблюдением и ручку `shared`: провал источника
несут ручки, и за него отвечают один раз через них. Читатель справочника решит,
что `shared()` без `then` оставляет провал источника неотвеченным — а это
не так. Доказательство: по чтению двух источников. Предлагаю: «…forward the
failure through `then` or a handle of `shared`…» в трёх местах.

Вердикт: принять. Сверено: dartdoc `Job` в `lib/src/job.dart` называет «a
handle of [shared]», строка «Observe a failure» `reference.md` — нет; решение
146 тоже считает ручку `shared` наблюдением. Правка в трёх местах. Итог:
сделано коммитом «docs: close the findings of the async_job 1.0.1 docs review»,
в трёх местах и в переводах. Зонд подтвердил до правки: ручка `shared()` без
`then`, которую ждут, несёт провал источника, и зона молчит, а неждаемая
отвечает за него сама; ручка, отменённая раньше провала, не несёт ничего,
и провал уходит в зону, — поэтому оговорка о продолжении на `errors.md`
распространена и на ручку.

**D6. Low. README, третий абзац и «Guides»; `why.md`, вступление.** Одна фраза
трижды (см. «Вход»). Предлагаю: третий абзац README говорит по-другому — зачем
идти на `why.md` («if a flag and a `finally` look like enough, Why a job shows
where they stop»), а описание страницы остаётся в Guides и во вступлении.

Вердикт: отклонить, решение 147. Ссылка на «Why a job» и с первого экрана,
и первой строкой «Guides» — замысел `2026-11-04-core-readme-entry-design.md`:
первый экран ведёт того, кто дальше не листает, таблица — того, кто ищет
страницу. Одна и та же фраза о странице в обоих местах — не дефект, а одно
описание одной страницы.

**D7. Low. `why.md`, конец «A fuller example».** Страница кончается трассой.
Читатель с pub.dev попадает на неё по ссылке на GitHub, где нет боковой панели
сайта, и дальше идти ему некуда, кроме кнопки «назад». Решение 107 запрещает
карты разделов во вступлениях; одна фраза в конце — не карта. Предлагаю: «The
pages go on from here: Outcomes for what `done` hands back, Cancellation for
the checkpoints the example used.»

Вердикт: принять. `why.md` — вторая ступень входа, и с GitHub с неё некуда
идти; фраза в конце не карта разделов, решение 107 её не касается. Итог:
сделано коммитом «docs: close the findings of the async_job 1.0.1 docs review»:
«The pages go on from here» со ссылками на «Outcomes» и «Cancellation»,
в переводе так же.

**D8. Low. `riverpod-and-bloc.md`, «A provider that is gone».** «`Database` is
the one of the README's quick start, reading by pages» — у `Database` README
`open()` без запроса и `readAll`, здесь `open(query)` и `readPage`. Фраза
обещает знакомый класс, а класс другой. Доказательство: по чтению
`example/quick_start.dart` и трасс страницы. Предлагаю: «a `Database` like the
README's, opened for a query and read by pages».

Вердикт: принять. Сверено: фраза стоит в строке 35 страницы, а у класса README
нет ни `open(query)`, ни `readPage`. Итог: сделано коммитом «docs: close the
findings of the async_job 1.0.1 docs review»: «like the one of the README's
quick start, but it opens for a query».

**D9. Low. `riverpod-and-bloc.md`, «A stream that cancels the job», новый абзац
1.0.1 (строки 338–348).** Первое предложение — пять строк с вставкой через
тире, внутри которой выражение
`CancelableOperation.fromFuture(call, onCancel: token.cancel).asStream()`
и ссылка. Смысл верный (проверил `asStream` в `package:async` 2.13.1: отмена
подписки отменяет операцию), но предложение не разобрать с первого раза.
Предлагаю: выражение — отдельной строкой кода, вокруг — два коротких
предложения.

Вердикт: принять. Абзац новый, вышел в 1.0.1, и решение 142 о плотности старых
страниц его не прикрывает: правится свой свежий текст. Итог: сделано коммитом
«docs: close the findings of the async_job 1.0.1 docs review». Разошлось
с предложенным: выражение осталось кодом в строке, в конце своего предложения,
а не отдельным блоком — блок Dart на странице уходит в стенд и должен
собираться. Предложение разбито на два.

**D10. Low. README, «Walking away from a call».** Раздел открывается кодом
с неопределённым `fetchQuote`, а Quick start — фразой задачи. Одна фраза
в том же роде («A job fetches a quote, and somebody cancels it while the
request is on its way») выровняла бы два раздела. Это вкус, а не дефект;
решение 71 о форме разделов на страницах `doc/` README не касается.

Вердикт: отклонить, решение 147. Задачу раздела говорит первый комментарий
кода — «Somebody left the screen while the quote was on its way», — а раздел
идёт второй сценой после Quick start, который задачу уже поставил прозой.
Ревьюер сам называет это вкусом.

**D11. Low. `error-rules.md`, «Where each error goes», таблица `answer`.**
Клетка `answered` — семь строк одного предложения с четырьмя «unless»;
за таблицей абзац «`later` promises nothing, and three of its errors…»
перечисляет три случая прозой. Это справочный материал, написанный как рассказ.
Доказательство: по чтению. Предлагаю: клетка `answered` — две–три строки,
а случаи — списком под таблицей; абзац о `later` — тоже списком из трёх
пунктов. Плотность по решению 142 правится по жалобе — считайте это жалобой
назначенного ревьюера, а не требованием.

Вердикт: отклонить, повтор решения 142 без нового довода. Решение ждёт жалобы
внешнего читателя, а назначенный ревьюер — тот следующий круг вычитки,
о котором говорят решения 132 и 142. Источники решения 142 дополнены этим
ревью.

**D12. Low. `cleanup-rules.md`, «A value that comes late».** Таблица из пяти
строк и за ней четыре абзаца, каждый начинается «Before the stack, the first
row…», «On the stack, the second row…» — пересказ строк. Самый трудный текст
пакета. Предлагаю: пояснение каждой строки — в третий столбец таблицы или
по одной фразе на строку; абзацы сократить до одного о том, почему отпускание
не ждёт разматывания. Как и D11 — под решение 142.

Вердикт: отклонить, как D11: повтор решения 142 без нового довода.

### 5. Для ИИ-агента

**A1. Medium. README, «Quick start» и первый экран.** Нигде в README и `why.md`
не сказано словами, что голый `await` в теле — не точка отмены. Первый экран
говорит «each call it awaits through `ctx.join` is a checkpoint», и из этого
надо вывести обратное. Агент с привычкой `await http.get(...)` напишет его
в тело — код соберётся, тест на успех пройдёт. Страницы говорят об этом
(`time.md` «Letting time pass», `cleanup-rules.md` «Registering after a plain
await», `observing.md`), но все три — далеко от входа. Доказательство:
`probe_agent_habits.dart`, раздел G — тело с `await Future.delayed(1 s)`,
отмена на 50 мс: «body continued after the delay at 1007 ms; cancel() returned
at 1015 ms; outcome: Cancelled(manual)»; раздел H — `timeout: 50 ms` над голым
`await` 300 мс: «outcome: Cancelled(timeout) at 303 ms». Предлагаю: одна фраза
в прозе Quick start после трассы: «A plain `await` in the body is no
checkpoint: the job learns of the cancellation at its next `ctx.` call, and
`cancel()` and a `timeout` wait that long. `async_job_lints` reports such an
`await` as `bare_await`.» Это же связывает абзац Install с кодом.

Вердикт: принять — главная находка ревью. Сверено поиском: в README и `why.md`
фразы о голом `await` нет. Решение 143 держит привычные ошибки агента в прозе
README, и эта — первая из них. Фраза в Quick start, вместе с D2. Итог: сделано
коммитом «docs: close the findings of the async_job 1.0.1 docs review».
Разошлось с предложенным: фраза стоит не после трассы, а во вступлении Quick
start, рядом с тем, что такое контрольная точка, и короче — «A plain `await` is
no checkpoint: the body runs on to the next checkpoint or its end, and
`cancel()` and a `timeout` wait that long; the lint `bare_await` reports such
an `await`», в редакции после R1 ревью правки. Зонды G и H ревьюера повторены
моим прогоном, выводы те же.

**A2. Low. README, второй абзац.** «or `await job.value` to get the value
returned by the body» — ни слова, что `value` бросает `Cancelled` и ошибку
тела. Агент с привычкой `CancelableOperation` напишет `await job.value`
в виджете и получит необработанный `Cancelled` после первой отмены.
Доказательство: зонд V — «await value threw: Cancelled Cancelled(manual)».
Предлагаю: «…or `await job.value` for the value alone: it throws the body's
error, and `Cancelled` when the job was cancelled».

Вердикт: принять. Сверено: второй абзац README о броске `value` молчит. Итог:
сделано коммитом «docs: close the findings of the async_job 1.0.1 docs review»,
короче предложенного: «`await job.value` for the value; in its place `value`
throws the error of the body or `Cancelled`», в редакции после R5 ревью правки.
Зонд V повторён, вывод тот же.

**A3. Low. `children.md`, вступление и «Running a child».** Страница говорит,
что `Job(body)` «starts by itself» и что компилятор не пустит его в `ctx.run`,
но не говорит, что будет с привычной формой
`final inner = Job(...); await ctx.join(() => inner.value)`: `inner` — корень
рядом с родителем, отмена родителя до него не доходит, `join` ждёт его
до конца. `chains.md` «Jobs that wait for the source» показывает такую форму
с `abandonable` как законную, но об отмене говорит только «`loaded` belongs to
whoever made it». Доказательство: зонд I — родитель отменён на 50 мс, «inner
finished at 314 ms; parent cancel() returned at 315 ms; parent:
Cancelled(manual); inner: Done(42)». Предлагаю: фраза в «Running a child»: «A
`Job(...)` made in the body is a root beside the parent, not its child: the
parent's cancellation does not reach it, and a `ctx.join` on its `value` waits
for it to end. Make a child instead, or cancel it in `ctx.onCancel`.»

Вердикт: принять. Фраза `chains.md` не противоречит: форма там законна, а фраза
говорит, куда отмена родителя не доходит. Итог: сделано коммитом «docs: close
the findings of the async_job 1.0.1 docs review»: фраза в «Running a child» без
совета «Make a child instead» — как сделать ребёнка, страница говорит строкой
выше. Зонд I повторён, вывод тот же.

**A4. Low. `cancellation.md`, вступление.** `await ctx.job.cancel()`
из собственного тела не возвращается — сказано только в dartdoc `cancel` (и для
колбэка `each` на `streams.md`, для уборщиков на `cleanup.md`). Агент, который
хочет «отменить себя при условии», напишет именно это. Решение 9 (нет
`StateError`) не трогаю — речь об одной фразе на странице отмены рядом с «A
body can cancel itself, by throwing `Cancelled`»: «…not by awaiting
`ctx.job.cancel()`, which waits for the body that awaits it». Доказательство:
по чтению dartdoc `Job.cancel` (строки 426–428).

Вердикт: принять, повтор решения 9 с новым доводом. Решение закрыло поведение
и оставило слово dartdoc; довод — фраза «A body can cancel itself»
на `cancellation.md` стоит там, где агент ищет, как отменить себя, и молчит
о тупике. Поведение не меняется; с правкой решение 9 назовёт и страницу. Итог:
сделано коммитом «docs: close the findings of the async_job 1.0.1 docs review»:
фраза во вступлении `cancellation.md` после того, как тело отменяет себя;
решение 9 называет теперь и страницу. После R4 ревью правки фраза говорит, что
ожидание задачу отменяет, но не кончается: «Awaiting `ctx.job.cancel()` cancels
the job but never ends».

Проверил и нашёл документированным хорошо, находок нет: `catch (e)` вокруг
`ctx.join` с запасным значением (зонд J: «catch took: Cancelled(manual); using
fallback … outcome: Cancelled(manual)») — `cancellation.md` «Catching errors of
the operation» и dartdoc `Cancelled`; `Job.deferred`, который никто не запустил
(зонд K: «debug: Job() awaited before start; still waiting after 100 ms») —
`children.md`, `error-rules.md`, dartdoc; `async`-колбэк в `ctx.onCancel` (зонд
W: ошибка в зоне, наблюдатель молчит) — `cancellation.md` «A stop that takes
time» и dartdoc `onCancel`; `Future.wait([ctx.run(a), ctx.run(b)])` (зонд X: «b
finished anyway; outcome: Failed») — `groups.md`; `job.outcome` сразу после
`cancel()` без `await` (зонд U: `isCancelled: true; outcome: null`) —
`outcomes.md` «Reacting before the outcome»; `await job` без `.done` —
`await_only_futures` из core-набора `package:lints` ловит (зонд
`probe_await_job.dart`: info, exit 0, печатает `null`), как README и обещает.
Про D2: `catch_without_check`, который ловит зонд J, тоже включается по имени —
агент, скопировавший yaml README, его не получит.

### 6. Что сделать для 10/10

**Документация, 8 → 10.**

| Шаг | Снимает | Вклад |
| --- | --- | --- |
| A1: фраза о голом `await` в Quick start | главное умолчание входа | +0,5 |
| D1: `rows read` в трассе Quick start | проза без доказательства в единственном месте, где трасса должна доказывать | +0,3 |
| D2: абзац Install — два рода правил, yaml с `diagnostics`, `^0.1.1` | читатель не включает `bare_await` и не знает об этом | +0,3 |
| D11, D12: клетки-абзацы и пересказ таблиц на двух страницах правил — в списки | две страницы, читающиеся заметно хуже остальных | +0,5 |
| D3, D4, D5: три правки `reference.md` (+ `shared` на `errors.md`, `outcomes.md`) | справочник, который читают по клеткам, говорит неточно | +0,2 |
| D6, D7, D9: дедупликация фразы, фраза в конце `why.md`, разбить абзац на `riverpod-and-bloc.md` | мелкие спотыкания входа | +0,2 |

**Агент-пользователь, 7 → 10.**

| Шаг | Снимает | Вклад |
| --- | --- | --- |
| A1 | самая частая ошибка, которую README не называет | +1,0 |
| D2 | агент называет плагин, но два правила-ловушки остаются выключенными | +0,7 |
| A2, A3 | `value` бросает; `Job(...)` в теле — не ребёнок | +0,8 |
| A4 | дедлок `await ctx.job.cancel()` — на странице отмены, не только в dartdoc | +0,2 |
| D5 | `shared` как наблюдение — агент иначе добавит лишний `ignoreFailure()` | +0,1 |
| D3 | клетка `ctx.pause` в таблице, которую агент читает первой | +0,2 |

Новых страниц и разделов не предлагаю: решение 143 держит привычные ошибки
агента в README и в прозе страниц, и всё выше — по фразе в уже существующих
местах.

### 7. Страницы

| Страница | Читаемость | Почему | Что сделать для 10 |
| --- | --- | --- | --- |
| `README.md` | 8 | Короткий, конкретный, два раздела с трассами; абзац Install путает, фраза о why трижды, второй раздел без фразы задачи | A1, D1, D2, D6, D10, A2 |
| `why.md` | 8 | Довод «флаг → `CancelableOperation` → три вещи» ясен; буллеты полного примера — лучший разбор кода в пакете; кончается в пустоту | D7; вступление не повторять фразу README |
| `reference.md` | 7 | Таблица хороша, но «Ends and throws», разорванный список, пропуск `shared`; «Four words» — определения по три строки в клетке | D3, D4, D5; определения «Four words» — по одной фразе, остаток в прозу под таблицей |
| `outcomes.md` | 8 | Первые попытки работают; таблица «Observes the failure?» — удачная; хвост о порядке слушателей `whenCancelled` — два списка по пять пунктов | D5; списки о слушателях — в таблицу «когда / порядок» |
| `cancellation.md` | 8 | Длинная (706 строк), но каждый раздел — одна сцена с трассой; «Catching errors of the operation» — самый тяжёлый, три формы `catch` и цена каждой; изолят — ясно для своей сложности | A4; в «Asking the job» таблица «форма clause → что теряет» вместо двух абзацев |
| `time.md` | 9 | Коротко, две таблицы сравнения, новый `ctx.check()` объяснён одной причиной | ничего |
| `children.md` | 8 | Три способа во вступлении — удачно; «When `ctx.run` refuses a child» после таблицы — два плотных абзаца о `runAll` | A3; абзацы об отказах `runAll` — в таблицу или на `groups.md` |
| `groups.md` | 7 | Карта «When / Read» хороша; «The two barriers» и «What a group hands back» — таблицы с клетками-предложениями, пять разделов о владении | Таблицу владения — короче клетки; «What `runAll` does not promise» поднять выше |
| `chains.md` | 7 | Много редких случаев (`shared`, continuation of a child, source waits for continuation); три таблицы «кто закрывает» | Хвост «What the source hands out» — короче; главные сцены первыми |
| `streams.md` | 8 | Три попытки — лучшая серия в пакете; «A job that only follows a stream» — чётко | ничего существенного |
| `cleanup.md` | 9 | Две таблицы и две сцены, всё по делу | ничего |
| `cleanup-rules.md` | 6 | «A value that comes late»: таблица + четыре абзаца-пересказа; «Registering on arrival» — таблица «кто закрывает» хороша | D12 |
| `observing.md` | 9 | Таблица хуков, таблица имени, две сцены | ничего |
| `errors.md` | 7 | Вводная таблица маршрутов — сильная; «Errors of a cancellation» — абзац в 13 строк с четырьмя оговорками о фильтре; слова observe/answer требуют «Four words» под рукой | Абзац о фильтре — в список «когда спрашивают / когда нет»; D5 |
| `error-rules.md` | 5 | Таблица `answer` с клеткой в семь строк, абзац «`later` promises nothing» с тремя случаями прозой, «Rare routes» — ещё таблица; это справочник, написанный рассказом | D11 |
| `testing.md` | 9 | Четыре сцены, каждая со своей ловушкой `fakeAsync`, таблица «что двигает время» | ничего |
| `extending.md` | 7 | Для своей аудитории ясно; длинный список «где ответ достаёт» и абзацы о зонах | Абзацы о `creationZone` — в одну таблицу «кто запускает / в какой зоне» |
| `engine.md` | 7 | Первая попытка с `cancellable: false` — хорошая; таблица «The whole engine» нужна, но говорит, что страница собрана из кусков | Собрать `MyJob` целиком одним блоком в конце |
| `riverpod-and-bloc.md` | 8 | Практично, трассы показывают разницу; `watch` объяснён; новый абзац — одно предложение на пять строк | D8, D9 |

Хуже остальных: `error-rules.md` и `cleanup-rules.md` — правила, которые
читают, чтобы найти свой случай, написаны абзацами, а не строками; затем
`groups.md` и `chains.md` — много редких случаев с таблицами владения, главные
сцены теряются среди них.

### 8. Что хорошо и трогать не надо

- Трассы под кодом и примеры совпадают строка в строку; `walk_away.dart`
  доказывает своё утверждение строкой `quote answered` — образец для D1.
- Пара Quick start / Walking away: один выбор пакета (`join` против
  `abandonable`) показан двумя трассами на первом экране.
- `why.md`: буллеты «что делает каждая строка» под полным примером.
- Таблица `reference.md` — лучший документ для агента; первые попытки с первой
  строкой-комментарием «что ломается»; тексты исключений, которые сами называют
  исправление (`call shared() for each branch`).
- Dartdoc: один абзац-подсказка, договор, одна ловушка, ссылка на раздел
  страницы — везде одинаково.
- `doc/` в архиве pub: агент с кэшем читает страницы без сети.
- `time.md`, `cleanup.md`, `testing.md`, `observing.md` — короткие страницы
  с таблицами сравнения; так должны выглядеть и страницы правил.

### 9. ПРОГОН

Окружение: хук `rtk` переписывал `git diff`/`git show`/`git log` в `rtk git …`,
и защита копии их отказывала; эти команды запускал как `/usr/bin/git …`.
`cd <копия> && git …` отказывался тем же хуком, `git rev-parse` без `cd`
прошёл. `cat` файлов хук переписывал в `rtk read`, и классификатор отказывал —
файлы читал инструментом Read. Проверки базовой линии (`dart format`,
`dart analyze --fatal-infos`, `dart test`) не повторял — принял из задания. Код
bloc/riverpod со страницы не запускал: нужны стенды `tool/*_snippets.py` вне
моего пакета; `asStream` и `value` в `package:async` проверил чтением
исходника. Запись `.review-tmp/report.md` отказал харнесс (см. начало).

| Команда | Последняя строка вывода |
| --- | --- |
| `git rev-parse HEAD` | `6a79b3b894f3ad9bdd37b7d9be14b480db85283e` |
| `git rev-parse 'async_job-v1.0.1^{commit}'` | `6a79b3b894f3ad9bdd37b7d9be14b480db85283e` |
| `cd packages/async_job && dart pub get` | `Changed 52 dependencies!` |
| `/usr/bin/git diff --stat async_job-v1.0.0 async_job-v1.0.1 -- packages/async_job` | `17 files changed, 879 insertions(+), 587 deletions(-)` |
| `/usr/bin/git show async_job-v1.0.0:packages/async_job/README.md` | `[flutter_solo](https://pub.dev/packages/flutter_solo).` |
| `/usr/bin/git diff async_job-v1.0.0 async_job-v1.0.1 -- …/doc/time.md …/doc/riverpod-and-bloc.md …/doc/cleanup-rules.md …/example/example.dart …/example/quick_start.dart` | `// README: end` |
| `dart run example/quick_start.dart` | `cancelled: manual` |
| `dart run example/walk_away.dart` | `quote answered` |
| `dart run example/example.dart` | `Cancelled(manual)` |
| `grep -n await_only_futures ~/.pub-cache/hosted/pub.dev/lints-6.1.0/lib/core.yaml` | `…/lints-6.1.0/lib/core.yaml:13:    - await_only_futures` |
| `grep -n '^## Install' -A 30 ../async_job_lints/README.md; grep -n '^version' ../async_job_lints/pubspec.yaml` | `6:version: 0.1.1` |
| `dart run test/probe_readme.dart` (разделы A, B, P1, P2, C, D, E, M, U) | `after await cancel(): Cancelled(manual)` |
| `dart run test/probe_agent_habits.dart` (разделы G, H, I, J, K, V, W, X) | `outcome: Failed(Bad state: a failed)` |
| `dart analyze test/probe_await_job.dart` | `1 issue found.` (info `await_only_futures`, строка 8; exit 0) |
| `dart run test/probe_await_job.dart` | `null` |
| `grep -n -A6 'Future<T> get value' ~/.pub-cache/hosted/pub.dev/async-2.13.1/lib/src/cancelable_operation.dart` | `Future<T> get value => _completer._inner?.future ?? Completer<T>().future;` |
| `grep -n -B2 -A12 'Stream<T> asStream()' …/cancelable_operation.dart` | `onError: (Object error, StackTrace stackTrace) {` (выше: `onCancel: _completer._cancel`) |
| `/usr/bin/git log -1 --format='%ci %d' async_job_lints-v0.1.1` | `2026-11-04 17:01:38 +0500  (tag: async_job_lints-v0.1.1)` |
| `/usr/bin/git log -1 --format='%ci %d' async_job-v1.0.1` | `2026-11-06 16:04:56 +0500  (HEAD -> worktree-agent-a4c47468f031e8143, tag: async_job-v1.0.1, origin/main, origin/HEAD)` |
| `grep -n -E '^## \|^\| \`' ../async_job_lints/README.md; cat .pubignore` | `README.ru.md` |
| `/usr/bin/git status --short; ls -la .review-tmp` (финальная) | `(empty)` — выше три строки `?? packages/async_job/test/probe_*.dart` |

Ключевые строки зондов (полный вывод — по командам выше):

- A: `body ran: false; outcome: Cancelled(manual); started: false`
- B: `zone: Bad state: read failed after cancel` → `outcome: Cancelled(manual)`
- P1: `zone: Bad state: open failed` → `switch: failed: …`; P2 (done рядом
  с конструктором): только `switch: failed: Bad state: open failed`
- C: `cancel() returned after 32 ms; outcome: Cancelled(manual)`
- D: `onCancel threw: Cancelled(manual)`
- E: `value completed 100 ms after cancel: false; isCanceled: true`
- M: `check=false`: `body returns: page without a thumbnail after 5 ms`,
  `outcome: Cancelled(timeout)`; `check=true`: `outcome: Cancelled(timeout)`
- U: `isCancelled: true; outcome: null`
- G: `body continued after the delay at 1007 ms` /
  `cancel() returned at 1015 ms; outcome: Cancelled(manual)`
- H: `body continued at 302 ms` / `outcome: Cancelled(timeout) at 303 ms`
- I: `inner finished at 314 ms` / `parent cancel() returned at 315 ms; parent:
  Cancelled(manual); inner: Done(42)`
- J: `catch took: Cancelled(manual); using fallback` / `saving cached rows` /
  `save ran` не напечатано / `outcome: Cancelled(manual)`
- K: `debug: Job() awaited before start` / `still waiting after 100 ms`
- V: `await value threw: Cancelled Cancelled(manual)`
- W: `zone: Bad state: stop failed` / `outcome: Cancelled(manual)`; `onError:`
  не напечатано
- X: `b finished anyway` / `outcome: Failed(Bad state: a failed)`

Зонды лежали в копии ревьюера, в `packages/async_job/test/`:
`probe_readme.dart`, `probe_agent_habits.dart`, `probe_await_job.dart`;
отслеживаемые файлы не менялись, `git status --short` показывает только их.

## Задание

Это ревью, а не реализация и не обсуждение замысла. Вопросов не задавай
и подтверждения не жди: ждать его не у кого. Ход считается проваленным, если ты
закончишь его без отчёта по форме ниже. Отчёт целиком — твой последний ответ;
перед ним запиши тот же отчёт в файл `.review-tmp/report.md` своей копии.

### Где ты работаешь

Твой рабочий каталог — копия репозитория (git worktree). Работай только в ней:
все команды запускай оттуда, `cd` в другие каталоги вне копии не делай. Первым
делом проверь, что HEAD копии — это коммит тега `async_job-v1.0.1`:
`git rev-parse HEAD` и `git rev-parse 'async_job-v1.0.1^{commit}'` должны
совпасть (ожидается `6a79b3b8…`). Если не совпали —
`git checkout --detach async_job-v1.0.1` и назови это в разделе ПРОГОН. Затем
в `packages/async_job` выполни `dart pub get` (именно `dart`, не `flutter`).
Временные файлы держи в копии, в каталоге `.review-tmp/`.

Репозиторий — монорепозиторий Dart-пакетов. `async_job` — ядро: структурная
асинхронная задача `Job` с деревом детей, отменой, уборкой и исходами. `solo`,
`flutter_solo`, `async_job_lints`, `solo_lints` — другие пакеты; **твоя
область — только документация `packages/async_job`**: `README.md`, `doc/*.md`,
`CHANGELOG.md` (раздел 1.0.1), `example/`, dartdoc публичного API в `lib/` —
как его видит пользователь в подсказке и на pub.dev.

### Что вышло

На pub.dev только что вышел `async_job` 1.0.1 — патч к 1.0.0. Код `lib/`
с 1.0.0 не менялся
(`git diff async_job-v1.0.0 async_job-v1.0.1 -- packages/async_job/lib` пуст).
Патч — документация: README стал коротким входом (быстрый старт и раздел
«Walking away from a call»), объяснение «зачем» ушло на новую страницу
`doc/why.md`, таблица контекста и «Four words» — на новую `doc/reference.md`;
README называет плагин анализатора `async_job_lints`; поправлены `doc/time.md`,
`doc/riverpod-and-bloc.md`, `doc/cleanup-rules.md`. Полный дифф патча:
`git diff async_job-v1.0.0 async_job-v1.0.1 -- packages/async_job`. Ревью —
документации в том виде, в каком она вышла, целиком, а не только диффа; но вход
(README → why → reference) — главное, что изменилось, и ему дай особое
внимание.

### Главный вопрос

Что нужно сделать, чтобы ты поставил 10? Ответь на него для каждой оценки,
которую ставишь: документации, агента-пользователя, README и каждой страницы
`doc/`. Перечень шагов, у каждого — какой недостаток он снимает и насколько,
по-твоему, поднимет оценку. «Ничего, уже 10» — тоже ответ, если объяснишь
почему.

### Что сделать

1. **Документация глазами пользователя.** Ты — Dart/Flutter-разработчик,
   который впервые нашёл пакет на pub.dev. README, страницы `doc/`, `example/`,
   dartdoc публичного API, раздел 1.0.1 `CHANGELOG.md`. Понятно ли с первого
   экрана README, что это и зачем; можно ли по README начать и не ошибиться;
   ведёт ли вход дальше — понятно ли, куда идти со второго вопроса; верен ли
   код в документах — собирается ли и делает ли то, что сказано в прозе; где
   читатель споткнётся, запутается или ошибётся без предупреждения; чего
   не хватает; что лишнее, многословное, трудное для чтения; не потерялось ли
   при переносе в `why.md` и `reference.md` то, что раньше было в README.
   Утверждение документа о поведении проверяй зондом, когда его можно
   проверить, — хотя бы на нескольких ключевых местах входа.
2. **Глазами ИИ-агента-пользователя.** Агент (Claude Code, Codex и подобные)
   пишет приложение на пакете по задаче человека. Он видит README и `doc/`
   с pub.dev или из кэша pub, dartdoc, сигнатуры, тексты исключений, сообщения
   анализатора. Насколько по этой документации ему легко написать правильный
   код; где правдоподобный код по привычке из других библиотек (Bloc, Riverpod,
   голые `Future` и `StreamSubscription`) соберётся и молча поведёт себя
   не так, и скажет ли ему документация об этом. Проверь зондом несколько таких
   «привычных» ошибок.
3. **Оценки.** Документация X/10 и агент-пользователь X/10, где 10 — максимум;
   объясни каждую: что подняло, что опустило. Затем оценку читаемости из десяти
   `README.md` и каждой странице `doc/*.md` глазами того же разработчика
   с pub.dev: язык и длина фраз, вступление, устройство разделов, списки
   и таблицы, первые попытки (многие разделы намеренно открываются ошибочной
   версией кода, к которой ведёт словарь API, — оцени, работает ли это). Назови
   страницы, которые читаются заметно хуже остальных, и почему.

Код `lib/` не ревьюй и оценку коду не ставь: он не менялся. Если, проверяя
документ, наткнёшься на расхождение документа с кодом — это находка
по документации.

### Чего не делать

- Не меняй отслеживаемые файлы. Новые файлы создавай только как зонды:
  `packages/async_job/test/probe_*.dart` — из корня копии `package:`-импорты
  не резолвятся. Под конец `git status --short` копии должен показывать только
  твои `probe_*` и `.review-tmp/`.
- Не читай `docs/records/`, `docs/handoff.md`, `docs/backlog.md`
  и `.artifacts/`: там история прошлых ревью и решений, она сместит взгляд.
  `AGENTS.md`, `docs/architecture.md` и `docs/conventions.md` читать можно.
  Если правила репозитория (`AGENTS.md` велит начинать с handoff, обновлять
  его, коммитить) спорят с этим заданием, выигрывает задание, а конфликт назови
  в отчёте.
- `docs/settled.md` прочитай целиком до начала работы: там решения «оставить
  как есть» и «не делать», закрывшие вопросы прошлых ревью. Находку, которая
  спорит с решением оттуда, поднимай только с доводом, которого в решении нет:
  новым фактом, зондом, случаем, о котором причина молчит. Такая находка
  помечается «повтор решения N» и называет новый довод. Без нового довода
  находки нет. Решения 131 и 132 о том, чего проект не делает, касаются агентов
  репозитория, а не тебя: это ревью назначил владелец.
- Не коммить, не пушь, не публикуй.
- Русские переводы (`README.ru.md`, `docs/ru/`) и сайт документации (`site/`,
  `tool/build_site.py`) — вне рамок.

### Базовая линия

На этом коммите: `dart format` без изменений, `dart analyze --fatal-infos` без
замечаний, `dart test` в `packages/async_job` — +1902, все прошли; пробная
публикация без предупреждений; архив проходит свои тесты на минимальных версиях
SDK и зависимостей; фрагменты кода страниц собирает и прогоняет CI. Поэтому
«тесты падают» и «анализатор ругается» находкой быть не могут; если у тебя
вышло иначе — это сведения о твоём окружении, назови их в ПРОГОНЕ.

### Отчёт

По-русски, Markdown. Разделы по порядку:

1. **Оценка** — документация X/10, агент-пользователь X/10; под каждой абзац
   объяснения.
2. **Сводка** — пять–десять строк: главное, что ты увидел.
3. **Вход** — README → `why.md` → `reference.md`: работает ли короткий вход,
   что потерялось или повторяется при переносе.
4. **Находки по документации** — номера D1, D2, … У каждой: тяжесть; место —
   файл и заголовок раздела; что не так; почему это мешает читателю;
   доказательство — зонд (файл, что делает, что напечатал) или «по чтению»; что
   предлагаешь. Тяжесть: **High** — документ ведёт к неверному коду или
   утверждает неверное о поведении; **Medium** — читатель вероятно ошибётся или
   не найдёт нужного; **Low** — остальное.
5. **Для ИИ-агента** — находки A1, A2, … в той же форме. Находку, которая уже
   стоит в D, не повторяй — сошлись на неё.
6. **Что сделать для 10/10** — ответ на главный вопрос для обеих оценок
   из раздела 1.
7. **Страницы** — таблица «страница — оценка читаемости — почему — что сделать
   для 10», `README.md` и все `doc/*.md`; какие страницы хуже остальных
   и почему.
8. **Что хорошо и трогать не надо** — коротко.
9. **ПРОГОН** — каждая команда, которую ты действительно запустил (проверки
   и зонды), с точной последней строкой её вывода. Чего не запускал или что
   упало из-за окружения — так и напиши.
