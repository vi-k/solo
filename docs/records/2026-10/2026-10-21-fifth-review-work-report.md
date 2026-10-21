> **Состояние на 2026-10-21:** ревью проведено, все шесть находок закрыты
> одним коммитом вместе с этой записью; итог каждой — в её вердикте.
> **Что это:** независимое ревью на Opus всего сделанного по пятому полному
> ревью, `9a781fa7..021a99ee`: правки кода по находкам, правки документов
> и волна читаемости на шести страницах. 6 находок: 1 High, 5 Low.
> **Связанные записи:** `2026-10-21-async-job-project-review-2.md`
> и `2026-10-21-solo-project-review-2.md` (находки, которые чинили),
> `2026-10-21-fifth-review-readability-plan.md` (план волны и её итоги).

# Ревью сделанного по пятому ревью

Ревьюер — Opus, в отдельной копии дерева на `021a99ee`. Задание: проверить
правки кода зондами и на старом коде, каждое новое утверждение страниц,
читаемость шести страниц, переводы, «Итоги» трёх записей и все проверки гейта.
Ниже находки в его словах, с вердиктом и итогом под каждой.

**Общая оценка ревьюера.** Все четыре правки кода закрывают свои находки. Новые
тесты к ним осмысленные: со старым кодом все они краснеют. Утверждения на шести
страницах и в dartdoc верны везде, где он их проверял, переводы совпадают
с оригиналами. Но гейт на `021a99ee` красный: в `packages/solo/example` падает
один тест.

## Находки

**1. High: тест примера `solo` падает, задание `dart` гейта красное.**
`packages/solo/example/test/camera_rakes_test.dart:1367`. Сторож держит старую
фразу `camera.md`, а `86fef765` её поменял: тест ждёт «replace drops the queued
job with the same key before it queues the new one», и прогон кончается
`00:00 +110 -1: Some tests failed.` Сам новый текст верен: `Solo.add` сначала
вставляет задачу, потом `removeWhere`. Отсюда же неверен «Итог» L1
в `2026-10-21-solo-project-review-2.md`: «Фраза `camera.md` сторожа
не получила». Чинить: перевести сторожа на новую фразу, в «Итоге» L1 написать,
что фразу держит сторож примера.

Вердикт: принято. Причина — пример `solo` не прогоняли перед коммитом
`86fef765`.

Итог: сторож `replace keeps only the last queued zoom` держит новую фразу,
пример `solo` зелёный (`+112`). «Итог» L1 исправлен: фразу держит сторож
примера, и его нашло это ревью.

**2. Low: рецепт `extending.md` всё ещё пускает в очередь задачу, которую уже
запустил родитель.** `MyQueue.add` в разделах «Refusing while the job waits»
и «The whole engine», копия в `test/extending_rakes_test.dart`. `adoptedBy`
не даёт родителю взять задачу из очереди, первая строка `add` не даёт очереди
взять задачу с `_queue`. Обратный порядок не закрыт: сначала `ctx.run(job)`,
потом `queue.add(job)`. Зонд: `loopError=Bad state: Job() is already running`,
и задача, стоявшая следом, так и не запустилась. Чинить: `add` отказывает
и задаче, которая идёт; полфразы в абзац под `adoptedBy` и тест.

Вердикт: принято.

Итог: вторая строка `add` бросает `StateError` на задаче, которая идёт, в обоих
блоках страницы, в переводе и в копии теста. Абзац под `adoptedBy` называет
этот путь. Тест `a job a parent has started is refused by the queue` краснеет
на старом рецепте.

**3. Low: `observing.md` называет `onUnanswered` исключением из «четырёх
хуков», в число которых он не входит.** `observing.md:52-54` и перевод: «The
four hooks of `JobObserver` do nothing by default… `onUnanswered` is the
exception». `onUnanswered` — член `JobAnswerer`, и «исключение» подсказывает
пятый хук `JobObserver`. Сам факт верен. Чинить: «`onUnanswered` of
`JobAnswerer` does something by default: it hands the failure to the zone…»

Вердикт: принято.

Итог: фраза — «`onUnanswered` of `JobAnswerer` is not empty by default: it
hands the failure to the zone…», в переводе так же. Сторожа у фразы нет.

**4. Low: таблица двух остановок в `extending.md` повторяет абзац над ней,
а одна клетка сдвигает момент.** Строки `cancellable: false`
и `ctx.uncancellable` для правила повторяют последнюю фразу абзаца в «A
cancellation of the engine's own». Клетка «as the body lets it out of a call
that asked the rule» читается как «когда вызов бросил», а задача принимает
отмену, когда `Cancelled` выходит из тела; клетка `then` у `onCancel` без
ясного «когда». Чинить: обе клетки — «when it leaves the body»; повтор убрать
из прозы или из таблицы.

Вердикт: клетки принять, повтор оставить. Таблица сравнивает две остановки
рядом, и в двух строках столбец правила совпадает с абзацем выше; без него
строка `_stop` теряет пару. Абзац же объясняет, почему правило так себя ведёт,
и без него таблица говорит «что», не говоря «почему».

Итог: обе клетки — «when it leaves the body», в переводе «когда она выходит
из тела». Повтор оставлен решением 99 в `docs/settled.md`.

**5. Low: на `errors.md` `solo` слово `onUnanswered` значит две вещи, а клетка
«Nowhere» спорит со своим хвостом.** `errors.md:37-50` и перевод. Абзац под
таблицей путей вводит: «`onUnanswered` stands for the answer route from
`onUnanswered` on» — одно слово стало и хуком, и отрезком пути. Клетка Report:
«Where it ends: Nowhere: …, and the error goes on along the answer route».
Чинить: назвать столбец «Who answers for it» без переопределения слова;
в клетке Report — «It does not end there: the hooks hear it and return, and the
error goes on along the answer route».

Вердикт: принято.

Итог: клетка Report — «It does not end there: …», сторож
в `errors_rakes_test.dart` переведён на неё. Фраза-переопределение заменена
другой: «An error that no outcome carries enters the answer route at
`onUnanswered` and goes on from there as the Answer row above says.»
`onUnanswered` в таблице снова значит хук. Столбец уже назывался «Who answers
for it» и остался так.

**6. Low: вступление `errors.md` ядра и место `ignoreFailure()`.**
`errors.md:5-17`. Вступление обещает: ошибка проходит места по порядку
и не идёт дальше первого, которое её забирает. `ignoreFailure()` останавливает
провал тела отменённой задачи, хотя исход его не несёт (зонд:
`heard=[load] unanswered=[] zone=[]`), а ни одно место таблицы этого
не описывает. Сказано ниже, в «What keeps an error out of the answer». Чинить:
дописать в строку «The outcome» или сослаться фразой под таблицей.

Вердикт: принято, фразой под таблицей: в строке «The outcome» место — исход,
а `ignoreFailure()` действует и там, где исход провала не несёт.

Итог: под таблицей фраза «`ignoreFailure()` on a job keeps the failure of its
body right after `onError`, even when the job ends `Cancelled`» со ссылкой
на «Where each error goes»; в переводе так же. Факт держат
`ignoreFailure closes the second way for a failure no outcome carries`
и `ignoreFailure silences a failure a late cancellation covered`.

## Чего ревьюер не проверял

Стенды `snippets` (`vs-bloc.md` и `accumulation.md` в диапазоне не менялись),
задание `floor` на SDK 3.27.0, правку M1 ядра под пользовательской зоной
и страницы, которые волна не трогала.
