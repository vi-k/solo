# Документы solo по третьему полному ревью: M5, M6, L1–L5, L12, L14, L17, L20

> **Состояние на 2026-10-20:** сделано в `main` одним коммитом, не отправлено.
> **Что это:** четвёртая волна правок по третьему полному ревью — документы
> `solo` и `flutter_solo`, их сторожа и dartdoc `Solo.job`; одиннадцать
> находок записи `2026-10-20-solo-project-review.md`.
> **Связанные записи:** `2026-10-20-solo-project-review.md`,
> `2026-10-20-async-job-docs-fixes-report.md`,
> `2026-10-20-solo-code-fixes-report.md`.

Владелец 2026-10-20 сказал «чини всё, что можешь». Волны до этой закрыли код
ядра, код `solo` и документы ядра; L15 этой записи закрыт там же, где L17 ядра,
в `2026-10-20-async-job-docs-fixes-report.md`. Эта волна — документы `solo`
и `flutter_solo`. Форма страниц (M9, L18, L21) — пятая волна.

## Что сделано

**M5.** `flutter_solo/doc/testing.md`, конец «Moving the clock». Абзац говорил,
что тест роняет только `Job` со сроком. Зонд на фейке самой страницы:

```text
open reported=[… A Timer is still pending even after the widget tree was disposed.]
closed outcome Cancelled(closed)
closed reported=[… A Timer is still pending even after the widget tree was disposed.]
closed+pump outcome Cancelled(closed)
closed+pump reported=[]
```

Теперь абзац говорит: тест роняет любой таймер, который ещё ждёт, когда
кончается тело, и у идущей загрузки он есть — десять миллисекунд фейка; срок
`Job` приносит второй. Закрытый в теле контроллер забирает срок, но не вызов,
от которого `Job` ушла: тест кончается чисто, когда `pump` с длительностью
переведёт часы дальше. Сторожа в `testing_rakes_test.dart`: загрузка на фейке
страницы и загрузка со сроком, оставленные идущими, — обе красные; закрытая
в теле загрузка на фейке — красная без `pump` и чистая с ним. Прежний тест
«та же `Job` без срока проходит» ушёл: он держал фразу, которой больше нет.

**M6.** `errors.md`, абзац после `Hangs`. Говорил, что задача со сроком
кончается `Cancelled(timeout)`, когда срок выходит. Теперь: срок отменяет
задачу, и она кончается, когда тело дойдёт до контрольной точки или вернётся;
тело, которое ждёт вызов голым `await`, не дойдёт ни до одной, пока вызов
не вернётся, и очередь и `close()` ждут его всё это время. Такой вызов
останавливает только его собственное средство — токен из раздела «A deadline of
a job» на `cancellation.md`; `ctx.abandonable` заканчивает ожидание и оставляет
вызов идти. Сторожа в `errors_rakes_test.dart`: прежний тест «Hangs only
reports, and a deadline stops the job» держит новые фразы и проверяет, что
вызов под `abandonable` идёт дальше; новый тест «a deadline does not stop a
body that awaits a call bare» — через шесть секунд при сроке в три задача
отменена, но не кончилась, стоящая за ней не начиналась, `close(drain)`
не вернулся; после конца вызова — `Cancelled(timeout)`, очередь выполнена,
закрытие вернулось.

**L1.** `reference.md`: метод, который зовёт экран, объявляет `Job<T>`; метод,
который делает ребёнка для `ctx.run`, — `SoloJob<T>`, потому что `ctx.run`
берёт `ChildJob<T>`.

**L2.** `jobs.md`: задача решает, отправлять ли провал в зону, на микрозадаче
после конца, а не в момент конца; начало той же фразы говорит «by the microtask
after it ends».

**L3.** `accumulation.md`, абзац об `adjacent` в рецепте команд. Прежний текст
обосновывал выбор задачей, которой в примере нет. Теперь: у трёх нажатий подряд
`join` дал бы то же; расходятся политики, когда между `resume` и `pause` стоит
задача другого рода — `join` вливает `pause` в группу перед ней, устройство
не слышит `resume` и встаёт на паузу раньше задачи. Зонд перед правкой:

```text
AccumulationPolicy.adjacent [start busy, device Cmd.resume, start seek, device Cmd.pause]
AccumulationPolicy.replace [start busy, start seek, device Cmd.pause]
AccumulationPolicy.join [start busy, device Cmd.pause, start seek]
```

Сторожа в `accumulation_rakes_test.dart`: новый тест «three taps in a row come
out the same under join» сверяет трассу `JoiningPlayer` с трассой `Player`
и с цитатой страницы; тест расхождения держит новые фразы.

**L4, L5.** Dartdoc `Solo.job`. Первый абзац говорит сразу верно:
`cancellable: false` отказывает `close` только бегущей задаче. Второй дополнен:
очередная задача, отказавшая `cancel`, стартует в свой черёд и проходит
целиком, и `await job.cancel()` возвращается только тогда. Тест «await cancel()
of a queued uncancellable job waits for its whole run»
в `cancellable_test.dart`.

**L12.** `CHANGELOG.md` `flutter_solo`: у пакета две страницы, «Mixins»
и «Testing».

**L14.** README `flutter_solo`, «Why»: тело, не дошедшее до контрольной точки,
«writes no state of its own» — состояние после отмены пишет `ifCancelled`.
Сторож в `readme_rakes_test.dart` держит новую фразу.

**L17.** README `solo`: `flutter_solo` приносит `SoloListenable`, виджеты
`SoloBuilder` и `SoloSelector` и `listen`.

**L20.** README примера `solo`: ссылка на страницу «Camera example», пути
ссылками, конец вывода с `shot: Cancelled(manual)` и фраза о том, что снимок
отменяет `dispose` намеренно, команда `dart test`. Перевода у этого README нет
и не было.

Все правки оригиналов переведены тем же коммитом.

## CHANGELOG

L12 — сама запись `CHANGELOG.md` `flutter_solo`, выше. Остальное записей
не требует: поведение не менялось.

## Проверки

- `packages/solo`: `dart format` без изменений, `dart analyze` —
  `No issues found!`, `dart test` — 1998 зелёных (до волны 1995); пример — 112
  (до волны 111).
- `packages/flutter_solo`: `flutter analyze` чистый, `flutter test` — 232
  зелёных (до волны 230); пример — 4.
- Стенды `vs-bloc` и `accumulation` со сверкой трасс — зелёные.
- Пол, `tool/archive_floor.py` на Flutter 3.27.0 по копии с коммитом волны
  до правок по ревью: пять корней зелёные.
- Откат страниц к прежнему тексту краснит их сторожей: M5 и L14 — пять тестов
  `testing_rakes_test.dart` и тест `readme_rakes_test.dart`, M6 — оба теста
  `errors_rakes_test.dart`, L3 — оба теста `accumulation_rakes_test.dart`.
  Подмена хвоста вывода в README примера краснит новый тест примера.
- `reflow.py --check`, `check_line_width.py`, `check_doc_shape.py`,
  `check_links.py`, `check_translations.py` — зелёные.

## Ревью

Opus в отдельной копии дерева, отвязанный worktree на `c6ec8aa7` с волной
поверх. Ревьюер прогнал гейт четырёх корней и проверки документов, гонял свои
зонды в пакете `solo` и откатывал страницы и код: откат каждой правленой
страницы краснит её сторожей, мутация `cancel()` ядра краснит тест L5. Все
одиннадцать находок он признал закрытыми, M6 — с оговоркой. Его находки, все
исправлены этим же коммитом:

1. Medium. Итоги не дописаны в вердикты, `docs/handoff.md` не тронут. Дописаны.
2. Low. Неточность L2 — о провале сообщают «в момент конца» — осталась
   в `testing.md` и `mistakes.md` `solo` и в `testing.md` `flutter_solo`. Его
   зонд читает `done` у задачи, которая уже `Failed`, и зона не слышит ничего.
   Исправлено «on the microtask after the job ends», с переводами и сторожами.
3. Low. M6: задача кончается `Cancelled(timeout)` не только на контрольной
   точке, но и когда тело просто вернулось, — это показывает собственный тест
   волны. Теперь «reaches a checkpoint or returns»; переменная теста
   `queuedStartedAtSix` переименована в `queuedFinishedAtSix`: она читает
   `isFinished`.
4. Low, спорная. Фраза L1 в абсолютной форме осталась в `jobs.md`: «только для
   вызывающего, который читает `isQueued`», а фабрики детей в `children.md`
   и `camera.md` объявляют `SoloJob<T>`. Дописана фраза о фабрике ребёнка, как
   в `reference.md`, с переводом.
5. Low. Перевод M5 терял «past that». Теперь «дальше этого ответа».
6. Low. Цитату вывода в README примера не держало ничего: подмена
   `shot: Cancelled(manual)` на `shot: Done(photo.jpg)` проходила все проверки.
   Новый тест в `example/test/camera_rakes_test.dart` сверяет начало и конец
   блока с выводом программы и держит фразу о намеренной отмене; та же подмена
   его краснит.
7. Low. Info анализатора `require_trailing_commas` в новом тесте M6. Исправлено
   ещё до его отчёта.

Сверх находок он заметил кальку «добавляет сторону Flutter» в `README.ru.md`
`solo` — теперь «добавляет то, что нужно во Flutter».

Повторного ревью правки по его находкам не было; находки 2, 3 и 6 держат
сторожа.
