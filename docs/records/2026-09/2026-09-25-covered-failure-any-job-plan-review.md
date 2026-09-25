# Ревью плана: покрытый провал отвечается у любой задачи

> **Состояние на 2026-09-26:** вердикты записаны: все девять находок приняты,
> третья и четвёртая частично — запись `CHANGELOG` остаётся `Fix`, а три
> страницы о провале, который несёт исход, не правятся, — и внесены в план
> `2026-09-25-covered-failure-any-job-plan.md`.
> **Что это:** независимое ревью `2026-09-25-covered-failure-any-job-plan.md`
> на Opus, по копии дерева на `5e1fb22`, с черновиком из раздела «Механика»,
> зондами и мутациями в скретч-каталоге.
> **Связанные записи:** `2026-09-25-covered-failure-any-job-plan.md`,
> `2026-09-25-covered-child-failure-plan.md`,
> `2026-09-25-covered-child-failure-report.md`,
> `2026-09-25-covered-child-failure-work-review.md`.

## Итог

Механика плана верна и проста: флаг `_takenByParent` уходит, `_reportCovered`
отвечает всегда, `ignore()` глушит. Черновик из «Механики» я применил в копии
дерева как написано, и всё, что план утверждает в разделе «Зонд», сошлось:
строки S1–S7 обеих таблиц, семь красных тестов `async_job` поимённо, `solo` —
795 зелёных. Двойного ответа нет ни на одном пути, который я прогнал:
у покрытого провала исход `Cancelled`, группа его не видит, а `finish`
по `Cancelled` ничего не подменяет.

Но правило «`ignore()` глушит, и это одно для всех» план проводит не до конца:
у ветки `runAll` он глушит покрытый провал и не глушит провал, который группа
не бросила (находка 1). Путь продолжения `then` правило задевает, а сторожа
у него нет, и мутация `announced` там больше не эквивалентна (находка 2).
Главное изменение для пользователя — прочитанный исход больше не держит такой
провал вне зоны — `CHANGELOG` и несколько страниц не называют (находки 3, 4).

## Находки

1. **Medium. `ignore()` у ветки `runAll` глушит покрытый провал, но не провал,
   который группа не бросила.**

   Суть. План: «`Job.ignore` глушит… Это правило одно для всех», и довод —
   «покрытый провал — провал этой задачи». Но группа отвечает за невыбранный
   `Failed` ветки сама, в `_RunAllGroup._conclude`
   (`packages/async_job/lib/src/job_context.dart:1744-1768`:
   `_handleUnanswered` для провала тела, `notifyError` для поданного движком),
   и на `ignore()` не смотрит; план это место не трогает. До плана `ignore()`
   на ветке не менял ни того, ни другого — так и говорит dartdoc `Job.ignore`
   (`packages/async_job/lib/src/job_base.dart:267-268`: «A child of
   [JobContext.run] and a branch of [JobContext.runAll] are observed by their
   parent, so this changes nothing for them»). После плана у одной ветки
   с `ignore()` два провала тела, которые родитель не может передать дальше,
   идут двумя разными дорогами. Довод плана к невыбранному провалу подходит
   дословно: это тоже провал этой задачи.

   Свидетельство. Зонд `zz_rev_probe2_test.dart`. B1: ветка
   `cancellable: false` с `ignore()` падает на 20 мс, группа бросает провал
   соседней ветки (10 мс). B2: ветка с `ignore()` падает на 5 мс, пока жив её
   ребёнок, родителя отменяют на 10 мс.

```text
HEAD:
  B1: onError: first / onError: second, not thrown /
      onUnanswered: second, not thrown / zone: second, not thrown
  B2: onError: branch, covered / onUnanswered: branch, covered /
      zone: branch, covered
черновик:
  B1: onError: first / onError: second, not thrown /
      onUnanswered: second, not thrown / zone: second, not thrown
  B2: onError: branch, covered
```

   Предложение. Решить до работы, в плане. Либо (а) `_conclude` тоже смотрит
   на `_ignored`: провал тела ветки с `ignore()` — ничего, поданный движком —
   `notifyObserver`, как у покрытого; сторож B1 через `expectOnlyTold`; dartdoc
   `runAll` («A failure the group received and did not throw is not lost
   either») и строка таблицы `observing.md` о ветке получают оговорку. Либо (б)
   оставить и сказать в dartdoc `Job.ignore` и `runAll` прямо, что невыбранный
   провал ветки `ignore()` не глушит, и почему. Я за (а): иначе у `ignore()`
   на ветке два смысла, и таблица страницы не даст читателю вывести, какой где.

   Вердикт: принято, вариант (а). Обещание `ignore()` — «провал этой задачи
   никому не нужен», и невыбранный провал ветки — тоже её провал. `_conclude`
   смотрит на `_ignored`: провал тела — ничего, `onError` его уже слышал;
   поданный движком — `notifyObserver`, как у покрытого. В план: механика;
   сторожа через `expectOnlyTold` — ветка с `ignore()`, чей провал тела группа
   не бросила (B1), и такая же ветка, которую движок кончил `Failed` руками;
   мутации «`_conclude` не смотрит на `_ignored`» и «при `_ignored` поданный
   движком провал не объявляется»; dartdoc `runAll`, строка таблицы
   `observing.md` о ветке, абзац под таблицей и запись `CHANGELOG`.

2. **Medium. Путь продолжения `then` не держит ни один сторож, а его аргумент
   `announced` перестал быть эквивалентным.**

   Суть. `_ThenJob._sourceFinished`
   (`packages/async_job/lib/src/job_then.dart:72-78`): источник упал,
   продолжение переслало провал и объявило его (`notifyObserver`),
   а наблюдатель продолжения отменил его прямо в `onError`. Исход продолжения —
   `Cancelled`, и зовётся `_reportCovered(result, announced: true)`. Прошлая
   работа записала мутацию «`then` передаёт `announced: false`» эквивалентной:
   у продолжения не было флага, и аргумент ничего не решал
   (`2026-09-25-covered-child-failure-report.md`, таблица мутаций). После плана
   решает: провал слышен в `onError` дважды. Ни существующий набор, ни сторожа
   из списка плана этот путь не проходят, в таблице мутаций плана его нет.
   `then_test.dart:295` «cancellation in the failure observer does not hide the
   error» в `_reportCovered` заходит, но считает только зону.

   Поведение там тоже меняется, и план этого не называет: зонд S13v — чтение
   `value` продолжения больше не снимает ответ. И формулировка правила
   («Провал, который покрыла отмена, не лежит ни в одном исходе») на этом пути
   неточна: провал лежит в исходе источника, `Failed`, а продолжение отвечает
   за него потому, что пересылка сняла ответственность с источника
   (`_source!._observed = true`, `job_then.dart:73`). Кто сверх того читает
   `source.value`, получит ошибку, и зона получит её тоже — так было
   и на `HEAD`, если `value` продолжения не читали; теперь и если читали.

   Свидетельство. Мутация `then-announced-false` (`mutate.py`,
   `run_mutations.sh`) по всему набору `async_job` плюс сторожа из списка плана
   (`zz_rev_sentinels_test.dart`, группа `plan`): красных сверх семи своих
   у черновика — один, мой сторож `extra then…`:

```text
Expected: ['onError: Bad state: source failed',
           'onUnanswered: Bad state: source failed']
  Actual: ['onError: Bad state: source failed',
           'onError: Bad state: source failed',
           'onUnanswered: Bad state: source failed']
```

   Зонд `zz_rev_probe_test.dart`, S13v (наблюдатель продолжения отменяет его
   в `onError`, `value` продолжения читают): `HEAD` — `c.onError`,
   `reader: Cancelled(manual)`; черновик — `c.onError`, `c.onUnanswered`, зона,
   `reader`. Зонд `zz_rev_probe3_test.dart`, S13s (то же, и `source.value` тоже
   читают): `HEAD` — `source reader: Bad state: source failed`, `c.onError`,
   и зона, только если `value` продолжения не читали; черновик —
   `source reader`, `c.onError`, `c.onUnanswered`, зона в обоих вариантах.

   Предложение. Сторож в новую группу: продолжение, отменённое своим
   наблюдателем, пока тот слышит провал источника, `value` читают, — через
   `expectAnswered`; то же с `ignore()` на продолжении — `expectOnlyTold`.
   Мутацию `announced: false` у `then` — в таблицу. В «Что станет» дописать
   путь `then` отдельной фразой: чей провал и почему отвечает продолжение.

   Вердикт: принято. Правило в «Что станет» переписано: покрытый провал
   не лежит в исходе той задачи, которая за него отвечает. У продолжения `then`
   он лежит в исходе источника, но пересылка сняла ответственность с источника,
   и отвечает продолжение — отдельной фразой. Сторожа: продолжение, которое его
   наблюдатель отменил из `onError`, `value` продолжения ждут —
   `expectAnswered`, с одним `onError`; то же с `ignore()` на продолжении —
   `expectOnlyTold`. Мутация «`then` передаёт `announced: false`» — в таблицу.

3. **Medium. Главное изменение для пользователя — прочитанный исход больше
   не держит провал вне зоны, — а `CHANGELOG` в плане говорит о другом.**

   Суть. План подаёт правку записью `Fix` ядра, а в `solo` — пунктом перечня
   `Solo.onUnanswered` и фразой «покрытый провал корня теперь доходит
   до `Solo.errorHandler`, а не прямо до зоны». Это верно для исхода, который
   никто не читал. Но для прочитанного — `await job.value`, `job.done`,
   `await ctx.each(...).value` — ошибка, которую раньше слышал один `onError`,
   теперь идёт в `Solo.errorHandler` или в зону. В тесте под `fakeAsync` зона —
   это тест, и он краснеет; во Flutter это `PlatformDispatcher.onError`.
   Закрывает этот провал теперь только `ignore()` или переопределение
   `onUnanswered`, а не чтение исхода. Запись `Breaking` ядра о `onUnanswered`
   называет такой вид изменения вслух: «it compiles, and the errors it used to
   swallow reach the zone». К тому же запись `Fix` прошлой работы
   (`packages/async_job/CHANGELOG.md:31-40`) говорит «`ignore` on the child
   changes nothing there» и «Any other job keeps the rule it had» — обе фразы
   план разворачивает.

   Свидетельство. Зонд `solo` (`zz_rev_solo_probe_test.dart`), обработчик
   задан, `HEAD` → черновик:

```text
R2 root, value read, cancel():     Solo.onError, reader
                                -> Solo.onError, Solo.onUnanswered,
                                   errorHandler, reader
R4 root, done read, solo.close():  Solo.onError, reader
                                -> ... errorHandler, reader: Cancelled(closed)
R5 each, value awaited:            Solo.onError
                                -> Solo.onError, Solo.onUnanswered,
                                   errorHandler
R6 root, value read, Policy.restart replaces it: то же, что R2
```

   Страницы, которые обещают обратное, — в находке 4.

   Предложение. Запись ядра переписать целиком, а не дописать: покрытый провал
   любой задачи отвечается через `onUnanswered`, чтение исхода его не снимает
   (читатель получил отмену), `ignore()` глушит — и у ребёнка `ctx.run` тоже.
   Решить, `Fix` это или `Breaking`: по мерке самого `CHANGELOG` — скорее
   второе. В записи `solo` — не только перечень, а фраза о том, что такой
   провал корня и ребёнка `each` доходит до `Solo.errorHandler`, даже когда
   `value` ждали. У `flutter_solo` унаследованная запись этого не несёт;
   прошлый отчёт обосновал, почему исправления ядра туда не идут, но это
   исправление меняет, что падает в тестах виджетов, — назвать или сознательно
   не назвать в отчёте.

   Вердикт: принято частично. Запись ядра переписывается целиком и называет
   главное: чтение исхода — `value`, `done`, `ctx.each(...).value` — больше
   не держит покрытый провал вне зоны, читатель получает отмену, а провал —
   `onUnanswered`; `ignore()` его глушит, и у ребёнка `ctx.run` тоже. Класс
   остаётся `Fix`. По мерке того же `CHANGELOG` ошибка, которая терялась
   и теперь доходит до зоны, — исправление: так записано «an action failing
   after the body walked away from it is no longer swallowed», и так же прошлая
   запись, которую эта заменяет; `Breaking` там — смена договора API, как
   у `onError`. Запись `solo` получает фразу: покрытый провал корня и ребёнка
   `each` доходит до `Solo.errorHandler`, даже когда `value` ждали.
   `flutter_solo` — нет: его унаследованные записи несут только ломающие
   изменения, исправления ядра туда не идут, как и в прошлой работе; отчёт это
   назовёт.

4. **Medium. Список документов неполон.**

   Суть. Грепом по `packages/*/lib`, `packages/*/doc`, `CHANGELOG`, README,
   `docs/ru`, `docs/architecture.md` (без `doc/api/`) нашлись места, которые
   станут неправдой и которых в плане нет:

   - dartdoc `Job.ignore` — не только абзац о ребёнке `ctx.run`.
     `job_base.dart:263-265`: «Waiting for [done] or [value] observes the job
     too; calling this afterwards changes nothing. Has no effect on
     [Cancelled], which is never reported to the zone.» Обе фразы неверны:
     `ignore()` после чтения `value` теперь глушит (зонд S10), а у задачи
     с исходом `Cancelled` — меняет ответ. `job_base.dart:267-268` («so this
     changes nothing for them») — тоже. И сюда же срок: вызывать до конца
     задачи или из `finished`, `onFinish`, `whenCancelled` (находка 8);
   - `docs/architecture.md:101-110`, определение «Наблюдение исхода»:
     `ignore()` в нём — вид наблюдения, а теперь он больше, чем наблюдение;
     и оговорка `:197-200` о `Failed`, собранном вокруг отмены (находка 5).
     План называет только «маршрут покрытого провала»;
   - `packages/async_job/doc/outcomes.md:113-117`, раздел «Telling the engine
     it is handled», а не «A failure nobody waits for»: «Accessing `done` or
     `value` observes a failure as well, so code that waits for the job … needs
     no `ignore()`». На этот раздел ссылается абзац под таблицей `observing.md`
     («Observing the outcome closes the first way»). Перевод —
     `docs/ru/async_job/outcomes.md`;
   - `packages/solo/doc/errors.md:360-363`, раздел «Observing the outcome»: «a
     caller that needs the result takes it with `await job.value` and answers
     for the error by catching it» — при покрытом провале такой вызывающий
     поймает `Cancelled`. Перевод;
   - `packages/solo/doc/testing.md:240-244` («an observed failure is the test's
     business rather than the zone's») и `:388-392` («`ignore()` is what stands
     in for that read») — теперь `ignore()` и чтение не равны. Перевод;
   - `packages/flutter_solo/README.md:414-417`: «an unobserved `Failed` fails
     the test itself … Either await the outcome or call `ignore()`». Покрытый
     провал валит тест и при ожидании исхода. `README.ru.md`;
   - `packages/flutter_solo/CHANGELOG.md` — находка 3;
   - `packages/async_job/doc/children.md:480-483` и `:550-553` о хвосте `then`
     («Observe the tail through `value`, `done` or `ignore`») — проверить
     на находку 2;
   - `observing.md`: у слитой строки таблицы теперь есть выключатель, которого
     нет у соседних строк `onUnanswered`, — `ignore()`; страница его
     не называет.

   Предложение. Внести в раздел «Документы» поимённо.

   Вердикт: принято частично. В «Документы» поимённо: dartdoc `Job.ignore`
   целиком — три фразы из находки и срок вызова; `docs/architecture.md` —
   определение «Наблюдение исхода», маршрут и строки о фильтре; `outcomes.md`,
   раздел «Telling the engine it is handled», и перевод; `solo/doc/errors.md`,
   раздел «Observing the outcome», и перевод; `ignore()` в абзаце под таблицей
   `observing.md`. Не правятся `solo/doc/testing.md`, `flutter_solo/README.md`
   и хвост `then` в `children.md`: они говорят о провале, который несёт исход,
   а для него чтение исхода по-прежнему снимает ответ. Исключение для покрытого
   провала живёт там, где определено правило наблюдения, — в dartdoc,
   `outcomes.md`, `observing.md` и `errors.md`, — а не при каждом упоминании
   `value` и `ignore()`.

5. **Low. У корня меняются ещё два случая, о которых план молчит.**

   Суть. На `HEAD` путь корня в `_reportCovered` (`job_base.dart:1395-1401`)
   звал `_zone.handleUncaughtError` сам, мимо `_toZone` и мимо наблюдателя.
   Черновик ведёт его через `_handleUnanswered` и `notifyError`. Отсюда две
   перемены у корня, которых нет ни в таблице «Зонд», ни в «Документах»:

   - `Failed`, собранный вокруг `Cancelled` и поданный движком поверх отметки,
     раньше доезжал до зоны, теперь фильтр его отбрасывает. Об этом говорят
     dartdoc `_toZone` (`job_base.dart:1095-1101`, «in a job whose outcome a
     parent took») и `docs/architecture.md:197-200` («У ребёнка, чей исход взял
     родитель, такой `Failed` … фильтр его отбрасывает»);
   - провал, поданный движком поверх отметки корня, раньше шёл в зону без
     `onError`, теперь — `onError`, `onUnanswered`, зона.

   Свидетельство. `zz_rev_sentinels_test.dart`, «root: a Failed built around a
   Cancelled over the mark is dropped» — красный на `HEAD`, зелёный
   на черновике. Зонд S9: `HEAD` — `onFinish`, `zone: by hand`; черновик —
   `onFinish`, `onError`, `onUnanswered`, зона.

   Предложение. Назвать оба в «Что станет», сторож фильтра у корня
   (с наблюдателем и без), поправить `_toZone` и `architecture.md` под «любую
   задачу».

   Вердикт: принято. В «Что станет» оба случая: `Failed`, собранный вокруг
   `Cancelled` и поданный движком поверх отметки корня, теперь отбрасывает
   фильтр, как у ребёнка `ctx.run`; провал, поданный движком поверх отметки
   корня, теперь слышат `onError` и `onUnanswered`. Сторожа: фильтр у корня
   с наблюдателем и без, `onError` и ответ для провала движка у корня. Dartdoc
   `_toZone`, `_handleUnanswered` и `docs/architecture.md` говорят о любой
   задаче, чей исход решает ядро.

6. **Low. Сторожа и имена тестов.**

   - `observing_rakes_test.dart`: `Reporter` (`:69-73`) печатает только
     `onError`, так что обещание плана «два теста ждут `onError`,
     `onUnanswered` и зону» требует другого наблюдателя —
     `Answering(passedOn: true)` из того же файла. Тест «the same in a child of
     run: onError, then the zone» (`:687-708`) сторожит строку, которую план
     сливает, — сказать, что с ним.
   - Зелёными останутся тесты, чьи имена и причины станут неправдой:
     `zone_test.dart:178` «an error a late cancellation covers goes where an
     uncovered one goes» (покрытый теперь идёт через `onUnanswered`,
     непокрытый — нет; `JobJournal` из `support/journal.dart` не пишет
     `onUnanswered`, поэтому тест этого не видит) и причина `:603-604` в «an
     observer that cancels from onError does not hide the failure» («on the
     same road it would have taken anyway»).
   - `solo`: 795 зелёных говорят только об изоляции. Я вставил печать
     в `_reportCovered` и прогнал весь набор `solo` на черновике: в этот путь
     заходят три теста, все — ребёнок `ctx.run` из группы «a failure a
     cancellation covered in a child». Корень и `each` не проходит ни один. Два
     сторожа `solo` из плана — оба корень под `cancel()`; корень в `solo`
     покрывают ещё `close()` (R4) и `Policy.restart` (R6), а `each` (R5) —
     отдельный случай из «Что станет». Добавить хотя бы `each`.
   - Срок `ignore()`: план проверяет только `onFinish`. Решение вопроса 1
     держат ещё два теста — `ignore()` из `whenCancelled` успевает (S12),
     из слушателя `done` — нет (S11d). Мутация «ответ микрозадачей» на моём
     наборе краснит оба места: сторож порядка прошлой работы и тест
     со слушателем `done`.

   Вердикт: принято. Два теста строки в `observing_rakes_test.dart` берут
   `Answering(passedOn: true)`. Тест «the same in a child of run» остаётся
   сторожем слитой строки у ребёнка `ctx.run`: его ожидания не меняются, имя
   меняется под слитую строку. `zone_test.dart:178` получает имя и причину
   о `onUnanswered`, причина `:603-604` переписывается. Сторож `solo` для
   `each`, чьё `value` ждут. Сторожа срока: `ignore()` из `whenCancelled`
   успевает, из слушателя `done` уже нет.

7. **Low. «У любой задачи» — кроме той, которую движок кончил руками.**

   Суть. План оставляет вне работы задачу, которую движок кончает руками, пока
   упавшее первым тело ждёт детей. Но теперь правило в dartdoc `Failed`
   и в таблице `observing.md` будет сказано обо всех задачах, а этот путь —
   тоже покрытый провал — по-прежнему слышит один `onError`: `_execute` выходит
   на `if (isFinished) return;` (`job_base.dart:1243-1248`). `solo` бегущую
   задачу руками не кончает, так что это движки вне пакета.

   Свидетельство. Зонд S16 (`ProbeJob`, тело падает на 5 мс при живом ребёнке,
   на 10 мс `drop(Cancelled)`): и на `HEAD`, и на черновике — `onError`,
   `onFinish`, ни ответа, ни зоны; без наблюдателя — пусто.

   Предложение. В `docs/architecture.md` и dartdoc `_reportCovered` оставить
   оговорку; на страницах сказать «задача, чей исход решает ядро», или
   промолчать сознательно — но не «любая».

   Вердикт: принято. Страницы описывают случай его обстоятельствами — тело
   упало, отмена пришла, пока задача ждала детей или шла уборка, — а не словами
   «у любой задачи». Оговорка о задаче, которую движок кончил руками, —
   в dartdoc `_reportCovered` и в `docs/architecture.md`.

8. **Low. Открытый вопрос 1: ответ синхронный — держится.**

   Мнение. Оставить синхронным. Микрозадача у непокрытого `Failed` служит
   позднему *читателю*: `done`, прочитанный микрозадачей позже, снимает провал.
   Для покрытого чтение ничего не снимает, и у окна не остаётся клиента, кроме
   позднего `ignore()`. А `ignore()` зовут при создании или движок —
   из `onFinish`; оба успевают, `whenCancelled` тоже. Микрозадача ломает
   порядок «ответ раньше, чем тело родителя услышит отмену», который держит
   сторож прошлой работы, а смешанный вариант — синхронно у детей, микрозадачей
   у остальных — возвращает ровно те два пути, которые план убирает.

   Свидетельство. Мутация `answer-microtask` (ответ микрозадачей с проверкой
   `_ignored` в ней): красные — «the answer comes before the parent hears the
   cancellation» и мой «ignore() from a done listener is too late». Значит,
   микрозадача покупает ровно одно — `ignore()` из слушателя `done`. Асимметрию
   надо назвать: зонды S11 и S11u — `scheduleMicrotask(job.ignore)`
   из `onFinish` глушит непокрытый провал и не глушит покрытый.

   Предложение. В dartdoc `Job.ignore`: вызывать до конца задачи, самое
   позднее — из `onFinish` или `whenCancelled`; позже покрытый провал уже
   отвечен.

   Вердикт: принято. Ответ остаётся синхронным. Срок вызова `ignore()` —
   в dartdoc `Job.ignore` (находка 4), сторожа срока — в находке 6.

9. **Low. Открытый вопрос 2: один `onError` — верно, но асимметрию стоит
   назвать.**

   Мнение. Один `onError`. Непокрытый `Failed`, поданный через `finish` задаче
   с `ignore()`, «тих» только для `onError`: он лежит в исходе, `onFinish`
   и `job.outcome` показывают `Failed(…)`. Покрытый не лежит нигде: исход —
   `Cancelled`, и без `onError` ошибка исчезнет целиком — вопреки правилу,
   которое ядро само пишет в `finish` («an error is never lost silently»,
   `job_base.dart:995-998`). И `ignore()` нигде не глушит `onError` для провала
   тела.

   Свидетельство. Зонд S9i (поверх отметки, `ignore()`):
   `onFinish probe: Cancelled(manual)`, `onError: by hand`. S9u (без отметки,
   `ignore()`): `onFinish probe: Failed(Bad state: by hand)`. Мутация
   `ignored-total-silence` (тишина целиком) ловится сторожем из списка плана.

   Предложение. Оставить; в dartdoc `_reportCovered` сказать, почему здесь
   `onError`, а у непокрытого — нет: тот виден в исходе.

   Вердикт: принято. Один `onError`; dartdoc `_reportCovered` говорит почему:
   непокрытый провал виден в исходе, а покрытый без `onError` исчез бы
   бесследно.

## Как проверено

- Копия дерева: `git checkout --detach 5e1fb22`. Черновик «Механики» —
  дословно: поле `_ignored`, `ignore()` ставит оба признака, `_reportCovered`
  без ветвления по хозяину исхода, строки флага в `_awaitChild` и группе убраны
  (`draft_job_base.dart`, `draft_job_context.dart`). После работы исходники
  возвращены копией, хэши сверены с `orig/`.
- Числа: `HEAD` — `async_job` 606 зелёных. Черновик — `async_job` 599 и семь
  красных, поимённо те, что в плане (счёт по `[E]`, `draft_async_job.txt`);
  `solo` — 795 из 795 (`draft_solo.txt`).
- Печать в `_reportCovered` на черновике (`draft_async_instr.txt`,
  `draft_solo_instr.txt`): в `solo` путь проходят три теста, в `async_job` —
  двадцать шесть: группы покрытого провала `unanswered_test.dart`, строки
  таблицы страницы, семь тестов `zone_test.dart`, `cancel_test.dart:651`
  и `then_test.dart:295`.
- Зонды печатают из-за пределов зоны и ничего не утверждают:
  `zz_rev_probe_test.dart` (S1–S19, `probe_head.txt`, `probe_draft.txt`),
  `zz_rev_probe2_test.dart` (B1, B2), `zz_rev_probe3_test.dart` (S13s),
  `zz_rev_solo_probe_test.dart` (R1–R6, `solo_probe_head.txt`,
  `solo_probe_draft.txt`).
- Сторожа `zz_rev_sentinels_test.dart`: группа `plan` — список плана, как я его
  прочёл (одиннадцать тестов), группа `extra` — предложенные здесь (четыре).
  На черновике зелёные все пятнадцать, на `HEAD` красных одиннадцать.
- Мутации: `mutate.py` и `run_mutations.sh`, откат копией файла со сверкой хэша
  (`hash-ok` после прогона), весь набор `async_job` со сторожами, счёт по `[E]`
  тех красных, которых нет среди семи красных черновика (`draft_reds.txt`,
  `mut_*.txt`): `then-announced-false` — 1 (только `extra`),
  `answer-microtask` — 2, `ignored-total-silence` — 1 (сторож плана),
  `observed-instead-of-ignored` — 17.
- Все файлы — в скретч-каталоге рядом с этим ревью; в копии дерева не осталось
  ничего своего.

## Общий вывод

По плану можно работать: механика верна, числа и таблицы воспроизводятся,
по вопросам 1 и 2 я на стороне плана. До начала обязательно внести: решение
о ветке `runAll` с `ignore()` (находка 1), путь `then` со сторожем и мутацией
(находка 2), формулировку и класс записи `CHANGELOG` вокруг «чтение исхода
больше не снимает» (находка 3) и полный список документов (находка 4).
Остальное — по ходу работы.
