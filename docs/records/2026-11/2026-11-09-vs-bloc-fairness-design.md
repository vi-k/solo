> **Состояние на 2026-11-09:** дизайн написан, ждёт независимого ревью
> и одобрения владельца; правок в дереве ещё нет.
> **Что это:** честная волна по `packages/solo/doc/vs-bloc.md` после спора
> «bloc или solo» и раздел о том, почему у `flutter_solo` нет `SoloProvider`.
> **Связанные записи:** `2026-11-07-bloc-vs-solo-debate-report.md`,
> `2026-11-03-bloc-pages-design.md`.

# Честная волна по vs-bloc.md

## Зачем

Спор с Sol и проверка свежим оппонентом,
`2026-11-07-bloc-vs-solo-debate-report.md`, нашли в `vs-bloc.md` места, где
сравнение говорит против bloc больше, чем показывает код: ответ bloc
не сильнейший из доступных ему, вступительная таблица ставит первую попытку
bloc рядом с готовым ответом solo, ловушка одного раздела опирается на имя
трансформера, другой раздел смешивает два требования. Владелец 2026-11-09 велел
начать круг исправлений с этой страницы.

Цель — чтобы каждое сравнение на странице держалось против сильнейшего ответа
bloc, который проверен стендом. Слабее solo от этого страница не станет: там,
где ответ bloc становится сильнее, у solo остаётся то, чего bloc не даёт, и это
надо назвать точно.

Вторая часть той же волны — по слову владельца 2026-11-09: «по SoloProvider,
возможно, стоит написать не только в settled, но и в документации
пользователю — почему его нет, с обоснованием».

Источники в `docs/backlog.md`: «Ответ bloc в «Closing and cancelling in-flight
work» `vs-bloc.md`», «Остальные замечания Sol к подаче `vs-bloc.md`», «Подача
`vs-bloc.md` по проверке свежим оппонентом», половина записи «Жизнь контроллера
во Flutter: `SoloProvider` и `SoloListener`».

## Что не входит

- `SoloListener`. Владелец 2026-11-09: «нужно отдельно подумать: может, стоит
  добавить». Запись бэклога остаётся, из неё уходит только `SoloProvider`.
- Ловушка рабочего типа (`W = Idle`, запись `Loading`, отмена на следующей
  контрольной точке) и исход задачи против исхода внешнего действия в общем
  виде. Это предмет страниц `state.md` и `jobs.md`, а не сравнения с bloc;
  следующий шаг круга.
- Самописный `Lock` в «Finishing an in-flight write before restarting»
  остаётся: владелец 2026-11-07, он показывает, как барьер устроен изнутри.
- Линты о `done` — отдельная работа круга.

## Что уже на месте

Две находки свежего оппонента страница уже учитывает, и правки они не требуют:

- **Сильнейший ответ bloc на порядок.** Раздел «Ordering updates to shared
  state» под заголовком Bloc уже показывает одну регистрацию `on<NotesEvent>`
  с `sequential()` на всё семейство команд.
- **Исход задачи против исхода платежа.** Раздел «Awaiting a particular
  request» уже разбирает его на платеже: `cancellable: false`, широкий рабочий
  тип, абзац о том, что `ctx.uncancellable` вокруг тела ответил бы
  `paid: false` за проведённый платёж, и абзац об идемпотентности.

## Правки

### 1. Вступительная таблица: колонка bloc

**Что не так.** Таблица под вводными абзацами (строки 22–34 сейчас) имеет
колонки «Scenario | What the first attempt tries | What solo uses». Первая
попытка написана на bloc, и читатель видит ошибку bloc рядом с ответом solo,
а ответа bloc в таблице нет.

**Правка.** Колонка «What bloc uses» между ними: «Scenario | What the first
attempt tries | What bloc uses | What solo uses». В ячейке — API, которым
пользуется ответ под заголовком Bloc этого раздела, в том же духе, что ячейка
solo: короткое перечисление членов, без оценки. Для разделов с двумя ответами
(«Bloc» и «Cubit» в «Awaiting a particular request») — оба через «;». Ячейки
пишутся по разделам после правок 2–4, а не по нынешней странице.

Вводный абзац над таблицей («The scenarios in order, with what the first
attempt tries and what the solo version uses») называет и третью колонку.

### 2. «Closing and cancelling in-flight work»: проверка до вызова

**Что не так.** Ответ bloc проверяет `isClosed` только после
`await _api.send(e.text)`. Тогда `close()` под `sequential()` выполняет
очередь, и сообщение, стоявшее за текущим, уходит на сервер. Проза solo
противопоставляет этому: «A message still queued behind the running one never
reaches the API … where `sequential()` would send it». А сильнейший ответ
bloc — проверка и до вызова: стенд `tool/bloc_snippets.py`, задание
`solo_table_closing`, уже гоняет его и требует, чтобы `bye` не ушло, `close()`
ждал только вызова в полёте и ни один ответ не был опубликован или отмечен
прочитанным. Таблица «Where bloc keeps its answer» в `bloc.md` ссылается именно
на этот вариант.

**Правка `vs-bloc.md`.**

- Код под заголовком Bloc получает `if (isClosed) return;` перед
  `final reply = await _api.send(e.text);`, после него проверка остаётся.
- Абзац под кодом: обе проверки вместе не дают ни ответа в состоянии,
  ни `MarkReplyRead`, ни отправки сообщений, стоящих в очереди; `close()` ждёт
  только вызов, который уже ушёл, и обработчики очереди проходят вхолостую.
- Абзац solo о сообщении в очереди перестаёт противопоставлять: очередь solo
  тоже не отправляет, разница в другом. Что остаётся за solo и проверено
  стендом раздела: `close()` не ждёт ответа на вызов в полёте, потому что
  `ctx.abandonable` отпускает его; вызов после `close()` возвращает задачу
  `Cancelled(closed)`, а `add` после `close()` бросает `StateError`; проверок
  `isClosed` в коде нет вовсе. Абзац о `SoloCloseMode.drain` остаётся: он про
  случай, когда очередь уйти должна.
- «What solo gives» раздела сверяется с новым текстом и правится, если в нём
  есть противопоставление очереди.

**Правка `bloc.md`.** Строка «Closing and cancelling in-flight work» таблицы
«Where bloc keeps its answer» говорит «the Bloc answer there with a check of
`isClosed` before the call as well as after it». Становится «the Bloc answer
there»: проверка до вызова теперь в нём.

**Правка стендов.**

- `tool/doc_snippets.py`, `bloc/item3`: сценарий «queued behind, guarded»
  требует сейчас `answered.length == 2` и пишет «sequential close must run the
  queued event as well». Он меняется на требование, что `bye` не отправлено
  и `close()` ждёт только `hi`. Трасса, если страница её цитирует, сверяется
  `check_traces.py`.
- `tool/bloc_snippets.py`, `solo_table_closing`: сейчас дописывает проверку
  к коду `vs-bloc.md` заменой строки `SEND`. После правки проверка уже в коде,
  и задание берёт блок как есть; `assert` о строке `SEND` меняется на `assert`
  о том, что проверок `isClosed` в блоке две. Комментарий над заданием правится
  тем же коммитом.

### 3. «Typed methods with queued execution»: два требования

**Что не так.** Требование раздела — типизированные методы и «rapid drag
updates should not leave the map at an older position». Ответ bloc
(`sequential()` на одной регистрации функций) его выполняет: карта кончает
на `MapState(3, z4)`. Ответ solo делает больше — останавливает первое
перемещение и не начинает среднее, — и «What solo gives» хвалит именно это,
хотя требования такого нет. Sol: раздел смешивает удобство методов
с требованиями очереди.

**Правка.** Требование называет обе половины явно: методы самого контроллера
с их аргументами, и перемещение, которое уже устарело, не должно занимать
карту — карта не должна проезжать 1, 2 и 3 по очереди, когда нужна только 3;
зум устаревшее перемещение не отменяет.

Под заголовком «Bloc with function events», после нынешнего разбора
`sequential()`, — абзац о второй половине. Одна регистрация — один трансформер
на все команды. `restartable()` на ней перезапускает и перемещение зумом. Зонд
Claude 2026-11-09 на bloc 9.2.1 и bloc_concurrency 0.3.0, код раздела
с `restartable()` вместо `sequential()` и тот же сценарий:

```text
sequential:
  moveTo 1 start, moveTo 1 end, moveTo 2 start, moveTo 2 end,
  moveTo 3 start, moveTo 3 end, zoom 4 start, zoom 4 end
  state MapState(3, z4)
restartable:
  moveTo 1 start, moveTo 2 start, moveTo 3 start, zoom 4 start,
  zoom 4 end, moveTo 3 end, moveTo 2 end, moveTo 1 end
  state MapState(0, z4)
```

Под `restartable()` все три перемещения идут на карту одновременно, потому что
отмена эмиттера не останавливает нативный вызов, а зум отменяет эмиттер
третьего: ни одно перемещение не записано в состояние. Регистрация на каждую
команду вернула бы две очереди — ссылка на «Ordering updates to shared state».
Как остановить сам нативный вызов, bloc не говорит: токен отмены придётся
провести через событие руками.

На странице эта трасса — в формате стенда, а не зонда: стенд раздела
`tool/doc_snippets.py`, `bloc/item6`, получает драйвер с `restartable()`
и сторож на `MapState(0, z4)`, а `check_traces.py` сверяет цитату. Код варианта
в отдельный блок не выносится: он отличается одним словом, и драйвер собирает
его заменой строки в блоке `CommandMapBloc` с `assert`, что замена одна.

«What solo gives» раздела остаётся по сути, но опирается теперь на названное
требование.

### 4. «Awaiting a particular request»: ловушка без опоры на имя

**Что не так.** Первая попытка вводится так: «`droppable()` reads like the
policy for sharing one payment». Ловушка выглядит построенной на имени
трансформера, и читатель, который знает bloc, слышит упрёк в незнании.

**Правка.** Вводный абзац первой попытки говорит, что делает `droppable()`, —
отбрасывает события, пришедшие, пока обработчик занят, — и почему к нему тянет:
повторные запросы того же заказа приходят как раз во время платежа. Код
и разбор остаются. Абзац о заказе B переформулируется так, чтобы читалось, что
ловушек две и обе не зависят от имени: трансформер правит всей регистрацией,
а не заказом, поэтому заказ B отброшен тоже; завершитель отброшенного события
никто не завершает, поэтому его вызывающий ждёт вечно. Вторая ловушка и есть
причина, по которой ответ bloc ниже держит карту платежей, а не другой
трансформер.

### 5. «Ordering updates to shared state»: цена одной очереди

**Что не так.** Раздел solo говорит, что очередь одна на контроллер и это
гарантирует порядок. Свежий оппонент: та же очередь заставляет ждать команду,
которая общего состояния не трогает. Страница говорит об этом только
в «Correspondences»: «There is no concurrent root-job policy; use children or
separate controllers».

**Правка.** В абзаце solo после «no arrangement of the methods can give two of
them a queue each» — фраза о цене: команда, которой порядок не нужен, ждёт
за загрузкой так же, и выход для неё — ребёнок или отдельный контроллер, ссылка
на «A tap that does not wait for a reload» в `jobs.md`.

### 6. Почему у `flutter_solo` нет `SoloProvider`

**Что сейчас.** `packages/flutter_solo/README.md`, «The controller's life»:
«There is no `SoloProvider`: a controller is an object, and it lives wherever
the rest of your objects live.» Дальше — `State`, общие места и scopo
с `ScopeModel` и `AsyncDataScope`. Причины, по которой провайдера нет,
на странице нет. В `vs-bloc.md`, «Correspondences», строка `BlocProvider` —
«Deliberately not part of the package: dependencies are passed by other means
and packages, such as scopo».

**Правка README `flutter_solo`.** После первого абзаца раздела — абзац
о причине. Набросок, формулировку правит исполнитель:

> The reason is the close. A controller's `close()` is asynchronous: it waits
> for the running job, and with `SoloCloseMode.drain` for the queue. A
> provider closes its object from a synchronous `dispose`, which cannot wait
> for that future: `BlocProvider` calls `bloc.close()` there and lets it run.
> A new screen can then create the next controller of a resource while the old
> one still holds it, and a failed close reaches only the zone. Waiting for a
> release needs a lifecycle of its own: a scope that awaits what it owns,
> orders the next owner of a resource after the previous one, and shows
> something while it waits. scopo is that lifecycle, as a package of its own,
> so it serves any object, a bloc included. A `SoloProvider` would be a weaker
> copy of it.

Каждое утверждение наброска сверяется по исходникам до записи: `Dispose<T>`
и `_CreateInheritedProviderState.dispose` в `provider-6.1.5+1`,
`BlocProvider.buildWithChild` во `flutter_bloc-9.1.1`, `disposeScope`,
`scopeKey` и ветвь закрытия `close()` в `scopo-1.0.0`. Что не подтвердится,
из абзаца уходит. Оговорка свежего оппонента о сроке — со сроком по умолчанию
следующий владелец ресурса может стартовать раньше — в абзаце не нужна:
нынешний текст раздела ниже уже говорит о сроке `disposeScopeTimeout`
и о `ScopeTimeout.none`.

**Правка `vs-bloc.md`.** Строка `BlocProvider` в «Correspondences» ссылается
на этот раздел README `flutter_solo` (адрес на GitHub, как у ссылок README
на `vs-bloc.md`).

**`docs/settled.md`.** Решение 148 в разделе `flutter_solo`: `SoloProvider`
не делаем; жизнь контроллера во Flutter — scopo, отдельный пакет того же
автора, и провайдер с синхронным `dispose` дал бы контракт слабее. Даты
2026-11-07 и 2026-11-09, записи — эта
и `2026-11-07-bloc-vs-solo-debate-report.md`.

## Переводы

Каждая правка английского — правкой перевода тем же коммитом:
`docs/ru/solo/vs-bloc.md`, `docs/ru/solo/bloc.md`,
`packages/flutter_solo/README.ru.md`. Изменённые абзацы переводов — через
линтер скилла `humanizer--ru`, только `ERROR`. Сверка —
`python3 tool/check_translations.py`.

## Бэклог

Тем же коммитом, что работа:

- «Ответ bloc в «Closing…»» и «Остальные замечания Sol к подаче…» удаляются;
- «Подача `vs-bloc.md` по проверке свежим оппонентом» переписывается
  на остаток — ловушка рабочего типа и исход задачи против исхода внешнего
  действия на страницах `state.md` и `jobs.md`;
- из записи о `SoloProvider` и `SoloListener` уходит `SoloProvider`, остаётся
  `SoloListener` со словом владельца 2026-11-09.

## Проверки

- `snippets`: все пять стендов, `tool/check_traces.py` — правки 2 и 3 меняют
  драйверы и цитаты.
- `docs`: `reflow.py --check`, `check_line_width.py`, `check_links.py`,
  `check_translations.py`, `check_dartdoc.py`, сторожа и сборка сайта
  `tool/build_site.py`.
- Мутация: сторож правки 2 краснеет, если из блока убрать проверку до вызова;
  сторож правки 3 краснеет, если в драйвере заменить `restartable()` обратно
  на `sequential()`.

## Решения исполнителя

- Точный текст ячеек таблицы и абзацев — за исполнителем, в рамках правил
  `docs/conventions.md` и скилла `doc-reader`.
- Если стенд покажет, что утверждение дизайна неверно, — правка идёт по стенду,
  а расхождение записывается в отчёт волны.
